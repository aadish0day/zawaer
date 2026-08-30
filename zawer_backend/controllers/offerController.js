const Offer = require("../models/Offer");
const Product = require("../models/Product");

// =========================================================
// GET ALL ACTIVE OFFERS & PROMOTIONS
// =========================================================
exports.getAllOffers = async (req, res) => {
  try {
    const now = new Date();
    const offers = await Offer.find({ isActive: true }).sort({ createdAt: -1 });

    const formattedOffers = offers.map((offer) => {
      const isExpired = now > offer.expiryDate;
      const msRemaining = Math.max(0, offer.expiryDate.getTime() - now.getTime());
      const daysRemaining = Math.floor(msRemaining / (1000 * 60 * 60 * 24));
      const hoursRemaining = Math.floor(
        (msRemaining % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60)
      );

      const isValid =
        offer.isActive &&
        !isExpired &&
        (offer.usageLimit === 0 || offer.usedCount < offer.usageLimit);

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
        expiryDate: offer.expiryDate,
        isExpired,
        daysRemaining,
        hoursRemaining,
        isValid,
        tag: offer.tag,
        bannerImage: offer.bannerImage,
        terms: offer.terms,
        usedCount: offer.usedCount,
      };
    });

    res.status(200).json({
      success: true,
      count: formattedOffers.length,
      offers: formattedOffers,
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: "Failed to retrieve offers",
      error: error.message,
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
    }).sort({ discountPercentage: -1 });

    res.status(200).json({
      success: true,
      count: discountedProducts.length,
      products: discountedProducts,
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: "Failed to fetch discounted products",
      error: error.message,
    });
  }
};

// =========================================================
// VALIDATE COUPON CODE & CALCULATE DISCOUNT
// =========================================================
exports.validateCoupon = async (req, res) => {
  try {
    const { couponCode, subtotal = 0, category } = req.body;

    if (!couponCode || typeof couponCode !== "string" || !couponCode.trim()) {
      return res.status(400).json({
        success: false,
        message: "Please provide a valid coupon code",
      });
    }

    const code = couponCode.trim().toUpperCase();
    const orderSubtotal = Number(subtotal) || 0;

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

    // Expiry Check
    if (now > offer.expiryDate) {
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

    // Minimum Order Amount Check
    if (orderSubtotal < offer.minOrderAmount) {
      return res.status(400).json({
        success: false,
        minOrderAmount: offer.minOrderAmount,
        message: `Minimum vault order valuation of ₹${offer.minOrderAmount.toLocaleString()} is required for code '${code}'`,
      });
    }

    // Category Restriction Check
    if (
      offer.applicableCategory &&
      offer.applicableCategory !== "All" &&
      category &&
      offer.applicableCategory.toLowerCase() !== category.toLowerCase()
    ) {
      return res.status(400).json({
        success: false,
        applicableCategory: offer.applicableCategory,
        message: `Code '${code}' is only applicable to ${offer.applicableCategory} collections`,
      });
    }

    // Calculate Discount
    let discountAmount = 0;
    if (offer.discountType === "percentage") {
      const rawDiscount = (orderSubtotal * offer.discountValue) / 100;
      if (offer.maxDiscount > 0) {
        discountAmount = Math.min(rawDiscount, offer.maxDiscount);
      } else {
        discountAmount = rawDiscount;
      }
    } else if (offer.discountType === "flat") {
      discountAmount = Math.min(offer.discountValue, orderSubtotal);
    }

    discountAmount = Math.round(discountAmount);
    const finalAmount = Math.max(0, orderSubtotal - discountAmount);

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
        finalAmount,
        savings: discountAmount,
        expiryDate: offer.expiryDate,
      },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: "Failed to validate coupon code",
      error: error.message,
    });
  }
};

// =========================================================
// GET SINGLE OFFER DETAILS BY CODE
// =========================================================
exports.getOfferByCode = async (req, res) => {
  try {
    const code = req.params.code.trim().toUpperCase();
    const offer = await Offer.findOne({ code });

    if (!offer) {
      return res.status(404).json({
        success: false,
        message: `Offer with code '${code}' not found`,
      });
    }

    const now = new Date();
    const isExpired = now > offer.expiryDate;

    res.status(200).json({
      success: true,
      offer: {
        ...offer.toObject(),
        isExpired,
      },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: "Error fetching offer",
      error: error.message,
    });
  }
};
