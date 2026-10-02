// Round-5 checks: idempotent replay compares the request, legacy wishlist items
// (stored with an _id) get normalized, 20-char phones, bcrypt 72-byte password cap,
// OTP backoff after a lockout. Controller-level, local throwaway DB only:
//   MONGO_URI=mongodb://127.0.0.1:27084/r5 node seed/product.js
//   MONGO_URI=mongodb://127.0.0.1:27084/r5 node test_round5.js
const assert = require("assert");
const mongoose = require("mongoose");
const Order = require("./models/Order");
const Wishlist = require("./models/Wishlist");
const Product = require("./models/Product");
const User = require("./models/User");
const { isValidPhone, isValidPassword } = require("./utils/validation");
const auth = require("./controllers/authController");
const orders = require("./controllers/orderController");
const { getWishlist } = require("./controllers/wishlistController");

const MONGO_URI = process.env.MONGO_URI || "";
if (!/^mongodb:\/\/(127\.0\.0\.1|localhost)[:/]/.test(MONGO_URI)) {
  console.error("Refusing to run: MONGO_URI must point at a local throwaway DB");
  process.exit(1);
}

const U = "r5_";
const tag = Date.now().toString(36);

async function call(fn, req) {
  const out = { status: 200, body: null };
  const res = {
    status(c) { out.status = c; return res; },
    json(d) { out.body = d; return res; },
  };
  await fn({ params: {}, body: {}, ...req }, res);
  return out;
}

const place = (userId, body) =>
  call(orders.placeOrder, {
    user: { id: userId },
    body: { customerName: "T", phone: "9876543210", address: "A, Mumbai", items: [{ productId: "1", quantity: 1 }], fromCart: false, ...body },
  });

async function cleanup() {
  await Order.deleteMany({ userId: { $regex: "^" + U } });
  await Wishlist.deleteMany({ userId: { $regex: "^" + U } });
  await User.deleteMany({ email: { $regex: "^r5_" } });
}

