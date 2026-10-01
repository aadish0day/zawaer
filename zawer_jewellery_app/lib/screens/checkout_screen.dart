import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../utils/colors.dart';
import '../utils/text_styles.dart';
import 'order_tracking_screen.dart';
import 'offers_screen.dart';

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
  // server never creates a duplicate order. Reset when the items change.
  String? idempotencyKey;
  String idempotencyItems = "";

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

    if (widget.buyNowItems != null) {
      setState(() {
        cartItems = widget.buyNowItems!;
        isLoading = false;
      });
      if (widget.initialCouponCode != null &&
          widget.initialCouponCode!.trim().isNotEmpty) {
        applyCoupon();
      }
      return;
    }

    final bool firstLoad = isLoading;
    final String previousItems = itemsSignature(cartItems);

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

      final bool itemsChanged = itemsSignature(joined) != previousItems;
      if (joined.isNotEmpty &&
          ((firstLoad &&
                  widget.initialCouponCode != null &&
                  widget.initialCouponCode!.trim().isNotEmpty) ||
              (!firstLoad && itemsChanged && appliedCouponCode != null))) {
        applyCoupon();
      }
    } else {
      setState(() {
        loadError = cartResult["message"]?.toString() ?? "Unable to load your cart";
        isLoading = false;
      });
    }
  }

  String itemsSignature(List<Map<String, dynamic>> items) {
    return items.map((item) => "${item["productId"]}x${item["quantity"]}").join(",");
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
  Future<void> applyCoupon() async {
    final code = couponController.text.trim().toUpperCase();
    if (code.isEmpty) return;

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

    if (!mounted) return;

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
    setState(() {
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

    if (nameController.text.trim().isEmpty ||
        phoneController.text.trim().isEmpty ||
        addressController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill in all delivery details")),
      );
      return;
    }

    setState(() {
      isPlacingOrder = true;
    });

    final String currentItems = itemsSignature(cartItems);
    if (idempotencyKey == null || idempotencyItems != currentItems) {
      final random = Random.secure();
      idempotencyKey = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, "0"),
      ).join();
      idempotencyItems = currentItems;
    }

    final result = await ApiService.placeOrder(
      customerName: nameController.text.trim(),
      phone: phoneController.text.trim(),
      address: addressController.text.trim(),
      paymentMethod: paymentMethod,
      couponCode: appliedCouponCode,
      discountAmount: appliedDiscount,
      idempotencyKey: idempotencyKey,
      items: cartItems.map((item) {
        return {
          "productId": item["productId"],
          "name": item["name"],
          "image": item["image"],
          "price": item["price"],
          "quantity": item["quantity"],
        };
      }).toList(),
    );

    if (!mounted) return;

    if (result["success"] == true) {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString("savedAddress", addressController.text.trim());
      // The server removes the ordered items from the cart itself.
      idempotencyKey = null;

      final String placedOrderId = result["order"]?["_id"]?.toString() ?? "";

      if (!mounted) return;

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
                appliedDiscount > 0
                    ? "Thank you for acquiring with ZAWER. Your ₹${appliedDiscount.toStringAsFixed(0)} privilege discount has been applied."
                    : "Thank you for acquiring with ZAWER. Your piece is registered under 100% insured armored transit.",
                textAlign: TextAlign.center,
                style: AppFonts.poppins(fontSize: 12.5, color: Colors.grey),
              ),
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
      setState(() {
        isPlacingOrder = false;
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

    return Scaffold(
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
                onTap: () {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  }
                },
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
      child: Column(
        children: [
          TextField(
            controller: nameController,
            style: AppFonts.poppins(fontSize: 13.5),
            decoration: InputDecoration(
              labelText: "Recipient Full Name",
              prefixIcon: const Icon(Icons.person_outline, color: AppColors.gold),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            style: AppFonts.poppins(fontSize: 13.5),
            decoration: InputDecoration(
              labelText: "Verified Phone Number",
              prefixIcon: const Icon(Icons.phone_outlined, color: AppColors.gold),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: addressController,
            maxLines: 2,
            style: AppFonts.poppins(fontSize: 13.5),
            decoration: InputDecoration(
              labelText: "Vault Delivery Destination",
              prefixIcon: const Icon(Icons.location_on_outlined, color: AppColors.gold),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
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
                  onPressed: removeCoupon,
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
            onTap: () async {
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
        onPressed: isPlacingOrder ? null : placeOrder,
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
