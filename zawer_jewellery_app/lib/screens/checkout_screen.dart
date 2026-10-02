import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../utils/colors.dart';
import '../utils/text_styles.dart';
import '../utils/validators.dart';
import 'order_tracking_screen.dart';
import 'offers_screen.dart';

// Delivery field rules, mirroring POST /api/orders validation.

String? validateCheckoutName(String? value) {
  final v = value?.trim() ?? "";
  if (v.isEmpty) return "Please enter the recipient's name";
  if (codePointLength(v) > maxNameLength) return "Name must be $maxNameLength characters or fewer";
  return null;
}

String? validateCheckoutPhone(String? value) {
  final v = value?.trim() ?? "";
  if (v.isEmpty) return "Please enter a phone number";
  if (v.length > maxPhoneLength || !isValidPhone(v)) {
    return "Enter a valid phone number (digits, spaces, +, - or brackets)";
  }
  return null;
}

String? validateCheckoutAddress(String? value) {
  final v = value?.trim() ?? "";
  if (v.isEmpty) return "Please enter a delivery address";
  if (codePointLength(v) > maxAddressLength) {
    return "Address must be $maxAddressLength characters or fewer";
  }
  return null;
}

// A persisted Buy Now key is reused only for the same items and quantities
// (see buyNowKeySignature) and only within 30 minutes; anything else starts a
// fresh attempt.
const Duration buyNowKeyMaxAge = Duration(minutes: 30);

// Items and quantities only (used for both cart and Buy Now): a retry after a
// lost response keeps the key even if details changed, so the server either
// replays that order (same details) or answers 409 "already placed" - never a
// second order.
String buyNowKeySignature(List<Map<String, dynamic>> items) =>
    items.map((item) => "${item["productId"]}x${item["quantity"]}").join(",");

// Items, quantities and prices: any change means an applied coupon's discount
// must be re-validated.
String pricedItemsSignature(List<Map<String, dynamic>> items) => items
    .map((item) => "${item["productId"]}x${item["quantity"]}@${item["price"]}")
    .join(",");

String? pendingBuyNowKey({
  required String signature,
  required String? storedKey,
  required String? storedSignature,
  required int? storedAt,
  required DateTime now,
}) {
  if (storedKey == null || storedSignature != signature || storedAt == null) {
    return null;
  }
  final age = now.difference(DateTime.fromMillisecondsSinceEpoch(storedAt));
  if (age.isNegative || age > buyNowKeyMaxAge) return null;
  return storedKey;
}

class CheckoutScreen extends StatefulWidget {
  final String? initialCouponCode;

  // Buy Now: check out exactly these items (same shape as loaded cart items)
  // instead of the cart. The cart is left untouched.
  final List<Map<String, dynamic>>? buyNowItems;

