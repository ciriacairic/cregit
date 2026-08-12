# rustTokenizer

## Introduction

rustTokenizer transcodes a Rust source file into the tokenized view consumed by
cregit (blameRepo / prettyPrint) — the same line:col token stream produced by
`srcml2token` and the Go tokenizer. It adds Rust (`.rs`) support to the pipeline.

Unlike the C/C++/Java path it does not go through srcML (which has no Rust
grammar). It lexes directly with `ra-ap-rustc_lexer`, rust-analyzer's maintained
snapshot of the lexer used by the Rust compiler, so it tolerates syntactically
invalid input — intermediate states in a repository's history still tokenize.

## Requirements

- A Rust toolchain (`cargo`); rustup recommended.

## How to build

```sh
make          # cargo build --release -> target/release/rust_tokenizer
```

## How to use

It reads a single `.rs` file given as an argument and writes the token stream to
stdout.

```sh
rust_tokenizer <filename>.rs
```

In the pipeline it is invoked through `tokenize/tokenize.pl`, which maps `.rs` to
this tokenizer.

## Tests

```sh
make test     # cargo test
```

## Output format

A line-oriented, TAB-separated stream:

```
-:-	begin_unit|revision:0.0.1;language:Rust;cregit-version:0.0.1
LINE:COL	kind|value
-:-	end_unit
```

Positions are 1-indexed and count code points (not bytes). Punctuation is emitted
as `op|<lexeme>`; all literal subkinds collapse to `literal|`; newlines inside
literals and comments are folded to spaces.

## License

Depends on `ra-ap-rustc_lexer` and `phf` (both MIT / Apache-2.0).
