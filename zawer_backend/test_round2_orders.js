// Round-2 checks for orders / cart / wishlist. Runs controllers directly against a LOCAL MongoDB.
// Usage: MONGO_URI=mongodb://127.0.0.1:27092/r1b node test_round2_orders.js
// (seed products first: node seed/product.js)
const assert = require("assert");
const mongoose = require("mongoose");
const Order = require("./models/Order");
const Offer = require("./models/Offer");
const Cart = require("./models/Cart");
const Wishlist = require("./models/Wishlist");
const Product = require("./models/Product");
const orders = require("./controllers/orderController");
const cart = require("./controllers/cartController");
const wishlist = require("./controllers/wishlistController");

const MONGO_URI = process.env.MONGO_URI || "";
if (!/^mongodb:\/\/(127\.0\.0\.1|localhost)[:/]/.test(MONGO_URI)) {
  console.error("Refusing to run: set MONGO_URI to a local MongoDB (127.0.0.1 / localhost).");
  process.exit(1);
}

const U = "r2_";
const ADMIN = { id: U + "admin", role: "admin" };

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
    body: { customerName: "T", phone: "1", address: "A, Mumbai", paymentMethod: "UPI", ...body },
  });

async function cleanup() {
  await Order.deleteMany({ userId: { $regex: "^" + U } });
  await Cart.deleteMany({ userId: { $regex: "^" + U } });
  await Wishlist.deleteMany({ userId: { $regex: "^" + U } });
  await Offer.deleteMany({ code: { $regex: "^R2TEST" } });
  await Product.deleteMany({ id: { $regex: "^r2ghost" } });
}

