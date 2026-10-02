const crypto = require("crypto");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const User = require("../models/User");
const { cpLen, isValidPhone } = require("../utils/validation");

const MAX_OTP_ATTEMPTS = 5;
const OTP_RESEND_MS = 60 * 1000;

// Shared validation contract (the app enforces the same rules; lengths in code points)
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const isValidPassword = (p) => cpLen(p) >= 6 && cpLen(p) <= 128;

const hashOtp = (otp) =>
  crypto.createHash("sha256").update(otp).digest("hex");

// JSON bodies can carry objects/arrays/numbers; only accept real strings.
const allStrings = (...values) =>
  values.every((v) => typeof v === "string");

// Optional fields: absent (undefined/null) or a string.
const optionalStrings = (...values) =>
  values.every((v) => v == null || typeof v === "string");

const registerUser = async (req, res) => {
  try {
    const { name, email, phone, password } = req.body;

    if (
      !allStrings(name, email, password) ||
      !optionalStrings(phone) ||
      !name.trim() ||
      !email.trim() ||
      !password
    ) {
      return res.status(400).json({
        success: false,
        message: "Name, email and password are required",
      });
    }

    const cleanEmail = email.toLowerCase().trim();
    const cleanPhone = (phone || "").trim();

    if (cpLen(name.trim()) > 100) {
      return res.status(400).json({ success: false, message: "Name must be at most 100 characters" });
    }
    if (cpLen(cleanEmail) > 254 || !EMAIL_RE.test(cleanEmail)) {
      return res.status(400).json({ success: false, message: "Please enter a valid email address" });
    }
    if (!isValidPassword(password)) {
      return res.status(400).json({ success: false, message: "Password must be 6-128 characters" });
    }
    if (cleanPhone && !isValidPhone(cleanPhone)) {
      return res.status(400).json({ success: false, message: "Please enter a valid phone number" });
    }

    const existingUser = await User.findOne({
      email: cleanEmail,
    });

    if (existingUser) {
      return res.status(400).json({
        success: false,
        message: "User already exists",
      });
    }

    const hashedPassword = await bcrypt.hash(password, 10);

    let user;
    try {
      user = await User.create({
        name: name.trim(),
        email: cleanEmail,
        phone: cleanPhone,
        password: hashedPassword,
      });
    } catch (error) {
      // Concurrent registration with the same email lost the unique-index race
      if (error.code === 11000) {
        return res.status(400).json({ success: false, message: "User already exists" });
      }
      throw error;
    }

    return res.status(201).json({
      success: true,
      message: "User registered successfully",
      user: {
        id: user._id,
        name: user.name,
        email: user.email,
        phone: user.phone,
      },
    });
  } catch (error) {
    console.error("Register Error:", error);

    return res.status(500).json({
      success: false,
      message: "Server error",
    });
  }
};

const loginUser = async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!allStrings(email, password) || !email.trim() || !password) {
      return res.status(400).json({
        success: false,
        message: "Email and password are required",
      });
    }

    const user = await User.findOne({
      email: email.toLowerCase().trim(),
    });

    if (!user) {
      return res.status(401).json({
        success: false,
        message: "Invalid email or password",
      });
    }

    const passwordMatch = await bcrypt.compare(
      password,
      user.password
    );

    if (!passwordMatch) {
      return res.status(401).json({
        success: false,
        message: "Invalid email or password",
      });
    }

    const token = jwt.sign(
      {
        id: user._id,
        email: user.email,
      },
      process.env.JWT_SECRET,
      {
        expiresIn: "7d",
      }
    );

    return res.status(200).json({
      success: true,
      message: "Login successful",
      token: token,
      user: {
        id: user._id,
        name: user.name,
        email: user.email,
        phone: user.phone,
        role: user.role,
      },
    });
  } catch (error) {
    console.error("Login Error:", error);

    return res.status(500).json({
      success: false,
      message: "Server error",
    });
  }
};


const getProfile = async (req, res) => {
  try {
    const user = await User.findById(req.user.id).select("-password");

    if (!user) {
      return res.status(404).json({
        success: false,
        message: "User not found",
      });
    }

    return res.status(200).json({
      success: true,
      user: {
        id: user._id,
        name: user.name,
        email: user.email,
        phone: user.phone,
        role: user.role,
      },
    });
  } catch (error) {
    console.error("Get Profile Error:", error);

    return res.status(500).json({
      success: false,
      message: "Server error",
    });
  }
};

const updateProfile = async (req, res) => {
  try {
    const { name, phone } = req.body;

    if (!optionalStrings(name, phone)) {
      return res.status(400).json({
        success: false,
        message: "Name and phone must be text",
      });
    }

    const user = await User.findById(req.user.id);

    if (!user) {
      return res.status(404).json({
        success: false,
        message: "User not found",
      });
    }

    if (name && cpLen(name.trim()) > 100) {
      return res.status(400).json({ success: false, message: "Name must be at most 100 characters" });
    }

    // Empty phone clears it; a new number must be valid. An unchanged (possibly legacy)
    // phone is not re-validated, so it can't block a name change.
    if (phone != null && phone.trim() && phone.trim() !== user.phone && !isValidPhone(phone)) {
      return res.status(400).json({ success: false, message: "Please enter a valid phone number" });
    }

    if (name && name.trim()) {
      user.name = name.trim();
    }

    if (phone != null) {
      user.phone = phone.trim();
    }

    await user.save();

    return res.status(200).json({
      success: true,
      message: "Profile updated successfully",
      user: {
        id: user._id,
        name: user.name,
        email: user.email,
        phone: user.phone,
      },
    });
  } catch (error) {
    console.error("Update Profile Error:", error);

    return res.status(500).json({
      success: false,
      message: "Server error",
    });
  }
};

