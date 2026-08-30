const Order = require("../models/Order");

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
    title: "Artisan Quality & Hallmarking",
    description: "Master jewelers are conducting 24-point prong & gemstone setting inspection.",
    location: "ZAWER Diamond Studio & Vault",
  },
  {
    status: "Shipped",
    title: "Dispatched via Armored Transit",
    description: "Handed over to Sequel Secure Logistics in tamper-evident, GPS-tracked casing.",
    location: "High-Security Transit Hub",
  },
  {
    status: "Out for Delivery",
    title: "Out for Luxury Delivery",
    description: "Our dedicated luxury delivery executive is on the way with hand-delivery protocol.",
    location: "Local Express Delivery Hub",
  },
  {
    status: "Delivered",
    title: "Delivered to Customer",
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
    const existing = timeline.find((t) => t.status.toLowerCase() === stage.status.toLowerCase());
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

const placeOrder = async (req, res) => {
  try {
    const userId = req.user.id;
    const { customerName, phone, address, paymentMethod, items } = req.body;

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

    let totalAmount = 0;

    for (const item of items) {
      if (!item.productId || !item.name || !item.price || !item.quantity) {
        return res.status(400).json({
          success: false,
          message: "Each item needs productId, name, price and quantity",
        });
      }
      totalAmount += Number(item.price) * Number(item.quantity);
    }

    const placedDate = new Date();
    const trackingNumber = "ZWR-" + Math.floor(100000 + Math.random() * 900000);
    const initialTimeline = generateInitialTimeline(placedDate);

    const order = await Order.create({
      userId,
      customerName,
      phone,
      address,
      paymentMethod: paymentMethod || "Cash on Delivery",
      items,
      totalAmount,
      status: "Order Placed",
      trackingNumber,
      courierPartner: "Sequel Secure Luxury Logistics",
      currentLocation: "ZAWER Central Vault Hub, Mumbai",
      estimatedDelivery: new Date(Date.now() + 4 * 24 * 60 * 60 * 1000),
      aiDeliveryInsight: AI_INSIGHTS["Order Placed"],
      timeline: initialTimeline,
    });

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

    // Ensure backwards compatibility for legacy orders without timeline
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
    const userId = req.user.id;

    const order = await Order.findOne({
      _id: orderId,
      userId,
    });

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
    const orderId = req.params.id;
    const userId = req.user.id;

    const order = await Order.findOne({
      _id: orderId,
      userId,
    });

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

    const order = await Order.findById(orderId);

    if (!order) {
      return res.status(404).json({
        success: false,
        message: "Order not found",
      });
    }

    order.status = status;
    order.timeline = updateTimelineForStatus(order.timeline || [], status);
    order.aiDeliveryInsight = AI_INSIGHTS[status] || order.aiDeliveryInsight;

    if (status === "Order Confirmed") {
      order.currentLocation = "ZAWER Central Verification Center";
    } else if (status === "Processing") {
      order.currentLocation = "ZAWER Diamond Studio & Vault";
    } else if (status === "Shipped") {
      order.currentLocation = "In Transit - Sequel Armored Division";
    } else if (status === "Out for Delivery") {
      order.currentLocation = "Local Delivery Hub, " + order.address.split(",").slice(-2).join(",").trim();
    } else if (status === "Delivered") {
      order.currentLocation = order.address;
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
};
