const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: {
    rejectUnauthorized: false,
  },
});

// Successful connection log
pool.on("connect", () => {
  console.log("✅ Connected to Railway PostgreSQL");
});

// Hard failure log
pool.on("error", (err) => {
  console.error("❌ PostgreSQL Pool Error:", err);
  process.exit(1);
});

// Query helper
async function query(text, params) {
  const start = Date.now();
  try {
    const res = await pool.query(text, params);
    const duration = Date.now() - start;

    if (process.env.NODE_ENV !== "production") {
      console.log("Executed query", { text, duration, rows: res.rowCount });
    } else {
      console.log("Executed query", { duration, rows: res.rowCount });
    }

    return res;
  } catch (error) {
    console.error("❌ Database query error:", error);
    throw error;
  }
}

// Get pool client
async function getClient() {
  const client = await pool.connect();
  return client;
}

module.exports = {
  query,
  getClient,
  pool,
};
