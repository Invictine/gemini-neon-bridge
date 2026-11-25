<img src="assets/icon.svg" width="64" height="64" alt="">

# Neon Bridge

**Neon Bridge** connects OpenCode to a local OpenAI-compatible bridge driven by a Chrome extension that sends requests through an inactive tab in your signed-in Gemini web app. Add **Gemini** as a separate OpenCode provider instance in regular T3 Code, defaulting to **Gemini 4 Neon** where your account supports it.

[Regular T3 Code setup](docs/t3-code-setup.md) · [Setup](#setup) · [Reliability checks](docs/reliability-report.md) · [Deprecated fork notice](#deprecated-windows-t3-code-fork)

## Live OpenCode terminal demo

[![Live Neon run in OpenCode showing the read tool and the returned file marker](assets/demo/neon-file-read.png)](assets/demo/neon-file-read.mp4?raw=true)

[Watch the short MP4](assets/demo/neon-file-read.mp4?raw=true). The condensed clip follows a live OpenCode run as it reads a scratch file and returns its contents through the local bridge.

## Compatibility and access

This project is unofficial. Gemini account quotas, model availability, and web UI updates can interrupt requests. These docs are public; setup requires access to the private, pinned bridge dependency while its upstream licensing is unresolved.

## Architecture

```
Regular T3 Code (OpenCode provider instance "gemini-bridge", display name "Gemini")
  -> OpenCode runtime (isolated XDG dirs + OPENCODE_CONFIG)
      -> OpenCode "gemini-app" provider  (config/t3-neon-opencode.json)
          -> local bridge  http://127.0.0.1:8100/v1  (vendor/gemini-web-api)
              -> signed-in Gemini tab (Chrome backend) or saved session (cookie backend)
```

Load the unpacked `vendor/gemini-web-api/extension` in the signed-in Chrome profile, set `GEMINI_BACKEND=chrome` in the project `.env`, and start the bridge in the background. The extension uses inactive Gemini tabs and selects the exact model. The [installed-extension check](#testing-the-installed-chrome-extension) can open a worker tab for you and verify Neon through the local API.

Add **Gemini** as a separate OpenCode provider instance in regular T3 Code following [the T3 Code setup guide](docs/t3-code-setup.md). For the separate [cookie backend](docs/cookie-capture.md), configure `.env` directly or verify cookies through `POST /v1/auth/session`. The [validation report](docs/reliability-report.md) tracks live Chrome and T3 results separately.

## ⚠️ Read this first

- This is **unofficial, reverse-engineered** access to the Gemini web app. It may **violate Google's Terms of Service** and can lead to **account restrictions or termination**.
- Use a **secondary / throwaway Google account** if at all possible.
- **Web-app quotas and rate limits apply** (not API quotas). Heavy use can trip abuse detection.
- Google deploys changes constantly: **RPC IDs and cookie handling can break without notice**. When that happens, update the vendored bridge (see Maintenance).

## Prerequisites

- **Python 3.12 and uv** for the local bridge.
- **Windows** and regular **T3 Code** with support for multiple OpenCode provider instances ([setup guide](docs/t3-code-setup.md)).
- **OpenCode 1.14.19** for the bridge provider instance. The Windows setup installs it cleanly at `%LOCALAPPDATA%\gemini-bridge\runtime\opencode` beside your existing OpenCode runtime.
- **Chrome**, logged into <https://gemini.google.com> with an account whose picker offers **4 Neon**, **4 Argon**, or **4 Hydrogen**.

## Setup

Start with [the Chrome bridge setup](#1-set-up-the-signed-in-chrome-bridge), then [add the separate Gemini provider instance in regular T3 Code](docs/t3-code-setup.md).

### 1. Set up the signed-in Chrome bridge

With access to the pinned dependency, clone this project.

```powershell
git clone --recurse-submodules https://github.com/Invictine/gemini-neon-bridge.git
cd gemini-neon-bridge
```

Install Python 3.12 and [uv](https://docs.astral.sh/uv/getting-started/installation/), then run the guided setup:

```powershell
.\scripts\setup-windows.ps1
```

The script installs the pinned bridge dependencies and the isolated OpenCode 1.14.19 runtime (`%LOCALAPPDATA%\gemini-bridge\runtime\opencode`), configures `.env` for Chrome, and starts the bridge in the background. It guides you through signing into Gemini and loading the unpacked extension from `vendor/gemini-web-api/extension`. Keep Chrome open. The script lists connected accounts, lets you choose one, and verifies a fresh-marker reply through an exact model offered by that account.

After setup, `.\scripts\check-bridge.ps1` should print **Bridge reachable: YES** and list `gemini-4-neon` and `gemini-4-hydrogen`. You can also run `.\scripts\start-bridge.ps1` without `-Background` to see bridge logs in the terminal while debugging. Model advertisement alone does not verify generation.

To launch the bridge automatically at Windows sign-in, run `.\scripts\install-bridge-startup.ps1`. It registers a hidden task (`Gemini Bridge`) for your Windows account and removes any legacy `T3 Code (Gemini) Bridge` task. Chrome still needs the enabled extension and a signed-in Gemini session.

### 2. Add the Gemini provider in regular T3 Code

Follow [the regular T3 Code setup guide](docs/t3-code-setup.md) to register **Gemini** (`gemini-bridge`) under **Settings → Providers → Add provider → OpenCode** using `config/t3-neon-opencode.json` and isolated `XDG_*` directories.

For the separate [cookie backend](docs/cookie-capture.md), put `__Secure-1PSID` and `__Secure-1PSIDTS` into `.env` (or POST them to `http://127.0.0.1:<port>/v1/auth/session` with `Authorization: Bearer gemini-local`). The auth endpoint checks cookies live against Google before saving to `.env` and applying them to the running shared client.

Cookie values are never returned in a response, echoed in an error, or written to logs. Credentials are also rejected if they are empty, over 4096 characters, or contain line breaks, NUL, or `=`.

> `.env` holds **session cookies = full account credentials**. Never commit, share, or paste it into a chat. It is gitignored. The auth endpoint uses the same `GEMINI_API_KEY` as `/v1/models`; CORS is restricted to loopback HTTP origins on the bridge port plus T3's `t3code://app`, `t3code-dev://app`, and legacy `t3code-gemini://app` webview origins. The `/ws` extension socket also requires that key or a trusted local/T3/extension origin. Override the credentials file location with `GEMINI_ENV_FILE` if you relocate it.

### 3. Pick the model and manage accounts or queue

In regular T3 Code's composer, select **Gemini → Gemini 4 Neon** (or **Gemini 4 Hydrogen**, **Gemini 4 Argon**, or **Gemini Auto**). The signed-in Google account's Gemini picker determines which modes work.

The local bridge exposes control endpoints with `Authorization: Bearer gemini-local`:

- `GET /v1/accounts` and `PUT /v1/accounts/default` (`{"authuser": "0"}`) inspect connected Chrome accounts and select which Google account new requests use.
- `GET /v1/requests` inspects active and queued requests; `POST /v1/extension/open-worker` asks the extension to open an inactive worker tab.
- `GET /v1/usage` (or `?refresh=1`) reports cached or refreshed quota windows read while Gemini's **Settings → Usage limits** panel or model picker is visible.
- `POST /v1/model-check/{model}` runs an isolated OpenCode file-read check against `neon`, `argon`, `hydrogen`, or `auto`.

### Use Gemini's website tools

With the Chrome backend, ask Gemini to search the public web for current information. Gemini can use its own Google Search, and the bridge carries clickable links into the T3 reply. **Sources from Gemini** lists links exposed by the site's citation UI. **Answer links from sites cited by Gemini** lists answer links whose host matches a citation chip. **Links in Gemini’s answer** lists the remaining links from the answer body.

To make dedicated search, image, and video tools available to regular T3 Code's **Gemini** provider (`%USERPROFILE%\.t3\gemini-bridge\config`), run:

```powershell
.\scripts\install-opencode-tools.ps1
```

Start a new **Gemini** thread in T3 Code so OpenCode reloads tools from `%USERPROFILE%\.t3\gemini-bridge\config\opencode\tools`. It discovers `gemini_app_search`, `gemini_app_generate_image`, `gemini_app_start_video`, and `gemini_app_video_status`. Ask for a web search with sources, an image, or a video. The video tool returns a job ID that can be checked for a download link. Google account access and quotas apply to media generation.

API clients can pass `"web_search_options": {}` in a text chat completion to request website Search. If Gemini omits usable citation links, the bridge includes that status with the answer. Set `"web_search_options": {"require_citations": true}` to require links backed by native citation evidence. Website Search requires a Chrome worker. Image and video are also available through their dedicated API endpoints.

## Deprecated: Windows T3 Code fork

> [!NOTE]
> The custom Windows fork ([`Invictine/t3code` branch `feat/gemini-native-provider`](https://github.com/Invictine/t3code/tree/feat/gemini-native-provider), **T3 Code (Gemini)**) is **deprecated** and unmaintained for this project.

Upstream regular T3 Code now supports adding **Gemini** (`gemini-bridge`) as an isolated OpenCode provider instance directly, so building or running a forked desktop binary is no longer needed. Existing bridge CORS support for `t3code-gemini://app` remains intact only for backward compatibility.

## Verification checklist

- [ ] `.\scripts\setup-windows.ps1` completes its real first-reply check, and `.\scripts\check-bridge.ps1` lists `gemini-4-neon` and `gemini-4-hydrogen`.
- [ ] Regular T3 Code shows the **Gemini** (`gemini-bridge`) provider ready with the signed-in Chrome worker connected.
- [ ] A test prompt in T3 returns a Gemini answer (watch the bridge terminal or `GET /v1/requests` for the request).
- [ ] Tool use works — OpenCode emulates tool calling over the bridge; try a harmless command like listing a directory.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| 403 / login page in bridge log | Cookies expired or DBSC — re-capture fresh values from Chrome (see cookie guide). |
| Models fall back to `gemini-3-flash` | Account not entitled, or alias resolution failed — check the bridge log and re-apply the `config.py` patch. |
| Tool-call parse failures | Emulated calling is best-effort, but failures are no longer silent: the bridge returns a structured `__gemini_tool_error__` tool call (and rejects tool names not supplied in the request) so the agent loop can react. Retry, or use a simpler prompt. |
| Model missing from Gemini's picker | Check which exact models Google offers on the signed-in account. The bridge will show the visible options and refuse to substitute a different model. |
| Port already in use | Change `GEMINI_API_PORT` in `.env` **and** the `baseURL` in `config\t3-neon-opencode.json` (plus `config\opencode-gemini*.json*`). |

## Limitations

- **Local bridge only / remote browsers.** The OpenCode configs target `http://127.0.0.1:<port>`, which is the loopback of the machine running them. This works for a local desktop T3 build and for a remote T3 server whose browser and bridge are on the same host. It does **not** work for a browser on a different machine from the bridge: the browser's `127.0.0.1` is not the T3 server host. Workarounds: run the bridge on the same host as the browser, or tunnel the bridge port (e.g. SSH `-L 8100:127.0.0.1:8100`) so loopback resolves to it.

## Maintenance

- **Update the vendored bridge:**
  ```powershell
  # This is a pinned patched fork. Review upstream updates before merging.
  git -C vendor\gemini-web-api fetch origin
  git -C vendor\gemini-web-api rev-parse HEAD
  Push-Location vendor\gemini-web-api; uv sync; Pop-Location
  ```
- **Re-apply the `config.py` patch after every update.** In `vendor\gemini-web-api\gemini_openai\config.py` (search for `Gemini 4 App aliases`) it adds:
  ```python
  # in _ALIASES
  "argon": "gemini-4-argon",
  "gemini-4-argon": "gemini-4-argon",
  "hydrogen": "gemini-4-hydrogen",
  "gemini-4-hydrogen": "gemini-4-hydrogen",
  "neon": "gemini-4-neon",
  "gemini-4-neon": "gemini-4-neon",
  # after _CANON (keeps _HAS_THINKING logic intact)
  _CANON.update({"gemini-4-argon": "gemini-4-argon",
                 "gemini-4-hydrogen": "gemini-4-hydrogen",
                 "gemini-4-neon": "gemini-4-neon"})
  ```
  Without it, unknown names collapse to `DEFAULT_MODEL` = `gemini-3-flash`.
- **Re-apply the runtime session patch after every upstream update.** It is a second local patch on the vendored bridge (committed in `vendor\gemini-web-api`):
  - `gemini_openai\gemini_pool.py` — `GeminiManager.apply_session()` installs new cookies under the pool lock, clears gemini_webapi's cookie cache, and drops the shared client so the next request re-inits with them. `verify_session()` runs a short throwaway `client.init()` against Google to confirm cookies before anything is saved/applied.
  - `gemini_openai\server.py` — loopback-on-bridge-port/T3 CORS middleware (no `null`), cookie validation (non-empty, <=4096, no CR/LF/NUL/`=`), the `.env` merge helper, and `POST /v1/auth/session` (verifies live before persisting; 401/502 on failure).
  - `gemini_openai\chrome_backend.py` — `/ws` accepts only a valid API key (query param) or a trusted loopback/T3/bundled-extension Origin.
  - Upstream versions may move these functions; after pulling, re-check that all three files still carry the patch before relying on T3 sign-in.
- Google's **RPC IDs** change with web-app deploys. If requests start failing, the upstream bridge usually needs an update — fetch and review upstream updates before merging them into the patched fork.

## Reliability checks

With access to the pinned dependency, run `git submodule update --init --recursive`
in an existing checkout. The tests expect the pinned revision.

```powershell
uv sync --locked --group dev --project vendor/gemini-web-api
Push-Location vendor/gemini-web-api
.\.venv\Scripts\python.exe -m pytest -q
Pop-Location
.\vendor\gemini-web-api\.venv\Scripts\python.exe scripts/test-bridge-scripts.py
.\vendor\gemini-web-api\.venv\Scripts\python.exe scripts/smoke-bridge.py --live
```

The first two suites run without Google credentials. `smoke-bridge.py --live`
tests the cookie backend, independently of the installed Chrome extension. It loads
this project's `.env`, verifies the session, and only tests entitled models. It
checks plain generation, streamed answer content, and a tool-result round trip
using a fresh nonce. It does not execute a shell tool or establish T3 desktop
acceptance. It exits nonzero on missing or
rejected credentials, unavailable target models, or failed checks. It suppresses
upstream logs and does not print cookies or generated content.

Streaming upstream failures now use OpenAI error envelopes, so SDK clients raise
instead of accepting an error message as a completed answer. Initialization is
bounded and retryable auth/API failures get one fresh-client attempt. Streams
are never replayed after output begins. Tool arguments with unresolved code
placeholders or invalid shapes produce a visible tool error instead of a file
write with fabricated or empty content.

See [the validation report](docs/reliability-report.md) for tested behavior and
remaining live acceptance requirements.

### Conversation continuity in Chrome

Follow-ups in a T3 Gemini thread continue in the same Gemini web chat. The bridge uses OpenCode's `X-Session-Affinity` header to keep threads separate and sends new turns and tool results when the supplied history extends the saved conversation. The mapping survives bridge and worker restarts. If the client edits or compacts its history, or Gemini can no longer open the saved chat, the bridge rebuilds context from the supplied transcript in a new chat.

Other OpenAI-compatible clients can opt in with a unique `X-Gemini-Conversation-Id` header per conversation. Keep sending the full `messages` history so the bridge can validate each follow-up. A request without a conversation identifier starts a fresh chat. To activate this feature on an existing installation, restart the local bridge and reload its Chrome extension after updating both.

### Testing the installed Chrome extension

With `GEMINI_BACKEND=chrome` and the bridge running:

```powershell
.\vendor\gemini-web-api\.venv\Scripts\python.exe scripts/smoke-extension.py --model neon --mode full --require-background
.\vendor\gemini-web-api\.venv\Scripts\python.exe scripts/smoke-extension.py --model neon --mode search --require-background
```

This tests the running HTTP bridge, including fresh response markers, streaming,
tool-call emission, and a nonce passed through a harmless tool result. Exact
output formatting is reported separately from marker delivery. To ask the
installed extension to open a dedicated worker tab, add `--open-worker`; Chrome
must be running with the updated extension enabled. The command waits up to 90
seconds for its alarm channel to open the tab.

Generation requests run in the existing background worker tab without activating
it or changing the focused window. With `GEMINI_BACKEND=chrome`, a chat request
can also recover a missing worker on its own. It waits up to 85 seconds for the
extension to open and connect an inactive Gemini tab. Keep Chrome running with
the extension enabled. The background check requires a hidden, unfocused worker
before and after the test.
Authenticated `/v1/extension/diagnostics` reports the model, stage, visibility,
and response structure without returning prompts, response text, or cookies.
