/// Sends trade actions and folds the daemon's orders and replies into a book.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../constant.dart';
import '../market/book.dart';
import '../nostr/catalog.dart';
import '../nostr/envelope.dart';
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

  StreamSubscription<DaemonReplyEvent>? _replySub;
  StreamSubscription<TwineOrder>? _orderSub;
  StreamSubscription<OpenedCatalog>? _catalogSub;
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

  Future<String?> dispute(String tradeId, {String? invoice}) async {
    final error = await _send(
      disputeRequest(tradeId: tradeId, invoice: invoice),
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
    _replySub = null;
    _orderSub = null;
    _catalogSub = null;
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
    if (generation != _generation) return;
    ready = true;
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
    notifyListeners();
    unawaited(_persist());
  }

  void _onCatalog(OpenedCatalog catalog) {
    book.applyCatalog(catalog.methods, catalog.updatedAt);
    if (_stopped) return;
    notifyListeners();
    unawaited(_persist());
  }

  void _onOrder(TwineOrder order) {
    book.applyOrder(order);
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

  Future<String?> _send(TwineEnvelope envelope) async {
    if (!ready) return 'The book is still opening.';
    if (sending) return 'Wait for the current request to finish.';
    book.notice = null;
    status = null;
    sending = true;
    notifyListeners();
    try {
      await nostr.send(envelope);
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
