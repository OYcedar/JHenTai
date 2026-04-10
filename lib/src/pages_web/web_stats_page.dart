import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';

enum _GraphSeg { allTime, year, month, day }

class WebStatsPage extends StatefulWidget {
  const WebStatsPage({super.key});

  @override
  State<WebStatsPage> createState() => _WebStatsPageState();
}

class _WebStatsPageState extends State<WebStatsPage> {
  _GraphSeg _seg = _GraphSeg.allTime;
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final gidStr = Get.parameters['gid'] ?? '';
    final token = Get.parameters['token'] ?? '';
    final gid = int.tryParse(gidStr);
    if (gid == null || token.isEmpty) {
      setState(() {
        _error = 'Invalid gallery';
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final m = await backendApiClient.fetchGalleryStats(gid, token);
      setState(() {
        _data = m;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('stats.title'.tr)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final d = _data!;
    final total = d['totalVisits'];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('stats.totalVisits'.trParams({'n': '$total'}),
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        SegmentedButton<_GraphSeg>(
          segments: [
            ButtonSegment(value: _GraphSeg.allTime, label: Text('stats.allTime'.tr)),
            ButtonSegment(value: _GraphSeg.year, label: Text('stats.year'.tr)),
            ButtonSegment(value: _GraphSeg.month, label: Text('stats.month'.tr)),
            ButtonSegment(value: _GraphSeg.day, label: Text('stats.day'.tr)),
          ],
          selected: {_seg},
          onSelectionChanged: (s) => setState(() => _seg = s.first),
        ),
        const SizedBox(height: 16),
        if (_seg == _GraphSeg.allTime) _allTimeTable(context, d) else _seriesTable(context, d),
      ],
    );
  }

  Widget _allTimeTable(BuildContext context, Map<String, dynamic> d) {
    final rows = <DataRow>[
      DataRow(cells: [
        DataCell(Text('stats.allTime'.tr)),
        DataCell(Text('${d['allTimeRanking'] ?? '—'}')),
        DataCell(Text('${d['allTimeScore'] ?? '—'}')),
      ]),
      DataRow(cells: [
        DataCell(Text('stats.year'.tr)),
        DataCell(Text('${d['yearRanking'] ?? '—'}')),
        DataCell(Text('${d['yearScore'] ?? '—'}')),
      ]),
      DataRow(cells: [
        DataCell(Text('stats.month'.tr)),
        DataCell(Text('${d['monthRanking'] ?? '—'}')),
        DataCell(Text('${d['monthScore'] ?? '—'}')),
      ]),
      DataRow(cells: [
        DataCell(Text('stats.day'.tr)),
        DataCell(Text('${d['dayRanking'] ?? '—'}')),
        DataCell(Text('${d['dayScore'] ?? '—'}')),
      ]),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          DataColumn(label: Text('stats.period'.tr)),
          DataColumn(label: Text('stats.ranking'.tr)),
          DataColumn(label: Text('stats.score'.tr)),
        ],
        rows: rows,
      ),
    );
  }

  Widget _seriesTable(BuildContext context, Map<String, dynamic> d) {
    final key = switch (_seg) {
      _GraphSeg.year => 'yearlyStats',
      _GraphSeg.month => 'monthlyStats',
      _ => 'dailyStats',
    };
    final list = (d[key] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text('stats.noSeries'.tr, style: const TextStyle(color: Colors.grey)),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          DataColumn(label: Text('stats.period'.tr)),
          DataColumn(label: Text('stats.visits'.tr)),
          DataColumn(label: Text('stats.hits'.tr)),
        ],
        rows: list
            .map((e) => DataRow(cells: [
                  DataCell(Text('${e['period'] ?? ''}')),
                  DataCell(Text(_fmtNum(e['visits']))),
                  DataCell(Text(_fmtNum(e['hits']))),
                ]))
            .toList(),
      ),
    );
  }

  String _fmtNum(dynamic v) {
    if (v is num) {
      if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
      if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K';
      return v.toStringAsFixed(0);
    }
    return '$v';
  }
}
