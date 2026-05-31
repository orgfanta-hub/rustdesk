// 럭스시스템 기사용 원격관리 — 로그인 게이트 (staff 프로필 전용)
// 빌드 시 apply-branding.mjs 가 이 파일을 flutter/lib/luxcom_gate.dart 로 복사하고
// __LUX_AUTH_URL__ 을 brand.config.json 의 auth.loginUrl 로 치환합니다.
//
// 동작:
//   - 메인 창(DesktopTabPage)을 LuxComGate 로 감싸 로그인 후에만 사용 가능.
//   - 인증서버(NAS) POST /api/login {username,password} → 200 이면 통과, 401 이면 거부.
//   - 로그인 성공 시 로컬에 세션 만료시각 저장(기본 24시간) → 그 사이엔 재로그인 불필요.
//
// 주의(정직): 이 게이트는 '사내 사용 제한/감사'용입니다. 클라이언트 측 검사는
//   기술적으로 우회 가능하므로(바이너리에 네트워크 키가 포함), 강제 차단이 필요하면
//   RustDesk Server Pro(서버측 로그인 강제)가 정답입니다. — CLAUDE.md 보안 경계 참조.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'models/platform_model.dart'; // bind.mainGetLocalOption / mainSetLocalOption

const String kLuxAuthUrl = '__LUX_AUTH_URL__';
const String _kSessKey = 'luxcom_session_until'; // 세션 만료 epoch(ms) 저장 키
const int _kSessionHours = 24;

const Color _kBg = Color(0xFF0D0E1C);
const Color _kCard = Color(0xFF181A30);
const Color _kBorder = Color(0xFF2A2D4D);
const Color _kSub = Color(0xFF9AA0C8);
const Color _kMuted = Color(0xFF6B7099);
const Color _kField = Color(0xFF0D0E1C);
const Color _kAccent = Color(0xFF4F46E5);

bool luxComSessionValid() {
  try {
    final v = bind.mainGetLocalOption(key: _kSessKey);
    if (v.isEmpty) return false;
    final until = int.tryParse(v) ?? 0;
    return until > DateTime.now().millisecondsSinceEpoch;
  } catch (_) {
    return false;
  }
}

Future<void> _luxComSetSession() async {
  final until = DateTime.now()
      .add(const Duration(hours: _kSessionHours))
      .millisecondsSinceEpoch;
  try {
    await bind.mainSetLocalOption(key: _kSessKey, value: until.toString());
  } catch (_) {}
}

/// 메인 창을 감싸는 게이트. 세션이 유효하면 [child], 아니면 로그인 화면.
class LuxComGate extends StatefulWidget {
  final Widget child;
  const LuxComGate({Key? key, required this.child}) : super(key: key);
  @override
  State<LuxComGate> createState() => _LuxComGateState();
}

class _LuxComGateState extends State<LuxComGate> {
  late bool _authed;

  @override
  void initState() {
    super.initState();
    _authed = luxComSessionValid();
  }

  @override
  Widget build(BuildContext context) {
    if (_authed) return widget.child;
    return _LuxComLoginPage(onSuccess: () => setState(() => _authed = true));
  }
}

class _LuxComLoginPage extends StatefulWidget {
  final VoidCallback onSuccess;
  const _LuxComLoginPage({required this.onSuccess});
  @override
  State<_LuxComLoginPage> createState() => _LuxComLoginPageState();
}

class _LuxComLoginPageState extends State<_LuxComLoginPage> {
  final _id = TextEditingController();
  final _pw = TextEditingController();
  final _pwFocus = FocusNode();
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _id.dispose();
    _pw.dispose();
    _pwFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_busy) return;
    final u = _id.text.trim();
    final p = _pw.text;
    if (u.isEmpty || p.isEmpty) {
      setState(() => _err = '아이디와 비밀번호를 입력하세요.');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final r = await http
          .post(
            Uri.parse('$kLuxAuthUrl/api/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': u, 'password': p}),
          )
          .timeout(const Duration(seconds: 12));
      if (r.statusCode == 200) {
        await _luxComSetSession();
        if (mounted) widget.onSuccess();
        return;
      }
      // 서버가 내려준 안내문구(만료/정지/자격오류)를 그대로 표시
      String msg = '';
      try {
        final m = jsonDecode(r.body);
        if (m is Map && m['message'] is String) msg = m['message'] as String;
      } catch (_) {}
      if (msg.isEmpty) {
        msg = r.statusCode == 401
            ? '아이디 또는 비밀번호가 올바르지 않습니다.'
            : '로그인할 수 없습니다 (${r.statusCode}).';
      }
      setState(() => _err = msg);
    } catch (_) {
      setState(() =>
          _err = '인증 서버에 연결할 수 없습니다. 인터넷 연결을 확인하세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 372,
            padding: const EdgeInsets.fromLTRB(30, 34, 30, 26),
            margin: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kBorder),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x554F46E5),
                    blurRadius: 40,
                    spreadRadius: -8,
                    offset: Offset(0, 18)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Image.asset(
                    'assets/logo.png',
                    width: 64,
                    height: 64,
                    errorBuilder: (_, __, ___) => const Icon(
                        Icons.shield_outlined,
                        color: _kAccent,
                        size: 56),
                  ),
                ),
                const SizedBox(height: 16),
                const Center(
                  child: Text('LuxCom 원격관리',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3)),
                ),
                const SizedBox(height: 5),
                const Center(
                  child: Text('인증된 기사만 사용할 수 있습니다',
                      style: TextStyle(color: _kSub, fontSize: 13)),
                ),
                const SizedBox(height: 24),
                _field(_id, '아이디', false,
                    onSubmit: (_) => _pwFocus.requestFocus()),
                const SizedBox(height: 10),
                _field(_pw, '비밀번호', true,
                    focusNode: _pwFocus, onSubmit: (_) => _login()),
                if (_err != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 13),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: Color(0xFFFF8A8A), size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(_err!,
                              style: const TextStyle(
                                  color: Color(0xFFFF8A8A), fontSize: 12.5)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      disabledBackgroundColor: _kAccent.withOpacity(0.5),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13)),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 21,
                            height: 21,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.2, color: Colors.white))
                        : const Text('로그인',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 15.5)),
                  ),
                ),
                const SizedBox(height: 16),
                const Center(
                  child: Text('럭스시스템 · 계정 문의 031-393-0144',
                      style: TextStyle(color: _kMuted, fontSize: 11.5)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, bool obscure,
      {FocusNode? focusNode, ValueChanged<String>? onSubmit}) {
    return TextField(
      controller: c,
      focusNode: focusNode,
      obscureText: obscure,
      autofocus: !obscure,
      onSubmitted: onSubmit,
      enabled: !_busy,
      style: const TextStyle(color: Colors.white, fontSize: 14.5),
      cursorColor: _kAccent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _kMuted, fontSize: 14),
        filled: true,
        fillColor: _kField,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF3A3D63))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _kAccent, width: 1.6)),
        disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF26284A))),
      ),
    );
  }
}
