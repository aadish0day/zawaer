const mongoose = require("mongoose");
const Order = require("../models/Order");
const Product = require("../models/Product");
const Cart = require("../models/Cart");
const Offer = require("../models/Offer");
const { PHONE_RE } = require("./authController");

const round2 = (x) => Math.round(x * 100) / 100;
const IDEMPOTENCY_WINDOW_MS = 24 * 60 * 60 * 1000;

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

  if (targetIndex === -1) {
    // Cancelled sits outside the 6-stage journey: append it once as a final step
    if (
      normalizedStatus.toLowerCase() !== "cancelled" ||
      (Array.isArray(timeline) && timeline.some((t) => t.status === "Cancelled"))
    ) {
      return timeline;
    }
    return [
      ...(Array.isArray(timeline) ? timeline : []),
      {
        status: "Cancelled",
        title: "Order Cancelled",
        description: "This order was cancelled and any processed payment has been queued for refund.",
        location: "Order Cancelled - Refund Initiated",
        timestamp: new Date(),
        isCompleted: true,
      },
    ];
  }

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

// Orders created before trackingNumber was stored show a number derived from their _id.
const derivedTrackingNumber = (id) => "ZWR-" + id.toString().slice(-6).toUpperCase();

// Lookups are always scoped to userId; only admin callers may pass { allUsers: true }.
const findOrderFlexible = async (query, userId, { allUsers = false } = {}) => {
  if (!query) return null;
  if (!userId && !allUsers) return null;
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
  const order = await Order.findOne(criteriaTracking);
  if (order) return order;

  // Legacy orders without a stored trackingNumber: match the _id suffix the API displays.
  // ponytail: $expr scan over orders lacking a trackingNumber (cheap per user, a full scan for
  // admins); backfill trackingNumber on old orders if that ever gets slow.
  const legacy = /^ZWR-([0-9a-f]{6})$/i.exec(trimmed);
  if (!legacy) return null;
  const criteriaLegacy = {
    trackingNumber: { $in: [null, ""] },
    $expr: {
      $eq: [{ $substrCP: [{ $toString: "$_id" }, 18, 6] }, legacy[1].toLowerCase()],
    },
  };
  if (userId) criteriaLegacy.userId = userId;
  return Order.findOne(criteriaLegacy);
};

const MAX_ITEM_QUANTITY = 10;
const MAX_ORDER_LINES = 50;

const isValidQuantity = (qty) =>
  Number.isInteger(qty) && qty >= 1 && qty <= MAX_ITEM_QUANTITY;

// Prices client items strictly from the DB. Returns { error } or
// { subtotal, verifiedItems, lines: [{ category, price, quantity }], orderedIds }.
async function priceItems(items) {
  if (items.length > MAX_ORDER_LINES) {
    return { error: `An order can contain at most ${MAX_ORDER_LINES} items` };
  }
  const productIds = [];
  for (const item of items) {
    if (
      !item ||
      !["string", "number"].includes(typeof item.productId) ||
      !item.productId ||
      item.quantity == null
    ) {
      return { error: "Each item needs productId and quantity" };
    }
    if (!isValidQuantity(Number(item.quantity))) {
      return {
        error: `Quantity must be a whole number between 1 and ${MAX_ITEM_QUANTITY} for item: ${item.productId}`,
      };
    }
    productIds.push(item.productId.toString());
  }

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

  let subtotal = 0;
  const verifiedItems = [];
  const lines = [];
  const orderedIds = new Set();

  // Merge lines naming the same product (by custom id or _id) before pricing and capping
  const merged = new Map();
  for (const item of items) {
    const pid = item.productId.toString();
    const dbProduct = productMap.get(pid);

    if (!dbProduct) {
      return { error: `Product not found: ${item.productId}` };
    }

    const key = dbProduct._id.toString();
    const line = merged.get(key) || { dbProduct, pid, quantity: 0 };
    line.quantity += Number(item.quantity);
    merged.set(key, line);
    orderedIds.add(pid);
  }

  for (const { dbProduct, pid, quantity: numQty } of merged.values()) {
    if (numQty > MAX_ITEM_QUANTITY) {
      return {
        error: `Total quantity cannot exceed ${MAX_ITEM_QUANTITY} for item: ${dbProduct.id || pid}`,
      };
    }

    const itemPrice = dbProduct.price;

    if (typeof itemPrice !== "number" || isNaN(itemPrice) || itemPrice < 0) {
      return { error: `Invalid price in database for product: ${dbProduct.id || pid}` };
    }

    subtotal += itemPrice * numQty;

    verifiedItems.push({
      productId: dbProduct.id || pid,
      name: dbProduct.name || "Jewellery Item",
      image: (dbProduct.images && dbProduct.images[0]) || "",
      price: itemPrice,
      quantity: numQty,
    });
    lines.push({ category: dbProduct.category, price: itemPrice, quantity: numQty });

    if (dbProduct.id) orderedIds.add(dbProduct.id.toString());
    orderedIds.add(dbProduct._id.toString());
  }

  return { subtotal, verifiedItems, lines, orderedIds: [...orderedIds] };
}

