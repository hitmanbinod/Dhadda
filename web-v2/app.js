/* Dhadda web-v2 - presentation only. No framework, no CDN, no data-layer changes. */
(() => {
'use strict';

const SYNC = window.DhaddaSync;
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const ic = (n, cls = '') => `<svg class="${cls}" aria-hidden="true"><use href="icons.svg#i-${n}"/></svg>`;
const esc = (v) => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

/* ---------------- storage (real keys, demo never writes) ---------------- */
const DEMO = new URLSearchParams(location.search).has('demo');
const K = {cats:'expense_cats_v1',txns:'expense_txns_v1',loans:'expense_loans_v1',projects:'expense_projects_v1',meta:'expense_meta_v1'};
const read = k => { if (DEMO) return null; try { return JSON.parse(localStorage.getItem(k) || 'null'); } catch { return null; } };
const write = (k, v) => { if (DEMO) return; try { localStorage.setItem(k, JSON.stringify(v)); } catch {} };

const DEFAULT_CATS = [
  {id:'food',name:'Food',icon:58763,color:0xFFEF6C00,budget:0},
  {id:'travel',name:'Travel',icon:58765,color:0xFF1565C0,budget:0},
  {id:'gym',name:'Gym',icon:0xe1d4,color:0xFFC2185B,budget:0},
  {id:'rent',name:'Rent',icon:0xe2dc,color:0xFF6A1B9A,budget:0},
  {id:'other',name:'Other',icon:0xe8b0,color:0xFF009688,budget:0},
];
const DEFAULT_META = {
  currency:'NPR', themeMode:'system', accent:'#006A60', userName:'Binod',
  calendarSystem:'ad', hideBalance:false,
  homeLayout:[
    {id:'balance',visible:true},{id:'stats',visible:true},{id:'categories',visible:true},
    {id:'budgets',visible:true},{id:'events',visible:true},{id:'recent',visible:true},
    {id:'todayRing',visible:false},{id:'rhythm',visible:false},{id:'forecast',visible:false},
  ],
};
const SECTION_LABELS = {balance:'Balance',stats:'Stats',categories:'Categories',budgets:'Budgets',events:'Events',recent:'Recent',todayRing:'Today',rhythm:'Daily rhythm',forecast:'Forecast'};

function load() {
  if (DEMO && window.__DHADDA_DEMO__) return JSON.parse(JSON.stringify(window.__DHADDA_DEMO__));
  return {
    cats: read(K.cats) || JSON.parse(JSON.stringify(DEFAULT_CATS)),
    txns: read(K.txns) || [],
    loans: read(K.loans) || [],
    projects: read(K.projects) || [],
    meta: {...DEFAULT_META, ...(read(K.meta) || {})},
  };
}
let data = load();
let saveTimer = null;
function persist() {
  if (DEMO || state.paired) return;
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    write(K.cats, data.cats); write(K.txns, data.txns);
    write(K.loans, data.loans); write(K.projects, data.projects); write(K.meta, data.meta);
  }, 50);
}
const meta = () => data.meta;
function persistRow(t, id, record, deleted = 0) {
  if (state.paired && SYNC) SYNC.setLocal(t, id, record, deleted);
  else persist();
}
function vaultData(g) {
  const settings = {};
  for (const s of (g.settings || [])) if (s && s.id) settings[s.id] = s.value;
  return {
    cats: g.categories?.length ? g.categories : data.cats,
    txns: g.transactions?.length ? g.transactions : data.txns,
    loans: g.loans?.length ? g.loans : data.loans,
    projects: g.projects?.length ? g.projects : data.projects,
    meta: {...DEFAULT_META, ...data.meta, ...settings},
  };
}

/* ---------------- formatting ---------------- */
const SYMBOLS = {NPR:'रू',INR:'₹',USD:'$',EUR:'€',GBP:'£',AUD:'A$',CAD:'C$',AED:'AED',JPY:'¥',CNY:'¥'};
const sym = () => SYMBOLS[meta().currency] || 'रू';
function num(v) { return Math.round(Math.abs(v || 0)).toLocaleString('en-US'); }
function money(v) { return `${sym()} ${num(v)}`; }
function amount(v, type) {
  return `<span class="amount ${type === 'income' ? 'income' : type === 'expense' ? 'expense' : ''}"><span class="symbol">${sym()}</span>${num(v)}</span>`;
}
function dayLabel(ms) {
  const d = new Date(ms), now = new Date();
  const same = (a, b) => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
  if (same(d, now)) return 'Today';
  const y = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
  if (same(d, y)) return 'Yesterday';
  return d.toLocaleDateString('en-US', {weekday:'short', month:'short', day:'numeric'});
}
function dateStr(ms) { return new Date(ms).toLocaleDateString('en-US', {month:'short', day:'numeric', year:'numeric'}); }
function monthLabel(d) { return d.toLocaleDateString('en-US', {month:'long', year:'numeric'}); }
function greeting() {
  const h = new Date().getHours();
  return h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good night';
}
const catOf = id => data.cats.find(c => c.id === id) || data.cats[data.cats.length - 1] || {id:'other',name:'Other',icon:0xe8b0,color:0xFF009688};
const ICON_MAP = {58763:'receipt',58765:'wallet',0xe1d4:'insights',0xe2dc:'home',0xe8b0:'more'};
const iconOf = c => ICON_MAP[c.icon] || 'receipt';
const colorOf = c => '#' + (c.color >>> 0).toString(16).padStart(8,'0').slice(1);
function tile(c, size = '') {
  const col = colorOf(c);
  return `<span class="tile ${size}" style="background:${col}22;color:${col}">${ic(iconOf(c))}</span>`;
}

