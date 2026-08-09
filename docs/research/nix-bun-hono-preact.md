# Nix packaging for a Bun + Hono + Preact SSR app

Research for GitHub issue #10 (supersedes #6 for the new stack locked by #9): package
`apps/baby-shower` - a Hono server entry (`src/main.ts`) SSR'ing Preact with streaming, a client
entry (`src/islands.ts`) hydrating `<preact-island>` custom elements, Tailwind v4 CSS, Drizzle +
`bun:sqlite` - as a nix-built OCI image, deployed to the hostinger VPS via `just deploy-vps` into
`virtualisation.oci-containers` (podman backend) behind Caddy at `baby.veracoechea.com`.

Prior findings adapted: `docs/research/nix-bun-tanstack-start.md` (branch
`research/nix-bun-tanstack-start`). Prior art: `~/Code/hyperlog/nix/packages/build.nix`,
`nix/packages/backend-image.nix`, `nix/services/containers.nix` (single compiled binary + static
assets + SQLite volume, validated in production with Deno).

## TL;DR recommendation

Keep **bun2nix** (`fetchBunDeps` + `hook`) for dependencies - the smaller, framework-free dep tree
makes it an even easier fit than in #6. The runtime answer changes: **nitro's `.output/` is gone,
so `bun build --compile` is now viable and is the recommended shape** - a single-file executable
(bun runtime embedded) plus two on-disk directories (`drizzle/` migrations and `public/` built
assets), exactly the hyperlog pattern. Hono officially documents standalone-binary deployment,
`bun:sqlite` is documented to work in compiled binaries, and Preact SSR is pure JS. Do NOT embed
assets into the binary (Hono's `serveStatic` + asset embedding is unverified upstream); ship the
directories next to the binary. The client bundle (`bun build src/islands.ts --target browser`)
and Tailwind CSS (`@tailwindcss/cli --minify`) build **inside the same derivation's `buildPhase`**,
after the bun2nix hook installs deps offline. Everything else from #6 carries over unchanged:
Drizzle `migrate()` at container start, `dockerTools.buildLayeredImage` + podman `imageFile`, and
the `services/baby-shower.nix` shape (now with the #3 tailnet gate on `/admin`).

---

## (a) bun2nix is still the right dependency mechanism for this `bun.lock`

Current state (checked 2026-08-09): bun2nix is at **2.1.2** (2026-07-21), actively maintained in
nix-community (@baileylu121), 519 commits. Still **not in nixpkgs** - consume as a flake input,
optionally via `inputs.bun2nix.overlays.default` which puts `bun2nix` into `pkgs`.
([repo](https://github.com/nix-community/bun2nix),
[tags](https://github.com/nix-community/bun2nix/tags),
[flake installation](https://nix-community.github.io/bun2nix/flake-installation.html))

Why it still wins over the alternatives from #6:

- The flow is unchanged: the CLI converts the text `bun.lock` (Bun v1.2+) into `bun.nix` where each
  dependency becomes a `fetchurl` with the hash taken directly from the lockfile;
  `bunDeps = bun2nix.fetchBunDeps { bunNix = ./bun.nix; };` plus `bun2nix.hook` in
  `nativeBuildInputs` gives a fully offline `bun install` in the sandbox.
  ([fetchBunDeps](https://nix-community.github.io/bun2nix/building-packages/fetchBunDeps.html),
  [hook](https://nix-community.github.io/bun2nix/building-packages/hook.html))
- The hook phases are: `bunSetInstallCacheDirPhase`, `bunPatchPhase`,
  `bunNodeModulesInstallPhase` (`bun install --ignore-scripts`), `bunLifecycleScriptsPhase`
  (postinstalls), then our own `buildPhase`. `dontUseBunBuild = true` skips the default build.
  ([hook docs](https://nix-community.github.io/bun2nix/building-packages/hook.html))
- `bun2nix.mkDerivation` is for producing executables and defaults to
  `bun build --compile --minify --sourcemap --bytecode`; for a multi-artifact build like ours
  (CSS + client bundle + compiled server) the docs recommend the plain hook with a custom
  `buildPhase`. ([mkDerivation](https://nix-community.github.io/bun2nix/building-packages/mkDerivation.html))
- The new dep tree removes the #6 risk factors: no Vite, no TanStack, no React. What remains:
  - `drizzle-kit` (dev-time only) pulls `esbuild`, which has a real postinstall (`node install.js`)
    plus platform `optionalDependencies` (`@esbuild/linux-x64`). Handled by
    `bunLifecycleScriptsPhase`; the native binary itself is a pinned optional dep in `bun.lock`.
    ([drizzle-kit on npm](https://registry.npmjs.org/drizzle-kit/latest),
    [esbuild on npm](https://registry.npmjs.org/esbuild/latest))
  - `@tailwindcss/cli@4.3.3` has **no install scripts and downloads nothing**; its native parts
    (`@tailwindcss/oxide`, `lightningcss` for `--minify`) ship as platform `optionalDependencies`,
    all normal registry tarballs pinned in `bun.lock` - fully offline-safe in the sandbox.
    ([@tailwindcss/cli on npm](https://registry.npmjs.org/@tailwindcss/cli/latest),
    [@tailwindcss/oxide on npm](https://registry.npmjs.org/@tailwindcss/oxide/latest),
    [lightningcss on npm](https://registry.npmjs.org/lightningcss/latest))
  - Open bun2nix issues that could bite (#67 tarball extraction on darwin, #71 workspaces, #77
    catalogs) do not apply: this app is a single non-workspace package and does not use catalogs.
    ([bun2nix issues](https://github.com/nix-community/bun2nix/issues))
- Known sharp edge unchanged: default `--linker=isolated`; if tooling expects hoisted
  `node_modules`, set `bunInstallFlags = [ "--linker=hoisted" ]`.
  ([hook troubleshooting](https://nix-community.github.io/bun2nix/building-packages/hook.html),
  [bun backend strategies](https://bun.com/docs/pm/isolated-installs#backend-strategies))

Alternatives stay rejected: the hyperlog fixed-output-derivation pattern (manual `outputHash`
re-paste on every dep change) remains the zero-new-inputs fallback; dream2nix has no bun subsystem
and warns it is unstable mid-refactor ([README](https://github.com/nix-community/dream2nix));
`node2nix`/`yarn2nix`/`buildNpmPackage` do not read `bun.lock`.

## (b) Production runtime shape: `bun build --compile` is viable now - recommended

#6 rejected `--compile` because nitro emits a `.output/` directory whose supported entry is
`bun run .output/server/index.mjs`. That constraint is gone: `src/main.ts` is a plain Hono-on-Bun
entry with no framework output directory. Re-evaluating the three shapes:

**1. `bun run src/main.ts` (ship source + node_modules + bun runtime).** Works but is the worst
shape: the image must carry the app's full source and a populated `node_modules`, and bun
re-transpiles on every start. Rejected.

**2. `bun build --target=bun` (single bundled JS + bun runtime).** Viable: one `server.js` run with
`bun run`; `bun:sqlite` is left as a builtin import for `target: "bun"` ("Bun and Node.js APIs are
supported and left untouched"). The docs even note bundling server code is often unnecessary.
([bun bundler announcement](https://bun.com/blog/bun-bundler),
[bundler docs](https://bun.com/docs/bundler)) Kept as the low-risk fallback.

**3. `bun build --compile` (single-file executable) - viable, recommended.**

- Produces a standalone binary bundling all imports "along with a copy of the Bun runtime. All
  built-in Bun and Node.js APIs are supported."
  ([bun executables docs](https://bun.com/docs/bundler/executables))
- **Hono officially documents it**: the Hono Bun deployment guide has a "Standalone Binary"
  section: `bun build --compile --minify --sourcemap ./index.ts --outfile myapp`.
  ([Hono Bun deployment](https://hono.dev/docs/deployment/bun))
- **`bun:sqlite` is documented to work in compiled binaries**: "You can use `bun:sqlite` imports
  with `bun build --compile`. By default, the database is resolved relative to the current working
  directory of the process." ([same source](https://bun.com/docs/bundler/executables))
- **Preact SSR is pure JS** - `preact-render-to-string/stream`'s `renderToReadableStream` "works in
  any Web Streams environment (Deno, Bun, Cloudflare Workers, ...)"; no bundling/compile
  incompatibilities found in the preact or bun issue trackers.
  ([preact-render-to-string README](https://github.com/preactjs/preact-render-to-string))
- This mirrors the hyperlog prior art (`deno compile` single binary + assets + SQLite volume),
  which is proven in production.

Three concrete constraints, all sourced:

1. **DB path must never come from `import.meta.dir`.** In a compiled binary `import.meta.dir` is
   the virtual `/$bunfs/root`; `new Database(import.meta.dir + '/x.db')` fails with
   `SQLITE_CANTOPEN` ([oven-sh/bun#15766](https://github.com/oven-sh/bun/issues/15766), closed
   working-as-designed). Use an absolute env-configured path (`DATABASE_URL=/data/baby-shower.db`).
   Do not use `embed: "true"` sqlite imports for app data - embedded DBs are in-memory, writes are
   lost on exit ([docs](https://bun.com/docs/bundler/executables),
   [oven-sh/bun#25328](https://github.com/oven-sh/bun/issues/25328)).
2. **Drizzle `migrate()` reads `migrationsFolder` from disk at runtime** - confirmed in source:
   `readMigrationFiles` does `fs.readFileSync` on `meta/_journal.json` and each `<tag>.sql`
   ([migrator.ts](https://github.com/drizzle-team/drizzle-orm/blob/main/drizzle-orm/src/migrator.ts),
   [bun-sqlite/migrator.ts](https://github.com/drizzle-team/drizzle-orm/blob/main/drizzle-orm/src/bun-sqlite/migrator.ts)).
   Ship `drizzle/` in the image next to the binary and resolve it relative to `WorkingDir`.
3. **Static assets must stay on disk too.** Hono's Bun `serveStatic` resolves `join(root, filename)`
   per request and reads with `Bun.file` / `node:fs`
   ([serve-static source](https://github.com/honojs/hono/blob/main/src/adapter/bun/serve-static.ts)).
   Embedding directories via `--asset` is documented for `Bun.serve` static routes, but the
   combination with Hono's `serveStatic` is unverified and directory embedding has an open bug
   ([oven-sh/bun#23852](https://github.com/oven-sh/bun/issues/23852)). Ship `public/` in the image;
   do not embed.

Net image contents: the compiled binary, `cacert` (outbound TLS), `/app/public`, `/app/drizzle`,
`/data` volume. The nixpkgs `bun` package is NOT needed in the image (runtime is embedded); the
binary's glibc interpreter points into the nix store and arrives via the derivation's closure in
`contents` (no manual `glibc`/`libgcc` like hyperlog's opaque FOD binary needed).

## (c) Client bundle and Tailwind CSS build inside the same derivation

Both are build-time artifacts, so both run in `package.nix`'s `buildPhase`, after the bun2nix
hook's install phases:

1. **Tailwind v4 CSS**: `bunx @tailwindcss/cli -i ./src/global.css -o ./public/styles.css --minify`.
   The CLI's exact flags (`-i`, `-o`, `--minify`/`-m`) confirmed from the shipped
   [dist/index.mjs](https://unpkg.com/@tailwindcss/cli@4.3.3/dist/index.mjs) and the
   [Tailwind CLI docs](https://tailwindcss.com/docs/installation/tailwind-cli). The npm package is
   a plain ESM script with a `#!/usr/bin/env node` shebang; bun2nix's `useFakeNode` (default true)
   patches dep scripts to run under bun
   ([fetchBunDeps docs](https://nix-community.github.io/bun2nix/building-packages/fetchBunDeps.html)).
   Offline-safe: oxide/lightningcss natives are pinned optional deps (see (a)). One caveat: the
   lockfile only pins the platform natives resolved at `bun install` time - generate `bun.lock` on
   Linux (or ensure the linux-x64 entries are present) before building the derivation on Linux.
2. **Client hydration bundle**: `bun build ./src/islands.ts --outdir ./public --target browser --minify`.
   `--target browser` is the default and valid; with default `naming` (`[dir]/[name].[ext]`, no
   entry hash) one entrypoint yields a deterministic `public/islands.js` that the SSR'd HTML
   references with a fixed `<script src="/public/islands.js" type="module">` (ESM is the default
   format). ([bun bundler docs](https://bun.com/docs/bundler))
3. **Server compile** (same phase, after assets exist): `bun build --compile --minify --sourcemap ./src/main.ts --outfile server`.

`installPhase` copies `server` to `$out/bin/baby-shower` and `public/` + `drizzle/` to
`$out/share/baby-shower/`. Nothing else leaves the sandbox.

## (d) What carries over from #6 - confirmed, with one diff

- **Drizzle `migrate()` at container start: unchanged.** `drizzle-kit generate` at dev time emits
  SQL into `drizzle/`; at startup, in-process, before Hono serves:
  ```ts
  import { migrate } from 'drizzle-orm/bun-sqlite/migrator';
  await migrate(db, { migrationsFolder: './drizzle' }); // resolves from WorkingDir=/app
  ```
  ([Drizzle migrations](https://orm.drizzle.team/docs/sqlite/migrations),
  [Bun SQLite driver](https://orm.drizzle.team/docs/sqlite/connect-bun-sqlite)) No init container
  needed for a single-instance SQLite app. DB file on the bind-mounted host volume
  (`/var/lib/baby-shower` -> `/data`, via `systemd.tmpfiles.rules`), path passed as
  `DATABASE_URL` - absolute, per constraint (b).1.
- **`dockerTools.buildLayeredImage` + podman `imageFile`: unchanged.** The oci-containers module's
  preStart runs literally `${cfg.backend} load -i ${container.imageFile}`; `podman load` reads the
  docker-format tarball; `image` must match the `name:tag` inside the tarball; backend defaults to
  podman and auto-enables `virtualisation.podman`.
  ([oci-containers.nix](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/virtualisation/oci-containers.nix),
  [podman-load(1)](https://docs.podman.io/en/latest/markdown/podman-load.1.html))
- **`services/baby-shower.nix` shape: unchanged**, with two diffs: image contents change (compiled
  binary instead of `.output/` + `bun` package), and the Caddy vhost gains the #3 tailnet gate for
  `/admin*` + `/api/admin/*` using the headplane `@tailnet` pattern
  ([services/headplane.nix](../../../services/headplane.nix)). Host port 3001 (headplane occupies
  127.0.0.1:3000 on the VPS).

What does NOT carry over from #6: shipping `.output/` + the bun runtime package, the nitro bun
preset and its `PORT`/`HOST`/`NITRO_*` env contract, the React 19 requirement, and the "never
compile" conclusion itself.

## Sketches

### 1. `apps/baby-shower/package.nix` - build derivation

```nix
{stdenv, bun2nix}:
stdenv.mkDerivation {
  pname = "baby-shower";
  version = "0.1.0";
  src = ./.;

  nativeBuildInputs = [bun2nix.hook];

  bunDeps = bun2nix.fetchBunDeps {
    bunNix = ./bun.nix; # generated: bunx bun2nix -o bun.nix (package.json postinstall)
  };

  dontUseBunBuild = true; # custom build: CSS + client bundle + compiled server

  buildPhase = ''
    runHook preBuild
    # Tailwind v4 CSS (offline: oxide/lightningcss natives are pinned optional deps)
    bunx @tailwindcss/cli -i ./src/global.css -o ./public/styles.css --minify
    # Client hydration bundle, deterministic name: public/islands.js
    bun build ./src/islands.ts --outdir ./public --target browser --minify
    # Server: single-file executable, bun runtime embedded
    bun build --compile --minify --sourcemap ./src/main.ts --outfile server
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share/baby-shower
    cp server $out/bin/baby-shower
    cp -r public $out/share/baby-shower/public
    cp -r drizzle $out/share/baby-shower/drizzle
    runHook postInstall
  '';
}
```

### 2. `apps/baby-shower/image.nix` - image derivation

No `bun` package (embedded in the binary), no manual `glibc`/`libgcc` (closure via `contents`),
`cacert` for outbound TLS. Adapted from hyperlog `nix/packages/backend-image.nix`.

```nix
{
  dockerTools,
  cacert,
  callPackage,
  baby-shower ? callPackage ./package.nix {},
}:
dockerTools.buildLayeredImage {
  name = "baby-shower";
  tag = "latest";

  contents = [baby-shower cacert];

  extraCommands = ''
    mkdir -p ./app ./data
    cp -r ${baby-shower}/share/baby-shower/public ./app/public
    cp -r ${baby-shower}/share/baby-shower/drizzle ./app/drizzle
    chmod 777 ./data
  '';

  config = {
    WorkingDir = "/app";
    Env = [
      "PORT=3000"
      "DATABASE_URL=/data/baby-shower.db" # absolute path, never import.meta.dir
    ];
    ExposedPorts."3000/tcp" = {};
    Volumes."/data" = {};
    Cmd = ["/bin/baby-shower"];
  };
}
```

### 3. `services/baby-shower.nix` - service module

Same shape as the #6 sketch (tmpfiles + oci-container + per-vhost ACME cert via the existing
Cloudflare DNS-01 setup in `services/caddy-vps.nix`), plus the #3 admin gate.

```nix
{pkgs, config, ...}: let
  baby-shower-image = pkgs.callPackage ../apps/baby-shower/image.nix {};
  hostPort = 3001; # headplane occupies 127.0.0.1:3000 on the VPS
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
    ports = ["127.0.0.1:${toString hostPort}:3000"];
    volumes = ["${dataDir}:/data"];
    environment = {
      PORT = "3000";
      DATABASE_URL = "/data/baby-shower.db";
    };
  };

  # Per-vhost cert, same pattern as security.acme.certs."vpn.veracoechea.com" in caddy-vps.nix.
  # Requires /var/lib/caddy/caddy.env (CLOUDFLARE_DNS_API_TOKEN=...) on hostinger - already present.
  security.acme.certs."baby.veracoechea.com" = {
    domain = "baby.veracoechea.com";
    dnsProvider = "cloudflare";
    dnsResolver = "1.1.1.1:53";
    dnsPropagationCheck = true;
    group = config.services.caddy.group;
    environmentFile = "/var/lib/caddy/caddy.env";
    reloadServices = ["caddy.service"];
  };

  # Admin gate per #3: tailnet-only for /admin* and /api/admin/*, public otherwise.
  services.caddy.virtualHosts."baby.veracoechea.com".extraConfig = ''
    tls /var/lib/acme/baby.veracoechea.com/fullchain.pem /var/lib/acme/baby.veracoechea.com/key.pem
    handle /admin* /api/admin/* {
      @tailnet remote_ip 100.64.0.0/10
      handle @tailnet {
        reverse_proxy 127.0.0.1:${toString hostPort}
      }
      handle {
        respond 403
      }
    }
    reverse_proxy 127.0.0.1:${toString hostPort}
  '';
}
```

Wiring: add the bun2nix input in `flake.nix` and apply `inputs.bun2nix.overlays.default` to the
nixpkgs instance so plain `pkgs.callPackage` resolves `bun2nix`; import
`../../services/baby-shower.nix` from `hosts/hostinger/configuration.nix`. Deploy unchanged:
`just deploy-vps` builds the image locally, copies the closure to hostinger, and the container unit
`podman load`s it on switch.

## Risks / unknowns to verify first in the build session

1. **bun2nix rev pin** - pin the flake input; run the CLI against the app's real `bun.lock` and
   build `fetchBunDeps` before writing the module. Confirm the lockfile is text `bun.lock`.
2. **Lockfile platform coverage** - regenerate/verify `bun.lock` on x86_64-linux so the
   `@tailwindcss/oxide-linux-x64-gnu`, `lightningcss-linux-x64-gnu` and `@esbuild/linux-x64`
   optional deps are pinned; a lockfile produced on darwin may lack them.
3. **esbuild postinstall** (via dev dep `drizzle-kit`) runs in `bunLifecycleScriptsPhase`; if it
   misbehaves, `dontRunLifecycleScripts = true` is the escape hatch (the platform binary comes from
   the optional dep regardless).
4. **Compiled-binary path traps** - `DATABASE_URL` absolute; `migrationsFolder: './drizzle'` with
   `WorkingDir=/app`; `serveStatic({root: './public'})`; never `import.meta.dir` for runtime files.
5. **First-build smoke test** - `podman run` the image with no bun package present; confirm
   migrations apply, `/` streams SSR HTML, `/public/islands.js` and `/public/styles.css` serve.
6. **Isolated-linker fallout** - if any tool misbehaves under the default `--linker=isolated`, set
   `bunInstallFlags = [ "--linker=hoisted" ]`.
7. **Hono `hc<AppType>` typing** is compile-time only; no runtime impact on any of the above.

## Sources

- bun2nix: [repo](https://github.com/nix-community/bun2nix),
  [tags](https://github.com/nix-community/bun2nix/tags),
  [flake installation](https://nix-community.github.io/bun2nix/flake-installation.html),
  [fetchBunDeps](https://nix-community.github.io/bun2nix/building-packages/fetchBunDeps.html),
  [hook](https://nix-community.github.io/bun2nix/building-packages/hook.html),
  [mkDerivation](https://nix-community.github.io/bun2nix/building-packages/mkDerivation.html),
  [open issues](https://github.com/nix-community/bun2nix/issues)
- Bun: [single-file executables + bun:sqlite + asset embedding](https://bun.com/docs/bundler/executables),
  [bundler docs](https://bun.com/docs/bundler),
  [bundler announcement (target bun builtins)](https://bun.com/blog/bun-bundler),
  [isolated installs](https://bun.com/docs/pm/isolated-installs#backend-strategies),
  [issue #15766 import.meta.dir + SQLITE_CANTOPEN](https://github.com/oven-sh/bun/issues/15766),
  [issue #23852 embedded directories + Hono serveStatic](https://github.com/oven-sh/bun/issues/23852),
  [issue #25328 embedded sqlite semantics](https://github.com/oven-sh/bun/issues/25328)
- Hono: [Bun deployment - standalone binary](https://hono.dev/docs/deployment/bun),
  [serve-static Bun adapter source](https://github.com/honojs/hono/blob/main/src/adapter/bun/serve-static.ts)
- Preact: [preact-render-to-string README](https://github.com/preactjs/preact-render-to-string)
- Drizzle: [migrations fundamentals](https://orm.drizzle.team/docs/sqlite/migrations),
  [Bun SQLite driver](https://orm.drizzle.team/docs/sqlite/connect-bun-sqlite),
  [migrator source (reads from disk)](https://github.com/drizzle-team/drizzle-orm/blob/main/drizzle-orm/src/migrator.ts),
  [bun-sqlite migrator source](https://github.com/drizzle-team/drizzle-orm/blob/main/drizzle-orm/src/bun-sqlite/migrator.ts)
- Tailwind: [CLI installation docs](https://tailwindcss.com/docs/installation/tailwind-cli),
  [@tailwindcss/cli on npm](https://registry.npmjs.org/@tailwindcss/cli/latest),
  [CLI dist (flags)](https://unpkg.com/@tailwindcss/cli@4.3.3/dist/index.mjs),
  [@tailwindcss/oxide on npm](https://registry.npmjs.org/@tailwindcss/oxide/latest),
  [lightningcss on npm](https://registry.npmjs.org/lightningcss/latest)
- NixOS/podman: [oci-containers.nix module source](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/virtualisation/oci-containers.nix),
  [podman-load(1)](https://docs.podman.io/en/latest/markdown/podman-load.1.html)
- Rejected: [dream2nix README](https://github.com/nix-community/dream2nix)
