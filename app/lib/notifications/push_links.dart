/// Where a push or a `bgoal://` link should take the user (pure, unit-tested).
library;

/// Match id from a push's data: `match_id`, else the `deep_link`.
int? matchIdFromData(Map<String, dynamic> data) {
  final id = int.tryParse('${data['match_id'] ?? ''}');
  if (id != null) return id;
  final link = data['deep_link'];
  final uri = link is String ? Uri.tryParse(link) : null;
  return uri == null ? null : matchIdFromUri(uri);
}

/// `bgoal://match/123` (where "match" is the URI host) or any `.../match/123` path.
int? matchIdFromUri(Uri uri) {
  final segments = [if (uri.scheme == 'bgoal' && uri.host.isNotEmpty) uri.host, ...uri.pathSegments];
  final i = segments.indexOf('match');
  return i >= 0 && i + 1 < segments.length ? int.tryParse(segments[i + 1]) : null;
}

/// Router redirect for links opened from outside the app.
///
/// Depending on platform and Flutter version, `bgoal://match/123` reaches the
/// router either whole or as just its path, "/123" (the "match" part is the URI host
/// and gets dropped). Both end up at /match/123. Returns null when nothing changes.
String? deepLinkRedirect(Uri uri) {
  if (uri.scheme == 'bgoal') {
    final id = matchIdFromUri(uri);
    return id == null ? '/' : '/match/$id';
  }
  final bare = RegExp(r'^/(\d+)/?$').firstMatch(uri.path);
  return bare == null ? null : '/match/${bare.group(1)}';
}
