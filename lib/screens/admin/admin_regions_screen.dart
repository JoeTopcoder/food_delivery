import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../models/delivery_region_model.dart';
import '../../providers/delivery_region_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';

class AdminRegionsScreen extends ConsumerStatefulWidget {
  const AdminRegionsScreen({super.key});

  @override
  ConsumerState<AdminRegionsScreen> createState() => _AdminRegionsScreenState();
}

class _AdminRegionsScreenState extends ConsumerState<AdminRegionsScreen> {
  static const _defaultLat = 18.1096;
  static const _defaultLng = -77.2975;

  final MapController _mapController = MapController();
  String? _selectedRegionId;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  static LatLng _centroid(List<LatLng> pts) {
    double lat = 0, lng = 0;
    for (final p in pts) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / pts.length, lng / pts.length);
  }

  Widget _buildMap(List<DeliveryRegion> regions) {
    LatLng center = const LatLng(_defaultLat, _defaultLng);
    if (regions.isNotEmpty) {
      final first = regions.first;
      center = first.hasPolygon
          ? _centroid(first.polygon!)
          : LatLng(first.latitude, first.longitude);
    }

    final polygonRegions = regions.where((r) => r.hasPolygon).toList();
    final circleRegions = regions.where((r) => !r.hasPolygon).toList();

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(16),
        bottomRight: Radius.circular(16),
      ),
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(initialCenter: center, initialZoom: 10),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'sevendash.app',
          ),
          PolygonLayer(
            polygons: polygonRegions.map((r) {
              final isSelected = r.id == _selectedRegionId;
              final color = r.isActive
                  ? const Color(0xFF10B981)
                  : const Color(0xFF9CA3AF);
              return Polygon(
                points: r.polygon!,
                color: color.withValues(alpha: isSelected ? 0.35 : 0.18),
                borderColor: color.withValues(alpha: isSelected ? 1.0 : 0.6),
                borderStrokeWidth: isSelected ? 3 : 1.5,
              );
            }).toList(),
          ),
          CircleLayer(
            circles: circleRegions.map((r) {
              final isSelected = r.id == _selectedRegionId;
              final color = r.isActive
                  ? const Color(0xFF10B981)
                  : const Color(0xFF9CA3AF);
              return CircleMarker(
                point: LatLng(r.latitude, r.longitude),
                radius: r.radiusKm * 1000,
                useRadiusInMeter: true,
                color: color.withValues(alpha: isSelected ? 0.35 : 0.18),
                borderColor: color.withValues(alpha: isSelected ? 1.0 : 0.6),
                borderStrokeWidth: isSelected ? 3 : 1.5,
              );
            }).toList(),
          ),
          MarkerLayer(
            markers: regions.map((r) {
              final point = r.hasPolygon
                  ? _centroid(r.polygon!)
                  : LatLng(r.latitude, r.longitude);
              return Marker(
                point: point,
                width: 32,
                height: 32,
                child: GestureDetector(
                  onTap: () {
                    setState(() => _selectedRegionId = r.id);
                    _mapController.move(point, 12);
                  },
                  child: Icon(
                    r.hasPolygon ? Icons.pentagon_outlined : Icons.location_on,
                    color: r.isActive
                        ? const Color(0xFF10B981)
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

  Widget _buildRegionCard(DeliveryRegion region) {
    final isSelected = region.id == _selectedRegionId;
    final center = region.hasPolygon
        ? _centroid(region.polygon!)
        : LatLng(region.latitude, region.longitude);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? const BorderSide(color: Color(0xFF10B981), width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() => _selectedRegionId = region.id);
          _mapController.move(center, 12);
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    region.hasPolygon
                        ? Icons.pentagon_outlined
                        : Icons.map_rounded,
                    color: region.isActive
                        ? const Color(0xFF10B981)
                        : const Color(0xFF9CA3AF),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      region.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Switch(
                    value: region.isActive,
                    activeThumbColor: const Color(0xFF10B981),
                    onChanged: (_) => _toggleRegion(region),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _infoChip(
                    context,
                    region.hasPolygon
                        ? Icons.draw_outlined
                        : Icons.circle_outlined,
                    region.hasPolygon
                        ? '${region.polygon!.length}-point polygon'
                        : '${region.radiusKm.toStringAsFixed(1)} km radius',
                  ),
                  const SizedBox(width: 8),
                  _infoChip(
                    context,
                    Icons.gps_fixed,
                    '${center.latitude.toStringAsFixed(4)}, ${center.longitude.toStringAsFixed(4)}',
                  ),
                ],
              ),
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
                  onPressed: () => _deleteRegion(region),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _infoChip(BuildContext context, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF6B7280).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  Future<void> _toggleRegion(DeliveryRegion region) async {
    final service = ref.read(deliveryRegionServiceProvider);
    await service.update(region.id, {'is_active': !region.isActive});
    ref.invalidate(allRegionsProvider);
  }

  Future<void> _deleteRegion(DeliveryRegion region) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Region'),
        content: Text('Delete "${region.name}"?'),
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
      final service = ref.read(deliveryRegionServiceProvider);
      await service.delete(region.id);
      if (_selectedRegionId == region.id)
        setState(() => _selectedRegionId = null);
      ref.invalidate(allRegionsProvider);
    }
  }

  Future<void> _openMapPicker(BuildContext ctx) async {
    final result = await Navigator.of(ctx).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const _RegionPolygonPicker()),
    );
    if (result != null && ctx.mounted) {
      try {
        final service = ref.read(deliveryRegionServiceProvider);
        await service.create(
          name: result['name'] as String,
          latitude: result['latitude'] as double,
          longitude: result['longitude'] as double,
          radiusKm: result['radiusKm'] as double,
          polygon: result['polygon'] as List<LatLng>?,
        );
        ref.invalidate(allRegionsProvider);
        if (ctx.mounted) {
          AppSnackbar.success(ctx, 'Region "${result['name']}" saved');
        }
      } catch (e) {
        if (ctx.mounted) {
          AppSnackbar.error(ctx, friendlyError(e));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final regionsAsync = ref.watch(allRegionsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Delivery Regions',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF004E89),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openMapPicker(context),
        backgroundColor: AppTheme.primaryColor,
        icon: const Icon(Icons.draw, color: Colors.white),
        label: const Text('Draw Region', style: TextStyle(color: Colors.white)),
      ),
      body: regionsAsync.when(
        loading: () => const AppLoadingIndicator(message: 'Loading regions...'),
        error: (e, _) => AppErrorState(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(allRegionsProvider),
        ),
        data: (regions) {
          if (regions.isEmpty) {
            return Column(
              children: [
                Expanded(flex: 2, child: _buildMap(regions)),
                const Expanded(
                  child: AppEmptyState(
                    icon: Icons.map_rounded,
                    title: 'No delivery regions configured',
                    subtitle: 'Tap "Draw Region" to draw a polygon on the map',
                  ),
                ),
              ],
            );
          }
          return Column(
            children: [
              Expanded(flex: 2, child: _buildMap(regions)),
              Expanded(
                flex: 3,
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: regions.length,
                  itemBuilder: (_, i) => _buildRegionCard(regions[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// _____________________________________________________________________________
// Polygon drawing picker
// _____________________________________________________________________________

class _RegionPolygonPicker extends StatefulWidget {
  const _RegionPolygonPicker();

  @override
  State<_RegionPolygonPicker> createState() => _RegionPolygonPickerState();
}

class _RegionPolygonPickerState extends State<_RegionPolygonPicker> {
  static const _defaultLat = 18.1096;
  static const _defaultLng = -77.2975;

  final MapController _mapController = MapController();
  final List<LatLng> _points = [];
  final _nameCtrl = TextEditingController();

  @override
  void dispose() {
    _mapController.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  LatLng get _centroid {
    if (_points.isEmpty) return const LatLng(_defaultLat, _defaultLng);
    double lat = 0, lng = 0;
    for (final p in _points) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / _points.length, lng / _points.length);
  }

  void _addPoint(LatLng pt) => setState(() => _points.add(pt));
  void _undoLast() {
    if (_points.isNotEmpty) setState(() => _points.removeLast());
  }

  void _clearAll() => setState(() => _points.clear());

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      AppSnackbar.warning(context, 'Enter a region name');
      return;
    }
    if (_points.length < 3) {
      AppSnackbar.warning(
        context,
        'Tap at least 3 points on the map to draw the region',
      );
      return;
    }
    final c = _centroid;
    Navigator.pop(context, {
      'name': name,
      'latitude': c.latitude,
      'longitude': c.longitude,
      'radiusKm': 10.0,
      'polygon': List<LatLng>.from(_points),
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasPolygon = _points.length >= 3;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Draw Region',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF004E89),
        foregroundColor: Colors.white,
        actions: [
          if (_points.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: 'Undo last point',
              onPressed: _undoLast,
            ),
          if (_points.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              tooltip: 'Clear all',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(_defaultLat, _defaultLng),
              initialZoom: 11,
              onTap: (_, point) => _addPoint(point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'sevendash.app',
              ),
              if (hasPolygon)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: _points,
                      color: const Color(0xFF10B981).withValues(alpha: 0.25),
                      borderColor: const Color(0xFF10B981),
                      borderStrokeWidth: 2.5,
                    ),
                  ],
                ),
              PolylineLayer(
                polylines: [
                  if (_points.length >= 2)
                    Polyline(
                      points: [..._points, if (hasPolygon) _points.first],
                      color: const Color(0xFF10B981),
                      strokeWidth: 2,
                      pattern: const StrokePattern.dotted(),
                    ),
                ],
              ),
              MarkerLayer(
                markers: _points.asMap().entries.map((e) {
                  final isFirst = e.key == 0;
                  return Marker(
                    point: e.value,
                    width: isFirst ? 20 : 14,
                    height: isFirst ? 20 : 14,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isFirst ? const Color(0xFF10B981) : Colors.white,
                        border: Border.all(
                          color: const Color(0xFF10B981),
                          width: 2,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),

          // Instruction banner
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _points.isEmpty
                    ? 'Tap the map to place polygon points'
                    : _points.length < 3
                    ? 'Keep tapping — need ${3 - _points.length} more point(s)'
                    : '${_points.length} points  •  tap to add more',
                style: const TextStyle(color: Colors.white, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          // Bottom panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.of(context).padding.bottom,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Region Name',
                      hintText: 'e.g. George Town',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_points.length} point${_points.length == 1 ? "" : "s"} placed',
                        style: TextStyle(
                          fontSize: 13,
                          color: hasPolygon
                              ? const Color(0xFF10B981)
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_points.isNotEmpty)
                        TextButton.icon(
                          icon: const Icon(Icons.undo, size: 16),
                          label: const Text('Undo'),
                          onPressed: _undoLast,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check, color: Colors.white),
                      label: const Text(
                        'Save Region',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: hasPolygon
                            ? const Color(0xFF10B981)
                            : Colors.grey,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: hasPolygon ? _submit : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
