import 'package:flutter/material.dart';
import '../utils/text_styles.dart';

import '../models/product_model.dart';
import '../services/api_service.dart';
import '../utils/colors.dart';
import 'cart_screen.dart';
import 'product_details_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {

String selectedCategory = "All";

bool isLoadingProducts = true;

List<Product> apiProducts = [];

final TextEditingController searchController =
TextEditingController();

@override
void initState() {
super.initState();

loadProducts();
}

// =====================================================
// LOAD PRODUCTS FROM BACKEND (MongoDB)
// =====================================================

Future<void> loadProducts() async {
setState(() {
isLoadingProducts = true;
});

final result = await ApiService.getProducts();

if (!mounted) {
return;
}

if (result["success"] == true) {
final List productList =
(result["products"] ?? []) as List;

setState(() {
apiProducts = productList
.map((p) => Product.fromJson(
p as Map<String, dynamic>,
))
.toList();

isLoadingProducts = false;
});
} else {
setState(() {
isLoadingProducts = false;
});
}
}

List<Product> get allProducts => apiProducts;

final List<String> categories = [
"All",
"Ring",
"Necklace",
"Chain",
"Bracelet",
"Earrings",
];

@override
Widget build(BuildContext context) {

final filteredProducts = allProducts.where((product) {

final matchesCategory =
selectedCategory == "All" ||
product.category == selectedCategory;

final matchesSearch = product.name
.toLowerCase()
.contains(
searchController.text.toLowerCase(),
);

return matchesCategory && matchesSearch;

}).toList();

return Scaffold(

backgroundColor: Theme.of(context).scaffoldBackgroundColor,

appBar: AppBar(

backgroundColor: Theme.of(context).colorScheme.surface,

elevation: 0,

centerTitle: true,

title: Text(
"ZAWER",
style: AppFonts.cinzel(
color: AppColors.brand(context),
fontWeight: FontWeight.bold,
letterSpacing: 3,
),
),

actions: [

IconButton(

icon: const Icon(Icons.search),

onPressed: () {

showSearch(
context: context,
delegate: ProductSearchDelegate(allProducts),
);

},

),

IconButton(

icon: const Icon(Icons.shopping_cart),

onPressed: () {

Navigator.push(
context,
MaterialPageRoute(
builder: (_) => const CartScreen(),
),
);

},

),

],

),

body: Column(

children: [

const SizedBox(height: 15),

Padding(

padding: const EdgeInsets.symmetric(
horizontal: 15,
),

child: TextField(

controller: searchController,

onChanged: (value) {

setState(() {});

},

decoration: InputDecoration(

hintText: "Search Jewellery",

prefixIcon:
const Icon(Icons.search),

filled: true,

fillColor: Theme.of(context).colorScheme.surface,

border: OutlineInputBorder(

borderRadius:
BorderRadius.circular(15),

borderSide: BorderSide.none,

),

),

),

),

const SizedBox(height: 20),
SizedBox(
height: 45,
child: ListView.builder(
scrollDirection: Axis.horizontal,
itemCount: categories.length,
itemBuilder: (context, index) {
final category = categories[index];

return GestureDetector(
onTap: () {
setState(() {
selectedCategory = category;
});
},
child: Container(
margin: const EdgeInsets.symmetric(horizontal: 8),
padding: const EdgeInsets.symmetric(horizontal: 20),
decoration: BoxDecoration(
color: selectedCategory == category
? AppColors.brand(context)
: Theme.of(context).colorScheme.surface,
borderRadius: BorderRadius.circular(25),
border: Border.all(
color: AppColors.brand(context),
),
),
child: Center(
child: Text(
category,
style: AppFonts.poppins(
color: selectedCategory == category
? Colors.white
: AppColors.brand(context),
fontWeight: FontWeight.w600,
),
),
),
),
);
},
),
),

const SizedBox(height: 20),

Expanded(
child: isLoadingProducts && apiProducts.isEmpty
? const Center(
child: CircularProgressIndicator(),
)
: filteredProducts.isEmpty
? RefreshIndicator(
onRefresh: loadProducts,
child: ListView(
physics: const AlwaysScrollableScrollPhysics(),
children: [
const SizedBox(height: 60),
Center(
child: Column(
mainAxisAlignment: MainAxisAlignment.center,
children: [
Icon(
Icons.diamond_outlined,
size: 54,
color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
),
const SizedBox(height: 12),
Text(
"No jewellery found in this collection",
style: AppFonts.poppins(
fontSize: 14,
color: Theme.of(context).colorScheme.onSurfaceVariant,
),
),
const SizedBox(height: 14),
OutlinedButton.icon(
onPressed: loadProducts,
icon: const Icon(Icons.refresh, size: 16),
label: const Text("Refresh Collection"),
),
],
),
),
],
),
)
: RefreshIndicator(
onRefresh: loadProducts,
child: GridView.builder(
padding: const EdgeInsets.symmetric(horizontal: 15),
physics: const AlwaysScrollableScrollPhysics(),
itemCount: filteredProducts.length,

gridDelegate:
const SliverGridDelegateWithFixedCrossAxisCount(
crossAxisCount: 2,
crossAxisSpacing: 15,
mainAxisSpacing: 15,
childAspectRatio: 0.67,
),

itemBuilder: (context, index) {

final product = filteredProducts[index];

return GestureDetector(

onTap: () {

Navigator.push(
context,
MaterialPageRoute(
builder: (_) => ProductDetailsScreen(
product: product,
),
),
);

},

child: Container(

decoration: BoxDecoration(

color: Theme.of(context).colorScheme.surface,

borderRadius:
BorderRadius.circular(20),

boxShadow: [
BoxShadow(
color: Colors.black.withValues(alpha: 0.08),
blurRadius: 10,
offset: const Offset(0, 5),
),
],

),

child: Column(

crossAxisAlignment:
CrossAxisAlignment.start,

children: [

Expanded(

child: Hero(

tag: "product_${product.id}",

child: Container(

decoration: BoxDecoration(

borderRadius:
const BorderRadius.vertical(
top: Radius.circular(20),
),

image: DecorationImage(

image:
AssetImage(product.images.first),

fit: BoxFit.cover,

),

),

),

),

),
Padding(
padding: const EdgeInsets.all(12),
child: Column(
crossAxisAlignment:
CrossAxisAlignment.start,
children: [

Text(
product.name,
style: AppFonts.poppins(
fontWeight: FontWeight.bold,
fontSize: 16,
),
maxLines: 1,
overflow:
TextOverflow.ellipsis,
),

const SizedBox(height: 4),

Row(
children: [

const Icon(
Icons.star,
color: Colors.amber,
size: 16,
),

const SizedBox(width: 4),

Text(
product.rating.toString(),
style: AppFonts.poppins(
fontWeight: FontWeight.w600,
),
),

],
),

const SizedBox(height: 8),

Text(
"₹${product.price.toStringAsFixed(0)}",
style: AppFonts.cinzel(
color: AppColors.brand(context),
fontWeight: FontWeight.bold,
fontSize: 20,
),
),

const SizedBox(height: 12),

SizedBox(
width: double.infinity,
height: 40,

child: ElevatedButton(

style: ElevatedButton.styleFrom(
backgroundColor: AppColors.primary,
shape: RoundedRectangleBorder(
borderRadius:
BorderRadius.circular(12),
),
),

onPressed: () {

Navigator.push(
context,
MaterialPageRoute(
builder: (_) =>
ProductDetailsScreen(
product: product,
),
),
);

},

child: Text(
"View",
style: AppFonts.poppins(
color: Colors.white,
fontWeight: FontWeight.bold,
),
),

),
),

],
),
),

],
),
),
);

},

),

),
),
],
),
);
}
}

