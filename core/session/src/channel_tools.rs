use std::{
    collections::HashMap,
    time::{Duration, Instant},
};

use base64::Engine;
use sha1::{Digest, Sha1};
use tsclient_rs::Client;

use crate::SessionError;

type Row = HashMap<String, String>;

#[derive(Debug, Clone, Default)]
pub struct AccessView {
    pub member_add_power: Option<i32>,
    pub member_remove_power: Option<i32>,
    pub kick_channel_power: Option<i32>,
    pub kick_server_power: Option<i32>,
    pub connection_epoch: Option<u64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KickTarget {
    Channel,
    Server,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GroupKind {
    Server,
    Channel,
}

#[derive(Debug, Clone)]
pub struct MemberGroupView {
    pub channel_id: u64,
    pub id: u64,
    pub name: String,
    pub kind: GroupKind,
    pub member: bool,
    pub can_add: bool,
    pub can_remove: bool,
}

#[derive(Debug, Clone)]
pub struct ChannelFileView {
    pub name: String,
    pub path: String,
    pub directory: bool,
    pub size: u64,
}

#[derive(Default)]
pub(crate) struct ChannelTools {
    permission_ids: Option<HashMap<String, u32>>,
    definitions: Option<(Instant, Vec<GroupDefinition>)>,
}

struct GroupDefinition {
    id: u64,
    name: String,
    kind: GroupKind,
    needed_add: Option<i32>,
    needed_remove: Option<i32>,
    persistent: bool,
}

pub(crate) fn channel_password(value: &str) -> String {
    if value.is_empty() {
        String::new()
    } else {
        base64::engine::general_purpose::STANDARD.encode(Sha1::digest(value.as_bytes()))
    }
}

pub(crate) fn protocol_error(error: tsclient_rs::Error) -> SessionError {
    match error {
        tsclient_rs::Error::ServerError { ref id, .. } if id == "781" => {
            SessionError::ChannelPasswordRequired
        }
        tsclient_rs::Error::CommandTimeout { .. } => SessionError::Timeout,
        error => SessionError::Protocol(error.to_string()),
    }
}

async fn query(client: &Client, command: &str) -> Result<Vec<Row>, SessionError> {
    client
        .exec_command_with_response(command, 15_000)
        .await
        .map_err(protocol_error)
}

pub(crate) async fn access(
    client: &Client,
    tools: &mut ChannelTools,
) -> Result<AccessView, SessionError> {
    if tools.permission_ids.is_none() {
        let rows = query(client, "permissionlist").await?;
        let mut ids = HashMap::new();
        for (index, row) in rows
            .iter()
            .filter(|row| row.contains_key("permname"))
            .enumerate()
        {
            let id = match row.get("permid") {
                Some(id) => id
                    .parse::<u32>()
                    .map_err(|_| SessionError::Protocol("invalid permission id".into()))?,
                None => u32::try_from(index + 1)
                    .map_err(|_| SessionError::Protocol("too many permissions".into()))?,
            };
            ids.insert(row["permname"].clone(), id);
        }
        tools.permission_ids = Some(ids);
    }
    let value = |name: &str| {
        tools
            .permission_ids
            .as_ref()
            .and_then(|ids| ids.get(name))
            .and_then(|id| client.permission_value(*id))
    };
    Ok(AccessView {
        member_add_power: value("i_group_member_add_power"),
        member_remove_power: value("i_group_member_remove_power"),
        kick_channel_power: value("i_client_kick_from_channel_power"),
        kick_server_power: value("i_client_kick_from_server_power"),
        connection_epoch: None,
    })
}

fn number(row: &Row, key: &str) -> Result<u64, SessionError> {
    row.get(key)
        .and_then(|v| v.parse().ok())
        .ok_or_else(|| SessionError::Protocol(format!("missing or invalid {key}")))
}

async fn member(client: &Client, uid: &str, client_id: i32) -> Result<Row, SessionError> {
    let directory = client
        .directory_snapshot()
        .ok_or(SessionError::NotConnected)?;
    let peer = kick_target(&directory.clients, uid, client_id)?;
    let info = tsclient_rs::getClientInfo(client, peer.id)
        .await
        .map_err(|error| SessionError::Protocol(format!("cannot read member details: {error}")))?;
    if info.get("client_unique_identifier").map(String::as_str) != Some(uid) {
        return Err(SessionError::Protocol("member identity changed".into()));
    }
    Ok(info)
}

fn validate_kick(
    target: KickTarget,
    power: Option<i32>,
    expected_channel: u64,
    current_channel: u64,
    is_self: bool,
) -> Result<(), SessionError> {
    if is_self {
        return Err(SessionError::Protocol("cannot kick yourself".into()));
    }
    if target == KickTarget::Channel
        && (expected_channel == 0 || current_channel != expected_channel)
    {
        return Err(SessionError::Protocol("member changed channel".into()));
    }
    if power.is_none_or(|power| power <= 0) {
        return Err(SessionError::Protocol("insufficient kick power".into()));
    }
    Ok(())
}

fn kick_target<'a>(
    clients: &'a [tsclient_rs::ClientInfo],
    uid: &str,
    client_id: i32,
) -> Result<&'a tsclient_rs::ClientInfo, SessionError> {
    clients
        .iter()
        .find(|peer| client_id > 0 && !uid.is_empty() && peer.id == client_id && peer.uid == uid)
        .ok_or_else(|| SessionError::Protocol("member is offline or identity changed".into()))
}

