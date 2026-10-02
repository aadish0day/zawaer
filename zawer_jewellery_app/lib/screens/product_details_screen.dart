import 'package:flutter/material.dart';
import '../utils/text_styles.dart';

import '../models/product_model.dart';
import '../services/api_service.dart';
import '../utils/colors.dart';
import 'checkout_screen.dart';
import 'login_screen.dart';

class ProductDetailsScreen extends StatefulWidget {
  final Product product;

  const ProductDetailsScreen({
    super.key,
    required this.product,
  });

  @override
  State<ProductDetailsScreen> createState() =>
      _ProductDetailsScreenState();
}

class _ProductDetailsScreenState
    extends State<ProductDetailsScreen> {

int quantity = 1;

bool isFavourite = false;

bool isAddingToCart = false;

bool isBuyingNow = false;

int currentImage = 0;

List<Map<String, dynamic>> reviews = [];

double averageRating = 0.0;

int totalReviews = 0;

bool isLoadingReviews = true;

bool isSubmittingReview = false;

@override
void initState() {
  super.initState();
  fetchReviews();
  checkWishlistStatus();
}

Future<void> checkWishlistStatus() async {
  final token = await ApiService.getToken();
  if (token.isEmpty) return;

  try {
    final wishResult = await ApiService.getWishlist();
    if (!mounted) return;
    if (wishResult["success"] == true) {
      final dynamic rawWish = wishResult["wishlist"];
      final List items = (rawWish?["items"] ?? []) as List;
      final bool exists = items.any(
        (item) => item["productId"]?.toString() == widget.product.id,
      );
      setState(() {
        isFavourite = exists;
      });
    }
  } catch (_) {}
}

void showLoginPromptDialog(String action) {
  showDialog(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            const Icon(Icons.lock_outline, color: AppColors.gold, size: 26),
            const SizedBox(width: 10),
            Text(
              "Sign In Required",
              style: AppFonts.cinzel(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Text(
          "Please sign in to your ZAWER account to $action and access your private vault.",
          style: AppFonts.poppins(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text("Cancel", style: AppFonts.poppins(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              ).then((_) => checkWishlistStatus());
            },
            child: Text(
              "Sign In",
              style: AppFonts.poppins(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );
    },
  );
}

// =====================================================
// FETCH REVIEWS
// =====================================================

Future<void> fetchReviews() async {
  setState(() {
    isLoadingReviews = true;
  });

  final result = await ApiService.getProductReviews(widget.product.id);

  if (!mounted) return;

  if (result["success"] == true) {
    setState(() {
      reviews = List<Map<String, dynamic>>.from(
        result["reviews"] ?? [],
      );
      averageRating = (result["averageRating"] ?? 0.0).toDouble();
      totalReviews = result["totalReviews"] ?? 0;
      isLoadingReviews = false;
    });
  } else {
    setState(() {
      isLoadingReviews = false;
    });
  }
}

// =====================================================
// SUBMIT REVIEW
// =====================================================

// Returns null on success, else the error to show in the review dialog.
Future<String?> submitReview({
  required int rating,
  required String comment,
}) async {
  setState(() {
    isSubmittingReview = true;
  });

  final result = await ApiService.addProductReview(
    productId: widget.product.id,
    rating: rating,
    comment: comment,
  );

  if (!mounted) return null;

  setState(() {
    isSubmittingReview = false;
  });

  if (result["success"] != true) {
    return result["message"]?.toString() ?? "Could not submit review";
  }

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text("Review submitted successfully"),
      backgroundColor: Colors.green,
    ),
  );
  fetchReviews();
  return null;
}

// =====================================================
// SHOW REVIEW DIALOG
// =====================================================

void showReviewDialog() {
  int selectedRating = 0;
  String? reviewError;
  final commentController = TextEditingController();

  showDialog(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              "Write a Review",
              style: AppFonts.cinzel(
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Rate this product",
                  style: AppFonts.poppins(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return IconButton(
                      icon: Icon(
                        index < selectedRating
                            ? Icons.star
                            : Icons.star_border,
                        color: Colors.amber,
                        size: 32,
                      ),
                      onPressed: () {
                        setDialogState(() {
                          selectedRating = index + 1;
                        });
                      },
                    );
                  }),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: commentController,
                  maxLines: 4,
                  minLines: 3,
                  maxLength: 1000,
                  decoration: InputDecoration(
                    hintText: "Write your review...",
                    errorText: reviewError,
                    errorMaxLines: 3,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                onPressed: isSubmittingReview || selectedRating == 0
                    ? null
                    : () async {
                        final comment = commentController.text.trim();
                        if (comment.isEmpty) {
                          setDialogState(() => reviewError = "Please write a review");
                          return;
                        }
                        // The dialog stays open (text kept) until the server
                        // accepts the review.
                        final pending = submitReview(
                          rating: selectedRating,
                          comment: comment,
                        );
                        setDialogState(() => reviewError = null);
                        final error = await pending;
                        if (!dialogContext.mounted) return;
                        if (error == null) {
                          Navigator.pop(dialogContext);
                        } else {
                          setDialogState(() => reviewError = error);
                        }
                      },
                child: isSubmittingReview
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        "Submit",
                        style: TextStyle(color: Colors.white),
                      ),
              ),
            ],
          );
        },
      );
    },
  ).then((_) {
    commentController.dispose();
  });
}

