import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_driver/core/utils/responsive.dart';
import 'package:food_driver/modules/car_services/models/index.dart';
import 'package:food_driver/modules/car_services/providers/car_services_providers.dart';
import 'package:food_driver/utils/app_logger.dart';

const _kPurple = Color(0xFF7C3AED);

class _DaySlot {
  final int dayOfWeek;
  bool isActive;
  TimeOfDay startTime;
  TimeOfDay endTime;

  _DaySlot({
    required this.dayOfWeek,
    required this.isActive,
    required this.startTime,
    required this.endTime,
  });

  String get dayName =>
      ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'][dayOfWeek];
}

class CarServiceProviderAvailabilityScreen extends ConsumerStatefulWidget {
  const CarServiceProviderAvailabilityScreen({super.key});

  @override
  ConsumerState<CarServiceProviderAvailabilityScreen> createState() =>
      _CarServiceProviderAvailabilityScreenState();
}

class _CarServiceProviderAvailabilityScreenState
    extends ConsumerState<CarServiceProviderAvailabilityScreen> {
  List<_DaySlot>? _slots;
  bool _saving = false;

  String get _providerId =>
      ModalRoute.of(context)!.settings.arguments as String? ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSlots());
  }

  void _loadSlots() {
    final avail = ref.read(providerAvailabilityProvider(_providerId));
    avail.whenData((list) => _applySlots(list));
    if (_slots == null) _buildDefaultSlots();
  }

  void _buildDefaultSlots() {
    _slots = List.generate(7, (i) {
      final isWeekday = i >= 1 && i <= 5;
      final isSat = i == 6;
      return _DaySlot(
        dayOfWeek: i,
        isActive: isWeekday || isSat,
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: isWeekday
            ? const TimeOfDay(hour: 17, minute: 0)
            : const TimeOfDay(hour: 14, minute: 0),
      );
    });
  }

  void _applySlots(List<ProviderAvailability> list) {
    if (list.isEmpty) {
      _buildDefaultSlots();
      return;
    }
    _slots = List.generate(7, (i) {
      final match = list.where((s) => s.dayOfWeek == i).firstOrNull;
      if (match == null) {
        return _DaySlot(
          dayOfWeek: i,
          isActive: false,
          startTime: const TimeOfDay(hour: 9, minute: 0),
          endTime: const TimeOfDay(hour: 17, minute: 0),
        );
      }
      final parts = match.startTime.split(':');
      final endParts = match.endTime.split(':');
      return _DaySlot(
        dayOfWeek: i,
        isActive: match.isActive,
        startTime: TimeOfDay(
            hour: int.parse(parts[0]), minute: int.parse(parts[1])),
        endTime: TimeOfDay(
            hour: int.parse(endParts[0]), minute: int.parse(endParts[1])),
      );
    });
    setState(() {});
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _pickTime(int index, bool isStart) async {
    final slot = _slots![index];
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? slot.startTime : slot.endTime,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _slots![index].startTime = picked;
      } else {
        _slots![index].endTime = picked;
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final slots = _slots!
          .map((s) => ProviderAvailability(
                id: '',
                providerId: _providerId,
                dayOfWeek: s.dayOfWeek,
                startTime: _formatTime(s.startTime),
                endTime: _formatTime(s.endTime),
                isActive: s.isActive,
              ))
          .toList();

      await ref.read(carServicesServiceProvider).upsertAvailability(slots);
      ref.invalidate(providerAvailabilityProvider(_providerId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Availability saved'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      AppLogger.error('Error saving availability', e);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final availAsync =
        ref.watch(providerAvailabilityProvider(_providerId));
    final hp = Responsive.horizontalPadding(context);

    if (_slots == null) {
      availAsync.whenData(_applySlots);
    }

    final slots = _slots;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Availability'),
        backgroundColor: _kPurple,
        foregroundColor: Colors.white,
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2)),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text('Save',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
        ],
      ),
      body: slots == null
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: EdgeInsets.symmetric(horizontal: hp, vertical: 16),
              itemCount: slots.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final slot = slots[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 100,
                        child: Row(
                          children: [
                            Switch(
                              value: slot.isActive,
                              activeThumbColor: _kPurple,
                              onChanged: (v) =>
                                  setState(() => slot.isActive = v),
                            ),
                            const SizedBox(width: 4),
                            Text(slot.dayName.substring(0, 3),
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: slot.isActive
                                        ? Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.4))),
                          ],
                        ),
                      ),
                      if (slot.isActive) ...[
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _pickTime(i, true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outline
                                        .withValues(alpha: 0.4)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(slot.startTime.format(context),
                                  textAlign: TextAlign.center),
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('–'),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _pickTime(i, false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outline
                                        .withValues(alpha: 0.4)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(slot.endTime.format(context),
                                  textAlign: TextAlign.center),
                            ),
                          ),
                        ),
                      ] else
                        const Expanded(
                          child: Text(
                            'Unavailable',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