const isAllCategories = (category) =>
  typeof category !== "string" || category.trim() === "" || category.trim().toLowerCase() === "all";

// Sum of price * qty over lines whose DB category matches the offer's category.
function eligibleSubtotalFor(offer, lines) {
  if (isAllCategories(offer.applicableCategory)) {
    return lines.reduce((sum, l) => sum + l.price * l.quantity, 0);
  }
  const target = offer.applicableCategory.trim().toLowerCase();
  return lines.reduce(
    (sum, l) =>
      typeof l.category === "string" && l.category.trim().toLowerCase() === target
        ? sum + l.price * l.quantity
        : sum,
    0
  );
}

const newTrackingNumber = () => "ZWR-" + Math.floor(100000 + Math.random() * 900000);

const releaseCoupon = (offerId) =>
  Offer.updateOne({ _id: offerId, usedCount: { $gt: 0 } }, { $inc: { usedCount: -1 } });

const placeOrder = async (req, res) => {
  try {
    const userId = req.user.id;
    const { items, couponCode, idempotencyKey, fromCart } = req.body;

    if (!Array.isArray(items) || items.length === 0) {
      return res.status(400).json({
        success: false,
        message: "Customer name, phone, address and at least one item are required",
      });
    }

    // Contact fields must be non-empty strings; paymentMethod defaults when omitted
    const contact = {};
    for (const [field, max] of [["customerName", 100], ["phone", 20], ["address", 500], ["paymentMethod", 30]]) {
      const value = field === "paymentMethod" && req.body[field] == null ? "Cash on Delivery" : req.body[field];
      if (typeof value !== "string" || !value.trim() || value.trim().length > max) {
        return res.status(400).json({
          success: false,
          message: `${field} must be a non-empty string of at most ${max} characters`,
        });
      }
      contact[field] = value.trim();
    }
    if (!PHONE_RE.test(contact.phone)) {
      return res.status(400).json({ success: false, message: "Please enter a valid phone number" });
    }

    if (couponCode != null && typeof couponCode !== "string") {
      return res.status(400).json({ success: false, message: "couponCode must be a string" });
    }

    if (fromCart != null && typeof fromCart !== "boolean") {
      return res.status(400).json({ success: false, message: "fromCart must be a boolean" });
    }

    if (
      idempotencyKey != null &&
      (typeof idempotencyKey !== "string" || !idempotencyKey.trim() || idempotencyKey.length > 64)
    ) {
      return res.status(400).json({
        success: false,
        message: "idempotencyKey must be a non-empty string of at most 64 characters",
      });
    }

    // Replays an order already created for this key, if it is recent enough. The unique
    // index keeps an old key from ever being reused, so the client must regenerate it.
    const replay = (existing) =>
      Date.now() - new Date(existing.createdAt).getTime() <= IDEMPOTENCY_WINDOW_MS
        ? res.status(200).json({ success: true, message: "Order placed successfully", order: existing })
        : res.status(409).json({
            success: false,
            idempotencyConflict: true,
            message: "This checkout session has expired. Please try again.",
          });

    // 0. Retried checkout: return the order already created for this key
    if (idempotencyKey) {
      const existing = await Order.findOne({ userId, idempotencyKey });
      if (existing) return replay(existing);
    }

    // 1-3. Validate quantities and price every item strictly from the DB
    const priced = await priceItems(items);
    if (priced.error) {
      return res.status(400).json({
        success: false,
        message: priced.error,
      });
    }
    const { verifiedItems, lines, orderedIds } = priced;
    const subtotal = round2(priced.subtotal);

    // 4. Strict coupon validation
    let finalDiscount = 0;
    let appliedCoupon = "";
    let appliedOfferId = null;

    if (couponCode && couponCode.trim() !== "") {
      const code = couponCode.trim().toUpperCase();
      const offer = await Offer.findOne({ code });

      if (!offer) {
        return res.status(400).json({
          success: false,
          couponError: true,
          message: `Coupon code '${code}' not found in the directory`,
        });
      }

      if (!offer.isActive) {
        return res.status(400).json({
          success: false,
          couponError: true,
          message: `Coupon code '${code}' is no longer active`,
        });
      }

      const now = new Date();

      // Missing expiryDate = no expiry (same as validate-coupon and the offers list)
      if (offer.isExpired()) {
        return res.status(400).json({
          success: false,
          couponError: true,
          isExpired: true,
          message: `Coupon code '${code}' has expired`,
        });
      }

      if (now < offer.startDate) {
        return res.status(400).json({
          success: false,
          couponError: true,
          message: `Coupon code '${code}' is not active yet`,
        });
      }

      if (offer.usageLimit > 0 && offer.usedCount >= offer.usageLimit) {
        return res.status(400).json({
          success: false,
          couponError: true,
          message: `Coupon code '${code}' has reached its maximum client usage limit`,
        });
      }

      // ponytail: count-then-create, so two simultaneous orders by the same user can both pass;
      // move to a per-user redemption collection with a unique index if that matters.
      if (offer.perUserLimit > 0) {
        const userUses = await Order.countDocuments({
          userId,
          couponCode: code,
          status: { $ne: "Cancelled" },
        });
        if (userUses >= offer.perUserLimit) {
          return res.status(400).json({
            success: false,
            couponError: true,
            message: `Coupon code '${code}' has already been used on your account`,
          });
        }
      }

      // Category coupons only discount the matching items (DB category, not client)
      const eligibleSubtotal = eligibleSubtotalFor(offer, lines);

      if (!isAllCategories(offer.applicableCategory) && eligibleSubtotal <= 0) {
        return res.status(400).json({
          success: false,
          couponError: true,
          applicableCategory: offer.applicableCategory,
          message: `Coupon code '${code}' is only applicable to ${offer.applicableCategory} collections`,
        });
      }

      if (eligibleSubtotal < offer.minOrderAmount) {
        return res.status(400).json({
          success: false,
          couponError: true,
          minOrderAmount: offer.minOrderAmount,
          message: `Minimum vault order valuation of ₹${offer.minOrderAmount.toLocaleString()} is required for code '${code}'`,
        });
      }

      // Reserve one use atomically so concurrent orders cannot exceed usageLimit
      const reserved = await Offer.findOneAndUpdate(
        {
          _id: offer._id,
          $or: [
            { usageLimit: null },
            { usageLimit: { $lte: 0 } },
            { $expr: { $lt: ["$usedCount", "$usageLimit"] } },
          ],
        },
        { $inc: { usedCount: 1 } }
      );

      if (!reserved) {
        return res.status(400).json({
          success: false,
          couponError: true,
          message: `Coupon code '${code}' has reached its maximum client usage limit`,
        });
      }

      finalDiscount = round2(offer.calculateDiscount(eligibleSubtotal));
      appliedCoupon = code;
      appliedOfferId = offer._id;
    }

    const totalAmount = round2(Math.max(0, subtotal - finalDiscount));

    const placedDate = new Date();
    const initialTimeline = generateInitialTimeline(placedDate);

    const orderData = {
      userId,
      ...contact,
      items: verifiedItems,
      subtotal,
      discountAmount: finalDiscount,
      couponCode: appliedCoupon,
      totalAmount,
      status: "Order Placed",
      courierPartner: "Sequel Secure Luxury Logistics",
      currentLocation: "ZAWER Central Vault Hub, Mumbai",
      estimatedDelivery: new Date(Date.now() + 4 * 24 * 60 * 60 * 1000),
      aiDeliveryInsight: AI_INSIGHTS["Order Placed"],
      timeline: initialTimeline,
    };
    if (idempotencyKey) orderData.idempotencyKey = idempotencyKey;
    if (appliedOfferId) orderData.couponOfferId = appliedOfferId;

    // 5. Create the order, retrying on tracking number collisions;
    //    release the coupon reservation if it cannot be created.
    let order = null;
    try {
      for (let attempt = 0; !order; attempt++) {
        try {
          order = await Order.create({ ...orderData, trackingNumber: newTrackingNumber() });
        } catch (err) {
          const trackingClash = err.code === 11000 && err.keyPattern && err.keyPattern.trackingNumber;
          if (!trackingClash || attempt >= 4) throw err;
        }
      }
    } catch (err) {
      if (appliedOfferId) await releaseCoupon(appliedOfferId);
      if (idempotencyKey && err.code === 11000 && err.keyPattern && err.keyPattern.idempotencyKey) {
        const existing = await Order.findOne({ userId, idempotencyKey });
        if (existing) return replay(existing);
      }
      throw err;
    }

    // 6. Cart checkout: remove only the ordered products. Buy Now (fromCart: false) leaves the cart alone.
    if (fromCart !== false) {
      try {
        await Cart.updateOne({ userId }, { $pull: { items: { productId: { $in: orderedIds } } } });
      } catch (cartError) {
        console.error("Cart cleanup after order failed:", cartError.message);
      }
    }

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
        orderObj.trackingNumber = derivedTrackingNumber(orderObj._id);
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
    console.error("Get Orders Error:", error);
    return res.status(500).json({
      success: false,
      message: "Failed to fetch orders",
    });
  }
};

