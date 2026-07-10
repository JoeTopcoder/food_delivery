import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';

/// Shown when opening an agent that's registered in ai_agents but not built
/// yet — so tapping "Open" always does something honest instead of silently
/// bouncing back to the home screen.
class AdminAgentComingSoonScreen extends StatelessWidget {
  final Map<String, dynamic> agent;
  const AdminAgentComingSoonScreen({super.key, required this.agent});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(agent['name'] ?? 'AI Agent', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)), centerTitle: true),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(Icons.hourglass_empty_rounded, size: 48, color: Colors.grey[600]),
              ),
              const SizedBox(height: 20),
              Text(agent['name'] ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(agent['department'] ?? '', style: const TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(20)),
                child: const Text('Not Built Yet', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
              ),
              if (agent['description'] != null) ...[
                const SizedBox(height: 20),
                Text(agent['description'], textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF4B5563))),
              ],
              const SizedBox(height: 28),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(foregroundColor: AppTheme.primaryColor),
                child: const Text('Back to AI Operations'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
