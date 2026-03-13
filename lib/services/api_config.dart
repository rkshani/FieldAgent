class ApiConfig {
  ApiConfig._();

  static const String domain = 'https://www.hisaab.org';

  static const String tclApiRoot = '/tclorder_apis_new_test/';
  static const String tclApiRootNoTrailingSlash = '/tclorder_apis_new_test';

  static const String tclApiNewTestRoot = '/tclorder_apis_new_test/';
  static const String tclApiNewTestRootNoTrailingSlash =
      '/tclorder_apis_new_test';

  static const String orderNewUrl = '$domain/order/new.php';
  static const String loginUrl = '$domain${tclApiRoot}new.php';

  static const String tclApiBase = '$domain$tclApiRoot';
  static const String tclApiBaseNewTest = '$domain$tclApiNewTestRoot';

  static String trimTrailingSlash(String value) {
    return value.replaceAll(RegExp(r'/$'), '');
  }

  static String trimLeadingSlash(String value) {
    return value.replaceAll(RegExp(r'^/+'), '');
  }

  static String joinBaseAndPath(String base, String path) {
    final b = trimTrailingSlash(base);
    final p = path.startsWith('/') ? path : '/$path';

    if (b.endsWith(tclApiRootNoTrailingSlash) && p.startsWith(tclApiRoot)) {
      return '$b${p.replaceFirst(tclApiRootNoTrailingSlash, '')}';
    }
    if (b.endsWith(tclApiNewTestRootNoTrailingSlash) &&
        p.startsWith(tclApiNewTestRoot)) {
      return '$b${p.replaceFirst(tclApiNewTestRootNoTrailingSlash, '')}';
    }

    return '$b$p';
  }
}
