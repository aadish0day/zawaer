import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../utils/colors.dart';
import '../utils/text_styles.dart';
import '../utils/theme_controller.dart';
import 'login_screen.dart';
import 'orders_screen.dart';
import 'order_tracking_screen.dart';
import 'offers_screen.dart';
import 'wishlist_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => ProfileScreenState();
}

class ProfileScreenState extends State<ProfileScreen> {
  bool isLoggedIn = false;
  String userName = "";
  String userEmail = "";
  String userPhone = "";
  String userAddress = "";
  int ordersCount = 0;
  int wishlistCount = 0;
  bool isLoadingStats = true;

  @override
  void initState() {
    super.initState();
    loadUserData();
    loadProfileStats();
  }

  // =====================================================
  // LOAD USER PROFILE
  // =====================================================
  Future<void> loadUserData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final bool hasToken = (prefs.getString("token") ?? "").isNotEmpty;
    final String savedName = prefs.getString("userName") ?? "";
    final String savedEmail = prefs.getString("userEmail") ?? "";
    final String savedPhone = prefs.getString("userPhone") ?? "";
    final String savedAddress = prefs.getString("savedAddress") ?? "";

    if (!mounted) return;

    setState(() {
      isLoggedIn = hasToken;
      userName = savedName;
      userEmail = savedEmail;
      userPhone = savedPhone;
      userAddress = savedAddress;
    });
  }

  Future<void> loadProfileStats() async {
    if ((await ApiService.getToken()).isEmpty) {
      if (!mounted) return;
      setState(() {
        ordersCount = 0;
        wishlistCount = 0;
        isLoadingStats = false;
      });
      return;
    }

    try {
      final ordersRes = await ApiService.getOrders();
      final wishRes = await ApiService.getWishlist();

      if (!mounted) return;

      // Session expired / revoked: re-read prefs so the guest view shows.
      if (ordersRes["statusCode"] == 401 || wishRes["statusCode"] == 401) {
        await loadUserData();
        if (!mounted) return;
      }

      int oCount = 0;
      if (ordersRes["success"] == true && ordersRes["orders"] is List) {
        oCount = (ordersRes["orders"] as List).length;
      }

      int wCount = 0;
      if (wishRes["success"] == true && wishRes["wishlist"]?["items"] is List) {
        wCount = (wishRes["wishlist"]["items"] as List).length;
      }

      setState(() {
        ordersCount = oCount;
        wishlistCount = wCount;
        isLoadingStats = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          isLoadingStats = false;
        });
      }
    }
  }

  // =====================================================
  // SIGN IN (guest)
  // =====================================================
  Future<void> openSignIn() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    if (!mounted) return;
    await reload();
  }

  // Called by BottomNavScreen when the Profile tab is selected.
  Future<void> reload() async {
    await Future.wait([loadUserData(), loadProfileStats()]);
  }

  // =====================================================
  // EDIT PROFILE DIALOG
  // =====================================================
  void showEditProfileDialog() {
    final nameController = TextEditingController(text: userName);
    final phoneController = TextEditingController(text: userPhone);
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF16161C) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: AppColors.gold.withValues(alpha: 0.3), width: 0.8),
              ),
              title: Text(
                "Edit Client Credentials",
                style: AppFonts.cinzel(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      validator: (value) =>
                          (value == null || value.trim().isEmpty) ? "Name is required" : null,
                      style: AppFonts.poppins(fontSize: 13.5),
                      decoration: InputDecoration(
                        labelText: "Full Name",
                        prefixIcon: const Icon(Icons.person_outline, color: AppColors.gold),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      validator: (value) {
                        final phone = value?.trim() ?? "";
                        if (phone.isNotEmpty && !RegExp(r'^\d{10,15}$').hasMatch(phone)) {
                          return "Enter 10-15 digits";
                        }
                        return null;
                      },
                      style: AppFonts.poppins(fontSize: 13.5),
                      decoration: InputDecoration(
                        labelText: "Phone Number",
                        prefixIcon: const Icon(Icons.phone_outlined, color: AppColors.gold),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text("Cancel", style: AppFonts.poppins(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          HapticFeedback.selectionClick();
                          // Page-level messenger: the dialog's own context is gone after pop.
                          final messenger = ScaffoldMessenger.of(this.context);
                          setDialogState(() {
                            isSaving = true;
                          });

                          final result = await ApiService.updateProfile(
                            name: nameController.text.trim(),
                            phone: phoneController.text.trim(),
                          );

                          if (result["success"] == true) {
                            final SharedPreferences prefs = await SharedPreferences.getInstance();
                            await prefs.setString("userName", nameController.text.trim());
                            await prefs.setString("userPhone", phoneController.text.trim());
                          }

                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);

                          if (!mounted) return;

                          final bool success = result["success"] == true;
                          // A 401 already cleared auth inside ApiService; reload
                          // either way so the screen reflects the real state.
                          loadUserData();
                          messenger.showSnackBar(
                            SnackBar(
                              behavior: SnackBarBehavior.floating,
                              backgroundColor: success ? null : Colors.red,
                              content: Text(
                                success
                                    ? "Credentials updated successfully"
                                    : result["statusCode"] == 401
                                        ? "Session expired. Please sign in again."
                                        : result["message"]?.toString() ?? "Could not update profile",
                              ),
                            ),
                          );
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          "Save Changes",
                          style: AppFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      nameController.dispose();
      phoneController.dispose();
    });
  }

  // =====================================================
  // SAVED ADDRESS DIALOG
  // =====================================================
  void showSavedAddressDialog() {
    final addressController = TextEditingController(text: userAddress);

    showDialog(
      context: context,
      builder: (dialogContext) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF16161C) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: AppColors.gold.withValues(alpha: 0.3), width: 0.8),
          ),
          title: Text(
            "Primary Vault Delivery Address",
            style: AppFonts.cinzel(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          content: TextField(
            controller: addressController,
            maxLines: 3,
            style: AppFonts.poppins(fontSize: 13.5),
            decoration: InputDecoration(
              labelText: "Delivery Address",
              hintText: "Enter suite, building, street, and pin code...",
              prefixIcon: const Icon(Icons.location_on_outlined, color: AppColors.gold),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text("Cancel", style: AppFonts.poppins(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                HapticFeedback.selectionClick();
                final messenger = ScaffoldMessenger.of(context);
                final SharedPreferences prefs = await SharedPreferences.getInstance();
                await prefs.setString("savedAddress", addressController.text.trim());

                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);

                if (!mounted) return;

                setState(() {
                  userAddress = addressController.text.trim();
                });

                messenger.showSnackBar(
                  const SnackBar(
                    behavior: SnackBarBehavior.floating,
                    content: Text("Vault address updated"),
                  ),
                );
              },
              child: Text(
                "Save Address",
                style: AppFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    ).then((_) {
      addressController.dispose();
    });
  }

  // =====================================================
  // LOGOUT
  // =====================================================
  Future<void> logoutUser() async {
    await ApiService.clearAuth();

    if (!mounted) return;

    Navigator.pushNamedAndRemoveUntil(
      context,
      "/login",
      (route) => false,
    );
  }

  void showLogoutDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF16161C) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: AppColors.gold.withValues(alpha: 0.3), width: 0.8),
          ),
          title: Text(
            "Maison Sign Out",
            style: AppFonts.cinzel(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: Text(
            "Are you sure you want to end your current vault session?",
            style: AppFonts.poppins(fontSize: 13, color: Colors.grey),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text("Stay Signed In", style: AppFonts.poppins(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade800,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                Navigator.pop(dialogContext);
                if (!mounted) return;
                await logoutUser();
              },
              child: Text(
                "Sign Out",
                style: AppFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
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
      appBar: buildMaisonAppBar(isDark),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([loadUserData(), loadProfileStats()]);
        },
        color: AppColors.gold,
        backgroundColor: isDark ? const Color(0xFF18181E) : Colors.white,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            children: [
              // 1. VIP Client Identity Card
              buildClientIdentityCard(isDark),
              const SizedBox(height: 16),
              // 2. Vault Quick Stats Hub
              buildVaultStatsHub(isDark),
              const SizedBox(height: 20),
              // 3. Vault & Concierge Hub
              buildSectionHeader("VAULT & CONCIERGE", isDark),
              const SizedBox(height: 8),
              buildHubGroup([
                buildHubItem(
                  icon: Icons.inventory_2_outlined,
                  title: "Maison Orders & Invoices",
                  subtitle: "$ordersCount previous acquired pieces",
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const OrdersScreen()),
                  ).then((_) => loadProfileStats()),
                ),
                buildHubItem(
                  icon: Icons.discount_outlined,
                  title: "Privilege Offers & Vouchers",
                  subtitle: "Exclusive coupons & flash promotions",
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const OffersScreen()),
                  ),
                ),
                buildHubItem(
                  icon: Icons.local_shipping_outlined,
                  title: "Live Armored Escort Tracking",
                  subtitle: "Sequel Secure Luxury Logistics",
                  onTap: showLiveTrackingLookupModal,
                ),
                buildHubItem(
                  icon: Icons.favorite_border_rounded,
                  title: "Curated Wishlist Vault",
                  subtitle: "$wishlistCount precious pieces preserved",
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const WishlistScreen()),
                  ).then((_) => loadProfileStats()),
                ),
                buildHubItem(
                  icon: Icons.location_on_outlined,
                  title: "Vault Delivery Address",
                  subtitle: userAddress.isNotEmpty ? userAddress : "Set primary delivery address",
                  onTap: showSavedAddressDialog,
                ),
              ], isDark),
              const SizedBox(height: 20),
              // 4. Maison Preferences
              buildSectionHeader("MAISON PREFERENCES", isDark),
              const SizedBox(height: 8),
              buildHubGroup([
                buildThemeToggleItem(isDark),
                if (isLoggedIn)
                  buildHubItem(
                    icon: Icons.badge_outlined,
                    title: "Client Credentials",
                    subtitle: "Edit name and verified phone",
                    onTap: showEditProfileDialog,
                  ),
                buildHubItem(
                  icon: Icons.diamond_outlined,
                  title: "Bespoke Engraving & Consultation",
                  subtitle: "Book private certified gemologist",
                  onTap: showConciergeModal,
                ),
              ], isDark),
              const SizedBox(height: 20),
              // 5. Sign Out Button (Sign In for guests)
              isLoggedIn ? buildSignOutButton(isDark) : buildSignInButton(),
              const SizedBox(height: 32),
              // 6. Maison Seal & Heritage Footer
              buildMaisonHeritageFooter(isDark),
              const SizedBox(height: 30),
            ],
          ),
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
            "Client Profile",
            style: AppFonts.cinzel(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
      actions: [
        if (isLoggedIn)
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            tooltip: "Edit Profile",
            onPressed: showEditProfileDialog,
          ),
        const SizedBox(width: 4),
      ],
    );
  }

  // =========================================================================
  // 2. VIP CLIENT IDENTITY CARD (Double-Bezel Architecture)
  // =========================================================================
  Widget buildClientIdentityCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(1.2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
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
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF141418) : Colors.white,
          borderRadius: BorderRadius.circular(23),
        ),
        child: Column(
          children: [
            Row(
              children: [
                // Avatar with Concentric Gold Halo
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [AppColors.gold, Color(0xFFFFF2D1), AppColors.gold],
                    ),
                  ),
                  child: Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? const Color(0xFF1D1D24) : const Color(0xFFF3EFE8),
                    ),
                    child: Center(
                      child: Text(
                        isLoggedIn && userName.isNotEmpty ? userName[0].toUpperCase() : "Z",
                        style: AppFonts.cinzel(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: AppColors.brand(context),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Name & VIP Badge
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.gold.withValues(alpha: 0.5),
                            width: 0.7,
                          ),
                        ),
                        child: Text(
                          isLoggedIn ? "HERITAGE PATRON • TIER I" : "GUEST",
                          style: AppFonts.poppins(
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: AppColors.gold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isLoggedIn ? (userName.isNotEmpty ? userName : "Client") : "Welcome, Guest",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.cinzel(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isLoggedIn ? userEmail : "Sign in to view your orders and details",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.poppins(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (isLoggedIn) ...[
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.phone_outlined, size: 14, color: AppColors.gold),
                      const SizedBox(width: 6),
                      Text(
                        userPhone.isNotEmpty ? userPhone : "No phone registered",
                        style: AppFonts.poppins(
                          fontSize: 11.5,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: showEditProfileDialog,
                    child: Text(
                      "Edit Details →",
                      style: AppFonts.poppins(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brand(context),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // 3. VAULT STATS QUICK HUB
  // =========================================================================
  Widget buildVaultStatsHub(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: buildStatBox(
            label: "ACQUISITIONS",
            value: ordersCount.toString(),
            icon: Icons.inventory_2_outlined,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OrdersScreen()),
            ).then((_) => loadProfileStats()),
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: buildStatBox(
            label: "WISHLIST",
            value: wishlistCount.toString(),
            icon: Icons.favorite_border_rounded,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WishlistScreen()),
            ).then((_) => loadProfileStats()),
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: buildStatBox(
            label: "ESCORT",
            value: "LIVE",
            icon: Icons.security_outlined,
            onTap: showLiveTrackingLookupModal,
            isDark: isDark,
          ),
        ),
      ],
    );
  }

  Widget buildStatBox({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF141418) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: AppColors.gold),
            const SizedBox(height: 6),
            Text(
              value,
              style: AppFonts.cinzel(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppFonts.poppins(
                fontSize: 8.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // 4. BESPOKE SECTION HUB & GROUP ITEMS
  // =========================================================================
  Widget buildSectionHeader(String title, bool isDark) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          title,
          style: AppFonts.poppins(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.6,
            color: AppColors.gold,
          ),
        ),
      ),
    );
  }

  Widget buildHubGroup(List<Widget> children, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141418) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget buildHubItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.gold.withValues(alpha: 0.1),
              ),
              child: Icon(icon, size: 18, color: AppColors.gold),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppFonts.cinzel(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.poppins(
                      fontSize: 11,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget buildThemeToggleItem(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.gold.withValues(alpha: 0.1),
            ),
            child: Icon(
              isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              size: 18,
              color: AppColors.gold,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "High-Contrast Dark Mode",
                  style: AppFonts.cinzel(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isDark ? "Obsidian luxury theme active" : "Champagne light theme active",
                  style: AppFonts.poppins(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: ThemeController.mode.value == ThemeMode.dark,
            activeThumbColor: AppColors.gold,
            activeTrackColor: AppColors.gold.withValues(alpha: 0.35),
            onChanged: (val) {
              HapticFeedback.selectionClick();
              ThemeController.setDarkMode(val);
            },
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 5. SIGN OUT BUTTON
  // =========================================================================
  Widget buildSignOutButton(bool isDark) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.redAccent,
          side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.35)),
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: showLogoutDialog,
        icon: const Icon(Icons.logout_rounded, size: 16),
        label: Text(
          "SIGN OUT OF MAISON SESSION",
          style: AppFonts.poppins(
            fontSize: 11.5,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }

  Widget buildSignInButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: openSignIn,
        icon: const Icon(Icons.login_rounded, size: 16),
        label: Text(
          "SIGN IN TO MAISON",
          style: AppFonts.poppins(
            fontSize: 11.5,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // 6. MAISON HERITAGE SEAL & FOOTER
  // =========================================================================
  Widget buildMaisonHeritageFooter(bool isDark) {
    return Column(
      children: [
        Icon(
          Icons.diamond_outlined,
          size: 24,
          color: AppColors.gold.withValues(alpha: 0.4),
        ),
        const SizedBox(height: 8),
        Text(
          "ZAWER MAISON DE HAUTE JOAILLERIE",
          style: AppFonts.cinzel(
            fontSize: 11,
            letterSpacing: 2.5,
            fontWeight: FontWeight.bold,
            color: AppColors.gold,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          "BIS 916 Hallmarked • IGI Certified Natural Diamonds",
          style: AppFonts.poppins(
            fontSize: 9.5,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // MODALS & HELPERS
  // =========================================================================
  void showLiveTrackingLookupModal() {
    final trackController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF16161C) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: AppColors.gold.withValues(alpha: 0.3), width: 0.8),
          ),
          title: Text(
            "Armored Transit Lookup",
            style: AppFonts.cinzel(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Enter your Order ID or Tracking Number (e.g. ZWR-XXXXXX) to monitor live armored transit.",
                style: AppFonts.poppins(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: trackController,
                style: AppFonts.poppins(fontSize: 13.5),
                decoration: InputDecoration(
                  labelText: "Tracking ID (e.g. ZWR-847762)",
                  prefixIcon: const Icon(Icons.qr_code_scanner, color: AppColors.gold),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text("Cancel", style: AppFonts.poppins(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                final query = trackController.text.trim();
                if (query.isNotEmpty) {
                  Navigator.pop(ctx);
                  if (!mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OrderTrackingScreen(orderId: query),
                    ),
                  );
                }
              },
              child: Text(
                "Track Transit",
                style: AppFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    ).then((_) {
      trackController.dispose();
    });
  }

  void showConciergeModal() {
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF16161C) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: AppColors.gold.withValues(alpha: 0.3), width: 0.8),
          ),
          title: Text(
            "Private Diamond Concierge",
            style: AppFonts.cinzel(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.gold.withValues(alpha: 0.15),
                ),
                child: const Icon(Icons.support_agent_rounded, size: 36, color: AppColors.gold),
              ),
              const SizedBox(height: 14),
              Text(
                "As a ZAWER Heritage Patron, you are entitled to private gemologist consultations, custom laser engravings, and bridal trousseau styling.",
                textAlign: TextAlign.center,
                style: AppFonts.poppins(fontSize: 12, height: 1.5, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: Text("Close", style: AppFonts.poppins(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
}