import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/driver_intelligence_models.dart';
import '../../providers/driver_intelligence_provider.dart';
import '../../utils/app_theme.dart';

class DemandHeatmapScreen extends ConsumerWidget {
  const DemandHeatmapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zonesAsync = ref.watch(demandZonesProvider);
    // Keep realtime updates flowing
    ref.watch(zoneRealtimeProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      body: zonesAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
        error: (e, _) => Center(
          child: Text('$e', style: const TextStyle(color: Colors.redAccent)),
        ),
        data: (zones) => _HeatmapBody(zones: zones),
      ),
    );
  }
}

class _HeatmapBody extends StatefulWidget {
  final List<DemandZone> zones;
  const _HeatmapBody({required this.zones});

  @override
  State<_HeatmapBody> createState() => _HeatmapBodyState();
}

class _HeatmapBodyState extends State<_HeatmapBody> {
  bool _showList = false;

  @override
  Widget build(BuildContext context) {
    final zones = widget.zones;
    // Default center: Cayman Islands (George Town)
    // Center map on active zones (those with orders), or all zones
    final activeZones = zones.where((z) => z.activeOrders > 0).toList();
    final targetZones = activeZones.isNotEmpty ? activeZones : zones;
    final center = targetZones.isNotEmpty
        ? LatLng(
            targetZones.map((z) => z.latitude).reduce((a, b) => a + b) /
                targetZones.length,
            targetZones.map((z) => z.longitude).reduce((a, b) => a + b) /
                targetZones.length,
          )
        : const LatLng(18.0095, -76.7936); // Kingston, Jamaica

    return Stack(
      children: [
        // ── Full screen map ─────────────────────────────────────
        FlutterMap(
          options: MapOptions(initialCenter: center, initialZoom: 13),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.foodhub.delivery',
            ),
            // Surge radius circles
            CircleLayer(
              circles: zones.map((z) {
                final color = _zoneColor(z);
                return CircleMarker(
                  point: LatLng(z.latitude, z.longitude),
                  radius: z.radiusKm * 300, // approximate pixel radius
                  color: color.withValues(alpha: 0.15),
                  borderColor: color.withValues(alpha: 0.5),
                  borderStrokeWidth: 2,
                  useRadiusInMeter: true,
                );
              }).toList(),
            ),
            // Zone markers
            MarkerLayer(
              markers: zones.map((z) {
                final color = _zoneColor(z);
                return Marker(
                  point: LatLng(z.latitude, z.longitude),
                  width: 80,
                  height: 56,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.4),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: z.hasSurge
                            ? Text(
                                '${z.surgeMultiplier.toStringAsFixed(1)}x',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              )
                            : Text(
                                z.demandLevel[0].toUpperCase() +
                                    z.demandLevel.substring(1),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        z.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),

        // ── App bar overlay ─────────────────────────────────────
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(
              16,
              MediaQuery.of(context).padding.top + 8,
              16,
              12,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F1117), Colors.transparent],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                ),
                const Expanded(
                  child: Text(
                    'Demand Heatmap',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _showList = !_showList),
                  icon: Icon(
                    _showList ? Icons.map_rounded : Icons.list_rounded,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Legend ──────────────────────────────────────────────
        Positioned(
          bottom: 16,
          left: 16,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2030).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2A2D3E)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Demand Levels',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                SizedBox(height: 8),
                _LegendRow(
                  color: Color(0xFFEF4444),
                  label: 'Very High (2x+ surge)',
                ),
                SizedBox(height: 4),
                _LegendRow(
                  color: Color(0xFFF97316),
                  label: 'High (1.5x surge)',
                ),
                SizedBox(height: 4),
                _LegendRow(color: Color(0xFFFBBF24), label: 'Moderate'),
                SizedBox(height: 4),
                _LegendRow(color: Color(0xFF22C55E), label: 'Normal'),
                SizedBox(height: 4),
                _LegendRow(color: Color(0xFF6B7280), label: 'Low'),
              ],
            ),
          ),
        ),

        // ── Zone list bottom sheet ──────────────────────────────
        if (_showList)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFF1E2030),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[700],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.bolt_rounded,
                          color: Color(0xFFF59E0B),
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Zone Activity',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: zones.length,
                      shrinkWrap: true,
                      itemBuilder: (_, i) => _ZoneListItem(zone: zones[i]),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Color _zoneColor(DemandZone z) {
    if (z.surgeMultiplier >= 2.0) return const Color(0xFFEF4444);
    if (z.surgeMultiplier >= 1.5) return const Color(0xFFF97316);
    switch (z.demandLevel) {
      case 'very_high':
        return const Color(0xFFEF4444);
      case 'high':
        return const Color(0xFFF97316);
      case 'moderate':
        return const Color(0xFFFBBF24);
      case 'low':
        return const Color(0xFF6B7280);
      default:
        return const Color(0xFF22C55E);
    }
  }
}

// ─── Legend Row ────────────────────────────────────────────────────────────────

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendRow({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 11)),
      ],
    );
  }
}

// ─── Zone List Item ───────────────────────────────────────────────────────────

class _ZoneListItem extends StatelessWidget {
  final DemandZone zone;
  const _ZoneListItem({required this.zone});

  @override
  Widget build(BuildContext context) {
    final Color color;
    if (zone.surgeMultiplier >= 2.0) {
      color = const Color(0xFFEF4444);
    } else if (zone.surgeMultiplier >= 1.5) {
      color = const Color(0xFFF97316);
    } else if (zone.demandLevel == 'high' || zone.demandLevel == 'very_high') {
      color = const Color(0xFFF97316);
    } else if (zone.demandLevel == 'moderate') {
      color = const Color(0xFFFBBF24);
    } else if (zone.demandLevel == 'low') {
      color = const Color(0xFF6B7280);
    } else {
      color = const Color(0xFF22C55E);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1117),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: zone.hasSurge
                ? Center(
                    child: Text(
                      '${zone.surgeMultiplier.toStringAsFixed(1)}x',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  )
                : Icon(Icons.location_on_rounded, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  zone.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '${zone.activeOrders} orders',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    Text('•', style: TextStyle(color: Colors.grey[600])),
                    const SizedBox(width: 8),
                    Text(
                      '${zone.availableDrivers} drivers',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  zone.demandLevel.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ),
              if (zone.hasSurge) ...[
                const SizedBox(height: 4),
                Text(
                  '⚡ ${zone.surgeMultiplier.toStringAsFixed(1)}x surge',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
