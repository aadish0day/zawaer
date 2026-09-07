const mongoose = require("mongoose");
const Order = require("../models/Order");
const Product = require("../models/Product");
const Cart = require("../models/Cart");
const Offer = require("../models/Offer");

const TRACKING_STAGES = [
  {
    status: "Order Placed",
    title: "Order Placed",
    description: "Your order has been received and registered in our luxury concierge queue.",
    location: "ZAWER Online Hub, Mumbai",
  },
  {
    status: "Order Confirmed",
    title: "Order Confirmed",
    description: "Authenticity certification generated and payment verification completed.",
    location: "ZAWER Central Verification Center",
  },
  {
    status: "Processing",
    title: "Processing & Hallmarking",
    description: "Master jewelers are conducting 24-point prong & gemstone setting inspection.",
    location: "ZAWER Diamond Studio & Vault",
  },
  {
    status: "Shipped",
    title: "Shipped & Dispatched",
    description: "Handed over to Sequel Secure Logistics in tamper-evident, GPS-tracked casing.",
    location: "High-Security Transit Hub",
  },
  {
    status: "Out for Delivery",
    title: "Out for Delivery",
    description: "Our dedicated luxury delivery executive is on the way with hand-delivery protocol.",
    location: "Local Express Delivery Hub",
  },
  {
    status: "Delivered",
    title: "Delivered",
    description: "Package successfully handed over to customer with seal inspection verified.",
    location: "Customer Destination Address",
  },
];

const AI_INSIGHTS = {
  "Order Placed": "AI Insight: Your luxury jewellery has been safely queued. Hallmarking and micro-prong setting checks will commence shortly.",
  "Placed": "AI Insight: Your luxury jewellery has been safely queued. Hallmarking and micro-prong setting checks will commence shortly.",
  "Order Confirmed": "AI Insight: Bureau of Indian Standards (BIS) hallmark and certificate of authenticity have been allocated to your piece.",
  "Processing": "AI Insight: Master artisans are completing final ultrasonic polishing and velvet presentation casing.",
  "Shipped": "AI Insight: Your shipment is travelling under 100% insured armored transit with real-time route optimization.",
  "Out for Delivery": "AI Insight: Delivery associate is within your local sector. Please keep your valid government ID ready for verification.",
  "Delivered": "AI Insight: Delivery completed. Please store in the provided anti-tarnish velvet box for lasting brilliance.",
  "Cancelled": "AI Insight: This order was cancelled. Any processed payment has been queued for immediate refund.",
};

function generateInitialTimeline(placedTime = new Date()) {
  return TRACKING_STAGES.map((stage, idx) => {
    const isCompleted = idx === 0;
    return {
      status: stage.status,
      title: stage.title,
      description: stage.description,
      location: stage.location,
      timestamp: isCompleted ? placedTime : null,
      isCompleted,
    };
  });
}

function updateTimelineForStatus(timeline, currentStatus) {
  const normalizedStatus = currentStatus === "Placed" ? "Order Placed" : currentStatus;
  const targetIndex = TRACKING_STAGES.findIndex(
    (s) => s.status.toLowerCase() === normalizedStatus.toLowerCase()
  );

  if (targetIndex === -1) return timeline;

  const now = new Date();
  return TRACKING_STAGES.map((stage, idx) => {
    const existing = Array.isArray(timeline)
      ? timeline.find((t) => t.status && t.status.toLowerCase() === stage.status.toLowerCase())
      : null;
    const isCompleted = idx <= targetIndex;
    let ts = existing?.timestamp;
    if (isCompleted && !ts) {
      ts = new Date(now.getTime() - (targetIndex - idx) * 3600 * 1000);
    }
    return {
      status: stage.status,
      title: stage.title,
      description: stage.description,
      location: stage.location,
      timestamp: isCompleted ? ts || now : null,
      isCompleted,
    };
  });
}

