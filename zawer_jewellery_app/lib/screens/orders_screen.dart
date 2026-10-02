import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../utils/colors.dart';
import '../utils/text_styles.dart';
import 'order_tracking_screen.dart';

// Same as derivedTrackingNumber on the server: last 6 chars of _id, uppercased.
String _derivedTrackingNumber(String? id) {
  final String s = id ?? "000000";
  return "ZWR-${(s.length > 6 ? s.substring(s.length - 6) : s).toUpperCase()}";
}

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  bool isLoading = true;
  String errorMessage = "";
  List<Map<String, dynamic>> orders = [];
  final TextEditingController searchController = TextEditingController();
  String searchQuery = "";
  String selectedFilter = "All";

  final List<String> filterTabs = ["All", "In Transit", "Delivered"];

  @override
  void initState() {
    super.initState();
    loadOrders();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  // =====================================================
  // LOAD ORDERS FROM BACKEND (MongoDB)
  // =====================================================
  Future<void> loadOrders() async {
    // Called from route-pop callbacks, which may fire after dispose.
    if (!mounted) return;
    setState(() {
      isLoading = true;
      errorMessage = "";
    });

    try {
      final result = await ApiService.getOrders();

      if (!mounted) return;

      if (result["success"] == true) {
        final List orderList = (result["orders"] ?? []) as List;
        setState(() {
          orders = orderList
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          isLoading = false;
          errorMessage = "";
        });
      } else {
        setState(() {
          isLoading = false;
          errorMessage = result["message"]?.toString() ?? "Failed to load orders";
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        errorMessage = "Unable to connect to Maison Vault server";
      });
    }
  }

  void openTracking(String identifier) {
    if (identifier.trim().isEmpty) return;
    HapticFeedback.mediumImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderTrackingScreen(orderId: identifier.trim()),
      ),
    ).then((_) => loadOrders());
  }

  Color getStatusColor(String status) {
    final lower = status.toLowerCase();
    if (lower.contains("delivered")) {
      return const Color(0xFF2E7D32);
    } else if (lower.contains("out for delivery")) {
      return const Color(0xFFE65100);
    } else if (lower.contains("shipped")) {
      return const Color(0xFF1565C0);
    } else if (lower.contains("processing")) {
      return const Color(0xFF6A1B9A);
    } else if (lower.contains("confirmed")) {
      return const Color(0xFF00695C);
    } else if (lower.contains("placed")) {
      return const Color(0xFFD4AF37);
    } else if (lower.contains("cancel")) {
      return const Color(0xFFC62828);
    }
    return AppColors.gold;
  }

  List<Map<String, dynamic>> get filteredOrders {
    List<Map<String, dynamic>> list = orders;

    // Filter by tab
    if (selectedFilter == "In Transit") {
      list = list.where((o) {
        final st = (o["status"] ?? "").toString().toLowerCase();
        return !st.contains("delivered") && !st.contains("cancel");
      }).toList();
    } else if (selectedFilter == "Delivered") {
      list = list.where((o) {
        final st = (o["status"] ?? "").toString().toLowerCase();
        return st.contains("delivered");
      }).toList();
    }

    // Filter by search query
    if (searchQuery.trim().isEmpty) return list;
    final q = searchQuery.toLowerCase().trim();

    return list.where((order) {
      final id = order["_id"]?.toString().toLowerCase() ?? "";
      final trackingNum = order["trackingNumber"]?.toString().toLowerCase() ?? "";
      final status = order["status"]?.toString().toLowerCase() ?? "";
      final custName = order["customerName"]?.toString().toLowerCase() ?? "";
      return id.contains(q) || trackingNum.contains(q) || status.contains(q) || custName.contains(q);
    }).toList();
  }

  int get inTransitCount {
    return orders.where((o) {
      final st = (o["status"] ?? "").toString().toLowerCase();
      return !st.contains("delivered") && !st.contains("cancel");
    }).length;
  }

  int get deliveredCount {
    return orders.where((o) {
      final st = (o["status"] ?? "").toString().toLowerCase();
      return st.contains("delivered");
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0C0C0E) : const Color(0xFFFAF8F5),
      appBar: buildMaisonAppBar(isDark),
      body: RefreshIndicator(
        onRefresh: loadOrders,
        color: AppColors.gold,
        backgroundColor: isDark ? const Color(0xFF18181E) : Colors.white,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  buildTrackingSearchBar(isDark),
                  const SizedBox(height: 14),
                  buildTelemetryPills(isDark),
                  const SizedBox(height: 14),
                  buildFilterTabs(isDark),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            isLoading
                ? SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 36,
                            height: 36,
                            child: CircularProgressIndicator(
                              color: AppColors.gold,
                              strokeWidth: 2.2,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            "Syncing Maison Vault Invoices...",
                            style: AppFonts.cinzel(fontSize: 13, color: AppColors.gold),
                          ),
                        ],
                      ),
                    ),
                  )
                : errorMessage.isNotEmpty
                    ? SliverFillRemaining(
                        child: buildErrorView(isDark),
                      )
                    : orders.isEmpty
                        ? SliverFillRemaining(
                            child: buildEmptyView(isDark),
                          )
                        : filteredOrders.isEmpty
                            ? SliverFillRemaining(
                                child: buildNoSearchResultsView(isDark),
                              )
                        : SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  return buildLuxuryOrderCard(filteredOrders[index], isDark);
                                },
                                childCount: filteredOrders.length,
                              ),
                            ),
                          ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 36),
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
            "Acquisitions & Escort",
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
          tooltip: "Refresh Invoices",
          onPressed: loadOrders,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  // =========================================================================
  // 2. FLOATING ARCHITECTURAL TRACKING SEARCH BAR
  // =========================================================================
  Widget buildTrackingSearchBar(bool isDark) {
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
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: searchController,
                onChanged: (val) {
                  setState(() {
                    searchQuery = val;
                  });
                },
                onSubmitted: (val) {
                  if (val.trim().isNotEmpty) {
                    openTracking(val.trim());
                  }
                },
                style: AppFonts.poppins(fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: "Track by ZWR-XXXXXX or Order ID...",
                  hintStyle: AppFonts.poppins(
                    fontSize: 12.5,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                  prefixIcon: const Icon(Icons.qr_code_scanner, size: 20, color: AppColors.gold),
                  suffixIcon: searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            searchController.clear();
                            setState(() {
                              searchQuery = "";
                            });
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
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(68, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  if (searchController.text.trim().isNotEmpty) {
                    openTracking(searchController.text.trim());
                  }
                },
                child: Text(
                  "TRACK",
                  style: AppFonts.cinzel(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
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
  // 3. TELEMETRY PILLS BAR
  // =========================================================================
  Widget buildTelemetryPills(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF141418) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.gold.withValues(alpha: 0.12),
                    ),
                    child: const Icon(Icons.local_shipping_outlined, size: 14, color: AppColors.gold),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "$inTransitCount IN TRANSIT",
                        style: AppFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.9,
                        ),
                      ),
                      Text(
                        "Armored Escort",
                        style: AppFonts.poppins(
                          fontSize: 9,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF141418) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                    ),
                    child: const Icon(Icons.verified_outlined, size: 14, color: Color(0xFF2E7D32)),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "$deliveredCount DELIVERED",
                        style: AppFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.9,
                        ),
                      ),
                      Text(
                        "Vault Acquired",
                        style: AppFonts.poppins(
                          fontSize: 9,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 4. FILTER TABS
  // =========================================================================
  Widget buildFilterTabs(bool isDark) {
    return SizedBox(
      height: 38,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: filterTabs.length,
        itemBuilder: (context, index) {
          final tab = filterTabs[index];
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

  // =========================================================================
  // 5. LUXURY ORDER CARD (Double-Bezel Concentric Architecture)
  // =========================================================================
  Widget buildLuxuryOrderCard(Map<String, dynamic> order, bool isDark) {
    final List items = (order["items"] ?? []) as List;
    final String status = order["status"]?.toString() ?? "Order Placed";
    final String trackingNum = order["trackingNumber"]?.toString() ??
        _derivedTrackingNumber(order["_id"]?.toString());
    final String orderId = order["_id"]?.toString() ?? "";
    final Color statusColor = getStatusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(1.2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [
            AppColors.gold.withValues(alpha: 0.35),
            AppColors.gold.withValues(alpha: 0.06),
            Colors.transparent,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF141418) : Colors.white,
          borderRadius: BorderRadius.circular(21),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Tracking ID & Luxury Status Chip
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      trackingNum,
                      style: AppFonts.cinzel(
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                        letterSpacing: 1.1,
                        color: AppColors.brand(context),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Clipboard.setData(ClipboardData(text: trackingNum));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            behavior: SnackBarBehavior.floating,
                            content: Text("Tracking number copied to clipboard"),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                        ),
                        child: const Icon(Icons.copy_rounded, size: 12, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withValues(alpha: 0.5), width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        status.toUpperCase(),
                        style: AppFonts.poppins(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              "Acquisition date: ${_formatDate(order["createdAt"]?.toString() ?? "")} • BIS 916 Insured",
              style: AppFonts.poppins(
                color: isDark ? Colors.white54 : Colors.black54,
                fontSize: 11,
              ),
            ),
            const Divider(height: 20),
            // Items Gallery
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 52,
                          height: 52,
                          color: isDark ? const Color(0xFF1C1C22) : const Color(0xFFF7F5F0),
                          child: item["image"].toString().isEmpty
                              ? const Icon(Icons.diamond_outlined, size: 20, color: AppColors.gold)
                              : Image.asset(
                                  item["image"],
                                  width: 52,
                                  height: 52,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(Icons.diamond_outlined, size: 20, color: AppColors.gold),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item["name"] ?? "Maison Masterpiece",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppFonts.cinzel(
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Qty: ${item["quantity"]} × ₹${_money(item["price"])}",
                              style: AppFonts.poppins(
                                color: isDark ? Colors.white60 : Colors.black54,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
            const Divider(height: 18),
            // Valuation & Tracking Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "TOTAL VALUATION",
                      style: AppFonts.poppins(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "₹${_money(order["totalAmount"])}",
                      style: AppFonts.cinzel(
                        color: AppColors.brand(context),
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(140, 42),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    openTracking(orderId.isNotEmpty ? orderId : trackingNum);
                  },
                  icon: const Icon(Icons.location_searching_rounded, size: 15, color: Colors.white),
                  label: Text(
                    "TRACK ESCORT",
                    style: AppFonts.cinzel(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      fontSize: 11.5,
                      color: Colors.white,
                    ),
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
  // 6. EMPTY & NO SEARCH VIEWS
  // =========================================================================
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
              child: const Icon(
                Icons.inventory_2_outlined,
                size: 48,
                color: AppColors.gold,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "No Acquisitions Recorded",
              textAlign: TextAlign.center,
              style: AppFonts.cinzel(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "When you acquire jewellery pieces, your authentic certificates and live armored transit updates will be archived here.",
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

  Widget buildNoSearchResultsView(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded, size: 54, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              "No Matching Acquisitions",
              style: AppFonts.cinzel(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              "Could not find '$searchQuery' in your active order list.",
              textAlign: TextAlign.center,
              style: AppFonts.poppins(fontSize: 12.5, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                openTracking(searchQuery);
              },
              icon: const Icon(Icons.location_searching_rounded, size: 16),
              label: Text("Track '$searchQuery' Directly"),
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
              "Unable to Load Acquisitions",
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
              onPressed: loadOrders,
              child: const Text("RETRY CONNECTION"),
            ),
          ],
        ),
      ),
    );
  }

  // Whole rupees, like the other screens. JSON may hold a num or a string.
  String _money(dynamic value) =>
      (num.tryParse(value?.toString() ?? "") ?? 0).toStringAsFixed(0);

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate).toLocal();
      return "${date.day.toString().padLeft(2, '0')}/"
          "${date.month.toString().padLeft(2, '0')}/"
          "${date.year}";
    } catch (_) {
      return isoDate;
    }
  }
}