/* ---------------- derived ---------------- */
function monthRange(d) {
  return [new Date(d.getFullYear(), d.getMonth(), 1).getTime(), new Date(d.getFullYear(), d.getMonth() + 1, 1).getTime()];
}
function analytics(from, to) {
  let spend = 0, income = 0;
  const byCat = {};
  for (const t of data.txns) {
    if (t.date < from || t.date >= to) continue;
    if (t.type === 'income') income += t.amount;
    else { spend += t.amount; byCat[t.categoryId] = (byCat[t.categoryId] || 0) + t.amount; }
  }
  const toReceive = data.loans.filter(l => (l.kind || 'lent') === 'lent').reduce((s,l)=>s+loanPending(l),0);
  return {spend, income, balance: income - spend, byCat, toReceive, toReturn: 0};
}
function loanPending(l) {
  const repaid = (l.repayments || []).reduce((s, r) => s + r.amount, 0);
  const topups = (l.topups || []).reduce((s, r) => s + r.amount, 0);
  return l.lent + topups - repaid;
}

/* ---------------- state ---------------- */
const state = {
  screen:'home', month:new Date(), period:'month',
  histQuery:'', histType:'all', histCat:'all', histView:'entries', histSelected:new Set(), histPage:60,
  catSelected:null, lentDir:'lent', lentFilter:'pending',
  modal:null, drawer:false, palette:false, paletteQuery:'', toast:null,
  booted:false, paired:false, backupAvailable:false, pairLink:'',
};
function go(screen) { state.screen = screen; state.modal = null; state.drawer = false; state.palette = false; render(); }

/* ---------------- shared UI ---------------- */
function shell() {
  const nav = [['home','Home','home'],['history','History','history'],['insights','Insights','insights'],['lent','Lent','lent']];
  return `<aside class="sidebar">
    <div class="brand"><svg viewBox="0 0 28 28" width="28" height="28"><rect width="28" height="28" rx="8" fill="#B8483C"/><text x="14" y="19" text-anchor="middle" font-size="16" font-weight="700" fill="#fff">D</text></svg>Dhadda</div>
    <button class="btn-primary" data-act="new">${ic('add')}<span>New entry</span><span class="key-hint">N</span></button>
    <nav class="nav" aria-label="Main">${nav.map(([id,label,icon]) =>
      `<button class="nav-item" data-nav="${id}" ${state.screen===id?'aria-current="page"':''}>${ic(icon)}<span>${label}</span></button>`).join('')}</nav>
    <div class="sidebar-foot">
      <button class="sync-line" data-act="sync-now" title="Sync now" style="width:100%;text-align:left"><span class="dot ${state.paired ? 'live' : ''}"></span><span id="sync-status">${state.paired && SYNC ? SYNC.status() : 'Not connected'}</span></button>
      <button class="profile-row" data-act="settings"><span class="avatar">${esc((meta().userName||'B')[0].toUpperCase())}</span><span class="profile-name">${esc(meta().userName||'Set your name')}</span>${ic('settings')}</button>
    </div>
  </aside><main><div id="screen"></div></main>
  ${state.screen!=='settings' ? '<button class="add-fab" data-act="new" aria-label="New entry">'+ic('add')+'</button>' : ''}
  <div id="overlay"></div>`;
}

function toast(msg, action) {
  state.toast = {msg, action};
  const el = $('#toast'); if (el) el.remove();
  const t = document.createElement('div');
  t.id = 'toast'; t.className = 'toast'; t.innerHTML = `<span>${esc(msg)}</span>${action?`<button data-act="undo">Undo</button>`:''}`;
  document.body.appendChild(t);
  setTimeout(() => { t.remove(); state.toast = null; }, 5000);
}

