use anyhow::{Context, Result, bail};
use nostr_sdk::prelude::*;

#[derive(Clone, Debug)]
pub struct AccountKeys {
    pub private_key: String,
    pub public_key: String,
    pub npub: String,
    pub nsec: String,
}

pub fn generate_account() -> Result<AccountKeys> {
    from_keys(Keys::generate())
}

pub fn parse_account(secret: &str) -> Result<Option<AccountKeys>> {
    let trimmed = secret.trim();
    if trimmed.is_empty() {
        return Ok(None);
    }
    match Keys::parse(trimmed) {
        Ok(keys) => Ok(Some(from_keys(keys)?)),
        Err(_) => Ok(None),
    }
}

pub fn parse_public_key(raw: &str) -> Option<String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return None;
    }
    if trimmed.to_ascii_lowercase().starts_with("nsec1") {
        return None;
    }
    PublicKey::parse(trimmed).ok().map(|key| key.to_hex())
}

pub fn encode_npub(hex: &str) -> Result<String> {
    Ok(PublicKey::parse(hex.trim())
        .context("invalid public key")?
        .to_bech32()?)
}

fn from_keys(keys: Keys) -> Result<AccountKeys> {
    let secret = keys.secret_key();
    let public = keys.public_key();
    let nsec = secret
        .to_bech32()
        .map_err(|error| anyhow::anyhow!("{error}"))?;
    let npub = public.to_bech32()?;
    Ok(AccountKeys {
        private_key: secret.to_secret_hex(),
        public_key: public.to_hex(),
        npub,
        nsec,
    })
}

pub fn keys_from_secret(secret: &str) -> Result<Keys> {
    Keys::parse(secret.trim()).context("invalid nsec")
}

pub fn require_websocket(url: &str) -> Result<String> {
    let trimmed = url.trim();
    let lower = trimmed.to_ascii_lowercase();
    if !lower.starts_with("wss://") && !lower.starts_with("ws://") {
        bail!("relay must be ws or wss");
    }
    Ok(trimmed.to_string())
}
