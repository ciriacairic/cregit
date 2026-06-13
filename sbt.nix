{ stdenv, fetchurl, makeWrapper, jdk8, bash }:

# sbt 0.13.18 is the last 0.13.x release. The cregit modules pin
# sbt.version=0.13.7 in project/build.properties; the 0.13.18 launcher
# downloads that version from Maven Central on first run. We need 0.13.18 for
# the launcher itself (newer versions break the sbt-onejar plugin).
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
