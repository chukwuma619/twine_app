import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/market/book.dart';
import 'package:twine_app/market/chat.dart';
import 'package:twine_app/market/phase.dart';
import 'package:twine_app/market/trade.dart';
import 'package:twine_app/nostr/order.dart';
import 'package:twine_app/nostr/twine_nostr.dart';
import 'package:twine_app/session/market.dart';
import 'package:twine_app/session/market_page.dart';
import 'package:twine_app/session/trade_page.dart';
import 'package:twine_app/store/book_store.dart';
import 'package:twine_app/ui/twine_tokens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reference row on the phone width', (tester) async {
    const reference = 'a6600d26-a8cd-4bf4-b748-71afb5c72d9e';
    for (final size in const [Size(402, 874), Size(320, 568)]) {
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        errors.add(details);
        previous?.call(details);
      };
      await _pumpTrade(
        tester,
        size: size,
        pubkey: 'buyer',
        phase: TradePhase.expired,
        sideSeller: 'seller',
        sideBuyer: 'buyer',
        reference: reference,
        notes: [
          TradeNote(
            id: 'status',
            tradeId: 'trade-1',
            at: DateTime.utc(2026, 10, 6, 4),
            kind: TradeNoteKind.status,
            text: 'The trade expired.',
          ),
        ],
      );
      FlutterError.onError = previous;
      expect(errors, isEmpty, reason: 'overflow at $size');
      final valueRect = tester.getRect(find.text(reference));
      final iconRect = tester.getRect(find.byIcon(Icons.copy));
      expect(valueRect.top, greaterThanOrEqualTo(iconRect.bottom - 1));
      expect(
        valueRect.left,
        closeTo(tester.getTopLeft(find.text('Reference')).dx, 1),
      );
      expect(valueRect.right, lessThan(size.width - TwineTokens.md + 1));
    }
  });

  testWidgets('settled outcome stays fully on screen', (tester) async {
    const size = Size(402, 874);
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      errors.add(details);
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);
    await _pumpTrade(
      tester,
      size: size,
      pubkey: 'seller',
      phase: TradePhase.settled,
      sideSeller: 'seller',
      sideBuyer: 'buyer',
      reference: '0466fba2-57c2-4881-930f-5f905af172a5',
      notes: const [],
    );
    expect(errors, isEmpty);
    const message =
        'The buyer received the CKB. Fiat was never held by this app.';
    final banner = tester.getRect(find.text(message));
    final summary = tester.getRect(find.byType(SingleChildScrollView).first);
    expect(banner.top, greaterThanOrEqualTo(summary.bottom - 1));
    expect(banner.height, greaterThan(32));
    expect(banner.bottom, lessThan(size.height));
    expect(find.text('No messages yet.'), findsNothing);
  });

  testWidgets('buyer chat on a short phone', (tester) async {
    await _pumpTrade(
      tester,
      size: const Size(320, 568),
      pubkey: 'buyer',
      phase: TradePhase.waitingFiat,
      sideSeller: 'seller',
      sideBuyer: 'buyer',
      notes: [
        TradeNote(
          id: 'long',
          tradeId: 'trade-1',
          at: DateTime.utc(2026, 10, 6, 3),
          kind: TradeNoteKind.text,
          author: 'seller',
          text: 'lnbc${'1' * 180}',
        ),
      ],
    );
  });

  testWidgets('seller lock screen on a short phone', (tester) async {
    await _pumpTrade(
      tester,
      size: const Size(320, 568),
      pubkey: 'seller',
      phase: TradePhase.waitingHold,
      sideSeller: 'seller',
      sideBuyer: 'buyer',
      holdInvoice: 'lnbc${'a' * 220}',
      notes: const [],
    );
  });

  testWidgets('keyboard covers the composer', (tester) async {
    await _pumpTrade(
      tester,
      size: const Size(390, 844),
      pubkey: 'buyer',
      phase: TradePhase.waitingFiat,
      sideSeller: 'seller',
      sideBuyer: 'buyer',
      insets: const EdgeInsets.only(bottom: 360),
      notes: [
        TradeNote(
          id: 'hello',
          tradeId: 'trade-1',
          at: DateTime.utc(2026, 10, 6, 2),
          kind: TradeNoteKind.text,
          author: 'buyer',
          text: 'On my way',
        ),
      ],
    );
    await tester.enterText(
      find.byType(TextField).last,
      'line\nline\nline\nline',
    );
    await tester.pump();
  });

  testWidgets('trades list with a long preview', (tester) async {
    final market = _market(pubkey: 'buyer');
    market.book.addNote(
      TradeNote(
        id: 'hello',
        tradeId: 'trade-1',
        at: DateTime.utc(2026, 10, 6, 2),
        kind: TradeNoteKind.text,
        author: 'seller',
        text: 'Paid yet? ${'no-break-' * 30}',
      ),
    );
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: TwineTokens.theme(),
        home: MarketPage(market: market, account: const SizedBox.shrink()),
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Trade'),
      ),
    );
    await tester.pumpAndSettle();
  });
}

Future<void> _pumpTrade(
  WidgetTester tester, {
  required Size size,
  required String pubkey,
  required TradePhase phase,
  required String sideSeller,
  required String sideBuyer,
  required List<TradeNote> notes,
  String? holdInvoice,
  String reference = 'REF-1234567890-ABCDEF',
  EdgeInsets insets = EdgeInsets.zero,
}) async {
  final market = _market(
    pubkey: pubkey,
    phase: phase,
    seller: sideSeller,
    buyer: sideBuyer,
    holdInvoice: holdInvoice,
    reference: reference,
  );
  for (final note in notes) {
    market.book.addNote(note);
  }
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: TwineTokens.theme(),
      home: MediaQuery(
        data: MediaQueryData(size: size, viewInsets: insets),
        child: TradePage(market: market, tradeId: 'trade-1'),
      ),
    ),
  );
  await tester.pump();
}

TwineMarket _market({
  String pubkey = 'buyer',
  TradePhase phase = TradePhase.waitingFiat,
  String seller = 'seller',
  String buyer = 'buyer',
  String? holdInvoice,
  String reference = 'REF-1234567890-ABCDEF',
}) {
  final order = TwineOrder(
    orderId: 'order-1',
    makerNostrPubkey: seller,
    makerFiberPubkey: 'fiber',
    availableCkb: '10',
    fiatCurrency: 'NGN',
    pricePerCkb: '1500',
    min: '1000',
    max: '5000',
    holdHours: 36,
    updatedAt: DateTime.utc(2026, 10, 6),
    status: PostStatus.open,
  );
  return TwineMarket(
    nostr: TwineNostr(),
    store: MemoryBookStore(),
    accountPubkey: pubkey,
    daemonPubkey: 'daemon',
    book: TwineBook(
      orders: [order],
      trades: [
        TwineTrade(
          id: 'trade-1',
          orderId: order.orderId,
          phase: phase,
          updatedAt: DateTime.utc(2026, 10, 6),
          amountShannons: '100000000',
          fiatAmount: '2500',
          fiatCurrency: 'NGN',
          reference: reference,
          holdInvoice: holdInvoice,
          sellerNostr: seller,
          buyerNostr: buyer,
          payBy: DateTime.now().toUtc().add(const Duration(hours: 2)),
          releaseBy: DateTime.now().toUtc().add(const Duration(hours: 3)),
          holdEndsAt: DateTime.now().toUtc().add(const Duration(hours: 20)),
        ),
      ],
    ),
  );
}
