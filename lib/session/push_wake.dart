import 'dart:isolate';
import 'dart:ui';

const pushWakePortName = 'twine.push.wake';

/// Content-free doorbell. The isolate that receives FCM must not decrypt.
///
/// FCM's background handler runs in another isolate. [bind] on the UI
/// isolate is what makes [note] from that handler visible here.
class PushWake {
  bool pending = false;
  ReceivePort? _inbox;

  void bind() {
    unbind();
    final inbox = ReceivePort();
    IsolateNameServer.removePortNameMapping(pushWakePortName);
    IsolateNameServer.registerPortWithName(inbox.sendPort, pushWakePortName);
    inbox.listen((_) {
      pending = true;
    });
    _inbox = inbox;
  }

  void unbind() {
    _inbox?.close();
    _inbox = null;
    IsolateNameServer.removePortNameMapping(pushWakePortName);
  }

  void note() {
    pending = true;
    IsolateNameServer.lookupPortByName(pushWakePortName)?.send(true);
  }

  bool consume() {
    final had = pending;
    pending = false;
    return had;
  }
}

final pushWake = PushWake();
