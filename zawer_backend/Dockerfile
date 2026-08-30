# Use official Node.js LTS lightweight image
FROM node:20-alpine

# Set working directory
WORKDIR /usr/src/app

# Install dependencies first for optimal layer caching
COPY package*.json ./

RUN npm ci --omit=dev --ignore-scripts

# Copy application source code
COPY . .

# Set environment variables
ENV NODE_ENV=production \
    PORT=5000

# Use non-root node user for enhanced security
USER node

# Expose backend service port
EXPOSE 5000

# Health check to ensure the service is running and responsive
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD node -e "fetch('http://localhost:' + (process.env.PORT || 5000) + '/').then(r => r.ok ? process.exit(0) : process.exit(1)).catch(() => process.exit(1))"

# Start the application
CMD ["node", "server.js"]
