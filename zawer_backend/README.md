# ZAWER Jewellery Backend

RESTful backend API for the ZAWER Jewellery application built with Express and MongoDB.

## Features

- **Authentication**: JWT-based authentication with bcrypt password hashing and OTP-based reset.
- **Products**: Catalog listing, search, details, and customer reviews.
- **Cart & Wishlist**: User-specific cart management and wishlist.
- **Orders**: Checkout and order history tracking.

---

## Running with Docker (Recommended)

### 1. Configure Environment
Ensure `.env` exists (copy from `.env.example` if needed):
```bash
cp .env.example .env
```
Then set `JWT_SECRET` to a random value of at least 32 characters; the server refuses to start otherwise:
```bash
node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"
```
`NODE_ENV=development` (the example default) returns password-reset OTPs in the API response and logs them. Never use it in production.

Behind a reverse proxy or load balancer, set `TRUST_PROXY` so the auth rate limiter sees the real client IP instead of the proxy's: a hop count (e.g. `1` for a single proxy) or a comma-separated list of trusted proxy IPs/subnets (e.g. `loopback, 10.0.0.0/8`). Leave it unset when clients connect directly, otherwise they can spoof `X-Forwarded-For`. IPv6 clients are rate-limited per /64 prefix.

### 2. Start the Backend Container
```bash
docker compose up -d --build
```
The server will be available at `http://localhost:5000`.

### 3. Optional: Run with Local MongoDB
If you prefer running a local MongoDB instance in a container instead of MongoDB Atlas, start the `backend-local` service (it starts `mongo` too and uses `mongodb://mongo:27017/zawer`, ignoring `MONGO_URI` from `.env`):
```bash
docker compose up -d --build backend-local
```
Run either `backend` or `backend-local`, not both: they share host port 5000.

### 4. Stop Containers
```bash
docker compose down
```

---

## Running Locally without Docker

```bash
# Install dependencies
npm install

# Start server
npm start

# Development mode (with nodemon)
npm run dev
```
