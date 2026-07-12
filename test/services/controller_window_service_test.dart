import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/models/controller_display.dart';
import 'package:openlogtool/services/controller_window_service.dart';

void main() {
  test('desktop child window arguments preserve display state', () {
    const launch = ControllerWindowLaunch(
      mode: ControllerWindowMode.secondDisplay,
      data: ControllerDisplayDto(
        sessionTitle: '周日晚间点名',
        currentOrdinal: 12,
        totalRecords: 11,
        current: ControllerRecordDisplay(
          controller: 'BG5CRL',
          callsign: 'BA4AAA',
        ),
      ),
      preferences: ControllerDisplayPreferences(
        detail: ControllerDisplayDetail.standard,
      ),
    );

    final restored = ControllerWindowLaunch.fromArguments(
      launch.toArguments(),
    );

    expect(restored.mode, ControllerWindowMode.secondDisplay);
    expect(restored.data.sessionTitle, '周日晚间点名');
    expect(restored.data.currentOrdinal, 12);
    expect(restored.data.current.callsign, 'BA4AAA');
    expect(
      restored.preferences.detail,
      ControllerDisplayDetail.standard,
    );
  });
}
