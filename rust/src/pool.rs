use std::sync::{Arc, OnceLock};
use std::time::Duration;

use anyhow::{Context, Result, bail};
use nostr::nips::nip44::{self, Version};
use nostr_sdk::prelude::*;
use tokio::sync::{Mutex, broadcast};
use tracing::{info, warn};

use crate::events::{ChatDto, FiberDto, OrderDto, ReplyDto};
use crate::keys::{keys_from_secret, require_websocket};
use crate::kinds::{
    FIBER_NODE_TAG, KIND_ACTION, KIND_CHAT, KIND_FIBER_NODE, KIND_ORDER, KIND_TRADE_RECORD,
    SUB_ACTIONS, SUB_CHAT, SUB_FIBER, SUB_ORDERS, SUB_TRADE_RECORDS,
};
use crate::live_subs::LiveSubs;
use crate::outbox::{self, Outbox};

const RELAY_CONNECT_TIMEOUT: Duration = Duration::from_secs(15);
const RELAY_RETRY: Duration = Duration::from_secs(5);
const RECONNECT_GRACE: Duration = Duration::from_millis(250);
const RESYNC_CONNECT_WAIT: Duration = Duration::from_secs(5);

static POOL: OnceLock<Arc<Pool>> = OnceLock::new();
static PENDING_PUSH: OnceLock<Mutex<(Option<String>, Option<String>)>> = OnceLock::new();

fn pending_push() -> &'static Mutex<(Option<String>, Option<String>)> {
    PENDING_PUSH.get_or_init(|| Mutex::new((None, None)))
}

pub struct Pool {
    client: Client,
    keys: Mutex<Keys>,
    daemon: Mutex<PublicKey>,
    live: LiveSubs,
    outbox: Outbox,
    replies: broadcast::Sender<ReplyDto>,
    orders: broadcast::Sender<OrderDto>,
    fiber: broadcast::Sender<FiberDto>,
    chats: broadcast::Sender<ChatDto>,
    chat_authors: Mutex<Vec<String>>,
    chat_trades: Mutex<Vec<String>>,
    push_url: Mutex<Option<String>>,
    push_token: Mutex<Option<String>>,
    resyncing: Mutex<()>,
}

impl Pool {
    pub fn replies(&self) -> broadcast::Receiver<ReplyDto> {
        self.replies.subscribe()
    }

    pub fn orders(&self) -> broadcast::Receiver<OrderDto> {
        self.orders.subscribe()
    }

    pub fn fiber(&self) -> broadcast::Receiver<FiberDto> {
        self.fiber.subscribe()
    }

    pub fn chats(&self) -> broadcast::Receiver<ChatDto> {
        self.chats.subscribe()
    }
}

pub fn pool() -> Result<Arc<Pool>> {
    POOL.get().cloned().context("nostr pool is not initialized")
}

pub async fn initialize(nsec: String, daemon_hex: String, relays: Vec<String>) -> Result<Vec<String>> {
    let keys = keys_from_secret(&nsec)?;
    let daemon = PublicKey::parse(daemon_hex.trim()).context("invalid daemon key")?;
    let relays = normalize_relays(&relays)?;
    if let Some(existing) = POOL.get() {
        let previous = existing.keys.lock().await.public_key();
        let previous_daemon = *existing.daemon.lock().await;
        if previous != keys.public_key() || previous_daemon != daemon {
            *existing.chat_authors.lock().await = Vec::new();
            *existing.chat_trades.lock().await = Vec::new();
        }
        *existing.keys.lock().await = keys;
        *existing.daemon.lock().await = daemon;
        let (push_url, push_token) = pending_push().lock().await.clone();
        *existing.push_url.lock().await = push_url;
        *existing.push_token.lock().await = push_token;
        replace_relays(&existing.client, &relays).await?;
        return existing.resync().await;
    }
    let client = Client::builder()
        .authenticator(SignerAuthenticator::new(keys.clone()))
        .build();
    for relay in &relays {
        client
            .add_relay(relay)
            .retry_interval(RELAY_RETRY)
            .adjust_retry_interval(false)
            .await
            .with_context(|| format!("invalid relay {relay}"))?;
    }
    client.connect().and_wait(RELAY_CONNECT_TIMEOUT).await;
    let (push_url, push_token) = pending_push().lock().await.clone();
    let (replies, _) = broadcast::channel(256);
    let (orders, _) = broadcast::channel(256);
    let (fiber, _) = broadcast::channel(256);
    let (chats, _) = broadcast::channel(256);
    let pool = Arc::new(Pool {
        client,
        keys: Mutex::new(keys),
        daemon: Mutex::new(daemon),
        live: LiveSubs::default(),
        outbox: Outbox::default(),
        replies,
        orders,
        fiber,
        chats,
        chat_authors: Mutex::new(Vec::new()),
        chat_trades: Mutex::new(Vec::new()),
        push_url: Mutex::new(push_url),
        push_token: Mutex::new(push_token),
        resyncing: Mutex::new(()),
    });
    let _ = POOL.set(pool.clone());
    spawn_notifications(pool.clone());
    pool.resync().await
}