/* ---------------- Home ---------------- */
function home() {
  const a = analytics(...monthRange(state.month));
  const layout = meta().homeLayout || DEFAULT_META.homeLayout;
  const visible = new Set(layout.filter(x => x.visible).map(x => x.id));
  const slices = Object.entries(a.byCat).sort((x,y)=>y[1]-x[1]).slice(0,6)
    .map(([id,v]) => ({id, value:v, cat:catOf(id)}));
  const events = data.projects.filter(p => data.txns.some(t => t.projectId === p.id && t.date >= monthRange(state.month)[0]));
  const recent = data.txns.filter(t => !t.projectId).sort((x,y)=>y.date-x.date).slice(0,5);
  const hero = [], left = [], right = [];
  for (const s of layout) {
    if (!visible.has(s.id)) continue;
    const html = section(s.id, a, slices, events, recent);
    if (s.id === 'balance' || s.id === 'stats') hero.push(html);
    else if (s.id === 'recent') right.push(html);
    else left.push(html);
  }
  return `<div class="content">
    <div class="page-head"><div style="display:flex;align-items:center;gap:10px"><button class="phone-avatar" data-act="settings" aria-label="Settings">${esc((meta().userName||'B')[0].toUpperCase())}</button><div class="greeting">${greeting()}, ${esc(meta().userName||'there')}</div></div>
      <div class="quiet-actions"><button class="icon-btn" data-act="customize" title="Customize">${ic('custom')}</button><button class="icon-btn" data-act="sync" title="Sync">${ic('sync')}</button></div></div>
    <div style="display:flex;align-items:baseline;gap:12px;margin-bottom:24px"><h1 class="page-title">${monthLabel(state.month)}</h1>
      <button class="icon-btn" data-act="prev-month" title="Previous month">${ic('left')}</button><button class="icon-btn" data-act="next-month" title="Next month">${ic('right')}</button></div>
    <div class="grid grid-5-7">${hero.join('')}</div>
    <div class="grid grid-7-5" style="margin-top:var(--shell-cardGap)"><div class="stack">${left.join('')}</div><div class="stack">${right.join('')}</div></div>
  </div>`;
}
function section(id, a, slices, events, recent) {
  if (id === 'balance') return balanceCard(a);
  if (id === 'stats') return statsCard(a);
  if (id === 'categories') return categoryCard(a, slices);
  if (id === 'events') return eventsCard(events);
  if (id === 'recent') return recentCard(recent);
  if (id === 'budgets') return budgetsCard();
  if (id === 'todayRing') return `<div class="card"><div class="card-head"><span class="card-title">Today</span></div><div class="empty">${ic('calendar')}<strong>No budget set</strong></div></div>`;
  if (id === 'rhythm') return rhythmCard();
  if (id === 'forecast') return `<div class="card"><div class="card-head"><span class="card-title">Forecast</span></div><div class="muted">${money(a.spend / Math.max(1,new Date().getDate()) * 30)} at this month's pace</div></div>`;
  return '';
}
function balanceCard(a) {
  const hidden = meta().hideBalance;
  const col = a.balance < 0 ? 'var(--expense)' : a.balance > 0 ? 'var(--income)' : 'var(--text)';
  return `<div class="card"><div class="section-label">Balance</div>
    <div style="display:flex;align-items:center;gap:12px"><div class="hero-amount" style="color:${col}">${hidden?'••••':`<span class="symbol">${sym()}</span>${num(a.balance)}`}</div>
    <button class="icon-btn" data-act="toggle-eye" title="${hidden?'Show':'Hide'} balance">${ic(hidden?'eye-off':'eye')}</button></div></div>`;
}
function statsCard(a) {
  const cell = (label, v, cls) => `<div style="flex:1;min-width:0"><div class="section-label">${label}</div>${amount(v,cls)}</div>`;
  return `<div class="card"><div style="display:flex;gap:16px">${cell('Spent',a.spend,'expense')}${cell('Income',a.income,'income')}${cell('Lent out',a.toReceive,'')}</div></div>`;
}
function categoryCard(a, slices) {
  if (!slices.length) return `<div class="card"><div class="card-head"><span class="card-title">By category</span></div><div class="empty">${ic('pie')}<strong>No expenses this month</strong></div></div>`;
  const total = slices.reduce((s,x)=>s+x.value,0);
  const bar = slices.map(s => `<span data-cat="${esc(s.id)}" title="${esc(s.cat.name)} ${money(s.value)}" style="width:${Math.max(8,(s.value/total*100))}%;height:9px;border-radius:999px;background:${colorOf(s.cat)};opacity:${state.catSelected&&state.catSelected!==s.id?'.38':'1'};display:block"></span>`).join('');
  const rows = slices.map(s => `<div class="row" data-cat-row="${esc(s.id)}" style="border-radius:10px;padding:8px;background:${state.catSelected===s.id?'var(--selectedRow)':'transparent'}">
      ${tile(s.cat)}<div class="row-main"><div class="row-title">${esc(s.cat.name)}</div></div>
      <span class="muted">${Math.round(s.value/total*100)}%</span>${amount(s.value,'expense')}</div>`).join('');
  return `<div class="card"><div class="card-head"><span class="card-title">By category</span></div>
    <div style="display:flex;gap:4px;margin-bottom:14px">${bar}</div>${rows}</div>`;
}
function eventsCard(events) {
  if (!events.length) return '';
  return `<div class="card"><div class="card-head"><span class="card-title">Events</span></div>${events.map(p => {
    const tx = data.txns.filter(t=>t.projectId===p.id);
    const sum = tx.filter(t=>t.type==='expense').reduce((s,t)=>s+t.amount,0);
    return `<div class="row">${tile({icon:p.icon,color:p.color})}<div class="row-main"><div class="row-title">${esc(p.name)}</div><div class="row-sub">${tx.length} entries · Spent ${money(sum)}</div></div>${ic('right')}</div>`;
  }).join('')}</div>`;
}
function recentCard(recent) {
  return `<div class="card"><div class="card-head"><span class="card-title">Recent</span><button class="link" data-nav="history">See all</button></div>
    ${recent.length ? recent.map(t => `<div class="row" data-txn="${esc(t.id)}">${tile(catOf(t.categoryId))}<div class="row-main"><div class="row-title">${esc(t.note||catOf(t.categoryId).name)}</div><div class="row-sub">${dateStr(t.date)} · ${esc(catOf(t.categoryId).name)}</div></div>${amount(t.amount,t.type)}</div>`).join('') : '<div class="empty">No entries yet.</div>'}</div>`;
}
function budgetsCard() {
  const withBudget = data.cats.filter(c => c.budget > 0);
  if (!withBudget.length) return '';
  return `<div class="card"><div class="card-head"><span class="card-title">Budgets</span></div>${withBudget.map(c => {
    const [f,t] = monthRange(state.month);
    const spent = data.txns.filter(x=>x.categoryId===c.id&&x.type==='expense'&&x.date>=f&&x.date<t).reduce((s,x)=>s+x.amount,0);
    return `<div style="margin:10px 0"><div style="display:flex;justify-content:space-between;font-size:13px"><span>${esc(c.name)}</span><span class="muted">${money(spent)} / ${money(c.budget)}</span></div><div class="meter" style="margin-top:6px"><i style="width:${Math.min(100,spent/c.budget*100)}%;background:${colorOf(c)}"></i></div></div>`;
  }).join('')}</div>`;
}
function rhythmCard() {
  const [f,t] = monthRange(state.month);
  const days = new Date(t).getDate();
  const vals = Array(days).fill(0);
  for (const x of data.txns) if (x.type==='expense'&&x.date>=f&&x.date<t) vals[new Date(x.date).getDate()-1] += x.amount;
  const max = Math.max(...vals, 1);
  return `<div class="card"><div class="card-head"><span class="card-title">Daily rhythm</span></div><div style="display:flex;align-items:flex-end;gap:2px;height:96px">${vals.map((v,i)=>`<i title="Day ${i+1}: ${money(v)}" style="flex:1;height:${Math.max(2,v/max*88)}px;background:var(--accent);opacity:${v?'.8':'.25'};border-radius:3px"></i>`).join('')}</div></div>`;
}