//==========================
// Wishlist Toggle
//==========================

bool isTogglingFavourite = false;

Future<void> toggleFavourite() async {
if (isTogglingFavourite) return;
isTogglingFavourite = true;
try {
  await _toggleFavourite();
} finally {
  isTogglingFavourite = false;
}
}

Future<void> _toggleFavourite() async {
final token = await ApiService.getToken();
if (!mounted) return;
if (token.isEmpty) {
  showLoginPromptDialog("save items to your wishlist");
  return;
}

final result = isFavourite
? await ApiService.removeFromWishlist(widget.product.id)
: await ApiService.addToWishlist(widget.product.id);

if (!mounted) {
return;
}

if (result["success"] == true) {
setState(() {
isFavourite = !isFavourite;
});
}

ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text(
result["message"]?.toString() ??
"Wishlist updated",
),
),
);

}

//==========================
// Add To Cart
//==========================

Future<bool> addProductToCart() async {
final token = await ApiService.getToken();
if (!mounted) return false;
if (token.isEmpty) {
  showLoginPromptDialog("add items to your cart");
  return false;
}

setState(() {
isAddingToCart = true;
});

final result = await ApiService.addToCart(
productId: widget.product.id,
quantity: quantity,
);

if (!mounted) {
return false;
}

setState(() {
isAddingToCart = false;
});

ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text(
result["success"] == true
? "${widget.product.name} added to cart"
: result["message"]?.toString() ??
"Could not add to cart",
),
),
);

return result["success"] == true;
}

