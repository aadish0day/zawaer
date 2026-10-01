import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/product_model.dart';
import '../services/api_service.dart';
import '../utils/colors.dart';
import '../utils/text_styles.dart';
import 'checkout_screen.dart';
import 'login_screen.dart';
import 'product_details_screen.dart';

class CartScreen extends StatefulWidget {
  final String? couponCode;
  const CartScreen({super.key, this.couponCode});

  @override
  State<CartScreen> createState() => CartScreenState();
}

class CartScreenState extends State<CartScreen> {
  bool isLoading = true;
  bool isGuest = false;
  String errorMessage = "";
  List<Map<String, dynamic>> cartItems = [];
  bool isGiftPackagingEnabled = true;

  @override
  void initState() {
    super.initState();
    loadCart();
  }

  // =====================================================
  // LOAD CART FROM BACKEND (MongoDB)
  // =====================================================
  Future<void> loadCart() async {
    // Called from route-pop callbacks, which may fire after dispose.
    if (!mounted) return;
    setState(() {
      isLoading = true;
      errorMessage = "";
    });

    try {
      final cartResult = await ApiService.getCart();

      if (!mounted) return;

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
          errorMessage = cartResult["message"]?.toString() ?? "Could not load cart";
        });
        return;
      }

      final dynamic rawCart = cartResult["cart"];
      final List items = (rawCart?["items"] ?? []) as List;

      final List<Map<String, dynamic>> joined = [];

      // A quantity sync still pending for an item is newer than what the
      // server just returned; keep the local value for those.
      final Map<String, int> pendingQty = {
        for (final item in cartItems)
          if (_qtySyncs.containsKey(item["productId"].toString()))
            item["productId"].toString(): (item["quantity"] as num).toInt(),
      };

      for (final item in items) {
        // Backend populates items[].product; null means the product was deleted.
        final rawProduct = item["product"];
        if (rawProduct is! Map<String, dynamic>) continue;
        final product = Product.fromJson(rawProduct);

        final String productId = item["productId"]?.toString() ?? product.id;
        joined.add({
          "productId": productId,
          "quantity": pendingQty[productId] ?? (item["quantity"] as num?)?.toInt() ?? 1,
          "name": product.name,
          "category": product.category,
          "price": product.price,
          "image": product.images.isNotEmpty
              ? product.images.first
              : "assets/images/ring.png",
          "product": product,
        });
      }

      if (!mounted) return;

      setState(() {
        cartItems = joined;
        isGuest = false;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        errorMessage = "Unable to connect to Maison Vault server";
      });
    }
  }

  // =====================================================
  // UPDATE QUANTITY
  // =====================================================
  // Latest desired quantity per productId, and the running sync loop per item.
  // Rapid taps only update the desired value; one PUT runs at a time per item
  // and always sends the newest value, so responses can't land out of order.
  // Loops keep running after dispose so pending quantities are never dropped.
  final Map<String, int> _desiredQty = {};
  final Map<String, Future<void>> _qtySyncs = {};
  bool isWaitingForSync = false;

  void changeQuantity(int index, int newQuantity) {
    if (newQuantity < 1 || newQuantity > 10) return;
    HapticFeedback.selectionClick();

    final productId = cartItems[index]["productId"].toString();

    setState(() {
      cartItems[index]["quantity"] = newQuantity;
    });

    _desiredQty[productId] = newQuantity;
    _qtySyncs[productId] ??= _syncQuantity(productId);
  }

  Future<void> _syncQuantity(String productId) async {
    String? failure;
    try {
      while (_desiredQty.containsKey(productId)) {
        final quantity = _desiredQty.remove(productId)!;
        final result = await ApiService.updateCartQuantity(
          productId: productId,
          quantity: quantity,
        );

        if (result["success"] != true) {
          _desiredQty.remove(productId);
          failure = result["message"]?.toString() ?? "Could not update quantity";
          break;
        }

        // Reconcile with the server-confirmed value unless a newer tap is queued.
        if (mounted && !_desiredQty.containsKey(productId)) {
          final List serverItems = (result["cart"]?["items"] ?? const []) as List;
          final confirmed = serverItems.firstWhere(
            (i) => i["productId"]?.toString() == productId,
            orElse: () => null,
          );
          final int confirmedQty = (confirmed?["quantity"] as num?)?.toInt() ?? quantity;
          setState(() {
            for (final item in cartItems) {
              if (item["productId"].toString() == productId) item["quantity"] = confirmedQty;
            }
          });
        }
      }
    } finally {
      _qtySyncs.remove(productId);
    }

    if (failure != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade900,
          content: Text(failure, style: AppFonts.poppins(color: Colors.white)),
        ),
      );
      loadCart();
    }
  }

  Future<void> proceedToCheckout() async {
    if (isWaitingForSync) return;
    HapticFeedback.mediumImpact();

    if (_qtySyncs.isNotEmpty) {
      setState(() => isWaitingForSync = true);
      while (_qtySyncs.isNotEmpty) {
        await Future.wait(_qtySyncs.values.toList());
      }
      if (!mounted) return;
      setState(() => isWaitingForSync = false);
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(initialCouponCode: widget.couponCode),
      ),
    );
    loadCart();
  }

  // =====================================================
  // REMOVE ITEM
  // =====================================================
  Future<void> removeItem(int index) async {
    HapticFeedback.lightImpact();
    final item = cartItems[index];
    _desiredQty.remove(item["productId"].toString());

    setState(() {
      cartItems.removeAt(index);
    });

    final result = await ApiService.removeFromCart(
      item["productId"].toString(),
    );

    if (!mounted) return;

    if (result["success"] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1E1E24),
          content: Text(
            "${item["name"]} removed from Vault Bag",
            style: AppFonts.poppins(fontSize: 12.5, color: Colors.white),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      await loadCart();
    }
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

  int get totalPieces {
    int sum = 0;
    for (final item in cartItems) {
      sum += (item["quantity"] as num?)?.toInt() ?? 1;
    }
    return sum;
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
              : errorMessage.isNotEmpty
                  ? buildErrorView(isDark)
                  : cartItems.isEmpty
                      ? buildEmptyView(isDark)
                      : buildCartView(isDark),
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
            "ZAWER MAISON",
            style: AppFonts.cinzel(
              fontSize: 10,
              letterSpacing: 3.5,
              fontWeight: FontWeight.w600,
              color: AppColors.gold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            "Vault Bag",
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
          icon: const Icon(Icons.refresh, size: 20),
          tooltip: "Refresh Bag",
          onPressed: loadCart,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  // =========================================================================
  // 2. MAIN CART VIEW WITH STACKED CHECKOUT CHASSIS
  // =========================================================================
  Widget buildCartView(bool isDark) {
    return Column(
      children: [
        // Trust Reassurance Top Strip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: isDark ? const Color(0xFF16161B) : const Color(0xFFF3EFE7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shield_outlined, size: 14, color: AppColors.gold),
              const SizedBox(width: 6),
              Text(
                "COMPLIMENTARY ARMORED ESCORT • 100% INSURED",
                style: AppFonts.poppins(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                  color: isDark ? AppColors.gold : const Color(0xFF8B6508),
                ),
              ),
            ],
          ),
        ),
        // Cart Items List
        Expanded(
          child: RefreshIndicator(
            onRefresh: loadCart,
            color: AppColors.gold,
            backgroundColor: isDark ? const Color(0xFF18181E) : Colors.white,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: cartItems.length + 1,
              itemBuilder: (context, index) {
                if (index == cartItems.length) {
                  return buildGiftPackagingCard(isDark);
                }
                return buildLuxuryCartItem(index, isDark);
              },
            ),
          ),
        ),
        // Fixed Luxury Bottom Valuation & Checkout Sheet
        buildCheckoutChassis(isDark),
      ],
    );
  }

  // =========================================================================
  // 3. BESPOKE CART ITEM CARD (Double-Bezel Concentric Architecture)
  // =========================================================================
  Widget buildLuxuryCartItem(int index, bool isDark) {
    final item = cartItems[index];
    final productObj = item["product"] as Product;

    final quantity = (item["quantity"] as num?)?.toInt() ?? 1;
    final itemPrice = (item["price"] as num?)?.toDouble() ?? 0.0;
    final itemSubtotal = itemPrice * quantity;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(1.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            AppColors.gold.withValues(alpha: 0.3),
            AppColors.gold.withValues(alpha: 0.06),
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
                ).then((_) => loadCart());
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
            // Details & Quantity Stepper
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
                            ).then((_) => loadCart());
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
                  Text(
                    "₹${itemPrice.toStringAsFixed(0)} / piece",
                    style: AppFonts.poppins(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Tactile Quantity Stepper
                      Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1F1F26) : const Color(0xFFF3EFE8),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? Colors.white12 : Colors.black12,
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                              onTap: () => changeQuantity(index, quantity - 1),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                child: Icon(
                                  quantity == 1 ? Icons.delete_outline_rounded : Icons.remove,
                                  size: 15,
                                  color: quantity == 1 ? Colors.redAccent : AppColors.brand(context),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                quantity.toString(),
                                style: AppFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            InkWell(
                              borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                              onTap: () => changeQuantity(index, quantity + 1),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                child: Icon(
                                  Icons.add,
                                  size: 15,
                                  color: AppColors.brand(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Item Total
                      Text(
                        "₹${itemSubtotal.toStringAsFixed(0)}",
                        style: AppFonts.cinzel(
                          fontSize: 16.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.brand(context),
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
  // 4. BESPOKE MAISON PACKAGING CARD
  // =========================================================================
  Widget buildGiftPackagingCard(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141418) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.gold.withValues(alpha: 0.25),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.card_giftcard_rounded, color: AppColors.gold, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Signature Velvet Presentation Box",
                  style: AppFonts.cinzel(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  "Complimentary anti-tarnish jewel pouch & wax seal.",
                  style: AppFonts.poppins(
                    fontSize: 10.5,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: isGiftPackagingEnabled,
            activeThumbColor: AppColors.gold,
            activeTrackColor: AppColors.gold.withValues(alpha: 0.35),
            onChanged: (val) {
              HapticFeedback.selectionClick();
              setState(() {
                isGiftPackagingEnabled = val;
              });
            },
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 5. FIXED LUXURY VALUATION & CHECKOUT CHASSIS (Doppelrand Bottom Sheet)
  // =========================================================================
  Widget buildCheckoutChassis(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141418) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border.all(
          color: AppColors.gold.withValues(alpha: 0.25),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "VAULT VALUATION ($totalPieces ${totalPieces == 1 ? 'PIECE' : 'PIECES'})",
                      style: AppFonts.poppins(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.6,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Taxes & Insurance Included",
                      style: AppFonts.poppins(
                        fontSize: 11,
                        color: const Color(0xFF2E7D32),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Text(
                  "₹${subtotal.toStringAsFixed(0)}",
                  style: AppFonts.cinzel(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
                onPressed: isWaitingForSync ? null : proceedToCheckout,
                child: isWaitingForSync
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 24),
                    Text(
                      "PROCEED TO VAULT CHECKOUT",
                      style: AppFonts.cinzel(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.4,
                        color: Colors.white,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // 6. GUEST, ERROR & EMPTY STATES
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
              "Sign in to your ZAWER account to view and secure the precious jewellery in your Vault Bag.",
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
                loadCart();
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
                Icons.shopping_bag_outlined,
                size: 48,
                color: AppColors.gold.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "Your Vault Bag is Empty",
              textAlign: TextAlign.center,
              style: AppFonts.cinzel(
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Discover exceptional solitaire rings, royal bridal necklaces, and 18K Italian chains in the catalog.",
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

  Widget buildErrorView(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 54, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(
              "Vault Bag Connection Error",
              style: AppFonts.cinzel(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: AppFonts.poppins(fontSize: 12.5, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: loadCart,
              child: const Text("RETRY CONNECTION"),
            ),
          ],
        ),
      ),
    );
  }
}
