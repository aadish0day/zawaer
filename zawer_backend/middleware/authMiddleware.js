const jwt = require("jsonwebtoken");
const User = require("../models/User");

// Returns { id, email, role } for a valid, unrevoked token, else null.
// DB errors propagate (Express's 500 handler) instead of a misleading 401.
const userFromToken = async (token) => {
  let decoded;

  try {
    decoded = jwt.verify(
      token,
      process.env.JWT_SECRET
    );
  } catch (error) {
    return null;
  }

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
    return null;
  }

  return {
    id: user._id.toString(),
    email: user.email,
    role: user.role,
  };
};

const authMiddleware = async (
  req,
  res,
  next
) => {
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

  const user = await userFromToken(
    authHeader.split(" ")[1]
  );

  if (!user) {
    return res.status(401).json({
      success: false,
      message: "Invalid or expired token",
    });
  }

  req.user = user;

  next();
};

// Sets req.user when a valid Bearer token is present; guests (no token or an
// invalid one) continue without req.user instead of being rejected.
const optionalAuth = async (req, res, next) => {
  const authHeader = req.headers.authorization;

  if (authHeader && authHeader.startsWith("Bearer ")) {
    const user = await userFromToken(authHeader.split(" ")[1]);
    if (user) req.user = user;
  }

  next();
};

module.exports = authMiddleware;
module.exports.optionalAuth = optionalAuth;