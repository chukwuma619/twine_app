use anyhow::{Context, Result};
use serde::Serialize;

#[derive(Serialize)]
struct RegisterBody<'a> {
    pubkey: &'a str,
    token: &'a str,
}

pub async fn register(base_url: &str, pubkey: &str, token: &str) -> Result<()> {
    post_token(base_url, "register", pubkey, token).await
}

pub async fn unregister(base_url: &str, pubkey: &str, token: &str) -> Result<()> {
    post_token(base_url, "unregister", pubkey, token).await
}

async fn post_token(base_url: &str, path: &str, pubkey: &str, token: &str) -> Result<()> {
    let url = format!("{}/{path}", base_url.trim_end_matches('/'));
    let client = reqwest::Client::new();
    let response = client
        .post(url)
        .json(&RegisterBody { pubkey, token })
        .send()
        .await
        .with_context(|| format!("push {path} failed"))?;
    if !response.status().is_success() {
        anyhow::bail!("push {path} returned {}", response.status());
    }
    Ok(())
}
