// Round-2 checks: empty/bad-type auth bodies, OTP reset race, per-user coupon
// limit on validate-coupon, items cap, no reviews in product lists.
// Needs a running server (NODE_ENV=development, so forgot-password returns devOtp)
// on a throwaway, seeded local DB, and the same MONGO_URI here (orders are
// created directly to simulate a prior coupon use):
//   MONGO_URI=mongodb://127.0.0.1:27091/r1a node seed/product.js && ... seed/offer.js
//   MONGO_URI=... PORT=5111 JWT_SECRET=<48-byte hex> NODE_ENV=development node server.js
//   MONGO_URI=... node test_round2_auth_offer.js   # BASE_URL defaults to http://127.0.0.1:5111
// Uses 19 reset-password calls: the limiter allows 20 / 15 min per IP, so
// restart the server before re-running.
const assert = require("assert");
const mongoose = require("mongoose");
const Order = require("./models/Order");
const Offer = require("./models/Offer");

const BASE_URL = process.env.BASE_URL || "http://127.0.0.1:5111";
const MONGO_URI = process.env.MONGO_URI || "";

if (!/^mongodb:\/\/(127\.0\.0\.1|localhost)[:/]/.test(MONGO_URI)) {
  console.error("Refusing to run: MONGO_URI must point at a local throwaway DB");
  process.exit(1);
}

