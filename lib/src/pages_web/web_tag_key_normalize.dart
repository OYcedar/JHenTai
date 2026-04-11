/// Normalize EH tag namespace/key for matching list HTML vs `/mytags` API keys.
String webNormalizeTagNamespace(String namespace) => namespace.trim().toLowerCase();

String webNormalizeTagKeyBody(String key) {
  var s = key.trim().toLowerCase();
  s = s.replaceAll('\u3000', ' ');
  s = s.replaceAll('_', ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  if (s.startsWith('temp:')) {
    s = s.substring('temp:'.length).trimLeft();
    s = s.replaceAll(RegExp(r'\s+'), ' ');
  }
  return s;
}

/// Canonical `namespace:key` for maps (lowercase ns, spaces in key).
String webCanonicalTagMapKey(String namespace, String key) {
  return '${webNormalizeTagNamespace(namespace)}:${webNormalizeTagKeyBody(key)}';
}

/// Try these map keys when merging list tags with `/mytags` colors.
List<String> webTagMapKeyVariants(String namespace, String key) {
  final ns = webNormalizeTagNamespace(namespace);
  final body = webNormalizeTagKeyBody(key);
  final rawNs = namespace.trim();
  final rawKey = key.trim();
  return {
    webCanonicalTagMapKey(namespace, key),
    '$ns:${body.replaceAll(' ', '_')}',
    if (rawNs.isNotEmpty && rawKey.isNotEmpty) '$rawNs:$rawKey',
    '${ns}:$rawKey',
    if (body.isNotEmpty) '$ns:$body',
    if (body.isNotEmpty) '$ns:temp:$body',
    if (body.isNotEmpty) '$ns:temp:${body.replaceAll(' ', '_')}',
  }.toList();
}
