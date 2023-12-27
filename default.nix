with import <nixpkgs>{};
let TextVimColor = perl536Packages.buildPerlPackage {
    pname = "Text-VimColor";
    version = "0.29";
    src = fetchurl {
      url = "mirror://cpan/authors/id/R/RW/RWSTAUNER/Text-VimColor-0.29.tar.gz";
      sha256 = "e20d3202c888af3d082a2245db5e87ee774e96fcf6708a30530f2eeb1a90988e";
    };
    buildInputs = [ vim perl536Packages.FileShareDirInstall perl536Packages.TestFileShareDir ];
    propagatedBuildInputs = [ perl536Packages.FileShareDir perl536Packages.PathClass ];
    meta = {
      homepage = "https://github.com/rwstauner/Text-VimColor";
      description = "Syntax highlight text using Vim";
      license = with lib.licenses; [ artistic1 gpl1Plus ];
    };
  };
in pkgs.stdenv.mkDerivation rec {
  pname = "personal-wiki";
  version = "0.1.0";
  src = builtins.path { name = "personal-wiki"; path = ./.; };

  buildInputs = with pkgs; [
    ikiwiki

    vim
    graphviz
    git
    tzdata

    # teximg
    imagemagick
    texlive.combined.scheme-basic
    ghostscript

    discount

    perl536
    perl536Packages.syntax
    perl536Packages.PathClass
    perl536Packages.FileShare
    perl536Packages.TextMultiMarkdown
    perl536Packages.SortNaturally
    TextVimColor
  ];

  preCheck = ''
    export TZDIR=${tzdata}/share/zoneinfo
  '';

  buildPhase = ''
    # Actually build
    ikiwiki --gettime --setup ./ikiwiki.setup -v
  '';

  installPhase = ''
    mv www $out
  '';
}
