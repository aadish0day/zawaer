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

### 2. Start the Backend Container
```bash
docker compose up -d --build
```
The server will be available at `http://localhost:5000`.

### 3. Optional: Run with Local MongoDB
If you prefer running a local MongoDB instance in a container instead of MongoDB Atlas:
```bash
docker compose --profile local-db up -d
```

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
