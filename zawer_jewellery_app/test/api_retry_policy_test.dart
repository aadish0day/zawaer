import 'package:flutter_test/flutter_test.dart';
import 'package:zawer_jewellery_app/services/api_service.dart';

void main() {
  test('only idempotent methods are retried; POST is sent once', () {
    expect(ApiService.maxAttempts("GET"), 3);
    expect(ApiService.maxAttempts("PUT"), 3);
    expect(ApiService.maxAttempts("DELETE"), 3);
    expect(ApiService.maxAttempts("POST"), 1);
  });
}
