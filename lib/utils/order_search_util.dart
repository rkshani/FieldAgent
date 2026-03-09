/// Search utility matching Android's multi-token search behavior
/// from SearchAdapter_new_for_item
class OrderSearchUtil {
  /// Performs Android-style multi-token search on items/packages
  /// Returns filtered and sorted list based on match quality
  static List<Map<String, dynamic>> searchItems({
    required List<Map<String, dynamic>> items,
    required String query,
  }) {
    if (query.trim().isEmpty) return items;

    final tokens = query.toLowerCase().trim().split(RegExp(r'\s+'));
    final results = <Map<String, dynamic>>[];

    for (final item in items) {
      final name = (item['name'] ?? item['bookname'] ?? '')
          .toString()
          .toLowerCase();
      final code = (item['code'] ?? item['bookcode'] ?? '')
          .toString()
          .toLowerCase();
      final searchText = '$name $code';

      // Check if all tokens match (Android behavior: multi-token AND logic)
      bool allTokensMatch = true;
      for (final token in tokens) {
        if (!searchText.contains(token)) {
          allTokensMatch = false;
          break;
        }
      }

      if (allTokensMatch) {
        // Calculate match score for sorting
        final matchScore = _calculateMatchScore(
          name: name,
          code: code,
          tokens: tokens,
          query: query.toLowerCase(),
        );

        final itemWithScore = Map<String, dynamic>.from(item);
        itemWithScore['_match_score'] = matchScore;
        itemWithScore['_match_highlight'] = _getHighlightedText(
          name: item['name']?.toString() ?? '',
          code: item['code']?.toString() ?? '',
          tokens: tokens,
        );
        results.add(itemWithScore);
      }
    }

    // Sort by match score (higher is better)
    results.sort((a, b) {
      final scoreA = a['_match_score'] as double? ?? 0;
      final scoreB = b['_match_score'] as double? ?? 0;
      return scoreB.compareTo(scoreA);
    });

    return results;
  }

  /// Calculate match relevance score
  /// Prioritizes: exact match > starts with > code match > name contains
  static double _calculateMatchScore({
    required String name,
    required String code,
    required List<String> tokens,
    required String query,
  }) {
    double score = 0;

    // Exact match bonus
    if (name == query || code == query) {
      score += 100;
    }

    // Code exact match (high priority in Android)
    if (code == query) {
      score += 50;
    }

    // Starts with query
    if (name.startsWith(query) || code.startsWith(query)) {
      score += 40;
    }

    // Each token match
    for (final token in tokens) {
      if (code.contains(token)) {
        score += 20; // Code match gets higher weight
      }
      if (name.contains(token)) {
        score += 10;
      }

      // Starts with token
      if (code.startsWith(token) || name.startsWith(token)) {
        score += 5;
      }
    }

    // Penalize longer names (prefer shorter, more specific matches)
    score -= name.length * 0.01;

    return score;
  }

  /// Generate highlighted text for display (for future rich text rendering)
  static String _getHighlightedText({
    required String name,
    required String code,
    required List<String> tokens,
  }) {
    // For now, return formatted text; can be enhanced for rich text later
    if (code.isNotEmpty) {
      return '$name ($code)';
    }
    return name;
  }

  /// Search packages with Android parity
  static List<Map<String, dynamic>> searchPackages({
    required List<Map<String, dynamic>> packages,
    required String query,
  }) {
    if (query.trim().isEmpty) return packages;

    final tokens = query.toLowerCase().trim().split(RegExp(r'\s+'));
    final results = <Map<String, dynamic>>[];

    for (final pkg in packages) {
      final name = (pkg['name'] ?? pkg['package_title'] ?? '')
          .toString()
          .toLowerCase();
      final searchText = name;

      bool allTokensMatch = true;
      for (final token in tokens) {
        if (!searchText.contains(token)) {
          allTokensMatch = false;
          break;
        }
      }

      if (allTokensMatch) {
        final matchScore = name.startsWith(query.toLowerCase()) ? 100.0 : 50.0;
        final pkgWithScore = Map<String, dynamic>.from(pkg);
        pkgWithScore['_match_score'] = matchScore;
        results.add(pkgWithScore);
      }
    }

    results.sort((a, b) {
      final scoreA = a['_match_score'] as double? ?? 0;
      final scoreB = b['_match_score'] as double? ?? 0;
      return scoreB.compareTo(scoreA);
    });

    return results;
  }

  /// Search parties
  static List<Map<String, dynamic>> searchParties({
    required List<Map<String, dynamic>> parties,
    required String query,
  }) {
    if (query.trim().isEmpty) return parties;

    final lowerQuery = query.toLowerCase();
    final results = <Map<String, dynamic>>[];

    for (final party in parties) {
      final name = (party['name'] ?? '').toString().toLowerCase();
      if (name.contains(lowerQuery)) {
        results.add(party);
      }
    }

    return results;
  }
}
