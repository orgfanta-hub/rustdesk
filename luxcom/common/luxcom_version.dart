// 럭스시스템 — 클라이언트 버전 게이트 (강제 업데이트)
// 빌드 시 apply-branding.mjs 가 flutter/lib/luxcom_version.dart 로 복사하고
// __LUX_BUILD_SERIAL__ / __LUX_VERSION_URL__ / __LUX_PROFILE__ 를 치환합니다.
//
// 동작: 앱 시작 시 version.json(405.kr 정적 파일) 1회 GET →
//   이 빌드의 serial 이 서버 minSerial 보다 작으면 전체화면 '업데이트 필요' 차단막 표시.
//   네트워크/형식 오류는 통과(fail-open) — 서버 장애로 전 클라가 막히는 사고 방지.
//   서버 부하: 정적 파일 1회 GET (Caddy file_server) = 사실상 0.
//
// 정직(보안): 클라이언트 자체 검사라 일반 사용자에겐 강제되나 우회 가능.
//   완전 차단은 RustDesk Server Pro 가 정답. — CLAUDE.md 보안 경계 참조.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher_string.dart';

const int kLuxBuildSerial = __LUX_BUILD_SERIAL__;
const String kLuxVersionUrl = '__LUX_VERSION_URL__';
const String kLuxProfile = '__LUX_PROFILE__';

const Color _kBg = Color(0xFF0D0E1C);
const Color _kCard = Color(0xFF181A30);
const Color _kBorder = Color(0xFF2A2D4D);
const Color _kSub = Color(0xFF9AA0C8);
const Color _kAccent = Color(0xFF0E8A7E);

/// 메인 창을 감싸 버전이 너무 오래되면 전체 화면을 막는 게이트. (양 프로필 공통)
class LuxComVersionGate extends StatefulWidget {
  final Widget child;
  const LuxComVersionGate({Key? key, required this.child}) : super(key: key);
  @override
  State<LuxComVersionGate> createState() => _LuxComVersionGateState();
}

class _LuxComVersionGateState extends State<LuxComVersionGate> {
  bool _blocked = false;
  String _url = 'https://405.kr/';
  String _msg = '';

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    // URL 미설정/미치환이면 검사 안 함(통과).
    if (kLuxVersionUrl.isEmpty || kLuxVersionUrl.startsWith('__')) return;
    try {
      final r = await http
          .get(Uri.parse(kLuxVersionUrl))
          .timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return; // fail-open
      final m = jsonDecode(r.body);
      if (m is! Map) return;
      final e = m[kLuxProfile];
      if (e is! Map) return;
      final min = e['minSerial'];
      if (min is! int) return;
      if (kLuxBuildSerial < min) {
        if (!mounted) return;
        setState(() {
          _blocked = true;
          if (e['url'] is String && (e['url'] as String).isNotEmpty) {
            _url = e['url'] as String;
          }
          if (e['message'] is String) _msg = e['message'] as String;
        });
      }
    } catch (_) {
      // 네트워크/파싱 일시 오류 → 통과(fail-open)
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_blocked) Positioned.fill(child: _UpdateBlocker(url: _url, msg: _msg)),
      ],
    );
  }
}

class _UpdateBlocker extends StatelessWidget {
  final String url;
  final String msg;
  const _UpdateBlocker({required this.url, required this.msg});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kBg,
      child: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 380,
            padding: const EdgeInsets.fromLTRB(30, 32, 30, 28),
            margin: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.system_update, color: _kAccent, size: 52),
                const SizedBox(height: 16),
                const Center(
                  child: Text('업데이트가 필요합니다',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    msg.isNotEmpty
                        ? msg
                        : '프로그램이 오래된 버전입니다.\n최신 버전을 받아 다시 실행해 주세요.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _kSub, fontSize: 13.5, height: 1.5),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => launchUrlString(url),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                    ),
                    child: const Text('최신 버전 받기',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15.5)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
