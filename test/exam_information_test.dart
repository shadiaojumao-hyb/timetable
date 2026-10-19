import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_app/exam_page.dart';
import 'package:my_app/exam_credentials.dart';
import 'package:my_app/grade_service.dart';

class InformationService extends GradeService {
  bool session = false;
  bool reject = false;
  bool failExams = false;
  int logins = 0;
  int queries = 0;
  @override
  bool get hasSession => session;
  @override
  Future<void> login(String account, String password) async {
    logins++;
    if (reject) throw LoginRequired();
    expect(account, 'student');
    expect(password, 'test-password');
    session = true;
  }

  @override
  Future<Map<String, dynamic>> fetchGrades() async {
    queries++;
    if (!session) throw LoginRequired();
    return {
      'data': [
        {'kc_mc': '成绩课程', 'zcjstr': '82'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchExams({String? term}) async {
    queries++;
    if (!session) throw LoginRequired();
    if (failExams) throw const FormatException('考试安排连接失败');
    return {
      'data': [
        {
          'xnxq01id': '2026-2027-1',
          'kc_mc': '资源与环境遥感',
          'kszc': '10',
          'ksxq': '2',
          'ksjc': '07-08',
          'js_mc': 'J14-121室',
          'ks_mc': '提前期末考试',
          'kssj': '2026-11-03 16:10-18:00',
        },
      ],
    };
  }
}

Future<void> openPage(
  WidgetTester tester,
  InformationService service, {
  GlobalKey<ExamPageState>? pageKey,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ExamPage(key: pageKey, service: service),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });
  testWidgets(
    'remembered login fetches both sections and reuses cache after restart',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final first = InformationService();
      await openPage(tester, first);
      expect(find.text('登录教务系统'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), 'student');
      await tester.enterText(find.byType(TextField).at(1), 'test-password');
      await tester.tap(find.byType(Checkbox));
      await tester.tap(find.text('登录并获取信息'));
      await tester.pumpAndSettle();
      expect(find.text('登录教务系统'), findsNothing);
      expect(find.text('资源与环境遥感'), findsOneWidget);
      expect(find.text('2026-11-03 16:10-18:00'), findsOneWidget);
      expect(find.text('地点：J14-121室'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect((await const ExamCredentialStore().read())?.account, 'student');
      expect(first.logins, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(examCacheKey), isNotNull);
      expect(prefs.getString(gradeCacheKey), isNotNull);
      await tester.pumpWidget(const SizedBox());
      final next = InformationService();
      final pageKey = GlobalKey<ExamPageState>();
      await openPage(tester, next, pageKey: pageKey);
      await tester.pumpAndSettle();
      expect(next.logins, 0);
      expect(next.queries, 0);
      await pageKey.currentState!.refresh();
      await tester.pumpAndSettle();
      expect(next.logins, 1);
      expect(next.queries, 2);
      expect(find.text('登录教务系统'), findsNothing);
    },
  );
  testWidgets(
    'invalid saved password prompts login and clears saved credentials',
    (tester) async {
      await const ExamCredentialStore().save(
        const SavedLogin('student', 'test-password'),
      );
      final service = InformationService()..reject = true;
      await openPage(tester, service);
      expect(find.text('登录教务系统'), findsOneWidget);
      expect(find.text('保存的登录信息已失效，请重新输入账号密码'), findsOneWidget);
      expect(await const ExamCredentialStore().read(), isNull);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'student',
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'unchecked login does not save password and failed exam refresh keeps cached schedule',
    (tester) async {
      final service = InformationService();
      final pageKey = GlobalKey<ExamPageState>();
      await openPage(tester, service, pageKey: pageKey);
      await tester.enterText(find.byType(TextField).at(0), 'student');
      await tester.enterText(find.byType(TextField).at(1), 'test-password');
      await tester.tap(find.text('登录并获取信息'));
      await tester.pumpAndSettle();
      expect(await const ExamCredentialStore().read(), isNull);
      final prefs = await SharedPreferences.getInstance();
      final oldSchedule = prefs.getString(examCacheKey);
      service.failExams = true;
      await pageKey.currentState!.refresh();
      await tester.pumpAndSettle();
      expect(find.text('资源与环境遥感'), findsOneWidget);
      expect(find.text('考试安排连接失败'), findsOneWidget);
      expect(prefs.getString(examCacheKey), oldSchedule);
      expect(jsonDecode(prefs.getString(gradeCacheKey)!)['data'], isNotEmpty);
    },
  );
}
