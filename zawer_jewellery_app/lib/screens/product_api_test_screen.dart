import 'package:flutter/material.dart';

import '../models/product_model.dart';
import '../services/api_service.dart';

class ProductApiTestScreen extends StatefulWidget {
  const ProductApiTestScreen({super.key});

  @override
  State<ProductApiTestScreen> createState() =>
      _ProductApiTestScreenState();
}

class _ProductApiTestScreenState
    extends State<ProductApiTestScreen> {
  bool isLoading = true;
  String errorMessage = "";

  List<Product> products = [];

  @override
  void initState() {
    super.initState();
    loadProducts();
  }

  Future<void> loadProducts() async {
    try {
      final result = await ApiService.getProducts();

      if (!mounted) return;

      if (result["success"] == true) {
        final List<dynamic> data =
            result["products"] ?? [];

        final List<Product> loadedProducts = data
            .map(
              (item) => Product.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
            .toList();

        setState(() {
          products = loadedProducts;
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
          errorMessage =
              result["message"]?.toString() ??
                  "Failed to load products";
        });
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        errorMessage = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Product API Test"),
      ),
      body: isLoading
          ? const Center(
        child: CircularProgressIndicator(),
      )
          : errorMessage.isNotEmpty
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            errorMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.red,
              fontSize: 16,
            ),
          ),
        ),
      )
          : products.isEmpty
          ? const Center(
        child: Text(
          "No products found",
          style: TextStyle(
            fontSize: 18,
          ),
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: products.length,
        itemBuilder: (context, index) {
          final product = products[index];

          return Card(
            margin: const EdgeInsets.only(
              bottom: 12,
            ),
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(
                  Icons.diamond,
                ),
              ),
              title: Text(
                product.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                "${product.category}  •  ₹${product.price.toStringAsFixed(0)}",
              ),
              trailing: Text(
                product.rating.toString(),
              ),
            ),
          );
        },
      ),
    );
  }
}