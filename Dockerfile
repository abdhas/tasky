# Build the binary of the App
FROM golang:1.19 AS build

WORKDIR /go/src/tasky
COPY . .
RUN go mod download
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /go/src/tasky/tasky

# Final Release Image with Bash and kubectl Installed
FROM alpine:3.17.0 as release

# Install bash, curl, and kubectl
RUN apk add --no-cache bash curl && \
    curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && mv kubectl /usr/local/bin/

WORKDIR /app
COPY --from=build /go/src/tasky/tasky .
COPY --from=build /go/src/tasky/assets ./assets

EXPOSE 8080
ENTRYPOINT ["/app/tasky"]
