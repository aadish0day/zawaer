// Round-4 checks: phone/length/paymentMethod contract, legacy phone on profile update,
// offers missing isActive/startDate/usageLimit, legacy coupon release on cancel,
// release failure not masking the original error, cart/wishlist normalization guard.
// Runs controllers directly against a LOCAL throwaway MongoDB (seed products first):
//   MONGO_URI=mongodb://127.0.0.1:27084/r4 node seed/product.js
//   MONGO_URI=mongodb://127.0.0.1:27084/r4 node test_round4.js
const assert = require("assert");
const mongoose = require("mongoose");
const Order = require("./models/Order");
const Offer = require("./models/Offer");
const Cart = require("./models/Cart");
const Wishlist = require("./models/Wishlist");
const Product = require("./models/Product");
const User = require("./models/User");
const { isValidPhone } = require("./utils/validation");
const auth = require("./controllers/authController");
const orders = require("./controllers/orderController");
const offers = require("./controllers/offerController");
const { getCart } = require("./controllers/cartController");
const { getWishlist } = require("./controllers/wishlistController");
const { addProductReview } = require("./controllers/productController");

const MONGO_URI = process.env.MONGO_URI || "";
if (!/^mongodb:\/\/(127\.0\.0\.1|localhost)[:/]/.test(MONGO_URI)) {
  console.error("Refusing to run: MONGO_URI must point at a local throwaway DB");
  process.exit(1);
}

const U = "r4_";
const CODE = "R4TEST";
const ADMIN = { id: U + "admin", role: "admin" };
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
  await Cart.deleteMany({ userId: { $regex: "^" + U } });
  await Wishlist.deleteMany({ userId: { $regex: "^" + U } });
  await Offer.deleteMany({ code: { $regex: "^" + CODE } });
  await User.deleteMany({ email: { $regex: "^r4_" } });
  await Product.updateOne({ id: "1" }, { $pull: { reviews: { userName: { $regex: "^R4" } } } });
}

