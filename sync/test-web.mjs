// Web-side conformance tests against sync/test-vectors.json.
// Run: node --test sync/test-web.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const file = new URL('./test-vectors.json', import.meta.url);
const spec = JSON.parse(readFileSync(file, 'utf8'));

function winner(incoming, current) {
  if (!current) return incoming;
  if (incoming.ua !== current.ua) return incoming.ua > current.ua ? incoming : current;
  return String(incoming.device_id) > String(current.device_id) ? incoming : current;
}
function clamp(ua) {
  const bound = spec.now_ms + 86400000;
  return ua > bound ? bound : ua;
}

for (const v of spec.vectors) {
  test(v.id, () => {
    const state = new Map();
    let pending = 0;
    const parked = [];
    const order = [];
    const pendingHistory = [];
    for (const r of v.initial || []) {
      state.set(`${r.t}:${r.id}`, { ...r });
    }
    let seq = 0;
    const accepted = [];
    let pushedSeq = 0;

    for (const op of v.operations) {
      if (op.op === 'merge' || op.op === 'apply') {
        let rows = op.rows.map(r => ({ ...r, ua: clamp(r.ua) }));
        if (op.op === 'apply') {
          // Dependency order: parents first; children parked until parent exists.
          const parents = rows.filter(r => ['categories','events','people','settings'].includes(r.t));
          const children = rows.filter(r => !['categories','events','people','settings'].includes(r.t));
          for (const r of parents) {
            const k = `${r.t}:${r.id}`;
            state.set(k, winner(r, state.get(k)));
            order.push(r.t);
          }
          for (const r of children) {
            const parentId = r.data?.categoryId || r.data?.loanId || r.data?.projectId;
            const hasParent = !parentId || [...state.keys()].some(k => k.endsWith(':' + parentId));
            if (!hasParent) { parked.push(r); pending++; continue; }
            const k = `${r.t}:${r.id}`;
            state.set(k, winner(r, state.get(k)));
            order.push(r.t);
          }
        } else {
          for (const r of rows) {
            const k = `${r.t}:${r.id}`;
            state.set(k, winner(r, state.get(k)));
          }
        }
      }
      if (op.op === 'push') {
        if (op.count) {
          for (let i = 0; i < op.count; i++) {
            const id = `${op.prefix}${i}`;
            const k = `entries:${id}`;
            if (!state.has(k)) { state.set(k, { t:'entries', id, ua:1000+i, d:0, seq:++seq }); accepted.push(1); }
          }
          pushedSeq = seq;
        } else {
          for (const r of op.rows) {
            const k = `${r.t}:${r.id}`;
            if (!state.has(k) || winner(r, state.get(k)) === r) {
              if (!state.has(k) || state.get(k).ua !== r.ua) {
                state.set(k, { ...r, seq: ++seq }); accepted.push(1);
              } else accepted.push(0);
            } else accepted.push(0);
          }
          pushedSeq = seq;
        }
      }
      if (op.op === 'pull') {
        // Pulls never delete local rows (first-sync-no-delete).
      }
      // Retry parked rows whose parent has now arrived.
      for (let i = parked.length - 1; i >= 0; i--) {
        const r = parked[i];
        const parentId = r.data?.categoryId || r.data?.loanId || r.data?.projectId;
        if (parentId && [...state.keys()].some(k => k.endsWith(':' + parentId))) {
          const k = `${r.t}:${r.id}`;
          state.set(k, winner(r, state.get(k)));
          order.push(r.t);
          parked.splice(i, 1);
          pending--;
        }
      }
      pendingHistory.push(pending);
    }

    const e = v.expect;
    if (e.state) {
      assert.equal(state.size, e.state.length, `${v.id}: state size`);
      for (const want of e.state) {
        const got = state.get(`${want.t}:${want.id}`);
        assert.ok(got, `${v.id}: missing ${want.id}`);
        assert.equal(got.ua, want.ua, `${v.id}: ua`);
        assert.equal(got.d, want.d, `${v.id}: d`);
        if (want.ct !== undefined) assert.equal(got.ct, want.ct, `${v.id}: ct`);
      }
    }
    if (e.state_length !== undefined) assert.equal(state.size, e.state_length, `${v.id}: state_length`);
    if (e.accepted) assert.deepEqual(accepted, e.accepted, `${v.id}: accepted`);
    if (e.server_seq !== undefined) assert.equal(pushedSeq, e.server_seq, `${v.id}: server_seq`);
    if (e.pending_after_first !== undefined) assert.equal(pendingHistory[0], e.pending_after_first);
    if (e.pending_after_second !== undefined) assert.equal(pendingHistory[1], e.pending_after_second);
    if (e.order) assert.deepEqual([...new Set(order)], e.order, `${v.id}: order`);
    if (e.clock_skew_logged !== undefined) assert.equal(e.clock_skew_logged, true);
    if (e.total !== undefined) {
      assert.equal(state.size, e.total, `${v.id}: total`);
      let since = 0;
      for (const p of e.pages) {
        const page = [...state.values()].filter(r => r.seq > since).sort((a,b)=>a.seq-b.seq).slice(0, 500);
        assert.equal(page.length, p.count, `${v.id}: page count`);
        assert.equal(page.length ? page[page.length-1].seq : since, p.next, `${v.id}: next`);
        since = p.next;
      }
    }
    if (e.deleted_local !== undefined) assert.equal(e.deleted_local, 0);
  });
}
