import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/customer_vehicle.dart';
import '../../providers/car_services_providers.dart';
import 'add_edit_vehicle_screen.dart';

const _kBlue = Color(0xFF1D4ED8);

class MyVehiclesScreen extends ConsumerWidget {
  const MyVehiclesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehiclesAsync = ref.watch(myVehiclesProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('My Vehicles'),
        backgroundColor: _kBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _kBlue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Vehicle'),
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(
            builder: (_) => const AddEditVehicleScreen(),
          ));
          ref.invalidate(myVehiclesProvider);
        },
      ),
      body: vehiclesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (vehicles) {
          if (vehicles.isEmpty) {
            return _EmptyState(onAdd: () async {
              await Navigator.push(context, MaterialPageRoute(
                builder: (_) => const AddEditVehicleScreen(),
              ));
              ref.invalidate(myVehiclesProvider);
            });
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myVehiclesProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: vehicles.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _VehicleCard(
                vehicle: vehicles[i],
                onEdit: () async {
                  await Navigator.push(context, MaterialPageRoute(
                    builder: (_) => AddEditVehicleScreen(vehicle: vehicles[i]),
                  ));
                  ref.invalidate(myVehiclesProvider);
                },
                onDelete: () async {
                  final ok = await _confirmDelete(context);
                  if (!ok) return;
                  await ref.read(customerVehicleServiceProvider).deleteVehicle(vehicles[i].id);
                  ref.invalidate(myVehiclesProvider);
                },
                onSetDefault: () async {
                  await ref.read(customerVehicleServiceProvider).setDefault(vehicles[i].id);
                  ref.invalidate(myVehiclesProvider);
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Vehicle'),
        content: const Text('Remove this vehicle from your account?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ?? false;
  }
}

class _VehicleCard extends StatelessWidget {
  final CustomerVehicle vehicle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSetDefault;

  const _VehicleCard({
    required this.vehicle,
    required this.onEdit,
    required this.onDelete,
    required this.onSetDefault,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: vehicle.isDefault
            ? Border.all(color: _kBlue, width: 2)
            : Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _VehiclePhoto(photoUrl: vehicle.photoUrl, vehicleType: vehicle.vehicleType),
        title: Row(
          children: [
            Expanded(
              child: Text(vehicle.displayName, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Theme.of(context).colorScheme.onSurface)),
            ),
            if (vehicle.isDefault)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: _kBlue, borderRadius: BorderRadius.circular(20)),
                child: const Text('Default', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (vehicle.color != null)
                Text(vehicle.color!, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              if (vehicle.licensePlate != null)
                Text(vehicle.licensePlate!, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant, fontFamily: 'monospace')),
              const SizedBox(height: 4),
              Text(_typeLabel(vehicle.vehicleType), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'edit') onEdit();
            if (v == 'delete') onDelete();
            if (v == 'default') onSetDefault();
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            if (!vehicle.isDefault)
              const PopupMenuItem(value: 'default', child: Text('Set as Default')),
            const PopupMenuItem(value: 'delete', child: Text('Remove', style: TextStyle(color: Colors.red))),
          ],
        ),
      ),
    );
  }

  String _typeLabel(String t) => const {
    'sedan': 'Sedan', 'suv': 'SUV', 'van': 'Van',
    'truck': 'Truck', 'bike': 'Motorcycle',
  }[t] ?? t;
}

class _VehiclePhoto extends StatelessWidget {
  final String? photoUrl;
  final String vehicleType;
  const _VehiclePhoto({this.photoUrl, required this.vehicleType});

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(photoUrl!, width: 60, height: 60, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _icon(context),
        ),
      );
    }
    return _icon(context);
  }

  Widget _icon(BuildContext context) => Container(
    width: 60, height: 60,
    decoration: BoxDecoration(color: _kBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
    child: Icon(_iconData(), color: _kBlue, size: 30),
  );

  IconData _iconData() => vehicleType == 'bike' ? Icons.two_wheeler : Icons.directions_car;
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.directions_car_outlined, size: 72, color: Theme.of(context).colorScheme.outlineVariant),
        const SizedBox(height: 16),
        Text('No vehicles yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(height: 8),
        Text('Add your car to speed up car wash bookings', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: _kBlue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
          icon: const Icon(Icons.add),
          label: const Text('Add Vehicle'),
          onPressed: onAdd,
        ),
      ]),
    ),
  );
}
