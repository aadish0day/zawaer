import 'package:flutter_test/flutter_test.dart';
import 'package:zawer_jewellery_app/services/api_service.dart';

void main() {
  test('only idempotent methods are retried; POST is sent once', () {
    expect(ApiService.maxAttempts("GET"), 3);
    expect(ApiService.maxAttempts("PUT"), 3);
    expect(ApiService.maxAttempts("DELETE"), 3);
    expect(ApiService.maxAttempts("POST"), 1);
  });

  test('retry: false sends once regardless of method (order status PUT)', () {
    expect(ApiService.maxAttempts("PUT", retry: false), 1);
    expect(ApiService.maxAttempts("GET", retry: false), 1);
  });

  test('debug/test builds have no config error and a usable baseUrl', () {
    expect(ApiService.configError, isNull);
    expect(ApiService.baseUrl, startsWith("http"));
  });
}
