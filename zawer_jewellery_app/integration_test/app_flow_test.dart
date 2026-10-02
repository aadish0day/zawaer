// End-to-end UI smoke test against a live backend.
//
// Run (desktop):  xvfb-run -a flutter test integration_test/app_flow_test.dart -d linux \
//                   --dart-define=API_BASE_URL=http://127.0.0.1:5198
// Creates a user ui_<timestamp>@zawer-smoke.test and places one real order.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zawer_jewellery_app/main.dart' as app;
import 'package:zawer_jewellery_app/services/api_service.dart';

const productName = "Silver Cuban Chain"; // 7999, clears MAISON10's 5000 minimum
const password = "uiTest123";
const newPassword = "uiTest456";

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("full app flow", (tester) async {
    final email = "ui_${DateTime.now().millisecondsSinceEpoch}@zawer-smoke.test";
    // ignore: avoid_print
    print("SMOKE EMAIL: $email");

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    final flutterErrors = <String>[];
    final testOnError = FlutterError.onError;
    final testErrorWidget = ErrorWidget.builder;
    app.main();
    await tester.pump(const Duration(milliseconds: 300));
    final appOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      // ignore: avoid_print
      if (flutterErrors.isEmpty) print("FIRST FLUTTER ERROR:\n$details\n${details.stack}");
      flutterErrors.add(details.exceptionAsString().split("\n").first);
      appOnError?.call(details);
    };

    final results = <String, String>{};
    Future<void> step(String name, Future<void> Function() body) async {
      try {
        await body();
        results[name] = "PASS";
      } catch (e) {
        results[name] = "FAIL: ${e.toString().split("\n").take(3).join(" | ")}";
        final texts = find
            .byType(Text)
            .evaluate()
            .map((el) => (el.widget as Text).data)
            .whereType<String>()
            .take(80)
            .join(" ¦ ");
        // ignore: avoid_print
        print("STEP $name FAILED: $e\nVISIBLE TEXTS: $texts");
      }
      // ignore: avoid_print
      print("STEP $name => ${results[name]}");
    }

    Future<void> waitFor(Finder f, {int seconds = 30}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 200));
        if (f.evaluate().isNotEmpty) return;
      }
      throw TestFailure("Timed out after ${seconds}s waiting for $f");
    }

    Future<void> settle([int ms = 800]) async {
      for (var i = 0; i < ms ~/ 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> waitNoSnack() async {
      final end = DateTime.now().add(const Duration(seconds: 10));
      while (find.byType(SnackBar).evaluate().isNotEmpty && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    Future<void> scrollTo(Finder f) async {
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      for (var i = 0; i < 30; i++) {
        if (f.evaluate().isNotEmpty) {
          // Centre it so bars/snackbars at the edges don't swallow the tap.
          await Scrollable.ensureVisible(tester.element(f.first), alignment: 0.5);
          await settle(400);
          return;
        }
        await tester.dragFrom(Offset(size.width / 2, size.height * 0.6), const Offset(0, -250));
        await settle(300);
      }
      throw TestFailure("Could not scroll to $f");
    }

    Future<void> tap(Finder f) async {
      await scrollTo(f);
      await tester.tap(f.first);
      await settle(500);
    }

    Future<void> enter(Finder f, String text) async {
      await scrollTo(f);
      await tester.enterText(f.first, text);
      await settle(200);
    }

    Future<void> back() async {
      await tester.binding.handlePopRoute();
      await settle(800);
    }

    Finder field(String label) => find.widgetWithText(TextFormField, label);
    Finder navTab(String label) =>
        find.descendant(of: find.byType(BottomNavigationBar), matching: find.text(label));

    // a. splash -> login
    await step("a splash->login", () async {
      await waitFor(find.text("ZAWER"), seconds: 10);
      await waitFor(find.text("LOGIN"), seconds: 20);
      expect(find.text("Continue as Guest"), findsOneWidget);
    });

    // b. register
    await step("b register", () async {
      await tap(find.text("Register"));
      await waitFor(find.text("REGISTER"));
      await enter(field("Full Name"), "UI Smoke");
      await enter(field("Email"), email);
      await enter(field("Phone Number (optional)"), "+91 98765 43210");
      await enter(field("Password"), password);
      await enter(field("Confirm Password"), password);
      await tap(find.byType(Checkbox));
      await tap(find.text("REGISTER"));
      await waitFor(find.text("Account created successfully!"));
      await waitFor(find.text("LOGIN"));
      await waitNoSnack();
    });

    // c. login -> home with products
    await step("c login->home", () async {
      await enter(field("Email Address"), email);
      await enter(field("Password"), password);
      await tap(find.text("LOGIN"));
      await waitFor(find.text("Masterpiece Catalog"));
      await waitFor(find.text("• Certified"), seconds: 30);
      expect(find.text("• Certified"), findsWidgets);
    });

    // d. product -> add to cart, toggle wishlist
    await step("d product: cart + wishlist", () async {
      await tap(find.text(productName));
      await waitFor(find.text("ADD TO CART"));
      final heart = find.descendant(of: find.byType(AppBar), matching: find.byIcon(Icons.favorite_border));
      await tap(heart);
      await waitFor(find.descendant(of: find.byType(AppBar), matching: find.byIcon(Icons.favorite)));
      await waitNoSnack();
      await tap(find.text("ADD TO CART"));
      await waitFor(find.text("$productName added to cart"));
      await waitNoSnack();
      await back();
      await waitFor(find.text("HAUTE JOAILLERIE"));
      expect(find.text("ADD TO CART"), findsNothing);
    });

    // e. wishlist tab
    await step("e wishlist tab", () async {
      await tap(navTab("Wishlist"));
      await waitFor(find.text("Curated Wishlist"));
      await waitFor(find.text(productName));
    });

    // f. cart tab + quantity
    await step("f cart tab + qty", () async {
      await tap(navTab("Cart"));
      await waitFor(find.text("PROCEED TO VAULT CHECKOUT"));
      await waitFor(find.text(productName));
      await tap(find.byIcon(Icons.add));
      await settle(2500);
      await waitFor(find.text("₹15998"));
    });

    // g. checkout with MAISON10
    await step("g checkout MAISON10", () async {
      await tap(find.text("PROCEED TO VAULT CHECKOUT"));
      await waitFor(find.text("Vault Checkout"));
      await waitFor(field("Recipient Full Name"));
      await settle(1500);
      await enter(field("Recipient Full Name"), "UI Smoke");
      await enter(field("Verified Phone Number"), "+91 98765 43210");
      await enter(field("Vault Delivery Destination"), "221B Baker Street, Mumbai 400001");
      await enter(find.widgetWithText(TextField, "Enter Privilege Code"), "MAISON10");
      await tap(find.text("APPLY"));
      await waitFor(find.textContaining("Privilege Discount (MAISON10)"));
      await tap(find.textContaining("AUTHORIZE VAULT ORDER"));
      await waitFor(find.text("Order Placed Successfully!"), seconds: 40);
      expect(find.textContaining("privilege discount has been applied"), findsOneWidget);
      await tap(find.text("Return to Catalog"));
      await settle(1500);
    });

    // h. orders -> tracking
    await step("h orders + tracking", () async {
      await tap(navTab("Profile"));
      await waitFor(find.text("Client Profile"));
      await tap(find.text("Maison Orders & Invoices"));
      await waitFor(find.text("Acquisitions & Escort"));
      await waitFor(find.textContaining("ZWR-"));
      // ignore: avoid_print
      print("ORDERS LISTED (TRACK ESCORT buttons): ${find.text("TRACK ESCORT").evaluate().length}");
      await tap(find.text("TRACK ESCORT"));
      await waitFor(find.text("Order Telemetry"));
      await waitFor(find.text("Order Placed"));
      await back();
      await back();
      await waitFor(find.text("Client Profile"));
    });

    // i. offers
    await step("i offers", () async {
      final res = await http.get(Uri.parse("${ApiService.baseUrl}/api/offers"));
      final live = ((jsonDecode(res.body)["offers"] as List))
          .where((o) => o["isValid"] == true)
          .map((o) => o["code"].toString())
          .toSet();
      await tap(find.text("Privilege Offers & Vouchers"));
      await waitFor(find.text("Privilege Offers"));
      await waitFor(find.textContaining("CODE: "));
      final shown = (find.textContaining("CODE: ").evaluate().first.widget as Text).data!.replaceFirst("CODE: ", "");
      // ignore: avoid_print
      print("FEATURED CODE: $shown, live codes: $live");
      expect(live.contains(shown), isTrue, reason: "featured code $shown not in live offers $live");
      await back();
      await waitFor(find.text("Client Profile"));
    });

    // j. profile, edit name, logout
    await step("j profile edit + logout", () async {
      await scrollTo(find.text(email));
      await tap(find.text("Edit Details →"));
      await waitFor(find.text("Edit Client Credentials"));
      await enter(find.descendant(of: find.byType(AlertDialog), matching: field("Full Name")), "UI Smoke Edited");
      await tap(find.text("Save Changes"));
      await waitFor(find.text("Credentials updated successfully"));
      await waitFor(find.text("UI Smoke Edited"));
      await waitNoSnack();
      await tap(find.text("SIGN OUT OF MAISON SESSION"));
      await tap(find.descendant(of: find.byType(AlertDialog), matching: find.text("Sign Out")));
      await waitFor(find.text("LOGIN"));
    });

    // k. forgot password with devOtp, then log in with the new password
    await step("k forgot password", () async {
      await tap(find.text("Forgot Password?"));
      await enter(field("Email Address"), email);
      await tap(find.text("SEND OTP"));
      await waitFor(find.textContaining("Dev code:"));
      final msg = (find.textContaining("Dev code:").evaluate().first.widget as Text).data!;
      final otp = RegExp(r"(\d{6})").firstMatch(msg)!.group(1)!;
      await enter(field("Enter OTP"), otp);
      await enter(field("New Password"), newPassword);
      await enter(field("Confirm Password"), newPassword);
      await waitNoSnack();
      await tap(find.text("RESET PASSWORD"));
      await waitFor(find.text("LOGIN"));
      await waitNoSnack();
      await enter(field("Email Address"), email);
      await enter(field("Password"), newPassword);
      await tap(find.text("LOGIN"));
      await waitFor(find.text("Masterpiece Catalog"));
    });

    // main() installs its own handlers; the test binding requires the originals back.
    FlutterError.onError = testOnError;
    ErrorWidget.builder = testErrorWidget;
    // ignore: avoid_print
    print("==== RESULTS ($email) ====");
    results.forEach((k, v) => print("$k: $v")); // ignore: avoid_print
    // ignore: avoid_print
    print("==== FLUTTER ERRORS (${flutterErrors.length}) ====\n${flutterErrors.join("\n")}");
    expect(results.values.where((v) => v != "PASS"), isEmpty);
    expect(flutterErrors, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
