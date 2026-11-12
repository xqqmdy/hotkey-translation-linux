# zh2en

System-wide hotkey: type/select Chinese anywhere, get English back via OpenRouter.

## Flow

1. Press `Mod+Y`, a fuzzel window pops up
2. Type Chinese, `Enter` (the input window switches rime to Chinese via D-Bus `SetAsciiMode` on open, and leaves it in English after Enter)
3. Pick a model (`Enter` confirms the preselected default, or type to filter, or type any custom `:free` ID), `Enter`
4. `Ctrl+V` pastes the English result

The picker step overwrites the clipboard with the English translation and shows it in a notification, so step 4 works in any app. `Esc` at either prompt aborts silently.

## Setup

```sh
cp config.example.toml ~/.config/zh2en/config.toml
chmod 600 ~/.config/zh2en/config.toml
# edit ~/.config/zh2en/config.toml, fill openrouter_api_key (https://openrouter.ai/keys)
ln -sf ~/data/code/zh2en/zh2en-hotkey ~/.local/bin/zh2en-hotkey
```

Niri bind (`~/.config/niri/binds.kdl`, Apps section):

```kdl
Mod+Y repeat=false { spawn "/home/xqqmdy/.local/bin/zh2en-hotkey"; }
```

Then reload Niri config (`niri msg action load-config-file` or re-login).

## Model list

The second prompt lists every ID in `models` with `model` preselected.
Default: `google/gemma-4-31b-it:free`. Free `:free` IDs rotate frequently; if the
hotkey reports 404, pick another entry in the picker or edit the list in
`~/.config/zh2en/config.toml`. Live list: https://openrouter.ai/models (filter free).

Note: some free endpoints may log prompts or use them for training; check the
provider policy on OpenRouter before sending anything private.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `clipboard is empty` | No fuzzel path only: copy first, `Ctrl+C`, then hotkey |
| `missing API key` | Fill `openrouter_api_key`, or export `OPENROUTER_API_KEY` |
| `401` | Wrong or revoked key |
| `404` | Model ID retired, pick another from the config list |
| `429` | Free tier quota hit, wait and retry |
| No notification | `notify-send` missing or D-Bus down; translation still lands in clipboard |

## Test

```sh
./tests/fake_server_test.sh
```

Spins a local fake OpenRouter server, bypasses both fuzzel prompts via
`ZH2EN_TEXT`/`ZH2EN_MODEL`, runs the hotkey script against it, and asserts the
clipboard holds the English result.
