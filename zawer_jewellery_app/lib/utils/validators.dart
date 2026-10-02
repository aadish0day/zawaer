// Permissive on purpose: accepts plus-addressing (user+tag@gmail.com) and
// long TLDs (a@shop.jewelry). The server is the real authority.
final RegExp _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

bool isValidEmail(String value) => _emailRegex.hasMatch(value.trim());

// Same contract the backend enforces: after trim, only digits, spaces,
// '-', '(', ')', '.' and a '+' as the first char; at most 20 chars and
// 7-15 digits.
final RegExp _phoneRegex = RegExp(r'^\+?[0-9 ()\-.]+$');

bool isValidPhone(String value) {
  final String v = value.trim();
  if (v.length > maxPhoneLength || !_phoneRegex.hasMatch(v)) return false;
  final int digits = v.replaceAll(RegExp(r'[^0-9]'), '').length;
  return digits >= 7 && digits <= 15;
}

// Lengths are counted in Unicode code points to match the backend
// (maxLength on a TextField counts graphemes, so it is only a UI hint).
int codePointLength(String s) => s.runes.length;

// Field length limits shared with the backend.
const int maxNameLength = 100;
const int maxEmailLength = 254;
const int maxPhoneLength = 20;
const int minPasswordLength = 6;
const int maxPasswordLength = 128;
const int maxAddressLength = 500;
const int maxReviewLength = 1000;

// Returns an error message, or null when the name is acceptable.
String? validateName(String? value) {
  final String v = value?.trim() ?? '';
  if (v.isEmpty) return "Please enter your full name";
  if (codePointLength(v) < 2) return "Enter a valid name";
  if (codePointLength(v) > maxNameLength) {
    return "Name must be at most $maxNameLength characters";
  }
  return null;
}

// For new passwords (register / reset). Login only checks non-empty.
String? validateNewPassword(String? value) {
  if (value == null || value.isEmpty) return "Password is required";
  final int len = codePointLength(value);
  if (len < minPasswordLength) {
    return "Password must contain at least $minPasswordLength characters";
  }
  if (len > maxPasswordLength) {
    return "Password must be at most $maxPasswordLength characters";
  }
  return null;
}
