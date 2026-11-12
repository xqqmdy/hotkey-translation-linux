# hotkey-translation

System-wide hotkey: type text in one language anywhere, get another language
back via OpenRouter. Default direction is Chinese to English; both ends are
configurable.

## Flow

1. Press `Mod+Y`, a rofi window pops up
2. Type the source text and press `Enter`; `Ctrl+Tab` switches to the model list
3. `Ctrl+V` pastes the translated result

`Enter` submits the text because rofi runs with `-format f` (it returns the
typed filter, not a selected row), and `-kb-custom-1 Control+Tab` exits with code 10,
which the script turns into "open the model window". Models never appear in the
text window, so typing can never be mistaken for a model pick.

The model window lists the live free-model list; `Enter` selects one and the
text window reopens with the new model. `Esc` there returns to the text window,
`Esc` in the text window quits.

All window text is English regardless of the source language. The rofi theme
mirrors `~/.config/fuzzel/fuzzel.ini` (monospace 12, `#1e1e2edd` background,
`#89b4faff` border, `#585b70ff` selection, 42em wide), so the window looks the
same as the fuzzel version did.

Rime is set for the source language while the window is open: Chinese source
forces the Chinese IME, any other source forces English, and English is left
behind afterwards. Rime only knows those two modes, so a third language keeps
whichever of the two is closer.

Model choice is not part of the typing flow. The active model is the config
`model` if set, else the last picked one, else the first live free model.

## Picking a model

`Mod+Shift+Y` (or `hotkey-translation --pick`) opens the model window directly.
The list comes from the live OpenRouter `/models` response, filtered to free
text models, and is cached for `models_ttl_secs` (a stale cache is used when the
network is down).

## Setup

```sh
cp config.example.toml ~/.config/hotkey-translation/config.toml
chmod 600 ~/.config/hotkey-translation/config.toml
# edit it, fill openrouter_api_key (https://openrouter.ai/keys)
ln -sf ~/data/code/hotkey-translation/hotkey-translation ~/.local/bin/hotkey-translation
```

Niri binds (`~/.config/niri/binds.kdl`, Apps section):

```kdl
Mod+Y repeat=false { spawn "/home/xqqmdy/.local/bin/hotkey-translation"; }
Mod+Shift+Y repeat=false { spawn "/home/xqqmdy/.local/bin/hotkey-translation" "--pick"; }
```

Then reload Niri config (`niri msg action load-config-file` or re-login).

Note: some free endpoints may log prompts or use them for training; check the
provider policy on OpenRouter before sending anything private.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `clipboard is empty` | No rofi path only: copy first, `Ctrl+C`, then hotkey |
| `missing API key` | Fill `openrouter_api_key`, or export `OPENROUTER_API_KEY` |
| `missing language` | Set `source_lang`/`target_lang` in the config |
| `401` | Wrong or revoked key |
| `404` | Model ID retired, press `Mod+Shift+Y` to pick another |
| `429` | Free tier quota hit, wait and retry |
| `no free models` | `/models` unreachable and no cache; check network |
| No notification | `notify-send` missing or D-Bus down; translation still lands in clipboard |

## Test

```sh
./tests/fake_server_test.sh
./tests/pick_test.sh
./tests/lang_test.sh
./tests/keys_test.sh
```

`fake_server_test.sh` bypasses the input prompt via `HT_TEXT`/`HT_MODEL` and
asserts the clipboard holds the translated result. `pick_test.sh` stubs
rofi and `/models` to assert the pick is persisted and the free filter holds.
`lang_test.sh` asserts the direction config reaches the system prompt and that
the defaults are `zh` to `en`. `keys_test.sh` replays the window loop (Ctrl+Tab,
model selection, text) with a stub rofi.
