# Commy Cloud — one static binary. Built inside Docker so the server needs
# nothing but Docker; the state lives in the /data volume.
FROM golang:1.24-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go test ./... && \
    CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/commy-cloud ./cmd/commy-cloud

FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata && \
    adduser -D -H -u 10001 cloud && mkdir /data && chown cloud:cloud /data
COPY --from=build /out/commy-cloud /usr/local/bin/commy-cloud
USER cloud
ENV COMMY_CLOUD_DATA=/data/cloud.json COMMY_CLOUD_ADDR=:8080
VOLUME /data
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1
ENTRYPOINT ["commy-cloud"]
CMD ["serve"]
