# Twine

Twine is the client for a peer-to-peer CKB market settled on [Fiber](https://github.com/nervosnetwork/fiber). Fiat moves outside the app. The seller's coins sit in a Fiber hold invoice until the seller releases them, or until that hold expires and Fiber refunds the seller.

This repository is the Flutter app. It talks to one [Twine daemon](https://github.com/chukwuma619/twine) over Nostr. It never holds a Fiber key, never pays an invoice, and never settles a hold. Each trader pays and receives on their own Fiber node. The daemon coordinates the trade and publishes the book.

The app does not charge a fee, keep ratings, or take a bond. Two traders chat here. The daemon does not read that thread.

## What you need

- A Twine daemon, and the relays it uses. A new install offers one daemon. Replace it before connecting if you run your own. The daemon logs the `npub` people paste here.
- A Fiber wallet on your own node. The app shows the operator's Fiber pubkey so you can open a channel to it, and it shows hold invoices for you to pay in that wallet.
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

## First launch

1. **Create a key**, or **import** an `nsec`. A 64-character hex secret is also accepted. An `npub` is rejected. The Nostr pubkey is the account. There is no username.

2. **Save the secret.** A new key is shown once as an `nsec` before anything else. Twine does not keep another copy. The same secret can be shown again later from Account.

3. **Connect to a daemon.** The form is filled with the official daemon. Replace the public key (`npub` or 64-character hex) and the relay list to use another one. An `nsec` is rejected. Relays are `ws://` or `wss://` URLs, separated by commas, spaces, or newlines.

The official daemon offered by a new install:

| | |
| --- | --- |
| Public key | `npub18wyh0ympmw9gfu7dfu6eqyqef449smmg74k5p5m79zunx8wusttqzpnmc8` |
| Relays | `wss://relay.damus.io`, `wss://nos.lol` |

After that the app opens those relays, subscribes to this daemon's replies, orders, Fiber node announcement, and payment catalog, and loads the book saved for this account and this daemon.

The status line says when relays are still connecting, when none connected, or when the Fiber node announcement has not arrived yet. Account lists the relays that actually connected when that set differs from the ones you entered.

## The book

The bottom bar is **Post**, **Trade**, and **Account**.

**Post** has two sides:

| Side | What it lists |
| --- | --- |
| Buy | Other people selling CKB, and your own buy posts. |
| Sell | Other people buying CKB, and your own sell posts. |

Your own post stays on the side you posted. Someone else's sell is an offer you can buy. Someone else's buy is a bid you can sell into.

A card shows the price per CKB, the CKB still available, the fiat limits, the payment methods, and the hold length. **Yours** marks your post. **Canceled** marks a post the poster took down. A post with no CKB left cannot be taken.

**New post** asks for:

| Field | Meaning |
| --- | --- |
| Sell CKB or Buy CKB | Who is offering the coins. |
| Your Fiber pubkey | Your node's pubkey. Remembered after the first post or take and filled in next time. |
| CKB available | Size of the post. |
| Currency | From the daemon's payment catalog. The post button stays off until that catalog arrives. |
| Price per CKB | Fiat price. |
| Minimum and maximum | Fiat limits for one take. The minimum cannot be above the maximum. |
| Payment methods | One or more methods in the chosen currency. |

The post shows on the book immediately, marked as yours, until the daemon's public order comes back. You cannot cancel that local copy. Once the public order is on the book, **Cancel post** removes it. You cannot take your own post.

**Take** asks for a fiat amount, your Fiber pubkey, and one payment method from the post. The app then waits for the hold invoice and tells you to look in Trades.

## A trade

The daemon decides whether an action is allowed and what state comes next. The app sends the action, then folds the reply into the trade it has already heard. An older reply cannot walk a finished trade backwards.

Open a trade from the post's **Trade** button, or from the **Trade** tab. The screen follows the phase:

| What you see | Who | What you do |
| --- | --- | --- |
| Waiting for the hold | Seller | Pay the hold invoice in your Fiber wallet. The invoice is on the trade. The app does not pay it. |
| Waiting for fiat | Seller | Share the account name, account number, and an optional note for the method the daemon named. |
| Waiting for fiat | Buyer | Wait for that account, then mark the fiat as sent. |
| Fiat sent | Seller | Release after the credit is in your account. Release asks you to confirm. The receipt is the buyer's claim. |
| Needs a new invoice | Buyer | The payout failed. Submit another Fiber invoice. |
| Disputed | Either party | The hold stays locked until the solver decides. The seller can still release when a payout invoice is already stored. |
| Releasing | Both | The daemon is paying the buyer, then settling the hold. |
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

| Kind | What it is |
| --- | --- |
| Text | A message, up to 1000 characters. |
| Payment details | The seller's account name, number, and optional note. |
| Payment proof | The buyer's amount, bank reference, and receipt image. |
| Status | A line the app adds when the daemon moves the trade, such as the hold locking or the trade settling. |

A receipt is chosen from the photo library, scaled down, and has to fit in one relay event. The limit is 48000 bytes after that. A picture that is still too large asks you to crop it.

Chat events are kind `4243`. The `p` tag is the other trader. The `t` tag is the trade id. The content is NIP-44 version 2, the same construction the daemon uses for actions. The plaintext is JSON:

```json
{
  "v": 1,
  "trade_id": "<trade id>",
  "type": "text",
  "text": "hello"
}
```

`type` is `text`, `payment-details`, or `payment-proof`. Unused fields are null. A status line is local. It is not published.

The app only accepts a thread message signed by the counterparty on that trade and tagged with that trade id.

## Account

Account shows your `npub`, the daemon `npub`, the relay list, and the operator's Fiber pubkey once the announcement arrives. Open a channel to that pubkey in your Fiber wallet before you need to pay a hold.

**Change daemon** replaces the public key and relays. The book is kept per account and per daemon, so the other daemon has its own book.

**Show secret** displays the `nsec` again.

**Log out** removes the Nostr secret from this device. It does not remove the daemon you chose, and it does not delete the saved book. Importing the same secret on this device brings that book back. Logging out does not delete the key from Nostr, and it does not cancel posts or trades. Keep the `nsec` if you still need the account.

## What stays on the device

The secret, the daemon, and the book are kept in the platform keystore: Keychain on Apple platforms, Keystore-backed storage on Android. On macOS the app uses the file-based keychain rather than the data-protection keychain, so a debug build can save without that entitlement.

| Stored value | Key |
| --- | --- |
| Nostr secret, hex | `twine_nostr_secret` |
| Daemon public key and relays | `twine_daemon` |
| Book for one account and one daemon | `twine_book_<account pubkey>_<daemon pubkey>` |

The book is the orders, trades, thread, payment catalog, your last Fiber pubkey, and the last notice from the daemon. A value that does not parse is deleted. A secret that is not a key is deleted. If the keystore cannot be read at startup, the app stops on "Could not read the saved account."

Nothing in this store is the Fiber seed. The Fiber pubkey you type is only the public key of your node.

## Nostr

Actions are encrypted to the daemon and signed with your key. Replies are encrypted to you and must be signed by the daemon you chose. Orders, the Fiber node pubkey, and the payment catalog are public events from that daemon. These kinds are application constants, not NIPs.

| Kind | What the app does with it |
| --- | --- |
| `4242` | Sends an action. Subscribes to replies authored by the daemon and tagged to this account. |
| `31420` | Reads public orders. The `d` tag is the order id. |
| `31421` | Reads the Fiber node announcement. The `d` tag is `fiber-node`. |
| `31422` | Reads the payment catalog. The `d` tag is `payment-methods`. |
| `4243` | Sends and reads the trade thread. The daemon does not subscribe to this kind. |

One connected relay is enough to publish. The app keeps the order subscription open and asks the relays again after you send an action, and again when a relay socket is replaced. A reconnect does not replay the previous subscription on its own, so an order published into that gap would otherwise never reach the book.

The envelope inside kind `4242` is `{ "action", "trade_id"?, "payload"? }`. The actions this app sends are `new-order`, `take`, `fiat-sent`, `release`, `cancel`, and `dispute`. The replies it applies are `pay-invoice`, `waiting-fiat`, `fiat-sent-ok`, `new-invoice`, `disputed`, `refunding`, `settled`, `canceled`, `expired`, and `cant-do`. Field names, who may send each action, and the clock (hold length, payment window, refund) are defined by the daemon.

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
