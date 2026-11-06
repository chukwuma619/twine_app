use anyhow::Result;

use crate::events::{ChatDto, FiberDto, OrderDto, ReplyDto};

pub async fn initialize(
    nsec: String,
    daemon_hex: String,
    relays: Vec<String>,
) -> Result<Vec<String>> {
    crate::pool::initialize(nsec, daemon_hex, relays).await
}

pub async fn resync() -> Result<Vec<String>> {
    crate::pool::resync().await
}

pub async fn send_action(envelope_json: String) -> Result<()> {
    crate::pool::send_action(envelope_json).await
}

pub async fn send_chat(peer_hex: String, body_json: String) -> Result<ChatDto> {
    crate::pool::send_chat(peer_hex, body_json).await
}

pub async fn watch_trade_chat(authors: Vec<String>, trade_ids: Vec<String>) -> Result<()> {
    crate::pool::watch_trade_chat(authors, trade_ids).await
}

pub async fn conversation_key(peer_hex: String) -> Result<String> {
    crate::pool::conversation_key(peer_hex).await
}

pub async fn connected_relays() -> Result<Vec<String>> {
    crate::pool::connected_relays().await
}

pub async fn connection_state() -> Result<String> {
    crate::pool::connection_state().await
}

pub struct ReplyStream {
    rx: tokio::sync::broadcast::Receiver<ReplyDto>,
}

pub fn listen_replies() -> Result<ReplyStream> {
    Ok(ReplyStream {
        rx: crate::pool::pool()?.replies(),
    })
}

impl ReplyStream {
    pub async fn next(&mut self) -> Option<ReplyDto> {
        recv(&mut self.rx).await
    }
}

pub struct OrderStream {
    rx: tokio::sync::broadcast::Receiver<OrderDto>,
}

pub fn listen_orders() -> Result<OrderStream> {
    Ok(OrderStream {
        rx: crate::pool::pool()?.orders(),
    })
}

impl OrderStream {
    pub async fn next(&mut self) -> Option<OrderDto> {
        recv(&mut self.rx).await
    }
}

pub struct FiberStream {
    rx: tokio::sync::broadcast::Receiver<FiberDto>,
}

pub fn listen_fiber() -> Result<FiberStream> {
    Ok(FiberStream {
        rx: crate::pool::pool()?.fiber(),
    })
}

impl FiberStream {
    pub async fn next(&mut self) -> Option<FiberDto> {
        recv(&mut self.rx).await
    }
}

pub struct ChatStream {
    rx: tokio::sync::broadcast::Receiver<ChatDto>,
}

pub fn listen_chats() -> Result<ChatStream> {
    Ok(ChatStream {
        rx: crate::pool::pool()?.chats(),
    })
}

impl ChatStream {
    pub async fn next(&mut self) -> Option<ChatDto> {
        recv(&mut self.rx).await
    }
}

async fn recv<T: Clone>(rx: &mut tokio::sync::broadcast::Receiver<T>) -> Option<T> {
    loop {
        match rx.recv().await {
            Ok(value) => return Some(value),
            Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
            Err(tokio::sync::broadcast::error::RecvError::Closed) => return None,
        }
    }
}