class ProductSearchDelegate extends SearchDelegate<String> {
  final List<Product> products;

  ProductSearchDelegate(this.products);

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = "";
        },
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, "");
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    final results = products.where((product) {
      return product.name
          .toLowerCase()
          .contains(query.toLowerCase()) ||
          product.category
              .toLowerCase()
              .contains(query.toLowerCase());
    }).toList();

    if (results.isEmpty) {
      return const Center(
        child: Text(
          "No jewellery found",
          style: TextStyle(fontSize: 18),
        ),
      );
    }

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final product = results[index];

        return ListTile(
          leading: Image.asset(
            product.images.first,
            width: 60,
            height: 60,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return const Icon(Icons.image_not_supported);
            },
          ),

          title: Text(product.name),

          subtitle: Text(
            "₹${product.price.toStringAsFixed(0)}",
          ),

          trailing: const Icon(Icons.arrow_forward_ios),

          onTap: () {
            close(context, "");

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProductDetailsScreen(
                  product: product,
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final suggestions = products.where((product) {
      return product.name
          .toLowerCase()
          .contains(query.toLowerCase()) ||
          product.category
              .toLowerCase()
              .contains(query.toLowerCase());
    }).toList();

    return ListView.builder(
      itemCount: suggestions.length,
      itemBuilder: (context, index) {
        final product = suggestions[index];

        return ListTile(
          leading: Image.asset(
            product.images.first,
            width: 60,
            height: 60,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return const Icon(Icons.image_not_supported);
            },
          ),

          title: Text(product.name),

          subtitle: Text(product.category),

          onTap: () {
            query = product.name;
            showResults(context);
          },
        );
      },
    );
  }
}