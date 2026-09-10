import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';

import '../../app/bootstrap/app_services_scope.dart';
import '../../app/bootstrap/polling_scheduler.dart';
import '../../app/telemetry/genesis_telemetry.dart';
import '../../components/auth/login_guard.dart';
import '../../components/chat/shared/chat_ui.dart';
import '../../components/page_header.dart';
import '../../ui/components/genesis_refresh_indicator.dart';
import '../../ui/theme/genesis_dark_theme.dart';
import '../../ui/tokens/genesis_colors.dart';
import '../../network/api_client.dart';
import '../../network/api_exception.dart';
import '../../network/direct_message_conversation_store.dart';
import '../../network/direct_message_message_store.dart';
import '../../network/genesis_api.dart';
import '../../network/json_utils.dart';
import '../../routers/app_router.dart';
import '../../ui/components/genesis_safe_area.dart';
import '../../utils/display_name_formatter.dart';
import '../../utils/genesis_ugc_text.dart';

const String _privateChatReplyGateHint = 'Wait for a reply to send more';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.peerUid,
    this.peerName = '',
    this.peerAvatar = '',
    this.conversationId = '',
  });

  final String peerUid;
  final String peerName;
  final String peerAvatar;
  final String conversationId;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  static const _draftSaveDelay = Duration(milliseconds: 250);

  late ScrollController _scrollController;
  final _textController = TextEditingController();
  final Map<String, DirectMessageMessageRecord> _failedLocalMessages = {};
  final Set<String> _readMarkedIncomingMessageIds = {};
  int _unseenIncomingCount = 0;
  late final GenesisPollingScheduler _poller;
  Timer? _draftSaveTimer;
  late DirectMessageMessageStore _messageStore;
  bool _loadedLocalMessages = false;
  bool _didRevealInitialMessages = false;
  bool _initialMessageRevealScheduled = false;
  bool _syncing = false;
  bool _sending = false;
  bool _loadingOlder = false;
  bool _applyingDraftText = false;
  String _latestSendFailureLocalMessageId = '';
  String _latestSendFailureMessage = '';
  String _lastDraftPeerUid = '';
  String _lastSavedDraft = '';
  String _myUid = '';
  String _myAvatarUrl = '';
  double _composerHeight = 0;
  String get _peerUid => widget.peerUid.trim();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController = _createScrollController();
    _messageStore = AppServicesScope.read(context).directMessageMessages;
    _textController.addListener(_handleDraftTextChanged);
    _poller = GenesisPollingScheduler(
      interval: const Duration(seconds: 5),
      onTick: () => _syncLatest(tracePolicy: ApiRequestTracePolicy.excluded),
    )..start(immediately: false);
    unawaited(_bootstrap());
  }

  @override
  void didUpdateWidget(covariant ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.peerUid.trim() == _peerUid) return;
    _flushDraft(peerUid: oldWidget.peerUid.trim());
    _resetDraftTracking();
    _applyingDraftText = true;
    _textController.clear();
    _applyingDraftText = false;
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _scrollController = _createScrollController();
    setState(() {
      _failedLocalMessages.clear();
      _readMarkedIncomingMessageIds.clear();
      _unseenIncomingCount = 0;
      _loadedLocalMessages = false;
      _didRevealInitialMessages = false;
      _initialMessageRevealScheduled = false;
      _syncing = false;
      _sending = false;
      _loadingOlder = false;
      _latestSendFailureLocalMessageId = '';
      _latestSendFailureMessage = '';
    });
    unawaited(_bootstrap());
  }

  ScrollController _createScrollController() {
    return ScrollController()..addListener(_handleScroll);
  }

  @override
  void didChangeMetrics() {
    _revealLatestMessageAfterLayout();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _poller.start();
    } else {
      _poller.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poller.stop();
    _flushDraft();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _textController.removeListener(_handleDraftTextChanged);
    _textController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final services = AppServicesScope.read(context);
    final uid = (await services.sessionStore.readUid())?.trim() ?? '';
    final userInfo = await services.sessionStore.readUserInfo();
    final myAvatarUrl = _resolvedProfileAvatar(
      userInfo ?? const <String, dynamic>{},
      '',
    );
    if (!mounted) return;
    setState(() {
      _myUid = uid;
      _myAvatarUrl = myAvatarUrl;
      _failedLocalMessages.clear();
      _readMarkedIncomingMessageIds.clear();
      _unseenIncomingCount = 0;
    });
    try {
      await _loadDraft(_peerUid);
      await _messageStore.loadFromDb(_peerUid);
      if (!mounted) return;
      final hasCachedMessages =
          _messageStore.orderedMessageIds.value.isNotEmpty;
      if (hasCachedMessages) {
        setState(() => _loadedLocalMessages = true);
        _scheduleInitialMessageReveal();
      }
      await _syncLatest();
      if (!hasCachedMessages && mounted) {
        setState(() => _loadedLocalMessages = true);
      }
      _scheduleInitialMessageReveal();
    } catch (error, stackTrace) {
      debugPrint('[ChatPage][DM] bootstrap failed: $error');
      debugPrint('[ChatPage][DM] stacktrace:\n$stackTrace');
      if (mounted) {
        setState(() => _loadedLocalMessages = true);
        _scheduleInitialMessageReveal();
      }
    }
  }

  Future<void> _syncLatest({
    ApiRequestTracePolicy tracePolicy = ApiRequestTracePolicy.standard,
  }) async {
    if (_syncing || _peerUid.isEmpty) return;
    final hasScrollClients = _scrollController.hasClients;
    final wasNearBottom = hasScrollClients && _isNearBottom();
    final canShowNewMessageNotice = _loadedLocalMessages && hasScrollClients;
    final previousIncomingIds = _incomingMessageIds(
      _messageStore.orderedMessageIds.value,
    );
    setState(() => _syncing = true);
    try {
      await _messageStore.syncLatest(_peerUid, tracePolicy: tracePolicy);
      final newIncomingIds = _newIncomingMessageIds(previousIncomingIds);
      if (newIncomingIds.isNotEmpty) {
        _handleNewIncomingMessages(
          newIncomingIds,
          shouldStickToBottom: wasNearBottom,
          showNotice: canShowNewMessageNotice && !wasNearBottom,
        );
      }
    } catch (error, stackTrace) {
      debugPrint('[ChatPage][DM] sync failed: $error');
      debugPrint('[ChatPage][DM] stacktrace:\n$stackTrace');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Set<String> _incomingMessageIds(List<String> messageIds) {
    return messageIds.where((messageId) {
      final record = _recordForMessageId(messageId);
      return record != null && _isIncomingMessage(record);
    }).toSet();
  }

  List<String> _newIncomingMessageIds(Set<String> previousIncomingIds) {
    final nextIncomingIds = _incomingMessageIds(
      _messageStore.orderedMessageIds.value,
    );
    return nextIncomingIds
        .where(
          (messageId) =>
              !previousIncomingIds.contains(messageId) &&
              !_readMarkedIncomingMessageIds.contains(messageId),
        )
        .toList(growable: false);
  }

  bool _isIncomingMessage(DirectMessageMessageRecord record) {
    final senderUid = record.senderUid.trim();
    final myUid = _myUid.trim();
    return senderUid.isNotEmpty &&
        (myUid.isEmpty || senderUid != myUid) &&
        record.sendStatus == DirectMessageSendStatus.sent;
  }

  void _handleNewIncomingMessages(
    List<String> messageIds, {
    required bool shouldStickToBottom,
    required bool showNotice,
  }) {
    final pendingIds = messageIds.toSet();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final renderedIds = _renderMessageIds(
        _messageStore.orderedMessageIds.value,
      ).toSet();
      if (!pendingIds.every(renderedIds.contains)) return;
      _readMarkedIncomingMessageIds.addAll(pendingIds);
      unawaited(_markRead());
      if (shouldStickToBottom) {
        _clearUnseenIncomingCount();
        _scrollToBottom(jump: true, settleFrames: 4);
        return;
      }
      if (!showNotice) return;
      setState(() {
        _unseenIncomingCount += pendingIds.length;
      });
    });
  }

  Future<void> _markRead() async {
    if (_peerUid.isEmpty) return;
    try {
      final services = AppServicesScope.read(context);
      await services.api.v1.dm.markRead(peerUid: _peerUid);
      await services.directMessageConversations.markPeerRead(_peerUid);
    } catch (error) {
      debugPrint('[ChatPage][DM] mark read failed: $error');
    }
  }

  void _handleScroll() {
    if (!_scrollController.hasClients || _loadingOlder || _peerUid.isEmpty) {
      return;
    }
    if (!_didRevealInitialMessages) return;
    if (_unseenIncomingCount > 0 && _isNearBottom()) {
      _clearUnseenIncomingCount();
    }
    final position = _scrollController.position;
    if (position.pixels > 120) return;
    if (position.userScrollDirection != ScrollDirection.forward) return;
    if (!_messageStore.hasMoreOlder) return;
    unawaited(_loadOlder());
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return false;
    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels < 80;
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder) return;
    final hadScrollClients = _scrollController.hasClients;
    final previousMaxScrollExtent = hadScrollClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    final previousPixels = hadScrollClients
        ? _scrollController.position.pixels
        : 0.0;
    setState(() => _loadingOlder = true);
    try {
      await _messageStore.loadOlder(_peerUid);
      _restoreScrollPositionAfterOlderMessages(
        previousMaxScrollExtent: previousMaxScrollExtent,
        previousPixels: previousPixels,
      );
    } catch (error, stackTrace) {
      debugPrint('[ChatPage][DM] load older failed: $error');
      debugPrint('[ChatPage][DM] stacktrace:\n$stackTrace');
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  void _restoreScrollPositionAfterOlderMessages({
    required double previousMaxScrollExtent,
    required double previousPixels,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final delta = position.maxScrollExtent - previousMaxScrollExtent;
      if (delta <= 0) return;
      final target = (previousPixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      position.jumpTo(target);
    });
  }

  Future<void> _send() async {
    if (_sending || _peerUid.isEmpty) return;
    final content = normalizeGenesisUgcTextForSubmission(_textController.text);
    if (isGenesisUgcTextBlank(content)) return;
    if (!await ensureGenesisLogin(context)) return;
    if (!mounted) return;
    final services = AppServicesScope.read(context);
    final sessionUid = (await services.sessionStore.readUid())?.trim() ?? '';
    if (!mounted) return;

    setState(() {
      _sending = true;
      if (sessionUid.isNotEmpty) _myUid = sessionUid;
    });
    await _clearDraft(_peerUid);
    if (!mounted) return;
    final senderUid = sessionUid.isNotEmpty ? sessionUid : '__anonymous__';
    final localMessageId = await _messageStore.insertLocalMessage(
      peerUid: _peerUid,
      senderUid: senderUid,
      content: content,
    );
    if (!mounted) return;
    _applyingDraftText = true;
    _textController.clear();
    _applyingDraftText = false;
    _clearUnseenIncomingCount();
    _scrollToBottom();

    try {
      final data = await services.api.v1.dm.send(
        peerUid: _peerUid,
        content: content,
      );
      final message = data['message'];
      if (message is Map) {
        final messageMap = asJsonMap(message);
        await _messageStore.replaceLocalMessage(
          peerUid: _peerUid,
          localMessageId: localMessageId,
          serverMessage: messageMap,
        );
        GenesisTelemetry.collectLog(
          actionType: 'event',
          action: 'private_chat_send_message',
          object1: _peerUid,
          object2: asString(
            messageMap['message_id'],
            fallback: asString(messageMap['id']),
          ),
        );
      }
      final conversation = data['conversation'];
      if (conversation is Map) {
        await services.directMessageConversations.mergeConversationJson(
          asJsonMap(conversation),
        );
      }
      if (!mounted) return;
      setState(() {
        _latestSendFailureLocalMessageId = '';
        _latestSendFailureMessage = '';
      });
      _scrollToBottom();
    } on ApiException catch (error, stackTrace) {
      debugPrint('[ChatPage][DM] send failed: $error');
      debugPrint('[ChatPage][DM] stacktrace:\n$stackTrace');
      if (mounted) {
        final message = error.message.trim();
        setState(() {
          _latestSendFailureLocalMessageId = localMessageId;
          _latestSendFailureMessage = message.isEmpty ? 'Send failed' : message;
        });
      }
      await _markLocalMessageSendFailed(localMessageId);
    } catch (error, stackTrace) {
      debugPrint('[ChatPage][DM] send failed: $error');
      debugPrint('[ChatPage][DM] stacktrace:\n$stackTrace');
      await _markLocalMessageSendFailed(localMessageId);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _markLocalMessageSendFailed(String localMessageId) async {
    final localRecord = _messageStore.rowListenable(localMessageId)?.value;
    await _messageStore.deleteMessage(
      peerUid: _peerUid,
      messageId: localMessageId,
    );
    if (localRecord == null || !mounted) return;
    setState(() {
      _failedLocalMessages[localMessageId] =
          DirectMessageMessageRecord.fromJson(
            localRecord.toJson(),
            localId: localRecord.localId,
            sendStatus: DirectMessageSendStatus.failed,
          );
    });
  }

  void _scrollToBottom({bool jump = false, int settleFrames = 2}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (jump) {
        _scrollController.jumpTo(target);
        if (settleFrames > 0) {
          _scrollToBottom(jump: true, settleFrames: settleFrames - 1);
        }
        return;
      }
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _scheduleInitialMessageReveal({int remainingAttempts = 4}) {
    if (_didRevealInitialMessages || _initialMessageRevealScheduled) return;
    _initialMessageRevealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialMessageRevealScheduled = false;
      if (!mounted || _didRevealInitialMessages) return;
      if (!_scrollController.hasClients) {
        if (remainingAttempts > 0) {
          _scheduleInitialMessageReveal(
            remainingAttempts: remainingAttempts - 1,
          );
        } else {
          _didRevealInitialMessages = true;
        }
        return;
      }
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      _didRevealInitialMessages = true;
    });
  }

  void _revealLatestMessageAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollToBottom(jump: true, settleFrames: 4);
    });
  }

  void _clearUnseenIncomingCount() {
    if (_unseenIncomingCount == 0 || !mounted) return;
    setState(() => _unseenIncomingCount = 0);
  }

  Future<void> _loadDraft(String peerUid) async {
    final cleanPeerUid = peerUid.trim();
    if (cleanPeerUid.isEmpty) return;
    try {
      final draft = await _messageStore.loadDraft(cleanPeerUid);
      if (!mounted || _peerUid != cleanPeerUid) return;
      _lastDraftPeerUid = cleanPeerUid;
      _lastSavedDraft = draft;
      if (draft.isEmpty || _textController.text.isNotEmpty) return;
      _applyingDraftText = true;
      _textController.value = TextEditingValue(
        text: draft,
        selection: TextSelection.collapsed(offset: draft.length),
      );
      _applyingDraftText = false;
    } catch (error) {
      debugPrint('[ChatPage][DM] load draft failed: $error');
    } finally {
      _applyingDraftText = false;
    }
  }

  void _handleDraftTextChanged() {
    if (_applyingDraftText || _peerUid.isEmpty) return;
    _scheduleDraftSave(_peerUid, _textController.text);
  }

  void _scheduleDraftSave(String peerUid, String content) {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(_draftSaveDelay, () {
      _draftSaveTimer = null;
      _saveDraftNow(peerUid: peerUid, content: content);
    });
  }

  void _flushDraft({String? peerUid}) {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = null;
    final cleanPeerUid = (peerUid ?? _peerUid).trim();
    if (cleanPeerUid.isEmpty) return;
    _saveDraftNow(peerUid: cleanPeerUid, content: _textController.text);
  }

  void _saveDraftNow({required String peerUid, required String content}) {
    final cleanPeerUid = peerUid.trim();
    if (cleanPeerUid.isEmpty) return;
    if (_lastDraftPeerUid == cleanPeerUid && _lastSavedDraft == content) {
      return;
    }
    _lastDraftPeerUid = cleanPeerUid;
    _lastSavedDraft = content;
    unawaited(
      _messageStore
          .saveDraft(peerUid: cleanPeerUid, content: content)
          .catchError(
            (Object error) =>
                debugPrint('[ChatPage][DM] save draft failed: $error'),
          ),
    );
  }

  Future<void> _clearDraft(String peerUid) async {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = null;
    final cleanPeerUid = peerUid.trim();
    if (cleanPeerUid.isEmpty) return;
    _lastDraftPeerUid = cleanPeerUid;
    _lastSavedDraft = '';
    try {
      await _messageStore.clearDraft(cleanPeerUid);
    } catch (error) {
      debugPrint('[ChatPage][DM] clear draft failed: $error');
    }
  }

  void _resetDraftTracking() {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = null;
    _lastDraftPeerUid = '';
    _lastSavedDraft = '';
  }

  void _openUnseenIncomingMessages() {
    _clearUnseenIncomingCount();
    _scrollToBottom(jump: true, settleFrames: 4);
  }

  VoidCallback? _avatarTapFor(DirectMessageMessageRecord record) {
    final senderUid = record.senderUid.trim();
    final myUid = _myUid.trim();
    if (senderUid.isEmpty || (myUid.isNotEmpty && senderUid == myUid)) {
      return null;
    }
    return () {
      Navigator.of(
        context,
      ).pushNamed(RouteNames.userInfo, arguments: {'uid': senderUid});
    };
  }

  @override
  Widget build(BuildContext context) {
    final peerTitle = firstNonEmpty([
      formatUidForDisplay(widget.peerName),
      formatUidForDisplay(_peerUid),
      'Direct message',
    ]);
    return GenesisDarkTheme(
      child: GenesisBottomSystemBarStyleScope(
        style: GenesisBottomSystemBarStyle(
          color: kPrivateChatStyle.composerBackgroundColor,
        ),
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: kChatDarkHeaderSystemUiOverlayStyle,
          child: Scaffold(
            backgroundColor: kPrivateChatStyle.conversationBackgroundColor,
            resizeToAvoidBottomInset: true,
            body: Stack(
              children: [
                Stack(
                  children: [
                    Positioned.fill(child: _buildMessages()),
                    if (_unseenIncomingCount > 0)
                      Positioned(
                        right: 16,
                        bottom: _privateChatComposerHeight() + 12,
                        child: _NewIncomingMessageNotice(
                          count: _unseenIncomingCount,
                          onTap: _openUnseenIncomingMessages,
                        ),
                      ),
                  ],
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: SizedBox(
                    height: _privateChatHeaderHeight(),
                    child: GenesisBackAppBar(pageName: peerTitle),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ChatComposer(
                    controller: _textController,
                    inputEnabled: _peerUid.isNotEmpty,
                    sendEnabled: _peerUid.isNotEmpty && !_sending,
                    sending: _sending,
                    onSend: _send,
                    sendLabel: 'Send',
                    hintText: _composerHintText(),
                    style: kPrivateChatStyle,
                    onHeightChanged: _handleComposerHeightChanged,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _composerHintText() {
    if (_latestVisibleMessageIsIncoming()) return null;
    final conversation = _conversationForPeer();
    if (conversation == null || conversation.canSendNextMessage) return null;
    return _privateChatReplyGateHint;
  }

  bool _latestVisibleMessageIsIncoming() {
    final ids = _messageStore.orderedMessageIds.value;
    if (ids.isEmpty) return false;
    final latest = _recordForMessageId(ids.last);
    return latest != null && _isIncomingMessage(latest);
  }

  DirectMessageConversationRecord? _conversationForPeer() {
    final conversations = AppServicesScope.read(
      context,
    ).directMessageConversations;
    for (final id in conversations.orderedConversationIds.value) {
      final record = conversations.rowListenable(id)?.value;
      if (record?.peerUid.trim() == _peerUid) return record;
    }
    return null;
  }

  Widget _buildMessages() {
    final style = kPrivateChatStyle;
    final listPadding = _messageListPadding(style);
    return ValueListenableBuilder<List<String>>(
      valueListenable: _messageStore.orderedMessageIds,
      builder: (context, messageIds, _) {
        final renderIds = _renderMessageIds(messageIds);
        if (!_loadedLocalMessages && renderIds.isEmpty) {
          return const Center(child: GenesisLoadingIndicator(strokeWidth: 4));
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            return ListView.builder(
              controller: _scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: listPadding,
              itemCount: renderIds.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _loadingOlder
                      ? Padding(
                          padding: EdgeInsets.only(
                            bottom: style.dateDividerBottomPadding,
                          ),
                          child: const Center(
                            child: GenesisLoadingIndicator(strokeWidth: 4),
                          ),
                        )
                      : const SizedBox.shrink();
                }
                return _buildMessageItem(renderIds, index - 1);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildMessageItem(List<String> renderIds, int messageIndex) {
    final messageId = renderIds[messageIndex];
    final failedRecord = _failedLocalMessages[messageId];
    if (failedRecord != null) {
      final previous = messageIndex == 0
          ? null
          : _recordForMessageId(renderIds[messageIndex - 1]);
      return _withInlineSendFailure(
        messageId: messageId,
        child: ChatMessageRow(
          key: ValueKey(messageId),
          message: _messageVm(failedRecord),
          style: kPrivateChatStyle,
          onAvatarTap: _avatarTapFor(failedRecord),
          showDateDivider: shouldShowChatDateDivider(
            previous?.createdAt,
            failedRecord.createdAt,
          ),
        ),
      );
    }
    final listenable = _messageStore.rowListenable(messageId);
    if (listenable == null) return const SizedBox.shrink();
    return ValueListenableBuilder<DirectMessageMessageRecord>(
      key: ValueKey(messageId),
      valueListenable: listenable,
      builder: (context, record, _) {
        final previous = messageIndex == 0
            ? null
            : _recordForMessageId(renderIds[messageIndex - 1]);
        return _withInlineSendFailure(
          messageId: messageId,
          child: ChatMessageRow(
            message: _messageVm(record),
            style: kPrivateChatStyle,
            onAvatarTap: _avatarTapFor(record),
            showDateDivider: shouldShowChatDateDivider(
              previous?.createdAt,
              record.createdAt,
            ),
          ),
        );
      },
    );
  }

  Widget _withInlineSendFailure({
    required String messageId,
    required Widget child,
  }) {
    if (messageId != _latestSendFailureLocalMessageId ||
        _latestSendFailureMessage.trim().isEmpty) {
      return child;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        child,
        LayoutBuilder(
          builder: (context, constraints) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Align(
                alignment: Alignment.center,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth - 48,
                  ),
                  child: Text(
                    _capitalizedSentence(_latestSendFailureMessage),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: GenesisColors.darkTextTertiary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  EdgeInsets _messageListPadding(ChatUiStyleConfig style) {
    return style.messageListPadding.copyWith(
      top: style.messageListPadding.top + _privateChatHeaderHeight(),
      bottom: style.messageListPadding.bottom + _privateChatComposerHeight(),
    );
  }

  double _privateChatHeaderHeight() {
    final topInset = GenesisSafeAreaInsets.top(context);
    return topInset + kGenesisTopBarHeight;
  }

  double _privateChatComposerHeight() {
    final bottomInset = GenesisSafeAreaInsets.bottom(context);
    return _composerHeight > 0
        ? _composerHeight
        : kPrivateChatStyle.composerPadding.vertical +
              kPrivateChatStyle.inputMinHeight +
              bottomInset;
  }

  void _handleComposerHeightChanged(double height) {
    if ((_composerHeight - height).abs() > 0.5) {
      setState(() => _composerHeight = height);
    }
    _revealLatestMessageAfterLayout();
  }

  List<String> _renderMessageIds(List<String> dbMessageIds) {
    final records = <DirectMessageMessageRecord>[];
    for (final id in dbMessageIds) {
      final record = _messageStore.rowListenable(id)?.value;
      if (record != null) records.add(record);
    }
    records.addAll(_failedLocalMessages.values);
    records.sort((a, b) {
      final byTime = a.sortValue.compareTo(b.sortValue);
      if (byTime != 0) return byTime;
      return a.messageId.compareTo(b.messageId);
    });
    return records.map((record) => record.messageId).toList(growable: false);
  }

  DirectMessageMessageRecord? _recordForMessageId(String messageId) {
    return _failedLocalMessages[messageId] ??
        _messageStore.rowListenable(messageId)?.value;
  }

  ChatMessageVm _messageVm(DirectMessageMessageRecord record) {
    final isMe = _myUid.trim().isNotEmpty && record.senderUid == _myUid.trim();
    final senderName = isMe
        ? 'Me'
        : firstNonEmpty([
            formatUidForDisplay(widget.peerName),
            formatUidForDisplay(record.senderUid),
            formatUidForDisplay(_peerUid),
          ]);
    final messageId = int.tryParse(record.messageId);
    return ChatMessageVm(
      localId: record.messageId,
      messageId: messageId,
      senderId: record.senderUid,
      senderName: senderName,
      avatarUrl: isMe ? _myAvatarUrl : widget.peerAvatar,
      text: decodeGenesisUgcTextForDisplay(record.content),
      isMe: isMe,
      status: record.sendStatus,
      createdAt: record.createdAt,
    );
  }
}

String _resolvedProfileAvatar(
  Map<dynamic, dynamic> userInfo,
  String profileAvatar,
) {
  final resolved = asResolvedImageUrl(
    _mapValue(userInfo, const ['avatar']),
    resolveAssetUrl,
    fallback: _mapValue(userInfo, const [
      'avatar_url',
      'photoUrl',
      'photo_url',
      'picture',
    ]),
  );
  if (resolved.isNotEmpty) return resolved;
  return asResolvedImageUrl(profileAvatar, resolveAssetUrl);
}

Object? _mapValue(Map<dynamic, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value == null) continue;
    final text = '$value'.trim();
    if (text.isNotEmpty) return value;
  }
  return null;
}

String _capitalizedSentence(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return trimmed;
  return trimmed[0].toUpperCase() + trimmed.substring(1);
}

class _NewIncomingMessageNotice extends StatelessWidget {
  const _NewIncomingMessageNotice({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GenesisColors.darkRaisedBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: GenesisColors.darkFaintFill),
      ),
      child: InkWell(
        key: const ValueKey('chat-new-message-notice'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            '$count new ${count == 1 ? 'message' : 'messages'}',
            style: const TextStyle(
              color: GenesisColors.darkTextPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
