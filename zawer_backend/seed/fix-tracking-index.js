// One-off migration: replace the old non-partial unique index on
// orders.trackingNumber with the partial one defined in models/Order.js.
// Safe to run more than once. Usage: node seed/fix-tracking-index.js
require("dotenv").config();
const mongoose = require("mongoose");
const Order = require("../models/Order");

const INDEX_NAME = "trackingNumber_1";

(async () => {
  await mongoose.connect(process.env.MONGO_URI);
  const collection = Order.collection;

  const indexes = await collection.indexes().catch((err) => {
    if (err.codeName === "NamespaceNotFound") return [];
    throw err;
  });
  const existing = indexes.find((i) => i.name === INDEX_NAME);

  if (existing && existing.partialFilterExpression) {
    console.log("Index is already partial. Nothing to do.");
    return;
  }

  // Real tracking numbers must already be unique, or the new index can't be built.
  const duplicates = await collection
    .aggregate([
      { $match: { trackingNumber: { $type: "string", $gt: "" } } },
      { $group: { _id: "$trackingNumber", count: { $sum: 1 } } },
      { $match: { count: { $gt: 1 } } },
    ])
    .toArray();
  if (duplicates.length) {
    console.error("Duplicate tracking numbers found, index not changed:", duplicates.map((d) => d._id));
    process.exitCode = 1;
    return;
  }

  if (existing) {
    await collection.dropIndex(INDEX_NAME);
    console.log("Dropped old index", INDEX_NAME);
  }
  await collection.createIndex(
    { trackingNumber: 1 },
    { name: INDEX_NAME, unique: true, partialFilterExpression: { trackingNumber: { $type: "string", $gt: "" } } }
  );
  console.log("Created partial unique index", INDEX_NAME);
})()
  .catch((err) => {
    console.error("Migration failed:", err.message);
    process.exitCode = 1;
  })
  .finally(() => mongoose.disconnect());
