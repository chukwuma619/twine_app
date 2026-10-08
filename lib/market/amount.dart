const shannonsPerCkb = 100000000;

String? aboutCkb(String fiatAmount, String pricePerCkb) {
  final fiat = double.tryParse(fiatAmount.trim());
  final price = double.tryParse(pricePerCkb.trim());
  if (fiat == null || price == null || fiat <= 0 || price <= 0) return null;
  final ckb = fiat / price;
  if (ckb >= 100) return ckb.toStringAsFixed(0);
  if (ckb >= 1) return ckb.toStringAsFixed(2);
  return ckb.toStringAsFixed(4);
}

String shannonsToCkb(String shannons) {
  final value = BigInt.tryParse(shannons.trim());
  if (value == null || value.isNegative) return shannons;
  final unit = BigInt.from(shannonsPerCkb);
  final whole = value ~/ unit;
  final fraction = (value % unit).toString().padLeft(8, '0');
  final trimmed = fraction.replaceFirst(RegExp(r'0+$'), '');
  if (trimmed.isEmpty) return whole.toString();
  return '$whole.$trimmed';
}
