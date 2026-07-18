# Site Manipulation Playbook

Hard-won techniques for reading and driving modern (SPA/GraphQL) websites from a
browser extension. Distilled from the Nextdoor Moderator extension port
(Firefox MV2 → Chrome MV3), where the sites actively hide their state from
naive DOM scraping. Applies directly to Porthole's `content/content.js`,
`background/api-observer.js`, `background/interaction-observer.js`, and the
Chrome port under `manifest.chrome.json`.

The through-line: **the DOM is a lossy render of the real state. The real state
lives in the framework's JS objects and in the site's API traffic.** When
scraping the DOM fails or goes stale, reach for one of these.

---

## 1. The isolated-world / page-world boundary (know which side you're on)

Extension content scripts do **not** share a JS context with the page. This is
the single most important thing to internalize, and Firefox and Chrome differ:

- **Firefox (MV2):** content scripts run in a sandbox with an **Xray wrapper**
  over `window`. You see a "clean" DOM but **not** the page's own JS
  properties added to objects (e.g. framework expandos on DOM nodes). To reach
  the page's real objects, go through `.wrappedJSObject`:
  ```js
  // Firefox content script — read a page-defined expando on a DOM node
  const pageNode = node.wrappedJSObject;      // page's view, incl. expandos
  const pageWin  = window.wrappedJSObject;     // page's real window/globals
  ```
  This is a Firefox superpower — no separate injected script needed for reads.

- **Chrome (MV3):** the isolated world has **no** equivalent of
  `wrappedJSObject`. To touch page JS you must run a script in the **MAIN
  world** (`"world": "MAIN"` content script, or an injected `<script>`), and
  bridge results back with `window.postMessage`. Page CSP usually blocks inline
  `<script>` injection, which is why a declared `world: "MAIN"` content script
  is the reliable route.

**Rule of thumb:** in Firefox, try `wrappedJSObject` first. In the Chrome port,
budget for a MAIN-world relay + postMessage bridge for the same capability.

---

## 2. Read SPA state from the framework, not the DOM (React fiber)

When the data you need (an id, an author, the full object behind a card) is
**not in the DOM** — React/Vue keep it in component state, not attributes.

React attaches expandos to DOM nodes: `__reactFiber$<hash>` (React 17+) or
`__reactInternalInstance$<hash>` (older). Walk up `.return` from any rendered
node to find the component whose `memoizedProps` holds the object you want.

```js
// Firefox: no injected script needed — use wrappedJSObject
function reactPropsFromNode(node) {
  const n = node.wrappedJSObject || node;
  const key = Object.keys(n).find(k =>
    k.startsWith('__reactFiber$') || k.startsWith('__reactInternalInstance$'));
  let fiber = key ? n[key] : null;
  let depth = 0;
  while (fiber && depth < 60) {          // cap the walk — fibers can loop
    const p = fiber.memoizedProps;
    if (p && p.post) return p;           // <-- your target prop
    fiber = fiber.return;
    depth++;
  }
  return null;
}
```

Anchor the walk on a **stable semantic node** (see §6), e.g.
`document.querySelector('button[aria-label="Close expanded post"]')`, not a
brittle nth-child path. In the Chrome port this exact walk has to happen inside
a MAIN-world script that posts the result back.

**Why this matters for Porthole:** when a tool needs to identify "what is the
user actually looking at right now" and the id isn't in the DOM, the fiber is
the source of truth — especially after client-side navigation (§3).

---

## 3. SPAs fire NO network request on cached / client-side navigation

The trap that cost the most debugging time: clicking "next", opening a cached
item, or navigating within an SPA often renders **entirely from an in-memory
store** and issues **zero network requests**. Consequences:

- Anything keyed off `webRequest` / `api-observer` **goes stale** — you keep
  serving the last captured response while the user has moved on.
- The new item's id may never appear in any request you can see.

**Fixes:**
- Don't treat "last captured API response" as "current state." Re-derive
  current state from the DOM or the fiber (§2) on demand.
- Detect client-side navigation via `history.pushState`/`popstate` and DOM
  mutation observers, **not** only via network events. Porthole's
  `interaction-observer.js` is the natural home for this.
- Invalidate/clear cached per-view state when the view changes, even with no
  network signal.

---

## 4. Capturing response bodies: Firefox has it easy, Chrome doesn't

- **Firefox (MV2):** `browser.webRequest.filterResponseData(requestId)` gives
  you a stream of the actual response body. This is the clean way and Porthole
  already holds `webRequest`/`webRequestBlocking`. Use it in `api-observer.js`
  to read GraphQL/JSON payloads directly.
  ```js
  browser.webRequest.onBeforeRequest.addListener((details) => {
    const filter = browser.webRequest.filterResponseData(details.requestId);
    const chunks = [];
    filter.ondata = e => { chunks.push(e.data); filter.write(e.data); };
    filter.onstop = () => {
      filter.close();
      const body = chunks.map(c => new TextDecoder('utf-8').decode(c)).join('');
      // parse body …
    };
  }, { urls: ['*://*/api/gql/*'] }, ['blocking']);
  ```

