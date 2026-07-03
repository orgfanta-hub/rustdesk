import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:ffi' hide Size; // [LUXCOM] dart:ffi 의 Size 는 숨김 — Flutter(dart:ui)의 Size 와 충돌 방지
import 'package:ffi/ffi.dart';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/animated_rotation_widget.dart';
import 'package:flutter_hbb/common/widgets/custom_password.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/connection_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/desktop/widgets/update_progress.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/plugin/ui_manager.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;
import '../widgets/button.dart';

class DesktopHomePage extends StatefulWidget {
  const DesktopHomePage({Key? key}) : super(key: key);

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

const borderColor = Color(0xFF2F65BA);

class _DesktopHomePageState extends State<DesktopHomePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final _leftPaneScrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;
  var systemError = '';
  StreamSubscription? _uniLinksSubscription;
  var svcStopped = false.obs;
  var watchIsCanScreenRecording = false;
  var watchIsProcessTrust = false;
  var watchIsInputMonitoring = false;
  var watchIsCanRecordAudio = false;
  Timer? _updateTimer;
  bool isCardClosed = false;

  final RxBool _editHover = false.obs;
  final RxBool _block = false.obs;

  final GlobalKey _childKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isIncomingOnly = bind.isIncomingOnly();
    return _buildBlock(
        child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildLeftPane(context),
        if (!isIncomingOnly) const VerticalDivider(width: 1),
        if (!isIncomingOnly) Expanded(child: buildRightPane(context)),
      ],
    ));
  }

  Widget _buildBlock({required Widget child}) {
    return buildRemoteBlock(
        block: _block, mask: true, use: canBeBlocked, child: child);
  }

  Widget buildLeftPane(BuildContext context) {
    final isIncomingOnly = bind.isIncomingOnly();
    final isOutgoingOnly = bind.isOutgoingOnly();
    // [LUXCOM] 기사(풀기능) 전용 깔끔 좌패널 — 시안(밝은 톤): 로고+설정 / 내 원격 번호+복사 / 안내
    if (!isIncomingOnly && !isOutgoingOnly) {
      return _buildLuxStaffLeftPane(context);
    }
    final children = <Widget>[
      if (!isOutgoingOnly) buildPresetPasswordWarning(),
      // [LUXCOM] powered-by(쇼핑몰 링크)·연락처 문구 제거 — 소비자 홈 정리. 버전·채널 정보는 스탠바이 카드에 표시.
      Align(
        alignment: Alignment.center,
        child: loadLogo(),
      ),
      buildTip(context),
      if (!isOutgoingOnly) buildIDBoard(context),
      if (isIncomingOnly)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.computer, size: 15),
            label: const Text('이 PC 정보', style: TextStyle(fontSize: 12.5)),
            onPressed: () => _showLuxSysInfo(context),
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 34)),
          ),
        ),
      // [LUXCOM] 소비자(수신전용)는 비밀번호 미사용(수락 방식) → 비번 칸 숨김
      if (!isOutgoingOnly && !isIncomingOnly) buildPasswordBoard(context),
      FutureBuilder<Widget>(
        future: Future.value(
            Obx(() => buildHelpCards(stateGlobal.updateUrl.value))),
        builder: (_, data) {
          if (data.hasData) {
            if (isIncomingOnly) {
              if (isInHomePage()) {
                Future.delayed(Duration(milliseconds: 300), () {
                  _updateWindowSize();
                });
              }
            }
            return data.data!;
          } else {
            return const Offstage();
          }
        },
      ),
      buildPluginEntry(),
    ];
    if (isIncomingOnly) {
      children.addAll([
        Divider(),
        OnlineStatusWidget(
          onSvcStatusChanged: () {
            if (isInHomePage()) {
              Future.delayed(Duration(milliseconds: 300), () {
                _updateWindowSize();
              });
            }
          },
        ).marginOnly(bottom: 6, right: 6),
        // [LUXCOM] 스탠바이(상주) 모드 — 켜면 무인 접속 에이전트로 상주, 끄면 제거
        const _LuxComStandbyCard().marginOnly(left: 6, right: 6, bottom: 6),
        // [LUXCOM] 버전(종료/하단) — RustDesk 베이스 + 우리 하부버전
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 12, 12),
          child: _LuxVersionFooter(),
        ),
      ]);
    }
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Container(
        width: isIncomingOnly ? 320.0 : 200.0,
        color: Theme.of(context).colorScheme.background,
        child: Stack(
          children: [
            Column(
              children: [
                SingleChildScrollView(
                  controller: _leftPaneScrollController,
                  child: Column(
                    key: _childKey,
                    children: children,
                  ),
                ),
                Expanded(child: Container())
              ],
            ),
            if (isOutgoingOnly)
              Positioned(
                bottom: 6,
                left: 12,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    child: Obx(
                      () => Icon(
                        Icons.settings,
                        color: _editHover.value
                            ? textColor
                            : Colors.grey.withOpacity(0.5),
                        size: 22,
                      ),
                    ),
                    onTap: () => {
                      if (DesktopSettingPage.tabKeys.isNotEmpty)
                        {
                          DesktopSettingPage.switch2page(
                              DesktopSettingPage.tabKeys[0])
                        }
                    },
                    onHover: (value) => _editHover.value = value,
                  ),
                ),
              )
          ],
        ),
      ),
    );
  }

  // [LUXCOM] 기사용 깔끔 좌패널 (시안): 로고 / 내 원격 번호(+설정) / 번호 복사 / 안내.
  // 비번보드·도움카드·프리셋경고 제거 → 번호 중심 단순화.
  Widget _buildLuxStaffLeftPane(BuildContext context) {
    final muted =
        Theme.of(context).textTheme.titleLarge?.color?.withOpacity(0.5);
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Container(
        width: 280,
        color: Theme.of(context).colorScheme.background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Align(alignment: Alignment.center, child: loadLogo()),
            const SizedBox(height: 10),
            buildIDBoard(context),
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 2),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('번호 복사', style: TextStyle(fontSize: 12)),
                onPressed: () {
                  Clipboard.setData(
                      ClipboardData(text: gFFI.serverModel.serverId.text));
                  showToast(translate("Copied"));
                },
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 4)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 6),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.computer, size: 14),
                label: const Text('이 PC 정보', style: TextStyle(fontSize: 12)),
                onPressed: () => _showLuxSysInfo(context),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4)),
              ),
            ),
            // [LUXCOM] 내 채널 표시(로그인 응답에서 저장한 값)
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 12),
              child: Builder(builder: (_) {
                String ch = '';
                try { ch = bind.mainGetLocalOption(key: 'luxcom-channel'); } catch (_) {}
                return Text(ch.isEmpty ? '내 채널: (미지정)' : '내 채널: $ch',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary));
              }),
            ),
            // [LUXCOM] 윈도우 공유/NAS/프린터 문제 해결 메뉴
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 10),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.build_circle_outlined, size: 14),
                label: const Text('윈도우 공유문제 해결', style: TextStyle(fontSize: 12)),
                onPressed: () => _showLuxWinFix(context),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4)),
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.only(left: 22, right: 16),
              child: Text(
                '고객이 이 번호로 접속을 요청하면\n알림이 뜹니다.',
                style: TextStyle(fontSize: 12.5, color: muted, height: 1.5),
              ),
            ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.only(left: 22, bottom: 8),
              child: _LuxVersionFooter(),
            ),
          ],
        ),
      ),
    );
  }

  // [LUXCOM] 윈도우 11 24H2/25H2 공유/NAS/프린터 문제 해결 — 적용/원상복구(관리자 권한)
  Future<void> _showLuxWinFix(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181A30),
        title: const Text('윈도우 공유 · NAS · 프린터 문제 해결',
            style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 470,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: const [
              Text('윈도우 11 24H2/25H2 업데이트 후 공유폴더·NAS·프린터 연결이 끊기는 문제를 한 번에 고칩니다. 누르면 관리자 권한(UAC) 창이 뜨니 "예"를 눌러주세요.',
                  style: TextStyle(fontSize: 13, color: Color(0xFFCDD2F0), height: 1.6)),
              SizedBox(height: 12),
              _LuxFixItem('🔓 SMB 게스트 접근 허용',
                  'NAS·공유폴더에 "게스트(비밀번호 없이)"로 접속하던 게 24H2부터 막혔습니다. 다시 허용합니다. (보안이 조금 낮아져 회사·집 내부망에서만 권장)'),
              _LuxFixItem('✍ SMB 서명 강제 해제',
                  '24H2가 통신에 "서명"을 강제해 구형 NAS·공유장비 연결이 안 되는 경우를 풉니다.'),
              _LuxFixItem('🔎 네트워크 검색 + 공유 켜기',
                  '"네트워크 검색"·"파일/프린터 공유" 방화벽을 켜고 관련 서비스를 자동 시작합니다. 다른 PC·NAS가 네트워크에 보이게 됩니다.'),
              _LuxFixItem('🖨 프린터 공유 오류 수정',
                  '공유 프린터 연결 시 나는 "0x0000011b" 오류를 해결합니다.'),
              SizedBox(height: 10),
              Text('⚠ 적용 내용은 아래 "원래대로 복구"로 되돌릴 수 있습니다. 적용 후 PC를 재부팅하면 확실합니다.',
                  style: TextStyle(fontSize: 12, color: Color(0xFFFFB366), height: 1.5)),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () { Navigator.pop(ctx); _luxRunWinFix(false).then((m) => showToast(m)); },
              child: const Text('원래대로 복구', style: TextStyle(color: Color(0xFF9AA0C8)))),
          TextButton(
              onPressed: () { Navigator.pop(ctx); _luxRunWinFix(true).then((m) => showToast(m)); },
              style: TextButton.styleFrom(backgroundColor: const Color(0xFF4F46E5)),
              child: const Text('공유 문제 해결 적용', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  buildRightPane(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ConnectionPage(),
    );
  }

  buildIDBoard(BuildContext context) {
    final model = gFFI.serverModel;
    return Container(
      margin: const EdgeInsets.only(left: 20, right: 11),
      height: 57,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Container(
            width: 2,
            decoration: const BoxDecoration(color: MyTheme.accent),
          ).marginOnly(top: 5),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 25,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          translate("ID"),
                          style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.color
                                  ?.withOpacity(0.5)),
                        ).marginOnly(top: 5),
                        // [LUXCOM] 소비자(수신전용)는 설정(⋮) 숨김 — 고객이 설정 못 들어가게
                        if (!bind.isIncomingOnly()) buildPopupMenu(context)
                      ],
                    ),
                  ),
                  Flexible(
                    child: GestureDetector(
                      onDoubleTap: () {
                        Clipboard.setData(
                            ClipboardData(text: model.serverId.text));
                        showToast(translate("Copied"));
                      },
                      child: TextFormField(
                        controller: model.serverId,
                        readOnly: true,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.only(top: 10, bottom: 10),
                        ),
                        style: TextStyle(
                          fontSize: 22,
                        ),
                      ).workaroundFreezeLinuxMint(),
                    ),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildPopupMenu(BuildContext context) {
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    RxBool hover = false.obs;
    return InkWell(
      onTap: DesktopTabPage.onAddSetting,
      child: Tooltip(
        message: translate('Settings'),
        child: Obx(
          () => CircleAvatar(
            radius: 15,
            backgroundColor: hover.value
                ? Theme.of(context).scaffoldBackgroundColor
                : Theme.of(context).colorScheme.background,
            child: Icon(
              Icons.more_vert_outlined,
              size: 20,
              color: hover.value ? textColor : textColor?.withOpacity(0.5),
            ),
          ),
        ),
      ),
      onHover: (value) => hover.value = value,
    );
  }

  buildPasswordBoard(BuildContext context) {
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(
          builder: (context, model, child) {
            return buildPasswordBoard2(context, model);
          },
        ));
  }

  buildPasswordBoard2(BuildContext context, ServerModel model) {
    RxBool refreshHover = false.obs;
    RxBool editHover = false.obs;
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    final showOneTime = model.approveMode != 'click' &&
        model.verificationMethod != kUsePermanentPassword;
    return Container(
      margin: EdgeInsets.only(left: 20.0, right: 16, top: 13, bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Container(
            width: 2,
            height: 52,
            decoration: BoxDecoration(color: MyTheme.accent),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AutoSizeText(
                    translate("One-time Password"),
                    style: TextStyle(
                        fontSize: 14, color: textColor?.withOpacity(0.5)),
                    maxLines: 1,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onDoubleTap: () {
                            if (showOneTime) {
                              Clipboard.setData(
                                  ClipboardData(text: model.serverPasswd.text));
                              showToast(translate("Copied"));
                            }
                          },
                          child: TextFormField(
                            controller: model.serverPasswd,
                            readOnly: true,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              contentPadding:
                                  EdgeInsets.only(top: 14, bottom: 10),
                            ),
                            style: TextStyle(fontSize: 15),
                          ).workaroundFreezeLinuxMint(),
                        ),
                      ),
                      if (showOneTime)
                        AnimatedRotationWidget(
                          onPressed: () => bind.mainUpdateTemporaryPassword(),
                          child: Tooltip(
                            message: translate('Refresh Password'),
                            child: Obx(() => RotatedBox(
                                quarterTurns: 2,
                                child: Icon(
                                  Icons.refresh,
                                  color: refreshHover.value
                                      ? textColor
                                      : Color(0xFFDDDDDD),
                                  size: 22,
                                ))),
                          ),
                          onHover: (value) => refreshHover.value = value,
                        ).marginOnly(right: 8, top: 4),
                      if (!bind.isDisableSettings())
                        InkWell(
                          child: Tooltip(
                            message: translate('Change Password'),
                            child: Obx(
                              () => Icon(
                                Icons.edit,
                                color: editHover.value
                                    ? textColor
                                    : Color(0xFFDDDDDD),
                                size: 22,
                              ).marginOnly(right: 8, top: 4),
                            ),
                          ),
                          onTap: () => DesktopSettingPage.switch2page(
                              SettingsTabKey.safety),
                          onHover: (value) => editHover.value = value,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  buildTip(BuildContext context) {
    final isOutgoingOnly = bind.isOutgoingOnly();
    return Padding(
      padding:
          const EdgeInsets.only(left: 20.0, right: 16, top: 16.0, bottom: 5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              if (!isOutgoingOnly)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    translate("Your Desktop"),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
            ],
          ),
          SizedBox(
            height: 10.0,
          ),
          if (!isOutgoingOnly)
            Text(
              bind.isIncomingOnly()
                  ? "아래 번호를 기사님께 알려주세요. 기사가 접속하면 \"수락\"을 누르시면 됩니다. (비밀번호 필요 없음)"
                  : translate("desk_tip"),
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (isOutgoingOnly)
            Text(
              translate("outgoing_only_desk_tip"),
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget buildHelpCards(String updateUrl) {
    if (!bind.isCustomClient() &&
        updateUrl.isNotEmpty &&
        !isCardClosed &&
        bind.mainUriPrefixSync().contains('rustdesk')) {
      final isToUpdate = (isWindows || isMacOS) && bind.mainIsInstalled();
      String btnText = isToUpdate ? 'Update' : 'Download';
      GestureTapCallback onPressed = () async {
        final Uri url = Uri.parse('https://rustdesk.com/download');
        await launchUrl(url);
      };
      if (isToUpdate) {
        onPressed = () {
          handleUpdate(updateUrl);
        };
      }
      return buildInstallCard(
          "Status",
          "${translate("new-version-of-{${bind.mainGetAppNameSync()}}-tip")} (${bind.mainGetNewVersion()}).",
          btnText,
          onPressed,
          closeButton: true,
          help: isToUpdate ? 'Changelog' : null,
          link: isToUpdate
              ? 'https://github.com/rustdesk/rustdesk/releases/tag/${bind.mainGetNewVersion()}'
              : null);
    }
    if (systemError.isNotEmpty) {
      return buildInstallCard("", systemError, "", () {});
    }

    if (isWindows && !bind.isDisableInstallation()) {
      if (!bind.mainIsInstalled()) {
        return buildInstallCard(
            "", bind.isOutgoingOnly() ? "" : "install_tip", "Install",
            () async {
          await rustDeskWinManager.closeAllSubWindows();
          bind.mainGotoInstall();
        });
      } else if (bind.mainIsInstalledLowerVersion()) {
        return buildInstallCard(
            "Status", "Your installation is lower version.", "Click to upgrade",
            () async {
          await rustDeskWinManager.closeAllSubWindows();
          bind.mainUpdateMe();
        });
      }
    } else if (isMacOS) {
      final isOutgoingOnly = bind.isOutgoingOnly();
      if (!(isOutgoingOnly || bind.mainIsCanScreenRecording(prompt: false))) {
        return buildInstallCard("Permissions", "config_screen", "Configure",
            () async {
          bind.mainIsCanScreenRecording(prompt: true);
          watchIsCanScreenRecording = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly && !bind.mainIsProcessTrusted(prompt: false)) {
        return buildInstallCard("Permissions", "config_acc", "Configure",
            () async {
          bind.mainIsProcessTrusted(prompt: true);
          watchIsProcessTrust = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!bind.mainIsCanInputMonitoring(prompt: false)) {
        return buildInstallCard("Permissions", "config_input", "Configure",
            () async {
          bind.mainIsCanInputMonitoring(prompt: true);
          watchIsInputMonitoring = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly &&
          !svcStopped.value &&
          bind.mainIsInstalled() &&
          !bind.mainIsInstalledDaemon(prompt: false)) {
        return buildInstallCard("", "install_daemon_tip", "Install", () async {
          bind.mainIsInstalledDaemon(prompt: true);
        });
      }
      //// Disable microphone configuration for macOS. We will request the permission when needed.
      // else if ((await osxCanRecordAudio() !=
      //     PermissionAuthorizeType.authorized)) {
      //   return buildInstallCard("Permissions", "config_microphone", "Configure",
      //       () async {
      //     osxRequestAudio();
      //     watchIsCanRecordAudio = true;
      //   });
      // }
    } else if (isLinux) {
      if (bind.isOutgoingOnly()) {
        return Container();
      }
      final LinuxCards = <Widget>[];
      if (bind.isSelinuxEnforcing()) {
        // Check is SELinux enforcing, but show user a tip of is SELinux enabled for simple.
        final keyShowSelinuxHelpTip = "show-selinux-help-tip";
        if (bind.mainGetLocalOption(key: keyShowSelinuxHelpTip) != 'N') {
          LinuxCards.add(buildInstallCard(
            "Warning",
            "selinux_tip",
            "",
            () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link:
                'https://rustdesk.com/docs/en/client/linux/#permissions-issue',
            closeButton: true,
            closeOption: keyShowSelinuxHelpTip,
          ));
        }
      }
      if (bind.mainCurrentIsWayland()) {
        LinuxCards.add(buildInstallCard(
            "Warning", "wayland_experiment_tip", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://rustdesk.com/docs/en/client/linux/#x11-required'));
      } else if (bind.mainIsLoginWayland()) {
        LinuxCards.add(buildInstallCard("Warning",
            "Login screen using Wayland is not supported", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://rustdesk.com/docs/en/client/linux/#login-screen'));
      }
      if (LinuxCards.isNotEmpty) {
        return Column(
          children: LinuxCards,
        );
      }
    }
    if (bind.isIncomingOnly()) {
      return Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton(
          onPressed: () {
            SystemNavigator.pop(); // Close the application
            // https://github.com/flutter/flutter/issues/66631
            if (isWindows) {
              exit(0);
            }
          },
          child: Text(translate('Quit')),
        ),
      ).marginAll(14);
    }
    return Container();
  }

  Widget buildInstallCard(String title, String content, String btnText,
      GestureTapCallback onPressed,
      {double marginTop = 20.0,
      String? help,
      String? link,
      bool? closeButton,
      String? closeOption}) {
    if (bind.mainGetBuildinOption(key: kOptionHideHelpCards) == 'Y' &&
        content != 'install_daemon_tip') {
      return const SizedBox();
    }
    void closeCard() async {
      if (closeOption != null) {
        await bind.mainSetLocalOption(key: closeOption, value: 'N');
        if (bind.mainGetLocalOption(key: closeOption) == 'N') {
          setState(() {
            isCardClosed = true;
          });
        }
      } else {
        setState(() {
          isCardClosed = true;
        });
      }
    }

    return Stack(
      children: [
        Container(
          margin: EdgeInsets.fromLTRB(
              0, marginTop, 0, bind.isIncomingOnly() ? marginTop : 0),
          child: Container(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color.fromARGB(255, 226, 66, 188),
                  Color.fromARGB(255, 244, 114, 124),
                ],
              )),
              padding: EdgeInsets.all(20),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: (title.isNotEmpty
                          ? <Widget>[
                              Center(
                                  child: Text(
                                translate(title),
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15),
                              ).marginOnly(bottom: 6)),
                            ]
                          : <Widget>[]) +
                      <Widget>[
                        if (content.isNotEmpty)
                          Text(
                            translate(content),
                            style: TextStyle(
                                height: 1.5,
                                color: Colors.white,
                                fontWeight: FontWeight.normal,
                                fontSize: 13),
                          ).marginOnly(bottom: 20)
                      ] +
                      (btnText.isNotEmpty
                          ? <Widget>[
                              Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    FixedWidthButton(
                                      width: 150,
                                      padding: 8,
                                      isOutline: true,
                                      text: translate(btnText),
                                      textColor: Colors.white,
                                      borderColor: Colors.white,
                                      textSize: 20,
                                      radius: 10,
                                      onTap: onPressed,
                                    )
                                  ])
                            ]
                          : <Widget>[]) +
                      (help != null
                          ? <Widget>[
                              Center(
                                  child: InkWell(
                                      onTap: () async =>
                                          await launchUrl(Uri.parse(link!)),
                                      child: Text(
                                        translate(help),
                                        style: TextStyle(
                                            decoration:
                                                TextDecoration.underline,
                                            color: Colors.white,
                                            fontSize: 12),
                                      )).marginOnly(top: 6)),
                            ]
                          : <Widget>[]))),
        ),
        if (closeButton != null && closeButton == true)
          Positioned(
            top: 18,
            right: 0,
            child: IconButton(
              icon: Icon(
                Icons.close,
                color: Colors.white,
                size: 20,
              ),
              onPressed: closeCard,
            ),
          ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _updateTimer = periodic_immediate(const Duration(seconds: 1), () async {
      await gFFI.serverModel.fetchID();
      final error = await bind.mainGetError();
      if (systemError != error) {
        systemError = error;
        setState(() {});
      }
      final v = await mainGetBoolOption(kOptionStopService);
      if (v != svcStopped.value) {
        svcStopped.value = v;
        setState(() {});
      }
      if (watchIsCanScreenRecording) {
        if (bind.mainIsCanScreenRecording(prompt: false)) {
          watchIsCanScreenRecording = false;
          setState(() {});
        }
      }
      if (watchIsProcessTrust) {
        if (bind.mainIsProcessTrusted(prompt: false)) {
          watchIsProcessTrust = false;
          setState(() {});
        }
      }
      if (watchIsInputMonitoring) {
        if (bind.mainIsCanInputMonitoring(prompt: false)) {
          watchIsInputMonitoring = false;
          // Do not notify for now.
          // Monitoring may not take effect until the process is restarted.
          // rustDeskWinManager.call(
          //     WindowType.RemoteDesktop, kWindowDisableGrabKeyboard, '');
          setState(() {});
        }
      }
      if (watchIsCanRecordAudio) {
        if (isMacOS) {
          Future.microtask(() async {
            if ((await osxCanRecordAudio() ==
                PermissionAuthorizeType.authorized)) {
              watchIsCanRecordAudio = false;
              setState(() {});
            }
          });
        } else {
          watchIsCanRecordAudio = false;
          setState(() {});
        }
      }
    });
    Get.put<RxBool>(svcStopped, tag: 'stop-service');
    rustDeskWinManager.registerActiveWindowListener(onActiveWindowChanged);

    screenToMap(window_size.Screen screen) => {
          'frame': {
            'l': screen.frame.left,
            't': screen.frame.top,
            'r': screen.frame.right,
            'b': screen.frame.bottom,
          },
          'visibleFrame': {
            'l': screen.visibleFrame.left,
            't': screen.visibleFrame.top,
            'r': screen.visibleFrame.right,
            'b': screen.visibleFrame.bottom,
          },
          'scaleFactor': screen.scaleFactor,
        };

    bool isChattyMethod(String methodName) {
      switch (methodName) {
        case kWindowBumpMouse: return true;
      }

      return false;
    }

    rustDeskWinManager.setMethodHandler((call, fromWindowId) async {
      if (!isChattyMethod(call.method)) {
        debugPrint(
          "[Main] call ${call.method} with args ${call.arguments} from window $fromWindowId");
      }
      if (call.method == kWindowMainWindowOnTop) {
        windowOnTop(null);
      } else if (call.method == kWindowRefreshCurrentUser) {
        gFFI.userModel.refreshCurrentUser();
      } else if (call.method == kWindowGetWindowInfo) {
        final screen = (await window_size.getWindowInfo()).screen;
        if (screen == null) {
          return '';
        } else {
          return jsonEncode(screenToMap(screen));
        }
      } else if (call.method == kWindowGetScreenList) {
        return jsonEncode(
            (await window_size.getScreenList()).map(screenToMap).toList());
      } else if (call.method == kWindowActionRebuild) {
        reloadCurrentWindow();
      } else if (call.method == kWindowEventShow) {
        await rustDeskWinManager.registerActiveWindow(call.arguments["id"]);
      } else if (call.method == kWindowEventHide) {
        await rustDeskWinManager.unregisterActiveWindow(call.arguments['id']);
      } else if (call.method == kWindowConnect) {
        await connectMainDesktop(
          call.arguments['id'],
          isFileTransfer: call.arguments['isFileTransfer'],
          isViewCamera: call.arguments['isViewCamera'],
          isTerminal: call.arguments['isTerminal'],
          isTcpTunneling: call.arguments['isTcpTunneling'],
          isRDP: call.arguments['isRDP'],
          password: call.arguments['password'],
          forceRelay: call.arguments['forceRelay'],
          connToken: call.arguments['connToken'],
        );
      } else if (call.method == kWindowBumpMouse) {
        return RdPlatformChannel.instance.bumpMouse(
          dx: call.arguments['dx'],
          dy: call.arguments['dy']);
      } else if (call.method == kWindowEventMoveTabToNewWindow) {
        final args = call.arguments.split(',');
        int? windowId;
        try {
          windowId = int.parse(args[0]);
        } catch (e) {
          debugPrint("Failed to parse window id '${call.arguments}': $e");
        }
        WindowType? windowType;
        try {
          windowType = WindowType.values.byName(args[3]);
        } catch (e) {
          debugPrint("Failed to parse window type '${call.arguments}': $e");
        }
        if (windowId != null && windowType != null) {
          await rustDeskWinManager.moveTabToNewWindow(
              windowId, args[1], args[2], windowType);
        }
      } else if (call.method == kWindowEventOpenMonitorSession) {
        final args = jsonDecode(call.arguments);
        final windowId = args['window_id'] as int;
        final peerId = args['peer_id'] as String;
        final display = args['display'] as int;
        final displayCount = args['display_count'] as int;
        final windowType = args['window_type'] as int;
        final screenRect = parseParamScreenRect(args);
        await rustDeskWinManager.openMonitorSession(
            windowId, peerId, display, displayCount, screenRect, windowType);
      } else if (call.method == kWindowEventRemoteWindowCoords) {
        final windowId = int.tryParse(call.arguments);
        if (windowId != null) {
          return jsonEncode(
              await rustDeskWinManager.getOtherRemoteWindowCoords(windowId));
        }
      }
    });
    _uniLinksSubscription = listenUniLinks();

    if (bind.isIncomingOnly()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateWindowSize();
      });
    }
    WidgetsBinding.instance.addObserver(this);
  }

  _updateWindowSize() {
    RenderObject? renderObject = _childKey.currentContext?.findRenderObject();
    if (renderObject == null) {
      return;
    }
    if (renderObject is RenderBox) {
      final size = renderObject.size;
      if (size != imcomingOnlyHomeSize) {
        imcomingOnlyHomeSize = size;
        windowManager.setSize(getIncomingOnlyHomeSize());
      }
    }
  }

  @override
  void dispose() {
    _uniLinksSubscription?.cancel();
    Get.delete<RxBool>(tag: 'stop-service');
    _updateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      shouldBeBlocked(_block, canBeBlocked);
    }
  }

  Widget buildPluginEntry() {
    final entries = PluginUiManager.instance.entries.entries;
    return Offstage(
      offstage: entries.isEmpty,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...entries.map((entry) {
            return entry.value;
          })
        ],
      ),
    );
  }
}

void setPasswordDialog({VoidCallback? notEmptyCallback}) async {
  final pw = await bind.mainGetPermanentPassword();
  final p0 = TextEditingController(text: pw);
  final p1 = TextEditingController(text: pw);
  var errMsg0 = "";
  var errMsg1 = "";
  final RxString rxPass = pw.trim().obs;
  final rules = [
    DigitValidationRule(),
    UppercaseValidationRule(),
    LowercaseValidationRule(),
    // SpecialCharacterValidationRule(),
    MinCharactersValidationRule(8),
  ];
  final maxLength = bind.mainMaxEncryptLen();

  gFFI.dialogManager.show((setState, close, context) {
    submit() {
      setState(() {
        errMsg0 = "";
        errMsg1 = "";
      });
      final pass = p0.text.trim();
      if (pass.isNotEmpty) {
        final Iterable violations = rules.where((r) => !r.validate(pass));
        if (violations.isNotEmpty) {
          setState(() {
            errMsg0 =
                '${translate('Prompt')}: ${violations.map((r) => r.name).join(', ')}';
          });
          return;
        }
      }
      if (p1.text.trim() != pass) {
        setState(() {
          errMsg1 =
              '${translate('Prompt')}: ${translate("The confirmation is not identical.")}';
        });
        return;
      }
      bind.mainSetPermanentPassword(password: pass);
      if (pass.isNotEmpty) {
        notEmptyCallback?.call();
      }
      close();
    }

    return CustomAlertDialog(
      title: Text(translate("Set Password")),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              height: 8.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Password'),
                        errorText: errMsg0.isNotEmpty ? errMsg0 : null),
                    controller: p0,
                    autofocus: true,
                    onChanged: (value) {
                      rxPass.value = value.trim();
                      setState(() {
                        errMsg0 = '';
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: PasswordStrengthIndicator(password: rxPass)),
              ],
            ).marginSymmetric(vertical: 8),
            const SizedBox(
              height: 8.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Confirmation'),
                        errorText: errMsg1.isNotEmpty ? errMsg1 : null),
                    controller: p1,
                    onChanged: (value) {
                      setState(() {
                        errMsg1 = '';
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            const SizedBox(
              height: 8.0,
            ),
            Obx(() => Wrap(
                  runSpacing: 8,
                  spacing: 4,
                  children: rules.map((e) {
                    var checked = e.validate(rxPass.value.trim());
                    return Chip(
                        label: Text(
                          e.name,
                          style: TextStyle(
                              color: checked
                                  ? const Color(0xFF0A9471)
                                  : Color.fromARGB(255, 198, 86, 157)),
                        ),
                        backgroundColor: checked
                            ? const Color(0xFFD0F7ED)
                            : Color.fromARGB(255, 247, 205, 232));
                  }).toList(),
                ))
          ],
        ),
      ),
      actions: [
        dialogButton("Cancel", onPressed: close, isOutline: true),
        dialogButton("OK", onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}

// ─────────────────────────────────────────────────────────────────────
// [LUXCOM] 스탠바이(상주) 모드 카드 — 소비자(수신전용) 클라 전용.
//  ON  : 고정 비밀번호 + 자동수락(무비번 승인창 없음) + 서비스 설치(재부팅에도 자동 시작)
//        → 기사가 PC 이름·비밀번호로 "언제든" 무인 접속.
//  OFF : 상주 해제 + 비밀번호 삭제 + 설치 제거 → 다시 "번호 + 수락" 일회성 방식.
//  플래그 'luxcom-standby'='Y' 는 main.dart 시작 시 승인모드 강제(click) 를 건너뛰는 가드로도 쓰임.
// ─────────────────────────────────────────────────────────────────────
class _LuxComStandbyCard extends StatefulWidget {
  const _LuxComStandbyCard();
  @override
  State<_LuxComStandbyCard> createState() => _LuxComStandbyCardState();
}

class _LuxComStandbyCardState extends State<_LuxComStandbyCard> {
  static const _accent = Color(0xFF4F46E5);

  bool get _on => bind.mainGetOptionSync(key: 'luxcom-standby') == 'Y';
  String get _pcName => bind.mainGetOptionSync(key: 'luxcom-standby-name');

  // [LUXCOM] 앱 실행 중(채널 지정 시) 채널·번호·PC명을 luxauth 에 주기 보고 → 기사 앱 목록에 표시.
  static const String _luxAuthBase = 'https://405.kr/luxauth';
  Timer? _presenceTimer;
  String _version = '';
  String _myId = ''; // 종료 시 offline 통지에 쓸 내 번호 캐시

  @override
  void initState() {
    super.initState();
    _ensureChannelFromFilename();
    bind.mainGetVersion().then((v) {
      if (mounted) setState(() => _version = v);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportPresence());
    _presenceTimer =
        // [LUXCOM] 5s 보고 → 기사 대기목록 실시간성↑ (서버 PRESENCE_MS=16s 와 한 쌍).
        Timer.periodic(const Duration(seconds: 5), (_) => _reportPresence());
  }

  @override
  void dispose() {
    _presenceTimer?.cancel();
    _reportOffline(); // 종료 시 즉시 오프라인 통지(best-effort) → 기사 목록서 바로 사라짐
    super.dispose();
  }

  // 종료/이탈/스탠바이끄기 시 즉시 오프라인 통지(채널+번호) → 기사 목록에서 바로 제거.
  Future<void> _reportOffline() async {
    try {
      final channel = bind.mainGetOptionSync(key: 'luxcom-channel').trim();
      var id = _myId;
      if (id.isEmpty) id = (await bind.mainGetMyId()).replaceAll(' ', '');
      if (channel.isEmpty || id.isEmpty) return;
      await http
          .post(Uri.parse('$_luxAuthBase/api/offline'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'channel': channel, 'id': id}))
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  // 파일명(remote-0010c.exe)에서 채널 번호를 한 번 읽어 옵션에 저장(설치 후에도 유지).
  Future<void> _ensureChannelFromFilename() async {
    try {
      // 사용자가 채널을 직접 지정(변경)했으면 파일명으로 덮어쓰지 않음 — 수동 우선.
      if (bind.mainGetOptionSync(key: 'luxcom-channel-manual') == 'Y') return;
      // 포터블 exe 는 임시폴더에 풀려 실행 → resolvedExecutable 은 원본 파일명이 아님.
      // 포터블 런처(libs/portable execute())가 원본 파일명을 RUSTDESK_APPNAME 환경변수로 전달.
      var base = (Platform.environment['RUSTDESK_APPNAME'] ?? '').trim();
      if (base.isEmpty) {
        base = Platform.resolvedExecutable.split(Platform.pathSeparator).last;
      }
      final m = RegExp(r'remote[-_]?(\d+)c', caseSensitive: false)
          .firstMatch(base);
      if (m != null) {
        final ch = int.parse(m.group(1)!).toString(); // 0010 → 10
        await bind.mainSetOption(key: 'luxcom-channel', value: ch);
        if (mounted) setState(() {});
        _reportPresence(); // 채널 잡히면 즉시 보고(30초 안 기다림)
      }
    } catch (_) {}
  }

  Future<void> _reportPresence() async {
    try {
      // [LUXCOM] 앱이 열려 있고 채널이 지정돼 있으면 보고(스탠바이 ON 아니어도) → 기사 목록에 노출.
      //   스탠바이는 '무인 자동수락' 여부일 뿐, 목록 노출 조건이 아님.
      final channel = bind.mainGetOptionSync(key: 'luxcom-channel').trim();
      if (channel.isEmpty) return;
      final id = (await bind.mainGetMyId()).replaceAll(' ', '');
      if (id.isEmpty) return;
      _myId = id;
      var name = bind.mainGetOptionSync(key: 'luxcom-standby-name').trim();
      if (name.isEmpty) {
        try {
          name = Platform.localHostname;
        } catch (_) {}
      }
      final lan = await _luxLanIp();
      final r = await http
          .post(Uri.parse('$_luxAuthBase/api/presence'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(
                  {'channel': channel, 'id': id, 'name': name, 'standby': _on, 'lan_ip': lan}))
          .timeout(const Duration(seconds: 10));
      // 기사가 보낸 원격 명령(예: 스탠바이 해제) 수신 → 처리
      try {
        final m = jsonDecode(r.body);
        if (m is Map && m['cmd'] is String && (m['cmd'] as String).isNotEmpty) {
          await _luxHandleCmd(m['cmd'] as String);
        }
      } catch (_) {}
    } catch (_) {}
  }

  // 로컬 사설 IPv4(내부IP) — presence 에 보고해 기사 고객리스트에 표시(3번)
  Future<String> _luxLanIp() async {
    try {
      final ifs = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
      for (final itf in ifs) {
        for (final a in itf.addresses) {
          final ip = a.address;
          if (ip.startsWith('192.168.') || ip.startsWith('10.') ||
              RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip)) return ip;
        }
      }
    } catch (_) {}
    return '';
  }

  // [LUXCOM] 재부팅 자동시작 — HKCU\Run 등록(관리자 권한 불필요, 설치/서비스 아님)
  Future<void> _luxSetAutostart(bool on) async {
    if (!Platform.isWindows) return;
    const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
    try {
      if (on) {
        await Process.run('reg', [
          'add', key, '/v', 'LuxComStandby', '/t', 'REG_SZ',
          '/d', Platform.resolvedExecutable, '/f'
        ]);
      } else {
        await Process.run('reg', ['delete', key, '/v', 'LuxComStandby', '/f']);
      }
    } catch (_) {}
  }

  // [LUXCOM] 시계 옆 트레이 아이콘 — 같은 exe 를 --tray 로 띄움(설치 무관, start_tray). 실패 시 조용히 무시.
  Future<void> _luxSpawnTray() async {
    if (!Platform.isWindows) return;
    try {
      await Process.start(Platform.resolvedExecutable, ['--tray'],
          mode: ProcessStartMode.detached);
    } catch (_) {}
  }

  // 기사 원격 명령 처리(presence 응답 cmd) — 2번: 스탠바이 원격 해제
  Future<void> _luxHandleCmd(String cmd) async {
    if (cmd == 'standby-off' && _on) {
      await _reportOffline();
      await bind.mainSetOption(key: 'luxcom-standby', value: '');
      await bind.mainSetOption(key: 'luxcom-standby-name', value: '');
      await bind.mainSetPermanentPassword(password: '');
      await bind.mainSetOption(key: 'approve-mode', value: 'click');
      await bind.mainSetOption(key: 'verification-method', value: '');
      await _luxSetAutostart(false); // [LUXCOM] 설치 안 했으니 자동시작만 해제(uninstall 불필요)
      if (mounted) setState(() {});
      try { await windowManager.show(); await windowManager.focus(); } catch (_) {}
    }
  }

  // [LUXCOM] 채널 직접 변경 — 기사님이 알려준 채널로(파일명 무관, 수동 우선).
  void _changeChannel() {
    final ctrl = TextEditingController(
        text: bind.mainGetOptionSync(key: 'luxcom-channel'));
    String err = '';
    gFFI.dialogManager.show((setDlg, close, context) {
      submit() async {
        final ch = ctrl.text.trim();
        if (!RegExp(r'^\d{1,6}$').hasMatch(ch)) {
          setDlg(() => err = '채널 번호(숫자)를 입력하세요.');
          return;
        }
        final norm = int.parse(ch).toString(); // 0010 → 10
        await bind.mainSetOption(key: 'luxcom-channel', value: norm);
        await bind.mainSetOption(key: 'luxcom-channel-manual', value: 'Y');
        close();
        if (mounted) setState(() {});
        _reportPresence();
      }

      return CustomAlertDialog(
        title: const Text('채널 변경',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('기사님이 알려준 채널 번호를 입력하세요.',
                  style: TextStyle(fontSize: 12, height: 1.4)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(
                  hintText: '예: 10',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (err.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(err,
                      style: const TextStyle(color: Colors.red, fontSize: 12)),
                ),
            ],
          ),
        ),
        actions: [
          dialogButton('취소', onPressed: close, isOutline: true),
          dialogButton('저장', onPressed: submit),
        ],
        onSubmit: submit,
        onCancel: close,
      );
    });
  }

  void _enable() {
    final nameCtrl = TextEditingController(text: _pcName);
    final pwCtrl = TextEditingController();
    String err = '';
    bool obscure = true;
    gFFI.dialogManager.show((setDlg, close, context) {
      submit() async {
        final name = nameCtrl.text.trim();
        final pw = pwCtrl.text;
        if (name.isEmpty) {
          setDlg(() => err = 'PC 이름을 입력하세요.');
          return;
        }
        if (pw.length < 6) {
          setDlg(() => err = '비밀번호는 6자 이상이어야 합니다.');
          return;
        }
        close();
        // 무인 접속 설정: 고정 비밀번호 + 자동 수락(승인창 없음)
        await bind.mainSetPermanentPassword(password: pw);
        await bind.mainSetOption(
            key: 'verification-method', value: 'use-permanent-password');
        await bind.mainSetOption(key: 'approve-mode', value: 'password');
        await bind.mainSetOption(key: 'luxcom-standby-name', value: name);
        await bind.mainSetOption(key: 'luxcom-standby', value: 'Y');
        if (mounted) setState(() {});
        // [LUXCOM] 스탠바이 = '설치'하지 않는다(핵심 수정).
        //   기존엔 installInstallMe(설치)가 현재 프로세스를 죽이고 설치본을 재시작 → 사장님이 본
        //   "고객 클라가 종료됨"의 원인. 대신 현재 프로세스를 그대로 백그라운드 상주(창만 숨김 →
        //   접속은 계속 대기), 재부팅 자동시작은 HKCU\Run 으로 가볍게(관리자 권한·UAC 불필요).
        await _luxSetAutostart(true); // 재부팅 자동시작
        await _luxSpawnTray();        // 시계 옆 트레이 아이콘(#3)
        try {
          await windowManager.hide(); // 창 숨김 → 작업표시줄에서도 사라짐. 프로세스는 유지.
        } catch (_) {}
      }

      return CustomAlertDialog(
        title: const Text('스탠바이 모드 켜기',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '이 PC를 상주 등록하면 기사가 번호 없이\n언제든 접속할 수 있어요.\n재부팅해도 자동으로 다시 대기합니다.',
                style: TextStyle(fontSize: 12, height: 1.45),
              ),
              const SizedBox(height: 16),
              const Text('이 PC 이름',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 5),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  hintText: '예: 안방 컴퓨터',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              const Text('접속 비밀번호 (6자 이상)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 5),
              TextField(
                controller: pwCtrl,
                obscureText: obscure,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: '기사에게 알려줄 비밀번호',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: Icon(
                        obscure ? Icons.visibility_off : Icons.visibility,
                        size: 18),
                    onPressed: () => setDlg(() => obscure = !obscure),
                  ),
                ),
              ),
              if (err.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(err,
                      style: const TextStyle(color: Colors.red, fontSize: 12)),
                ),
              const SizedBox(height: 12),
              const Text(
                '※ 켜면 창이 사라지고 시계 옆 트레이 아이콘으로 대기합니다.\n   (설치·권한 창 없음 · 재부팅해도 자동으로 다시 대기)',
                style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          dialogButton('취소', onPressed: close, isOutline: true),
          dialogButton('켜기', onPressed: submit),
        ],
        onSubmit: submit,
        onCancel: close,
      );
    });
  }

  void _disable() {
    gFFI.dialogManager.show((setDlg, close, context) {
      doDisable() async {
        close();
        await _reportOffline(); // [LUXCOM] 끄는 즉시 기사 대기목록에서 제거(이전 이력 삭제)
        // 무인 접속 해제 → 일회성(수락) 방식으로 복귀
        await bind.mainSetOption(key: 'luxcom-standby', value: '');
        await bind.mainSetOption(key: 'luxcom-standby-name', value: ''); // 이전 이름(이력) 제거
        await bind.mainSetPermanentPassword(password: '');
        await bind.mainSetOption(key: 'approve-mode', value: 'click');
        await bind.mainSetOption(key: 'verification-method', value: '');
        if (mounted) setState(() {});
        // [LUXCOM] 설치를 안 했으니 제거(uninstall·UAC)도 없음 — 자동시작만 해제하고 창 복원.
        await _luxSetAutostart(false);
        try {
          await windowManager.show();
          await windowManager.focus();
        } catch (_) {}
      }

      return CustomAlertDialog(
        title: const Text('스탠바이 모드 끄기',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: double.maxFinite,
          child: Text(
            '상주 등록을 해제합니다.\n이후 기사는 자동으로 접속할 수 없으며,\n다시 "번호 + 수락" 방식으로 돌아갑니다.\n\n끄는 중 Windows 권한 창이 뜨면 "예"를 눌러주세요.',
            style: const TextStyle(fontSize: 12.5, height: 1.5),
          ),
        ),
        actions: [
          dialogButton('취소', onPressed: close, isOutline: true),
          dialogButton('끄기 (제거)', onPressed: doDisable),
        ],
        onCancel: close,
      );
    });
  }

  void _viewPassword() async {
    final pw = await bind.mainGetPermanentPassword();
    gFFI.dialogManager.show((setDlg, close, context) => CustomAlertDialog(
          title: const Text('접속 비밀번호',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: double.maxFinite,
            child: SelectableText(
              pw.isEmpty ? '(미설정)' : pw,
              style: const TextStyle(
                  fontSize: 22, letterSpacing: 2, fontWeight: FontWeight.bold),
            ),
          ),
          actions: [dialogButton('닫기', onPressed: close)],
          onSubmit: close,
          onCancel: close,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final on = _on;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: on
            ? _accent.withOpacity(0.06)
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color:
                on ? _accent.withOpacity(0.4) : Colors.grey.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // [LUXCOM] 버전 · 현재 채널 + 변경
          Row(
            children: [
              Builder(builder: (_) {
                final ch =
                    bind.mainGetOptionSync(key: 'luxcom-channel').trim();
                return Text('채널 ${ch.isEmpty ? "미지정" : ch}',
                    style: const TextStyle(
                        fontSize: 11.5,
                        color: _accent,
                        fontWeight: FontWeight.w700));
              }),
              const Spacer(),
              InkWell(
                onTap: _changeChannel,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text('채널 변경',
                      style: TextStyle(
                          fontSize: 11,
                          color: _accent,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(on ? Icons.shield : Icons.shield_outlined,
                  size: 18, color: on ? _accent : Colors.grey),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('스탠바이 모드',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              SizedBox(
                height: 26,
                child: Switch(
                  value: on,
                  activeColor: _accent,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (v) {
                    if (v) {
                      _enable();
                    } else {
                      _disable();
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (on) ...[
            Text('상주 중 · 기사가 언제든 접속',
                style: TextStyle(
                    fontSize: 12, color: _accent, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('이 PC 이름: ${_pcName.isEmpty ? "(미설정)" : _pcName}',
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.key, size: 14),
              label: const Text('비밀번호 보기', style: TextStyle(fontSize: 12)),
              onPressed: _viewPassword,
              style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  minimumSize: const Size(0, 30)),
            ),
          ] else
            const Text(
              '켜두면 기사가 번호 없이 언제든 접속할 수 있어요.\n재부팅해도 자동으로 다시 대기합니다.',
              style:
                  TextStyle(fontSize: 11.5, color: Colors.grey, height: 1.4),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// [LUXCOM] 이 PC 정보 — PC명·도메인/워크그룹·내부/외부IP·Windows·비트·CPU.
//  기사가 원격 붙은 PC를 파악하는 데 유용(장치 설치 등). 순수 Dart 수집(콘솔창 없음):
//  Platform / NetworkInterface / 환경변수 + 외부IP는 luxauth /api/ip.
// ─────────────────────────────────────────────────────────────────────
const List<String> _kSysInfoKeys = ['PC 이름', '도메인/워크그룹', '내부 IP', '외부 IP', 'Windows', '비트', 'CPU', '논리 코어', 'RAM', '그래픽카드', '메인보드', '바이오스'];

// [LUXCOM] 버전 라벨 — RustDesk 베이스(1.4.6) + 우리 빌드 번호(4번째 자리). 패치마다 kLuxComBuild++.
const String kLuxRustDeskVer = '1.4.6';
const int kLuxComBuild = 4;
const String kLuxVerLabel = 'v$kLuxRustDeskVer.$kLuxComBuild'; // = v1.4.6.3

// [LUXCOM] 버전 표시(2줄) — 소비자 패널 하단 + 기사 패널 하단 공용.
class _LuxVersionFooter extends StatelessWidget {
  const _LuxVersionFooter();
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).textTheme.titleLarge?.color?.withOpacity(0.45);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(kLuxVerLabel,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
        Text('RustDesk $kLuxRustDeskVer 기반',
            style: TextStyle(fontSize: 9.5, color: c)),
      ],
    );
  }
}

// [LUXCOM] RAM·그래픽카드·메인보드·바이오스 — Win32 API/레지스트리로 수집(콘솔창 없음, Windows 전용).
//  RAM=GlobalMemoryStatusEx(kernel32) / GPU·메인보드·바이오스=RegGetValueW(advapi32) HKLM 레지스트리.
final class _MemStatusEx extends Struct {
  @Uint32() external int dwLength;
  @Uint32() external int dwMemoryLoad;
  @Uint64() external int ullTotalPhys;
  @Uint64() external int ullAvailPhys;
  @Uint64() external int ullTotalPageFile;
  @Uint64() external int ullAvailPageFile;
  @Uint64() external int ullTotalVirtual;
  @Uint64() external int ullAvailVirtual;
  @Uint64() external int ullAvailExtendedVirtual;
}

typedef _GmsExNative = Int32 Function(Pointer<_MemStatusEx>);
typedef _GmsExDart = int Function(Pointer<_MemStatusEx>);
typedef _RegGetNative = Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>, Uint32,
    Pointer<Uint32>, Pointer<Void>, Pointer<Uint32>);
typedef _RegGetDart = int Function(int, Pointer<Utf16>, Pointer<Utf16>, int,
    Pointer<Uint32>, Pointer<Void>, Pointer<Uint32>);

String _luxRegStr(_RegGetDart regGet, String subKey, String value) {
  final sk = subKey.toNativeUtf16();
  final v = value.toNativeUtf16();
  const cap = 512;
  final buf = calloc<Uint16>(cap);
  final sz = calloc<Uint32>()..value = cap * 2;
  try {
    // HKEY_LOCAL_MACHINE=0x80000002, RRF_RT_ANY=0x0000ffff, ERROR_SUCCESS=0
    final r = regGet(0x80000002, sk, v, 0x0000ffff, nullptr, buf.cast<Void>(), sz);
    if (r == 0) return buf.cast<Utf16>().toDartString().trim();
  } catch (_) {} finally {
    calloc.free(sk);
    calloc.free(v);
    calloc.free(buf);
    calloc.free(sz);
  }
  return '';
}

Map<String, String> _luxHwInfo() {
  final m = <String, String>{};
  if (!Platform.isWindows) return m;
  // RAM 총 용량
  try {
    final gms = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<_GmsExNative, _GmsExDart>('GlobalMemoryStatusEx');
    final mem = calloc<_MemStatusEx>();
    try {
      mem.ref.dwLength = sizeOf<_MemStatusEx>();
      if (gms(mem) != 0) {
        final gb = mem.ref.ullTotalPhys / (1024 * 1024 * 1024);
        if (gb > 0) m['RAM'] = '${gb.round()}GB';
      }
    } finally {
      calloc.free(mem);
    }
  } catch (_) {}
  // 그래픽카드·메인보드·바이오스 (레지스트리)
  try {
    final regGet = DynamicLibrary.open('advapi32.dll')
        .lookupFunction<_RegGetNative, _RegGetDart>('RegGetValueW');
    final gpu = _luxRegStr(
        regGet,
        r'SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000',
        'DriverDesc');
    if (gpu.isNotEmpty) m['그래픽카드'] = gpu;
    const bios = r'HARDWARE\DESCRIPTION\System\BIOS';
    final boardMfr = _luxRegStr(regGet, bios, 'BaseBoardManufacturer');
    final boardProd = _luxRegStr(regGet, bios, 'BaseBoardProduct');
    final board = [boardMfr, boardProd].where((s) => s.isNotEmpty).join(' ');
    if (board.isNotEmpty) m['메인보드'] = board;
    final biosVendor = _luxRegStr(regGet, bios, 'BIOSVendor');
    final biosVer = _luxRegStr(regGet, bios, 'BIOSVersion');
    final biosDate = _luxRegStr(regGet, bios, 'BIOSReleaseDate');
    final bv = [biosVendor, biosVer].where((s) => s.isNotEmpty).join(' ');
    if (bv.isNotEmpty) m['바이오스'] = biosDate.isNotEmpty ? '$bv ($biosDate)' : bv;
  } catch (_) {}
  return m;
}

Future<Map<String, String>> _gatherSysInfo() async {
  final m = <String, String>{};
  final env = Platform.environment;
  try { m['PC 이름'] = Platform.localHostname; } catch (_) {}
  final dom = (env['USERDOMAIN'] ?? '').trim();
  final comp = (env['COMPUTERNAME'] ?? '').trim();
  if (dom.isNotEmpty) {
    m['도메인/워크그룹'] = (dom.toUpperCase() == comp.toUpperCase()) ? '작업그룹 PC (도메인 아님)' : '도메인: $dom';
  }
  try {
    final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    final ips = <String>[];
    for (final i in ifs) { for (final a in i.addresses) { ips.add(a.address); } }
    if (ips.isNotEmpty) m['내부 IP'] = ips.join(', ');
  } catch (_) {}
  try {
    final r = await http.get(Uri.parse('https://405.kr/luxauth/api/ip')).timeout(const Duration(seconds: 8));
    if (r.statusCode == 200) {
      final j = jsonDecode(r.body);
      if (j is Map && j['ip'] != null) m['외부 IP'] = j['ip'].toString();
    }
  } catch (_) {}
  try { m['Windows'] = Platform.operatingSystemVersion; } catch (_) {}
  final arch = (env['PROCESSOR_ARCHITECTURE'] ?? '').toUpperCase();
  final arch6432 = (env['PROCESSOR_ARCHITEW6432'] ?? '').toUpperCase();
  m['비트'] = (arch.contains('64') || arch6432.contains('64')) ? '64비트' : (arch.isEmpty ? '확인 불가' : '32비트');
  final cpu = (env['PROCESSOR_IDENTIFIER'] ?? '').trim();
  if (cpu.isNotEmpty) m['CPU'] = cpu;
  final cores = (env['NUMBER_OF_PROCESSORS'] ?? '').trim();
  if (cores.isNotEmpty) m['논리 코어'] = '$cores개';
  try { m.addAll(_luxHwInfo()); } catch (_) {} // RAM·그래픽카드·메인보드·바이오스 (Win32, 콘솔창 없음)
  return m;
}

void _showLuxSysInfo(BuildContext context) {
  // [LUXCOM] 가로 넓은 PC정보 창. 소비자(좁은 창)는 보이도록 창을 잠시 넓혔다가 닫을 때 복원.
  final inc = bind.isIncomingOnly();
  if (inc) { try { windowManager.setSize(const Size(680, 660)); } catch (_) {} }
  gFFI.dialogManager.show((setDlg, close, ctx) => CustomAlertDialog(
        title: const Text('이 PC 정보', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: const SizedBox(width: 600, child: _LuxSysInfo()),
        actions: [dialogButton('닫기', onPressed: close)],
        onSubmit: close,
        onCancel: close,
      )).then((_) { if (inc) { try { windowManager.setSize(getIncomingOnlyHomeSize()); } catch (_) {} } });
}

// [LUXCOM] 공유문제 해결 다이얼로그의 항목 설명 위젯
class _LuxFixItem extends StatelessWidget {
  final String title;
  final String desc;
  const _LuxFixItem(this.title, this.desc);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 12.8, fontWeight: FontWeight.bold, color: Color(0xFF86E08A))),
          Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(desc, style: const TextStyle(fontSize: 11.8, color: Color(0xFF9AA0C8), height: 1.5))),
        ]),
      );
}

// 공유문제 해결: 스크립트를 임시폴더에 쓰고 관리자 권한(UAC)으로 실행. apply=적용+복구스크립트 생성 / false=복구.
Future<String> _luxRunWinFix(bool apply) async {
  if (!Platform.isWindows) return '윈도우에서만 지원합니다.';
  try {
    final tmp = Platform.environment['TEMP'] ?? Platform.environment['TMP'] ?? r'C:\Windows\Temp';
    final f = File('$tmp\\luxcom_winfix_${apply ? 'apply' : 'restore'}.ps1');
    await f.writeAsString(apply ? _kLuxFixApplyPs : _kLuxFixRestorePs, flush: true);
    await Process.start('powershell', [
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-Command',
      "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File','${f.path}'"
    ]);
    return apply
        ? 'UAC 창에서 "예"를 누르면 적용됩니다. 완료 후 재부팅을 권장합니다.'
        : 'UAC 창에서 "예"를 누르면 원래대로 복구됩니다.';
  } catch (e) {
    return '실행 실패: $e';
  }
}

// 적용: 현재 레지스트리 값을 캡처해 복구 스크립트(ProgramData\LuxCom\winfix_restore.ps1) 생성 후 수정 적용.
const String _kLuxFixApplyPs = r'''
$ErrorActionPreference='SilentlyContinue'
$dir="$env:ProgramData\LuxCom"; New-Item -ItemType Directory -Force -Path $dir | Out-Null
$ws='HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'
$pr='HKLM:\SYSTEM\CurrentControlSet\Control\Print'
New-Item -Path $ws -Force | Out-Null
$R=@("`$ErrorActionPreference='SilentlyContinue'")
function Bak($p,$n){ $cur=(Get-ItemProperty -Path $p -Name $n -EA 0).$n; if($null -eq $cur){ "Remove-ItemProperty -Path '$p' -Name '$n' -EA 0" } else { "New-ItemProperty -Path '$p' -Name '$n' -Value $cur -PropertyType DWord -Force | Out-Null" } }
$R+=Bak $ws 'AllowInsecureGuestAuth'
$R+=Bak $ws 'RequireSecuritySignature'
$R+=Bak $ws 'EnableSecuritySignature'
$R+=Bak $pr 'RpcAuthnLevelPrivacyEnabled'
$R+="Disable-NetFirewallRule -Group '@FirewallAPI.dll,-32752' -EA 0"
$R+="Disable-NetFirewallRule -Group '@FirewallAPI.dll,-28502' -EA 0"
$R+="try{ `$w=Get-Service LanmanWorkstation -EA 0; if(`$w.Status -ne 'Stopped'){ Stop-Service LanmanWorkstation -Force -EA 0; `$w.WaitForStatus('Stopped','00:00:15') }; Start-Service LanmanWorkstation -EA 0; (Get-Service LanmanWorkstation).WaitForStatus('Running','00:00:15') }catch{}; Start-Service Browser -EA 0"
$R | Set-Content "$dir\winfix_restore.ps1" -Encoding UTF8
New-ItemProperty -Path $ws -Name 'AllowInsecureGuestAuth' -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $ws -Name 'RequireSecuritySignature' -Value 0 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $ws -Name 'EnableSecuritySignature' -Value 0 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $pr -Name 'RpcAuthnLevelPrivacyEnabled' -Value 0 -PropertyType DWord -Force | Out-Null
Enable-NetFirewallRule -Group '@FirewallAPI.dll,-32752' -EA 0
Enable-NetFirewallRule -Group '@FirewallAPI.dll,-28502' -EA 0
foreach($s in 'FDResPub','fdPHost','SSDPSRV','upnphost','LanmanServer'){ Set-Service $s -StartupType Automatic -EA 0; Start-Service $s -EA 0 }
# [LUXCOM] LanmanWorkstation(SMB 클라이언트) 안전 재시작 — 기존엔 Start 직후 곧바로 Restart-Service -Force 라
#   START_PENDING 경합으로 서비스가 '중지'된 채 남는 사고가 있었다. Stop(완전정지 대기)->Start(실행 대기, 최대 3회)로 교체.
Set-Service LanmanWorkstation -StartupType Automatic -EA 0
try{ $w=Get-Service LanmanWorkstation -EA 0; if($w -and $w.Status -ne 'Stopped'){ Stop-Service LanmanWorkstation -Force -EA 0; $w.WaitForStatus('Stopped','00:00:15') } }catch{}
for($i=0;$i -lt 3;$i++){ try{ Start-Service LanmanWorkstation -EA 0; (Get-Service LanmanWorkstation).WaitForStatus('Running','00:00:15') }catch{}; if((Get-Service LanmanWorkstation -EA 0).Status -eq 'Running'){ break } }
Start-Service Browser -EA 0
''';

// 복구: 적용 때 생성된 복구 스크립트를 실행(없으면 무동작).
const String _kLuxFixRestorePs = r'''
$ErrorActionPreference='SilentlyContinue'
$f="$env:ProgramData\LuxCom\winfix_restore.ps1"
if(Test-Path $f){ & $f }
''';

class _LuxSysInfo extends StatefulWidget {
  const _LuxSysInfo();
  @override
  State<_LuxSysInfo> createState() => _LuxSysInfoState();
}

class _LuxSysInfoState extends State<_LuxSysInfo> {
  Map<String, String>? _info;
  @override
  void initState() {
    super.initState();
    _gatherSysInfo().then((m) { if (mounted) setState(() => _info = m); });
  }
  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info == null) {
      return const SizedBox(height: 90, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    final keys = _kSysInfoKeys.where((k) => (info[k] ?? '').isNotEmpty).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...keys.map((k) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 92, child: Text(k, style: const TextStyle(fontSize: 12.5, color: Colors.grey))),
                Expanded(child: SelectableText(info[k]!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
              ]),
            )),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('전체 복사'),
            onPressed: () {
              final t = keys.map((k) => '$k: ${info[k]}').join('\n');
              Clipboard.setData(ClipboardData(text: t));
              showToast(translate('Copied'));
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// [LUXCOM] 실행 시 데스크탑 화면 우측하단에 별도 광고 창을 띄움 — 소비자·기사 둘 다, 프로세스당 1회.
//  앱 창 안이 아니라 desktop_multi_window 의 별도 창(RaiDrive식)으로 생성한다(렌더는 main.dart _LuxComAdWindow).
//  광고 페이지(기본 405.kr/ad/) = 우리 쇼핑몰(luxcom.co.kr) 자체 홍보.
//  ⚠️ 데스크탑 앱 광고창이라 구글 애드센스 금지(정책 위반=계정 정지) — 자체광고만. 애드센스는 웹페이지(405.kr) 쪽에만.
//  옵션 'luxcom-ad-url'='off' 면 끔, 그 외 값이면 그 URL 사용. 생성/로드 실패 시 조용히 생략.
// ─────────────────────────────────────────────────────────────────────
class _LuxComAdOverlay extends StatefulWidget {
  const _LuxComAdOverlay();
  @override
  State<_LuxComAdOverlay> createState() => _LuxComAdOverlayState();
}

class _LuxComAdOverlayState extends State<_LuxComAdOverlay> {
  static bool _shownThisLaunch = false;

  @override
  void initState() {
    super.initState();
    if (!_shownThisLaunch) {
      _shownThisLaunch = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _spawn());
    }
  }

  // 데스크탑 화면 우측하단에 별도 광고 창을 생성한다.
  // 창은 스스로 위치를 잡고 표시된다(main.dart 의 _LuxComAdWindow).
  Future<void> _spawn() async {
    final opt = bind.mainGetOptionSync(key: 'luxcom-ad-url');
    if (opt == 'off') return; // 킬 스위치
    final url = opt.isEmpty ? 'https://405.kr/ad/' : opt;
    try {
      await DesktopMultiWindow.createWindow(jsonEncode({
        'luxcom_ad': true,
        'url': url,
      }));
    } catch (_) {
      // 멀티윈도우 생성 실패 → 광고 생략 (앱 동작엔 영향 없음)
    }
  }

  // 인앱 UI 없음 — 광고는 별도 데스크탑 창으로 표시된다.
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
