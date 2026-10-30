import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/draft_service.dart';

final sharedDiaryDraftStoreProvider =
    Provider.family<SharedDiaryDraftStore, ({String userId, String dateStr})>(
      (ref, scope) =>
          SharedDiaryDraftStore(userId: scope.userId, dateStr: scope.dateStr),
    );
