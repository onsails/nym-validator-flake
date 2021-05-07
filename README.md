# Nym Validator flake

This flake builds `nymd` in a way closest to [the official instruction](https://nymtech.net/docs/run-nym-nodes/validators/).
The resulting binary is linked to a `libwasm.so` which is already in the store upon nymd build.

```bash
nix build .#packages.x86_64-linux.nymd
```
