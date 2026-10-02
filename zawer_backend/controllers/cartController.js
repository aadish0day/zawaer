const mongoose = require("mongoose");
const Cart = require("../models/Cart");
const Product = require("../models/Product");
const { MAX_ITEM_QUANTITY, MAX_ORDER_LINES } = require("./orderController");

const CART_FULL = Symbol("cartFull");

const isValidQuantity = (qty) =>
  Number.isInteger(qty) && qty >= 1 && qty <= MAX_ITEM_QUANTITY;

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

// Maps stored productIds (custom id or legacy Mongo _id) to the product's custom id.
// Ids of deleted products are absent from the map.
const canonicalProductIds = async (ids) => {
  const objectIds = ids.filter((id) => mongoose.Types.ObjectId.isValid(id));
  const products = await Product.find(
    { $or: [{ id: { $in: ids } }, { _id: { $in: objectIds } }] },
    "id"
  );
  const map = new Map();
  for (const p of products) {
    map.set(p.id, p.id);
    map.set(p._id.toString(), p.id);
  }
  return map;
};

// Every form a :productId param may be stored under (raw, custom id, _id).
const productIdForms = async (rawId) => {
  const pid = String(rawId);
  const product = await Product.findByAnyId(pid);
  return product ? [pid, product.id, product._id.toString()] : [pid];
};

const getCart = async (req, res) => {
  try {
    const userId = req.user.id.toString();

    // Raw doc kept so the normalization write below can guard on the exact stored items
    const raw = await retryOnDuplicate(() =>
      Cart.findOneAndUpdate(
        { userId },
        { $setOnInsert: { items: [] } },
        { returnDocument: "after", upsert: true }
      ).lean()
    );
    const cart = Cart.hydrate(raw);

    // Normalize legacy _id lines to the custom id (merged, capped) and drop deleted products
    if (cart.items.length > 0) {
      const canonical = await canonicalProductIds(cart.items.map((i) => i.productId));
      const merged = new Map();
      for (const { productId, quantity } of cart.items) {
        const id = canonical.get(productId);
        if (id) merged.set(id, Math.min(MAX_ITEM_QUANTITY, (merged.get(id) || 0) + quantity));
      }
      const items = [...merged].map(([productId, quantity]) => ({ productId, quantity }));
      const changed =
        items.length !== cart.items.length ||
        items.some((it, i) => it.productId !== cart.items[i].productId || it.quantity !== cart.items[i].quantity);
      if (changed) {
        // Guarded on the items array we read so a concurrent add isn't overwritten; a miss just retries next read
        await Cart.updateOne({ _id: cart._id, $expr: { $eq: ["$items", { $literal: raw.items }] } }, { $set: { items } });
      }
    }

    return res.status(200).json({
      success: true,
      cart: await Cart.findById(cart._id).populate({ path: "items.product", select: "-reviews" }),
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

      // A new line can't go past MAX_ORDER_LINES distinct pieces (checkout's limit)
      const full = await Cart.exists({
        userId,
        [`items.${MAX_ORDER_LINES - 1}`]: { $exists: true },
        "items.productId": { $ne: prodIdStr },
      });
      if (full) return CART_FULL;

      // 2. Push only if the line is still absent and the cart has room. If another request
      // changed that meanwhile, the filter misses, the upsert hits the unique userId (E11000)
      // and we retry, which re-runs the checks above.
      return Cart.findOneAndUpdate(
        {
          userId,
          "items.productId": { $ne: prodIdStr },
          [`items.${MAX_ORDER_LINES - 1}`]: { $exists: false },
        },
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

    if (cart === CART_FULL) {
      return res.status(400).json({
        success: false,
        message: `Your bag can hold at most ${MAX_ORDER_LINES} different pieces`,
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

    const ids = await productIdForms(productId);
    const cart = await Cart.findOneAndUpdate(
      { userId, "items.productId": { $in: ids } },
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

    const ids = await productIdForms(productId);
    const cart = await Cart.findOneAndUpdate(
      { userId },
      { $pull: { items: { productId: { $in: ids } } } },
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
  canonicalProductIds,
  productIdForms,
};