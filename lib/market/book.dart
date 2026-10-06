/// The posts and trades this device has heard, folded forward.
library;

import '../nostr/envelope.dart';
import '../nostr/order.dart';
import '../nostr/reply.dart';
import 'phase.dart';
import 'trade.dart';

class TwineBook {
  TwineBook({
    List<TwineOrder>? orders,
    List<TwineTrade>? trades,
    this.fiberPubkey,
    this.notice,
  }) : orders = [...?orders],
       trades = [...?trades];

  final List<TwineOrder> orders;
  final List<TwineTrade> trades;
  String? fiberPubkey;
  String? notice;

  TwineOrder? order(String id) {
    for (final item in orders) {
      if (item.orderId == id) return item;
    }
    return null;
  }

  TwineTrade? trade(String id) {
    for (final item in trades) {
      if (item.id == id) return item;
    }
    return null;
  }

  TwineTrade? openTradeFor(String orderId) {
    for (final item in trades) {
      if (item.orderId == orderId && !item.phase.terminal) return item;
    }
    return null;
  }

  void applyOrder(TwineOrder incoming) {
    final index = orders.indexWhere((item) => item.orderId == incoming.orderId);
    if (index >= 0 && incoming.updatedAt.isBefore(orders[index].updatedAt)) {
      return;
    }
    if (index >= 0) {
      orders[index] = incoming;
    } else {
      orders.add(incoming);
    }
    orders.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  void applyReply(TwineEnvelope envelope, DateTime at) {
    final reply = DaemonReply.parse(envelope.action);
    if (reply == null) return;
    switch (reply) {
      case DaemonReply.payInvoice:
        _payInvoice(envelope, at);
      case DaemonReply.waitingFiat:
        _waitingFiat(envelope, at);
      case DaemonReply.fiatSentOk:
        _move(envelope, at, TradePhase.fiatSent);
      case DaemonReply.newInvoice:
        _newInvoice(envelope, at);
      case DaemonReply.disputed:
        _move(envelope, at, TradePhase.disputed);
      case DaemonReply.refunding:
        _move(envelope, at, TradePhase.refunding);
      case DaemonReply.settled:
        _move(envelope, at, TradePhase.settled);
      case DaemonReply.canceled:
        _canceled(envelope, at);
      case DaemonReply.expired:
        _move(envelope, at, TradePhase.expired);
      case DaemonReply.cantDo:
        _cantDo(envelope);
    }
  }

  /// Marks a release in progress. Returns an error when this phase cannot release.
  String? beginRelease(String tradeId) {
    final current = trade(tradeId);
    if (current == null) return 'That trade is not on this device yet.';
    if (current.phase == TradePhase.releasing) return null;
    if (!canEnter(current.phase, TradePhase.releasing)) {
      return 'The seller can release after the fiat is sent.';
    }
    _putTrade(
      current.copyWith(
        phase: TradePhase.releasing,
        releaseFrom: current.phase,
        keepNotice: false,
      ),
    );
    return null;
  }

  void revertRelease(String tradeId) {
    final current = trade(tradeId);
    final prior = current?.releaseFrom;
    if (current == null ||
        current.phase != TradePhase.releasing ||
        prior == null) {
      return;
    }
    _putTrade(current.copyWith(phase: prior, keepReleaseFrom: false));
  }

  void _payInvoice(TwineEnvelope envelope, DateTime at) {
    final pay = PayInvoice.tryParse(envelope.payload);
    if (pay == null) {
      notice = 'The daemon sent a hold invoice this app could not read.';
      return;
    }
    _move(envelope, at, TradePhase.waitingHold, pay: pay);
  }

  void _waitingFiat(TwineEnvelope envelope, DateTime at) {
    final fiat = WaitingFiat.tryParse(envelope.payload);
    if (fiat == null) {
      notice = 'The daemon sent a fiat step this app could not read.';
      return;
    }
    _move(envelope, at, TradePhase.waitingFiat, fiat: fiat);
  }

  void _newInvoice(TwineEnvelope envelope, DateTime at) {
    final reason =
        ReasonPayload.tryParse(envelope.payload)?.reason ??
        'The payout failed.';
    _move(envelope, at, TradePhase.awaitingInvoice, payoutFailure: reason);
  }

  void _canceled(TwineEnvelope envelope, DateTime at) {
    final tradeId = envelope.tradeId;
    if (tradeId == null || tradeId.isEmpty) {
      notice = 'Canceled.';
      return;
    }
    _move(envelope, at, TradePhase.canceled);
  }

  void _cantDo(TwineEnvelope envelope) {
    final reason =
        ReasonPayload.tryParse(envelope.payload)?.reason ??
        'The daemon refused that.';
    notice = reason;
    final tradeId = envelope.tradeId;
    if (tradeId == null || tradeId.isEmpty) return;
    final current = trade(tradeId);
    if (current == null) return;
    final prior = current.releaseFrom;
    _putTrade(
      current.copyWith(
        phase: prior ?? current.phase,
        notice: reason,
        keepReleaseFrom: false,
      ),
    );
  }

  void _move(
    TwineEnvelope envelope,
    DateTime at,
    TradePhase phase, {
    PayInvoice? pay,
    WaitingFiat? fiat,
    String? payoutFailure,
  }) {
    final tradeId = envelope.tradeId;
    if (tradeId == null || tradeId.isEmpty) {
      notice = 'The daemon reply was missing a trade.';
      return;
    }
    final current = trade(tradeId);
    final moving = canEnter(current?.phase, phase);
    if (current == null && !moving) return;
    final base =
        current ??
        TwineTrade(
          id: tradeId,
          orderId: pay?.orderId ?? '',
          phase: phase,
          updatedAt: at,
        );
    final clearFailure =
        moving &&
        payoutFailure == null &&
        (phase == TradePhase.settled ||
            phase == TradePhase.canceled ||
            phase == TradePhase.expired ||
            phase == TradePhase.refunding);
    _putTrade(
      TwineTrade(
        id: base.id,
        orderId: _keep(pay?.orderId, base.orderId),
        phase: moving ? phase : base.phase,
        updatedAt: _later(base.updatedAt, at),
        holdInvoice: pay?.invoice ?? base.holdInvoice,
        amountShannons: pay?.amountShannons ?? base.amountShannons,
        fiatAmount: fiat?.fiatAmount ?? base.fiatAmount,
        fiatCurrency: fiat?.fiatCurrency ?? base.fiatCurrency,
        paymentKind: fiat?.kind ?? base.paymentKind,
        paymentLabel: fiat?.label ?? base.paymentLabel,
        paymentCurrency: fiat?.currency ?? base.paymentCurrency,
        reference: fiat?.reference ?? base.reference,
        payoutFailure:
            payoutFailure ?? (clearFailure ? null : base.payoutFailure),
        notice: moving ? null : base.notice,
        releaseFrom: moving ? null : base.releaseFrom,
      ),
    );
  }

  void _putTrade(TwineTrade next) {
    final index = trades.indexWhere((item) => item.id == next.id);
    if (index >= 0) {
      trades[index] = next;
    } else {
      trades.add(next);
    }
    trades.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Map<String, Object?> toJson() {
    return {
      'fiber_pubkey': fiberPubkey,
      'notice': notice,
      'orders': [for (final item in orders) item.toJson()],
      'trades': [for (final item in trades) item.toJson()],
    };
  }

  static TwineBook? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = value.map((key, item) => MapEntry('$key', item));
    final orders = <TwineOrder>[];
    final trades = <TwineTrade>[];
    final rawOrders = map['orders'];
    final rawTrades = map['trades'];
    if (rawOrders is List) {
      for (final item in rawOrders) {
        final order = TwineOrder.fromJson(item);
        if (order != null) orders.add(order);
      }
    }
    if (rawTrades is List) {
      for (final item in rawTrades) {
        final trade = TwineTrade.fromJson(item);
        if (trade != null) trades.add(trade);
      }
    }
    final fiber = map['fiber_pubkey'];
    final notice = map['notice'];
    return TwineBook(
      orders: orders,
      trades: trades,
      fiberPubkey: fiber is String && fiber.trim().isNotEmpty
          ? fiber.trim()
          : null,
      notice: notice is String && notice.trim().isNotEmpty
          ? notice.trim()
          : null,
    );
  }
}

String _keep(String? incoming, String current) {
  if (incoming == null || incoming.isEmpty) return current;
  return incoming;
}

DateTime _later(DateTime current, DateTime at) {
  if (at.isAfter(current)) return at;
  return current;
}
