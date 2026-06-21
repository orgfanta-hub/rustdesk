import 'dart:async';
import 'dart:convert';

import 'package:auto_size_text_field/auto_size_text_field.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/common/widgets/connection_page_title.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_hbb/models/peer_model.dart';

import '../../common.dart';
import '../../common/widgets/peer_tab_page.dart';
import '../../common/widgets/autocomplete.dart';
import '../../consts.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import 'home_page.dart';

/// Connection page for connecting to a remote peer.
class ConnectionPage extends StatefulWidget implements PageShape {
  ConnectionPage({Key? key, required this.appBarActions}) : super(key: key);

  @override
  final icon = const Icon(Icons.connected_tv);

  @override
  final title = translate("Connection");

  @override
  final List<Widget> appBarActions;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

/// State for the connection page.
class _ConnectionPageState extends State<ConnectionPage> {
  /// Controller for the id input bar.
  final _idController = IDTextEditingController();
  final RxBool _idEmpty = true.obs;

  final FocusNode _idFocusNode = FocusNode();
  final TextEditingController _idEditingController = TextEditingController();

  final AllPeersLoader _allPeersLoader = AllPeersLoader();

  StreamSubscription? _uniLinksSubscription;

  // https://github.com/flutter/flutter/issues/157244
  Iterable<Peer> _autocompleteOpts = [];

  _ConnectionPageState() {
    if (!isWeb) _uniLinksSubscription = listenUniLinks();
    _idController.addListener(() {
      _idEmpty.value = _idController.text.isEmpty;
    });
    Get.put<IDTextEditingController>(_idController);
  }

