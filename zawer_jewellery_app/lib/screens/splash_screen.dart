import 'package:flutter/material.dart';
import '../utils/text_styles.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../utils/colors.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    checkLoginStatus();
  }

  Future<void> checkLoginStatus() async {
    // Keep the splash screen visible for a moment.
    await Future.delayed(
      const Duration(milliseconds: 800),
    );

    if (!mounted) return;

    // Read saved login information.
    final SharedPreferences prefs =
    await SharedPreferences.getInstance();

    String token =
        prefs.getString("token") ?? "";

    // Verify the saved session. A 401 clears stored auth inside ApiService;
    // network errors keep the saved session (offline tolerance).
    if (token.isNotEmpty) {
      final profile = await ApiService.getProfile();
      if (profile["statusCode"] == 401) {
        token = "";
      } else if (profile["success"] == true && profile["user"] is Map) {
        await prefs.setString(
          "userRole",
          profile["user"]["role"]?.toString() ?? "user",
        );
      }
    }

    if (!mounted) return;

    // Decide where to go safely without leaving Navigator history empty
    if (token.isNotEmpty) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        "/bottomNav",
        (route) => false,
      );
    } else {
      Navigator.pushNamedAndRemoveUntil(
        context,
        "/login",
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,

        body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            // ==========================
            // LOGO
            // ==========================

            Container(
              height: 130,
              width: 130,

              decoration: BoxDecoration(
                color: Colors.white,

                borderRadius:
                BorderRadius.circular(35),

                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: 0.08,
                    ),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),

              child: const Icon(
                Icons.diamond,
                color: AppColors.primary,
                size: 75,
              ),
            ),

            const SizedBox(height: 25),

            // ==========================
            // ZAWER NAME
            // ==========================

            Text(
              "ZAWER",
              style: AppFonts.cinzel(
                fontSize: 42,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
                letterSpacing: 5,
              ),
            ),

            const SizedBox(height: 10),

            // ==========================
            // SUBTITLE
            // ==========================

            Text(
              "Luxury Jewellery Collection",
              style: AppFonts.poppins(
                color: Colors.grey.shade600,
                fontSize: 16,
              ),
            ),

            const SizedBox(height: 45),

            // ==========================
            // LOADING
            // ==========================

            const CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2.5,
            ),
          ],
        ),
      ),
    ),
  );
}
}