const getOrderById = async (req, res) => {
  try {
    const orderId = req.params.id;
    const userId = req.user && req.user.id;
    const isAdmin = Boolean(req.user && req.user.role === "admin");

    const order = await findOrderFlexible(orderId, isAdmin ? null : userId, { allUsers: isAdmin });

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
      orderObj.trackingNumber = derivedTrackingNumber(orderObj._id);
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
    console.error("Get Order Error:", error);
    return res.status(500).json({
      success: false,
      message: "Failed to fetch order",
    });
  }
};

const getOrderTracking = async (req, res) => {
  try {
    const query = req.params.id || req.params.query;
    const userId = req.user && req.user.id;
    const isAdmin = Boolean(req.user && req.user.role === "admin");

    const order = await findOrderFlexible(query, isAdmin ? null : userId, { allUsers: isAdmin });

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
      trackingNumber: order.trackingNumber || derivedTrackingNumber(order._id),
      currentStatus: order.status === "Placed" ? "Order Placed" : order.status,
      courierPartner: order.courierPartner || "Sequel Secure Luxury Logistics",
      currentLocation: order.currentLocation || "In Transit via Armored Vehicle",
      estimatedDelivery:
        order.estimatedDelivery ||
        (order.createdAt ? new Date(new Date(order.createdAt).getTime() + 4 * 24 * 60 * 60 * 1000) : null),
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
    console.error("Order Tracking Error:", error);
    return res.status(500).json({
      success: false,
      message: "Failed to fetch order tracking",
    });
  }
};

