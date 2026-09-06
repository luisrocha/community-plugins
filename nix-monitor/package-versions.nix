{ flakePath, configuration, username }:
let
  flake = builtins.getFlake ("path:" + flakePath);
  config = flake.nixosConfigurations.${configuration}.config;
  lib = flake.nixosConfigurations.${configuration}.pkgs.lib;
  users = config.home-manager.users or {};
  userPackages = if builtins.hasAttr username users then users.${username}.home.packages else [];
  records = scope: packages:
    map (package: {
      inherit scope;
      name = package.pname or (lib.getName package);
      version = package.version or (lib.getVersion package);
    }) packages;
in records "system" config.environment.systemPackages ++ records "user" userPackages
