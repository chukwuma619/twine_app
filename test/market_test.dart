import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/market/book.dart';
import 'package:twine_app/market/phase.dart';
import 'package:twine_app/market/role.dart';
import 'package:twine_app/market/trade.dart';
import 'package:twine_app/nostr/catalog.dart';
import 'package:twine_app/nostr/envelope.dart';
import 'package:twine_app/nostr/order.dart';
import 'package:twine_app/nostr/request.dart';
import 'package:twine_app/nostr/twine_nostr.dart';
import 'package:twine_app/session/market.dart';
import 'package:twine_app/session/market_page.dart';
import 'package:twine_app/session/post_page.dart';
import 'package:twine_app/session/take_page.dart';
import 'package:twine_app/session/trade_page.dart';
import 'package:twine_app/store/book_store.dart';

void main() {
  test('the seller pays the hold and the buyer sends fiat', () {
    final seller = TradeActions.of(
      phase: TradePhase.waitingHold,
      side: TradeSide.seller,
      hasHoldInvoice: true,
    );
    expect(seller.payHold, isTrue);
    expect(seller.sendFiat, isFalse);

    final buyer = TradeActions.of(
      phase: TradePhase.waitingFiat,
      side: TradeSide.buyer,
      hasHoldInvoice: true,
    );
    expect(buyer.sendFiat, isTrue);
    expect(buyer.payHold, isFalse);
    expect(buyer.dispute, isTrue);
  });

  testWidgets('the book shows a post to take and hides taking your own', (
    tester,
  ) async {
    final market = _market(
      pubkey: 'taker',
      orders: [
        _order(maker: 'maker'),
        _order(id: 'mine', maker: 'taker'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MarketPage(
          market: market,
          account: const SizedBox.shrink(),
          fiberNode: '02abc',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Take'), findsOneWidget);
    expect(find.text('Yours'), findsNothing);

    await tester.tap(find.text('Sell'));
    await tester.pumpAndSettle();

    expect(find.text('Yours'), findsOneWidget);
    expect(find.text('Cancel post'), findsOneWidget);
    expect(find.text('Take'), findsNothing);

    await tester.tap(find.text('Buy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take'));
    await tester.pumpAndSettle();
    expect(find.text('Buy CKB'), findsWidgets);
    expect(
      find.text('You pay by mobile transfer after the seller locks.'),
      findsOneWidget,
    );
    expect(find.text('Fiat amount'), findsOneWidget);
    expect(find.text('GTBank · bank'), findsOneWidget);
  });

  testWidgets('a sell just posted shows under sell', (tester) async {
    final market = _market(pubkey: 'taker');
    market.pending.add(_order(id: 'local-1', maker: 'taker'));

    await tester.pumpWidget(
      MaterialApp(
        home: MarketPage(market: market, account: const SizedBox.shrink()),
      ),
    );

    expect(find.text('10 CKB'), findsNothing);
    await tester.tap(find.text('Sell'));
    await tester.pumpAndSettle();

    expect(find.text('10 CKB'), findsOneWidget);
    expect(find.text('Publishing'), findsOneWidget);
    expect(find.text('Cancel post'), findsNothing);
  });

  testWidgets('a sell is offered under buy and a buy under sell', (
    tester,
  ) async {
    final market = _market(
      pubkey: 'taker',
      orders: [
        _order(available: '10'),
        _order(id: 'buy-1', side: OrderSide.buy, available: '20'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MarketPage(market: market, account: const SizedBox.shrink()),
      ),
    );

    expect(find.text('10 CKB'), findsOneWidget);
    expect(find.text('20 CKB'), findsNothing);

    await tester.tap(find.text('Sell'));
    await tester.pumpAndSettle();

    expect(find.text('20 CKB'), findsOneWidget);
    expect(find.text('10 CKB'), findsNothing);

    await tester.tap(find.text('Trade'));
    await tester.pumpAndSettle();

    expect(find.text('No trades yet.'), findsOneWidget);
    expect(find.text('Buy'), findsNothing);
  });

  testWidgets('a canceled post cannot be taken or canceled again', (
    tester,
  ) async {
    final market = _market(
      pubkey: 'taker',
      orders: [
        _order(status: PostStatus.canceled),
        _order(id: 'mine', maker: 'taker', status: PostStatus.canceled),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MarketPage(market: market, account: const SizedBox.shrink()),
      ),
    );

    expect(find.text('Canceled'), findsNothing);
    expect(find.text('Take'), findsNothing);

    await tester.tap(find.text('Show canceled'));
    await tester.pumpAndSettle();

    expect(find.text('Canceled'), findsOneWidget);
    expect(find.text('Take'), findsNothing);

    await tester.tap(find.text('Sell'));
    await tester.pumpAndSettle();

    expect(find.text('Canceled'), findsOneWidget);
    expect(find.text('Cancel post'), findsNothing);
  });

  testWidgets('a seller waiting on the hold sees the invoice to pay', (
    tester,
  ) async {
    final order = _order(maker: 'seller');
    final market = _market(
      pubkey: 'seller',
      orders: [order],
      trades: [
        TwineTrade(
          id: 'trade-1',
          orderId: order.orderId,
          phase: TradePhase.waitingHold,
          updatedAt: DateTime.utc(2026, 10, 6),
          holdInvoice: 'hold-invoice',
          amountShannons: '100000000',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TradePage(market: market, tradeId: 'trade-1'),
      ),
    );

    expect(find.text('Lock the CKB'), findsOneWidget);
    expect(
      find.text(
        'A buyer took this. Pay this in your Fiber wallet. You cannot cancel after it locks.',
      ),
      findsOneWidget,
    );
    expect(find.text('hold-invoice'), findsOneWidget);
    expect(find.text('1 CKB'), findsOneWidget);
    expect(find.text('Cancel trade'), findsOneWidget);
    expect(find.text("I've sent the fiat"), findsNothing);
  });

  testWidgets('a buyer waiting on the hold is told the seller is locking', (
    tester,
  ) async {
    final order = _order(maker: 'seller');
    final market = _market(
      pubkey: 'buyer',
      orders: [order],
      trades: [
        TwineTrade(
          id: 'trade-1',
          orderId: order.orderId,
          phase: TradePhase.waitingHold,
          updatedAt: DateTime.utc(2026, 10, 6),
          holdInvoice: 'hold-invoice',
          amountShannons: '100000000',
          sellerNostr: 'seller',
          buyerNostr: 'buyer',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TradePage(market: market, tradeId: 'trade-1'),
      ),
    );

    expect(find.text('Waiting for the seller'), findsOneWidget);
    expect(
      find.text(
        'You will have 15 minutes for a mobile transfer once the seller locks.',
      ),
      findsOneWidget,
    );
    expect(find.text('hold-invoice'), findsNothing);
    expect(find.text('Cancel trade'), findsOneWidget);
  });

  testWidgets('the seller shares an account and the buyer waits for it', (
    tester,
  ) async {
    final order = _order(maker: 'seller');
    TwineTrade trade(String id) {
      return TwineTrade(
        id: 'trade-1',
        orderId: order.orderId,
        phase: TradePhase.waitingFiat,
        updatedAt: DateTime.utc(2026, 10, 6),
        fiatAmount: '2500',
        fiatCurrency: 'NGN',
        paymentLabel: 'GTBank',
        reference: 'trade-1',
        sellerNostr: 'seller',
        buyerNostr: 'buyer',
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: TradePage(
          market: _market(
            pubkey: 'seller',
            orders: [order],
            trades: [trade('seller')],
          ),
          tradeId: 'trade-1',
        ),
      ),
    );
    expect(find.text('Share account'), findsOneWidget);
    expect(find.text('Account name'), findsOneWidget);
    expect(find.text('The hold is locked.'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: TradePage(
          market: _market(
            pubkey: 'buyer',
            orders: [order],
            trades: [trade('buyer')],
          ),
          tradeId: 'trade-1',
        ),
      ),
    );
    expect(find.text('Pay the seller'), findsOneWidget);
    expect(
      find.text(
        'The CKB is locked. Waiting for the seller to share the account you should pay.',
      ),
      findsOneWidget,
    );
    expect(find.text('Pay 2500 NGN with GTBank.'), findsOneWidget);
    expect(find.text("I've paid"), findsNothing);
  });

  testWidgets('posting sends the draft and stays when the draft is refused', (
    tester,
  ) async {
    NewOrderDraft? sent;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => PostPage(
                      catalog: _catalog,
                      onSubmit: (draft) async {
                        sent = draft;
                        return draft.validate(_catalog);
                      },
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Post'));
    await tester.tap(find.text('Post'));
    await tester.pump();
    expect(find.text('Enter your Fiber pubkey.'), findsOneWidget);
    expect(sent, isNull);

    await tester.enterText(_field('Your Fiber pubkey'), '02abc');
    await tester.enterText(_field('CKB available'), '10');
    await tester.enterText(_field('Price per CKB'), '1500');
    await tester.enterText(_field('Minimum'), '1000');
    await tester.enterText(_field('Maximum'), '5000');
    await tester.ensureVisible(find.text('Post'));
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(sent?.side, OrderSide.sell);
    expect(sent?.fiatCurrency, 'NGN');
    expect(sent?.methodIds, ['gtbank']);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('the currency select switches the payment methods', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PostPage(
          catalog: _catalog,
          onSubmit: (draft) async => draft.validate(_catalog),
        ),
      ),
    );

    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(find.text('GTBank'), findsOneWidget);
    expect(find.text('Zelle'), findsNothing);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('USD').last);
    await tester.pumpAndSettle();

    expect(find.text('Zelle'), findsOneWidget);
    expect(find.text('GTBank'), findsNothing);
  });

  test('dispute is hidden when the solver is absent', () {
    final hidden = TradeActions.of(
      phase: TradePhase.waitingFiat,
      side: TradeSide.buyer,
      hasHoldInvoice: true,
      solverAvailable: false,
    );
    expect(hidden.dispute, isFalse);

    final shown = TradeActions.of(
      phase: TradePhase.waitingFiat,
      side: TradeSide.buyer,
      hasHoldInvoice: true,
      solverAvailable: null,
    );
    expect(shown.dispute, isTrue);
  });

  testWidgets('a trade countdown uses the stored deadline', (tester) async {
    final order = _order(maker: 'seller');
    final market = _market(
      pubkey: 'buyer',
      orders: [order],
      trades: [
        TwineTrade(
          id: 'trade-1',
          orderId: order.orderId,
          phase: TradePhase.waitingFiat,
          updatedAt: DateTime.utc(2026, 10, 6),
          fiatAmount: '2500',
          fiatCurrency: 'NGN',
          paymentLabel: 'GTBank',
          sellerNostr: 'seller',
          buyerNostr: 'buyer',
          payBy: DateTime.now().toUtc().add(const Duration(hours: 2, minutes: 3)),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: TradePage(market: market, tradeId: 'trade-1')),
    );

    expect(find.textContaining('2h'), findsOneWidget);
    expect(find.textContaining('left'), findsOneWidget);
  });

  testWidgets('a settled trade names the outcome', (tester) async {
    final market = _market(
      pubkey: 'buyer',
      trades: [
        TwineTrade(
          id: 'trade-1',
          orderId: 'order-1',
          phase: TradePhase.settled,
          updatedAt: DateTime.utc(2026, 10, 6),
          amountShannons: '100000000',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: TradePage(market: market, tradeId: 'trade-1')),
    );

    expect(
      find.text('The buyer received the CKB. Fiat was never held by this app.'),
      findsOneWidget,
    );
    expect(find.text('Message'), findsNothing);
  });

  testWidgets('dispute stays off the trade when the solver is null', (
    tester,
  ) async {
    final order = _order(maker: 'seller');
    final market = _market(
      pubkey: 'buyer',
      orders: [order],
      trades: [
        TwineTrade(
          id: 'trade-1',
          orderId: order.orderId,
          phase: TradePhase.waitingFiat,
          updatedAt: DateTime.utc(2026, 10, 6),
          fiatAmount: '2500',
          fiatCurrency: 'NGN',
          sellerNostr: 'seller',
          buyerNostr: 'buyer',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TradePage(
          market: market,
          tradeId: 'trade-1',
          solverAvailable: false,
        ),
      ),
    );

    expect(find.text('Dispute'), findsNothing);
  });

  test('a cant-do for a post removes the local card', () {
    final market = _market(pubkey: 'taker');
    market.pending.add(_order(id: 'local-1', maker: 'taker'));
    market.awaitingPost = true;
    market.applyDaemonReply(
      const TwineEnvelope(
        action: 'cant-do',
        payload: {'reason': 'that post is too small'},
      ),
      DateTime.utc(2026, 10, 6),
    );
    expect(market.pending, isEmpty);
    expect(market.book.notice, 'that post is too small');
  });

  testWidgets('taking a buy post confirms the seller role', (tester) async {
    final market = _market(
      pubkey: 'taker',
      orders: [_order(id: 'buy-1', side: OrderSide.buy)],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TakePage(
          market: market,
          orderId: 'buy-1',
          fiberNode: '02abc',
        ),
      ),
    );

    expect(find.text('Sell CKB'), findsOneWidget);
    expect(find.text('You lock CKB in your Fiber wallet.'), findsOneWidget);
    await tester.enterText(_field('Your Fiber pubkey'), '02abc');
    await tester.enterText(_field('Fiat amount'), '1500');
    await tester.pump();
    expect(find.text('About 1.00 CKB'), findsOneWidget);
    await tester.ensureVisible(find.text('Take'));
    await tester.tap(find.text('Take'));
    await tester.pumpAndSettle();
    expect(find.text('Sell CKB?'), findsOneWidget);
    expect(find.textContaining('About 1.00 CKB'), findsWidgets);
  });

  testWidgets('the post form waits until the daemon publishes methods', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: PostPage(onSubmit: (draft) async => null)),
    );

    expect(find.text('Waiting for payment methods.'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Post'),
    );
    expect(button.onPressed, isNull);
  });
}

TwineMarket _market({
  required String pubkey,
  List<TwineOrder> orders = const [],
  List<TwineTrade> trades = const [],
}) {
  return TwineMarket(
    nostr: TwineNostr(),
    store: MemoryBookStore(),
    accountPubkey: pubkey,
    daemonPubkey: 'daemon',
    book: TwineBook(orders: orders, trades: trades),
  );
}

const _catalog = [
  CatalogMethod(id: 'gtbank', kind: 'bank', label: 'GTBank', currency: 'NGN'),
  CatalogMethod(id: 'zelle', kind: 'wallet', label: 'Zelle', currency: 'USD'),
];

TwineOrder _order({
  String id = 'order-1',
  String maker = 'maker',
  OrderSide side = OrderSide.sell,
  PostStatus status = PostStatus.open,
  String available = '10',
}) {
  return TwineOrder(
    orderId: id,
    side: side,
    makerNostrPubkey: maker,
    makerFiberPubkey: 'fiber',
    availableCkb: available,
    fiatCurrency: 'NGN',
    pricePerCkb: '1500',
    min: '1000',
    max: '5000',
    paymentMethods: const [
      TwinePaymentMethod(
        id: 'gtbank',
        kind: 'bank',
        label: 'GTBank',
        currency: 'NGN',
      ),
    ],
    holdHours: 36,
    updatedAt: DateTime.utc(2026, 10, 6),
    status: status,
  );
}

Finder _field(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
}
