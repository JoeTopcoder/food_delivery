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

  Color get _accent =>
      widget.isCaller ? AppTheme.primaryColor : const Color(0xFF22C55E);

  String get _displayName => widget.otherPartyName ?? 'Order Participant';

  String get _initials {
    final parts = _displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1))
        .toUpperCase();
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1F35), Color(0xFF0B0D16)],
          ),
        ),
        child: Stack(
          children: [
            // Soft brand glow behind the avatar.
            Positioned(
              top: -60,
              left: -40,
              right: -40,
              height: 360,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [accent.withValues(alpha: 0.22), Colors.transparent],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 14),
                  _topLabel(),
                  const Spacer(flex: 2),
                  _buildAvatar(),
                  const SizedBox(height: 26),
                  Text(
                    _displayName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _statusPill(),
                  if (_callStatus == CallStatus.accepted) ...[
                    const SizedBox(height: 14),
                    Text(
                      _formattedDuration,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 1.5,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  _buildConnectionStages(),
                  const Spacer(flex: 3),
                  _buildControls(),
                  const SizedBox(height: 44),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topLabel() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.phone_in_talk_rounded, size: 15, color: _accent),
        const SizedBox(width: 6),
        Text(
          'QuickDash Call',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }

  Widget _statusPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: _buildStatusText(),
    );
  }

  Widget _buildAvatar() {
    final accent = _accent;
    final ringing = _callStatus == CallStatus.ringing;
    final connected = _callStatus == CallStatus.accepted;
    final borderColor = connected
        ? const Color(0xFF22C55E)
        : (ringing ? accent : const Color(0xFF6B7280));

    final core = Container(
      width: 116,
      height: 116,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.85),
            accent.withValues(alpha: 0.45),
          ],
        ),
        border: Border.all(color: borderColor, width: 3),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: connected || ringing ? 0.45 : 0.25),
            blurRadius: 28,
            spreadRadius: 2,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 42,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    if (!ringing) return core;

    // Animated pulse rings while ringing.
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, __) {
        final t = (_pulseAnim.value - 1.0) / 0.35; // 0..1
        return SizedBox(
          width: 180,
          height: 180,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: _pulseAnim.value,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: accent.withValues(alpha: 0.35 * (1 - t)),
                      width: 2,
                    ),
                  ),
                ),
              ),
              Transform.scale(
                scale: 1 + (_pulseAnim.value - 1) * 0.6,
                child: Container(
                  width: 132,
                  height: 132,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: accent.withValues(alpha: 0.5 * (1 - t)),
                      width: 2,
                    ),
                  ),
                ),
              ),
              core,
            ],
          ),
        );
      },
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
    final size = large ? 74.0 : 62.0;
    // "Glassy" neutral buttons keep a subtle translucent look; coloured action
    // buttons (accept/decline/end) stay solid with a matching glow.
    final isNeutral = color == const Color(0xFF2A2D3E);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isNeutral ? Colors.white.withValues(alpha: 0.08) : color,
            border: isNeutral
                ? Border.all(color: Colors.white.withValues(alpha: 0.14))
                : null,
            boxShadow: isNeutral
                ? null
                : [
                    BoxShadow(
                      color: color.withValues(alpha: 0.45),
                      blurRadius: 20,
                      spreadRadius: 1,
                    ),
                  ],
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Icon(icon, color: Colors.white, size: large ? 32 : 26),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
