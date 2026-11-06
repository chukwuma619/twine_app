use anyhow::Result;

pub async fn set_push_token(url: String, token: String) -> Result<()> {
    crate::pool::set_push(
        if url.trim().is_empty() {
            None
        } else {
            Some(url)
        },
        if token.trim().is_empty() {
            None
        } else {
            Some(token)
        },
    )
    .await
}