  @override
  void initState() {
    super.initState();
    _allPeersLoader.init(setState);
    _idFocusNode.addListener(onFocusChanged);
    if (_idController.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final lastRemoteId = await bind.mainGetLastRemoteId();
        if (lastRemoteId != _idController.id) {
          setState(() {
            _idController.id = lastRemoteId;
          });
        }
      });
    }
    Get.put<TextEditingController>(_idEditingController);
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<FfiModel>(context);
    return CustomScrollView(
      slivers: [
        SliverList(
            delegate: SliverChildListDelegate([
          if (!bind.isCustomClient() && !isIOS)
            Obx(() => _buildUpdateUI(stateGlobal.updateUrl.value)),
          _buildRemoteIDTextField(),
        ])),
        SliverFillRemaining(
          hasScrollBody: true,
          // [LUXCOM] 기사 앱: 최근세션(PeerTabPage) 대신 내 채널의 대기(스탠바이) 고객 목록 표시.
          //  데스크톱 connection_page 와 동일한 위젯(복제). 줄/버튼 클릭 → 해당 고객에게 바로 접속.
          child: _LuxComStandbyList(onPick: (id) => connect(context, id)),
        )
      ],
    ).marginOnly(top: 2, left: 10, right: 10);
  }

  /// Callback for the connect button.
  /// Connects to the selected peer.
  void onConnect() {
    var id = _idController.id;
    connect(context, id);
  }

  void onFocusChanged() {
    _idEmpty.value = _idEditingController.text.isEmpty;
    if (_idFocusNode.hasFocus) {
      if (_allPeersLoader.needLoad) {
        _allPeersLoader.getAllPeers();
      }

      final textLength = _idEditingController.value.text.length;
      // Select all to facilitate removing text, just following the behavior of address input of chrome.
      _idEditingController.selection =
          TextSelection(baseOffset: 0, extentOffset: textLength);
    }
  }

  /// UI for software update.
  /// If _updateUrl] is not empty, shows a button to update the software.
  Widget _buildUpdateUI(String updateUrl) {
    return updateUrl.isEmpty
        ? const SizedBox(height: 0)
        : InkWell(
            onTap: () async {
              final url = 'https://rustdesk.com/download';
              // https://pub.dev/packages/url_launcher#configuration
              // https://developer.android.com/training/package-visibility/use-cases#open-urls-custom-tabs
              //
              // `await launchUrl(Uri.parse(url))` can also run if skip
              // 1. The following check
              // 2. `<action android:name="android.support.customtabs.action.CustomTabsService" />` in AndroidManifest.xml
              //
              // But it is better to add the check.
              await launchUrl(Uri.parse(url));
            },
            child: Container(
                alignment: AlignmentDirectional.center,
                width: double.infinity,
                color: Colors.pinkAccent,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(translate('Download new version'),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold))));
  }

  /// UI for the remote ID TextField.
  /// Search for a peer and connect to it if the id exists.
  Widget _buildRemoteIDTextField() {
    final w = SizedBox(
      height: 84,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Ink(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.all(Radius.circular(13)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Container(
                  padding: const EdgeInsets.only(left: 16, right: 16),
                  child: RawAutocomplete<Peer>(
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text == '') {
                        _autocompleteOpts = const Iterable<Peer>.empty();
                      } else if (_allPeersLoader.peers.isEmpty &&
                          !_allPeersLoader.isPeersLoaded) {
                        Peer emptyPeer = Peer(
                          id: '',
                          username: '',
                          hostname: '',
                          alias: '',
                          platform: '',
                          tags: [],
                          hash: '',
                          password: '',
                          forceAlwaysRelay: false,
                          rdpPort: '',
                          rdpUsername: '',
                          loginName: '',
                          device_group_name: '',
                          note: '',
                        );
                        _autocompleteOpts = [emptyPeer];
                      } else {
                        String textWithoutSpaces =
                            textEditingValue.text.replaceAll(" ", "");
                        if (int.tryParse(textWithoutSpaces) != null) {
                          textEditingValue = TextEditingValue(
                            text: textWithoutSpaces,
                            selection: textEditingValue.selection,
                          );
                        }
                        String textToFind = textEditingValue.text.toLowerCase();

                        _autocompleteOpts = _allPeersLoader.peers
                            .where((peer) =>
                                peer.id.toLowerCase().contains(textToFind) ||
                                peer.username
                                    .toLowerCase()
                                    .contains(textToFind) ||
                                peer.hostname
                                    .toLowerCase()
                                    .contains(textToFind) ||
                                peer.alias.toLowerCase().contains(textToFind))
                            .toList();
                      }
                      return _autocompleteOpts;
                    },
                    focusNode: _idFocusNode,
                    textEditingController: _idEditingController,
                    fieldViewBuilder: (BuildContext context,
                        TextEditingController fieldTextEditingController,
                        FocusNode fieldFocusNode,
                        VoidCallback onFieldSubmitted) {
                      updateTextAndPreserveSelection(
                          fieldTextEditingController, _idController.text);
                      return AutoSizeTextField(
                        controller: fieldTextEditingController,
                        focusNode: fieldFocusNode,
                        minFontSize: 18,
                        autocorrect: false,
                        enableSuggestions: false,
                        keyboardType: TextInputType.visiblePassword,
                        // keyboardType: TextInputType.number,
                        onChanged: (String text) {
                          _idController.id = text;
                        },
                        style: const TextStyle(
                          fontFamily: 'WorkSans',
                          fontWeight: FontWeight.bold,
                          fontSize: 30,
                          color: MyTheme.idColor,
                        ),
                        decoration: InputDecoration(
                          labelText: translate('Remote ID'),
                          // hintText: 'Enter your remote ID',
                          border: InputBorder.none,
                          helperStyle: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: MyTheme.darkGray,
                          ),
                          labelStyle: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            letterSpacing: 0.2,
                            color: MyTheme.darkGray,
                          ),
                        ),
                        inputFormatters: [IDTextInputFormatter()],
                        onSubmitted: (_) {
                          onConnect();
                        },
                      );
                    },
                    onSelected: (option) {
                      setState(() {
                        _idController.id = option.id;
                        FocusScope.of(context).unfocus();
                      });
                    },
                    optionsViewBuilder: (BuildContext context,
                        AutocompleteOnSelected<Peer> onSelected,
                        Iterable<Peer> options) {
                      options = _autocompleteOpts;
                      double maxHeight = options.length * 50;
                      if (options.length == 1) {
                        maxHeight = 52;
                      } else if (options.length == 3) {
                        maxHeight = 146;
                      } else if (options.length == 4) {
                        maxHeight = 193;
                      }
                      maxHeight = maxHeight.clamp(0, 200);
                      return Align(
                          alignment: Alignment.topLeft,
                          child: Container(
                              decoration: BoxDecoration(
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 5,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                  borderRadius: BorderRadius.circular(5),
                                  child: Material(
                                      elevation: 4,
                                      child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxHeight: maxHeight,
                                            maxWidth: 320,
                                          ),
                                          child: _allPeersLoader
                                                      .peers.isEmpty &&
                                                  !_allPeersLoader.isPeersLoaded
                                              ? Container(
                                                  height: 80,
                                                  child: Center(
                                                      child:
                                                          CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  )))
                                              : ListView(
                                                  padding:
                                                      EdgeInsets.only(top: 5),
                                                  children: options
                                                      .map((peer) =>
                                                          AutocompletePeerTile(
                                                              onSelect: () =>
                                                                  onSelected(
                                                                      peer),
                                                              peer: peer))
                                                      .toList(),
                                                ))))));
                    },
                  ),
                ),
              ),
              Obx(() => Offstage(
                    offstage: _idEmpty.value,
                    child: IconButton(
                        onPressed: () {
                          setState(() {
                            _idController.clear();
                          });
                        },
                        icon: Icon(Icons.clear, color: MyTheme.darkGray)),
                  )),
              SizedBox(
                width: 60,
                height: 60,
                child: IconButton(
                  icon: const Icon(Icons.arrow_forward,
                      color: MyTheme.darkGray, size: 45),
                  onPressed: onConnect,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final child = Column(children: [
      if (isWebDesktop)
        getConnectionPageTitle(context, true)
            .marginOnly(bottom: 10, top: 15, left: 12),
      w
    ]);
    return Align(
        alignment: Alignment.topCenter,
        child: Container(constraints: kMobilePageConstraints, child: child));
  }

  @override
  void dispose() {
    _uniLinksSubscription?.cancel();
    _idController.dispose();
    _idFocusNode.removeListener(onFocusChanged);
    _allPeersLoader.clear();
    _idFocusNode.dispose();
    _idEditingController.dispose();
    if (Get.isRegistered<IDTextEditingController>()) {
      Get.delete<IDTextEditingController>();
    }
    if (Get.isRegistered<TextEditingController>()) {
      Get.delete<TextEditingController>();
    }
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────
// [LUXCOM] 기사 앱 내 스탠바이(대기 고객) 목록 패널 — 모바일.
//  데스크톱 desktop/pages/connection_page.dart 의 _LuxComStandbyList 를 복제(동일 로직).
//  기사 로그인 세션으로 luxauth /api/standby 를 2초마다 폴링 → 내 채널의
//  대기(스탠바이) 고객 목록 표시. 줄/버튼 클릭 시 onPick(id) → connect.
//  세션 토큰 = LuxComGate 가 저장한 local option 'luxcom_session_token'.
//  ⚠ 데스크톱 버전 수정 시 이 복제본도 함께 동기화할 것.
// ─────────────────────────────────────────────────────────────────────
class _LuxComStandbyList extends StatefulWidget {
  final void Function(String id) onPick;
  const _LuxComStandbyList({required this.onPick});
  @override
  State<_LuxComStandbyList> createState() => _LuxComStandbyListState();
}

class _LuxComStandbyListState extends State<_LuxComStandbyList> {
  static const String _luxAuthBase = 'https://405.kr/luxauth';
  static const Color _accent = Color(0xFF4F46E5);
  Timer? _timer;
  List<dynamic> _clients = [];
  String _channel = '';
  bool _loading = true;
  String _err = '';

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll()); // [LUXCOM] 2s 폴링 → 고객 접속/해제 반영 빠르게
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _token() {
    try {
      return bind.mainGetLocalOption(key: 'luxcom_session_token');
    } catch (_) {
      return '';
    }
  }

  // [LUXCOM] 기사가 고객 스탠바이(상주) 모드를 원격 해제 — 기사 로그인 비밀번호 재확인 필수
  void _confirmStandbyOff(String id, String name) {
    String err = '';
    bool busy = false;
    gFFI.dialogManager.show((setDlg, close, context) {
      doOff() async {
        if (busy) return;
        setDlg(() { busy = true; err = ''; });
        try {
          final r = await http
              .post(Uri.parse('$_luxAuthBase/api/standby-off'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'session': _token(),
                    'channel': _channel,
                    'id': id
                  }))
              .timeout(const Duration(seconds: 10));
          dynamic m;
          try { m = jsonDecode(r.body); } catch (_) { m = {}; }
          if (r.statusCode == 200 && m is Map && m['ok'] == true) {
            close();
            showToast('해제 명령을 보냈습니다 — 잠시 후(최대 5초) 고객 PC에서 상주가 해제됩니다.');
          } else {
            setDlg(() {
              busy = false;
              err = (m is Map && m['message'] != null)
                  ? m['message'].toString()
                  : '해제에 실패했습니다 (${r.statusCode}).';
            });
          }
        } catch (_) {
          setDlg(() { busy = false; err = '서버에 연결할 수 없습니다.'; });
        }
      }

      return CustomAlertDialog(
        title: const Text('스탠바이(상주) 원격 해제',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  '${name.isEmpty ? "번호 $id" : name} 의 상주(무인 접속) 모드를 원격으로 해제합니다.\n로그인된 기사 본인 확인으로 바로 해제됩니다.',
                  style: const TextStyle(fontSize: 12.5, height: 1.5)),
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
          dialogButton(busy ? '처리 중…' : '해제', onPressed: busy ? null : doOff),
        ],
        onCancel: close,
      );
    });
  }

  Future<void> _poll() async {
    final tok = _token();
    if (tok.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _err = '기사 로그인이 필요합니다.';
        });
      }
      return;
    }
    try {
      final r = await http
          .post(Uri.parse('$_luxAuthBase/api/standby'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'session': tok}))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final m = jsonDecode(r.body);
        if (mounted) {
          setState(() {
            _loading = false;
            _err = '';
            _channel = (m is Map && m['channel'] != null)
                ? m['channel'].toString()
                : '';
            _clients =
                (m is Map && m['clients'] is List) ? m['clients'] as List : [];
          });
        }
      } else if (mounted) {
        setState(() {
          _loading = false;
          _err = '목록을 불러올 수 없습니다 (${r.statusCode}).';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false); // 일시 오류: 이전 목록 유지
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 10, bottom: 8),
          child: Row(
            children: [
              const Text('대기 중인 고객',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(width: 8),
              if (_channel.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: _accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999)),
                  child: Text('채널 $_channel',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _accent)),
                ),
              const Spacer(),
              Text('${_clients.length}명',
                  style: TextStyle(fontSize: 12.5, color: theme.hintColor)),
              IconButton(
                tooltip: '새로고침',
                icon: const Icon(Icons.refresh, size: 18),
                splashRadius: 18,
                onPressed: _poll,
              ),
            ],
          ),
        ),
        Expanded(child: _body(theme)),
      ],
    );
  }

  Widget _body(ThemeData theme) {
    if (_loading) {
      return const Center(
          child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_clients.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _err.isNotEmpty
                ? _err
                : '대기 중인 고객이 없습니다.\n고객이 받은 프로그램을 실행하면 여기에 표시됩니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.hintColor, fontSize: 13, height: 1.6),
          ),
        ),
      );
    }
    return ListView.separated(
      // [LUXCOM] 모바일: 우하단 로그아웃 버튼/하단 탭바에 마지막 항목이 가리지 않도록 하단 여백 확대.
      padding: const EdgeInsets.only(right: 8, bottom: 84),
      itemCount: _clients.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final c = _clients[i] as Map;
        final id = (c['id'] ?? '').toString();
        final name = (c['name'] ?? '').toString();
        final standby = c['standby'] == true; // true=스탠바이(상주·무인), false=일반(수락 필요)
        return Material(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => widget.onPick(id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                        color: standby
                            ? const Color(0xFF16C47F)
                            : const Color(0xFFF59E0B),
                        shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(name.isEmpty ? '(이름 없음)' : name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14)),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                  color: (standby
                                          ? const Color(0xFF16C47F)
                                          : const Color(0xFFF59E0B))
                                      .withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6)),
                              child: Text(standby ? '상주' : '일반',
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: standby
                                          ? const Color(0xFF0E9F6E)
                                          : const Color(0xFFB45309))),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text('번호 $id',
                            style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: _accent)),
                        if (((c['ip'] ?? '').toString().isNotEmpty) ||
                            ((c['lan_ip'] ?? '').toString().isNotEmpty))
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                                '외부 ${(c['ip'] ?? '').toString().isEmpty ? '-' : c['ip']}   ·   내부 ${(c['lan_ip'] ?? '').toString().isEmpty ? '-' : c['lan_ip']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: theme.hintColor,
                                    fontWeight: FontWeight.w500)),
                          ),
                      ],
                    ),
                  ),
                  if (standby) ...[
                    const SizedBox(width: 6),
                    Tooltip(
                      message: '스탠바이(상주) 모드 원격 해제',
                      child: OutlinedButton(
                        onPressed: () => _confirmStandbyOff(id, name),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFB45309),
                          side: const BorderSide(color: Color(0xFFF59E0B)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 9),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9)),
                        ),
                        child: const Text('상주 끄기',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => widget.onPick(id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9)),
                    ),
                    child: const Text('접속',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
