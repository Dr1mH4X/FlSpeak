use super::*;

pub(super) type TestCommandHandler = Arc<
    dyn Fn(
            String,
        )
            -> Pin<Box<dyn std::future::Future<Output = Result<(), tsclient_rs::Error>> + Send>>
        + Send
        + Sync,
>;

pub(super) fn audio_actor() -> Actor {
    let (events, _) = broadcast::channel(16);
    let (commands, _) = mpsc::unbounded_channel();
    let (_, audio) = mpsc::channel(16);
    let voice = VoiceEngine::spawn(|_| {}, |_| {}).unwrap();
    let (levels, _) = crate::events::level_channel();
    let mut actor = Actor::new(
        PathBuf::new(),
        ServerRegistry::new(),
        events,
        commands,
        SessionAudio {
            voice,
            events: audio,
            levels,
            enabled: false,
        },
    );
    actor.state = SessionState::Connected {
        client_id: 1,
        channel_id: 5,
    };
    actor.self_channel_id = 5;
    actor.capture_active = true;
    actor
}

pub(super) fn client_info(id: i32, channel_id: u64, nickname: &str) -> ClientInfo {
    ClientInfo {
        id,
        nickname: nickname.to_string(),
        uid: String::new(),
        channel_id,
        r#type: 0,
        server_groups: Vec::new(),
        away: None,
        away_message: None,
        input_muted: None,
        output_muted: None,
        channel_commander: None,
    }
}
