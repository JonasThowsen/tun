# What scripts/test-screens.sh builds to see a screen's build refuse
# (spec/typescript.md 6.2, 6.3).  FLAKE is Tun's flake at the working tree.
{ flake }:
let
  system = "x86_64-linux";
  screen = flake.packages.${system}.showcase-screen;
in
{
  # The showcase's screen with a type error put in its code.
  typeError = screen.overrideAttrs (_: {
    postPatch = ''
      echo 'export const wrong: number = "a text";' >> src/main.ts
    '';
  });
  # The showcase's screen whose build writes nothing.
  noIndex = screen.overrideAttrs (_: {
    postPatch = ''
      substituteInPlace package.json --replace-fail '"vite build"' '"true"'
    '';
  });
  # A client whose screen would go out of its source.
  outOfSource = (flake.lib.${system}.buildClient {
    pname = "out-of-source";
    src = ./.;
    screens = { "../elsewhere" = screen; };
  }).drvPath;
}
