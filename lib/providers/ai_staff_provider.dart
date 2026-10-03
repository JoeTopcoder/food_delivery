import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/supabase_config.dart';
import 'auth_provider.dart';

/// Providers + models for the admin "AI Staff" section (Stages 2–6).
///
/// All reads go through the normal authenticated Supabase client, so the RLS
/// policies on ai_staff_* (admin-only, public.is_admin()) are the access
/// control — no service key is ever in the app. Workflow writes (approve /
/// reject / assign / start / complete a suggestion, acknowledge / resolve an
/// alert) go through the admin-only UPDATE policies and record who + when.
///
/// The AI never executes an action here. Approving a suggestion only records
/// the decision; anything touching prices, refunds, payouts, rider
/// restrictions or customer messages still runs through its existing human
/// workflow elsewhere in the app.

class AiRole {
  final String id, slug, title, jobDescription, status;
  final String? department, dailyReporting;
  final List<String> dataCategories;
  final int maxSuggestions;
  AiRole(this.id, this.slug, this.title, this.jobDescription, this.status,
      this.department, this.dailyReporting, this.dataCategories, this.maxSuggestions);
  factory AiRole.fromJson(Map<String, dynamic> j) => AiRole(
        j['id'] as String,
        j['slug'] as String,
        (j['title'] as String?) ?? j['slug'] as String,
        (j['job_description'] as String?) ?? '',
        (j['status'] as String?) ?? 'active',
        j['department'] as String?,
        j['daily_reporting_requirements'] as String?,
        ((j['data_categories'] as List?) ?? const []).map((e) => e.toString()).toList(),
        (j['max_suggestions'] as num?)?.toInt() ?? 3,
      );
}

class AiStaffReport {
  final String id, roleId, reportDate, status;
  final String? summary;
  final Map<String, dynamic> metrics;
  final Map<String, dynamic> evidence; // { findings:[], data_limitations }
  final String? error;
  final DateTime? createdAt;
  AiStaffReport(this.id, this.roleId, this.reportDate, this.status, this.summary,
      this.metrics, this.evidence, this.error, this.createdAt);
  factory AiStaffReport.fromJson(Map<String, dynamic> j) => AiStaffReport(
        j['id'] as String,
        j['role_id'] as String,
        j['report_date'].toString(),
        (j['status'] as String?) ?? 'completed',
        j['summary'] as String?,
        Map<String, dynamic>.from((j['metrics'] as Map?) ?? const {}),
        Map<String, dynamic>.from((j['evidence'] as Map?) ?? const {}),
        j['error'] as String?,
        j['created_at'] != null ? DateTime.tryParse(j['created_at'].toString()) : null,
      );
  List<dynamic> get findings => (evidence['findings'] as List?) ?? const [];
  String get dataLimitations => (evidence['data_limitations'] as String?) ?? '';
}

class AiSuggestion {
  final String id, reportDate, title, description, priority, status;
  final String? roleId, rationale, estimatedImpact, reviewedBy, assignedTo, reviewNotes;
  final DateTime? reviewedAt, assignedAt, completedAt;
  final Map<String, dynamic> evidence;
  // Stage 8 action proposal + execution lifecycle
  final String? actionType, actionStatus;
  final bool requiresManualAdmin, hasExternalEffect;
  final Map<String, dynamic>? actionPayload;
  AiSuggestion(this.id, this.reportDate, this.title, this.description, this.priority,
      this.status, this.roleId, this.rationale, this.estimatedImpact, this.reviewedBy,
      this.assignedTo, this.reviewNotes, this.reviewedAt, this.assignedAt, this.completedAt,
      this.evidence, this.actionType, this.actionStatus, this.requiresManualAdmin,
      this.hasExternalEffect, this.actionPayload);
  factory AiSuggestion.fromJson(Map<String, dynamic> j) => AiSuggestion(
        j['id'] as String,
        j['report_date'].toString(),
        (j['title'] as String?) ?? 'Suggestion',
        (j['description'] as String?) ?? '',
        (j['priority'] as String?) ?? 'medium',
        (j['status'] as String?) ?? 'pending',
        j['role_id'] as String?,
        j['rationale'] as String?,
        j['estimated_impact'] as String?,
        j['reviewed_by'] as String?,
        j['assigned_to'] as String?,
        j['review_notes'] as String?,
        j['reviewed_at'] != null ? DateTime.tryParse(j['reviewed_at'].toString()) : null,
        j['assigned_at'] != null ? DateTime.tryParse(j['assigned_at'].toString()) : null,
        j['completed_at'] != null ? DateTime.tryParse(j['completed_at'].toString()) : null,
        Map<String, dynamic>.from((j['evidence'] as Map?) ?? const {}),
        j['action_type'] as String?,
        j['action_status'] as String?,
        (j['requires_manual_admin'] as bool?) ?? false,
        (j['has_external_effect'] as bool?) ?? false,
        j['action_payload'] != null ? Map<String, dynamic>.from(j['action_payload'] as Map) : null,
      );
  bool get isExecutable => actionType != null && actionPayload != null && !requiresManualAdmin;
}

