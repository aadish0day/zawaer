import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/product_model.dart';
import '../services/api_service.dart';
import '../utils/colors.dart';
import '../utils/text_styles.dart';
import 'cart_screen.dart';
import 'offers_screen.dart';
import 'product_details_screen.dart';
import 'wishlist_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  String selectedCategory = "All";
  bool isLoadingProducts = true;
  List<Product> apiProducts = [];
  Set<String> wishlistedIds = {};
  final Set<String> _togglingWishlistIds = {};
  final TextEditingController searchController = TextEditingController();
  final PageController _heroPageController = PageController();
  int _currentHeroPage = 0;
  Timer? _heroTimer;

  final List<Map<String, String>> heroBanners = [
    {
      "eyebrow": "THE 2026 HERITAGE COLLECTION",
      "title": "Solitaire & Haute Joaillerie",
      "subtitle": "Certified VVS1 Natural Diamonds in 18K Solid Gold",
      "image": "assets/images/necklace.jpg",
      "tag": "EXQUISITE",
    },
    {
      "eyebrow": "ARTISANAL ROYAL WEDDING",
      "title": "Imperial Bridal Masterpieces",
      "subtitle": "Intricate Temple & Polki Kundan Sets",
      "image": "assets/images/ring.png",
      "tag": "LIMITED",
    },
    {
      "eyebrow": "CONTEMPORARY LUXURY",
      "title": "Italian Chains & Diamond Bands",
      "subtitle": "Precision-Engineered Everyday Opulence",
      "image": "assets/images/bracelet.png",
      "tag": "TRENDING",
    },
  ];

  final List<Map<String, dynamic>> categoryMetadata = [
    {"name": "All", "icon": Icons.auto_awesome_outlined},
    {"name": "Ring", "icon": Icons.diamond_outlined},
    {"name": "Necklace", "icon": Icons.circle_outlined},
    {"name": "Chain", "icon": Icons.link_rounded},
    {"name": "Bracelet", "icon": Icons.watch_outlined},
    {"name": "Earrings", "icon": Icons.grain_rounded},
  ];

  @override
  void initState() {
    super.initState();
    loadProducts();
    loadWishlistState();
    _startHeroAutoScroll();
  }

  @override
  void dispose() {
    _heroTimer?.cancel();
    _heroPageController.dispose();
    searchController.dispose();
    super.dispose();
  }

  void _startHeroAutoScroll() {
    _heroTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_heroPageController.hasClients) {
        final nextPage = (_currentHeroPage + 1) % heroBanners.length;
        _heroPageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  // Bumped per request; a response whose number is no longer current is
  // stale (a newer refresh started) and is dropped.
  int _productsRequestSeq = 0;
  int _wishlistRequestSeq = 0;
  int _wishlistFetchesInFlight = 0;

  Future<void> loadProducts() async {
    // Can be called from a SnackBar's Retry after this screen is gone
    if (!mounted) return;
    final int seq = ++_productsRequestSeq;
    setState(() {
      isLoadingProducts = true;
    });

    // The API is paginated: walk every page (capped so a bad `pages` value
    // can't loop forever). Keyed by id so an item shifting between pages
    // mid-walk isn't shown twice.
    final Map<String, Product> byId = {};
    Map<String, dynamic> result = const {};
    for (int page = 1; page <= 20; page++) {
      result = await ApiService.getProducts(page: page, limit: 100);
      if (seq != _productsRequestSeq) return;
      if (result["success"] != true) break;
      for (final p in (result["products"] ?? []) as List) {
        final product = Product.fromJson(p as Map<String, dynamic>);
        byId.putIfAbsent(product.id, () => product);
      }
      final int pages = (result["pages"] as num?)?.toInt() ?? page;
      if (page >= pages) break;
    }

    if (!mounted || seq != _productsRequestSeq) return;

    final bool failed = result["success"] != true;
    setState(() {
      // On failure keep whatever we have rather than blanking the catalog.
      if (!failed || byId.isNotEmpty) apiProducts = byId.values.toList();
      isLoadingProducts = false;
    });

    if (failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
          content: Text(
            byId.isEmpty
                ? (result["message"]?.toString() ?? "Could not load the collection")
                : "Some products could not be loaded. The collection may be incomplete.",
            style: AppFonts.poppins(fontSize: 12.5, color: Colors.white),
          ),
          action: SnackBarAction(
            label: "RETRY",
            textColor: Colors.white,
            onPressed: loadProducts,
          ),
        ),
      );
    }
  }

  Future<void> loadWishlistState() async {
    final int seq = ++_wishlistRequestSeq;
    final Map<String, dynamic> result;
    _wishlistFetchesInFlight++;
    try {
      result = await ApiService.getWishlist();
    } finally {
      _wishlistFetchesInFlight--;
    }
    if (!mounted || seq != _wishlistRequestSeq) return;
    if (result["statusCode"] == 401) {
      // Signed out: clear stale hearts.
      setState(() => wishlistedIds = {});
      return;
    }
    if (result["success"] != true) return;

    final dynamic rawWish = result["wishlist"];
    final List items = (rawWish?["items"] ?? []) as List;

    setState(() {
      wishlistedIds = items
          .map((i) => i["productId"]?.toString() ?? "")
          .where((id) => id.isNotEmpty)
          .toSet();
    });
  }

  Future<void> toggleWishlist(Product product) async {
    final token = await ApiService.getToken();
    if (token.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1E1E24),
          content: Text(
            "Please sign in to manage your wishlist",
            style: AppFonts.poppins(fontSize: 12.5, color: Colors.white),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    if (!_togglingWishlistIds.add(product.id)) return;
    HapticFeedback.lightImpact();
    final isWishlisted = wishlistedIds.contains(product.id);
    // Invalidate any in-flight wishlist GET so it cannot overwrite this tap;
    // if one was dropped, refetch once the tap settles.
    final bool droppedFetch = _wishlistFetchesInFlight > 0;
    _wishlistRequestSeq++;

    setState(() {
      if (isWishlisted) {
        wishlistedIds.remove(product.id);
      } else {
        wishlistedIds.add(product.id);
      }
    });

    final Map<String, dynamic> res;
    try {
      res = isWishlisted
          ? await ApiService.removeFromWishlist(product.id)
          : await ApiService.addToWishlist(product.id);
    } finally {
      _togglingWishlistIds.remove(product.id);
    }
    if (droppedFetch && mounted) loadWishlistState();

    if (res["success"] != true) {
      if (!mounted) return;
      setState(() {
        if (isWishlisted) {
          wishlistedIds.add(product.id);
        } else {
          wishlistedIds.remove(product.id);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
          content: Text(
            res["message"]?.toString() ?? "Failed to update wishlist",
            style: AppFonts.poppins(fontSize: 12.5, color: Colors.white),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  List<Product> get allProducts => apiProducts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final filteredProducts = allProducts.where((product) {
      final matchesCategory = selectedCategory == "All" ||
          product.category.toLowerCase() == selectedCategory.toLowerCase();
      final matchesSearch = product.name
              .toLowerCase()
              .contains(searchController.text.toLowerCase()) ||
          product.category
              .toLowerCase()
              .contains(searchController.text.toLowerCase());
      return matchesCategory && matchesSearch;
    }).toList();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0C0C0E) : const Color(0xFFFAF8F5),
      appBar: buildMaisonAppBar(isDark),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([loadProducts(), loadWishlistState()]);
        },
        color: AppColors.gold,
        backgroundColor: isDark ? const Color(0xFF1C1C22) : Colors.white,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  buildLuxurySearchBar(isDark),
                  const SizedBox(height: 16),
                  buildHeroShowcase(isDark),
                  const SizedBox(height: 20),
                  buildTrustPillarsStrip(isDark),
                  const SizedBox(height: 24),
                  buildCategorySection(isDark),
                  const SizedBox(height: 18),
                  buildCollectionHeader(filteredProducts.length, isDark),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            isLoadingProducts && apiProducts.isEmpty
                ? SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: buildShimmerProductGrid(isDark),
                  )
                : filteredProducts.isEmpty
                    ? SliverToBoxAdapter(
                        child: buildEmptyCollectionState(isDark),
                      )
                    : SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 16,
                            childAspectRatio: 0.58,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final product = filteredProducts[index];
                              return buildLuxuryProductCard(product, isDark);
                            },
                            childCount: filteredProducts.length,
                          ),
                        ),
                      ),
            SliverToBoxAdapter(
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  buildHauteConciergeBanner(isDark),
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // 1. MAISON APP BAR
  // =========================================================================
  PreferredSizeWidget buildMaisonAppBar(bool isDark) {
    return AppBar(
      backgroundColor: isDark ? const Color(0xFF0C0C0E) : const Color(0xFFFAF8F5),
      elevation: 0,
      centerTitle: true,
      leading: Padding(
        padding: const EdgeInsets.all(10),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.35), width: 0.8),
            color: isDark ? const Color(0xFF18181D) : Colors.white,
          ),
          child: const Icon(Icons.diamond_outlined, size: 16, color: AppColors.gold),
        ),
      ),
      title: Column(
        children: [
          Text(
            "ZAWER",
            style: AppFonts.cinzel(
              fontSize: 19,
              letterSpacing: 4.5,
              fontWeight: FontWeight.bold,
              color: AppColors.brand(context),
            ),
          ),
          Text(
            "HAUTE JOAILLERIE",
            style: AppFonts.poppins(
              fontSize: 8.5,
              letterSpacing: 2.2,
              fontWeight: FontWeight.w600,
              color: AppColors.gold,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.discount_outlined, size: 21, color: AppColors.gold),
          tooltip: "Privilege Offers",
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OffersScreen()),
            );
          },
        ),
        IconButton(
          icon: Icon(
            wishlistedIds.isNotEmpty ? Icons.favorite : Icons.favorite_border_rounded,
            size: 21,
            color: wishlistedIds.isNotEmpty ? Colors.redAccent : null,
          ),
          tooltip: "Wishlist",
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WishlistScreen()),
            ).then((_) => loadWishlistState());
          },
        ),
        IconButton(
          icon: const Icon(Icons.shopping_bag_outlined, size: 21),
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
  // 2. LUXURY SEARCH BAR
  // =========================================================================
  Widget buildLuxurySearchBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF15151A) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.gold.withValues(alpha: isDark ? 0.25 : 0.2),
            width: 0.9,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TextField(
          controller: searchController,
          onChanged: (_) => setState(() {}),
          style: AppFonts.poppins(fontSize: 13.5),
          decoration: InputDecoration(
            hintText: "Search Solitaires, Chokers, Kada, 18K Gold...",
            hintStyle: AppFonts.poppins(
              fontSize: 12.5,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.gold),
            suffixIcon: searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      searchController.clear();
                      setState(() {});
                    },
                  )
                : null,
            contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // 3. EDITORIAL HERO SHOWCASE CAROUSEL
  // =========================================================================
  Widget buildHeroShowcase(bool isDark) {
    return Column(
      children: [
        SizedBox(
          height: 185,
          child: PageView.builder(
            controller: _heroPageController,
            onPageChanged: (idx) {
              setState(() {
                _currentHeroPage = idx;
              });
            },
            itemCount: heroBanners.length,
            itemBuilder: (context, index) {
              final banner = heroBanners[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(1.2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(
                      colors: [
                        AppColors.gold.withValues(alpha: 0.5),
                        AppColors.gold.withValues(alpha: 0.1),
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
                        image: AssetImage(banner["image"]!),
                        fit: BoxFit.cover,
                        colorFilter: ColorFilter.mode(
                          Colors.black.withValues(alpha: 0.58),
                          BlendMode.darken,
                        ),
                      ),
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
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
                            banner["eyebrow"]!,
                            style: AppFonts.poppins(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.6,
                              color: AppColors.gold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          banner["title"]!,
                          style: AppFonts.cinzel(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          banner["subtitle"]!,
                          style: AppFonts.poppins(
                            fontSize: 11.5,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(heroBanners.length, (idx) {
            final isCurrent = idx == _currentHeroPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: isCurrent ? 22 : 6,
              height: 5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: isCurrent
                    ? AppColors.gold
                    : (isDark ? Colors.white24 : Colors.black12),
              ),
            );
          }),
        ),
      ],
    );
  }

  // =========================================================================
  // 4. MAISON TRUST PILLARS STRIP
  // =========================================================================
  Widget buildTrustPillarsStrip(bool isDark) {
    final pillars = [
      {"icon": Icons.verified_outlined, "title": "IGI Certified", "sub": "100% Natural"},
      {"icon": Icons.workspace_premium_outlined, "title": "BIS 916", "sub": "Hallmarked"},
      {"icon": Icons.shield_outlined, "title": "Armored Transit", "sub": "100% Insured"},
      {"icon": Icons.cached_rounded, "title": "Lifetime Buyback", "sub": "Best Value"},
    ];

    return SizedBox(
      height: 62,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: pillars.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, idx) {
          final p = pillars[idx];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF15151A) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(p["icon"] as IconData, size: 14, color: AppColors.gold),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      p["title"] as String,
                      style: AppFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      p["sub"] as String,
                      style: AppFonts.poppins(
                        fontSize: 9.5,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // =========================================================================
  // 5. CURATED CATEGORY SELECTOR
  // =========================================================================
  Widget buildCategorySection(bool isDark) {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: categoryMetadata.length,
        itemBuilder: (context, index) {
          final cat = categoryMetadata[index];
          final name = cat["name"] as String;
          final icon = cat["icon"] as IconData;
          final isSelected = selectedCategory.toLowerCase() == name.toLowerCase();

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  selectedCategory = name;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.gold
                      : (isDark ? const Color(0xFF16161C) : Colors.white),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.gold
                        : (isDark ? Colors.white12 : Colors.black12),
                    width: isSelected ? 1.2 : 0.8,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppColors.gold.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 14,
                      color: isSelected ? Colors.black : AppColors.gold,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      name,
                      style: AppFonts.poppins(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        color: isSelected
                            ? Colors.black
                            : (isDark ? Colors.white : AppColors.black),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // =========================================================================
  // 6. COLLECTION HEADER
  // =========================================================================
  Widget buildCollectionHeader(int count, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                selectedCategory == "All" ? "Masterpiece Catalog" : "$selectedCategory Collection",
                style: AppFonts.cinzel(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              "$count PIECES",
              style: AppFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
                color: AppColors.gold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 7. AWWWARDS-TIER LUXURY PRODUCT CARD (Double-Bezel Architecture)
  // =========================================================================
  Widget buildLuxuryProductCard(Product product, bool isDark) {
    final isWishlisted = wishlistedIds.contains(product.id);

    return Container(
      // Outer Bezel
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
        // Inner Core
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF141418) : Colors.white,
          borderRadius: BorderRadius.circular(21),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(21),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProductDetailsScreen(product: product),
              ),
            ).then((_) => loadWishlistState());
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Image with Overlay Badges
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
                              product.images.isNotEmpty
                                  ? product.images.first
                                  : "assets/images/ring.png",
                            ),
                          ),
                          fit: BoxFit.cover,
                          onError: (exception, stackTrace) {},
                        ),
                      ),
                    ),
                    // Category Tag Top Left
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.gold.withValues(alpha: 0.4),
                            width: 0.6,
                          ),
                        ),
                        child: Text(
                          product.category.toUpperCase(),
                          style: AppFonts.poppins(
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.9,
                            color: AppColors.gold,
                          ),
                        ),
                      ),
                    ),
                    // Wishlist Heart Button Top Right
                    Positioned(
                      top: 8,
                      right: 8,
                      child: InkWell(
                        onTap: () => toggleWishlist(product),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDark ? const Color(0xDD121216) : const Color(0xEEFFFFFF),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: Icon(
                            isWishlisted ? Icons.favorite : Icons.favorite_border_rounded,
                            size: 15,
                            color: isWishlisted ? Colors.redAccent : (isDark ? Colors.white70 : Colors.black54),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Product Details Bottom
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 12),
                        const SizedBox(width: 3),
                        Text(
                          product.rating.toStringAsFixed(1),
                          style: AppFonts.poppins(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          "• Certified",
                          style: AppFonts.poppins(
                            fontSize: 10,
                            color: AppColors.gold,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "₹${product.price.toStringAsFixed(0)}",
                          style: AppFonts.cinzel(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppColors.brand(context),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: AppColors.brand(context).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 11,
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
      ),
    );
  }

  // =========================================================================
  // 8. HAUTE CONCIERGE BANNER
  // =========================================================================
  Widget buildHauteConciergeBanner(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF15151B) : const Color(0xFFF6F3EC),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: AppColors.gold.withValues(alpha: 0.3),
            width: 0.9,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.gold.withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.support_agent_rounded, color: AppColors.gold, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Private Concierge & Custom Vault",
                    style: AppFonts.cinzel(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    "Book a 1-on-1 certified gemologist appointment for custom bridal engravings.",
                    style: AppFonts.poppins(
                      fontSize: 11,
                      height: 1.4,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
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
  // SHIMMER SKELETON LOADING GRID
  // =========================================================================
  Widget buildShimmerProductGrid(bool isDark) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 16,
        childAspectRatio: 0.58,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          return Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF15151A) : Colors.white,
              borderRadius: BorderRadius.circular(21),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1F1F26) : const Color(0xFFEDE8E0),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(21)),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 50,
                        height: 10,
                        color: isDark ? Colors.white10 : Colors.black12,
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        height: 14,
                        color: isDark ? Colors.white10 : Colors.black12,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 70,
                        height: 14,
                        color: isDark ? Colors.white10 : Colors.black12,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
        childCount: 4,
      ),
    );
  }

  Widget buildEmptyCollectionState(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.diamond_outlined,
            size: 52,
            color: AppColors.gold.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 14),
          Text(
            "No Masterpieces Found",
            style: AppFonts.cinzel(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            "We could not find jewellery matching your filter in the vault.",
            textAlign: TextAlign.center,
            style: AppFonts.poppins(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.gold,
              side: BorderSide(color: AppColors.gold.withValues(alpha: 0.4)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () {
              searchController.clear();
              setState(() {
                selectedCategory = "All";
              });
              loadProducts();
            },
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text("Reset Filters"),
          ),
        ],
      ),
    );
  }
}