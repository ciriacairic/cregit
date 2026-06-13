{ lib, perlPackages, fetchurl }:

let
  # Email::Find declares Mail::Address and Email::Valid as runtime deps, but
  # Email::Find::addrspec (the only submodule HTML::FromText consumes) only
  # uses strict/vars/Exporter. We disable doCheck to avoid that cascade.
  EmailFind = perlPackages.buildPerlPackage {
    pname = "Email-Find";
    version = "0.10";
    src = fetchurl {
      url = "mirror://cpan/authors/id/M/MI/MIYAGAWA/Email-Find-0.10.tar.gz";
      sha256 = "03pjrkl58kfwwala8fw8x7293jnyxa8z333pvgcai96ys03s1ai9";
    };
    doCheck = false;
    meta = {
      description = "Find RFC 822 email addresses in plain text";
      license = with lib.licenses; [ artistic1 gpl1Plus ];
    };
  };

  HTMLFromText = perlPackages.buildPerlPackage {
    pname = "HTML-FromText";
    version = "2.07";
    src = fetchurl {
      url = "mirror://cpan/authors/id/R/RJ/RJBS/HTML-FromText-2.07.tar.gz";
      sha256 = "1b93zria8is1kcanwaldyzjcijqcsgrbasvlnmzp1gh584r11q65";
    };
    propagatedBuildInputs = [
      EmailFind
      perlPackages.HTMLParser  # provides HTML::Entities
    ];
    doCheck = false;
    meta = {
      description = "Converts plain text to HTML";
      license = with lib.licenses; [ artistic1 gpl1Plus ];
    };
  };
in {
  inherit HTMLFromText EmailFind;
}
