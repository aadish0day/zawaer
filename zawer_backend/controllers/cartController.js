const Cart = require("../models/Cart");
const getCart = async (req, res) => {
  try {
    const userId = req.user.id;

    let cart = await Cart.findOne({
      userId: userId.toString(),
    });

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

    let cart = await Cart.findOne({
      userId,
    });

    if (!cart) {
      cart = await Cart.create({
        userId,
        items: [],
      });
    }

    const existingItem =
      cart.items.find(
        (item) =>
          item.productId ===
          productId.toString()
      );

    if (existingItem) {
      existingItem.quantity += Number(quantity);
    } else {
      cart.items.push({
        productId: productId.toString(),
        quantity: Number(quantity),
      });
    }

    await cart.save();

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

const updateCartQuantity = async (
  req,
  res
) => {
  try {
    const userId = req.user.id.toString();

    const productId =
      req.params.productId;

    const quantity =
      Number(req.body.quantity);

    if (!quantity || quantity < 1) {
      return res.status(400).json({
        success: false,
        message: "Quantity must be at least 1",
      });
    }

    const cart = await Cart.findOne({
      userId,
    });

    if (!cart) {
      return res.status(404).json({
        success: false,
        message: "Cart not found",
      });
    }

    const item =
      cart.items.find(
        (cartItem) =>
          cartItem.productId.toString() === productId.toString()
      );

    if (!item) {
      return res.status(404).json({
        success: false,
        message: "Product not found in cart",
      });
    }

    item.quantity = quantity;

    await cart.save();

    return res.status(200).json({
      success: true,
      message: "Cart quantity updated",
      cart,
    });
  } catch (error) {
    console.error(
      "Update Cart Error:",
      error.message
    );

    return res.status(500).json({
      success: false,
      message:
          "Failed to update cart quantity",
    });
  }
};

const removeFromCart = async (
  req,
  res
) => {
  try {
    const userId = req.user.id.toString();

    const productId =
      req.params.productId;

    const cart = await Cart.findOne({
      userId,
    });

    if (!cart) {
      return res.status(404).json({
        success: false,
        message: "Cart not found",
      });
    }

    cart.items =
        cart.items.filter(
      (item) =>
        item.productId.toString() !== productId.toString()
    );

    await cart.save();

    return res.status(200).json({
      success: true,
      message: "Product removed from cart",
      cart,
    });
  } catch (error) {
    console.error(
      "Remove Cart Error:",
      error.message
    );

    return res.status(500).json({
      success: false,
      message: "Failed to remove product",
    });
  }
};

const clearCart = async (
  req,
  res
) => {
  try {
    const userId = req.user.id.toString();

    const cart = await Cart.findOne({
      userId,
    });

    if (!cart) {
      return res.status(404).json({
        success: false,
        message: "Cart not found",
      });
    }

    cart.items = [];

    await cart.save();

    return res.status(200).json({
      success: true,
      message: "Cart cleared",
      cart,
    });
  } catch (error) {
    console.error(
      "Clear Cart Error:",
      error.message
    );

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