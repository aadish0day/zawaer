require("dotenv").config();

const mongoose = require("mongoose");
const Product = require("../models/Product");

const products = [
  // ==================== RINGS ====================
  {
    id: "1",
    name: "Royal Diamond Ring",
    category: "Ring",
    description: "Luxury diamond ring crafted in 18K gold.",
    price: 25999,
    rating: 4.9,
    images: ["assets/images/ring.png", "assets/images/ring1.png", "assets/images/ring2.png"],
  },
  {
    id: "21",
    name: "Classic Gold Band",
    category: "Ring",
    description: "Timeless plain gold band for everyday elegance.",
    price: 8999,
    rating: 4.6,
    images: ["assets/images/ring1.png", "assets/images/ring.png", "assets/images/ring2.png"],
  },
  {
    id: "22",
    name: "Emerald Solitaire Ring",
    category: "Ring",
    description: "Stunning solitaire featuring a certified emerald centre stone.",
    price: 45999,
    rating: 4.8,
    images: ["assets/images/ring2.png", "assets/images/ring.png", "assets/images/ring1.png"],
  },
  {
    id: "23",
    name: "Rose Gold Couple Ring",
    category: "Ring",
    description: "Romantic rose gold ring set, perfect for couples.",
    price: 12999,
    rating: 4.7,
    images: ["assets/images/ring.png", "assets/images/ring2.png", "assets/images/ring1.png"],
  },

  // ==================== NECKLACES ====================
  {
    id: "2",
    name: "Luxury Necklace",
    category: "Necklace",
    description: "Elegant necklace for special occasions.",
    price: 35999,
    rating: 4.8,
    images: ["assets/images/necklace.jpg", "assets/images/necklace1.jpg", "assets/images/necklace2.jpg"],
  },
  {
    id: "24",
    name: "Pearl Choker Necklace",
    category: "Necklace",
    description: "Graceful choker strung with hand-picked freshwater pearls.",
    price: 18999,
    rating: 4.7,
    images: ["assets/images/necklace1.jpg", "assets/images/necklace.jpg", "assets/images/necklace2.jpg"],
  },
  {
    id: "25",
    name: "Diamond Pendant Necklace",
    category: "Necklace",
    description: "Sparkling solitaire diamond pendant on a delicate gold chain.",
    price: 52999,
    rating: 4.9,
    images: ["assets/images/necklace2.jpg", "assets/images/necklace1.jpg", "assets/images/necklace.jpg"],
  },
  {
    id: "26",
    name: "Kundan Bridal Set",
    category: "Necklace",
    description: "Traditional kundan bridal necklace for the perfect wedding look.",
    price: 68999,
    rating: 5.0,
    images: ["assets/images/necklace.jpg", "assets/images/necklace2.jpg", "assets/images/necklace1.jpg"],
  },

  // ==================== CHAINS ====================
  {
    id: "3",
    name: "Premium Chain",
    category: "Chain",
    description: "Premium gold chain.",
    price: 18999,
    rating: 4.7,
    images: ["assets/images/chain.png", "assets/images/chain1.png", "assets/images/chain2.png"],
  },
  {
    id: "27",
    name: "Italian Gold Chain",
    category: "Chain",
    description: "Imported 18K Italian craftsmanship with mirror finish.",
    price: 24999,
    rating: 4.6,
    images: ["assets/images/chain1.png", "assets/images/chain.png", "assets/images/chain2.png"],
  },
  {
    id: "28",
    name: "Platinum Rope Chain",
    category: "Chain",
    description: "Durable platinum rope pattern for a bold statement.",
    price: 31999,
    rating: 4.8,
    images: ["assets/images/chain2.png", "assets/images/chain1.png", "assets/images/chain.png"],
  },
  {
    id: "29",
    name: "Silver Cuban Chain",
    category: "Chain",
    description: "Sterling silver Cuban link with rhodium polish.",
    price: 7999,
    rating: 4.5,
    images: ["assets/images/chain.png", "assets/images/chain2.png", "assets/images/chain1.png"],
  },

  // ==================== EARRINGS ====================
  {
    id: "4",
    name: "Diamond Earrings",
    category: "Earrings",
    description: "Luxury earrings with certified diamonds.",
    price: 14999,
    rating: 4.9,
    images: ["assets/images/earing.jpg", "assets/images/earing1.jpg", "assets/images/earing2.jpg"],
  },
  {
    id: "30",
    name: "Gold Jhumka Earrings",
    category: "Earrings",
    description: "Classic temple-design jhumkas in antique gold finish.",
    price: 16999,
    rating: 4.8,
    images: ["assets/images/earing1.jpg", "assets/images/earing.jpg", "assets/images/earing2.jpg"],
  },
  {
    id: "31",
    name: "Pearl Drop Earrings",
    category: "Earrings",
    description: "Delicate pearl drops that sway with every movement.",
    price: 9999,
    rating: 4.6,
    images: ["assets/images/earing2.jpg", "assets/images/earing1.jpg", "assets/images/earing.jpg"],
  },
  {
    id: "32",
    name: "Chandbali Earrings",
    category: "Earrings",
    description: "Crescent-shaped chandbalis studded with polki stones.",
    price: 13999,
    rating: 4.7,
    images: ["assets/images/earing.jpg", "assets/images/earing2.jpg", "assets/images/earing1.jpg"],
  },

  // ==================== BRACELETS ====================
  {
    id: "5",
    name: "Luxury Bracelet",
    category: "Bracelet",
    description: "Designer bracelet for women.",
    price: 22999,
    rating: 4.8,
    images: ["assets/images/bracelet.png", "assets/images/bracelet1.png", "assets/images/bracelet2.png"],
  },
  {
    id: "33",
    name: "Tennis Diamond Bracelet",
    category: "Bracelet",
    description: "A continuous line of brilliant-cut diamonds in white gold.",
    price: 47999,
    rating: 4.9,
    images: ["assets/images/bracelet1.png", "assets/images/bracelet.png", "assets/images/bracelet2.png"],
  },
  {
    id: "34",
    name: "Gold Kada Bracelet",
    category: "Bracelet",
    description: "Heavy traditional kada with intricate carved patterns.",
    price: 27999,
    rating: 4.7,
    images: ["assets/images/bracelet2.png", "assets/images/bracelet1.png", "assets/images/bracelet.png"],
  },
  {
    id: "35",
    name: "Charm Bracelet",
    category: "Bracelet",
    description: "Playful charm bracelet - collect a charm for every occasion.",
    price: 10999,
    rating: 4.5,
    images: ["assets/images/bracelet.png", "assets/images/bracelet2.png", "assets/images/bracelet1.png"],
  },
];

async function seedProducts() {
  try {
    await mongoose.connect(process.env.MONGO_URI);

    console.log("MongoDB connected for product seeding.");

    await Product.deleteMany({});

    await Product.insertMany(products);

    console.log(
      `${products.length} products inserted successfully.`
    );

    await mongoose.disconnect();

    console.log("MongoDB connection closed.");
  } catch (error) {
    console.error("Product seeding failed:");
    console.error(error.message);

    process.exit(1);
  }
}

seedProducts();
