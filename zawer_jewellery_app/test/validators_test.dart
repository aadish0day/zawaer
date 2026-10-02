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
    for (final ok in [
      '(022) 2345 6789',
      '98765.43210',
      '+91 98765 43210',
      '098765-43210',
      '9876543210',
      ' 1234567 ',
      '1' * 15,
    ]) {
      expect(isValidPhone(ok), isTrue, reason: ok);
    }
    for (final bad in [
      '1------',
      '123456', // 6 digits
      '1' * 16, // 16 digits
      '+1 (234) 567-890-1234', // 21 chars
      '91+9876543210', // + not first
      '98765abcde',
      '',
    ]) {
      expect(isValidPhone(bad), isFalse, reason: bad);
    }
  });

  test('lengths count code points', () {
    expect(codePointLength('\u{1F48E}'), 1); // gem emoji: 2 UTF-16 units
    expect(validateName('\u{1F48E}' * 101), isNotNull);
    expect(validateName('a\u{1F48E}' * 50), isNull); // 100 code points
    expect(validateNewPassword('\u{1F48E}' * 128), isNull);
    expect(validateNewPassword('\u{1F48E}' * 129), isNotNull);
    expect(validateNewPassword('12345'), isNotNull);
  });
}
