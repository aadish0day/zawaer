import 'package:flutter/material.dart';
import '../utils/text_styles.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../utils/colors.dart';
import 'order_tracking_screen.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final nameController = TextEditingController();

  final phoneController = TextEditingController();

  final addressController = TextEditingController();

  String paymentMethod = "Cash on Delivery";

  bool isLoading = true;

  bool isPlacingOrder = false;

  List<Map<String, dynamic>> cartItems = [];

  @override
  void initState() {
    super.initState();

    loadCheckoutData();
  }

  @override
  void dispose() {
    nameController.dispose();

    phoneController.dispose();

    addressController.dispose();

    super.dispose();
  }

  // =====================================================
  // LOAD CART + USER PREFILL
  // =====================================================

  Future<void> loadCheckoutData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    nameController.text = prefs.getString("userName") ?? "";

    phoneController.text = prefs.getString("userPhone") ?? "";

    addressController.text = prefs.getString("savedAddress") ?? "";

    final cartResult = await ApiService.getCart();

    if (!mounted) {
      return;
    }

    if (cartResult["success"] == true) {
      final dynamic rawCart = cartResult["cart"];
      final List items = (rawCart?["items"] ?? []) as List;

      final productResult = await ApiService.getProducts();

      final Map<String, dynamic> productMap = {};

      if (productResult["success"] == true) {
        final List productList = (productResult["products"] ?? []) as List;

        for (final p in productList) {
          final map = p as Map<String, dynamic>;

          productMap[map["id"]?.toString() ?? ""] = map;
        }
      }

      final List<Map<String, dynamic>> joined = [];

      for (final item in items) {
        final productId = item["productId"]?.toString() ?? "";

        final product = productMap[productId];

        joined.add({
          "productId": productId,
          "quantity": item["quantity"] ?? 1,
          "name": product?["name"]?.toString() ?? "Unknown Product",
          "price": (product?["price"] as num?) ?? 0,
          "image":
              (product?["images"] as List?) is List &&
                  ((product?["images"] as List).isNotEmpty)
              ? (product!["images"] as List).first.toString()
              : "",
        });
      }

      setState(() {
        cartItems = joined;
        isLoading = false;
      });
    } else {
      setState(() {
        isLoading = false;
      });
    }
  }

  int get itemCount {
    int count = 0;

    for (final item in cartItems) {
      count += item["quantity"] as int;
    }

    return count;
  }

  double get subtotal {
    double sum = 0;

    for (final item in cartItems) {
      sum += (item["price"] as num) * (item["quantity"] as num);
    }

    return sum;
  }

  // =====================================================
  // PLACE ORDER
  // =====================================================

  Future<void> placeOrder() async {
    if (cartItems.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Your cart is empty")));
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

    final result = await ApiService.placeOrder(
      customerName: nameController.text.trim(),
      phone: phoneController.text.trim(),
      address: addressController.text.trim(),
      paymentMethod: paymentMethod,
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

    if (!mounted) {
      return;
    }

    if (result["success"] == true) {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      await prefs.setString("savedAddress", addressController.text.trim());

      await ApiService.clearCart();

      final String placedOrderId = result["order"]?["_id"]?.toString() ?? "";

      if (!mounted) {
        return;
      }

      setState(() {
        isPlacingOrder = false;
        cartItems = [];
      });

      showDialog(
        context: context,

        barrierDismissible: false,

        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),

          title: const Icon(Icons.check_circle, color: Colors.green, size: 70),

          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Order Placed Successfully!",
                textAlign: TextAlign.center,
                style: AppFonts.cinzel(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),

              const SizedBox(height: 10),

              Text(
                "Thank you for shopping with ZAWER Jewellery. Your handcrafted piece is registered under high-security transit.",
                textAlign: TextAlign.center,
                style: AppFonts.poppins(fontSize: 13),
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(context); // close dialog
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                OrderTrackingScreen(orderId: placedOrderId),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.location_searching_rounded,
                        size: 18,
                      ),
                      label: Text(
                        "TRACK ORDER LIVE",
                        style: AppFonts.cinzel(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.pop(context);
                    },
                    child: Text(
                      "Continue Shopping",
                      style: AppFonts.poppins(fontWeight: FontWeight.w600),
                    ),
                  ),
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
          content: Text(
            result["message"]?.toString() ?? "Could not place order",
          ),
        ),
      );
    }
  }

  // =====================================================
  // BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,

      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,

        elevation: 0,

        centerTitle: true,

        title: Text(
          "Checkout",

          style: AppFonts.cinzel(
            color: Theme.of(context).colorScheme.onSurface,

            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Text(
                    "Customer Details",

                    style: AppFonts.cinzel(
                      fontSize: 24,

                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 20),

                  TextField(
                    controller: nameController,

                    decoration: InputDecoration(
                      labelText: "Full Name",

                      prefixIcon: const Icon(Icons.person),

                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  TextField(
                    controller: phoneController,

                    keyboardType: TextInputType.phone,

                    decoration: InputDecoration(
                      labelText: "Phone Number",

                      prefixIcon: const Icon(Icons.phone),

                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  TextField(
                    controller: addressController,

                    maxLines: 3,

                    decoration: InputDecoration(
                      labelText: "Delivery Address",

                      prefixIcon: const Icon(Icons.location_on),

                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),

                  Text(
                    "Payment Method",

                    style: AppFonts.cinzel(
                      fontSize: 22,

                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 15),

                  RadioGroup<String>(
                    groupValue: paymentMethod,
                    onChanged: (value) {
                      setState(() {
                        paymentMethod = value ?? "Cash on Delivery";
                      });
                    },
                    child: Column(
                      children: [
                        RadioListTile<String>(
                          value: "UPI",
                          activeColor: Theme.of(context).colorScheme.primary,
                          title: const Text("UPI Payment"),
                          secondary: const Icon(Icons.qr_code),
                        ),

                        RadioListTile<String>(
                          value: "Credit/Debit Card",
                          activeColor: Theme.of(context).colorScheme.primary,
                          title: const Text("Credit / Debit Card"),
                          secondary: const Icon(Icons.credit_card),
                        ),

                        RadioListTile<String>(
                          value: "Cash on Delivery",
                          activeColor: Theme.of(context).colorScheme.primary,
                          title: const Text("Cash on Delivery"),
                          secondary: const Icon(Icons.payments),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .08),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        buildRow("Items", itemCount.toString()),

                        buildRow("Subtotal", "₹${subtotal.toStringAsFixed(0)}"),

                        buildRow("Delivery", "FREE"),

                        const Divider(),

                        buildRow(
                          "Grand Total",
                          "₹${subtotal.toStringAsFixed(0)}",
                          isBold: true,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 35),

                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      onPressed: isPlacingOrder ? null : placeOrder,
                      child: isPlacingOrder
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              "PLACE ORDER",
                              style: AppFonts.cinzel(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }

  Widget buildRow(String title, String value, {bool isBold = false}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: AppFonts.poppins(
                fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),

          Text(
            value,
            style: AppFonts.poppins(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: isBold
                  ? AppColors.brand(context)
                  : theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