/* ---------------- History ---------------- */
function history() {
  let tx = [...data.txns].sort((a,b)=>b.date-a.date);
  if (state.histQuery) { const q=state.histQuery.toLowerCase(); tx = tx.filter(t=>(t.note||'').toLowerCase().includes(q)||catOf(t.categoryId).name.toLowerCase().includes(q)||t.mode.toLowerCase().includes(q)||num(t.amount).includes(q)); }
  if (state.histType!=='all') tx = tx.filter(t=>t.type===state.histType);
  if (state.histCat!=='all') tx = tx.filter(t=>t.categoryId===state.histCat);
  const groups = [];
  for (const t of tx) { const k=dayLabel(t.date); const g=groups.find(g=>g.k===k); (g||groups[groups.length-1]&&groups[groups.length-1].k===k?groups[groups.length-1]:(groups.push({k,items:[]}),groups[groups.length-1])).items.push(t); }
  const shown = groups.slice(0, state.histPage).map(g => `<div class="day-head">${esc(g.k)}<span class="muted">${money(g.items.reduce((s,t)=>s+(t.type==='income'?t.amount:-t.amount),0))}</span></div>
    ${g.items.map(t => `<div class="row" data-txn="${esc(t.id)}">
      <input type="checkbox" data-sel="${esc(t.id)}" ${state.histSelected.has(t.id)?'checked':''} aria-label="Select">
      ${tile(catOf(t.categoryId))}<div class="row-main"><div class="row-title">${esc(t.note||catOf(t.categoryId).name)}</div><div class="row-sub">${esc(catOf(t.categoryId).name)} · ${esc(t.mode)}</div></div>
      ${amount(t.amount,t.type)}<button class="icon-btn" data-edit="${esc(t.id)}" title="Edit">${ic('edit')}</button><button class="icon-btn" data-dup="${esc(t.id)}" title="Duplicate">${ic('copy')}</button><button class="icon-btn" data-del="${esc(t.id)}" title="Delete">${ic('trash')}</button></div>`).join('')}`).join('');
  return `<div class="content"><div class="page-head"><h1 class="page-title">History</h1></div>
    <div style="display:flex;gap:8px;margin-bottom:16px;flex-wrap:wrap">
      <input class="input" id="hist-q" placeholder="Search notes, categories, modes" value="${esc(state.histQuery)}" style="max-width:320px">
      ${['all','expense','income'].map(v=>`<button class="chip" data-type="${v}" aria-pressed="${state.histType===v}">${v[0].toUpperCase()+v.slice(1)}</button>`).join('')}
      <button class="chip" data-view="categories" aria-pressed="${state.histView==='categories'}">Categories</button>
      <button class="chip" data-view="events" aria-pressed="${state.histView==='events'}">Events</button>
    </div>
    ${state.histSelected.size?`<div style="display:flex;gap:12px;align-items:center;margin-bottom:16px"><strong>${state.histSelected.size} selected</strong><button class="chip" data-act="delete-selected">Delete</button></div>`:''}
    <div class="card" style="padding:4px 16px">${shown||'<div class="empty">No entries found.</div>'}</div>
    ${groups.length>state.histPage?`<button class="chip" data-act="more" style="margin-top:16px">Show more</button>`:''}</div>`;
}

/* ---------------- Insights ---------------- */
function insights() {
  const periods = [['month','Month'],['3m','3 months'],['6m','6 months'],['year','Year'],['fiscal','Fiscal year']];
  const [f,t] = monthRange(state.month);
  const a = analytics(f,t);
  const top = Object.keys(a.byCat).map(id=>({cat:catOf(id),value:a.byCat[id]})).sort((x,y)=>y.value-x.value).slice(0,5);
  const total = top.reduce((s,x)=>s+x.value,0)||1;
  const months = Array.from({length:6},(_,i)=>{
    const d = new Date(state.month.getFullYear(), state.month.getMonth()-5+i, 1);
    const [mf,mt] = monthRange(d);
    return {label:d.toLocaleDateString('en-US',{month:'short'}),
      v:data.txns.filter(x=>x.type==='expense'&&x.date>=mf&&x.date<mt).reduce((s,x)=>s+x.amount,0)};
  });
  const mmax = Math.max(...months.map(x=>x.v),1);
  return `<div class="content"><div class="page-head"><h1 class="page-title">Insights</h1></div>
    <div class="segmented equal" style="max-width:460px;margin-bottom:24px">${periods.map(([id,label])=>`<button data-period="${id}" aria-pressed="${state.period===id}">${label}</button>`).join('')}</div>
    <div class="grid grid-5-7">
      <div class="card"><div class="section-label">Spent this month</div><div class="hero-amount" style="color:var(--expense);font-size:44px">${money(a.spend)}</div>
        <div style="display:flex;gap:24px;margin-top:16px;padding-top:16px;border-top:1px solid var(--hairline)"><div><div class="section-label">Income</div>${amount(a.income,'income')}</div><div><div class="section-label">Net</div>${amount(a.balance,a.balance<0?'expense':'income')}</div></div></div>
      <div class="card"><div class="card-title" style="margin-bottom:12px">Where it went</div>${top.map(x=>`<div class="row">${tile(x.cat)}<div class="row-main"><div class="row-title">${esc(x.cat.name)}</div><div class="meter" style="margin-top:6px"><i style="width:${x.value/total*100}%;background:${colorOf(x.cat)}"></i></div></div>${amount(x.value,'expense')}</div>`).join('')||'<div class="empty">No spending</div>'}</div>
      <div class="card"><div class="card-head"><span class="card-title">Money on loan</span><span class="muted">Now</span></div>
        <div class="row"><span>To receive</span><span style="margin-left:auto">${amount(a.toReceive)}</span></div>
        <div class="row"><span>To return</span><span style="margin-left:auto">${amount(data.loans.filter(l=>(l.kind||'lent')==='borrowed').reduce((s,l)=>s+loanPending(l),0))}</span></div></div>
      <div class="card"><div class="card-head"><span class="card-title">Monthly rhythm</span></div>
        <div style="display:flex;align-items:flex-end;gap:8px;height:110px">${months.map(x=>`<div style="flex:1;text-align:center"><div class="muted" style="font-size:12px">${money(x.v)}</div><div style="height:${Math.max(4,x.v/mmax*72)}px;background:var(--accent);opacity:.85;border-radius:4px 4px 0 0;margin-top:4px"></div><div class="muted" style="font-size:12px;margin-top:6px">${x.label}</div></div>`).join('')}</div></div>
    </div></div>`;
}

