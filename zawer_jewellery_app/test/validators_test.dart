import 'package:flutter_test/flutter_test.dart';
import 'package:zawer_jewellery_app/utils/validators.dart';

void main() {
  test('isValidEmail', () {
    expect(isValidEmail('user+tag@gmail.com'), isTrue);
    expect(isValidEmail(' a@shop.jewelry '), isTrue);
    expect(isValidEmail('no-at.example.com'), isFalse);
    expect(isValidEmail('a@b'), isFalse);
    expect(isValidEmail('a b@c.com'), isFalse);
  });

  test('isValidPhone matches the backend contract', () {
    expect(isValidPhone('9876543210'), isTrue);
    expect(isValidPhone('+91 98765-43210'), isTrue);
    expect(isValidPhone('(022) 1234567'), isFalse); // must start with + or digit
    expect(isValidPhone(' 1234567 '), isTrue); // 7 chars after trim
    expect(isValidPhone('123456'), isFalse); // too short
    expect(isValidPhone('1' * 20), isTrue);
    expect(isValidPhone('1' * 21), isFalse); // too long
    expect(isValidPhone('98765abcde'), isFalse);
    expect(isValidPhone(''), isFalse);
  });
}
