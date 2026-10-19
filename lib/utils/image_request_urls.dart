import '../constants/api_config.dart';

class ImageRequestUrls {
  ImageRequestUrls._();
  static bool supportsPreview(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return false;
    final trustedOrigins = {
      Uri.parse(ApiConfig.apiBaseUrl).origin,
      Uri.parse(ApiConfig.siteUrl).origin,
    };
    return trustedOrigins.contains(uri.origin) &&
        RegExp(r'^/(?:api/)?uploads/[^/]+$').hasMatch(uri.path);
  }

  static String variant(String url, String variant) {
    final uri = Uri.parse(url);
    return uri
        .replace(
          queryParameters: {
            ...uri.queryParameters,
            'variant': variant,
            if (variant != 'original') 'pv': '1',
          },
        )
        .toString();
  }

  static String original(String url) {
    final uri = Uri.parse(url);
    final parameters = Map<String, String>.of(uri.queryParameters)
      ..remove('variant')
      ..remove('pv');
    final result = uri.replace(queryParameters: parameters).toString();
    return result.endsWith('?')
        ? result.substring(0, result.length - 1)
        : result;
  }
}
