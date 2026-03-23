# Multi-stage build for ssbc/go-ssb-room
# Stage 1: Build
FROM golang:1.22-alpine AS builder

RUN apk add --no-cache git ca-certificates

WORKDIR /build

# Clone ssbc/go-ssb-room at a known-good tag
ARG GO_SSB_ROOM_TAG=v1.3.1
RUN git clone --depth 1 --branch ${GO_SSB_ROOM_TAG} \
    https://github.com/ssbc/go-ssb-room.git . \
    || git clone --depth 1 https://github.com/ssbc/go-ssb-room.git .

# Build the room server binary
RUN go mod download
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" \
    -o /go-ssb-room ./cmd/server

# Stage 2: Runtime
FROM alpine:3.19

RUN apk add --no-cache ca-certificates tzdata

# Create data directory and non-root user
RUN addgroup -S ssb && adduser -S -G ssb ssb
RUN mkdir -p /data && chown ssb:ssb /data

COPY --from=builder /go-ssb-room /usr/local/bin/go-ssb-room

USER ssb
WORKDIR /data

EXPOSE 8008 3000

ENTRYPOINT ["/usr/local/bin/go-ssb-room"]
CMD ["-repo", "/data", "-lishttp", ":3000", "-lismux", ":8008", "-mode", "open"]
