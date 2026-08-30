import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/text_styles.dart';
import '../services/api_service.dart';
import '../utils/colors.dart';
import 'order_tracking_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  bool isLoading = true;
  List<Map<String, dynamic>> orders = [];
  final TextEditingController searchController = TextEditingController();
  String searchQuery = "";

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
  // LOAD ORDERS FROM BACKEND
  // =====================================================

  Future<void> loadOrders() async {
    setState(() {
      isLoading = true;
    });

    final result = await ApiService.getOrders();

    if (!mounted) {
      return;
    }

    if (result["success"] == true) {
      final List orderList = (result["orders"] ?? []) as List;

      setState(() {
        orders = orderList.cast<Map<String, dynamic>>().toList();
        isLoading = false;
      });
    } else {
      setState(() {
        isLoading = false;
      });
    }
  }

  void openTracking(String identifier) {
    if (identifier.trim().isEmpty) return;
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
      return Colors.green;
    } else if (lower.contains("out for delivery")) {
      return Colors.orange.shade800;
    } else if (lower.contains("shipped")) {
      return Colors.indigo.shade600;
    } else if (lower.contains("processing")) {
      return Colors.deepPurple;
    } else if (lower.contains("confirmed")) {
      return Colors.teal.shade700;
    } else if (lower.contains("placed")) {
      return const Color(0xFFD4AF37);
    } else if (lower.contains("cancel")) {
      return Colors.red;
    }
    return AppColors.primary;
  }

  List<Map<String, dynamic>> get filteredOrders {
    if (searchQuery.trim().isEmpty) return orders;
    final q = searchQuery.toLowerCase().trim();
    return orders.where((order) {
      final id = order["_id"]?.toString().toLowerCase() ?? "";
      final trackingNum = order["trackingNumber"]?.toString().toLowerCase() ?? "";
      final status = order["status"]?.toString().toLowerCase() ?? "";
      final custName = order["customerName"]?.toString().toLowerCase() ?? "";
      return id.contains(q) || trackingNum.contains(q) || status.contains(q) || custName.contains(q);
    }).toList();
  }

  // =====================================================
  // BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "My Orders",
          style: AppFonts.cinzel(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh",
            onPressed: loadOrders,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                buildTrackingSearchBar(),
                Expanded(
                  child: orders.isEmpty
                      ? buildEmptyView()
                      : filteredOrders.isEmpty
                          ? buildNoSearchResultsView()
                          : buildOrdersView(),
                ),
              ],
            ),
    );
  }

  Widget buildTrackingSearchBar() {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: theme.colorScheme.surface,
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
              decoration: InputDecoration(
                hintText: "Track by Order ID or ZWR-XXXXXX...",
                hintStyle: AppFonts.poppins(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                prefixIcon: const Icon(Icons.search, size: 20),
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
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brand(context),
              foregroundColor: Colors.white,
              minimumSize: const Size(78, 44),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () {
              if (searchController.text.trim().isNotEmpty) {
                openTracking(searchController.text.trim());
              }
            },
            child: const Text(
              "TRACK",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildEmptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: 70,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 15),
            Text(
              "No orders placed yet",
              style: AppFonts.cinzel(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Your placed jewellery orders and live tracking will appear here.",
              textAlign: TextAlign.center,
              style: AppFonts.poppins(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildNoSearchResultsView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 60, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              "No matching orders",
              style: AppFonts.cinzel(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              "Try searching with full Tracking Number (e.g. ZWR-123456) or Order ID.",
              textAlign: TextAlign.center,
              style: AppFonts.poppins(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                openTracking(searchQuery);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: Text("Track '$searchQuery' Directly"),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildOrdersView() {
    return RefreshIndicator(
      onRefresh: loadOrders,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        itemCount: filteredOrders.length,
        itemBuilder: (context, index) {
          return buildOrderCard(filteredOrders[index]);
        },
      ),
    );
  }

  Widget buildOrderCard(Map<String, dynamic> order) {
    final theme = Theme.of(context);
    final List items = (order["items"] ?? []) as List;
    final String status = order["status"]?.toString() ?? "Order Placed";
    final String trackingNum = order["trackingNumber"]?.toString() ??
        "ZWR-${order["_id"]?.toString().substring(0, 6).toUpperCase() ?? "000000"}";
    final String orderId = order["_id"]?.toString() ?? "";
    final Color statusColor = getStatusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: AppColors.gold.withValues(alpha: 0.18),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    trackingNum,
                    style: AppFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppColors.brand(context),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: trackingNum));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Tracking number copied"),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    child: Icon(
                      Icons.copy_rounded,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
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
                      status,
                      style: AppFonts.poppins(
                        color: statusColor,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "Placed on ${_formatDate(order["createdAt"]?.toString() ?? "")}",
            style: AppFonts.poppins(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const Divider(height: 22),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: item["image"].toString().isEmpty
                          ? Container(
                              width: 48,
                              height: 48,
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.diamond_outlined, size: 20),
                            )
                          : Image.asset(
                              item["image"],
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                width: 48,
                                height: 48,
                                color: theme.colorScheme.surfaceContainerHighest,
                                child: const Icon(Icons.diamond_outlined, size: 20),
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item["name"] ?? "",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Qty: ${item["quantity"]} × ₹${item["price"] ?? 0}",
                            style: AppFonts.poppins(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Total Amount",
                style: AppFonts.poppins(fontWeight: FontWeight.w500, fontSize: 13),
              ),
              Text(
                "₹${order["totalAmount"]}",
                style: AppFonts.cinzel(
                  color: AppColors.brand(context),
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                openTracking(orderId.isNotEmpty ? orderId : trackingNum);
              },
              icon: const Icon(Icons.location_searching_rounded, size: 18),
              label: Text(
                "TRACK ORDER LIVE",
                style: AppFonts.cinzel(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      return "${date.day.toString().padLeft(2, '0')}/"
          "${date.month.toString().padLeft(2, '0')}/"
          "${date.year}";
    } catch (_) {
      return isoDate;
    }
  }
}
