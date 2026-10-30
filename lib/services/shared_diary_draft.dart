import '../models/shared_moment.dart';
import '../widgets/photo_grid_picker.dart';
import 'draft_service.dart';

class SharedDraftPhoto {
  final String blockId;
  final String authorId;
  final DraftPhotoItem item;

  const SharedDraftPhoto({
    required this.blockId,
    required this.authorId,
    required this.item,
  });

  PhotoEntry get entry => item.isLocal
      ? PhotoEntry.file(
          item.file!,
          isMotion: item.isMotion,
          uploadLive: item.uploadLive,
        )
      : PhotoEntry.url(
          item.url!,
          isMotion: item.isMotion,
          uploadLive: item.uploadLive,
        );
}

class SharedDiaryDraft {
  final SharedMoment base;
  final List<SharedMomentBlock> blocks;
  final List<Map<String, dynamic>> splits;
  final List<SharedDraftPhoto> photos;
  final SharedMoment? reference;

  const SharedDiaryDraft({
    required this.base,
    required this.blocks,
    required this.splits,
    required this.photos,
    this.reference,
  });
}
