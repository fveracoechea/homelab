# Headplane API-key auth, no OIDC

Headplane (Headscale web UI) authenticates via a Headscale API key pasted into the login screen, not via OIDC/SSO. The API key is generated on the VPS with `sudo headscale apikeys create` and entered once per browser session.

## Considered Options

- **OIDC with an external provider** (rejected) — would provide SSO and automatic user provisioning, but requires standing up an OIDC provider (Kanidm, Authentik, Keycloak), configuring it, and wiring Headplane's `oidc.headscale_api_key_path` (the only file-based API key path the NixOS module exposes). Too much infrastructure for a single-user homelab where the only person logging in is the owner.
- **API-key auth** (chosen) — zero additional infrastructure. The Headscale API key is generated on the VPS and pasted into the Headplane UI at `https://gateway.veracoechea.com/admin`. No OIDC provider, no client secrets, no redirect URIs. The NixOS headplane module has no `headscale.api_key_path` option — for non-OIDC setups, the key is entered via the UI, not a file.

## Consequences

- The Headscale API key is not stored on disk — it lives in Headplane's internal database after first login. Losing the browser session requires regenerating the key and re-pasting.
- The NixOS `services.headplane.settings.headscale` submodule does not expose `api_key` or `api_key_path` — only `oidc.headscale_api_key_path` (which requires OIDC to be configured). Attempting to set `headscale.api_key_path` will fail evaluation with "option does not exist."
- Headplane serves its UI at `/admin`, not `/`. Visiting `https://gateway.veracoechea.com/` returns 404; the login page is at `/admin`.
- If multi-user access is needed later, revisit this decision — OIDC with `oidc.headscale_api_key_path` is the path to SSO.
