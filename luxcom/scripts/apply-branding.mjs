#!/usr/bin/env node
/**
 * 럭스시스템 전용 RustDesk 클라이언트 — 브랜딩/모드 패치 스크립트 (프로필 지원)
 *
 * 사용:
 *   PROFILE=consumer node apply-branding.mjs <RUSTDESK_체크아웃_경로>   # 소비자용(수신전용)
 *   PROFILE=staff    node apply-branding.mjs <RUSTDESK_체크아웃_경로>   # 사업자(기사)용(풀기능)
 *   (PROFILE 생략 시 brand.config.json 의 defaultProfile 사용)
 *
 * 동작: RustDesk 소스(+ libs/hbb_common 서브모듈)에 아래를 주입.
 *   [필수] 서버(RENDEZVOUS_SERVERS), 공개키(RS_PUB_KEY)
 *   [필수] 수신전용 프로필이면 is_incoming_only()=true (외부 제어 UI 자동 숨김)
 *   [브랜딩] APP_NAME, EXE 속성(Runner.rc), 앱 아이콘, (소비자용) 홈화면 상호·연락처
 *
 * 설계: 내용 기반 앵커(정규식). 핵심 패치 실패 시 즉시 종료(코드 1) → 잘못된 배포 방지.
 */
import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';
import { execSync } from 'node:child_process';

const here = path.dirname(url.fileURLToPath(import.meta.url));
const builderRoot = path.resolve(here, '..');
const repoDir = path.resolve(process.argv[2] || '.');
const configPath = process.env.BRAND_CONFIG || path.join(builderRoot, 'brand.config.json');
const cfg = JSON.parse(fs.readFileSync(configPath, 'utf8'));

const profileName = process.env.PROFILE || process.argv[3] || cfg.defaultProfile || 'consumer';
const prof = cfg.profiles && cfg.profiles[profileName];
if (!prof) {
  console.error(`❌ 프로필 '${profileName}' 없음. 사용 가능: ${Object.keys(cfg.profiles || {}).join(', ')}`);
  process.exit(1);
}

const report = [];
let hardFail = false;

function log(status, label, detail) {
  const tag = status === 'OK' ? 'OK  ' : status === 'SKIP' ? 'SKIP' : 'WARN';
  console.log(`[${tag}] ${label}${detail ? ' — ' + detail : ''}`);
  report.push({ status, label, detail: detail || '' });
}

function patch(relFile, label, re, replacement, { required = false } = {}) {
  const p = path.join(repoDir, relFile);
  if (!fs.existsSync(p)) {
    log('WARN', label, `파일 없음: ${relFile}`);
    if (required) hardFail = true;
    return;
  }
  const before = fs.readFileSync(p, 'utf8');
  if (!re.test(before)) {
    log(required ? 'WARN' : 'SKIP', label, `앵커 미발견(${relFile}) — RustDesk ${cfg.rustdeskTag} 구조 변경 가능`);
    if (required) hardFail = true;
    return;
  }
  const after = before.replace(re, replacement);
  if (after === before) {
    log(required ? 'WARN' : 'SKIP', label, `치환 결과 동일(${relFile})`);
    if (required) hardFail = true;
    return;
  }
  fs.writeFileSync(p, after);
  log('OK', label, relFile);
}

const CONFIG_RS = path.join('libs', 'hbb_common', 'src', 'config.rs');

console.log(`\n=== 럭스시스템 RustDesk 빌더 — 패치 시작 ===`);
console.log(`프로필    : ${profileName} (${prof._desc || ''})`);
console.log(`수신전용  : ${!!prof.receiveOnly}`);
console.log(`대상 소스 : ${repoDir}`);
console.log(`핀 버전   : ${cfg.rustdeskTag}\n`);

