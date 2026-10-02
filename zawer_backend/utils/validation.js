// Shared validation contract (the app enforces the same rules).

// Length in Unicode code points, so an emoji counts as one character.
const cpLen = (s) => [...s].length;

// Digits, spaces, ( ) . - and an optional leading +; at most 20 chars total, 7-15 digits.
const isValidPhone = (s) => {
  if (typeof s !== "string") return false;
  const p = s.trim();
  if (p.length > 20 || !/^\+?[0-9 ().-]+$/.test(p)) return false;
  const digits = p.replace(/\D/g, "").length;
  return digits >= 7 && digits <= 15;
};

// bcrypt only uses the first 72 bytes: 6-72 code points and at most 72 UTF-8 bytes.
const isValidPassword = (p) =>
  typeof p === "string" && cpLen(p) >= 6 && cpLen(p) <= 72 && Buffer.byteLength(p, "utf8") <= 72;

module.exports = { cpLen, isValidPhone, isValidPassword };
