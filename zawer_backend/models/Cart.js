const mongoose = require("mongoose");

const cartItemSchema = new mongoose.Schema(
  {
    productId: {
      type: String,
      required: true,
    },

    quantity: {
      type: Number,
      required: true,
      min: 1,
      default: 1,
    },
  },
  {
    _id: false,
    toJSON: { virtuals: true },
    toObject: { virtuals: true },
  }
);

cartItemSchema.virtual("product", {
  ref: "Product",
  localField: "productId",
  foreignField: "id",
  justOne: true,
});

const cartSchema = new mongoose.Schema(
  {
    userId: {
      type: String,
      required: true,
      unique: true,
    },

    items: {
      type: [cartItemSchema],
      default: [],
    },
  },
  {
    timestamps: true,
    collection: "carts",
    toJSON: { virtuals: true },
    toObject: { virtuals: true },
  }
);

cartSchema.virtual("product", {
  ref: "Product",
  localField: "productId",
  foreignField: "id",
  justOne: true,
});

module.exports = mongoose.model("Cart", cartSchema);