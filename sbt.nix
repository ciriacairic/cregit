{ stdenv, fetchurl, makeWrapper, jdk8, bash }:

# sbt 0.13.18 é o último release 0.13.x. Os módulos do cregit pinam
# sbt.version=0.13.7 em project/build.properties; o launcher 0.13.18 baixa
# essa versão de Maven Central no primeiro run. Precisamos do 0.13.18 pro
# próprio launcher (versões mais recentes quebram o plugin sbt-onejar).
stdenv.mkDerivation rec {
  pname = "sbt";
  version = "0.13.18";

  src = fetchurl {
    url = "https://github.com/sbt/sbt/releases/download/v${version}/sbt-${version}.tgz";
    sha256 = "0cdkhcys0wj0h5430m3zb8z6rp5pbr8yph8gw7qycqwfr8i27s5g";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/sbt $out/bin
    cp -r bin conf lib $out/share/sbt/
    makeWrapper ${bash}/bin/bash $out/bin/sbt \
      --set JAVA_HOME "${jdk8}" \
      --add-flags "$out/share/sbt/bin/sbt"
    runHook postInstall
  '';

  meta = {
    description = "Scala Build Tool, pinned to 0.13.18 for the cregit sbt-onejar plugin";
    homepage = "https://www.scala-sbt.org/";
    platforms = [ "x86_64-linux" ];
  };
}