pub async fn resync() -> Result<Vec<String>> {
    pool()?.resync().await
}

pub async fn send_action(envelope_json: String) -> Result<()> {
    let pool = pool()?;
    let keys = pool.keys.lock().await.clone();
    let daemon = *pool.daemon.lock().await;
    let ciphertext = nip44::encrypt(keys.secret_key(), &daemon, envelope_json, Version::V2)?;
    let event = EventBuilder::new(Kind::from(KIND_ACTION), ciphertext)
        .tag(Tag::public_key(daemon))
        .finalize(&keys)?;
    if let Err(error) = outbox::publish_first_ok(&pool.client, &event).await {
        warn!(%error, "action queued until a relay accepts it");
        pool.outbox.enqueue(event).await;
    }
    Ok(())
}

pub async fn send_chat(peer_hex: String, body_json: String) -> Result<ChatDto> {
    let pool = pool()?;
    let keys = pool.keys.lock().await.clone();
    let peer = PublicKey::parse(peer_hex.trim()).context("invalid peer key")?;
    let body: serde_json::Value = serde_json::from_str(&body_json)?;
    let trade_id = body
        .get("trade_id")
        .and_then(|value| value.as_str())
        .context("chat body missing trade_id")?
        .to_string();
    let ciphertext = nip44::encrypt(keys.secret_key(), &peer, &body_json, Version::V2)?;
    let event = EventBuilder::new(Kind::from(KIND_CHAT), ciphertext)
        .tag(Tag::public_key(peer))
        .tag(Tag::hashtag(trade_id))
        .finalize(&keys)?;
    if let Err(error) = outbox::publish_first_ok(&pool.client, &event).await {
        warn!(%error, "chat queued until a relay accepts it");
        pool.outbox.enqueue(event.clone()).await;
    }
    Ok(ChatDto {
        id: event.id.to_hex(),
        author: event.pubkey.to_hex(),
        created_at_secs: timestamp_secs(&event),
        body_json,
    })
}

pub async fn watch_trade_chat(authors: Vec<String>, trade_ids: Vec<String>) -> Result<()> {
    let pool = pool()?;
    *pool.chat_authors.lock().await = authors;
    *pool.chat_trades.lock().await = trade_ids;
    pool.subscribe_chat().await
}

pub async fn conversation_key(peer_hex: String) -> Result<String> {
    let pool = pool()?;
    let keys = pool.keys.lock().await.clone();
    let peer = PublicKey::parse(peer_hex.trim()).context("invalid peer key")?;
    let key = nip44::v2::ConversationKey::derive(keys.secret_key(), &peer)?;
    Ok(hex::encode(key.as_bytes()))
}

pub async fn set_push(url: Option<String>, token: Option<String>) -> Result<()> {
    let url = url.filter(|value| !value.trim().is_empty());
    let token = token.filter(|value| !value.trim().is_empty());
    *pending_push().lock().await = (url.clone(), token.clone());
    let Ok(pool) = pool() else {
        return Ok(());
    };
    let previous_url = pool.push_url.lock().await.clone();
    let previous_token = pool.push_token.lock().await.clone();
    *pool.push_url.lock().await = url.clone();
    *pool.push_token.lock().await = token.clone();
    let changed = previous_url != url || previous_token != token;
    if changed {
        if let (Some(prev_url), Some(prev_token)) = (previous_url, previous_token) {
            let pubkey = pool.keys.lock().await.public_key().to_hex();
            if let Err(error) = crate::push::unregister(&prev_url, &pubkey, &prev_token).await {
                warn!(%error, "push unregister failed");
            }
        }
    }
    if url.is_some() && token.is_some() {
        pool.reconcile_push().await
    } else {
        Ok(())
    }
}

