const express = require("express");
const router = express.Router();
const offerController = require("../controllers/offerController");
const { optionalAuth } = require("../middleware/authMiddleware");

// Public routes for offers & discounts
router.get("/", offerController.getAllOffers);
router.get("/discounted-products", offerController.getDiscountedProducts);
// Guests allowed; a valid token enables the per-user limit check
router.post("/validate-coupon", optionalAuth, offerController.validateCoupon);
router.get("/:code", offerController.getOfferByCode);

module.exports = router;
