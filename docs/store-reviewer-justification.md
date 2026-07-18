# Permission Justification — Porthole for Claude

Porthole for Claude is an AI browser assistant. The user types natural-language requests in a side panel; the extension gives Claude the tools to carry them out on the active page. Every permission below is exercised by a specific, user-invoked tool — nothing runs automatically or in the background beyond passive network observation.

---

## `<all_urls>` host permission

**Why:** Claude needs to operate on whichever site the user is currently on. The extension is not domain-specific — it is a general-purpose assistant. The content script must be injected into every page so Claude can read the DOM, click elements, fill forms, or take screenshots when the user asks.

**What it does NOT do:** It never sends page content anywhere other than the Anthropic API endpoint the user has explicitly configured with their own API key.

---

## `tabs`

**Why:** Claude needs to create tabs (`create_tab`), close tabs (`close_tab`), list open tabs (`list_tabs`), navigate (`navigate`), and read the current tab's URL/title for context. All of these are direct responses to user instructions.

---

## `activeTab`

**Why:** Used alongside `tabs` to access the currently focused tab without requiring persistent access to all tab content.

---

## `webRequest`

**Why:** Used passively and read-only. The extension observes outgoing request URLs and response status codes to help Claude understand a site's API patterns (e.g. "what endpoints does this page call?"). This powers the `get_network_requests` tool.

**Important:** No request bodies or response bodies are read. The extension does not intercept, block, or modify any network traffic.

---

## `webNavigation`

**Why:** Used by the workflow recording feature. When a user records a multi-step workflow, the extension listens for page navigations (`tabs.onUpdated` + `webNavigation`) to insert `navigate` steps into the recorded sequence automatically.

---

## `storage`

**Why:** All extension state is stored locally in `chrome.storage.local`:
- The user's Anthropic API key and model preference
- Per-domain site knowledge (CSS selectors, API endpoints the user has discovered)
- Saved workflows
- Conversation state (so the sidebar survives a service worker restart)
- Debug logs (options page only)

Nothing is synced externally.

---

## `cookies`

**Why:** Exposes three user-invoked tools: `get_cookies` (read cookies for a URL), `set_cookie`, and `delete_cookie`. These are used when a user asks Claude to help debug authentication or session issues on a site they are actively working with.

---

## `clipboardRead`

**Why:** Powers the `read_clipboard` tool. When a user asks Claude to act on something they have copied (e.g. "process this JSON I just copied"), the extension reads the clipboard. This is always an explicit user request.

---

## `clipboardWrite`

**Why:** Powers the `write_clipboard` tool. Claude can write a result (e.g. a generated code snippet or formatted text) to the clipboard when the user asks.

---

## `history`

**Why:** Exposes `search_history` and `delete_history` tools. A user can ask Claude to search their browser history for a URL they visited, or delete specific entries. All invocations are explicit user requests.

---

## `downloads`

**Why:** Claude can download files (`download_file` tool) and search completed downloads (`find_download` tool) when a user asks. The extension also uses `downloads` to save generated reports to disk.

---

## `downloads.open`

**Why:** After a file is downloaded, the extension attempts to open it automatically in the appropriate application. Wrapped in try/catch — Chrome silently rejects this in some contexts and the failure is non-fatal.

---

## `browsingData`

**Why:** Powers the `clear_browsing_data` tool. A user can ask Claude to clear cache, cookies, history, localStorage, or other browser data by data type and time range. This is always an explicit destructive action the user has requested; the extension does not clear browsing data automatically.

---

## Content script on all frames (`all_frames: true`)

**Why:** Many modern web apps render primary content inside iframes (embedded widgets, embedded editors, sub-page navigation). Without `all_frames`, Claude cannot interact with those frames when the user asks it to work with content inside them.

---

## Single external endpoint

The only data that ever leaves the user's machine is the conversation payload sent to `https://api.anthropic.com`. The user provides their own API key in the extension's options page. No other external connections are made. No telemetry, no analytics, no remote configuration.
