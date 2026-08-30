import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/order_model.dart';
import '../services/api_service.dart';
import '../utils/colors.dart';
import '../utils/text_styles.dart';

class OrderTrackingScreen extends StatefulWidget {
  final String orderId;

  const OrderTrackingScreen({
    super.key,
    required this.orderId,
  });

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen>
    with SingleTickerProviderStateMixin {
  bool isLoading = true;
  String? errorMessage;
  OrderTrackingModel? trackingData;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final List<String> allStages = [
    "Order Placed",
    "Order Confirmed",
    "Processing",
    "Shipped",
    "Out for Delivery",
    "Delivered",
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    loadTrackingData();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> loadTrackingData() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    final result = await ApiService.getOrderTracking(widget.orderId);

    if (!mounted) return;

    if (result["success"] == true && result["tracking"] != null) {
      setState(() {
        trackingData = OrderTrackingModel.fromJson(
          result["tracking"] as Map<String, dynamic>,
        );
        isLoading = false;
      });
    } else {
      setState(() {
        isLoading = false;
        errorMessage = result["message"]?.toString() ?? "Failed to load tracking information";
      });
    }
  }

  Future<void> advanceToStatus(String status) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text("Updating status to $status in MongoDB..."),
        duration: const Duration(seconds: 1),
      ),
    );

    final result = await ApiService.updateOrderStatus(
      orderId: widget.orderId,
      status: status,
    );

    if (!mounted) return;

    if (result["success"] == true) {
      await loadTrackingData();
      messenger.showSnackBar(
        SnackBar(
          content: Text("Order is now: $status"),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(result["message"]?.toString() ?? "Failed to update status"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  int get currentStageIndex {
    if (trackingData == null) return 0;
    final normalized = trackingData!.currentStatus == "Placed"
        ? "Order Placed"
        : trackingData!.currentStatus;
    final idx = allStages.indexWhere(
      (s) => s.toLowerCase() == normalized.toLowerCase(),
    );
    return idx != -1 ? idx : 0;
  }

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
          "Order Tracking",
          style: AppFonts.cinzel(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh Tracking",
            onPressed: loadTrackingData,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? buildErrorView()
              : trackingData == null
                  ? buildEmptyView()
                  : RefreshIndicator(
                      onRefresh: loadTrackingData,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            buildHeroStatusCard(),
                            const SizedBox(height: 16),
                            buildAiInsightCard(),
                            const SizedBox(height: 20),
                            buildTimelineSection(),
                            const SizedBox(height: 20),
                            buildCourierSecurityCard(),
                            const SizedBox(height: 20),
                            buildDeliveryAddressCard(),
                            const SizedBox(height: 20),
                            buildOrderItemsCard(),
                            const SizedBox(height: 24),
                            buildSimulationControls(),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ),
    );
  }

  Widget buildHeroStatusCard() {
    final theme = Theme.of(context);
    final isDelivered = trackingData!.currentStatus == "Delivered";
    final isCancelled = trackingData!.currentStatus == "Cancelled";

    Color statusColor = AppColors.gold;
    if (isDelivered) statusColor = Colors.green;
    if (isCancelled) statusColor = Colors.red;

    final progress = ((currentStageIndex + 1) / allStages.length).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(
          color: AppColors.gold.withValues(alpha: 0.25),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "TRACKING NUMBER",
                    style: AppFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        trackingData!.trackingNumber,
                        style: AppFonts.cinzel(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.brand(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: trackingData!.trackingNumber),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Tracking number copied to clipboard"),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        child: Icon(
                          Icons.copy_rounded,
                          size: 16,
                          color: AppColors.brand(context),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              ScaleTransition(
                scale: _pulseAnimation,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        trackingData!.currentStatus,
                        style: AppFonts.poppins(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.gold),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_month_outlined, size: 18, color: AppColors.gold),
                  const SizedBox(width: 6),
                  Text(
                    trackingData!.estimatedDelivery != null
                        ? "Est. Delivery: ${DateFormat('dd MMM yyyy').format(trackingData!.estimatedDelivery!)}"
                        : "Est. Delivery: 3-5 Business Days",
                    style: AppFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Icon(Icons.location_on_outlined, size: 18, color: AppColors.primary),
                  const SizedBox(width: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 130),
                    child: Text(
                      trackingData!.currentLocation,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.poppins(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildAiInsightCard() {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.12),
            AppColors.gold.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.gold.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 20,
              color: Color(0xFFD4AF37),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      "AI Delivery Concierge",
                      style: AppFonts.cinzel(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brand(context),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        "LIVE",
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  trackingData!.aiDeliveryInsight,
                  style: AppFonts.poppins(
                    fontSize: 12.5,
                    height: 1.45,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildTimelineSection() {
    final theme = Theme.of(context);
    final timeline = trackingData!.timeline;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timeline, color: AppColors.gold, size: 22),
              const SizedBox(width: 8),
              Text(
                "Tracking Milestones",
                style: AppFonts.cinzel(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: allStages.length,
            itemBuilder: (context, index) {
              final stageName = allStages[index];
              final stepData = timeline.firstWhere(
                (t) => t.status.toLowerCase() == stageName.toLowerCase(),
                orElse: () => TrackingStep(
                  status: stageName,
                  title: stageName,
                  description: "",
                  location: "",
                  isCompleted: index <= currentStageIndex,
                ),
              );

              final isCompleted = index <= currentStageIndex;
              final isCurrent = index == currentStageIndex;
              final isLast = index == allStages.length - 1;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      isCurrent
                          ? ScaleTransition(
                              scale: _pulseAnimation,
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.gold,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.gold.withValues(alpha: 0.5),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.diamond,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isCompleted
                                    ? AppColors.primary
                                    : theme.colorScheme.surfaceContainerHighest,
                                border: Border.all(
                                  color: isCompleted
                                      ? AppColors.gold
                                      : Colors.grey.withValues(alpha: 0.4),
                                  width: 1.5,
                                ),
                              ),
                              child: Icon(
                                isCompleted ? Icons.check : Icons.circle,
                                size: isCompleted ? 14 : 8,
                                color: isCompleted
                                    ? Colors.white
                                    : Colors.grey.withValues(alpha: 0.6),
                              ),
                            ),
                      if (!isLast)
                        Container(
                          width: 2,
                          height: 48,
                          color: isCompleted
                              ? AppColors.gold
                              : theme.colorScheme.surfaceContainerHighest,
                        ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                stepData.title.isNotEmpty ? stepData.title : stageName,
                                style: AppFonts.poppins(
                                  fontSize: 14,
                                  fontWeight:
                                      isCurrent ? FontWeight.bold : FontWeight.w600,
                                  color: isCompleted
                                      ? theme.colorScheme.onSurface
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              if (stepData.timestamp != null && isCompleted)
                                Text(
                                  DateFormat("hh:mm a, dd MMM").format(stepData.timestamp!),
                                  style: AppFonts.poppins(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                          if (stepData.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              stepData.description,
                              style: AppFonts.poppins(
                                fontSize: 12,
                                color: isCompleted
                                    ? theme.colorScheme.onSurfaceVariant
                                    : Colors.grey,
                              ),
                            ),
                          ],
                          if (stepData.location.isNotEmpty && isCompleted) ...[
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                const Icon(Icons.pin_drop, size: 12, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(
                                  stepData.location,
                                  style: AppFonts.poppins(
                                    fontSize: 11,
                                    color: Colors.grey,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget buildCourierSecurityCard() {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_outlined, color: Colors.green, size: 22),
              const SizedBox(width: 8),
              Text(
                "Secure Armored Logistics",
                style: AppFonts.cinzel(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Carrier Partner:",
                style: AppFonts.poppins(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
              ),
              Text(
                trackingData!.courierPartner,
                style: AppFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Transit Insurance:",
                style: AppFonts.poppins(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "100% Insured Valuables",
                  style: AppFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.green,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildDeliveryAddressCard() {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on, color: AppColors.brand(context), size: 22),
              const SizedBox(width: 8),
              Text(
                "Delivery Address",
                style: AppFonts.cinzel(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            trackingData!.customerName,
            style: AppFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            trackingData!.phone,
            style: AppFonts.poppins(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            trackingData!.address,
            style: AppFonts.poppins(fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget buildOrderItemsCard() {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.diamond_outlined, color: AppColors.gold, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    "Order Items (${trackingData!.items.length})",
                    style: AppFonts.cinzel(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Text(
                "₹${trackingData!.totalAmount.toStringAsFixed(0)}",
                style: AppFonts.cinzel(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.brand(context),
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          ...trackingData!.items.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: item.image.isNotEmpty
                        ? Image.asset(
                            item.image,
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              width: 50,
                              height: 50,
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.diamond, size: 24),
                            ),
                          )
                        : Container(
                            width: 50,
                            height: 50,
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.diamond, size: 24),
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: AppFonts.poppins(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "Qty: ${item.quantity} × ₹${item.price.toStringAsFixed(0)}",
                          style: AppFonts.poppins(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    "₹${(item.price * item.quantity).toStringAsFixed(0)}",
                    style: AppFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.gold,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget buildSimulationControls() {
    final nextIndex = currentStageIndex + 1;
    final hasNext = nextIndex < allStages.length;
    final nextStatus = hasNext ? allStages[nextIndex] : "Completed";

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.developer_mode, size: 18, color: Colors.orange),
              const SizedBox(width: 6),
              Text(
                "Live Tracking Simulation",
                style: AppFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "Test live MongoDB updates by advancing order through the 6 stages:",
            style: AppFonts.poppins(fontSize: 11.5, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: allStages.map((stage) {
              final isSelected = trackingData!.currentStatus.toLowerCase() == stage.toLowerCase();
              return ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSelected ? AppColors.gold : Theme.of(context).colorScheme.surface,
                  foregroundColor: isSelected ? Colors.black : Theme.of(context).colorScheme.onSurface,
                  elevation: 0,
                  side: BorderSide(
                    color: isSelected ? AppColors.gold : Colors.grey.withValues(alpha: 0.4),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => advanceToStatus(stage),
                child: Text(
                  stage,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              );
            }).toList(),
          ),
          if (hasNext) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => advanceToStatus(nextStatus),
                icon: const Icon(Icons.fast_forward, size: 18),
                label: Text(
                  "Advance to '$nextStatus'",
                  style: AppFonts.cinzel(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.red),
            const SizedBox(height: 12),
            Text(
              "Unable to load order tracking",
              style: AppFonts.cinzel(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage ?? "",
              textAlign: TextAlign.center,
              style: AppFonts.poppins(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: loadTrackingData,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text("Try Again"),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildEmptyView() {
    return Center(
      child: Text(
        "No tracking information found.",
        style: AppFonts.poppins(),
      ),
    );
  }
}
