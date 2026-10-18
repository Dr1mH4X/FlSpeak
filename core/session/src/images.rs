//! 第三方图片 URL 的最小抓取器。
//!
//! 只用于聊天里用户明确粘贴/图床返回的图片 URL；不走 myTeamSpeak，也不处理
//! `ts.file.myts` 附件。抓取前校验 scheme/官方域名/DNS 结果，抓取时限制重定向、
//! 大小与 content-type，避免把聊天变成任意 SSRF/下载器。官方域名清单与连接
//! 共用 `proto` 的一份定义。

use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr};
use std::time::Duration;

use reqwest::header::{CONTENT_LENGTH, CONTENT_TYPE, LOCATION};
use reqwest::redirect::Policy;
use reqwest::{Client, Url};
use thiserror::Error;

const MAX_IMAGE_BYTES: usize = 20 * 1024 * 1024;
const MAX_REDIRECTS: usize = 3;
const TIMEOUT: Duration = Duration::from_secs(15);

#[derive(Debug, Error)]
pub enum ImageError {
    #[error("图片 URL 不合法: {0}")]
    InvalidUrl(String),
    #[error("图片 URL 指向不允许的主机: {0}")]
    BlockedHost(String),
    #[error("图片地址不允许: {0}")]
    BlockedAddress(String),
    #[error("图片请求失败: {0}")]
    Request(String),
    #[error("不支持的图片格式: {0}")]
    UnsupportedContent(String),
    #[error("图片超过 20 MiB 上限")]
    TooLarge,
    #[error("图片重定向次数过多")]
    TooManyRedirects,
}

/// 抓取一张第三方 URL 图片，返回原始字节。
pub async fn fetch_image(raw_url: &str) -> Result<Vec<u8>, ImageError> {
    let mut current = validate_url(raw_url)?;

    for redirects in 0..=MAX_REDIRECTS {
        let client = build_client(&current).await?;
        let response = client
            .get(current.clone())
            .send()
            .await
            .map_err(|err| ImageError::Request(err.to_string()))?;

        if response.status().is_redirection() {
            if redirects == MAX_REDIRECTS {
                return Err(ImageError::TooManyRedirects);
            }
            let location = response
                .headers()
                .get(LOCATION)
                .and_then(|value| value.to_str().ok())
                .ok_or_else(|| ImageError::InvalidUrl("重定向缺少 Location".into()))?;
            let next = current
                .join(location)
                .map_err(|err| ImageError::InvalidUrl(err.to_string()))?;
            current = validate_url(next.as_str())?;
            continue;
        }

        if !response.status().is_success() {
            return Err(ImageError::Request(format!(
                "HTTP {}",
                response.status().as_u16()
            )));
        }

        if let Some(length) = response
            .headers()
            .get(CONTENT_LENGTH)
            .and_then(|value| value.to_str().ok())
            .and_then(|value| value.parse::<usize>().ok())
            && length > MAX_IMAGE_BYTES
        {
            return Err(ImageError::TooLarge);
        }

        let content_type = response
            .headers()
            .get(CONTENT_TYPE)
            .and_then(|value| value.to_str().ok())
            .unwrap_or("")
            .to_ascii_lowercase();

        let bytes = read_limited(response).await?;
        if bytes.is_empty() {
            return Err(ImageError::UnsupportedContent("空响应".into()));
        }
        if !content_type.starts_with("image/") && !looks_like_image(&bytes) {
            return Err(ImageError::UnsupportedContent(content_type));
        }
        if !looks_like_image(&bytes) {
            return Err(ImageError::UnsupportedContent(
                "content-type 是图片但字节不是 PNG/JPEG/GIF/WebP/AVIF".into(),
            ));
        }
        return Ok(bytes);
    }

    Err(ImageError::TooManyRedirects)
}

async fn read_limited(mut response: reqwest::Response) -> Result<Vec<u8>, ImageError> {
    let mut bytes = Vec::new();
    while let Some(chunk) = response
        .chunk()
        .await
        .map_err(|err| ImageError::Request(err.to_string()))?
    {
        if bytes.len().saturating_add(chunk.len()) > MAX_IMAGE_BYTES {
            return Err(ImageError::TooLarge);
        }
        bytes.extend_from_slice(&chunk);
    }
    Ok(bytes)
}

fn validate_url(raw: &str) -> Result<Url, ImageError> {
    let trimmed = raw.trim();
    let url = Url::parse(trimmed).map_err(|err| ImageError::InvalidUrl(err.to_string()))?;
    if !matches!(url.scheme(), "http" | "https") {
        return Err(ImageError::InvalidUrl("只允许 http/https 图片 URL".into()));
    }
    if !url.username().is_empty() || url.password().is_some() {
        return Err(ImageError::InvalidUrl("图片 URL 不能带凭据".into()));
    }
    let host = url
        .host_str()
        .ok_or_else(|| ImageError::InvalidUrl("缺少主机名".into()))?;
    if proto::forbidden_host(host).is_some() {
        return Err(ImageError::BlockedHost(host.to_string()));
    }
    if host.eq_ignore_ascii_case("localhost") {
        return Err(ImageError::BlockedAddress(host.to_string()));
    }
    Ok(url)
}