function escapeRegex(text) {
  if (typeof text !== "string") return "";
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

const findOrderFlexible = async (query, userId = null) => {
  if (!query) return null;
  const trimmed = query.toString().trim();

  // Try by ObjectId if valid
  if (mongoose.Types.ObjectId.isValid(trimmed)) {
    const criteria = { _id: trimmed };
    if (userId) criteria.userId = userId;
    const order = await Order.findOne(criteria);
    if (order) return order;
  }

  const safeQuery = escapeRegex(trimmed);

  // Try by exact tracking number (case-insensitive)
  const criteriaTracking = {
    trackingNumber: { $regex: new RegExp(`^${safeQuery}$`, "i") },
  };
  if (userId) criteriaTracking.userId = userId;
  const orderTracking = await Order.findOne(criteriaTracking);
  if (orderTracking) return orderTracking;

  // Fallback: If not found under user, but tracking number matches globally
  const globalTracking = await Order.findOne({
    trackingNumber: { $regex: new RegExp(`^${safeQuery}$`, "i") },
  });
  return globalTracking;
};

const placeOrder = async (req, res) => {
  try {
    const userId = req.user.id;
    const { customerName, phone, address, paymentMethod, items, couponCode } = req.body;

    if (
      !customerName ||
      !phone ||
      !address ||
      !Array.isArray(items) ||
      items.length === 0
    ) {
      return res.status(400).json({
        success: false,
        message: "Customer name, phone, address and at least one item are required",
      });
    }

    // 1. Extract product IDs and validate quantities
    const productIds = [];
    for (const item of items) {
      if (!item.productId || item.quantity == null) {
        return res.status(400).json({
          success: false,
          message: "Each item needs productId and quantity",
        });
      }
      const numQty = Number(item.quantity);
      if (isNaN(numQty) || numQty < 1) {
        return res.status(400).json({
          success: false,
          message: `Invalid quantity specified for item: ${item.productId}`,
        });
      }
      productIds.push(item.productId.toString());
    }

    // 2. Query database for products
    const validObjectIds = productIds.filter((id) => mongoose.Types.ObjectId.isValid(id));
    const dbProducts = await Product.find({
      $or: [
        { id: { $in: productIds } },
        ...(validObjectIds.length > 0 ? [{ _id: { $in: validObjectIds } }] : []),
      ],
    });

    const productMap = new Map();
    for (const p of dbProducts) {
      if (p.id) productMap.set(p.id.toString(), p);
      if (p._id) productMap.set(p._id.toString(), p);
    }

    // 3. Server-side price validation: Calculate totalAmount strictly using dbProduct.price
    let subtotal = 0;
    const verifiedItems = [];

    for (const item of items) {
      const pid = item.productId.toString();
      const dbProduct = productMap.get(pid);

      if (!dbProduct) {
        return res.status(400).json({
          success: false,
          message: `Product not found: ${item.productId}`,
        });
      }

      const numQty = Number(item.quantity);
      const itemPrice = dbProduct.price;

      if (typeof itemPrice !== "number" || isNaN(itemPrice) || itemPrice < 0) {
        return res.status(400).json({
          success: false,
          message: `Invalid price in database for product: ${item.productId}`,
        });
      }

      subtotal += itemPrice * numQty;

      verifiedItems.push({
        productId: dbProduct.id || pid,
        name: item.name || dbProduct.name || "Jewellery Item",
        image: item.image || (dbProduct.images && dbProduct.images[0]) || "",
        price: itemPrice,
        quantity: numQty,
      });
    }

    // 4. Strict coupon validation
    let finalDiscount = 0;
    let appliedCoupon = "";
    let appliedOfferId = null;

    if (couponCode && typeof couponCode === "string" && couponCode.trim() !== "") {
      const code = couponCode.trim().toUpperCase();
      const offer = await Offer.findOne({ code });

      if (!offer) {
        return res.status(400).json({
          success: false,
          message: `Coupon code '${code}' not found in the directory`,
        });
      }

      if (!offer.isActive) {
        return res.status(400).json({
          success: false,
          message: `Coupon code '${code}' is no longer active`,
        });
      }

      const now = new Date();

      if (offer.isExpired() || now > offer.expiryDate) {
        return res.status(400).json({
          success: false,
          isExpired: true,
          message: `Coupon code '${code}' has expired`,
        });
      }

      if (now < offer.startDate) {
        return res.status(400).json({
          success: false,
          message: `Coupon code '${code}' is not active yet`,
        });
      }

      if (offer.usageLimit > 0 && offer.usedCount >= offer.usageLimit) {
        return res.status(400).json({
          success: false,
          message: `Coupon code '${code}' has reached its maximum client usage limit`,
        });
      }

      if (subtotal < offer.minOrderAmount) {
        return res.status(400).json({
          success: false,
          minOrderAmount: offer.minOrderAmount,
          message: `Minimum vault order valuation of ₹${offer.minOrderAmount.toLocaleString()} is required for code '${code}'`,
        });
      }

      if (
        offer.applicableCategory &&
        offer.applicableCategory.toLowerCase() !== "all"
      ) {
        const matchesCategory = items.some((item) => {
          const dbProduct = productMap.get(item.productId.toString());
          const cat = (dbProduct && dbProduct.category) || item.category;
          return (
            cat &&
            cat.toLowerCase() === offer.applicableCategory.toLowerCase()
          );
        });

        if (!matchesCategory) {
          return res.status(400).json({
            success: false,
            applicableCategory: offer.applicableCategory,
            message: `Coupon code '${code}' is only applicable to ${offer.applicableCategory} collections`,
          });
        }
      }

      finalDiscount = offer.calculateDiscount(subtotal);
      appliedCoupon = code;
      appliedOfferId = offer._id;
    }

    const totalAmount = Math.max(0, subtotal - finalDiscount);

    const placedDate = new Date();
    const trackingNumber = "ZWR-" + Math.floor(100000 + Math.random() * 900000);
    const initialTimeline = generateInitialTimeline(placedDate);

    const order = await Order.create({
      userId,
      customerName,
      phone,
      address,
      paymentMethod: paymentMethod || "Cash on Delivery",
      items: verifiedItems,
      subtotal,
      discountAmount: finalDiscount,
      couponCode: appliedCoupon,
      totalAmount,
      status: "Order Placed",
      trackingNumber,
      courierPartner: "Sequel Secure Luxury Logistics",
      currentLocation: "ZAWER Central Vault Hub, Mumbai",
      estimatedDelivery: new Date(Date.now() + 4 * 24 * 60 * 60 * 1000),
      aiDeliveryInsight: AI_INSIGHTS["Order Placed"],
      timeline: initialTimeline,
    });

    // 5. Increment coupon usage count after order is confirmed created
    if (appliedOfferId) {
      await Offer.updateOne({ _id: appliedOfferId }, { $inc: { usedCount: 1 } });
    }

    // 6. Clear cart upon successful order creation
    await Cart.findOneAndUpdate({ userId }, { $set: { items: [] } });

    return res.status(201).json({
      success: true,
      message: "Order placed successfully",
      order,
    });
  } catch (error) {
    console.error("Place Order Error:", error);
    return res.status(500).json({
      success: false,
      message: "Failed to place order",
      error: error.message,
    });
  }
};

const getMyOrders = async (req, res) => {
  try {
    const userId = req.user.id;

    const rawOrders = await Order.find({ userId }).sort({
      createdAt: -1,
    });

    const orders = rawOrders.map((order) => {
      const orderObj = order.toObject();
      if (!orderObj.timeline || orderObj.timeline.length === 0) {
        orderObj.timeline = updateTimelineForStatus([], orderObj.status || "Order Placed");
      }
      if (!orderObj.trackingNumber) {
        orderObj.trackingNumber = "ZWR-" + orderObj._id.toString().slice(-6).toUpperCase();
      }
      if (!orderObj.courierPartner) {
        orderObj.courierPartner = "Sequel Secure Luxury Logistics";
      }
      if (!orderObj.aiDeliveryInsight) {
        orderObj.aiDeliveryInsight = AI_INSIGHTS[orderObj.status] || AI_INSIGHTS["Order Placed"];
      }
      return orderObj;
    });

    return res.status(200).json({
      success: true,
      count: orders.length,
      orders,
    });
  } catch (error) {
    return res.status(500).json({
      success: false,
      message: "Failed to fetch orders",
      error: error.message,
    });
  }
};

const getOrderById = async (req, res) => {
  try {
    const orderId = req.params.id;
    const userId = req.user ? req.user.id : null;

    const order = await findOrderFlexible(orderId, userId);

    if (!order) {
      return res.status(404).json({
        success: false,
        message: "Order not found",
      });
    }

    const orderObj = order.toObject();
    if (!orderObj.timeline || orderObj.timeline.length === 0) {
      orderObj.timeline = updateTimelineForStatus([], orderObj.status || "Order Placed");
    }
    if (!orderObj.trackingNumber) {
      orderObj.trackingNumber = "ZWR-" + orderObj._id.toString().slice(-6).toUpperCase();
    }
    if (!orderObj.courierPartner) {
      orderObj.courierPartner = "Sequel Secure Luxury Logistics";
    }
    if (!orderObj.aiDeliveryInsight) {
      orderObj.aiDeliveryInsight = AI_INSIGHTS[orderObj.status] || AI_INSIGHTS["Order Placed"];
    }

    return res.status(200).json({
      success: true,
      order: orderObj,
    });
  } catch (error) {
    return res.status(500).json({
      success: false,
      message: "Failed to fetch order",
      error: error.message,
    });
  }
};

const getOrderTracking = async (req, res) => {
  try {
    const query = req.params.id || req.params.query;
    const userId = req.user ? req.user.id : null;

    const order = await findOrderFlexible(query, userId);

    if (!order) {
      return res.status(404).json({
        success: false,
        message: "Order not found for tracking",
      });
    }

    let timeline = order.timeline && order.timeline.length > 0
      ? order.timeline
      : updateTimelineForStatus([], order.status);

    timeline = updateTimelineForStatus(timeline, order.status);

    const trackingData = {
      orderId: order._id,
      trackingNumber: order.trackingNumber || ("ZWR-" + order._id.toString().slice(-6).toUpperCase()),
      currentStatus: order.status === "Placed" ? "Order Placed" : order.status,
      courierPartner: order.courierPartner || "Sequel Secure Luxury Logistics",
      currentLocation: order.currentLocation || "In Transit via Armored Vehicle",
      estimatedDelivery: order.estimatedDelivery || new Date(Date.now() + 4 * 24 * 60 * 60 * 1000),
      aiDeliveryInsight: AI_INSIGHTS[order.status] || AI_INSIGHTS["Order Placed"],
      customerName: order.customerName,
      address: order.address,
      phone: order.phone,
      totalAmount: order.totalAmount,
      items: order.items,
      createdAt: order.createdAt,
      timeline,
    };

    return res.status(200).json({
      success: true,
      tracking: trackingData,
    });
  } catch (error) {
    return res.status(500).json({
      success: false,
      message: "Failed to fetch order tracking",
      error: error.message,
    });
  }
};

const updateOrderStatus = async (req, res) => {
  try {
    if (req.user && req.user.role && req.user.role !== "admin") {
      return res.status(403).json({
        success: false,
        message: "Only administrators can update order status",
      });
    }

    const orderId = req.params.id;
    const { status } = req.body;

    const validStatuses = [
      "Order Placed",
      "Order Confirmed",
      "Processing",
      "Shipped",
      "Out for Delivery",
      "Delivered",
      "Cancelled",
    ];

    if (!status || !validStatuses.includes(status)) {
      return res.status(400).json({
        success: false,
        message: `Status must be one of: ${validStatuses.join(", ")}`,
      });
    }

    const order = await findOrderFlexible(orderId);

    if (!order) {
      return res.status(404).json({
        success: false,
        message: "Order not found",
      });
    }

    order.status = status;
    order.timeline = updateTimelineForStatus(order.timeline || [], status);
    order.aiDeliveryInsight = AI_INSIGHTS[status] || order.aiDeliveryInsight;

    if (status === "Order Placed") {
      order.currentLocation = "ZAWER Central Vault Hub, Mumbai";
    } else if (status === "Order Confirmed") {
      order.currentLocation = "ZAWER Central Verification Center";
    } else if (status === "Processing") {
      order.currentLocation = "ZAWER Diamond Studio & Vault";
    } else if (status === "Shipped") {
      order.currentLocation = "In Transit - Sequel Armored Division";
    } else if (status === "Out for Delivery") {
      order.currentLocation = "Local Delivery Hub, " + (order.address ? order.address.split(",").slice(-2).join(",").trim() : "Sector Hub");
    } else if (status === "Delivered") {
      order.currentLocation = order.address || "Delivered to Customer";
    } else if (status === "Cancelled") {
      order.currentLocation = "Order Cancelled - Refund Initiated";
    }

    await order.save();

    return res.status(200).json({
      success: true,
      message: `Order status updated to ${status}`,
      order,
    });
  } catch (error) {
    return res.status(500).json({
      success: false,
      message: "Failed to update order status",
      error: error.message,
    });
  }
};

module.exports = {
  placeOrder,
  getMyOrders,
  getOrderById,
  getOrderTracking,
  updateOrderStatus,
  findOrderFlexible,
};
