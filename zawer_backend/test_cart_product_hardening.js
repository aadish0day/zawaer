// Cart / wishlist / product hardening checks over HTTP. Needs a running server on a
// throwaway, seeded DB (node seed/product.js):
//   MONGO_URI=mongodb://127.0.0.1:27098/zawer_med PORT=5103 JWT_SECRET=<48-byte hex> node server.js
//   node test_cart_product_hardening.js     # BASE_URL defaults to http://127.0.0.1:5103
// Uses one login per run (the limiter allows 20 / 15 min per IP).
const assert = require("assert");

const BASE_URL = process.env.BASE_URL || "http://127.0.0.1:5103";

const call = async (method, path, body, token, rawBody) => {
  const res = await fetch(BASE_URL + path, {
    method,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: rawBody !== undefined ? rawBody : body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, data: await res.json() };
};

const main = async () => {
  const email = `cart_test_${Date.now()}@example.com`;
  const password = "cartpass123";
  let r = await call("POST", "/api/auth/register", { name: "Cart Test", email, password });
  assert.strictEqual(r.status, 201, "register");
  r = await call("POST", "/api/auth/login", { email, password });
  assert.strictEqual(r.status, 200, "login");
  const token = r.data.token;

  // Concurrent get-or-create on a brand-new user never 500s
  const gets = await Promise.all([
    ...Array.from({ length: 5 }, () => call("GET", "/api/cart", null, token)),
    ...Array.from({ length: 5 }, () => call("GET", "/api/wishlist", null, token)),
  ]);
  assert.deepStrictEqual(gets.map((g) => g.status), Array(10).fill(200), "concurrent get-or-create");
  console.log("ok  concurrent cart/wishlist get-or-create");

  // 10 concurrent adds of the same product -> one line, quantity 10, then cap
  const adds = await Promise.all(
    Array.from({ length: 10 }, () => call("POST", "/api/cart", { productId: "1", quantity: 1 }, token))
  );
  assert.deepStrictEqual(adds.map((a) => a.status), Array(10).fill(200), "concurrent adds");
  r = await call("GET", "/api/cart", null, token);
  const lines = r.data.cart.items.filter((i) => i.productId === "1");
  assert.strictEqual(lines.length, 1, "one cart line");
  assert.strictEqual(lines[0].quantity, 10, "quantity summed");
  r = await call("POST", "/api/cart", { productId: "1", quantity: 1 }, token);
  assert.strictEqual(r.status, 400, "cap 10");
  console.log("ok  10 concurrent adds -> one line (qty 10), 11th rejected");

  // Unknown product -> 404; Mongo _id accepted but custom id stored
  for (const path of ["/api/cart", "/api/wishlist"]) {
    for (const productId of ["no-such-product", "507f1f77bcf86cd799439011"]) {
      r = await call("POST", path, { productId }, token);
      assert.strictEqual(r.status, 404, `${path} ${productId}`);
    }
  }
  r = await call("GET", "/api/products/2");
  const mongoId = r.data.product._id;
  r = await call("POST", "/api/wishlist", { productId: mongoId }, token);
  assert.strictEqual(r.status, 200, "wishlist add by _id");
  r = await call("POST", "/api/cart", { productId: mongoId }, token);
  assert.strictEqual(r.status, 200, "cart add by _id");
  assert.ok(r.data.cart.items.some((i) => i.productId === "2"), "custom id stored");
  console.log("ok  unknown product -> 404 (cart & wishlist); _id accepted, custom id stored");

  // GET includes populated product
  const checkItem = (item, id) => {
    assert.ok(item.product, "product populated");
    assert.strictEqual(item.product.id, id);
    for (const k of ["name", "price", "originalPrice", "discountPercentage", "images", "category", "rating"]) {
      assert.ok(k in item.product, `product.${k}`);
    }
    assert.ok(!("reviews" in item.product), "reviews not included");
  };
  r = await call("GET", "/api/cart", null, token);
  checkItem(r.data.cart.items.find((i) => i.productId === "2"), "2");
  r = await call("GET", "/api/wishlist", null, token);
  assert.strictEqual(r.data.wishlist.items.length, 1);
  checkItem(r.data.wishlist.items[0], "2");
  console.log("ok  cart/wishlist GET include items[].product");

  // Unknown route / malformed JSON -> JSON errors
  r = await call("GET", "/api/nope");
  assert.strictEqual(r.status, 404);
  assert.strictEqual(r.data.success, false);
  r = await call("POST", "/api/cart", null, token, "{bad json");
  assert.strictEqual(r.status, 400);
  assert.strictEqual(r.data.success, false);
  assert.ok(!JSON.stringify(r.data).includes("at "), "no stack trace");
  console.log("ok  unknown route -> JSON 404, malformed JSON -> JSON 400");

  // Paging caps / validation
  r = await call("GET", "/api/products?limit=100000");
  assert.strictEqual(r.status, 200);
  assert.ok(r.data.products.length <= 100 && r.data.pages >= 1, "limit capped");
  r = await call("GET", "/api/products/search?search=a&limit=100000");
  assert.strictEqual(r.status, 200);
  assert.ok(r.data.products.length <= 100 && "total" in r.data, "search capped");
  r = await call("GET", "/api/products/search?search=ring&limit=1&page=2");
  assert.strictEqual(r.data.count, 1, "search paginated");
  for (const q of ["page=0", "limit=-1", "limit=abc", "page=1.5"]) {
    assert.strictEqual((await call("GET", `/api/products?${q}`)).status, 400, q);
  }
  console.log("ok  limit capped at 100, search paginated, bad page/limit -> 400");

  // Review validation
  for (const rating of ["abc", 1.5, 6, 0, true, null]) {
    r = await call("POST", "/api/products/1/reviews", { rating, comment: "x" }, token);
    assert.strictEqual(r.status, 400, `rating ${rating}`);
  }
  for (const comment of [123, "   ", "x".repeat(1001)]) {
    r = await call("POST", "/api/products/1/reviews", { rating: 5, comment }, token);
    assert.strictEqual(r.status, 400, "bad comment");
  }
  console.log("ok  bad rating / comment -> 400");

  // First review: seeded rating is the baseline until real reviews exist
  r = await call("GET", "/api/products?limit=100");
  // Lists no longer carry reviews: ask the reviews endpoint which product is unreviewed
  let fresh;
  for (const p of r.data.products.filter((p) => p.rating > 0)) {
    if ((await call("GET", `/api/products/${p.id}/reviews`)).data.totalReviews === 0) {
      fresh = p;
      break;
    }
  }
  if (!fresh) {
    console.log("skip first-review check: no unreviewed seeded product left (reseed)");
  } else {
    r = await call("GET", `/api/products/${fresh.id}/reviews`);
    assert.strictEqual(r.data.averageRating, fresh.rating, "seeded rating shown before reviews");

    // Concurrent duplicate reviews -> exactly one stored
    const posts = await Promise.all(
      Array.from({ length: 5 }, () =>
        call("POST", `/api/products/${fresh.id}/reviews`, { rating: 4, comment: "  Nice  " }, token)
      )
    );
    const codes = posts.map((p) => p.status).sort();
    assert.deepStrictEqual(codes, [201, 400, 400, 400, 400], "one review wins");
    r = await call("GET", `/api/products/${fresh.id}/reviews`);
    assert.strictEqual(r.data.totalReviews, 1, "one review stored");
    assert.strictEqual(r.data.reviews[0].comment, "Nice", "comment trimmed");
    assert.strictEqual(r.data.averageRating, 4, "rating = review average once reviews exist");
    console.log(`ok  first review on ${fresh.id}: ${fresh.rating} baseline -> 4; concurrent duplicates -> one review`);
  }

  console.log("ALL CART/PRODUCT HARDENING CHECKS PASSED");
};

main().catch((err) => {
  console.error("FAILED:", err.message);
  process.exit(1);
});
