# Nym Validator flake

## nymd package

This flake builds `nymd` in a way closest to [the official instruction](https://nymtech.net/docs/run-nym-nodes/validators/).
The resulting binary is linked to a `libwasm.so` which is already in the store upon nymd build.

```bash
nix build .#packages.x86_64-linux.nymd
```

## nymd NixOS systemd service

flake.nix:
```nix
{
  inputs = {
    nixpkgs-unstable.url = github:NixOS/nixpkgs/nixos-unstable;
    nymd-src.url = github:onsails/nym-validator-flake;
  };

  outputs = { nixpkgs-unstable, nymd-src }: {
    nixosConfigurations.node-name = nixpkgs-unstable.lib.nixosSystem(
      let system = "x86_64-linux";
      in
      {
        inherit system;
        modules = [
          # other modules for example:
          # "${nixpkgs-unstable}/nixos/modules/virtualisation/google-compute-image.nix"
          inputs.nymd-src.nixosModules.${system}.nymd
          ({lib, ...}: {
            nixpkgs.overlays = [
              (self: super: {
                nymd = inputs.nymd-src.packages.${system}.nymd;
              })
            ];

            services.nymd = {
              enable = true;
              name = "Your Validator Name";

              publicAddr = {
                ip = "sentry node ip";
                port = "sentry node port";
              };
            };
          })
        ];
      }
    );
  };
}
```

You can also enable prometheus monitoring, see [options](https://github.com/onsails/nym-validator-flake/tree/master/nix/nixos-module.nix).
