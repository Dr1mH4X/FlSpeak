//! 协议事件按顺序广播，电平只保留最新值，在每个订阅者出口合并。

use audio::level::LevelReading;
use tokio::sync::{broadcast, watch};

use crate::{SessionEvent, SessionState};

#[derive(Clone)]
pub(crate) struct LevelPublisher {
    sender: watch::Sender<LevelReading>,
}

pub(crate) fn level_channel() -> (LevelPublisher, watch::Receiver<LevelReading>) {
    let (sender, receiver) = watch::channel(LevelReading::default());
    (LevelPublisher { sender }, receiver)
}

impl LevelPublisher {
    pub fn set_epoch(&self, epoch: Option<u64>) {
        let epoch = epoch.unwrap_or(0);
        self.sender.send_if_modified(|latest| {
            if latest.connection_epoch == epoch {
                return false;
            }
            *latest = LevelReading {
                connection_epoch: epoch,
                ..Default::default()
            };
            true
        });
    }

    pub fn publish(&self, reading: LevelReading) {
        self.sender.send_if_modified(|latest| {
            if reading.connection_epoch == 0 || latest.connection_epoch != reading.connection_epoch
            {
                return false;
            }
            *latest = reading;
            true
        });
    }
}

/// 连接与消息优先，电平按订阅时的当前连接及随后交付的状态校验代次。
pub struct SessionSubscription {
    events: broadcast::Receiver<SessionEvent>,
    levels: watch::Receiver<LevelReading>,
    connected_epoch: Option<u64>,
}

impl SessionSubscription {
    pub(crate) fn new(
        events: broadcast::Receiver<SessionEvent>,
        levels: watch::Receiver<LevelReading>,
    ) -> Self {
        let epoch = levels.borrow().connection_epoch;
        Self {
            events,
            levels,
            connected_epoch: (epoch != 0).then_some(epoch),
        }
    }

    pub async fn recv(&mut self) -> Result<SessionEvent, broadcast::error::RecvError> {
        loop {
            tokio::select! {
                biased;
                event = self.events.recv() => {
                    let event = event?;
                    if let SessionEvent::State { state, connection_epoch } = &event {
                        self.connected_epoch = matches!(state, SessionState::Connected { .. })
                            .then_some(*connection_epoch);
                    }
                    return Ok(event);
                }
                changed = self.levels.changed() => {
                    // 发送者由 actor 与音频线程持有；二者退出后订阅随之结束。
                    changed.map_err(|_| broadcast::error::RecvError::Closed)?;
                    let reading = *self.levels.borrow_and_update();
                    if self.connected_epoch == Some(reading.connection_epoch) {
                        return Ok(SessionEvent::Levels { mic: reading.mic, received: reading.received });
                    }
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn meter_pressure_cannot_evict_ordered_session_events() {
        let (events, receiver) = broadcast::channel(4);
        let (publisher, levels) = level_channel();
        let mut subscription = SessionSubscription::new(receiver, levels);
        publisher.set_epoch(Some(1));
        events
            .send(SessionEvent::State {
                state: SessionState::Connected {
                    client_id: 1,
                    channel_id: 5,
                },
                connection_epoch: 1,
            })
            .unwrap();
        for index in 0..10_000 {
            publisher.publish(LevelReading {
                connection_epoch: 1,
                mic: index as f32 / 10_000.0,
                received: 0.0,
            });
        }
        events
            .send(SessionEvent::TextMessage(crate::TextMessageView {
                from: "Peer".into(),
                from_uid: "peer".into(),
                from_id: 2,
                message: "still delivered".into(),
                target_mode: 2,
                target_id: 5,
                at: 1,
            }))
            .unwrap();
        assert!(matches!(
            subscription.recv().await.unwrap(),
            SessionEvent::State { .. }
        ));
        assert!(matches!(
            subscription.recv().await.unwrap(),
            SessionEvent::TextMessage(_)
        ));
        assert!(
            matches!(subscription.recv().await.unwrap(), SessionEvent::Levels { mic, .. } if mic > 0.99)
        );
    }

    #[tokio::test]
    async fn old_samples_cannot_cross_a_reconnect_or_overwrite_the_new_scope() {
        let (events, receiver) = broadcast::channel(4);
        let (publisher, levels) = level_channel();
        publisher.set_epoch(Some(1));
        publisher.publish(LevelReading {
            connection_epoch: 1,
            mic: 0.9,
            received: 0.9,
        });
        let mut subscription = SessionSubscription::new(receiver, levels);
        publisher.set_epoch(None);
        events
            .send(SessionEvent::State {
                state: SessionState::Disconnected,
                connection_epoch: 2,
            })
            .unwrap();
        publisher.set_epoch(Some(3));
        events
            .send(SessionEvent::State {
                state: SessionState::Connected {
                    client_id: 2,
                    channel_id: 9,
                },
                connection_epoch: 3,
            })
            .unwrap();
        publisher.publish(LevelReading {
            connection_epoch: 1,
            mic: 0.9,
            received: 0.9,
        });
        assert!(matches!(
            subscription.recv().await.unwrap(),
            SessionEvent::State {
                state: SessionState::Disconnected,
                ..
            }
        ));
        assert!(matches!(
            subscription.recv().await.unwrap(),
            SessionEvent::State {
                state: SessionState::Connected { .. },
                ..
            }
        ));
        assert!(matches!(
            subscription.recv().await.unwrap(),
            SessionEvent::Levels {
                mic: 0.0,
                received: 0.0
            }
        ));
        publisher.publish(LevelReading {
            connection_epoch: 3,
            mic: 0.2,
            received: 0.3,
        });
        assert!(matches!(
            subscription.recv().await.unwrap(),
            SessionEvent::Levels {
                mic: 0.2,
                received: 0.3
            }
        ));
    }

    #[tokio::test]
    async fn actor_shutdown_closes_subscriptions_even_with_a_broadcast_sender_retained() {
        let (_events, receiver) = broadcast::channel(4);
        let (publisher, levels) = level_channel();
        let mut subscription = SessionSubscription::new(receiver, levels);
        drop(publisher);
        assert!(matches!(
            subscription.recv().await,
            Err(broadcast::error::RecvError::Closed)
        ));
    }
}
