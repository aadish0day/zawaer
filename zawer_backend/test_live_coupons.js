// End-to-end coupon test against a running server and ITS real database (e.g. Atlas).
// A throwaway account places real orders with each live coupon and checks the math.
// Afterwards it deletes those orders and gives back exactly the coupon uses it took,
// so offer usedCount values end where they started.
//   BASE_URL=http://127.0.0.1:5000 node test_live_coupons.js
require("dotenv").config({ quiet: true });
const assert = require("assert");
const crypto = require("crypto");
const mongoose = require("mongoose");

const BASE_URL = process.env.BASE_URL || "http://127.0.0.1:5000";
const email = `coupon_${Date.now()}@zawer-smoke.test`;
let passed = 0;

const call = async (method, path, body, token) => {
  const res = await fetch(BASE_URL + path, {
    method,
    headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return { status: res.status, data: await res.json() };
};
const step = (name) => { passed++; console.log(`ok  ${name}`); };
const round2 = (x) => Math.round(x * 100) / 100;

async function main() {
  await call("POST", "/api/auth/register", { name: "Coupon Test", email, password: "couponPass1" });
  const login = await call("POST", "/api/auth/login", { email, password: "couponPass1" });
  assert.strictEqual(login.status, 200);
  const token = login.data.token;

  const offers = (await call("GET", "/api/offers")).data.offers;
  const live = offers.filter((o) => o.isValid);
  console.log("live coupons:", live.map((o) => o.code).join(", ") || "(none)");
  assert.ok(live.length > 0, "no valid coupons on this database");

  const products = (await call("GET", "/api/products?limit=100")).data.products;
  const inCat = (cat) => products.filter((p) => p.category.toLowerCase() === cat.toLowerCase());
  const outCat = (cat) => products.filter((p) => p.category.toLowerCase() !== cat.toLowerCase());

  const order = (items, couponCode) =>
    call("POST", "/api/orders", {
      customerName: "Coupon Test", phone: "+91 98765 43210", address: "1 Test Street, Mumbai",
      paymentMethod: "Cash on Delivery", items, couponCode, fromCart: false,
      idempotencyKey: crypto.randomBytes(16).toString("hex"),
    }, token);

  // Expected discount, mirroring Offer.calculateDiscount on the eligible subtotal
  const expected = (o, eligible) => {
    let d = o.discountType === "percentage" ? (eligible * o.discountValue) / 100 : o.discountValue;
    if (o.maxDiscount > 0) d = Math.min(d, o.maxDiscount);
    return Math.min(Math.round(Math.max(0, d)), eligible);
  };

  for (const o of live) {
    const all = !o.applicableCategory || o.applicableCategory.toLowerCase() === "all";
    const pool = all ? products : inCat(o.applicableCategory);
    if (!pool.length) { console.log(`--  ${o.code}: no products in ${o.applicableCategory}, skipped`); continue; }
    const p = pool.sort((a, b) => b.price - a.price)[0];
    const qty = Math.min(10, Math.max(1, Math.ceil((o.minOrderAmount + 1) / p.price)));
    const items = [{ productId: p.id, quantity: qty }];
    const eligible = round2(p.price * qty);
    // A non-matching item must not be discounted for category coupons
    const other = all ? null : outCat(o.applicableCategory)[0];
    if (other) items.push({ productId: other.id, quantity: 1 });
    const want = expected(o, eligible);

    // Preview (no usage) — lowercase code must work too
    const pv = await call("POST", "/api/offers/validate-coupon", { couponCode: o.code.toLowerCase(), items }, token);
    assert.strictEqual(pv.status, 200, `${o.code} preview: ${pv.data.message}`);
    assert.strictEqual(pv.data.coupon.discountAmount, want, `${o.code} preview discount`);

    const r = await order(items, o.code);
    assert.strictEqual(r.status, 201, `${o.code} order: ${r.data.message}`);
    assert.strictEqual(r.data.order.discountAmount, want, `${o.code} order discount`);
    const subtotal = round2(eligible + (other ? other.price : 0));
    assert.strictEqual(r.data.order.totalAmount, round2(Math.max(0, subtotal - want)), `${o.code} total`);
    step(`${o.code}: ${o.discountType} ${o.discountValue}${all ? "" : " on " + o.applicableCategory} -> ₹${want} off ₹${subtotal}${other ? " (other category not discounted)" : ""}`);

    if (o.perUserLimit > 0 || o.code === "MAISON10") {
      const again = await order(items, o.code);
      if (again.status === 400) {
        assert.strictEqual(again.data.couponError, true);
        step(`${o.code}: second use by same user rejected (${again.data.message})`);
      }
    }

    if (!all && other) {
      const wrong = await order([{ productId: other.id, quantity: 1 }], o.code);
      assert.strictEqual(wrong.status, 400); assert.strictEqual(wrong.data.couponError, true);
      step(`${o.code}: rejected for ${other.category} only`);
    }

    if (o.minOrderAmount > 0) {
      const cheap = pool.sort((a, b) => a.price - b.price)[0];
      if (cheap.price < o.minOrderAmount) {
        const low = await call("POST", "/api/offers/validate-coupon", { couponCode: o.code, items: [{ productId: cheap.id, quantity: 1 }] }, token);
        assert.strictEqual(low.status, 400, `${o.code} under minimum`);
        step(`${o.code}: below ₹${o.minOrderAmount} minimum rejected`);
      }
    }
  }

  for (const o of offers.filter((x) => !x.isValid)) {
    const r = await order([{ productId: products[0].id, quantity: 1 }], o.code);
    assert.strictEqual(r.status, 400); assert.strictEqual(r.data.couponError, true);
    step(`${o.code}: invalid/expired coupon rejected (${r.data.message})`);
  }

  const bogus = await order([{ productId: products[0].id, quantity: 1 }], "NOSUCHCODE");
  assert.ok([400, 404].includes(bogus.status), "unknown code");
  step("unknown code rejected");
}

async function cleanup() {
  await mongoose.connect(process.env.MONGO_URI);
  const db = mongoose.connection.db;
  const user = await db.collection("users").findOne({ email });
  if (user) {
    const uid = user._id.toString();
    const used = await db.collection("orders").find({ userId: uid, couponCode: { $nin: [null, ""] } }).toArray();
    const perCode = {};
    for (const o of used) perCode[o.couponCode] = (perCode[o.couponCode] || 0) + 1;
    for (const [code, n] of Object.entries(perCode)) {
      await db.collection("offers").updateOne({ code }, { $inc: { usedCount: -n } });
    }
    const del = await db.collection("orders").deleteMany({ userId: uid });
    await db.collection("carts").deleteMany({ userId: uid });
    await db.collection("wishlists").deleteMany({ userId: uid });
    console.log(`cleanup: ${del.deletedCount} orders, coupon uses returned: ${JSON.stringify(perCode)}`);
  }
  const u = await db.collection("users").deleteMany({ email });
  console.log(`cleanup: ${u.deletedCount} user`);
  await mongoose.disconnect();
}

main()
  .then(() => console.log(`\nALL ${passed} LIVE COUPON CHECKS PASSED`))
  .catch((err) => { console.error(`\nFAILED after ${passed} checks:`, err.message); process.exitCode = 1; })
  .finally(cleanup);
