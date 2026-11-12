# hotkey-translation

System-wide hotkey: type text in one language anywhere, get another language
back via OpenRouter. Default direction is Chinese to English; both ends are
configurable.

## Flow

1. Press `Mod+Y`, a fuzzel window pops up
2. Type the source text, `Enter`
3. `Ctrl+V` pastes the translated result

Source and target come from `source_lang` / `target_lang` in the config
(defaults `zh` to `en`). Any code the model understands works (`ja`, `ko`,
`fr`, `de`, ...); common codes are mapped to full names for the prompt, and
unknown ones are passed through as-is.

When the source language is Chinese, the input window switches rime to Chinese
through D-Bus `SetAsciiMode` on open and leaves it in English after `Enter`.
Other source languages leave the IME untouched, since rime only toggles
Chinese and English.

Model choice is not part of this flow. The active model is the config `model`
if set, else the last picked one, else the first live free model.

## Picking a model

`Mod+Shift+Y` (or `hotkey-translation --pick`) opens a picker built from the
live OpenRouter `/models` response, filtered to free text models. The list is
tab-separated (id, name, context) and rendered with `--with-nth` columns; the
selected id is stored in `~/.cache/hotkey-translation/last_model`, so the next
`Mod+Y` uses it without asking. There is no hand-written model list to
maintain.

The fetched list is cached for `models_ttl_secs` (default one day); a stale
cache is still used when the network is down.

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
| `clipboard is empty` | No fuzzel path only: copy first, `Ctrl+C`, then hotkey |
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
```

`fake_server_test.sh` bypasses the input prompt via `HT_TEXT`/`HT_MODEL` and
asserts the clipboard holds the translated result. `pick_test.sh` stubs fuzzel
and `/models` to assert the tab-column picker format and that the pick is
persisted. `lang_test.sh` asserts the direction config reaches the system
prompt and that the defaults are `zh` to `en`.