pub(crate) async fn kick(
    client: &Client,
    tools: &mut ChannelTools,
    uid: &str,
    client_id: i32,
    channel_id: u64,
    target: KickTarget,
    reason: &str,
) -> Result<(), SessionError> {
    if reason.contains('\0') {
        return Err(SessionError::Protocol("invalid kick reason".into()));
    }
    let own = access(client, tools).await?;
    let directory = client
        .directory_snapshot()
        .ok_or(SessionError::NotConnected)?;
    let peer = kick_target(&directory.clients, uid, client_id)?;
    let power = match target {
        KickTarget::Channel => own.kick_channel_power,
        KickTarget::Server => own.kick_server_power,
    };
    validate_kick(
        target,
        power,
        channel_id,
        peer.channel_id,
        peer.id == client.client_id(),
    )?;
    let reason_code = match target {
        KickTarget::Channel => tsclient_rs::KickReason::Channel,
        KickTarget::Server => tsclient_rs::KickReason::Server,
    };
    tsclient_rs::clientKick(client, peer.id, reason_code, reason.trim())
        .await
        .map_err(protocol_error)
}

fn permitted(power: Option<i32>, needed: Option<i32>) -> bool {
    matches!((power, needed), (Some(power), Some(needed)) if power > 0 && power >= needed)
}

