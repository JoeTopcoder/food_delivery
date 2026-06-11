class PackageRecord {
  final String id;
  final String shippingCompanyId;
  final String trackingNumber;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final String? warehouseLocation;
  final String? deliveryAddress;
  final double? deliveryLat;
  final double? deliveryLng;
  final double? packageWeight;
  final String packageType;
  final double? packageValue;
  final String? barcodeData;
  final String packageStatus;
  final bool verified;
  final String? notes;

  const PackageRecord({
    required this.id,
    required this.shippingCompanyId,
    required this.trackingNumber,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.warehouseLocation,
    this.deliveryAddress,
    this.deliveryLat,
    this.deliveryLng,
    this.packageWeight,
    required this.packageType,
    this.packageValue,
    this.barcodeData,
    required this.packageStatus,
    required this.verified,
    this.notes,
  });

  factory PackageRecord.fromJson(Map<String, dynamic> j) => PackageRecord(
        id: j['id'] as String,
        shippingCompanyId: j['shipping_company_id'] as String,
        trackingNumber: j['tracking_number'] as String,
        customerId: j['customer_id'] as String?,
        customerName: j['customer_name'] as String?,
        customerPhone: j['customer_phone'] as String?,
        warehouseLocation: j['warehouse_location'] as String?,
        deliveryAddress: j['delivery_address'] as String?,
        deliveryLat: (j['delivery_lat'] as num?)?.toDouble(),
        deliveryLng: (j['delivery_lng'] as num?)?.toDouble(),
        packageWeight: (j['package_weight'] as num?)?.toDouble(),
        packageType: j['package_type'] as String? ?? 'small',
        packageValue: (j['package_value'] as num?)?.toDouble(),
        barcodeData: j['barcode_data'] as String?,
        packageStatus: j['package_status'] as String? ?? 'at_warehouse',
        verified: j['verified'] as bool? ?? false,
        notes: j['notes'] as String?,
      );

  String get displayWeight =>
      packageWeight != null ? '${packageWeight!.toStringAsFixed(1)} kg' : 'Unknown';

  String get displayValue =>
      packageValue != null ? '\$${packageValue!.toStringAsFixed(2)}' : 'Not declared';
}
