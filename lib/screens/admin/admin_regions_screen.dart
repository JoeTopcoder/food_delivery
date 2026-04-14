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

  @override
  Widget build(BuildContext context) {
    final regionsAsync = ref.watch(allRegionsProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
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
        icon: const Icon(Icons.add_location_alt, color: Colors.white),
        label: const Text('New Region', style: TextStyle(color: Colors.white)),
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
                    subtitle: 'Tap + to create a region on the map',
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

  Widget _buildMap(List<DeliveryRegion> regions) {
    LatLng center = const LatLng(_defaultLat, _defaultLng);
    double zoom = 10;
    if (regions.isNotEmpty) {
      center = LatLng(regions.first.latitude, regions.first.longitude);
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
            circles: regions.map((r) {
              final isSelected = r.id == _selectedRegionId;
              return CircleMarker(
                point: LatLng(r.latitude, r.longitude),
                radius: r.radiusKm * 1000,
                useRadiusInMeter: true,
                color: r.isActive
                    ? (isSelected
                          ? const Color(0xFF10B981).withValues(alpha: 0.35)
                          : const Color(0xFF10B981).withValues(alpha: 0.18))
                    : const Color(0xFF9CA3AF).withValues(alpha: 0.15),
                borderColor: r.isActive
                    ? (isSelected
                          ? const Color(0xFF10B981)
                          : const Color(0xFF10B981).withValues(alpha: 0.6))
                    : const Color(0xFF9CA3AF).withValues(alpha: 0.4),
                borderStrokeWidth: isSelected ? 3 : 1.5,
              );
            }).toList(),
          ),
          MarkerLayer(
            markers: regions.map((r) {
              return Marker(
                point: LatLng(r.latitude, r.longitude),
                width: 32,
                height: 32,
                child: GestureDetector(
                  onTap: () {
                    setState(() => _selectedRegionId = r.id);
                    _mapController.move(LatLng(r.latitude, r.longitude), 12);
                  },
                  child: Icon(
                    Icons.location_on,
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
          _mapController.move(LatLng(region.latitude, region.longitude), 12);
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.map_rounded,
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
                    activeColor: const Color(0xFF10B981),
                    onChanged: (_) => _toggleRegion(region),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _InfoChip(
                    Icons.circle_outlined,
                    '${region.radiusKm.toStringAsFixed(1)} km radius',
                  ),
                  const SizedBox(width: 8),
                  _InfoChip(
                    Icons.gps_fixed,
                    '${region.latitude.toStringAsFixed(4)}, ${region.longitude.toStringAsFixed(4)}',
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
      if (_selectedRegionId == region.id) {
        setState(() => _selectedRegionId = null);
      }
      ref.invalidate(allRegionsProvider);
    }
  }

  Future<void> _openMapPicker(BuildContext ctx) async {
    final result = await Navigator.of(ctx).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const _RegionMapPicker()),
    );
    if (result != null && ctx.mounted) {
      final service = ref.read(deliveryRegionServiceProvider);
      await service.create(
        name: result['name'] as String,
        latitude: result['latitude'] as double,
        longitude: result['longitude'] as double,
        radiusKm: result['radiusKm'] as double,
      );
      ref.invalidate(allRegionsProvider);
    }
  }
}

// ─── Full-screen Map Picker for creating a delivery region ────────────────

class _RegionMapPicker extends StatefulWidget {
  const _RegionMapPicker();

  @override
  State<_RegionMapPicker> createState() => _RegionMapPickerState();
}

class _RegionMapPickerState extends State<_RegionMapPicker> {
  static const _defaultLat = 18.1096;
  static const _defaultLng = -77.2975;

  final MapController _mapController = MapController();
  LatLng _pin = const LatLng(_defaultLat, _defaultLng);
  double _radiusKm = 10;

  final _nameCtrl = TextEditingController();

  @override
  void dispose() {
    _mapController.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Pick Region Location',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF004E89),
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _pin,
              initialZoom: 11,
              onTap: (_, point) => setState(() => _pin = point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.foodhub.delivery',
              ),
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: _pin,
                    radius: _radiusKm * 1000,
                    useRadiusInMeter: true,
                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                    borderColor: const Color(0xFF10B981),
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _pin,
                    width: 36,
                    height: 36,
                    child: const Icon(
                      Icons.location_on,
                      color: Color(0xFF10B981),
                      size: 36,
                    ),
                  ),
                ],
              ),
            ],
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
                      hintText: 'e.g. Kingston Metro',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text(
                        'Radius:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Expanded(
                        child: Slider(
                          value: _radiusKm,
                          min: 1,
                          max: 50,
                          divisions: 49,
                          label: '${_radiusKm.toStringAsFixed(0)} km',
                          activeColor: const Color(0xFF10B981),
                          onChanged: (v) => setState(() => _radiusKm = v),
                        ),
                      ),
                      Text('${_radiusKm.toStringAsFixed(0)} km'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Lat ${_pin.latitude.toStringAsFixed(5)}, '
                    'Lng ${_pin.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check, color: Colors.white),
                      label: const Text(
                        'Create Region',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        final name = _nameCtrl.text.trim();
                        if (name.isEmpty) {
                          AppSnackbar.warning(context, 'Enter a region name');
                          return;
                        }
                        Navigator.pop(context, {
                          'name': name,
                          'latitude': _pin.latitude,
                          'longitude': _pin.longitude,
                          'radiusKm': _radiusKm,
                        });
                      },
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
