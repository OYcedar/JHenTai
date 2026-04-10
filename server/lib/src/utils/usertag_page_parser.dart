import 'package:html/parser.dart' as html_parser;

/// Parses EH `/mytags` HTML (aligned with native [EHSpiderParser.myTagsPage2TagSetNamesAndTagSetsAndApikey]).
Map<String, dynamic> parseMyTagsPage(String html) {
  final document = html_parser.parse(html);

  final tagSets = <Map<String, dynamic>>[];
  for (final o in document.querySelectorAll('#tagset_outer > div > select > option')) {
    final v = o.attributes['value'];
    if (v == null) continue;
    final n = int.tryParse(v);
    if (n == null) continue;
    tagSets.add({'number': n, 'name': o.text.trim()});
  }

  final tagSetEnable =
      document.querySelector('#tagset_outer > div:nth-child(5) > label > input[checked=checked]') != null;
  final tagSetBg =
      document.querySelector('#tagset_outer > div:nth-child(9) > input')?.attributes['value'];

  final tags = <Map<String, dynamic>>[];
  for (final div in document.querySelectorAll('#usertags_outer > div')) {
    if (div.id == 'usertag_0') continue;
    final titleDiv = div.querySelector('div:nth-child(1) > a > div');
    if (titleDiv == null) continue;
    final pair = titleDiv.attributes['title'] ?? '';
    final idAttr = titleDiv.attributes['id'] ?? '';
    final idParts = idAttr.split('_');
    final tagId = idParts.length >= 2 ? int.tryParse(idParts[1]) : null;
    if (tagId == null) continue;

    final parts = pair.split(':');
    final namespace = parts.isNotEmpty && parts[0].isNotEmpty ? parts[0] : 'temp';
    final key = parts.length > 1 ? parts.sublist(1).join(':') : '';

    final weightStr = div.querySelector('div:nth-child(11) > input')?.attributes['value'] ?? '10';
    final weight = int.tryParse(weightStr) ?? 10;

    tags.add({
      'tagId': tagId,
      'namespace': namespace,
      'key': key,
      'watched': div.querySelector('div:nth-child(3) > label > input[checked=checked]') != null,
      'hidden': div.querySelector('div:nth-child(5) > label > input[checked=checked]') != null,
      'weight': weight,
      'tagColor': div.querySelector('div:nth-child(9) > input')?.attributes['value'] ?? '',
    });
  }

  String? apikey;
  final script = document.querySelector('#outer > script:nth-child(1)');
  if (script != null) {
    final m = RegExp(r'apikey = \"(.*)\"').firstMatch(script.text);
    apikey = m?.group(1);
  }

  return {
    'tagSets': tagSets,
    'tagSetEnable': tagSetEnable,
    'tagSetBackgroundColor': tagSetBg,
    'tags': tags,
    'apikey': apikey,
  };
}
