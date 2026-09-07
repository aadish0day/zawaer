const Product = require("../models/Product");

function escapeRegex(text) {
  if (typeof text !== "string") return "";
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

const getProducts = async (req, res) => {
  try {
    const page = Math.max(1, parseInt(req.query.page, 10) || 1);
    const limit = Math.max(1, parseInt(req.query.limit, 10) || 50);
    const skip = (page - 1) * limit;

    const total = await Product.countDocuments();
    const products = await Product.find()
      .sort({
        createdAt: -1,
      })
      .skip(skip)
      .limit(limit);

    return res.status(200).json({
      success: true,
      count: products.length,
      total,
      page,
      pages: Math.ceil(total / limit),
      products,
    });
  } catch (error) {
    console.error(
      "Get Products Error:",
      error.message
    );

    return res.status(500).json({
      success: false,
      message: "Failed to fetch products",
    });
  }
};

const getProductById = async (req, res) => {
  try {
    const product = await Product.findOne({
      id: req.params.id,
    });

    if (!product) {
      return res.status(404).json({
        success: false,
        message: "Product not found",
      });
    }

    return res.status(200).json({
      success: true,
      product,
    });
  } catch (error) {
    console.error(
      "Get Product Error:",
      error.message
    );

    return res.status(500).json({
      success: false,
      message: "Failed to fetch product",
    });
  }
};

const searchProducts = async (req, res) => {
  try {
    const rawSearch = req.query.search || "";
    const search = escapeRegex(rawSearch.toString().trim());

    const products = await Product.find({
      $or: [
        {
          name: {
            $regex: search,
            $options: "i",
          },
        },
        {
          category: {
            $regex: search,
            $options: "i",
          },
        },
      ],
    });

    return res.status(200).json({
      success: true,
      count: products.length,
      products,
    });
  } catch (error) {
    console.error(
      "Search Products Error:",
      error.message
    );

    return res.status(500).json({
      success: false,
      message: "Product search failed",
    });
  }
};

const User = require("../models/User");

const addProductReview = async (req, res) => {
  try {
    const { rating, comment } = req.body;
    const productId = req.params.id;
    const userId = req.user.id;

    if (!rating || !comment) {
      return res.status(400).json({
        success: false,
        message: "Rating and comment are required",
      });
    }

    if (rating < 1 || rating > 5) {
      return res.status(400).json({
        success: false,
        message: "Rating must be between 1 and 5",
      });
    }

    const product = await Product.findOne({ id: productId });

    if (!product) {
      return res.status(404).json({
        success: false,
        message: "Product not found",
      });
    }

    const existingReview = product.reviews.find(
      (r) => r.userId === userId
    );

    if (existingReview) {
      return res.status(400).json({
        success: false,
        message: "You have already reviewed this product",
      });
    }

    const user = await User.findById(userId);
    const userName = user ? user.name : "Anonymous";

    const newReview = {
      userId,
      userName,
      rating: Number(rating),
      comment,
      date: new Date(),
    };

    product.reviews.push(newReview);

    const totalRating = product.reviews.reduce(
      (sum, r) => sum + r.rating,
      0
    );
    product.rating = totalRating / product.reviews.length;

    await product.save();

    return res.status(201).json({
      success: true,
      message: "Review added successfully",
      review: newReview,
      averageRating: product.rating,
      totalReviews: product.reviews.length,
    });
  } catch (error) {
    console.error("Add Review Error:", error.message);

    return res.status(500).json({
      success: false,
      message: "Failed to add review",
    });
  }
};

const getProductReviews = async (req, res) => {
  try {
    const productId = req.params.id;

    const product = await Product.findOne({ id: productId });

    if (!product) {
      return res.status(404).json({
        success: false,
        message: "Product not found",
      });
    }

    const sortedReviews = [...product.reviews].sort(
      (a, b) => new Date(b.date) - new Date(a.date)
    );

    return res.status(200).json({
      success: true,
      reviews: sortedReviews,
      averageRating: product.rating,
      totalReviews: product.reviews.length,
    });
  } catch (error) {
    console.error("Get Reviews Error:", error.message);

    return res.status(500).json({
      success: false,
      message: "Failed to fetch reviews",
    });
  }
};

module.exports = {
  getProducts,
  getProductById,
  searchProducts,
  addProductReview,
  getProductReviews,
};