/* ---------------- Lent ---------------- */
function lent() {
  const loans = data.loans.filter(l => (l.kind||'lent') === state.lentDir)
    .filter(l => state.lentFilter==='all' ? true : state.lentFilter==='settled' ? loanPending(l)<=0.005 : loanPending(l)>0.005);
  const receive = data.loans.filter(l=>(l.kind||'lent')==='lent').reduce((s,l)=>s+loanPending(l),0);
  const ret = data.loans.filter(l=>(l.kind||'lent')==='borrowed').reduce((s,l)=>s+loanPending(l),0);
  return `<div class="content"><div class="page-head"><h1 class="page-title">Lent</h1><button class="btn-primary" style="width:auto;padding:0 16px" data-act="new-loan">${ic('add')} New loan</button></div>
    <div class="segmented" style="margin-bottom:16px"><button data-lent-dir="lent" aria-pressed="${state.lentDir==='lent'}">Lent out</button><button data-lent-dir="borrowed" aria-pressed="${state.lentDir==='borrowed'}">Borrowed</button></div>
    <div class="grid grid-5-7" style="margin-bottom:24px">
      <div class="card"><div class="section-label">To receive</div>${amount(receive)}</div>
      <div class="card"><div class="section-label">To return</div>${amount(ret)}</div></div>
    <div style="display:flex;gap:8px;margin-bottom:16px">${['pending','settled','all'].map(v=>`<button class="chip" data-lent-filter="${v}" aria-pressed="${state.lentFilter===v}">${v[0].toUpperCase()+v.slice(1)}</button>`).join('')}</div>
    ${loans.length?loans.map(l => {
      const pending = loanPending(l), settled = pending<=0.005;
      const ratio = l.lent ? Math.min(100,(1-pending/l.lent)*100) : 100;
      return `<div class="card" style="margin-bottom:16px"><div class="row"><span class="avatar">${esc(l.person[0].toUpperCase())}</span>
        <div class="row-main"><div class="row-title">${esc(l.person)}</div><div class="row-sub">${settled?'Settled':money(pending)} · ${dateStr(l.dateLent)}${l.dueDate?' · Due '+dateStr(l.dueDate):''}</div></div>
        <button class="icon-btn" data-loan-topup="${esc(l.id)}" title="Top up">${ic('add')}</button><button class="icon-btn" data-loan-repay="${esc(l.id)}" title="Repayment">${ic('down')}</button></div>
        <div class="meter" style="margin-top:10px"><i style="width:${ratio}%;background:${settled?'var(--income)':'var(--accent)'}"></i></div>
        ${(l.repayments||[]).map(r=>`<div class="row"><span>${ic('down')} Returned ${money(r.amount)}</span><span class="muted">${dateStr(r.date)}</span></div>`).join('')}
      </div>`; }).join(''):'<div class="empty">No loans here yet.</div>'}</div>`;
}

/* ---------------- Settings ---------------- */
function settings() {
  const m = meta();
  const row = (label, control, hint='') => `<div class="row"><div class="row-main"><div class="row-title">${label}</div>${hint?`<div class="row-sub">${hint}</div>`:''}</div>${control}</div>`;
  const theme = `<div class="segmented">${['system','light','dark'].map(v=>`<button data-theme="${v}" aria-pressed="${m.themeMode===v}">${v[0].toUpperCase()+v.slice(1)}</button>`).join('')}</div>`;
  return `<div class="content"><a href="#" data-act="back" class="link">‹ Back</a><div class="page-head" style="margin-top:16px"><h1 class="page-title">Settings</h1></div>
    <div class="stack">
      <div class="card"><div class="card-title" style="margin-bottom:10px">Appearance</div>
        ${row('Theme',theme)}${row('Accent colour',`<span style="width:14px;height:14px;border-radius:50%;background:${m.accent};display:inline-block"></span>`)}
        ${row('Hide balance on launch',`<button class="switch" data-act="hide" role="switch" aria-checked="${!!m.hideBalance}"></button>`,'Mask amounts until tapped')}</div>
      <div class="card"><div class="card-title" style="margin-bottom:10px">Preferences</div>
        ${row('Calendar',`<div class="segmented"><button data-cal="ad" aria-pressed="${m.calendarSystem==='ad'}">AD</button><button data-cal="bs" aria-pressed="${m.calendarSystem==='bs'}">BS</button></div>`)}
        ${m.calendarSystem==='bs'?'<div class="row-sub" style="padding:8px 0">Calendar data for 2084 onward is an estimate.</div>':''}
        ${row('Display currency',`<select class="input" data-act="currency" style="width:90px">${Object.keys(SYMBOLS).map(c=>`<option ${c===m.currency?'selected':''}>${c}</option>`).join('')}</select>`)}
        ${row('Edit Home',`<button class="chip" data-act="customize">Open</button>`)}</div>
      <div class="card"><div class="card-title" style="margin-bottom:10px">Your data</div>
        ${row('Accounts',`<button class="chip" data-act="accounts">Manage</button>`)}
        ${row('Auto-category rules',`<button class="chip" data-act="rules">Manage</button>`)}
        ${row('Receipts',`<span class="muted">${DEMO?'Demo store':'On this device'}</span>`)}</div>
      <div class="card"><div class="card-title" style="margin-bottom:10px">Account</div>
        ${row('Profile',`<button class="chip" data-act="account">${esc(m.userName||'Set name')}</button>`,'Name and avatar style')}</div>
      <div class="card"><div class="card-title" style="margin-bottom:10px">About</div>
        ${row('App lock, SMS import, reminders',`<span class="muted">Device-only</span>`,'These features stay on the phone app.')}
        ${row('Erase all data',`<button class="chip" data-act="erase">Erase</button>`)}</div>
    </div></div>`;
}

