const jwt = require("jsonwebtoken");
const User = require("../models/User");

const authMiddleware = async (
  req,
  res,
  next
) => {
  let decoded;

  try {
    const authHeader =
      req.headers.authorization;

    if (!authHeader) {
      return res.status(401).json({
        success: false,
        message: "Authorization token is required",
      });
    }

    if (!authHeader.startsWith("Bearer ")) {
      return res.status(401).json({
        success: false,
        message: "Invalid authorization format",
      });
    }

    const token =
      authHeader.split(" ")[1];

    decoded = jwt.verify(
      token,
      process.env.JWT_SECRET
    );
  } catch (error) {
    return res.status(401).json({
      success: false,
      message: "Invalid or expired token",
    });
  }

  // DB errors fall through to Express's 500 handler instead of a misleading 401
  const user = await User.findById(decoded.id).select(
    "email role passwordChangedAt"
  );

  // iat has 1s resolution: only reject tokens issued in a second before the
  // password change, so a login right after a reset is not rejected.
  if (
    !user ||
    (user.passwordChangedAt &&
      decoded.iat <
        Math.floor(user.passwordChangedAt.getTime() / 1000))
  ) {
    return res.status(401).json({
      success: false,
      message: "Invalid or expired token",
    });
  }

  req.user = {
    id: user._id.toString(),
    email: user.email,
    role: user.role,
  };

  next();
};

module.exports = authMiddleware;