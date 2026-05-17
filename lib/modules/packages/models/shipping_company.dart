class ShippingCompany {
  final String id;
  final String name;
  final String? logoUrl;
  final String warehouseAddress;
  final double warehouseLat;
  final double warehouseLng;
  final String? supportEmail;
  final String? supportPhone;
  final String verificationType;
  final bool active;

  const ShippingCompany({
    required this.id,
    required this.name,
    this.logoUrl,
    required this.warehouseAddress,
    required this.warehouseLat,
    required this.warehouseLng,
    this.supportEmail,
    this.supportPhone,
    required this.verificationType,
    required this.active,
  });

  factory ShippingCompany.fromJson(Map<String, dynamic> j) => ShippingCompany(
        id: j['id'] as String,
        name: j['name'] as String,
        logoUrl: j['logo_url'] as String?,
        warehouseAddress: j['warehouse_address'] as String,
        warehouseLat: (j['warehouse_lat'] as num).toDouble(),
        warehouseLng: (j['warehouse_lng'] as num).toDouble(),
        supportEmail: j['support_email'] as String?,
        supportPhone: j['support_phone'] as String?,
        verificationType: j['verification_type'] as String? ?? 'manual',
        active: j['active'] as bool? ?? true,
      );
}
