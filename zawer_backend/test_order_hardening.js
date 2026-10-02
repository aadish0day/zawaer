// Checks for order/coupon hardening. Runs controllers directly against a LOCAL MongoDB.
// Usage: MONGO_URI=mongodb://127.0.0.1:27099/zawer_orders_test node test_order_hardening.js
// (seed products first: node seed/product.js)
const assert = require("assert");
const mongoose = require("mongoose");
const Order = require("./models/Order");
const Offer = require("./models/Offer");
const Cart = require("./models/Cart");
const Product = require("./models/Product");
const orders = require("./controllers/orderController");
const { validateCoupon } = require("./controllers/offerController");
const { addToCart } = require("./controllers/cartController");

const MONGO_URI = process.env.MONGO_URI || "";
if (!/127\.0\.0\.1|localhost/.test(MONGO_URI)) {
  console.error("Refusing to run: set MONGO_URI to a local MongoDB (127.0.0.1 / localhost).");
  process.exit(1);
}

const U = "hard_"; // prefix for every test user id
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
    body: { customerName: "T", phone: "9876543210", address: "A, Mumbai", ...body },
  });

const offer = (code, extra) =>
  Offer.create({
    code, title: code, description: code, discountType: "percentage", discountValue: 10,
    maxDiscount: 0, minOrderAmount: 0, applicableCategory: "All",
    expiryDate: new Date(Date.now() + 86400000), usageLimit: 0, ...extra,
  });

async function cleanup() {
  await Order.deleteMany({ userId: { $regex: "^" + U } });
  await Cart.deleteMany({ userId: { $regex: "^" + U } });
  await Offer.deleteMany({ code: { $regex: "^HARDTEST" } });
}

