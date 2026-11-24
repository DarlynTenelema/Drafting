# Multi-stage Dockerfile portátil (funciona igual en Railway, Fly.io, VPS o Bare Metal)
FROM golang:1.26-alpine AS builder

WORKDIR /app
RUN apk add --no-cache ca-certificates git

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o /app/api ./cmd/api

FROM alpine:3.21
RUN apk add --no-cache ca-certificates tzdata ffmpeg
WORKDIR /app

COPY --from=builder /app/api /app/api
RUN mkdir -p /app/uploads/reels

EXPOSE 8080
CMD ["/app/api"]