async fn groups(
    client: &Client,
    info: &Row,
    tools: &mut ChannelTools,
) -> Result<Vec<MemberGroupView>, SessionError> {
    let own = access(client, tools).await?;
    let definitions = match &tools.definitions {
        Some((loaded, definitions)) if loaded.elapsed() < Duration::from_secs(30) => definitions,
        _ => {
            let mut definitions = Vec::new();
            for (kind, prefix, key) in [
                (GroupKind::Server, "servergroup", "sgid"),
                (GroupKind::Channel, "channelgroup", "cgid"),
            ] {
                let rows = match client
                    .exec_command_with_response(&format!("{prefix}list"), 15_000)
                    .await
                {
                    Ok(rows) => rows,
                    Err(tsclient_rs::Error::ServerError { id, .. }) if id == "2568" => Vec::new(),
                    Err(error) => return Err(protocol_error(error)),
                };
                for row in rows {
                    if row.get("type").map(String::as_str) != Some("1") {
                        continue;
                    }
                    definitions.push(GroupDefinition {
                        id: number(&row, key)?,
                        name: row.get("name").cloned().unwrap_or_default(),
                        kind,
                        needed_add: row.get("n_member_addp").and_then(|v| v.parse().ok()),
                        needed_remove: row.get("n_member_removep").and_then(|v| v.parse().ok()),
                        persistent: kind == GroupKind::Channel
                            || row.get("savedb").map(String::as_str) == Some("1"),
                    });
                }
            }
            &tools.definitions.insert((Instant::now(), definitions)).1
        }
    };
    let server_groups = info
        .get("client_servergroups")
        .map(|v| v.split(',').collect::<Vec<_>>())
        .unwrap_or_default();
    let current_channel = info
        .get("client_channel_group_id")
        .and_then(|v| v.parse::<u64>().ok());
    let mut result = Vec::new();
    for definition in definitions {
        result.push(MemberGroupView {
            channel_id: number(info, "cid")?,
            id: definition.id,
            name: definition.name.clone(),
            kind: definition.kind,
            member: if definition.kind == GroupKind::Server {
                server_groups.contains(&definition.id.to_string().as_str())
            } else {
                current_channel == Some(definition.id)
            },
            can_add: definition.persistent
                && permitted(own.member_add_power, definition.needed_add),
            can_remove: definition.persistent
                && permitted(own.member_remove_power, definition.needed_remove),
        });
    }
    let can_remove_current = result
        .iter()
        .any(|g| g.kind == GroupKind::Channel && g.member && g.can_remove);
    for group in &mut result {
        if group.kind == GroupKind::Channel {
            group.can_add &= can_remove_current;
        }
    }
    Ok(result)
}

pub(crate) async fn member_groups(
    client: &Client,
    uid: &str,
    client_id: i32,
    tools: &mut ChannelTools,
) -> Result<Vec<MemberGroupView>, SessionError> {
    groups(client, &member(client, uid, client_id).await?, tools).await
}

pub(crate) async fn set_member_group(
    client: &Client,
    (uid, client_id): (&str, i32),
    group_id: u64,
    channel_id: u64,
    kind: GroupKind,
    enabled: bool,
    tools: &mut ChannelTools,
) -> Result<(), SessionError> {
    let info = member(client, uid, client_id).await?;
    if kind == GroupKind::Channel && number(&info, "cid")? != channel_id {
        return Err(SessionError::Protocol("member changed channel".into()));
    }
    let available = groups(client, &info, tools).await?;
    let group = available
        .iter()
        .find(|g| g.id == group_id && g.kind == kind)
        .ok_or_else(|| SessionError::Protocol("group is unavailable".into()))?;
    if kind == GroupKind::Channel && !enabled {
        return Err(SessionError::Protocol(
            "select a replacement channel group".into(),
        ));
    }
    if group.member == enabled {
        return Ok(());
    }
    if !(if enabled {
        group.can_add
    } else {
        group.can_remove
    }) {
        return Err(SessionError::Protocol(
            "insufficient group member power".into(),
        ));
    }
    let dbid = number(&info, "client_database_id")?;
    let command = match kind {
        GroupKind::Server => format!(
            "servergroup{}client sgid={group_id} cldbid={dbid}",
            if enabled { "add" } else { "del" }
        ),
        GroupKind::Channel => format!(
            "setclientchannelgroup cgid={group_id} cid={} cldbid={dbid}",
            number(&info, "cid")?
        ),
    };
    let result = client
        .exec_command(&command, 15_000)
        .await
        .map_err(protocol_error);
    if result.is_err() {
        tools.definitions = None;
    }
    result
}

pub(crate) fn remote_path(path: &str) -> Result<(), SessionError> {
    if !path.starts_with('/')
        || path.contains(['\0', '\\'])
        || path.split('/').any(|part| part == ".." || part == ".")
    {
        return Err(SessionError::Transfer("invalid remote file path".into()));
    }
    Ok(())
}

