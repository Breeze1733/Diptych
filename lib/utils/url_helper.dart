import '../constants/api_config.dart';

/// URL 工具
class UrlHelper {
  static const String _siteUrl = ApiConfig.siteUrl;

  /// 本站图片保存相对路径，外部图片地址保持原样。
  static String imageReference(String url) {
    final normalized = normalize(url);
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.origin != Uri.parse(_siteUrl).origin ||
        !uri.path.startsWith('/uploads/')) {
      return url;
    }
    final suffix = StringBuffer(uri.path);
    if (uri.hasQuery) suffix.write('?${uri.query}');
    if (uri.hasFragment) suffix.write('#${uri.fragment}');
    return suffix.toString();
  }

  /// 补全相对路径为完整 URL
  static String normalize(String url) {
    if (url.isEmpty) return url;
    final uri = Uri.tryParse(url);
    if (uri != null) {
      final isRelative = !uri.hasScheme && !uri.hasAuthority;
      final isWebUrl =
          (uri.scheme == 'http' || uri.scheme == 'https') && uri.hasAuthority;
      final isCurrentSite =
          isWebUrl && uri.origin == Uri.parse(_siteUrl).origin;
      final isOldSite = isWebUrl && uri.origin == 'https://breeze.qzz.io';
      final path = uri.path.startsWith('/') ? uri.path : '/${uri.path}';
      final legacyUpload = path.startsWith('/api/uploads/');
      if ((isRelative || isCurrentSite || isOldSite) &&
          (legacyUpload || (isOldSite && path.startsWith('/uploads/')))) {
        return Uri.parse(_siteUrl)
            .replace(
              path: legacyUpload ? path.substring(4) : path,
              query: uri.hasQuery ? uri.query : null,
              fragment: uri.hasFragment ? uri.fragment : null,
            )
            .toString();
      }
    }
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('/')) return '$_siteUrl$url';
    return '$_siteUrl/$url';
  }
}
