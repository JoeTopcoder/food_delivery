// Cooking Gas (LPG) module models. Money is stored server-side in JMD CENTS
// (bigint); these models keep cents and expose dollar getters for display.
import '../../../config/app_constants.dart';

int _int(dynamic v) => v == null ? 0 : (v is int ? v : int.tryParse(v.toString()) ?? 0);
double? _dbl(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse(v.toString()));
bool _bool(dynamic v) => v == true || v == 'true' || v == 1;

/// Format JMD cents for display, e.g. 500000 -> "J$5,000.00".
String gasMoney(int cents) {
  final d = cents / 100.0;
  final s = d.toStringAsFixed(2);
  // thousands separator on the integer part
  final parts = s.split('.');
  final intPart = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  return '${AppConstants.currencySymbol}$intPart.${parts[1]}';
}

class GasSupplier {
  final String id;
  final String ownerId;
  final String businessName;
  final String? contactPhone;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? logoUrl;
  final List<String> approvedBrands;
  final bool acceptingOrders;
  final bool deliveryOperational;
  final String verificationStatus;
  final bool isActive;

  const GasSupplier({
    required this.id,
    required this.ownerId,
    required this.businessName,
    this.contactPhone,
    this.address,
    this.latitude,
    this.longitude,
    this.logoUrl,
    this.approvedBrands = const [],
    this.acceptingOrders = false,
    this.deliveryOperational = false,
    this.verificationStatus = 'pending',
    this.isActive = true,
  });

  bool get isLive =>
      verificationStatus == 'approved' && isActive && deliveryOperational;
  bool get isOpen => isLive && acceptingOrders;

