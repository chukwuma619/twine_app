/// CKB amounts the daemon sends as shannons.
library;

const shannonsPerCkb = 100000000;

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