async function main() {
  await mongoose.connect(MONGO_URI);
  await Order.init();
  const p1 = await Product.findOne({ id: "1" });
  const p21 = await Product.findOne({ id: "21" });
  assert(p1 && p21, "seed products first (node seed/product.js)");
  await cleanup();

  // 1. Buy Now (fromCart: false) keeps the cart line; default checkout removes it
  await Cart.create({ userId: U + "a", items: [{ productId: "1", quantity: 2 }] });
  let r = await place(U + "a", { items: [{ productId: "1", quantity: 1 }], fromCart: false });
  assert.strictEqual(r.status, 201);
  assert.strictEqual((await Cart.findOne({ userId: U + "a" })).items.length, 1, "Buy Now must keep cart");
  r = await place(U + "a", { items: [{ productId: "1", quantity: 1 }] });
  assert.strictEqual(r.status, 201);
  assert.strictEqual((await Cart.findOne({ userId: U + "a" })).items.length, 0, "cart checkout clears line");
  assert.strictEqual((await place(U + "a", { items: [{ productId: "1", quantity: 1 }], fromCart: "false" })).status, 400);
  console.log("ok  fromCart:false keeps cart, default pulls ordered line");

  // 2. Bad-type contact fields / coupon -> 400, no leak
  for (const bad of [
    { customerName: { $gt: "" } }, { customerName: "   " }, { phone: 123 },
    { address: "x".repeat(501) }, { paymentMethod: ["UPI"] }, { couponCode: { code: "X" } }, { couponCode: 5 },
  ]) {
    r = await place(U + "b", { items: [{ productId: "1", quantity: 1 }], ...bad });
    assert.strictEqual(r.status, 400, "bad input must be 400: " + JSON.stringify(bad));
    assert(!("error" in r.body));
  }
  r = await place(U + "b", { customerName: "  Asha  ", items: [{ productId: "1", quantity: 1 }], paymentMethod: undefined });
  assert.strictEqual(r.status, 201);
  assert.strictEqual(r.body.order.customerName, "Asha");
  assert.strictEqual(r.body.order.paymentMethod, "Cash on Delivery");
  console.log("ok  object/empty/oversized fields and non-string couponCode -> 400");

  // 3. Duplicate lines merged and capped; items array capped
  r = await place(U + "c", { items: [{ productId: "1", quantity: 10 }, { productId: "1", quantity: 10 }] });
  assert.strictEqual(r.status, 400, "10+10 of one product must be 400");
  r = await place(U + "c", { items: [{ productId: "1", quantity: 6 }, { productId: p1._id.toString(), quantity: 6 }] });
  assert.strictEqual(r.status, 400, "custom id + _id lines merge before the cap");
  r = await place(U + "c", { items: [{ productId: "21", quantity: 3 }, { productId: "21", quantity: 4 }] });
  assert.strictEqual(r.status, 201);
  assert.strictEqual(r.body.order.items.length, 1);
  assert.strictEqual(r.body.order.items[0].quantity, 7);
  assert.strictEqual(r.body.order.subtotal, p21.price * 7);
  r = await place(U + "c", { items: Array.from({ length: 51 }, () => ({ productId: "1", quantity: 1 })) });
  assert.strictEqual(r.status, 400);
  console.log("ok  duplicate lines merged (3+4 -> 7), merged cap and 50-line cap -> 400");

  // 4. Cancel releases the coupon by offer id (even if the code was later renamed)
  const offer = await Offer.create({
    code: "R2TESTA", title: "t", description: "t", discountType: "percentage", discountValue: 10,
    maxDiscount: 0, minOrderAmount: 0, applicableCategory: "All",
    expiryDate: new Date(Date.now() + 86400000), usageLimit: 5,
  });
  r = await place(U + "d", { items: [{ productId: "1", quantity: 1 }], couponCode: "r2testa" });
  assert.strictEqual(r.status, 201);
  const couponOrder = r.body.order;
  assert.strictEqual(String(couponOrder.couponOfferId), offer._id.toString());
  assert.strictEqual((await Offer.findById(offer._id)).usedCount, 1);
  await Offer.updateOne({ _id: offer._id }, { code: "R2TESTB" });
  r = await call(orders.updateOrderStatus, { user: ADMIN, params: { id: couponOrder._id.toString() }, body: { status: "Cancelled" } });
  assert.strictEqual(r.status, 200);
  assert.strictEqual((await Offer.findById(offer._id)).usedCount, 0, "release by offer id");
  console.log("ok  cancel releases coupon by couponOfferId");

  // 5. Same-status update is idempotent 200; no double release
  r = await call(orders.updateOrderStatus, { user: ADMIN, params: { id: couponOrder._id.toString() }, body: { status: "Cancelled" } });
  assert.strictEqual(r.status, 200);
  assert.strictEqual(r.body.order.status, "Cancelled");
  assert.strictEqual((await Offer.findById(offer._id)).usedCount, 0);
  const o5 = (await place(U + "e", { items: [{ productId: "1", quantity: 1 }] })).body.order;
  for (const s of ["Shipped", "Shipped"]) {
    r = await call(orders.updateOrderStatus, { user: ADMIN, params: { id: o5._id.toString() }, body: { status: s } });
    assert.strictEqual(r.status, 200);
  }
  r = await call(orders.updateOrderStatus, { user: ADMIN, params: { id: o5._id.toString() }, body: { status: "Processing" } });
  assert.strictEqual(r.status, 400, "backward still 400");
  console.log("ok  same-status update -> 200, backward still 400");

  // 6. Admin reads any order; other users cannot
  for (const fn of [orders.getOrderTracking, orders.getOrderById]) {
    for (const id of [o5._id.toString(), o5.trackingNumber]) {
      assert.strictEqual((await call(fn, { user: ADMIN, params: { id } })).status, 200);
      assert.strictEqual((await call(fn, { user: { id: U + "x", role: "user" }, params: { id } })).status, 404);
      assert.strictEqual((await call(fn, { user: { id: U + "e" }, params: { id } })).status, 200);
    }
  }
  console.log("ok  admin can read any order's tracking, other users 404");

  // 7. Legacy order without trackingNumber resolves by its displayed (derived) number
  const legacyId = new mongoose.Types.ObjectId();
  await Order.collection.insertOne({
    _id: legacyId, userId: U + "f", customerName: "L", phone: "1", address: "A",
    items: [], totalAmount: 0, status: "Order Placed",
  });
  const listed = (await call(orders.getMyOrders, { user: { id: U + "f" } })).body.orders[0];
  const derived = listed.trackingNumber;
  assert.strictEqual(derived, "ZWR-" + legacyId.toString().slice(-6).toUpperCase());
  r = await call(orders.getOrderTracking, { user: { id: U + "f" }, params: { query: derived.toLowerCase() } });
  assert.strictEqual(r.status, 200);
  assert.strictEqual(r.body.tracking.orderId.toString(), legacyId.toString());
  assert.strictEqual(r.body.tracking.trackingNumber, derived);
  assert.strictEqual((await call(orders.getOrderTracking, { user: { id: U + "g" }, params: { query: derived } })).status, 404);
  console.log("ok  legacy derived tracking number resolves (owner only)");

  // 8. Cart PUT/DELETE by _id match a custom-id line and vice versa
  await Cart.create({ userId: U + "h", items: [{ productId: "1", quantity: 1 }, { productId: p21._id.toString(), quantity: 2 }] });
  r = await call(cart.updateCartQuantity, { user: { id: U + "h" }, params: { productId: p1._id.toString() }, body: { quantity: 4 } });
  assert.strictEqual(r.status, 200);
  assert.strictEqual(r.body.cart.items.find((i) => i.productId === "1").quantity, 4);
  r = await call(cart.removeFromCart, { user: { id: U + "h" }, params: { productId: p1._id.toString() } });
  assert.strictEqual(r.status, 200);
  r = await call(cart.removeFromCart, { user: { id: U + "h" }, params: { productId: "21" } });
  assert.strictEqual(r.body.cart.items.length, 0, "custom id removes legacy _id line");
  await Wishlist.create({ userId: U + "h", items: [{ productId: "1" }] });
  r = await call(wishlist.removeFromWishlist, { user: { id: U + "h" }, params: { productId: p1._id.toString() } });
  assert.strictEqual(r.body.wishlist.items.length, 0);
  console.log("ok  cart PUT/DELETE and wishlist DELETE match either id form");

  // 9. getCart / getWishlist normalize _id lines and drop ghosts
  await Cart.create({
    userId: U + "i",
    items: [
      { productId: "1", quantity: 7 },
      { productId: p1._id.toString(), quantity: 6 },
      { productId: "r2ghost-gone", quantity: 1 },
      { productId: p21._id.toString(), quantity: 2 },
    ],
  });
  r = await call(cart.getCart, { user: { id: U + "i" } });
  assert.strictEqual(r.status, 200);
  const stored = (await Cart.findOne({ userId: U + "i" })).items.map((i) => [i.productId, i.quantity]);
  assert.deepStrictEqual(stored, [["1", 10], ["21", 2]]);
  assert.strictEqual(r.body.cart.items.length, 2);
  assert(r.body.cart.items.every((i) => i.product), "lines are populated");
  await Wishlist.create({ userId: U + "i", items: [{ productId: "r2ghost-gone" }, { productId: p1._id.toString() }, { productId: "1" }] });
  r = await call(wishlist.getWishlist, { user: { id: U + "i" } });
  assert.deepStrictEqual((await Wishlist.findOne({ userId: U + "i" })).items.map((i) => i.productId), ["1"]);
  assert.strictEqual(r.body.wishlist.items.length, 1);
  console.log("ok  getCart/getWishlist normalize legacy lines and drop ghosts");

  await cleanup();
  await mongoose.disconnect();
  console.log("\nAll round-2 checks passed.");
}

main().catch(async (err) => {
  console.error("FAIL", err);
  await mongoose.disconnect();
  process.exit(1);
});
