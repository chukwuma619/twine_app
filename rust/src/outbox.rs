use std::collections::VecDeque;
use std::time::Duration;

use nostr_sdk::prelude::{Client, Event};
use tracing::warn;

const MAX_ATTEMPTS: u32 = 5;
const OK_TIMEOUT: Duration = Duration::from_secs(4);

#[derive(Clone)]
struct Pending {
    event: Event,
    attempts: u32,
}

#[derive(Default)]
pub struct Outbox {
    queued: tokio::sync::Mutex<VecDeque<Pending>>,
}

impl Outbox {
    pub async fn enqueue(&self, event: Event) {
        self.queued.lock().await.push_back(Pending { event, attempts: 0 });
    }

    pub async fn flush(&self, client: &Client) -> usize {
        let mut sent = 0;
        loop {
            let next = { self.queued.lock().await.pop_front() };
            let Some(mut item) = next else {
                break;
            };
            item.attempts += 1;
            match publish_first_ok(client, &item.event).await {
                Ok(()) => sent += 1,
                Err(error) => {
                    warn!(%error, attempt = item.attempts, "outbox publish failed");
                    if item.attempts < MAX_ATTEMPTS {
                        self.queued.lock().await.push_front(item);
                    }
                    // Retry on the next resync. Sleeping here blocks resume.
                    break;
                }
            }
        }
        sent
    }

    #[cfg(test)]
    pub async fn len(&self) -> usize {
        self.queued.lock().await.len()
    }
}

pub async fn publish_first_ok(client: &Client, event: &Event) -> anyhow::Result<()> {
    let output = client.send_event(event).ok_timeout(OK_TIMEOUT).await?;
    if output.success.is_empty() {
        anyhow::bail!("no relay accepted the event");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn flush_on_an_empty_outbox_is_a_no_op() {
        let box_ = Outbox::default();
        let client = Client::new();
        assert_eq!(box_.flush(&client).await, 0);
        assert_eq!(box_.len().await, 0);
    }
}