/// Executions + tasks produced for a suggestion (evidence of work).
final aiSuggestionWorkProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, suggestionId) async {
  final execs = await SupabaseConfig.client
      .from('ai_action_executions').select().eq('suggestion_id', suggestionId)
      .order('created_at', ascending: false);
  final tasks = await SupabaseConfig.client
      .from('ai_admin_tasks').select().eq('suggestion_id', suggestionId)
      .order('created_at', ascending: false);
  return {'executions': execs as List, 'tasks': tasks as List};
});

class AiAlert {
  final String id, reportDate, severity, title, message, status;
  final String? roleId, acknowledgedBy, resolvedBy;
  final DateTime? createdAt, acknowledgedAt, resolvedAt;
  final Map<String, dynamic> evidence;
  AiAlert(this.id, this.reportDate, this.severity, this.title, this.message, this.status,
      this.roleId, this.acknowledgedBy, this.resolvedBy, this.createdAt, this.acknowledgedAt,
      this.resolvedAt, this.evidence);
  factory AiAlert.fromJson(Map<String, dynamic> j) => AiAlert(
        j['id'] as String,
        j['report_date'].toString(),
        (j['severity'] as String?) ?? 'high',
        (j['title'] as String?) ?? 'Alert',
        (j['message'] as String?) ?? '',
        (j['status'] as String?) ?? 'open',
        j['role_id'] as String?,
        j['acknowledged_by'] as String?,
        j['resolved_by'] as String?,
        j['created_at'] != null ? DateTime.tryParse(j['created_at'].toString()) : null,
        j['acknowledged_at'] != null ? DateTime.tryParse(j['acknowledged_at'].toString()) : null,
        j['resolved_at'] != null ? DateTime.tryParse(j['resolved_at'].toString()) : null,
        Map<String, dynamic>.from((j['evidence'] as Map?) ?? const {}),
      );
}

class AiBriefing {
  final String id, briefingDate;
  final String? headline, summary;
  final Map<String, dynamic> highlights, metrics;
  final int rolesReported, suggestionsCount, urgentCount;
  AiBriefing(this.id, this.briefingDate, this.headline, this.summary, this.highlights,
      this.metrics, this.rolesReported, this.suggestionsCount, this.urgentCount);
  factory AiBriefing.fromJson(Map<String, dynamic> j) => AiBriefing(
        j['id'] as String,
        j['briefing_date'].toString(),
        j['headline'] as String?,
        j['summary'] as String?,
        Map<String, dynamic>.from((j['highlights'] as Map?) ?? const {}),
        Map<String, dynamic>.from((j['metrics'] as Map?) ?? const {}),
        (j['roles_reported'] as num?)?.toInt() ?? 0,
        (j['suggestions_count'] as num?)?.toInt() ?? 0,
        (j['urgent_count'] as num?)?.toInt() ?? 0,
      );
}

