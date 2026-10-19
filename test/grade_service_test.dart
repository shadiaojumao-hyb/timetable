import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/grade_service.dart';

void main() {
  test('exam term follows autumn and spring academic semesters', () {
    expect(GradeService.currentExamTerm(DateTime(2026, 10, 19)), '2026-2027-1');
    expect(GradeService.currentExamTerm(DateTime(2027, 1, 10)), '2026-2027-1');
    expect(GradeService.currentExamTerm(DateTime(2027, 3, 10)), '2026-2027-2');
  });
  test('exam endpoint uses Python parameters and collects all pages', () async {
    final dio = Dio();
    var pages = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          expect(request.uri.path, '/jsxsd/xsks/xsstk_list');
          expect(request.uri.queryParameters['xnxqid'], '2026-2027-1');
          expect(request.uri.queryParameters['xsfs'], 'all');
          expect(request.uri.queryParameters['sfxsbcxq'], '1');
          expect(
            request.headers['Referer'],
            endsWith('/jsxsd/framework/xsrxkz.html'),
          );
          pages++;
          expect(request.uri.queryParameters['pageNum'], '$pages');
          handler.resolve(
            Response<String>(
              requestOptions: request,
              statusCode: 200,
              data: jsonEncode({
                'code': 0,
                'data': [
                  {'kc_mc': '资源与环境遥感', 'kssj': '2026-11-03 16:10-18:00'},
                ],
                'count': 2,
              }),
            ),
          );
        },
      ),
    );
    final data = await GradeService(dio: dio).fetchExams(term: '2026-2027-1');
    expect(pages, 2);
    expect((data['data'] as List).length, 2);
    expect(data['xnxqid'], '2026-2027-1');
  });
  test(
    'login retains cookies across redirect and combines grade pages',
    () async {
      final dio = Dio();
      var pageRequests = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            final uri = request.uri;
            String body;
            var status = 200;
            var headers = <String, List<String>>{};
            if (uri.queryParameters['flag'] == 'sess') {
              body = 'abcdefgh#120';
              headers = {
                'set-cookie': ['JSESSIONID=main; Path=/; HttpOnly'],
              };
            } else if (uri.path == '/Logon.do') {
              expect(request.headers['Cookie'], contains('JSESSIONID=main'));
              expect(
                (request.data as Map)['encoded'],
                GradeService.encodeLogin(
                  'student',
                  'password',
                  'abcdefgh',
                  '120',
                ),
              );
              status = 302;
              headers = {
                'location': ['/jsxsd/home'],
                'set-cookie': ['JSESSIONID=sub; Path=/jsxsd; HttpOnly'],
              };
              body = '';
            } else if (uri.path == '/jsxsd/home') {
              expect(
                request.headers['Cookie'],
                'JSESSIONID=sub; JSESSIONID=main',
              );
              body = '<html>Welcome</html>';
            } else {
              pageRequests++;
              expect(
                request.headers['Cookie'],
                'JSESSIONID=sub; JSESSIONID=main',
              );
              expect(uri.queryParameters['pageNum'], '$pageRequests');
              body = jsonEncode({
                'code': 0,
                'data': [
                  {'kc_mc': '课程$pageRequests', 'zcjstr': '良'},
                ],
                'count': 2,
              });
            }
            handler.resolve(
              Response<String>(
                requestOptions: request,
                statusCode: status,
                data: body,
                headers: Headers.fromMap(headers),
              ),
            );
          },
        ),
      );
      final service = GradeService(dio: dio);
      await service.login('student', 'password');
      final result = await service.fetchGrades();
      expect(pageRequests, 2);
      expect((result['data'] as List).length, 2);
      expect(result['savedAt'], isNotNull);
    },
  );
  test('expired session HTML requests login', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          handler.resolve(
            Response<String>(
              requestOptions: request,
              statusCode: 200,
              data: '<html>请先登录</html>',
            ),
          );
        },
      ),
    );
    await expectLater(
      GradeService(dio: dio).fetchGrades(),
      throwsA(isA<LoginRequired>()),
    );
  });
}
