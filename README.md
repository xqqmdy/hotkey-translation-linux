# hotkey-translation

Type text in one language anywhere, get another language back via OpenRouter.
Default direction is Chinese to English; both ends are configurable.

## Flow

1. Run the hotkey you bound, a rofi window pops up
2. Type the source text and press `Enter`; `Ctrl+Tab` switches to the model list
3. `Ctrl+V` pastes the translated result

`Enter` submits the text because rofi runs with `-format f` (it returns the
typed filter, not a selected row), and `-kb-custom-1 Control+Tab` exits with code
10, which the script turns into "open the model window". Models never appear in
the text window, so typing can never be mistaken for a model pick.

The model window lists the live free models; `Enter` selects one and the text
window reopens with the new model. `Esc` there returns to the text window, `Esc`
in the text window quits.

All window text is English regardless of the source language. The rofi theme is
a dark translucent window: monospace 12, `#1e1e2edd` background, `#89b4faff`
border, `#585b70ff` selection, 42em wide.

Rime is only touched when it can help: a Chinese source switches it to Chinese,
a Latin-script source (`en`, `fr`, `de`, ...) switches it to English. Any other
source (`ja`, `ko`, `ar`, ...) leaves the current mode alone, because forcing
English there would send that language's keystrokes down the ASCII path. After
the window the IME is left in English, and the model window restores whatever
mode was active when it opened.

Model choice is not part of the typing flow. The active model is the config
`model` if set, else the last picked one, else the first live free model.

## Binding

The tool assumes no particular key. Bind the command in your compositor or
desktop environment:

```sh
hotkey-translation          # translate window
hotkey-translation --pick   # model window only
```

A second binding for `--pick` is optional; `Ctrl+Tab` inside the translate
window reaches the same list.

## Picking a model

`hotkey-translation --pick` opens the model window directly. The list comes from
the live OpenRouter `/models` response, filtered to free text models. The cache
(`~/.cache/hotkey-translation/models.json`) stores the raw payload, so filter
changes apply on the next read instead of waiting for the TTL. A fresh cache
(default one day) skips the network; a stale one is served immediately and
refreshed in the background, so the window never blocks on `/models`. Only a
missing cache pays one blocking fetch (about half a second here).
`--list-models` prints the current rows, `--refresh-models` updates the cache by
hand.

## Clipboard

Writes go to the first working backend in this order: `wl-copy`, `xclip`,
`xsel`. Reads use `wl-paste` (clipboard, then primary), then `xclip`, then
`xsel`. So the tool runs on a Wayland session with `wl-clipboard`, on X11 with
`xclip` or `xsel`, and on a mixed session with either. Rofi, fcitx5 and the
notification daemon are session-agnostic; rofi 2.x picks its Wayland backend
when `WAYLAND_DISPLAY` is set.

## Setup

```sh
cp config.example.toml ~/.config/hotkey-translation/config.toml
chmod 600 ~/.config/hotkey-translation/config.toml
# edit it, fill openrouter_api_key (https://openrouter.ai/keys)
ln -sf /path/to/hotkey-translation ~/.local/bin/hotkey-translation
```

Note: some free endpoints may log prompts or use them for training; check the
provider policy on OpenRouter before sending anything private.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `clipboard is empty` | No rofi path only: copy first, `Ctrl+C`, then run the hotkey |
| `missing API key` | Fill `openrouter_api_key`, or export `OPENROUTER_API_KEY` |
| `missing language` | Set `source_lang`/`target_lang` in the config |
| `401` | Wrong or revoked key |
| `404` | Model ID retired, pick another with `hotkey-translation --pick` |
| `429` | Free tier quota hit, wait and retry |
| `model returned no translation` | Reasoning model burned `max_tokens` on hidden thinking; raise `max_tokens` or pick another model |
| `no free models` | `/models` unreachable and no cache; check network |
| No notification | `notify-send` missing or D-Bus down; translation still lands in clipboard |

## Test

```sh
./tests/fake_server_test.sh
./tests/pick_test.sh
./tests/lang_test.sh
./tests/keys_test.sh
./tests/cache_test.sh
./tests/clipboard_test.sh
```

`fake_server_test.sh` bypasses the input prompt via `HT_TEXT`/`HT_MODEL` and
asserts the clipboard holds the translated result. `pick_test.sh` stubs rofi and
`/models` to assert the pick is persisted and the free filter holds.
`lang_test.sh` asserts the direction config reaches the system prompt and that
the defaults are `zh` to `en`. `keys_test.sh` replays the window loop (Ctrl+Tab,
model selection, text) with a stub rofi. `cache_test.sh` asserts the raw payload
cache, the warm no-network path, read-time filters, and the stale serve plus
background refresh. `clipboard_test.sh` asserts the X11 fallback.

## License

MIT, see [LICENSE](LICENSE).
