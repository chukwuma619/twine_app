import 'dart:async';
import 'dart:convert';

import 'package:dart_nostr/dart_nostr.dart';
import 'package:flutter/foundation.dart';

import '../constant.dart';
import '../market/book.dart';
import '../market/chat.dart';
import '../market/phase.dart';
import '../market/role.dart';
import '../nostr/catalog.dart';
import '../nostr/chat.dart';
import '../nostr/envelope.dart';
import '../nostr/nip44.dart';
import '../nostr/order.dart';
import '../nostr/reply.dart';
import '../nostr/request.dart';
import '../nostr/twine_nostr.dart';
import '../store/book_store.dart';

class TwineMarket extends ChangeNotifier {
  TwineMarket({
    required this.nostr,
    required this.store,
    required this.accountPubkey,
    required this.daemonPubkey,
    TwineBook? book,
  }) : book = book ?? TwineBook();

  final TwineNostr nostr;
  final BookStore store;
  final String accountPubkey;
  final String daemonPubkey;
  TwineBook book;

  bool ready = false;
  bool sending = false;
  bool awaitingPost = false;
  bool awaitingTake = false;
  String? status;

  /// Posts sent from this device, shown until the public order comes back.
  final List<TwineOrder> pending = [];

  StreamSubscription<DaemonReplyEvent>? _replySub;
  StreamSubscription<TwineOrder>? _orderSub;
  StreamSubscription<OpenedCatalog>? _catalogSub;
  StreamSubscription<NostrEvent>? _chatSub;
  Future<void>? _opening;
  int _generation = 0;
  Set<String> _ordersBeforePost = const {};
  Set<String> _tradesBeforeTake = const {};
  bool _stopped = false;

  String? get fiberPubkey => book.fiberPubkey;

  Future<void> open() {
    final pending = _opening;
    if (pending != null) return pending;
    final future = _open();
    _opening = future;
    return future;
  }

  Future<String?> post(NewOrderDraft draft) async {
    final invalid = draft.validate(book.catalog);
    if (invalid != null) return invalid;
    final before = {for (final order in book.orders) order.orderId};
    final error = await _send(draft.envelope());
    if (error != null) return error;
    book.fiberPubkey = draft.fiberPubkey.trim();
    _ordersBeforePost = before;
    pending.add(_pendingOrder(draft));
    awaitingPost = true;
    _clearAwaitingPost();
    notifyListeners();
    await _persist();
    return null;
  }

  Future<String?> take(TakeDraft draft) async {
    final invalid = draft.validate();
    if (invalid != null) return invalid;
    final order = book.order(draft.orderId);
    if (order != null &&
        order.makerNostrPubkey.toLowerCase() == accountPubkey.toLowerCase()) {
      return 'You cannot take your own post.';
    }
    final before = {for (final trade in book.trades) trade.id};
    final error = await _send(draft.envelope());
    if (error != null) return error;
    book.fiberPubkey = draft.fiberPubkey.trim();
    _tradesBeforeTake = before;
    awaitingTake = !book.trades.any((trade) => !before.contains(trade.id));
    notifyListeners();
    await _persist();
    return null;
  }

  Future<String?> fiatSent(String tradeId, String invoice) async {
    final invalid = invoiceError(invoice);
    if (invalid != null) return invalid;
    final error = await _send(
      fiatSentRequest(tradeId: tradeId, invoice: invoice),
    );
    if (error != null) return error;
    await _persist();
    return null;
  }

  Future<String?> release(String tradeId) async {
    final invalid = book.beginRelease(tradeId);
    if (invalid != null) return invalid;
    notifyListeners();
    final error = await _send(releaseRequest(tradeId));
    if (error != null) {
      book.revertRelease(tradeId);
      notifyListeners();
      await _persist();
      return error;
    }
    await _persist();
    return null;
  }

  Future<String?> sendChat(String tradeId, String text) async {
    final trade = book.trade(tradeId);
    if (trade == null) return 'That trade is not on this device yet.';
    if (trade.phase.terminal) return 'This trade is finished.';
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 'Write a message.';
    if (trimmed.length > maxChatText) return 'That message is too long.';
    return _sendChat(
      ChatBody(tradeId: tradeId, kind: TradeNoteKind.text, text: trimmed),
    );
  }

  Future<String?> shareAccount(
    String tradeId, {
    required String accountName,
    required String accountNumber,
    String? note,
  }) async {
    final trade = book.trade(tradeId);
    if (trade == null) return 'That trade is not on this device yet.';
    final order = trade.orderId.isEmpty ? null : book.order(trade.orderId);
    if (sideOn(trade, accountPubkey, order) != TradeSide.seller) {
      return 'The seller shares the account.';
    }
    if (trade.phase != TradePhase.waitingFiat) {
      return 'Share the account while the trade is waiting for fiat.';
    }
    if (book.paymentDetails(tradeId) != null) {
      return 'The account is already on this trade.';
    }
    final name = accountName.trim();
    final number = accountNumber.trim();
    final extra = note?.trim();
    if (name.isEmpty) return 'Enter the account name.';
    if (number.isEmpty) return 'Enter the account number.';
    if (name.length > 80 || number.length > 80) {
      return 'That account detail is too long.';
    }
    if (extra != null && extra.length > maxChatText) {
      return 'That note is too long.';
    }
    return _sendChat(
      ChatBody(
        tradeId: tradeId,
        kind: TradeNoteKind.paymentDetails,
        accountName: name,
        accountNumber: number,
        note: extra == null || extra.isEmpty ? null : extra,
      ),
    );
  }

