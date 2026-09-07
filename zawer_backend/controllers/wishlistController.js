const Wishlist = require("../models/Wishlist");
const Product = require("../models/Product");

const getWishlist = async (req, res) => {
  try {
    const userId = req.user.id;

    let wishlist = await Wishlist.findOne({ userId }).populate({ path: "items.product", model: "Product" });

    if (!wishlist) {
      wishlist = await Wishlist.create({ userId, items: [] });
    }

    return res.status(200).json({
      success: true,
      wishlist,
    });
  } catch (error) {
    return res.status(500).json({
      success: false,
      message: "Failed to fetch wishlist",
    });
  }
};

const addToWishlist = async (req, res) => {
  try {
    const { productId } = req.body;
    const userId = req.user.id;

    if (!productId) {
      return res.status(400).json({
        success: false,
        message: "Product ID is required",
      });
    }

    const prodIdStr = productId.toString();
    const existing = await Wishlist.findOne({
      userId,
      "items.productId": prodIdStr,
    });

    const wishlist = await Wishlist.findOneAndUpdate(
      { userId },
      { $addToSet: { items: { productId: prodIdStr } } },
      { returnDocument: "after", upsert: true, setDefaultsOnInsert: true }
    );

    return res.status(200).json({
      success: true,
      message: existing
        ? "Product already in wishlist"
        : "Product added to wishlist",
      wishlist,
    });
  } catch (error) {
    return res.status(500).json({
      success: false,
      message: "Failed to add to wishlist",
    });
  }
};

const removeFromWishlist = async (req, res) => {
  try {
    const productId = req.params.productId;
    const userId = req.user.id;

    const prodIdStr = productId.toString();
    const wishlist = await Wishlist.findOneAndUpdate(
      { userId },
      { $pull: { items: { productId: prodIdStr } } },
      { returnDocument: "after" }
    );

    if (!wishlist) {
      return res.status(404).json({
        success: false,
        message: "Wishlist not found",
      });
    }

    return res.status(200).json({
      success: true,
      message: "Product removed from wishlist",
      wishlist,
    });
  } catch (error) {
    return res.status(500).json({
      success: false,
      message: "Failed to remove from wishlist",
    });
  }
};

module.exports = {
  getWishlist,
  addToWishlist,
  removeFromWishlist,
};
