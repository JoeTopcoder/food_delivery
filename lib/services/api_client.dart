import 'package:dio/dio.dart';
import '../utils/app_logger.dart';

class ApiClient {
  late final Dio _dio;

  ApiClient() {
    _dio = Dio();
    _setupInterceptors();
  }

  void _setupInterceptors() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          AppLogger.debug('API Request: ${options.method} ${options.path}');
          return handler.next(options);
        },
        onResponse: (response, handler) {
          AppLogger.debug('API Response: ${response.statusCode}');
          return handler.next(response);
        },
        onError: (error, handler) {
          AppLogger.error('API Error: ${error.message}');
          return handler.next(error);
        },
      ),
    );
  }

  // GET request
  Future<dynamic> get(
    String url, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.get(url, queryParameters: queryParameters);
      return response.data;
    } catch (e) {
      AppLogger.error('GET request error: $e');
      rethrow;
    }
  }

  // POST request
  Future<dynamic> post(
    String url, {
    required dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.post(
        url,
        data: data,
        queryParameters: queryParameters,
      );
      return response.data;
    } catch (e) {
      AppLogger.error('POST request error: $e');
      rethrow;
    }
  }

  // PUT request
  Future<dynamic> put(
    String url, {
    required dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.put(
        url,
        data: data,
        queryParameters: queryParameters,
      );
      return response.data;
    } catch (e) {
      AppLogger.error('PUT request error: $e');
      rethrow;
    }
  }

  // DELETE request
  Future<void> delete(
    String url, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      await _dio.delete(url, queryParameters: queryParameters);
    } catch (e) {
      AppLogger.error('DELETE request error: $e');
      rethrow;
    }
  }

  // PATCH request
  Future<dynamic> patch(
    String url, {
    required dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.patch(
        url,
        data: data,
        queryParameters: queryParameters,
      );
      return response.data;
    } catch (e) {
      AppLogger.error('PATCH request error: $e');
      rethrow;
    }
  }

  // Download file
  Future<String> downloadFile({
    required String url,
    required String savePath,
  }) async {
    try {
      await _dio.download(url, savePath);
      return savePath;
    } catch (e) {
      AppLogger.error('Download error: $e');
      rethrow;
    }
  }

  // Set authorization header
  void setAuthToken(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  // Remove authorization header
  void removeAuthToken() {
    _dio.options.headers.remove('Authorization');
  }

  // Get Dio instance for custom usage
  Dio get dio => _dio;
}
