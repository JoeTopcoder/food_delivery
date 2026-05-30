import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../providers/driver_provider.dart';
import '../../../../providers/admin_provider.dart';

const _kPurple = Color(0xFF7C3AED);

// ── Screen ────────────────────────────────────────────────────────────────────

class RideDriverApprovalPage extends ConsumerWidget {
  const RideDriverApprovalPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pendingVerificationDriversProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Approvals', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _kPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(pendingVerificationDriversProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: _kPurple,
        onRefresh: () async => ref.invalidate(pendingVerificationDriversProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator(color: _kPurple)),
          error: (e, _) => _ErrorRetry(
            message: e.toString(),
            onRetry: () => ref.invalidate(pendingVerificationDriversProvider),
          ),
          data: (drivers) {
            if (drivers.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline, size: 56, color: Colors.green),
                    SizedBox(height: 12),
                    Text(
                      'No pending approvals',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'All drivers have been reviewed.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: drivers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _DriverApprovalCard(
                driver: drivers[i],
                onApprove: () => _handleDecision(context, ref, drivers[i], true),
                onReject: () => _handleDecision(context, ref, drivers[i], false),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _handleDecision(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> driver,
    bool approve,
  ) async {
    final driverId = driver['id'] as String;
    final name = (driver['users'] as Map?)?['name'] as String? ?? 'this driver';
    final action = approve ? 'approve' : 'reject';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${approve ? 'Approve' : 'Reject'} Driver'),
        content: Text('Are you sure you want to $action $name?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: approve ? Colors.green : Colors.red,
            ),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      final adminService = ref.read(adminServiceProvider);
      await adminService.verifyDriver(driverId, approve);
      ref.invalidate(pendingVerificationDriversProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$name ${approve ? 'approved' : 'rejected'} successfully.'),
            backgroundColor: approve ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to $action driver: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

// ── Card ──────────────────────────────────────────────────────────────────────

class _DriverApprovalCard extends StatelessWidget {
  final Map<String, dynamic> driver;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _DriverApprovalCard({
    required this.driver,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final user = driver['users'] as Map?;
    final name = user?['name'] as String? ?? 'Unknown Driver';
    final email = user?['email'] as String? ?? '—';
    final status = driver['driver_status'] as String? ?? 'pending_review';
    final vehicleType = driver['vehicle_type'] as String?;
    final vehicleNumber = driver['vehicle_number'] as String?;
    final submittedAt = _fmt(driver['submitted_at'] as String?);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: _kPurple.withValues(alpha: 0.1),
                  radius: 22,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: _kPurple,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      Text(
                        email,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                _StatusBadge(status: status),
              ],
            ),

            const Divider(height: 16),

            // Details
            _InfoRow(label: 'Submitted', value: submittedAt),
            if (vehicleType != null)
              _InfoRow(label: 'Vehicle Type', value: vehicleType),
            if (vehicleNumber != null)
              _InfoRow(label: 'Vehicle #', value: vehicleNumber),
            _InfoRow(
              label: 'Driver ID',
              value: _shortId(driver['id'] as String?),
            ),

            const SizedBox(height: 12),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Approve'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isUnderReview = status == 'under_review';
    final color = isUnderReview ? const Color(0xFF0EA5E9) : Colors.orange;
    final label = isUnderReview ? 'Under Review' : 'Pending';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPurple,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _shortId(String? id) {
  if (id == null) return '—';
  return id.length > 8 ? '#${id.substring(0, 8)}' : '#$id';
}

String _fmt(String? iso) {
  if (iso == null) return '—';
  try {
    return DateFormat('MMM d, yyyy · h:mm a').format(DateTime.parse(iso).toLocal());
  } catch (_) {
    return '—';
  }
}