/* ---------------- overlays ---------------- */
function renderOverlay() {
  const o = $('#overlay'); if (!o) return;
  let html = '';
  if (state.palette) html += `<div class="scrim blur" data-close="palette"><div class="palette" data-stop>
      <input class="input" id="palette-q" placeholder="Search entries, jump to a screen, run a command" value="${esc(state.paletteQuery)}">
      <div class="palette-list">${paletteItems().map((x,i)=>`<button class="palette-item" data-pal="${esc(x.cmd)}" aria-selected="${i===0}">${ic(x.icon)}<span>${esc(x.label)}</span></button>`).join('')}</div></div></div>`;
  if (state.drawer) html += `<div class="scrim" data-close="drawer"><div class="drawer" data-stop><div class="card-head"><h2>Customize Home</h2><button class="icon-btn" data-close="drawer">${ic('close')}</button></div>
      ${(meta().homeLayout||[]).map(s=>`<div class="drawer-row">${ic('more')}<span style="flex:1">${SECTION_LABELS[s.id]||s.id}</span><button class="switch" data-section="${s.id}" role="switch" aria-checked="${s.visible}" ${s.id==='balance'?'disabled':''}></button></div>`).join('')}</div></div>`;
  if (state.modal) html += modalHtml();
  o.innerHTML = html;
  if (state.palette) { const q=$('#palette-q'); if (q) { q.focus(); q.setSelectionRange(q.value.length,q.value.length); } }
}
function paletteItems() {
  const q = state.paletteQuery.toLowerCase();
  const items = [
    {cmd:'new',label:'New entry',icon:'add'},
    {cmd:'nav:home',label:'Go to Home',icon:'home'},
    {cmd:'nav:history',label:'Go to History',icon:'history'},
    {cmd:'nav:insights',label:'Go to Insights',icon:'insights'},
    {cmd:'nav:lent',label:'Go to Lent',icon:'lent'},
    {cmd:'theme',label:'Toggle theme',icon:'settings'},
  ];
  for (const t of data.txns.slice(0,40)) items.push({cmd:'txn:'+t.id,label:`${t.note||catOf(t.categoryId).name} · ${money(t.amount)}`,icon:'receipt'});
  return items.filter(x=>x.label.toLowerCase().includes(q)).slice(0,12);
}
function modalHtml() {
  const m = state.modal;
  if (m.type === 'entry') {
    const t = m.txn;
    return `<div class="scrim" data-close="modal"><div class="sheet" data-stop><div class="sheet-head"><h2 class="card-title">${t?'Edit':'New'} entry</h2><button class="icon-btn" data-close="modal">${ic('close')}</button></div>
      <div class="segmented" style="margin-bottom:16px"><button data-entry-type="expense" aria-pressed="${m.typeValue!=='income'}">Expense</button><button data-entry-type="income" aria-pressed="${m.typeValue==='income'}">Income</button></div>
      <label class="field-label">Amount</label><div class="card tight" style="display:flex;align-items:center;gap:8px;margin-bottom:16px"><span class="symbol">${sym()}</span><input id="entry-amount" class="input" style="border:0;padding:0;font-size:28px;font-weight:700" inputmode="decimal" value="${t?t.amount:''}" placeholder="0"></div>
      <label class="field-label">Category</label><div style="display:flex;gap:8px;flex-wrap:wrap;margin-bottom:16px">${data.cats.map(c=>`<button class="chip" data-entry-cat="${esc(c.id)}" aria-pressed="${m.catId===c.id}">${esc(c.name)}</button>`).join('')}</div>
      <label class="field-label">Note</label><input id="entry-note" class="input" style="margin-bottom:16px" value="${esc(t?.note||'')}" placeholder="Note (optional)">
      <label class="field-label">Date</label><input id="entry-date" class="input" type="date" style="margin-bottom:16px" value="${new Date(t?.date||Date.now()).toISOString().slice(0,10)}">
      <div style="display:flex;gap:12px"><button class="btn-primary" data-act="save-entry">Save entry</button>${t?`<button class="chip" data-act="duplicate-entry">Duplicate</button><button class="chip" data-act="delete-entry">Delete</button>`:''}</div>
    </div></div>`;
  }
  if (m.type === 'account') return `<div class="scrim" data-close="modal"><div class="sheet" data-stop><div class="sheet-head"><h2 class="card-title">Account &amp; avatar</h2><button class="icon-btn" data-close="modal">${ic('close')}</button></div>
    <label class="field-label">Name</label><input id="acct-name" class="input" value="${esc(meta().userName||'')}" style="margin-bottom:16px">
    <button class="btn-primary" data-act="save-account">Save</button></div></div>`;
  if (m.type === 'loan') return `<div class="scrim" data-close="modal"><div class="sheet" data-stop><div class="sheet-head"><h2 class="card-title">New loan</h2><button class="icon-btn" data-close="modal">${ic('close')}</button></div>
    <label class="field-label">Person</label><input id="loan-person" class="input" style="margin-bottom:12px">
    <label class="field-label">Amount</label><input id="loan-amount" class="input" inputmode="decimal" style="margin-bottom:16px">
    <button class="btn-primary" data-act="save-loan">Save loan</button></div></div>`;
  return '';
}

/* ---------------- first run / pairing ---------------- */
function firstRun() {
  return `<div class="content" style="max-width:620px"><div class="page-head"><h1 class="page-title">Connect your phone</h1></div>
    <div class="card"><p class="muted" style="margin-bottom:18px">One-time setup. Your data is encrypted on the phone; only ciphertext is stored in the cloud.</p>
      <ol style="padding-left:20px;line-height:1.9"><li>Open <strong>Dhadda</strong> on your phone.</li>
      <li>Go to <strong>Settings → Web access → Create link</strong>.</li>
      <li>Copy the link and paste it below.</li></ol>
      <label class="field-label" style="margin-top:20px">Pairing link</label>
      <input id="pair-link" class="input" placeholder="https://…#v=…&t=…&k=…" autocomplete="off">
      <div id="pair-msg" class="muted" style="margin-top:10px"></div>
      <div style="display:flex;gap:12px;margin-top:18px;flex-wrap:wrap">
        <button class="btn-primary" style="width:auto;padding:0 20px" data-act="connect">Connect</button>
        ${state.backupAvailable?'<button class="chip" data-act="download-backup">Download backup of old web data</button>':''}
      </div>
      <p class="muted" style="margin-top:20px;font-size:12px">Anyone with this link can read your data. Do not post it. The link is also your recovery key.</p>
    </div></div>`;
}

