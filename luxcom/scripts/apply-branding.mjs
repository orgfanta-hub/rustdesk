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
