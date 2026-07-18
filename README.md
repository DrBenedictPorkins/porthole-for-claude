# Foxhole for Claude — Chrome

A Chrome side panel where Claude learns how each website works and remembers it across sessions.

Instead of rediscovering the same selectors, endpoints, and interaction patterns every time, Claude builds persistent site knowledge — profiles, working selectors, API endpoints, multi-step workflows — and uses them on the next visit.

## What makes this different

- **Site profiles** — Claude detects whether a site is UI-driven (React SPA), API-driven, or hybrid, and saves that as a profile. Next visit, it knows the interaction model upfront.
- **Persistent site specs** — Working selectors, API endpoints, storage keys, and multi-step workflows are saved per-domain and injected into every conversation on that site.
- **Spec staleness** — Specs are age-badged (`[aging]` > 3 weeks, `[STALE]` > 2 months). Claude can delete broken ones and save corrected versions.
- **Passive API observer** — Every XHR/fetch is recorded per domain in the background. Claude can query captured endpoints, auth header patterns, and payload shapes via `get_network_requests`.
- **Assistant, not automation** — Claude asks you to handle age gates, logins, and CAPTCHAs instead of trying to automate past them.
- **Prompt injection defense** — Page content is sanitized, marked as untrusted, and wrapped in boundaries before Claude sees it.
- **Context compression** — Screenshots and raw payloads are replaced with semantic summaries in older turns so conversations stay within context limits.
- **Sidebar persistence** — Conversation state per tab survives sidebar close/reopen (24h TTL).

## Install

1. Clone or download this repo
2. `chrome://extensions` → Enable **Developer mode** (top right)
3. Click **Load unpacked** → select this folder
4. Click the Foxhole icon in the toolbar → side panel opens
5. Settings → enter your [Anthropic API key](https://console.anthropic.com/)

## Tools

| Category | Tools |
|----------|-------|
| Tabs | `list_tabs` `get_active_tab` `switch_tab` `create_tab` `close_tab` |
| Navigation | `navigate` `reload_page` `go_back` `go_forward` `get_current_url` `get_page_title` |
| DOM | `dom_stats` `get_page_content` `get_dom_structure` `query_selector` `get_element_properties` `get_computed_styles` `get_element_bounds` `list_frames` |
| Discovery | `get_accessibility_tree` `find_elements` `detect_page_tech` |
| Interaction | `click_element` `type_text` `fill_form` `scroll_to` `hover_element` `focus_element` `press_key` `select_option` `set_checkbox` `upload_file` |
| Dialogs | `handle_dialog` |
| Vision | `take_screenshot` `take_element_screenshot` `read_image` |
| Output | `create_markdown` `create_html` `open_download` |
| Cookies | `get_cookies` `set_cookie` `delete_cookie` |
| Storage | `get_local_storage` `get_session_storage` `set_storage_item` `clear_storage` |
| Browsing Data | `clear_browsing_data` `list_indexeddb` `clear_indexeddb` `list_cache_storage` `clear_cache_storage` `search_history` `delete_history` |
| Script | `execute_script` |
| Wait | `wait_for_element` `wait_for_navigation` `wait` |
| Network | `get_network_requests` `clear_network_requests` `get_network_request_detail` `fetch_url` `fetch_with_session` |
| Clipboard | `read_clipboard` `write_clipboard` |
| Selection | `toggle_selection_mode` `get_user_selections` `clear_user_selections` |
| Knowledge | `save_site_spec` `delete_site_spec` |

## Architecture

Manifest V3 WebExtension. Raw JS/CSS/HTML — no bundler, no build step.

| Layer | Path | Role |
|-------|------|------|
| Background | `background/` | API calls, tool routing, site knowledge, network capture (passive), context compression |
| Content Script | `content/` | Page context — DOM access, element registry, console capture |
| Sidebar | `sidebar/` | Chat UI, streaming renderer, modals, tab state |
| Options | `options/` | Settings (API key, model, high-risk tools) |

## Chrome vs Firefox differences

- **Response body capture** — not available on Chrome (Firefox-only `filterResponseData` API). Request metadata, headers, and status codes are captured.
- **Service worker** — background terminates after ~30s idle; conversation state in the sidebar is unaffected. `tabAutonomyModes` (confirm/auto setting per tab) is persisted to `chrome.storage.session` and restored on restart.

## Privacy

All data stays local (`chrome.storage.local`). The only external call is to Anthropic's API with your key. No telemetry, no tracking.

## License

[PolyForm Noncommercial 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0/) — free for personal, educational, and non-commercial use. Commercial use prohibited.
