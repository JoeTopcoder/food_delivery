// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_constants.dart';
import '../../config/supabase_config.dart';
import '../../core/utils/responsive.dart';
import '../../providers/auth_provider.dart';
import '../../providers/driver_provider.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../utils/safe_state_mixin.dart';

class MultiStopDeliveryScreen extends ConsumerStatefulWidget {
  final String deliveryTaskId;
  final String driverId;

  const MultiStopDeliveryScreen({
    super.key,
    required this.deliveryTaskId,
    required this.driverId,
  });

  @override
  ConsumerState<MultiStopDeliveryScreen> createState() =>
      _MultiStopDeliveryScreenState();
}

class _MultiStopDeliveryScreenState
    extends ConsumerState<MultiStopDeliveryScreen>
    with SafeConsumerStateMixin<MultiStopDeliveryScreen> {
  bool _processing = false;

  Future<Map<String, String>> _freshHeader() async {
    String? token;
    try {
      final res = await SupabaseConfig.client.auth.refreshSession();
      token = res.session?.accessToken;
    } catch (_) {}
    token ??= SupabaseConfig.client.auth.currentSession?.accessToken;
    return token != null && token.isNotEmpty
        ? {'Authorization': 'Bearer $token'}
        : {};
  }

  Future<void> _updateStop(String stopId, String action) async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      final resp = await SupabaseConfig.client.functions.invoke(
        'update-delivery-stop',
        body: {
          'stop_id': stopId,
          'action': action,
          'driver_id': widget.driverId,
        },
        headers: await _freshHeader(),
      );
      final data = resp.data is String
          ? jsonDecode(resp.data as String) as Map<String, dynamic>
          : resp.data as Map<String, dynamic>;
      if (data['error'] != null) throw Exception(data['error']);

      ref.invalidate(activeDeliveryTasksProvider(widget.driverId));
      if (mounted) {
        AppSnackbar.success(
          context,
          action == 'arrived' ? 'Marked as arrived' : 'Stop completed',
        );
        // If all stops completed (task done), pop back
        final allStops = (data['all_stops'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final allDone = allStops.isNotEmpty &&
            allStops.every((s) => s['status'] == 'completed');
        if (allDone && mounted) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e.toString()));
    } finally {
      setState(() => _processing = false);
    }
  }

  void _openNavigation(double lat, double lng) async {
    final google = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    final fallback = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );
    if (await canLaunchUrl(google)) {
      await launchUrl(google);
    } else {
      await launchUrl(fallback, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserIdProvider);
    if (currentUserId == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    final tasksAsync = ref.watch(activeDeliveryTasksProvider(widget.driverId));

    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1117),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Multi-Stop Delivery',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.3),
        ),
      ),
      body: tasksAsync.when(
        data: (tasks) {
          final task = tasks.cast<Map<String, dynamic>?>().firstWhere(
            (t) => t?['id'] == widget.deliveryTaskId,
            orElse: () => null,
          );
          if (task == null) {
            return const Center(
              child: Text('Task not found', style: TextStyle(color: Colors.white)),
            );
          }

          final stops = ((task['delivery_stops'] as List?) ?? [])
              .cast<Map<String, dynamic>>()
            ..sort((a, b) =>
                (a['sequence_number'] as int).compareTo(b['sequence_number'] as int));

          final pickupStops =
              stops.where((s) => s['stop_type'] == 'pickup').toList();

          final allPickupsDone = pickupStops
              .every((s) => s['status'] == 'completed');
          final earning = (task['driver_earning'] as num?)?.toDouble() ?? 0.0;
          final distKm =
              (task['total_distance_km'] as num?)?.toDouble() ?? 0.0;
          final etaMin = task['estimated_duration_minutes'] as int? ?? 0;

          return Column(
            children: [
              // ── Earnings banner ──────────────────────────────────────
              Container(
                margin: EdgeInsets.all(Responsive.horizontalPadding(context)),
                padding: EdgeInsets.all(Responsive.cardPadding(context)),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.12),
                  borderRadius:
                      BorderRadius.circular(Responsive.cardRadius(context)),
                  border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.monetization_on_rounded,
                        color: AppTheme.primaryColor, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Earning: ${AppConstants.currencySymbol}${earning.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: AppTheme.primaryColor,
                              fontWeight: FontWeight.w700,
                              fontSize: Responsive.bodyText(context),
                            ),
                          ),
                          Text(
                            '${distKm.toStringAsFixed(1)} km · ~$etaMin min · ${pickupStops.length} pickup${pickupStops.length > 1 ? "s" : ""}',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: Responsive.smallText(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Stop list ────────────────────────────────────────────
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                    Responsive.horizontalPadding(context),
                    0,
                    Responsive.horizontalPadding(context),
                    32,
                  ),
                  itemCount: stops.length,
                  itemBuilder: (context, index) {
                    final stop = stops[index];
                    final isPickup = stop['stop_type'] == 'pickup';
                    final status = stop['status'] as String? ?? 'pending';
                    final address = stop['address'] as String? ?? 'Unknown address';
                    final lat = (stop['latitude'] as num?)?.toDouble();
                    final lng = (stop['longitude'] as num?)?.toDouble();
                    final isDropoff = !isPickup;
                    final dropoffBlocked = isDropoff && !allPickupsDone;

                    final statusColor = status == 'completed'
                        ? const Color(0xFF22C55E)
                        : status == 'arrived'
                            ? const Color(0xFFF59E0B)
                            : Colors.white38;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E2030),
                        borderRadius: BorderRadius.circular(
                            Responsive.cardRadius(context)),
                        border: Border.all(
                          color: status == 'completed'
                              ? const Color(0xFF22C55E).withValues(alpha: 0.4)
                              : status == 'arrived'
                                  ? const Color(0xFFF59E0B).withValues(alpha: 0.4)
                                  : Colors.white12,
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(Responsive.cardPadding(context)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Stop header
                            Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                    border:
                                        Border.all(color: statusColor, width: 1.5),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        color: statusColor,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            isPickup
                                                ? Icons.store_rounded
                                                : Icons.home_rounded,
                                            size: 14,
                                            color: isPickup
                                                ? AppTheme.primaryColor
                                                : const Color(0xFF22C55E),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            isPickup
                                                ? 'Pickup ${pickupStops.indexOf(stop) + 1}'
                                                : 'Drop Off',
                                            style: TextStyle(
                                              color: isPickup
                                                  ? AppTheme.primaryColor
                                                  : const Color(0xFF22C55E),
                                              fontWeight: FontWeight.w700,
                                              fontSize: Responsive.smallText(context),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color:
                                                  statusColor.withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              status.toUpperCase(),
                                              style: TextStyle(
                                                color: statusColor,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        address,
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: Responsive.smallText(context),
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            if (dropoffBlocked) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: Colors.orange.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.lock_rounded,
                                        color: Colors.orange, size: 14),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Complete all pickups first',
                                      style: TextStyle(
                                        color: Colors.orange,
                                        fontSize: Responsive.smallText(context),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            if (status != 'completed') ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  // Navigate button
                                  if (lat != null && lng != null)
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _openNavigation(lat, lng),
                                        icon: const Icon(Icons.navigation_rounded,
                                            size: 16),
                                        label: const Text('Navigate'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.white70,
                                          side: const BorderSide(
                                              color: Colors.white24),
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 8),
                                          textStyle: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ),
                                  if (lat != null && lng != null)
                                    const SizedBox(width: 8),
                                  // Action button
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: _processing || dropoffBlocked
                                          ? null
                                          : () => _updateStop(
                                                stop['id'] as String,
                                                status == 'arrived'
                                                    ? 'completed'
                                                    : 'arrived',
                                              ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: status == 'arrived'
                                            ? const Color(0xFF22C55E)
                                            : AppTheme.primaryColor,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8),
                                        elevation: 0,
                                        textStyle: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700),
                                      ),
                                      child: _processing
                                          ? const SizedBox(
                                              height: 14,
                                              width: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : Text(
                                              status == 'arrived'
                                                  ? (isPickup
                                                      ? 'Picked Up'
                                                      : 'Delivered')
                                                  : 'Arrived',
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.check_circle_rounded,
                                      color: Color(0xFF22C55E), size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    isPickup ? 'Picked up' : 'Delivered',
                                    style: const TextStyle(
                                      color: Color(0xFF22C55E),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
        loading: () => const Center(
          child: AppLoadingIndicator(message: 'Loading delivery task…'),
        ),
        error: (err, _) => Center(
          child: AppErrorState(message: friendlyError(err)),
        ),
      ),
    );
  }
}
