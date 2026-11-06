use anyhow::Result;

use crate::events::AccountDto;

pub fn generate_account() -> Result<AccountDto> {
    Ok(crate::keys::generate_account()?.into())
}

pub fn parse_account(secret: String) -> Result<Option<AccountDto>> {
    Ok(crate::keys::parse_account(&secret)?.map(Into::into))
}

pub fn parse_public_key(raw: String) -> Option<String> {
    crate::keys::parse_public_key(&raw)
}

pub fn encode_npub(hex: String) -> Result<String> {
    crate::keys::encode_npub(&hex)
}