pub async fn connected_relays() -> Result<Vec<String>> {
    Ok(connected_relay_urls(&pool()?.client).await)
}

pub async fn connection_state() -> Result<String> {
    Ok(if connected_relays().await?.is_empty() {
        "disconnected".into()
    } else {
        "connected".into()
    })
}

impl Pool {
    async fn resync(&self) -> Result<Vec<String>> {
        let _guard = self.resyncing.lock().await;
        self.run_resync().await
    }

    async fn run_resync(&self) -> Result<Vec<String>> {
        wake_disconnected(&self.client).await;
        self.client.connect().and_wait(RESYNC_CONNECT_WAIT).await;
        self.subscribe_core().await?;
        self.subscribe_chat().await?;
        self.live.repair_all(&self.client).await;
        self.outbox.flush(&self.client).await;
        let _ = self.reconcile_push().await;
        let urls = connected_relay_urls(&self.client).await;
        if urls.is_empty() {
            warn!("no nostr relay connected; live_subs will repair");
        }
        Ok(urls)
    }

    async fn subscribe_core(&self) -> Result<()> {
        let keys = self.keys.lock().await.clone();
        let daemon = *self.daemon.lock().await;
        let account = keys.public_key();
        self.live
            .replace(
                &self.client,
                SubscriptionId::new(SUB_ACTIONS),
                Filter::new()
                    .kind(Kind::from(KIND_ACTION))
                    .author(daemon)
                    .pubkey(account),
            )
            .await?;
        self.live
            .replace(
                &self.client,
                SubscriptionId::new(SUB_ORDERS),
                Filter::new().kind(Kind::from(KIND_ORDER)).author(daemon),
            )
            .await?;
        self.live
            .replace(
                &self.client,
                SubscriptionId::new(SUB_FIBER),
                Filter::new()
                    .kind(Kind::from(KIND_FIBER_NODE))
                    .author(daemon)
                    .identifier(FIBER_NODE_TAG),
            )
            .await?;
        self.live
            .replace(
                &self.client,
                SubscriptionId::new(SUB_TRADE_RECORDS),
                Filter::new()
                    .kind(Kind::from(KIND_TRADE_RECORD))
                    .author(daemon),
            )
            .await?;
        Ok(())
    }

    async fn subscribe_chat(&self) -> Result<()> {
        let authors = self.chat_authors.lock().await.clone();
        let trades = self.chat_trades.lock().await.clone();
        let keys = self.keys.lock().await.clone();
        if authors.is_empty() || trades.is_empty() {
            self.live
                .close(&self.client, &SubscriptionId::new(SUB_CHAT))
                .await;
            return Ok(());
        }
        let mut pubkeys = Vec::new();
        for author in authors {
            if let Ok(pubkey) = PublicKey::parse(&author) {
                pubkeys.push(pubkey);
            }
        }
        if pubkeys.is_empty() {
            self.live
                .close(&self.client, &SubscriptionId::new(SUB_CHAT))
                .await;
            return Ok(());
        }
        let filter = Filter::new()
            .kind(Kind::from(KIND_CHAT))
            .pubkey(keys.public_key())
            .authors(pubkeys)
            .hashtags(trades);
        self.live
            .replace(&self.client, SubscriptionId::new(SUB_CHAT), filter)
            .await?;
        Ok(())
    }

    async fn reconcile_push(&self) -> Result<()> {
        let url = self.push_url.lock().await.clone();
        let token = self.push_token.lock().await.clone();
        let (Some(url), Some(token)) = (url, token) else {
            return Ok(());
        };
        let pubkey = self.keys.lock().await.public_key().to_hex();
        crate::push::register(&url, &pubkey, &token).await
    }

    async fn handle_event(&self, event: Event) {
        let kind = event.kind.as_u16();
        if kind == KIND_ACTION {
            self.handle_action(event).await;
        } else if kind == KIND_ORDER {
            self.handle_order(event).await;
        } else if kind == KIND_FIBER_NODE {
            self.handle_fiber(event).await;
        } else if kind == KIND_TRADE_RECORD {
            self.handle_trade_record(event).await;
        } else if kind == KIND_CHAT {
            self.handle_chat(event).await;
        }
    }

