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
  bool _initialized = false;
  bool _isInChannel = false;

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
      debugPrint('AgoraService: already initialized');
      onEngineReady?.call();
      return true;
    }

    try {
      _engine = createAgoraRtcEngine();
      await _engine!.initialize(
        RtcEngineContext(
          appId: AppConstants.agoraAppId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );

      _engine!.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection conn, int elapsed) {
            debugPrint(
              'AgoraService: ✅ joined ${conn.channelId} uid=${conn.localUid}',
            );
            _isInChannel = true;
            onJoined?.call(conn.localUid ?? 0);
          },
          onUserJoined: (RtcConnection conn, int remoteUid, int elapsed) {
            debugPrint('AgoraService: remote user $remoteUid joined');
            onUserJoined?.call(remoteUid);
          },
          onUserOffline:
              (
                RtcConnection conn,
                int remoteUid,
                UserOfflineReasonType reason,
              ) {
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
                debugPrint('AgoraService: conn state=$state reason=$reason');
                if (state == ConnectionStateType.connectionStateFailed) {
                  _isInChannel = false;
                  onConnectionFailed?.call();
                }
              },
          onTokenPrivilegeWillExpire: (RtcConnection conn, String token) {
            debugPrint('AgoraService: token expiring soon');
            onTokenExpiring?.call();
          },
          onError: (ErrorCodeType code, String msg) {
            debugPrint('AgoraService: error $code — $msg');
            onError?.call('$code: $msg');
          },
        ),
      );

      await _engine!.enableAudio();
      await _engine!.disableVideo();

      _initialized = true;
      debugPrint('AgoraService: engine ready');
      onEngineReady?.call();
      return true;
    } catch (e, st) {
      debugPrint('AgoraService: init failed: $e\n$st');
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
      debugPrint('AgoraService: cannot join — engine not ready');
      return false;
    }
    if (_isInChannel) {
      debugPrint('AgoraService: already in channel');
      return true;
    }
    try {
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
      return true;
    } catch (e) {
      debugPrint('AgoraService: joinChannel failed: $e');
      onError?.call('Join failed: $e');
      return false;
    }
  }

  // ── Leave channel (keep engine alive for next call) ──────────────────────
  Future<void> leaveChannel() async {
    if (_engine == null) return;
    try {
      await _engine!.leaveChannel();
    } catch (e) {
      debugPrint('AgoraService: leaveChannel: $e');
    }
    _isInChannel = false;
  }

  // ── Renew token mid-call ─────────────────────────────────────────────────
  Future<void> renewToken(String token) async {
    try {
      await _engine?.renewToken(token);
    } catch (e) {
      debugPrint('AgoraService: renewToken failed: $e');
    }
  }

  // ── Audio controls ───────────────────────────────────────────────────────
  void setMuted(bool muted) => _engine?.muteLocalAudioStream(muted);
  void setSpeaker(bool speaker) => _engine?.setEnableSpeakerphone(speaker);
  void setVolumes() {
    _engine?.adjustRecordingSignalVolume(400);
    _engine?.adjustPlaybackSignalVolume(400);
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
      await _engine?.release();
    } catch (_) {}
    _engine = null;
    _initialized = false;
    debugPrint('AgoraService: fully disposed');
  }
}
