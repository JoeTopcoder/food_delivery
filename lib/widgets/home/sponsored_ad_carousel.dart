import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../config/supabase_config.dart';
import '../../core/utils/responsive.dart';
import '../../models/catalog/ad_model.dart';
import '../../models/catalog/restaurant_model.dart';
import '../../providers/catalog/ads_provider.dart';
import '../../providers/auth_user/address_provider.dart';
import '../../utils/app_theme.dart';
import '../common/app_cached_image.dart';

/// Sponsored restaurant ads carousel (image + short video creatives). Rendered
/// below the ordinary promo banners; shows nothing when the feature is off or
/// there are no eligible ads. Non-blocking: any failure renders nothing.
///
/// Video behaviour: muted autoplay of only the CURRENTLY visible page, one at a
/// time; pauses when the page changes, the app backgrounds, or the widget is
/// disposed; sound requires a tap; falls back to the thumbnail on load/playback
/// failure. Analytics (impression ≥1s on screen, video start/complete, CTA
/// click) are reported deduped per session.
class SponsoredAdCarousel extends ConsumerWidget {
  const SponsoredAdCarousel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addr = ref.watch(selectedAddressProvider);
    final q = adQuery(addr?.latitude, addr?.longitude);
    final adsAsync = ref.watch(sponsoredAdsProvider(q));
    return adsAsync.maybeWhen(
      data: (ads) => ads.isEmpty ? const SizedBox.shrink() : _AdPager(ads: ads),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _AdPager extends ConsumerStatefulWidget {
  final List<SponsoredAd> ads;
  const _AdPager({required this.ads});
  @override
  ConsumerState<_AdPager> createState() => _AdPagerState();
}

class _AdPagerState extends ConsumerState<_AdPager>
    with WidgetsBindingObserver {
  final _pageCtrl = PageController();
  int _current = 0;
  Timer? _advanceTimer;
  Timer? _impressionTimer;
  bool _interacting = false; // user turned sound on / touched the video
  final Set<String> _impressed = {};

  VideoPlayerController? _video;
  int _videoForPage = -1;
  bool _muted = true;
  bool _startedLogged = false;
  bool _completeLogged = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onPage(0, first: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _advanceTimer?.cancel();
    _impressionTimer?.cancel();
    _video?.removeListener(_videoListener);
    _video?.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _video?.pause();
      _advanceTimer?.cancel();
    } else {
      if (_videoForPage == _current && _video != null && _video!.value.isInitialized) {
        _video!.play();
      }
      _armAdvance();
    }
  }

  SponsoredAd get _cur => widget.ads[_current];

  void _onPage(int i, {bool first = false}) {
    if (!mounted) return;
    setState(() => _current = i);
    _interacting = false;
    // teardown any previous video
    _teardownVideo();
    // impression: count once the page is on screen for 1 continuous second
    _impressionTimer?.cancel();
    _impressionTimer = Timer(const Duration(seconds: 1), () {
      if (mounted && _current == i) _logImpression(widget.ads[i]);
    });
    // set up video for this page if needed
    if (widget.ads[i].isVideo && (widget.ads[i].playbackUrl?.isNotEmpty ?? false)) {
      _initVideo(i);
    }
    _armAdvance();
  }

  void _teardownVideo() {
    _advanceTimer?.cancel();
    if (_video != null) {
      _video!.removeListener(_videoListener);
      _video!.pause();
      _video!.dispose();
      _video = null;
      _videoForPage = -1;
    }
    _muted = true;
    _startedLogged = false;
    _completeLogged = false;
  }

  Future<void> _initVideo(int page) async {
    final url = widget.ads[page].playbackUrl!;
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    _video = c;
    _videoForPage = page;
    try {
      await c.setLooping(false);
      await c.setVolume(0);
      await c.initialize();
      if (!mounted || _videoForPage != page || _current != page) {
        c.dispose();
        if (_video == c) _video = null;
        return;
      }
      c.addListener(_videoListener);
      await c.play();
      if (mounted) setState(() {});
    } catch (_) {
      // playback failed -> fall back to thumbnail (handled in build)
      if (_video == c) {
        c.dispose();
        _video = null;
        _videoForPage = -1;
      }
      if (mounted) setState(() {});
    }
  }

  void _videoListener() {
    final c = _video;
    if (c == null || !c.value.isInitialized) return;
    if (!_startedLogged && c.value.isPlaying) {
      _startedLogged = true;
      _logEvent(_cur, 'video_start');
    }
    final dur = c.value.duration.inMilliseconds;
    final pos = c.value.position.inMilliseconds;
    if (!_completeLogged && dur > 0 && pos >= dur * 0.95) {
      _completeLogged = true;
      _logEvent(_cur, 'video_complete');
    }
  }

  // Auto-advance: images dwell 6s; videos advance when finished (listener-driven
  // via the clamped duration), capped at 20s so a stalled video can't trap the
  // carousel. Never advance while the user is interacting with a video.
  void _armAdvance() {
    _advanceTimer?.cancel();
    if (widget.ads.length < 2 || _interacting) return;
    Duration dwell = const Duration(seconds: 6);
    if (_cur.isVideo) {
      final d = _video?.value.duration ?? const Duration(seconds: 10);
      dwell = d > const Duration(seconds: 20) ? const Duration(seconds: 20) : d;
      if (dwell < const Duration(seconds: 4)) dwell = const Duration(seconds: 6);
      dwell += const Duration(milliseconds: 400);
    }
    _advanceTimer = Timer(dwell, () {
      if (!mounted || _interacting) return;
      final next = (_current + 1) % widget.ads.length;
      _pageCtrl.animateToPage(next,
          duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    });
  }

  void _toggleMute() {
    final c = _video;
    if (c == null) return;
    setState(() {
      _muted = !_muted;
      c.setVolume(_muted ? 0 : 1);
      _interacting = !_muted; // unmuting = interacting -> stop auto-advance
    });
    if (_interacting) _advanceTimer?.cancel(); else _armAdvance();
  }

  void _logImpression(SponsoredAd ad) {
    if (_impressed.contains(ad.creativeId)) return;
    _impressed.add(ad.creativeId);
    _logEvent(ad, 'impression');
  }

  void _logEvent(SponsoredAd ad, String type) {
    final session = ref.read(adSessionIdProvider);
    ref.read(adsServiceProvider).recordEvent(
          campaignId: ad.campaignId,
          eventType: type,
          sessionId: session,
          creativeId: ad.creativeId,
          dedupeKey: '$session:${ad.creativeId}:$type',
        );
  }

  Future<void> _onCta(SponsoredAd ad) async {
    _logEvent(ad, 'cta_click');
    try {
      final data = await SupabaseConfig.client
          .from('restaurants')
          .select()
          .eq('id', ad.restaurantId)
          .single();
      final restaurant = Restaurant.fromJson(data);
      if (!mounted) return;
      // Revalidate: unavailable dish falls back to the restaurant menu.
      Navigator.pushNamed(context, '/restaurant-detail', arguments: restaurant);
    } catch (_) {
      // restaurant gone -> silently ignore (no broken navigation)
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = (MediaQuery.of(context).size.width * 0.34).clamp(140.0, 200.0);
    return Column(
      children: [
        SizedBox(
          height: h,
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: widget.ads.length,
            onPageChanged: (i) => _onPage(i),
            itemBuilder: (_, i) => _card(widget.ads[i], i),
          ),
        ),
        if (widget.ads.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              widget.ads.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _current == i ? 20 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _current == i
                      ? AppTheme.primaryColor
                      : Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _card(SponsoredAd ad, int index) {
    final scheme = Theme.of(context).colorScheme;
    final showVideo = ad.isVideo &&
        _videoForPage == index &&
        _video != null &&
        _video!.value.isInitialized;

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
        onTap: () => _onCta(ad),
        child: Container(
          margin: EdgeInsets.symmetric(
              horizontal: Responsive.horizontalPadding(context)),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              media,
              // Readability overlay
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
              // Sponsored label
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
              // Video controls (sound + play/pause) — only for the live video
              if (showVideo)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Row(children: [
                    _ctrlBtn(
                      icon: _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      label: _muted ? 'Unmute ad' : 'Mute ad',
                      onTap: _toggleMute,
                    ),
                    const SizedBox(width: 6),
                    _ctrlBtn(
                      icon: _video!.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      label: _video!.value.isPlaying ? 'Pause ad' : 'Play ad',
                      onTap: () {
                        setState(() {
                          if (_video!.value.isPlaying) {
                            _video!.pause();
                            _interacting = true;
                            _advanceTimer?.cancel();
                          } else {
                            _video!.play();
                          }
                        });
                      },
                    ),
                  ]),
                ),
              // Text + CTA
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
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                          if (ad.headline != null && ad.headline!.trim().isNotEmpty)
                            Text(ad.headline!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9), fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => _onCta(ad),
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

  Widget _ctrlBtn({required IconData icon, required String label, required VoidCallback onTap}) {
    return Semantics(
      label: label,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
      ),
    );
  }
}