const TERMINAL_STATUSES = ["Delivered", "Cancelled"];

const updateOrderStatus = async (req, res) => {
  try {
    if (!req.user || req.user.role !== "admin") {
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

    const order = await findOrderFlexible(orderId, null, { allUsers: true });

    if (!order) {
      return res.status(404).json({
        success: false,
        message: "Order not found",
      });
    }

    const previousStatus = order.status;
    // Retried PUT whose first attempt already applied: report success, change nothing
    if (status === previousStatus) {
      return res.status(200).json({
        success: true,
        message: `Order status is already ${status}`,
        order,
      });
    }

    if (TERMINAL_STATUSES.includes(previousStatus)) {
      return res.status(400).json({
        success: false,
        message: `Order is already ${previousStatus} and can no longer be updated`,
      });
    }

    // Stages only move forward; Cancelled is allowed from any non-terminal stage
    if (
      status !== "Cancelled" &&
      validStatuses.indexOf(status) <= validStatuses.indexOf(previousStatus)
    ) {
      return res.status(400).json({
        success: false,
        message: `Cannot move order from ${previousStatus} to ${status}`,
      });
    }

    let currentLocation = order.currentLocation;
    if (status === "Order Placed") {
      currentLocation = "ZAWER Central Vault Hub, Mumbai";
    } else if (status === "Order Confirmed") {
      currentLocation = "ZAWER Central Verification Center";
    } else if (status === "Processing") {
      currentLocation = "ZAWER Diamond Studio & Vault";
    } else if (status === "Shipped") {
      currentLocation = "In Transit - Sequel Armored Division";
    } else if (status === "Out for Delivery") {
      currentLocation = "Local Delivery Hub, " + (order.address ? order.address.split(",").slice(-2).join(",").trim() : "Sector Hub");
    } else if (status === "Delivered") {
      currentLocation = order.address || "Delivered to Customer";
    } else if (status === "Cancelled") {
      currentLocation = "Order Cancelled - Refund Initiated";
    }

    // Conditional on the status we read, so two concurrent updates cannot both apply
    // (and a cancellation cannot release the coupon twice).
    const updated = await Order.findOneAndUpdate(
      { _id: order._id, status: previousStatus },
      {
        $set: {
          status,
          timeline: updateTimelineForStatus(order.toObject().timeline || [], status),
          aiDeliveryInsight: AI_INSIGHTS[status] || order.aiDeliveryInsight,
          currentLocation,
        },
      },
      { returnDocument: "after", runValidators: true }
    );

    if (!updated) {
      return res.status(409).json({
        success: false,
        message: "Order status changed concurrently, please retry",
      });
    }

    if (status === "Cancelled" && (updated.couponOfferId || updated.couponCode)) {
      // Release by offer id; orders placed before couponOfferId existed fall back to the code.
      const offerFilter = updated.couponOfferId
        ? { _id: updated.couponOfferId }
        : { code: updated.couponCode };
      try {
        await Offer.updateOne({ ...offerFilter, usedCount: { $gt: 0 } }, { $inc: { usedCount: -1 } });
      } catch (releaseError) {
        // The cancel is already saved, so don't fail the request.
        // ponytail: usedCount stays one too high here; a reconciliation job recounting
        // non-cancelled orders per offer could fix the counts.
        console.error("Coupon release after cancel failed:", updated._id.toString(), releaseError.message);
      }
    }

    return res.status(200).json({
      success: true,
      message: `Order status updated to ${status}`,
      order: updated,
    });
  } catch (error) {
    console.error("Update Order Status Error:", error);
    return res.status(500).json({
      success: false,
      message: "Failed to update order status",
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
  priceItems,
  eligibleSubtotalFor,
  isAllCategories,
  round2,
  MAX_ITEM_QUANTITY,
  MAX_ORDER_LINES,
};