@override
Widget build(BuildContext context) {

final product = widget.product;

return Scaffold(
backgroundColor: Theme.of(context).scaffoldBackgroundColor,

appBar: AppBar(
backgroundColor: Theme.of(context).colorScheme.surface,
elevation: 0,

iconTheme: IconThemeData(
color: Theme.of(context).colorScheme.onSurface,
),

title: Text(
product.name,
style: AppFonts.cinzel(
color: AppColors.brand(context),
fontWeight: FontWeight.bold,
letterSpacing: 1,
),
),

centerTitle: true,

actions: [

IconButton(
onPressed: toggleFavourite,
icon: Icon(
isFavourite
? Icons.favorite
: Icons.favorite_border,
color: Colors.red,
),
),

],
),

body: SingleChildScrollView(

child: Column(

crossAxisAlignment:
CrossAxisAlignment.start,

children: [
//==========================
// Product Images
//==========================

Container(
height: 360,
width: double.infinity,
color: Theme.of(context).colorScheme.surface,

child: Column(
children: [

Expanded(

child: PageView.builder(

itemCount: product.images.length,

onPageChanged: (index) {
setState(() {
currentImage = index;
});
},

itemBuilder: (context, index) {

return Padding(

padding: const EdgeInsets.all(20),

child: Hero(

tag: index == 0 ? product.id : "${product.id}_$index",

child: Image.asset(
product.images[index],
fit: BoxFit.contain,

errorBuilder:
(context, error, stackTrace) {
return const Center(
child: Icon(
Icons.image_not_supported,
size: 80,
color: Colors.grey,
),
);
},
),

),

);

},

),

),

const SizedBox(height: 10),

Row(

mainAxisAlignment:
MainAxisAlignment.center,

children: List.generate(

product.images.length,

(index) => AnimatedContainer(

duration:
const Duration(milliseconds: 250),

margin:
const EdgeInsets.symmetric(horizontal: 4),

height: 8,

width: currentImage == index ? 22 : 8,

decoration: BoxDecoration(

color: currentImage == index
? AppColors.brand(context)
: Colors.grey.shade400,

borderRadius:
BorderRadius.circular(20),

),

),

),

),

const SizedBox(height: 18),

],
),
),

const SizedBox(height: 20),

Padding(

padding:
const EdgeInsets.symmetric(horizontal: 20),

child: Column(

crossAxisAlignment:
CrossAxisAlignment.start,

children: [
//==========================
// Product Name
//==========================

Text(
product.name,
style: AppFonts.cinzel(
fontSize: 28,
fontWeight: FontWeight.bold,
color: Theme.of(context).colorScheme.onSurface,
),
),

const SizedBox(height: 10),

//==========================
// Rating
//==========================

Row(
children: [

const Icon(
Icons.star,
color: Colors.amber,
size: 20,
),

const SizedBox(width: 5),

Text(
(totalReviews > 0 ? averageRating : product.rating).toStringAsFixed(1),
style: AppFonts.poppins(
fontWeight: FontWeight.w600,
fontSize: 16,
),
),

const SizedBox(width: 8),

Text(
isLoadingReviews
? ""
: totalReviews > 0
? "($totalReviews ${totalReviews == 1 ? "Review" : "Reviews"})"
: "(No reviews yet)",
style: AppFonts.poppins(
color: Theme.of(context).colorScheme.onSurfaceVariant,
),
),

],
),

const SizedBox(height: 20),

//==========================
// Price
//==========================

Text(
"₹${product.price.toStringAsFixed(0)}",
style: AppFonts.poppins(
fontSize: 30,
fontWeight: FontWeight.bold,
color: AppColors.brand(context),
),
),

const SizedBox(height: 25),

//==========================
// Description
//==========================

Text(
"Description",
style: AppFonts.cinzel(
fontSize: 22,
fontWeight: FontWeight.bold,
color: AppColors.brand(context),
),
),

const SizedBox(height: 10),

Text(
product.description,
style: AppFonts.poppins(
fontSize: 15,
color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
height: 1.6,
),
),

const SizedBox(height: 25),

//==========================
// Quantity
//==========================

Text(
"Quantity",
style: AppFonts.cinzel(
fontSize: 22,
fontWeight: FontWeight.bold,
color: AppColors.brand(context),
),
),

const SizedBox(height: 12),

Row(
children: [

IconButton(
onPressed: () {
if (quantity > 1) {
setState(() {
quantity--;
});
}
},
icon: const Icon(
Icons.remove_circle_outline,
),
),

Container(
width: 55,
alignment: Alignment.center,
child: Text(
quantity.toString(),
style: AppFonts.poppins(
fontSize: 20,
fontWeight: FontWeight.bold,
),
),
),

IconButton(
onPressed: () {
if (quantity >= 10) return;
setState(() {
quantity++;
});
},
icon: const Icon(
Icons.add_circle_outline,
),
),

],
),

const SizedBox(height: 30),
//==========================
// Specifications
//==========================

Text(
"Specifications",
style: AppFonts.cinzel(
fontSize: 22,
fontWeight: FontWeight.bold,
color: AppColors.brand(context),
),
),

const SizedBox(height: 15),

buildSpecification(
"Metal",
"18K Gold",
),

buildSpecification(
"Diamond",
"Natural Diamond",
),

buildSpecification(
"Weight",
"7.5 gm",
),

buildSpecification(
"Purity",
"916 Hallmarked",
),

buildSpecification(
"Size",
"Adjustable",
),

buildSpecification(
"Warranty",
"Lifetime",
),

const SizedBox(height: 30),

//==========================
// Features
//==========================

Text(
"Features",
style: AppFonts.cinzel(
fontSize: 22,
fontWeight: FontWeight.bold,
color: AppColors.brand(context),
),
),

const SizedBox(height: 15),

buildFeature(
Icons.verified,
"100% Certified Jewellery",
),

buildFeature(
Icons.local_shipping,
"Free & Secure Shipping",
),

buildFeature(
Icons.autorenew,
"Easy 30-Day Return",
),

buildFeature(
Icons.workspace_premium,
"Lifetime Maintenance",
),

const SizedBox(height: 30),

//==========================
// Add To Cart Button
//==========================

SizedBox(
width: double.infinity,
height: 55,

child: ElevatedButton.icon(

onPressed: isAddingToCart
? null
: addProductToCart,

icon: isAddingToCart
? const SizedBox(
width: 22,
height: 22,
child: CircularProgressIndicator(
color: Colors.white,
strokeWidth: 2,
),
)
: const Icon(
Icons.shopping_cart,
color: Colors.white,
),

label: Text(
"ADD TO CART",
style: AppFonts.cinzel(
fontSize: 18,
fontWeight: FontWeight.bold,
color: Colors.white,
letterSpacing: 1,
),
),

style: ElevatedButton.styleFrom(
backgroundColor: AppColors.primary,
shape: RoundedRectangleBorder(
borderRadius:
BorderRadius.circular(15),
),
),
),

),

],

),

),

const SizedBox(height: 15),

//==========================
// Buy Now Button
//==========================

SizedBox(
width: double.infinity,
height: 55,

child: OutlinedButton.icon(

onPressed: isBuyingNow ? null : () async {
final navigator = Navigator.of(context);
setState(() => isBuyingNow = true);
final token = await ApiService.getToken();
if (!mounted) return;
if (token.isEmpty) {
  setState(() => isBuyingNow = false);
  showLoginPromptDialog("proceed to checkout");
  return;
}

// Check out only this piece at the selected qty; the cart is left untouched.
final product = widget.product;
await navigator.push(
MaterialPageRoute(
builder: (_) => CheckoutScreen(
buyNowItems: [
{
"productId": product.id,
"quantity": quantity,
"name": product.name,
"price": product.price,
"category": product.category,
"image": product.images.isNotEmpty
    ? product.images.first
    : "assets/images/ring.png",
},
],
),
),
);

if (mounted) setState(() => isBuyingNow = false);

},

icon: Icon(
Icons.flash_on,
color: AppColors.brand(context),
),

label: Text(
"BUY NOW",
style: AppFonts.cinzel(
fontSize: 18,
color: AppColors.brand(context),
fontWeight: FontWeight.bold,
letterSpacing: 1,
),
),

style: OutlinedButton.styleFrom(
side: BorderSide(
color: AppColors.brand(context),
width: 2,
),
shape: RoundedRectangleBorder(
borderRadius:
BorderRadius.circular(15),
),
),

),

),

const SizedBox(height: 30),
  //==========================
  // Delivery Information
  //==========================

  Container(
    padding: const EdgeInsets.all(18),

    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),

      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 10,
          offset: const Offset(0, 5),
        ),
      ],
    ),

    child: Column(
      children: [

        ListTile(
          leading: Icon(
            Icons.local_shipping,
            color: AppColors.brand(context),
          ),

          title: Text(
            "Free Delivery",
            style: AppFonts.poppins(
              fontWeight: FontWeight.bold,
            ),
          ),

          subtitle: Text(
            "Delivery within 3-5 business days.",
            style: AppFonts.poppins(),
          ),
        ),

        const Divider(),

        ListTile(
          leading: Icon(
            Icons.verified_user,
            color: AppColors.brand(context),
          ),

          title: Text(
            "100% Hallmarked",
            style: AppFonts.poppins(
              fontWeight: FontWeight.bold,
            ),
          ),

          subtitle: Text(
            "Certified BIS Hallmarked Jewellery.",
            style: AppFonts.poppins(),
          ),
        ),

        const Divider(),

        ListTile(
          leading: Icon(
            Icons.credit_card,
            color: AppColors.brand(context),
          ),

          title: Text(
            "Secure Payment",
            style: AppFonts.poppins(
              fontWeight: FontWeight.bold,
            ),
          ),

          subtitle: Text(
            "UPI, Cards, Net Banking & COD Available.",
            style: AppFonts.poppins(),
          ),
),

      ],
    ),
  ),

  const SizedBox(height: 30),

  //==========================
  // Reviews Section
  //==========================

  buildReviewsSection(),

  const SizedBox(height: 30),

]
),
),
);
}

