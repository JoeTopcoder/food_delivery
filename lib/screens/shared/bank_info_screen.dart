import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/driver_provider.dart';
import '../../providers/payout_provider.dart';
import '../../providers/restaurant_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';

class BankInfoScreen extends ConsumerStatefulWidget {
  final String role; // 'driver' or 'restaurant'
  const BankInfoScreen({super.key, required this.role});

  @override
  ConsumerState<BankInfoScreen> createState() => _BankInfoScreenState();
}

class _BankInfoScreenState extends ConsumerState<BankInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _bankNameCtrl = TextEditingController();
  final _bankBranchCtrl = TextEditingController();
  final _accountNumberCtrl = TextEditingController();
  final _accountHolderCtrl = TextEditingController();
  String _accountType = 'checking';
  bool _saving = false;
  bool _initialized = false;

  static const Map<String, List<String>> _bankBranches = {
    'National Commercial Bank': [
      'Half Way Tree',
      'New Kingston',
      'Cross Roads',
      'Liguanea',
      'Constant Spring',
      'Manor Park',
      'Downtown Kingston',
      'Portmore',
      'Spanish Town',
      'May Pen',
      'Mandeville',
      'Montego Bay',
      'Ocho Rios',
      'Savanna-la-Mar',
      'Falmouth',
      'Port Antonio',
      'Black River',
      'Linstead',
      'Old Harbour',
      'Santa Cruz',
      'Morant Bay',
      'Lucea',
      'Port Maria',
      'Brown\'s Town',
      'Christiana',
    ],
    'Scotiabank Jamaica': [
      'Half Way Tree',
      'New Kingston',
      'Cross Roads',
      'Liguanea',
      'Constant Spring',
      'Downtown Kingston',
      'Portmore',
      'Spanish Town',
      'May Pen',
      'Mandeville',
      'Montego Bay',
      'Ocho Rios',
      'Savanna-la-Mar',
      'Falmouth',
      'Port Antonio',
      'Black River',
      'Linstead',
      'Old Harbour',
      'Morant Bay',
      'Brown\'s Town',
    ],
    'JMMB Bank': [
      'New Kingston',
      'Half Way Tree',
      'Portmore',
      'Spanish Town',
      'May Pen',
      'Mandeville',
      'Montego Bay',
      'Ocho Rios',
      'Savanna-la-Mar',
    ],
    'Sagicor Bank Jamaica': [
      'New Kingston',
      'Half Way Tree',
      'Liguanea',
      'Portmore',
      'Spanish Town',
      'May Pen',
      'Mandeville',
      'Montego Bay',
      'Ocho Rios',
    ],
    'CIBC FirstCaribbean': [
      'New Kingston',
      'Half Way Tree',
      'Montego Bay',
      'Ocho Rios',
      'Mandeville',
    ],
    'JN Bank': [
      'Half Way Tree',
      'New Kingston',
      'Cross Roads',
      'Portmore',
      'Spanish Town',
      'May Pen',
      'Mandeville',
      'Montego Bay',
      'Ocho Rios',
      'Savanna-la-Mar',
      'Port Antonio',
      'Brown\'s Town',
      'Linstead',
    ],
    'First Global Bank': [
      'New Kingston',
      'Montego Bay',
      'Mandeville',
      'Ocho Rios',
    ],
    'VM Building Society': [
      'Half Way Tree',
      'New Kingston',
      'Cross Roads',
      'Portmore',
      'Spanish Town',
      'May Pen',
      'Mandeville',
      'Montego Bay',
      'Ocho Rios',
      'Savanna-la-Mar',
    ],
    'Bank of Nova Scotia Jamaica': [
      'Half Way Tree',
      'New Kingston',
      'Cross Roads',
      'Liguanea',
      'Constant Spring',
      'Downtown Kingston',
      'Portmore',
      'Spanish Town',
      'May Pen',
      'Mandeville',
      'Montego Bay',
      'Ocho Rios',
      'Savanna-la-Mar',
      'Falmouth',
      'Port Antonio',
      'Black River',
      'Linstead',
      'Old Harbour',
      'Morant Bay',
      'Brown\'s Town',
    ],
    'Mayberry Investments': ['New Kingston', 'Mandeville', 'Montego Bay'],
  };

  List<String> get _availableBranches {
    final bank = _bankNameCtrl.text;
    return _bankBranches[bank] ?? [];
  }

  @override
  void dispose() {
    _bankNameCtrl.dispose();
    _bankBranchCtrl.dispose();
    _accountNumberCtrl.dispose();
    _accountHolderCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserIdProvider);
    if (currentUserId == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    final isDriver = widget.role == 'driver';

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text(
          'Banking Information',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: isDriver
            ? AppTheme.primaryColor
            : const Color(0xFF10B981),
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
      loading: () => const AppLoadingIndicator(message: 'Loading bank info...'),
      error: (e, _) => AppErrorState(
        message: friendlyError(e),
        onRetry: () => ref.invalidate(driverProfileProvider(userId)),
      ),
      data: (driver) {
        if (driver == null) {
          return const Center(child: Text('No driver profile'));
        }
        if (!_initialized) {
          _bankNameCtrl.text = driver.bankName ?? '';
          _bankBranchCtrl.text = driver.bankBranch ?? '';
          _accountNumberCtrl.text = driver.bankAccountNumber ?? '';
          _accountHolderCtrl.text = driver.bankAccountHolder ?? '';
          _accountType = driver.bankAccountType ?? 'checking';
          _initialized = true;
        }
        return _buildForm(
          onSave: () async {
            final svc = ref.read(payoutServiceProvider);
            await svc.saveDriverBankInfo(
              driverId: driver.id,
              bankName: _bankNameCtrl.text.trim(),
              bankBranch: _bankBranchCtrl.text.trim(),
              accountNumber: _accountNumberCtrl.text.trim(),
              accountHolder: _accountHolderCtrl.text.trim(),
              accountType: _accountType,
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
      loading: () => const AppLoadingIndicator(message: 'Loading bank info...'),
      error: (e, _) => AppErrorState(
        message: friendlyError(e),
        onRetry: () => ref.invalidate(restaurantByOwnerProvider(userId)),
      ),
      data: (restaurant) {
        if (restaurant == null) {
          return const Center(child: Text('No restaurant profile'));
        }
        if (!_initialized) {
          _bankNameCtrl.text = restaurant.bankName ?? '';
          _bankBranchCtrl.text = restaurant.bankBranch ?? '';
          _accountNumberCtrl.text = restaurant.bankAccountNumber ?? '';
          _accountHolderCtrl.text = restaurant.bankAccountHolder ?? '';
          _accountType = restaurant.bankAccountType ?? 'checking';
          _initialized = true;
        }
        return _buildForm(
          onSave: () async {
            final svc = ref.read(payoutServiceProvider);
            await svc.saveRestaurantBankInfo(
              restaurantId: restaurant.id,
              bankName: _bankNameCtrl.text.trim(),
              bankBranch: _bankBranchCtrl.text.trim(),
              accountNumber: _accountNumberCtrl.text.trim(),
              accountHolder: _accountHolderCtrl.text.trim(),
              accountType: _accountType,
            );
            ref.invalidate(restaurantByOwnerProvider(userId));
          },
        );
      },
    );
  }

  Widget _buildForm({required Future<void> Function() onSave}) {
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
                  Icon(Icons.info_outline, color: Color(0xFF3B82F6), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Add your bank details to receive payouts. '
                      'Your information is stored securely.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF1E40AF)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            const Text(
              'Bank Name',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _bankBranches.containsKey(_bankNameCtrl.text)
                  ? _bankNameCtrl.text
                  : null,
              decoration: _inputDecoration('Select your bank'),
              isExpanded: true,
              items: _bankBranches.keys
                  .map(
                    (bank) => DropdownMenuItem(
                      value: bank,
                      child: Text(bank, style: const TextStyle(fontSize: 14)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _bankNameCtrl.text = value;
                    _bankBranchCtrl.text = '';
                  });
                }
              },
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            const Text(
              'Branch',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              key: ValueKey(_bankNameCtrl.text),
              initialValue: _availableBranches.contains(_bankBranchCtrl.text)
                  ? _bankBranchCtrl.text
                  : null,
              decoration: _inputDecoration(
                _bankNameCtrl.text.isEmpty
                    ? 'Select a bank first'
                    : 'Select your branch',
              ),
              isExpanded: true,
              items: _availableBranches
                  .map(
                    (branch) => DropdownMenuItem(
                      value: branch,
                      child: Text(branch, style: const TextStyle(fontSize: 14)),
                    ),
                  )
                  .toList(),
              onChanged: _bankNameCtrl.text.isEmpty
                  ? null
                  : (value) {
                      if (value != null) {
                        _bankBranchCtrl.text = value;
                      }
                    },
            ),
            const SizedBox(height: 16),

            const Text(
              'Account Number',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _accountNumberCtrl,
              decoration: _inputDecoration('Your bank account number'),
              keyboardType: TextInputType.number,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            const Text(
              'Account Holder Name',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _accountHolderCtrl,
              decoration: _inputDecoration('Full name on the account'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            const Text(
              'Account Type',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _accountType,
              decoration: _inputDecoration(''),
              items: const [
                DropdownMenuItem(value: 'checking', child: Text('Checking')),
                DropdownMenuItem(value: 'savings', child: Text('Savings')),
              ],
              onChanged: (v) => setState(() => _accountType = v ?? 'checking'),
            ),
            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : () => _save(onSave),
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
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Save Banking Info',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
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
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Future<void> _save(Future<void> Function() onSave) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await onSave();
      if (mounted) {
        AppSnackbar.success(context, 'Banking info saved!');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
