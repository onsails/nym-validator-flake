{
  inputs = {
    utils.url = github:numtide/flake-utils;
    nixpkgs-unstable.url = github:NixOS/nixpkgs/nixpkgs-unstable;
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, utils }: utils.lib.eachSystem [ "x86_64-linux" ] (system:
    let
      pkgs = import nixpkgs-unstable {
        inherit system;
      };
    in
    {
      packages.nymd = pkgs.callPackage ./nix/nymd.nix { };
    });
}