//==========================
// Specification Widget
//==========================

Widget buildSpecification(
    String title,
    String value,
    ) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),

    child: Row(
      children: [

        Expanded(
          child: Text(
            title,
            style: AppFonts.poppins(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        Text(
          value,
          style: AppFonts.poppins(),
        ),

      ],
    ),
  );
}

//==========================
// Feature Widget
//==========================

Widget buildFeature(
    IconData icon,
    String text,
    ) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 15),

    child: Row(
      children: [

        Icon(
          icon,
          color: AppColors.brand(context),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: Text(
            text,
            style: AppFonts.poppins(),
          ),
        ),

      ],
    ),
  );
}

// =====================================================
// REVIEWS SECTION
// =====================================================

Widget buildReviewsSection() {
  return Container(
    padding: const EdgeInsets.all(18),

    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),

      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 10,
          offset: const Offset(0, 5),
        ),
      ],
    ),

    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,

          children: [

            Text(
              "Customer Reviews",
              style: AppFonts.cinzel(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.brand(context),
              ),
            ),

            if (totalReviews > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),

                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),

                child: Row(
                  mainAxisSize: MainAxisSize.min,

                  children: [

                    const Icon(Icons.star,
                        color: Colors.amber, size: 18),

                    const SizedBox(width: 4),

                    Text(
                      "${averageRating.toStringAsFixed(1)} ($totalReviews reviews)",
                      style: AppFonts.poppins(
                        fontWeight: FontWeight.w600,
                        color: Colors.amber.shade800,
                      ),
                    ),

                  ],
                ),
              ),
          ],
        ),

        const SizedBox(height: 20),

        if (isLoadingReviews)
          const Center(child: CircularProgressIndicator())
        else if (reviews.isEmpty)
          Column(
            children: [
              Icon(
                Icons.rate_review_outlined,
                size: 48,
                color: Theme.of(context)
                    .colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                "No reviews yet",
                style: AppFonts.cinzel(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Be the first to review this product!",
                style: AppFonts.poppins(
                  color: Theme.of(context)
                      .colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: showReviewDialog,
                icon: const Icon(Icons.add, color: Colors.white),
                label: Text(
                  "Write a Review",
                  style: AppFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          )
        else
          Column(
            children: [
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: reviews.length,
                separatorBuilder: (context, index) =>
                    const Divider(height: 20),
                itemBuilder: (context, index) {
                  final review = reviews[index];
                  return _buildReviewItem(review);
                },
              ),

              const SizedBox(height: 20),

              Center(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        AppColors.primary.withValues(alpha: 0.1),
                    foregroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: showReviewDialog,
                  icon: const Icon(Icons.add),
                  label: Text(
                    "Write a Review",
                    style: AppFonts.poppins(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),

      ],
    ),
  );
}

Widget _buildReviewItem(Map<String, dynamic> review) {
  final rating = (review["rating"] ?? 0).toInt();
  final userName = review["userName"] ?? "Anonymous";
  final comment = review["comment"] ?? "";
  final date = review["date"]?.toString() ?? "";

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,

    children: [

      Row(
        children: [

          CircleAvatar(
            backgroundColor:
                AppColors.primary.withValues(alpha: 0.2),
            child: Text(
              userName.isNotEmpty ? userName[0].toUpperCase() : "?",
              style: AppFonts.cinzel(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [

                Text(
                  userName,
                  style: AppFonts.cinzel(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),

                if (date.isNotEmpty)
                  Text(
                    _formatDate(date),
                    style: AppFonts.poppins(
                      color: Theme.of(context)
                          .colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),

              ],
            ),
          ),

          Row(
            children: List.generate(5, (index) {
              return Icon(
                index < rating ? Icons.star : Icons.star_border,
                color: Colors.amber,
                size: 18,
              );
            }),
          ),

        ],
      ),

      const SizedBox(height: 10),

      if (comment.isNotEmpty)
        Text(
          comment,
          style: AppFonts.poppins(),
        ),

    ],
  );
}

String _formatDate(String dateString) {
  try {
    final date = DateTime.parse(dateString).toLocal();
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return "${difference.inDays}d ago";
    } else if (difference.inHours > 0) {
      return "${difference.inHours}h ago";
    } else if (difference.inMinutes > 0) {
      return "${difference.inMinutes}m ago";
    } else {
      return "Just now";
    }
  } catch (_) {
    return dateString;
  }
}
}