/// Selected period for the admin overview KPIs.
// Default to a 30-day window so the dashboard opens on real activity rather than
// a quiet "today" that reads $0 when nothing has been delivered yet today.
final adminOverviewPeriodProvider = StateProvider<String>((ref) => '30d');

/// Admin overview KPIs for a selected period (today/7d/30d/all).
/// Direct table queries (admin RLS) so it can't hang on an RPC; America/Jamaica
/// day windows (UTC-5). Revenue = delivered orders' total in the window; orders
/// = placed in the window; riders/stores = current live counts.
final adminOverviewStatsProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, period) async {
  final client = SupabaseConfig.client;
  // Jamaica midnight (05:00 UTC) for the requested window.
  final jamNow = DateTime.now().toUtc().subtract(const Duration(hours: 5));
  final jamMidnightUtc = DateTime.utc(jamNow.year, jamNow.month, jamNow.day, 5);
  DateTime? from;
  if (period == 'today') {
    from = jamMidnightUtc;
  } else if (period == '7d') {
    from = jamMidnightUtc.subtract(const Duration(days: 6));
  } else if (period == '30d') {
    from = jamMidnightUtc.subtract(const Duration(days: 29));
  } // else 'all' → no lower bound

  Future<T> guarded<T>(Future<T> f, T fallback) =>
      f.timeout(const Duration(seconds: 12)).catchError((_) => fallback);

  // Orders placed in window
  final ordersRows = await guarded(() {
    var q = client.from('orders').select('id');
    if (from != null) q = q.gte('ordered_at', from.toIso8601String());
    return q;
  }(), const <dynamic>[]);
  final orders = ordersRows.length;

  // Delivered orders in window: one fetch gives both figures.
  //  • Total sales (GMV)      = sum of total_amount (all sales the company made)
  //  • Platform revenue        = what HotBite actually earns per order:
  //      subtotal×commission_rate + service/peak/priority/pickup fees.
  //    commission_rate is stored as a fraction (0.15 = 15%) and is populated on
  //    every order, so this is consistent across all history (unlike the newer
  //    platform_revenue_ledger, which only covers recent orders).
  final revRows = await guarded(() {
    var q = client
        .from('orders')
        .select('total_amount, subtotal, commission_rate, commission_amount, '
            'platform_service_fee, delivery_fee, peak_fee, priority_fee, pickup_fee')
        .eq('status', 'delivered');
    if (from != null) q = q.gte('delivered_at', from.toIso8601String());
    return q;
  }(), const <dynamic>[]);
  double totalSales = 0;
  double platformRevenue = 0;
  double d(Map m, String k) => (m[k] as num?)?.toDouble() ?? 0;
  for (final row in revRows) {
    final r = row as Map;
    totalSales += d(r, 'total_amount');
    // Prefer the recorded commission_amount; fall back to subtotal×rate.
    final commissionAmt = (r['commission_amount'] as num?)?.toDouble();
    final commission =
        commissionAmt ?? (d(r, 'subtotal') * d(r, 'commission_rate'));
    // Platform revenue = commission + service fee + delivery fee + surcharges.
    platformRevenue += commission +
        d(r, 'platform_service_fee') +
        d(r, 'delivery_fee') +
        d(r, 'peak_fee') +
        d(r, 'priority_fee') +
        d(r, 'pickup_fee');
  }

  // Membership fees (HotBite+) are sales the company made AND 100% platform
  // revenue — add to both. Windowed by when the membership was purchased.
  final memRows = await guarded(() {
    var q = client.from('customer_memberships').select('price_paid');
    if (from != null) q = q.gte('created_at', from.toIso8601String());
    return q;
  }(), const <dynamic>[]);
  double membershipRevenue = 0;
  for (final r in memRows) {
    membershipRevenue += ((r as Map)['price_paid'] as num?)?.toDouble() ?? 0;
  }
  totalSales += membershipRevenue;
  platformRevenue += membershipRevenue;

  final riderRows = await guarded(
      client.from('drivers').select('id').eq('is_online', true), const <dynamic>[]);
  final storeRows = await guarded(
      client.from('restaurants').select('id').eq('is_verified', true), const <dynamic>[]);

  return {
    'total_sales': totalSales,
    'platform_revenue': platformRevenue,
    // Back-compat: existing readers of 'revenue' get gross sales as before.
    'revenue': totalSales,
    'orders': orders,
    'online_riders': riderRows.length,
    'active_stores': storeRows.length,
  };
});

