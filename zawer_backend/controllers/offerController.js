const Offer = require("../models/Offer");
const Product = require("../models/Product");
const Order = require("../models/Order");
const {
  priceItems,
  eligibleSubtotalFor,
  isAllCategories,
  round2,
} = require("./orderController");

const MAX_ITEMS = 50;

// Public shape shared by the list and single-offer endpoints (no usage internals).
// A missing expiryDate means no expiry.
const formatOffer = (offer, now = new Date()) => {
  const hasExpiry = offer.expiryDate instanceof Date;
  const isExpired = offer.isExpired();
  const msRemaining = hasExpiry ? Math.max(0, offer.expiryDate.getTime() - now.getTime()) : null;
  const daysRemaining = hasExpiry ? Math.floor(msRemaining / (1000 * 60 * 60 * 24)) : null;
  const hoursRemaining = hasExpiry
    ? Math.floor((msRemaining % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60))
    : null;

  const isValid =
    offer.isActive &&
    !isExpired &&
    !(offer.startDate && now < offer.startDate) &&
    // null / <= 0 = unlimited, same as checkout
    (!(offer.usageLimit > 0) || offer.usedCount < offer.usageLimit);

  return {
    id: offer._id,
    code: offer.code,
    title: offer.title,
    description: offer.description,
    discountType: offer.discountType,
    discountValue: offer.discountValue,
    maxDiscount: offer.maxDiscount,
    minOrderAmount: offer.minOrderAmount,
    applicableCategory: offer.applicableCategory,
    startDate: offer.startDate,
    expiryDate: offer.expiryDate ?? null,
    isExpired,
    daysRemaining,
    hoursRemaining,
    isValid,
    tag: offer.tag,
    bannerImage: offer.bannerImage,
    terms: offer.terms,
  };
};

// =========================================================
// GET ALL ACTIVE OFFERS & PROMOTIONS
// =========================================================
exports.getAllOffers = async (req, res) => {
  try {
    const now = new Date();
    const offers = await Offer.find({ isActive: true }).sort({ createdAt: -1 });

    const formattedOffers = offers.map((offer) => formatOffer(offer, now));

    res.status(200).json({
      success: true,
      count: formattedOffers.length,
      offers: formattedOffers,
    });
  } catch (error) {
    console.error("Get Offers Error:", error);
    res.status(500).json({
      success: false,
      message: "Failed to retrieve offers",
    });
  }
};

// =========================================================
// GET DISCOUNTED JEWELLERY PRODUCTS
// =========================================================
exports.getDiscountedProducts = async (req, res) => {
  try {
    const discountedProducts = await Product.find({
      $or: [
        { isSpecialOffer: true },
        { discountPercentage: { $gt: 0 } },
      ],
    })
      .select("-reviews")
      .sort({ discountPercentage: -1 });

    res.status(200).json({
      success: true,
      count: discountedProducts.length,
      products: discountedProducts,
    });
  } catch (error) {
    console.error("Get Discounted Products Error:", error);
    res.status(500).json({
      success: false,
      message: "Failed to fetch discounted products",
    });
  }
};

