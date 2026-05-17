import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/chat_model.dart';
import '../../providers/chat_provider.dart';
import '../../services/social/agora_service.dart';
import '../../services/notification_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_feedback_widgets.dart';

class CallScreen extends ConsumerStatefulWidget {
  final CallRecord call;
  final bool isCaller;
  final String? otherPartyName;

  const CallScreen({
    super.key,
    required this.call,
    required this.isCaller,
    this.otherPartyName,
  });

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen>
    with TickerProviderStateMixin {
  // ── Call state ─────────────────────────────────────────────────────────────
  late CallStatus _callStatus;
  int _seconds = 0;
  Timer? _durationTimer;
  Timer? _ringTimer;

  // ── Audio controls ─────────────────────────────────────────────────────────
  bool _isMuted = false;
  bool _isSpeaker = false;

  // ── Stage indicators ───────────────────────────────────────────────────────
  // ignore: unused_field
  bool _micReady = false;
  // ignore: unused_field
  bool _engineReady = false;
  // ignore: unused_field
  bool _tokenReady = false;
  bool _channelReady = false;
  bool _audioReady = false;
  String? _stageError;

  // ── Join state ─────────────────────────────────────────────────────────────
  String? _token;
  bool _isJoining = false;
  int _joinRetryCount = 0;
  Timer? _remoteLeftTimer; // grace period before ending call on user leave

  // ── Animation ──────────────────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  final _agora = AgoraService.instance;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _callStatus = widget.call.status;

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnim = Tween<double>(
      begin: 1.0,
      end: 1.35,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut));

    if (_callStatus == CallStatus.ringing) _startRinging();
    if (_callStatus == CallStatus.accepted) _startDurationTimer();