async function main() {
  await mongoose.connect(MONGO_URI);
  assert(await Product.findOne({ id: "1" }), "seed products first (node seed/product.js)");
  await cleanup();

  // --- 1. Replay only for the same request
  const key = "r5key" + tag;
  let r = await place(U + "idem", { idempotencyKey: key });
  assert.strictEqual(r.status, 201, "first order");
  const firstId = String(r.body.order._id);
  assert.strictEqual(r.body.order.requestHash, undefined, "hash not exposed on create");
  r = await place(U + "idem", { idempotencyKey: key });
  assert.strictEqual(r.status, 200, "same request replays");
  assert.strictEqual(String(r.body.order._id), firstId, "same order returned");
  assert.strictEqual(r.body.order.requestHash, undefined, "hash not exposed on replay");
  r = await place(U + "idem", { idempotencyKey: key, address: "Somewhere else" });
  assert.strictEqual(r.status, 409, "same key, different details -> 409");
  assert.strictEqual(r.body.idempotencyConflict, true);
  r = await place(U + "idem", { idempotencyKey: key, items: [{ productId: "1", quantity: 2 }] });
  assert.strictEqual(r.status, 409, "same key, different quantity -> 409");
  assert.strictEqual(await Order.countDocuments({ userId: U + "idem" }), 1, "still one order");
  // Orders saved before the fingerprint existed still replay
  await mongoose.connection.db.collection("orders").updateOne({ _id: new mongoose.Types.ObjectId(firstId) }, { $unset: { requestHash: "" } });
  r = await place(U + "idem", { idempotencyKey: key, address: "Somewhere else" });
  assert.strictEqual(r.status, 200, "legacy order without hash replays");
  console.log("ok  idempotent replay requires the same request");

  // --- 2. Legacy wishlist items stored with an _id are normalized
  const wl = mongoose.connection.db.collection("wishlists");
  const legacyProduct = await Product.findOne({ id: "2" });
  await wl.insertOne({
    userId: U + "wl",
    items: [
      { productId: "1", _id: new mongoose.Types.ObjectId() },
      { productId: legacyProduct._id.toString(), _id: new mongoose.Types.ObjectId() },
      { productId: "no-such-product", _id: new mongoose.Types.ObjectId() },
    ],
    createdAt: new Date(),
    updatedAt: new Date(),
  });
  r = await call(getWishlist, { user: { id: U + "wl" } });
  assert.strictEqual(r.status, 200);
  const stored = await wl.findOne({ userId: U + "wl" });
  assert.deepStrictEqual(stored.items.map((i) => i.productId), ["1", "2"], "legacy wishlist rewritten (ghost dropped, _id form canonicalized)");
  console.log("ok  legacy wishlist items with _id get normalized");

  // --- 3. Phone length 20 with or without +
  assert.ok(isValidPhone("(022) 2345-6789 0123"), "20 chars, no +");
  assert.ok(isValidPhone("+44 (0) 20 7946 0958"), "20 chars with +");
  assert.ok(!isValidPhone("(022) 2345-6789 01234"), "21 chars rejected");
  console.log("ok  phone: 20 chars allowed with or without +");

  // --- 4. Password: 6-72 code points and <=72 UTF-8 bytes
  assert.ok(isValidPassword("a".repeat(72)) && !isValidPassword("a".repeat(73)), "72 ASCII ok, 73 rejected");
  assert.ok(isValidPassword("\u{1F512}".repeat(18)) && !isValidPassword("\u{1F512}".repeat(19)), "18 emoji ok, 19 rejected");
  r = await call(auth.registerUser, { body: { name: "A", email: `r5_pw${tag}@example.com`, password: "a".repeat(73) } });
  assert.strictEqual(r.status, 400, "register 73-char password rejected");
  console.log("ok  password capped at bcrypt's 72 bytes");

  // --- 5. Lockout backs off OTP re-issue for 15 minutes
  const email = `r5_otp${tag}@example.com`;
  r = await call(auth.registerUser, { body: { name: "Otp", email, password: "secret1" } });
  assert.strictEqual(r.status, 201);
  const prevEnv = process.env.NODE_ENV;
  process.env.NODE_ENV = "development";
  r = await call(auth.forgotPassword, { body: { email } });
  assert.ok(r.body.devOtp, "OTP issued");
  const wrong = r.body.devOtp === "000000" ? "111111" : "000000";
  for (let i = 0; i < 5; i++) await call(auth.resetPassword, { body: { email, otp: wrong, newPassword: "secret2" } });
  // Even after the normal 60s window, a locked-out account gets no new OTP
  await User.updateOne({ email }, [{ $set: { otpIssuedAt: { $add: ["$otpIssuedAt", -61000] } } }], { updatePipeline: true });
  r = await call(auth.forgotPassword, { body: { email } });
  assert.strictEqual(r.status, 200, "same generic reply");
  assert.strictEqual(r.body.devOtp, undefined, "no OTP during the 15-min backoff");
  await User.updateOne({ email }, { $set: { otpIssuedAt: new Date(Date.now() - 61000) } });
  r = await call(auth.forgotPassword, { body: { email } });
  assert.ok(r.body.devOtp, "OTP issued again after the backoff");
  console.log("ok  OTP re-issue backs off 15 min after a lockout");

  // --- 6. Wrong guesses carry over to a re-issued OTP ("4 guesses, new OTP, repeat")
  const email2 = `r5_otp2${tag}@example.com`;
  await call(auth.registerUser, { body: { name: "Otp2", email: email2, password: "secret1" } });
  r = await call(auth.forgotPassword, { body: { email: email2 } });
  const wrong2 = r.body.devOtp === "000000" ? "111111" : "000000";
  for (let i = 0; i < 4; i++) {
    r = await call(auth.resetPassword, { body: { email: email2, otp: wrong2, newPassword: "secret2" } });
    assert.strictEqual(r.status, 400, "wrong guess " + i);
  }
  await User.updateOne({ email: email2 }, { $set: { otpIssuedAt: new Date(Date.now() - 61000) } });
  r = await call(auth.forgotPassword, { body: { email: email2 } });
  assert.ok(r.body.devOtp, "re-issued after 60s");
  assert.strictEqual((await User.findOne({ email: email2 }).lean()).otpAttempts, 4, "attempts carried over");
  r = await call(auth.resetPassword, { body: { email: email2, otp: r.body.devOtp === "000000" ? "111111" : "000000", newPassword: "secret2" } });
  assert.strictEqual(r.status, 429, "5th wrong guess across re-issues locks out");
  // An hour later the count starts fresh
  await User.updateOne({ email: email2 }, { $set: { otpIssuedAt: new Date(Date.now() - 61 * 60 * 1000), otpAttempts: 3 } });
  await call(auth.forgotPassword, { body: { email: email2 } });
  assert.strictEqual((await User.findOne({ email: email2 }).lean()).otpAttempts, 0, "attempts reset after an hour");
  process.env.NODE_ENV = prevEnv;
  console.log("ok  wrong OTP guesses count across re-issues within an hour");

  await cleanup();
  await mongoose.disconnect();
  console.log("ALL ROUND 5 CHECKS PASSED");
}

main().catch(async (err) => {
  console.error("FAILED:", err.message);
  await mongoose.disconnect().catch(() => {});
  process.exit(1);
});
