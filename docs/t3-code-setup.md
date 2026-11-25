# Gemini in regular T3 Code on Windows

Recent T3 Code builds let you add a second OpenCode provider instance. Give it the label **Gemini** to select it separately in the composer. The settings below give it its own configuration and session data.

1. Follow the [Chrome bridge setup](../README.md#1-set-up-the-signed-in-chrome-bridge). The setup script installs OpenCode 1.14.19 at `%LOCALAPPDATA%\gemini-bridge\runtime\opencode` and checks the signed-in Chrome worker with a real model request.
2. In regular T3 Code, open **Settings → Providers → Add provider** and select **OpenCode**.
3. Set **Label** to `Gemini` and **Instance ID** to `gemini-bridge`. Set **Binary path** to the full path of `opencode.exe` installed by the setup script. Its default location is `%LOCALAPPDATA%\gemini-bridge\runtime\opencode\node_modules\opencode-windows-x64\bin\opencode.exe`. Leave **Server URL** empty so T3 Code starts the runtime. Choose **Add instance**.
4. Select the new **Gemini** instance in **Settings → Providers** and add these variables in **Environment**. Expand `%USERPROFILE%` to your actual Windows profile directory when entering the paths.

   | Variable | Value |
   | --- | --- |
   | `OPENCODE_CONFIG` | Absolute path to [`config/t3-neon-opencode.json`](../config/t3-neon-opencode.json) in your checkout |
   | `OPENCODE_DISABLE_PROJECT_CONFIG` | `1` |
   | `XDG_CONFIG_HOME` | `%USERPROFILE%\.t3\gemini-bridge\config` |
   | `XDG_DATA_HOME` | `%USERPROFILE%\.t3\gemini-bridge\data` |
   | `XDG_STATE_HOME` | `%USERPROFILE%\.t3\gemini-bridge\state` |
   | `XDG_CACHE_HOME` | `%USERPROFILE%\.t3\gemini-bridge\cache` |
   | `GEMINI_API_KEY` | The bridge key from your local `.env`, `gemini-local` by default. Mark the entry sensitive if you set a custom key. |

5. Select **Gemini → Gemini 4 Neon** in the composer. The configuration also offers **Gemini Auto**, **Gemini 4 Argon**, and **Gemini 4 Hydrogen**. Choose **Gemini Auto** when the Gemini web picker offers Auto after the other modes reach their limits. The signed-in account's Gemini web picker determines which models work. If a requested model is unavailable, the bridge reports the failure and keeps the requested model and account fixed.
6. *(Optional)* Run `.\scripts\install-opencode-tools.ps1` to install `gemini_app_search`, `gemini_app_generate_image`, `gemini_app_start_video`, and `gemini_app_video_status` into `%USERPROFILE%\.t3\gemini-bridge\config\opencode\tools`.

The configuration targets the default local port `8100`. If your bridge uses a different port, point `OPENCODE_CONFIG` to a local copy of the file with the matching `baseURL`.

> [!NOTE]
> Regular T3 Code replaces the deprecated **T3 Code (Gemini)** Windows fork (`Invictine/t3code` branch `feat/gemini-native-provider`).
