import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../providers/banks_provider.dart';
import '../../providers/driver_provider.dart';
import '../../providers/payout_provider.dart';
import '../../providers/restaurant_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';

class BankInfoScreen extends ConsumerStatefulWidget {
  final String role;
  const BankInfoScreen({super.key, required this.role});

  @override
  ConsumerState<BankInfoScreen> createState() => _BankInfoScreenState();
}

class _BankInfoScreenState extends ConsumerState<BankInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _accountNumberCtrl = TextEditingController();
  final _accountHolderCtrl = TextEditingController();

  String? _selectedCountryCode;
  String? _selectedBankName;
  String? _selectedBranch;
  String _accountType = 'checking';
  bool _saving = false;
  bool _initialized = false;

  @override
  void dispose() {
    _accountNumberCtrl.dispose();
    _accountHolderCtrl.dispose();
    super.dispose();
  }

  // Load saved bank_country_code from DB (bypass model to avoid codegen)
  Future<String?> _loadSavedCountryCode(String table, String id) async {
    try {
      final row = await Supabase.instance.client
          .from(table)
          .select('bank_country_code')
          .eq('id', id)
          .maybeSingle();
      return row?['bank_country_code'] as String?;
    } catch (_) {
      return null;
    }
  }

  void _onCountryChanged(String? code) {
    setState(() {
      _selectedCountryCode = code;
      _selectedBankName = null;
      _selectedBranch = null;
    });
  }

  void _onBankChanged(String? bankName, List<String> branches) {
    setState(() {
      _selectedBankName = bankName;
      _selectedBranch = branches.isEmpty ? '' : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserIdProvider);
    if (currentUserId == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    final isDriver = widget.role == 'driver';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Banking Information',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor:
            isDriver ? AppTheme.primaryColor : const Color(0xFF10B981),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: isDriver
          ? _buildDriverBody(currentUserId)
          : _buildRestaurantBody(currentUserId),
    );
  }

  Widget _buildDriverBody(String userId) {
    final driverAsync = ref.watch(driverProfileProvider(userId));
    return driverAsync.when(
      loading: () =>
          const AppLoadingIndicator(message: 'Loading bank info...'),
      error: (e, _) => AppErrorState(
        message: friendlyError(e),
        onRetry: () => ref.invalidate(driverProfileProvider(userId)),
      ),
      data: (driver) {
        if (driver == null) {
          return const Center(child: Text('No driver profile'));
        }
        if (!_initialized) {
          _accountNumberCtrl.text = driver.bankAccountNumber ?? '';
          _accountHolderCtrl.text = driver.bankAccountHolder ?? '';
          _accountType = driver.bankAccountType ?? 'checking';
          _selectedBankName = driver.bankName?.isNotEmpty == true
              ? driver.bankName
              : null;
          _initialized = true;
          // Fetch saved country code asynchronously
          _loadSavedCountryCode('drivers', driver.id).then((code) {
            if (mounted && _selectedCountryCode == null) {
              setState(() => _selectedCountryCode = code ?? 'KY');
            }
          });
        }
        return _buildForm(
          onSave: (countryCode) async {
            final svc = ref.read(payoutServiceProvider);
            await svc.saveDriverBankInfo(
              driverId: driver.id,
              bankName: _selectedBankName ?? '',
              bankBranch: _selectedBranch ?? '',
              accountNumber: _accountNumberCtrl.text.trim(),
              accountHolder: _accountHolderCtrl.text.trim(),
              accountType: _accountType,
              bankCountryCode: countryCode,
            );
            ref.invalidate(driverProfileProvider(userId));
          },
        );
      },
    );
  }

  Widget _buildRestaurantBody(String userId) {
    final restAsync = ref.watch(restaurantByOwnerProvider(userId));
    return restAsync.when(
      loading: () =>
          const AppLoadingIndicator(message: 'Loading bank info...'),
      error: (e, _) => AppErrorState(
        message: friendlyError(e),
        onRetry: () => ref.invalidate(restaurantByOwnerProvider(userId)),
      ),
      data: (restaurant) {
        if (restaurant == null) {
          return const Center(child: Text('No restaurant profile'));
        }
        if (!_initialized) {
          _accountNumberCtrl.text = restaurant.bankAccountNumber ?? '';
          _accountHolderCtrl.text = restaurant.bankAccountHolder ?? '';
          _accountType = restaurant.bankAccountType ?? 'checking';
          _selectedBankName = restaurant.bankName?.isNotEmpty == true
              ? restaurant.bankName
              : null;
          _initialized = true;
          _loadSavedCountryCode('restaurants', restaurant.id).then((code) {
            if (mounted && _selectedCountryCode == null) {
              setState(() => _selectedCountryCode = code ?? 'KY');
            }
          });
        }
        return _buildForm(
          onSave: (countryCode) async {
            final svc = ref.read(payoutServiceProvider);
            await svc.saveRestaurantBankInfo(
              restaurantId: restaurant.id,
              bankName: _selectedBankName ?? '',
              bankBranch: _selectedBranch ?? '',
              accountNumber: _accountNumberCtrl.text.trim(),
              accountHolder: _accountHolderCtrl.text.trim(),
              accountType: _accountType,
              bankCountryCode: countryCode,
            );
            ref.invalidate(restaurantByOwnerProvider(userId));
          },
        );
      },
    );
  }

  Widget _buildForm({required Future<void> Function(String countryCode) onSave}) {
    final countriesAsync = ref.watch(countriesWithBanksProvider);
    final banksAsync = ref.watch(
      banksByCountryProvider(_selectedCountryCode ?? ''),
    );

    final banks = banksAsync.valueOrNull ?? [];
    final selectedBank = banks.firstWhere(
      (b) => b.bankName == _selectedBankName,
      orElse: () => BankEntry(
        id: '', countryCode: '', bankName: '', branches: [],
      ),
    );
    final branches = selectedBank.branches;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info banner
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline,
                      color: Color(0xFF3B82F6), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Add your bank details to receive payouts. '
                      'Your information is stored securely.',
                      style:
                          TextStyle(fontSize: 13, color: Color(0xFF1E40AF)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Country ──────────────────────────────────────────
            const _Label('Country'),
            const SizedBox(height: 6),
            countriesAsync.when(
              loading: () => const _LoadingField(),
              error: (_, __) => const _ErrorField('Could not load countries'),
              data: (countries) => DropdownButtonFormField<String>(
                initialValue: countries.any((c) => c.code == _selectedCountryCode)
                    ? _selectedCountryCode
                    : null,
                decoration: _inputDecoration('Select your country'),
                isExpanded: true,
                items: countries.map((c) => DropdownMenuItem(
                  value: c.code,
                  child: Text(c.name, style: const TextStyle(fontSize: 14)),
                )).toList(),
                onChanged: _onCountryChanged,
                validator: (v) =>
                    v == null || v.isEmpty ? 'Required' : null,
              ),
            ),
            const SizedBox(height: 16),

            // ── Bank ─────────────────────────────────────────────
            const _Label('Bank Name'),
            const SizedBox(height: 6),
            if (_selectedCountryCode == null)
              _inputHint('Select a country first')
            else
              banksAsync.when(
                loading: () => const _LoadingField(),
                error: (_, __) =>
                    const _ErrorField('Could not load banks'),
                data: (bankList) => DropdownButtonFormField<String>(
                  key: ValueKey(_selectedCountryCode),
                  initialValue: bankList.any((b) => b.bankName == _selectedBankName)
                      ? _selectedBankName
                      : null,
                  decoration: _inputDecoration('Select your bank'),
                  isExpanded: true,
                  items: bankList.map((b) => DropdownMenuItem(
                    value: b.bankName,
                    child: Text(b.bankName,
                        style: const TextStyle(fontSize: 14)),
                  )).toList(),
                  onChanged: (value) => _onBankChanged(
                    value,
                    bankList.firstWhere(
                      (b) => b.bankName == value,
                      orElse: () => BankEntry(
                          id: '', countryCode: '', bankName: '',
                          branches: []),
                    ).branches,
                  ),
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Required' : null,
                ),
              ),
            const SizedBox(height: 16),

            // ── Branch (only when the selected bank has branches) ─
            if (branches.isNotEmpty) ...[
              const _Label('Branch'),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                key: ValueKey(_selectedBankName),
                initialValue: branches.contains(_selectedBranch)
                    ? _selectedBranch
                    : null,
                decoration: _inputDecoration('Select your branch'),
                isExpanded: true,
                items: branches.map((br) => DropdownMenuItem(
                  value: br,
                  child: Text(br, style: const TextStyle(fontSize: 14)),
                )).toList(),
                onChanged: (v) => setState(() => _selectedBranch = v),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
            ],

            // ── Account Number ───────────────────────────────────
            const _Label('Account Number'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _accountNumberCtrl,
              decoration: _inputDecoration('Your bank account number'),
              keyboardType: TextInputType.number,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            // ── Account Holder ───────────────────────────────────
            const _Label('Account Holder Name'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _accountHolderCtrl,
              decoration: _inputDecoration('Full name on the account'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            // ── Account Type ─────────────────────────────────────
            const _Label('Account Type'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _accountType,
              decoration: _inputDecoration(''),
              items: const [
                DropdownMenuItem(value: 'checking', child: Text('Checking')),
                DropdownMenuItem(value: 'savings', child: Text('Savings')),
              ],
              onChanged: (v) =>
                  setState(() => _accountType = v ?? 'checking'),
            ),
            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saving
                    ? null
                    : () => _save(() => onSave(_selectedCountryCode ?? 'KY')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.role == 'driver'
                      ? AppTheme.primaryColor
                      : const Color(0xFF10B981),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        'Save Banking Info',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Theme.of(context).inputDecorationTheme.fillColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _inputHint(String text) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).inputDecorationTheme.fillColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      alignment: Alignment.centerLeft,
      child: Text(text,
          style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
    );
  }

  Future<void> _save(Future<void> Function() onSave) async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBankName == null || _selectedBankName!.isEmpty) {
      AppSnackbar.error(context, 'Please select a bank');
      return;
    }
    setState(() => _saving = true);
    try {
      await onSave();
      if (mounted) {
        AppSnackbar.success(context, 'Banking info saved!');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ── Small helpers ─────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text,
        style:
            const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      );
}

class _LoadingField extends StatelessWidget {
  const _LoadingField();
  @override
  Widget build(BuildContext context) => Container(
        height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFD1D5DB)),
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
}

class _ErrorField extends StatelessWidget {
  final String message;
  const _ErrorField(this.message);
  @override
  Widget build(BuildContext context) => Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFEF4444)),
        ),
        alignment: Alignment.centerLeft,
        child: Text(message,
            style:
                const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
      );
}