/// Unread admin notifications count + recent list.
final adminNotificationsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final uid = SupabaseConfig.client.auth.currentUser?.id;
  if (uid == null) return [];
  try {
    final rows = await SupabaseConfig.client
        .from('notifications').select().eq('user_id', uid)
        .order('created_at', ascending: false).limit(40);
    return (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  } catch (_) {
    return [];
  }
});

/// Headline counts for the admin overview AI-Staff card.
final aiStaffOverviewProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  Future<int> countSug(String col, String val) async {
    final r = await SupabaseConfig.client.from('ai_suggestions').select('id').eq(col, val).count();
    return r.count;
  }
  Future<int> countExec(String val) async {
    final r = await SupabaseConfig.client.from('ai_action_executions').select('id').eq('status', val).count();
    return r.count;
  }
  int roles = 24;
  try { roles = (await SupabaseConfig.client.from('ai_staff_roles').select('id').eq('status', 'active').count()).count; } catch (_) {}
  int awaiting = 0, working = 0, verified = 0;
  try { awaiting = await countSug('action_status', 'awaiting_approval'); } catch (_) {}
  try {
    working = await countExec('executing');
    working += (await SupabaseConfig.client.from('ai_suggestions').select('id').eq('action_status', 'executing').count()).count;
  } catch (_) {}
  try { verified = await countExec('completed'); } catch (_) {}
  return {'roles': roles, 'awaiting': awaiting, 'working': working, 'verified': verified};
});

/// Today's (or the latest available) briefing.
final aiTodayBriefingProvider = FutureProvider.autoDispose<AiBriefing?>((ref) async {
  final rows = await SupabaseConfig.client
      .from('ai_admin_briefings')
      .select()
      .order('briefing_date', ascending: false)
      .limit(1);
  final list = rows as List;
  return list.isEmpty ? null : AiBriefing.fromJson(Map<String, dynamic>.from(list.first as Map));
});

/// All 24 roles, ordered.
final aiRolesProvider = FutureProvider.autoDispose<List<AiRole>>((ref) async {
  final rows = await SupabaseConfig.client
      .from('ai_staff_roles')
      .select()
      .order('sort_order');
  return (rows as List).map((e) => AiRole.fromJson(Map<String, dynamic>.from(e as Map))).toList();
});

/// Latest report per role (for "last report time" + the role list).
final aiLatestReportsProvider = FutureProvider.autoDispose<Map<String, AiStaffReport>>((ref) async {
  final rows = await SupabaseConfig.client
      .from('ai_staff_reports')
      .select()
      .order('report_date', ascending: false)
      .limit(200);
  final map = <String, AiStaffReport>{};
  for (final r in (rows as List)) {
    final rep = AiStaffReport.fromJson(Map<String, dynamic>.from(r as Map));
    map.putIfAbsent(rep.roleId, () => rep); // first seen = newest (ordered desc)
  }
  return map;
});

/// All reports for one role (history), newest first.
final aiRoleReportsProvider =
    FutureProvider.autoDispose.family<List<AiStaffReport>, String>((ref, roleId) async {
  final rows = await SupabaseConfig.client
      .from('ai_staff_reports')
      .select()
      .eq('role_id', roleId)
      .order('report_date', ascending: false)
      .limit(60);
  return (rows as List).map((e) => AiStaffReport.fromJson(Map<String, dynamic>.from(e as Map))).toList();
});

