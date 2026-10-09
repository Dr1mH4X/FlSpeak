//! 说话人播放队列。
//!
//! Opus 解码器状态按流独立，队列也必须按说话人分开。tsclient-rs 没有把接收语音包
//! 的序号暴露出来（`VoiceData` 只有 client_id / codec / data），所以这里只能按到达
//! 顺序排队，丢帧交给 Opus 的丢包隐藏处理，不做重排序。

use std::collections::{HashMap, VecDeque};

/// 一帧待播放的语音。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VoiceFrame {
    pub client_id: i32,
    pub codec: i32,
    pub data: Vec<u8>,
}

#[derive(Debug)]
pub struct TalkerQueues {
    capacity_per_talker: usize,
    max_talkers: usize,
    queues: HashMap<i32, VecDeque<VoiceFrame>>,
    dropped_frames: u64,
}

impl TalkerQueues {
    pub fn new(capacity_per_talker: usize, max_talkers: usize) -> Self {
        Self {
            capacity_per_talker: capacity_per_talker.max(1),
            max_talkers: max_talkers.max(1),
            queues: HashMap::new(),
            dropped_frames: 0,
        }
    }

    /// 入队。返回被挤出的最旧帧（队列满或说话人名额用尽时）。
    pub fn push(&mut self, frame: VoiceFrame) -> Option<VoiceFrame> {
        if !self.queues.contains_key(&frame.client_id) && self.queues.len() >= self.max_talkers {
            let victim = self.oldest_talker()?;
            self.dropped_frames += self.queues.remove(&victim).map_or(0, |q| q.len() as u64);
        }

        let queue = self.queues.entry(frame.client_id).or_default();
        queue.push_back(frame);
        if queue.len() > self.capacity_per_talker {
            let evicted = queue.pop_front();
            if evicted.is_some() {
                self.dropped_frames += 1;
            }
            return evicted;
        }
        None
    }

    pub fn pop(&mut self, client_id: i32) -> Option<VoiceFrame> {
        let frame = self.queues.get_mut(&client_id)?.pop_front();
        if self.queues.get(&client_id).is_some_and(VecDeque::is_empty) {
            self.queues.remove(&client_id);
        }
        frame
    }

    pub fn len(&self, client_id: i32) -> usize {
        self.queues.get(&client_id).map_or(0, VecDeque::len)
    }

    pub fn is_empty(&self) -> bool {
        self.queues.is_empty()
    }

    pub fn active_talkers(&self) -> Vec<i32> {
        let mut talkers: Vec<i32> = self.queues.keys().copied().collect();
        talkers.sort_unstable();
        talkers
    }

    pub fn dropped_frames(&self) -> u64 {
        self.dropped_frames
    }

    fn oldest_talker(&self) -> Option<i32> {
        self.queues
            .iter()
            .min_by_key(|(_, queue)| queue.front().map(|f| f.client_id))
            .map(|(client_id, _)| *client_id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frame(client_id: i32) -> VoiceFrame {
        VoiceFrame {
            client_id,
            codec: 4,
            data: vec![0u8; 8],
        }
    }

    #[test]
    fn keeps_queues_per_talker() {
        let mut queues = TalkerQueues::new(3, 2);
        queues.push(frame(1));
        queues.push(frame(2));
        assert_eq!(queues.active_talkers(), vec![1, 2]);
        assert_eq!(queues.len(1), 1);
        assert!(queues.pop(1).is_some());
        assert_eq!(queues.active_talkers(), vec![2]);
    }

    #[test]
    fn drops_oldest_frame_when_talker_is_saturated() {
        let mut queues = TalkerQueues::new(2, 4);
        assert!(queues.push(frame(7)).is_none());
        assert!(queues.push(frame(7)).is_none());
        assert!(queues.push(frame(7)).is_some());
        assert_eq!(queues.len(7), 2);
        assert_eq!(queues.dropped_frames(), 1);
    }

    #[test]
    fn evicts_a_talker_when_talker_slots_are_exhausted() {
        let mut queues = TalkerQueues::new(2, 1);
        queues.push(frame(1));
        queues.push(frame(2));
        assert_eq!(queues.active_talkers(), vec![2]);
        assert_eq!(queues.dropped_frames(), 1);
        assert!(queues.pop(1).is_none());
    }

    #[test]
    fn pop_missing_talker_is_none() {
        let mut queues = TalkerQueues::new(2, 2);
        assert!(queues.pop(42).is_none());
        assert!(queues.is_empty());
    }
}
