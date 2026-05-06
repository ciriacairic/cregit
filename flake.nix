{
  description = "cregit reproducible dev shell (srcML, sbt 0.13.18, Perl modules)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      srcml = pkgs.callPackage ./srcml.nix { };

      sbt013 = pkgs.callPackage ./sbt.nix { inherit (pkgs) jdk8; };

      perlExtras = pkgs.callPackage ./perl-html-fromtext.nix { };

      perlWithMods = pkgs.perl.withPackages (p: with p; [
        DBI
        DBDSQLite
        SetScalar
        perlExtras.HTMLFromText
      ]);
    in {
      packages.${system} = {
        inherit srcml sbt013;
        inherit (perlExtras) HTMLFromText EmailFind;
      };

      devShells.${system}.default = pkgs.mkShell {
        name = "cregit-dev";

        packages = [
          pkgs.jdk8
          sbt013
          srcml
          pkgs.universal-ctags
          pkgs.xercesc
          pkgs.sqlite
          perlWithMods
        ];

        shellHook = ''
          export JAVA_HOME="${pkgs.jdk8}/lib/openjdk"

          # BFG environment variables.
          # CREGIT_ROOT must point at the directory that contains ./cregit/.
          # Autodetect it from PWD; if ./cregit is not there, go up one level
          # (common case: running `nix develop` from a sibling directory). If
          # it still cannot be found, warn instead of silently exporting a
          # broken path -- BFG accepts an invalid BFG_TOKENIZE_CMD without an
          # error and returns the original blob, which ruins tokenization of
          # the whole repository.
          if [ -z "''${CREGIT_ROOT:-}" ]; then
            if [ -d "$PWD/cregit" ]; then
              CREGIT_ROOT="$PWD"
            elif [ -d "$PWD/../cregit" ]; then
              CREGIT_ROOT="$(cd "$PWD/.." && pwd)"
            else
              echo "  [warn] could not locate ./cregit -- set CREGIT_ROOT manually."
              CREGIT_ROOT="$PWD"
            fi
          fi
          export CREGIT_ROOT
          export BFG_MEMO_DIR="''${BFG_MEMO_DIR:-$HOME/.cache/cregit-bfg-memo}"
          # Point at the tokenize.pl dispatcher rather than tokenizeSrcMl.pl
          # directly, so languages outside srcML (e.g. Rust) are supported. The
          # srcml/srcml2token/ctags flags are forwarded by the dispatcher only
          # to srcML parsers; for other parsers they are silently ignored.
          export BFG_TOKENIZE_CMD="$CREGIT_ROOT/cregit/tokenize/tokenize.pl \
            --srcml2token=$CREGIT_ROOT/cregit/tokenize/srcMLtoken/srcml2token \
            --srcml=${srcml}/bin/srcml \
            --ctags=${pkgs.universal-ctags}/bin/ctags"
          mkdir -p "$BFG_MEMO_DIR"

          echo "cregit dev shell ready:"
          echo "  JDK       = $(java -version 2>&1 | head -1)"
          echo "  sbt       = 0.13.18 (launcher; bootstraps the pinned version on first run)"
          echo "  srcml     = $(srcml --version 2>/dev/null | head -1)"
          echo "  ctags     = $(ctags --version | head -1)"
          echo "  CREGIT_ROOT   = $CREGIT_ROOT"
          echo "  BFG_MEMO_DIR  = $BFG_MEMO_DIR"
          if [ ! -x "$CREGIT_ROOT/cregit/tokenize/tokenize.pl" ]; then
            echo "  [ERROR] $CREGIT_ROOT/cregit/tokenize/tokenize.pl not found -- BFG will not be able to tokenize anything."
            echo "          Reopen the shell with CREGIT_ROOT pointing to the directory that contains ./cregit/."
          fi
          if [ ! -x "$CREGIT_ROOT/cregit/tokenize/srcMLtoken/srcml2token" ]; then
            echo "  [warn] srcml2token has not been compiled yet. Run: (cd cregit/tokenize/srcMLtoken && make)"
          fi
        '';
      };
    };
}
