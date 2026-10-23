# Twine

Twine is an app for buying and selling CKB person to person. Fiat moves outside the app. CKB stays in your Fiber wallet.

This repository is the Flutter client. It talks to one [Twine daemon](https://github.com/chukwuma619/twine) over Nostr. It never holds a Fiber key, never pays an invoice, and never settles a hold. You pay and receive on your own Fiber node. The daemon coordinates the trade and publishes the book.

There is no fee, no rating, and no bond. Two traders chat here. The daemon does not read that thread.

## How a trade works

A post offers CKB. The poster is the seller. The taker is the buyer. There is no buy post, and there is no automatic matching: you pick a post.

To buy CKB:

1. Create a Nostr key. That key is your account. There is no username.
2. Connect to a daemon. Connect your Fiber node outbound to that operator's hub.
3. Browse posts. Each one is someone selling CKB at a price, with fiat limits and payment methods.
4. Take a post. Enter the fiat amount, your Fiber pubkey, a payment method, and a Fiber invoice that should receive the CKB.
5. Wait for the seller to lock. They pay a hold invoice in their own Fiber wallet. The app does not pay it.
6. The seller shares their account in chat. You send fiat outside Twine, then mark it sent.
7. The seller checks the credit and releases. The daemon pays your invoice. The trade is done.

To sell, post instead of taking, then lock the hold, wait for fiat, and release.

If the buyer does not pay in time, or the hold runs out, Fiber refunds the seller. Fiat never enters this app.

## What you need

- A Twine daemon, and the relays it uses. A new install offers one daemon. Replace it before connecting if you run your own. The daemon logs the `npub` people paste here.
- A Fiber wallet on your own node. Account shows the operator's Fiber pubkey and listen address so you can connect to that hub. A laptop node does not need a public IP: connect outbound. Sellers then fund a channel for outbound liquidity. Buyers stay online with auto-accept on; Twine opens inbound to them at payout if they cannot receive yet.
- Flutter, with the Dart SDK named in `pubspec.yaml`.

## Run

```bash
flutter pub get
flutter run
```

`flutter run` picks a connected phone, simulator, or desktop. Pass `-d` to choose one. Photo library access is declared on iOS and macOS so a buyer can attach a receipt. Android backup of app data is off.

```bash
flutter test
```

## Tester builds

macOS, Windows, Linux, and Android builds are published as a GitHub Release.

From a clean checkout of the commit testers should get, publish the next version with:

```bash
tool/release.sh 1.0.2
```

That sets `version:` in `pubspec.yaml`, commits it, tags `v1.0.2`, and pushes. GitHub Actions builds four files and attaches them to that release, with first-launch notes on the release page:

| File | Testers |
| --- | --- |
| `Twine-1.0.2-macos.dmg` | macOS 12 or newer |
| `Twine-1.0.2-windows-x64.zip` | Windows 10 or 11, 64-bit |
| `Twine-1.0.2-linux-x64.tar.gz` | Linux desktop, 64-bit |
| `Twine-1.0.2-android.apk` | Android |

To sign the APK with the same key as a local release, add repository secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, and `ANDROID_KEY_ALIAS`. The keystore secret is the base64 of the `.jks` file. Without those secrets, the APK is signed with the debug key, and it will not install over a release-signed copy.

The workflow is pinned to Flutter 3.41.6, the same revision as this project. Bump that pin in `.github/workflows/release.yml` when Flutter is upgraded here.

To try the workflow before a real version, run **Release** from the Actions tab. That publishes a prerelease from the selected branch.

## First launch

1. **Create a key**, or **import** an `nsec`. A 64-character hex secret is also accepted. An `npub` is rejected. The Nostr pubkey is the account.

2. **Save the secret.** A new key is shown once as an `nsec` before anything else. Twine does not keep another copy. The same secret can be shown again later from Account.

3. **Connect to a daemon.** The form is filled with the official daemon. Replace the public key (`npub` or 64-character hex) and the relay list to use another one. An `nsec` is rejected. Relays are `ws://` or `wss://` URLs, separated by commas, spaces, or newlines.

The official daemon offered by a new install:

| | |
| --- | --- |
| Public key | `npub18wyh0ympmw9gfu7dfu6eqyqef449smmg74k5p5m79zunx8wusttqzpnmc8` |
| Relays | `wss://relay.damus.io`, `wss://nos.lol` |

After that the app opens those relays and loads the book for this account and this daemon.

The status line says when relays are still connecting, when none connected, or when the Fiber node announcement has not arrived yet. Account lists the relays that actually connected when that set differs from the ones you entered.

## Posts

The bottom bar is **Posts**, **Trade**, and **Account**.

Posts is one list: other people selling CKB, and your own posts. **Take** buys from someone else's post. **Cancel post** takes yours down. You cannot take your own post. A post with no CKB left cannot be taken.

A card shows the price per CKB, the CKB still available, the fiat limits, the payment methods, and the hold length. **Yours** marks your post. **Canceled** marks a post the poster took down. **Fully taken** means no CKB is left.

**New post** asks for your Fiber pubkey, how much CKB is for sale, a currency from the daemon's catalog, a price per CKB, fiat min and max, and one or more payment methods. The post button stays off until that catalog arrives and until you confirm the Fiber channel is ready. The Fiber pubkey is remembered after the first post or take.

The post shows on the book immediately, marked as yours, until the daemon's public order comes back. You cannot cancel that local copy. Once the public order is on the book, **Cancel post** removes it.

**Take** asks for a fiat amount, your Fiber pubkey, one payment method from the post, and a Fiber invoice that should receive the CKB. You can add a **public** Fiber listen multiaddr. A local `127.0.0.1` address is refused; connect that node outbound to the hub instead. The app then waits for the hold invoice and tells you to look in Trades.

## A trade

Open a trade from the post's **Trade** button, or from the **Trade** tab. The screen follows the phase. The daemon decides whether an action is allowed. The app sends it, then folds the reply into the trade it has already heard.

| Screen | Who | What you do |
| --- | --- | --- |
| Lock the CKB | Seller | Pay the hold invoice in your Fiber wallet. The invoice is on the trade. The app does not pay it. |
| Share your account | Seller | Send the account name, account number, and an optional note for the method the daemon named. |
| Pay the seller | Buyer | Wait for that account, send fiat outside Twine, then mark it sent. |
| Check the payment | Seller | Release after the credit is in your account. Release asks you to confirm. The receipt is the buyer's claim. |
| Send a new invoice | Buyer | The payout failed. Submit another Fiber invoice. |
| Disputed | Either party | The hold stays locked until the solver decides. The seller can still release when a payout invoice is already stored. |
| Sending the CKB | Both | The daemon is paying the buyer, then settling the hold. |
| Settled, canceled, or expired | Both | The trade is finished. The composer closes. |

**Cancel trade** is only offered while the hold is still unpaid. Either party can send it. After the hold locks, cancel is gone and the coins wait for release or for Fiber's timelock.

**Dispute** is offered while the trade is waiting for fiat, after fiat is sent, or while a new invoice is needed. Confirming it tells you the solver can read this chat. The app sends the shared conversation key with the dispute so the solver can decrypt the thread. The daemon still cannot. This app has no solver screen. Resolving a dispute is a daemon action from the solver's key.

The buyer marks fiat as sent from **I've paid**:

1. Enter the bank reference and attach a receipt photo, unless a receipt is already on the thread.
2. Paste the Fiber invoice that should receive the CKB.
3. The app posts the receipt on the thread, then sends `fiat-sent` with that invoice.

If the receipt is already posted and the mark is retried, the receipt stays and only the invoice is sent again. A later payout failure asks for a new invoice without a new receipt.

Amounts the daemon sends as shannons are shown in CKB. `1` CKB is `100000000` shannons.

## Chat

The thread is on the trade, encrypted to the other trader, once the daemon has named both Nostr keys. Until then the app says it is still waiting to learn who the other person is.

You can send a text (up to 1000 characters), payment details (the seller's account), or a payment proof (the buyer's amount, bank reference, and receipt). The app also adds a local status line when the daemon moves the trade. That line is not published.

A receipt is chosen from the photo library, scaled down, and has to fit in one relay event. The limit is 48000 bytes after that. A picture that is still too large asks you to crop it.

The app only accepts a thread message signed by the counterparty on that trade and tagged with that trade id.

## Account

Account shows your `npub`, the daemon `npub`, the relay list, and the operator's Fiber pubkey and listen address once the announcement arrives. Connect your node to that hub, then open and fund a channel before you sell. To buy, keep that outbound connection up with auto-accept on and about 99 CKB on-chain so Twine can open inbound at payout.

**Change daemon** replaces the public key and relays. The book is kept per account and per daemon, so the other daemon has its own book.

**Show secret** displays the `nsec` again.

**Log out** removes the Nostr secret from this device. It does not remove the daemon you chose, and it does not delete the saved book. Importing the same secret on this device brings that book back. Logging out does not delete the key from Nostr, and it does not cancel posts or trades. Keep the `nsec` if you still need the account.

## What stays on the device

The secret, the daemon, and the book are kept in the platform keystore: Keychain on Apple platforms, Keystore-backed storage on Android. On macOS the app uses the file-based keychain rather than the data-protection keychain, so a debug build can save without that entitlement.

Nothing in this store is the Fiber seed. The Fiber pubkey you type is only the public key of your node. If the keystore cannot be read at startup, the app stops on "Could not read the saved account."

## Nostr

Actions are encrypted to the daemon and signed with your key. Replies are encrypted to you and must be signed by the daemon you chose. Orders, the Fiber node pubkey, and the payment catalog are public events from that daemon. These kinds are application constants, not NIPs.

| Kind | What the app does with it |
| --- | --- |
| `4242` | Sends an action. Subscribes to replies authored by the daemon and tagged to this account. |
| `31420` | Reads public orders. The `d` tag is the order id. |
| `31421` | Reads the Fiber node announcement. The `d` tag is `fiber-node`. |
| `31422` | Reads the payment catalog. The `d` tag is `payment-methods`. |
| `4243` | Sends and reads the trade thread. The daemon does not subscribe to this kind. |

The actions this app sends are `new-order`, `take`, `fiat-sent`, `release`, `cancel`, and `dispute`. Field names, who may send each action, and the clock (hold length, payment window, refund) are defined by the daemon.

## Layout

| Path | What it is |
| --- | --- |
| `lib/main.dart` | Reads the saved account and daemon, then starts the app. |
| `lib/constant.dart` | Event kinds and action names shared with the daemon. |
| `lib/session/` | Screens, the signed-in session, and sending actions. |
| `lib/market/` | The book, trade phases, who may press which button, and the thread. |
| `lib/nostr/` | Keys, NIP-44, sealing actions and chat, and the relay client. |
| `lib/store/` | Keystore reads and writes for the secret, the daemon, and the book. |
| `test/` | Book, order, chat, catalog, key, and screen tests. No live relay. |
