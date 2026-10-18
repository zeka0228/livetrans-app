import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:livetrans_app/core/api/rest_client.dart';

void main() {
  test('detail.code/message 형식의 오류 본문을 풀어 담는다 (Q-API-7)', () {
    final res = http.Response.bytes(
      utf8.encode(jsonEncode({'detail': {'code': 'E_CAPTURE_TARGET', 'message': '대상 없음'}})),
      400,
    );
    final e = ApiException.fromResponse(res);
    expect(e.code, 'E_CAPTURE_TARGET');
    expect(e.message, '대상 없음');
    expect(e.statusCode, 400);
    expect(e.toString(), 'E_CAPTURE_TARGET: 대상 없음');
  });

  test('422 처럼 detail 이 리스트면 문자열로만 남긴다', () {
    final res = http.Response(jsonEncode({'detail': [{'loc': ['body'], 'msg': 'bad'}]}), 422);
    final e = ApiException.fromResponse(res);
    expect(e.code, isNull);
    expect(e.statusCode, 422);
    expect(e.message, contains('bad'));
  });

  test('JSON 이 아니면 본문 그대로', () {
    final e = ApiException.fromResponse(http.Response('Internal Server Error', 500));
    expect(e.message, 'Internal Server Error');
    expect(e.toString(), 'HTTP 500: Internal Server Error');
  });
}
