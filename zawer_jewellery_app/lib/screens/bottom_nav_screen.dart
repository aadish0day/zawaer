import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/colors.dart';
import 'home_screen.dart';
import 'wishlist_screen.dart';
import 'cart_screen.dart';
import 'profile_screen.dart';

class BottomNavScreen extends StatefulWidget {
  const BottomNavScreen({super.key});

  @override
  State<BottomNavScreen> createState() =>
      _BottomNavScreenState();
}

class _BottomNavScreenState
    extends State<BottomNavScreen> {

  int currentIndex = 0;

  final GlobalKey<HomeScreenState> homeKey =
  GlobalKey();

  final GlobalKey<WishlistScreenState>
  wishlistKey = GlobalKey();

  final GlobalKey<CartScreenState> cartKey =
  GlobalKey();

  late final List<Widget> screens = [

    HomeScreen(key: homeKey),

    WishlistScreen(key: wishlistKey),

    CartScreen(key: cartKey),

    const ProfileScreen(),

  ];

  @override
  Widget build(BuildContext context) {

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (currentIndex != 0) {
          homeKey.currentState?.loadWishlistState();
          setState(() {
            currentIndex = 0;
          });
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(

        body: IndexedStack(
        index: currentIndex,
        children: screens,
      ),

      bottomNavigationBar: BottomNavigationBar(

        currentIndex: currentIndex,

        selectedItemColor: AppColors.gold,

        unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,

        type: BottomNavigationBarType.fixed,

        backgroundColor: Theme.of(context).colorScheme.surface,

        onTap: (index){

          if (index == 0) {
            homeKey.currentState?.loadWishlistState();
          }

          if (index == 1) {
            wishlistKey.currentState
                ?.loadWishlist();
          }

          if (index == 2) {
            cartKey.currentState?.loadCart();
          }

          setState(() {

            currentIndex = index;

          });

        },

        items: const [

          BottomNavigationBarItem(

            icon: Icon(Icons.home),

            label: "Home",

          ),

          BottomNavigationBarItem(

            icon: Icon(Icons.favorite),

            label: "Wishlist",

          ),

          BottomNavigationBarItem(

            icon: Icon(Icons.shopping_cart),

            label: "Cart",

          ),

          BottomNavigationBarItem(

            icon: Icon(Icons.person),

            label: "Profile",

          ),

        ],

      ),

    ),

    );

  }

}