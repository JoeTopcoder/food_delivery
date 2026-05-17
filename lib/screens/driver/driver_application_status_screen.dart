import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/driver_model.dart';
import '../../providers/driver_provider.dart';
import '../../providers/auth_provider.dart';
import 'driver_verification_screen.dart';
import 'driver_document_reupload_screen.dart';

class DriverApplicationStatusScreen extends ConsumerWidget {
  const DriverApplicationStatusScreen({super.key});

  static const _bg = Color(0xFF0F1117);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final driverAsync = ref.watch(driverProfileProvider(userId));

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text('Application Status', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(driverProfileProvider(userId)),
          ),
        ],
      ),
      body: driverAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString(), style: const TextStyle(color: Colors.redAccent))),
        data: (driver) {
          if (driver == null) return const Center(child: Text('No profile found.', style: TextStyle(color: Colors.white54)));
          return _StatusBody(driver: driver);
        },
      ),
    );
  }
}

class _StatusBody extends ConsumerWidget {
  final Driver driver;
  const _StatusBody({required this.driver});

  static const _accent = Color(0xFF6C63FF);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusBadge(status: driver.driverStatus),
          const SizedBox(height: 24),
          _InfoCard(driver: driver),
          const SizedBox(height: 20),
          _StepChecklist(driver: driver),
          const SizedBox(height: 24),
          if (driver.driverStatus == 'rejected') ...[
            _RejectionCard(reason: driver.rejectionReason),
            const SizedBox(height: 16),
            _ActionButton(
              label: 'Re-upload Documents',
              icon: Icons.upload_file,
              color: Colors.orangeAccent,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DriverDocumentReuploadScreen(driver: driver)),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (driver.isDraft || driver.onboardingStep < 8)
            _ActionButton(
              label: driver.onboardingStep == 0 ? 'Start Verification' : 'Continue Verification',
              icon: Icons.arrow_forward,
              color: _accent,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DriverVerificationScreen(driver: driver)),
              ),
            ),
          if (driver.isApproved) ...[
            const SizedBox(height: 12),
            _ActionButton(
              label: 'Go to Dashboard',
              icon: Icons.dashboard,
              color: const Color(0xFF00C896),
              onTap: () => Navigator.pushNamedAndRemoveUntil(context, '/driver-dashboard', (_) => false),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final config = _statusConfig(status);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: config.color.withValues(alpha: 0.12),
        border: Border.all(color: config.color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(config.icon, color: config.color, size: 48),
          const SizedBox(height: 12),
          Text(
            config.title,
            style: TextStyle(color: config.color, fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            config.message,
            style: const TextStyle(color: Colors.white60, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  _StatusConfig _statusConfig(String status) {
    switch (status) {
      case 'approved':
        return _StatusConfig(
          icon: Icons.verified,
          color: const Color(0xFF00C896),
          title: 'Application Approved!',
          message: 'You are approved to drive on our platform. Head to your dashboard to start earning.',
        );
      case 'pending_review':
        return _StatusConfig(
          icon: Icons.hourglass_top,
          color: Colors.orangeAccent,
          title: 'Under Review',
          message: 'Your application has been submitted and is being reviewed. This typically takes 1-3 business days.',
        );
      case 'under_review':
        return _StatusConfig(
          icon: Icons.manage_search,
          color: Colors.blueAccent,
          title: 'Being Reviewed',
          message: 'An admin is actively reviewing your documents. You will be notified soon.',
        );
      case 'rejected':
        return _StatusConfig(
          icon: Icons.cancel_outlined,
          color: Colors.redAccent,
          title: 'Application Rejected',
          message: 'Your application was not approved. Please review the reason below and resubmit.',
        );
      case 'suspended':
        return _StatusConfig(
          icon: Icons.block,
          color: Colors.red,
          title: 'Account Suspended',
          message: 'Your account has been suspended. Please contact support.',
        );
      case 'expired_documents':
        return _StatusConfig(
          icon: Icons.warning_amber,
          color: Colors.amber,
          title: 'Documents Expired',
          message: 'One or more of your documents have expired. Please re-upload valid documents.',
        );
      default:
        return _StatusConfig(
          icon: Icons.edit_document,
          color: Colors.white54,
          title: 'Application Draft',
          message: 'Complete your verification to start driving on our platform.',
        );
    }
  }
}

class _InfoCard extends StatelessWidget {
  final Driver driver;
  const _InfoCard({required this.driver});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F2E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Application Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 12),
          _InfoRow('Service Type', _serviceLabel(driver.serviceType)),
          _InfoRow('Onboarding Progress', '${driver.onboardingStep}/8 steps'),
          if (driver.submittedAt != null)
            _InfoRow('Submitted', _formatDate(driver.submittedAt!)),
          if (driver.approvedAt != null)
            _InfoRow('Approved', _formatDate(driver.approvedAt!)),
          if (driver.reviewedAt != null)
            _InfoRow('Reviewed', _formatDate(driver.reviewedAt!)),
          _InfoRow('Food Delivery', driver.isFoodDriverApproved ? 'Approved' : 'Pending'),
          if (driver.serviceType == 'ride_sharing' || driver.serviceType == 'both')
            _InfoRow('Ride Sharing', driver.isRideDriverApproved ? 'Approved' : 'Pending'),
        ],
      ),
    );
  }

  String _serviceLabel(String t) {
    switch (t) {
      case 'food_delivery': return 'Food Delivery';
      case 'ride_sharing': return 'Ride Sharing';
      case 'both': return 'Food & Rides';
      default: return t;
    }
  }

  String _formatDate(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    ),
  );
}

class _StepChecklist extends StatelessWidget {
  final Driver driver;
  const _StepChecklist({required this.driver});

  @override
  Widget build(BuildContext context) {
    final steps = [
      ('Personal Information', driver.onboardingStep > 0),
      ('Profile Photo', driver.onboardingStep > 1),
      ('Service Type', driver.onboardingStep > 2),
      ('Identity Document', driver.onboardingStep > 3),
      ("Driver's License", driver.onboardingStep > 4),
      ('Vehicle Details', driver.onboardingStep > 5),
      ('Insurance', driver.onboardingStep > 6),
      ('Agreements', driver.onboardingStep > 7),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1F2E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Verification Checklist', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 12),
          ...steps.map((s) => _CheckRow(label: s.$1, done: s.$2)),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final String label;
  final bool done;
  const _CheckRow({required this.label, required this.done});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Icon(
          done ? Icons.check_circle : Icons.radio_button_unchecked,
          color: done ? const Color(0xFF00C896) : Colors.white24,
          size: 20,
        ),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: done ? Colors.white : Colors.white38, fontSize: 13)),
      ],
    ),
  );
}

class _RejectionCard extends StatelessWidget {
  final String? reason;
  const _RejectionCard({required this.reason});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.redAccent.withValues(alpha: 0.1),
      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.redAccent, size: 18),
            SizedBox(width: 8),
            Text('Rejection Reason', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          reason ?? 'No reason provided. Please contact support.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    ),
  );
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}

class _StatusConfig {
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  const _StatusConfig({required this.icon, required this.color, required this.title, required this.message});
}
