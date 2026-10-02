import 'package:flutter_test/flutter_test.dart';
import 'package:zawer_jewellery_app/screens/checkout_screen.dart';

void main() {
  test('delivery field validators match the order contract', () {
    expect(validateCheckoutName(' '), isNotNull);
    expect(validateCheckoutName('A' * 100), isNull);
    expect(validateCheckoutName('A' * 101), isNotNull);

    expect(validateCheckoutPhone(''), isNotNull);
    expect(validateCheckoutPhone('+91 98765 43210'), isNull);
    expect(validateCheckoutPhone('022 (555) 0101'), isNull);
    expect(
      validateCheckoutPhone('(022) 555-0101'),
      isNotNull,
    ); // must start with + or digit
    expect(validateCheckoutPhone('12345'), isNotNull);
    expect(validateCheckoutPhone('phone123'), isNotNull);
    expect(validateCheckoutPhone('+${'1' * 20}'), isNotNull); // 21 chars

    expect(validateCheckoutAddress(''), isNotNull);
    expect(validateCheckoutAddress('x' * 500), isNull);
    expect(validateCheckoutAddress('x' * 501), isNotNull);
  });

  test('persisted Buy Now key is reused only when fresh and matching', () {
    final now = DateTime(2026, 10, 2, 12);
    String? key({String sig = 's', int? at}) => pendingBuyNowKey(
      signature: 's',
      storedKey: 'k',
      storedSignature: sig,
      storedAt: at,
      now: now,
    );
    int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch;

    expect(key(at: ago(const Duration(minutes: 5))), 'k');
    expect(key(at: ago(const Duration(minutes: 31))), isNull);
    expect(key(sig: 'other', at: ago(Duration.zero)), isNull);
    expect(key(), isNull); // legacy key without a timestamp
  });
}
