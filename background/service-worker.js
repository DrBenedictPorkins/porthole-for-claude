// Chrome MV3 Service Worker entry point for Porthole for Claude.
//
// Service workers have no `window` global. All background scripts use window.X
// to share state across script boundaries, so we alias globalThis → window
// before importing anything. This is safe because service workers have no DOM.
globalThis.window = globalThis;

// browser-polyfill maps browser.* → chrome.* so all background scripts work unmodified.
importScripts('../sidebar/lib/browser-polyfill.min.js');

importScripts(
  'prompt-loader.js',
  'content-sanitizer.js',
  'Readability.js',
  'tools.js',
  'claude-api.js',
  'tool-router.js',
  'site-knowledge.js',
  'api-observer.js',
  'interaction-observer.js',
  'background.js'
);

// Open the side panel when the toolbar button is clicked.
// setPanelBehavior replaces the need for an onClicked handler.
chrome.sidePanel
  .setPanelBehavior({ openPanelOnActionClick: true })
  .catch(() => {});