  const CheckoutScreen({
    super.key,
    this.initialCouponCode,
    this.buyNowItems,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final addressController = TextEditingController();
  final couponController = TextEditingController();

  String paymentMethod = "Cash on Delivery";
  bool isLoading = true;
  bool isPlacingOrder = false;
  bool isValidatingCoupon = false;

  String? appliedCouponCode;
  double appliedDiscount = 0.0;
  String couponSuccessMessage = "";
  String couponErrorMessage = "";

  List<Map<String, dynamic>> cartItems = [];
  String? loadError;

  // One key per checkout attempt; reused across retries / double taps so the
  // server never creates a duplicate order. Reset when any order input changes.
  String? idempotencyKey;
  String idempotencySignature = "";

  // Buy Now has no server cart to show a timed-out order went through, so its
  // pending key survives leaving and re-entering checkout.
  static const String pendingKeyPref = "buyNowPendingOrderKey";
  static const String pendingSigPref = "buyNowPendingOrderSig";
  static const String pendingAtPref = "buyNowPendingOrderAt";

  final deliveryFormKey = GlobalKey<FormState>();

  static Future<void> clearPendingBuyNow(SharedPreferences prefs) async {
    await prefs.remove(pendingKeyPref);
    await prefs.remove(pendingSigPref);
    await prefs.remove(pendingAtPref);
  }

  static String generateIdempotencyKey() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, "0"),
    ).join();
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialCouponCode != null && widget.initialCouponCode!.trim().isNotEmpty) {
      couponController.text = widget.initialCouponCode!.trim().toUpperCase();
    }
    loadCheckoutData();
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    addressController.dispose();
    couponController.dispose();
    super.dispose();
  }

  // =====================================================
  // LOAD CART + USER PREFILL
  // =====================================================
  Future<void> loadCheckoutData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    // Prefill only empty fields so a reload keeps the user's edits.
    if (nameController.text.isEmpty) {
      nameController.text = prefs.getString("userName") ?? "";
    }
    if (phoneController.text.isEmpty) {
      phoneController.text = prefs.getString("userPhone") ?? "";
    }
    if (addressController.text.isEmpty) {
      addressController.text = prefs.getString("savedAddress") ?? "";
    }

    if (!mounted) return;

    final bool firstLoad = isLoading;
    final String previousItems = pricedItemsSignature(cartItems);

    if (widget.buyNowItems != null) {
      final items = await refreshBuyNowPrices(widget.buyNowItems!);
      if (!mounted) return;
      setState(() {
        cartItems = items;
        isLoading = false;
      });
      recheckCoupon(firstLoad, previousItems);
      return;
    }

    final cartResult = await ApiService.getCart();

    if (!mounted) return;

    if (cartResult["success"] == true) {
      final dynamic rawCart = cartResult["cart"];
      final List items = (rawCart?["items"] ?? []) as List;

      final List<Map<String, dynamic>> joined = [];

      for (final item in items) {
        // Backend populates items[].product; null means the product was deleted.
        final product = item["product"];
        if (product is! Map<String, dynamic>) continue;
        final List images = product["images"] is List ? product["images"] as List : const [];

        joined.add({
          "productId": item["productId"]?.toString() ?? product["id"]?.toString() ?? "",
          "quantity": (item["quantity"] as num?)?.toInt() ?? 1,
          "name": product["name"]?.toString() ?? "",
          "price": (product["price"] as num?)?.toDouble() ?? 0.0,
          "category": product["category"]?.toString() ?? "Jewellery",
          "image": images.isNotEmpty
              ? images.first.toString()
              : "assets/images/ring.png",
        });
      }

      setState(() {
        cartItems = joined;
        loadError = null;
        isLoading = false;
      });

      recheckCoupon(firstLoad, previousItems);
    } else {
      setState(() {
        loadError = cartResult["message"]?.toString() ?? "Unable to load your cart";
        isLoading = false;
      });
    }
  }

  // First load applies the coupon passed in; later reloads re-validate an
  // applied coupon whenever item prices or quantities changed.
  void recheckCoupon(bool firstLoad, String previousItems) {
    if (cartItems.isEmpty) return;
    final bool initialCoupon = widget.initialCouponCode?.trim().isNotEmpty ?? false;
    if (firstLoad
        ? initialCoupon
        : appliedCouponCode != null &&
            pricedItemsSignature(cartItems) != previousItems) {
      applyCoupon(appliedCouponCode);
    }
  }

  // The passed Buy Now price may be stale (the product screen can sit open for
  // a long time); show the current price. On failure keep the passed price.
  Future<List<Map<String, dynamic>>> refreshBuyNowPrices(
    List<Map<String, dynamic>> items,
  ) async {
    return Future.wait(items.map((item) async {
      final copy = Map<String, dynamic>.from(item);
      final result = await ApiService.getProductById(item["productId"].toString());
      final price = result["success"] == true ? (result["product"]?["price"]) : null;
      if (price is num) copy["price"] = price.toDouble();
      return copy;
    }));
  }

  List<Map<String, dynamic>> get couponItems {
    return cartItems.map((item) {
      return {"productId": item["productId"], "quantity": item["quantity"]};
    }).toList();
  }

  int get itemCount {
    int count = 0;
    for (final item in cartItems) {
      count += (item["quantity"] as num?)?.toInt() ?? 1;
    }
    return count;
  }

  double get subtotal {
    double sum = 0;
    for (final item in cartItems) {
      final price = (item["price"] as num?)?.toDouble() ?? 0.0;
      final quantity = (item["quantity"] as num?)?.toInt() ?? 1;
      sum += price * quantity;
    }
    return sum;
  }

  double get grandTotal {
    return (subtotal - appliedDiscount).clamp(0.0, double.infinity);
  }

  // =====================================================
  // APPLY COUPON CODE
  // =====================================================
  // [codeOverride] re-validates an already applied coupon (e.g. after a cart
  // reload) regardless of what is in the text field.
  // Bumped per check (and on remove); only the latest result is applied.
  int _couponRequestSeq = 0;

  Future<void> applyCoupon([String? codeOverride]) async {
    final code = (codeOverride ?? couponController.text).trim().toUpperCase();
    if (code.isEmpty) return;
    final int seq = ++_couponRequestSeq;

    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();

    setState(() {
      isValidatingCoupon = true;
      couponErrorMessage = "";
      couponSuccessMessage = "";
    });

    final result = await ApiService.validateCoupon(
      code: code,
      subtotal: subtotal,
      items: couponItems,
    );

    if (!mounted || seq != _couponRequestSeq) return;

    setState(() {
      isValidatingCoupon = false;
    });

    if (result["success"] == true) {
      final couponData = result["coupon"];
      final double discount = (couponData?["discountAmount"] as num?)?.toDouble() ?? 0.0;

      setState(() {
        appliedCouponCode = code;
        appliedDiscount = discount;
        couponSuccessMessage = result["message"]?.toString() ?? "Privilege coupon applied!";
        couponErrorMessage = "";
      });
      HapticFeedback.heavyImpact();
    } else {
      setState(() {
        appliedCouponCode = null;
        appliedDiscount = 0.0;
        couponErrorMessage = result["message"]?.toString() ?? "Invalid coupon code";
        couponSuccessMessage = "";
      });
    }
  }

  void removeCoupon() {
    HapticFeedback.lightImpact();
    _couponRequestSeq++;
    setState(() {
      isValidatingCoupon = false;
      appliedCouponCode = null;
      appliedDiscount = 0.0;
      couponController.clear();
      couponSuccessMessage = "";
      couponErrorMessage = "";
    });
  }

  // =====================================================
  // PLACE ORDER
  // =====================================================
  Future<void> placeOrder() async {
    if (isPlacingOrder) return;

    if (cartItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Your cart is empty")),
      );
      return;
    }

    if (!(deliveryFormKey.currentState?.validate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please check your delivery details")),
      );
      return;
    }

    setState(() {
      isPlacingOrder = true;
    });

    // Captured up front: the success path below may run after this screen
    // is gone, when the controllers are already disposed.
    final bool isBuyNow = widget.buyNowItems != null;
    final String name = nameController.text.trim();
    final String phone = phoneController.text.trim();
    final String address = addressController.text.trim();
    final List<Map<String, dynamic>> orderItems = cartItems.map((item) {
      return {
        "productId": item["productId"],
        "name": item["name"],
        "image": item["image"],
        "price": item["price"],
        "quantity": item["quantity"],
      };
    }).toList();
    // The key only changes with the items/quantities. If a timed-out attempt actually
    // created the order, a retry with edited details reuses the key and the server
    // answers 409 ("already placed") instead of creating a second order.
    final String keySignature = buyNowKeySignature(cartItems);

    final SharedPreferences prefs = await SharedPreferences.getInstance();

    Future<void> newKey() async {
      idempotencyKey = generateIdempotencyKey();
      if (isBuyNow) {
        await prefs.setString(pendingKeyPref, idempotencyKey!);
        await prefs.setString(pendingSigPref, keySignature);
        await prefs.setInt(pendingAtPref, DateTime.now().millisecondsSinceEpoch);
      }
    }

    if (idempotencyKey == null || idempotencySignature != keySignature) {
      final String? pendingKey = isBuyNow
          ? pendingBuyNowKey(
              signature: keySignature,
              storedKey: prefs.getString(pendingKeyPref),
              storedSignature: prefs.getString(pendingSigPref),
              storedAt: prefs.getInt(pendingAtPref),
              now: DateTime.now(),
            )
          : null;
      if (pendingKey != null) {
        idempotencyKey = pendingKey;
      } else {
        await newKey(); // overwrites any stale persisted Buy Now key
      }
      idempotencySignature = keySignature;
    }

    Future<Map<String, dynamic>> send() => ApiService.placeOrder(
          fromCart: !isBuyNow,
          customerName: name,
          phone: phone,
          address: address,
          paymentMethod: paymentMethod,
          couponCode: appliedCouponCode,
          discountAmount: appliedDiscount,
          idempotencyKey: idempotencyKey,
          items: orderItems,
        );

    Map<String, dynamic> result = await send();

    // 409 means an order already exists for this key (placed over 24h ago).
    // Resending with a new key would duplicate it, so stop and point to Orders.
    final bool alreadyPlaced = result["statusCode"] == 409 && result["idempotencyConflict"] == true;
    if (alreadyPlaced) {
      idempotencyKey = null;
      if (isBuyNow) await clearPendingBuyNow(prefs);
      result = {
        ...result,
        "message": "This order was already placed earlier. Please check My Orders before ordering again.",
      };
    }

    if (result["success"] == true) {
      // No context needed: runs even if the screen was popped mid-request,
      // so a placed Buy Now order never leaves a reusable key behind.
      idempotencyKey = null;
      if (isBuyNow) await clearPendingBuyNow(prefs);
      await prefs.setString("savedAddress", address);
    }

    if (!mounted) return;

    // The earlier attempt went through and the server already took those items out
    // of the cart; reload so the next tap can't re-order stale items.
    if (alreadyPlaced && !isBuyNow) loadCheckoutData();

    if (result["success"] == true) {
      // The server removes the ordered items from the cart itself.
      final dynamic order = result["order"];
      final String placedOrderId = order?["_id"]?.toString() ?? "";
      final double paidDiscount = (order?["discountAmount"] as num?)?.toDouble() ?? 0.0;
      final double? paidTotal = (order?["totalAmount"] as num?)?.toDouble();

      setState(() {
        isPlacingOrder = false;
        cartItems = [];
      });

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Icon(Icons.check_circle_rounded, color: AppColors.gold, size: 64),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Order Placed Successfully!",
                textAlign: TextAlign.center,
                style: AppFonts.cinzel(fontWeight: FontWeight.bold, fontSize: 19),
              ),
              const SizedBox(height: 10),
              Text(
                paidDiscount > 0
                    ? "Thank you for acquiring with ZAWER. Your ₹${paidDiscount.toStringAsFixed(0)} privilege discount has been applied."
                    : "Thank you for acquiring with ZAWER. Your piece is registered under 100% insured armored transit.",
                textAlign: TextAlign.center,
                style: AppFonts.poppins(fontSize: 12.5, color: Colors.grey),
              ),
              if (paidTotal != null) ...[
                const SizedBox(height: 8),
                Text(
                  "Total: ₹${paidTotal.toStringAsFixed(0)}",
                  textAlign: TextAlign.center,
                  style: AppFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
          actions: [
            Column(
              children: [
                if (placedOrderId.isNotEmpty) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OrderTrackingScreen(orderId: placedOrderId),
                          ),
                        );
                      },
                      icon: const Icon(Icons.local_shipping_outlined, size: 18),
                      label: Text(
                        "TRACK ARMORED TRANSIT",
                        style: AppFonts.cinzel(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    } else {
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        "/bottomNav",
                        (route) => false,
                      );
                    }
                  },
                  child: Text("Return to Catalog", style: AppFonts.poppins(color: Colors.grey)),
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      // The server flags every coupon rejection from POST /api/orders.
      final bool couponRejected = result["statusCode"] == 400 &&
          appliedCouponCode != null &&
          result["couponError"] == true;

      setState(() {
        isPlacingOrder = false;
        if (couponRejected) {
          appliedCouponCode = null;
          appliedDiscount = 0.0;
          couponController.clear();
          couponSuccessMessage = "";
          couponErrorMessage =
              "${result["message"]} The coupon was removed; review your total and place the order again.";
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade900,
          content: Text(
            result["message"]?.toString() ?? "Failed to place order",
            style: AppFonts.poppins(color: Colors.white),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Leaving mid-request would skip the success handling below.
    return PopScope(
      canPop: !isPlacingOrder,
      child: Scaffold(
      backgroundColor: isDark ? const Color(0xFF0C0C0E) : const Color(0xFFFAF8F5),
      appBar: buildMaisonAppBar(isDark),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded, color: AppColors.gold, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      loadError!,
                      textAlign: TextAlign.center,
                      style: AppFonts.poppins(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        setState(() {
                          isLoading = true;
                          loadError = null;
                        });
                        loadCheckoutData();
                      },
                      child: const Text("RETRY"),
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Customer Delivery Details Card
                  buildSectionHeader("DELIVERY SPECIFICATIONS", isDark),
                  const SizedBox(height: 8),
                  buildDeliveryCard(isDark),
                  const SizedBox(height: 20),

                  // 2. Maison Privilege Coupon Voucher Section
                  buildSectionHeader("MAISON PRIVILEGE VOUCHERS", isDark),
                  const SizedBox(height: 8),
                  buildCouponSection(isDark),
                  const SizedBox(height: 20),

                  // 3. Payment Method Section
                  buildSectionHeader("PAYMENT PROTOCOL", isDark),
                  const SizedBox(height: 8),
                  buildPaymentCard(isDark),
                  const SizedBox(height: 20),

                  // 4. Valuation & Invoicing Breakdown Card
                  buildSectionHeader("VALUATION BREAKDOWN", isDark),
                  const SizedBox(height: 8),
                  buildValuationBreakdownCard(isDark),
                  const SizedBox(height: 24),

                  // 5. Place Order Button
                  buildPlaceOrderButton(isDark),
                  const SizedBox(height: 36),
                ],
              ),
            ),
      ),
    );
  }

  PreferredSizeWidget buildMaisonAppBar(bool isDark) {
    return AppBar(
      backgroundColor: isDark ? const Color(0xFF0C0C0E) : const Color(0xFFFAF8F5),
      elevation: 0,
      centerTitle: true,
      leading: Navigator.canPop(context)
          ? Padding(
              padding: const EdgeInsets.all(8.0),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.maybePop(context),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.gold.withValues(alpha: 0.3), width: 0.8),
                    color: isDark ? const Color(0xFF18181D) : Colors.white,
                  ),
                  child: const Icon(Icons.arrow_back_ios_new, size: 16),
                ),
              ),
            )
          : null,
      title: Column(
        children: [
          Text(
            "ZAWER VAULT",
            style: AppFonts.cinzel(
              fontSize: 10,
              letterSpacing: 3.5,
              fontWeight: FontWeight.w600,
              color: AppColors.gold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            "Vault Checkout",
            style: AppFonts.cinzel(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: AppFonts.poppins(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
          color: AppColors.gold,
        ),
      ),
    );
  }

  Widget buildDeliveryCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141418) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Form(
        key: deliveryFormKey,
        child: Column(
        children: [
          TextFormField(
            controller: nameController,
            maxLength: maxNameLength,
            validator: validateCheckoutName,
            style: AppFonts.poppins(fontSize: 13.5),
            decoration: InputDecoration(
              labelText: "Recipient Full Name",
              prefixIcon: const Icon(Icons.person_outline, color: AppColors.gold),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            maxLength: maxPhoneLength,
            validator: validateCheckoutPhone,
            style: AppFonts.poppins(fontSize: 13.5),
            decoration: InputDecoration(
              labelText: "Verified Phone Number",
              prefixIcon: const Icon(Icons.phone_outlined, color: AppColors.gold),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: addressController,
            maxLines: 2,
            maxLength: maxAddressLength,
            validator: validateCheckoutAddress,
            style: AppFonts.poppins(fontSize: 13.5),
            decoration: InputDecoration(
              labelText: "Vault Delivery Destination",
              prefixIcon: const Icon(Icons.location_on_outlined, color: AppColors.gold),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget buildCouponSection(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141418) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: appliedCouponCode != null
              ? AppColors.gold
              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
          width: appliedCouponCode != null ? 1.0 : 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: couponController,
                  readOnly: appliedCouponCode != null,
                  textCapitalization: TextCapitalization.characters,
                  style: AppFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: "Enter Privilege Code (e.g. ROYAL20)",
                    hintStyle: AppFonts.poppins(fontSize: 12, color: Colors.grey),
                    prefixIcon: const Icon(Icons.card_giftcard_rounded, color: AppColors.gold, size: 20),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (appliedCouponCode == null)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(80, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: isValidatingCoupon ? null : applyCoupon,
                  child: isValidatingCoupon
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          "APPLY",
                          style: AppFonts.poppins(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                )
              else
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    minimumSize: const Size(80, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: isValidatingCoupon ? null : removeCoupon,
                  child: const Text("REMOVE"),
                ),
            ],
          ),
          if (couponSuccessMessage.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32), size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    couponSuccessMessage,
                    style: AppFonts.poppins(
                      fontSize: 11.5,
                      color: const Color(0xFF2E7D32),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (couponErrorMessage.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    couponErrorMessage,
                    style: AppFonts.poppins(fontSize: 11.5, color: Colors.redAccent),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          InkWell(
            // Not while an order is in flight: the result dialog must open over Checkout.
            onTap: isPlacingOrder ? null : () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OffersScreen()),
              );
              // The cart may have changed on pushed screens; reload it.
              if (mounted) loadCheckoutData();
            },
            child: Row(
              children: [
                const Icon(Icons.discount_outlined, size: 14, color: AppColors.gold),
                const SizedBox(width: 6),
                Text(
                  "View All Active Maison Privilege Codes →",
                  style: AppFonts.poppins(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildPaymentCard(bool isDark) {
    final paymentOptions = [
      {
        "id": "Cash on Delivery",
        "title": "Cash / Pay on Armored Delivery",
        "subtitle": "Hand-delivery protocol with ID verification",
        "icon": Icons.payments_outlined,
      },
      {
        "id": "UPI",
        "title": "Instant UPI Transfer",
        "subtitle": "Google Pay, PhonePe, Paytm, BHIM",
        "icon": Icons.qr_code_rounded,
      },
      {
        "id": "Credit/Debit Card",
        "title": "Private Bank Wire / Amex Card",
        "subtitle": "Encrypted 256-bit vault gateway",
        "icon": Icons.credit_card_outlined,
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141418) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        children: paymentOptions.map((opt) {
          final isSelected = paymentMethod == opt["id"];
          return InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                paymentMethod = opt["id"] as String;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? AppColors.gold.withValues(alpha: 0.15)
                          : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                    ),
                    child: Icon(opt["icon"] as IconData, size: 18, color: AppColors.gold),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          opt["title"] as String,
                          style: AppFonts.cinzel(fontSize: 13.5, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          opt["subtitle"] as String,
                          style: AppFonts.poppins(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? AppColors.gold : Colors.grey.shade600,
                        width: 1.5,
                      ),
                    ),
                    child: isSelected
                        ? Center(
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.gold,
                              ),
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget buildValuationBreakdownCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141418) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        children: [
          buildBreakdownRow("Vault Pieces", "$itemCount Pieces"),
          buildBreakdownRow("Gross Subtotal", "₹${subtotal.toStringAsFixed(0)}"),
          if (appliedDiscount > 0)
            buildBreakdownRow(
              "Privilege Discount ($appliedCouponCode)",
              "- ₹${appliedDiscount.toStringAsFixed(0)}",
              color: const Color(0xFF2E7D32),
            ),
          buildBreakdownRow("Armored Escort Transit", "COMPLIMENTARY", color: const Color(0xFF2E7D32)),
          buildBreakdownRow("BIS 916 & Insurance", "INCLUDED", color: const Color(0xFF2E7D32)),
          const Divider(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Net Valuation Payable",
                style: AppFonts.cinzel(fontSize: 14.5, fontWeight: FontWeight.bold),
              ),
              Text(
                "₹${grandTotal.toStringAsFixed(0)}",
                style: AppFonts.cinzel(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.brand(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildBreakdownRow(String title, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: AppFonts.poppins(fontSize: 12, color: Colors.grey)),
          Text(
            value,
            style: AppFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color ?? Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildPlaceOrderButton(bool isDark) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: isPlacingOrder || isValidatingCoupon ? null : placeOrder,
        child: isPlacingOrder
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline_rounded, size: 16, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    "AUTHORIZE VAULT ORDER (₹${grandTotal.toStringAsFixed(0)})",
                    style: AppFonts.cinzel(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
