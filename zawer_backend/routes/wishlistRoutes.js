const express = require("express");

const router = express.Router();

const authMiddleware = require("../middleware/authMiddleware");

const {
  getWishlist,
  addToWishlist,
  removeFromWishlist,
} = require("../controllers/wishlistController");

router.use(authMiddleware);

router.get("/", getWishlist);

router.post("/", addToWishlist);

router.delete("/:productId", removeFromWishlist);

module.exports = router;
