require("dotenv").config();

const mongoose = require("mongoose");
const app = require("./app");
const connectDB = require("./config/db");

const PORT = process.env.PORT || 5000;

let server;

const JWT_SECRET = process.env.JWT_SECRET || "";

const GENERATE_HINT =
  "Generate one with: node -e \"console.log(require('crypto').randomBytes(48).toString('hex'))\"";

// Missing or the published example value: anyone could forge tokens, so refuse to start.
if (!JWT_SECRET || JWT_SECRET === "zawer_secret_key_change_in_production") {
  console.error("JWT_SECRET is missing or the public example value. " + GENERATE_HINT);
  process.exit(1);
}

// Short secrets are easier to guess: allowed, but warned about on every start.
if (JWT_SECRET.length < 32) {
  console.warn(
    `WARNING: JWT_SECRET is only ${JWT_SECRET.length} characters; 32+ random characters is recommended. ` +
      GENERATE_HINT
  );
}

const startServer = async () => {
  try {
    await connectDB();
    server = app.listen(PORT, () => {
      console.log(`ZAWER Backend running on port ${PORT}`);
    });
  } catch (error) {
    console.error("Failed to start server:", error);
    process.exit(1);
  }
};

const gracefulShutdown = (signal) => {
  console.log(`Received ${signal}. Shutting down gracefully...`);
  if (server) {
    server.close(async () => {
      console.log("HTTP server closed.");
      try {
        await mongoose.connection.close(false);
        console.log("MongoDB connection closed.");
      } catch (err) {
        console.error("Error closing MongoDB connection:", err);
      }
      process.exit(0);
    });
  } else {
    process.exit(0);
  }
};

process.on("SIGINT", () => gracefulShutdown("SIGINT"));
process.on("SIGTERM", () => gracefulShutdown("SIGTERM"));
process.on("unhandledRejection", (reason, promise) => {
  console.error("Unhandled Rejection at:", promise, "reason:", reason);
  if (server) {
    server.close(() => process.exit(1));
  } else {
    process.exit(1);
  }
});

startServer();