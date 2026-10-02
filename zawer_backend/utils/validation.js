// Shared validation contract (the app enforces the same rules).

// Length in Unicode code points, so an emoji counts as one character.
const cpLen = (s) => [...s].length;

// Digits, spaces, ( ) . - and an optional leading +; at most 20 chars, 7-15 digits.
const isValidPhone = (s) => {
  if (typeof s !== "string") return false;
  const p = s.trim();
  if (!/^\+?[0-9 ().-]{1,19}$/.test(p)) return false;
  const digits = p.replace(/\D/g, "").length;
  return digits >= 7 && digits <= 15;
};

module.exports = { cpLen, isValidPhone };
