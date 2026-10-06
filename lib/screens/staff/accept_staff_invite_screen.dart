import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/restaurant/staff_service.dart';

/// Accepts a staff invitation. The token can be prefilled from the deep link
/// (/accept-staff-invite?token=...) or pasted. Acceptance is server-side: the
/// signed-in user's VERIFIED email must match the invitation.
class AcceptStaffInviteScreen extends ConsumerStatefulWidget {
  final String? token;
  const AcceptStaffInviteScreen({super.key, this.token});
  @override
  ConsumerState<AcceptStaffInviteScreen> createState() => _S();
}

class _S extends ConsumerState<AcceptStaffInviteScreen> {
  late final TextEditingController _c = TextEditingController(text: widget.token ?? '');
  bool _busy = false;
  String? _result;

  Future<void> _accept() async {
    final token = _c.text.trim();
    if (token.isEmpty) return;
    setState(() { _busy = true; _result = null; });
    final r = await StaffService().acceptInvite(token);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = r.ok
          ? 'Invitation accepted — you are now staff at this restaurant. Open "My Shift" to start.'
          : 'Could not accept: ${_friendly(r.reason)}';
    });
  }

  String _friendly(String? reason) => switch (reason) {
        'email_not_verified' => 'please verify your account email first',
        'invalid_or_email_mismatch' => 'this invite is invalid or was sent to a different email',
        'expired' => 'this invitation has expired (ask for a new one)',
        'inviter_no_longer_authorized' => 'the person who invited you no longer has access',
        'not_authenticated' => 'please sign in first',
        _ => reason ?? 'unknown error',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Accept staff invite')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Join a HotBite restaurant as staff',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('Sign in with the email the invite was sent to, then accept. '
            'New here? Create your account with that email and verify it first.',
            style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 20),
        TextField(
          controller: _c,
          decoration: const InputDecoration(labelText: 'Invitation code', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _busy ? null : _accept,
          child: _busy
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Accept invitation'),
        ),
        if (_result != null) Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(_result!, style: TextStyle(
            color: _result!.startsWith('Invitation accepted') ? Colors.green : Colors.red)),
        ),
      ]),
    );
  }
}
