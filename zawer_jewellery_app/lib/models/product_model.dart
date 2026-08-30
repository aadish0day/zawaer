class Product {
  final String id;
  final String name;
  final String category;
  final String description;
  final double price;
  final double rating;
  final List<String> images;
  final bool isFavourite;

  Product({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.price,
    required this.rating,
    required this.images,
    this.isFavourite = false,
  });

  factory Product.fromJson(
      Map<String, dynamic> json,
      ) {
    return Product(
      id: json["id"]?.toString() ??
          json["_id"]?.toString() ??
          "",

      name: json["name"]?.toString() ?? "",

      category:
      json["category"]?.toString() ?? "",

      description:
      json["description"]?.toString() ?? "",

      price:
      (json["price"] as num?)?.toDouble() ??
          0.0,

      rating:
      (json["rating"] as num?)?.toDouble() ??
          0.0,

      images: json["images"] is List
          ? List<String>.from(
        (json["images"] as List).map(
              (image) => image.toString(),
        ),
      )
          : [],

      isFavourite:
      json["isFavourite"] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "name": name,
      "category": category,
      "description": description,
      "price": price,
      "rating": rating,
      "images": images,
      "isFavourite": isFavourite,
    };
  }
}