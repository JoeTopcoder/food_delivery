import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../services/company/company_service.dart';
import '../../utils/app_theme.dart';
import 'company_dashboard_screen.dart';
import 'company_register_screen.dart';

/// Employee "My Company": search a company, apply, and see application status.
/// Uses the employee's normal HotBite account.
class MyCompanyScreen extends ConsumerStatefulWidget {
  const MyCompanyScreen({super.key});
  @override
  ConsumerState<MyCompanyScreen> createState() => _MyCompanyScreenState();
}

class _MyCompanyScreenState extends ConsumerState<MyCompanyScreen> {
  final _search = TextEditingController();
  List<Company> _results = [];
  List<CompanyMembership> _memberships = [];
  bool _loading = true;
  bool _searching = false;
  bool _ownsCompany = false;

  CompanyService get _svc => ref.read(companyServiceProvider);

  @override
  void initState() {
    super.initState();
    _loadMemberships();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadMemberships() async {
    setState(() => _loading = true);
    try {
      _memberships = await _svc.myMemberships();
      _ownsCompany = (await _svc.myCompany()) != null;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _doSearch() async {
    setState(() => _searching = true);
    try {
      _results = await _svc.searchCompanies(_search.text);
    } catch (_) {}
    if (mounted) setState(() => _searching = false);
  }

  Future<void> _apply(Company c) async {
    try {
      await _svc.apply(c.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Application sent to ${c.name}')));
      _search.clear();
      setState(() => _results = []);
      _loadMemberships();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not apply: $e')));
    }
  }

  Color _statusColor(String s) => switch (s) {
        'approved' => const Color(0xFF16A34A),
        'pending' => const Color(0xFFD97706),
        'rejected' => const Color(0xFFDC2626),
        'suspended' => const Color(0xFF6B7280),
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    final appliedIds = _memberships.map((m) => m.companyId).toSet();
    return Scaffold(
      appBar: AppBar(title: const Text('My Company')),
      body: RefreshIndicator(
        onRefresh: _loadMemberships,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Join your company',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _doSearch(),
                  decoration: const InputDecoration(
                    hintText: 'Search company name',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _searching ? null : _doSearch,
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                child: _searching
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Search'),
              ),
            ]),
            const SizedBox(height: 8),
            ..._results.map((c) => Card(
                  child: ListTile(
                    title: Text(c.name),
                    subtitle: Text(c.deliveryAddress),
                    trailing: appliedIds.contains(c.id)
                        ? const Text('Applied')
                        : FilledButton(
                            onPressed: () => _apply(c),
                            style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                            child: const Text('Apply'),
                          ),
                  ),
                )),
            const Divider(height: 32),
            Text('Your applications',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (_memberships.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('You haven\'t applied to any company yet.',
                    style: TextStyle(color: Colors.grey)))
            else
              ..._memberships.map((m) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.business_rounded),
                      title: Text(m.companyName ?? 'Company'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _statusColor(m.status).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          m.status[0].toUpperCase() + m.status.substring(1),
                          style: TextStyle(color: _statusColor(m.status), fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ),
                    ),
                  )),
            const SizedBox(height: 8),
            Text(
              'Approved employees of an active company can choose "Company-sponsored order" at checkout — once per day. Your company covers delivery and service fees.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5, height: 1.4),
            ),
            const Divider(height: 32),
            _companyAdminFooter(),
          ],
        ),
      ),
    );
  }

  /// Dashboard access is only for company owners / HotBite admins. Regular
  /// customers see a modest "Register a company" affordance instead — never a
  /// company dashboard.
  Widget _companyAdminFooter() {
    final isHotbiteAdmin = ref.read(currentUserProvider)?.role == 'admin';
    if (_ownsCompany || isHotbiteAdmin) {
      return OutlinedButton.icon(
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const CompanyDashboardScreen())),
        icon: const Icon(Icons.dashboard_customize_rounded),
        label: const Text('Open company dashboard'),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Are you a company?',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5)),
      TextButton.icon(
        onPressed: () async {
          final created = await Navigator.push<bool>(context,
              MaterialPageRoute(builder: (_) => const CompanyRegisterScreen()));
          if (created == true) _loadMemberships();
        },
        style: TextButton.styleFrom(foregroundColor: AppTheme.primaryColor, padding: EdgeInsets.zero),
        icon: const Icon(Icons.add_business_rounded, size: 18),
        label: const Text('Register your company'),
      ),
    ]);
  }
}
