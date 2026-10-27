import 'dart:collection';
import 'dart:convert';

import 'package:diptych/constants/api_config.dart';
import 'package:diptych/models/shared_moment.dart';
import 'package:diptych/services/api_service.dart';
import 'package:diptych/services/http_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _Call {
  final String method;
  final Uri uri;
  final Map<String, String>? headers;
  final Object? body;

  const _Call(this.method, this.uri, this.headers, this.body);
}

class _RecordingRequests extends HttpRequests {
  _RecordingRequests(Iterable<http.Response> responses)
    : responses = Queue.of(responses);

  final Queue<http.Response> responses;
  final calls = <_Call>[];

  Future<http.Response> _respond(
    String method,
    Uri uri,
    Map<String, String>? headers,
    Object? body,
  ) async {
    calls.add(_Call(method, uri, headers, body));
    if (responses.isEmpty) throw StateError('No response queued');
    return responses.removeFirst();
  }

  @override
  Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 25),
  }) => _respond('GET', url, headers, null);

  @override
  Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 25),
  }) => _respond('POST', url, headers, body);

  @override
  Future<http.Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) => _respond('PUT', url, headers, body);
}

Map<String, dynamic> _sharedJson({int revision = 0}) => {
  'id': 'shared-1',
  'date_str': '2025-06-18',
  'schema_version': 1,
  'revision': revision,
  'blocks': const [],
  'created_by': 'A',
  'created_at': '2025-06-18T08:00:00.000+08:00',
  'updated_at': '2025-06-18T08:00:00.000+08:00',
};

http.Response _jsonResponse(Object? data, {int status = 200, bool ok = true}) =>
    http.Response(
      jsonEncode({'ok': ok, 'data': data}),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  test('GET by date preserves cached-null server semantics', () async {
    final requests = _RecordingRequests([_jsonResponse(null)]);
    final service = ApiService(http: requests);

    expect(await service.getSharedMoment('2025-06-18'), isNull);

    final call = requests.calls.single;
    expect(call.method, 'GET');
    expect(
      call.uri.path,
      '${Uri.parse(ApiConfig.apiBaseUrl).path}/shared-moments',
    );
    expect(call.uri.queryParameters, {'date_str': '2025-06-18'});
    expect(call.headers?['Cache-Control'], 'no-cache, no-store');
  });

  test('activation sends the selected date and import policy', () async {
    final requests = _RecordingRequests([_jsonResponse(_sharedJson())]);
    final service = ApiService(http: requests);

    final result = await service.activateSharedMoment('2025-06-18');

    expect(result.id, 'shared-1');
    final call = requests.calls.single;
    expect(call.method, 'POST');
    expect(jsonDecode(call.body! as String), {
      'date_str': '2025-06-18',
      'import_standard': false,
    });
  });

  test(
    'activation can atomically send initial blocks and import policy',
    () async {
      final requests = _RecordingRequests([_jsonResponse(_sharedJson())]);
      final service = ApiService(http: requests);
      final block = SharedMomentBlock.text(
        id: 'initial-text',
        authorId: 'A',
        text: '带入编辑内容',
      );

      await service.activateSharedMoment(
        '2025-06-18',
        blocks: [block],
        importStandard: true,
      );

      expect(jsonDecode(requests.calls.single.body! as String), {
        'date_str': '2025-06-18',
        'blocks': [block.toJson()],
        'import_standard': true,
      });
    },
  );

  test('update sends revision, blocks and split metadata', () async {
    final requests = _RecordingRequests([
      _jsonResponse(_sharedJson(revision: 4)),
    ]);
    final service = ApiService(http: requests);
    final original = SharedMoment.fromJson(_sharedJson(revision: 3));
    final blocks = [
      SharedMomentBlock.text(id: 'b-1', authorId: 'A', text: '新内容'),
    ];

    final result = await service.updateSharedMoment(
      moment: original,
      blocks: blocks,
      splitForeignText: const [
        {'block_id': 'foreign-1', 'offset': 2},
      ],
    );

    expect(result.revision, 4);
    final call = requests.calls.single;
    expect(call.method, 'PUT');
    expect(call.uri.path, endsWith('/shared-moments/shared-1'));
    final body = jsonDecode(call.body! as String) as Map<String, dynamic>;
    expect(body['base_revision'], 3);
    expect((body['blocks'] as List).single['id'], 'b-1');
    expect(body['split_foreign_text'], [
      {'block_id': 'foreign-1', 'offset': 2},
    ]);
  });

  test('revision conflict exposes the latest server document', () async {
    final requests = _RecordingRequests([
      http.Response(
        jsonEncode({
          'ok': false,
          'code': 'revision_conflict',
          'data': _sharedJson(revision: 9),
        }),
        409,
      ),
    ]);
    final service = ApiService(http: requests);
    final original = SharedMoment.fromJson(_sharedJson(revision: 3));

    await expectLater(
      service.updateSharedMoment(moment: original, blocks: const []),
      throwsA(
        isA<SharedMomentConflictException>().having(
          (error) => error.latest.revision,
          'latest revision',
          9,
        ),
      ),
    );
  });

  test('non-revision 409 keeps the server validation message', () async {
    final requests = _RecordingRequests([
      http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'ok': false,
            'code': 'split_source_changed',
            'error': '要拆分的文字块已不存在，请刷新后重试',
          }),
        ),
        409,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      ),
    ]);
    final service = ApiService(http: requests);

    await expectLater(
      service.updateSharedMoment(
        moment: SharedMoment.fromJson(_sharedJson(revision: 3)),
        blocks: const [],
      ),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('要拆分的文字块已不存在'),
        ),
      ),
    );
  });

  for (final wrapped in [false, true]) {
    test('dates accepts ${wrapped ? 'wrapped' : 'list'} response', () async {
      final dates = ['2025-06-18', '2025-06-19'];
      final requests = _RecordingRequests([
        _jsonResponse(wrapped ? {'dates': dates} : dates),
      ]);

      expect(await ApiService(http: requests).getSharedMomentDates(), dates);
      expect(
        requests.calls.single.uri.path,
        '${Uri.parse(ApiConfig.apiBaseUrl).path}/shared-moments/dates',
      );
    });
  }

  test('shared search keeps its own cursor and decodes pagination', () async {
    final requests = _RecordingRequests([
      _jsonResponse({
        'items': [_sharedJson(revision: 5)],
        'has_more': true,
        'next_cursor': 'shared-1',
      }),
    ]);

    final result = await ApiService(http: requests)
        .searchSharedMoments('一起', limit: 7, cursor: 'previous-shared');

    expect(result.items.single.revision, 5);
    expect(result.hasMore, isTrue);
    expect(result.nextCursor, 'shared-1');
    final call = requests.calls.single;
    expect(call.method, 'GET');
    expect(
      call.uri.path,
      '${Uri.parse(ApiConfig.apiBaseUrl).path}/shared-moments/search',
    );
    expect(call.uri.queryParameters, {
      'keyword': '一起',
      'limit': '7',
      'cursor': 'previous-shared',
    });
  });
}
