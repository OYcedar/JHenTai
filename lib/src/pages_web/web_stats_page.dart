import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/web_scroll_to_top.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

enum _GraphSeg { allTime, year, month, day }

class _StatPoint {
  final String period;
  final int visits;
  final int hits;

  const _StatPoint({
    required this.period,
    required this.visits,
    required this.hits,
  });
}

class WebStatsPage extends StatefulWidget {
  const WebStatsPage({super.key});

  @override
  State<WebStatsPage> createState() => _WebStatsPageState();
}

class _WebStatsPageState extends State<WebStatsPage>
    with WebScrollToTopState<WebStatsPage> {
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
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: Text('common.retry'.tr),
                          onPressed: _load,
                        ),
                      ],
                    ),
                  ),
                )
              : _buildBody(context),
      floatingActionButton: buildScrollToTopFab(),
    );
  }

  Widget _buildBody(BuildContext context) {
    final d = _data!;
    final total = d['totalVisits'];
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        Text('stats.totalVisits'.trParams({'n': '$total'}),
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<_GraphSeg>(
            segments: [
              ButtonSegment(
                  value: _GraphSeg.allTime, label: Text('stats.allTime'.tr)),
              ButtonSegment(
                  value: _GraphSeg.year, label: Text('stats.year'.tr)),
              ButtonSegment(
                  value: _GraphSeg.month, label: Text('stats.month'.tr)),
              ButtonSegment(value: _GraphSeg.day, label: Text('stats.day'.tr)),
            ],
            selected: {_seg},
            onSelectionChanged: (s) => setState(() => _seg = s.first),
          ),
        ),
        const SizedBox(height: 16),
        if (_seg == _GraphSeg.allTime)
          _allTimeTable(context, d)
        else
          _seriesPanel(context, d),
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

  Widget _seriesPanel(BuildContext context, Map<String, dynamic> d) {
    final key = switch (_seg) {
      _GraphSeg.year => 'yearlyStats',
      _GraphSeg.month => 'monthlyStats',
      _ => 'dailyStats',
    };
    final list = ((d[key] as List?) ?? [])
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList();
    final points = list
        .map((e) => _StatPoint(
              period: '${e['period'] ?? ''}',
              visits: _asInt(e['visits']),
              hits: _asInt(e['hits']),
            ))
        .where((point) => point.period.isNotEmpty)
        .toList();
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text('stats.noSeries'.tr,
            style: const TextStyle(color: Colors.grey)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 340,
          child: SfCartesianChart(
            legend: const Legend(
              isVisible: true,
              position: LegendPosition.bottom,
            ),
            trackballBehavior: TrackballBehavior(
              enable: true,
              activationMode: ActivationMode.singleTap,
              tooltipSettings:
                  const InteractiveTooltip(format: 'point.x: point.y'),
            ),
            primaryXAxis: const CategoryAxis(
              majorGridLines: MajorGridLines(width: 0),
              edgeLabelPlacement: EdgeLabelPlacement.shift,
            ),
            primaryYAxis: NumericAxis(
              title: AxisTitle(text: 'stats.visits'.tr),
              numberFormat: null,
            ),
            axes: [
              NumericAxis(
                name: 'hitsAxis',
                opposedPosition: true,
                title: AxisTitle(text: 'stats.hits'.tr),
              ),
            ],
            series: [
              LineSeries<_StatPoint, String>(
                name: 'stats.visits'.tr,
                dataSource: points,
                xValueMapper: (point, _) => point.period,
                yValueMapper: (point, _) => point.visits,
                markerSettings: const MarkerSettings(isVisible: true),
              ),
              LineSeries<_StatPoint, String>(
                name: 'stats.hits'.tr,
                dataSource: points,
                xValueMapper: (point, _) => point.period,
                yValueMapper: (point, _) => point.hits,
                yAxisName: 'hitsAxis',
                markerSettings: const MarkerSettings(isVisible: true),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
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
        ),
      ],
    );
  }

  int _asInt(dynamic v) {
    if (v is num) {
      return v.toInt();
    }
    return int.tryParse('$v') ?? 0;
  }

  String _fmtNum(dynamic v) {
    if (v is num) {
      if (v >= 1e6) {
        return '${(v / 1e6).toStringAsFixed(1)}M';
      }
      if (v >= 1e3) {
        return '${(v / 1e3).toStringAsFixed(1)}K';
      }
      return v.toStringAsFixed(0);
    }
    return '$v';
  }
}
