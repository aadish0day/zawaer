const mongoose = require("mongoose");

const offerSchema = new mongoose.Schema(
  {
    code: {
      type: String,
      required: true,
      unique: true,
      uppercase: true,
      trim: true,
    },
    title: {
      type: String,
      required: true,
      trim: true,
    },
    description: {
      type: String,
      required: true,
      trim: true,
    },
    discountType: {
      type: String,
      enum: ["percentage", "flat"],
      default: "percentage",
    },
    discountValue: {
      type: Number,
      required: true,
      min: 0,
      // Runs on save/create only, so reading existing docs never fails
      validate: {
        validator: function (v) {
          return this.discountType !== "percentage" || v <= 100;
        },
        message: "Percentage discount cannot exceed 100",
      },
    },
    maxDiscount: {
      type: Number,
      default: 0, // 0 means no cap
    },
    minOrderAmount: {
      type: Number,
      default: 0,
    },
    applicableCategory: {
      type: String,
      default: "All",
      trim: true,
    },
    startDate: {
      type: Date,
      default: Date.now,
    },
    expiryDate: {
      type: Date,
      required: true,
    },
    usageLimit: {
      type: Number,
      default: 1000,
    },
    perUserLimit: {
      type: Number,
      default: 0, // 0 means unlimited uses per user
    },
    usedCount: {
      type: Number,
      default: 0,
    },
    isActive: {
      type: Boolean,
      default: true,
    },
    tag: {
      type: String,
      default: "PRIVILEGE OFFER",
      trim: true,
    },
    bannerImage: {
      type: String,
      default: "assets/images/necklace.jpg",
    },
    terms: {
      type: [String],
      default: [
        "Valid on certified 18K/22K gold and diamond jewellery.",
        "Cannot be combined with other promotional codes.",
        "Subject to minimum purchase requirement.",
        "Maison ZAWER reserves the right to modify terms.",
      ],
    },
  },
  {
    timestamps: true,
  }
);

// Virtual helper for expiration check
// Missing expiryDate = no expiry
offerSchema.methods.isExpired = function () {
  return this.expiryDate instanceof Date && new Date() > this.expiryDate;
};

// Calculate exact discount for a given amount
offerSchema.methods.calculateDiscount = function (orderAmount) {
  if (orderAmount < this.minOrderAmount) {
    return 0;
  }

  let discount = 0;
  if (this.discountType === "percentage") {
    discount = (orderAmount * this.discountValue) / 100;
    if (this.maxDiscount > 0 && discount > this.maxDiscount) {
      discount = this.maxDiscount;
    }
  } else if (this.discountType === "flat") {
    discount = this.discountValue;
  }

  // Never more than the order (covers legacy percentage docs above 100)
  return Math.min(Math.round(Math.max(0, discount)), Math.max(0, orderAmount));
};

module.exports = mongoose.model("Offer", offerSchema);
