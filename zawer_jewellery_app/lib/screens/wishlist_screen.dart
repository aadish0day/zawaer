import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/product_model.dart';
import '../services/api_service.dart';
import '../utils/colors.dart';
import '../utils/text_styles.dart';
import 'cart_screen.dart';
import 'login_screen.dart';
import 'product_details_screen.dart';

class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => WishlistScreenState();
}

class WishlistScreenState extends State<WishlistScreen> {
  bool isLoading = true;
  bool isGuest = false;
  List<Map<String, dynamic>> wishlist = [];
  bool isMovingAll = false;

  @override
  void initState() {
    super.initState();
    loadWishlist();
  }

  // =====================================================
  // LOAD WISHLIST FROM BACKEND (MongoDB)
  // =====================================================
  Future<void> loadWishlist() async {
    // Called from route-pop callbacks, which may fire after dispose.
    if (!mounted) return;
    setState(() {
      isLoading = true;
    });

    try {
      final wishResult = await ApiService.getWishlist();

      if (!mounted) return;

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
      final List items = (rawWish?["items"] ?? []) as List;

      final List<Map<String, dynamic>> joined = [];

      for (final item in items) {
        // Backend populates items[].product; null means the product was deleted.
        final rawProduct = item["product"];
        if (rawProduct is! Map<String, dynamic>) continue;
        final product = Product.fromJson(rawProduct);

        joined.add({
          "productId": item["productId"]?.toString() ?? product.id,
          "name": product.name,
          "price": product.price,
          "category": product.category,
          "image": product.images.isNotEmpty ? product.images.first : "assets/images/ring.png",
          "product": product,
        });
      }

      if (!mounted) return;

      setState(() {
        wishlist = joined;
        isGuest = false;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
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
    HapticFeedback.lightImpact();
    final item = wishlist[index];
    final productId = item["productId"].toString();

    setState(() {
      wishlist.removeAt(index);
    });

    final result = await ApiService.removeFromWishlist(productId);

    if (!mounted) return;

    if (result["success"] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1E1E24),
          content: Text(
            "${item["name"]} removed from your vault list",
            style: AppFonts.poppins(fontSize: 12.5, color: Colors.white),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      await loadWishlist();
    }
  }

  // =====================================================
  // MOVE SINGLE ITEM TO BAG
  // =====================================================
  // Product ids with a "move to bag" in flight; blocks double taps.
  final Set<String> movingIds = {};

  Future<void> moveToCart(int index) async {
    final item = wishlist[index];
    final productId = item["productId"].toString();
    if (isMovingAll || !movingIds.add(productId)) return;
    try {
      await _moveToCart(item);
    } finally {
      movingIds.remove(productId);
    }
  }

  Future<void> _moveToCart(Map<String, dynamic> item) async {
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.of(context);

    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1E1E24),
        content: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
            ),
            const SizedBox(width: 10),
            Text(
              "Transferring ${item["name"]} to Vault Bag...",
              style: AppFonts.poppins(fontSize: 12, color: Colors.white),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 700),
      ),
    );

    final result = await ApiService.addToCart(
      productId: item["productId"].toString(),
      quantity: 1,
    );

    if (!mounted) return;

