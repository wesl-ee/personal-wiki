with import <nixpkgs>{};
let TextVimColor = perl534Packages.buildPerlPackage {
    pname = "Text-VimColor";
    version = "0.29";
    src = fetchurl {
      url = "mirror://cpan/authors/id/R/RW/RWSTAUNER/Text-VimColor-0.29.tar.gz";
      sha256 = "e20d3202c888af3d082a2245db5e87ee774e96fcf6708a30530f2eeb1a90988e";
    };
    buildInputs = [ vim perl534Packages.FileShareDirInstall perl534Packages.TestFileShareDir ];
    propagatedBuildInputs = [ perl534Packages.FileShareDir perl534Packages.PathClass ];
    meta = {
      homepage = "https://github.com/rwstauner/Text-VimColor";
      description = "Syntax highlight text using Vim";
      license = with lib.licenses; [ artistic1 gpl1Plus ];
    };
  };
in pkgs.mkShell rec {
  buildInputs = with pkgs; [
    ikiwiki

    vim
    graphviz

    # teximg
    imagemagick
    texlive.combined.scheme-basic
    ghostscript

    git-lfs
    discount

    perl
    perl534Packages.syntax
    perl534Packages.PathClass
    perl534Packages.FileShare
    perl534Packages.SortNaturally
    TextVimColor
  ];
}
