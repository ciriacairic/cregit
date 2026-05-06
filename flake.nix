{
  description = "cregit dev shell (Etapa 2.1 — baseline com srcml e HTML::FromText)";

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

          # Etapa 5: variáveis de ambiente do BFG.
          # CREGIT_ROOT precisa apontar pro diretório que contém ./cregit/ —
          # tipicamente o pai do cregit-nix. Tenta autodetectar a partir do
          # PWD; se não achar ./cregit, sobe um nível (caso comum: rodar
          # `nix develop` de dentro do cregit-nix). Se ainda assim falhar,
          # avisa em vez de silenciosamente exportar um caminho quebrado —
          # BFG aceita um BFG_TOKENIZE_CMD inválido sem erro e devolve o blob
          # original, o que arruina a tokenização do repo inteiro.
          if [ -z "''${CREGIT_ROOT:-}" ]; then
            if [ -d "$PWD/cregit" ]; then
              CREGIT_ROOT="$PWD"
            elif [ -d "$PWD/../cregit" ]; then
              CREGIT_ROOT="$(cd "$PWD/.." && pwd)"
            else
              echo "  [aviso] não consegui localizar ./cregit — exporte CREGIT_ROOT manualmente."
              CREGIT_ROOT="$PWD"
            fi
          fi
          export CREGIT_ROOT
          export BFG_MEMO_DIR="''${BFG_MEMO_DIR:-$HOME/.cache/cregit-bfg-memo}"
          # Aponta para o dispatcher tokenize.pl em vez do tokenizeSrcMl.pl
          # direto, pra suportar linguagens fora do srcML (ex.: Rust). As flags
          # srcml/srcml2token/ctags são encaminhadas pelo dispatcher só pra
          # parsers srcML — para outros parsers são silenciosamente ignoradas.
          export BFG_TOKENIZE_CMD="$CREGIT_ROOT/cregit/tokenize/tokenize.pl \
            --srcml2token=$CREGIT_ROOT/cregit/tokenize/srcMLtoken/srcml2token \
            --srcml=${srcml}/bin/srcml \
            --ctags=${pkgs.universal-ctags}/bin/ctags"
          mkdir -p "$BFG_MEMO_DIR"

          echo "cregit dev shell pronto:"
          echo "  JDK       = $(java -version 2>&1 | head -1)"
          echo "  sbt       = 0.13.18 (launcher; bootstrapa a versão pinada no primeiro run)"
          echo "  srcml     = $(srcml --version 2>/dev/null | head -1)"
          echo "  ctags     = $(ctags --version | head -1)"
          echo "  CREGIT_ROOT   = $CREGIT_ROOT"
          echo "  BFG_MEMO_DIR  = $BFG_MEMO_DIR"
          if [ ! -x "$CREGIT_ROOT/cregit/tokenize/tokenize.pl" ]; then
            echo "  [ERRO] $CREGIT_ROOT/cregit/tokenize/tokenize.pl não existe — BFG não vai conseguir tokenizar nada."
            echo "         Reabra o shell com CREGIT_ROOT apontando pro diretório que contém ./cregit/."
          fi
          if [ ! -x "$CREGIT_ROOT/cregit/tokenize/srcMLtoken/srcml2token" ]; then
            echo "  [aviso] srcml2token ainda não foi compilado. Rode: (cd cregit/tokenize/srcMLtoken && make)"
          fi
        '';
      };
    };
}
