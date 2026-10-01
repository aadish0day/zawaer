const Product = require("../models/Product");

function escapeRegex(text) {
  if (typeof text !== "string") return "";
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 100;
const MAX_COMMENT_LENGTH = 1000;

// Returns { page, limit, skip } or null when page/limit are not positive integers.
function parsePaging(query) {
  const page = query.page === undefined ? 1 : Number(query.page);
  const limit = query.limit === undefined ? DEFAULT_LIMIT : Number(query.limit);
  if (!Number.isSafeInteger(page) || page < 1 || !Number.isSafeInteger(limit) || limit < 1) {
    return null;
  }
  const capped = Math.min(limit, MAX_LIMIT);
  return { page, limit: capped, skip: (page - 1) * capped };
}

const badPaging = (res) =>
  res.status(400).json({
    success: false,
    message: "page and limit must be positive whole numbers",
  });

const getProducts = async (req, res) => {
  try {
    const paging = parsePaging(req.query);
    if (!paging) return badPaging(res);
    const { page, limit, skip } = paging;

    const total = await Product.countDocuments();
    // Reviews have their own endpoint; never ship them (or reviewer ids) in lists
    const products = await Product.find()
      .select("-reviews")
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
    }).select("-reviews");

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
    const paging = parsePaging(req.query);
    if (!paging) return badPaging(res);
    const { page, limit, skip } = paging;

    const rawSearch = req.query.search || "";
    const search = escapeRegex(rawSearch.toString().trim());

    const filter = {
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
    };

    const total = await Product.countDocuments(filter);
    const products = await Product.find(filter)
      .select("-reviews")
      .sort({ createdAt: -1 })
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
    const { rating, comment } = req.body || {};
    const productId = req.params.id;
    const userId = req.user.id;

    const numRating = Number(rating);
    if (
      (typeof rating !== "number" && typeof rating !== "string") ||
      !Number.isInteger(numRating) ||
      numRating < 1 ||
      numRating > 5
    ) {
      return res.status(400).json({
        success: false,
        message: "Rating must be a whole number between 1 and 5",
      });
    }

    const text = typeof comment === "string" ? comment.trim() : "";
    if (!text || text.length > MAX_COMMENT_LENGTH) {
      return res.status(400).json({
        success: false,
        message: `Comment is required (max ${MAX_COMMENT_LENGTH} characters)`,
      });
    }

    const user = await User.findById(userId);
    const userName = user ? user.name : "Anonymous";

    const newReview = {
      userId,
      userName,
      rating: numRating,
      comment: text,
      date: new Date(),
    };

    // Atomic duplicate check: only push if this user has no review yet
    const pushed = await Product.updateOne(
      { id: productId, "reviews.userId": { $ne: userId } },
      { $push: { reviews: newReview } }
    );

    if (pushed.matchedCount === 0) {
      const exists = await Product.exists({ id: productId });
      return res.status(exists ? 400 : 404).json({
        success: false,
        message: exists
          ? "You have already reviewed this product"
          : "Product not found",
      });
    }

    // No review-count field exists, so the seeded rating is only a baseline
    // while there are zero reviews; once reviews exist, rating = their average.
    // Recomputed server-side from the current array so concurrent reviews can't
    // overwrite each other with a stale average.
    const product = await Product.findOneAndUpdate(
      { id: productId },
      [{ $set: { rating: { $round: [{ $avg: "$reviews.rating" }, 1] } } }],
      { returnDocument: "after", updatePipeline: true }
    );

    return res.status(201).json({
      success: true,
      message: "Review added successfully",
      review: product.reviews.find((r) => r.userId === userId),
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

    // Public shape only: no reviewer userId
    const sortedReviews = [...product.reviews]
      .sort((a, b) => new Date(b.date) - new Date(a.date))
      .map(({ rating, userName, comment, date }) => ({
        rating,
        userName,
        comment,
        date,
      }));

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