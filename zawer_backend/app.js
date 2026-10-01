const express = require("express");
const cors = require("cors");

const authRoutes =
  require("./routes/authRoutes");

const productRoutes =
  require("./routes/productRoutes");

const cartRoutes =
  require("./routes/cartRoutes");

const wishlistRoutes =
  require("./routes/wishlistRoutes");

const orderRoutes =
  require("./routes/orderRoutes");

const offerRoutes =
  require("./routes/offerRoutes");

const app = express();

app.use(cors());

app.use(express.json());

app.get("/", (req, res) => {
  res.json({
    success: true,
    message:
      "ZAWER Jewellery API is running",
  });
});

// ponytail: in-memory, per-process limiter (20 req / 15 min per IP per route).
// Behind a load balancer or with several instances this must move to a shared
// store (e.g. Redis); behind a reverse proxy also set `trust proxy` so req.ip
// is the client, not the proxy.
const AUTH_RATE_LIMIT = 20;
const AUTH_RATE_WINDOW_MS = 15 * 60 * 1000;
const authHits = new Map();

setInterval(() => {
  const now = Date.now();
  for (const [key, entry] of authHits) {
    if (entry.resetAt <= now) authHits.delete(key);
  }
}, AUTH_RATE_WINDOW_MS).unref();

const authRateLimit = (req, res, next) => {
  // Routing is case-insensitive and non-strict, so normalise the key
  const key = `${req.ip}:${req.path.toLowerCase().replace(/\/+$/, "")}`;
  const now = Date.now();
  const entry = authHits.get(key);

  if (!entry || entry.resetAt <= now) {
    authHits.set(key, { count: 1, resetAt: now + AUTH_RATE_WINDOW_MS });
    return next();
  }

  entry.count += 1;

  if (entry.count > AUTH_RATE_LIMIT) {
    res.set("Retry-After", Math.ceil((entry.resetAt - now) / 1000));
    return res.status(429).json({
      success: false,
      message: "Too many requests. Please try again later",
    });
  }

  next();
};

app.post(
  [
    "/api/auth/login",
    "/api/auth/forgot-password",
    "/api/auth/reset-password",
  ],
  authRateLimit
);

app.use(
  "/api/auth",
  authRoutes
);

app.use(
  "/api/products",
  productRoutes
);

app.use(
  "/api/cart",
  cartRoutes
);

app.use(
  "/api/wishlist",
  wishlistRoutes
);

app.use(
  "/api/orders",
  orderRoutes
);

app.use(
  "/api/offers",
  offerRoutes
);

module.exports = app;