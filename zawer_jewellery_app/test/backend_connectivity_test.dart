// Dart → Node.js → MongoDB Atlas connectivity test
//
// Verifies the Flutter app can fetch data from the backend which reads
// from MongoDB Atlas.  Run with:
//   dart test test/backend_connectivity_test.dart
//
// Requires the backend to be running on localhost:5000.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

const String baseUrl = 'http://localhost:5000';

void main() {
  group('Backend → Atlas connectivity', () {
    test('GET /api/products returns products from Atlas', () async {
      final response = await http
          .get(Uri.parse('$baseUrl/api/products'))
          .timeout(const Duration(seconds: 15));

      expect(response.statusCode, equals(200));

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      expect(body['success'], isTrue, reason: 'API should return success: true');
      expect(body['products'], isA<List>(), reason: 'Should contain a products list');
      expect((body['products'] as List).isNotEmpty, isTrue,
          reason: 'Products list should not be empty (Atlas has data)');
      expect(body['total'], isA<int>());

      // Validate product shape
      final product = (body['products'] as List).first as Map<String, dynamic>;
      expect(product, contains('_id'));
      expect(product, contains('category'));
      expect(product, contains('description'));

      print('✅ Products endpoint: ${body['total']} products fetched from Atlas');
      print('   First product: ${product['id'] ?? product['_id']} — ${product['category']}');
    });

    test('GET /api/offers returns offers from Atlas', () async {
      final response = await http
          .get(Uri.parse('$baseUrl/api/offers'))
          .timeout(const Duration(seconds: 15));

      expect(response.statusCode, equals(200));

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      expect(body['success'], isTrue);

      final offers = body['offers'] as List?;
      expect(offers, isA<List>(), reason: 'Should contain an offers list');

      print('✅ Offers endpoint: ${offers?.length ?? 0} offers fetched from Atlas');
    });

    test('POST /api/auth/login rejects invalid credentials (proves Atlas auth lookup works)', () async {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': 'nonexistent_test_user_${DateTime.now().millisecondsSinceEpoch}@example.com',
              'password': 'wrongpassword123456',
            }),
          )
          .timeout(const Duration(seconds: 15));

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      // A proper rejection (not a connection error) proves the backend queried Atlas
      // and didn't find the user — the DB round-trip worked.
      expect(response.statusCode, isNot(equals(500)),
          reason: 'Should not be a server error — Atlas should be reachable');
      expect(body['success'], isFalse,
          reason: 'Login with fake creds should fail');

      print('✅ Auth endpoint: login correctly rejected (Atlas user lookup works)');
    });

    test('GET /api/products/:id returns a single product from Atlas', () async {
      // First get the list to grab a real ID
      final listResponse = await http
          .get(Uri.parse('$baseUrl/api/products'))
          .timeout(const Duration(seconds: 15));
      final listBody = jsonDecode(listResponse.body) as Map<String, dynamic>;
      final products = listBody['products'] as List;
      expect(products.isNotEmpty, isTrue, reason: 'Need at least one product');

      // Backend uses the custom 'id' field (e.g. prod_ring_01), not MongoDB _id
      final productId = (products.first as Map<String, dynamic>)['id'] as String;

      // Now fetch by ID
      final response = await http
          .get(Uri.parse('$baseUrl/api/products/$productId'))
          .timeout(const Duration(seconds: 15));

      expect(response.statusCode, equals(200));

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      expect(body['success'], isTrue);
      expect(body['product'], isA<Map>());
      expect((body['product'] as Map)['id'], equals(productId));

      print('✅ Single product endpoint: fetched product $productId from Atlas');
    });

    test('GET /api/products with pagination works', () async {
      final response = await http
          .get(Uri.parse('$baseUrl/api/products?page=1&limit=5'))
          .timeout(const Duration(seconds: 15));

      expect(response.statusCode, equals(200));

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      expect(body['success'], isTrue);
      expect((body['products'] as List).length, lessThanOrEqualTo(5));
      expect(body['page'], equals(1));

      print('✅ Pagination: page 1, limit 5 → ${(body['products'] as List).length} products');
    });
  });
}