/// Suggestions, optionally filtered by workflow status.
final aiSuggestionsProvider =
    FutureProvider.autoDispose.family<List<AiSuggestion>, String?>((ref, status) async {
  var q = SupabaseConfig.client.from('ai_suggestions').select();
  if (status != null && status.isNotEmpty) q = q.eq('status', status);
  final rows = await q.order('report_date', ascending: false).limit(300);
  return (rows as List).map((e) => AiSuggestion.fromJson(Map<String, dynamic>.from(e as Map))).toList();
});

/// Alerts, newest first.
final aiAlertsProvider = FutureProvider.autoDispose<List<AiAlert>>((ref) async {
  final rows = await SupabaseConfig.client
      .from('ai_urgent_alerts')
      .select()
      .order('created_at', ascending: false)
      .limit(200);
  return (rows as List).map((e) => AiAlert.fromJson(Map<String, dynamic>.from(e as Map))).toList();
});

/// Briefing history (for the History screen), newest first.
final aiBriefingHistoryProvider = FutureProvider.autoDispose<List<AiBriefing>>((ref) async {
  final rows = await SupabaseConfig.client
      .from('ai_admin_briefings')
      .select()
      .order('briefing_date', ascending: false)
      .limit(120);
  return (rows as List).map((e) => AiBriefing.fromJson(Map<String, dynamic>.from(e as Map))).toList();
});

/// Workflow actions. Each records who acted (auth.uid via currentUserId) and
/// when. These only move a suggestion/alert through its human review states —
/// they never perform the underlying operational change.
class AiStaffActions {
  AiStaffActions(this._ref);
  final Ref _ref;

  String? get _uid => _ref.read(currentUserIdProvider);

  /// Stage 8: admin decision that can trigger the approved-action engine.
  /// decision ∈ execute | investigate | assign_human | reject.
  /// Returns the engine result (status: completed / waiting_human / failed / …).
  Future<Map<String, dynamic>> decideAction(String id, String decision, {String? notes}) async {
    final res = await SupabaseConfig.client.rpc('ai_review_suggestion_action',
        params: {'p_suggestion_id': id, 'p_decision': decision, 'p_notes': notes});
    _ref.invalidate(aiSuggestionsProvider);
    _ref.invalidate(aiSuggestionWorkProvider(id));
    return res is Map ? Map<String, dynamic>.from(res) : {'status': res.toString()};
  }

  Future<void> reviewSuggestion(String id, String status, {String? notes}) async {
    await SupabaseConfig.client.from('ai_suggestions').update({
      'status': status,
      'reviewed_by': _uid,
      'reviewed_at': DateTime.now().toIso8601String(),
      if (notes != null) 'review_notes': notes,
    }).eq('id', id);
    _ref.invalidate(aiSuggestionsProvider);
  }

  Future<void> assignSuggestion(String id, {String? assignee}) async {
    await SupabaseConfig.client.from('ai_suggestions').update({
      'status': 'assigned',
      'assigned_to': assignee ?? _uid,
      'assigned_by': _uid,
      'assigned_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
    _ref.invalidate(aiSuggestionsProvider);
  }

  Future<void> setSuggestionStatus(String id, String status) async {
    final patch = <String, dynamic>{'status': status};
    if (status == 'completed') {
      patch['completed_by'] = _uid;
      patch['completed_at'] = DateTime.now().toIso8601String();
    }
    await SupabaseConfig.client.from('ai_suggestions').update(patch).eq('id', id);
    _ref.invalidate(aiSuggestionsProvider);
  }

  Future<void> acknowledgeAlert(String id) async {
    await SupabaseConfig.client.from('ai_urgent_alerts').update({
      'status': 'acknowledged',
      'acknowledged_by': _uid,
      'acknowledged_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
    _ref.invalidate(aiAlertsProvider);
  }

  Future<void> resolveAlert(String id) async {
    await SupabaseConfig.client.from('ai_urgent_alerts').update({
      'status': 'resolved',
      'resolved_by': _uid,
      'resolved_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
    _ref.invalidate(aiAlertsProvider);
  }
}

final aiStaffActionsProvider = Provider<AiStaffActions>((ref) => AiStaffActions(ref));
