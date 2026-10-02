const Wishlist = require("../models/Wishlist");
const Product = require("../models/Product");
const { canonicalProductIds, productIdForms } = require("./cartController");

// Concurrent upserts on the unique userId can lose with E11000; the retry sees the winner's doc.
const retryOnDuplicate = async (fn, retries = 3) => {
  for (let attempt = 0; ; attempt++) {
    try {
      return await fn();
    } catch (error) {
      if (error.code !== 11000 || attempt >= retries) throw error;
    }
  }
};

const getWishlist = async (req, res) => {
  try {
    const userId = req.user.id;

    // Raw doc kept so the normalization write below can guard on the exact stored items
    const raw = await retryOnDuplicate(() =>
      Wishlist.findOneAndUpdate(
        { userId },
        { $setOnInsert: { items: [] } },
        { returnDocument: "after", upsert: true }
      ).lean()
    );
    const wishlist = Wishlist.hydrate(raw);

    // Normalize legacy _id lines to the custom id (deduped) and drop deleted products
    if (wishlist.items.length > 0) {
      const canonical = await canonicalProductIds(wishlist.items.map((i) => i.productId));
      const ids = [...new Set(wishlist.items.map((i) => canonical.get(i.productId)).filter(Boolean))];
      if (ids.length !== wishlist.items.length || ids.some((id, i) => id !== wishlist.items[i].productId)) {
        // Guarded on the items array we read so a concurrent add isn't overwritten; a miss just retries next read
        await Wishlist.updateOne(
          { _id: wishlist._id, $expr: { $eq: ["$items", { $literal: raw.items }] } },
          { $set: { items: ids.map((productId) => ({ productId })) } }
        );
      }
    }

    return res.status(200).json({
      success: true,
      wishlist: await Wishlist.findById(wishlist._id).populate({ path: "items.product", select: "-reviews" }),
    });
  } catch (error) {
    console.error("Get Wishlist Error:", error.message);
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

    const product = await Product.findByAnyId(productId);
    if (!product) {
      return res.status(404).json({
        success: false,
        message: "Product not found",
      });
    }

    const prodIdStr = product.id;
    const existing = await Wishlist.findOne({
      userId,
      "items.productId": prodIdStr,
    });

    const wishlist = await retryOnDuplicate(() =>
      Wishlist.findOneAndUpdate(
        { userId },
        { $addToSet: { items: { productId: prodIdStr } } },
        { returnDocument: "after", upsert: true, setDefaultsOnInsert: true }
      )
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

    const ids = await productIdForms(productId);
    const wishlist = await Wishlist.findOneAndUpdate(
      { userId },
      { $pull: { items: { productId: { $in: ids } } } },
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
