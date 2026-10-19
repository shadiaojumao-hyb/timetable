import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'grade_service.dart';
import 'exam_credentials.dart';

const gradeCacheKey = 'exam_grades_v1';
const examCacheKey = 'exam_times_v1';
const _cacheAccountKey = 'exam_cache_account';

class ExamPage extends StatefulWidget {
  const ExamPage({
    super.key,
    this.service,
    this.credentials = const ExamCredentialStore(),
  });
  final GradeService? service;
  final ExamCredentialStore credentials;
  @override
  State<ExamPage> createState() => ExamPageState();
}

class ExamPageState extends State<ExamPage> {
  late final GradeService _service = widget.service ?? GradeService();
  Map<String, dynamic>? _cache;
  Map<String, dynamic>? _exams;
  String? _examError;
  bool _busy = true;
  bool _expanded = false;
  String? _error;
  final _vertical = ScrollController();
  final _horizontal = ScrollController();

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in [gradeCacheKey, examCacheKey]) {
        final raw = prefs.getString(key);
        if (raw == null) continue;
        try {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          if (data['data'] is! List) throw const FormatException();
          if (key == gradeCacheKey) {
            _cache = data;
          } else {
            _exams = data;
          }
        } catch (_) {
          if (key == gradeCacheKey) {
            _error = '本地成绩无法读取，请刷新重试';
          } else {
            _examError = '本地考试安排无法读取，请刷新重试';
          }
        }
      }
    } catch (_) {
      _error = '本地缓存无法读取，请刷新重试';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    // Existing grade-only caches stay offline until the user refreshes.
    if (_cache == null && _exams == null) await refresh();
  }

  Future<void> refresh() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _examError = null;
    });
    try {
      Map<String, dynamic>? data;
      String initialAccount = '';
      String? loginError;
      if (_service.hasSession) {
        try {
          data = await _fetchInformation(_service);
        } on LoginRequired {
          /* Attempt saved login below. */
        }
      }
      if (data == null) {
        SavedLogin? saved;
        try {
          saved = await widget.credentials.read();
        } catch (_) {
          loginError = '无法读取保存的登录信息，请重新登录';
        }
        if (saved != null) {
          initialAccount = saved.account;
          try {
            await _service.login(saved.account, saved.password);
            data = {
              ...await _fetchInformation(_service),
              'account': saved.account,
            };
          } on LoginRequired {
            try {
              await widget.credentials.clear();
            } catch (_) {
              /* Manual login remains available. */
            }
            loginError = '保存的登录信息已失效，请重新输入账号密码';
          } catch (error) {
            loginError = '自动登录未完成：${_friendlyError(error)}';
          }
        }
      }
      if (data == null) {
        if (!mounted) return;
        data = await showDialog<Map<String, dynamic>>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _GradeLoginDialog(
            service: _service,
            credentials: widget.credentials,
            initialAccount: initialAccount,
            initialError: loginError,
          ),
        );
      }
      if (data != null) {
        if (!mounted) return;
        final prefs = await SharedPreferences.getInstance();
        final account = data['account'] as String?;
        if (account != null && prefs.getString(_cacheAccountKey) != account) {
          _cache = null;
          _exams = null;
          await prefs.remove(gradeCacheKey);
          await prefs.remove(examCacheKey);
          await prefs.setString(_cacheAccountKey, account);
        }
        if (!mounted) return;
        setState(() {
          _cache = data!['grades'] as Map<String, dynamic>? ?? _cache;
          _exams = data['exams'] as Map<String, dynamic>? ?? _exams;
          _error = data['gradeError'] as String?;
          _examError = data['examError'] as String?;
        });
        try {
          if (data['grades'] != null) {
            await prefs.setString(gradeCacheKey, jsonEncode(data['grades']));
          }
          if (data['exams'] != null) {
            await prefs.setString(examCacheKey, jsonEncode(data['exams']));
          }
        } catch (_) {
          _error = '已获取数据，但本地保存失败，请稍后刷新重试';
        }
      }
    } catch (error) {
      _error = _friendlyError(error);
      _examError = _friendlyError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _examTimes() {
    final rows = (_exams?['data'] as List? ?? []).whereType<Map>().toList()
      ..sort((a, b) => '${a['kssj'] ?? ''}'.compareTo('${b['kssj'] ?? ''}'));
    return Column(
      children: [
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_examError != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              _examError!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _exams == null ? '点击右上角刷新获取考试安排' : '暂无结课考试安排',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  key: const PageStorageKey('exam-times'),
                  padding: const EdgeInsets.all(12),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xfff5f8fd),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xffe3e8ef)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _value(row, 'kc_mc'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _value(row, 'kssj'),
                            style: const TextStyle(
                              color: Color(0xff2c7be5),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text('地点：${_value(row, 'js_mc')}'),
                          Text(
                            '${_value(row, 'ks_mc')} · ${_value(row, 'xnxq01id')}',
                          ),
                          Text(
                            '第${_value(row, 'kszc')}周 · 星期${_value(row, 'ksxq')} · 第${_value(row, 'ksjc')}节',
                            style: const TextStyle(
                              color: Color(0xff5f6b7a),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          if (!_expanded) ...[
            Expanded(child: _panel('考试时间', _examTimes())),
            const SizedBox(height: 12),
          ],
          Expanded(
            key: const ValueKey('exam-grades-panel'),
            child: _panel(
              '考试成绩',
              _grades(),
              action: IconButton(
                tooltip: _expanded ? '缩小' : '放大',
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded ? Icons.fullscreen_exit : Icons.fullscreen,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _panel(String title, Widget content, {Widget? action}) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xffe3e8ef)),
    ),
    child: Column(
      children: [
        SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ?action,
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(child: content),
      ],
    ),
  );

  Widget _grades() {
    final rows = (_cache?['data'] as List? ?? []).whereType<Map>().toList();
    final groups = <String, List<Map>>{};
    for (final row in rows) {
      final term =
          ['xnxqid', 'xqmc', 'xqstr']
              .map((key) => '${row[key] ?? ''}'.trim())
              .where((value) => value.isNotEmpty)
              .firstOrNull ??
          '未知学期';
      groups.putIfAbsent(term, () => []).add(row);
    }
    final terms = groups.keys.toList()..sort(_compareTerms);
    final entries = <({String term, Map? row, bool header})>[
      for (final term in terms) ...[
        (term: term, row: null, header: false),
        (term: term, row: const {}, header: true),
        for (final row in groups[term]!) (term: term, row: row, header: false),
      ],
    ];
    return Column(
      children: [
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              _error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_cache != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '共 ${rows.length} 门 · 更新于 ${_savedTime()}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Color(0xff5f6b7a)),
              ),
            ),
          ),
        Expanded(
          child: _cache == null
              ? Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('登录教务系统后查看成绩'),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _busy ? null : refresh,
                          child: const Text('登录'),
                        ),
                      ],
                    ),
                  ),
                )
              : rows.isEmpty
              ? const Center(child: Text('暂无考试成绩'))
              : LayoutBuilder(
                  builder: (context, constraints) => Scrollbar(
                    controller: _horizontal,
                    thumbVisibility: true,
                    notificationPredicate: (n) =>
                        n.metrics.axis == Axis.horizontal,
                    child: SingleChildScrollView(
                      controller: _horizontal,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: constraints.maxWidth < 1350
                            ? 1350
                            : constraints.maxWidth,
                        child: Scrollbar(
                          controller: _vertical,
                          thumbVisibility: true,
                          child: ListView.builder(
                            controller: _vertical,
                            itemExtent: 72,
                            cacheExtent: 216,
                            padding: const EdgeInsets.only(bottom: 16),
                            itemCount: entries.length,
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              if (entry.row == null) {
                                return ColoredBox(
                                  color: const Color(0xffe8f0fe),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        '${entry.term} · ${groups[entry.term]!.length} 门',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xff2c7be5),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }
                              return _gradeRow(
                                entry.row!,
                                header: entry.header,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  static const _columns = <({String label, String key, double width})>[
    (label: '课程名称', key: 'kc_mc', width: 260),
    (label: '成绩', key: 'zcjstr', width: 80),
    (label: '学分', key: 'xf', width: 70),
    (label: '绩点', key: 'jd', width: 70),
    (label: '学期', key: 'xqmc', width: 150),
    (label: '课程属性', key: 'kcsx', width: 100),
    (label: '课程性质', key: 'kcxzmc', width: 150),
    (label: '考核方式', key: 'ksfs', width: 100),
    (label: '考试性质', key: 'ksxz', width: 110),
    (label: '学时', key: 'zxs', width: 80),
    (label: '课程编号', key: 'kch', width: 180),
  ];

  Widget _gradeRow(Map row, {required bool header}) => DecoratedBox(
    decoration: BoxDecoration(
      color: header ? const Color(0xffeef4fd) : Colors.white,
      border: const Border(bottom: BorderSide(color: Color(0xffe3e8ef))),
    ),
    child: Row(
      children: [
        for (final column in _columns)
          SizedBox(
            width: column.width,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Semantics(
                header: header,
                child: Text(
                  header
                      ? column.label
                      : _value(
                          row,
                          column.key,
                          fallback: column.key == 'zcjstr'
                              ? 'zcj'
                              : column.key == 'xqmc'
                              ? 'xnxqid'
                              : null,
                        ),
                  maxLines: column.key == 'kc_mc' ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: header || column.key == 'zcjstr'
                        ? FontWeight.w700
                        : FontWeight.normal,
                    color: !header && column.key == 'zcjstr'
                        ? const Color(0xff2c7be5)
                        : null,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
  String _savedTime() => '${_cache?['savedAt'] ?? _cache?['tjsj'] ?? '—'}'
      .replaceFirst('T', ' ')
      .split('.')
      .first;

  static int _compareTerms(String a, String b) {
    if (a == b) return 0;
    if (a == '未知学期') return 1;
    if (b == '未知学期') return -1;
    final aParts = RegExp(
      r'\d+',
    ).allMatches(a).map((m) => int.parse(m[0]!)).toList();
    final bParts = RegExp(
      r'\d+',
    ).allMatches(b).map((m) => int.parse(m[0]!)).toList();
    for (var i = 0; i < aParts.length && i < bParts.length; i++) {
      final comparison = bParts[i].compareTo(aParts[i]);
      if (comparison != 0) return comparison;
    }
    return b.compareTo(a);
  }

  String _value(Map row, String key, {String? fallback}) {
    final value = row[key];
    return '${value == null || value == '' ? row[fallback] ?? '—' : value}';
  }
}

Future<Map<String, dynamic>> _fetchInformation(GradeService service) async {
  final result = <String, dynamic>{};
  try {
    result['grades'] = await service.fetchGrades();
  } on LoginRequired {
    rethrow;
  } catch (error) {
    result['gradeError'] = _friendlyError(error);
  }
  try {
    result['exams'] = await service.fetchExams();
  } on LoginRequired {
    rethrow;
  } catch (error) {
    result['examError'] = _friendlyError(error);
  }
  if (result['grades'] == null && result['exams'] == null) {
    throw FormatException('${result['gradeError']}；${result['examError']}');
  }
  return result;
}

String _friendlyError(Object error) {
  if (error is LoginRequired) return '账号或密码错误，或登录已失效，请重新登录';
  if (error is DioException) return '连接教务系统失败，请检查网络后重试';
  if (error is FormatException) return error.message;
  return '获取考试信息失败，请稍后重试';
}

class _GradeLoginDialog extends StatefulWidget {
  const _GradeLoginDialog({
    required this.service,
    required this.credentials,
    this.initialAccount = '',
    this.initialError,
  });
  final ExamCredentialStore credentials;
  final String initialAccount;
  final String? initialError;
  final GradeService service;
  @override
  State<_GradeLoginDialog> createState() => _GradeLoginDialogState();
}

class _GradeLoginDialogState extends State<_GradeLoginDialog> {
  late final _account = TextEditingController(text: widget.initialAccount);
  final _password = TextEditingController();
  bool _busy = false;
  late String? _error = widget.initialError;
  bool _remember = false;
  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_account.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = '请输入账号和密码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.login(_account.text.trim(), _password.text);
      final data = {
        ...await _fetchInformation(widget.service),
        'account': _account.text.trim(),
      };
      try {
        if (_remember) {
          await widget.credentials.save(
            SavedLogin(_account.text.trim(), _password.text),
          );
        } else {
          await widget.credentials.clear();
        }
      } catch (_) {
        if (mounted) setState(() => _error = '登录成功，但保存登录设置失败，请重试或取消勾选');
        return;
      }
      if (mounted) Navigator.pop(context, data);
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('登录教务系统'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '登录后获取成绩和结课考试安排，查询结果将保存在本机。',
                style: TextStyle(color: Color(0xff5f6b7a)),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _account,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: '账号 / 学号',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: '密码',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
              CheckboxListTile(
                value: _remember,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('保存账号密码，下次自动登录'),
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _remember = value ?? false),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? '正在获取…' : '登录并获取信息'),
        ),
      ],
    ),
  );
}
