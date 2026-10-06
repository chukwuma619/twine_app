/// JSON body of an action or a reply: `{ action, trade_id?, payload? }`.
library;

import 'dart:convert';

class TwineEnvelope {
  const TwineEnvelope({required this.action, this.tradeId, this.payload});

  final String action;
  final String? tradeId;
  final Object? payload;

  String encode() {
    final body = <String, Object>{'action': action};
    final trade = tradeId;
    if (trade != null) body['trade_id'] = trade;
    final extra = payload;
    if (extra != null) body['payload'] = extra;
    return jsonEncode(body);
  }

  static TwineEnvelope? tryDecode(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final action = decoded['action'];
    if (action is! String || action.isEmpty) return null;
    final tradeId = decoded['trade_id'];
    if (tradeId != null && tradeId is! String) return null;
    return TwineEnvelope(
      action: action,
      tradeId: tradeId as String?,
      payload: decoded['payload'],
    );
  }
}
