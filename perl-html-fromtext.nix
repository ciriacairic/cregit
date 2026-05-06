{ lib, perlPackages, fetchurl }:

let
  # Email::Find declara Mail::Address e Email::Valid como runtime deps, mas
  # Email::Find::addrspec (o único submódulo que HTML::FromText consome)
  # só usa strict/vars/Exporter. Desligamos doCheck para evitar a cascata.
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
      perlPackages.HTMLParser  # provê HTML::Entities
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
