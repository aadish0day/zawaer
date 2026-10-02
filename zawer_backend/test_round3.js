// Round-3 checks: partial trackingNumber index, discount caps, offers without expiryDate,
// public getOfferByCode, 50-line cart cap, register/profile/order validation contract,
// forgot-password resend throttle, money rounding, idempotency replay window.
// Needs a running server (NODE_ENV=development, so forgot-password returns devOtp)
// on a throwaway, seeded local DB, and the same MONGO_URI here:
//   MONGO_URI=mongodb://127.0.0.1:27089/r3 node seed/product.js && ... seed/offer.js
//   MONGO_URI=... PORT=5121 JWT_SECRET=<48-byte hex> NODE_ENV=development node server.js
//   MONGO_URI=... node test_round3.js   # BASE_URL defaults to http://127.0.0.1:5121
// Uses ~20 register calls (ends by hitting the limiter), so restart the server before re-running.
const assert = require("assert");
const mongoose = require("mongoose");
const Order = require("./models/Order");
const Offer = require("./models/Offer");
const Product = require("./models/Product");
const User = require("./models/User");

const BASE_URL = process.env.BASE_URL || "http://127.0.0.1:5121";
const MONGO_URI = process.env.MONGO_URI || "";

if (!/^mongodb:\/\/(127\.0\.0\.1|localhost)[:/]/.test(MONGO_URI)) {
  console.error("Refusing to run: MONGO_URI must point at a local throwaway DB");
  process.exit(1);
}

