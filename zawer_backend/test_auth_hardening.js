// Auth hardening checks over HTTP. Needs a running server started with
// NODE_ENV=development (so forgot-password returns devOtp) and a throwaway DB:
//   MONGO_URI=mongodb://127.0.0.1:27099/zawer_auth_test PORT=5101 \
//   JWT_SECRET=<48-byte hex> NODE_ENV=development node server.js
//   node test_auth_hardening.js            # BASE_URL defaults to http://127.0.0.1:5101
// Note: each run uses ~7 reset-password calls; the limiter allows 20 / 15 min per IP.
const assert = require("assert");
const { spawnSync } = require("child_process");

const BASE_URL = process.env.BASE_URL || "http://127.0.0.1:5101";

const call = async (method, path, body, token) => {
  const res = await fetch(BASE_URL + path, {
    method,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, data: await res.json() };
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const main = async () => {
  const email = `auth_test_${Date.now()}@example.com`;
  const password = "oldpass123";

  let r = await call("POST", "/api/auth/register", { name: "Auth Test", email, password });
  assert.strictEqual(r.status, 201, "register");

  r = await call("POST", "/api/auth/login", { email, password });
  assert.strictEqual(r.status, 200, "login");
  assert.strictEqual(r.data.user.role, "user", "login returns role");
  const oldToken = r.data.token;

  r = await call("GET", "/api/auth/profile", null, oldToken);
  assert.strictEqual(r.status, 200, "profile");
  assert.strictEqual(r.data.user.role, "user", "profile returns role");

  // Unknown and known emails get the identical response (devOtp aside)
  const unknown = await call("POST", "/api/auth/forgot-password", { email: `nobody_${Date.now()}@example.com` });
  assert.strictEqual(unknown.status, 200, "forgot unknown = 200");
  assert.strictEqual(unknown.data.devOtp, undefined, "no OTP for unknown email");
  r = await call("POST", "/api/auth/forgot-password", { email });
  assert.strictEqual(r.status, 200, "forgot known = 200");
  assert.strictEqual(r.data.message, unknown.data.message, "same message either way");
  assert.ok(r.data.devOtp, "devOtp present (server must run with NODE_ENV=development)");
  const lockedOtp = r.data.devOtp;
  const wrong = lockedOtp === "123456" ? "654321" : "123456";

  for (let i = 1; i <= 5; i++) {
    r = await call("POST", "/api/auth/reset-password", { email, otp: wrong, newPassword: "newpass123" });
    assert.strictEqual(r.status, i < 5 ? 400 : 429, `wrong attempt ${i}`);
  }
  r = await call("POST", "/api/auth/reset-password", { email, otp: lockedOtp, newPassword: "newpass123" });
  assert.strictEqual(r.status, 400, "correct OTP rejected after lockout");

  // iat has 1s resolution; make sure the reset lands in a later second than the old token
  await sleep(1100);

  r = await call("POST", "/api/auth/forgot-password", { email });
  r = await call("POST", "/api/auth/reset-password", { email, otp: r.data.devOtp, newPassword: "newpass123" });
  assert.strictEqual(r.status, 200, "reset with fresh OTP");

  r = await call("GET", "/api/auth/profile", null, oldToken);
  assert.strictEqual(r.status, 401, "old token rejected after reset");

  r = await call("POST", "/api/auth/login", { email, password: "newpass123" });
  assert.strictEqual(r.status, 200, "login with new password");
  r = await call("GET", "/api/auth/profile", null, r.data.token);
  assert.strictEqual(r.status, 200, "new token works right after reset");

  // Weak / public JWT secrets must stop the server before it connects anywhere
  for (const secret of ["zawer_secret_key_change_in_production", "short", ""]) {
    const run = spawnSync(process.execPath, ["server.js"], {
      cwd: __dirname,
      env: { ...process.env, JWT_SECRET: secret, MONGO_URI: "mongodb://127.0.0.1:1/never", PORT: "0" },
      timeout: 10000,
    });
    assert.strictEqual(run.status, 1, `server refuses JWT_SECRET=${JSON.stringify(secret)}`);
  }

  console.log("All auth hardening checks passed");
};

main().catch((err) => {
  console.error("FAILED:", err.message);
  process.exit(1);
});
