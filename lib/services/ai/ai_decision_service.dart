import '../../config/supabase_config.dart';

/// Client for the admin "AI Decision Room". All authorization is enforced
/// server-side (RLS + RPC + edge function); this is a thin wrapper. No AI keys
/// ever touch the client.
class AiDecisionService {
  final _c = SupabaseConfig.client;

  Future<Map<String, dynamic>> usage() async {
    final r = await _c.rpc('ai_decision_usage');
    return (r as Map?)?.cast<String, dynamic>() ?? {};
  }

  Future<List<Map<String, dynamic>>> list({String? status, String? search}) async {
    var q = _c.from('ai_decisions').select(
        'id,title,question,category,status,final_choice,created_at,completed_at,include_metrics');
    if (status != null && status.isNotEmpty) q = q.eq('status', status);
    if (search != null && search.trim().isNotEmpty) {
      q = q.ilike('title', '%${search.trim()}%');
    }
    final r = await q.order('created_at', ascending: false).limit(100);
    return (r as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>?> get(String id) async {
    final r = await _c.from('ai_decisions').select('*').eq('id', id).maybeSingle();
    return r;
  }

  Future<List<Map<String, dynamic>>> stages(String decisionId) async {
    final r = await _c
        .from('ai_decision_stages')
        .select('stage,provider,status,seq,output,error,tokens_in,tokens_out')
        .eq('decision_id', decisionId)
        .order('seq');
    return (r as List).cast<Map<String, dynamic>>();
  }

  Future<({bool ok, String? id, String? reason})> create({
    required String title,
    required String question,
    String? context,
    List<String> options = const [],
    String? goals,
    String? budget,
    String? constraints,
    String category = 'other',
    bool includeMetrics = false,
    String synthModel = 'openai',
  }) async {
    final r = await _c.rpc('ai_decision_create', params: {
      'p_title': title,
      'p_question': question,
      'p_context': context,
      'p_options': options,
      'p_goals': goals,
      'p_budget': budget,
      'p_constraints': constraints,
      'p_category': category,
      'p_include_metrics': includeMetrics,
      'p_synth_model': synthModel,
    });
    final m = (r as Map?)?.cast<String, dynamic>() ?? {};
    return (ok: m['ok'] == true, id: m['decision_id'] as String?, reason: m['reason'] as String?);
  }

  /// Runs the next workflow stage. Returns the progress payload. Call in a loop
  /// until done==true or stage_status=='failed'.
  Future<Map<String, dynamic>> advance(String decisionId) async {
    final res = await _c.functions
        .invoke('ai-decision-advance', body: {'decision_id': decisionId});
    return (res.data as Map?)?.cast<String, dynamic>() ?? {};
  }

  Future<bool> cancel(String decisionId) async {
    final r = await _c.rpc('ai_decision_cancel', params: {'p_id': decisionId});
    return (r as Map?)?['ok'] == true;
  }

  Future<bool> retryStage(String decisionId, String stage) async {
    final r = await _c
        .rpc('ai_decision_retry_stage', params: {'p_id': decisionId, 'p_stage': stage});
    return (r as Map?)?['ok'] == true;
  }

  Future<bool> saveFinal(String decisionId, String choice, String notes) async {
    final r = await _c.rpc('ai_decision_save_final',
        params: {'p_id': decisionId, 'p_choice': choice, 'p_notes': notes});
    return (r as Map?)?['ok'] == true;
  }

  Future<Map<String, dynamic>> metricsPreview({int days = 30}) async {
    final r = await _c.rpc('ai_decision_metrics_preview', params: {'p_days': days});
    return (r as Map?)?.cast<String, dynamic>() ?? {};
  }
}
