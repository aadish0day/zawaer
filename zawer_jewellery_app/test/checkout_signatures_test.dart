import 'package:flutter_test/flutter_test.dart';
import 'package:zawer_jewellery_app/screens/checkout_screen.dart';

void main() {
  test('Buy Now key signature ignores price; coupon recheck signature does not', () {
    final a = [
      {'productId': 'p1', 'quantity': 2, 'price': 100.0},
    ];
    final repriced = [
      {'productId': 'p1', 'quantity': 2, 'price': 120.0},
    ];
    final requantified = [
      {'productId': 'p1', 'quantity': 3, 'price': 100.0},
    ];

    expect(buyNowKeySignature(a), buyNowKeySignature(repriced));
    expect(buyNowKeySignature(a), isNot(buyNowKeySignature(requantified)));
    expect(pricedItemsSignature(a), isNot(pricedItemsSignature(repriced)));
    expect(pricedItemsSignature(a), isNot(pricedItemsSignature(requantified)));
  });

  test('delivery length limits count code points, not UTF-16 units', () {
    final emoji = '\u{1F48D}'; // 2 UTF-16 units, 1 code point
    expect(validateCheckoutName(emoji * 100), isNull);
    expect(validateCheckoutName(emoji * 101), isNotNull);
    expect(validateCheckoutAddress(emoji * 500), isNull);
    expect(validateCheckoutAddress(emoji * 501), isNotNull);
  });
}
