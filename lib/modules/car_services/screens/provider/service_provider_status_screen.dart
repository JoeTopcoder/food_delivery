import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/car_services_providers.dart';

enum ProviderStatus { pending, rejected, suspended }

const _kBlue = Color(0xFF1D4ED8);
const _kBlueDark = Color(0xFF1E3A8A);

class ServiceProviderStatusScreen extends ConsumerWidget {
  final ProviderStatus status;
  final String? reason;

  const ServiceProviderStatusScreen({
    super.key,
    required this.status,
    this.reason,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: _kBlueDark,
        foregroundColor: Colors.white,
        title: const Text('7Dash Car Services'),
        automaticallyImplyLeading: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pushNamed('/'),
            child: const Text('Sign Out', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildContent(context, ref),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref) {
    switch (status) {
      case ProviderStatus.pending:
        return _PendingContent(
          onRefresh: () => ref.invalidate(myCarServiceProviderProfileProvider),
        );
      case ProviderStatus.rejected:
        return _RejectedContent(
          reason: reason,
          onResubmit: () => Navigator.of(context).pushNamed('/onboarding/service-provider'),
        );
      case ProviderStatus.suspended:
        return const _SuspendedContent();
    }
  }
}

// ── Pending ─────────────────────────────────────────────────────────────────────

class _PendingContent extends StatelessWidget {
  final VoidCallback onRefresh;
  const _PendingContent({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Spacer(),
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: _kBlue.withAlpha(15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.hourglass_top_rounded, size: 52, color: _kBlue),
        ),
        const SizedBox(height: 24),
        const Text(
          'Application Under Review',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _kBlueDark),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const Text(
          'Our team is reviewing your car service provider application. This typically takes 1–2 business days.',
          style: TextStyle(color: Colors.grey, fontSize: 14),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        _Timeline(steps: const [
          _TimelineStep(
            icon: Icons.check_circle_rounded,
            label: 'Application submitted',
            done: true,
          ),
          _TimelineStep(
            icon: Icons.search_rounded,
            label: 'Under admin review',
            active: true,
          ),
          _TimelineStep(
            icon: Icons.verified_rounded,
            label: 'Account approved',
          ),
          _TimelineStep(
            icon: Icons.store_rounded,
            label: 'Start receiving bookings',
          ),
        ]),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Check status'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'We\'ll notify you by email once a decision is made.',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _Timeline extends StatelessWidget {
  final List<_TimelineStep> steps;
  const _Timeline({required this.steps});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: steps
            .asMap()
            .entries
            .map((e) => _TimelineRow(
                  step: e.value,
                  isLast: e.key == steps.length - 1,
                ))
            .toList(),
      ),
    );
  }
}

class _TimelineStep {
  final IconData icon;
  final String label;
  final bool done;
  final bool active;

  const _TimelineStep({
    required this.icon,
    required this.label,
    this.done = false,
    this.active = false,
  });
}

class _TimelineRow extends StatelessWidget {
  final _TimelineStep step;
  final bool isLast;
  const _TimelineRow({required this.step, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final Color color;
    if (step.done) {
      color = Colors.green;
    } else if (step.active) {
      color = _kBlue;
    } else {
      color = Colors.grey.shade300;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: color.withAlpha(20),
              child: Icon(step.icon, size: 18, color: color),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 32,
                color: color.withAlpha(40),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            step.label,
            style: TextStyle(
              fontWeight: (step.active || step.done) ? FontWeight.w600 : FontWeight.normal,
              color: (step.active || step.done) ? Colors.black87 : Colors.grey,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Rejected ────────────────────────────────────────────────────────────────────

class _RejectedContent extends StatelessWidget {
  final String? reason;
  final VoidCallback onResubmit;

  const _RejectedContent({this.reason, required this.onResubmit});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Spacer(),
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: Colors.red.withAlpha(15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.cancel_rounded, size: 52, color: Colors.red),
        ),
        const SizedBox(height: 24),
        const Text(
          'Application Not Approved',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const Text(
          'Unfortunately, your application was not approved at this time.',
          style: TextStyle(color: Colors.grey, fontSize: 14),
          textAlign: TextAlign.center,
        ),
        if (reason != null && reason!.isNotEmpty) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.red.withAlpha(10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withAlpha(40)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reason:',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                ),
                const SizedBox(height: 4),
                Text(reason!, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ],
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onResubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Update & Resubmit Application'),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.of(context).pushNamed('/'),
          child: const Text('Sign out'),
        ),
      ],
    );
  }
}

// ── Suspended ───────────────────────────────────────────────────────────────────

class _SuspendedContent extends StatelessWidget {
  const _SuspendedContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Spacer(),
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: Colors.orange.withAlpha(15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.pause_circle_rounded, size: 52, color: Colors.orange),
        ),
        const SizedBox(height: 24),
        const Text(
          'Account Suspended',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const Text(
          'Your provider account has been temporarily suspended. Please contact support for assistance.',
          style: TextStyle(color: Colors.grey, fontSize: 14),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.withAlpha(10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.withAlpha(40)),
          ),
          child: const Row(
            children: [
              Icon(Icons.support_agent_rounded, color: Colors.orange),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Contact support at support@7dash.com to resolve this.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.of(context).pushNamed('/'),
          child: const Text('Sign out'),
        ),
      ],
    );
  }
}
