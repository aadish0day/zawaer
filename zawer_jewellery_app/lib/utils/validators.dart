// Permissive on purpose: accepts plus-addressing (user+tag@gmail.com) and
// long TLDs (a@shop.jewelry). The server is the real authority.
final RegExp _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

bool isValidEmail(String value) => _emailRegex.hasMatch(value.trim());

// Same contract the backend enforces: optional digits with an optional
// leading +, spaces, dashes and parentheses; 7-20 chars after trim.
final RegExp _phoneRegex = RegExp(r'^\+?[0-9][0-9 ()-]{6,19}$');

bool isValidPhone(String value) => _phoneRegex.hasMatch(value.trim());

// Field length limits shared with the backend.
const int maxNameLength = 100;
const int maxEmailLength = 254;
const int maxPhoneLength = 20;
const int minPasswordLength = 6;
const int maxPasswordLength = 128;
