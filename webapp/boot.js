/* Theme before first paint - no flash. External file so the strict CSP
   (script-src 'self') does not block it. */
(function () {
  try {
    var m = JSON.parse(localStorage.getItem('expense_meta_v1') || '{}');
    var t = m.themeMode || 'system';
    var d = window.matchMedia('(prefers-color-scheme: dark)').matches;
    document.documentElement.dataset.theme = t === 'system' ? (d ? 'dark' : 'light') : t;
  } catch (e) {
    document.documentElement.dataset.theme = 'light';
  }
})();
