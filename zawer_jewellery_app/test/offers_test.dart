import 'package:flutter_test/flutter_test.dart';
import 'package:zawer_jewellery_app/models/offer_model.dart';
import 'package:zawer_jewellery_app/models/product_model.dart';

void main() {
  group('Offers & Discounts Model & Core Logic Tests', () {
    test('OfferModel parses percentage discount payload correctly', () {
      final json = {
        "id": "offer_01",
        "code": "ROYAL20",
        "title": "Royal 20% Heritage Privilege",
        "description": "20% off on all valuations above 25k",
        "discountType": "percentage",
        "discountValue": 20,
        "maxDiscount": 10000,
        "minOrderAmount": 25000,
        "applicableCategory": "All",
        "expiryDate": DateTime.now().add(const Duration(days: 30)).toIso8601String(),
        "isExpired": false,
        "daysRemaining": 30,
        "hoursRemaining": 0,
        "isValid": true,
        "tag": "MAISON EXCLUSIVE",
        "bannerImage": "assets/images/necklace.jpg",
        "terms": ["Valid on 18K solid gold."],
        "usedCount": 15,
      };

      final offer = OfferModel.fromJson(json);

      expect(offer.code, equals("ROYAL20"));
      expect(offer.discountType, equals("percentage"));
      expect(offer.discountValue, equals(20.0));
      expect(offer.maxDiscount, equals(10000.0));
      expect(offer.minOrderAmount, equals(25000.0));
      expect(offer.isExpired, isFalse);
      expect(offer.discountLabel, equals("20% OFF"));
      expect(offer.minOrderText, equals("On orders above ₹25000"));
    });

    test('OfferModel calculates percentage discount with max cap correctly', () {
      final offer = OfferModel(
        id: "1",
        code: "ROYAL20",
        title: "20% Off",
        description: "",
        discountType: "percentage",
        discountValue: 20,
        maxDiscount: 10000,
        minOrderAmount: 25000,
        applicableCategory: "All",
        isExpired: false,
        daysRemaining: 15,
        hoursRemaining: 0,
        isValid: true,
        tag: "",
        bannerImage: "",
        terms: [],
      );

      // Below min order
      expect(offer.calculateDiscount(20000), equals(0.0));

      // Exactly 30,000 (20% = 6,000, below 10,000 cap)
      expect(offer.calculateDiscount(30000), equals(6000.0));

      // Above cap: 60,000 (20% = 12,000, capped at 10,000)
      expect(offer.calculateDiscount(60000), equals(10000.0));
    });

    test('OfferModel calculates flat discount correctly', () {
      final flatOffer = OfferModel(
        id: "2",
        code: "SOLITAIRE5000",
        title: "Flat ₹5,000 Off",
        description: "",
        discountType: "flat",
        discountValue: 5000,
        maxDiscount: 5000,
        minOrderAmount: 35000,
        applicableCategory: "Ring",
        isExpired: false,
        daysRemaining: 20,
        hoursRemaining: 0,
        isValid: true,
        tag: "",
        bannerImage: "",
        terms: [],
      );

      expect(flatOffer.discountLabel, equals("FLAT ₹5000 OFF"));
      expect(flatOffer.calculateDiscount(30000), equals(0.0)); // Below min
      expect(flatOffer.calculateDiscount(40000), equals(5000.0));
    });

    test('OfferModel detects expired offers correctly', () {
      final pastDate = DateTime.now().subtract(const Duration(days: 5));
      final expiredOffer = OfferModel.fromJson({
        "id": "exp_01",
        "code": "EXPIRED50",
        "title": "Expired Promo",
        "description": "",
        "discountType": "percentage",
        "discountValue": 50,
        "maxDiscount": 0,
        "minOrderAmount": 0,
        "applicableCategory": "All",
        "expiryDate": pastDate.toIso8601String(),
        "isExpired": true,
        "daysRemaining": 0,
        "hoursRemaining": 0,
        "isValid": false,
        "tag": "",
        "bannerImage": "",
        "terms": [],
      });

      expect(expiredOffer.isExpired, isTrue);
    });

    test('Product model parses discount fields and computes savings', () {
      final productJson = {
        "id": "prod_disc_01",
        "name": "Imperial Solitaire Diamond Ring",
        "category": "Ring",
        "description": "VVS1 natural diamond",
        "price": 24000,
        "originalPrice": 30000,
        "discountPercentage": 20,
        "isSpecialOffer": true,
        "offerTag": "20% FESTIVE",
        "rating": 4.9,
        "images": ["assets/images/ring.png"],
      };

      final product = Product.fromJson(productJson);

      expect(product.hasDiscount, isTrue);
      expect(product.savingsAmount, equals(6000.0));
      expect(product.isSpecialOffer, isTrue);
      expect(product.offerTag, equals("20% FESTIVE"));
    });
  });
}
