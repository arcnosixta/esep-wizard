import 'dart:convert';

import 'package:http/http.dart' as http;

import 'payment_service.dart';
import 'supabase_service.dart';

class XPaymentService {
  XPaymentService._();

  static String get _baseUrl => PaymentService.apiBaseUrl;

  static Map<String, String> _headers() {
    final token = SupabaseService.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Создаёт сессию оплаты через /api/xpayment/create и возвращает
  /// checkout_url (реальная ссылка Kaspi через XPayment либо демо-страница).
  static Future<String> createCheckout({
    required String applicationId,
    required int amount,
  }) async {
    final resp = await http.post(
      Uri.parse('$_baseUrl/api/xpayment/create'),
      headers: _headers(),
      body: jsonEncode({'application_id': applicationId, 'amount': amount}),
    );
    if (resp.statusCode != 200) {
      throw Exception('XPayment: ${resp.body}');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final url = data['checkout_url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception('XPayment: пустой checkout_url');
    }
    return url;
  }

  /// Просит сервер сверить статусы XPayment-платежей заявки с провайдером.
  /// Возвращает true, если после синхронизации есть подтверждённый платёж.
  static Future<bool> syncStatus(String applicationId) async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/api/xpayment/status'),
        headers: _headers(),
        body: jsonEncode({'application_id': applicationId}),
      );
      if (resp.statusCode != 200) return false;
      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      return (data['confirmed'] as num? ?? 0) > 0;
    } catch (_) {
      return false;
    }
  }
}
