import 'package:flutter_test/flutter_test.dart';
import 'package:openlogtool/services/url_sync.dart';

void main() {
  test('builds query for page and session', () {
    expect(buildSyncQuery('workbench', null), '?page=workbench');
    expect(
        buildSyncQuery('sessions', 'sess-1'), '?page=sessions&session=sess-1');
  });

  test('parses query', () {
    final r = parseSyncQuery('?page=sessions&session=abc');
    expect(r.page, 'sessions');
    expect(r.session, 'abc');
    expect(parseSyncQuery('').page, isNull);
    expect(parseSyncQuery('?foo=bar').page, isNull);
  });

  test('maps home index to page name and back', () {
    expect(pageForHomeIndex(0), 'workbench');
    expect(pageForHomeIndex(3), 'settings');
    expect(homeIndexForPage('data'), 2);
    expect(homeIndexForPage('unknown'), 0);
  });
}
