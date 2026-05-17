import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/feedback_model.dart';
import '../../config/app_constants.dart';
import '../../utils/app_logger.dart';

class FeedbackService {
  final SupabaseClient _client;
  FeedbackService(this._client);

  // Submit feedback
  Future<AppFeedback?> submitFeedback({
    required String userId,
    required String type,
    required String message,
    int? rating,
    String? screenshotUrl,
  }) async {
    try {
      final response = await _client
          .from('app_feedback')
          .insert({
            'user_id': userId,
            'type': type,
            'message': message,
            'rating': ?rating,
            'app_version': AppConstants.appVersion,
            'screenshot_url': ?screenshotUrl,
          })
          .select()
          .single();
      return AppFeedback.fromJson(response);
    } catch (e) {
      AppLogger.error('Error submitting feedback: $e');
      return null;
    }
  }

  // Get user's feedback
  Future<List<AppFeedback>> getUserFeedback(String userId) async {
    try {
      final response = await _client
          .from('app_feedback')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return (response as List).map((e) => AppFeedback.fromJson(e)).toList();
    } catch (e) {
      AppLogger.error('Error fetching feedback: $e');
      return [];
    }
  }

  // Get all feedback (admin)
  Future<List<AppFeedback>> getAllFeedback({String? typeFilter}) async {
    try {
      var query = _client.from('app_feedback').select();
      if (typeFilter != null) {
        query = query.eq('type', typeFilter);
      }
      final response = await query.order('created_at', ascending: false);
      return (response as List).map((e) => AppFeedback.fromJson(e)).toList();
    } catch (e) {
      AppLogger.error('Error fetching all feedback: $e');
      return [];
    }
  }

  // Respond to feedback (admin)
  Future<bool> respondToFeedback({
    required String feedbackId,
    required String response,
    required String status,
  }) async {
    try {
      await _client
          .from('app_feedback')
          .update({'admin_response': response, 'status': status})
          .eq('id', feedbackId);
      return true;
    } catch (e) {
      AppLogger.error('Error responding to feedback: $e');
      return false;
    }
  }
}
