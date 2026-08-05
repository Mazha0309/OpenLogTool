import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/services/web_controller_bridge_stub.dart'
    as bridge;

void main() {
  test('stub controller tab URL is inert off web', () {
    expect(bridge.controllerTabUrl('sess-123'), '');
  });
}
