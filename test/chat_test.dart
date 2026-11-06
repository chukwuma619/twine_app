import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/market/chat.dart';
import 'package:twine_app/nostr/chat.dart';

void main() {
  test('a thread message body round-trips', () {
    const body = ChatBody(
      tradeId: 'trade-1',
      kind: TradeNoteKind.paymentDetails,
      text: 'Ada\n0123456789',
    );
    final opened = ChatBody.tryDecode(body.encode());
    expect(opened?.tradeId, 'trade-1');
    expect(opened?.text, 'Ada\n0123456789');
    expect(opened?.kind, TradeNoteKind.paymentDetails);
    expect(ChatBody.tryDecode('not-json'), isNull);
  });
}
