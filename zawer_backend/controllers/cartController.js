const Cart = require("../models/Cart");
const Product = require("../models/Product");
const { MAX_ITEM_QUANTITY } = require("./orderController");

const isValidQuantity = (qty) =>
  Number.isInteger(qty) && qty >= 1 && qty <= MAX_ITEM_QUANTITY;

const getCart = async (req, res) => {
  try {
    const userId = req.user.id;

    let cart = await Cart.findOne({ userId }).populate({ path: "items.product", model: "Product" });

    if (!cart) {
      cart = await Cart.create({
        userId: userId.toString(),
        items: [],
      });
    }

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

    const prodIdStr = productId.toString();

    // 1. Try to atomically increment quantity if the product is already in the cart (capped)
    let cart = await Cart.findOneAndUpdate(
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

    if (!cart && (await Cart.exists({ userId, "items.productId": prodIdStr }))) {
      return res.status(400).json({
        success: false,
        message: `You can add at most ${MAX_ITEM_QUANTITY} of this item`,
      });
    }

    // 2. If the product was not in the cart (or cart does not exist), push item and upsert
    if (!cart) {
      cart = await Cart.findOneAndUpdate(
        { userId },
        {
          $push: {
            items: {
              productId: prodIdStr,
              quantity: numQty,
            },
          },
        },
        { returnDocument: "after", upsert: true }
      );
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