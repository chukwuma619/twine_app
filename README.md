# Twine

Twine is a Flutter app for buying and selling CKB with another person. Fiat moves outside the app. CKB stays in your Fiber wallet.

The app talks to one [Twine daemon](https://github.com/chukwuma619/twine) over Nostr. It does not hold a Fiber key, does not pay an invoice, and does not settle a hold. You pay and receive on your own Fiber node. The daemon coordinates the trade and publishes the book.

## What you can do today

- Create a Nostr key, or import an `nsec`. That key is the account.
- Connect to a daemon and browse sell posts.
- Post CKB for sale, take a slice with a Fiber invoice, and cancel before the hold locks.
- Follow the trade. The seller locks CKB in their own Fiber wallet, writes how to pay, and releases after the fiat arrives. The buyer sends fiat outside Twine, attaches a receipt, and marks it sent.
- Chat with the other trader. Messages and receipt photos are encrypted to that person.
- Open a dispute. This app does not resolve one. The solver does that from their own key.
- Keep the Nostr secret in the platform keystore.

A new install offers one public daemon. Replace the public key and relays if you run your own. The daemon logs the `npub` to paste here.

| | |
| --- | --- |
| Public key | `npub1avxxz0xj3pgxugrr9s9e56xsfhw0f3slgrusw3960s4ak8ys0lsqhs05j6` |
| Relays | `wss://relay.backr.site` |

## Planned

Not in the app yet. The daemon side of this list is in [PROPOSAL.md](https://github.com/chukwuma619/twine/blob/main/PROPOSAL.md).

- Payment methods on a post, starting with NGN bank transfer and USD via Zelle, and a clock for that method's window as well as the hold.
- A counterparty's public trade record: settled trades, completion rate, and typical time to pay or release.
- Privacy mode, which uses a fresh Nostr key for a single trade.
- The hub's receivable and payable CKB, and a short guide to inbound and outbound channels.
- Filters on the book, and scanning a Fiber invoice.
- UDT posts, once the daemon lists them.
- App Store and Play Store builds. macOS, Windows, Linux, and Android files are already published as GitHub releases.

## Run

Use the Flutter SDK named in `pubspec.yaml`.

```bash
flutter pub get
flutter run
```

`flutter run` picks a connected phone, simulator, or desktop. Pass `-d` to choose one.

```bash
flutter test
```

## Releases

From a clean checkout of the commit testers should get:

```bash
tool/release.sh 1.0.2
```

That sets `version:` in `pubspec.yaml`, commits it, tags `v1.0.2`, and pushes. GitHub Actions attaches these files to the release:

| File | Testers |
| --- | --- |
| `Twine-1.0.2-macos.dmg` | macOS 12 or newer |
| `Twine-1.0.2-windows-x64.zip` | Windows 10 or 11, 64-bit |
| `Twine-1.0.2-linux-x64.tar.gz` | Linux desktop, 64-bit |
| `Twine-1.0.2-android.apk` | Android |

To sign the APK with a release key, add repository secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, and `ANDROID_KEY_ALIAS`. Without those secrets the APK is signed with the debug key.

## Layout

| Path | What it is |
| --- | --- |
| `lib/main.dart` | Reads the saved account and starts the app. |
| `lib/session/` | Screens and sending actions. |
| `lib/market/` | The book, trade phases, and the thread. |
| `lib/nostr/` | Keys, NIP-44, and the relay client. |
| `lib/store/` | Keystore for the secret, the daemon, and the book. |
| `test/` | Widget and unit tests. No live relay. |
