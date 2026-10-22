import 'package:diptych/constants/api_config.dart';
import 'package:diptych/services/http_request.dart';
import 'package:diptych/services/topic_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _DeleteResponseRequests extends HttpRequests {
  _DeleteResponseRequests(this.response);

  final http.Response response;
  Uri? requestedUrl;

  @override
  Future<http.Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    requestedUrl = url;
    return response;
  }
}

void main() {
  test(
    'deletePost completes only after a successful server acknowledgement',
    () async {
      final requests = _DeleteResponseRequests(
        http.Response('{"ok":true}', 200),
      );
      final service = TopicService(http: requests);

      await service.deletePost('topic-1', 'post-1');

      expect(
        requests.requestedUrl,
        Uri.parse('${ApiConfig.apiBaseUrl}/topics/topic-1/posts/post-1'),
      );
    },
  );

  for (final status in [401, 403, 404, 500]) {
    test('deletePost rejects HTTP $status even if its body says ok', () async {
      final service = TopicService(
        http: _DeleteResponseRequests(http.Response('{"ok":true}', status)),
      );

      await expectLater(
        service.deletePost('topic-1', 'post-1'),
        throwsException,
      );
    });
  }

  test(
    'deletePost rejects an application error in an HTTP 200 response',
    () async {
      final service = TopicService(
        http: _DeleteResponseRequests(
          http.Response('{"ok":false,"error":"forbidden"}', 200),
        ),
      );

      await expectLater(
        service.deletePost('topic-1', 'post-1'),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('forbidden'),
          ),
        ),
      );
    },
  );

  for (final body in ['{}', '[]', 'null', '{"ok":"true"}', 'not-json', '']) {
    test('deletePost rejects an unconfirmed response: $body', () async {
      final service = TopicService(
        http: _DeleteResponseRequests(http.Response(body, 200)),
      );

      await expectLater(
        service.deletePost('topic-1', 'post-1'),
        throwsException,
      );
    });
  }
}
