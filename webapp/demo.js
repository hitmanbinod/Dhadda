/* Dev-only demo dataset loader. External file so the strict CSP
   (script-src 'self') does not block it. Loaded before the app modules. */
if (new URLSearchParams(location.search).has('demo')) {
  document.write('<scr' + 'ipt src="demo-data.js"><\/scr' + 'ipt>');
}