const call = async (method, path, body, token) => {
  const res = await fetch(BASE_URL + path, {
    method,
    headers: {
      ...(body !== undefined ? { "Content-Type": "application/json" } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, data: await res.json() };
};

const tag = Date.now().toString(36);
const order = (extra) => ({
  customerName: "Round Three",
  phone: "+91 98765-43210",
  address: "1 Test Street, Mumbai",
  items: [{ productId: "1", quantity: 1 }],
  fromCart: false,
  ...extra,
});

const main = async () => {
  await mongoose.connect(MONGO_URI);
  const orders = mongoose.connection.db.collection("orders");
  const offers = mongoose.connection.db.collection("offers");

  // --- 1. trackingNumber index is partial
  await Order.syncIndexes();
  const idx = (await orders.indexes()).filter((i) => i.key.trackingNumber === 1);
  assert.strictEqual(idx.length, 1, "exactly one trackingNumber index");
  assert.ok(idx[0].unique && idx[0].partialFilterExpression, "trackingNumber index is unique + partial");
  const legacy = { userId: `legacy_${tag}`, customerName: "L", phone: "1234567", address: "A", totalAmount: 1 };
  await orders.insertMany([{ ...legacy }, { ...legacy }, { ...legacy, trackingNumber: "" }, { ...legacy, trackingNumber: null }]);
  await orders.insertOne({ ...legacy, trackingNumber: `ZWR-T${tag}` });
  await assert.rejects(orders.insertOne({ ...legacy, trackingNumber: `ZWR-T${tag}` }), /E11000/, "real duplicates still rejected");
  console.log("ok  partial trackingNumber index: legacy orders without one coexist");

  // --- 2. Discount caps + percentage validator
  const pct = new Offer({ code: "X", title: "t", description: "d", discountType: "percentage", discountValue: 150, expiryDate: new Date(Date.now() + 864e5) });
  assert.strictEqual(pct.calculateDiscount(1000), 1000, "percent >100 capped at amount");
  await assert.rejects(pct.validate(), /discountValue/, "percentage > 100 rejected on save");
  const flat = new Offer({ code: "Y", title: "t", description: "d", discountType: "flat", discountValue: 5000, expiryDate: new Date() });
  assert.strictEqual(flat.calculateDiscount(1200), 1200, "flat capped at amount");
  await flat.validate(); // flat > 100 still valid
  await offers.insertOne({ code: `LEG150${tag}`.toUpperCase(), title: "t", description: "d", discountType: "percentage", discountValue: 150, minOrderAmount: 0, usageLimit: 0, isActive: true, startDate: new Date(0), expiryDate: new Date(Date.now() + 864e5) });
  const legacyOffer = await Offer.findOne({ code: `LEG150${tag}`.toUpperCase() });
  assert.ok(legacyOffer, "legacy >100% doc still readable");
  console.log("ok  discounts capped at order amount; percentage validator");

  // --- Accounts
  let r;
  for (const [body, label] of [
    [{ name: "A", email: `a_${tag}@example.com`, password: "12345" }, "short password"],
    [{ name: "A", email: `a_${tag}@example.com`, password: "x".repeat(129) }, "long password"],
    [{ name: "A", email: `a_${tag}@example.com`, password: "secret1", phone: "abc123" }, "bad phone"],
    [{ name: "A", email: "not-an-email", password: "secret1" }, "bad email"],
    [{ name: "A".repeat(101), email: `a_${tag}@example.com`, password: "secret1" }, "long name"],
  ]) {
    r = await call("POST", "/api/auth/register", body);
    assert.strictEqual(r.status, 400, label);
  }
  console.log("ok  register contract violations -> 400");

  const dupEmail = `dup_${tag}@example.com`;
  const dups = await Promise.all(
    Array.from({ length: 5 }, () => call("POST", "/api/auth/register", { name: "Dup", email: dupEmail, password: "secret1" }))
  );
  assert.strictEqual(dups.filter((x) => x.status === 201).length, 1, "one concurrent register wins");
  assert.ok(dups.every((x) => x.status === 201 || (x.status === 400 && x.data.message === "User already exists")), "losers get 400");
  console.log("ok  concurrent duplicate register -> one 201, rest 400");

  const email = `r3_${tag}@example.com`;
  r = await call("POST", "/api/auth/register", { name: "  Round Three  ", email, password: "secret1", phone: "" });
  assert.strictEqual(r.status, 201, "register with empty phone");
  r = await call("POST", "/api/auth/login", { email, password: "secret1" });
  const token = r.data.token;
  const userId = r.data.user.id;

  r = await call("PUT", "/api/auth/profile", { phone: "abc" }, token);
  assert.strictEqual(r.status, 400, "profile bad phone");
  r = await call("PUT", "/api/auth/profile", { phone: "022 (1234)-5678" }, token);
  assert.strictEqual(r.status, 200, "profile good phone");
  r = await call("PUT", "/api/auth/profile", { phone: "" }, token);
  assert.strictEqual(r.status, 200, "profile clears phone");
  assert.strictEqual(r.data.user.phone, "", "phone cleared");
  r = await call("PUT", "/api/auth/profile", { name: "N".repeat(101) }, token);
  assert.strictEqual(r.status, 400, "profile long name");
  console.log("ok  profile phone/name contract");

  // --- 6. forgot-password resend throttle
  r = await call("POST", "/api/auth/forgot-password", { email });
  const firstOtp = r.data.devOtp;
  assert.ok(firstOtp, "first OTP issued");
  const before = await User.findById(userId).lean();
  await User.updateOne({ _id: userId }, { $set: { otpAttempts: 3 } });
  const second = await call("POST", "/api/auth/forgot-password", { email });
  assert.strictEqual(second.status, 200, "second forgot = 200");
  assert.strictEqual(second.data.message, r.data.message, "same generic message");
  assert.strictEqual(second.data.devOtp, undefined, "no new OTP within 60s");
  const afterU = await User.findById(userId).lean();
  assert.strictEqual(afterU.otpCode, before.otpCode, "first OTP kept");
  assert.strictEqual(afterU.otpAttempts, 3, "attempts not reset");
  // A lockout clears otpCode but must not allow an instant re-issue
  await User.updateOne({ _id: userId }, { $set: { otpCode: "", otpExpiry: null, otpAttempts: 0 } });
  const afterLockout = await call("POST", "/api/auth/forgot-password", { email });
  assert.strictEqual(afterLockout.data.devOtp, undefined, "no new OTP right after lockout");
  // After 60s a new one is issued
  await User.updateOne({ _id: userId }, { $set: { otpIssuedAt: new Date(Date.now() - 61000) } });
  r = await call("POST", "/api/auth/forgot-password", { email });
  assert.ok(r.data.devOtp, "new OTP after 60s");
  r = await call("POST", "/api/auth/reset-password", { email, otp: r.data.devOtp, newPassword: "secret2" });
  assert.strictEqual(r.status, 200, "reset with fresh OTP");
  r = await call("POST", "/api/auth/login", { email, password: "secret2" });
  const tok = r.data.token;
  console.log("ok  forgot-password within 60s keeps the first OTP");

  // --- 3/4. Offers without expiryDate; getOfferByCode public shape
  const noExp = `NOEXP${tag}`.toUpperCase();
  await offers.insertOne({ code: noExp, title: "No expiry", description: "d", discountType: "flat", discountValue: 100, minOrderAmount: 0, usageLimit: 0, isActive: true, startDate: new Date(0) });
  r = await call("GET", "/api/offers");
  assert.strictEqual(r.status, 200, "offers list with missing expiry");
  const listed = r.data.offers.find((o) => o.code === noExp);
  assert.ok(listed && listed.isExpired === false && listed.daysRemaining === null && listed.isValid, "no expiry = valid");
  assert.ok(r.data.offers.every((o) => o.usedCount === undefined), "list hides usedCount");
  r = await call("POST", "/api/offers/validate-coupon", { couponCode: noExp, items: [{ productId: "1", quantity: 1 }] });
  assert.strictEqual(r.status, 200, "validate coupon without expiry");
  r = await call("GET", `/api/offers/${noExp}`);
  assert.strictEqual(r.status, 200, "getOfferByCode without expiry");
  r = await call("POST", "/api/orders", order({ couponCode: noExp }), tok);
  assert.strictEqual(r.status, 201, "checkout with no-expiry coupon");
  assert.strictEqual(r.data.order.discountAmount, 100, "discount applied");

  r = await call("GET", "/api/offers/royal20");
  assert.strictEqual(r.status, 200, "getOfferByCode");
  for (const k of ["usageLimit", "perUserLimit", "usedCount", "__v", "_id"]) {
    assert.strictEqual(r.data.offer[k], undefined, `getOfferByCode hides ${k}`);
  }
  assert.deepStrictEqual(Object.keys(r.data.offer).sort(), Object.keys(listed).sort(), "same shape as list");
  await offers.insertOne({ code: `OFF${tag}`.toUpperCase(), title: "t", description: "d", discountType: "flat", discountValue: 1, isActive: false, expiryDate: new Date(Date.now() + 864e5) });
  r = await call("GET", `/api/offers/OFF${tag}`);
  assert.strictEqual(r.status, 404, "inactive offer hidden");
  console.log("ok  missing expiryDate = no expiry everywhere; getOfferByCode public + active only");

  // --- percentage >100 legacy doc can't make total negative
  r = await call("POST", "/api/orders", order({ couponCode: legacyOffer.code }), tok);
  assert.strictEqual(r.status, 201, "checkout with legacy 150%");
  assert.strictEqual(r.data.order.totalAmount, 0, "total floored at 0");
  assert.strictEqual(r.data.order.discountAmount, r.data.order.subtotal, "discount = subtotal");
  console.log("ok  legacy >100% offer discount capped at subtotal");

  // --- 7. Money rounding
  await Product.create({ id: `cent_${tag}`, name: "Cent", category: "Ring", description: "d", price: 0.1 });
  r = await call("POST", "/api/orders", order({ items: [{ productId: `cent_${tag}`, quantity: 3 }] }), tok);
  assert.strictEqual(r.status, 201, "fractional order");
  assert.strictEqual(r.data.order.subtotal, 0.3, "subtotal rounded");
  assert.strictEqual(r.data.order.totalAmount, 0.3, "total rounded");
  r = await call("POST", "/api/offers/validate-coupon", { couponCode: noExp, items: [{ productId: `cent_${tag}`, quantity: 3 }] });
  assert.strictEqual(r.status, 200, "validate fractional");
  assert.strictEqual(r.data.coupon.subtotal, 0.3, "validate subtotal rounded");
  assert.strictEqual(r.data.coupon.finalAmount, 0, "validate final rounded/capped");
  assert.strictEqual(r.data.coupon.discountAmount, 0.3, "flat discount capped at amount");
  console.log("ok  money rounded to 2 decimals");

  // --- placeOrder contact contract
  r = await call("POST", "/api/orders", order({ phone: "call me" }), tok);
  assert.strictEqual(r.status, 400, "order bad phone");
  r = await call("POST", "/api/orders", order({ phone: "" }), tok);
  assert.strictEqual(r.status, 400, "order empty phone");
  r = await call("POST", "/api/orders", order({ address: "x".repeat(501) }), tok);
  assert.strictEqual(r.status, 400, "order long address");
  console.log("ok  placeOrder phone/name/address contract");

  // --- 9. Idempotency replay window
  const key = `key_${tag}`;
  const first = await call("POST", "/api/orders", order({ idempotencyKey: key }), tok);
  assert.strictEqual(first.status, 201, "keyed order");
  r = await call("POST", "/api/orders", order({ idempotencyKey: key }), tok);
  assert.strictEqual(r.status, 200, "recent replay");
  assert.strictEqual(r.data.order._id, first.data.order._id, "same order replayed");
  await orders.updateOne({ _id: new mongoose.Types.ObjectId(first.data.order._id) }, { $set: { createdAt: new Date(Date.now() - 25 * 3600e3) } });
  r = await call("POST", "/api/orders", order({ idempotencyKey: key }), tok);
  assert.strictEqual(r.status, 409, "old key -> 409");
  assert.strictEqual(r.data.idempotencyConflict, true, "idempotencyConflict flag");
  assert.strictEqual(await Order.countDocuments({ userId, idempotencyKey: key }), 1, "no second order");
  console.log("ok  idempotency key older than 24h -> 409");

  // --- 4. Cart line cap
  await Product.insertMany(
    Array.from({ length: 51 }, (_, i) => ({ id: `cap_${tag}_${i}`, name: `Cap ${i}`, category: "Ring", description: "d", price: 1 }))
  );
  for (let i = 0; i < 50; i++) {
    r = await call("POST", "/api/cart", { productId: `cap_${tag}_${i}` }, tok);
    assert.strictEqual(r.status, 200, `add line ${i}`);
  }
  r = await call("POST", "/api/cart", { productId: `cap_${tag}_50` }, tok);
  assert.strictEqual(r.status, 400, "51st line rejected");
  assert.strictEqual(r.data.message, "Your bag can hold at most 50 different pieces");
  r = await call("POST", "/api/cart", { productId: `cap_${tag}_0` }, tok);
  assert.strictEqual(r.status, 200, "existing line still increments at cap");
  const racers = await Promise.all(
    [1, 2, 3].map(() => call("POST", "/api/cart", { productId: `cap_${tag}_50` }, tok))
  );
  assert.ok(racers.every((x) => x.status === 400), "concurrent 51st adds rejected");
  r = await call("GET", "/api/cart", undefined, tok);
  assert.strictEqual(r.data.cart.items.length, 50, "cart holds 50 lines");
  console.log("ok  cart capped at 50 distinct lines");

  // --- register is rate limited
  let limited = false;
  for (let i = 0; i < 25 && !limited; i++) {
    r = await call("POST", "/api/auth/register", { name: "L", email: "bad", password: "x" });
    limited = r.status === 429;
  }
  assert.ok(limited, "register hits the limiter");
  console.log("ok  POST /api/auth/register is rate limited");

  console.log("\nAll round-3 checks passed");
};

main()
  .catch((err) => {
    console.error("FAIL:", err.message);
    process.exitCode = 1;
  })
  .finally(() => mongoose.disconnect());
