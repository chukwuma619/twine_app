import 'package:dart_nostr/dart_nostr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/market/chat.dart';
import 'package:twine_app/nostr/account.dart';
import 'package:twine_app/nostr/chat.dart';
import 'package:twine_app/nostr/nip44.dart';

void main() {
  test('a thread message opens for the other trader', () {
    final nostr = Nostr();
    final seller = TwineAccount.generate(nostr);
    final buyer = TwineAccount.generate(nostr);
    final event = sealChat(
      sender: seller,
      peer: buyer.publicKey,
      body: const ChatBody(
        tradeId: 'trade-1',
        kind: TradeNoteKind.paymentDetails,
        accountName: 'Ada',
        accountNumber: '0123456789',
      ),
      createdAt: DateTime.utc(2026, 10, 6),
    );

    final opened = openChat(
      recipient: buyer,
      senderPublicKey: seller.publicKey,
      event: event,
    );
    expect(opened?.tradeId, 'trade-1');
    expect(opened?.accountName, 'Ada');
    expect(opened?.accountNumber, '0123456789');

    final key = nip44ConversationKeyHex(seller.privateKey, buyer.publicKey);
    final plain = nip44DecryptWithConversationKey(
      conversationKeyHex: key,
      payload: event.content!,
    );
    expect(ChatBody.tryDecode(plain)?.accountNumber, '0123456789');
    expect(
      openChat(
        recipient: buyer,
        senderPublicKey: buyer.publicKey,
        event: event,
      ),
      isNull,
    );
  });
}
