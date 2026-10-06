/// The payment methods a daemon publishes for new posts.
library;

import 'dart:convert';

import 'package:dart_nostr/dart_nostr.dart';

import '../constant.dart';
import 'verify.dart';

class CatalogMethod {
  const CatalogMethod({
    required this.id,
    required this.kind,
    required this.label,
    required this.currency,
  });

  final String id;
  final String kind;
  final String label;
  final String currency;

  static CatalogMethod? tryParse(Object? value) {
    if (value is! Map) return null;
    final map = value.map((key, item) => MapEntry('$key', item));
    final id = _text(map['id']);
    final kind = _text(map['kind']);
    final label = _text(map['label']);
    final currency = _text(map['currency']);
    if (id == null || kind == null || label == null || currency == null) {
      return null;
    }
    return CatalogMethod(id: id, kind: kind, label: label, currency: currency);
  }

  Map<String, String> toJson() {
    return {'id': id, 'kind': kind, 'label': label, 'currency': currency};
  }
}

class OpenedCatalog {
  const OpenedCatalog({required this.methods, required this.updatedAt});

  final List<CatalogMethod> methods;
  final DateTime updatedAt;
}

/// Methods from a kind-31422 event signed by [daemonPublicKey].
/// Null when the event is not that announcement.
OpenedCatalog? openCatalog({
  required String daemonPublicKey,
  required NostrEvent event,
}) {
  if (event.kind != kindCatalog) return null;
  if (!_tagged(event.tags, paymentCatalogTag)) return null;
  if (!signedBy(event, daemonPublicKey)) return null;
  final createdAt = event.createdAt;
  final content = event.content;
  if (createdAt == null || content == null) return null;

  final Object? decoded;
  try {
    decoded = jsonDecode(content);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  final raw = decoded['methods'];
  if (raw is! List) return null;
  final methods = <CatalogMethod>[];
  for (final item in raw) {
    final method = CatalogMethod.tryParse(item);
    if (method == null) return null;
    methods.add(method);
  }
  return OpenedCatalog(methods: methods, updatedAt: createdAt);
}

List<CatalogMethod> methodsForCurrency(
  List<CatalogMethod> catalog,
  String currency,
) {
  return [
    for (final method in catalog)
      if (method.currency == currency) method,
  ];
}

List<String> catalogCurrencies(List<CatalogMethod> catalog) {
  final currencies = <String>[];
  for (final method in catalog) {
    if (!currencies.contains(method.currency)) currencies.add(method.currency);
  }
  return currencies;
}

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return trimmed;
}

bool _tagged(List<List<String>>? tags, String identifier) {
  if (tags == null) return false;
  for (final tag in tags) {
    if (tag.length >= 2 && tag[0] == 'd' && tag[1] == identifier) return true;
  }
  return false;
}
