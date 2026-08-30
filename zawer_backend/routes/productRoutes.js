const express = require("express");

const {
  getProducts,
  getProductById,
  searchProducts,
  addProductReview,
  getProductReviews,
} = require("../controllers/productController");

const authMiddleware = require("../middleware/authMiddleware");

const router = express.Router();

// Get all products
router.get("/", getProducts);

// Search products
router.get("/search", searchProducts);

// Get product by ID
router.get("/:id", getProductById);

// Get product reviews
router.get("/:id/reviews", getProductReviews);

// Add product review (requires auth)
router.post("/:id/reviews", authMiddleware, addProductReview);

module.exports = router;