import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/weather_model.dart';
import '../providers/weather_provider.dart';
import '../services/weather_service.dart';
import '../utils/app_theme.dart';
import '../utils/est_datetime.dart';
import 'weather_details_sheet.dart';

/// Compact weather card for the customer home screen. Sits below the delivery
/// address. Non-blocking: it watches an autoDispose FutureProvider and renders
/// its own loading / loaded / empty / stale / error states without holding up
/// the rest of the home screen. Tapping opens the details bottom sheet.
class WeatherCard extends ConsumerWidget {
  const WeatherCard({super.key});

  static const double _radius = 16;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(effectiveWeatherQueryProvider);

    if (query == null) {
      return _Shell(child: _NoLocation(ref: ref));
    }

    final async = ref.watch(weatherProvider(query));

    return async.when(
      loading: () => const _Shell(child: _LoadingSkeleton()),
      error: (e, _) => _Shell(
        child: _ErrorState(
          code: e is WeatherException ? e.code : 'weather_error',
          onRetry: () => ref.invalidate(weatherProvider(query)),
        ),
      ),
      data: (w) => _Shell(
        onTap: () => showWeatherDetailsSheet(context, query),
        child: _Loaded(weather: w, query: query),
      ),
    );
  }
}

/// Shared outer container so every state keeps identical size/shape/theming.
class _Shell extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _Shell({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(WeatherCard._radius),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryColor.withValues(alpha: 0.10),
                  AppTheme.primaryColor.withValues(alpha: 0.03),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(WeatherCard._radius),
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.14),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: scheme.onSurface),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _Loaded extends StatelessWidget {
  final Weather weather;
  final WeatherQuery query;
  const _Loaded({required this.weather, required this.query});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = weather.current;
    final isDay = c.isDay;
    final icon = WeatherCodes.iconFor(c.conditionCode, isDay: isDay);

    // Prefer the provider's resolved location name; fall back to the query
    // label (address label / "Current location").
    final place = (weather.location.name?.trim().isNotEmpty ?? false)
        ? weather.location.name!.trim()
        : (query.label ?? 'Your area');

    final isCurrentLoc = query.source == WeatherSource.currentLocation;
    final updated =
        weather.providerObservedAt?.jmRelative ??
        weather.retrievedAt?.jmRelative;

    final temp = c.tempC != null ? '${c.tempC!.round()}°C' : '--';
    final feels = c.feelsLikeC != null
        ? 'Feels like ${c.feelsLikeC!.round()}°C'
        : null;
    final condition = c.conditionText ?? '';

    return Row(
      children: [
        Icon(icon, color: AppTheme.primaryColor, size: 34),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      condition.isNotEmpty
                          ? '$condition near $place'
                          : 'Weather near $place',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    temp,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(
                    isCurrentLoc
                        ? Icons.my_location
                        : Icons.location_on_outlined,
                    size: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      [
                        if (feels != null) feels,
                        if (updated != null) 'Updated $updated',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              if (weather.stale)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: _StaleChip(),
                ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
      ],
    );
  }
}

class _StaleChip extends StatelessWidget {
  const _StaleChip();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_rounded, size: 11, color: Colors.orange),
          SizedBox(width: 3),
          Text(
            'Last known — may be out of date',
            style: TextStyle(
              fontSize: 10,
              color: Colors.orange,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();
  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08);
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(6),
      ),
    );
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: base, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            bar(160, 13),
            const SizedBox(height: 7),
            bar(110, 11),
          ],
        ),
      ],
    );
  }
}

class _NoLocation extends StatelessWidget {
  final WidgetRef ref;
  const _NoLocation({required this.ref});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.cloud_outlined, color: scheme.onSurfaceVariant, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Select a location to see the weather.',
            style: TextStyle(fontSize: 13, color: scheme.onSurface),
          ),
        ),
        _UseCurrentLocationButton(ref: ref),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String code;
  final VoidCallback onRetry;
  const _ErrorState({required this.code, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final msg = switch (code) {
      'invalid_coordinates' => 'Weather unavailable for this location.',
      'weather_quota' || 'weather_key_invalid' =>
        'Weather is temporarily unavailable.',
      _ => "Couldn't load weather.",
    };
    return Row(
      children: [
        Icon(Icons.cloud_off_outlined, color: scheme.onSurfaceVariant, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            msg,
            style: TextStyle(fontSize: 13, color: scheme.onSurface),
          ),
        ),
        TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Retry'),
        ),
      ],
    );
  }
}

/// "Use my current location" action. Requests GPS only when tapped, handles
/// denial gracefully, and never changes the delivery address.
class _UseCurrentLocationButton extends StatefulWidget {
  final WidgetRef ref;
  const _UseCurrentLocationButton({required this.ref});

  @override
  State<_UseCurrentLocationButton> createState() =>
      _UseCurrentLocationButtonState();
}

class _UseCurrentLocationButtonState
    extends State<_UseCurrentLocationButton> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    bool ok = false;
    try {
      ok = await useCurrentLocationForWeather(widget.ref);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location unavailable. Enable location services and permission to '
            'use your current location.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: _busy ? null : _run,
      icon: _busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.my_location, size: 16),
      label: const Text('Use my location', style: TextStyle(fontSize: 12)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
