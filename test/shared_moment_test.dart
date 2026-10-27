import 'package:diptych/constants/api_config.dart';
import 'package:diptych/models/shared_moment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('block factories create stable non-index identities', () {
    final first = SharedMomentBlock.text(authorId: 'A', text: '第一段');
    final second = SharedMomentBlock.image(
      authorId: 'B',
      imageUrl: '/api/uploads/photo.jpg',
    );

    expect(first.id, isNotEmpty);
    expect(second.id, isNotEmpty);
    expect(second.id, isNot(first.id));
    expect(first.copyWith(text: '修改后').id, first.id);
  });

  test('shared moment JSON round trip keeps its fixed block schema', () {
    final createdAt = DateTime.parse('2026-10-26T08:00:00+08:00');
    final updatedAt = DateTime.parse('2026-10-26T09:30:00+08:00');
    final moment = SharedMoment(
      id: 'shared-1',
      dateStr: '2025-06-18',
      schemaVersion: 1,
      revision: 7,
      createdBy: 'A',
      createdAt: createdAt,
      updatedAt: updatedAt,
      blocks: [
        SharedMomentBlock.text(
          id: 'block-text',
          authorId: 'A',
          text: '一起写下这一天',
          createdAt: createdAt,
          updatedAt: updatedAt,
        ),
        SharedMomentBlock.image(
          id: 'block-image',
          authorId: 'B',
          imageUrl: '/api/uploads/photo.jpg',
          createdAt: updatedAt,
          updatedAt: updatedAt,
        ),
      ],
    );

    final json = moment.toJson();
    expect(json.keys, {
      'id',
      'date_str',
      'schema_version',
      'revision',
      'blocks',
      'created_by',
      'created_at',
      'updated_at',
    });
    final textJson = (json['blocks'] as List).first as Map<String, dynamic>;
    expect(textJson.keys, {
      'id',
      'type',
      'author_id',
      'text',
      'image_url',
      'created_at',
      'updated_at',
    });
    expect(textJson['image_url'], '');

    final decoded = SharedMoment.fromJson(json);
    expect(decoded.id, moment.id);
    expect(decoded.dateStr, moment.dateStr);
    expect(decoded.schemaVersion, 1);
    expect(decoded.revision, 7);
    expect(decoded.createdBy, 'A');
    expect(decoded.createdAt.toUtc(), createdAt.toUtc());
    expect(decoded.updatedAt.toUtc(), updatedAt.toUtc());
    expect(decoded.blocks.map((block) => block.id), [
      'block-text',
      'block-image',
    ]);
    expect(decoded.blocks.first.text, '一起写下这一天');
    expect(
      decoded.blocks.last.imageUrl,
      '${ApiConfig.siteUrl}/api/uploads/photo.jpg',
    );
  });

  test('unknown block types are rejected instead of rendered incorrectly', () {
    expect(
      () => SharedMomentBlock.fromJson({
        'id': 'future-block',
        'type': 'audio',
        'author_id': 'A',
      }),
      throwsFormatException,
    );
  });
}
