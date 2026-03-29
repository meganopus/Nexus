# Backend build stage
FROM golang:1.24-alpine AS backend-builder

WORKDIR /app

# Install git for go mod download
RUN apk add --no-cache git

COPY go.mod ./

# Copy source code first so we can tidy
COPY . .

# Run tidy to generate go.sum and download deps
RUN go mod tidy

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o nexus-backend cmd/server/main.go

# Frontend build stage
FROM node:20-alpine AS ui-builder

WORKDIR /ui

COPY nexus-frontend/package*.json ./
RUN npm ci --legacy-peer-deps

COPY nexus-frontend/ ./
RUN npm run build

# Normalize Angular output to /out (works for dist/... or dist.../browser)
RUN mkdir -p /out && \
    if [ -d "dist/nexus-frontend/browser" ]; then \
        cp -a dist/nexus-frontend/browser/. /out/; \
    else \
        cp -a dist/nexus-frontend/. /out/; \
    fi

# Runtime stage: single URL via nginx reverse proxy to the Go backend
FROM nginx:alpine

RUN apk add --no-cache ca-certificates tini

WORKDIR /root

COPY nginx.single.conf /etc/nginx/conf.d/default.conf
COPY --from=backend-builder /app/nexus-backend /root/nexus-backend
COPY --from=ui-builder /out/ /usr/share/nginx/html

# Create uploads directory (mounted as a volume in production if you need persistence)
RUN mkdir -p /root/uploads

EXPOSE 80

ENTRYPOINT ["tini", "--"]
CMD ["sh", "-c", "/root/nexus-backend & exec nginx -g 'daemon off;'"]