    async fn handle_action(&self, event: Event) {
        let keys = self.keys.lock().await.clone();
        let daemon = *self.daemon.lock().await;
        if event.pubkey != daemon {
            return;
        }
        if event.verify().is_err() {
            return;
        }
        let Ok(plaintext) = nip44::decrypt(keys.secret_key(), &event.pubkey, event.content.as_str())
        else {
            return;
        };
        let _ = self.replies.send(ReplyDto {
            envelope_json: plaintext,
            created_at_secs: timestamp_secs(&event),
        });
    }

    async fn handle_order(&self, event: Event) {
        let daemon = *self.daemon.lock().await;
        if event.pubkey != daemon || event.verify().is_err() {
            return;
        }
        let Some(identifier) = event.tags.identifier().map(|value| value.to_string()) else {
            return;
        };
        let _ = self.orders.send(OrderDto {
            content_json: event.content.clone(),
            identifier,
            created_at_secs: timestamp_secs(&event),
        });
    }

    async fn handle_fiber(&self, event: Event) {
        let daemon = *self.daemon.lock().await;
        if event.pubkey != daemon || event.verify().is_err() {
            return;
        }
        if event.tags.identifier().as_deref() != Some(FIBER_NODE_TAG) {
            return;
        }
        let _ = self.fiber.send(FiberDto {
            content_json: event.content.clone(),
        });
    }

    /// Public kind 31422 from the daemon, remapped to the private `trade-record` reply.
    async fn handle_trade_record(&self, event: Event) {
        let daemon = *self.daemon.lock().await;
        if event.pubkey != daemon || event.verify().is_err() {
            return;
        }
        let Ok(value) = serde_json::from_str::<serde_json::Value>(&event.content) else {
            return;
        };
        let Some(trade_id) = value
            .get("trade_id")
            .and_then(|item| item.as_str())
            .map(str::trim)
            .filter(|value| !value.is_empty())
        else {
            return;
        };
        let Some(outcome) = value
            .get("outcome")
            .and_then(|item| item.as_str())
            .map(str::trim)
            .filter(|value| !value.is_empty())
        else {
            return;
        };
        let account = self.keys.lock().await.public_key().to_hex().to_lowercase();
        let seller = value
            .get("seller_nostr")
            .and_then(|item| item.as_str())
            .unwrap_or("")
            .to_lowercase();
        let buyer = value
            .get("buyer_nostr")
            .and_then(|item| item.as_str())
            .unwrap_or("")
            .to_lowercase();
        if account != seller && account != buyer {
            return;
        }
        let Ok(envelope_json) = serde_json::to_string(&serde_json::json!({
            "action": "trade-record",
            "trade_id": trade_id,
            "payload": { "outcome": outcome },
        })) else {
            return;
        };
        let _ = self.replies.send(ReplyDto {
            envelope_json,
            created_at_secs: timestamp_secs(&event),
        });
    }

    async fn handle_chat(&self, event: Event) {
        let keys = self.keys.lock().await.clone();
        if event.verify().is_err() {
            return;
        }
        let Ok(plaintext) = nip44::decrypt(keys.secret_key(), &event.pubkey, event.content.as_str())
        else {
            return;
        };
        let _ = self.chats.send(ChatDto {
            id: event.id.to_hex(),
            author: event.pubkey.to_hex(),
            created_at_secs: timestamp_secs(&event),
            body_json: plaintext,
        });
    }
}

fn spawn_notifications(pool: Arc<Pool>) {
    tokio::spawn(async move {
        loop {
            let mut notifications = pool.client.notifications();
            while let Some(notification) = notifications.next().await {
                match notification {
                    ClientNotification::Event { event, .. } => {
                        pool.handle_event(*event).await;
                    }
                    ClientNotification::Message { message, relay_url, .. } => {
                        let RelayMessage::Closed {
                            subscription_id, ..
                        } = message.as_ref()
                        else {
                            continue;
                        };
                        if pool.live.contains(subscription_id).await {
                            warn!(%relay_url, %subscription_id, "subscription closed; repairing");
                            pool.live.repair_relay(&pool.client, &relay_url.to_string()).await;
                        }
                    }
                    ClientNotification::Shutdown => {
                        warn!("nostr notification stream ended; reopening");
                        break;
                    }
                }
            }
            tokio::time::sleep(Duration::from_secs(1)).await;
        }
    });
}

