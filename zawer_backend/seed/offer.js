const mongoose = require("mongoose");
require("dotenv").config();
const Offer = require("../models/Offer");
const Product = require("../models/Product");

const MONGO_URI =
  process.env.MONGO_URI || "mongodb://127.0.0.1:27017/zawer_jewellery";

const seedOffers = [
  {
    code: "ROYAL20",
    title: "Royal 20% Heritage Privilege",
    description: "Enjoy 20% off on all mastercrafted diamond and gold jewellery valuations above ₹25,000.",
    discountType: "percentage",
    discountValue: 20,
    maxDiscount: 10000,
    minOrderAmount: 25000,
    applicableCategory: "All",
    startDate: new Date(),
    expiryDate: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000), // 30 days from now
    usageLimit: 500,
    usedCount: 14,
    isActive: true,
    tag: "MAISON EXCLUSIVE",
    bannerImage: "assets/images/necklace.jpg",
    terms: [
      "Applicable on all certified natural diamond and 18K/22K solid gold items.",
      "Maximum discount capped at ₹10,000 per vault order.",
      "Requires a minimum cart valuation of ₹25,000.",
      "Includes complimentary armored courier transit.",
    ],
  },
  {
    code: "SOLITAIRE5000",
    title: "Imperial Solitaire Flat ₹5,000 Off",
    description: "Flat ₹5,000 instant deduction on all certified Solitaire Rings and VVS1 Diamond collections.",
    discountType: "flat",
    discountValue: 5000,
    maxDiscount: 5000,
    minOrderAmount: 35000,
    applicableCategory: "Ring",
    startDate: new Date(),
    expiryDate: new Date(Date.now() + 45 * 24 * 60 * 60 * 1000), // 45 days
    usageLimit: 300,
    usedCount: 8,
    isActive: true,
    tag: "SOLITAIRE PRIVILEGE",
    bannerImage: "assets/images/ring.png",
    terms: [
      "Valid exclusively on the Solitaire and Engagement Ring collections.",
      "Flat ₹5,000 deduction on minimum order valuation of ₹35,000.",
      "Includes complimentary laser engraving & IGI appraisal.",
    ],
  },
  {
    code: "MAISON10",
    title: "Maison Patron First Order 10%",
    description: "Welcome privilege for new collectors. 10% off on your first handcrafted jewellery piece.",
    discountType: "percentage",
    discountValue: 10,
    maxDiscount: 3000,
    minOrderAmount: 5000,
    applicableCategory: "All",
    startDate: new Date(),
    expiryDate: new Date(Date.now() + 60 * 24 * 60 * 60 * 1000), // 60 days
    usageLimit: 1000,
    usedCount: 42,
    isActive: true,
    tag: "WELCOME PRIVILEGE",
    bannerImage: "assets/images/bracelet.png",
    terms: [
      "Valid across all jewellery categories for first-time orders.",
      "Maximum savings capped at ₹3,000.",
      "No minimum threshold above ₹5,000.",
    ],
  },
  {
    code: "BRIDAL15",
    title: "Imperial Bridal Suite 15% Privilege",
    description: "Elevate your wedding trousseau with 15% off on Royal Kundan, Polki, and Bridal Sets.",
    discountType: "percentage",
    discountValue: 15,
    maxDiscount: 15000,
    minOrderAmount: 50000,
    applicableCategory: "Necklace",
    startDate: new Date(),
    expiryDate: new Date(Date.now() + 20 * 24 * 60 * 60 * 1000), // 20 days
    usageLimit: 200,
    usedCount: 5,
    isActive: true,
    tag: "BRIDAL HEIRLOOM",
    bannerImage: "assets/images/necklace.jpg",
    terms: [
      "Valid on Necklaces and Imperial Bridal Suite collections.",
      "Requires minimum cart order of ₹50,000.",
      "Max discount of ₹15,000 applied directly at checkout.",
    ],
  },
  {
    code: "GOLD2500",
    title: "22K Solid Gold Chains Flat ₹2,500",
    description: "Flat ₹2,500 concession on hallmarked 22K Italian and Royal heritage gold chains.",
    discountType: "flat",
    discountValue: 2500,
    maxDiscount: 2500,
    minOrderAmount: 20000,
    applicableCategory: "Chain",
    startDate: new Date(),
    expiryDate: new Date(Date.now() + 15 * 24 * 60 * 60 * 1000), // 15 days
    usageLimit: 400,
    usedCount: 19,
    isActive: true,
    tag: "SOLID GOLD",
    bannerImage: "assets/images/bracelet.png",
    terms: [
      "Valid on solid gold chain masterpieces.",
      "Minimum order valuation of ₹20,000 required.",
    ],
  },
  {
    code: "EXPIRED50",
    title: "Past Festival 50% Flash Offer",
    description: "Expired commemorative promotion (used for verifying rigorous expiry guard rails).",
    discountType: "percentage",
    discountValue: 50,
    maxDiscount: 25000,
    minOrderAmount: 10000,
    applicableCategory: "All",
    startDate: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000),
    expiryDate: new Date(Date.now() - 5 * 24 * 60 * 60 * 1000), // Expired 5 days ago
    usageLimit: 100,
    usedCount: 100,
    isActive: true,
    tag: "EXPIRED SPECIAL",
    bannerImage: "assets/images/ring.png",
    terms: ["This promotional offer has expired."],
  },
];

async function runSeed() {
  try {
    console.log("Connecting to MongoDB for Offer Seeding...");
    await mongoose.connect(MONGO_URI);
    console.log("MongoDB connected successfully.");

    await Offer.deleteMany({});
    console.log("Cleared existing offers collection.");

    const inserted = await Offer.insertMany(seedOffers);
    console.log(`Successfully seeded ${inserted.length} promotional offers & coupons.`);

    // Also update some products with special discounts for discounted-products feature
    const products = await Product.find({});
    if (products.length > 0) {
      // Mark 6 products with special discounts
      const discountMap = [
        { id: "1", originalPrice: 28500, discountPercentage: 15, tag: "15% FESTIVE" },
        { id: "2", originalPrice: 65000, discountPercentage: 20, tag: "20% BRIDAL" },
        { id: "3", originalPrice: 42000, discountPercentage: 10, tag: "10% PRIVILEGE" },
        { id: "4", originalPrice: 19500, discountPercentage: 12, tag: "12% SPECIAL" },
        { id: "5", originalPrice: 55000, discountPercentage: 18, tag: "18% ROYAL" },
        { id: "6", originalPrice: 31000, discountPercentage: 15, tag: "15% SOLITAIRE" },
      ];

      for (const item of discountMap) {
        await Product.updateOne(
          { id: item.id },
          {
            $set: {
              originalPrice: item.originalPrice,
              discountPercentage: item.discountPercentage,
              isSpecialOffer: true,
              offerTag: item.tag,
            },
          }
        );
      }
      console.log("Updated sample products with discount pricing & special offer tags.");
    }

    await mongoose.connection.close();
    console.log("MongoDB connection closed.");
  } catch (error) {
    console.error("Seeding Error:", error);
    process.exit(1);
  }
}

runSeed();
