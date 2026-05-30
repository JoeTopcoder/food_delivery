import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/ride_pricing_settings.dart';
import '../../providers/ride_providers.dart';
import '../../../../utils/app_feedback_widgets.dart';

class RidePricingSettingsPage extends ConsumerStatefulWidget {
  const RidePricingSettingsPage({super.key});

  @override
  ConsumerState<RidePricingSettingsPage> createState() =>
      _RidePricingSettingsPageState();
}

class _RidePricingSettingsPageState
    extends ConsumerState<RidePricingSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  bool _loaded = false;

  // Controllers for every editable field
  late final TextEditingController _baseFare;
  late final TextEditingController _perKm;
  late final TextEditingController _perMin;
  late final TextEditingController _minFare;
  late final TextEditingController _commission;
  late final TextEditingController _surge;
  late final TextEditingController _searchRadius;
  late final TextEditingController _driverTimeout;
  late final TextEditingController _waitingFee;
  late final TextEditingController _authBuffer;
  bool _cashEnabled = true;
  bool _cardEnabled = true;

  @override
  void dispose() {
    _baseFare.dispose();
    _perKm.dispose();
    _perMin.dispose();
    _minFare.dispose();
    _commission.dispose();
    _surge.dispose();
    _searchRadius.dispose();
    _driverTimeout.dispose();
    _waitingFee.dispose();
    _authBuffer.dispose();
    super.dispose();
  }

  void _initControllers(RidePricingSettings s) {
    if (_loaded) return;
    _loaded = true;
    _baseFare = TextEditingController(text: s.baseFare.toString());
    _perKm = TextEditingController(text: s.perKmRate.toString());
    _perMin = TextEditingController(text: s.perMinuteRate.toString());
    _minFare = TextEditingController(text: s.minimumFare.toString());
    _commission =
        TextEditingController(text: s.platformCommissionPercent.toString());
    _surge = TextEditingController(text: s.surgeMultiplier.toString());
    _searchRadius =
        TextEditingController(text: s.maxSearchRadiusKm.toString());
    _driverTimeout =
        TextEditingController(text: s.driverRequestTimeoutSeconds.toString());
    _waitingFee =
        TextEditingController(text: s.waitingFeePerMin.toString());
    _authBuffer =
        TextEditingController(text: s.cardAuthBufferPercent.toString());
    _cashEnabled = s.cashEnabled;
    _cardEnabled = s.cardEnabled;
  }

  Future<void> _save(RidePricingSettings current) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final updated = current.copyWith(
        baseFare: double.parse(_baseFare.text),
        perKmRate: double.parse(_perKm.text),
        perMinuteRate: double.parse(_perMin.text),
        minimumFare: double.parse(_minFare.text),
        platformCommissionPercent: double.parse(_commission.text),
        surgeMultiplier: double.parse(_surge.text),
        maxSearchRadiusKm: double.parse(_searchRadius.text),
        driverRequestTimeoutSeconds: int.parse(_driverTimeout.text),
        waitingFeePerMin: double.parse(_waitingFee.text),
        cardAuthBufferPercent: double.parse(_authBuffer.text),
        cashEnabled: _cashEnabled,
        cardEnabled: _cardEnabled,
      );
      await ref.read(rideServiceProvider).updatePricingSettings(updated);
      ref.invalidate(ridePricingSettingsProvider);
      if (mounted) AppSnackbar.success(context, 'Settings saved');
    } catch (e) {
      if (mounted) AppSnackbar.error(context, 'Failed to save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(ridePricingSettingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride Pricing Settings'),
        elevation: 0,
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (settings) {
          _initControllers(settings);
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _Section(
                  title: 'Fare Calculation',
                  children: [
                    _Field(
                      label: 'Base Fare (J\$)',
                      ctrl: _baseFare,
                      hint: 'e.g. 300',
                    ),
                    _Field(
                      label: 'Per-km Rate (J\$)',
                      ctrl: _perKm,
                      hint: 'e.g. 120',
                    ),
                    _Field(
                      label: 'Per-minute Rate (J\$)',
                      ctrl: _perMin,
                      hint: 'e.g. 25',
                    ),
                    _Field(
                      label: 'Minimum Fare (J\$)',
                      ctrl: _minFare,
                      hint: 'e.g. 500',
                    ),
                    _Field(
                      label: 'Surge Multiplier',
                      ctrl: _surge,
                      hint: 'e.g. 1.0',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _Section(
                  title: 'Fees & Commission',
                  children: [
                    _Field(
                      label: 'Platform Commission (%)',
                      ctrl: _commission,
                      hint: 'e.g. 20',
                      suffix: '%',
                    ),
                    _Field(
                      label: 'Waiting Fee per Minute (J\$)',
                      ctrl: _waitingFee,
                      hint: 'e.g. 75',
                    ),
                    _Field(
                      label: 'Card Auth Buffer (%)',
                      ctrl: _authBuffer,
                      hint: 'e.g. 50',
                      suffix: '%',
                      helperText:
                          'Extra % held on card at booking to cover wait fees & overruns. '
                          '50% on a J\$500 fare holds J\$750.',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _Section(
                  title: 'Dispatch',
                  children: [
                    _Field(
                      label: 'Max Search Radius (km)',
                      ctrl: _searchRadius,
                      hint: 'e.g. 15',
                    ),
                    _Field(
                      label: 'Driver Request Timeout (seconds)',
                      ctrl: _driverTimeout,
                      hint: 'e.g. 60',
                      isInt: true,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _Section(
                  title: 'Payment Methods',
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Cash Payments'),
                      value: _cashEnabled,
                      onChanged: (v) => setState(() => _cashEnabled = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Card Payments'),
                      value: _cardEnabled,
                      onChanged: (v) => setState(() => _cardEnabled = v),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _saving ? null : () => _save(settings),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'Save Settings',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.primary,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final String hint;
  final String? suffix;
  final String? helperText;
  final bool isInt;

  const _Field({
    required this.label,
    required this.ctrl,
    required this.hint,
    this.suffix,
    this.helperText,
    this.isInt = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: ctrl,
        keyboardType:
            isInt ? TextInputType.number : const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          suffixText: suffix,
          helperText: helperText,
          helperMaxLines: 3,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          isDense: true,
        ),
        validator: (v) {
          if (v == null || v.isEmpty) return 'Required';
          if (isInt) {
            if (int.tryParse(v) == null) return 'Enter a whole number';
          } else {
            if (double.tryParse(v) == null) return 'Enter a valid number';
          }
          return null;
        },
      ),
    );
  }
}