fn timestamp_secs(event: &Event) -> i64 {
    i64::try_from(event.created_at.as_secs()).unwrap_or(0)
}

fn normalize_relays(relays: &[String]) -> Result<Vec<String>> {
    let mut out = Vec::new();
    for relay in relays {
        let url = require_websocket(relay)?;
        if !out.contains(&url) {
            out.push(url);
        }
    }
    if out.is_empty() {
        bail!("enter at least one relay starting with wss://");
    }
    Ok(out)
}

async fn replace_relays(client: &Client, relays: &[String]) -> Result<()> {
    let current: Vec<String> = client
        .relays()
        .await
        .keys()
        .map(|url| url.to_string())
        .collect();
    for url in &current {
        if !relays.iter().any(|relay| relay == url) {
            let _ = client.remove_relay(url).await;
        }
    }
    for relay in relays {
        if !current.iter().any(|url| url == relay) {
            client
                .add_relay(relay)
                .retry_interval(RELAY_RETRY)
                .adjust_retry_interval(false)
                .await
                .with_context(|| format!("invalid relay {relay}"))?;
        }
    }
    Ok(())
}

pub fn disconnected_relay_urls(
    relays: impl IntoIterator<Item = (String, RelayStatus)>,
) -> Vec<String> {
    relays
        .into_iter()
        .filter(|(_, status)| *status == RelayStatus::Disconnected)
        .map(|(url, _)| url)
        .collect()
}

pub async fn wake_disconnected(client: &Client) -> usize {
    let urls = disconnected_relay_urls(
        client
            .relays()
            .await
            .into_iter()
            .map(|(url, relay)| (url.to_string(), relay.status())),
    );
    for url in &urls {
        if let Err(error) = client.disconnect_relay(url.as_str()).await {
            warn!(%url, %error, "disconnect before wake failed");
        }
    }
    if !urls.is_empty() {
        tokio::time::sleep(RECONNECT_GRACE).await;
    }
    for url in &urls {
        if let Err(error) = client.connect_relay(url.as_str()).await {
            warn!(%url, %error, "wake did not start");
        }
    }
    if !urls.is_empty() {
        info!(count = urls.len(), "woke disconnected relays");
    }
    urls.len()
}

pub async fn connected_relay_urls(client: &Client) -> Vec<String> {
    let mut urls = Vec::new();
    for (url, relay) in client.relays().await {
        if relay.status().is_connected() {
            urls.push(url.to_string());
        }
    }
    urls.sort();
    urls
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn disconnected_relays_are_the_ones_connect_cannot_wake() {
        assert_eq!(
            disconnected_relay_urls([
                ("wss://a".into(), RelayStatus::Connected),
                ("wss://b".into(), RelayStatus::Disconnected),
                ("wss://c".into(), RelayStatus::Terminated),
            ]),
            vec!["wss://b".to_string()]
        );
    }

    #[test]
    fn require_websocket_rejects_http() {
        assert!(require_websocket("https://example.com").is_err());
        assert!(require_websocket("wss://relay.example.com").is_ok());
    }

    #[tokio::test]
    async fn resync_is_single_flight() {
        // Without a live pool, resync reports the missing init instead of
        // stacking two recovery passes.
        let first = resync();
        let second = resync();
        let (a, b) = tokio::join!(first, second);
        assert!(a.is_err());
        assert!(b.is_err());
    }

    #[tokio::test]
    async fn set_push_before_init_is_remembered() {
        set_push(
            Some("https://push.example".into()),
            Some("device-token".into()),
        )
        .await
        .expect("pending push does not need a pool");
        let pending = pending_push().lock().await.clone();
        assert_eq!(pending.0.as_deref(), Some("https://push.example"));
        assert_eq!(pending.1.as_deref(), Some("device-token"));
        set_push(None, None)
            .await
            .expect("clearing push does not need a pool");
        let pending = pending_push().lock().await.clone();
        assert_eq!(pending.0, None);
        assert_eq!(pending.1, None);
    }
}
