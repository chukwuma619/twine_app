import 'package:flutter_test/flutter_test.dart';
import 'package:twine_app/market/channel.dart';

void main() {
  test('the desk node is optional peer information', () {
    final summary = deskNodeSummary();
    expect(summary, contains('needs a peer'));
    expect(summary, contains('invoices'));
  });
}