  /// Posts the receipt, then marks the trade paid with the payout invoice.
  /// A receipt that is already on the thread is left there when the mark retries.
  Future<String?> markPaid(
    String tradeId, {
    required String invoice,
    required String bankReference,
    String? image,
  }) async {
    final trade = book.trade(tradeId);
    if (trade == null) return 'That trade is not on this device yet.';
    final order = trade.orderId.isEmpty ? null : book.order(trade.orderId);
    if (sideOn(trade, accountPubkey, order) != TradeSide.buyer) {
      return 'The buyer marks the fiat as sent.';
    }
    if (book.paymentDetails(tradeId) == null) {
      return 'Wait for the seller to share the account.';
    }
    if (book.paymentProof(tradeId) == null) {
      final reference = bankReference.trim();
      if (reference.isEmpty) return 'Enter the bank reference.';
      if (reference.length > 80) return 'That reference is too long.';
      final receipt = image?.trim();
      if (receipt == null || receipt.isEmpty) return 'Attach the receipt.';
      final List<int> raw;
      try {
        raw = base64Decode(receipt);
      } catch (_) {
        return 'That receipt could not be read.';
      }
      if (raw.length > maxReceiptBytes) {
        return 'Crop the receipt and try a smaller picture.';
      }
      final posted = await _sendChat(
        ChatBody(
          tradeId: tradeId,
          kind: TradeNoteKind.paymentProof,
          amount: trade.fiatAmount,
          bankReference: reference,
          image: receipt,
        ),
      );
      if (posted != null) return posted;
    }
    return fiatSent(tradeId, invoice);
  }

  Future<String?> dispute(String tradeId, {String? invoice}) async {
    final error = await _send(
      disputeRequest(
        tradeId: tradeId,
        invoice: invoice,
        conversationKey: _conversationKey(tradeId),
      ),
    );
    if (error != null) return error;
    await _persist();
    return null;
  }

  Future<String?> cancelOrder(String orderId) async {
    final error = await _send(cancelOrderRequest(orderId));
    if (error != null) return error;
    await _persist();
    return null;
  }

  Future<String?> cancelTrade(String tradeId) async {
    final error = await _send(cancelTradeRequest(tradeId));
    if (error != null) return error;
    await _persist();
    return null;
  }

  void stop() {
    _stopped = true;
    _generation++;
    _replySub?.cancel();
    _orderSub?.cancel();
    _catalogSub?.cancel();
    _chatSub?.cancel();
    _replySub = null;
    _orderSub = null;
    _catalogSub = null;
    _chatSub = null;
  }

  Future<void> _open() async {
    final generation = _generation;
    final saved = await store.read(accountPubkey, daemonPubkey);
    if (generation != _generation) return;
    if (saved != null) {
      book = saved;
    }
    _replySub = nostr.replies.listen(_onReply, onError: (_) {});
    _orderSub = nostr.orders.listen(_onOrder, onError: (_) {});
    _catalogSub = nostr.catalogs.listen(_onCatalog, onError: (_) {});
    _chatSub = nostr.chats.listen(_onChat, onError: (_) {});
    if (generation != _generation) return;
    ready = true;
    _watchChat();
    if (!_stopped) notifyListeners();
  }

  void _onReply(DaemonReplyEvent event) {
    book.applyReply(event.envelope, event.createdAt);
    if (event.envelope.action == replyCantDo) {
      awaitingPost = false;
      awaitingTake = false;
      status = null;
    }
    if (event.envelope.action == replyPayInvoice) _clearAwaitingTake();
    _watchChat();
    notifyListeners();
    unawaited(_persist());
  }

  void _onChat(NostrEvent event) {
    final signer = nostr.account;
    final id = event.id;
    final at = event.createdAt;
    if (signer == null || id == null || at == null) return;
    final body = openChat(
      recipient: signer,
      senderPublicKey: event.pubkey,
      event: event,
    );
    if (body == null) return;
    final trade = book.trade(body.tradeId);
    if (trade == null) return;
    final peer = counterparty(trade, accountPubkey);
    if (peer == null || peer.toLowerCase() != event.pubkey.toLowerCase()) {
      return;
    }
    book.addNote(body.noteFor(id: id, author: event.pubkey, at: at));
    if (_stopped) return;
    notifyListeners();
    unawaited(_persist());
  }

  void _watchChat() {
    final authors = <String>{};
    final trades = <String>[];
    for (final trade in book.trades) {
      final peer = counterparty(trade, accountPubkey);
      if (peer == null) continue;
      authors.add(peer);
      trades.add(trade.id);
    }
    nostr.watchTradeChat(
      accountPubkey: accountPubkey,
      authors: authors.toList(),
      tradeIds: trades,
    );
  }