/* ---------------- render ---------------- */
function render() {
  if (!state.booted) return;
  if (!state.paired) { $('#app').innerHTML = firstRun(); return; }
  $('#app').innerHTML = shell();
  const s = $('#screen');
  s.innerHTML = state.screen==='home' ? home() : state.screen==='history' ? history() :
    state.screen==='insights' ? insights() : state.screen==='lent' ? lent() : settings();
  renderOverlay();
}

/* ---------------- actions ---------------- */
function addTxn(values) {
  const t = {id:'txn-'+Date.now()+'-'+Math.random().toString(36).slice(2,6), type:values.type, amount:values.amount,
    categoryId:values.categoryId, date:values.date, note:values.note||'', mode:values.mode||'cash', projectId:values.projectId||''};
  data.txns.unshift(t); persist(); persistRow('entries', t.id, t); return t;
}
function saveEntry() {
  const m = state.modal; if (!m) return;
  const amount = Number(($('#entry-amount')?.value||'').replace(/,/g,''));
  if (!(amount > 0)) { toast('Enter a valid amount'); return; }
  const values = {type:m.typeValue, amount, categoryId:m.catId||data.cats[0].id,
    date:new Date($('#entry-date').value+'T12:00').getTime(), note:$('#entry-note').value.trim()};
  if (m.txn) { Object.assign(m.txn, values); persistRow('entries', m.txn.id, m.txn); }
  else addTxn(values);
  persist(); state.modal = null; render(); toast('Saved');
}
function deleteTxn(id) {
  const i = data.txns.findIndex(t=>t.id===id); if (i<0) return;
  const [removed] = data.txns.splice(i,1); persist(); persistRow('entries', id, {}, 1);
  state.modal = null; render(); toast('Deleted', () => { data.txns.splice(i,0,removed); persist(); persistRow('entries', removed.id, removed); render(); });
}
function applyTheme() {
  const t = meta().themeMode;
  const dark = t==='dark' || (t==='system' && matchMedia('(prefers-color-scheme: dark)').matches);
  document.documentElement.dataset.theme = dark ? 'dark' : 'light';
  document.querySelector('meta[name="color-scheme"]').content = dark ? 'dark light' : 'light dark';
}

/* ---------------- events (delegated) ---------------- */
document.addEventListener('click', (e) => {
  const t = e.target.closest('[data-nav],[data-act],[data-close],[data-period],[data-type],[data-view],[data-cat],[data-cat-row],[data-txn],[data-edit],[data-dup],[data-del],[data-sel],[data-theme],[data-cal],[data-lent-dir],[data-lent-filter],[data-section],[data-entry-type],[data-entry-cat],[data-pal],[data-lent-dir]');
  if (!t) {
    if (e.target.closest('[data-close]')) return;
    return;
  }
  if (t.dataset.close) {
    const what = t.dataset.close;
    if (what==='palette') state.palette=false;
    if (what==='drawer') state.drawer=false;
    if (what==='modal') state.modal=null;
    if (e.target.closest('.palette-item')) return;
    renderOverlay(); return;
  }
  if (t.dataset.nav) { e.preventDefault(); go(t.dataset.nav); return; }
  if (t.dataset.act) {
    switch (t.dataset.act) {
      case 'connect': {
        const link = $('#pair-link')?.value.trim();
        const msg = $('#pair-msg');
        if (!link) { if (msg) msg.textContent = 'Paste the link first.'; return; }
        if (msg) msg.textContent = 'Connecting and syncing…';
        SYNC.connect(link).then(async () => {
          state.paired = true;
          const g = await SYNC.getAll();
          data = vaultData(g);
          render();
          toast('Connected');
        }).catch(() => { if (msg) msg.textContent = 'Invalid link or connection failed.'; });
        return;
      }
      case 'download-backup': SYNC.downloadBackup(); return;
      case 'sync-now': if (state.paired) { SYNC.pull(); toast('Syncing…'); } return;
      case 'new': case 'new-loan':
        if (t.dataset.act==='new-loan') { state.modal={type:'loan'}; }
        else state.modal={type:'entry',typeValue:'expense',catId:data.cats[0]?.id};
        renderOverlay(); return;
      case 'settings': go('settings'); return;
      case 'back': e.preventDefault(); go('home'); return;
      case 'customize': state.drawer=true; renderOverlay(); return;
      case 'sync': toast('Sync is a later task'); return;
      case 'toggle-eye': meta().hideBalance=!meta().hideBalance; persist(); render(); return;
      case 'prev-month': state.month=new Date(state.month.getFullYear(),state.month.getMonth()-1,1); render(); return;
      case 'next-month': state.month=new Date(state.month.getFullYear(),state.month.getMonth()+1,1); render(); return;
      case 'more': state.histPage+=60; render(); return;
      case 'undo': if (state.toast?.action) { state.toast.action(); state.toast=null; } return;
      case 'save-entry': saveEntry(); return;
      case 'duplicate-entry': { const m=state.modal; if(m?.txn){ addTxn({...m.txn}); state.modal=null; render(); toast('Duplicated'); } return; }
      case 'delete-entry': if (state.modal?.txn) deleteTxn(state.modal.txn.id); return;
      case 'save-account': { const n=$('#acct-name').value.trim()||'Set your name'; meta().userName=n; persist(); persistRow('settings','userName',{value:n}); state.modal=null; render(); toast('Saved'); return; }
      case 'save-loan': { const p=$('#loan-person').value.trim(), a=Number($('#loan-amount').value); if(!p||!(a>0)){toast('Enter a name and amount');return;} const loan={id:'loan-'+Date.now(),person:p,lent:a,dateLent:Date.now(),dueDate:0,note:'',repayments:[],topups:[],kind:state.lentDir,remindAt:0}; data.loans.unshift(loan); persist(); persistRow('people', loan.id, loan); state.modal=null; render(); toast('Saved'); return; }
      case 'hide': meta().hideBalance=!meta().hideBalance; persist(); render(); return;
      case 'delete-selected': { const ids=[...state.histSelected]; data.txns=data.txns.filter(t=>!ids.includes(t.id)); state.histSelected.clear(); persist(); render(); toast('Deleted',()=>{}); return; }
      case 'erase': if(confirm('Erase all data in this browser?')){ for(const k of Object.values(K)) localStorage.removeItem(k); data=load(); render(); toast('All data erased'); } return;
      case 'accounts': case 'rules': case 'account':
        if (t.dataset.act==='account') { state.modal={type:'account'}; renderOverlay(); }
        else toast('Manager coming in a later phase');
        return;
    }
  }
  if (t.dataset.period) { state.period=t.dataset.period; render(); return; }
  if (t.dataset.type) { state.histType=t.dataset.type; render(); return; }
  if (t.dataset.view) { state.histView=t.dataset.view; return; }
  if (t.dataset.cat) { state.catSelected = state.catSelected===t.dataset.cat?null:t.dataset.cat; render(); return; }
  if (t.dataset.catRow) { state.catSelected = state.catSelected===t.dataset.catRow?null:t.dataset.catRow; render(); return; }
  if (t.dataset.txn) { const tx=data.txns.find(x=>x.id===t.dataset.txn); if(tx){state.modal={type:'entry',txn:tx,typeValue:tx.type,catId:tx.categoryId};renderOverlay();} return; }
  if (t.dataset.edit) { const tx=data.txns.find(x=>x.id===t.dataset.edit); if(tx){state.modal={type:'entry',txn:tx,typeValue:tx.type,catId:tx.categoryId};renderOverlay();} return; }
  if (t.dataset.dup) { const tx=data.txns.find(x=>x.id===t.dataset.dup); if(tx){addTxn({...tx});render();toast('Duplicated');} return; }
  if (t.dataset.del) { deleteTxn(t.dataset.del); return; }
  if (t.dataset.theme) { meta().themeMode=t.dataset.theme; persist(); applyTheme(); render(); return; }
  if (t.dataset.cal) { meta().calendarSystem=t.dataset.cal; persist(); persistRow('settings','calendarSystem',{value:t.dataset.cal}); render(); return; }
  if (t.dataset.lentDir) { state.lentDir=t.dataset.lentDir; render(); return; }
  if (t.dataset.lentFilter) { state.lentFilter=t.dataset.lentFilter; render(); return; }
  if (t.dataset.section) { const s=(meta().homeLayout||[]).find(x=>x.id===t.dataset.section); if(s&&s.id!=='balance'){s.visible=!s.visible;persist();renderOverlay();render();} return; }
  if (t.dataset.entryType) { state.modal.typeValue=t.dataset.entryType; renderOverlay(); return; }
  if (t.dataset.entryCat) { state.modal.catId=t.dataset.entryCat; renderOverlay(); return; }
  if (t.dataset.pal) {
    const c=t.dataset.pal; state.palette=false;
    if (c.startsWith('nav:')) go(c.slice(4));
    else if (c==='new') { state.modal={type:'entry',typeValue:'expense',catId:data.cats[0]?.id}; }
    else if (c==='theme') { meta().themeMode=meta().themeMode==='dark'?'light':'dark'; persist(); applyTheme(); }
    else if (c.startsWith('txn:')) { const tx=data.txns.find(x=>x.id===c.slice(4)); if(tx) state.modal={type:'entry',txn:tx,typeValue:tx.type,catId:tx.categoryId}; }
    render(); return;
  }
});

