{
  description = "generic ruby dsl resources";

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
    flake-utils,
    ruby-nix,
    substrate,
    forge,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ruby-nix.overlays.ruby];
      };
      rnix = ruby-nix.lib pkgs;
      rnix-env = rnix {
        name = "abstract-synthesizer";
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
      devShells = rec {
        default = dev;
        dev = pkgs.mkShell {
          buildInputs = [
            env
            ruby
          ];
        };
      };

      apps = rubyBuild.mkRubyGemApps {
        srcDir = self;
        name = "abstract-synthesizer";
      };
    });
}
