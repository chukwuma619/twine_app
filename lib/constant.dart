/// Event kinds and tags shared with the daemon. These are application constants, not NIPs.
library;

/// Kind of an encrypted action or reply. The `p` tag is the recipient.
const kindAction = 4242;

/// Addressable order. The `d` tag is the order id. The daemon publishes these.
const kindOrder = 31420;

/// Addressable announcement of a daemon's Fiber node. The `d` tag is [fiberNodeTag].
const kindFiberNode = 31421;

/// `d` tag on a Fiber node announcement.
const fiberNodeTag = 'fiber-node';

const actionNewOrder = 'new-order';
const actionTake = 'take';
const actionFiatSent = 'fiat-sent';
const actionRelease = 'release';
const actionCancel = 'cancel';
const actionDispute = 'dispute';

const replyPayInvoice = 'pay-invoice';
const replyWaitingFiat = 'waiting-fiat';
const replyFiatSentOk = 'fiat-sent-ok';
const replyNewInvoice = 'new-invoice';
const replyDisputed = 'disputed';
const replyRefunding = 'refunding';
const replySettled = 'settled';
const replyCanceled = 'canceled';
const replyExpired = 'expired';
const replyCantDo = 'cant-do';

/// A payment method the daemon ships with. A post names these ids.
/// Taking reads the methods off the public order, so a post can show a method
/// this install did not use when it was created.
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
}

const catalogMethods = <CatalogMethod>[
  CatalogMethod(id: 'gtbank', kind: 'bank', label: 'GTBank', currency: 'NGN'),
  CatalogMethod(id: 'zelle', kind: 'wallet', label: 'Zelle', currency: 'USD'),
];

List<CatalogMethod> methodsForCurrency(String currency) {
  return [
    for (final method in catalogMethods)
      if (method.currency == currency) method,
  ];
}

List<String> catalogCurrencies() {
  final currencies = <String>[];
  for (final method in catalogMethods) {
    if (!currencies.contains(method.currency)) currencies.add(method.currency);
  }
  return currencies;
}
