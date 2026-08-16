{
  autoPatchelfHook,
  bun2nix,
  fetchurl,
  gnumake,
  node-gyp,
  nodejs_22,
  python3,
  stdenv,
  src,
}: let
  version = "0-unstable-2026-08-16";
  inlangMessageFormatPlugin = fetchurl {
    url = "https://cdn.jsdelivr.net/npm/@inlang/plugin-message-format@4.4.2/dist/index.js";
    hash = "sha256-Z4Hj9pNdMxklu3GrgK1QimfaLDTs4Q3rtqV8bsCN3ZA=";
  };
  inlangMFunctionMatcherPlugin = fetchurl {
    url = "https://cdn.jsdelivr.net/npm/@inlang/plugin-m-function-matcher@2.2.0/dist/index.js";
    hash = "sha256-hYYvYwV5O1a/2a/lNosJbmP7Kuqzi3eZwFFRe+NJnAs=";
  };
in
  stdenv.mkDerivation {
    pname = "baby-shower";
    inherit version src;

    nativeBuildInputs = [
      autoPatchelfHook
      bun2nix.hook
      gnumake
      node-gyp
      nodejs_22
      python3
    ];
    buildInputs = [stdenv.cc.cc.lib];

    bunDeps = bun2nix.fetchBunDeps {
      bunNix = ./bun.nix;
    };
    bunInstallFlags = ["--linker=hoisted"];
    dontUseBunBuild = true;

    buildPhase = ''
      runHook preBuild
      export DATABASE_URL="$TMPDIR/build.sqlite"
      export NITRO_COMPATIBILITY_DATE="2026-08-16"
      export npm_config_nodedir="${nodejs_22}"
      mkdir -p project.inlang/cache/plugins
      cp ${inlangMessageFormatPlugin} project.inlang/cache/plugins/2sy648wh9sugi
      cp ${inlangMFunctionMatcherPlugin} project.inlang/cache/plugins/ygx0uiahq6uw
      chmod u+w project.inlang/cache/plugins/*
      (cd node_modules/better-sqlite3 && ${nodejs_22}/bin/node ${node-gyp}/lib/node_modules/node-gyp/bin/node-gyp.js rebuild --release)
      bun --bun run build
      grep -q "meta_title" src/paraglide/messages/_index.js
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/app"
      rm .output/nitro.json
      cp -r .output "$out/app/.output"
      cp -r drizzle "$out/app/drizzle"
      runHook postInstall
    '';

    dontFixup = false;
  }
