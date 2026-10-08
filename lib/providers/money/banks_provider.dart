import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BankCountry {
  final String code;
  final String name;
  const BankCountry({required this.code, required this.name});
}

class BankEntry {
  final String id;
  final String countryCode;
  final String bankName;
  final List<String> branches;
  const BankEntry({
    required this.id,
    required this.countryCode,
    required this.bankName,
    required this.branches,
  });
}

// Distinct countries present in the banks table, sorted by name.
final countriesWithBanksProvider = FutureProvider<List<BankCountry>>((ref) async {
  final rows = await Supabase.instance.client
      .from('banks')
      .select('country_code, country_name')
      .eq('is_active', true)
      .order('country_name');

  final seen = <String>{};
  final out = <BankCountry>[];
  for (final r in (rows as List)) {
    final code = r['country_code'] as String;
    if (seen.add(code)) {
      out.add(BankCountry(code: code, name: r['country_name'] as String));
    }
  }
  return out;
});

// Banks for a given country code.
final banksByCountryProvider =
    FutureProvider.family<List<BankEntry>, String>((ref, countryCode) async {
  if (countryCode.isEmpty) return [];
  final rows = await Supabase.instance.client
      .from('banks')
      .select('id, bank_name, branches')
      .eq('country_code', countryCode)
      .eq('is_active', true)
      .order('sort_order')
      .order('bank_name');

  return (rows as List).map((r) => BankEntry(
    id: r['id'] as String,
    countryCode: countryCode,
    bankName: r['bank_name'] as String,
    branches: List<String>.from(r['branches'] as List? ?? []),
  )).toList();
});
