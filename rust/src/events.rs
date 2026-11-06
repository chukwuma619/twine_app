#[derive(Clone, Debug)]
pub struct ReplyDto {
    pub envelope_json: String,
    pub created_at_secs: i64,
}

#[derive(Clone, Debug)]
pub struct OrderDto {
    pub content_json: String,
    pub identifier: String,
    pub created_at_secs: i64,
}

#[derive(Clone, Debug)]
pub struct FiberDto {
    pub content_json: String,
}

#[derive(Clone, Debug)]
pub struct ChatDto {
    pub id: String,
    pub author: String,
    pub created_at_secs: i64,
    pub body_json: String,
}

#[derive(Clone, Debug)]
pub struct AccountDto {
    pub private_key: String,
    pub public_key: String,
    pub npub: String,
    pub nsec: String,
}

impl From<crate::keys::AccountKeys> for AccountDto {
    fn from(keys: crate::keys::AccountKeys) -> Self {
        Self {
            private_key: keys.private_key,
            public_key: keys.public_key,
            npub: keys.npub,
            nsec: keys.nsec,
        }
    }
}
