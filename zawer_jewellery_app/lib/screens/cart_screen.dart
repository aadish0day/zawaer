import 'package:flutter/material.dart';
import '../utils/text_styles.dart';

import '../models/product_model.dart';
import '../services/api_service.dart';

import '../utils/colors.dart';
import 'checkout_screen.dart';
import 'login_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => CartScreenState();
}

class CartScreenState extends State<CartScreen> {

  bool isLoading = true;

  bool isGuest = false;

  String errorMessage = "";

  List<Map<String, dynamic>> cartItems = [];

  @override
  void initState() {
    super.initState();

    loadCart();
  }

  // =====================================================
  // LOAD CART FROM BACKEND
  // =====================================================

  Future<void> loadCart() async {

    setState(() {
      isLoading = true;
      errorMessage = "";
    });

    try {

      final cartResult = await ApiService.getCart();

      if (!mounted) {
        return;
      }

      if (cartResult["statusCode"] == 401) {
        setState(() {
          isGuest = true;
          isLoading = false;
          cartItems = [];
        });
        return;
      }

      if (cartResult["success"] != true) {
        setState(() {
          isLoading = false;
          errorMessage =
              cartResult["message"]?.toString() ??
                  "Could not load cart";
        });
        return;
      }

      final dynamic rawCart = cartResult["cart"];
      final List items = (rawCart?["items"] ?? []) as List;

      final productResult =
      await ApiService.getProducts();

      final Map<String, Product> productMap = {};

      if (productResult["success"] == true) {
        final List productList =
        (productResult["products"] ?? []) as List;

        for (final p in productList) {
          final product = Product.fromJson(
            p as Map<String, dynamic>,
          );

          productMap[product.id] = product;
        }
      }

      final List<Map<String, dynamic>> joined = [];

      for (final item in items) {
        final productId =
            item["productId"]?.toString() ?? "";

        final product = productMap[productId];

        joined.add({
          "productId": productId,
          "quantity": item["quantity"] ?? 1,
          "name": product?.name ?? "Unknown Product",
          "price": product?.price ?? 0,
          "image": (product?.images
              .isNotEmpty ?? false)
              ? product!.images.first
              : "",
        });
      }

      if (!mounted) {
        return;
      }

      setState(() {
        cartItems = joined;
        isGuest = false;
        isLoading = false;
      });

    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        isLoading = false;
        errorMessage =
            "Unable to connect to server";
      });
    }
  }

  // =====================================================
  // UPDATE QUANTITY ON BACKEND
  // =====================================================

  Future<void> changeQuantity(
      int index,
      int newQuantity,
      ) async {

    final item = cartItems[index];

    if (newQuantity < 1) {
      return;
    }

    setState(() {
      cartItems[index]["quantity"] = newQuantity;
    });

    final result =
    await ApiService.updateCartQuantity(
      productId: item["productId"].toString(),
      quantity: newQuantity,
    );

    if (result["success"] != true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result["message"]?.toString() ??
                "Could not update quantity",
          ),
        ),
      );

      loadCart();
    }
  }

  // =====================================================
  // REMOVE ITEM ON BACKEND
  // =====================================================

  Future<void> removeItem(int index) async {

    final item = cartItems[index];

    final result = await ApiService.removeFromCart(
      item["productId"].toString(),
    );

    if (!mounted) {
      return;
    }

    if (result["success"] == true) {
      setState(() {
        cartItems.removeAt(index);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Item removed from cart"),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result["message"]?.toString() ??
                "Could not remove item",
          ),
        ),
      );
    }
  }

  double get total {
    double sum = 0;

    for (final item in cartItems) {
      sum += (item["price"] as num) *
          (item["quantity"] as num);
    }

    return sum;
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
          "My Cart",
          style: AppFonts.cinzel(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      body: isLoading
          ? const Center(
        child: CircularProgressIndicator(),
      )
          : isGuest
          ? buildGuestView()
          : errorMessage.isNotEmpty
          ? buildErrorView()
          : cartItems.isEmpty
          ? buildEmptyView()
          : buildCartView(),
    );
  }

  Widget buildGuestView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [

          Icon(
            Icons.lock_outline,
            size: 60,
            color:
            Theme.of(context).colorScheme.onSurfaceVariant,
          ),

          const SizedBox(height: 15),

          Text(
            "Login to view your cart",
            style: AppFonts.cinzel(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 20),

          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const LoginScreen(),
                ),
              );
            },
            child: Text(
              "LOGIN",
              style: AppFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

        ],
      ),
    );
  }

  Widget buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [

          const Icon(
            Icons.wifi_off,
            size: 60,
            color: Colors.grey,
          ),

          const SizedBox(height: 15),

          Text(
            errorMessage,
            textAlign: TextAlign.center,
            style: AppFonts.poppins(),
          ),

          const SizedBox(height: 20),

          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
            onPressed: loadCart,
            child: Text(
              "RETRY",
              style: AppFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

        ],
      ),
    );
  }

  Widget buildEmptyView() {
    return Center(
      child: Text(
        "Your Cart is Empty",
        style: AppFonts.cinzel(
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget buildCartView() {
    return Column(
      children: [

        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: cartItems.length,
            itemBuilder: (context, index) {
              return Padding(
                padding:
                const EdgeInsets.only(bottom: 20),
                child: buildCartItem(index),
              );
            },
          ),
        ),

        Container(
          padding: const EdgeInsets.all(20),

          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(25),
              topRight: Radius.circular(25),
            ),
          ),

          child: Column(
            children: [

              Row(
                mainAxisAlignment:
                MainAxisAlignment.spaceBetween,

                children: [

                  Text(
                    "Total",
                    style: AppFonts.cinzel(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  Text(
                    "₹${total.toStringAsFixed(0)}",
                    style: AppFonts.cinzel(
                      color: AppColors.brand(context),
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),

                ],
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 55,

                child: ElevatedButton(

                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,

                    shape: RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(15),
                    ),
                  ),

                  onPressed: () async {

                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                        const CheckoutScreen(),
                      ),
                    );

                    loadCart();

                  },

                  child: Text(
                    "PROCEED TO CHECKOUT",
                    style: AppFonts.cinzel(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                ),
              ),

            ],
          ),
        ),

      ],
    );
  }

  Widget buildCartItem(int index) {
    final item = cartItems[index];

    return Container(
      padding: const EdgeInsets.all(15),

      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),

        boxShadow: [

          BoxShadow(
            color: Colors.black.withValues(alpha: .08),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),

        ],
      ),

      child: Row(
        children: [

          ClipRRect(
            borderRadius: BorderRadius.circular(15),

            child: item["image"].toString().isEmpty
                ? Container(
              width: 90,
              height: 90,
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest,
              child: const Icon(
                Icons.image_not_supported,
              ),
            )
                : Image.asset(
              item["image"],
              height: 90,
              width: 90,
              fit: BoxFit.cover,
              errorBuilder:
                  (context, error, stackTrace) {
                return Container(
                  width: 90,
                  height: 90,
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  child: const Icon(
                    Icons.image_not_supported,
                  ),
                );
              },
            ),
          ),

          const SizedBox(width: 15),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,

              children: [

                Text(
                  item["name"],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.cinzel(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  "₹${item["price"]}",
                  style: AppFonts.cinzel(
                    color: AppColors.brand(context),
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),

                const SizedBox(height: 12),

                Row(
                  children: [

                    InkWell(
                      onTap: () {
                        changeQuantity(
                          index,
                          (item["quantity"] as int) - 1,
                        );
                      },
                      child: Container(
                        padding:
                        const EdgeInsets.all(5),

                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius:
                          BorderRadius.circular(8),
                        ),

                        child: const Icon(
                          Icons.remove,
                          color: Colors.white,
                        ),
                      ),
                    ),

                    Padding(
                      padding:
                      const EdgeInsets.symmetric(
                          horizontal: 15),
                      child: Text(
                        item["quantity"].toString(),
                        style: AppFonts.poppins(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),

                    InkWell(
                      onTap: () {
                        changeQuantity(
                          index,
                          (item["quantity"] as int) + 1,
                        );
                      },
                      child: Container(
                        padding:
                        const EdgeInsets.all(5),

                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius:
                          BorderRadius.circular(8),
                        ),

                        child: const Icon(
                          Icons.add,
                          color: Colors.white,
                        ),
                      ),
                    ),

                  ],
                ),

              ],
            ),
          ),

          IconButton(
            onPressed: () => removeItem(index),
            icon: const Icon(
              Icons.delete,
              color: Colors.red,
            ),
          ),

        ],
      ),
    );
  }
}
