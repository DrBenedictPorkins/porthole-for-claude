// Chrome extension pages don't have native browser.* — load polyfill only when needed.
// MUST be the first script loaded in sidebar.html.
if (typeof globalThis.browser === 'undefined') {
  document.write('<script src="lib/browser-polyfill.min.js"><\/script>');
}
