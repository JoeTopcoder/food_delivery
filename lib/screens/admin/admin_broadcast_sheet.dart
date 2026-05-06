import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';

/// Bottom sheet that lets an admin broadcast a push + email campaign to
/// customers via the `admin-broadcast` edge function.
class AdminBroadcastSheet extends ConsumerStatefulWidget {
  const AdminBroadcastSheet({super.key});

  @override
  ConsumerState<AdminBroadcastSheet> createState() => _AdminBroadcastSheetState();
}

class _AdminBroadcastSheetState extends ConsumerState<AdminBroadcastSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  final _promoCodeController = TextEditingController();
  String _target = 'all';
  bool _sendPush = true;
  bool _sendEmail = true;
  bool _sending = false;

  static const _targets = <String, String>{
    'all': 'All customers',
    'active': 'Active (ordered in last 30 days)',
    'inactive': 'Inactive (no order in 30+ days)',
    'segment': 'New users (segment)',
  };

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    _promoCodeController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_sendPush && !_sendEmail) {
      AppSnackbar.error(context, 'Pick at least one channel.');
      return;
    }
    setState(() => _sending = true);
    try {
      final body = <String, dynamic>{
        'title': _titleController.text.trim(),
        'message': _messageController.text.trim(),
        'target': _target == 'segment' ? 'segment' : _target,
        if (_target == 'segment') 'segment': 'new_user',
        'send_push': _sendPush,
        'send_email': _sendEmail,
      };
      final code = _promoCodeController.text.trim();
      if (code.isNotEmpty) body['promo_code'] = code;

      final resp = await SupabaseConfig.client.functions
          .invoke('admin-broadcast', body: body);
      final data = resp.data is Map
          ? resp.data as Map<String, dynamic>
          : <String, dynamic>{};
      if (data['error'] != null) throw Exception(data['error']);

      if (!mounted) return;
      Navigator.pop(context);
      AppSnackbar.success(
        context,
        'Broadcast sent — push: ${data['push_sent'] ?? 0}, email: ${data['email_sent'] ?? 0}',
      );
    } on FunctionException catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.campaign_rounded, color: AppTheme.primaryColor),
                    const SizedBox(width: 8),
                    const Text(
                      'Broadcast to Customers',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Sends a push notification and/or email to the selected audience.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    prefixIcon: Icon(Icons.title_rounded),
                    helperText: 'Shown as the push title and email subject',
                  ),
                  maxLength: 60,
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? 'Required' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _messageController,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    prefixIcon: Icon(Icons.message_rounded),
                    alignLabelWithHint: true,
                  ),
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 400,
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? 'Required' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _promoCodeController,
                  decoration: const InputDecoration(
                    labelText: 'Promo code (optional)',
                    prefixIcon: Icon(Icons.confirmation_number_rounded),
                    helperText: 'Highlighted in the email + sent in push data',
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _target,
                  decoration: const InputDecoration(
                    labelText: 'Audience',
                    prefixIcon: Icon(Icons.group_rounded),
                  ),
                  items: _targets.entries
                      .map((e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setState(() => _target = v ?? 'all'),
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _sendPush,
                  onChanged: (v) => setState(() => _sendPush = v),
                  title: const Text('Send push notification'),
                  secondary: const Icon(Icons.notifications_active_rounded),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _sendEmail,
                  onChanged: (v) => setState(() => _sendEmail = v),
                  title: const Text('Send email'),
                  secondary: const Icon(Icons.email_rounded),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _sending ? null : _send,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: _sending
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(_sending ? 'Sending…' : 'Send broadcast'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
