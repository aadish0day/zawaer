import 'package:flutter/material.dart';
import '../utils/text_styles.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../utils/colors.dart';
import '../utils/theme_controller.dart';
import 'orders_screen.dart';
import 'order_tracking_screen.dart';
import 'wishlist_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() =>
      _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String userName = "ZAWER User";
  String userEmail = "user@email.com";
  String userPhone = "";
  String userAddress = "";

  @override
  void initState() {
    super.initState();

    loadUserData();
  }

  // =====================================================
  // LOAD USER DATA
  // =====================================================

  Future<void> loadUserData() async {
    final SharedPreferences prefs =
    await SharedPreferences.getInstance();

    final String savedName =
        prefs.getString("userName") ?? "";

    final String savedEmail =
        prefs.getString("userEmail") ?? "";

    final String savedPhone =
        prefs.getString("userPhone") ?? "";

    final String savedAddress =
        prefs.getString("savedAddress") ?? "";

    if (!mounted) {
      return;
    }

    setState(() {
      if (savedName.isNotEmpty) {
        userName = savedName;
      }

      if (savedEmail.isNotEmpty) {
        userEmail = savedEmail;
      }

      userPhone = savedPhone;

      userAddress = savedAddress;
    });
  }

  // =====================================================
  // EDIT PROFILE
  // =====================================================

  void showEditProfileDialog() {
    final nameController =
    TextEditingController(text: userName);

    final phoneController =
    TextEditingController(text: userPhone);

    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius:
                BorderRadius.circular(20),
              ),

              title: Text(
                "Edit Profile",
                style: AppFonts.cinzel(
                  fontWeight: FontWeight.bold,
                ),
              ),

              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [

                  TextField(
                    controller: nameController,
                    decoration:
                    const InputDecoration(
                      labelText: "Name",
                      prefixIcon:
                      Icon(Icons.person),
                    ),
                  ),

                  const SizedBox(height: 15),

                  TextField(
                    controller: phoneController,
                    keyboardType:
                    TextInputType.phone,
                    decoration:
                    const InputDecoration(
                      labelText: "Phone",
                      prefixIcon:
                      Icon(Icons.phone),
                    ),
                  ),

                ],
              ),

              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text("Cancel"),
                ),

                ElevatedButton(
                  style:
                  ElevatedButton.styleFrom(
                    backgroundColor:
                    AppColors.primary,
                  ),

                  onPressed: isSaving
                      ? null
                      : () async {
                    final messenger =
                    ScaffoldMessenger.of(context);

                    setDialogState(() {
                      isSaving = true;
                    });

                    final result =
                    await ApiService
                        .updateProfile(
                      name: nameController
                          .text
                          .trim(),
                      phone:
                      phoneController.text
                          .trim(),
                    );

                    if (result["success"] ==
                        true) {
                      final SharedPreferences
                      prefs =
                      await SharedPreferences
                          .getInstance();

                      await prefs.setString(
                        "userName",
                        nameController.text
                            .trim(),
                      );

                      await prefs.setString(
                        "userPhone",
                        phoneController.text
                            .trim(),
                      );
                    }

                    if (!dialogContext.mounted) {
                      return;
                    }

                    Navigator.pop(dialogContext);

                    if (result["success"] ==
                        true) {
                      loadUserData();

                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Profile updated successfully",
                          ),
                        ),
                      );
                    } else {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            result["message"]
                                ?.toString() ??
                                "Could not update profile",
                          ),
                        ),
                      );
                    }
                  },

                  child: isSaving
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child:
                    CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : const Text(
                    "Save",
                    style: TextStyle(
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // =====================================================
  // LOGOUT
  // =====================================================

  Future<void> logoutUser() async {
    final SharedPreferences prefs =
    await SharedPreferences.getInstance();

    await prefs.clear();

    if (!mounted) {
      return;
    }

    Navigator.pushNamedAndRemoveUntil(
      context,
      "/login",
          (route) => false,
    );
  }

  // =====================================================
  // SETTINGS
  // =====================================================

  void showSettingsDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),

          title: Text(
            "Settings",
            style: AppFonts.cinzel(
              fontWeight: FontWeight.bold,
            ),
          ),

          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              ListTile(
                leading:
                const Icon(Icons.light_mode),
                title:
                const Text("Light Mode"),
                onTap: () {
                  ThemeController.setDarkMode(false);
                  Navigator.pop(dialogContext);
                },
              ),

              ListTile(
                leading:
                const Icon(Icons.dark_mode),
                title:
                const Text("Dark Mode"),
                onTap: () {
                  ThemeController.setDarkMode(true);
                  Navigator.pop(dialogContext);
                },
              ),

            ],
          ),
        );
      },
    );
  }

  // =====================================================
  // SAVED ADDRESS
  // =====================================================

  void showSavedAddressDialog() {
    final addressController =
    TextEditingController(text: userAddress);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),

          title: Text(
            "Saved Address",
            style: AppFonts.cinzel(
              fontWeight: FontWeight.bold,
            ),
          ),

          content: TextField(
            controller: addressController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: "Delivery Address",
              prefixIcon:
              Icon(Icons.location_on),
            ),
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text("Cancel"),
            ),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                AppColors.primary,
              ),
              onPressed: () async {
                final messenger =
                ScaffoldMessenger.of(context);

                final SharedPreferences prefs =
                await SharedPreferences
                    .getInstance();

                await prefs.setString(
                  "savedAddress",
                  addressController.text.trim(),
                );

                if (!dialogContext.mounted) {
                  return;
                }

                setState(() {
                  userAddress =
                      addressController.text.trim();
                });

                Navigator.pop(dialogContext);

                messenger.showSnackBar(
                  const SnackBar(
                    content: Text(
                      "Address saved",
                    ),
                  ),
                );
              },
              child: const Text(
                "Save",
                style: TextStyle(
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // =====================================================
  // LOGOUT DIALOG
  // =====================================================

  void showLogoutDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),

          title: Text(
            "Logout",
            style: AppFonts.cinzel(
              fontWeight: FontWeight.bold,
            ),
          ),

          content: Text(
            "Are you sure you want to logout?",
            style: AppFonts.poppins(),
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text("Cancel"),
            ),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),

              onPressed: () async {
                Navigator.pop(dialogContext);

                await logoutUser();
              },

              child: const Text(
                "Logout",
                style: TextStyle(
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // =====================================================
  // BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,

      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        centerTitle: true,

        title: Text(
          "My Profile",
          style: AppFonts.cinzel(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      body: SingleChildScrollView(
        child: Column(
          children: [

            const SizedBox(height: 25),

            // =====================================================
            // PROFILE IMAGE
            // =====================================================

            CircleAvatar(
              radius: 55,
              backgroundColor: AppColors.primary,

              child: CircleAvatar(
                radius: 52,
                backgroundColor: Theme.of(context).colorScheme.surface,
                child: Icon(
                  Icons.person,
                  size: 60,
                  color: AppColors.brand(context),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // =====================================================
            // USER NAME
            // =====================================================

            Text(
              userName,
              textAlign: TextAlign.center,

              style: AppFonts.cinzel(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            // =====================================================
            // USER EMAIL
            // =====================================================

            Text(
              userEmail,
              textAlign: TextAlign.center,

              style: AppFonts.poppins(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 15,
              ),
            ),

            if (userPhone.isNotEmpty) ...[
              const SizedBox(height: 5),

              Text(
                userPhone,
                style: AppFonts.poppins(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
            ],

            const SizedBox(height: 35),

            // =====================================================
            // EDIT PROFILE
            // =====================================================

            buildTile(
              Icons.person,
              "Edit Profile",
                  showEditProfileDialog,
            ),

            // =====================================================
            // MY ORDERS
            // =====================================================

            buildTile(
              Icons.shopping_bag,
              "My Orders",
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const OrdersScreen(),
                  ),
                );
              },
            ),

            // =====================================================
            // TRACK AN ORDER
            // =====================================================

            buildTile(
              Icons.location_searching_rounded,
              "Track Order Live",
              () {
                final trackController = TextEditingController();
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    title: Text(
                      "Track Your Jewellery",
                      style: AppFonts.cinzel(fontWeight: FontWeight.bold),
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "Enter your Order ID or Tracking Number (e.g. ZWR-XXXXXX) to view live vault status & transit updates.",
                          style: AppFonts.poppins(fontSize: 12.5),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: trackController,
                          decoration: InputDecoration(
                            labelText: "Order ID / Tracking Number",
                            prefixIcon: const Icon(Icons.qr_code_scanner),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text("Cancel"),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                        onPressed: () {
                          final query = trackController.text.trim();
                          if (query.isNotEmpty) {
                            Navigator.pop(ctx);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => OrderTrackingScreen(orderId: query),
                              ),
                            );
                          }
                        },
                        child: const Text("Track Now", style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );
              },
            ),

            // =====================================================
            // WISHLIST
            // =====================================================

            buildTile(
              Icons.favorite,
              "Wishlist",
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const WishlistScreen(),
                  ),
                );
              },
            ),

            // =====================================================
            // SAVED ADDRESS
            // =====================================================

            buildTile(
              Icons.location_on,
              "Saved Address",
                  showSavedAddressDialog,
            ),

            // =====================================================
            // SETTINGS
            // =====================================================

            buildTile(
              Icons.settings,
              "Settings",
                  showSettingsDialog,
            ),

            // =====================================================
            // DARK MODE
            // =====================================================

            Card(
              margin: const EdgeInsets.symmetric(
                horizontal: 15,
                vertical: 6,
              ),

              elevation: 2,

              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),

              child: SwitchListTile(
                activeThumbColor: Theme.of(context).colorScheme.primary,

                title: Text(
                  "Dark Mode",
                  style: AppFonts.poppins(
                    fontWeight: FontWeight.w600,
                  ),
                ),

                secondary: CircleAvatar(
                  backgroundColor:
                  Theme.of(context).colorScheme.primary.withValues(
                    alpha: 0.1,
                  ),

                  child: Icon(
                    Icons.dark_mode,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),

                value: ThemeController.mode.value ==
                    ThemeMode.dark,

                onChanged: (value) {
                  ThemeController.setDarkMode(value);
                },
              ),
            ),

            const SizedBox(height: 20),

            // =====================================================
            // LOGOUT BUTTON
            // =====================================================

            SizedBox(
              width: double.infinity,

              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                ),

                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,

                    minimumSize:
                    const Size(
                      double.infinity,
                      55,
                    ),

                    shape:
                    RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(15),
                    ),
                  ),

                  icon: const Icon(
                    Icons.logout,
                    color: Colors.white,
                  ),

                  label: Text(
                    "LOGOUT",

                    style: AppFonts.cinzel(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),

                  onPressed: showLogoutDialog,
                ),
              ),
            ),

            const SizedBox(height: 35),

            // =====================================================
            // FOOTER
            // =====================================================

            Text(
              "ZAWER Jewellery",
              style: AppFonts.cinzel(
                fontSize: 24,
                color: AppColors.brand(context),
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              "Luxury Jewellery Since 2026",
              style: AppFonts.poppins(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 15,
              ),
            ),

            const SizedBox(height: 25),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // PROFILE TILE
  // =====================================================

  Widget buildTile(
      IconData icon,
      String title,
      VoidCallback onTap,
      ) {
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: 15,
        vertical: 6,
      ),

      elevation: 2,

      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),

      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
          Theme.of(context).colorScheme.primary.withValues(
            alpha: 0.1,
          ),

          child: Icon(
            icon,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),

        title: Text(
          title,
          style: AppFonts.poppins(
            fontWeight: FontWeight.w600,
          ),
        ),

        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 18,
        ),

        onTap: onTap,
      ),
    );
  }
}