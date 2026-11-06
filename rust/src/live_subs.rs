//! Desired long-lived REQs, kept apart from the SDK registry.
//!
//! nostr-sdk 0.45 drops a subscription that fails to send. A resume that
//! replaces filters while every relay is down would otherwise stay deaf.

use std::collections::HashMap;
use std::time::Duration;

use anyhow::{Result, anyhow};
use nostr_sdk::prelude::{Client, Filter, RelayStatus, SubscriptionId};

const REPAIR_TIMEOUT: Duration = Duration::from_secs(10);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Issued {
    Live,
    Deferred,
}

#[derive(Default)]
pub struct LiveSubs {
    desired: tokio::sync::Mutex<HashMap<SubscriptionId, Filter>>,
}

impl LiveSubs {
    pub async fn replace(
        &self,
        client: &Client,
        id: SubscriptionId,
        filter: Filter,
    ) -> Result<Issued> {
        {
            let mut desired = self.desired.lock().await;
            desired.insert(id.clone(), filter.clone());
        }
        let _ = client.unsubscribe(&id).await;
        issue(client, &id, &filter).await
    }

    pub async fn close(&self, client: &Client, id: &SubscriptionId) {
        self.desired.lock().await.remove(id);
        let _ = client.unsubscribe(id).await;
    }

    pub async fn contains(&self, id: &SubscriptionId) -> bool {
        self.desired.lock().await.contains_key(id)
    }

    pub async fn repair_relay(&self, client: &Client, url: &str) -> usize {
        let Ok(Some(relay)) = client.relay(url).await else {
            return 0;
        };
        let candidates: Vec<SubscriptionId> = {
            let desired = self.desired.lock().await;
            if desired.is_empty() || relay.status() != RelayStatus::Connected {
                return 0;
            }
            missing_on(&desired, &relay.subscriptions().await)
                .into_iter()
                .map(|(id, _)| id)
                .collect()
        };
        let mut issued = 0;
        for id in candidates {
            let filter = {
                let desired = self.desired.lock().await;
                let Some(filter) = desired.get(&id).cloned() else {
                    continue;
                };
                filter
            };
            if relay.status() != RelayStatus::Connected {
                break;
            }
            match relay.subscription(&id).await {
                Some(held) if held.as_slice() == std::slice::from_ref(&filter) => continue,
                Some(_) => {
                    let _ = relay.unsubscribe(&id).await;
                }
                None => {}
            }
            let attempt = tokio::time::timeout(
                REPAIR_TIMEOUT,
                std::future::IntoFuture::into_future(relay.subscribe(filter).with_id(id.clone())),
            )
            .await;
            if matches!(attempt, Ok(Ok(_))) {
                issued += 1;
            }
        }
        issued
    }

    pub async fn repair_all(&self, client: &Client) -> usize {
        let urls: Vec<String> = client
            .relays()
            .await
            .keys()
            .map(|url| url.to_string())
            .collect();
        let mut issued = 0;
        for url in urls {
            issued += self.repair_relay(client, &url).await;
        }
        issued
    }
}

async fn issue(client: &Client, id: &SubscriptionId, filter: &Filter) -> Result<Issued> {
    let output = client
        .subscribe(filter.clone())
        .with_id(id.clone())
        .await
        .map_err(|error| anyhow!("subscribe {id} failed: {error}"))?;
    Ok(if output.success.is_empty() {
        Issued::Deferred
    } else {
        Issued::Live
    })
}

pub fn missing_on(
    desired: &HashMap<SubscriptionId, Filter>,
    present: &HashMap<SubscriptionId, Vec<Filter>>,
) -> Vec<(SubscriptionId, Filter)> {
    desired
        .iter()
        .filter(|(id, filter)| {
            present
                .get(*id)
                .is_none_or(|held| held.as_slice() != std::slice::from_ref(*filter))
        })
        .map(|(id, filter)| (id.clone(), filter.clone()))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use nostr_sdk::prelude::{Keys, Kind};

    fn sample_filter() -> Filter {
        Filter::new()
            .kind(Kind::from(4242))
            .pubkey(Keys::generate().public_key())
    }

    #[test]
    fn missing_on_reports_absent_and_superseded_only() {
        let kept = SubscriptionId::new("kept");
        let absent = SubscriptionId::new("absent");
        let stale = SubscriptionId::new("stale");
        let (kept_f, absent_f, stale_f) = (sample_filter(), sample_filter(), sample_filter());
        let desired = HashMap::from([
            (kept.clone(), kept_f.clone()),
            (absent.clone(), absent_f),
            (stale.clone(), stale_f),
        ]);
        let present = HashMap::from([(kept, vec![kept_f]), (stale.clone(), vec![sample_filter()])]);
        let mut missing: Vec<String> = missing_on(&desired, &present)
            .into_iter()
            .map(|(id, _)| id.to_string())
            .collect();
        missing.sort();
        assert_eq!(missing, vec![absent.to_string(), stale.to_string()]);
    }

    #[tokio::test]
    async fn a_subscription_replaced_while_offline_is_reissued_when_the_relay_connects() {
        let relay = nostr_sdk::local_relay::MockRelay::run()
            .await
            .expect("mock relay");
        let url = relay.url().await;
        let client = Client::new();
        client.add_relay(&url).await.expect("add relay");
        let subs = LiveSubs::default();
        let id = SubscriptionId::new("twine-actions-test");
        let filter = sample_filter();

        let issued = subs
            .replace(&client, id.clone(), filter.clone())
            .await
            .expect("offline replace is deferred");
        client
            .try_connect_relay(&url, Duration::from_secs(3))
            .await
            .expect("connect");
        let sdk_relay = client.relay(&url).await.expect("relay").expect("known");
        assert!(sdk_relay.subscription(&id).await.is_none());
        assert_eq!(issued, Issued::Deferred);
        assert_eq!(subs.repair_relay(&client, url.as_str()).await, 1);
        assert_eq!(sdk_relay.subscription(&id).await, Some(vec![filter]));
        assert_eq!(subs.repair_relay(&client, url.as_str()).await, 0);
    }
}
