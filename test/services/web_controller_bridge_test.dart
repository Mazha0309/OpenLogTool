import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/services/web_controller_bridge_stub.dart' as bridge;

void main() {
  test('controller tab URL carries page and session params', () {
    final url = bridge.controllerTabUrl('sess-123');
    expect(url, startsWith('?'));
    expect(url, contains('page=controller'));
    expect(url, contains('session=sess-123'));
  });

  test('controller tab URL omits empty session', () {
    final url = bridge.controllerTabUrl('');
    expect(url, contains('page=controller'));
    expect(url, isNot(contains('session=')));
  });
}
