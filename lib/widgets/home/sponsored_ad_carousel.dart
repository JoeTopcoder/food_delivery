import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../config/supabase_config.dart';
import '../../models/catalog/ad_model.dart';
import '../../models/catalog/restaurant_model.dart';
import '../../providers/catalog/ads_provider.dart';
import '../../utils/app_theme.dart';
import '../common/app_cached_image.dart';

/// A single sponsored-ad slide (image or short video) rendered INSIDE the shared
/// home banner carousel. The parent carousel passes [isActive] = true only for
/// the currently visible page, so just one video plays at a time; it pauses and
/// disposes when the page changes, and pauses when the app backgrounds.
///
/// Video: muted autoplay, loops, no play/pause button (tap the mute control for
/// sound). Falls back to the thumbnail on load/playback failure. Analytics
/// (impression >=1s, video start/complete, CTA) are reported deduped per session.
class SponsoredAdSlide extends ConsumerStatefulWidget {
  final SponsoredAd ad;
  final bool isActive;

  /// Fired once the video has played through twice — the carousel waits for this
  /// before advancing off a video slide.
  final VoidCallback? onCompletedTwice;

  const SponsoredAdSlide({
    super.key,
    required this.ad,
    required this.isActive,
    this.onCompletedTwice,
  });

  @override
  ConsumerState<SponsoredAdSlide> createState() => _SponsoredAdSlideState();
}

class _SponsoredAdSlideState extends ConsumerState<SponsoredAdSlide>
    with WidgetsBindingObserver {
  VideoPlayerController? _video;
  bool _muted = false; // sound on by default
  bool _started = false;
  int _loops = 0;
  int _lastPosMs = 0;
  bool _signaledTwice = false;
  Timer? _impressionTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.isActive) _onActivate();
  }

  @override
  void didUpdateWidget(SponsoredAdSlide old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) _onActivate();
    if (!widget.isActive && old.isActive) _onDeactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _impressionTimer?.cancel();
    _disposeVideo();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _video?.pause();
    } else if (widget.isActive && _video != null && _video!.value.isInitialized) {
      _video!.play();
    }
  }

  void _onActivate() {
    // impression after 1 continuous second on screen (server dedupes per session)
    _impressionTimer?.cancel();
    _impressionTimer = Timer(const Duration(seconds: 1), () {
      if (mounted && widget.isActive) _log('impression');
    });
    if (widget.ad.isVideo && (widget.ad.playbackUrl?.isNotEmpty ?? false)) {
      _initVideo();
    }
  }

  void _onDeactivate() {
    _impressionTimer?.cancel();
    _disposeVideo();
    if (mounted) setState(() {});
  }

  Future<void> _initVideo() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.ad.playbackUrl!));
    _video = c;
    _started = false;
    _loops = 0;
    _lastPosMs = 0;
    _signaledTwice = false;
    try {
      await c.setLooping(true); // repeat the clip
      await c.setVolume(_muted ? 0 : 1); // sound on by default
      await c.initialize();
      if (!mounted || !widget.isActive || _video != c) {
        c.dispose();
        if (_video == c) _video = null;
        return;
      }
      c.addListener(_videoListener);
      await c.play();
      if (mounted) setState(() {});
    } catch (_) {
      if (_video == c) {
        c.dispose();
        _video = null;
      }
      if (mounted) setState(() {});
    }
  }

  void _disposeVideo() {
    final c = _video;
    if (c != null) {
      c.removeListener(_videoListener);
      c.pause();
      c.dispose();
      _video = null;
    }
    _muted = true;
  }

  void _videoListener() {
    final c = _video;
    if (c == null || !c.value.isInitialized) return;
    if (!_started && c.value.isPlaying) {
      _started = true;
      _log('video_start');
    }
    final pos = c.value.position.inMilliseconds;
    // With looping on, position jumps back to ~0 at the end of each play — detect
    // that wrap to count completions. Carousel waits for TWO completions.
    if (pos < _lastPosMs - 500) {
      _loops++;
      if (_loops == 1) _log('video_complete');
      if (_loops >= 2 && !_signaledTwice) {
        _signaledTwice = true;
        widget.onCompletedTwice?.call();
      }
    }
    _lastPosMs = pos;
  }

  void _toggleMute() {
    final c = _video;
    if (c == null) return;
    setState(() {
      _muted = !_muted;
      c.setVolume(_muted ? 0 : 1);
    });
  }

  void _log(String type) {
    final session = ref.read(adSessionIdProvider);
    ref.read(adsServiceProvider).recordEvent(
          campaignId: widget.ad.campaignId,
          eventType: type,
          sessionId: session,
          creativeId: widget.ad.creativeId,
          dedupeKey: '$session:${widget.ad.creativeId}:$type',
        );
  }

  Future<void> _onCta() async {
    _log('cta_click');
    try {
      final data = await SupabaseConfig.client
          .from('restaurants')
          .select()
          .eq('id', widget.ad.restaurantId)
          .single();
      final restaurant = Restaurant.fromJson(data);
      if (!mounted) return;
      Navigator.pushNamed(context, '/restaurant-detail', arguments: restaurant);
    } catch (_) {/* restaurant gone -> ignore */}
  }

  @override
  Widget build(BuildContext context) {
    final ad = widget.ad;
    final scheme = Theme.of(context).colorScheme;
    final showVideo = ad.isVideo && _video != null && _video!.value.isInitialized;

    Widget media;
    if (showVideo) {
      media = FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _video!.value.size.width,
          height: _video!.value.size.height,
          child: VideoPlayer(_video!),
        ),
      );
    } else if ((ad.thumbnailUrl ?? ad.playbackUrl)?.isNotEmpty ?? false) {
      media = AppCachedImage(
        url: ad.isVideo ? ad.thumbnailUrl : (ad.playbackUrl ?? ad.thumbnailUrl),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    } else {
      media = Container(color: scheme.surfaceContainerHighest);
    }

    return Semantics(
      label: 'Sponsored ad for ${ad.restaurantName ?? 'a restaurant'}'
          '${ad.headline != null ? ': ${ad.headline}' : ''}',
      button: true,
      child: GestureDetector(
        onTap: _onCta,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              media,
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.black.withValues(alpha: 0.55),
                      Colors.black.withValues(alpha: 0.10),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Sponsored',
                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ),
              if (showVideo)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Semantics(
                    label: _muted ? 'Unmute ad' : 'Mute ad',
                    button: true,
                    child: GestureDetector(
                      onTap: _toggleMute,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                        child: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                            color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (ad.restaurantName != null)
                            Text(ad.restaurantName!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                          if (ad.headline != null && ad.headline!.trim().isNotEmpty)
                            Text(ad.headline!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _onCta,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Order now', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
