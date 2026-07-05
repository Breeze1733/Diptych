/// URL 工具
class UrlHelper {
  static const String _siteUrl = 'https://example.com';

  /// 补全相对路径为完整 URL
  static String normalize(String url) {
    if (url.isEmpty) return url;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('/')) return '$_siteUrl$url';
    return '$_siteUrl/$url';
  }
}
