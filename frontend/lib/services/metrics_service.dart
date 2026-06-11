import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/metrics_model.dart';

class MetricsService {
  static const String _endpoint = '/api/metrics';

  Future<MetricsModel> fetchMetrics() async {
    final uri = Uri.parse(_endpoint);
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return MetricsModel.fromJson(json);
    }
    throw Exception('HTTP ${response.statusCode}');
  }
}
