import 'customer_vehicle.dart';
import 'car_service_offering.dart';
import 'numeric_utils.dart';

class ServiceBookingItem {
  final String id;
  final String bookingId;
  final String serviceId;
  final String? vehicleId;
  final String serviceNameSnapshot;
  final Map<String, dynamic>? vehicleSnapshot;
  final double basePrice;
  final double vehiclePrice;
  final double addOnPrice;
  final int quantity;
  final double lineTotal;
  final DateTime createdAt;

  // Optional joined/transient fields (not persisted)
  final CustomerVehicle? vehicle;
  final CarServiceOffering? offering;

  const ServiceBookingItem({
    required this.id,
    required this.bookingId,
    required this.serviceId,
    this.vehicleId,
    required this.serviceNameSnapshot,
    this.vehicleSnapshot,
    required this.basePrice,
    required this.vehiclePrice,
    required this.addOnPrice,
    required this.quantity,
    required this.lineTotal,
    required this.createdAt,
    this.vehicle,
    this.offering,
  });

  factory ServiceBookingItem.fromMap(Map<String, dynamic> m) =>
      ServiceBookingItem(
        id: m['id'] as String,
        bookingId: m['booking_id'] as String,
        serviceId: m['service_id'] as String,
        vehicleId: m['vehicle_id'] as String?,
        serviceNameSnapshot: m['service_name_snapshot'] as String,
        vehicleSnapshot: m['vehicle_snapshot'] as Map<String, dynamic>?,
        basePrice: parseDoubleRequired(m['base_price']),
        vehiclePrice: parseDoubleRequired(m['vehicle_price']),
        addOnPrice: parseDoubleRequired(m['add_on_price']),
        quantity: m['quantity'] as int? ?? 1,
        lineTotal: parseDoubleRequired(m['line_total']),
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  Map<String, dynamic> toInsertMap() => {
        'booking_id': bookingId,
        'service_id': serviceId,
        if (vehicleId != null) 'vehicle_id': vehicleId,
        'service_name_snapshot': serviceNameSnapshot,
        if (vehicleSnapshot != null) 'vehicle_snapshot': vehicleSnapshot,
        'base_price': basePrice,
        'vehicle_price': vehiclePrice,
        'add_on_price': addOnPrice,
        'quantity': quantity,
        'line_total': lineTotal,
      };
}

/// Transient grouping used in the booking UI — not a DB model.
class VehicleServiceGroup {
  final CustomerVehicle vehicle;
  final List<CarServiceOffering> services;

  const VehicleServiceGroup({required this.vehicle, required this.services});

  double get subtotal => services.fold(0.0, (sum, s) => sum + s.basePrice);
}