// ── [필수] 서버 ────────────────────────────────────────────────────
patch(
  CONFIG_RS, '서버(RENDEZVOUS_SERVERS) 주입',
  /pub const RENDEZVOUS_SERVERS:\s*&\[&str\]\s*=\s*&\[[^\]]*\];/,
  `pub const RENDEZVOUS_SERVERS: &[&str] = &["${cfg.server.idServer}"];`,
  { required: true }
);
// ── [필수] 공개키 ──────────────────────────────────────────────────
patch(
  CONFIG_RS, '공개키(RS_PUB_KEY) 주입',
  /pub const RS_PUB_KEY:\s*&str\s*=\s*"[^"]*";/,
  `pub const RS_PUB_KEY: &str = "${cfg.server.key}";`,
  { required: true }
);
// ── [필수, 소비자용] 수신 전용 ─────────────────────────────────────
if (prof.receiveOnly) {
  patch(
    CONFIG_RS, '수신전용(is_incoming_only → true)',
    /pub fn is_incoming_only\(\)\s*->\s*bool\s*\{/,
    (m) => `#[allow(unreachable_code)]\n${m}\n    return true; // [LUXCOM] 럭스시스템 수신전용 클라이언트`,
    { required: true }
  );
} else {
  log('SKIP', '수신전용 패치', '사업자(풀기능) 프로필 — 외부 제어 기능 유지');
}
// ── [브랜딩] 앱 이름 ───────────────────────────────────────────────
patch(
  CONFIG_RS, '앱 이름(APP_NAME) 리브랜딩',
  /(pub static ref APP_NAME:\s*RwLock<String>\s*=\s*RwLock::new\(")[^"]*("\.to_owned\(\)\);)/,
  `$1${prof.productName}$2`
);

// ── [브랜딩] EXE 파일 속성 ─────────────────────────────────────────
const RC = path.join('flutter', 'windows', 'runner', 'Runner.rc');
patch(RC, 'EXE 속성 ProductName',     /(VALUE "ProductName",\s*")[^"]*(")/,     `$1${prof.productName}$2`);
patch(RC, 'EXE 속성 FileDescription', /(VALUE "FileDescription",\s*")[^"]*(")/, `$1${prof.productName}$2`);
patch(RC, 'EXE 속성 CompanyName',     /(VALUE "CompanyName",\s*")[^"]*(")/,     `$1${prof.companyName}$2`);
patch(RC, 'EXE 속성 LegalCopyright',  /(VALUE "LegalCopyright",\s*")[^"]*(")/,  `$1${prof.copyright}$2`);

// ── [브랜딩] 앱 아이콘 ─────────────────────────────────────────────
(function applyIcon() {
  const label = '앱 아이콘 교체';
  const target = path.join(repoDir, 'flutter', 'windows', 'runner', 'resources', 'app_icon.ico');
  if (!fs.existsSync(path.dirname(target))) { log('SKIP', label, 'runner/resources 경로 없음'); return; }
  const icoSrc = path.join(builderRoot, cfg.logo.ico || 'assets/app_icon.ico');
  const pngSrc = path.join(builderRoot, cfg.logo.png || 'assets/logo.png');
  if (fs.existsSync(icoSrc)) {
    fs.copyFileSync(icoSrc, target);
    log('OK', label, `복사: ${path.relative(builderRoot, icoSrc)}`);
    return;
  }
  if (fs.existsSync(pngSrc)) {
    for (const bin of ['magick', 'convert']) {
      try {
        execSync(`${bin} "${pngSrc}" -define icon:auto-resize=256,128,64,48,32,16 "${target}"`, { stdio: 'ignore' });
        log('OK', label, `변환(${bin}): logo.png → app_icon.ico`);
        return;
      } catch { /* 다음 후보 */ }
    }
    log('WARN', label, 'ImageMagick 없음 → 기본 아이콘 유지. assets/app_icon.ico 를 직접 넣어주세요.');
    return;
  }
  log('SKIP', label, 'assets 에 app_icon.ico/logo.png 둘 다 없음 → 기본 아이콘 유지');
})();

// ── [브랜딩, 소비자용] 홈 화면 상호·연락처 ────────────────────────
// ── [브랜딩] 상단 'RustDesk 제공' 링크 → 우리 쇼핑몰 (common.dart loadPowered) ──
const COMMON = path.join('flutter', 'lib', 'common.dart');
if (cfg.poweredBy && cfg.poweredBy.url) {
  patch(COMMON, 'Powered-by 링크 URL', /launchUrl\(Uri\.parse\('https:\/\/rustdesk\.com'\)\);/, `launchUrl(Uri.parse('${cfg.poweredBy.url}'));`);
}
if (cfg.poweredBy && cfg.poweredBy.text) {
  patch(COMMON, "Powered-by 문구('RustDesk 제공' 교체)", /translate\("powered_by_me"\)/, `'${cfg.poweredBy.text.replace(/'/g, "\\'")}'`);
}

// ── [브랜딩] 앱 내부 로고 (flutter/assets/logo.png, loadLogo) ──
(function applyInAppLogo() {
  const label = '앱 내부 로고 교체(flutter/assets/logo.png)';
  const pngSrc = path.join(builderRoot, cfg.logo.png || 'assets/logo.png');
  const target = path.join(repoDir, 'flutter', 'assets', 'logo.png');
  if (!fs.existsSync(pngSrc)) { log('SKIP', label, 'assets/logo.png 없음(로고 미제공)'); return; }
  if (!fs.existsSync(path.dirname(target))) { log('SKIP', label, 'flutter/assets 경로 없음'); return; }
  fs.copyFileSync(pngSrc, target);
  log('OK', label, 'flutter/assets/logo.png');
})();

// ── [브랜딩] 탭바/타이틀바 아이콘 (flutter/assets/icon.png, loadIcon) ──
// loadLogo 와 별개로 loadIcon 은 assets/icon.png 를 씀(탭바 좌상단 아이콘 등). 이것도 교체.
(function applyAppIconAsset() {
  const label = '앱 아이콘 에셋 교체(flutter/assets/icon.png)';
  const pngSrc = path.join(builderRoot, cfg.logo.png || 'assets/logo.png');
  const target = path.join(repoDir, 'flutter', 'assets', 'icon.png');
  if (!fs.existsSync(pngSrc)) { log('SKIP', label, 'assets/logo.png 없음'); return; }
  if (!fs.existsSync(path.dirname(target))) { log('SKIP', label, 'flutter/assets 경로 없음'); return; }
  fs.copyFileSync(pngSrc, target);
  log('OK', label, 'flutter/assets/icon.png');
})();

// ── [RustDesk 흔적 정리] 여러 파일 일괄 치환 헬퍼 ──
function patchFiles(relFiles, label, re, replacement) {
  let cnt = 0;
  for (const rf of relFiles) {
    const p = path.join(repoDir, rf);
    if (!fs.existsSync(p)) continue;
    const before = fs.readFileSync(p, 'utf8');
    const after = before.replace(re, replacement);
    if (after !== before) { fs.writeFileSync(p, after); cnt++; }
  }
  log(cnt > 0 ? 'OK' : 'SKIP', label, cnt > 0 ? (cnt + '개 파일') : '변경 없음');
}
const DESKTOP_PAGES = [
  path.join('flutter', 'lib', 'common.dart'),
  path.join('flutter', 'lib', 'desktop', 'pages', 'desktop_setting_page.dart'),
  path.join('flutter', 'lib', 'desktop', 'pages', 'install_page.dart'),
  path.join('flutter', 'lib', 'desktop', 'pages', 'connection_page.dart'),
  path.join('flutter', 'lib', 'desktop', 'pages', 'desktop_home_page.dart'),
];

// rustdesk.com 모든 링크 → 우리 쇼핑몰 (흔적 제거)
if (cfg.poweredBy && cfg.poweredBy.url) {
  patchFiles(DESKTOP_PAGES, 'rustdesk.com 링크 → 쇼핑몰', /https:\/\/rustdesk\.com[^\s'")]*/g, cfg.poweredBy.url);
}
// About 제목 'About RustDesk' → 브랜드 정보
patch(
  path.join('flutter', 'lib', 'desktop', 'pages', 'desktop_setting_page.dart'),
  "About 제목('About RustDesk' 교체)",
  /translate\('About RustDesk'\)/,
  `'${((cfg.contact && cfg.contact.businessName) || 'LuxCom')} 정보'`
);
// 세련된 디자인: 액센트 컬러(RustDesk 파랑 0071FF) → 브랜드 컬러
if (cfg.theme && cfg.theme.accentColor) {
  const hex = cfg.theme.accentColor.replace('#', '').toUpperCase();
  patchFiles([COMMON], `액센트 컬러 → #${hex}`, /0071FF/g, hex);
}

// ── [소비자용 정리] 수신전용(incoming-only)에서 'Install(시스템 설치/UAC)' 카드 숨김 ──
// RustDesk식 UAC/설치 안내가 뜨지 않게 — 수신전용 클라엔 불필요. 사업자(staff)는 유지.
patch(
  path.join('flutter', 'lib', 'desktop', 'pages', 'desktop_home_page.dart'),
  '설치/UAC 카드 숨김(수신전용)',
  /if \(isWindows && !bind\.isDisableInstallation\(\)\) \{/,
  'if (isWindows && !bind.isDisableInstallation() && !bind.isIncomingOnly()) {'
);

// ── [소비자 편의] 수신전용: 비번 없이 '접속 시 수락' + 끄면 완전종료(접속 불가) ──
// (A) approve-mode=click 고정: 비밀번호 칸 사라지고, 접속 시 소비자에게 수락/거부 팝업.
patch(
  path.join('flutter', 'lib', 'main.dart'),
  '수신전용 승인모드(click·무비번) 고정',
  /await bind\.mainCheckConnectStatus\(\);/,
  `await bind.mainCheckConnectStatus();\n  if (bind.isIncomingOnly()) {\n    await bind.mainSetOption(key: kOptionApproveMode, value: 'click');\n  }`
);
// (B) 메인창 닫기 → 수신전용이면 트레이 숨김 대신 완전 종료(프로세스 종료=서버 중단=기사 접속 불가).
patch(
  path.join('flutter', 'lib', 'desktop', 'widgets', 'tabbar_widget.dart'),
  '수신전용 닫기=완전종료(끄면 접속 불가)',
  /mainWindowClose\(\) async => await windowManager\.hide\(\);/,
  `mainWindowClose() async {\n      if (bind.isIncomingOnly()) {\n        await windowManager.setPreventClose(false);\n        await windowManager.close();\n        return;\n      }\n      await windowManager.hide();\n    }`
);

if (prof.showContact && cfg.contact && cfg.contact.businessName) {
  const HOME = path.join('flutter', 'lib', 'desktop', 'pages', 'desktop_home_page.dart');
  const c = cfg.contact;
  const line = [c.businessName, c.phone, c.mobile].filter(Boolean).join('  |  ');
  const safe = line.replace(/"/g, '\\"');
  patch(
    HOME, '홈화면 상호·연락처 표기',
    /buildPasswordBoard\(context\),/,
    `buildPasswordBoard(context),\n        Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: SelectableText("${safe}", style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)))),`
  );
} else {
  log('SKIP', '홈화면 연락처', '이 프로필은 연락처 표기 안 함');
}

// ── [기사 로그인 게이트] staff 전용: NAS 인증서버 로그인 후에만 사용 ──
// 메인 창(DesktopTabPage)을 LuxComGate 로 감싼다. 소비자용(수신전용)은 미적용.
if (prof.requireLogin && cfg.auth && cfg.auth.loginUrl) {
  const MAIN = path.join('flutter', 'lib', 'main.dart');
  const authUrl = String(cfg.auth.loginUrl).replace(/\/+$/, '');
  // 1) 게이트 위젯 파일 복사(+ 인증 URL 치환)
  (function copyGate() {
    const label = '기사 로그인 게이트 위젯';
    const src = path.join(builderRoot, 'staff', 'luxcom_gate.dart');
    const dst = path.join(repoDir, 'flutter', 'lib', 'luxcom_gate.dart');
    if (!fs.existsSync(src)) {
      log('WARN', label, `원본 없음: ${path.relative(builderRoot, src)}`);
      hardFail = true;
      return;
    }
    const code = fs.readFileSync(src, 'utf8').replace(/__LUX_AUTH_URL__/g, authUrl);
    fs.writeFileSync(dst, code);
    log('OK', label, `flutter/lib/luxcom_gate.dart (auth=${authUrl})`);
  })();
  // 2) main.dart import 추가
  patch(
    MAIN, '로그인 게이트 import',
    /^import 'consts\.dart';/m,
    `import 'luxcom_gate.dart';\nimport 'consts.dart';`,
    { required: true }
  );
  // 3) 메인 창 home 을 게이트로 감싸기 (데스크톱 main 창에만 적용)
  patch(
    MAIN, '메인 창 로그인 게이트 적용',
    /\?\s*const DesktopTabPage\(\)/,
    `? const LuxComGate(child: DesktopTabPage())`,
    { required: true }
  );
} else {
  log('SKIP', '기사 로그인 게이트', prof.requireLogin ? 'auth.loginUrl 미설정' : '이 프로필은 로그인 불필요');
}

// ── 리포트 ─────────────────────────────────────────────────────────
const okCount = report.filter(r => r.status === 'OK').length;
const reportMd = [
  `# 럭스시스템 RustDesk 클라이언트 — 브랜딩 리포트`,
  ``,
  `- 프로필: \`${profileName}\` / 수신전용: \`${!!prof.receiveOnly}\` / 제품명: \`${prof.productName}\``,
  `- RustDesk: \`${cfg.rustdeskTag}\` / 서버: \`${cfg.server.idServer}\``,
  `- 적용 OK: ${okCount} / 전체 ${report.length}`,
  ``,
  `| 상태 | 항목 | 비고 |`,
  `|------|------|------|`,
  ...report.map(r => `| ${r.status} | ${r.label} | ${r.detail} |`),
  ``,
  hardFail ? `> ❌ 핵심 패치 실패. config.rs 구조 변경 가능 — 위 WARN 확인.` : `> ✅ 핵심 패치 정상.`,
  ``,
].join('\n');
fs.writeFileSync(path.join(repoDir, `LUXCOM_BRANDING_REPORT.${profileName}.md`), reportMd);

console.log(`\n=== 패치 완료 [${profileName}]: OK ${okCount}/${report.length} ===`);
if (hardFail) {
  console.error('❌ 핵심 패치 실패 — 빌드를 중단합니다.');
  process.exit(1);
}
console.log('✅ 핵심 패치 정상. 빌드를 계속 진행하세요.\n');
