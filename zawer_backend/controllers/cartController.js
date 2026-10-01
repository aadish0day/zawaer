const Cart = require("../models/Cart");
const Product = require("../models/Product");
const { MAX_ITEM_QUANTITY } = require("./orderController");

const isValidQuantity = (qty) =>
  Number.isInteger(qty) && qty >= 1 && qty <= MAX_ITEM_QUANTITY;

// Concurrent upserts on the unique userId can lose with E11000; the retry sees the winner's doc.
const retryOnDuplicate = async (fn) => {
  try {
    return await fn();
  } catch (error) {
    if (error.code !== 11000) throw error;
    return fn();
  }
};

const getCart = async (req, res) => {
  try {
    const userId = req.user.id.toString();

    const cart = await retryOnDuplicate(() =>
      Cart.findOneAndUpdate(
        { userId },
        { $setOnInsert: { items: [] } },
        { returnDocument: "after", upsert: true }
      ).populate({ path: "items.product", select: "-reviews" })
    );

    return res.status(200).json({
      success: true,
      cart,
    });
  } catch (error) {
    console.error("Get Cart Error:", error.message);

    return res.status(500).json({
      success: false,
      message: "Failed to fetch cart",
    });
  }
};

const addToCart = async (req, res) => {
  try {
    const userId = req.user.id.toString();

    const {
      productId,
      quantity = 1,
    } = req.body;

    if (!productId) {
      return res.status(400).json({
        success: false,
        message: "Product ID is required",
      });
    }

    const numQty = Number(quantity);
    if (!isValidQuantity(numQty)) {
      return res.status(400).json({
        success: false,
        message: `Quantity must be a whole number between 1 and ${MAX_ITEM_QUANTITY}`,
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

    const cart = await retryOnDuplicate(async () => {
      // 1. Atomically increment quantity if the product is already in the cart (capped)
      const updated = await Cart.findOneAndUpdate(
        {
          userId,
          items: {
            $elemMatch: {
              productId: prodIdStr,
              quantity: { $lte: MAX_ITEM_QUANTITY - numQty },
            },
          },
        },
        { $inc: { "items.$.quantity": numQty } },
        { returnDocument: "after" }
      );
      if (updated) return updated;

      const overCap = await Cart.exists({
        userId,
        items: {
          $elemMatch: {
            productId: prodIdStr,
            quantity: { $gt: MAX_ITEM_QUANTITY - numQty },
          },
        },
      });
      if (overCap) return null;

      // 2. Push only if the line is still absent. If another request added it meanwhile,
      // the filter misses, the upsert hits the unique userId (E11000) and we retry.
      return Cart.findOneAndUpdate(
        { userId, "items.productId": { $ne: prodIdStr } },
        { $push: { items: { productId: prodIdStr, quantity: numQty } } },
        { returnDocument: "after", upsert: true }
      );
    });

    if (!cart) {
      return res.status(400).json({
        success: false,
        message: `You can add at most ${MAX_ITEM_QUANTITY} of this item`,
      });
    }

    return res.status(200).json({
      success: true,
      message: "Product added to cart",
      cart,
    });
  } catch (error) {
    console.error("Add Cart Error:", error.message);

    return res.status(500).json({
      success: false,
      message: "Failed to add product to cart",
    });
  }
};

const updateCartQuantity = async (req, res) => {
  try {
    const userId = req.user.id.toString();
    const productId = req.params.productId;
    const quantity = Number(req.body.quantity);

    if (!isValidQuantity(quantity)) {
      return res.status(400).json({
        success: false,
        message: `Quantity must be a whole number between 1 and ${MAX_ITEM_QUANTITY}`,
      });
    }

    const prodIdStr = productId.toString();
    const cart = await Cart.findOneAndUpdate(
      { userId, "items.productId": prodIdStr },
      { $set: { "items.$.quantity": quantity } },
      { returnDocument: "after" }
    );

    if (!cart) {
      return res.status(404).json({
        success: false,
        message: "Product not found in cart",
      });
    }

    return res.status(200).json({
      success: true,
      message: "Cart quantity updated",
      cart,
    });
  } catch (error) {
    console.error("Update Cart Error:", error.message);
    return res.status(500).json({
      success: false,
      message: "Failed to update cart quantity",
    });
  }
};

const removeFromCart = async (req, res) => {
  try {
    const userId = req.user.id.toString();
    const productId = req.params.productId;

    const prodIdStr = productId.toString();
    const cart = await Cart.findOneAndUpdate(
      { userId },
      { $pull: { items: { productId: prodIdStr } } },
      { returnDocument: "after" }
    );

    if (!cart) {
      return res.status(404).json({
        success: false,
        message: "Cart not found",
      });
    }

    return res.status(200).json({
      success: true,
      message: "Product removed from cart",
      cart,
    });
  } catch (error) {
    console.error("Remove Cart Error:", error.message);
    return res.status(500).json({
      success: false,
      message: "Failed to remove product",
    });
  }
};

const clearCart = async (req, res) => {
  try {
    const userId = req.user.id.toString();

    const cart = await Cart.findOneAndUpdate(
      { userId },
      { $set: { items: [] } },
      { returnDocument: "after" }
    );

    if (!cart) {
      return res.status(404).json({
        success: false,
        message: "Cart not found",
      });
    }

    return res.status(200).json({
      success: true,
      message: "Cart cleared",
      cart,
    });
  } catch (error) {
    console.error("Clear Cart Error:", error.message);
    return res.status(500).json({
      success: false,
      message: "Failed to clear cart",
    });
  }
};

module.exports = {
  getCart,
  addToCart,
  updateCartQuantity,
  removeFromCart,
  clearCart,
};