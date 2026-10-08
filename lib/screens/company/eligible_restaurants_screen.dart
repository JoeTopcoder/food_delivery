import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/company/company_service.dart';
import '../../widgets/common/app_cached_image.dart';

/// Restaurants within a company's delivery radius (same server distance calc as
/// checkout validation). Shown when an employee wants to find an eligible place.
class EligibleRestaurantsScreen extends ConsumerStatefulWidget {
  const EligibleRestaurantsScreen({super.key, required this.company});
  final Company company;
  @override
  ConsumerState<EligibleRestaurantsScreen> createState() => _EligibleRestaurantsScreenState();
}

class _EligibleRestaurantsScreenState extends ConsumerState<EligibleRestaurantsScreen> {
  List<Map<String, dynamic>> _restaurants = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _restaurants = await ref.read(companyServiceProvider).eligibleRestaurants(widget.company);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Within ${widget.company.radiusKm} km of ${widget.company.name}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _restaurants.isEmpty
              ? const Center(child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No restaurants within your company\'s delivery radius.',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _restaurants.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final r = _restaurants[i];
                    final img = (r['image_url'] ?? '') as String;
                    return Card(
                      child: ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 48, height: 48,
                            child: img.isNotEmpty
                                ? AppCachedImage(url: img, width: 48, height: 48)
                                : Container(color: Colors.grey.shade200, child: const Icon(Icons.restaurant)),
                          ),
                        ),
                        title: Text(r['name'] ?? ''),
                        subtitle: Text(r['cuisine_type'] ?? ''),
                        trailing: Text('${r['distance_km']} km',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    );
                  },
                ),
    );
  }
}
