import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/app_constants.dart';

/// Singleton that owns the Agora RTC engine for the lifetime of the app.
/// One engine instance is reused across calls — it is ONLY released when
/// explicitly disposed. This avoids the singleton corruption that occurs
/// when release() + create() race on the native layer.
class AgoraService {
  AgoraService._();
  static final AgoraService instance = AgoraService._();

  RtcEngine? _engine;
  RtcEngineEventHandler? _eventHandler;
  bool _initialized = false;
  bool _isInChannel = false;
  int _joinFailures = 0; // consecutive join failures → trigger reinit

  // ── Public state callbacks (set by CallScreen) ──────────────────────────
  VoidCallback? onEngineReady;
  void Function(int localUid)? onJoined;
  void Function(int remoteUid)? onUserJoined;
  void Function(int remoteUid)? onUserLeft;
  VoidCallback? onRemoteAudioActive; // fired when remote audio starts decoding
  void Function(String error)? onError;
  VoidCallback? onConnectionFailed;
  VoidCallback? onTokenExpiring;

  bool get isInChannel => _isInChannel;
  RtcEngine? get engine => _engine;

  // ── Request microphone permission ────────────────────────────────────────
  Future<bool> requestMicPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  // ── Initialize (idempotent — safe to call multiple times) ────────────────
  Future<bool> init() async {
    if (_initialized && _engine != null) {
      if (kDebugMode) debugPrint('AgoraService: already initialized');
      onEngineReady?.call();
      return true;
    }

    // Clean up any stale engine before creating a new one
    if (_engine != null) {
      if (kDebugMode)
        debugPrint('AgoraService: cleaning up stale engine before reinit');
      try {
        await _engine!.leaveChannel();
      } catch (_) {}
      try {
        _engine!.unregisterEventHandler(_eventHandler!);
      } catch (_) {}
      try {
        await _engine!.release();
      } catch (_) {}
      _engine = null;
      _initialized = false;
      _isInChannel = false;
    }

    try {
      _engine = createAgoraRtcEngine();
      await _engine!.initialize(
        RtcEngineContext(
          appId: AppConstants.agoraAppId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );

      _eventHandler = RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection conn, int elapsed) {
          if (kDebugMode) {
            debugPrint(
              'AgoraService: ✅ joined ${conn.channelId} uid=${conn.localUid}',
            );
          }
          _isInChannel = true;
          _joinFailures = 0;
          onJoined?.call(conn.localUid ?? 0);
        },
        onUserJoined: (RtcConnection conn, int remoteUid, int elapsed) {
          if (kDebugMode)
            debugPrint('AgoraService: remote user $remoteUid joined');
          onUserJoined?.call(remoteUid);
        },
        onUserOffline:
            (RtcConnection conn, int remoteUid, UserOfflineReasonType reason) {
              if (kDebugMode)
                debugPrint(
                  'AgoraService: remote user $remoteUid left ($reason)',
                );
              onUserLeft?.call(remoteUid);
            },
        onRemoteAudioStateChanged:
            (
              RtcConnection conn,
              int remoteUid,
              RemoteAudioState state,
              RemoteAudioStateReason reason,
              int elapsed,
            ) {
              if (state == RemoteAudioState.remoteAudioStateDecoding) {
                onUserJoined?.call(remoteUid);
                onRemoteAudioActive?.call();
              }
            },
        onConnectionStateChanged:
            (
              RtcConnection conn,
              ConnectionStateType state,
              ConnectionChangedReasonType reason,
            ) {
              if (kDebugMode)
                debugPrint('AgoraService: conn state=$state reason=$reason');
              if (state == ConnectionStateType.connectionStateFailed) {
                _isInChannel = false;
                onConnectionFailed?.call();
              }
            },
        onTokenPrivilegeWillExpire: (RtcConnection conn, String token) {
          if (kDebugMode) debugPrint('AgoraService: token expiring soon');
          onTokenExpiring?.call();
        },
        onError: (ErrorCodeType code, String msg) {
          if (kDebugMode) debugPrint('AgoraService: error $code — $msg');
          onError?.call('$code: $msg');
        },
      );
      _engine!.registerEventHandler(_eventHandler!);

      await _engine!.setAudioProfile(
        profile: AudioProfileType.audioProfileDefault,
        scenario: AudioScenarioType.audioScenarioChatroom,
      );
      await _engine!.enableAudio();
      await _engine!.disableVideo();
      await _engine!.setDefaultAudioRouteToSpeakerphone(false);

      _initialized = true;
      if (kDebugMode) debugPrint('AgoraService: engine ready');
      onEngineReady?.call();
      return true;
    } catch (e, st) {
      if (kDebugMode) debugPrint('AgoraService: init failed: $e\n$st');
      _engine = null;
      _initialized = false;
      onError?.call('Engine init failed: $e');
      return false;
    }
  }

  // ── Join channel ─────────────────────────────────────────────────────────
  Future<bool> joinChannel({
    required String token,
    required String channelName,
  }) async {
    if (_engine == null || !_initialized) {
      if (kDebugMode) {
        debugPrint(
          'AgoraService: cannot join — engine not ready (engine=${_engine != null}, init=$_initialized)',
        );
      }
      return false;
    }
    if (_isInChannel) {
      if (kDebugMode) {
        debugPrint(
          'AgoraService: stale isInChannel — forcing leave before re-join',
        );
      }
      await leaveChannel();
    }
    try {
      if (kDebugMode) {
        debugPrint(
          'AgoraService: joining channel=$channelName tokenLen=${token.length}',
        );
      }
      await _engine!.joinChannel(
        token: token,
        channelId: channelName,
        uid: 0,
        options: const ChannelMediaOptions(
          autoSubscribeAudio: true,
          autoSubscribeVideo: false,
          publishMicrophoneTrack: true,
          publishCameraTrack: false,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );
      if (kDebugMode) {
        debugPrint(
          'AgoraService: joinChannel call completed (waiting for onJoinChannelSuccess)',
        );
      }
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('AgoraService: joinChannel failed: $e');
      _joinFailures++;
      onError?.call('Join failed: $e');
      return false;
    }
  }

  /// Force full engine teardown + re-create. Use when the engine is in a
  /// corrupt state after repeated join failures.
  Future<bool> forceReinit() async {
    if (kDebugMode)
      debugPrint('AgoraService: forceReinit — tearing down engine');
    clearCallbacks();
    _isInChannel = false;
    try {
      if (_eventHandler != null)
        _engine?.unregisterEventHandler(_eventHandler!);
    } catch (_) {}
    try {
      await _engine?.leaveChannel();
    } catch (_) {}
    try {
      await _engine?.release();
    } catch (_) {}
    _engine = null;
    _eventHandler = null;
    _initialized = false;
    _joinFailures = 0;
    return init();
  }

  /// Whether the engine appears corrupted (too many consecutive join failures).
  bool get needsReinit => _joinFailures >= 2;

  // ── Leave channel (keep engine alive for next call) ──────────────────────
  Future<void> leaveChannel() async {
    // Set false immediately so new calls don't see stale state
    _isInChannel = false;
    if (_engine == null) return;
    try {
      await _engine!.leaveChannel();
    } catch (e) {
      if (kDebugMode) debugPrint('AgoraService: leaveChannel: $e');
    }
  }

  // ── Renew token mid-call ─────────────────────────────────────────────────
  Future<void> renewToken(String token) async {
    try {
      await _engine?.renewToken(token);
    } catch (e) {
      if (kDebugMode) debugPrint('AgoraService: renewToken failed: $e');
    }
  }

  // ── Audio controls ───────────────────────────────────────────────────────
  void setMuted(bool muted) => _engine?.muteLocalAudioStream(muted);
  void setSpeaker(bool speaker) => _engine?.setEnableSpeakerphone(speaker);
  void setVolumes() {
    _engine?.adjustRecordingSignalVolume(400);
    _engine?.adjustPlaybackSignalVolume(400);
  }

  /// Ensure all audio paths are fully open after joining a channel.
  Future<void> ensureAudioActive() async {
    if (_engine == null) return;
    await _engine!.enableLocalAudio(true);
    await _engine!.muteLocalAudioStream(false);
    await _engine!.muteAllRemoteAudioStreams(false);
  }

  // ── Clear callbacks (call from CallScreen.dispose) ───────────────────────
  void clearCallbacks() {
    onEngineReady = null;
    onJoined = null;
    onUserJoined = null;
    onUserLeft = null;
    onRemoteAudioActive = null;
    onError = null;
    onConnectionFailed = null;
    onTokenExpiring = null;
  }

  // ── Full release — only call when app terminates ─────────────────────────
  Future<void> dispose() async {
    clearCallbacks();
    await leaveChannel();
    try {
      if (_eventHandler != null)
        _engine?.unregisterEventHandler(_eventHandler!);
    } catch (_) {}
    try {
      await _engine?.release();
    } catch (_) {}
    _engine = null;
    _eventHandler = null;
    _initialized = false;
    _joinFailures = 0;
    if (kDebugMode) debugPrint('AgoraService: fully disposed');
  }
}
