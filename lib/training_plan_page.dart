import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'exam_credentials.dart';
import 'exam_page.dart';
import 'grade_service.dart';

class TrainingPlanPage extends StatefulWidget {
  const TrainingPlanPage({super.key, required this.service});
  final GradeService service;

  @override
  State<TrainingPlanPage> createState() => TrainingPlanPageState();
}

class TrainingPlanPageState extends State<TrainingPlanPage> {
  static const _credentials = ExamCredentialStore();
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false;
  bool _courses = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) refresh();
    });
  }

  Future<void> refresh() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final service = widget.service;
    try {
      Map<String, dynamic>? data;
      if (service.hasSession) {
        try {
          data = await service.fetchTrainingPlan();
        } on LoginRequired {
          // Reuse the saved academic login below.
        }
      }
      SavedLogin? saved;
      String? loginError;
      if (data == null) {
        try {
          saved = await _credentials.read();
        } catch (_) {
          loginError = '无法读取已保存的登录信息，请手动登录';
        }
        if (saved != null) {
          try {
            await service.login(saved.account, saved.password);
            data = await service.fetchTrainingPlan();
          } on LoginRequired {
            loginError = '保存的登录信息已失效，请重新登录';
          }
        }
      }
      if (data == null && mounted) {
        data = await showDialog<Map<String, dynamic>>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AcademicLoginDialog(
            service: service,
            credentials: _credentials,
            initialAccount: saved?.account ?? '',
            initialError: loginError,
            loadData: service.fetchTrainingPlan,
          ),
        );
      }
      if (mounted && data != null) setState(() => _data = data);
    } catch (error) {
      if (mounted) {
        setState(() => _error = switch (error) {
          FormatException(:final message) => message,
          DioException() => '连接教务系统失败，请检查网络后刷新',
          _ => '获取完成计划失败，请刷新重试',
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Card(
          margin: EdgeInsets.zero,
          color: Colors.white,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              if (data == null)
                Expanded(
                  child: Center(
                    child: _busy
                        ? const Text('正在获取完成计划…')
                        : TextButton(onPressed: refresh, child: const Text('获取完成计划')),
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('学分汇总')),
                      ButtonSegment(value: true, label: Text('课程明细')),
                    ],
                    selected: {_courses},
                    onSelectionChanged: (value) => setState(() => _courses = value.single),
                  ),
                ),
                Expanded(child: _table(data)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _table(Map<String, dynamic> data) {
    final fields = _courses ? GradeService.planCourseColumns : GradeService.planSummaryColumns;
    final widths = _courses
        ? const <double>[112, 128, 220, 64, 180, 108, 94, 90]
        : const <double>[200, 88, 88, 106];
    final records = <Map>[
      ...(data[_courses ? '课程明细' : '学分汇总'] as List).whereType<Map>(),
      if (!_courses && data['学分合计'] is Map) data['学分合计'] as Map,
    ];
    if (records.isEmpty) return const Center(child: Text('暂无课程明细'));
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        key: PageStorageKey('plan-horizontal-$_courses'),
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: widths.fold<double>(0, (sum, width) => sum + width),
          height: constraints.maxHeight,
          child: Column(
            children: [
              _row(fields, widths, highlighted: true),
              Expanded(
                child: ListView.builder(
                  key: PageStorageKey('plan-vertical-$_courses'),
                  primary: false,
                  itemExtent: 56,
                  itemCount: records.length,
                  itemBuilder: (context, index) => _row(
                    [for (final field in fields) _cell(records[index][field])],
                    widths,
                    highlighted: !_courses && index == records.length - 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _cell(Object? value) => value == null || value == '' ? '—' : value.toString();

  Widget _row(List<String> values, List<double> widths, {required bool highlighted}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xffeef4fd) : Colors.white,
        border: const Border(bottom: BorderSide(color: Color(0xffe3e8ef))),
      ),
      child: SizedBox(
        height: 56,
        child: Row(children: [
          for (var i = 0; i < values.length; i++)
            SizedBox(
              width: widths[i],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  values[i],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: highlighted ? FontWeight.w700 : FontWeight.normal),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
