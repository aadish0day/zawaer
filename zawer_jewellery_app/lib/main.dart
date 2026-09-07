import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/home_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/wishlist_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/checkout_screen.dart';
import 'screens/bottom_nav_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/product_api_test_screen.dart';

import 'utils/theme.dart';
import 'utils/theme_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await ThemeController.load();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  ErrorWidget.builder = (details) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 60,
              ),
              const SizedBox(height: 15),
              const Text(
                "Something went wrong",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                details.exceptionAsString(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  };

  runApp(
    const ZawerJewelleryApp(),
  );
}

class ZawerJewelleryApp extends StatelessWidget {
  const ZawerJewelleryApp({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, mode, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,

          title: "ZAWER Jewellery",

          theme: AppTheme.lightTheme,

          darkTheme: AppTheme.darkTheme,

          themeMode: mode,

          home: const SplashScreen(),

          onUnknownRoute: (settings) => MaterialPageRoute(
            builder: (_) => const SplashScreen(),
          ),

          routes: {
        // ==========================
        // MAIN ROUTES
        // ==========================

        "/login": (context) =>
        const LoginScreen(),

        "/register": (context) =>
        const RegisterScreen(),

        "/forgot": (context) =>
        const ForgotPasswordScreen(),

        "/home": (context) =>
        const HomeScreen(),

        "/bottomNav": (context) =>
        const BottomNavScreen(),

        // ==========================
        // OTHER SCREENS
        // ==========================

        "/cart": (context) =>
        const CartScreen(),

        "/wishlist": (context) =>
        const WishlistScreen(),

        "/profile": (context) =>
        const ProfileScreen(),

        "/checkout": (context) =>
        const CheckoutScreen(),

        "/orders": (context) =>
        const OrdersScreen(),

        // ==========================
        // TEMPORARY PRODUCT API TEST
        // ==========================

        "/productApiTest": (context) =>
        const ProductApiTestScreen(),
          },
        );
      },
    );
  }
}