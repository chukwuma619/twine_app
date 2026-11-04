import 'update_client.dart';
import 'update_stub.dart' if (dart.library.io) 'update_io.dart';

UpdateClient createUpdateClient() => createPlatformUpdateClient();
