const net = require("net");
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

// Behind a reverse proxy, set TRUST_PROXY (hop count, or a comma list of
// proxy IPs/subnets) so req.ip is the real client for the rate limiter.
if (process.env.TRUST_PROXY) {
  const trust = process.env.TRUST_PROXY.trim();
  app.set("trust proxy", /^\d+$/.test(trust) ? Number(trust) : trust);
}

app.use(cors());

app.use(express.json());

// Express 5 leaves req.body undefined when no JSON body was sent; default it
// so handlers can destructure without a 500.
app.use((req, res, next) => {
  req.body ??= {};
  next();
});

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

// One IPv6 client usually owns a whole /64, so key IPv6 by its /64 prefix.
const rateLimitIp = (ip = "") => {
  if (!net.isIPv6(ip) || ip.toLowerCase().startsWith("::ffff:")) return ip;
  const [head, tail] = ip.split("%")[0].split("::");
  const groups = head ? head.split(":") : [];
  if (tail !== undefined) {
    const tailGroups = tail ? tail.split(":") : [];
    groups.push(...Array(Math.max(0, 8 - groups.length - tailGroups.length)).fill("0"), ...tailGroups);
  }
  return `${groups.slice(0, 4).map((g) => parseInt(g, 16).toString(16)).join(":")}::/64`;
};

setInterval(() => {
  const now = Date.now();
  for (const [key, entry] of authHits) {
    if (entry.resetAt <= now) authHits.delete(key);
  }
}, AUTH_RATE_WINDOW_MS).unref();

const authRateLimit = (req, res, next) => {
  // Routing is case-insensitive and non-strict, so normalise the key
  const key = `${rateLimitIp(req.ip)}:${req.path.toLowerCase().replace(/\/+$/, "")}`;
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
    "/api/auth/register",
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

app.use((req, res) => {
  res.status(404).json({
    success: false,
    message: "Route not found",
  });
});

// Final error handler: JSON only, never a stack trace.
app.use((err, req, res, next) => {
  if (res.headersSent) return next(err);

  // Body-parser errors (malformed JSON, too large, ...) carry a 4xx status
  const status = err.status >= 400 && err.status < 500 ? err.status : 500;
  if (status === 500) console.error("Unhandled Error:", err);

  res.status(status).json({
    success: false,
    message:
      err.type === "entity.parse.failed"
        ? "Malformed JSON body"
        : status === 500
          ? "Internal server error"
          : "Invalid request",
  });
});

module.exports = app;