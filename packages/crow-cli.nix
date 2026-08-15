{ lib, stdenvNoCC, fetchurl }:

let
  version = "6.5.0";
  sources = {
    "x86_64-linux" = {
      arch = "amd64";
      hash = "sha256-xRuUNvtxh7O9J7UHqkpgbWrxvNcy7+r5EHaMlkeCmmc=";
    };
    "aarch64-linux" = {
      arch = "arm64";
      hash = "sha256-DGS/vtQgFp2Y24q2fx8EIO2PpR2jnux7LDPYNNOZooA=";
    };
  };
  source = sources.${stdenvNoCC.hostPlatform.system} or
    (throw "crow-cli: unsupported system ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "crow-cli";
  inherit version;

  src = fetchurl {
    url = "https://codefloe.com/crowci/crow/releases/download/v${version}/crow-cli_linux_${source.arch}.tar.gz";
    inherit (source) hash;
  };

  # Upstream's archive contains the single `crow` executable at its root, not
  # a directory for the generic unpacker to select as sourceRoot.
  unpackPhase = ''
    runHook preUnpack
    tar -xzf "$src"
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    install -Dm0555 crow "$out/bin/crow"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test "$("$out/bin/crow" --version)" = "crow version ${version}"
    runHook postInstallCheck
  '';

  meta = {
    description = "Command-line client for Crow CI";
    homepage = "https://crowci.dev";
    license = lib.licenses.asl20;
    mainProgram = "crow";
    platforms = builtins.attrNames sources;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