- **Chrome (MV3):** there is **no** `filterResponseData`. Response bodies are
  unreadable from the service worker. The workaround is to monkey-patch
  `window.fetch` and `XMLHttpRequest` in a MAIN-world content script at
  `document_start`, clone the response, and `postMessage` the text out to the
  isolated-world script, which forwards it to the worker. Budget for this in
  the Chrome port — it's ~3 hops (page → isolated → worker) and must install
  before the site's own app code runs.

---

## 5. Talking to a site's own API (GraphQL persisted queries)

Modern sites use Apollo **persisted queries (APQ)**: the client doesn't send the
query text, only its hash. A request looks like:

```
POST /api/gql/<OperationName>
{
  "operationName": "SubmitModerationChoice",
  "variables": { ... },
  "extensions": { "persistedQuery": { "version": 1, "sha256Hash": "<hex>" } }
}
```

To **replay or call** such an API yourself:
- **The hash is not yours to invent** — harvest it from an observed request
  (`api-observer.js`). It changes when the site ships a new query version, so
  never hardcode it long-term; capture it live.
- You need the site's auth surface: the **CSRF token** (usually a cookie like
  `csrftoken`, echoed in an `x-csrftoken` header) plus **site-specific
  headers** the app sends (release/build tokens, locale, request-time stamps).
  Sniff a real request and mirror its header set.
- The call must originate from the **page origin with credentials** — a
  cross-origin `fetch` from the wrong context gets a 403. In Firefox you have
  more latitude; in the Chrome port, do the `fetch` from a MAIN-world script so
  it carries the page's origin and cookies.

**Caution / Porthole design fit:** replaying write-mutations (voting, posting,
deleting) is powerful and risky. Keep it behind explicit user confirmation —
consistent with Porthole's "Assistant, Not Automation" stance. Prefer reads;
gate writes.

---

## 6. Anchor on stable semantics, not DOM position

SPAs re-render constantly and destroy/recreate nodes. Two consequences:

- **A cached DOM node reference or nth-child selector rots.** Re-resolve by a
  stable signal each time: `aria-label`, `data-*`, a role, or the fiber id
  (§2). Porthole's `tref_N` element-registry handles should resolve to elements
  by re-querying stable attributes, not by holding a detached node.
- To find data, **walk from a semantic anchor**. "The close button of the
  expanded post" (`button[aria-label="Close expanded post"]`) is durable; a
  path like `div > div:nth-child(3) > span` is not.

---

## 7. "Load more" / pagination is adversarial — guard against it

Two real failure modes when auto-expanding content:

- **Infinite no-op loop.** A "See more comments" control can be a persistent
  element that never disappears and does nothing (already fully loaded). A
  naive "click until it's gone" loops forever. **Stall-guard:** track a cheap
  progress metric (e.g. `document.getElementsByTagName('*').length`); after N
  consecutive clicks with **no growth**, abandon.
  ```js
  let stalls = 0, last = countNodes();
  while (moreBtn() && stalls < 2) {
    moreBtn().click();
    await sleep(400);
    const now = countNodes();
    if (now <= last) stalls++; else { stalls = 0; last = now; }
  }
  ```
- **Servers lie about totals.** A `totalCount` / "N results" field frequently
  **over-reports** (counts deleted/hidden items). Don't drive "X items are
  missing" warnings off it — gate on the authoritative
  `pageInfo.hasNextPage` and only warn when there's genuinely a next page.

---

## 8. Clipboard writes fail silently — always catch + fall back

`navigator.clipboard.writeText()` requires document focus **and** transient user
activation. When it rejects it does so silently; a `.then()`-only handler shows
no error and nothing lands on the clipboard — reads to the user as "the button
is broken."

```js
async function copy(text, btn) {
  try {
    await navigator.clipboard.writeText(text);
    flash(btn, '✓ Copied');
  } catch {
    // Fallback: temp textarea + execCommand (works without focus in more cases)
    const ta = document.createElement('textarea');
    ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0';
    document.body.appendChild(ta); ta.select();
    const ok = document.execCommand('copy');
    ta.remove();
    flash(btn, ok ? '✓ Copied' : 'Copy failed');   // <-- always show a state
  }
}
```

Rule: every clipboard action needs a `.catch` **and** a visible failure state.

---

## 9. Clicking elements in a framework SPA

- **The "button" is rarely a `<button>`.** SPAs render clickable controls as
  `div[role="button"]`, `<a>`, or styled `<span>`s. A `<button>`-only selector
  silently misses them. Query both and match by **role + text**:
  ```js
  const btn = [...document.querySelectorAll('[role="button"], button')]
    .find(el => /see more comments/i.test(el.textContent.trim()));
  ```