    if (result["success"] == true) {
      await ApiService.removeFromWishlist(item["productId"].toString());
      if (!mounted) return;
      await loadWishlist();
      if (!mounted) return;

      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.black87,
          action: SnackBarAction(
            label: "VIEW BAG",
            textColor: AppColors.gold,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CartScreen()),
              );
            },
          ),
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.gold, size: 16),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  "${item["name"]} added to Vault Bag",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade900,
          content: Text(
            result["message"]?.toString() ?? "Could not add to bag",
            style: AppFonts.poppins(color: Colors.white),
          ),
        ),
      );
    }
  }

  // =====================================================
  // MOVE ALL TO BAG
  // =====================================================
  Future<void> moveAllToCart() async {
    if (wishlist.isEmpty || isMovingAll) return;
    HapticFeedback.heavyImpact();

    setState(() {
      isMovingAll = true;
    });

    final messenger = ScaffoldMessenger.of(context);

    int successCount = 0;
    final itemsToMove = List<Map<String, dynamic>>.from(wishlist);
    for (final item in itemsToMove) {
      final productId = item["productId"].toString();
      final res = await ApiService.addToCart(
        productId: productId,
        quantity: 1,
      );
      if (res["success"] == true) {
        successCount++;
        await ApiService.removeFromWishlist(productId);
      }
    }

    if (!mounted) return;

    await loadWishlist();

    if (!mounted) return;

    setState(() {
      isMovingAll = false;
    });

    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.black87,
        action: SnackBarAction(
          label: "GO TO BAG",
          textColor: AppColors.gold,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CartScreen()),
            );
          },
        ),
        content: Text(
          "$successCount pieces moved to your Vault Bag",
          style: AppFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  double get totalWishlistValue {
    return wishlist.fold(0.0, (sum, item) => sum + ((item["price"] as num?)?.toDouble() ?? 0.0));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0C0C0E) : const Color(0xFFFAF8F5),
      appBar: buildMaisonAppBar(isDark),
      body: isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 38,
                    height: 38,
                    child: CircularProgressIndicator(
                      color: AppColors.gold,
                      strokeWidth: 2.2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Connecting to Maison Vault...",
                    style: AppFonts.cinzel(
                      fontSize: 13,
                      letterSpacing: 1.2,
                      color: AppColors.gold,
                    ),
                  ),
                ],
              ),
            )
          : isGuest
              ? buildGuestView(isDark)
              : wishlist.isEmpty
                  ? buildEmptyView(isDark)
                  : RefreshIndicator(
                      onRefresh: loadWishlist,
                      color: AppColors.gold,
                      backgroundColor: isDark ? const Color(0xFF18181E) : Colors.white,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: buildCuratorHeaderCard(isDark),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final item = wishlist[index];
                                  return buildLuxuryWishlistItem(item, index, isDark);
                                },
                                childCount: wishlist.length,
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Column(
                              children: [
                                const SizedBox(height: 14),
                                buildMaisonGuaranteeStrip(isDark),
                                const SizedBox(height: 40),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
    );
  }

  // =========================================================================
  // 1. APP BAR
  // =========================================================================
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
            "Curated Wishlist",
            style: AppFonts.cinzel(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.shopping_bag_outlined, size: 20),
          tooltip: "Vault Bag",
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CartScreen()),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.refresh, size: 20),
          tooltip: "Refresh",
          onPressed: loadWishlist,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  // =========================================================================
  // 2. CURATOR SUMMARY & MOVE-ALL CARD (Double-Bezel Architecture)
  // =========================================================================
  Widget buildCuratorHeaderCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(1.2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [
            AppColors.gold.withValues(alpha: 0.4),
            AppColors.gold.withValues(alpha: 0.08),
            Colors.transparent,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF141418) : Colors.white,
          borderRadius: BorderRadius.circular(21),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "SAVED VALUABLES",
                      style: AppFonts.poppins(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.8,
                        color: AppColors.gold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      "${wishlist.length} Curated ${wishlist.length == 1 ? 'Piece' : 'Pieces'}",
                      style: AppFonts.cinzel(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      "TOTAL VALUATION",
                      style: AppFonts.poppins(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.8,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      "₹${totalWishlistValue.toStringAsFixed(0)}",
                      style: AppFonts.cinzel(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brand(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: isMovingAll ? null : moveAllToCart,
                icon: isMovingAll
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.shopping_bag_outlined, size: 16),
                label: Text(
                  isMovingAll ? "TRANSFERRING..." : "MOVE ALL TO VAULT BAG",
                  style: AppFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // 3. BESPOKE WISHLIST ITEM CARD (Double-Bezel Concentric Architecture)
  // =========================================================================
  Widget buildLuxuryWishlistItem(Map<String, dynamic> item, int index, bool isDark) {
    final productObj = item["product"] as Product;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(1.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            AppColors.gold.withValues(alpha: 0.28),
            AppColors.gold.withValues(alpha: 0.05),
            Colors.transparent,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF141418) : Colors.white,
          borderRadius: BorderRadius.circular(19),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Jewellery Piece Image
            InkWell(
              borderRadius: BorderRadius.circular(15),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ProductDetailsScreen(product: productObj)),
                ).then((_) => loadWishlist());
              },
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Container(
                      width: 96,
                      height: 96,
                      color: isDark ? const Color(0xFF1C1C22) : const Color(0xFFF7F5F0),
                      child: Image.asset(
                        item["image"].toString(),
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          width: 96,
                          height: 96,
                          color: isDark ? const Color(0xFF222228) : const Color(0xFFF2EEE7),
                          child: const Icon(Icons.diamond_outlined, size: 24, color: AppColors.gold),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.gold.withValues(alpha: 0.4), width: 0.6),
                      ),
                      child: Text(
                        item["category"].toString().toUpperCase(),
                        style: AppFonts.poppins(
                          fontSize: 7.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6,
                          color: AppColors.gold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            // Piece Details & Actions
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => ProductDetailsScreen(product: productObj)),
                            ).then((_) => loadWishlist());
                          },
                          child: Text(
                            item["name"].toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppFonts.cinzel(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => removeItem(index),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 15,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        "In Vault Stock • BIS Certified",
                        style: AppFonts.poppins(
                          fontSize: 10,
                          color: const Color(0xFF2E7D32),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "₹${(item["price"] as num?)?.toStringAsFixed(0) ?? '0'}",
                        style: AppFonts.cinzel(
                          color: AppColors.brand(context),
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? const Color(0xFF201D17) : const Color(0xFFF9F5EC),
                          foregroundColor: AppColors.gold,
                          elevation: 0,
                          minimumSize: const Size(96, 34),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: AppColors.gold.withValues(alpha: 0.4), width: 0.8),
                          ),
                        ),
                        onPressed: () => moveToCart(index),
                        icon: const Icon(Icons.shopping_bag_outlined, size: 13, color: AppColors.gold),
                        label: Text(
                          "Add to Bag",
                          style: AppFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppColors.gold : const Color(0xFF8B6508),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // 4. MAISON GUARANTEE STRIP
  // =========================================================================
  Widget buildMaisonGuaranteeStrip(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131317) : const Color(0xFFF7F5F0),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.gold.withValues(alpha: 0.2),
            width: 0.8,
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified_user_outlined, color: AppColors.gold, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "All pieces in your wishlist are 100% certified natural diamonds & BIS 916 hallmarked.",
                style: AppFonts.poppins(
                  fontSize: 11,
                  height: 1.4,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // 5. GUEST & EMPTY STATES
  // =========================================================================
  Widget buildGuestView(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.gold.withValues(alpha: 0.12),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
              ),
              child: const Icon(
                Icons.lock_person_outlined,
                size: 44,
                color: AppColors.gold,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "Private Vault Access Required",
              textAlign: TextAlign.center,
              style: AppFonts.cinzel(
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Sign in to your ZAWER Maison account to preserve and access your curated wishlist across devices.",
              textAlign: TextAlign.center,
              style: AppFonts.poppins(
                fontSize: 12.5,
                height: 1.5,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(200, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
                loadWishlist();
              },
              child: Text(
                "SIGN IN TO VAULT",
                style: AppFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildEmptyView(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.gold.withValues(alpha: 0.1),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.25)),
              ),
              child: Icon(
                Icons.favorite_border_rounded,
                size: 48,
                color: AppColors.gold.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "Your Vault Wishlist is Empty",
              textAlign: TextAlign.center,
              style: AppFonts.cinzel(
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Curate your dream jewellery pieces by tapping the heart icon on any solitaire, necklace, or chain in the catalog.",
              textAlign: TextAlign.center,
              style: AppFonts.poppins(
                fontSize: 12.5,
                height: 1.5,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(200, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () {
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
              icon: const Icon(Icons.explore_outlined, size: 18),
              label: Text(
                "EXPLORE CATALOG",
                style: AppFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
