/// Event kinds and tags shared with the daemon. These are application constants, not NIPs.
library;

/// Kind of an encrypted action or reply. The `p` tag is the recipient.
const kindAction = 4242;

/// Kind of a trade thread message. The `p` tag is the other trader.
/// The `t` tag is the trade id. Not a NIP.
const kindChat = 4243;

/// Addressable order. The `d` tag is the order id. The daemon publishes these.
const kindOrder = 31420;

/// Addressable announcement of a daemon's Fiber node. The `d` tag is [fiberNodeTag].
const kindFiberNode = 31421;

/// `d` tag on a Fiber node announcement.
const fiberNodeTag = 'fiber-node';

/// Addressable payment catalog. The `d` tag is [paymentCatalogTag].
const kindCatalog = 31422;

/// `d` tag on a payment catalog announcement.
const paymentCatalogTag = 'payment-methods';

const actionNewOrder = 'new-order';
const actionTake = 'take';
const actionPayoutInvoice = 'payout-invoice';
const actionFiatSent = 'fiat-sent';
const actionRelease = 'release';
const actionCancel = 'cancel';
const actionDispute = 'dispute';
const actionMyTrades = 'my-trades';

const replyPayInvoice = 'pay-invoice';
const replyNeedInvoice = 'need-invoice';
const replyWaitingFiat = 'waiting-fiat';
const replyFiatSentOk = 'fiat-sent-ok';
const replyNewInvoice = 'new-invoice';
const replyDisputed = 'disputed';
const replyRefunding = 'refunding';
const replySettled = 'settled';
const replyCanceled = 'canceled';
const replyExpired = 'expired';
const replyCantDo = 'cant-do';
const replyTrades = 'trades';
