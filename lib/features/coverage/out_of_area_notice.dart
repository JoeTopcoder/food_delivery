import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/address_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';
import 'coverage_provider.dart';

/// Shown instead of an empty restaurant list when the customer is outside the
/// delivery radius.
///
/// "No restaurants found" reads as a broken app, and it is the moment someone
/// deletes it. This says the true thing — we are not there yet — and takes a
/// contact, which turns a bounce into a line on the list of where to open next.
class OutOfAreaNotice extends ConsumerStatefulWidget {
  const OutOfAreaNotice({super.key});

  @override
  ConsumerState<OutOfAreaNotice> createState() => _OutOfAreaNoticeState();
}

class _OutOfAreaNoticeState extends ConsumerState<OutOfAreaNotice> {
  final _contact = TextEditingController();
  bool _sending = false;
  bool _joined = false;

  @override
  void initState() {
    super.initState();
    // Prefill from the account: most people signed in will not retype it, and
    // an empty box is one more reason to give up here.
    final user = ref.read(currentUserProvider);
    _contact.text = user?.email ?? user?.phone ?? '';
  }

  @override
  void dispose() {
    _contact.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final contact = _contact.text.trim();
    if (contact.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an email or phone number')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      final address = ref.read(selectedAddressProvider);
      final coverage = ref.read(coverageProvider).valueOrNull;
      await ref
          .read(coverageServiceProvider)
          .joinWaitlist(
            contact: contact,
            latitude: address?.latitude,
            longitude: address?.longitude,
            address: address?.address,
            nearestKm: coverage?.nearestKm,
          );
      if (!mounted) return;
      setState(() {
        _sending = false;
        _joined = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final address = ref.watch(selectedAddressProvider);
    final nearest = ref.watch(coverageProvider).valueOrNull?.nearestKmRounded;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.location_off_outlined,
                color: AppTheme.primaryColor,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "We're not delivering here yet",
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            address?.address != null
                ? 'Nothing is close enough to ${address!.address} to deliver'
                      '${nearest != null ? ' — our nearest store is ${nearest.toStringAsFixed(0)} km away' : ''}.'
                : 'Nothing is close enough to your address to deliver yet.',
            style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),

          if (_joined)
            Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: Color(0xFF12B76A),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "You're on the list. We'll be in touch the moment we reach "
                    'you.',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ],
            )
          else ...[
            Text(
              'Tell us where you are and we’ll let you know as soon as we get '
              'there.',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _contact,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Email or phone',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 46,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _sending ? null : _join,
                    child: _sending
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Notify me'),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 14),
          Text(
            'Already somewhere we deliver? Change your address at the top of '
            'the screen.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
