import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// Parses EH gallery stats HTML to JSON-friendly maps (aligned with native [EHSpiderParser.statPage2GalleryStats]).
Map<String, dynamic>? parseGalleryStatsHtml(String html) {
  final document = html_parser.parse(html);

  final totalEl = document.querySelector('.stuffbox > p > strong');
  if (totalEl == null) return null;

  int totalVisits;
  try {
    totalVisits = int.parse(totalEl.text.replaceAll(',', ''));
  } catch (_) {
    return null;
  }

  Element? rankScoreTbody = document.querySelector('.stuffbox > table > tbody');
  final graphs = document.querySelectorAll('#graphs > div');
  if (graphs.length < 3) {
    return {
      'totalVisits': totalVisits,
      'allTimeRanking': null,
      'allTimeScore': null,
      'yearRanking': null,
      'yearScore': null,
      'monthRanking': null,
      'monthScore': null,
      'dayRanking': null,
      'dayScore': null,
      'yearlyStats': <Map<String, dynamic>>[],
      'monthlyStats': <Map<String, dynamic>>[],
      'dailyStats': <Map<String, dynamic>>[],
    };
  }

  Element yearlyStatTbody = graphs[2].querySelector('table > tbody')!;
  Element monthlyStatTbody = graphs[1].querySelector('table > tbody')!;
  Element dailyStatTbody = graphs[0].querySelector('table > tbody')!;

  int? cell(Element? tbody, int tr, int td) {
    if (tbody == null) return null;
    final el = tbody.querySelector('tr:nth-child($tr) > td:nth-child($td)');
    return int.tryParse(el?.text.replaceAll(',', '') ?? '');
  }

  return {
    'totalVisits': totalVisits,
    'allTimeRanking': cell(rankScoreTbody, 2, 4),
    'allTimeScore': cell(rankScoreTbody, 2, 5),
    'yearRanking': cell(rankScoreTbody, 4, 4),
    'yearScore': cell(rankScoreTbody, 4, 5),
    'monthRanking': cell(rankScoreTbody, 6, 4),
    'monthScore': cell(rankScoreTbody, 6, 5),
    'dayRanking': cell(rankScoreTbody, 8, 4),
    'dayScore': cell(rankScoreTbody, 8, 5),
    'yearlyStats': _parseStatsTable(yearlyStatTbody),
    'monthlyStats': _parseStatsTable(monthlyStatTbody),
    'dailyStats': _parseStatsTable(dailyStatTbody),
  };
}

List<Map<String, dynamic>> _parseStatsTable(Element tbody) {
  final periods = tbody.querySelectorAll('tr:nth-child(4) > .stdk').map((e) => e.text).toList();
  final visits = tbody.querySelectorAll('tr:nth-child(6) > .stdv').map((e) => e.text).toList();
  final hits = tbody.querySelectorAll('tr:nth-child(8) > .stdv').map((e) => e.text).toList();

  double parseNumber(String s) {
    if (s.endsWith('K')) {
      return double.parse(s.substring(0, s.length - 1)) * 1000;
    }
    if (s.endsWith('M')) {
      return double.parse(s.substring(0, s.length - 1)) * 1000 * 1000;
    }
    return double.tryParse(s) ?? 0;
  }

  final n = [periods.length, visits.length, hits.length].reduce((a, b) => a < b ? a : b);
  final stats = <Map<String, dynamic>>[];
  for (var i = 0; i < n; i++) {
    stats.add({
      'period': periods[i],
      'visits': parseNumber(visits[i]),
      'hits': parseNumber(hits[i]),
    });
  }

  final beginIndex = stats.indexWhere((s) => (s['visits'] as double) > 0);
  if (beginIndex == -1) return [];
  return stats.sublist(beginIndex);
}
