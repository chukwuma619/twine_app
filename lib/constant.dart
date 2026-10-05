/// Event kinds and tags shared with the daemon. These are application constants, not NIPs.
library;

/// Kind of an encrypted action or reply. The `p` tag is the recipient.
const kindAction = 4242;

/// Addressable announcement of a daemon's Fiber node. The `d` tag is [fiberNodeTag].
const kindFiberNode = 31421;

/// `d` tag on a Fiber node announcement.
const fiberNodeTag = 'fiber-node';
