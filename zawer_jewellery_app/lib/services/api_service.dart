import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // =========================================================
  // AUTO-CONNECT
  // =========================================================
  //
  // Retries failed requests up to 3 times with a short delay,
  // so the app connects automatically as soon as the backend
  // is up.
  // =========================================================

  static Future<Map<String, dynamic>> _handleResponse(
    http.Response response,
  ) async {
    final dynamic decoded = jsonDecode(response.body);

    if (decoded is Map<String, dynamic>) {
      return {
        "statusCode": response.statusCode,
        ...decoded,
      };
    }

    return {
      "statusCode": response.statusCode,
      "success": false,
      "message": "Invalid server response",
    };
  }

  static Future<http.Response> _send(
    Future<http.Response> Function() request,
  ) async {
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        return await request();
      } catch (_) {
        if (attempt == 2) rethrow;
        await Future.delayed(
          Duration(milliseconds: 700 * (attempt + 1)),
        );
      }
    }
    throw Exception("Request failed");
  }

  // =========================================================
  // BACKEND URL
  // =========================================================
  //
  // Default: 10.0.2.2 -> host PC's localhost from the Android
  // emulator. For physical devices: pass --dart-define=API_BASE_URL=http://192.168.x.x:5000
  //
  static const String baseUrl = String.fromEnvironment(
    "API_BASE_URL",
    defaultValue: "http://10.0.2.2:5000",
  );

  // =========================================================
  // GET SAVED TOKEN
  // =========================================================

  static Future<String> getToken() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString("token") ?? "";
  }

  // =========================================================
  // REGISTER USER
  // =========================================================

  static Future<Map<String, dynamic>> registerUser({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    final Uri url = Uri.parse("$baseUrl/api/auth/register");

    try {
      final response = await _send(() => http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "name": name,
          "email": email,
          "phone": phone,
          "password": password,
        }),
      ));

      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": "Unable to connect to server",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // LOGIN USER
  // =========================================================

  static Future<Map<String, dynamic>> loginUser({
    required String email,
    required String password,
  }) async {
    final Uri url = Uri.parse("$baseUrl/api/auth/login");

    try {
      final response = await _send(() => http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": email, "password": password}),
      ));

      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": "Unable to connect to server",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // GET ALL PRODUCTS
  // =========================================================

  static Future<Map<String, dynamic>> getProducts() async {
    final Uri url = Uri.parse("$baseUrl/api/products");

    try {
      final response = await _send(() => http.get(url));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": "Unable to connect to server",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // GET PRODUCT BY ID
  // =========================================================

  static Future<Map<String, dynamic>> getProductById(String id) async {
    final Uri url = Uri.parse("$baseUrl/api/products/$id");

    try {
      final response = await _send(() => http.get(url));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": "Unable to connect to server",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // SEARCH PRODUCTS
  // =========================================================

  static Future<Map<String, dynamic>> searchProducts(String search) async {
    final String encodedSearch = Uri.encodeComponent(search);
    final Uri url = Uri.parse("$baseUrl/api/products/search?search=$encodedSearch");

    try {
      final response = await _send(() => http.get(url));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": "Unable to connect to server",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // ADD TO CART
  // =========================================================

  static Future<Map<String, dynamic>> addToCart({
    required String productId,
    int quantity = 1,
  }) async {
    final String token = await getToken();
    final Uri url = Uri.parse("$baseUrl/api/cart");

    try {
      final response = await _send(() => http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({"productId": productId, "quantity": quantity}),
      ));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": "Unable to connect to server",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // GET CART
  // =========================================================

  static Future<Map<String, dynamic>> getCart() async {
    final String token = await getToken();
    final Uri url = Uri.parse("$baseUrl/api/cart");

    try {
      final response = await _send(() => http.get(
        url,
        headers: {"Authorization": "Bearer $token"},
      ));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": "Unable to connect to server",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // UPDATE CART QUANTITY
  // =========================================================

  static Future<Map<String, dynamic>> updateCartQuantity({
    required String productId,
    required int quantity,
  }) async {
    final String token = await getToken();
    final Uri url = Uri.parse("$baseUrl/api/cart/$productId");

    try {
      final response = await _send(() => http.put(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({"quantity": quantity}),
      ));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": "Unable to connect to server",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // REMOVE FROM CART
  // =========================================================

  static Future<Map<String, dynamic>> removeFromCart(String productId) async {
    final String token = await getToken();
    final Uri url = Uri.parse("$baseUrl/api/cart/$productId");

    try {
      final response = await _send(() => http.delete(
        url,
        headers: {"Authorization": "Bearer $token"},
      ));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": "Unable to connect to server",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // CLEAR CART
  // =========================================================

  static Future<Map<String, dynamic>> clearCart() async {
    final String token = await getToken();
    final Uri url = Uri.parse("$baseUrl/api/cart");

    try {
      final response = await _send(() => http.delete(
        url,
        headers: {"Authorization": "Bearer $token"},
      ));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": "Unable to connect to server",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // ADD TO WISHLIST
  // =========================================================

  static Future<Map<String, dynamic>> addToWishlist(String productId) async {
    final String token = await getToken();
    final Uri url = Uri.parse("$baseUrl/api/wishlist");

    try {
      final response = await _send(() => http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({"productId": productId}),
      ));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": "Unable to connect to server",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // GET WISHLIST
  // =========================================================

  static Future<Map<String, dynamic>> getWishlist() async {
    final String token = await getToken();
    final Uri url = Uri.parse("$baseUrl/api/wishlist");

    try {
      final response = await _send(() => http.get(
        url,
        headers: {"Authorization": "Bearer $token"},
      ));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": "Unable to connect to server",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // REMOVE FROM WISHLIST
  // =========================================================

  static Future<Map<String, dynamic>> removeFromWishlist(String productId) async {
    final String token = await getToken();
    final Uri url = Uri.parse("$baseUrl/api/wishlist/$productId");

    try {
      final response = await _send(() => http.delete(
        url,
        headers: {"Authorization": "Bearer $token"},
      ));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": "Unable to connect to server",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // FORGOT PASSWORD
  // =========================================================

  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    final Uri url = Uri.parse("$baseUrl/api/auth/forgot-password");

    try {
      final response = await _send(() => http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": email}),
      ));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": "Unable to connect to server",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // RESET PASSWORD
  // =========================================================

  static Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    final Uri url = Uri.parse("$baseUrl/api/auth/reset-password");

    try {
      final response = await _send(() => http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "email": email,
          "otp": otp,
          "newPassword": newPassword,
        }),
      ));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": "Unable to connect to server",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // GET PROFILE
  // =========================================================

  static Future<Map<String, dynamic>> getProfile() async {
    final String token = await getToken();
    final Uri url = Uri.parse("$baseUrl/api/auth/profile");

    try {
      final response = await _send(() => http.get(
        url,
        headers: {"Authorization": "Bearer $token"},
      ));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": "Unable to connect to server",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // UPDATE PROFILE
  // =========================================================

  static Future<Map<String, dynamic>> updateProfile({
    required String name,
    required String phone,
  }) async {
    final String token = await getToken();
    final Uri url = Uri.parse("$baseUrl/api/auth/profile");

    try {
      final response = await _send(() => http.put(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({"name": name, "phone": phone}),
      ));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": "Unable to connect to server",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // PLACE ORDER
  // =========================================================

  static Future<Map<String, dynamic>> placeOrder({
    required String customerName,
    required String phone,
    required String address,
    required String paymentMethod,
    required List<Map<String, dynamic>> items,
  }) async {
    final String token = await getToken();
    final Uri url = Uri.parse("$baseUrl/api/orders");

    try {
      final response = await _send(() => http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({
          "customerName": customerName,
          "phone": phone,
          "address": address,
          "paymentMethod": paymentMethod,
          "items": items,
        }),
      ));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": "Unable to connect to server",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // GET PRODUCT REVIEWS
  // =========================================================

  static Future<Map<String, dynamic>> getProductReviews(String productId) async {
    final Uri url = Uri.parse("$baseUrl/api/products/$productId/reviews");

    try {
      final response = await _send(() => http.get(url));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": "Unable to connect to server",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // ADD PRODUCT REVIEW
  // =========================================================

  static Future<Map<String, dynamic>> addProductReview({
    required String productId,
    required int rating,
    required String comment,
  }) async {
    final String token = await getToken();
    final Uri url = Uri.parse("$baseUrl/api/products/$productId/reviews");

    try {
      final response = await _send(() => http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({"rating": rating, "comment": comment}),
      ));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": "Unable to connect to server",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // GET MY ORDERS
  // =========================================================

  static Future<Map<String, dynamic>> getOrders() async {
    final String token = await getToken();
    final Uri url = Uri.parse("$baseUrl/api/orders");

    try {
      final response = await _send(() => http.get(
        url,
        headers: {"Authorization": "Bearer $token"},
      ));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": "Unable to connect to server",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // GET ORDER TRACKING DATA (MONGODB)
  // =========================================================

  static Future<Map<String, dynamic>> getOrderTracking(String orderId) async {
    final String token = await getToken();
    final Uri url = Uri.parse("$baseUrl/api/orders/$orderId/tracking");

    try {
      final response = await _send(() => http.get(
        url,
        headers: {"Authorization": "Bearer $token"},
      ));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": "Unable to fetch order tracking",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // GET ORDER BY ID
  // =========================================================

  static Future<Map<String, dynamic>> getOrderById(String orderId) async {
    final String token = await getToken();
    final Uri url = Uri.parse("$baseUrl/api/orders/$orderId");

    try {
      final response = await _send(() => http.get(
        url,
        headers: {"Authorization": "Bearer $token"},
      ));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": "Unable to fetch order details",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // UPDATE / ADVANCE ORDER STATUS
  // =========================================================

  static Future<Map<String, dynamic>> updateOrderStatus({
    required String orderId,
    required String status,
  }) async {
    final String token = await getToken();
    final Uri url = Uri.parse("$baseUrl/api/orders/$orderId/status");

    try {
      final response = await _send(() => http.put(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({"status": status}),
      ));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": "Unable to update order status",
        "error": error.toString(),
      };
    }
  }
}