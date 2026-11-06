use nostr::nips::nip44::{self, Version};
use nostr_sdk::prelude::*;

#[test]
fn conversation_keys_match_the_nip44_vectors() {
    let cases = [
        (
            "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364139",
            "0000000000000000000000000000000000000000000000000000000000000002",
            "8b6392dbf2ec6a2b2d5b1477fc2be84d63ef254b667cadd31bd3f444c44ae6ba",
        ),
        (
            "0000000000000000000000000000000000000000000000000000000000000002",
            "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdeb",
            "be234f46f60a250bef52a5ee34c758800c4ca8e5030bf4cc1a31d37ba2104d43",
        ),
        (
            "0000000000000000000000000000000000000000000000000000000000000001",
            "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
            "3b4610cb7189beb9cc29eb3716ecc6102f1247e8f3101a03a1787d8908aeb54e",
        ),
    ];
    for (secret, public, expected) in cases {
        let keys = Keys::parse(secret).unwrap();
        let peer = PublicKey::parse(public).unwrap();
        let key = nip44::v2::ConversationKey::derive(keys.secret_key(), &peer).unwrap();
        assert_eq!(hex::encode(key.as_bytes()), expected);
    }
}

#[test]
fn a_generated_account_imports_back() {
    let created = crate::keys::generate_account().unwrap();
    let imported = crate::keys::parse_account(&created.nsec)
        .unwrap()
        .expect("nsec");
    assert_eq!(imported.public_key, created.public_key);
    assert_eq!(imported.npub, created.npub);
    assert!(crate::keys::parse_account("not-a-key").unwrap().is_none());
    assert!(crate::keys::parse_public_key(&created.nsec).is_none());
    assert_eq!(
        crate::keys::parse_public_key(&created.npub).as_deref(),
        Some(created.public_key.as_str())
    );
}

#[test]
fn action_round_trip_opens_only_for_the_daemon() {
    let user = Keys::generate();
    let daemon = Keys::generate();
    let stranger = Keys::generate();
    let envelope = r#"{"action":"new-order","payload":{"side":"sell"}}"#;
    let ciphertext = nip44::encrypt(
        user.secret_key(),
        &daemon.public_key(),
        envelope,
        Version::V2,
    )
    .unwrap();
    let opened = nip44::decrypt(daemon.secret_key(), &user.public_key(), &ciphertext).unwrap();
    assert_eq!(opened, envelope);
    assert!(nip44::decrypt(stranger.secret_key(), &user.public_key(), &ciphertext).is_err());
}