const forgotPassword = async (req, res) => {
  try {
    const { email } = req.body;

    if (!allStrings(email) || !email.trim()) {
      return res.status(400).json({
        success: false,
        message: "Email is required",
      });
    }

    const user = await User.findOne({
      email: email.toLowerCase().trim(),
    });

    // Same response whether or not the account exists (no email enumeration)
    const responsePayload = {
      success: true,
      message: "If an account exists for this email, an OTP has been sent",
    };

    if (!user) {
      return res.status(200).json(responsePayload);
    }

    const otp = crypto.randomInt(100000, 1000000).toString();
    const now = new Date();

    // Per-account throttle: a still-valid OTP issued under 60s ago is kept, so nobody can
    // keep cancelling a victim's OTP (and resetting its attempt count). Same generic reply.
    const issued = await User.findOneAndUpdate(
      {
        _id: user._id,
        // Time-based only: a lockout that cleared otpCode must not allow an instant re-issue.
        // (OTPs expire after 10 min, so an expired one is always past this window.)
        otpIssuedAt: { $not: { $gt: new Date(now.getTime() - OTP_RESEND_MS) } },
      },
      {
        $set: {
          otpCode: hashOtp(otp),
          otpExpiry: new Date(now.getTime() + 10 * 60 * 1000),
          otpIssuedAt: now,
          otpAttempts: 0,
        },
      }
    );

    if (!issued) {
      return res.status(200).json(responsePayload);
    }

    // Explicit opt-in only: never expose the OTP unless NODE_ENV=development
    if (process.env.NODE_ENV === "development") {
      console.log(`[AUTH] Reset OTP for ${user.email}: ${otp}`);
      responsePayload.devOtp = otp;
    }

    return res.status(200).json(responsePayload);
  } catch (error) {
    console.error("Forgot Password Error:", error);

    return res.status(500).json({
      success: false,
      message: "Server error",
    });
  }
};

const resetPassword = async (req, res) => {
  try {
    const { email, otp, newPassword } = req.body;

    if (
      !allStrings(email, otp, newPassword) ||
      !email.trim() ||
      !otp.trim() ||
      !newPassword
    ) {
      return res.status(400).json({
        success: false,
        message: "Email, OTP and new password are required",
      });
    }

    if (!isValidPassword(newPassword)) {
      return res.status(400).json({
        success: false,
        message: "Password must be 6-128 characters",
      });
    }

    const user = await User.findOne({
      email: email.toLowerCase().trim(),
    });

    if (
      !user ||
      !user.otpCode ||
      !user.otpExpiry ||
      user.otpExpiry < new Date()
    ) {
      return res.status(400).json({
        success: false,
        message: "Invalid or expired OTP",
      });
    }

    const otpHash = hashOtp(otp.trim());

    if (user.otpCode !== otpHash) {
      // Atomic increment so parallel guesses can't skip past the limit
      const updated = await User.findOneAndUpdate(
        { _id: user._id, otpCode: user.otpCode },
        { $inc: { otpAttempts: 1 } },
        { returnDocument: "after" }
      );

      if (updated && updated.otpAttempts >= MAX_OTP_ATTEMPTS) {
        await User.updateOne(
          { _id: user._id, otpCode: user.otpCode },
          { otpCode: "", otpExpiry: null, otpAttempts: 0 }
        );

        return res.status(429).json({
          success: false,
          message:
            "Too many incorrect attempts. Please request a new OTP",
        });
      }

      return res.status(400).json({
        success: false,
        message: "Invalid or expired OTP",
      });
    }

    const hashedPassword = await bcrypt.hash(newPassword, 10);
    const now = new Date();

    // Conditional atomic write: the OTP must still be current, unexpired and
    // under the attempt limit at write time, so a guess racing a lockout (or a
    // second request after a successful reset) cannot succeed on stale state.
    const reset = await User.findOneAndUpdate(
      {
        _id: user._id,
        otpCode: otpHash,
        otpExpiry: { $gt: now },
        otpAttempts: { $lt: MAX_OTP_ATTEMPTS },
      },
      {
        $set: {
          password: hashedPassword,
          passwordChangedAt: now,
          otpCode: "",
          otpExpiry: null,
          otpAttempts: 0,
        },
      }
    );

    if (!reset) {
      return res.status(400).json({
        success: false,
        message: "Invalid or expired OTP",
      });
    }

    return res.status(200).json({
      success: true,
      message: "Password reset successful",
    });
  } catch (error) {
    console.error("Reset Password Error:", error);

    return res.status(500).json({
      success: false,
      message: "Server error",
    });
  }
};
module.exports = {
  registerUser,
  loginUser,
  getProfile,
  updateProfile,
  forgotPassword,
  resetPassword,
};