  factory GasSupplier.fromMap(Map<String, dynamic> m) => GasSupplier(
        id: m['id'].toString(),
        ownerId: m['owner_id']?.toString() ?? '',
        businessName: m['business_name']?.toString() ?? 'Gas Supplier',
        contactPhone: m['contact_phone']?.toString(),
        address: m['address']?.toString(),
        latitude: _dbl(m['latitude']),
        longitude: _dbl(m['longitude']),
        logoUrl: m['logo_url']?.toString(),
        approvedBrands: (m['approved_brands'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        acceptingOrders: _bool(m['accepting_orders']),
        deliveryOperational: _bool(m['delivery_operational']),
        verificationStatus: m['verification_status']?.toString() ?? 'pending',
        isActive: _bool(m['is_active']),
      );
}

class GasProduct {
  final String id;
  final String supplierId;
  final String brand;
  final String sizeLabel;
  final String? description;
  final String? imageUrl;
  final int? exchangePriceCents;
  final int? newPriceCents;
  final int depositCents;
  final int stockQty;
  final bool exchangeAvailable;
  final bool newAvailable;

  const GasProduct({
    required this.id,
    required this.supplierId,
    required this.brand,
    required this.sizeLabel,
    this.description,
    this.imageUrl,
    this.exchangePriceCents,
    this.newPriceCents,
    this.depositCents = 0,
    this.stockQty = 0,
    this.exchangeAvailable = true,
    this.newAvailable = false,
  });

  bool get inStock => stockQty > 0;

  factory GasProduct.fromMap(Map<String, dynamic> m) => GasProduct(
        id: m['id'].toString(),
        supplierId: m['supplier_id']?.toString() ?? '',
        brand: m['brand']?.toString() ?? '',
        sizeLabel: m['size_label']?.toString() ?? '',
        description: m['description']?.toString(),
        imageUrl: m['image_url']?.toString(),
        exchangePriceCents: m['exchange_price_cents'] == null ? null : _int(m['exchange_price_cents']),
        newPriceCents: m['new_price_cents'] == null ? null : _int(m['new_price_cents']),
        depositCents: _int(m['deposit_cents']),
        stockQty: _int(m['stock_qty']),
        exchangeAvailable: _bool(m['exchange_available']),
        newAvailable: _bool(m['new_available']),
      );
}

/// A line the customer is building before placing the order.
class GasCartLine {
  final GasProduct product;
  final String purchaseType; // 'exchange' | 'new'
  int qty;
  // exchange declaration (required when purchaseType == 'exchange')
  String? existingBrand;
  String? existingSize;
  String? condition;

  GasCartLine({
    required this.product,
    required this.purchaseType,
    this.qty = 1,
    this.existingBrand,
    this.existingSize,
    this.condition,
  });

  int get unitCents =>
      (purchaseType == 'exchange' ? product.exchangePriceCents : product.newPriceCents) ?? 0;
  int get depositCents => purchaseType == 'new' ? product.depositCents * qty : 0;
  int get lineCents => unitCents * qty + depositCents;

  Map<String, dynamic> toItemJson() => {
        'product_id': product.id,
        'purchase_type': purchaseType,
        'qty': qty,
        if (purchaseType == 'exchange')
          'exchange': {
            'existing_brand': existingBrand ?? product.brand,
            'existing_size': existingSize ?? product.sizeLabel,
            'condition': condition ?? 'unspecified',
          },
      };
}

class GasOrder {
  final String id;
  final String customerId;
  final String supplierId;
  final String status;
  final String paymentStatus;
  final String? paymentMethod;
  final int itemsCents;
  final int depositCents;
  final int deliveryCents;
  final int serviceFeeCents;
  final int totalCents;
  final String? deliveryAddress;
  final DateTime? placedAt;

  const GasOrder({
    required this.id,
    required this.customerId,
    required this.supplierId,
    required this.status,
    required this.paymentStatus,
    this.paymentMethod,
    this.itemsCents = 0,
    this.depositCents = 0,
    this.deliveryCents = 0,
    this.serviceFeeCents = 0,
    this.totalCents = 0,
    this.deliveryAddress,
    this.placedAt,
  });

  bool get awaitingPayment => status == 'awaiting_payment';
  bool get isTerminal =>
      status == 'completed' || status == 'cancelled' || status == 'rejected' || status == 'refunded';

  /// Human label for the current fulfilment status.
  String get statusLabel {
    switch (status) {
      case 'pending_supplier': return 'Pending supplier confirmation';
      case 'supplier_accepted': return 'Supplier accepted';
      case 'awaiting_payment': return 'Awaiting payment';
      case 'payment_confirmed': return 'Payment confirmed';
      case 'preparing': return 'Preparing cylinder';
      case 'assigned': return 'Delivery assigned';
      case 'out_for_delivery': return 'Out for delivery';
      case 'delivered': return 'Delivered';
      case 'exchange_completed': return 'Exchange completed';
      case 'completed': return 'Completed';
      case 'cancelled': return 'Cancelled';
      case 'rejected': return 'Rejected';
      case 'failed_delivery': return 'Failed delivery';
      case 'refund_pending': return 'Refund pending';
      case 'refunded': return 'Refunded';
      default: return status;
    }
  }

  factory GasOrder.fromMap(Map<String, dynamic> m) => GasOrder(
        id: m['id'].toString(),
        customerId: m['customer_id']?.toString() ?? '',
        supplierId: m['supplier_id']?.toString() ?? '',
        status: m['status']?.toString() ?? 'pending_supplier',
        paymentStatus: m['payment_status']?.toString() ?? 'unpaid',
        paymentMethod: m['payment_method']?.toString(),
        itemsCents: _int(m['items_cents']),
        depositCents: _int(m['deposit_cents']),
        deliveryCents: _int(m['delivery_cents']),
        serviceFeeCents: _int(m['service_fee_cents']),
        totalCents: _int(m['total_cents']),
        deliveryAddress: m['delivery_address']?.toString(),
        placedAt: m['placed_at'] == null ? null : DateTime.tryParse(m['placed_at'].toString()),
      );
}
