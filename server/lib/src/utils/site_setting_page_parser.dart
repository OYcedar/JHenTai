import 'package:html/parser.dart' as html_parser;

Map<String, dynamic> parseSiteSettingProfiles(String html) {
  final document = html_parser.parse(html);
  final profiles = document
      .querySelectorAll('#profile_form > select > option')
      .map((option) {
        final number = int.tryParse(option.attributes['value'] ?? '');
        if (number == null) return null;
        return {
          'number': number,
          'name': option.text.trim(),
          'selected': option.attributes['selected'] != null,
        };
      })
      .whereType<Map<String, dynamic>>()
      .toList();

  return {'profiles': profiles};
}