async fn build_client(url: &Url) -> Result<Client, ImageError> {
    let host = url
        .host_str()
        .ok_or_else(|| ImageError::InvalidUrl("缺少主机名".into()))?;
    let port = url
        .port_or_known_default()
        .ok_or_else(|| ImageError::InvalidUrl("缺少端口".into()))?;

    let mut builder = Client::builder().timeout(TIMEOUT).redirect(Policy::none());

    let literal_host = host.trim_start_matches('[').trim_end_matches(']');
    if let Ok(ip) = literal_host.parse::<IpAddr>() {
        if !is_public_ip(ip) {
            return Err(ImageError::BlockedAddress(host.to_string()));
        }
    } else {
        let addresses = tokio::net::lookup_host((host, port))
            .await
            .map_err(|err| ImageError::Request(format!("DNS 解析失败: {err}")))?;
        let mut first: Option<SocketAddr> = None;
        for address in addresses {
            if !is_public_ip(address.ip()) {
                return Err(ImageError::BlockedAddress(format!(
                    "{host} -> {}",
                    address.ip()
                )));
            }
            first.get_or_insert(address);
        }
        let address = first.ok_or_else(|| ImageError::Request("DNS 无结果".into()))?;
        builder = builder.resolve(host, address);
    }

    builder
        .build()
        .map_err(|err| ImageError::Request(err.to_string()))
}

fn is_public_ip(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(ip) => is_public_v4(ip),
        IpAddr::V6(ip) => is_public_v6(ip),
    }
}

fn is_public_v4(ip: Ipv4Addr) -> bool {
    let octets = ip.octets();
    if ip.is_private()
        || ip.is_loopback()
        || ip.is_link_local()
        || ip.is_broadcast()
        || ip.is_documentation()
        || ip.is_unspecified()
        || ip.is_multicast()
    {
        return false;
    }
    // 100.64.0.0/10 (CGNAT)、198.18.0.0/15 (benchmark) 也不是公共图片主机。
    !(octets[0] == 100 && (64..=127).contains(&octets[1])
        || octets[0] == 198 && (18..=19).contains(&octets[1]))
}

fn is_public_v6(ip: Ipv6Addr) -> bool {
    if let Some(mapped) = ip.to_ipv4_mapped() {
        return is_public_v4(mapped);
    }
    !(ip.is_loopback()
        || ip.is_unspecified()
        || ip.is_multicast()
        || ip.is_unique_local()
        || ip.is_unicast_link_local())
}

fn looks_like_image(bytes: &[u8]) -> bool {
    bytes.starts_with(b"\x89PNG\r\n\x1a\n")
        || bytes.starts_with(&[0xFF, 0xD8, 0xFF])
        || bytes.starts_with(b"GIF87a")
        || bytes.starts_with(b"GIF89a")
        || (bytes.len() >= 12 && &bytes[0..4] == b"RIFF" && &bytes[8..12] == b"WEBP")
        || (bytes.len() >= 12 && &bytes[4..8] == b"ftyp" && &bytes[8..12] == b"avif")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_non_http_and_credentials() {
        assert!(matches!(
            validate_url("file:///tmp/a.png"),
            Err(ImageError::InvalidUrl(_))
        ));
        assert!(matches!(
            validate_url("https://user:pass@example.com/a.png"),
            Err(ImageError::InvalidUrl(_))
        ));
    }

    #[test]
    fn rejects_forbidden_hosts() {
        let host = proto::FORBIDDEN_HOST_SUFFIXES[0];
        let url = format!("https://{host}/a.png");
        assert!(matches!(
            validate_url(&url),
            Err(ImageError::BlockedHost(_))
        ));
    }

    #[test]
    fn rejects_private_address_literals() {
        for url in [
            "http://127.0.0.1/a.png",
            "http://10.0.0.1/a.png",
            "http://192.168.1.1/a.png",
            "http://[::1]/a.png",
        ] {
            let parsed = validate_url(url).unwrap();
            assert!(matches!(
                build_client_blocking(&parsed),
                Err(ImageError::BlockedAddress(_))
            ));
        }
    }

    fn build_client_blocking(url: &Url) -> Result<Client, ImageError> {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        runtime.block_on(build_client(url))
    }

    #[test]
    fn detects_common_image_magic() {
        assert!(looks_like_image(b"\x89PNG\r\n\x1a\nxxx"));
        assert!(looks_like_image(&[0xFF, 0xD8, 0xFF, 0x00]));
        assert!(looks_like_image(b"GIF89a"));
        assert!(looks_like_image(b"RIFF\0\0\0\0WEBP"));
        assert!(!looks_like_image(b"<html>nope</html>"));
    }
}
