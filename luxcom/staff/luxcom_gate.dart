// 럭스시스템 기사용 원격관리 — 로그인 게이트 (staff 프로필 전용)
// 빌드 시 apply-branding.mjs 가 flutter/lib/luxcom_gate.dart 로 복사하고
// __LUX_AUTH_URL__ 을 brand.config.json 의 auth.loginUrl 로 치환합니다.
//
// 동작: 메인 창(DesktopTabPage)을 LuxComGate 로 감싸 로그인 후에만 사용.
//   - POST /api/login → 성공 시 session 토큰 + heartbeat 주기 수신.
//   - 실행 중 주기적으로 POST /api/heartbeat (세션 유지 = 동시접속 슬롯 점유).
//   - 재시작 시 저장된 토큰으로 POST /api/resume (비번 없이 복귀; 슬롯/만료 확인).
//   - 동시접속 초과/정지/만료/강제종료 시 서버가 거부 → 로그인 화면.
//
// 정직(보안): 클라 게이트는 사내 사용제한·감사용. 우회 가능하므로 강제 차단은
//   RustDesk Server Pro 가 정답. — CLAUDE.md 보안 경계 참조.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'models/platform_model.dart'; // bind.mainGetLocalOption / mainSetLocalOption

const String kLuxAuthUrl = '__LUX_AUTH_URL__';
const String _kTokKey = 'luxcom_session_token'; // 세션 토큰 저장 키

const Color _kBg = Color(0xFF0D0E1C);
const Color _kCard = Color(0xFF181A30);
const Color _kBorder = Color(0xFF2A2D4D);
const Color _kSub = Color(0xFF9AA0C8);
const Color _kMuted = Color(0xFF6B7099);
const Color _kAccent = Color(0xFF4F46E5);

String _getTok() { try { return bind.mainGetLocalOption(key: _kTokKey); } catch (_) { return ''; } }
Future<void> _setTok(String v) async { try { await bind.mainSetLocalOption(key: _kTokKey, value: v); } catch (_) {} }

/// 메인 창을 감싸는 게이트.
class LuxComGate extends StatefulWidget {
  final Widget child;
  const LuxComGate({Key? key, required this.child}) : super(key: key);
  @override
  State<LuxComGate> createState() => _LuxComGateState();
}

class _LuxComGateState extends State<LuxComGate> {
  bool _authed = false;
  bool _checking = true; // 시작 시 resume 확인 중
  int _hbSec = 30;
  Timer? _hb;

  @override
  void initState() {
    super.initState();
    _tryResume();
  }

  @override
  void dispose() {
    _hb?.cancel();
    super.dispose();
  }

  Future<void> _tryResume() async {
    final tok = _getTok();
    if (tok.isEmpty) {
      if (mounted) setState(() { _checking = false; _authed = false; });
      return;
    }
    try {
      final r = await http
          .post(Uri.parse('$kLuxAuthUrl/api/resume'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'session': tok}))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        try {
          final m = jsonDecode(r.body);
          if (m is Map && m['heartbeat'] is int) _hbSec = m['heartbeat'] as int;
        } catch (_) {}
        _onAuthed(tok);
        return;
      }
    } catch (_) {
      // 네트워크 일시 오류: 토큰 유지한 채 로그인 화면(수동 재시도 가능)
    }
    await _setTok('');
    if (mounted) setState(() { _checking = false; _authed = false; });
  }

  void _onAuthed(String tok) {
    _setTok(tok);
    if (mounted) setState(() { _authed = true; _checking = false; });
    _startHeartbeat();
  }

  void _startHeartbeat() {
    _hb?.cancel();
    _hb = Timer.periodic(Duration(seconds: _hbSec), (_) async {
      final tok = _getTok();
      if (tok.isEmpty) return;
      try {
        final r = await http
            .post(Uri.parse('$kLuxAuthUrl/api/heartbeat'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'session': tok}))
            .timeout(const Duration(seconds: 10));
        if (r.statusCode == 401) _revoked(); // 세션 종료/강제종료됨
      } catch (_) {
        // 일시 네트워크 오류는 무시(다음 주기 재시도)
      }
    });
  }

  void _revoked() {
    _hb?.cancel();
    _setTok('');
    if (mounted) setState(() => _authed = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: _kBg,
        body: Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: _kAccent)),
      );
    }
    if (_authed) return widget.child;
    return _LuxComLoginPage(onSuccess: (tok, hb) { _hbSec = hb; _onAuthed(tok); });
  }
}

class _LuxComLoginPage extends StatefulWidget {
  final void Function(String token, int hbSec) onSuccess;
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
    setState(() { _busy = true; _err = null; });
    try {
      final r = await http
          .post(Uri.parse('$kLuxAuthUrl/api/login'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'username': u, 'password': p}))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode == 200) {
        String tok = '';
        int hb = 30;
        try {
          final m = jsonDecode(r.body);
          if (m is Map) {
            tok = (m['session'] ?? '').toString();
            if (m['heartbeat'] is int) hb = m['heartbeat'] as int;
          }
        } catch (_) {}
        if (mounted) widget.onSuccess(tok, hb);
        return;
      }
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
      setState(() => _err = '인증 서버에 연결할 수 없습니다. 인터넷 연결을 확인하세요.');
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
                BoxShadow(color: Color(0x554F46E5), blurRadius: 40, spreadRadius: -8, offset: Offset(0, 18)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Image.asset('assets/logo.png', width: 64, height: 64,
                      errorBuilder: (_, __, ___) => const Icon(Icons.shield_outlined, color: _kAccent, size: 56)),
                ),
                const SizedBox(height: 16),
                const Center(child: Text('405 원격관리', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.3))),
                const SizedBox(height: 5),
                const Center(child: Text('인증된 기사만 사용할 수 있습니다', style: TextStyle(color: _kSub, fontSize: 13))),
                const SizedBox(height: 24),
                _field(_id, '아이디', false, onSubmit: (_) => _pwFocus.requestFocus()),
                const SizedBox(height: 10),
                _field(_pw, '비밀번호', true, focusNode: _pwFocus, onSubmit: (_) => _login()),
                if (_err != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 13),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: Color(0xFFFF8A8A), size: 16),
                      const SizedBox(width: 6),
                      Expanded(child: Text(_err!, style: const TextStyle(color: Color(0xFFFF8A8A), fontSize: 12.5))),
                    ]),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                    ),
                    child: _busy
                        ? const SizedBox(width: 21, height: 21, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                        : const Text('로그인', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15.5)),
                  ),
                ),
                const SizedBox(height: 16),
                const Center(child: Text('럭스시스템 · 계정 문의 031-393-0144', style: TextStyle(color: _kMuted, fontSize: 11.5))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, bool obscure, {FocusNode? focusNode, ValueChanged<String>? onSubmit}) {
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
        fillColor: _kBg,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF3A3D63))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _kAccent, width: 1.6)),
        disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF26284A))),
      ),
    );
  }
}
