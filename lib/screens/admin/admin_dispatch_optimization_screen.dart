import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_theme.dart';

/// Dispatch Optimization Agent — driver ranking by distance is deterministic
/// (haversine); the AI only explains the recommendation. This never assigns
/// a driver itself — an admin still confirms via the existing dispatch flow.
class AdminDispatchOptimizationScreen extends StatefulWidget {
  const AdminDispatchOptimizationScreen({super.key});

  @override
  State<AdminDispatchOptimizationScreen> createState() => _AdminDispatchOptimizationScreenState();
}

class _AdminDispatchOptimizationScreenState extends State<AdminDispatchOptimizationScreen> {
  bool _loadingOrders = true;
  bool _ranking = false;
  String? _error;
  List<Map<String, dynamic>> _orders = [];
  String? _selectedOrderId;
  List<Map<String, dynamic>>? _rankedDrivers;
  String? _narrative;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() { _loadingOrders = true; _error = null; });
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'ops-report-agent',
        body: {'agent_slug': 'dispatch_optimization', 'list_orders': true},
      );
      final data = res.data;
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      setState(() => _orders = List<Map<String, dynamic>>.from(data['orders'] as List));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loadingOrders = false);
    }
  }

  Future<void> _rankFor(String orderId) async {
    setState(() { _ranking = true; _error = null; _rankedDrivers = null; _narrative = null; _selectedOrderId = orderId; });
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'ops-report-agent',
        body: {'agent_slug': 'dispatch_optimization', 'order_id': orderId},
      );
      final data = res.data;
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      setState(() {
        _rankedDrivers = List<Map<String, dynamic>>.from(data['ranked_drivers'] as List);
        _narrative = data['narrative'] as String?;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _ranking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispatch Optimization', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadOrders)],
      ),
      body: _loadingOrders
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Orders Needing a Driver', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 8),
                if (_orders.isEmpty)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('No orders currently need dispatch.', style: TextStyle(color: Colors.grey)))
                else
                  ..._orders.map((o) => Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: _selectedOrderId == o['id'] ? AppTheme.primaryColor : Colors.grey.shade200, width: _selectedOrderId == o['id'] ? 1.5 : 1),
                        ),
                        child: ListTile(
                          title: Text(o['receipt_number'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          subtitle: Text(o['restaurant'] ?? '', style: const TextStyle(fontSize: 12)),
                          trailing: _ranking && _selectedOrderId == o['id']
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.chevron_right, size: 18),
                          onTap: _ranking ? null : () => _rankFor(o['id']),
                        ),
                      )),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                if (_narrative != null && _narrative!.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Card(
                    elevation: 0,
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.06),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFEDE9FE))),
                    child: Padding(padding: const EdgeInsets.all(16), child: Text(_narrative!, style: const TextStyle(fontSize: 14, height: 1.5))),
                  ),
                ],
                if (_rankedDrivers != null) ...[
                  const SizedBox(height: 16),
                  const Text('Ranked Drivers (nearest first)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 8),
                  if (_rankedDrivers!.isEmpty)
                    const Text('No available drivers online right now.', style: TextStyle(color: Colors.grey))
                  else
                    ..._rankedDrivers!.asMap().entries.map((entry) {
                      final i = entry.key;
                      final d = entry.value;
                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 6),
                        color: i == 0 ? const Color(0xFFDCFCE7) : null,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade200)),
                        child: ListTile(
                          dense: true,
                          leading: CircleAvatar(radius: 12, child: Text('${i + 1}', style: const TextStyle(fontSize: 11))),
                          title: Text(d['driver'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          trailing: Text('${d['distance_km']} km', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      );
                    }),
                ],
              ],
            ),
    );
  }
}
