import 'dart:isolate';

void registerIsolatePort(ReceivePort port, bool isBackground) {
  // No-op on Web
  print('ℹ️ Skipping isolate port registration on Web');
}