async function main() {
  await mongoose.connect(MONGO_URI);
  await Order.init(); // make sure unique indexes exist before racing
  assert(await Product.exists({ id: "1" }), "seed products first (node seed/product.js)");
  await cleanup();

  // 1. Only admins can change status
  const o1 = (await place(U + "a", { items: [{ productId: "1", quantity: 1 }] })).body.order;
  for (const user of [undefined, { id: U + "a" }, { id: U + "a", role: "user" }]) {
    const r = await call(orders.updateOrderStatus, { user, params: { id: o1._id.toString() }, body: { status: "Delivered" } });
    assert.strictEqual(r.status, 403, "non-admin status update must be 403");
  }
  console.log("ok  non-admin status update -> 403");

  // 1b. Status only moves forward
  const fwd = await call(orders.updateOrderStatus, { user: ADMIN, params: { id: o1._id.toString() }, body: { status: "Shipped" } });
  assert.strictEqual(fwd.status, 200, "forward status update must succeed");
  const back = await call(orders.updateOrderStatus, { user: ADMIN, params: { id: o1._id.toString() }, body: { status: "Processing" } });
  assert.strictEqual(back.status, 400, "Shipped -> Processing must be 400");
  // Same status is an idempotent retry: 200, unchanged
  const same = await call(orders.updateOrderStatus, { user: ADMIN, params: { id: o1._id.toString() }, body: { status: "Shipped" } });
  assert.strictEqual(same.status, 200, "Shipped -> Shipped must be 200 (idempotent)");
  console.log("ok  backward status update -> 400, repeated -> 200");

  // 2. Other users cannot see the order by id or tracking number
  for (const id of [o1._id.toString(), o1.trackingNumber, o1.trackingNumber.toLowerCase()]) {
    const byId = await call(orders.getOrderById, { user: { id: U + "b" }, params: { id } });
    const track = await call(orders.getOrderTracking, { user: { id: U + "b" }, params: { query: id } });
    assert.strictEqual(byId.status, 404);
    assert.strictEqual(track.status, 404);
  }
  assert.strictEqual((await call(orders.getOrderTracking, { user: { id: U + "a" }, params: { query: o1.trackingNumber } })).status, 200);
  console.log("ok  other user's order/tracking lookup -> 404");

  // 3. Usage limit holds under 10 concurrent orders with 1 use left
  await offer("HARDTEST_LIMIT", { usageLimit: 5, usedCount: 4 });
  const race = await Promise.all(
    Array.from({ length: 10 }, (_, i) =>
      place(U + "race" + i, { couponCode: "HARDTEST_LIMIT", items: [{ productId: "1", quantity: 1 }] })
    )
  );
  assert.strictEqual(race.filter((r) => r.status === 201).length, 1, "exactly one coupon order");
  assert.strictEqual(race.filter((r) => r.status === 400).length, 9);
  assert.strictEqual((await Offer.findOne({ code: "HARDTEST_LIMIT" })).usedCount, 5);
  console.log("ok  usage limit not exceeded under 10 concurrent orders");

  // 4. perUserLimit, and cancelling releases the use
  await offer("HARDTEST_ONCE", { perUserLimit: 1 });
  const once = { couponCode: "HARDTEST_ONCE", items: [{ productId: "1", quantity: 1 }] };
  const first = await place(U + "once", once);
  assert.strictEqual(first.status, 201);
  assert.strictEqual((await place(U + "once", once)).status, 400, "second use rejected");
  assert.strictEqual((await place(U + "other", once)).status, 201, "other user unaffected");
  const cancel = await call(orders.updateOrderStatus, { user: ADMIN, params: { id: first.body.order._id.toString() }, body: { status: "Cancelled" } });
  assert.strictEqual(cancel.status, 200);
  assert(cancel.body.order.timeline.some((t) => t.status === "Cancelled"), "Cancelled shown in timeline");
  assert.strictEqual((await Offer.findOne({ code: "HARDTEST_ONCE" })).usedCount, 1, "cancel released one use");
  const reopen = await call(orders.updateOrderStatus, { user: ADMIN, params: { id: first.body.order._id.toString() }, body: { status: "Processing" } });
  assert.strictEqual(reopen.status, 400, "Cancelled is terminal");
  assert.strictEqual((await place(U + "once", once)).status, 201, "usable again after cancel");
  console.log("ok  perUserLimit enforced; cancel releases it; terminal status locked");

  // 5. Category coupon discounts only eligible items (DB category, case-insensitive)
  await offer("HARDTEST_RING", { applicableCategory: "ring", minOrderAmount: 20000 });
  const mixed = [{ productId: "1", quantity: 1 }, { productId: "2", quantity: 1, category: "Ring" }];
  const ring = await Product.findOne({ id: "1" });
  const neck = await Product.findOne({ id: "2" });
  const expected = Math.round(ring.price * 0.1);
  const cat = await place(U + "cat", { couponCode: "HARDTEST_RING", items: mixed });
  assert.strictEqual(cat.status, 201);
  assert.strictEqual(cat.body.order.discountAmount, expected, "only the ring is discounted");
  assert.strictEqual(cat.body.order.totalAmount, ring.price + neck.price - expected);
  const preview = await call(validateCoupon, { body: { couponCode: "hardtest_ring", items: mixed } });
  assert.strictEqual(preview.status, 200);
  assert.strictEqual(preview.body.coupon.discountAmount, expected, "preview matches checkout");
  const noRing = [{ productId: "2", quantity: 1, category: "Ring" }];
  assert.strictEqual((await place(U + "cat", { couponCode: "HARDTEST_RING", items: noRing })).status, 400);
  assert.strictEqual((await call(validateCoupon, { body: { couponCode: "HARDTEST_RING", items: noRing } })).status, 400);
  const weird = await call(validateCoupon, { body: { couponCode: "HARDTEST_RING", subtotal: 50000, category: { $ne: 1 } } });
  assert.notStrictEqual(weird.status, 500, "non-string category does not crash");
  console.log("ok  category coupon discounts only eligible items; preview matches");

  // 6. Same idempotencyKey (sequential and concurrent) -> one order
  const key = "11111111-2222-3333-4444-555555555555";
  const idem = await Promise.all(
    [1, 2, 3].map(() => place(U + "idem", { idempotencyKey: key, items: [{ productId: "1", quantity: 1 }] }))
  );
  const again = await place(U + "idem", { idempotencyKey: key, items: [{ productId: "1", quantity: 1 }] });
  assert(idem.concat(again).every((r) => r.body.success), "all retries succeed");
  assert.strictEqual(again.status, 200);
  assert.strictEqual(new Set(idem.concat(again).map((r) => r.body.order._id.toString())).size, 1);
  assert.strictEqual(await Order.countDocuments({ userId: U + "idem" }), 1);
  assert.strictEqual((await place(U + "idem", { idempotencyKey: "x".repeat(65), items: [{ productId: "1", quantity: 1 }] })).status, 400);
  console.log("ok  same idempotencyKey -> one order");

  // 7. Cart keeps items that were not ordered
  await Cart.create({ userId: U + "cart", items: [{ productId: "1", quantity: 1 }, { productId: "3", quantity: 2 }] });
  assert.strictEqual((await place(U + "cart", { items: [{ productId: "1", quantity: 1 }] })).status, 201);
  const cart = await Cart.findOne({ userId: U + "cart" });
  assert.deepStrictEqual(cart.items.map((i) => i.productId), ["3"]);
  console.log("ok  cart keeps non-ordered items");

  // 8. Quantities must be whole numbers in 1..MAX
  for (const quantity of [1.5, 0, -1, 11, "abc"]) {
    assert.strictEqual((await place(U + "qty", { items: [{ productId: "1", quantity }] })).status, 400, `qty ${quantity}`);
    assert.strictEqual((await call(addToCart, { user: { id: U + "qty" }, body: { productId: "1", quantity } })).status, 400);
  }
  assert.strictEqual((await call(addToCart, { user: { id: U + "qty" }, body: { productId: "1", quantity: 10 } })).status, 200);
  assert.strictEqual((await call(addToCart, { user: { id: U + "qty" }, body: { productId: "1", quantity: 1 } })).status, 400, "cart cap");
  console.log("ok  quantity 1.5 / out-of-range rejected (cap " + orders.MAX_ITEM_QUANTITY + ")");

  await cleanup();
  await mongoose.disconnect();
  console.log("ALL HARDENING CHECKS PASSED");
}

main().catch(async (err) => {
  console.error("FAILED:", err.message);
  await mongoose.disconnect().catch(() => {});
  process.exit(1);
});
