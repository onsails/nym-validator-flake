{
  inputs = {
    utils.url = github:numtide/flake-utils;
    nixpkgs-unstable.url = github:NixOS/nixpkgs/nixpkgs-unstable;
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, utils }: utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs-unstable {
        inherit system;
      };
    in
    with pkgs;
    let
      version = "0.14.1";
      src = fetchFromGitHub {
        owner = "CosmWasm";
        repo = "wasmd";
        rev = "v${version}";
        sha256 = "sha256-ejiNkeme0WJc0x2FfuM+9w3jyw/1Zjy/yVJuS4+7KQE=";
      };
    in
    {
      # https://nymtech.net/docs/run-nym-nodes/validators/
      packages.nymd = pkgs.buildGoModule
        rec {
          name = "nymd";
          inherit version src;

          WASMD_VERSION = "v${version}";
          BECH32_PREFIX = "hal";

          subPackages = [ "cmd/wasmd" ];

          buildFlags = [ "-tags netgo" "-tags ledger" ];

          preBuild = ''
            mkdir -p $out/lib
            cp vendor/github.com/CosmWasm/wasmvm/api/libwasmvm.so $out/lib

            # speakeasy hardcodes /bin/stty https://github.com/bgentry/speakeasy/issues/22
            substituteInPlace vendor/github.com/bgentry/speakeasy/speakeasy_unix.go \
              --replace "/bin/stty" "${coreutils}/bin/stty"
          '';

          preFixup = ''
            patchelf --set-rpath "$out/lib" $out/bin/wasmd
            mv $out/bin/wasmd $out/bin/nymd
          '';

          buildFlagsArray =
            let
              ldflagsX = [
                "github.com/cosmos/cosmos-sdk/version.Name=nymd"
                "github.com/cosmos/cosmos-sdk/version.AppName=nymd"
                "github.com/CosmWasm/wasmd/app.NodeDir=.nymd"
                "github.com/cosmos/cosmos-sdk/version.Version=${WASMD_VERSION}"
                "github.com/cosmos/cosmos-sdk/version.Commit=${src.rev}"
                "github.com/CosmWasm/wasmd/app.Bech32Prefix=${BECH32_PREFIX}"
                "github.com/cosmos/cosmos-sdk/version.BuildTags=netgo,ledger'"
              ];
            in
            "-ldflags=${lib.concatMapStringsSep " " (f: "-X ${f}") ldflagsX}";

          runVend = true;

          vendorSha256 = "1cjgq0nqv9f91gx81s5v5riwr89ri9hy9fcv7dm5l7pkw9srr3lq";

          meta.platforms = [ "x86_64-linux" ];
        };
    });
}
