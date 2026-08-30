const express = require("express");

const router = express.Router();

const authMiddleware = require("../middleware/authMiddleware");

const {
  placeOrder,
  getMyOrders,
  getOrderById,
  getOrderTracking,
  updateOrderStatus,
} = require("../controllers/orderController");

router.use(authMiddleware);

// Place a new order
router.post("/", placeOrder);

// Get list of orders for authenticated user
router.get("/", getMyOrders);

// Get specific order by ID
router.get("/:id", getOrderById);

// Get live order tracking module data by ID
router.get("/:id/tracking", getOrderTracking);

// Get live order tracking by Tracking Number or ID query
router.get("/track/:query", getOrderTracking);

// Update / advance order tracking status
router.put("/:id/status", updateOrderStatus);

module.exports = router;
