class Product {
  final String id;
  final String name;
  final String category;
  final String description;
  final double price;
  final double originalPrice;
  final double discountPercentage;
  final bool isSpecialOffer;
  final String offerTag;
  final double rating;
  final List<String> images;
  final bool isFavourite;

  Product({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.price,
    double? originalPrice,
    this.discountPercentage = 0.0,
    this.isSpecialOffer = false,
    this.offerTag = "",
    required this.rating,
    required this.images,
    this.isFavourite = false,
  }) : originalPrice = originalPrice ?? price;

  bool get hasDiscount => discountPercentage > 0 || originalPrice > price;

  double get savingsAmount => hasDiscount ? (originalPrice - price) : 0.0;

  factory Product.fromJson(Map<String, dynamic> json) {
    final double priceVal = (json["price"] as num?)?.toDouble() ?? 0.0;
    final double origPriceVal =
        (json["originalPrice"] as num?)?.toDouble() ?? priceVal;
    final double discPercent =
        (json["discountPercentage"] as num?)?.toDouble() ?? 0.0;

    return Product(
      id: json["id"]?.toString() ?? json["_id"]?.toString() ?? "",
      name: json["name"]?.toString() ?? "",
      category: json["category"]?.toString() ?? "",
      description: json["description"]?.toString() ?? "",
      price: priceVal,
      originalPrice: origPriceVal,
      discountPercentage: discPercent,
      isSpecialOffer: json["isSpecialOffer"] == true,
      offerTag: json["offerTag"]?.toString() ?? "",
      rating: (json["rating"] as num?)?.toDouble() ?? 0.0,
      images: json["images"] is List
          ? List<String>.from((json["images"] as List).map((image) => image.toString()))
          : [],
      isFavourite: json["isFavourite"] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "name": name,
      "category": category,
      "description": description,
      "price": price,
      "originalPrice": originalPrice,
      "discountPercentage": discountPercentage,
      "isSpecialOffer": isSpecialOffer,
      "offerTag": offerTag,
      "rating": rating,
      "images": images,
      "isFavourite": isFavourite,
    };
  }
}