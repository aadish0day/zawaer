require("dotenv").config();
const mongoose = require("mongoose");
const Order = require("./models/Order");
const {
  placeOrder,
  getMyOrders,
  getOrderById,
  getOrderTracking,
  updateOrderStatus,
  findOrderFlexible,
} = require("./controllers/orderController");

async function runTests() {
  console.log("=================================================");
  console.log("🚀 STARTING ORDER TRACKING CORE & LOGIC TESTS");
  console.log("=================================================\n");

  let passed = 0;
  let failed = 0;

  function assert(condition, message) {
    if (condition) {
      console.log(`  ✅ PASS: ${message}`);
      passed++;
    } else {
      console.error(`  ❌ FAIL: ${message}`);
      failed++;
    }
  }

  // -------------------------------------------------------------
  // TEST 1: Schema Default Values & Validation
  // -------------------------------------------------------------
  console.log("🧪 TEST SUITE 1: Schema Defaults & Data Integrity");
  
  const testOrderDoc = new Order({
    userId: "user_test_123",
    customerName: "Aadish Test",
    phone: "+91 9876543210",
    address: "101 Luxury Heights, Mumbai, Maharashtra 400001",
    paymentMethod: "Cash on Delivery",
    totalAmount: 185000,
    items: [
      {
        productId: "prod_ring_01",
        name: "Solitaire Diamond Ring",
        image: "assets/images/ring1.png",
        price: 185000,
        quantity: 1,
      },
    ],
  });

  assert(testOrderDoc.status === "Order Placed", "Default status is 'Order Placed'");
  assert(
    testOrderDoc.trackingNumber && testOrderDoc.trackingNumber.startsWith("ZWR-"),
    `Tracking number generated properly: ${testOrderDoc.trackingNumber}`
  );
  assert(
    testOrderDoc.courierPartner === "Sequel Secure Luxury Logistics",
    `Default courier partner set to: ${testOrderDoc.courierPartner}`
  );
  assert(
    testOrderDoc.currentLocation === "Mumbai Central Vault Hub",
    `Default location set to: ${testOrderDoc.currentLocation}`
  );
  assert(
    testOrderDoc.estimatedDelivery instanceof Date,
    `Estimated delivery is valid date: ${testOrderDoc.estimatedDelivery}`
  );

  // -------------------------------------------------------------
  // TEST 2: Controller Timeline & Status Progression Logic
  // -------------------------------------------------------------
  console.log("\n🧪 TEST SUITE 2: All 6 Tracking Stages Lifecycle");

  const STAGES = [
    "Order Placed",
    "Order Confirmed",
    "Processing",
    "Shipped",
    "Out for Delivery",
    "Delivered",
  ];

  // Test placeOrder controller simulation
  const reqPlace = {
    user: { id: "user_test_999" },
    body: {
      customerName: "Priya Sharma",
      phone: "+91 9988776655",
      address: "Villa 42, Palm Avenue, Bandra West, Mumbai 400050",
      paymentMethod: "UPI",
      items: [
        {
          productId: "prod_necklace_01",
          name: "24K Royal Polki Necklace",
          image: "assets/images/necklace1.jpg",
          price: 320000,
          quantity: 1,
        },
      ],
    },
  };

  let placedOrderData = null;
  const resPlace = {
    status: function (code) {
      this.statusCode = code;
      return this;
    },
    json: function (data) {
      placedOrderData = data;
      return this;
    },
  };

  // Mock Order.create in controller or connect to DB if available
  let dbConnected = false;
  try {
    if (process.env.MONGO_URI) {
      await mongoose.connect(process.env.MONGO_URI, { serverSelectionTimeoutMS: 5000 });
      dbConnected = true;
      console.log("  📦 MongoDB Atlas connection established for live testing.");
    }
  } catch (err) {
    console.warn("  ⚠️ MongoDB Atlas connection skipped (offline mode):", err.message);
  }

  if (dbConnected) {
    // Clean up any previous test orders
    await Order.deleteMany({ userId: "user_test_999" });

    await placeOrder(reqPlace, resPlace);

    assert(
      resPlace.statusCode === 201 && placedOrderData && placedOrderData.success,
      "Order placed successfully via API"
    );

    const order = placedOrderData.order;
    assert(order.status === "Order Placed", "Initial stage is 'Order Placed'");
    assert(order.timeline.length === 6, `Timeline initialized with all 6 stages (found ${order.timeline.length})`);
    assert(order.timeline[0].isCompleted === true, "Stage 1 (Order Placed) is marked completed");
    assert(order.timeline[1].isCompleted === false, "Stage 2 (Order Confirmed) is pending");

    // Test advancing through all 6 stages sequentially
    console.log("\n🧪 TEST SUITE 3: Sequential Stage Advancement & Timestamps");

    for (let i = 1; i < STAGES.length; i++) {
      const nextStage = STAGES[i];
      const reqUpdate = {
        params: { id: order._id.toString() },
        body: { status: nextStage },
      };
      let updateResData = null;
      const resUpdate = {
        status: function (code) {
          this.statusCode = code;
          return this;
        },
        json: function (data) {
          updateResData = data;
          return this;
        },
      };

      await updateOrderStatus(reqUpdate, resUpdate);

      assert(
        resUpdate.statusCode === 200 && updateResData.success,
        `Successfully advanced to stage ${i + 1}: '${nextStage}'`
      );

      const updatedOrder = updateResData.order;
      assert(updatedOrder.status === nextStage, `Order status is correctly '${nextStage}'`);
      
      // Check that all stages up to i are completed
      const allPriorCompleted = updatedOrder.timeline.slice(0, i + 1).every((s) => s.isCompleted === true);
      const remainingPending = updatedOrder.timeline.slice(i + 1).every((s) => s.isCompleted === false);

      assert(allPriorCompleted, `Stages 1 to ${i + 1} marked completed`);
      assert(remainingPending, `Stages > ${i + 1} marked pending`);
    }

    // -------------------------------------------------------------
    // TEST 4: Tracking Lookup by Tracking Number & Order ID
    // -------------------------------------------------------------
    console.log("\n🧪 TEST SUITE 4: Multi-Query Flexible Tracking Lookup");

    // Lookup by Order ID
    const reqTrackById = {
      params: { id: order._id.toString() },
      user: { id: "user_test_999" },
    };
    let trackByIdData = null;
    const resTrackById = {
      status: (c) => ({ statusCode: c, json: (d) => (trackByIdData = d) }),
      json: (d) => (trackByIdData = d),
    };
    await getOrderTracking(reqTrackById, resTrackById);
    assert(
      trackByIdData && trackByIdData.success && trackByIdData.tracking.currentStatus === "Delivered",
      `Lookup by MongoDB ObjectId succeeded (Status: ${trackByIdData?.tracking?.currentStatus})`
    );

    // Lookup by Tracking Number (e.g. ZWR-XXXXXX)
    const reqTrackByNumber = {
      params: { id: order.trackingNumber },
      user: { id: "user_test_999" },
    };
    let trackByNumData = null;
    const resTrackByNum = {
      status: (c) => ({ statusCode: c, json: (d) => (trackByNumData = d) }),
      json: (d) => (trackByNumData = d),
    };
    await getOrderTracking(reqTrackByNumber, resTrackByNum);
    assert(
      trackByNumData && trackByNumData.success && trackByNumData.tracking.trackingNumber === order.trackingNumber,
      `Lookup by Tracking Number '${order.trackingNumber}' succeeded`
    );

    // Case-insensitive lookup (e.g. lowercase zwr-xxxxxx)
    const reqTrackLower = {
      params: { query: order.trackingNumber.toLowerCase() },
      user: { id: "user_test_999" },
    };
    let trackLowerData = null;
    const resTrackLower = {
      status: (c) => ({ statusCode: c, json: (d) => (trackLowerData = d) }),
      json: (d) => (trackLowerData = d),
    };
    await getOrderTracking(reqTrackLower, resTrackLower);
    assert(
      trackLowerData && trackLowerData.success,
      `Case-insensitive Tracking lookup ('${order.trackingNumber.toLowerCase()}') succeeded`
    );

    // -------------------------------------------------------------
    // TEST 5: Edge Cases & Error Handling
    // -------------------------------------------------------------
    console.log("\n🧪 TEST SUITE 5: Edge Cases & Validation");

    // Invalid Status
    const reqInvalidStatus = {
      params: { id: order._id.toString() },
      body: { status: "Flying in the sky" },
    };
    let invalidStatusData = null;
    const resInvalidStatus = {
      status: function (code) {
        this.statusCode = code;
        return this;
      },
      json: (d) => (invalidStatusData = d),
    };
    await updateOrderStatus(reqInvalidStatus, resInvalidStatus);
    assert(
      resInvalidStatus.statusCode === 400 && !invalidStatusData.success,
      "Invalid status transition rejected with HTTP 400"
    );

    // Non-existent order ID
    const reqNotFound = {
      params: { id: new mongoose.Types.ObjectId().toString() },
      user: { id: "user_test_999" },
    };
    let notFoundData = null;
    const resNotFound = {
      status: function (code) {
        this.statusCode = code;
        return this;
      },
      json: (d) => (notFoundData = d),
    };
    await getOrderTracking(reqNotFound, resNotFound);
    assert(
      resNotFound.statusCode === 404 && !notFoundData.success,
      "Non-existent order query handled cleanly with HTTP 404"
    );

    // Clean up
    await Order.deleteMany({ userId: "user_test_999" });
    await mongoose.disconnect();
  }

  console.log("\n=================================================");
  console.log(`📊 RESULTS: ${passed} PASSED, ${failed} FAILED`);
  console.log("=================================================\n");

  process.exit(failed > 0 ? 1 : 0);
}

runTests().catch((err) => {
  console.error("Test execution error:", err);
  process.exit(1);
});
