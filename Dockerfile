# syntax=docker/dockerfile:1

# 1.82 is what the repo's rust-toolchain file pins; a different base makes rustup
# download a second toolchain on every build.
FROM rust:1.82-bookworm AS builder

# fastcrypto and the three sui crates are git dependencies of monorepo size.
# Cargo's bundled libgit2 fetches them far slower than git and fails on them
# intermittently.
ENV CARGO_NET_GIT_FETCH_WITH_CLI=true

WORKDIR /build

# Build the dependency graph against stub sources first, so this layer is keyed
# on Cargo.lock alone and a source-only change does not recompile sui-types.
COPY Cargo.toml Cargo.lock rust-toolchain ./
COPY .cargo ./.cargo
RUN mkdir -p src \
 && echo 'fn main() {}' > src/main.rs \
 && touch src/lib.rs \
 && cargo build --release --locked \
 && rm -rf src

COPY src ./src
# COPY carries the build context's mtimes, which are older than the stub objects
# just compiled, so cargo would consider the crate fresh and skip it.
RUN touch src/main.rs src/lib.rs \
 && cargo build --release --locked --bin zklogin-verifier

# cc-debian12 carries glibc, libgcc and the CA bundle — enough for the crates that
# compile C (ring, secp256k1-sys, zstd-sys) — with no shell and no package manager.
FROM gcr.io/distroless/cc-debian12:nonroot

COPY --from=builder /build/target/release/zklogin-verifier /usr/local/bin/zklogin-verifier

# src/main.rs binds 0.0.0.0:3000 unconditionally; there is no env var to move it.
EXPOSE 3000

USER nonroot
ENTRYPOINT ["/usr/local/bin/zklogin-verifier"]
