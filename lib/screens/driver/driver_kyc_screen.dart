import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/payment/payout_service.dart' show StripePayoutService;
import '../../providers/driver_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/friendly_error.dart';
import '../../utils/safe_state_mixin.dart';

class DriverKycScreen extends ConsumerStatefulWidget {
  const DriverKycScreen({super.key});
  @override
  ConsumerState<DriverKycScreen> createState() => _DriverKycScreenState();
}

class _DriverKycScreenState extends ConsumerState<DriverKycScreen>
    with SafeConsumerStateMixin<DriverKycScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _ssn = TextEditingController();
  final _line1 = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _postal = TextEditingController();

  DateTime? _dob;
  bool _loading = false;
  String? _error;
  String? _success;

  static const _bg = Color(0xFF0F1117);
  static const _cardBg = Color(0xFF1C1F2E);
  static const _accent = Color(0xFF6C63FF);

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _ssn.dispose();
    _line1.dispose();
    _city.dispose();
    _state.dispose();
    _postal.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(1990, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _accent,
            surface: _cardBg,
          ),
        ),
        child: child!,
      ),
    );
    if (d != null) setState(() => _dob = d);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dob == null) {
      setState(() => _error = 'Please select your date of birth.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });
    try {
      await StripePayoutService.instance.updateKyc(
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        dobDay: _dob!.day,
        dobMonth: _dob!.month,
        dobYear: _dob!.year,
        ssnLast4: _ssn.text.trim().isEmpty ? null : _ssn.text.trim(),
        addressLine1: _line1.text.trim().isEmpty ? null : _line1.text.trim(),
        addressCity: _city.text.trim().isEmpty ? null : _city.text.trim(),
        addressState: _state.text.trim().isEmpty ? null : _state.text.trim(),
        addressPostal: _postal.text.trim().isEmpty ? null : _postal.text.trim(),
      );
      final userId = ref.read(currentUserIdProvider);
      if (userId != null) ref.invalidate(driverProfileProvider(userId));
      setState(
        () => _success =
            'Identity information submitted! Payouts will be enabled once Stripe verifies your details.',
      );
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text(
          'Identity Verification',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.1),
                  border: Border.all(color: _accent.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      color: Color(0xFF6C63FF),
                      size: 18,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This information is securely transmitted to Stripe for identity verification. We never store your SSN.',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _Section(
                label: 'Legal Name',
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _Field(
                          label: 'First Name',
                          controller: _firstName,
                          validator: (v) =>
                              v!.trim().isEmpty ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Field(
                          label: 'Last Name',
                          controller: _lastName,
                          validator: (v) =>
                              v!.trim().isEmpty ? 'Required' : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _Section(
                label: 'Date of Birth',
                children: [
                  GestureDetector(
                    onTap: _pickDob,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: _bg,
                        border: Border.all(color: Colors.white24),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_today,
                            color: Colors.white38,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _dob == null
                                ? 'Select date of birth'
                                : '${_dob!.month.toString().padLeft(2, '0')}/${_dob!.day.toString().padLeft(2, '0')}/${_dob!.year}',
                            style: TextStyle(
                              color: _dob == null
                                  ? Colors.white38
                                  : Colors.white,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _Section(
                label: 'SSN Last 4 Digits',
                subtitle: 'Used to verify your identity',
                children: [
                  _Field(
                    label: 'Last 4 digits of SSN',
                    controller: _ssn,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    obscureText: true,
                    validator: (v) {
                      if (v == null || v.isEmpty) return null;
                      if (v.length != 4) return 'Must be exactly 4 digits';
                      return null;
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _Section(
                label: 'Home Address',
                subtitle: 'Your residential address',
                children: [
                  _Field(label: 'Street Address', controller: _line1),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: _Field(label: 'City', controller: _city),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Field(
                          label: 'State',
                          controller: _state,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(2),
                            UpperCaseTextFormatter(),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _Field(
                    label: 'ZIP Code',
                    controller: _postal,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 28),
              if (_error != null)
                _Banner(
                  message: _error!,
                  color: Colors.redAccent,
                  icon: Icons.error_outline,
                ),
              if (_success != null)
                _Banner(
                  message: _success!,
                  color: const Color(0xFF00C896),
                  icon: Icons.check_circle,
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Submit Identity Info',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String label;
  final String? subtitle;
  final List<Widget> children;
  const _Section({required this.label, this.subtitle, required this.children});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 2),
        Text(
          subtitle!,
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ],
      const SizedBox(height: 10),
      ...children,
    ],
  );
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final bool obscureText;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  const _Field({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.obscureText = false,
    this.inputFormatters,
    this.validator,
  });
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: keyboardType,
    obscureText: obscureText,
    inputFormatters: inputFormatters,
    validator: validator,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white38),
      filled: true,
      fillColor: const Color(0xFF0F1117),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF6C63FF)),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    ),
  );
}

class _Banner extends StatelessWidget {
  final String message;
  final Color color;
  final IconData icon;
  const _Banner({
    required this.message,
    required this.color,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      border: Border.all(color: color.withValues(alpha: 0.4)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message, style: TextStyle(color: color, fontSize: 13)),
        ),
      ],
    ),
  );
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(
    text: newValue.text.toUpperCase(),
    selection: newValue.selection,
  );
}