    _listenForCallUpdates();
    _initCall();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _ringTimer?.cancel();
    _remoteLeftTimer?.cancel();
    _pulseCtrl.dispose();
    _agora.clearCallbacks();
    _agora.leaveChannel();
    super.dispose();
  }

  // ── Init: permission → engine → join ──────────────────────────────────────
  Future<void> _initCall() async {
    // 0. Force-leave any stale channel from a previous call
    await _agora.leaveChannel();

    // 1. Microphone permission
    final hasMic = await _agora.requestMicPermission();
    if (!mounted) return;
    if (!hasMic) {
      setState(() => _stageError = 'Microphone permission denied');
      if (mounted) {
        AppSnackbar.warning(
          context,
          'Microphone permission required for calls',
        );
      }
      return;
    }
    setState(() => _micReady = true);

    // 2. Wire up engine callbacks
    _wireCallbacks();

    // 3. Initialize engine (idempotent)
    final ok = await _agora.init();
    if (!mounted) return;
    if (!ok) {
      setState(() => _stageError = 'Engine failed to start');
      return;
    }

    // 4. Caller joins immediately; receiver joins after accepting
    if (widget.isCaller || _callStatus == CallStatus.accepted) {
      await _joinChannel();
    }
  }

  /// Wire Agora callbacks. Extracted so we can re-wire after forceReinit.
  void _wireCallbacks() {
    _agora.onEngineReady = () {
      if (mounted) setState(() => _engineReady = true);
    };
    _agora.onJoined = (_) async {
      if (!mounted) return;
      setState(() {
        _channelReady = true;
        _audioReady = true; // local audio is live once we join
        _isJoining = false;
        _joinRetryCount = 0;
      });
      await _agora.ensureAudioActive();
      _agora.setVolumes();
    };
    _agora.onUserJoined = (_) {
      if (mounted) setState(() => _audioReady = true);
      // Remote user reconnected — cancel any pending end-call timer
      _remoteLeftTimer?.cancel();
      _remoteLeftTimer = null;
    };
    _agora.onRemoteAudioActive = () {
      if (mounted) setState(() => _audioReady = true);
      _remoteLeftTimer?.cancel();
      _remoteLeftTimer = null;
    };
    _agora.onUserLeft = (_) {
      if (mounted) setState(() => _audioReady = false);
      // Don't end immediately — give 10s for the remote party to reconnect
      // (covers brief network hiccups, app backgrounding, etc.)
      if (mounted && _callStatus == CallStatus.accepted) {
        _remoteLeftTimer?.cancel();
        _remoteLeftTimer = Timer(const Duration(seconds: 10), () {
          if (mounted && _callStatus != CallStatus.ended) _endCall();
        });
      } else if (mounted && _callStatus == CallStatus.ringing) {
        // During ringing, the other party hasn't connected yet — ignore
      }
    };
    _agora.onConnectionFailed = () {
      if (!mounted) return;
      setState(() {
        _stageError = 'Connection failed — retrying';
        _channelReady = false;
        _audioReady = false;
      });
      _retryJoin();
    };
    _agora.onTokenExpiring = _renewToken;
    _agora.onError = (err) {
      if (mounted) setState(() => _stageError = err);
    };
  }

  // ── Fetch Agora token ──────────────────────────────────────────────────────
  Future<String?> _fetchToken() async {
    try {
      final result = await ref
          .read(chatServiceProvider)
          .fetchAgoraToken(widget.call.id, widget.call.channelName);
      if (result != null && result.token.isNotEmpty) {
        if (mounted) setState(() => _tokenReady = true);
        return result.token;
      }
      if (mounted) setState(() => _stageError = 'Empty token from server');
      return null;
    } catch (e) {
      if (mounted) setState(() => _stageError = 'Token error: $e');
      return null;
    }
  }

  // ── Join Agora channel ─────────────────────────────────────────────────────
  Future<void> _joinChannel() async {
    if (_isJoining) {
      if (kDebugMode)
        debugPrint('CallScreen: _joinChannel skipped — already joining');
      return;
    }
    if (_agora.isInChannel) {
      if (kDebugMode)
        debugPrint('CallScreen: already in channel — marking ready');
      if (mounted) {
        setState(() {
          _channelReady = true;
          _audioReady = true;
        });
      }
      return;
    }
    _isJoining = true;
    if (mounted) setState(() => _stageError = null);

    _token = await _fetchToken();
    if (!mounted) {
      _isJoining = false;
      return;
    }
    if (_token == null || _token!.isEmpty) {
      if (kDebugMode)
        debugPrint('CallScreen: token null/empty — will retry in 3s');
      _isJoining = false;
      // Auto-retry after 3 s
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && !_agora.isInChannel) {
          _joinChannel();
        }
      });
      return;
    }

    if (kDebugMode) {
      debugPrint(
        'CallScreen: calling joinChannel with token (${_token!.length} chars)',
      );
    }
    final joined = await _agora.joinChannel(
      token: _token!,
      channelName: widget.call.channelName,
    );
    _isJoining = false;

    if (!joined && mounted) {
      setState(() => _stageError = 'Join returned false — retrying');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && !_agora.isInChannel && !_isJoining) _retryJoin();
      });
      return;
    }

    // Safety net: retry after 8 s if channel not connected
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted && !_agora.isInChannel && !_isJoining) _retryJoin();
    });
  }

  Future<void> _retryJoin() async {
    if (_isJoining) return;
    _joinRetryCount++;
    if (_joinRetryCount > 6) {
      if (mounted) {
        setState(
          () => _stageError = 'Could not connect — check your connection',
        );
      }
      return;
    }
    if (kDebugMode)
      debugPrint('CallScreen: retry #$_joinRetryCount — re-joining...');

    // If the engine has accumulated failures, force a full reinit
    if (_agora.needsReinit) {
      if (kDebugMode)
        debugPrint('CallScreen: engine corrupted — forcing reinit');
      if (mounted) setState(() => _stageError = 'Reinitializing audio...');
      final ok = await _agora.forceReinit();
      if (!mounted) return;
      if (!ok) {
        setState(() => _stageError = 'Engine reinit failed');
        return;
      }
      // Re-wire callbacks after reinit since forceReinit clears them
      _wireCallbacks();
      setState(() {
        _engineReady = true;
        _stageError = null;
      });
    }

    if (mounted) {
      setState(() {
        _stageError = 'Retrying (#$_joinRetryCount)...';
        _tokenReady = false;
        _channelReady = false;
        _audioReady = false;
      });
    }
    _token = null;
    await _agora.leaveChannel();
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) _joinChannel();
  }

  Future<void> _renewToken() async {
    final newToken = await _fetchToken();
    if (newToken != null) {
      _token = newToken;
      await _agora.renewToken(newToken);
    }
  }

  // ── Call lifecycle ─────────────────────────────────────────────────────────
  Future<void> _acceptCall() async {
    _stopRinging();
    NotificationService().cancelCallNotification();
    await ref
        .read(chatServiceProvider)
        .updateCallStatus(widget.call.id, CallStatus.accepted);
    if (mounted) {
      setState(() => _callStatus = CallStatus.accepted);
      _startDurationTimer();
    }

    // Ensure engine is ready before joining
    if (!_agora.isInChannel && !_isJoining) {
      // Re-init engine if needed (idempotent)
      final ok = await _agora.init();
      if (!mounted) return;
      if (!ok) {
        setState(() => _stageError = 'Engine failed on accept');
        return;
      }
      await _joinChannel();
    }
  }

  Future<void> _declineCall() async {
    _stopRinging();
    NotificationService().cancelCallNotification();
    await ref
        .read(chatServiceProvider)
        .updateCallStatus(widget.call.id, CallStatus.declined);
    await _agora.leaveChannel();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _endCall() async {
    if (_callStatus == CallStatus.ended) return;
    _durationTimer?.cancel();
    _remoteLeftTimer?.cancel();
    _remoteLeftTimer = null;
    _stopRinging();
    NotificationService().cancelCallNotification();
    if (mounted) setState(() => _callStatus = CallStatus.ended);
    await ref
        .read(chatServiceProvider)
        .updateCallStatus(widget.call.id, CallStatus.ended);
    await _agora.leaveChannel();
    if (mounted) {
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) Navigator.of(context).pop();
    }
  }

  // ── Real-time call status listener ────────────────────────────────────────
  void _listenForCallUpdates() {
    final userId = widget.isCaller
        ? widget.call.callerId
        : widget.call.receiverId;
    ref.listenManual(activeCallsProvider(userId), (_, next) {
      next.whenData((calls) {
        final match = calls.where((c) => c.id == widget.call.id).toList();
        if (match.isEmpty) return;
        final updated = match.first;
        if (updated.status == _callStatus) return;
        if (!mounted) return;
        setState(() => _callStatus = updated.status);
        switch (_callStatus) {
          case CallStatus.accepted:
            _stopRinging();
            _startDurationTimer();
            // Receiver joins now that call was accepted
            if (!_agora.isInChannel && !_isJoining) {
              _joinChannel();
            }
            break;
          case CallStatus.ended:
          case CallStatus.declined:
          case CallStatus.missed:
          case CallStatus.failed:
            _stopRinging();
            _durationTimer?.cancel();
            _agora.leaveChannel().then((_) {
              if (mounted) Navigator.of(context).pop();
            });
            break;
          default:
            break;
        }
      });
    });
  }

  // ── Ringing helpers ────────────────────────────────────────────────────────
  void _startRinging() {
    _pulseCtrl.repeat(reverse: true);
    HapticFeedback.mediumImpact();
    _ringTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_callStatus == CallStatus.ringing && mounted) {
        HapticFeedback.mediumImpact();
      }
    });
  }

  void _stopRinging() {
    _ringTimer?.cancel();
    _ringTimer = null;
    _pulseCtrl
      ..stop()
      ..reset();
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  String get _formattedDuration {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            _buildAvatar(),
            const SizedBox(height: 20),
            Text(
              widget.otherPartyName ?? 'Order Participant',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _buildStatusText(),
            if (_callStatus == CallStatus.accepted) ...[
              const SizedBox(height: 4),
              Text(
                _formattedDuration,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 32,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
            const SizedBox(height: 24),
            _buildConnectionStages(),
            const Spacer(flex: 3),
            _buildControls(),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final ringColor = widget.isCaller
        ? AppTheme.primaryColor
        : const Color(0xFF22C55E);
    if (_callStatus == CallStatus.ringing) {
      return AnimatedBuilder(
        animation: _pulseAnim,
        builder: (_, _) => SizedBox(
          width: 140,
          height: 140,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: _pulseAnim.value,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: ringColor.withAlpha(
                        (100 * (1.35 - _pulseAnim.value) / 0.35).round(),
                      ),
                      width: 2.5,
                    ),
                  ),
                ),
              ),
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1E2030),
                  border: Border.all(color: ringColor, width: 3),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  size: 48,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF1E2030),
        border: Border.all(
          color: _callStatus == CallStatus.accepted
              ? const Color(0xFF22C55E)
              : const Color(0xFF6B7280),
          width: 3,
        ),
      ),
      child: const Icon(
        Icons.person_rounded,
        size: 48,
        color: Color(0xFF6B7280),
      ),
    );
  }

  Widget _buildConnectionStages() {
    // Show nothing while ringing (status text already covers it)
    if (_callStatus == CallStatus.ringing &&
        !_channelReady &&
        _stageError == null) {
      return const SizedBox.shrink();
    }

    // Determine overall connection state
    final bool isConnected = _channelReady && _audioReady;
    final bool hasFailed = _stageError != null;

    if (!isConnected && !hasFailed) {
      // Still connecting — show a subtle spinner
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Connecting...',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ],
      );
    }

    if (hasFailed) {
      return Text(
        'Connection failed',
        style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13),
        textAlign: TextAlign.center,
      );
    }

    // Connected — nothing extra needed (status text shows "Connected")
    return const SizedBox.shrink();
  }

  Widget _buildStatusText() {
    switch (_callStatus) {
      case CallStatus.ringing:
        return widget.isCaller
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Ringing...',
                    style: TextStyle(
                      color: AppTheme.primaryColor,
                      fontSize: 15,
                    ),
                  ),
                ],
              )
            : const Text(
                'Incoming call',
                style: TextStyle(color: Color(0xFF22C55E), fontSize: 15),
              );
      case CallStatus.accepted:
        return const Text(
          'Connected',
          style: TextStyle(color: Color(0xFF22C55E), fontSize: 15),
        );
      case CallStatus.ended:
        return Text(
          'Call ended',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 15,
          ),
        );
      case CallStatus.declined:
        return const Text(
          'Call declined',
          style: TextStyle(color: Color(0xFFEF4444), fontSize: 15),
        );
      case CallStatus.missed:
        return const Text(
          'Missed call',
          style: TextStyle(color: Color(0xFFEF4444), fontSize: 15),
        );
      case CallStatus.failed:
        return const Text(
          'Call failed',
          style: TextStyle(color: Color(0xFFEF4444), fontSize: 15),
        );
    }
  }

  Widget _buildControls() {
    switch (_callStatus) {
      case CallStatus.ringing:
        if (!widget.isCaller) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _CallButton(
                icon: Icons.call_end_rounded,
                color: const Color(0xFFEF4444),
                label: 'Decline',
                onTap: _declineCall,
              ),
              _CallButton(
                icon: Icons.call_rounded,
                color: const Color(0xFF22C55E),
                label: 'Accept',
                onTap: _acceptCall,
              ),
            ],
          );
        }
        return _CallButton(
          icon: Icons.call_end_rounded,
          color: const Color(0xFFEF4444),
          label: 'Cancel',
          onTap: _endCall,
          large: true,
        );
      case CallStatus.accepted:
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _CallButton(
              icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              color: _isMuted
                  ? const Color(0xFFEF4444)
                  : const Color(0xFF2A2D3E),
              label: _isMuted ? 'Unmute' : 'Mute',
              onTap: () {
                setState(() => _isMuted = !_isMuted);
                _agora.setMuted(_isMuted);
              },
            ),
            _CallButton(
              icon: Icons.call_end_rounded,
              color: const Color(0xFFEF4444),
              label: 'End',
              onTap: _endCall,
              large: true,
            ),
            _CallButton(
              icon: _isSpeaker
                  ? Icons.volume_up_rounded
                  : Icons.volume_down_rounded,
              color: _isSpeaker
                  ? AppTheme.primaryColor
                  : const Color(0xFF2A2D3E),
              label: 'Speaker',
              onTap: () {
                setState(() => _isSpeaker = !_isSpeaker);
                _agora.setSpeaker(_isSpeaker);
              },
            ),
          ],
        );
      default:
        return Text(
          'Call Ended',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 16,
          ),
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _CallButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final bool large;

  const _CallButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = large ? 72.0 : 56.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: large ? 32 : 24),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
