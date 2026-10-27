import 'dart:math';

import '../utils/date_helper.dart';
import '../utils/url_helper.dart';

enum SharedMomentBlockType { text, image }

/// An independently addressable fragment in a co-written diary.
///
/// Block ids are persisted with the document and must never be derived from the
/// current list index: inserting a block may move its neighbours, but it must
/// not change their identities.
class SharedMomentBlock {
  final String id;
  final SharedMomentBlockType type;
  final String authorId;
  final String text;
  final String imageUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const SharedMomentBlock({
    required this.id,
    required this.type,
    required this.authorId,
    this.text = '',
    this.imageUrl = '',
    this.createdAt,
    this.updatedAt,
  });

  factory SharedMomentBlock.text({
    String? id,
    required String authorId,
    required String text,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SharedMomentBlock(
      id: id ?? _newBlockId(),
      type: SharedMomentBlockType.text,
      authorId: authorId,
      text: text,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  factory SharedMomentBlock.image({
    String? id,
    required String authorId,
    required String imageUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SharedMomentBlock(
      id: id ?? _newBlockId(),
      type: SharedMomentBlockType.image,
      authorId: authorId,
      imageUrl: imageUrl,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  factory SharedMomentBlock.fromJson(Map<String, dynamic> json) {
    final type = switch (json['type']) {
      'text' => SharedMomentBlockType.text,
      'image' => SharedMomentBlockType.image,
      final value => throw FormatException('未知的共写日记块类型: $value'),
    };
    final rawImageUrl = json['image_url'] as String? ?? '';
    return SharedMomentBlock(
      id: json['id']?.toString() ?? '',
      type: type,
      authorId: json['author_id'] as String? ?? '',
      text: json['text'] as String? ?? '',
      imageUrl: rawImageUrl.isEmpty ? '' : UrlHelper.normalize(rawImageUrl),
      createdAt: _tryParseOptionalDate(json['created_at']),
      updatedAt: _tryParseOptionalDate(json['updated_at']),
    );
  }

  SharedMomentBlock copyWith({
    String? id,
    SharedMomentBlockType? type,
    String? authorId,
    String? text,
    String? imageUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SharedMomentBlock(
      id: id ?? this.id,
      type: type ?? this.type,
      authorId: authorId ?? this.authorId,
      text: text ?? this.text,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'author_id': authorId,
      'text': text,
      'image_url': imageUrl,
      'created_at': createdAt == null
          ? null
          : DateHelper.toIsoString(createdAt!),
      'updated_at': updatedAt == null
          ? null
          : DateHelper.toIsoString(updatedAt!),
    };
  }

  static final Random _random = Random.secure();

  static String _newBlockId() {
    final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final entropy = _random.nextInt(0x7fffffff).toRadixString(36);
    return 'b_${time}_$entropy';
  }
}

class SharedMoment {
  final String id;
  final String dateStr;
  final int schemaVersion;
  final int revision;
  final List<SharedMomentBlock> blocks;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SharedMoment({
    required this.id,
    required this.dateStr,
    this.schemaVersion = 1,
    required this.revision,
    this.blocks = const [],
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SharedMoment.fromJson(Map<String, dynamic> json) {
    final rawBlocks = json['blocks'];
    return SharedMoment(
      id: json['id']?.toString() ?? '',
      dateStr: json['date_str'] as String? ?? '',
      schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 1,
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      blocks: rawBlocks is List
          ? rawBlocks
                .whereType<Map>()
                .map(
                  (raw) => SharedMomentBlock.fromJson(
                    Map<String, dynamic>.from(raw),
                  ),
                )
                .toList(growable: false)
          : const [],
      createdBy: json['created_by'] as String?,
      createdAt: DateHelper.tryParseDateTime(
        json['created_at'] as String? ?? '',
      ),
      updatedAt: DateHelper.tryParseDateTime(
        json['updated_at'] as String? ?? '',
      ),
    );
  }

  SharedMoment copyWith({
    String? id,
    String? dateStr,
    int? schemaVersion,
    int? revision,
    List<SharedMomentBlock>? blocks,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SharedMoment(
      id: id ?? this.id,
      dateStr: dateStr ?? this.dateStr,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      revision: revision ?? this.revision,
      blocks: blocks ?? this.blocks,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date_str': dateStr,
      'schema_version': schemaVersion,
      'revision': revision,
      'blocks': blocks.map((block) => block.toJson()).toList(),
      'created_by': createdBy,
      'created_at': DateHelper.toIsoString(createdAt),
      'updated_at': DateHelper.toIsoString(updatedAt),
    };
  }
}

DateTime? _tryParseOptionalDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateHelper.tryParseDateTime(value);
}
