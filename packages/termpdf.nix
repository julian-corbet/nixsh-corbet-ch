{ lib
, stdenv
, fetchFromGitHub
, makeWrapper
, bash
, bc
, coreutils
, cups
, curl
, djvulibre
, file
, findutils
, gawk
, ghostscript
, gnugrep
, gnused
, gnutar
, imagemagick
, kitty
, less
, libsixel
, libtiff
, ncurses
, pdfgrep
, poppler-utils
, procps
, unzip
, util-linux
, xdg-utils
,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "termpdf";
  version = "0-unstable-2022-05-02";

  src = fetchFromGitHub {
    owner = "dsanson";
    repo = "termpdf";
    rev = "671f3a27f22eea608b7b3c0068a2c94e1e4ffbe3";
    hash = "sha256-SnLpF40wIIU7pN2YHO4IczL3fVCrMI9LlfegvWZpBgI=";
  };

  terminalDimensionsSrc = fetchFromGitHub {
    owner = "dsanson";
    repo = "terminal_dimensions";
    rev = "8e34b6fc888c5272bdee84a7aacee4be12145726";
    hash = "sha256-FqWt6nDTwOsZ3TNK8fa2ODDxMDOqGPbBexVFhr3SXGc=";
  };

  nativeBuildInputs = [ makeWrapper ];

  # wrapProgram moves each script behind a hidden `.wrapped` path. Upstream prints basename $0 in
  # help output, which would otherwise leak that implementation detail as `.termpdf-wrapped`.
  postPatch = ''
    substituteInPlace termpdf --replace-fail '$(basename $0)' 'termpdf'
    substituteInPlace tpdfc --replace-fail '$(basename $0)' 'tpdfc'
  '';

  buildPhase = ''
    runHook preBuild
    $CC -O2 "$terminalDimensionsSrc/terminal_dimensions.c" -o terminal_dimensions
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm0555 termpdf tpdfc terminal_dimensions -t "$out/bin"
    runHook postInstall
  '';

  postFixup = ''
    runtime_path=${lib.makeBinPath [
      bash
      bc
      coreutils
      cups
      curl
      djvulibre
      file
      findutils
      gawk
      ghostscript
      gnugrep
      gnused
      gnutar
      imagemagick
      kitty
      less
      libsixel
      libtiff
      ncurses
      pdfgrep
      poppler-utils
      procps
      unzip
      util-linux
      xdg-utils
    ]}:$out/bin

    wrapProgram "$out/bin/termpdf" --prefix PATH : "$runtime_path"
    wrapProgram "$out/bin/tpdfc" --prefix PATH : "$runtime_path"
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/termpdf" --help | grep -F "termpdf <options>"
    "$out/bin/tpdfc" --help | grep -F "tpdfc <option> <termpdf command>"
    test "$("$out/bin/terminal_dimensions" | awk '{ print NF }')" -eq 4
    runHook postInstallCheck
  '';

  meta = {
    description = "Graphical PDF and image viewer for Kitty, iTerm2, and Sixel terminals";
    homepage = "https://github.com/dsanson/termpdf";
    license = lib.licenses.mit;
    mainProgram = "termpdf";
    platforms = lib.platforms.unix;
  };
})
