import 'package:dio/dio.dart';

/// A failed backend call, read from ASP.NET ProblemDetails (`code`, `detail`)
/// or from request-shape validation (`errors`).
class ApiException implements Exception {
  const ApiException({required this.message, this.status, this.code});

  final int? status;
  final String? code;
  final String message;

  bool get isNetwork => status == null;

  factory ApiException.fromDio(DioException error) {
    final response = error.response;
    if (response == null) {
      return const ApiException(message: 'Cannot reach the server. Check your connection and try again.');
    }
    final data = response.data;
    String? code;
    String? detail;
    if (data is Map) {
      code = data['code'] as String?;
      detail = (data['detail'] ?? data['title']) as String?;
      final errors = data['errors'];
      if (detail == null && errors is Map && errors.isNotEmpty) {
        final first = errors.values.first;
        detail = first is List && first.isNotEmpty ? '${first.first}' : '$first';
      }
    }
    return ApiException(
      status: response.statusCode,
      code: code,
      message: detail ?? 'The request failed (${response.statusCode}).',
    );
  }

  @override
  String toString() => 'ApiException($status, $code): $message';
}
