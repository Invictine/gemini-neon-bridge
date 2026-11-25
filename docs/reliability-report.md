# Reliability validation

> [!NOTE]
> **2026-11-25:** The custom Windows fork (**T3 Code (Gemini)** / `feat/gemini-native-provider`) referenced in the November 20 historical records below is now **deprecated** in favor of regular upstream T3 Code configured with a separate `gemini-bridge` OpenCode provider instance ([setup guide](t3-code-setup.md)).

This report separates code-level reliability from live Google model behavior.

## Current result

The Windows Gemini edition offers **Gemini 4 Neon** (`gemini-app/neon`). On 20
November, Neon passed live plain generation, streaming, the required
`get_status` tool call, and the tool-result nonce round trip. The streaming
reply contained its fresh marker with additional formatting. Chrome reported
the worker hidden and unfocused before and after the run.

The bridge selects the `4 Neon` option by its exact picker label.
OpenCode 1.14.19 also completed a live Neon file-read round trip. The `read`
tool opened a temporary file, and Neon's final answer contained the exact
random marker stored in it.

Installed **T3 Code (Gemini) 0.0.38-gemini.1** on Windows alongside the existing
T3 Code installation. Its Start menu shortcut points to the separate executable,
and its isolated settings select Neon. The installed binary started its backend
in a hidden smoke test and served the environment endpoint and bundled web app.

## Installed-edition session-start failure (20 November)

The installed Gemini edition initially failed every `startSession`. The server
trace recorded `ProviderAdapterProcessError`: the bundled OpenCode exited with
code 1 during startup after `ConfigInvalidError` at
`%USERPROFILE%\.config\opencode\opencode.jsonc`, rejecting the keys
`subagent_depth`, `tool_output`, and `attachment`. Those keys belong to the newer
OpenCode 2.2.5 config used by the regular installation, not to the bundled
OpenCode 1.14.19. No turn had completed through the installed app.

The cause was ineffective config isolation in `GeminiDriver.ts`. It set
`OPENCODE_CONFIG_CONTENT`, which OpenCode v1 **merges** with the global config,
and a misspelled `OPENCODE_CONFIG_PROJECT_DISABLE` (the real flag is
`OPENCODE_DISABLE_PROJECT_CONFIG`, and it only disables project-local config).
The spawned server therefore still loaded and validated the regular config. A
second collision came from the shared `~/.local/share/opencode/opencode.db`,
whose newer schema broke v1's first-run migration.

The installed app was repaired without a rebuild by adding an `environment`
array to `providerInstances.gemini` in
`%USERPROFILE%\.t3-gemini\userdata\settings.json`. It sets `XDG_CONFIG_HOME`,
`XDG_DATA_HOME`, and `XDG_STATE_HOME` to Gemini-owned directories and the correct
`OPENCODE_DISABLE_PROJECT_CONFIG=1` flag. Provider-instance variables reach the
spawned process, and settings changes hot-reload. The same isolation was patched
into `GeminiDriver.ts` in the `feat/gemini-native-provider` fork so future builds
are correct by default.

After the fix, a one-shot bundled-OpenCode run started cleanly, completed its own
database migration, and reached the bridge. A stale worker first reported
“Gemini mode picker was not found”; opening a fresh worker with
`POST /v1/extension/open-worker` resolved it. A subsequent live turn through
bridge → Chrome extension → Gemini returned the exact fresh marker with HTTP
200, and diagnostics showed stage `complete`, model `Neon`, worker hidden and
unfocused. This was the first completed turn through the installed path.

## Earlier model checks

On 20 November, the signed-in picker showed `4 Hydrogen` and `4 Neon`, with no
`4 Argon` option. A live Hydrogen plain prompt through the background bridge
returned its exact marker. Argon requests fail at model selection and include
the options the picker exposed. The bridge does not substitute Neon for Argon.
Hydrogen also passed the required `get_status` call and consumed its returned
nonce in a follow-up. The standalone streaming check failed in the same run.

Windows Task Scheduler started the Chrome bridge after the previous process was
stopped. Its hidden per-user task runs at sign-in and exited successfully after
checking the new listener. The unpacked extension reconnected independently.