document.addEventListener('input', (e) => {
  if (e.target.id==='hist-q') {
    state.histQuery=e.target.value;
    clearTimeout(window._q); window._q=setTimeout(()=>{ const pos=e.target.selectionStart; render(); const n=$('#hist-q'); if(n){n.focus();n.setSelectionRange(pos,pos);} },50);
  }
  if (e.target.id==='palette-q') { state.paletteQuery=e.target.value; renderOverlay(); }
});
document.addEventListener('change', (e) => {
  if (e.target.dataset.act==='currency') { meta().currency=e.target.value; persist(); persistRow('settings','currency',{value:e.target.value}); render(); }
  if (e.target.dataset.sel) { const id=e.target.dataset.sel; e.target.checked?state.histSelected.add(id):state.histSelected.delete(id); render(); }
});
document.addEventListener('keydown', (e) => {
  const typing = ['INPUT','TEXTAREA','SELECT'].includes(document.activeElement?.tagName);
  if ((e.ctrlKey||e.metaKey) && e.key.toLowerCase()==='k') { e.preventDefault(); state.palette=!state.palette; renderOverlay(); return; }
  if (e.key==='Escape') { if(state.modal)state.modal=null; else if(state.drawer)state.drawer=false; else if(state.palette)state.palette=false; renderOverlay(); return; }
  if (typing) { if (e.key==='Enter' && state.modal?.type==='entry') { e.preventDefault(); saveEntry(); } return; }
  if (e.key==='/') { e.preventDefault(); state.palette=true; renderOverlay(); return; }
  if (e.key.toLowerCase()==='n') { e.preventDefault(); state.modal={type:'entry',typeValue:'expense',catId:data.cats[0]?.id}; renderOverlay(); return; }
  if (e.key==='[') { state.month=new Date(state.month.getFullYear(),state.month.getMonth()-1,1); render(); return; }
  if (e.key===']') { state.month=new Date(state.month.getFullYear(),state.month.getMonth()+1,1); render(); return; }
  if (['1','2','3','4'].includes(e.key)) go(['home','history','insights','lent'][Number(e.key)-1]);
});
matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => { if (meta().themeMode==='system') applyTheme(); });

/* ---------------- boot ---------------- */
async function boot() {
  let ok = false;
  try {
    ok = await SYNC.init({
      onData: () => {
        if (!state.paired || !SYNC) return;
        SYNC.getAll().then(g => { data = vaultData(g); render(); });
      },
      onStatus: (s) => { const el = document.getElementById('sync-status'); if (el) el.textContent = s; },
      onBackupAvailable: () => { state.backupAvailable = true; },
    });
  } catch (e) { ok = false; }
  state.booted = true;
  // Demo mode stays presentation-only: no pairing, no vault, no network.
  state.paired = DEMO || !!(ok && SYNC.isPaired());
  if (state.paired) {
    const g = await SYNC.getAll();
    data = vaultData(g);
  }
  applyTheme();
  render();
}
document.addEventListener('DOMContentLoaded', boot);
})();
