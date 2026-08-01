# Stage 1: Build the static binary
FROM gcc:latest AS builder
COPY hello.c .
# The build flags ensure the binary contains all its dependencies internally
RUN gcc -static -o hello hello.c

# Stage 2: Create the final microscopic image
FROM scratch
COPY --from=builder /hello /hello
CMD ["/hello"]
