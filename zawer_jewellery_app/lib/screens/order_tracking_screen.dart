import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  bool isAdmin = false;
  String? errorMessage;
  OrderTrackingModel? trackingData;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _glowAnimation;

  final List<Map<String, dynamic>> stageMetadata = [
    {
      "status": "Order Placed",
      "title": "Order Placed",
      "subtitle": "Vault Registration & Concierge Allocation",
      "icon": Icons.inventory_2_outlined,
      "defaultLocation": "ZAWER Online Hub, Mumbai",
    },
    {
      "status": "Order Confirmed",
      "title": "Order Confirmed",
      "subtitle": "BIS Hallmarking & Authenticity Allocated",
      "icon": Icons.verified_outlined,
      "defaultLocation": "ZAWER Central Verification Center",
    },
    {
      "status": "Processing",
      "title": "Processing & Setting",
      "subtitle": "24-Point Master Artisan Gemstone Inspection",
      "icon": Icons.diamond_outlined,
      "defaultLocation": "ZAWER Diamond Studio & Vault",
    },
    {
      "status": "Shipped",
      "title": "Shipped & Dispatched",
      "subtitle": "Tamper-Evident Armored Vehicle Transit",
      "icon": Icons.local_shipping_outlined,
      "defaultLocation": "High-Security Transit Hub",
    },
    {
      "status": "Out for Delivery",
      "title": "Out for Delivery",
      "subtitle": "White-Glove Executive In Local Sector",
      "icon": Icons.directions_bike_outlined,
      "defaultLocation": "Local Express Delivery Hub",
    },
    {
      "status": "Delivered",
      "title": "Delivered",
      "subtitle": "Velvet Presentation Box Handed Over",
      "icon": Icons.card_giftcard_outlined,
      "defaultLocation": "Customer Destination Address",
    },
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutCubic),
    );

    _glowAnimation = Tween<double>(begin: 0.3, end: 0.85).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    loadTrackingData();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) setState(() => isAdmin = prefs.getString("userRole") == "admin");
    });
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
          Map<String, dynamic>.from(result["tracking"] as Map),
        );
        isLoading = false;
      });
    } else {
      setState(() {
        isLoading = false;
        errorMessage = result["message"]?.toString() ?? "Unable to load live tracking";
      });
    }
  }

  Future<void> advanceToStatus(String status) async {
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.of(context);

    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1E1E24),
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
            ),
            const SizedBox(width: 12),
            Text(
              "Advancing vault status to '$status'...",
              style: AppFonts.poppins(fontSize: 12, color: Colors.white),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 900),
      ),
    );

    final result = await ApiService.updateOrderStatus(
      orderId: widget.orderId,
      status: status,
    );

    if (!mounted) return;

    if (result["success"] == true) {
      await loadTrackingData();
      HapticFeedback.lightImpact();
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.black87,
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.gold, size: 18),
              const SizedBox(width: 10),
              Text(
                "Status updated: $status",
                style: AppFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade900,
          content: Text(
            result["message"]?.toString() ?? "Failed to update status",
            style: AppFonts.poppins(color: Colors.white),
          ),
        ),
      );
    }
  }

  bool get isOrderCancelled => trackingData?.currentStatus == "Cancelled";

  int get currentStageIndex {
    if (trackingData == null) return 0;
    // Cancelled isn't a stage: show the last stage actually reached
    if (isOrderCancelled) {
      final reached = stageMetadata.lastIndexWhere((s) => trackingData!.timeline.any(
            (t) => t.isCompleted && t.status.toLowerCase() == s["status"].toString().toLowerCase(),
          ));
      return reached != -1 ? reached : 0;
    }
    final normalized = trackingData!.currentStatus == "Placed"
        ? "Order Placed"
        : trackingData!.currentStatus;
    final idx = stageMetadata.indexWhere(
      (s) => s["status"].toString().toLowerCase() == normalized.toLowerCase(),
    );
    return idx != -1 ? idx : 0;
  }

  void showSimulationBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF16161A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.tune_rounded, color: AppColors.gold, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Maison Vault Simulator",
                          style: AppFonts.cinzel(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : AppColors.black,
                          ),
                        ),
                        Text(
                          "Test live MongoDB updates across the 6 core stages",
                          style: AppFonts.poppins(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: stageMetadata.map((stage) {
                    final stageName = stage["status"] as String;
                    final isSelected =
                        trackingData?.currentStatus.toLowerCase() == stageName.toLowerCase();
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        Navigator.pop(ctx);
                        advanceToStatus(stageName);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.gold
                              : (isDark ? const Color(0xFF222228) : const Color(0xFFF7F5F0)),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.gold
                                : (isDark ? Colors.white12 : Colors.black12),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              stage["icon"] as IconData,
                              size: 14,
                              color: isSelected ? Colors.black : AppColors.gold,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              stageName,
                              style: AppFonts.poppins(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected
                                    ? Colors.black
                                    : (isDark ? Colors.white : Colors.black87),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0C0C0E) : const Color(0xFFFAF8F5),
      appBar: AppBar(
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
                fontSize: 10.5,
                letterSpacing: 3.5,
                fontWeight: FontWeight.w600,
                color: AppColors.gold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              "Order Telemetry",
              style: AppFonts.cinzel(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.tune_rounded, size: 20, color: AppColors.gold),
              tooltip: "Vault Simulator",
              onPressed: showSimulationBottomSheet,
            ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: "Refresh",
            onPressed: loadTrackingData,
          ),
        ],
      ),
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
          : errorMessage != null
              ? buildErrorView()
              : trackingData == null
                  ? buildEmptyView()
                  : RefreshIndicator(
                      onRefresh: loadTrackingData,
                      color: AppColors.gold,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            buildHeroVaultCard(),
                            const SizedBox(height: 14),
                            buildConciergeDispatchCard(),
                            const SizedBox(height: 20),
                            buildMilestoneTimeline(),
                            const SizedBox(height: 20),
                            buildArmoredLogisticsCard(),
                            const SizedBox(height: 16),
                            buildDestinationCard(),
                            const SizedBox(height: 16),
                            buildJewelleryPiecesCard(),
                            const SizedBox(height: 28),
                            if (isAdmin) buildDiscreetSimulatorButton(),
                            const SizedBox(height: 36),
                          ],
                        ),
                      ),
                    ),
    );
  }

  // =========================================================================
  // 1. HERO VAULT TRACKING CARD (Concentric Double-Bezel Architecture)
  // =========================================================================
  Widget buildHeroVaultCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isDelivered = trackingData!.currentStatus == "Delivered";
    final isCancelled = trackingData!.currentStatus == "Cancelled";

    Color statusBadgeColor = AppColors.gold;
    if (isDelivered) statusBadgeColor = const Color(0xFF2E7D32);
    if (isCancelled) statusBadgeColor = const Color(0xFFC62828);

    final progress = ((currentStageIndex + 1) / stageMetadata.length).clamp(0.0, 1.0);

    return Container(
      // Outer shell
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          colors: [
            AppColors.gold.withValues(alpha: 0.45),
            AppColors.gold.withValues(alpha: 0.1),
            Colors.transparent,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Container(
        // Inner Core
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF141418) : Colors.white,
          borderRadius: BorderRadius.circular(24.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "DISPATCH IDENTIFIER",
                        style: AppFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.0,
                          color: AppColors.gold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              trackingData!.trackingNumber,
                              style: AppFonts.cinzel(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              Clipboard.setData(
                                ClipboardData(text: trackingData!.trackingNumber),
                              );
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
                                color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                Icons.copy_rounded,
                                size: 14,
                                color: AppColors.brand(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusBadgeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: statusBadgeColor.withValues(alpha: 0.4),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedBuilder(
                          animation: _glowAnimation,
                          builder: (context, child) => Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: statusBadgeColor.withValues(alpha: _glowAnimation.value),
                              boxShadow: [
                                BoxShadow(
                                  color: statusBadgeColor.withValues(alpha: 0.6),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          trackingData!.currentStatus,
                          style: AppFonts.poppins(
                            color: statusBadgeColor,
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            // Progress rail with diamond pips
            Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 5.5,
                    backgroundColor: isDark ? const Color(0xFF222228) : const Color(0xFFEDE8DE),
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.gold),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(stageMetadata.length, (idx) {
                    final isReached = idx <= currentStageIndex;
                    return Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isReached
                            ? AppColors.gold
                            : (isDark ? Colors.white12 : Colors.black12),
                      ),
                    );
                  }),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.gold),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          trackingData!.estimatedDelivery != null
                              ? "Est: ${DateFormat('dd MMM yyyy').format(trackingData!.estimatedDelivery!)}"
                              : "Est: 3-5 Business Days",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(Icons.pin_drop_outlined, size: 14, color: AppColors.brand(context)),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          trackingData!.currentLocation,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: AppFonts.poppins(
                            fontSize: 11.5,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
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
  // 2. CONCIERGE DISPATCH BRIEF (High Jewellery Security Brief)
  // =========================================================================
  Widget buildConciergeDispatchCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131317) : const Color(0xFFF9F7F2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.gold.withValues(alpha: 0.22),
          width: 0.9,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
            ),
            child: const Icon(
              Icons.workspace_premium_outlined,
              size: 20,
              color: AppColors.gold,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Maison Vault Dispatch",
                      style: AppFonts.cinzel(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brand(context),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF242018) : const Color(0xFFEDE4CC),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.gold.withValues(alpha: 0.4), width: 0.7),
                      ),
                      child: Text(
                        "BIS 916 VERIFIED",
                        style: AppFonts.poppins(
                          fontSize: 8.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: isDark ? AppColors.gold : const Color(0xFF8B6508),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  trackingData!.aiDeliveryInsight,
                  style: AppFonts.poppins(
                    fontSize: 12,
                    height: 1.45,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 3. BESPOKE 6-STAGE TIMELINE (Haute Joaillerie Journey)
  // =========================================================================
  Widget buildMilestoneTimeline() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final timeline = trackingData!.timeline;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141418) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
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
                  const Icon(Icons.hourglass_top_rounded, color: AppColors.gold, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    "Creation & Transit Stages",
                    style: AppFonts.cinzel(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              Text(
                isOrderCancelled ? "CANCELLED" : "${currentStageIndex + 1}/6 COMPLETED",
                style: AppFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: isOrderCancelled ? const Color(0xFFC62828) : AppColors.gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: stageMetadata.length,
            itemBuilder: (context, index) {
              final stageMeta = stageMetadata[index];
              final stageName = stageMeta["status"] as String;
              final defaultTitle = stageMeta["title"] as String;
              final subtitle = stageMeta["subtitle"] as String;
              final icon = stageMeta["icon"] as IconData;

              final stepData = timeline.firstWhere(
                (t) => t.status.toLowerCase() == stageName.toLowerCase(),
                orElse: () => TrackingStep(
                  status: stageName,
                  title: defaultTitle,
                  description: subtitle,
                  location: stageMeta["defaultLocation"] as String,
                  isCompleted: index <= currentStageIndex,
                ),
              );

              final isCompleted = index <= currentStageIndex;
              final isCurrent = !isOrderCancelled && index == currentStageIndex;
              final isLast = index == stageMetadata.length - 1;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Milestone Node & Connector
                  Column(
                    children: [
                      isCurrent
                          ? ScaleTransition(
                              scale: _pulseAnimation,
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.gold,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.gold.withValues(alpha: 0.55),
                                      blurRadius: 12,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Icon(icon, size: 16, color: Colors.black),
                              ),
                            )
                          : Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isCompleted
                                    ? (isDark ? const Color(0xFF262015) : const Color(0xFFF3EBD8))
                                    : (isDark ? const Color(0xFF1B1B20) : const Color(0xFFF0EFEA)),
                                border: Border.all(
                                  color: isCompleted
                                      ? AppColors.gold
                                      : (isDark ? Colors.white12 : Colors.black12),
                                  width: isCompleted ? 1.4 : 1.0,
                                ),
                              ),
                              child: Icon(
                                isCompleted ? Icons.check : icon,
                                size: 14,
                                color: isCompleted
                                    ? AppColors.gold
                                    : (isDark ? Colors.white30 : Colors.black26),
                              ),
                            ),
                      if (!isLast)
                        Container(
                          width: 1.5,
                          height: 52,
                          color: isCompleted && index < currentStageIndex
                              ? AppColors.gold.withValues(alpha: 0.8)
                              : (isDark ? const Color(0xFF25252D) : const Color(0xFFE4E0D6)),
                        ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  // Milestone Details Card
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  stepData.title.isNotEmpty ? stepData.title : defaultTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppFonts.poppins(
                                    fontSize: 13.5,
                                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                                    color: isCompleted
                                        ? theme.colorScheme.onSurface
                                        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                  ),
                                ),
                              ),
                              if (stepData.timestamp != null && isCompleted) ...[
                                const SizedBox(width: 8),
                                Text(
                                  DateFormat("hh:mm a, dd MMM").format(stepData.timestamp!),
                                  style: AppFonts.poppins(
                                    fontSize: 10.5,
                                    color: AppColors.gold,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            stepData.description.isNotEmpty ? stepData.description : subtitle,
                            style: AppFonts.poppins(
                              fontSize: 11.5,
                              height: 1.4,
                              color: isCompleted
                                  ? theme.colorScheme.onSurfaceVariant
                                  : (isDark ? Colors.white24 : Colors.black26),
                            ),
                          ),
                          if (stepData.location.isNotEmpty && isCompleted) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on_outlined,
                                  size: 12,
                                  color: AppColors.gold.withValues(alpha: 0.8),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    stepData.location,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppFonts.poppins(
                                      fontSize: 10.5,
                                      color: isDark ? Colors.white54 : Colors.black45,
                                      fontStyle: FontStyle.italic,
                                    ),
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

  // =========================================================================
  // 4. ARMORED LOGISTICS & TRANSIT INSURANCE CARD
  // =========================================================================
  Widget buildArmoredLogisticsCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141418) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_outlined, color: Color(0xFF2E7D32), size: 16),
              ),
              const SizedBox(width: 10),
              Text(
                "Armored Security Escort",
                style: AppFonts.cinzel(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Carrier Division:",
                style: AppFonts.poppins(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  trackingData!.courierPartner,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: AppFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Transit Insurance:",
                style: AppFonts.poppins(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "100% Insured Valuables",
                  style: AppFonts.poppins(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF2E7D32),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 5. DESTINATION ADDRESS CARD
  // =========================================================================
  Widget buildDestinationCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141418) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.person_pin_circle_outlined, color: AppColors.brand(context), size: 16),
              ),
              const SizedBox(width: 10),
              Text(
                "Destination Concierge",
                style: AppFonts.cinzel(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            trackingData!.customerName,
            style: AppFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            trackingData!.phone,
            style: AppFonts.poppins(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            trackingData!.address,
            style: AppFonts.poppins(fontSize: 12, height: 1.45, color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 6. ORDERED JEWELLERY ITEMS CARD
  // =========================================================================
  Widget buildJewelleryPiecesCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141418) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
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
                  const Icon(Icons.diamond_outlined, color: AppColors.gold, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    "Jewellery Enclosure (${trackingData!.items.length})",
                    style: AppFonts.cinzel(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              Text(
                "₹${trackingData!.totalAmount.toStringAsFixed(0)}",
                style: AppFonts.cinzel(
                  fontSize: 15,
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
                    borderRadius: BorderRadius.circular(12),
                    child: item.image.isNotEmpty
                        ? Image.asset(
                            item.image,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              width: 48,
                              height: 48,
                              color: isDark ? const Color(0xFF222228) : const Color(0xFFF2EEE7),
                              child: const Icon(Icons.diamond_outlined, size: 20, color: AppColors.gold),
                            ),
                          )
                        : Container(
                            width: 48,
                            height: 48,
                            color: isDark ? const Color(0xFF222228) : const Color(0xFFF2EEE7),
                            child: const Icon(Icons.diamond_outlined, size: 20, color: AppColors.gold),
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
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "Qty: ${item.quantity} × ₹${item.price.toStringAsFixed(0)}",
                          style: AppFonts.poppins(
                            fontSize: 11.5,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    "₹${(item.price * item.quantity).toStringAsFixed(0)}",
                    style: AppFonts.poppins(
                      fontSize: 13,
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

  // =========================================================================
  // 7. DISCREET SIMULATOR BUTTON (Clean Luxury Experience)
  // =========================================================================
  Widget buildDiscreetSimulatorButton() {
    return Center(
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.gold,
          side: BorderSide(color: AppColors.gold.withValues(alpha: 0.35)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: showSimulationBottomSheet,
        icon: const Icon(Icons.tune_rounded, size: 16),
        label: Text(
          "Open Maison Vault Simulator (6 Stages)",
          style: AppFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  // =========================================================================
  // ERROR & EMPTY STATES
  // =========================================================================
  Widget buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 54, color: Colors.redAccent),
            const SizedBox(height: 14),
            Text(
              "Unable to Track Vault Order",
              style: AppFonts.cinzel(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage ?? "Could not find registered telemetry data.",
              textAlign: TextAlign.center,
              style: AppFonts.poppins(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: loadTrackingData,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text("Retry Telemetry"),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildEmptyView() {
    return Center(
      child: Text(
        "No tracking record found.",
        style: AppFonts.poppins(),
      ),
    );
  }
}