const call = async (method, path, body, token, rawBody) => {
  const res = await fetch(BASE_URL + path, {
    method,
    headers: {
      ...(body !== undefined ? { "Content-Type": "application/json" } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: rawBody ?? (body !== undefined ? JSON.stringify(body) : undefined),
  });
  return { status: res.status, data: await res.json() };
};

const main = async () => {
  // --- Missing / bad-type bodies -> 400 JSON, never 500
  for (const path of ["/api/auth/login", "/api/auth/register", "/api/auth/forgot-password"]) {
    const r = await call("POST", path);
    assert.strictEqual(r.status, 400, `empty body ${path}`);
    assert.strictEqual(r.data.success, false, `JSON error ${path}`);
  }
  let r = await call("POST", "/api/auth/login", { email: { $gt: "" }, password: "x" });
  assert.strictEqual(r.status, 400, "object email login");
  r = await call("POST", "/api/auth/register", { name: "X", email: ["a@b.c"], password: "secret1" });
  assert.strictEqual(r.status, 400, "array email register");
  r = await call("POST", "/api/auth/register", { name: "X", email: "a@b.c", password: "secret1", phone: { a: 1 } });
  assert.strictEqual(r.status, 400, "object phone register");
  console.log("ok  empty / bad-type auth bodies -> 400");

  // --- Account
  const email = `r2_${Date.now()}@example.com`;
  const password = "oldpass123";
  r = await call("POST", "/api/auth/register", { name: "Round Two", email, password, phone: "9999999999" });
  assert.strictEqual(r.status, 201, "register");
  r = await call("POST", "/api/auth/login", { email, password });
  assert.strictEqual(r.status, 200, "login");
  const token = r.data.token;
  const userId = r.data.user.id;

  r = await call("PUT", "/api/auth/profile", { phone: 12345 }, token);
  assert.strictEqual(r.status, 400, "number phone update");
  console.log("ok  updateProfile bad type -> 400");

  // --- Reset: lockout, then parallel correct guesses must all fail
  r = await call("POST", "/api/auth/forgot-password", { email });
  const otp = r.data.devOtp;
  assert.ok(otp, "devOtp present (NODE_ENV=development)");
  r = await call("POST", "/api/auth/reset-password", { email, otp: { $ne: "" }, newPassword: "hacked1" });
  assert.strictEqual(r.status, 400, "object otp -> 400");

  const wrong = otp === "000000" ? "111111" : "000000";
  for (let i = 1; i <= 5; i++) {
    r = await call("POST", "/api/auth/reset-password", { email, otp: wrong, newPassword: "hacked1" });
    assert.strictEqual(r.status, i < 5 ? 400 : 429, `wrong guess ${i}`);
  }
  const after = await Promise.all(
    Array.from({ length: 10 }, () =>
      call("POST", "/api/auth/reset-password", { email, otp, newPassword: "hacked1" })
    )
  );
  assert.ok(after.every((x) => x.status === 400), "no reset after lockout");
  r = await call("POST", "/api/auth/login", { email, password: "hacked1" });
  assert.strictEqual(r.status, 401, "locked-out password not set");
  console.log("ok  10 parallel resets after lockout all rejected");

  // --- Correct flow; concurrent replays of the same OTP: exactly one wins
  r = await call("POST", "/api/auth/forgot-password", { email });
  const otp2 = r.data.devOtp;
  const results = await Promise.all(
    ["newpass1", "newpass2", "newpass3"].map((newPassword) =>
      call("POST", "/api/auth/reset-password", { email, otp: otp2, newPassword })
    )
  );
  const winners = results.map((x, i) => [x.status, `newpass${i + 1}`]).filter(([s]) => s === 200);
  assert.strictEqual(winners.length, 1, "exactly one concurrent reset succeeds");
  r = await call("POST", "/api/auth/login", { email, password: winners[0][1] });
  assert.strictEqual(r.status, 200, "login with new password");
  const newToken = r.data.token;
  r = await call("POST", "/api/auth/login", { email, password });
  assert.strictEqual(r.status, 401, "old password rejected");
  console.log("ok  correct reset works, OTP single-use under concurrency");

  // --- Product lists carry no reviews; reviews endpoint hides userId
  r = await call("GET", "/api/products?limit=100");
  assert.strictEqual(r.status, 200);
  assert.ok(r.data.products.length > 0, "seeded products");
  assert.ok(r.data.products.every((p) => !("reviews" in p)), "no reviews in list");
  const pricey = r.data.products.find((p) => p.price >= 5000);
  r = await call("GET", "/api/products/search?search=a");
  assert.ok(r.data.products.every((p) => !("reviews" in p)), "no reviews in search");
  r = await call("GET", "/api/offers/discounted-products");
  assert.ok(r.data.products.every((p) => !("reviews" in p)), "no reviews in discounted");
  r = await call("GET", `/api/products/${pricey.id}`);
  assert.ok(!("reviews" in r.data.product), "no reviews in product detail");
  r = await call("POST", `/api/products/${pricey.id}/reviews`, { rating: 5, comment: "Lovely" }, newToken);
  assert.strictEqual(r.status, 201, "add review");
  r = await call("GET", `/api/products/${pricey.id}/reviews`);
  assert.ok(r.data.reviews.length > 0);
  assert.ok(r.data.reviews.every((x) => !("userId" in x) && "userName" in x && "rating" in x), "review shape");
  console.log("ok  no reviews in product lists; review list hides userId");

  // --- validate-coupon: items cap / type, per-user limit
  const items = [{ productId: pricey.id, quantity: 1 }];
  r = await call("POST", "/api/offers/validate-coupon", {
    couponCode: "MAISON10",
    items: Array.from({ length: 51 }, () => items[0]),
  });
  assert.strictEqual(r.status, 400, "51 items -> 400");
  r = await call("POST", "/api/offers/validate-coupon", { couponCode: "MAISON10", items: "x" });
  assert.strictEqual(r.status, 400, "non-array items -> 400");

  r = await call("POST", "/api/offers/validate-coupon", { couponCode: "MAISON10", items }, newToken);
  assert.strictEqual(r.status, 200, "unused once-per-user coupon valid");

  await mongoose.connect(MONGO_URI);
  await Order.create({
    userId,
    customerName: "Round Two",
    phone: "9999999999",
    address: "1 Test Street",
    couponCode: "maison10",
    totalAmount: 1,
  });

  r = await call("POST", "/api/offers/validate-coupon", { couponCode: "MAISON10", items }, newToken);
  assert.strictEqual(r.status, 400, "used once-per-user coupon -> 400");
  assert.match(r.data.message, /already been used on your account/);
  r = await call("POST", "/api/offers/validate-coupon", { couponCode: "MAISON10", items });
  assert.strictEqual(r.status, 200, "guest still previews");
  r = await call("POST", "/api/offers/validate-coupon", { couponCode: "MAISON10", items }, "garbage");
  assert.strictEqual(r.status, 200, "invalid token -> treated as guest");

  await Order.updateMany({ userId }, { status: "Cancelled" });
  r = await call("POST", "/api/offers/validate-coupon", { couponCode: "MAISON10", items }, newToken);
  assert.strictEqual(r.status, 200, "cancelled order frees the coupon");
  console.log("ok  validate-coupon items cap + per-user limit");

  // usageLimit null = unlimited (same as checkout)
  await Offer.updateOne({ code: "MAISON10" }, { $set: { usageLimit: null } });
  r = await call("GET", "/api/offers");
  assert.strictEqual(r.status, 200);
  assert.strictEqual(r.data.offers.find((o) => o.code === "MAISON10").isValid, true, "null usageLimit = valid");
  await Offer.updateOne({ code: "MAISON10" }, { $set: { usageLimit: 1000 } });
  console.log("ok  offers list treats null usageLimit as unlimited");

  console.log("\nAll round-2 auth/offer checks passed");
};

main()
  .catch((err) => {
    console.error("FAIL:", err.message);
    process.exitCode = 1;
  })
  .finally(() => mongoose.disconnect());