async function main() {
  await mongoose.connect(MONGO_URI);
  const product = await Product.findOne({ id: "1" });
  assert(product, "seed products first (node seed/product.js)");
  await cleanup();
  const rawOffers = mongoose.connection.db.collection("offers");
  const rawOrders = mongoose.connection.db.collection("orders");

  // --- 1. Phone contract
  for (const p of ["(022) 2345 6789", "98765.43210", "+91 98765 43210", "098765-43210", "+ 91 98765 43210", "1234567", "123456789012345"]) {
    assert.ok(isValidPhone(p), "phone should pass: " + p);
  }
  for (const p of ["1------", "123456", "1234567890123456", "91+9876543210", "++919876543210", "98765 abc", "1 1 1 1 1 1 1 1 1 1 1", "", 9876543210]) {
    assert.ok(!isValidPhone(p), "phone should fail: " + p);
  }
  let r = await call(auth.registerUser, { body: { name: "A", email: `r4_p${tag}@example.com`, password: "secret1", phone: "1------" } });
  assert.strictEqual(r.status, 400, "register bad phone");
  r = await call(auth.registerUser, { body: { name: "A", email: `r4_p${tag}@example.com`, password: "secret1", phone: "98765.43210" } });
  assert.strictEqual(r.status, 201, "register dotted phone");
  assert.strictEqual((await place(U + "ph", { phone: "1------" })).status, 400, "order bad phone");
  assert.strictEqual((await place(U + "ph", { phone: "(022) 2345 6789" })).status, 201, "order landline phone");
  console.log("ok  phone contract (helper, register, placeOrder)");

  // --- 2. Code-point lengths
  const e = "\u{1F48E}"; // gem emoji: 2 UTF-16 units, 1 code point
  r = await call(auth.registerUser, { body: { name: e.repeat(100), email: `r4_n${tag}@example.com`, password: "\u{1F512}".repeat(128) } });
  assert.strictEqual(r.status, 201, "100-emoji name + 128-emoji password ok");
  r = await call(auth.registerUser, { body: { name: e.repeat(101), email: `r4_m${tag}@example.com`, password: "secret1" } });
  assert.strictEqual(r.status, 400, "101-emoji name rejected");
  r = await call(auth.registerUser, { body: { name: "A", email: `r4_q${tag}@example.com`, password: "\u{1F512}".repeat(5) } });
  assert.strictEqual(r.status, 400, "5-emoji password rejected");
  assert.strictEqual((await place(U + "len", { customerName: e.repeat(100), address: e.repeat(500) })).status, 201, "order emoji name/address at limit");
  assert.strictEqual((await place(U + "len", { customerName: e.repeat(101) })).status, 400, "order 101-emoji name");
  assert.strictEqual((await place(U + "len", { address: e.repeat(501) })).status, 400, "order 501-emoji address");
  const reviewer = await User.create({ name: "R4 Reviewer", email: `r4_rev${tag}@example.com`, password: "x" });
  const review = (comment) => call(addProductReview, { user: { id: reviewer._id.toString() }, params: { id: "1" }, body: { rating: 5, comment } });
  assert.strictEqual((await review(e.repeat(1001))).status, 400, "1001-emoji comment rejected");
  assert.ok([200, 201].includes((await review(e.repeat(1000))).status), "1000-emoji comment ok");
  console.log("ok  lengths counted in code points (name, password, address, review)");

  // --- 3. paymentMethod allow-list
  for (const pm of [undefined, "Cash on Delivery", "UPI", "Credit/Debit Card", "  UPI  "]) {
    assert.strictEqual((await place(U + "pay", { paymentMethod: pm })).status, 201, "payment ok: " + pm);
  }
  for (const pm of ["Bitcoin", "upi", "cash on delivery", ""]) {
    assert.strictEqual((await place(U + "pay", { paymentMethod: pm })).status, 400, "payment rejected: " + pm);
  }
  console.log("ok  paymentMethod allow-list");

  // --- 4. Profile: unchanged legacy phone doesn't block a name change
  const legacyUser = await User.create({ name: "Old", email: `r4_legacy${tag}@example.com`, password: "x", phone: "1" });
  const me = { id: legacyUser._id.toString() };
  r = await call(auth.updateProfile, { user: me, body: { name: "New Name", phone: "1" } });
  assert.strictEqual(r.status, 200, "name change with same legacy phone");
  assert.strictEqual(r.body.user.name, "New Name");
  assert.strictEqual((await call(auth.updateProfile, { user: me, body: { phone: "2" } })).status, 400, "new invalid phone rejected");
  assert.strictEqual((await call(auth.updateProfile, { user: me, body: { phone: "+91 98765 43210" } })).status, 200, "new valid phone ok");
  console.log("ok  profile: legacy phone only validated when changed");

  // --- 5. Offers missing isActive / startDate / usageLimit
  const base = { title: "t", description: "d", discountType: "flat", discountValue: 10, minOrderAmount: 0, expiryDate: new Date(Date.now() + 864e5) };
  await rawOffers.insertOne({ ...base, code: CODE + "BARE", usedCount: 5 }); // no isActive, startDate, usageLimit
  r = await call(offers.getAllOffers, {});
  const bare = r.body.offers.find((o) => o.code === CODE + "BARE");
  assert.ok(bare, "offer with isActive missing is listed");
  assert.strictEqual(bare.isValid, true, "offer without startDate is valid");
  r = await call(offers.getOfferByCode, { params: { code: CODE + "BARE" } });
  assert.strictEqual(r.status, 200, "getOfferByCode finds isActive-missing offer");
  assert.strictEqual(r.body.offer.isValid, true);
  await rawOffers.insertOne({ ...base, code: CODE + "OFF", isActive: false });
  r = await call(offers.getAllOffers, {});
  assert.ok(!r.body.offers.some((o) => o.code === CODE + "OFF"), "inactive offer hidden");
  // Missing usageLimit = schema default 1000 in both the pre-check and the reservation
  r = await place(U + "lim", { couponCode: CODE + "BARE" });
  assert.strictEqual(r.status, 201, "coupon with missing usageLimit applies");
  assert.strictEqual((await rawOffers.findOne({ code: CODE + "BARE" })).usedCount, 6, "reserved one use");
  await rawOffers.updateOne({ code: CODE + "BARE" }, { $set: { usedCount: 1000 } });
  r = await place(U + "lim", { couponCode: CODE + "BARE" });
  assert.strictEqual(r.status, 400, "missing usageLimit behaves as 1000");
  // The reservation itself enforces the effective limit (pre-check bypassed via stale read)
  await rawOffers.updateOne({ code: CODE + "BARE" }, { $set: { usedCount: 999 } });
  const realFindOne = Offer.findOne;
  Offer.findOne = function (...args) {
    const q = realFindOne.apply(this, args);
    return q.then((doc) => { if (doc) doc.usedCount = 0; return rawOffers.updateOne({ code: CODE + "BARE" }, { $set: { usedCount: 1000 } }).then(() => doc); });
  };
  try {
    r = await place(U + "lim", { couponCode: CODE + "BARE" });
  } finally {
    Offer.findOne = realFindOne;
  }
  assert.strictEqual(r.status, 400, "atomic reservation uses the effective (default) limit");
  assert.strictEqual((await rawOffers.findOne({ code: CODE + "BARE" })).usedCount, 1000, "no over-reservation");
  console.log("ok  offers: missing isActive listed, missing startDate valid, missing usageLimit consistent");

  // --- 6. Cancel of legacy coupon orders (no couponOfferId)
  const legacyOrder = (code, createdAt) => ({
    userId: U + "cancel", customerName: "L", phone: "9876543210", address: "A", items: [{ productId: "1", name: "x", price: 100, quantity: 1 }],
    subtotal: 100, discountAmount: 10, couponCode: code, totalAmount: 90, status: "Order Placed", createdAt, updatedAt: createdAt,
  });
  const cancel = (id) => call(orders.updateOrderStatus, { user: ADMIN, params: { id: id.toString() }, body: { status: "Cancelled" } });
  // Code re-created after the order was placed: that use never counted against the new offer
  const old = new Date(Date.now() - 864e5);
  const { insertedId: o1 } = await rawOrders.insertOne(legacyOrder(CODE + "NEW", old));
  await rawOffers.insertOne({ ...base, code: CODE + "NEW", usedCount: 3, createdAt: new Date() });
  r = await cancel(o1);
  assert.strictEqual(r.status, 200, "legacy cancel ok");
  assert.strictEqual((await rawOffers.findOne({ code: CODE + "NEW" })).usedCount, 3, "re-created code not decremented");
  // Offer that existed when the legacy order was placed: that use was counted, so it is released
  await rawOffers.insertOne({ ...base, code: CODE + "OLD", usedCount: 3, createdAt: new Date(Date.now() - 2 * 864e5) });
  const { insertedId: o2 } = await rawOrders.insertOne(legacyOrder(CODE + "OLD", old));
  assert.strictEqual((await cancel(o2)).status, 200);
  assert.strictEqual((await rawOffers.findOne({ code: CODE + "OLD" })).usedCount, 2, "pre-existing offer released");
  console.log("ok  legacy coupon cancel only releases an offer that existed at order time");

  // --- 7. Release failure in placeOrder's error path doesn't mask the original error
  await rawOffers.insertOne({ ...base, code: CODE + "REL", usedCount: 0, usageLimit: 0, isActive: true, startDate: new Date(0) });
  const key = "r4-key-" + tag;
  const realCreate = Order.create;
  const realUpdateOne = Offer.updateOne;
  let createdFirst = null;
  Order.create = async function (data) {
    // A concurrent request with the same key wins the insert, then this one hits E11000
    createdFirst = await realCreate.call(Order, { ...data, trackingNumber: "ZWR-R4" + tag });
    const err = new Error("E11000 duplicate key");
    err.code = 11000;
    err.keyPattern = { userId: 1, idempotencyKey: 1 };
    throw err;
  };
  Offer.updateOne = async () => { throw new Error("release blew up"); };
  try {
    r = await place(U + "rel", { couponCode: CODE + "REL", idempotencyKey: key });
  } finally {
    Order.create = realCreate;
    Offer.updateOne = realUpdateOne;
  }
  assert.strictEqual(r.status, 200, "original duplicate-key error still replays the winner");
  assert.strictEqual(r.body.order._id.toString(), createdFirst._id.toString());
  Order.create = async () => { throw new Error("db down"); };
  Offer.updateOne = async () => { throw new Error("release blew up"); };
  try {
    r = await place(U + "rel", { couponCode: CODE + "REL" });
  } finally {
    Order.create = realCreate;
    Offer.updateOne = realUpdateOne;
  }
  assert.strictEqual(r.status, 500, "generic failure still 500");
  assert.strictEqual(r.body.message, "Failed to place order");
  console.log("ok  release failure logged, original error surfaced");

  // --- 8. Cart / wishlist normalization guarded on the items we read
  const legacyId = product._id.toString();
  const realFind = Product.find;
  const withConcurrentWrite = async (write, fn) => {
    Product.find = function (...args) {
      Product.find = realFind;
      return write().then(() => realFind.apply(Product, args));
    };
    try { return await fn(); } finally { Product.find = realFind; }
  };
  const carts = mongoose.connection.db.collection("carts");
  await carts.insertOne({ userId: U + "cart", items: [{ productId: legacyId, quantity: 2 }], createdAt: new Date(), updatedAt: new Date() });
  await withConcurrentWrite(
    () => carts.updateOne({ userId: U + "cart" }, { $push: { items: { productId: "2", quantity: 1 } } }),
    () => call(getCart, { user: { id: U + "cart" } })
  );
  let raw = await carts.findOne({ userId: U + "cart" });
  assert.ok(raw.items.some((i) => i.productId === "2"), "concurrent cart add not overwritten");
  r = await call(getCart, { user: { id: U + "cart" } });
  assert.strictEqual(r.status, 200);
  raw = await carts.findOne({ userId: U + "cart" });
  assert.deepStrictEqual(raw.items.map((i) => [i.productId, i.quantity]), [["1", 2], ["2", 1]], "cart normalized on the next read");

  const wl = mongoose.connection.db.collection(Wishlist.collection.name);
  await wl.insertOne({ userId: U + "wl", items: [{ productId: legacyId }], createdAt: new Date(), updatedAt: new Date() });
  await withConcurrentWrite(
    () => wl.updateOne({ userId: U + "wl" }, { $push: { items: { productId: "2" } } }),
    () => call(getWishlist, { user: { id: U + "wl" } })
  );
  raw = await wl.findOne({ userId: U + "wl" });
  assert.ok(raw.items.some((i) => i.productId === "2"), "concurrent wishlist add not overwritten");
  await call(getWishlist, { user: { id: U + "wl" } });
  raw = await wl.findOne({ userId: U + "wl" });
  assert.deepStrictEqual(raw.items.map((i) => i.productId), ["1", "2"], "wishlist normalized on the next read");
  console.log("ok  cart/wishlist normalization guarded on the items array");

  await cleanup();
  await mongoose.disconnect();
  console.log("ALL ROUND 4 CHECKS PASSED");
}

main().catch(async (err) => {
  console.error("FAILED:", err.message);
  await mongoose.disconnect().catch(() => {});
  process.exit(1);
});
