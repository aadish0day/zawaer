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