pub(crate) async fn files(
    client: &Client,
    channel_id: u64,
    path: &str,
    password: &str,
) -> Result<Vec<ChannelFileView>, SessionError> {
    remote_path(path)?;
    let command = format!(
        "ftgetfilelist cid={channel_id} cpw={} path={}",
        tsclient_rs::escape(&channel_password(password)).0,
        tsclient_rs::escape(path).0
    );
    let rows = match client.exec_command_with_response(&command, 5_000).await {
        Ok(rows) => rows,
        Err(tsclient_rs::Error::ServerError { id, .. }) if id == "1281" => return Ok(Vec::new()),
        Err(error) => return Err(protocol_error(error)),
    };
    rows.into_iter()
        .map(|row| {
            let name = row
                .get("name")
                .map(|v| v.to_string())
                .ok_or_else(|| SessionError::Transfer("missing file name".into()))?;
            if name.is_empty() || name == "." || name == ".." || name.contains(['/', '\\', '\0']) {
                return Err(SessionError::Transfer("invalid file name".into()));
            }
            let full = format!("{}/{}", path.trim_end_matches('/'), name);
            remote_path(&full)?;
            Ok(ChannelFileView {
                name,
                path: full,
                directory: row.get("type").map(String::as_str) == Some("0"),
                size: row.get("size").and_then(|v| v.parse().ok()).unwrap_or(0),
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn kick_resolves_the_selected_clone_and_rejects_a_reused_client_id() {
        let peer = |id, uid: &str| tsclient_rs::ClientInfo {
            id,
            uid: uid.into(),
            nickname: uid.into(),
            channel_id: 5,
            server_groups: Vec::new(),
            r#type: 0,
            away: None,
            away_message: None,
            input_muted: None,
            output_muted: None,
            channel_commander: None,
        };
        let mut clients = vec![peer(2, "same"), peer(3, "same")];
        assert_eq!(kick_target(&clients, "same", 3).unwrap().id, 3);
        clients[1] = peer(3, "different");
        assert!(kick_target(&clients, "same", 3).is_err());
        assert!(kick_target(&clients, "same", 4).is_err());
        assert!(kick_target(&clients, "", 2).is_err());
        assert!(kick_target(&clients, "same", 0).is_err());
    }
    #[test]
    fn kick_validation_rejects_stale_channels_self_and_missing_power() {
        assert!(validate_kick(KickTarget::Channel, Some(50), 3, 4, false).is_err());
        assert!(validate_kick(KickTarget::Channel, Some(50), 0, 0, false).is_err());
        for target in [KickTarget::Channel, KickTarget::Server] {
            assert!(validate_kick(target, Some(75), 3, 3, true).is_err());
            for power in [None, Some(0), Some(-1)] {
                assert!(validate_kick(target, power, 3, 3, false).is_err());
            }
            assert!(validate_kick(target, Some(50), 3, 3, false).is_ok());
        }
        assert!(validate_kick(KickTarget::Server, Some(50), 3, 4, false).is_ok());
    }
    #[test]
    fn privileges_fail_closed_and_compare_numeric_power() {
        assert!(!permitted(None, Some(0)));
        assert!(!permitted(Some(75), None));
        assert!(!permitted(Some(0), Some(0)));
        assert!(!permitted(Some(50), Some(75)));
        assert!(permitted(Some(75), Some(75)));
    }
    #[test]
    fn password_hash_and_remote_path_validation() {
        assert_eq!(channel_password(""), "");
        assert_eq!(channel_password("test"), "qUqP5cyxm6YcTAhz05Hph5gvu9M=");
        assert!(remote_path("/folder/file.txt").is_ok());
        for path in ["file", "/../file", "/a/./b", "/a\\b", "/a\0b"] {
            assert!(remote_path(path).is_err());
        }
    }
}
