use anyhow::{Context, Result};
use nostr::nips::nip98::{HttpData, HttpMethod};
use nostr::prelude::*;
use serde::Serialize;
use sha2::{Digest, Sha256};

#[derive(Serialize)]
struct RegisterBody<'a> {
    token: &'a str,
}

pub async fn register(base_url: &str, keys: &Keys, token: &str) -> Result<()> {
    post_token(base_url, "register", keys, token).await
}

pub async fn unregister(base_url: &str, keys: &Keys, token: &str) -> Result<()> {
    post_token(base_url, "unregister", keys, token).await
}

async fn post_token(base_url: &str, path: &str, keys: &Keys, token: &str) -> Result<()> {
    let url = format!("{}/{path}", base_url.trim_end_matches('/'));
    let body = RegisterBody { token };
    let body_bytes = serde_json::to_vec(&body).context("push body")?;
    let payload = Sha256Hash::from_byte_array(Sha256::digest(&body_bytes).into());
    let auth = HttpData::new(Url::parse(&url).context("push url")?, HttpMethod::POST)
        .payload(payload)
        .to_authorization(keys)
        .await
        .context("push auth")?;
    let client = reqwest::Client::new();
    let response = client
        .post(&url)
        .header(reqwest::header::AUTHORIZATION, auth)
        .header(reqwest::header::CONTENT_TYPE, "application/json")
        .body(body_bytes)
        .send()
        .await
        .with_context(|| format!("push {path} failed"))?;
    if !response.status().is_success() {
        anyhow::bail!("push {path} returned {}", response.status());
    }
    Ok(())
}
