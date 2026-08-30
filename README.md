# ZAWER Jewellery Platform

Monorepo containing the ZAWER Flutter mobile/web frontend and Express/MongoDB backend.

## Project Structure

- `zawer_backend/`: Node.js Express REST API containerized with Docker.
- `zawer_jewellery_app/`: Flutter mobile and web client.

---

## Quick Start (Docker)

To run the backend using Docker:

```bash
# Start backend service
docker compose up -d --build

# Check status
docker compose ps

# View logs
docker compose logs -f

# Stop backend service
docker compose down
```
