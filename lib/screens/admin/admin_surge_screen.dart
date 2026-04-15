import 'dart:math';
import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../models/delivery_region_model.dart';
import '../../providers/delivery_region_provider.dart';
import '../../providers/feature_providers.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';

class AdminSurgeScreen extends ConsumerStatefulWidget {
  const AdminSurgeScreen({super.key});

  @override
  ConsumerState<AdminSurgeScreen> createState() => _AdminSurgeScreenState();
}

class _AdminSurgeScreenState extends ConsumerState<AdminSurgeScreen> {
  // Default to George Town, Grand Cayman
  static const _defaultLat = 19.2869;
  static const _defaultLng = -81.3812;

  final MapController _mapController = MapController();
  String? _selectedZoneId;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zonesAsync = ref.watch(allSurgeZonesProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text(
          'Surge Zones',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF004E89),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openMapPicker(context),
        backgroundColor: AppTheme.primaryColor,
        icon: const Icon(Icons.add_location_alt, color: Colors.white),
        label: const Text('New Zone', style: TextStyle(color: Colors.white)),
      ),
      body: zonesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (zones) {
          if (zones.isEmpty) {
            return Column(
              children: [
                Expanded(flex: 2, child: _buildMap(zones)),
                const Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt, size: 48, color: Color(0xFF9CA3AF)),
                        SizedBox(height: 8),
                        Text(
                          'No surge zones configured',
                          style: TextStyle(color: Color(0xFF6B7280)),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Tap + to place one on the map',
                          style: TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }
          return Column(
            children: [
              Expanded(flex: 2, child: _buildMap(zones)),
              Expanded(
                flex: 3,
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: zones.length,
                  itemBuilder: (_, i) => _buildZoneCard(zones[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMap(List<Map<String, dynamic>> zones) {
    LatLng center = const LatLng(_defaultLat, _defaultLng);
    double zoom = 11;

    if (zones.isNotEmpty) {
      final first = zones.first;
      center = LatLng(
        (first['latitude'] as num?)?.toDouble() ?? _defaultLat,
        (first['longitude'] as num?)?.toDouble() ?? _defaultLng,
      );
    }

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(16),
        bottomRight: Radius.circular(16),
      ),
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(initialCenter: center, initialZoom: zoom),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.foodhub.delivery',
          ),
          CircleLayer(
            circles: zones.map((zone) {
              final lat = (zone['latitude'] as num?)?.toDouble() ?? 0;
              final lng = (zone['longitude'] as num?)?.toDouble() ?? 0;
              final radiusKm = (zone['radius_km'] as num?)?.toDouble() ?? 3;
              final isActive = zone['is_active'] == true;
              final isSelected = zone['id'] == _selectedZoneId;
              return CircleMarker(
                point: LatLng(lat, lng),
                radius: radiusKm * 1000, // metres
                useRadiusInMeter: true,
                color: isActive
                    ? (isSelected
                          ? const Color(0xFFFFA630).withValues(alpha: 0.35)
                          : const Color(0xFFFFA630).withValues(alpha: 0.2))
                    : const Color(0xFF9CA3AF).withValues(alpha: 0.15),
                borderColor: isActive
                    ? (isSelected
                          ? const Color(0xFFFFA630)
                          : const Color(0xFFFFA630).withValues(alpha: 0.6))
                    : const Color(0xFF9CA3AF).withValues(alpha: 0.4),
                borderStrokeWidth: isSelected ? 3 : 1.5,
              );
            }).toList(),
          ),
          MarkerLayer(
            markers: zones.map((zone) {
              final lat = (zone['latitude'] as num?)?.toDouble() ?? 0;
              final lng = (zone['longitude'] as num?)?.toDouble() ?? 0;
              final isActive = zone['is_active'] == true;
              return Marker(
                point: LatLng(lat, lng),
                width: 32,
                height: 32,
                child: GestureDetector(
                  onTap: () {
                    setState(() => _selectedZoneId = zone['id']);
                    _mapController.move(LatLng(lat, lng), 13);
                  },
                  child: Icon(
                    Icons.bolt,
                    color: isActive
                        ? const Color(0xFFFFA630)
                        : const Color(0xFF9CA3AF),
                    size: 28,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildZoneCard(Map<String, dynamic> zone) {
    final isActive = zone['is_active'] == true;
    final isSelected = zone['id'] == _selectedZoneId;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? const BorderSide(color: Color(0xFFFFA630), width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          final lat = (zone['latitude'] as num?)?.toDouble() ?? _defaultLat;
          final lng = (zone['longitude'] as num?)?.toDouble() ?? _defaultLng;
          setState(() => _selectedZoneId = zone['id']);
          _mapController.move(LatLng(lat, lng), 13);
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.bolt,
                    color: isActive
                        ? const Color(0xFFFFA630)
                        : const Color(0xFF9CA3AF),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      zone['name'] ?? 'Zone',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Switch(
                    value: isActive,
                    activeThumbColor: const Color(0xFFFFA630),
                    onChanged: (_) => _toggleZone(zone),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _InfoChip(
                    Icons.percent,
                    '${((zone['multiplier'] as num? ?? 1) * 100 - 100).toStringAsFixed(0)}% surge',
                  ),
                  const SizedBox(width: 8),
                  _InfoChip(
                    Icons.circle_outlined,
                    '${zone['radius_km'] ?? 0} km radius',
                  ),
                ],
              ),
              if (zone['reason'] != null) ...[
                const SizedBox(height: 4),
                Text(
                  zone['reason'],
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: Colors.red,
                  ),
                  label: const Text(
                    'Delete',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                  onPressed: () => _deleteZone(zone),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ignore: non_constant_identifier_names
  Widget _InfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF6B7280).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFF6B7280)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  Future<void> _toggleZone(Map<String, dynamic> zone) async {
    final service = ref.read(surgeServiceProvider);
    await service.toggleSurgeZone(zone['id'], !(zone['is_active'] == true));
    ref.invalidate(allSurgeZonesProvider);
  }

  Future<void> _deleteZone(Map<String, dynamic> zone) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Zone'),
        content: Text('Delete "${zone['name']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final service = ref.read(surgeServiceProvider);
      await service.deleteSurgeZone(zone['id']);
      if (_selectedZoneId == zone['id']) {
        setState(() => _selectedZoneId = null);
      }
      ref.invalidate(allSurgeZonesProvider);
    }
  }

  Future<void> _openMapPicker(BuildContext ctx) async {
    final result = await Navigator.of(ctx).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const _SurgeZoneMapPicker()),
    );
    if (result != null && ctx.mounted) {
      final service = ref.read(surgeServiceProvider);
      final ok = await service.createSurgeZone(
        name: result['name'] as String,
        latitude: result['latitude'] as double,
        longitude: result['longitude'] as double,
        radiusKm: result['radiusKm'] as double,
        multiplier: result['multiplier'] as double,
        reason: result['reason'] as String?,
      );
      if (ctx.mounted) {
        if (ok) {
          AppSnackbar.success(ctx, 'Surge zone created');
        } else {
          AppSnackbar.error(ctx, 'Failed to create surge zone');
        }
      }
      ref.invalidate(allSurgeZonesProvider);
    }
  }
}

// ─── Full-screen Map Picker for creating a surge zone ──────────────────────

/// Haversine distance in km.
double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const R = 6371.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLng = (lng2 - lng1) * pi / 180;
  final a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) *
          cos(lat2 * pi / 180) *
          sin(dLng / 2) *
          sin(dLng / 2);
  return R * 2 * atan2(sqrt(a), sqrt(1 - a));
}

class _SurgeZoneMapPicker extends ConsumerStatefulWidget {
  const _SurgeZoneMapPicker();

  @override
  ConsumerState<_SurgeZoneMapPicker> createState() =>
      _SurgeZoneMapPickerState();
}

class _SurgeZoneMapPickerState extends ConsumerState<_SurgeZoneMapPicker> {
  static const _defaultLat = 18.1096;
  static const _defaultLng = -77.2975;

  final MapController _mapController = MapController();
  LatLng _pin = const LatLng(_defaultLat, _defaultLng);
  double _radiusKm = 3;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  /// Find the delivery region containing [point]. Returns null if outside all.
  DeliveryRegion? _containingRegion(
    LatLng point,
    List<DeliveryRegion> regions,
  ) {
    for (final r in regions) {
      final dist = _haversineKm(
        point.latitude,
        point.longitude,
        r.latitude,
        r.longitude,
      );
      if (dist <= r.radiusKm) return r;
    }
    return null;
  }

  /// Max surge radius so the surge circle fits within the enclosing region.
  double _maxAllowedRadius(LatLng point, List<DeliveryRegion> regions) {
    final region = _containingRegion(point, regions);
    if (region == null) return 0;
    final distToCenter = _haversineKm(
      point.latitude,
      point.longitude,
      region.latitude,
      region.longitude,
    );
    return (region.radiusKm - distToCenter).clamp(0.5, region.radiusKm);
  }

  @override
  Widget build(BuildContext context) {
    final regionsAsync = ref.watch(activeRegionsProvider);
    final regions = regionsAsync.valueOrNull ?? [];
    final maxRadius = regions.isEmpty ? 20.0 : _maxAllowedRadius(_pin, regions);
    final insideRegion =
        regions.isEmpty || _containingRegion(_pin, regions) != null;

    // Clamp current radius if it exceeds the new max
    if (_radiusKm > maxRadius && maxRadius > 0) {
      Future.microtask(() => setState(() => _radiusKm = maxRadius));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Pick Zone Location',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF004E89),
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _pin,
              initialZoom: 12,
              onTap: (_, point) => setState(() {
                _pin = point;
                // Auto-clamp radius to new max
                final newMax = regions.isEmpty
                    ? 20.0
                    : _maxAllowedRadius(point, regions);
                if (_radiusKm > newMax && newMax > 0) _radiusKm = newMax;
              }),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.foodhub.delivery',
              ),
              // Delivery region circles (green, behind surge)
              CircleLayer(
                circles: regions
                    .map(
                      (r) => CircleMarker(
                        point: LatLng(r.latitude, r.longitude),
                        radius: r.radiusKm * 1000,
                        useRadiusInMeter: true,
                        color: const Color(0xFF10B981).withValues(alpha: 0.10),
                        borderColor: const Color(
                          0xFF10B981,
                        ).withValues(alpha: 0.5),
                        borderStrokeWidth: 1.5,
                      ),
                    )
                    .toList(),
              ),
              // Surge zone circle
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: _pin,
                    radius: _radiusKm * 1000,
                    useRadiusInMeter: true,
                    color: (insideRegion ? const Color(0xFFFFA630) : Colors.red)
                        .withValues(alpha: 0.25),
                    borderColor: insideRegion
                        ? const Color(0xFFFFA630)
                        : Colors.red,
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _pin,
                    width: 40,
                    height: 40,
                    child: Icon(
                      Icons.bolt,
                      color: insideRegion
                          ? const Color(0xFFFFA630)
                          : Colors.red,
                      size: 36,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Hint
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: _HintChip(
                insideRegion
                    ? 'Tap the map to place the surge zone centre'
                    : 'Pin is outside delivery regions — move it inside',
              ),
            ),
          ),

          // Radius slider
          Positioned(
            left: 16,
            right: 16,
            bottom: 100,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.radar,
                        size: 18,
                        color: Color(0xFFFFA630),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Radius: ${_radiusKm.toStringAsFixed(1)} km',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      if (regions.isNotEmpty) ...[
                        const Spacer(),
                        Text(
                          'max ${maxRadius.toStringAsFixed(1)} km',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Slider(
                    value: _radiusKm.clamp(0.5, maxRadius.clamp(0.5, 20.0)),
                    min: 0.5,
                    max: maxRadius.clamp(0.5, 20.0),
                    divisions: ((maxRadius.clamp(0.5, 20.0) - 0.5) * 2)
                        .round()
                        .clamp(1, 39),
                    activeColor: const Color(0xFFFFA630),
                    label: '${_radiusKm.toStringAsFixed(1)} km',
                    onChanged: insideRegion
                        ? (v) => setState(() => _radiusKm = v)
                        : null,
                  ),
                ],
              ),
            ),
          ),

          // Coordinate display
          Positioned(
            left: 16,
            right: 16,
            bottom: 56,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Text(
                  '${_pin.latitude.toStringAsFixed(5)}, ${_pin.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF374151),
                  ),
                ),
              ),
            ),
          ),

          // Confirm button
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(
              child: SizedBox(
                height: 32,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: insideRegion
                        ? AppTheme.primaryColor
                        : Colors.grey,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text(
                    'Set Location',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: insideRegion ? () => _showDetailsDialog() : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDetailsDialog() {
    final nameCtrl = TextEditingController();
    final multiplierCtrl = TextEditingController(text: '1.5');
    final reasonCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.bolt, color: Color(0xFFFFA630)),
            SizedBox(width: 8),
            Text('Zone Details'),
          ],
        ),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Zone Name',
                    hintText: 'e.g. George Town Centre',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: multiplierCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Surge Multiplier',
                    hintText: '1.5 = 50% extra',
                    border: OutlineInputBorder(),
                    suffixText: 'x',
                  ),
                  validator: (v) {
                    final val = double.tryParse(v ?? '');
                    if (val == null || val < 1.0) return 'Min 1.0';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Reason (optional)',
                    hintText: 'e.g. High demand area',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 16,
                        color: Color(0xFF6B7280),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${_pin.latitude.toStringAsFixed(4)}, ${_pin.longitude.toStringAsFixed(4)} · ${_radiusKm.toStringAsFixed(1)} km',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Back'),
          ),
          ElevatedButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(dCtx); // close dialog
              Navigator.pop(context, {
                'name': nameCtrl.text.trim(),
                'latitude': _pin.latitude,
                'longitude': _pin.longitude,
                'radiusKm': _radiusKm,
                'multiplier': double.tryParse(multiplierCtrl.text) ?? 1.5,
                'reason': reasonCtrl.text.trim().isNotEmpty
                    ? reasonCtrl.text.trim()
                    : null,
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Create Zone'),
          ),
        ],
      ),
    );
  }
}

class _HintChip extends StatelessWidget {
  final String text;
  const _HintChip(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.touch_app, size: 16, color: Color(0xFF6B7280)),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
          ),
        ],
      ),
    );
  }
}
