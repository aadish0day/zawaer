import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/offer_model.dart';
import '../models/product_model.dart';
import '../services/api_service.dart';
import '../utils/colors.dart';
import '../utils/text_styles.dart';
import 'cart_screen.dart';
import 'product_details_screen.dart';

class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key});

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  bool isLoading = true;
  String errorMessage = "";
  List<OfferModel> offers = [];
  List<Product> discountedProducts = [];
  String selectedFilter = "All"; // "All", "Coupons", "Discounted Pieces", "Calculator"

  // Calculator State
  final TextEditingController calcAmountController = TextEditingController(text: "35000");
  String? selectedCalcCoupon = "ROYAL20";
  double simulatedDiscount = 7000;
  double simulatedFinalAmount = 28000;
  String calcMessage = "";

  Timer? _countdownTimer;
  Duration _flashDuration = const Duration(days: 4, hours: 14, minutes: 28, seconds: 45);

  @override
  void initState() {
    super.initState();
    loadOffersData();
    _startCountdown();
    _recalculateSimulation();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    calcAmountController.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_flashDuration.inSeconds > 0) {
        setState(() {
          _flashDuration = _flashDuration - const Duration(seconds: 1);
        });
      }
    });
  }

  Future<void> loadOffersData() async {
    setState(() {
      isLoading = true;
      errorMessage = "";
    });

    try {
      final offersRes = await ApiService.getOffers();
      final productsRes = await ApiService.getDiscountedProducts();

      if (!mounted) return;

      if (offersRes["success"] != true && productsRes["success"] != true) {
        setState(() {
          isLoading = false;
          errorMessage = offersRes["message"]?.toString() ??
              productsRes["message"]?.toString() ??
              "Unable to load promotional offers";
        });
        return;
      }

      List<OfferModel> loadedOffers = [];
      if (offersRes["success"] == true && offersRes["offers"] is List) {
        loadedOffers = (offersRes["offers"] as List)
            .map((o) => OfferModel.fromJson(o as Map<String, dynamic>))
            .toList();
      }

      List<Product> loadedProducts = [];
      if (productsRes["success"] == true && productsRes["products"] is List) {
        loadedProducts = (productsRes["products"] as List)
            .map((p) => Product.fromJson(p as Map<String, dynamic>))
            .toList();
      }

      setState(() {
        offers = loadedOffers;
        discountedProducts = loadedProducts;
        isLoading = false;
        errorMessage = "";
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          isLoading = false;
          errorMessage = "Unable to connect to Maison Vault server";
        });
      }
    }
  }

  void _recalculateSimulation() {
    final subtotal = double.tryParse(calcAmountController.text.trim()) ?? 0.0;
    if (selectedCalcCoupon == null || selectedCalcCoupon!.isEmpty) {
      setState(() {
        simulatedDiscount = 0.0;
        simulatedFinalAmount = subtotal;
        calcMessage = "Enter or select a privilege coupon code";
      });
      return;
    }

    final offer = offers.firstWhere(
      (o) => o.code == selectedCalcCoupon,
      orElse: () => OfferModel(
        id: "",
        code: selectedCalcCoupon!,
        title: "",
        description: "",
        discountType: "percentage",
        discountValue: 20,
        maxDiscount: 10000,
        minOrderAmount: 25000,
        applicableCategory: "All",
        isExpired: false,
        daysRemaining: 10,
        hoursRemaining: 0,
        isValid: true,
        tag: "",
        bannerImage: "",
        terms: [],
      ),
    );

    if (subtotal < offer.minOrderAmount) {
      setState(() {
        simulatedDiscount = 0.0;
        simulatedFinalAmount = subtotal;
        calcMessage = "Minimum cart valuation of ₹${offer.minOrderAmount.toStringAsFixed(0)} required";
      });
      return;
    }

    final disc = offer.calculateDiscount(subtotal);
    setState(() {
      simulatedDiscount = disc;
      simulatedFinalAmount = subtotal - disc;
      calcMessage = "You save ₹${disc.toStringAsFixed(0)} with '${offer.code}'!";
    });
  }

  void copyCouponCode(String code) {
    HapticFeedback.mediumImpact();
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1B1B22),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.gold, size: 16),
            const SizedBox(width: 8),
            Text(
              "Privilege code '$code' copied to clipboard",
              style: AppFonts.poppins(fontSize: 12.5, color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0C0C0E) : const Color(0xFFFAF8F5),
      appBar: buildMaisonAppBar(isDark),
      body: RefreshIndicator(
        onRefresh: loadOffersData,
        color: AppColors.gold,
        backgroundColor: isDark ? const Color(0xFF18181E) : Colors.white,
        child: isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2.2),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      "Unlocking Maison Privilege Vault...",
                      style: AppFonts.cinzel(fontSize: 13, color: AppColors.gold),
                    ),
                  ],
                ),
              )
            : errorMessage.isNotEmpty
                ? buildErrorView(isDark)
                : CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        // 1. Featured Flash Offer Hero Banner
                        buildFlashHeroBanner(isDark),
                        const SizedBox(height: 16),
                        // 2. Filter Tabs
                        buildFilterTabs(isDark),
                        const SizedBox(height: 14),
                      ],
                    ),
                  ),
                  if (selectedFilter == "All" || selectedFilter == "Coupons") ...[
                    SliverToBoxAdapter(
                      child: buildSectionHeader("MAISON PRIVILEGE VOUCHERS", isDark),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            return buildPerforatedCouponCard(offers[index], isDark);
                          },
                          childCount: offers.length,
                        ),
                      ),
                    ),
                  ],
                  if ((selectedFilter == "All" || selectedFilter == "Discounted Pieces") &&
                      discountedProducts.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 16),
                          buildSectionHeader("SPECIAL DISCOUNTED MASTERPIECES", isDark),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 16,
                          childAspectRatio: 0.56,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final product = discountedProducts[index];
                            return buildDiscountedProductCard(product, isDark);
                          },
                          childCount: discountedProducts.length,
                        ),
                      ),
                    ),
                  ],
                  if (selectedFilter == "All" || selectedFilter == "Calculator") ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        child: buildDiscountCalculatorCard(isDark),
                      ),
                    ),
                  ],
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 48),
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
            "Privilege Offers",
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
        const SizedBox(width: 4),
      ],
    );
  }

  // =========================================================================
  // 2. FEATURED FLASH HERO BANNER WITH LIVE COUNTDOWN
  // =========================================================================
  Widget buildFlashHeroBanner(bool isDark) {
    final days = _flashDuration.inDays.toString().padLeft(2, '0');
    final hours = (_flashDuration.inHours % 24).toString().padLeft(2, '0');
    final mins = (_flashDuration.inMinutes % 60).toString().padLeft(2, '0');
    final secs = (_flashDuration.inSeconds % 60).toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(1.2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: [
              AppColors.gold.withValues(alpha: 0.6),
              AppColors.gold.withValues(alpha: 0.15),
              Colors.transparent,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF131317) : const Color(0xFF221F1B),
            borderRadius: BorderRadius.circular(23),
            image: DecorationImage(
              image: const AssetImage("assets/images/necklace.jpg"),
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(
                Colors.black.withValues(alpha: 0.65),
                BlendMode.darken,
              ),
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppColors.gold.withValues(alpha: 0.6),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      "FLASH PRIVILEGE",
                      style: AppFonts.poppins(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.4,
                        color: AppColors.gold,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined, size: 14, color: AppColors.gold),
                      const SizedBox(width: 4),
                      Text(
                        "$days : $hours : $mins : $secs",
                        style: AppFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                          color: AppColors.gold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                "Royal 20% Heritage Privilege",
                style: AppFonts.cinzel(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "Unlock up to ₹10,000 concession on 18K solid gold & solitaire suites above ₹25,000.",
                style: AppFonts.poppins(
                  fontSize: 11.5,
                  height: 1.4,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Text(
                          "CODE: ROYAL20",
                          style: AppFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                            color: AppColors.gold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => copyCouponCode("ROYAL20"),
                          child: const Icon(Icons.copy_rounded, size: 13, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(100, 36),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      copyCouponCode("ROYAL20");
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CartScreen(couponCode: "ROYAL20")),
                      );
                    },
                    child: Text(
                      "CLAIM NOW",
                      style: AppFonts.cinzel(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // 3. FILTER TABS
  // =========================================================================
  Widget buildFilterTabs(bool isDark) {
    final tabs = ["All", "Coupons", "Discounted Pieces", "Calculator"];

    return SizedBox(
      height: 38,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final isSelected = selectedFilter == tab;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  selectedFilter = tab;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.gold
                      : (isDark ? const Color(0xFF16161C) : Colors.white),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? AppColors.gold : (isDark ? Colors.white12 : Colors.black12),
                    width: isSelected ? 1.2 : 0.8,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppColors.gold.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  tab,
                  style: AppFonts.poppins(
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    color: isSelected ? Colors.black : (isDark ? Colors.white : AppColors.black),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        title,
        style: AppFonts.poppins(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.6,
          color: AppColors.gold,
        ),
      ),
    );
  }

  // =========================================================================
  // 4. PERFORATED COUPON CARD (Doppelrand Architecture)
  // =========================================================================
  Widget buildPerforatedCouponCard(OfferModel offer, bool isDark) {
    final bool isExpired = offer.isExpired;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(1.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            isExpired
                ? Colors.grey.withValues(alpha: 0.2)
                : AppColors.gold.withValues(alpha: 0.35),
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF141418) : Colors.white,
          borderRadius: BorderRadius.circular(19),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Code Pill + Discount Badge + Expiry Status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isExpired
                            ? Colors.grey.withValues(alpha: 0.2)
                            : AppColors.gold.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isExpired ? Colors.grey : AppColors.gold,
                          width: 0.9,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            offer.code,
                            style: AppFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1,
                              color: isExpired ? Colors.grey : AppColors.gold,
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: isExpired ? null : () => copyCouponCode(offer.code),
                            child: Icon(
                              Icons.copy_rounded,
                              size: 13,
                              color: isExpired ? Colors.grey : AppColors.gold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E26) : const Color(0xFFF3EFE8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        offer.discountLabel,
                        style: AppFonts.poppins(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.brand(context),
                        ),
                      ),
                    ),
                  ],
                ),
                // Expiry Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isExpired
                        ? Colors.red.withValues(alpha: 0.12)
                        : const Color(0xFF2E7D32).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isExpired ? Icons.cancel_outlined : Icons.check_circle_outline_rounded,
                        size: 12,
                        color: isExpired ? Colors.red : const Color(0xFF2E7D32),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isExpired ? "EXPIRED" : "${offer.daysRemaining}d left",
                        style: AppFonts.poppins(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: isExpired ? Colors.red : const Color(0xFF2E7D32),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              offer.title,
              style: AppFonts.cinzel(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              offer.description,
              style: AppFonts.poppins(
                fontSize: 11.5,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 12, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  offer.minOrderText,
                  style: AppFonts.poppins(fontSize: 10.5, color: Colors.grey),
                ),
              ],
            ),
            const Divider(height: 18),
            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                InkWell(
                  onTap: () => showTermsModal(offer),
                  child: Row(
                    children: [
                      Text(
                        "Terms & Conditions",
                        style: AppFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Colors.grey),
                    ],
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isExpired ? Colors.grey.shade800 : AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    minimumSize: const Size(110, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: isExpired
                      ? null
                      : () {
                          copyCouponCode(offer.code);
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => CartScreen(couponCode: offer.code)),
                          );
                        },
                  child: Text(
                    isExpired ? "EXPIRED" : "APPLY IN BAG",
                    style: AppFonts.poppins(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // 5. DISCOUNTED PRODUCT CARD
  // =========================================================================
  Widget buildDiscountedProductCard(Product product, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(1.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [
            AppColors.gold.withValues(alpha: 0.35),
            AppColors.gold.withValues(alpha: 0.05),
            Colors.transparent,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF141418) : Colors.white,
          borderRadius: BorderRadius.circular(21),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(21),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ProductDetailsScreen(product: product)),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(21)),
                        color: isDark ? const Color(0xFF1C1C22) : const Color(0xFFF7F5F0),
                        image: DecorationImage(
                          image: AssetImage(
                            Product.normalizeAssetPath(
                              product.images.isNotEmpty ? product.images.first : "assets/images/ring.png",
                            ),
                          ),
                          fit: BoxFit.cover,
                          onError: (exception, stackTrace) {},
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          product.offerTag.isNotEmpty
                              ? product.offerTag
                              : "${product.discountPercentage.toStringAsFixed(0)}% OFF",
                          style: AppFonts.poppins(
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          "₹${product.price.toStringAsFixed(0)}",
                          style: AppFonts.cinzel(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppColors.brand(context),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (product.originalPrice > product.price)
                          Text(
                            "₹${product.originalPrice.toStringAsFixed(0)}",
                            style: AppFonts.cinzel(
                              fontSize: 11,
                              color: Colors.grey,
                              decoration: TextDecoration.lineThrough,
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
      ),
    );
  }

  // =========================================================================
  // 6. INTERACTIVE MAISON DISCOUNT CALCULATOR
  // =========================================================================
  Widget buildDiscountCalculatorCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(1.2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            AppColors.gold.withValues(alpha: 0.45),
            AppColors.gold.withValues(alpha: 0.08),
            Colors.transparent,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF141418) : Colors.white,
          borderRadius: BorderRadius.circular(23),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.gold.withValues(alpha: 0.12),
                  ),
                  child: const Icon(Icons.calculate_outlined, color: AppColors.gold, size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "DISCOUNT CALCULATOR",
                      style: AppFonts.poppins(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.4,
                        color: AppColors.gold,
                      ),
                    ),
                    Text(
                      "Simulate Vault Privilege Savings",
                      style: AppFonts.cinzel(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: calcAmountController,
              keyboardType: TextInputType.number,
              style: AppFonts.poppins(fontSize: 14),
              onChanged: (_) => _recalculateSimulation(),
              decoration: InputDecoration(
                labelText: "Simulated Cart Order Valuation (₹)",
                prefixIcon: const Icon(Icons.currency_rupee, color: AppColors.gold, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 12),
            // Coupon Selector Pills
            SizedBox(
              height: 34,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: offers.length,
                itemBuilder: (context, idx) {
                  final off = offers[idx];
                  final isSel = selectedCalcCoupon == off.code;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        setState(() {
                          selectedCalcCoupon = off.code;
                        });
                        _recalculateSimulation();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSel ? AppColors.gold : (isDark ? const Color(0xFF1F1F26) : const Color(0xFFF1EEE8)),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSel ? AppColors.gold : (isDark ? Colors.white12 : Colors.black12),
                          ),
                        ),
                        child: Text(
                          off.code,
                          style: AppFonts.poppins(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: isSel ? Colors.black : (isDark ? Colors.white70 : Colors.black87),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 24),
            // Simulation Results
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Privilege Savings:", style: AppFonts.poppins(fontSize: 12, color: Colors.grey)),
                Text(
                  "- ₹${simulatedDiscount.toStringAsFixed(0)}",
                  style: AppFonts.cinzel(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF2E7D32),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Net Payable Amount:", style: AppFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold)),
                Text(
                  "₹${simulatedFinalAmount.toStringAsFixed(0)}",
                  style: AppFonts.cinzel(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand(context),
                  ),
                ),
              ],
            ),
            if (calcMessage.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                calcMessage,
                style: AppFonts.poppins(
                  fontSize: 11,
                  color: simulatedDiscount > 0 ? const Color(0xFF2E7D32) : Colors.orangeAccent,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void showTermsModal(OfferModel offer) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF16161C) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.3), width: 0.8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Terms & Conditions",
                    style: AppFonts.cinzel(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                "Privilege Code: ${offer.code}",
                style: AppFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.gold),
              ),
              const Divider(height: 20),
              ...offer.terms.map((term) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("• ", style: TextStyle(color: AppColors.gold, fontSize: 16)),
                        Expanded(
                          child: Text(
                            term,
                            style: AppFonts.poppins(fontSize: 12, height: 1.4, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget buildErrorView(bool isDark) {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.withValues(alpha: 0.1),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.redAccent),
            ),
            const SizedBox(height: 18),
            Text(
              "Privilege Vault Connection Error",
              textAlign: TextAlign.center,
              style: AppFonts.cinzel(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: AppFonts.poppins(fontSize: 12.5, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(160, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: loadOffersData,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(
                "RETRY",
                style: AppFonts.poppins(fontWeight: FontWeight.bold, letterSpacing: 1.1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