// =========================================================
// VALIDATE COUPON CODE & CALCULATE DISCOUNT
// =========================================================
exports.validateCoupon = async (req, res) => {
  try {
    const { couponCode, subtotal = 0, category, items } = req.body;

    if (!couponCode || typeof couponCode !== "string" || !couponCode.trim()) {
      return res.status(400).json({
        success: false,
        message: "Please provide a valid coupon code",
      });
    }

    const code = couponCode.trim().toUpperCase();
    let orderSubtotal = Number(subtotal) || 0;

    // Preferred: price { productId, quantity } items from the DB so the preview matches checkout.
    // Without items, fall back to the client-supplied subtotal/category (legacy callers).
    let lines = null;
    if (items != null && (!Array.isArray(items) || items.length > MAX_ITEMS)) {
      return res.status(400).json({
        success: false,
        message: `items must be an array of at most ${MAX_ITEMS} entries`,
      });
    }
    if (Array.isArray(items) && items.length > 0) {
      const priced = await priceItems(items);
      if (priced.error) {
        return res.status(400).json({
          success: false,
          message: priced.error,
        });
      }
      orderSubtotal = priced.subtotal;
      lines = priced.lines;
    }

    const offer = await Offer.findOne({ code });

    if (!offer) {
      return res.status(404).json({
        success: false,
        message: `Privilege code '${code}' not found in the Maison directory`,
      });
    }

    if (!offer.isActive) {
      return res.status(400).json({
        success: false,
        message: `Privilege code '${code}' is no longer active`,
      });
    }

    const now = new Date();

    // Expiry Check (missing expiryDate = no expiry, same as checkout)
    if (offer.isExpired()) {
      const expStr = offer.expiryDate.toLocaleDateString("en-IN", {
        day: "2-digit",
        month: "short",
        year: "numeric",
      });
      return res.status(400).json({
        success: false,
        isExpired: true,
        message: `Privilege code '${code}' expired on ${expStr}`,
      });
    }

    // Start Date Check
    if (now < offer.startDate) {
      return res.status(400).json({
        success: false,
        message: `Privilege code '${code}' will be active from ${offer.startDate.toLocaleDateString()}`,
      });
    }

    // Usage Limit Check
    if (offer.usageLimit > 0 && offer.usedCount >= offer.usageLimit) {
      return res.status(400).json({
        success: false,
        message: `Privilege code '${code}' has reached its maximum client usage limit`,
      });
    }

    // Per-user limit (signed-in callers only; checkout enforces it regardless)
    if (offer.perUserLimit > 0 && req.user) {
      const userUses = await Order.countDocuments({
        userId: req.user.id,
        couponCode: code,
        status: { $ne: "Cancelled" },
      });
      if (userUses >= offer.perUserLimit) {
        return res.status(400).json({
          success: false,
          message: `Coupon code '${code}' has already been used on your account`,
        });
      }
    }

    // Category Restriction Check (eligibleSubtotal = value of matching items only)
    let eligibleSubtotal = orderSubtotal;
    if (lines) {
      eligibleSubtotal = eligibleSubtotalFor(offer, lines);
      if (!isAllCategories(offer.applicableCategory) && eligibleSubtotal <= 0) {
        return res.status(400).json({
          success: false,
          applicableCategory: offer.applicableCategory,
          message: `Code '${code}' is only applicable to ${offer.applicableCategory} collections`,
        });
      }
    } else if (
      !isAllCategories(offer.applicableCategory) &&
      typeof category === "string" &&
      category.trim() &&
      offer.applicableCategory.trim().toLowerCase() !== category.trim().toLowerCase()
    ) {
      return res.status(400).json({
        success: false,
        applicableCategory: offer.applicableCategory,
        message: `Code '${code}' is only applicable to ${offer.applicableCategory} collections`,
      });
    }

    // Minimum Order Amount Check
    if (eligibleSubtotal < offer.minOrderAmount) {
      return res.status(400).json({
        success: false,
        minOrderAmount: offer.minOrderAmount,
        message: `Minimum vault order valuation of ₹${offer.minOrderAmount.toLocaleString()} is required for code '${code}'`,
      });
    }

    // Calculate Discount (same method checkout uses)
    const discountAmount = round2(offer.calculateDiscount(eligibleSubtotal));
    const finalAmount = round2(Math.max(0, orderSubtotal - discountAmount));
    orderSubtotal = round2(orderSubtotal);
    eligibleSubtotal = round2(eligibleSubtotal);

    res.status(200).json({
      success: true,
      message: `Privilege code '${code}' applied! You saved ₹${discountAmount.toLocaleString()}`,
      coupon: {
        code: offer.code,
        title: offer.title,
        discountType: offer.discountType,
        discountValue: offer.discountValue,
        discountAmount,
        maxDiscount: offer.maxDiscount,
        minOrderAmount: offer.minOrderAmount,
        subtotal: orderSubtotal,
        eligibleSubtotal,
        finalAmount,
        savings: discountAmount,
        expiryDate: offer.expiryDate ?? null,
      },
    });
  } catch (error) {
    console.error("Validate Coupon Error:", error);
    res.status(500).json({
      success: false,
      message: "Failed to validate coupon code",
    });
  }
};

// =========================================================
// GET SINGLE OFFER DETAILS BY CODE
// =========================================================
exports.getOfferByCode = async (req, res) => {
  try {
    const code = req.params.code.trim().toUpperCase();
    const offer = await Offer.findOne({ code, isActive: true });

    if (!offer) {
      return res.status(404).json({
        success: false,
        message: `Offer with code '${code}' not found`,
      });
    }

    res.status(200).json({
      success: true,
      offer: formatOffer(offer),
    });
  } catch (error) {
    console.error("Get Offer Error:", error);
    res.status(500).json({
      success: false,
      message: "Error fetching offer",
    });
  }
};
