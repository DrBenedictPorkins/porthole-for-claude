# Porthole for Claude — Chrome Extension

## What this is

Chrome MV3 WebExtension. This is the **primary source of truth** — all development happens here.

Load directly in `chrome://extensions` (Developer mode → Load unpacked).

## Architecture

Raw JS/CSS/HTML — no bundler, no build step.

| Layer | Path | Role |
|-------|------|------|
| Background | `background/service-worker.js` | Entry point — aliases `globalThis→window`, imports polyfill + all background scripts |
| Background scripts | `background/*.js` | API calls, tool routing, site knowledge, prompt injection defense, context compression |
| Content Script | `content/content.js` | Page context execution, DOM access, element registry (`tref_N` handles) |
| Sidebar | `sidebar/` | Chat UI, streaming renderer, modals, tab state |
| Options | `options/` | Settings (API key, model, high-risk tools) |
| Viewer | `viewer/` | Renders markdown/HTML reports stored in `browser.storage.local` |

## Key Chrome-specific files

| File | Role |
|------|------|
| `manifest.json` | MV3 manifest — edit directly here |
| `background/service-worker.js` | SW entry point — `globalThis.window = globalThis`, importScripts |
| `sidebar/sidebar-init.js` | Conditional polyfill loader — emits polyfill script tag only when `browser` is undefined (Chrome) |
| `sidebar/lib/browser-polyfill.min.js` | Maps `browser.*` → `chrome.*` for background and content scripts |

## Chrome limitations

- **No response body capture** — `filterResponseData` is Firefox-only. Chrome captures request/response metadata only. `get_network_requests` works, response bodies absent.
- **Service worker lifecycle** — SW terminates after ~30s idle. In-flight streams lost on restart; sidebar detects disconnect and handles gracefully. `tabAutonomyModes` persisted via `chrome.storage.session`.
- **No `downloads.open()`** — Chrome blocks this from background; wrapped in try/catch, fails silently.

## Testing

1. `chrome://extensions` → Developer mode → Load unpacked → select this directory
2. Open any tab → click Porthole icon → side panel opens
3. Service Worker errors: `chrome://extensions` → click "Service Worker" link
4. Sidebar errors: right-click sidebar → Inspect

## Release

```bash
bash scripts/release.sh         # cuts current version, bumps to next
bash scripts/release.sh 1.x.0   # override version
```

Convention: `manifest.json` always carries the **next** (unreleased) version. Cutting a release = tag current, bump to next.
