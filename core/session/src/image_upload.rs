use std::net::IpAddr;
use std::time::Duration;

use reqwest::{Client, Request, Url, redirect::Policy};

use crate::ImageError;
use crate::images::{MAX_IMAGE_BYTES, image_format};

pub fn validate_image_host(upload_base: &str, public_base: &str) -> Result<(), ImageError> {
    base_url(upload_base)?;
    base_url(public_base)?;
    Ok(())
}

/// 图床由用户配置；聊天消息不能指定上传目标。公开地址也只从配置生成。
pub async fn upload_image(
    upload_base: &str,
    public_base: &str,
    token: Option<&str>,
    bytes: Vec<u8>,
) -> Result<String, ImageError> {
    let client = Client::builder()
        .no_proxy()
        .redirect(Policy::none())
        .timeout(Duration::from_secs(60))
        .build()
        .map_err(|err| ImageError::Request(err.to_string()))?;
    let (request, public_url) = upload_request(&client, upload_base, public_base, token, bytes)?;
    let response = client
        .execute(request)
        .await
        .map_err(|err| ImageError::Request(err.to_string()))?;
    if !response.status().is_success() {
        return Err(ImageError::Request(format!(
            "上传返回 HTTP {}",
            response.status().as_u16()
        )));
    }
    Ok(public_url.to_string())
}

fn upload_request(
    client: &Client,
    upload_base: &str,
    public_base: &str,
    token: Option<&str>,
    bytes: Vec<u8>,
) -> Result<(Request, Url), ImageError> {
    let upload_base = base_url(upload_base)?;
    let public_base = base_url(public_base)?;
    if bytes.len() > MAX_IMAGE_BYTES {
        return Err(ImageError::TooLarge);
    }
    let (mime, extension) = image_format(&bytes)
        .ok_or_else(|| ImageError::UnsupportedContent("只支持 PNG/JPEG/GIF/WebP/AVIF".into()))?;
    let filename = format!("{:032x}.{extension}", rand::random::<u128>());
    let target = upload_base
        .join(&filename)
        .map_err(|err| ImageError::InvalidUrl(err.to_string()))?;
    let public_url = public_base
        .join(&filename)
        .map_err(|err| ImageError::InvalidUrl(err.to_string()))?;
    let mut request = client
        .put(target)
        .header(reqwest::header::CONTENT_TYPE, mime)
        .body(bytes);
    if let Some(token) = token.filter(|token| !token.is_empty()) {
        request = request.bearer_auth(token);
    }
    Ok((
        request
            .build()
            .map_err(|err| ImageError::Request(err.to_string()))?,
        public_url,
    ))
}

fn base_url(raw: &str) -> Result<Url, ImageError> {
    let mut url = Url::parse(raw.trim()).map_err(|err| ImageError::InvalidUrl(err.to_string()))?;
    let host = url
        .host_str()
        .ok_or_else(|| ImageError::InvalidUrl("缺少图床主机名".into()))?;
    if proto::forbidden_host(host).is_some() {
        return Err(ImageError::BlockedHost(host.into()));
    }
    let loopback = host.eq_ignore_ascii_case("localhost")
        || host
            .trim_matches(['[', ']'])
            .parse::<IpAddr>()
            .is_ok_and(|ip| ip.is_loopback());
    if url.scheme() != "https" && !(url.scheme() == "http" && loopback) {
        return Err(ImageError::InvalidUrl(
            "图床必须使用 HTTPS；本机开发可使用 HTTP".into(),
        ));
    }
    if !url.username().is_empty()
        || url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
    {
        return Err(ImageError::InvalidUrl(
            "图床地址不能带凭据、查询参数或片段".into(),
        ));
    }
    if !url.path().ends_with('/') {
        url.set_path(&format!("{}/", url.path()));
    }
    Ok(url)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn upload_contract_uses_opaque_names_exact_bytes_and_configured_public_base() {
        let bytes = b"\x89PNG\r\n\x1a\npayload".to_vec();
        let (request, public) = upload_request(
            &Client::new(),
            "https://upload.example.com/objects",
            "https://media.example.com/photos",
            Some("test-token"),
            bytes.clone(),
        )
        .unwrap();
        assert_eq!(request.method(), reqwest::Method::PUT);
        assert_eq!(
            request.headers()[reqwest::header::CONTENT_TYPE],
            "image/png"
        );
        assert_eq!(
            request.headers()[reqwest::header::AUTHORIZATION],
            "Bearer test-token"
        );
        assert_eq!(request.body().unwrap().as_bytes().unwrap(), bytes);
        assert_eq!(
            request.url().path_segments().unwrap().next_back(),
            public.path_segments().unwrap().next_back()
        );
        assert!(request.url().path().starts_with("/objects/"));
        assert!(
            public
                .as_str()
                .starts_with("https://media.example.com/photos/")
        );
    }

    #[test]
    fn rejects_invalid_credentials_and_official_hosts_in_both_bases() {
        for raw in [
            "http://upload.example.com/",
            "https://user:secret@example.com/",
            "https://example.com/?token=secret",
            "file:///tmp/",
        ] {
            assert!(base_url(raw).is_err());
        }
        let official = format!("https://media.{}/", proto::FORBIDDEN_HOST_SUFFIXES[0]);
        assert!(matches!(
            validate_image_host(&official, "https://example.com/"),
            Err(ImageError::BlockedHost(_))
        ));
        assert!(matches!(
            validate_image_host("https://example.com/", &official),
            Err(ImageError::BlockedHost(_))
        ));
        assert!(
            validate_image_host("http://127.0.0.1/upload", "https://images.example.com/").is_ok()
        );
    }

    #[test]
    fn refuses_non_images_and_oversized_payloads_before_uploading() {
        assert!(matches!(
            upload_request(
                &Client::new(),
                "https://upload.example.com",
                "https://media.example.com",
                None,
                b"not an image".to_vec()
            ),
            Err(ImageError::UnsupportedContent(_))
        ));
        assert!(matches!(
            upload_request(
                &Client::new(),
                "https://upload.example.com",
                "https://media.example.com",
                None,
                vec![0; MAX_IMAGE_BYTES + 1]
            ),
            Err(ImageError::TooLarge)
        ));
    }
}
