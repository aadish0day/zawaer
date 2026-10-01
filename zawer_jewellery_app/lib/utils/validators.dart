// Permissive on purpose: accepts plus-addressing (user+tag@gmail.com) and
// long TLDs (a@shop.jewelry). The server is the real authority.
final RegExp _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

bool isValidEmail(String value) => _emailRegex.hasMatch(value.trim());
