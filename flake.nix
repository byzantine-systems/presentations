{
  description = "Chrysopolis presentation — Org-mode + Beamer";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    devenv = {
      url = "github:cachix/devenv";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
    };
  };

  outputs = inputs@{ self, devenv, flake-parts, nixpkgs, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      perSystem = { pkgs, system, ... }:
        let
          # texliveSmall.withPackages
          texenv = pkgs.texlive.combine {
            inherit (pkgs.texlive)
              beamer
              beamertheme-simpleplus
              collection-basic
              collection-fontsextra
              collection-fontsrecommended
              collection-langenglish
              collection-langportuguese
              collection-latex
              collection-latexextra
              collection-mathscience
              enumitem
              fancyhdr
              fontawesome
              graphics
              graphics-cfg
              graphviz
              hyphen-portuguese
              latexmk
              textcase
              scheme-medium
            ;
          };

          customEmacs = (pkgs.emacsPackagesFor pkgs.emacs-nox).emacsWithPackages (
            epkgs:
            (with epkgs.melpaPackages;
              [ citeproc fontawesome htmlize ]
              ++ (with epkgs.elpaPackages; [ org ])
            )
          );

          # Keep the ~39M of reference PDFs (and build outputs) out of the store
          # copy — they are research material, not build inputs.
          presentationSrc = pkgs.lib.cleanSourceWith {
            src = pkgs.lib.cleanSource ./.;
            filter = path: type:
              !(builtins.elem (baseNameOf (toString path)) [
                "seL4"
                "public"
                "result"
                "build-publish.log"
              ]);
          };

          fontsConf = pkgs.makeFontsConf {
            fontDirectories = [
              pkgs.dejavu_fonts
              pkgs.noto-fonts
              pkgs.noto-fonts-color-emoji
            ];
          };
        in
        {
          # This sets `pkgs` to a nixpkgs with allowUnfree option set.
          _module.args.pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };

          # nix build
          packages = {
            default = pkgs.stdenvNoCC.mkDerivation {
              name = "presentation";
              src = presentationSrc;
              buildInputs = with pkgs; [
                bash
                coreutils
                customEmacs
                gnumake
                graphviz
                texenv
              ];
              phases = [ "unpackPhase" "buildPhase" "installPhase" ];
              buildPhase = ''
                export XDG_CACHE_HOME="$(mktemp -d)"
                export HOME="$(mktemp -d)"
                export SOURCE_DATE_EPOCH="${toString self.lastModified}"
                export FONTCONFIG_FILE="${fontsConf}"

                make build

                printf "\n=== Build directory ===\n"
                ls -la public/
              '';
              installPhase = ''
                if ! find public -type f -name '*.pdf' -print -quit | grep -q .; then
                  echo "error: no PDF was produced, see build-publish.log above" >&2
                  exit 1
                fi
                mkdir -p "$out"
                cp -r public/. "$out/"
                printf "\n=== Successfully copied site to output ===\n"
                ls -la "$out/"
              '';
            };
          };

          # nix develop
          devShells = {
            ci = pkgs.mkShell {
              SOURCE_DATE_EPOCH = "${toString self.lastModified}";
              FONTCONFIG_FILE = "${fontsConf}";
              buildInputs = with pkgs; [ gnumake customEmacs graphviz texenv ];
            };

            default = devenv.lib.mkShell {
              inherit inputs pkgs;
              modules = [
                ({ pkgs, lib, ... }: {
                  packages = with pkgs; [ bash gnumake graphviz texenv ];

                  env = {
                    SOURCE_DATE_EPOCH = "${toString self.lastModified}";
                  };

                  languages.texlive.enable = true;
                })
              ];
            };
          };
        };

      flake = { };
    };
}