The extension now operates in the background. Requests use the existing Gemini
worker without activating its tab or window, and recovery opens new worker tabs
with `active: false`. The installed worker was live-verified after recovery;
diagnostics showed it hidden and unfocused before and after requests.

On 18 November, both Argon and Hydrogen passed the live plain-generation check
through `/v1/chat/completions` after the service worker timing fix. Each returned
its exact fresh marker from a multiline prompt. Worker diagnostics were hidden
and unfocused before and after the run. An earlier full Hydrogen run also
passed SSE streaming, a required `get_status` tool call, and a tool result with
a fresh nonce in the background.

The subsequent full run on 18 November kept the worker hidden and unfocused.
Argon reached the response deadline on the plain check, so its streaming and
tool checks were skipped. Hydrogen passed plain generation and streaming. The
required tool call was missing in that run, so there was no tool round trip.

Earlier live checks failed intermittently. Argon returned Google's “I'm having
a hard time fulfilling your request” message in one probe and did not finish
before the bridge deadline in another. Both models also hit a fresh-chat error
on a stale worker before their prompts were submitted. These failures remain
relevant to repeatability.

## Local verification

- 102 Python tests passed, including a loopback chat request that waits for
  recovery and completes when a test extension connects.
- 34 extension Node tests passed, including background-only tab creation,
  heartbeat/reload recovery, model selection, fresh-chat isolation, multiline
  prompt insertion, hidden Markdown/code extraction, and tool-result handling.
- 4 PowerShell bridge black-box checks passed.
- OpenAI error-envelope behavior was verified: upstream failures become client
  errors rather than successful assistant text.
- The pinned bridge passed its hosted Python and Node checks.

These tests do not prove live entitlement, quota, model identity, cookie
longevity, or end-to-end T3 desktop use.

## Important fixes

- Neon, Argon, and Hydrogen requests fail explicitly when unavailable. The account default
  is never presented under the requested model name.
- Initialization has a bounded retry path with failed-client cleanup and
  protection against an old request resetting a newer client.
- Stream failures, missing required tools, invalid tool arguments, and
  unresolved file placeholders return structured errors.
- Cookie input is validated before use and authentication exceptions are not
  echoed back to callers.
- The launcher pins the project `.env` path, propagates bridge exit status, and
  can start a hidden process with `-Background`. Hidden startup and a second
  invocation reusing the healthy process were verified locally.
- Multiline prompts use a verified synthetic paste path; truncated first-line
  submissions are rejected. Fresh-chat setup waits for the prior turn to clear,
  and response scraping excludes stale nodes while preserving hidden Markdown
  and code blocks.
- The service worker owns the WebSocket heartbeat and recovery polling, so a
  hidden tab can remain connected without foreground UI control.
- A normal chat request in forced Chrome mode queues a missing worker. Calls
  share the recovery window and stop waiting after 85 seconds.
- The service worker runs short UI waits for hidden tabs, and response stability
  is measured by elapsed time. A timed-out chat does not send the prompt again.

## Live limitations

The saved two-cookie session was previously unauthenticated and discovered only
`gemini-flash-lite`. Current live checks use the signed-in Chrome session.

The previous OpenCode runtime was incompatible with T3's native server API.
The Windows edition uses a dedicated OpenCode 1.14.19 installation. Its native
server completed a read tool round trip against a synthetic provider. Long-duration
endurance and quota behavior remain unverified.

## Reproduce

Run the local suites from the project root:

```powershell
Push-Location vendor\gemini-web-api
.\.venv\Scripts\python.exe -m pytest -q
node --test tests/extension_model_test.cjs tests/extension_background_test.cjs
Pop-Location
.\vendor\gemini-web-api\.venv\Scripts\python.exe scripts/test-bridge-scripts.py
```

For a live installed-extension check, start the bridge with the Chrome backend
and run:

```powershell
.\vendor\gemini-web-api\.venv\Scripts\python.exe scripts/smoke-extension.py --model neon --mode full --require-background
```

The live command is single-attempt per check, never prints credentials or
generated text, and exits nonzero when a model fails.
