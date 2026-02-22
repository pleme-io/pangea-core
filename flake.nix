{
  description = "Pangea Core — shared types and utilities for Pangea infrastructure DSL";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    ruby-nix.url = "github:inscapist/ruby-nix";
    flake-utils.url = "github:numtide/flake-utils";
    substrate = {
      url = "github:pleme-io/substrate";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    forge = {
      url = "github:pleme-io/forge";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.substrate.follows = "substrate";
    };
  };

  outputs = {
    self,
    nixpkgs,
    ruby-nix,
    flake-utils,
    substrate,
    forge,
    ...
  }:
    flake-utils.lib.eachSystem ["x86_64-linux" "aarch64-linux" "aarch64-darwin"] (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ruby-nix.overlays.ruby];
      };
      rnix = ruby-nix.lib pkgs;
      rnix-env = rnix {
        name = "pangea-core";
        gemset = ./gemset.nix;
      };
      env = rnix-env.env;
      ruby = rnix-env.ruby;

      rubyBuild = import "${substrate}/lib/ruby-build.nix" {
        inherit pkgs;
        forgeCmd = "${forge.packages.${system}.default}/bin/forge";
        defaultGhcrToken = "";
      };
    in {
      devShells.default = pkgs.mkShell {
        buildInputs = [env ruby];
        shellHook = ''
          export RUBYLIB=$PWD/lib:$RUBYLIB
          export DRY_TYPES_WARNINGS=false
        '';
      };

      apps = rubyBuild.mkRubyGemApps {
        srcDir = self;
        name = "pangea-core";
      };
    });
}