  String? _conversationKey(String tradeId) {
    final trade = book.trade(tradeId);
    final signer = nostr.account;
    if (trade == null || signer == null) return null;
    final peer = counterparty(trade, accountPubkey);
    if (peer == null) return null;
    try {
      return nip44ConversationKeyHex(signer.privateKey, peer);
    } on Nip44Exception {
      return null;
    }
  }

  Future<String?> _sendChat(ChatBody body) async {
    final signer = nostr.account;
    final trade = book.trade(body.tradeId);
    final peer = trade == null ? null : counterparty(trade, accountPubkey);
    if (signer == null || peer == null) {
      return 'The other person is not on this trade yet.';
    }
    if (!ready) return 'The book is still opening.';
    if (sending) return 'Wait for the current request to finish.';
    sending = true;
    notifyListeners();
    try {
      final event = sealChat(sender: signer, peer: peer, body: body);
      final id = event.id;
      final at = event.createdAt;
      if (id == null || at == null) {
        sending = false;
        if (!_stopped) notifyListeners();
        return 'Could not sign the message.';
      }
      await nostr.publish(event);
      book.addNote(body.noteFor(id: id, author: signer.publicKey, at: at));
      sending = false;
      if (!_stopped) notifyListeners();
      await _persist();
      return null;
    } on TwineRelayException catch (error) {
      sending = false;
      if (!_stopped) notifyListeners();
      return error.message;
    } on Nip44Exception {
      sending = false;
      if (!_stopped) notifyListeners();
      return 'Could not encrypt the message.';
    } catch (_) {
      sending = false;
      if (!_stopped) notifyListeners();
      return 'Could not reach the relays.';
    }
  }

  void _onCatalog(OpenedCatalog catalog) {
    book.applyCatalog(catalog.methods, catalog.updatedAt);
    if (_stopped) return;
    notifyListeners();
    unawaited(_persist());
  }

  void _onOrder(TwineOrder order) {
    final known = book.order(order.orderId) != null;
    book.applyOrder(order);
    if (!known &&
        order.makerNostrPubkey.toLowerCase() == accountPubkey.toLowerCase()) {
      pending.removeWhere((item) => item.side == order.side);
    }
    _clearAwaitingPost();
    notifyListeners();
    unawaited(_persist());
  }

  void _clearAwaitingPost() {
    if (!awaitingPost) return;
    for (final order in book.orders) {
      if (order.makerNostrPubkey.toLowerCase() == accountPubkey.toLowerCase() &&
          !_ordersBeforePost.contains(order.orderId)) {
        awaitingPost = false;
        status = 'Your post is on the book.';
        return;
      }
    }
  }

  void _clearAwaitingTake() {
    if (!awaitingTake) return;
    for (final trade in book.trades) {
      if (!_tradesBeforeTake.contains(trade.id)) {
        awaitingTake = false;
        status = 'The hold invoice is in Trades.';
        return;
      }
    }
  }

  TwineOrder _pendingOrder(NewOrderDraft draft) {
    final methods = <TwinePaymentMethod>[];
    for (final id in draft.methodIds) {
      for (final method in book.catalog) {
        if (method.id != id) continue;
        methods.add(
          TwinePaymentMethod(
            id: method.id,
            kind: method.kind,
            label: method.label,
            currency: method.currency,
          ),
        );
      }
    }
    return TwineOrder(
      orderId: 'local-${pending.length}-${draft.side.wire}',
      side: draft.side,
      makerNostrPubkey: accountPubkey,
      makerFiberPubkey: draft.fiberPubkey.trim(),
      availableCkb: draft.availableCkb.trim(),
      fiatCurrency: draft.fiatCurrency.trim(),
      pricePerCkb: draft.pricePerCkb.trim(),
      min: draft.min.trim(),
      max: draft.max.trim(),
      paymentMethods: methods,
      holdHours: 36,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  void _refreshOrders() {
    try {
      nostr.replayOrders();
    } catch (_) {}
  }

  Future<String?> _send(TwineEnvelope envelope) async {
    if (!ready) return 'The book is still opening.';
    if (sending) return 'Wait for the current request to finish.';
    book.notice = null;
    status = null;
    sending = true;
    notifyListeners();
    try {
      await nostr.send(envelope);
      _refreshOrders();
      sending = false;
      if (!_stopped) notifyListeners();
      return null;
    } on TwineRelayException catch (error) {
      sending = false;
      if (!_stopped) notifyListeners();
      return error.message;
    } on StateError {
      sending = false;
      if (!_stopped) notifyListeners();
      return 'Sign in and choose a daemon first.';
    } catch (_) {
      sending = false;
      if (!_stopped) notifyListeners();
      return 'Could not reach the relays.';
    }
  }

  Future<void> _persist() async {
    try {
      await store.write(accountPubkey, daemonPubkey, book);
    } catch (_) {
      book.notice ??= 'Could not save this book on the device.';
      if (!_stopped) notifyListeners();
    }
  }
}
