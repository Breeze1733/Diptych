import 'package:diptych/models/app_notification.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared moment notification metadata survives cache round trip', () {
    final notification = AppNotification.fromJson({
      'id': 'notification-1',
      'recipient_id': 'B',
      'type': 'moment',
      'title': '对方更新了共记',
      'content': '',
      'date_str': '2025-06-18',
      'shared_moment_id': 'shared-1',
      'created_at': '2025-06-18T12:00:00.000+08:00',
    });

    expect(notification.sharedMomentId, 'shared-1');
    expect(notification.toJson()['shared_moment_id'], 'shared-1');
    expect(
      AppNotification.fromJson(notification.toJson()).sharedMomentId,
      'shared-1',
    );
  });
}
