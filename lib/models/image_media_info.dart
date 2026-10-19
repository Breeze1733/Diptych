class ImageMediaInfo {
  const ImageMediaInfo({
    required this.originalBytes,
    required this.width,
    required this.height,
    required this.isMotion,
  });
  final int originalBytes;
  final int width;
  final int height;
  final bool isMotion;
  factory ImageMediaInfo.fromJson(Map<String, dynamic> json) => ImageMediaInfo(
    originalBytes: (json['original_bytes'] as num?)?.toInt() ?? 0,
    width: (json['width'] as num?)?.toInt() ?? 0,
    height: (json['height'] as num?)?.toInt() ?? 0,
    isMotion: json['is_motion'] == true,
  );
  Map<String, dynamic> toJson() => {
    'original_bytes': originalBytes,
    'width': width,
    'height': height,
    'is_motion': isMotion,
  };
}
