import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_driver/core/utils/responsive.dart';
import 'package:food_driver/modules/car_services/models/index.dart';
import 'package:food_driver/modules/car_services/providers/car_services_providers.dart';
import 'package:food_driver/utils/app_logger.dart';

const _kPurple = Color(0xFF7C3AED);

class CarServiceProviderServicesScreen extends ConsumerStatefulWidget {
  const CarServiceProviderServicesScreen({super.key});

  @override
  ConsumerState<CarServiceProviderServicesScreen> createState() =>
      _CarServiceProviderServicesScreenState();
}

class _CarServiceProviderServicesScreenState
    extends ConsumerState<CarServiceProviderServicesScreen> {
  String get _providerId =>
      ModalRoute.of(context)!.settings.arguments as String? ?? '';

  void _showOfferingSheet({CarServiceOffering? existing, required List<CarServiceCategory> categories}) {
    String? selectedCategoryId = existing?.categoryId ?? categories.firstOrNull?.id;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final durationCtrl = TextEditingController(
        text: existing != null ? existing.durationMinutes.toString() : '60');
    final priceCtrl = TextEditingController(
        text: existing != null ? existing.basePrice.toStringAsFixed(2) : '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      existing == null ? 'Add Service' : 'Edit Service',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    if (categories.isNotEmpty)
                      DropdownButtonFormField<String>(
                        initialValue: selectedCategoryId,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          border: OutlineInputBorder(),
                        ),
                        items: categories
                            .map((c) => DropdownMenuItem(
                                  value: c.id,
                                  child: Text(c.name),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setSheetState(() => selectedCategoryId = v),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Service Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: durationCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Duration (min)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: priceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Price (\$)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: _kPurple,
                          minimumSize: const Size(double.infinity, 48)),
                      onPressed: () async {
                        final name = nameCtrl.text.trim();
                        final price = double.tryParse(priceCtrl.text.trim());
                        final duration =
                            int.tryParse(durationCtrl.text.trim()) ?? 60;
                        if (name.isEmpty || price == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Name and price are required')),
                          );
                          return;
                        }
                        final messenger = ScaffoldMessenger.of(context);
                        final svc = ref.read(carServicesServiceProvider);
                        final data = {
                          'provider_id': _providerId,
                          if (selectedCategoryId != null)
                            'category_id': selectedCategoryId,
                          'name': name,
                          'description':
                              descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                          'duration_minutes': duration,
                          'base_price': price,
                          'is_active': true,
                        };
                        try {
                          if (existing == null) {
                            await svc.createOffering(data);
                          } else {
                            await svc.updateOffering(existing.id, data);
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                          ref.invalidate(carServiceOfferingsProvider(
                              _providerId));
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(existing == null
                                  ? 'Service added'
                                  : 'Service updated'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        } catch (e) {
                          AppLogger.error('Error saving offering', e);
                          messenger.showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteOffering(CarServiceOffering offering) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Service'),
        content: Text('Remove "${offering.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref.read(carServicesServiceProvider).deleteOffering(offering.id);
      ref.invalidate(carServiceOfferingsProvider(_providerId));
    } catch (e) {
      AppLogger.error('Error deleting offering', e);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final offeringsAsync =
        ref.watch(carServiceOfferingsProvider(_providerId));
    final hp = Responsive.horizontalPadding(context);

    final categoriesAsync = ref.watch(carServiceCategoriesProvider);
    final categories = categoriesAsync.valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Services'),
        backgroundColor: _kPurple,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showOfferingSheet(categories: categories),
        backgroundColor: _kPurple,
        icon: const Icon(Icons.add),
        label: const Text('Add Service'),
      ),
      body: offeringsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (offerings) {
          if (offerings.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.car_repair,
                      size: 64,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.3)),
                  const SizedBox(height: 12),
                  const Text('No services yet — tap + to add one'),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(hp, 16, hp, 100),
            itemCount: offerings.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final o = offerings[i];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _kPurple.withValues(alpha: 0.12),
                    child:
                        const Icon(Icons.car_repair, color: _kPurple, size: 20),
                  ),
                  title: Text(o.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      '${o.category?.name ?? ''} · ${o.durationMinutes} min'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '\$${o.basePrice.toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: _kPurple,
                            fontWeight: FontWeight.bold,
                            fontSize: 15),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'edit') _showOfferingSheet(existing: o, categories: categories);
                          if (v == 'delete') _deleteOffering(o);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'edit', child: Text('Edit')),
                          const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete',
                                  style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
