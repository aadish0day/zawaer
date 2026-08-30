const express = require("express");
const router = express.Router();
const offerController = require("../controllers/offerController");

// Public routes for offers & discounts
router.get("/", offerController.getAllOffers);
router.get("/discounted-products", offerController.getDiscountedProducts);
router.post("/validate-coupon", offerController.validateCoupon);
router.get("/:code", offerController.getOfferByCode);

module.exports = router;
