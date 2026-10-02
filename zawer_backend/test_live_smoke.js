// End-to-end smoke test against a running server and ITS real database (e.g. Atlas).
// Uses one throwaway account and deletes everything it created at the end.
// It never seeds, never applies a real coupon and never posts reviews, so the
// catalog, coupon counts and product ratings are untouched.
//   1. start the server normally (NODE_ENV=development so forgot-password returns devOtp)
//   2. BASE_URL=http://127.0.0.1:5000 node test_live_smoke.js
require("dotenv").config({ quiet: true });
const assert = require("assert");
const crypto = require("crypto");
const mongoose = require("mongoose");

const BASE_URL = process.env.BASE_URL || "http://127.0.0.1:5000";
const email = `smoke_${Date.now()}@zawer-smoke.test`;
let userId = null;
let passed = 0;

const call = async (method, path, body, token) => {
  const res = await fetch(BASE_URL + path, {
    method,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let data;
  try { data = JSON.parse(text); } catch { data = { raw: text }; }
  return { status: res.status, data };
};

const step = (name) => { passed++; console.log(`ok  ${name}`); };

const order = (token, items, extra = {}) =>
  call("POST", "/api/orders", {
    customerName: "Smoke Test",
    phone: "+91 98765 43210",
    address: "1 Test Street, Mumbai",
    paymentMethod: "Cash on Delivery",
    items,
    idempotencyKey: crypto.randomBytes(16).toString("hex"),
    ...extra,
  }, token);

async function main() {
  // --- basics
  let r = await call("GET", "/api/nope");
  assert.strictEqual(r.status, 404); step("unknown route -> JSON 404");
  r = await call("POST", "/api/auth/login");
  assert.strictEqual(r.status, 400); step("empty body -> 400");

  // --- register / login / profile
  const password = "smokePass1";
  r = await call("POST", "/api/auth/register", { name: "Smoke Test", email, password, phone: "+91 98765 43210" });
  assert.strictEqual(r.status, 201, JSON.stringify(r.data)); step("register");
  r = await call("POST", "/api/auth/login", { email, password });
  assert.strictEqual(r.status, 200); let token = r.data.token; userId = r.data.user.id;
  assert.strictEqual(r.data.user.role, "user"); step("login (role user)");
  r = await call("GET", "/api/auth/profile", undefined, token);
  assert.strictEqual(r.status, 200); step("profile");
  r = await call("PUT", "/api/auth/profile", { name: "Smoke Tester" }, token);
  assert.strictEqual(r.status, 200); step("profile update");

  // --- catalog
  r = await call("GET", "/api/products?limit=100");
  assert.strictEqual(r.status, 200);
  const products = r.data.products;
  assert.ok(products.length >= 2, "need at least 2 products");
  assert.ok(products.every((p) => p.reviews === undefined), "lists hide reviews");
  const [p1, p2] = products;
  step(`products (${r.data.total ?? products.length} total, reviews hidden)`);
  r = await call("GET", `/api/products/${encodeURIComponent(p1.id)}/reviews`);
  assert.strictEqual(r.status, 200);
  assert.ok((r.data.reviews || []).every((x) => x.userId === undefined)); step("reviews hide user ids");
  r = await call("GET", "/api/offers");
  assert.strictEqual(r.status, 200); step(`offers (${r.data.offers.length})`);

  // --- wishlist
  r = await call("POST", "/api/wishlist", { productId: p1.id }, token);
  assert.ok(r.status === 200 || r.status === 201);
  r = await call("GET", "/api/wishlist", undefined, token);
  assert.ok(r.data.wishlist.items.some((i) => i.product && i.product.id === p1.id)); step("wishlist add + populated get");
  r = await call("DELETE", `/api/wishlist/${encodeURIComponent(p1.id)}`, undefined, token);
  assert.strictEqual(r.status, 200); step("wishlist remove");

  // --- cart
  r = await call("POST", "/api/cart", { productId: p1.id, quantity: 2 }, token);
  assert.ok(r.status === 200 || r.status === 201, JSON.stringify(r.data));
  await call("POST", "/api/cart", { productId: p2.id, quantity: 1 }, token);
  r = await call("PUT", `/api/cart/${encodeURIComponent(p1.id)}`, { quantity: 3 }, token);
  assert.strictEqual(r.status, 200);
  r = await call("GET", "/api/cart", undefined, token);
  const line = r.data.cart.items.find((i) => i.productId === p1.id);
  assert.strictEqual(line.quantity, 3); assert.ok(line.product && line.product.price > 0);
  step("cart add / update / populated get");
  r = await call("POST", "/api/cart", { productId: p1.id, quantity: 1.5 }, token);
  assert.strictEqual(r.status, 400); step("cart rejects 1.5");

  // --- coupon preview (fake code: no real coupon touched)
  r = await call("POST", "/api/offers/validate-coupon", { couponCode: "NOSUCHSMOKE", items: [{ productId: p1.id, quantity: 1 }] }, token);
  assert.ok(r.status === 404 || r.status === 400); step("unknown coupon rejected");

  // --- cart order + idempotent replay
  const key = crypto.randomBytes(16).toString("hex");
  r = await order(token, [{ productId: p1.id, quantity: 3 }], { idempotencyKey: key, fromCart: true });
  assert.strictEqual(r.status, 201, JSON.stringify(r.data));
  const o1 = r.data.order;
  assert.strictEqual(o1.subtotal, Math.round(p1.price * 3 * 100) / 100, "server prices from DB");
  r = await order(token, [{ productId: p1.id, quantity: 3 }], { idempotencyKey: key, fromCart: true });
  assert.strictEqual(r.status, 200); assert.strictEqual(r.data.order._id, o1._id); step("cart order + replay returns same order");
  r = await call("GET", "/api/cart", undefined, token);
  const ids = r.data.cart.items.map((i) => i.productId);
  assert.ok(!ids.includes(p1.id) && ids.includes(p2.id)); step("only ordered item left the cart");

  // --- Buy Now leaves the cart alone
  r = await order(token, [{ productId: p2.id, quantity: 1 }], { fromCart: false });
  assert.strictEqual(r.status, 201, JSON.stringify(r.data));
  r = await call("GET", "/api/cart", undefined, token);
  assert.ok(r.data.cart.items.some((i) => i.productId === p2.id)); step("Buy Now keeps cart");

  // --- validation
  r = await order(token, [{ productId: p1.id, quantity: 1 }], { customerName: { a: 1 } });
  assert.strictEqual(r.status, 400); step("bad customerName -> 400");
  r = await order(token, [{ productId: p1.id, quantity: 10 }, { productId: p1.id, quantity: 10 }]);
  assert.strictEqual(r.status, 400); step("duplicate lines over cap -> 400");

  // --- orders, tracking, authorization
  r = await call("GET", "/api/orders", undefined, token);
  assert.strictEqual(r.data.orders.length, 2); step("my orders");
  r = await call("GET", `/api/orders/${o1._id}/tracking`, undefined, token);
  assert.strictEqual(r.status, 200);
  r = await call("GET", `/api/orders/track/${encodeURIComponent(o1.trackingNumber)}`, undefined, token);
  assert.strictEqual(r.status, 200); step("tracking by id and number");
  r = await call("PUT", `/api/orders/${o1._id}/status`, { status: "Delivered" }, token);
  assert.strictEqual(r.status, 403); step("non-admin status change -> 403");

  // --- password reset revokes old token
  r = await call("POST", "/api/auth/forgot-password", { email });
  assert.strictEqual(r.status, 200);
  const otp = r.data.devOtp;
  if (otp) {
    r = await call("POST", "/api/auth/reset-password", { email, otp: otp === "000000" ? "111111" : "000000", newPassword: "newSmoke1" });
    assert.strictEqual(r.status, 400); step("wrong OTP -> 400");
    await new Promise((res) => setTimeout(res, 1100)); // token iat has 1s resolution
    r = await call("POST", "/api/auth/reset-password", { email, otp, newPassword: "newSmoke1" });
    assert.strictEqual(r.status, 200); step("reset with OTP");
    r = await call("GET", "/api/auth/profile", undefined, token);
    assert.strictEqual(r.status, 401); step("old token revoked after reset");
    r = await call("POST", "/api/auth/login", { email, password: "newSmoke1" });
    assert.strictEqual(r.status, 200); token = r.data.token; step("login with new password");
  } else {
    step("forgot-password 200 (no devOtp: NODE_ENV isn't development, reset skipped)");
  }
}

async function cleanup() {
  await mongoose.connect(process.env.MONGO_URI);
  const db = mongoose.connection.db;
  const user = await db.collection("users").findOne({ email });
  const uid = user ? user._id.toString() : userId;
  if (uid) {
    const o = await db.collection("orders").deleteMany({ userId: uid });
    const c = await db.collection("carts").deleteMany({ userId: uid });
    const w = await db.collection("wishlists").deleteMany({ userId: uid });
    console.log(`cleanup: ${o.deletedCount} orders, ${c.deletedCount} carts, ${w.deletedCount} wishlists`);
  }
  const u = await db.collection("users").deleteMany({ email });
  console.log(`cleanup: ${u.deletedCount} user`);
  await mongoose.disconnect();
}

main()
  .then(() => console.log(`\nALL ${passed} LIVE SMOKE CHECKS PASSED`))
  .catch((err) => { console.error(`\nFAILED after ${passed} checks:`, err.message); process.exitCode = 1; })
  .finally(cleanup);
