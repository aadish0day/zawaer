const mongoose = require("mongoose");

const orderItemSchema = new mongoose.Schema(
  {
    productId: {
      type: String,
      required: true,
    },
    name: {
      type: String,
      required: true,
    },
    image: {
      type: String,
      default: "",
    },
    price: {
      type: Number,
      required: true,
      min: 0,
    },
    quantity: {
      type: Number,
      required: true,
      min: 1,
    },
  },
  { _id: false }
);

const timelineStepSchema = new mongoose.Schema(
  {
    status: {
      type: String,
      required: true,
    },
    title: {
      type: String,
      required: true,
    },
    description: {
      type: String,
      default: "",
    },
    location: {
      type: String,
      default: "ZAWER Luxury Vault Hub",
    },
    timestamp: {
      type: Date,
      default: Date.now,
    },
    isCompleted: {
      type: Boolean,
      default: false,
    },
  },
  { _id: false }
);

const orderSchema = new mongoose.Schema(
  {
    userId: {
      type: String,
      required: true,
      trim: true,
    },

    customerName: {
      type: String,
      required: true,
      trim: true,
    },

    phone: {
      type: String,
      required: true,
      trim: true,
    },

    address: {
      type: String,
      required: true,
      trim: true,
    },

    paymentMethod: {
      type: String,
      default: "Cash on Delivery",
    },

    items: [orderItemSchema],

    subtotal: {
      type: Number,
    },

    discountAmount: {
      type: Number,
      default: 0,
    },

    couponCode: {
      type: String,
      default: "",
      uppercase: true,
      trim: true,
    },

    // Offer whose usedCount this order reserved; released by id on cancel (absent on old orders)
    couponOfferId: {
      type: mongoose.Schema.Types.ObjectId,
    },

    totalAmount: {
      type: Number,
      required: true,
      min: 0,
    },

    status: {
      type: String,
      enum: [
        "Placed",
        "Order Placed",
        "Order Confirmed",
        "Processing",
        "Shipped",
        "Out for Delivery",
        "Delivered",
        "Cancelled",
      ],
      default: "Order Placed",
    },

    trackingNumber: {
      type: String,
      // New orders only: Mongoose also applies defaults when loading old orders that lack the
      // field, which would show a different random number on every read.
      default: function () {
        return this.isNew ? "ZWR-" + Math.floor(100000 + Math.random() * 900000) : undefined;
      },
    },

    courierPartner: {
      type: String,
      default: "Sequel Secure Luxury Logistics",
    },

    currentLocation: {
      type: String,
      default: "Mumbai Central Vault Hub",
    },

    estimatedDelivery: {
      type: Date,
      // Only for new orders; otherwise old orders get a fresh date on every read
      default: function () {
        return this.isNew ? new Date(Date.now() + 4 * 24 * 60 * 60 * 1000) : undefined;
      },
    },

    aiDeliveryInsight: {
      type: String,
      default:
        "Your handcrafted luxury jewellery has been registered in our high-security vault system and is queued for hallmarking inspection.",
    },

    timeline: {
      type: [timelineStepSchema],
      default: [],
    },

    // Client-generated key so a retried checkout returns the same order
    idempotencyKey: {
      type: String,
    },
    // sha256 of the request that created the order with this key (see placeOrder replay)
    requestHash: {
      type: String,
      select: false,
    },
  },
  {
    timestamps: true,
  }
);

// Partial: only real tracking numbers are unique, so legacy orders without one can coexist.
// An existing non-partial trackingNumber_1 index must be replaced: run node seed/fix-tracking-index.js
orderSchema.index(
  { trackingNumber: 1 },
  { unique: true, partialFilterExpression: { trackingNumber: { $type: "string", $gt: "" } } }
);
orderSchema.index({ userId: 1 });
orderSchema.index(
  { userId: 1, idempotencyKey: 1 },
  { unique: true, partialFilterExpression: { idempotencyKey: { $type: "string" } } }
);

orderSchema.pre("validate", function () {
  if (this.subtotal == null) {
    if (this.totalAmount != null) {
      this.subtotal = this.totalAmount;
    } else if (Array.isArray(this.items) && this.items.length > 0) {
      this.subtotal = this.items.reduce(
        (sum, item) => sum + (Number(item.price) || 0) * (Number(item.quantity) || 1),
        0
      );
    }
  }
});

module.exports = mongoose.model("Order", orderSchema);
