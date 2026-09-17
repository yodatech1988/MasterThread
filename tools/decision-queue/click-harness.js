// Drives the REAL page script in jsdom: fake db, real clicks, real re-renders.
// usage: node click-harness.js <page.html>
const fs = require('fs');
const path = require('path');
const { JSDOM } = require('jsdom');

const file = process.argv[2] || 'ops-decision-queue.html';
const body = fs.readFileSync(path.join(__dirname, file), 'utf8').replace(/@import url\([^)]*\);/, '');
const html = '<!doctype html><html><head></head><body>' + body + '</body></html>';

let fail = 0;
const ok = (name, c) => { console.log((c ? 'PASS ' : 'FAIL ') + name); if (!c) fail++; };
const tick = () => new Promise(r => setTimeout(r, 0));

async function makePage(cards) {
  const writes = [];
  const adds = [];
  let pushDecisions = null;
  let holdUpdates = false;
  const held = [];
  const dom = new JSDOM(html, {
    runScripts: 'dangerously',
    pretendToBeVisual: true,
    url: 'https://example.test/',
    beforeParse(window) {
      window.localStorage.setItem('aegis-decision-queue-device-id', 'dev-1');
      window.matchMedia = () => ({ matches: false });
      const db = {
        doc(p) {
          return {
            onSnapshot(cb) { if (p === 'settings/approval-device') cb({ exists: true, data: () => ({ deviceId: 'dev-1', label: 'test pc' }) }); },
            update(data) {
              writes.push({ path: p, data });
              if (holdUpdates) return new Promise(res => held.push(res));
              return Promise.resolve();
            },
            set() { return Promise.resolve(); },
          };
        },
        collection() {
          return {
            limit() { return this; },
            onSnapshot(cb) { pushDecisions = (list) => cb({ docs: list.map(c => ({ id: c.id, data: () => { const { id, ...rest } = c; return rest; } })) }); pushDecisions(cards); },
            add(data) { adds.push(data); return Promise.resolve(); },
          };
        },
      };
      window.claude = { use: async () => db };
    },
  });
  await tick(); await tick();
  const doc = dom.window.document;
  return {
    dom, doc, writes, adds,
    rerender: async (list) => { pushDecisions(list || cards); await tick(); },
    card: (id) => doc.querySelector('.card[data-id="' + id + '"]'),
    click: async (el) => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); await tick(); },
    hold: (v) => { holdUpdates = v; },
    chosenText: (id) => { const b = doc.querySelector('.card[data-id="' + id + '"] .option-btn.chosen'); return b ? b.firstChild.textContent : null; },
    approve: (id) => doc.querySelector('.card[data-id="' + id + '"] [data-action="approve-recommended"]'),
  };
}

const base = () => ({ id: 'c1', title: 'Pick a host', ownerRequired: true, status: 'open', kind: 'decision', context: 'ctx.', bestPractice: 'bp', options: ['Option A', 'Option B', 'Option C'], recommendedOption: 0, createdAt: new Date().toISOString() });
const other = () => ({ id: 'c2', title: 'Other', ownerRequired: true, status: 'open', kind: 'decision', context: 'x.', bestPractice: 'bp', options: ['Yes', 'No'], recommendedOption: 0, createdAt: new Date().toISOString() });

