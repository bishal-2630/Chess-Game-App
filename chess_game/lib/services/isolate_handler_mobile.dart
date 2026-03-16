import 'dart:ui';
import 'dart:isolate';

void registerIsolatePort(ReceivePort port, bool isBackground) {
  final portName = isBackground ? 'chess_game_bg_port' : 'chess_game_main_port';
  try {
    IsolateNameServer.removePortNameMapping(portName);
    IsolateNameServer.registerPortWithName(port.sendPort, portName);
    print('✅ Registered isolate port: $portName');
  } catch (e) {
    print('❌ Failed to register isolate port: $e');
  }
}
