import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
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
    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      // Proxy error pages (502/504 HTML) or empty bodies: the server was
      // reached, so don't report it as a connection failure.
      return {
        "statusCode": response.statusCode,
        "success": false,
        "message": "Server error (${response.statusCode}). Please try again.",
      };
    }

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

  static const String _timeoutMessage =
      "The server took too long to respond. Please try again.";

  // Only idempotent methods are safe to resend automatically. Most PUTs and
  // DELETEs here set an absolute value, but not all of them: order status
  // updates are state transitions, so callers pass `retry: false` for those.
  // POSTs (orders, cart adds, auth) must never be replayed.
  static int maxAttempts(String method, {bool retry = true}) =>
      retry && const {"GET", "PUT", "DELETE"}.contains(method) ? 3 : 1;

  static Future<http.Response> _send(
    String method,
    Future<http.Response> Function() request, {
    bool retry = true,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final int attempts = maxAttempts(method, retry: retry);
    for (int attempt = 0; attempt < attempts; attempt++) {
      try {
        final response = await request().timeout(timeout);
        // Expired / revoked session: drop local auth, but only if the request
        // carried the token that is still stored. A stale 401 from before a
        // fresh login (or a guest's empty "Bearer ") must not wipe the session.
        if (response.statusCode == 401) {
          final String sent = (response.request?.headers["Authorization"] ?? "")
              .replaceFirst("Bearer", "")
              .trim();
          if (sent.isNotEmpty && sent == await getToken()) {
            await clearAuth();
          }
        }
        return response;
      } catch (_) {
        if (attempt == attempts - 1) rethrow;
        await Future.delayed(
          Duration(milliseconds: 700 * (attempt + 1)),
        );
      }
    }
    throw Exception("Request failed");
  }

  // =========================================================
  // CLEAR SAVED AUTH (logout / 401)
  // =========================================================

  static Future<void> clearAuth() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    for (final key in const [
      "token",
      "userId",
      "userName",
      "userEmail",
      "userPhone",
      "userRole",
      "savedAddress",
    ]) {
      await prefs.remove(key);
    }
  }

  // =========================================================
  // BACKEND URL
  // =========================================================
  //
  // Adaptive and platform-aware backend URL:
  // - kIsWeb: http://localhost:5000
  // - Platform.isAndroid: http://10.0.2.2:5000
  // - Else (iOS, macOS, Linux, Windows): http://localhost:5000
  // Overridable via --dart-define=API_BASE_URL=...
  //
  static const String _envUrl = String.fromEnvironment("API_BASE_URL");

  // Release builds block cleartext HTTP, so the dev fallbacks below can't work
  // there. main.dart shows this message instead of the app when non-null.
  static String? get configError => kReleaseMode && _envUrl.isEmpty
      ? "Release builds need --dart-define=API_BASE_URL=https://your-server"
      : null;

  static String get baseUrl {
    if (_envUrl.isNotEmpty) {
      return _envUrl;
    }
    if (kIsWeb) {
      return "http://localhost:5000";
    }
    if (Platform.isAndroid) {
      return "http://10.0.2.2:5000";
    }
    return "http://localhost:5000";
  }

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
      final response = await _send("POST", () => http.post(
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
        "message": error is TimeoutException ? _timeoutMessage : "Unable to connect to server",
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
      final response = await _send("POST", () => http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": email, "password": password}),
      ));

      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": error is TimeoutException ? _timeoutMessage : "Unable to connect to server",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // GET ALL PRODUCTS
  // =========================================================

  static Future<Map<String, dynamic>> getProducts({int? page, int? limit}) async {
    final Uri url = Uri.parse("$baseUrl/api/products").replace(queryParameters: {
      if (page != null) "page": "$page",
      if (limit != null) "limit": "$limit",
    });

    try {
      final response = await _send("GET", () => http.get(url));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": error is TimeoutException ? _timeoutMessage : "Unable to connect to server",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // GET PRODUCT BY ID
  // =========================================================

  static Future<Map<String, dynamic>> getProductById(String id) async {
    final Uri url = Uri.parse("$baseUrl/api/products/${Uri.encodeComponent(id)}");

    try {
      final response = await _send("GET", () => http.get(url));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": error is TimeoutException ? _timeoutMessage : "Unable to connect to server",
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
      final response = await _send("POST", () => http.post(
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
        "message": error is TimeoutException ? _timeoutMessage : "Unable to connect to server",
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
      final response = await _send("GET", () => http.get(
        url,
        headers: {"Authorization": "Bearer $token"},
      ));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": error is TimeoutException ? _timeoutMessage : "Unable to connect to server",
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
    final Uri url = Uri.parse("$baseUrl/api/cart/${Uri.encodeComponent(productId)}");

    try {
      final response = await _send("PUT", () => http.put(
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
        "message": error is TimeoutException ? _timeoutMessage : "Unable to connect to server",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // REMOVE FROM CART
  // =========================================================

  static Future<Map<String, dynamic>> removeFromCart(String productId) async {
    final String token = await getToken();
    final Uri url = Uri.parse("$baseUrl/api/cart/${Uri.encodeComponent(productId)}");

    try {
      final response = await _send("DELETE", () => http.delete(
        url,
        headers: {"Authorization": "Bearer $token"},
      ));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": error is TimeoutException ? _timeoutMessage : "Unable to connect to server",
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
      final response = await _send("DELETE", () => http.delete(
        url,
        headers: {"Authorization": "Bearer $token"},
      ));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": error is TimeoutException ? _timeoutMessage : "Unable to connect to server",
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
      final response = await _send("POST", () => http.post(
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
        "message": error is TimeoutException ? _timeoutMessage : "Unable to connect to server",
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
      final response = await _send("GET", () => http.get(
        url,
        headers: {"Authorization": "Bearer $token"},
      ));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": error is TimeoutException ? _timeoutMessage : "Unable to connect to server",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // REMOVE FROM WISHLIST
  // =========================================================

  static Future<Map<String, dynamic>> removeFromWishlist(String productId) async {
    final String token = await getToken();
    final Uri url = Uri.parse("$baseUrl/api/wishlist/${Uri.encodeComponent(productId)}");

    try {
      final response = await _send("DELETE", () => http.delete(
        url,
        headers: {"Authorization": "Bearer $token"},
      ));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": error is TimeoutException ? _timeoutMessage : "Unable to connect to server",
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
      final response = await _send("POST", () => http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": email}),
      ));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": error is TimeoutException ? _timeoutMessage : "Unable to connect to server",
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
      final response = await _send("POST", () => http.post(
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
        "message": error is TimeoutException ? _timeoutMessage : "Unable to connect to server",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // GET PROFILE
  // =========================================================

  // `quick`: one attempt with a short timeout (startup session check).
  static Future<Map<String, dynamic>> getProfile({bool quick = false}) async {
    final String token = await getToken();
    final Uri url = Uri.parse("$baseUrl/api/auth/profile");

    try {
      final response = await _send(
        "GET",
        () => http.get(url, headers: {"Authorization": "Bearer $token"}),
        retry: !quick,
        timeout: Duration(seconds: quick ? 6 : 20),
      );
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": error is TimeoutException ? _timeoutMessage : "Unable to connect to server",
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
      final response = await _send("PUT", () => http.put(
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
        "message": error is TimeoutException ? _timeoutMessage : "Unable to connect to server",
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
    String? couponCode,
    double? discountAmount,
    String? idempotencyKey,
    bool fromCart = true,
  }) async {
    final String token = await getToken();
    final Uri url = Uri.parse("$baseUrl/api/orders");

    try {
      final response = await _send("POST", () => http.post(
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
          if (couponCode != null && couponCode.isNotEmpty) "couponCode": couponCode,
          if (discountAmount != null && discountAmount > 0) "discountAmount": discountAmount,
          "idempotencyKey": ?idempotencyKey,
          "fromCart": fromCart,
        }),
      ));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": error is TimeoutException ? _timeoutMessage : "Unable to connect to server",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // GET PRODUCT REVIEWS
  // =========================================================

  static Future<Map<String, dynamic>> getProductReviews(String productId) async {
    final Uri url = Uri.parse("$baseUrl/api/products/${Uri.encodeComponent(productId)}/reviews");

    try {
      final response = await _send("GET", () => http.get(url));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": error is TimeoutException ? _timeoutMessage : "Unable to connect to server",
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
    final Uri url = Uri.parse("$baseUrl/api/products/${Uri.encodeComponent(productId)}/reviews");

    try {
      final response = await _send("POST", () => http.post(
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
        "message": error is TimeoutException ? _timeoutMessage : "Unable to connect to server",
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
      final response = await _send("GET", () => http.get(
        url,
        headers: {"Authorization": "Bearer $token"},
      ));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": error is TimeoutException ? _timeoutMessage : "Unable to connect to server",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // GET ORDER TRACKING DATA (MONGODB)
  // =========================================================

  static Future<Map<String, dynamic>> getOrderTracking(String orderId) async {
    final String token = await getToken();
    final Uri url = Uri.parse(
      "$baseUrl/api/orders/${Uri.encodeComponent(orderId.trim())}/tracking",
    );

    try {
      final response = await _send("GET", () => http.get(
        url,
        headers: {"Authorization": "Bearer $token"},
      ));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": error is TimeoutException ? _timeoutMessage : "Unable to fetch order tracking",
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
    final Uri url = Uri.parse(
      "$baseUrl/api/orders/${Uri.encodeComponent(orderId.trim())}/status",
    );

    try {
      final response = await _send("PUT", () => http.put(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({"status": status}),
      ), retry: false);
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": error is TimeoutException ? _timeoutMessage : "Unable to update order status",
        "error": error.toString(),
      };
    }
  }

  // =========================================================
  // OFFERS & COUPONS MODULE (Module 12)
  // =========================================================

  // GET ALL ACTIVE OFFERS
  static Future<Map<String, dynamic>> getOffers() async {
    final Uri url = Uri.parse("$baseUrl/api/offers");

    try {
      final response = await _send("GET", () => http.get(url));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": error is TimeoutException ? _timeoutMessage : "Unable to fetch promotional offers",
        "error": error.toString(),
      };
    }
  }

  // GET DISCOUNTED PRODUCTS
  static Future<Map<String, dynamic>> getDiscountedProducts() async {
    final Uri url = Uri.parse("$baseUrl/api/offers/discounted-products");

    try {
      final response = await _send("GET", () => http.get(url));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": error is TimeoutException ? _timeoutMessage : "Unable to fetch discounted products",
        "error": error.toString(),
      };
    }
  }

  // VALIDATE COUPON CODE
  static Future<Map<String, dynamic>> validateCoupon({
    required String code,
    required double subtotal,
    String? category,
    List<Map<String, dynamic>>? items,
  }) async {
    final String token = await getToken();
    final Uri url = Uri.parse("$baseUrl/api/offers/validate-coupon");

    try {
      final response = await _send("POST", () => http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          if (token.isNotEmpty) "Authorization": "Bearer $token",
        },
        body: jsonEncode({
          "couponCode": code.trim().toUpperCase(),
          "subtotal": subtotal,
          if (category != null && category.isNotEmpty) "category": category,
          "items": ?items,
        }),
      ));
      return await _handleResponse(response);
    } catch (error) {
      return {
        "statusCode": 0,
        "success": false,
        "message": error is TimeoutException ? _timeoutMessage : "Unable to validate coupon code",
        "error": error.toString(),
      };
    }
  }
}