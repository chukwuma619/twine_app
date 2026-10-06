/// The posts and trades this device has heard, folded forward.
library;

import '../nostr/catalog.dart';
import '../nostr/envelope.dart';
import '../nostr/order.dart';
import '../nostr/reply.dart';
import 'chat.dart';
import 'phase.dart';
import 'trade.dart';

class TwineBook {
  TwineBook({
    List<TwineOrder>? orders,
    List<TwineTrade>? trades,
    List<TradeNote>? notes,
    List<CatalogMethod>? catalog,
    this.catalogUpdatedAt,
    this.fiberPubkey,
    this.notice,
  }) : orders = [...?orders],
       trades = [...?trades],
       notes = [...?notes],
       catalog = [...?catalog];

  final List<TwineOrder> orders;
  final List<TwineTrade> trades;
  final List<TradeNote> notes;
  List<CatalogMethod> catalog;
  DateTime? catalogUpdatedAt;
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

  List<TradeNote> thread(String tradeId) {
    final lines = notes.where((item) => item.tradeId == tradeId).toList();
    lines.sort((a, b) => a.at.compareTo(b.at));
    return lines;
  }

  TradeNote? paymentDetails(String tradeId) {
    for (final item in thread(tradeId).reversed) {
      if (item.kind == TradeNoteKind.paymentDetails) return item;
    }
    return null;
  }

  TradeNote? paymentProof(String tradeId) {
    for (final item in thread(tradeId).reversed) {
      if (item.kind == TradeNoteKind.paymentProof) return item;
    }
    return null;
  }

  void addNote(TradeNote note) {
    if (notes.any((item) => item.id == note.id)) return;
    notes.add(note);
    notes.sort((a, b) => a.at.compareTo(b.at));
  }

  TwineTrade? openTradeFor(String orderId) {
    for (final item in trades) {
      if (item.orderId == orderId && !item.phase.terminal) return item;
    }
    return null;
  }

  void applyOrder(TwineOrder incoming) {
    final index = orders.indexWhere((item) => item.orderId == incoming.orderId);
    if (index >= 0) {
      final current = orders[index];
      if (incoming.updatedAt.isBefore(current.updatedAt)) return;
      if (current.status == PostStatus.canceled &&
          incoming.status == PostStatus.open &&
          !incoming.updatedAt.isAfter(current.updatedAt)) {
        return;
      }
      orders[index] = incoming;
    } else {
      orders.add(incoming);
    }
    orders.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  void applyCatalog(List<CatalogMethod> methods, DateTime at) {
    final current = catalogUpdatedAt;
    if (current != null && at.isBefore(current)) return;
    catalog = [...methods];
    catalogUpdatedAt = at;
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
    if (tradeId != null && tradeId.isNotEmpty) {
      _move(envelope, at, TradePhase.canceled);
      return;
    }
    final orderId = _orderId(envelope.payload);
    if (orderId == null) {
      notice = 'Canceled.';
      return;
    }
    final index = orders.indexWhere((item) => item.orderId == orderId);
    if (index < 0) {
      notice = 'Canceled.';
      return;
    }
    orders[index] = orders[index].copyWith(status: PostStatus.canceled);
    notice = null;
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
        sellerNostr: pay?.sellerNostr ?? fiat?.sellerNostr ?? base.sellerNostr,
        buyerNostr: pay?.buyerNostr ?? fiat?.buyerNostr ?? base.buyerNostr,
        payoutFailure:
            payoutFailure ?? (clearFailure ? null : base.payoutFailure),
        notice: moving ? null : base.notice,
        releaseFrom: moving ? null : base.releaseFrom,
      ),
    );
    if (!moving) return;
    final line = statusLine(phase);
    if (line == null) return;
    addNote(
      TradeNote(
        id: 'status:$tradeId:${phase.wire}',
        tradeId: tradeId,
        at: at,
        kind: TradeNoteKind.status,
        text: line,
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
      'catalog': [for (final method in catalog) method.toJson()],
      'catalog_updated_at': catalogUpdatedAt?.toIso8601String(),
      'orders': [for (final item in orders) item.toJson()],
      'trades': [for (final item in trades) item.toJson()],
      'notes': [for (final item in notes) item.toJson()],
    };
  }

  static TwineBook? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = value.map((key, item) => MapEntry('$key', item));
    final orders = <TwineOrder>[];
    final trades = <TwineTrade>[];
    final notes = <TradeNote>[];
    final rawOrders = map['orders'];
    final rawTrades = map['trades'];
    final rawNotes = map['notes'];
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
    if (rawNotes is List) {
      for (final item in rawNotes) {
        final note = TradeNote.fromJson(item);
        if (note != null) notes.add(note);
      }
    }
    final fiber = map['fiber_pubkey'];
    final notice = map['notice'];
    final catalogAt = DateTime.tryParse(
      map['catalog_updated_at'] is String
          ? map['catalog_updated_at'] as String
          : '',
    );
    return TwineBook(
      orders: orders,
      trades: trades,
      notes: notes,
      catalog: _catalog(map['catalog']),
      catalogUpdatedAt: catalogAt,
      fiberPubkey: fiber is String && fiber.trim().isNotEmpty
          ? fiber.trim()
          : null,
      notice: notice is String && notice.trim().isNotEmpty
          ? notice.trim()
          : null,
    );
  }
}

List<CatalogMethod> _catalog(Object? value) {
  if (value is! List) return const [];
  final methods = <CatalogMethod>[];
  for (final item in value) {
    final method = CatalogMethod.tryParse(item);
    if (method == null) return const [];
    methods.add(method);
  }
  return methods;
}

String? _orderId(Object? payload) {
  if (payload is! Map) return null;
  final id = payload['order_id'];
  if (id is! String || id.trim().isEmpty) return null;
  return id.trim();
}

String _keep(String? incoming, String current) {
  if (incoming == null || incoming.isEmpty) return current;
  return incoming;
}

DateTime _later(DateTime current, DateTime at) {
  if (at.isAfter(current)) return at;
  return current;
}
