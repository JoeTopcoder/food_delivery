import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/shipping_company.dart';
import '../../providers/package_providers.dart';
import 'package_searching_screen.dart';

class PackageDeliverySummaryScreen extends ConsumerStatefulWidget {
  final ShippingCompany company;
  final Map<String, dynamic> verifyResult;

  const PackageDeliverySummaryScreen({
    super.key,
    required this.company,
    required this.verifyResult,
  });

  @override
  ConsumerState<PackageDeliverySummaryScreen> createState() =>
      _PackageDeliverySummaryScreenState();
}

class _PackageDeliverySummaryScreenState
    extends ConsumerState<PackageDeliverySummaryScreen> {
  Map<String, dynamic>? _feeData;
  bool _loadingFee = true;
  bool _placingOrder = false;
  String _paymentMethod = 'card';

  Map<String, dynamic> get _pkg =>
      widget.verifyResult['package'] as Map<String, dynamic>;

  @override
  void initState() {
    super.initState();
    _fetchFee();
  }

  Future<void> _fetchFee() async {
    try {
      final fee = await ref.read(packageServiceProvider).calculateFee(
            pickupLat: (widget.company.warehouseLat),
            pickupLng: (widget.company.warehouseLng),
            destinationLat: (_pkg['delivery_lat'] as num? ?? 0).toDouble(),
            destinationLng: (_pkg['delivery_lng'] as num? ?? 0).toDouble(),
            packageType: _pkg['package_type'] as String? ?? 'small',
            packageWeight: (_pkg['package_weight'] as num?)?.toDouble(),
          );
      if (mounted) setState(() => _feeData = fee);
    } catch (_) {
      if (mounted) setState(() => _feeData = null);
    } finally {
      if (mounted) setState(() => _loadingFee = false);
    }
  }

  Future<void> _requestDelivery() async {
    if (_feeData == null) return;
    setState(() => _placingOrder = true);
    try {
      final delivery = await ref.read(packageServiceProvider).createDelivery(
            packageRecordId: _pkg['id'] as String,
            shippingCompanyId: widget.company.id,
            paymentMethod: _paymentMethod,
            deliveryFee: (_feeData!['delivery_fee'] as num).toDouble(),
            platformFee: (_feeData!['platform_fee'] as num).toDouble(),
            driverEarning: (_feeData!['driver_earning'] as num).toDouble(),
          );
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) =>
              PackageSearchingScreen(deliveryRequest: delivery),
        ),
        (route) => route.isFirst,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _placingOrder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery Summary'),
        backgroundColor: const Color(0xFF7C3AED),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionCard(
              title: 'Package Details',
              icon: Icons.inventory_2,
              children: [
                _InfoRow('Tracking', _pkg['tracking_number'] as String? ?? ''),
                _InfoRow('Recipient', _pkg['customer_name'] as String? ?? ''),
                _InfoRow('Phone', _pkg['customer_phone'] as String? ?? ''),
                _InfoRow('Type',
                    (_pkg['package_type'] as String? ?? '').toUpperCase()),
                if (_pkg['package_weight'] != null)
                  _InfoRow('Weight',
                      '${_pkg['package_weight']} kg'),
                if (_pkg['package_value'] != null)
                  _InfoRow('Declared Value',
                      'JMD ${_pkg['package_value']}'),
                if (_pkg['notes'] != null && (_pkg['notes'] as String).isNotEmpty)
                  _InfoRow('Notes', _pkg['notes'] as String),
              ],
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Delivery Route',
              icon: Icons.route,
              children: [
                _InfoRow('Pickup', widget.company.warehouseAddress),
                _InfoRow('Delivery', _pkg['delivery_address'] as String? ?? ''),
              ],
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Pricing',
              icon: Icons.receipt,
              children: _loadingFee
                  ? [const Center(child: CircularProgressIndicator())]
                  : _feeData == null
                      ? [const Text('Could not calculate fee')]
                      : [
                          _InfoRow('Distance',
                              '${_feeData!['distance_km']} km'),
                          _InfoRow('Est. Duration',
                              '${_feeData!['duration_minutes']} min'),
                          _InfoRow('Delivery Fee',
                              'JMD ${_feeData!['delivery_fee']}'),
                          const Divider(),
                          _InfoRow(
                            'Total',
                            'JMD ${_feeData!['total_charge']}',
                            bold: true,
                          ),
                        ],
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Payment Method',
              icon: Icons.payment,
              children: [
                RadioListTile<String>(
                  value: 'card',
                  groupValue: _paymentMethod,
                  onChanged: (v) => setState(() => _paymentMethod = v!),
                  title: const Text('Card'),
                  secondary: const Icon(Icons.credit_card),
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFF7C3AED),
                ),
                RadioListTile<String>(
                  value: 'cash',
                  groupValue: _paymentMethod,
                  onChanged: (v) => setState(() => _paymentMethod = v!),
                  title: const Text('Cash on Delivery'),
                  secondary: const Icon(Icons.money),
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFF7C3AED),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed:
                    (_loadingFee || _feeData == null || _placingOrder)
                        ? null
                        : _requestDelivery,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _placingOrder
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Request Delivery',
                        style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFF7C3AED), size: 20),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _InfoRow(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    bold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
