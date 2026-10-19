import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class MemoryCacheRepository extends NonStoringObjectProvider {
  final _items = <String, CacheObject>{};
  int _nextId = 1;
  @override
  Future<CacheObject?> get(String url) async => _items[url];
  @override
  Future<CacheObject> updateOrInsert(CacheObject object) async {
    final stored = object.copyWith(id: _items[object.key]?.id ?? _nextId++);
    _items[object.key] = stored;
    return stored;
  }

  @override
  Future<List<CacheObject>> getAllObjects() async => _items.values.toList();
  @override
  Future<int> deleteAll(Iterable<int> ids) async {
    final before = _items.length;
    _items.removeWhere((_, object) => ids.contains(object.id));
    return before - _items.length;
  }
}
