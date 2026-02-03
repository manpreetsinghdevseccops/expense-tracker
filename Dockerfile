# Multi-stage build for Angular + Express application
FROM node:18-alpine AS base

# Install dumb-init for proper signal handling
RUN apk add --no-cache dumb-init

# Create app directory and user
WORKDIR /app
RUN addgroup -g 1001 -S nodejs && \
    adduser -S angular -u 1001 -G nodejs

# Stage 1: Install dependencies
FROM base AS deps
WORKDIR /app

# Copy package files
COPY package*.json ./

# Use npm install instead of npm ci to handle lock file sync issues
RUN npm install && npm cache clean --force

# Stage 2: Build the application
FROM base AS build
WORKDIR /app

# Copy dependencies from deps stage
COPY --from=deps /app/node_modules ./node_modules

# Copy source code
COPY . .

# Build the Angular application
RUN npm run build -- --configuration=production --output-path=dist

# Stage 3: Production dependencies
FROM base AS prod-deps
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install only production dependencies, use install to avoid sync issues
RUN npm install --omit=dev && npm cache clean --force

# Stage 4: Production image
FROM base AS production

# Set NODE_ENV
ENV NODE_ENV=production
ENV PORT=4200

WORKDIR /app

# Copy production dependencies
COPY --from=prod-deps /app/node_modules ./node_modules

# Copy package files
COPY --from=prod-deps /app/package*.json ./

# Copy built application
COPY --from=build /app/dist ./dist

# Copy backend directory (check if it exists first)
COPY backend ./backend

# Copy other necessary files
COPY angular.json ./
COPY tsconfig*.json ./

# Change ownership to non-root user
RUN chown -R angular:nodejs /app

# Switch to non-root user
USER angular

# Expose port
EXPOSE 4200

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:4200/ || exit 1

# Use dumb-init to handle signals properly
ENTRYPOINT ["dumb-init", "--"]

# Start the application
CMD ["npm", "start"]