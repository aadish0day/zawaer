import 'package:flutter/material.dart';
import '../utils/text_styles.dart';

import '../models/product_model.dart';
import '../services/api_service.dart';

import '../utils/colors.dart';
import 'login_screen.dart';
import 'product_details_screen.dart';

class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() =>
      WishlistScreenState();
}

class WishlistScreenState
    extends State<WishlistScreen> {

  bool isLoading = true;

  bool isGuest = false;

  List<Map<String, dynamic>> wishlist = [];

  @override
  void initState() {
    super.initState();

    loadWishlist();
  }

  // =====================================================
  // LOAD WISHLIST FROM BACKEND
  // =====================================================

  Future<void> loadWishlist() async {

    setState(() {
      isLoading = true;
    });

    try {

      final wishResult =
      await ApiService.getWishlist();

      if (!mounted) {
        return;
      }

      if (wishResult["statusCode"] == 401) {
        setState(() {
          isGuest = true;
          isLoading = false;
          wishlist = [];
        });
        return;
      }

      if (wishResult["success"] != true) {
        setState(() {
          isLoading = false;
          wishlist = [];
        });
        return;
      }

      final dynamic rawWish = wishResult["wishlist"];
      final List items =
      (rawWish?["items"] ?? []) as List;

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

        if (product == null) {
          continue;
        }

        joined.add({
          "productId": productId,
          "name": product.name,
          "price": product.price,
          "category": product.category,
          "image": product.images.isNotEmpty
              ? product.images.first
              : "",
        });
      }

      if (!mounted) {
        return;
      }

      setState(() {
        wishlist = joined;
        isGuest = false;
        isLoading = false;
      });

    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        isLoading = false;
        wishlist = [];
      });
    }
  }

  // =====================================================
  // REMOVE FROM WISHLIST
  // =====================================================

  Future<void> removeItem(int index) async {

    final item = wishlist[index];

    final result =
    await ApiService.removeFromWishlist(
      item["productId"].toString(),
    );

    if (!mounted) {
      return;
    }

    if (result["success"] == true) {
      setState(() {
        wishlist.removeAt(index);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Removed from Wishlist",
          ),
        ),
      );
    }
  }

  // =====================================================
  // MOVE TO CART
  // =====================================================

  Future<void> moveToCart(int index) async {

    final item = wishlist[index];

    final result = await ApiService.addToCart(
      productId: item["productId"].toString(),
      quantity: 1,
    );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result["success"] == true
              ? "${item["name"]} added to cart"
              : result["message"]?.toString() ??
              "Could not add to cart",
        ),
      ),
    );
  }

  // =====================================================
  // BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor:
      Theme.of(context).scaffoldBackgroundColor,

      appBar: AppBar(

        backgroundColor:
        Theme.of(context).colorScheme.surface,

        elevation: 0,

        centerTitle: true,

        title: Text(

          "Wishlist",

          style: AppFonts.cinzel(

            color:
            Theme.of(context).colorScheme.onSurface,

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
          : wishlist.isEmpty
          ? buildEmptyView()
          : buildWishlistView(),

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
            "Login to view your wishlist",
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
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const LoginScreen(),
                ),
              );

              loadWishlist();
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

  Widget buildEmptyView() {
    return Center(
      child: Text(
        "Your Wishlist is Empty",
        style: AppFonts.cinzel(
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget buildWishlistView() {
    return ListView.builder(

      padding: const EdgeInsets.all(15),

      itemCount: wishlist.length,

      itemBuilder: (context, index) {
        final item = wishlist[index];

        return buildWishlistItem(item, index);
      },

    );
  }

  Widget buildWishlistItem(
      Map<String, dynamic> item,
      int index,
      ) {

    return Container(

      margin: const EdgeInsets.only(bottom: 18),

      padding: const EdgeInsets.all(15),

      decoration: BoxDecoration(

        color: Theme.of(context).colorScheme.surface,

        borderRadius: BorderRadius.circular(20),

        boxShadow: [

          BoxShadow(

            color: Colors.black.withValues(alpha: .08),

            blurRadius: 10,

            offset: const Offset(0,5),

          ),

        ],

      ),

      child: Row(

        children: [

          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ProductDetailsScreen(
                        product: Product(
                          id: item["productId"],
                          name: item["name"],
                          category: item["category"],
                          description: "",
                          price: (item["price"]
                          as num).toDouble(),
                          rating: 0,
                          images: [
                            item["image"],
                          ],
                        ),
                      ),
                ),
              );
            },

            child: ClipRRect(

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

                width: 90,

                height: 90,

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
          ),

          const SizedBox(width:15),

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

                    fontSize:17,

                  ),

                ),

                const SizedBox(height:10),

                Text(

                  "₹${item["price"]}",

                  style: AppFonts.cinzel(

                    color: AppColors.brand(context),

                    fontWeight: FontWeight.bold,

                    fontSize:20,

                  ),

                ),

                const SizedBox(height:15),

                Row(

                  children: [

                    Expanded(

                      child: ElevatedButton.icon(

                        style:
                        ElevatedButton.styleFrom(

                          backgroundColor:
                          AppColors.primary,

                          shape:
                          RoundedRectangleBorder(

                            borderRadius:
                            BorderRadius.circular(12),

                          ),

                        ),

                        onPressed: () => moveToCart(index),

                        icon: const Icon(

                          Icons.shopping_cart,

                          color: Colors.white,

                          size:18,

                        ),

                        label: Text(

                          "Cart",

                          style:
                          AppFonts.poppins(

                            color: Colors.white,

                            fontWeight:
                            FontWeight.bold,

                          ),

                        ),

                      ),

                    ),

                    const SizedBox(width:10),

                    CircleAvatar(

                      backgroundColor:
                      Colors.red.shade50,

                      child: IconButton(

                        icon: const Icon(

                          Icons.delete,

                          color: Colors.red,

                        ),

                        onPressed: () =>
                            removeItem(index),

                      ),

                    ),

                  ],

                ),

              ],

            ),

          ),

        ],

      ),

    );

  }

}
