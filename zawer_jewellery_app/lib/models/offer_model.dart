class OfferModel {
  final String id;
  final String code;
  final String title;
  final String description;
  final String discountType; // "percentage" or "flat"
  final double discountValue;
  final double maxDiscount;
  final double minOrderAmount;
  final String applicableCategory;
  final DateTime? expiryDate;
  final bool isExpired;
  final int daysRemaining;
  final int hoursRemaining;
  final bool isValid;
  final String tag;
  final String bannerImage;
  final List<String> terms;
  final int usedCount;

  OfferModel({
    required this.id,
    required this.code,
    required this.title,
    required this.description,
    required this.discountType,
    required this.discountValue,
    required this.maxDiscount,
    required this.minOrderAmount,
    required this.applicableCategory,
    this.expiryDate,
    required this.isExpired,
    required this.daysRemaining,
    required this.hoursRemaining,
    required this.isValid,
    required this.tag,
    required this.bannerImage,
    required this.terms,
    this.usedCount = 0,
  });

  String get discountLabel {
    if (discountType == "percentage") {
      return "${discountValue.toStringAsFixed(0)}% OFF";
    } else {
      return "FLAT ₹${discountValue.toStringAsFixed(0)} OFF";
    }
  }

  // Same rule as the server's isAllCategories: blank or "All" means unrestricted.
  bool get isCategoryLimited {
    final c = applicableCategory.trim().toLowerCase();
    return c.isNotEmpty && c != "all";
  }

  String get minOrderText {
    if (minOrderAmount <= 0) return "No minimum order";
    return "On orders above ₹${minOrderAmount.toStringAsFixed(0)}";
  }

  // Mirrors Offer.calculateDiscount on the server, including the final
  // Math.round (same as roundToDouble for the non-negative values here).
  double calculateDiscount(double subtotal) {
    if (subtotal < minOrderAmount) return 0.0;
    double discount = 0.0;
    if (discountType == "percentage") {
      discount = (subtotal * discountValue) / 100.0;
      if (maxDiscount > 0 && discount > maxDiscount) {
        discount = maxDiscount;
      }
    } else if (discountType == "flat") {
      discount = discountValue > subtotal ? subtotal : discountValue;
    }
    return discount.roundToDouble();
  }

  factory OfferModel.fromJson(Map<String, dynamic> json) {
    DateTime? exp;
    if (json["expiryDate"] != null) {
      try {
        exp = DateTime.parse(json["expiryDate"].toString()).toLocal();
      } catch (_) {}
    }

    final bool expired = json["isExpired"] == true ||
        (exp != null && DateTime.now().isAfter(exp));

    return OfferModel(
      id: json["id"]?.toString() ?? json["_id"]?.toString() ?? "",
      code: json["code"]?.toString().toUpperCase() ?? "",
      title: json["title"]?.toString() ?? "",
      description: json["description"]?.toString() ?? "",
      discountType: json["discountType"]?.toString() ?? "percentage",
      discountValue: (json["discountValue"] as num?)?.toDouble() ?? 0.0,
      maxDiscount: (json["maxDiscount"] as num?)?.toDouble() ?? 0.0,
      minOrderAmount: (json["minOrderAmount"] as num?)?.toDouble() ?? 0.0,
      applicableCategory: json["applicableCategory"]?.toString() ?? "All",
      expiryDate: exp,
      isExpired: expired,
      daysRemaining: (json["daysRemaining"] as num?)?.toInt() ?? 0,
      hoursRemaining: (json["hoursRemaining"] as num?)?.toInt() ?? 0,
      isValid: json["isValid"] == true,
      tag: json["tag"]?.toString() ?? "PRIVILEGE OFFER",
      bannerImage: json["bannerImage"]?.toString() ?? "assets/images/necklace.jpg",
      terms: json["terms"] is List
          ? List<String>.from((json["terms"] as List).map((e) => e.toString()))
          : [
              "Valid on certified 18K/22K gold & diamond jewellery.",
              "Subject to minimum purchase requirement.",
            ],
      usedCount: (json["usedCount"] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "code": code,
      "title": title,
      "description": description,
      "discountType": discountType,
      "discountValue": discountValue,
      "maxDiscount": maxDiscount,
      "minOrderAmount": minOrderAmount,
      "applicableCategory": applicableCategory,
      "expiryDate": expiryDate?.toIso8601String(),
      "isExpired": isExpired,
      "daysRemaining": daysRemaining,
      "hoursRemaining": hoursRemaining,
      "isValid": isValid,
      "tag": tag,
      "bannerImage": bannerImage,
      "terms": terms,
      "usedCount": usedCount,
    };
  }
}
