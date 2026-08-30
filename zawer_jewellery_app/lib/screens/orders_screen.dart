import 'package:flutter/material.dart';
import '../utils/text_styles.dart';

import '../services/api_service.dart';
import '../utils/colors.dart';
import 'order_tracking_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() =>
      _OrdersScreenState();
}

class _OrdersScreenState
    extends State<OrdersScreen> {

  bool isLoading = true;

  List<Map<String, dynamic>> orders = [];

  @override
  void initState() {
    super.initState();

    loadOrders();
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
      final List orderList =
      (result["orders"] ?? []) as List;

      setState(() {
        orders = orderList
            .cast<Map<String, dynamic>>()
            .toList();

        isLoading = false;
      });
    } else {
      setState(() {
        isLoading = false;
      });
    }
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

          "My Orders",

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
          : orders.isEmpty
          ? buildEmptyView()
          : buildOrdersView(),

    );
  }

  Widget buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [

          Icon(
            Icons.shopping_bag_outlined,
            size: 70,
            color:
            Theme.of(context).colorScheme.onSurfaceVariant,
          ),

          const SizedBox(height: 15),

          Text(
            "No orders yet",
            style: AppFonts.cinzel(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),

        ],
      ),
    );
  }

  Widget buildOrdersView() {
    return RefreshIndicator(
      onRefresh: loadOrders,

      child: ListView.builder(
        padding: const EdgeInsets.all(15),
        itemCount: orders.length,
        itemBuilder: (context, index) {
          return buildOrderCard(orders[index]);
        },
      ),
    );
  }

  Widget buildOrderCard(Map<String, dynamic> order) {

    final List items =
    (order["items"] ?? []) as List;

    final String status =
        order["status"]?.toString() ?? "Placed";

    Color statusColor = AppColors.primary;

    if (status == "Delivered") {
      statusColor = Colors.green;
    } else if (status == "Cancelled") {
      statusColor = Colors.red;
    }

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
            offset: const Offset(0, 5),
          ),

        ],

      ),

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          Row(

            mainAxisAlignment:
            MainAxisAlignment.spaceBetween,

            children: [

              Text(
                "Order #${order["_id"]
                    ?.toString()
                    .substring(0, 8) ?? ""}",
                style: AppFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .12),
                  borderRadius:
                  BorderRadius.circular(12),
                ),
                child: Text(
                  status,
                  style: AppFonts.poppins(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

            ],

          ),

          const SizedBox(height: 6),

          Text(
            "Placed on ${_formatDate(order["createdAt"]?.toString() ?? "")}",
            style: AppFonts.poppins(
              color: Theme.of(context)
                  .colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),

          const Divider(height: 25),

          ...items.map((item) => Padding(
            padding:
            const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [

                ClipRRect(
                  borderRadius:
                  BorderRadius.circular(10),
                  child: item["image"].toString()
                      .isEmpty
                      ? Container(
                    width: 55,
                    height: 55,
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    child: const Icon(
                      Icons.image_not_supported,
                      size: 22,
                    ),
                  )
                      : Image.asset(
                    item["image"],
                    width: 55,
                    height: 55,
                    fit: BoxFit.cover,
                    errorBuilder: (context,
                        error, stackTrace) {
                      return Container(
                        width: 55,
                        height: 55,
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: const Icon(
                          Icons
                              .image_not_supported,
                          size: 22,
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(
                        item["name"] ?? "",
                        maxLines: 1,
                        overflow:
                        TextOverflow.ellipsis,
                        style: AppFonts.poppins(
                          fontWeight:
                          FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        "Qty: ${item["quantity"]}",
                        style: AppFonts.poppins(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

              ],
            ),
          )),

          const Divider(height: 5),

          const SizedBox(height: 10),

          Row(
            mainAxisAlignment:
            MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Total",
                style: AppFonts.poppins(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "₹${order["totalAmount"]}",
                style: AppFonts.cinzel(
                  color: AppColors.brand(context),
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brand(context),
                side: BorderSide(
                  color: AppColors.gold,
                  width: 1.2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                final orderId = order["_id"]?.toString() ?? "";
                if (orderId.isNotEmpty) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OrderTrackingScreen(orderId: orderId),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.location_searching_rounded, size: 18),
              label: Text(
                "TRACK ORDER",
                style: AppFonts.cinzel(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
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
