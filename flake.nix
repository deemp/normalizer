{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    devshell = {
      url = "github:deemp/devshell";
      inputs.flake-utils.follows = "flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };
    systems.url = "github:nix-systems/default";
    flake-parts.url = "github:hercules-ci/flake-parts";
    haskell-flake.url = "github:srid/haskell-flake";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    mdsh = {
      url = "github:zimbatm/mdsh";
      inputs.flake-utils.follows = "flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-compat = {
      url = "https://flakehub.com/f/edolstra/flake-compat/1.tar.gz";
      flake = false;
    };
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      imports = [
        inputs.haskell-flake.flakeModule
        inputs.treefmt-nix.flakeModule
        inputs.devshell.flakeModule
      ];
      perSystem =
        {
          self',
          system,
          lib,
          config,
          pkgs,
          ...
        }:
        let
          ghcVersion = "964";
          stack-wrapped = pkgs.symlinkJoin {
            name = "stack"; # will be available as the usual `stack` in terminal
            paths = [ pkgs.stack ];
            meta = pkgs.stack.meta;
            buildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              wrapProgram $out/bin/stack \
                --add-flags "\
                  --system-ghc \
                  --no-install-ghc \
                  --nix \
                  --nix-shell-file stack.nix \
                  --nix-path nixpkgs=${inputs.nixpkgs} \
                "
            '';
          };
          mkShellApps = lib.mapAttrs (
            name: value:
            if !(lib.isDerivation value) && lib.isAttrs value then
              pkgs.writeShellApplication (value // { inherit name; })
            else
              value
          );
          bash.vars = ''
            export LC_ALL=C.UTF-8
          '';
        in
        {
          # Our only Haskell project. You can have multiple projects, but this template
          # has only one.
          # See https://github.com/srid/haskell-flake/blob/master/example/flake.nix
          haskellProjects.default = {
            # To avoid unnecessary rebuilds, we filter projectRoot:
            # https://community.flake.parts/haskell-flake/local#rebuild
            projectRoot = builtins.toString (
              lib.fileset.toSource {
                root = ./.;
                fileset = lib.fileset.unions [
                  ./eo-phi-normalizer
                  ./scripts/transform-eo-tests
                  ./cabal.project
                  ./README.md
                ];
              }
            );

            basePackages = pkgs.haskell.packages."ghc${ghcVersion}";

            # don't want hlint and ghcid - https://github.com/srid/haskell-flake/blob/847292fc793a5c15c873e52e7751ee4267ef32a0/nix/modules/project/defaults.nix#L23-L28
            defaults.devShell.tools = hp: { inherit (hp) cabal-install haskell-language-server; };

            # Development shell configuration
            devShell = {
              hlsCheck.enable = false;
            };

            # What should haskell-flake add to flake outputs?
            autoWire = [
              "packages"
              "apps"
              "checks"
            ]; # Wire all but the devShell
          };

          # Auto formatters. This also adds a flake check to ensure that the
          # source tree was auto formatted.
          treefmt.config = {
            projectRootFile = "flake.nix";
            programs = {
              nixfmt-rfc-style.enable = true;
              hlint.enable = true;
              shellcheck.enable = true;
              fourmolu = {
                enable = true;
                ghcOpts = [
                  "NoPatternSynonyms"
                  "CPP"
                ];
              };
            };
            settings = {
              formatter = rec {
                fourmolu.excludes = [
                  "eo"
                  "eo-phi-normalizer/Setup.hs"
                  "eo-phi-normalizer/src/Language/EO/Phi/Syntax/*"
                  "*.cabal"
                ];
                hlint.excludes = fourmolu.excludes;
              };
              global.excludes = [ "eo" ];
            };
          };

          # Default package & app.
          apps.default = self'.packages.default;

          packages = mkShellApps {
            default = self'.packages.eo-phi-normalizer;
            pipeline = {
              runtimeInputs = [
                stack-wrapped
                pkgs.jdk21
                pkgs.maven
                pkgs.perl
              ];
              text = ''
                export JAVA_HOME="${pkgs.jdk21.home}"
                ${builtins.readFile ./scripts/pipeline.sh}
              '';
              meta.description = "Run pipeline";
              excludeShellChecks = [ "SC2317" ];
            };

            update-markdown = {
              meta.description = "Update Markdown files using mdsh and prettier";
              runtimeInputs = [
                inputs.mdsh.packages.${system}.default
                pkgs.mdbook-linkcheck
                stack-wrapped
              ];
              text =
                let
                  name = "update-markdown";
                  text = ''
                    mdsh

                    ${lib.concatMapStringsSep "\n" (x: "mdsh -i site/docs/src/${x} --work_dir .") [
                      "common/sample-program.md"
                      "common/celsius.md"
                      "normalizer.md"
                      "normalizer/transform.md"
                      "normalizer/metrics.md"
                      "normalizer/dataize.md"
                      "normalizer/report.md"
                      "contributing.md"
                    ]}

                    rm program.phi celsius.phi

                    npm i
                    npx prettier -w "**/*.md"'';
                in
                ''
                  ${bash.vars}
                  stack install

                  cat << EOF > scripts/${name}.sh
                  # shellcheck disable=SC2148

                  ${text}
                  EOF

                  chmod +x scripts/${name}.sh

                  ${text}
                '';
            };
          };

          devShells = {
            # buildStackProject arguments: https://github.com/NixOS/nixpkgs/blob/c7089236291045a523429e681bdaecb49bb501f3/pkgs/development/haskell-modules/generic-stack-builder.nix#L4-L11
            stack-shell = pkgs.haskell.lib.buildStackProject {
              name = "stack-shell";
              ghc = pkgs.haskell.compiler."ghc${ghcVersion}";
            };
          };

          # Default shell.
          devshells.default = {
            packagesFrom = [
              config.haskellProjects.default.outputs.devShell
              config.treefmt.build.devShell
            ];
            bash.extra = bash.vars;
            commands = {
              tools = [
                stack-wrapped
                pkgs.ghcid
                pkgs.hpack
                pkgs.gh
                pkgs.mdsh
                pkgs.mdbook
                pkgs.yq-go
              ];
              scripts = [
                {
                  prefix = "nix run .#";
                  packages = {
                    inherit (self'.packages) pipeline update-markdown;
                  };
                }
              ];
            };
          };
        };
    };

  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://cache.iog.io"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
    ];
  };
}
