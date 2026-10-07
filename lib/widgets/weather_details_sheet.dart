import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/weather_model.dart';
import '../providers/weather_provider.dart';
import '../services/weather_service.dart';
import '../utils/app_theme.dart';
import '../utils/est_datetime.dart';

/// Opens the weather details bottom sheet for [query].
Future<void> showWeatherDetailsSheet(BuildContext context, WeatherQuery query) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _WeatherDetailsSheet(query: query),
  );
}

class _WeatherDetailsSheet extends ConsumerWidget {
  final WeatherQuery query;
  const _WeatherDetailsSheet({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(weatherProvider(query));
    // Clear both insets per the app's bottom-sheet convention (keyboard + nav
    // bar) so the refresh/attribution row is never under the system nav bar.
    final bottomInset =
        MediaQuery.of(context).padding.bottom +
        MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.82;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Flexible(
              child: async.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => _SheetError(
                  code: e is WeatherException ? e.code : 'weather_error',
                  onRetry: () => ref.invalidate(weatherProvider(query)),
                ),
                data: (w) => _Content(
                  weather: w,
                  query: query,
                  onRefresh: () => ref.invalidate(weatherProvider(query)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  final Weather weather;
  final WeatherQuery query;
  final VoidCallback onRefresh;
  const _Content({
    required this.weather,
    required this.query,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = weather.current;
    final place = (weather.location.name?.trim().isNotEmpty ?? false)
        ? weather.location.name!.trim()
        : (query.label ?? 'Your area');
    final isCurrentLoc = query.source == WeatherSource.currentLocation;

    // Hourly labels use the forecast location's timezone (the provider's hour
    // "time" strings are already local to that location), so we format them
    // directly without converting to the device zone.
    final hours = weather.upcomingHours(6);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                WeatherCodes.iconFor(c.conditionCode, isDay: c.isDay),
                color: AppTheme.primaryColor,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isCurrentLoc
                              ? Icons.my_location
                              : Icons.location_on,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            isCurrentLoc
                                ? 'Near your current location'
                                : 'Near $place',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      c.conditionText ?? 'Weather',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                c.tempC != null ? '${c.tempC!.round()}°C' : '--',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primaryColor,
                ),
              ),
            ],
          ),
          if (c.feelsLikeC != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Feels like ${c.feelsLikeC!.round()}°C',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ),

          if (weather.stale)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _Banner(
                color: Colors.orange,
                icon: Icons.history_rounded,
                text:
                    'Showing last known conditions — the weather service is '
                    'temporarily unavailable, so this may be out of date.',
              ),
            ),

          _deliveryMessage(context),

          const SizedBox(height: 16),
          // Metrics grid
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Metric(
                icon: Icons.water_drop_outlined,
                label: 'Humidity',
                value: c.humidity != null ? '${c.humidity}%' : '--',
              ),
              _Metric(
                icon: Icons.air_rounded,
                label: 'Wind',
                value: c.windKph != null
                    ? '${c.windKph!.round()} km/h'
                    : '--',
              ),
              _Metric(
                icon: Icons.umbrella_outlined,
                label: 'Precipitation',
                value: c.precipMm != null
                    ? '${c.precipMm!.toStringAsFixed(1)} mm'
                    : '--',
              ),
            ],
          ),

          const SizedBox(height: 18),
          Text(
            'Next hours',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          if (hours.isEmpty)
            Text(
              'Hourly forecast unavailable.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            )
          else
            SizedBox(
              height: 104,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: hours.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => _HourTile(hour: hours[i]),
              ),
            ),

          const SizedBox(height: 16),
          // Updated info + refresh
          Row(
            children: [
              Expanded(
                child: Text(
                  _updatedLine(weather),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // WeatherAPI.com attribution (free-plan requirement: link back).
          GestureDetector(
            onTap: () => launchUrl(
              Uri.parse('https://www.weatherapi.com/'),
              mode: LaunchMode.externalApplication,
            ),
            child: Text(
              'Powered by WeatherAPI.com',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.primaryColor,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deliveryMessage(BuildContext context) {
    final c = weather.current;
    final hours = weather.upcomingHours(6);
    final rainForecast = hours.any((h) => h.chanceOfRain >= 50);

    String? text;
    if (c.isCurrentlyRaining) {
      text = 'Rain near your delivery location may affect delivery times.';
    } else if (rainForecast) {
      text = 'Rain is forecast near your delivery location.';
    }
    if (text == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: _Banner(
        color: AppTheme.primaryColor,
        icon: Icons.umbrella_rounded,
        text: text,
      ),
    );
  }

  String _updatedLine(Weather w) {
    final parts = <String>[];
    if (w.providerObservedAt != null) {
      parts.add('Observed ${w.providerObservedAt!.jmRelative}');
    }
    if (w.retrievedAt != null) {
      parts.add('retrieved ${w.retrievedAt!.jmRelative}');
    }
    return parts.isEmpty ? 'Updated recently' : parts.join(' · ');
  }
}

class _HourTile extends StatelessWidget {
  final WeatherHour hour;
  const _HourTile({required this.hour});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = hour.time != null
        ? TimeOfDay.fromDateTime(hour.time!).format(context)
        : '--';
    return Container(
      width: 66,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            maxLines: 1,
          ),
          Icon(
            WeatherCodes.iconFor(hour.conditionCode, isDay: hour.isDay),
            size: 22,
            color: AppTheme.primaryColor,
          ),
          Text(
            hour.tempC != null ? '${hour.tempC!.round()}°' : '--',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.water_drop,
                size: 10,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 2),
              Text(
                '${hour.chanceOfRain}%',
                style: TextStyle(
                  fontSize: 10,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: (MediaQuery.of(context).size.width - 32 - 20) / 3,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: AppTheme.primaryColor),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  const _Banner({required this.color, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetError extends StatelessWidget {
  final String code;
  final VoidCallback onRetry;
  const _SheetError({required this.code, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 40),
          const SizedBox(height: 12),
          const Text(
            "Couldn't load weather.",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
