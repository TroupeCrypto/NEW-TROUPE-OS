const express = require("express");
const db = require("./db");

// Initialize Express app
const app = express();

// ✅ REQUIRED: Railway-safe port + interface binding
const PORT = process.env.PORT || 8080;

// Middleware
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Request logging middleware
app.use((req, res, next) => {
  console.log(`${new Date().toISOString()} - ${req.method} ${req.path}`);
  next();
});

// ✅ Health check endpoint
app.get("/health", async (req, res) => {
  try {
    const result = await db.query("SELECT NOW()");
    res.json({
      status: "healthy",
      timestamp: new Date().toISOString(),
      database: "connected",
      databaseTime: result.rows[0].now,
    });
  } catch (error) {
    res.status(503).json({
      status: "unhealthy",
      timestamp: new Date().toISOString(),
      database: "disconnected",
      error: error.message,
    });
  }
});

// Root endpoint
app.get("/", (req, res) => {
  res.json({
    name: "TROUPE-OS API",
    version: "1.0.0",
    description: "Railway-first API-only Node.js platform",
    endpoints: {
      health: "/health",
      api: "/api",
    },
  });
});

// API placeholder
app.get("/api", (req, res) => {
  res.json({
    message: "API endpoint",
    version: "1.0.0",
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    error: "Not Found",
    message: `Route ${req.method} ${req.path} not found`,
    timestamp: new Date().toISOString(),
  });
});

// Global error handler
app.use((err, req, res, next) => {
  console.error("❌ Express Error:", err);
  res.status(err.status || 500).json({
    error: err.message || "Internal Server Error",
    timestamp: new Date().toISOString(),
  });
});

// ✅ START SERVER — THIS WAS THE FINAL CRASH FIX
const server = app.listen(PORT, "0.0.0.0", () => {
  console.log(`✅ TROUPE-OS API server running on port ${PORT}`);
  console.log(`✅ Environment: ${process.env.NODE_ENV || "development"}`);
  console.log(
    `✅ Database URL configured: ${process.env.DATABASE_URL ? "Yes" : "No"}`
  );
});

// ✅ Graceful shutdown (Railway sends SIGTERM on redeploy)
process.on("SIGTERM", () => {
  console.log("⚠️ SIGTERM received — shutting down safely...");

  server.close(() => {
    console.log("✅ HTTP server closed");

    db.pool.end(() => {
      console.log("✅ Database pool closed");
      process.exit(0);
    });
  });
});
