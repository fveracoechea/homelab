# Nix packaging for a Bun + TanStack Start app

Research for GitHub issue #6: package a Bun + TanStack Start (Vite) app (`apps/baby-shower`) as a
nix-built OCI image, deployed to the hostinger VPS via `just deploy-vps`
(`nixos-rebuild switch --flake .#hostinger --target-host hostinger`) into
`virtualisation.oci-containers` (podman backend) behind Caddy at `baby.veracoechea.com`.

Prior art adapted from: `~/Code/hyperlog/nix/packages/build.nix`, `nix/packages/backend-image.nix`,
`nix/services/containers.nix`, `makefile` (validated in production with Deno + docker + nginx).
Pinned differences: Bun not Deno, Caddy not nginx, podman not docker, app lives inside this flake.

## TL;DR recommendation

Use [bun2nix](https://github.com/nix-community/bun2nix) (`fetchBunDeps` + `hook`) to install
dependencies from `bun.lock` purely in the sandbox - no manual `outputHash` maintenance like the
hyperlog fixed-output-derivation pattern needed. Do NOT use `bun build --compile` for the final
artifact: TanStack Start's production build (via the `nitro/vite` plugin with `preset: 'bun'`)
emits a Nitro `.output/` directory whose supported entry point is `bun run .output/server/index.mjs`,
so ship `.output/` plus the `bun` runtime in a `dockerTools.buildLayeredImage`. Run Drizzle
migrations in-process at server startup (`migrate()` from `drizzle-orm/bun-sqlite/migrator`),
with the SQLite file on a bind-mounted host volume (`/var/lib/baby-shower` -> `/data`). The
podman backend loads `imageFile` via `podman load -i` exactly like docker did - no changes needed.

---

## (a) Installing a `bun.lock` project in the nix sandbox

### Options that exist today (2026)

**1. bun2nix (recommended)** - [repo](https://github.com/nix-community/bun2nix),
[docs](https://nix-community.github.io/bun2nix/)

- A Rust CLI converts the `bun.lock` text lockfile (Bun v1.2+) into a `bun.nix` file where each
  dependency becomes a `fetchurl` whose hash is taken directly from the lockfile - no manual hash
  prefetching. ([fetchBunDeps operating details](https://nix-community.github.io/bun2nix/building-packages/fetchBunDeps.html))
- `bun2nix.fetchBunDeps { bunNix = ./bun.nix; }` builds a Bun-compatible install cache in the nix
  store; the `bun2nix.hook` setup hook points `$BUN_INSTALL_CACHE_DIR` at it and runs a fully
  offline `bun install` inside the sandbox during `bunNodeModulesInstallPhase`, then runs any
  dependency lifecycle scripts in `bunLifecycleScriptsPhase`.
  ([hook docs](https://nix-community.github.io/bun2nix/building-packages/hook.html))
- The hook is the right tool for a Vite build (non-executable artifact): you supply your own
  `buildPhase` (e.g. `bun --bun run build`). `bun2nix.mkDerivation` is the thin wrapper for
  producing compiled executables via `bun build --compile` (default flags
  `--compile --minify --sourcemap`) - not what we want here.
  ([mkDerivation docs](https://nix-community.github.io/bun2nix/building-packages/mkDerivation.html))
- Known sharp edge, documented upstream: default installs use bun's isolated linker; if a tool
  expects hoisted `node_modules`, set `bunInstallFlags = [ "--linker=hoisted" ]`.
  ([hook troubleshooting](https://nix-community.github.io/bun2nix/building-packages/hook.html),
  [bun backend strategies](https://bun.com/docs/pm/isolated-installs#backend-strategies))
- Broken deps (network access in postinstall, etc.) are fixed via the `overrides` API on
  `fetchBunDeps`. ([overrides](https://nix-community.github.io/bun2nix/building-packages/fetchBunDeps.html))
- Not packaged in nixpkgs (checked 2026-08: no `bun2nix` attribute), so it is a new flake input:
  `bun2nix.url = "github:nix-community/bun2nix";`. It lives in the nix-community org
  (maintainer @baileylu121) and is small but actively maintained.
- Requires the text `bun.lock` (Bun v1.2+ default), not the legacy binary `bun.lockb`.
  ([bun2nix intro](https://nix-community.github.io/bun2nix/))
- `pkgs.bun` itself is in nixpkgs (1.3.11 on nixos-unstable at research time).

**2. Fixed-output derivation with manual `outputHash` (the hyperlog prior-art pattern)** - viable
fallback, zero new flake inputs:

- Same shape as `~/Code/hyperlog/nix/packages/build.nix`: one `stdenv.mkDerivation` with
  `outputHashMode = "nar"`, `outputHashAlgo = "sha256"`, a manually-maintained `outputHash`,
  `dontFixup = true`; in `buildPhase` export `HOME=$TMPDIR` (bun writes its global cache under the
  home dir, see [bun cache docs](https://github.com/oven-sh/bun/blob/main/docs/install/cache.md))
  and run `bun install --frozen-lockfile` followed by the vite build; FODs are allowed network
  access, so the registry fetch works in the sandbox.
- Downsides vs bun2nix: every dependency change means a failed hash + manual re-paste cycle; the
  whole node_modules + build is one monolithic FOD (no per-package caching); any upstream tarball
  change invalidates the hash. This was acceptable for hyperlog's small Deno dep tree; a TanStack
  Start + Vite tree is much larger, so the pain scales up.

**3. dream2nix - rejected.** No bun subsystem exists (its nodejs modules consume
`package-lock.json`, e.g. `nodejs-package-lock-v3`), and the project itself warns it is "unstable
software" mid-refactor with breaking API changes. ([dream2nix README](https://github.com/nix-community/dream2nix))

**4. Others:** `node2nix`/`yarn2nix`/`js2nix` don't read `bun.lock` (listed as the alternatives
bun2nix positions against, [docs](https://nix-community.github.io/bun2nix/)). `buildNpmPackage`
needs `package-lock.json`. Nothing else first-party from Bun exists for nix.

**Recommendation: bun2nix.** Pure installs, hashes derived from the lockfile (no manual
`outputHash`), granular per-package fetch caching, workspace + catalog support, and an escape
hatch (`overrides`) for misbehaving deps. The FOD pattern remains as a documented fallback if
adding a flake input is ever a problem.

## (b) Final packaging step: ship `.output/` + bun runtime, NOT `bun build --compile`

What TanStack Start emits today (checked against current docs, 2026):

- TanStack Start builds with Vite (or Rsbuild); the old vinxi layer is gone. For server hosting the
  docs prescribe the `nitro/vite` plugin, which "natively integrates with Vite Environments API as
  the underlying build tool for TanStack Start" (flagged as under active development).
  ([TanStack Start hosting guide](https://tanstack.com/start/latest/docs/framework/react/guide/hosting))
- With Nitro, `vite build` emits a `.output/` directory and the documented production commands are
  `"build": "vite build"` / `"start": "node .output/server/index.mjs"` for Node, and for Bun:
  add `nitro({ preset: 'bun' })` to `vite.config.ts` and start with `bun run .output/server/index.mjs`.
  ([hosting guide, Bun section](https://tanstack.com/start/latest/docs/framework/react/guide/hosting),
  [Bun's TanStack Start guide](https://bun.com/docs/guides/ecosystem/tanstack-start))
- Nitro documents the `bun` preset as producing output you run with `bun run ./.output/server/index.mjs`;
  the preset sets `exportConditions: ["bun"]` and `serveStatic: true`, and the server reads
  `PORT` / `HOST` / `NITRO_PORT` / `NITRO_HOST` env vars.
  ([Nitro bun runtime](https://nitro.build/deploy/runtimes/bun),
  [preset source](https://github.com/nitrojs/nitro/blob/e4c50b09/src/presets/bun/preset.ts),
  [nitro discussion #4176](https://github.com/nitrojs/nitro/discussions/4176))
- The Bun-specific path requires React 19 (`react`/`react-dom` >= 19.0.0).
  ([hosting guide](https://tanstack.com/start/latest/docs/framework/react/guide/hosting))
- Without Nitro, plain `vite build` emits `dist/client` + `dist/server/server.js`, and TanStack
  ships a reference `server.ts` (Bun-native `Bun.serve` with asset preloading) that you run with
  `bun run server.ts` - again a bun-runtime deployment, not a compiled binary.
  ([start-bun example](https://github.com/TanStack/router/tree/main/examples/react/start-bun))

Why not `bun build --compile` here:

- `--compile` produces a standalone binary from a single JS/TS entry point
  ([bun docs](https://bun.com/docs/bundler/executables)), but the Nitro artifact is a directory:
  `.output/server/` plus `.output/public/` static assets that the server reads from disk at
  runtime (`serveStatic: true` in the bun preset). A single-file binary does not remove the need
  to ship the asset tree, and none of the three official sources (TanStack hosting guide, Bun's
  ecosystem guide, Nitro docs) use or mention `--compile` for this workload - the supported shape
  is `bun run .output/server/index.mjs`.
- Bonus: shipping the runtime keeps `process.env` handling, sourcemaps and debugging sane, and the
  image build is a plain file copy.

Image contents therefore: `bun` (from nixpkgs), `cacert` (outbound HTTPS), and the app's
`.output/` + `drizzle/` (migration SQL) copied to `/app`. ~ No glibc/libgcc needed - nixpkgs `bun`
is a proper nix package with its closure (unlike hyperlog's deno-compiled binary, which needed
`glibc`/`libgcc` added explicitly).

## (c) `bun:sqlite` + Drizzle sharp edges

- `bun:sqlite` is built into the bun runtime and **does** work in `bun build --compile` binaries:
  "You can use `bun:sqlite` imports with `bun build --compile`. By default, the database is
  resolved relative to the current working directory of the process." There are no native
  bindings to worry about - it is compiled into bun itself, not a node-gyp module.
  ([bun executables docs](https://bun.com/docs/bundler/executables))
- Do not use the `embed: "true"` sqlite import attribute for app data: embedded databases are
  "read-write, but all changes are lost when the executable exits (since it's stored in memory)".
  ([same source](https://bun.com/docs/bundler/executables)) Persistent data must always be a file
  resolved at runtime.
- Drizzle natively supports `bun:sqlite` via `drizzle-orm/bun-sqlite`:
  `const db = drizzle({ client: new Database('sqlite.db') })`.
  ([Drizzle <> Bun SQLite](https://orm.drizzle.team/docs/sqlite/connect-bun-sqlite))
- Migrations: the codebase-first runtime pattern (Drizzle's "Option 4", recommended for
  monolithic apps doing zero-downtime deploys) is `drizzle-kit generate` at dev time to emit SQL
  migration files, then apply them at app startup with the driver-specific migrator:
  ([Drizzle migrations fundamentals](https://orm.drizzle.team/docs/sqlite/migrations))
  ```ts
  import { migrate } from 'drizzle-orm/bun-sqlite/migrator';
  await migrate(db, { migrationsFolder: './drizzle' });
  ```
  The `drizzle-orm/bun-sqlite/migrator` import path is what production Bun apps use, e.g.
  [zerobyte](https://github.com/nicotsx/zerobyte/blob/main/app/server/db/db.ts). This runs at
  container start, in-process, before the server accepts traffic - no separate migration job or
  init container needed for a single-instance SQLite app.
- The `drizzle/` migrations folder must be copied into the image, and `migrationsFolder` resolves
  relative to the process cwd - set `WorkingDir = "/app"` in the image config and keep paths
  consistent.
- SQLite file location: a host directory bind-mounted into the container
  (`/var/lib/baby-shower` -> `/data`, created via `systemd.tmpfiles.rules`), with the DB path
  passed as an env var (e.g. `DATABASE_URL=/data/baby-shower.db`). Same shape as hyperlog's
  `DB_FILENAME` + `Volumes` + host `dbDir`.

## (d) podman backend + `imageFile`: confirmed working, no differences that matter

From the nixpkgs module source
([oci-containers.nix](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/virtualisation/oci-containers.nix)):

- The generated preStart script runs literally `${cfg.backend} load -i ${container.imageFile}` -
  with `backend = "podman"` that is `podman load -i <dockerTools tarball>`.
- `podman load` reads docker-format tar archives (what `dockerTools.buildLayeredImage` produces),
  "preserving its layers, history and tags".
  ([podman-load(1)](https://docs.podman.io/en/latest/markdown/podman-load.1.html))
- The `image` attribute must match the name+tag inside the tarball, otherwise the module falls
  back to pulling from a registry - keep `image = "baby-shower:latest"` in sync with the
  `buildLayeredImage { name; tag; }`.
  ([imageFile option](https://mynixos.com/nixpkgs/option/virtualisation.oci-containers.containers.%3Cname%3E.imageFile))
- The default backend is already podman for `system.stateVersion >= 22.05` (hostinger is on
  24.05), and the module sets `virtualisation.podman.enable = true` automatically when the
  backend is podman - the explicit `virtualisation.podman.enable = true;` in
  `services/paperless-gpt.nix` is redundant but harmless. hyperlog needed `backend = "docker"`
  and the docker group in tmpfiles; here we drop both.
- Behavior notes: `podman load` re-tags on every unit restart (tag `latest` gets overwritten with
  the new store path's image - desired); `podman load` uses `/var/tmp` for staging by default
  (`TMPDIR` override documented in podman-load(1)); when `imageFile` is set the unit does not wait
  on `network-online.target`, which is nice for boot resilience.
- Store-churn note (optional, future): the module also offers `imageStream` for
  `pkgs.dockerTools.streamLayeredImage` to avoid keeping the image tarball in the nix store -
  premature for an app this size. (same module source as above)

## (e) Sketch: the three nix files + Caddy vhost

Layout: the JS app lives at `apps/baby-shower/` (package.json, bun.lock, vite.config.ts with
`nitro({ preset: 'bun' })`, `drizzle/` migrations, plus a generated `bun.nix` committed after
running the bun2nix CLI). Nix packaging sits next to it; the service module follows the existing
`services/*.nix` pattern.

### 1. `apps/baby-shower/package.nix` - build derivation

```nix
# bun2nix variant (recommended)
{ stdenv, bun2nix }:
stdenv.mkDerivation {
  pname = "baby-shower";
  version = "0.1.0";
  src = ./.;

  nativeBuildInputs = [ bun2nix.hook ];

  bunDeps = bun2nix.fetchBunDeps {
    bunNix = ./bun.nix; # generated: nix run github:nix-community/bun2nix -- -o bun.nix
  };

  dontUseBunBuild = true; # we drive vite ourselves

  buildPhase = ''
    runHook preBuild
    bun --bun run build   # "build": "bun --bun vite build"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r .output $out/.output   # nitro bun-preset output
    cp -r drizzle $out/drizzle   # SQL migrations for runtime migrate()
    runHook postInstall
  '';
}
```

FOD fallback (same file, no flake input - mirrors hyperlog `nix/packages/build.nix`):

```nix
{ stdenv, bun }:
stdenv.mkDerivation {
  pname = "baby-shower";
  version = "0.1.0";
  src = ./.;
  dontFixup = true;
  preferLocalBuild = true;
  nativeBuildInputs = [ bun ];
  buildPhase = ''
    export HOME=$TMPDIR
    bun install --frozen-lockfile
    bun --bun run build
  '';
  installPhase = ''
    mkdir -p $out
    cp -r .output $out/.output
    cp -r drizzle $out/drizzle
  '';
  outputHashMode = "nar";
  outputHashAlgo = "sha256";
  outputHash = "sha256-AAAA...."; # lib.fakeHash first, paste real hash on failure
}
```

### 2. `apps/baby-shower/image.nix` - image derivation

Adapted from hyperlog `nix/packages/backend-image.nix`. No `glibc`/`libgcc` (nixpkgs bun carries
its own closure); `cacert` added for outbound TLS; absolute `Cmd` path instead of relying on
bare-name PATH resolution.

```nix
{
  dockerTools,
  bun,
  cacert,
  callPackage,
  baby-shower ? callPackage ./package.nix { },
}:
dockerTools.buildLayeredImage {
  name = "baby-shower";
  tag = "latest";

  contents = [ bun cacert ];

  extraCommands = ''
    mkdir -p ./app ./data
    cp -r ${baby-shower}/.output ./app/.output
    cp -r ${baby-shower}/drizzle ./app/drizzle
    chmod 777 ./data
  '';

  config = {
    WorkingDir = "/app";
    Env = [
      "PORT=3000"                # nitro reads PORT/HOST
      "DATABASE_URL=/data/baby-shower.db"
    ];
    ExposedPorts."3000/tcp" = { };
    Volumes."/data" = { };
    Cmd = [ "/bin/bun" "run" "/app/.output/server/index.mjs" ];
  };
}
```

### 3. `services/baby-shower.nix` - service module

Adapted from hyperlog `nix/services/containers.nix` (docker -> podman) and the VPS Caddy pattern
in `services/caddy-vps.nix` + `services/headplane.nix` (per-domain ACME cert via Cloudflare
DNS-01, `auto_https off` already set globally, manual `tls` directive per vhost). Host port 3001
because headplane already occupies 127.0.0.1:3000 on the VPS.

```nix
{ pkgs, config, ... }:
let
  baby-shower-image = pkgs.callPackage ../apps/baby-shower/image.nix { };
  hostPort = 3001;
  dataDir = "/var/lib/baby-shower";
in {
  # SQLite directory, written by root inside the rootful podman container
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0755 root root - -"
  ];

  virtualisation.oci-containers.containers.baby-shower = {
    autoStart = true;
    imageFile = baby-shower-image;
    image = "baby-shower:latest"; # must match name:tag in the tarball
    ports = [ "127.0.0.1:${toString hostPort}:3000" ];
    volumes = [ "${dataDir}:/data" ];
    environment = {
      PORT = "3000";
      DATABASE_URL = "/data/baby-shower.db";
    };
    # environmentFiles = [ "${dataDir}/baby-shower.env" ]; # secrets, like paperless-gpt.nix
  };

  # Per-vhost cert, same pattern as security.acme.certs."vpn.veracoechea.com" in caddy-vps.nix.
  # Requires /var/lib/caddy/caddy.env (CLOUDFLARE_DNS_API_TOKEN=...) on hostinger - already
  # present for the vpn cert.
  security.acme.certs."baby.veracoechea.com" = {
    domain = "baby.veracoechea.com";
    dnsProvider = "cloudflare";
    dnsResolver = "1.1.1.1:53";
    dnsPropagationCheck = true;
    group = config.services.caddy.group;
    environmentFile = "/var/lib/caddy/caddy.env";
    reloadServices = [ "caddy.service" ];
  };

  services.caddy.virtualHosts."baby.veracoechea.com".extraConfig = ''
    tls /var/lib/acme/baby.veracoechea.com/fullchain.pem /var/lib/acme/baby.veracoechea.com/key.pem
    reverse_proxy 127.0.0.1:${toString hostPort}
  '';
}
```

Wiring: import `../../services/baby-shower.nix` from `hosts/hostinger/configuration.nix`, and add
the bun2nix input in `flake.nix` (pass `bun2nix` down via `specialArgs`, then
`pkgs.callPackage ../apps/baby-shower/image.nix { inherit bun2nix; }`-style threading, or expose
`bun2nix` through an overlay). Deploy is unchanged: `just deploy-vps` builds the image locally,
copies the closure to hostinger, and the container unit `podman load`s it on switch.

## Risks / unknowns to verify first in the build session

1. **bun2nix maturity** - nix-community org but small (~130 stars); pin a rev in the flake input
   and verify it parses the app's real `bun.lock` (run the CLI and build `fetchBunDeps` before
   writing the module). Confirm the lockfile is text `bun.lock`, not binary `bun.lockb`.
2. **Isolated-linker fallout** - bun2nix defaults to `--linker=isolated`; if vite/TanStack plugins
   misbehave, set `bunInstallFlags = [ "--linker=hoisted" ]` (documented upstream).
3. **Deps with postinstall/native builds** - anything node-gyp based in the tree (esbuild, sharp,
   etc.) must build in the sandbox; use `fetchBunDeps.overrides` / `autoPatchElf` if a dep
   downloads binaries at install time. Using `bun:sqlite` (built into bun) instead of
   `better-sqlite3` eliminates the most likely offender.
4. **`.output/` self-containedness** - verify after the first real build that
   `.output/server/index.mjs` starts under nixpkgs `bun` with no `node_modules` present (Nitro v3
   bundles; if a `.output/server/node_modules` appears, `cp -r .output` already covers it).
5. **React 19** - the Bun preset path requires react/react-dom >= 19 per TanStack docs.
6. **Migrations path** - `migrationsFolder` resolves relative to cwd; confirm the app runs
   `migrate()` before serving requests and that `WorkingDir=/app` matches the copied `drizzle/`.
7. **nitro/vite plugin stability** - TanStack flags it as "under active development"; pin
   versions in the app and expect churn on upgrades.

## Sources

- bun2nix: [repo](https://github.com/nix-community/bun2nix),
  [intro](https://nix-community.github.io/bun2nix/),
  [mkDerivation](https://nix-community.github.io/bun2nix/building-packages/mkDerivation.html),
  [hook](https://nix-community.github.io/bun2nix/building-packages/hook.html),
  [fetchBunDeps](https://nix-community.github.io/bun2nix/building-packages/fetchBunDeps.html)
- Bun: [single-file executables + bun:sqlite](https://bun.com/docs/bundler/executables),
  [isolated installs / backend strategies](https://bun.com/docs/pm/isolated-installs#backend-strategies),
  [install cache](https://github.com/oven-sh/bun/blob/main/docs/install/cache.md),
  [TanStack Start ecosystem guide](https://bun.com/docs/guides/ecosystem/tanstack-start)
- TanStack: [Start hosting guide](https://tanstack.com/start/latest/docs/framework/react/guide/hosting),
  [start-bun example](https://github.com/TanStack/router/tree/main/examples/react/start-bun)
- Nitro: [bun runtime](https://nitro.build/deploy/runtimes/bun),
  [bun preset source](https://github.com/nitrojs/nitro/blob/e4c50b09/src/presets/bun/preset.ts),
  [discussion #4176 (env vars)](https://github.com/nitrojs/nitro/discussions/4176)
- Drizzle: [migrations fundamentals](https://orm.drizzle.team/docs/sqlite/migrations),
  [Bun SQLite driver](https://orm.drizzle.team/docs/sqlite/connect-bun-sqlite),
  [bun-sqlite/migrator usage example](https://github.com/nicotsx/zerobyte/blob/main/app/server/db/db.ts)
- NixOS/podman: [oci-containers.nix module source](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/virtualisation/oci-containers.nix),
  [imageFile option](https://mynixos.com/nixpkgs/option/virtualisation.oci-containers.containers.%3Cname%3E.imageFile),
  [podman-load(1)](https://docs.podman.io/en/latest/markdown/podman-load.1.html)
- Rejected: [dream2nix README](https://github.com/nix-community/dream2nix)
