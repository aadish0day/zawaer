const mongoose = require("mongoose");
require("dotenv").config();

const Offer = require("./models/Offer");
const Product = require("./models/Product");
const Order = require("./models/Order");
const offerController = require("./controllers/offerController");
const orderController = require("./controllers/orderController");

const MONGO_URI =
  process.env.MONGO_URI || "mongodb://127.0.0.1:27017/zawer_jewellery";

// This suite writes real orders and coupon usage: never run it against a remote DB.
if (!/127\.0\.0\.1|localhost/.test(MONGO_URI)) {
  console.error("Refusing to run: MONGO_URI must point at a local MongoDB (127.0.0.1 / localhost).");
  process.exit(1);
}

// Helper to create mock Express req and res
function mockReqRes(body = {}, params = {}, query = {}, user = { id: "test_user_777" }) {
  const req = { body, params, query, user };
  let statusCode = 200;
  let responseData = null;

  const res = {
    status: (code) => {
      statusCode = code;
      return res;
    },
    json: (data) => {
      responseData = data;
      return res;
    },
  };

  return {
    req,
    res,
    getStatus: () => statusCode,
    getData: () => responseData,
  };
}

async function runDeepTests() {
  console.log("=================================================");
  console.log("💎 STARTING OFFERS & DISCOUNTS CORE LOGIC TESTS");
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

  try {
    await mongoose.connect(MONGO_URI);
    console.log("📦 MongoDB Atlas connection established for testing.\n");

    // -------------------------------------------------------------
    // TEST SUITE 1: Fetching Active Offers & Expiry Calculations
    // -------------------------------------------------------------
    console.log("🧪 TEST SUITE 1: Fetching Active Offers & Expiry Calculations");
    const m1 = mockReqRes();
    await offerController.getAllOffers(m1.req, m1.res);
    assert(m1.getStatus() === 200, "getAllOffers returns HTTP 200");
    assert(m1.getData().success === true, "Response success is true");
    assert(Array.isArray(m1.getData().offers), "Offers is returned as array");
    assert(m1.getData().offers.length >= 5, `Found ${m1.getData().offers.length} offers in database`);

    const royal20 = m1.getData().offers.find((o) => o.code === "ROYAL20");
    assert(royal20 != null, "Found 'ROYAL20' offer");
    assert(royal20.isExpired === false, "'ROYAL20' is marked active / not expired");
    assert(royal20.daysRemaining > 0, `'ROYAL20' has valid remaining days (${royal20.daysRemaining} days)`);
    assert(royal20.isValid === true, "'ROYAL20' is marked valid for client usage");

    const expired50 = m1.getData().offers.find((o) => o.code === "EXPIRED50");
    assert(expired50 != null, "Found 'EXPIRED50' offer in directory");
    assert(expired50.isExpired === true, "'EXPIRED50' is correctly marked expired");
    assert(expired50.isValid === false, "'EXPIRED50' is marked invalid for usage");

    // -------------------------------------------------------------
    // TEST SUITE 2: Discounted Products Catalog
    // -------------------------------------------------------------
    console.log("\n🧪 TEST SUITE 2: Discounted Jewellery Products Catalog");
    const m2 = mockReqRes();
    await offerController.getDiscountedProducts(m2.req, m2.res);
    assert(m2.getStatus() === 200, "getDiscountedProducts returns HTTP 200");
    assert(m2.getData().success === true, "Discounted products response success is true");
    assert(Array.isArray(m2.getData().products), "Discounted products is an array");
    assert(m2.getData().products.length > 0, `Found ${m2.getData().products.length} discounted products`);

    // -------------------------------------------------------------
    // TEST SUITE 3: Coupon Validation & Discount Calculations
    // -------------------------------------------------------------
    console.log("\n🧪 TEST SUITE 3: Coupon Validation & Discount Calculations");

    // A. Percentage calculation (20% of 30,000 = 6,000)
    const m3A = mockReqRes({ couponCode: "ROYAL20", subtotal: 30000 });
    await offerController.validateCoupon(m3A.req, m3A.res);
    assert(m3A.getStatus() === 200, "Validate ROYAL20 on ₹30,000 succeeds with HTTP 200");
    assert(m3A.getData().coupon.discountAmount === 6000, "20% discount on ₹30,000 is exactly ₹6,000");
    assert(m3A.getData().coupon.finalAmount === 24000, "Final payable amount is exactly ₹24,000");

    // B. Max Discount Cap (20% of 60,000 = 12,000, capped at max 10,000)
    const m3B = mockReqRes({ couponCode: "ROYAL20", subtotal: 60000 });
    await offerController.validateCoupon(m3B.req, m3B.res);
    assert(m3B.getData().coupon.discountAmount === 10000, "Discount capped at maxDiscount ₹10,000 (instead of ₹12,000)");
    assert(m3B.getData().coupon.finalAmount === 50000, "Final payable amount correctly reflects cap (₹50,000)");

    // C. Flat Discount (SOLITAIRE5000: Flat 5,000 off on 40,000)
    const m3C = mockReqRes({ couponCode: "SOLITAIRE5000", subtotal: 40000, category: "Ring" });
    await offerController.validateCoupon(m3C.req, m3C.res);
    assert(m3C.getStatus() === 200, "Validate SOLITAIRE5000 on Ring succeeds");
    assert(m3C.getData().coupon.discountAmount === 5000, "Flat ₹5,000 discount applied");
    assert(m3C.getData().coupon.finalAmount === 35000, "Final amount is ₹35,000");

    // -------------------------------------------------------------
    // TEST SUITE 4: Guard Rails & Error Handling (Expiry, Min Value, Category)
    // -------------------------------------------------------------
    console.log("\n🧪 TEST SUITE 4: Guard Rails & Rejection Logic");

    // A. Minimum order value rejection
    const m4A = mockReqRes({ couponCode: "ROYAL20", subtotal: 15000 }); // requires 25,000
    await offerController.validateCoupon(m4A.req, m4A.res);
    assert(m4A.getStatus() === 400, "Order below minOrderAmount rejected with HTTP 400");
    assert(m4A.getData().success === false, "Rejection returns success: false");

    // B. Expiry rejection
    const m4B = mockReqRes({ couponCode: "EXPIRED50", subtotal: 20000 });
    await offerController.validateCoupon(m4B.req, m4B.res);
    assert(m4B.getStatus() === 400, "Expired coupon rejected with HTTP 400");
    assert(m4B.getData().isExpired === true, "Response explicitly identifies isExpired: true");

    // C. Category mismatch rejection
    const m4C = mockReqRes({ couponCode: "SOLITAIRE5000", subtotal: 40000, category: "Necklace" }); // Requires Ring
    await offerController.validateCoupon(m4C.req, m4C.res);
    assert(m4C.getStatus() === 400, "Category mismatch rejected with HTTP 400");

    // D. Non-existent coupon code
    const m4D = mockReqRes({ couponCode: "NONEXISTENT999", subtotal: 50000 });
    await offerController.validateCoupon(m4D.req, m4D.res);
    assert(m4D.getStatus() === 404, "Non-existent coupon code returns HTTP 404");

    // -------------------------------------------------------------
    // TEST SUITE 5: Placing Order with Coupon & Discount Attachment
    // -------------------------------------------------------------
    console.log("\n🧪 TEST SUITE 5: Placing Order with Coupon & Discount Attachment");
    const m5 = mockReqRes({
      customerName: "Heritage Patron",
      phone: "9876543210",
      address: "742 Evergreen Vault, Mumbai",
      paymentMethod: "Cash on Delivery",
      couponCode: "ROYAL20",
      items: [
        {
          productId: "1",
          name: "Imperial Solitaire Diamond Ring",
          price: 30000,
          quantity: 1,
        },
      ],
    });

    await orderController.placeOrder(m5.req, m5.res);
    assert(m5.getStatus() === 201, "Order with coupon placed with HTTP 201");
    const createdOrder = m5.getData().order;
    assert(createdOrder.couponCode === "ROYAL20", "Order has couponCode: 'ROYAL20'");
    assert(createdOrder.subtotal === 30000, "Order subtotal is ₹30,000");
    assert(createdOrder.discountAmount === 6000, "Order discountAmount is ₹6,000");
    assert(createdOrder.totalAmount === 24000, "Order totalAmount is ₹24,000");

    // Verify usage increment in DB
    const updatedOffer = await Offer.findOne({ code: "ROYAL20" });
    assert(updatedOffer.usedCount > 14, `Offer usage counter incremented in MongoDB (now ${updatedOffer.usedCount})`);

    console.log("\n=================================================");
    console.log(`📊 RESULTS: ${passed} PASSED, ${failed} FAILED`);
    console.log("=================================================\n");

    await mongoose.connection.close();
    process.exit(failed > 0 ? 1 : 0);
  } catch (err) {
    console.error("Test execution failed with error:", err);
    process.exit(1);
  }
}

runDeepTests();
