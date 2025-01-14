# Dart + Rust FFI Project

This project demonstrates how to integrate Rust with Dart using the Foreign Function Interface (FFI). The Rust code has to be compiled for the x86_64 architecture to ensure compatibility with the Globe runtime.

## Getting Started

Requirements

- Dart SDK
- Rust (with the [`cross`](https://github.com/cross-rs/cross) tool for cross-compilation)
- Globe CLI

## Project Structure

```
├── dart_project/ # Dart project source code
│ ├── bin/
│ │ └── server.dart # Entry point of the Dart application
│ ├── pubspec.yaml # Dart package configuration
├── native_hello/ # Rust source code for the library
│ ├── src/
│ │ └── lib.rs # Rust FFI implementation
│ ├── Cargo.toml # Rust package configuration
│ └── target/ # Directory for compiled Rust binaries
└── globe.yaml # Configuration for Globe
```

## Compiling the Rust Library

The Rust library needs to be compiled for the x86_64 architecture. We recommend using the cross tool for this purpose, which simplifies cross-compilation.

1. Install [`cross`](https://github.com/cross-rs/cross)

```sh
cargo install cross
```

2. Compile for `x86_64-unknown-linux-gnu`

Navigate to the rust_library directory and run:

```sh
cross build --release --target x86_64-unknown-linux-gnu
```

The compiled library will be located in:

```
native_hello/target/x86_64-unknown-linux-gnu/release/libnative_hello.so
```

3. Add the compiled library to the Dart project:

```yaml
assets:
  - native_hello/target/x86_64-unknown-linux-gnu/release/libnative_hello.so:static/libnative_hello.so
```

## Deployment

```sh
globe deploy
```