(async () => {
  // 0. "No pre-highlight" (owner decision 2026-09-17): nothing selected, Approve inert until a pick.
  {
    const p = await makePage([base()]);
    ok('0 no option starts highlighted', p.chosenText('c1') === null);
    ok('0 the recommended option is labelled, not selected', /ops recommends/.test(p.card('c1').querySelector('[data-opt="0"]').textContent) && !/ops recommends/.test(p.card('c1').querySelector('[data-opt="1"]').textContent));
    ok('0 recommendation box still shows which and why', /Ops recommends/.test(p.card('c1').querySelector('.suggestion').textContent) && /Option A/.test(p.card('c1').querySelector('.suggestion').textContent));
    ok('0 Approve is disabled and the hint shows', p.approve('c1').disabled === true && p.card('c1').querySelector('[data-role="pick-hint"]').hidden === false);
    await p.click(p.approve('c1')); await p.click(p.approve('c1'));
    p.approve('c1').disabled = false; // even if something re-enabled it, no pick means no write
    await p.click(p.approve('c1')); await p.click(p.approve('c1'));
    ok('0 no pick -> Approve writes nothing, however often it is clicked', p.writes.length === 0 && !p.approve('c1').classList.contains('armed'));
    await p.rerender();
    ok('0 still nothing selected after a re-render', p.chosenText('c1') === null && p.approve('c1').disabled === true);
    await p.click(p.card('c1').querySelector('[data-opt="0"]'));
    ok('0 picking enables Approve and hides the hint', p.approve('c1').disabled === false && p.card('c1').querySelector('[data-role="pick-hint"]').hidden === true);
    await p.rerender();
    ok('0 re-render keeps the pick and keeps Approve enabled', p.chosenText('c1') === 'Option A' && p.approve('c1').disabled === false && p.card('c1').querySelector('[data-role="pick-hint"]').hidden === true);
    await p.click(p.approve('c1'));
    ok('0 picking the recommended one reads as an approval', /Will approve: "Option A"/.test(p.card('c1').querySelector('.status-banner').textContent) && p.writes.length === 0);
    await p.click(p.approve('c1'));
    ok('0 pick -> two clicks -> writes the pick', p.writes.length === 1 && p.writes[0].data.resolution === 'Option A');
  }
  // 1. The reported bug: pick B -> re-render -> arm -> confirm must write B.
  {
    const p = await makePage([base(), other()]);
    ok('1 starts with nothing selected', p.chosenText('c1') === null);
    await p.click(p.card('c1').querySelector('[data-opt="1"]'));
    await p.rerender([base(), { ...other(), title: 'Other (changed by a session)' }]);
    ok('1 pick survives a re-render (highlight)', p.chosenText('c1') === 'Option B');
    ok('1 the other card is untouched', p.chosenText('c2') === null);
    await p.click(p.card('c1').querySelector('[data-action="approve-recommended"]'));
    ok('1 banner names B when arming', /Will override with: "Option B"/.test(p.card('c1').querySelector('.status-banner').textContent));
    ok('1 nothing written on first click', p.writes.length === 0);
    await p.click(p.card('c1').querySelector('[data-action="approve-recommended"]'));
    ok('1 second click writes exactly once', p.writes.length === 1);
    ok('1 written resolution is B, not the recommendation', p.writes[0] && p.writes[0].data.resolution === 'Option B' && p.writes[0].data.status === 'resolved' && p.writes[0].path === 'decisions/c1');
  }
  // 2. Re-render lands BETWEEN the two clicks: still one confirm click, still B.
  {
    const p = await makePage([base()]);
    await p.click(p.card('c1').querySelector('[data-opt="1"]'));
    await p.click(p.card('c1').querySelector('[data-action="approve-recommended"]'));
    await p.rerender();
    const btn = p.card('c1').querySelector('[data-action="approve-recommended"]');
    ok('2 confirm stays armed across the re-render', btn.classList.contains('armed') && btn.textContent === 'Click again to confirm');
    ok('2 still nothing written', p.writes.length === 0);
    await p.click(btn);
    ok('2 confirm click writes B', p.writes.length === 1 && p.writes[0].data.resolution === 'Option B');
  }
  // 3. Options list changes under an armed confirm: pick and confirm are both dropped.
  {
    const p = await makePage([base()]);
    await p.click(p.card('c1').querySelector('[data-opt="1"]'));
    await p.click(p.card('c1').querySelector('[data-action="approve-recommended"]'));
    await p.rerender([{ ...base(), options: ['Option A', 'Option B2', 'Option C'] }]);
    const btn = p.card('c1').querySelector('[data-action="approve-recommended"]');
    ok('3 changed options: the pick is dropped, nothing selected', p.chosenText('c1') === null);
    ok('3 changed options: confirm is disarmed and Approve disabled again', !btn.classList.contains('armed') && btn.disabled === true);
    await p.click(btn); await p.click(btn);
    ok('3 clicks write nothing until he picks again', p.writes.length === 0);
  }
  // 4. Arm on A, then pick B: disarms; the next two clicks write B.
  {
    const p = await makePage([base()]);
    const btn = () => p.card('c1').querySelector('[data-action="approve-recommended"]');
    await p.click(p.card('c1').querySelector('[data-opt="0"]'));
    await p.click(btn());
    ok('4 armed on A', btn().classList.contains('armed'));
    await p.click(p.card('c1').querySelector('[data-opt="1"]'));
    ok('4 picking another option disarms', !btn().classList.contains('armed'));
    await p.rerender();
    ok('4 stays disarmed after a re-render', !btn().classList.contains('armed') && p.chosenText('c1') === 'Option B');
    await p.click(btn());
    ok('4 first click after the change only arms', p.writes.length === 0);
    await p.click(btn());
    ok('4 writes B', p.writes.length === 1 && p.writes[0].data.resolution === 'Option B');
  }
  // 5. Armed confirm expires after 8s even if a re-render happened in between.
  {
    const p = await makePage([base()]);
    const realNow = p.dom.window.Date.now;
    await p.click(p.card('c1').querySelector('[data-opt="0"]'));
    await p.click(p.card('c1').querySelector('[data-action="approve-recommended"]'));
    ok('5 armed', p.approve('c1').classList.contains('armed'));
    p.dom.window.Date.now = () => realNow() + 9000;
    await p.rerender();
    const btn = p.card('c1').querySelector('[data-action="approve-recommended"]');
    ok('5 expired confirm is not restored', !btn.classList.contains('armed'));
    await p.click(btn);
    ok('5 click after expiry only arms', p.writes.length === 0 && btn.classList.contains('armed'));
  }
  // 6. Card resolves then reopens: the old pick is gone.
  {
    const p = await makePage([base()]);
    await p.click(p.card('c1').querySelector('[data-opt="2"]'));
    await p.rerender([{ ...base(), status: 'resolved', resolution: 'Option C', resolvedAt: new Date().toISOString() }]);
    await p.rerender([base()]);
    ok('6 reopened card starts with nothing selected again', p.chosenText('c1') === null && p.approve('c1').disabled === true);
  }
  // 7. Card with options but no recommendation ("custom" path): pick survives, writes the pick.
  {
    const c = { ...base(), recommendedOption: undefined, suggestedResolution: '' };
    const p = await makePage([c]);
    ok('7 nothing preselected without a recommendation', p.chosenText('c1') === null);
    await p.click(p.card('c1').querySelector('[data-opt="2"]'));
    await p.rerender();
    ok('7 pick survives re-render', p.chosenText('c1') === 'Option C');
    const btn = () => p.card('c1').querySelector('[data-action="custom"]');
    await p.click(btn()); await p.click(btn());
    ok('7 writes the pick', p.writes.length === 1 && p.writes[0].data.resolution === 'Option C');
  }
  // 8. Save path: Copy buttons stay usable, action buttons lock.
  {
    const a = { id: 'a1', title: 'Run it', ownerRequired: true, status: 'open', kind: 'action', context: '1. Run C:\\Users\\x\\file.cmd\n2. Done', createdAt: new Date().toISOString() };
    const p = await makePage([a]);
    p.hold(true);
    const claim = p.card('a1').querySelector('[data-action="claim"]');
    await p.click(claim); await p.click(claim);
    ok('8 claim written, status untouched', p.writes.length === 1 && 'claimedAt' in p.writes[0].data && !('status' in p.writes[0].data));
    ok('8 action button locked while saving', claim.disabled === true);
    const copy = p.card('a1').querySelector('[data-copy]');
    ok('8 Copy button not locked while saving', !!copy && copy.disabled === false);
  }
  // 9. relTime units.
  {
    const mins = (m) => new Date(Date.now() - m * 60000).toISOString();
    const mk = (id, m) => ({ id, title: id, ownerRequired: true, status: 'open', kind: 'action', context: 'x', claimedAt: mins(m), createdAt: mins(m) });
    const p = await makePage([mk('t1', 12), mk('t2', 300), mk('t3', 4320), mk('t4', 1500)]);
    const txt = (id) => p.card(id).querySelector('.check-banner b').textContent;
    ok('9 minutes: "12m ago"', /12m ago/.test(txt('t1')));
    ok('9 hours: "5h ago"', /5h ago/.test(txt('t2')));
    ok('9 days: "3 days ago" (was "4320m ago")', /3 days ago/.test(txt('t3')) && !/4320m/.test(txt('t3')));
    ok('9 singular: "1 day ago"', /1 day ago/.test(txt('t4')));
  }
  // 10. Add form writes summary + points (max 5, blanks dropped).
  {
    const p = await makePage([]);
    const $ = (id) => p.doc.getElementById(id);
    $('f-title').value = 'T';
    $('f-summary').value = ' Should we do X? ';
    $('f-points').value = 'one\n\n two \nthree\nfour\nfive\nsix';
    $('f-best-practice').value = 'bp';
    $('add-form').dispatchEvent(new p.dom.window.Event('submit', { bubbles: true, cancelable: true }));
    await tick();
    const w = p.adds[0] || {};
    ok('10 summary written, trimmed', w.summary === 'Should we do X?');
    ok('10 points: array, blanks dropped, capped at 5', Array.isArray(w.points) && w.points.join('|') === 'one|two|three|four|five');
    ok('10 never files as resolved', w.status === 'open' && !('resolution' in w));
  }
  // 11. Action card that carries options: no option can resolve; "It looked wrong" reports.
  {
    const mk = (extra) => ({ id: 'o1', title: 'Ask the author', ownerRequired: true, status: 'open', context: '1. Email them', options: ['Done, got written permission', 'Done, terms are restrictive', 'Not now', 'It looked wrong'], recommendedOption: 0, createdAt: new Date().toISOString(), ...extra });
    for (const variant of [{}, { kind: 'action' }]) {
      const tag = variant.kind ? '(kind:action)' : '(heuristic)';
      const p = await makePage([mk(variant)]);
      const c = p.card('o1');
      ok('11 ' + tag + ' rendered as an action card, nothing preselected', !!c.querySelector('[data-action="claim"]') && !c.querySelector('.option-btn') && !c.querySelector('[data-action="approve-recommended"]'));
      const reports = Array.from(c.querySelectorAll('[data-action="report"]')).map(b => b.textContent);
      ok('11 ' + tag + ' only "It looked wrong" becomes a button', reports.join('|') === 'It looked wrong');
      ok('11 ' + tag + ' both Done variants are named for the comment box', /got written permission/.test(c.textContent) && /terms are restrictive/.test(c.textContent));
      c.querySelector(':scope > textarea.comment').value = 'the form 404s';
      const btn = () => p.card('o1').querySelector('[data-action="report"]');
      await p.click(btn());
      ok('11 ' + tag + ' first click writes nothing', p.writes.length === 0 && btn().classList.contains('armed'));
      await p.rerender();
      ok('11 ' + tag + ' report confirm and typed comment survive a re-render', btn().classList.contains('armed') && p.card('o1').querySelector(':scope > textarea.comment').value === 'the form 404s');
      await p.click(btn());
      const w = (p.writes[0] || {}).data || {};
      ok('11 ' + tag + ' second click writes exactly one update', p.writes.length === 1);
      ok('11 ' + tag + ' writes checkResult + comment, checkedBy owner', w.checkResult === 'It looked wrong - the form 404s' && w.checkedBy === 'owner' && !!w.checkedAt);
      ok('11 ' + tag + ' never resolves: no status, no resolution, claimedAt cleared', !('status' in w) && !('resolution' in w) && !('resolvedAt' in w) && w.claimedAt === '');
    }
    // after the report lands, the card is still open and shows it as HIS report
    const p = await makePage([mk({ kind: 'action', checkResult: 'It looked wrong - the form 404s', checkedBy: 'owner', checkedAt: new Date().toISOString() })]);
    ok('11 reported card stays in the list, labelled as his report', !!p.card('o1') && /You reported a problem/.test(p.card('o1').textContent) && !/it has not happened yet/.test(p.card('o1').textContent));
    const q = await makePage([mk({ kind: 'action', checkResult: 'PR still open', checkedBy: 'github-8b', checkedAt: new Date().toISOString() })]);
    ok('11 a session\'s failed check keeps its old wording', /Last check .* by github-8b: it has not happened yet/.test(q.card('o1').textContent));
    // claim + report buttons keep separate armed slots
    const r = await makePage([mk({ kind: 'action' })]);
    await r.click(r.card('o1').querySelector('[data-action="report"]'));
    await r.click(r.card('o1').querySelector('[data-action="claim"]'));
    ok('11 arming Claim disarms Report (one armed button per card)', !r.card('o1').querySelector('[data-action="report"]').classList.contains('armed') && r.card('o1').querySelector('[data-action="claim"]').classList.contains('armed') && r.writes.length === 0);
    await r.click(r.card('o1').querySelector('[data-action="claim"]'));
    ok('11 claim still writes a claim only', r.writes.length === 1 && 'claimedAt' in r.writes[0].data && r.writes[0].data.claimedAt !== '' && !('status' in r.writes[0].data));
  }
  console.log(fail ? ('FAILURES: ' + fail) : 'ALL PASS');
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error('HARNESS ERROR', e); process.exit(2); });
