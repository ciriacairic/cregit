{ stdenv, fetchurl, autoPatchelfHook, libarchive, curl, libxml2, libxslt }:

stdenv.mkDerivation rec {
  pname = "srcml";
  version = "1.1.0";

  src = fetchurl {
    url = "https://github.com/srcML/srcML/releases/download/v${version}/srcml_${version}-1_ubuntu22.04_amd64.tar.gz";
    sha256 = "1maxb8yjdn0m5d55ysfix2j8mpyrzhj0493ci9657nm0c4ffpjyi";
  };

  # Tarball não tem diretório raiz, extrai em .
  sourceRoot = ".";

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [
    libarchive
    curl
    libxml2
    libxslt
    (stdenv.cc.cc.lib or stdenv.cc.cc)
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r bin lib share $out/
    runHook postInstall
  '';

  dontStrip = true;

  meta = {
    description = "Source-code XML toolkit used by the cregit pipeline";
    homepage = "https://www.srcml.org/";
    platforms = [ "x86_64-linux" ];
  };
}