- **Plain `element.click()` works on React `onClick`.** React 17+ attaches a
  single **delegated** listener at the root; a native `.click()` dispatches a
  real, bubbling `MouseEvent` that reaches it. You usually do **not** need to
  hand-craft events for a normal click.
- **When `.click()` isn't enough** — widgets that listen for a pointer/mouse
  sequence, hover, or focus (drag handles, custom dropdowns, canvas UIs).
  Dispatch the full sequence, all with `bubbles: true`:
  ```js
  for (const type of ['pointerdown', 'mousedown', 'mouseup', 'click']) {
    el.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, view: window }));
  }
  el.focus?.();
  ```
- **The `isTrusted` gotcha.** Synthetic events are `isTrusted: false`. A few
  sites gate real actions on trusted events and you **cannot forge that** from a
  content script — only a genuine user gesture qualifies. In the Chrome port,
  CDP `Input.dispatchMouseEvent` (via the debugger) produces trusted events;
  Firefox has no content-script equivalent.
- **Click is async.** It kicks off network + re-render — don't read state on the
  next line. Settle on a progress signal (we polled `document.getElementsByTagName('*').length`
  growth and treated "no growth after N clicks" as done — §7 stall-guard).
  `scrollIntoView()` first if the list virtualizes offscreen rows out of the DOM.

**Companion — typing into React inputs.** Setting `input.value = x` does **not**
notify React (its `onChange` never fires, so the app never sees the text). Use
the native setter + an `input` event:
```js
const setter = Object.getOwnPropertyDescriptor(
  window.HTMLInputElement.prototype, 'value').set;   // or HTMLTextAreaElement
setter.call(input, text);
input.dispatchEvent(new Event('input', { bubbles: true }));
```
Directly relevant to any Porthole tool that fills a site form.

---

## 10. Tracking elements across re-renders (handles / weak-hash)

To let a tool refer to an element on a *later* turn ("click element 7" —
Porthole's `tref_N` registry), you assign each element a stable handle and keep
the mapping. Two different "hashes" are in play; they behave oppositely.

**The page-side hash is not yours.** React's `__reactFiber$<hash>` suffix is a
random string React picks **once per page load** to namespace its own expando —
not content-derived, not stable across reloads. Match it by **prefix**, never
hardcode it (§2). It locates React's data; it is not a tracking id.

**Your tracking id — store it weakly:**
```js
const handleFor = new WeakMap();   // Element  -> "tref_7"
const byHandle  = new Map();        // "tref_7" -> WeakRef(Element)
```
Why `WeakMap`/`WeakRef`: the element is held **weakly**, so when the SPA unmounts
that node the entry is **garbage-collected automatically** — no memory leak, no
zombie handle pointing at a detached node.

**The catch — weak tracking does not survive re-renders.** SPAs re-render by
creating a **brand-new element object** for what is logically "the same button."
A `WeakMap` keyed on the old node object therefore:
- drops the old node's handle when it's GC'd, and
- gives the visually-identical replacement **no** handle,

even though nothing changed for the user. Weak storage cleans up correctly but
**can't preserve identity** — there's no stable object to hang onto.

**The robust pattern is hybrid.** Don't trust the cached handle as ground truth.
Each turn, **re-resolve** the handle to a *live* element by a stable signal —
`aria-label` / `data-*` / role / the fiber id (§2, §6) — then refresh the
WeakMap. Weak storage for auto-cleanup; **stable-attribute re-resolution for
identity.** A handle that only ever dereferences a cached node reference will
silently break on the next render.

---

## Quick checklist when a site fights you

1. Is the data missing from the DOM? → read the **React fiber** (§2).
2. Did state go stale after a click with no request? → **client-side nav**, no
   network fired (§3); re-derive from DOM/fiber.
3. Need the response body? → Firefox `filterResponseData`; Chrome monkey-patch
   fetch/XHR in MAIN world (§4).
4. Want to call the site's API? → harvest the **persisted-query hash + CSRF +
   headers** live; call from page origin (§5).
5. Selector keeps breaking? → anchor on **aria-label/data-*/fiber**, re-query
   each time (§6).
6. "Load more" loops or false "missing items"? → **stall-guard** + trust
   `hasNextPage`, not `totalCount` (§7).
7. Copy button "doesn't work"? → missing `.catch`; add fallback + visible state
   (§8).
8. Click does nothing? → target is probably `div[role="button"]`, not `<button>`;
   plain `.click()` works for React `onClick`, escalate to a pointer/mouse
   sequence, and **settle async** (§9). Typed text ignored? → native value setter
   + `input` event (§9).
9. Stored element handle broke after a render? → it was keyed on a cached node
   object; the SPA made a new one. Store weakly, **re-resolve by stable
   attribute each turn** (§10).

---

*Source: techniques proven live against Nextdoor's moderation SPA
(React + Apollo GraphQL) during the MV2→MV3 port. Firefox specifics
(`wrappedJSObject`, `filterResponseData`) verified against MV2; Chrome
specifics apply to the `manifest.chrome.json` port.*
