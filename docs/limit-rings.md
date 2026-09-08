# Codex Pet Limit Rings

Codex Pet Limit Rings is a native macOS companion app for Codex pets. It does not patch Codex, replace pet art, or modify the Codex app bundle. It follows the current pet with a transparent always-on-top window and exposes its own menu-bar icon.

The rings are pet-agnostic. They work with any pet Codex displays because the app tracks the pet window bounds rather than reading, editing, or understanding the pet artwork.

## Experience Contract

- A rings icon appears in the macOS menu bar.
- `Show Rings` toggles the overlay without quitting the app.
- `Ring Colors` selects separate outer-ring and inner-ring presets or macOS custom colors for the current pet.
- `Ring Opacity` selects separate outer-ring and inner-ring opacity presets for the current pet.
- `Refresh Now` rereads usage and pet-position state.
- Hovering over the ring or pet shows exact remaining percentages and reset timing.
- Dragging the pet makes the rings follow the gesture immediately while Codex persists the new position.
- Right-clicking the ring or pet opens Codex Settings through Codex's settings deep link.
- Closing the Codex pet hides the rings.
- Multi-display positioning uses the screen containing the pet bounds, not the currently focused screen.
- macOS desktop/Space switching keeps the rings visible with the pet rather than tying them to one active desktop.
- Switching to another Codex pet requires no extra setup; the overlay follows the active pet.

## Data Flow

The app reads live usage first, then local files as support or fallback:

- `https://chatgpt.com/backend-api/wham/usage`: live usage endpoint, called with the local ChatGPT access token from `~/.codex/auth.json`.
- `~/.codex/auth.json`: local ChatGPT auth token used for the live usage call.
- `~/.codex/.codex-global-state.json`: current pet bounds, using `electron-avatar-overlay-bounds.mascot` or compatible mascot geometry under `byDisplayId` / `byResolution` when Codex writes an incomplete top-level record.
- `electron-avatar-overlay-open` in the same state file: whether the Codex pet is currently open.
- `~/.codex/config.toml`, `[desktop]`: current `selected-avatar-id`, `avatar-overlay-mascot-width-px`, and `avatar-overlay-pet-visible` settings. Older installations fall back to `electron-persisted-atom-state.selected-avatar-id` for per-pet colors.
- `~/.codex/logs_2.sqlite`: fallback source using the newest `codex.rate_limits` event when the live usage call fails.

The app caches only the latest desktop pet preferences and reparses the config when its modification time, size, or inode changes. The existing two-second frame timer also picks up config edits, including atomic file replacement. No additional polling timer, child process, accessibility permission, or screen capture is required. Configs larger than 1 MiB are not parsed; the reader uses defaults instead. The small preference reader supports single-line integer, boolean, basic-string and literal-string values in a `[desktop]` table (including quoted table/key names and trailing comments); it is not a general TOML parser.

The app watches `~/.codex/.codex-global-state.json` with a macOS file event source, so pet open/close and position writes trigger an immediate frame update. A slow frame timer remains as a fallback in case the file is replaced or an event is missed.

On multi-display setups, Codex can persist only the selected display id and moving mascot origin at the top level while keeping mascot size in a nested display or resolution entry. The app selects a compatible nested size and combines it with the live top-level mascot origin without reapplying the nested entry's stale relative offset, so the rings remain aligned and continue to follow pet drags.

Current native Codex builds persist a mascot anchor directly as `x` / `y` and omit the `mascot` rectangle. When no legacy rectangle is available, a recognized placement and display record enables native fallback geometry. Width comes from the desktop size setting (80–224 px); height follows the renderer’s 192:208 aspect ratio. At the default setting of 112, the current renderer uses 7.04rem, so the fallback uses 113 × 123 after upward rounding at a 16px root font. This is a compatibility assumption tied to the current renderer, not a live measurement: nonstandard root font scaling and future layout changes may require an update. Unknown or malformed explicit geometry remains hidden.

No OpenAI API key is required. The menu summary says `Live` when the direct usage read succeeds and `Cached` when it is showing the local event-log fallback.

Codex may move the weekly bucket into the API's primary slot when the short-window limit is temporarily unavailable. The app classifies available buckets by their window duration, so a seven-day bucket remains the weekly inner ring instead of being mislabeled as the short-window ring.

## Rendering Model

- Outer ring: short-window remaining percentage.
- Inner ring: weekly remaining percentage.
- Healthy ring colors come from the selected outer-ring and inner-ring presets or custom colors for the current pet. Built-in presets include Default, Sakura, Amber, Purple, Brown, Emerald, Aqua, Ruby, Lime, and Graphite.
- Outer and inner ring opacity come from separate presets for the current pet.
- Ring colors still move to amber for low capacity and red for critical capacity.
- Exact percentages and reset timing are shown only on hover to keep the pet feeling ambient rather than dashboard-like.
- Additional model-limit buckets may appear as small outer markers when available.

Color and opacity settings are saved in the app's macOS defaults domain using the selected pet id as part of the key. Outer and inner ring choices are stored separately. Custom colors are saved as RGB hex values selected through the macOS color panel. If a pet has no saved preset or custom color, the app falls back to the default preset. Older single-color-preset settings are still read as a compatibility fallback. They do not modify Codex pet assets or the Codex app bundle.

## Install Contract

`tools/install-limit-rings.sh` builds:

```text
~/Applications/CodexPetLimitRings.app
```

and installs:

```text
~/Library/LaunchAgents/com.codex-pet.limit-rings.plist
```

The LaunchAgent starts the app at login. The installer also removes the earlier prototype app and LaunchAgent names if present:

```text
~/Applications/CodexLimitAura.app
~/Library/LaunchAgents/com.codex-pet.limit-aura.plist
```

`tools/uninstall-limit-rings.sh` unloads the LaunchAgent, removes the app bundle, clears saved app preferences including pet color and opacity settings, and also cleans up those earlier prototype names.

## Development

Build and run the app from the repository:

```bash
tools/run-limit-rings.sh
```

Render a static preview:

```bash
swiftc tools/codex-pet-limit-rings.swift -o tmp/codex-pet-limit-rings -framework AppKit -lsqlite3
tmp/codex-pet-limit-rings --preview tmp/limit-rings-preview.png --size 164
```


Run the geometry and preference regression checks (no live credentials or GUI required):

```bash
tools/test-pet-frame-reader.sh
```

## Codex Skill

The repository includes a skill at `skills/codex-pet-limit-rings/`. Copy that folder into `~/.codex/skills/` or run `tools/install-codex-skill.sh` to make Codex auto-discover the workflow in future sessions.

The skill intentionally points agents at the companion-app boundary and validation commands. It should not encourage app-bundle patching as the default path.
