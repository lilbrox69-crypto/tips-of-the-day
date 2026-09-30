// Tips of the Day - rezultati uživo (Cloudflare Worker, besplatno).
// Jedan poziv za sve današnje fudbalske i jedan za sve košarkaške utakmice, keš 2 minute za sve posjetioce.
// Kočnica: ako API-Football ostane ispod 2500 poziva za danas, uživo se pauzira sat vremena (tipovi i tiket nikad ne ostanu bez podataka).
const TTL = 120, MIN_LEFT = 2500;
const CORS = { 'Access-Control-Allow-Origin': '*', 'Content-Type': 'application/json; charset=utf-8' };

function todaySarajevo() {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Sarajevo', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
}

// ======================= TIPSTER LIGA (nalozi, tiketi, tabele) =======================
// Igra se "monopol" novcem (nije pravi novac): ulog 50 € monopol po tiketu, 1 tiket dnevno, 2-5 parova sa stranice.
// Podaci u Cloudflare KV (binding LIGA): user:<nick>, sess:<token>, tk:<datum>:<nick>, day:<datum> (lista nadimaka).
const STAKE = 50, SITE = 'https://tipsoftheday.win';
const J = (o, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...CORS, 'Cache-Control': 'no-store' } });
const nowSa = () => { const p = Object.fromEntries(new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Sarajevo', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false }).formatToParts(new Date()).map(x => [x.type, x.value])); return { d: `${p.year}-${p.month}-${p.day}`, hm: `${p.hour === '24' ? '00' : p.hour}:${p.minute}` }; };
const hex = b => [...new Uint8Array(b)].map(x => x.toString(16).padStart(2, '0')).join('');
async function hashPass(pass, salt) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(pass), 'PBKDF2', false, ['deriveBits']);
  return hex(await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt: new TextEncoder().encode(salt), iterations: 20000 }, key, 256));
}
async function siteData(ctx) {   // danasnji tipovi sa stranice (da niko ne moze podmetnuti svoje kvote)
  const c = caches.default, k = new Request('https://totd-live.cache/sitedata');
  const hit = await c.match(k); if (hit) return hit.json();
  const d = await (await fetch(SITE + '/data.json?x=' + Date.now())).json();
  ctx.waitUntil(c.put(k, new Response(JSON.stringify(d), { headers: { 'Cache-Control': 'max-age=300' } })));
  return d;
}
function judge(sp, mk, x) {   // konacna ocjena para (1/0/null)
  const h = +x.h || 0, a = +x.a || 0, t = h + a;
  const r = sp === 'basketball'
    ? { w1: h > a, w2: a > h, o220: t >= 221, u220: t <= 220, m10: Math.abs(h - a) >= 10, h110: h >= 110, o160: t >= 161, u160: t <= 160, h80: h >= 80 }[mk]
    : { gg: h > 0 && a > 0, o15: t >= 2, o25: t >= 3, u25: t <= 2, hs: h > 0, as: a > 0, w1: h > a, x: h === a, w2: a > h,
        c8: x.hc == null ? undefined : (x.hc + x.ac) >= 8, y3: x.hy == null ? undefined : (x.hy + x.ay) >= 3 }[mk];
  return r === undefined ? null : (r ? 1 : 0);
}
async function settleTicket(tk, env) {   // dohvati rezultate parova i obracunaj tiket
  if (tk.r != null) return false;
  const H = { 'x-apisports-key': env.API_KEY }, OFF = ['PST', 'CANC', 'ABD', 'AWD', 'WO'];
  const fb = tk.legs.filter(l => l.sport === 'football' && l.r == null).map(l => l.id.slice(2));
  const res = {};
  if (fb.length) { try { const j = await (await fetch('https://v3.football.api-sports.io/fixtures?ids=' + fb.join('-'), { headers: H })).json();
    for (const f of (j.response || [])) { const s = f.fixture.status.short; const st = (tid, type) => { const z = (f.statistics || []).find(q => q.team.id === tid); const v = z && (z.statistics.find(q => q.type === type) || {}).value; return v == null ? null : Number(v); };
      const hc = st(f.teams.home.id, 'Corner Kicks'), ac = st(f.teams.away.id, 'Corner Kicks');
      res['af' + f.fixture.id] = { s, fin: ['FT', 'AET', 'PEN'].includes(s), off: OFF.includes(s), h: f.goals.home, a: f.goals.away, ...(hc != null && ac != null && hc + ac > 0 ? { hc, ac, hy: st(f.teams.home.id, 'Yellow Cards') || 0, ay: st(f.teams.away.id, 'Yellow Cards') || 0 } : {}) }; } } catch (e) {} }
  for (const l of tk.legs.filter(l => l.sport === 'basketball' && l.r == null)) {
    try { const j = await (await fetch('https://v1.basketball.api-sports.io/games?id=' + l.id.slice(2), { headers: H })).json(); const g = (j.response || [])[0];
      if (g) res[l.id] = { s: g.status.short, fin: ['FT', 'AOT'].includes(g.status.short), off: OFF.includes(g.status.short), h: g.scores.home.total, a: g.scores.away.total }; } catch (e) {}
  }
  let changed = false;
  for (const l of tk.legs) {
    if (l.r != null) continue; const x = res[l.id]; if (!x) continue;
    if (x.off) { l.r = 1; l.void = 1; l.o = 1; changed = true; continue; }   // odgodjena utakmica = kvota 1.00, kao u kladionici
    if (!x.fin) continue;
    const v = judge(l.sport, l.mk, x); l.sc = `${x.h}:${x.a}`;
    l.r = v == null ? 1 : v; if (v == null) { l.void = 1; l.o = 1; } changed = true;   // bez statistike kornera -> ponisteno (kvota 1)
  }
  if (tk.legs.some(l => l.r === 0)) { tk.r = 0; tk.win = -STAKE; changed = true; }
  else if (tk.legs.every(l => l.r === 1)) { tk.odd = Math.round(tk.legs.reduce((m, l) => m * l.o, 1) * 100) / 100; tk.r = 1; tk.win = Math.round((STAKE * tk.odd - STAKE) * 100) / 100; changed = true; }
  return changed;
}
async function getTicketsFor(dates, env, ctx, settle) {
  const out = [];
  for (const d of dates) {
    const nicks = (await env.LIGA.get('day:' + d, 'json')) || [];
    for (const n of nicks) {
      const k = `tk:${d}:${n}`; const tk = await env.LIGA.get(k, 'json'); if (!tk) continue;
      if (settle && tk.r == null && env.API_KEY && await settleTicket(tk, env)) ctx.waitUntil(env.LIGA.put(k, JSON.stringify(tk)));
      out.push(tk);
    }
  }
  return out;
}
function periodDates(p) {
  const { d } = nowSa(); const t = new Date(d + 'T12:00:00Z'); const out = [];
  let start;
  if (p === 'month') start = new Date(d.slice(0, 8) + '01T12:00:00Z');
  else { const wd = (t.getUTCDay() + 6) % 7; start = new Date(t.getTime() - wd * 86400000); }   // sedmica od ponedjeljka
  for (let x = start; x <= t; x = new Date(x.getTime() + 86400000)) out.push(x.toISOString().slice(0, 10));
  return out;
}
async function handleApi(req, env, ctx, url) {
  if (req.method === 'OPTIONS') return new Response(null, { headers: { ...CORS, 'Access-Control-Allow-Methods': 'GET,POST,OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type' } });
  if (!env.LIGA) return J({ err: 'noliga' }, 503);
  const path = url.pathname.slice(5);
  let body = {}; if (req.method === 'POST') { try { body = JSON.parse(await req.text()); } catch (e) { return J({ err: 'bad' }, 400); } }
  const auth = async () => { const t = String(body.tok || url.searchParams.get('tok') || ''); if (!/^[0-9a-f]{40}$/.test(t)) return null; return env.LIGA.get('sess:' + t); };
  const newSess = async (nk) => { const t = hex(crypto.getRandomValues(new Uint8Array(20))); await env.LIGA.put('sess:' + t, nk, { expirationTtl: 60 * 60 * 24 * 180 }); return t; };

  if (path === 'register' || path === 'login') {
    const nick = String(body.nick || '').trim(), pass = String(body.pass || '');
    if (!/^[\p{L}\p{N}_.\-]{3,20}$/u.test(nick)) return J({ err: 'nick' }, 400);
    if (pass.length < 6 || pass.length > 64) return J({ err: 'pass' }, 400);
    const nk = nick.toLowerCase(); const u = await env.LIGA.get('user:' + nk, 'json');
    if (path === 'register') {
      if (u) return J({ err: 'taken' }, 409);
      const salt = hex(crypto.getRandomValues(new Uint8Array(16)));
      await env.LIGA.put('user:' + nk, JSON.stringify({ nick, salt, hash: await hashPass(pass, salt), created: nowSa().d, days: [] }));
      return J({ ok: 1, nick, tok: await newSess(nk) });
    }
    if (!u || u.hash !== await hashPass(pass, u.salt)) return J({ err: 'wrong' }, 401);
    return J({ ok: 1, nick: u.nick, tok: await newSess(nk) });
  }
  if (path === 'ticket' && req.method === 'POST') {
    const nk = await auth(); if (!nk) return J({ err: 'auth' }, 401);
    const { d, hm } = nowSa(); const key = `tk:${d}:${nk}`;
    if (await env.LIGA.get(key)) return J({ err: 'already' }, 409);
    const want = Array.isArray(body.legs) ? body.legs.slice(0, 6) : [];
    if (want.length < 2 || want.length > 5) return J({ err: 'count' }, 400);
    const data = await siteData(ctx); if (data.today !== d) return J({ err: 'notready' }, 409);
    const pool = {};
    for (const m of ((data.days || []).find(x => x.date === d) || {}).matches || []) pool[m.id] = ['football', m];
    for (const m of (((data.sports || {}).basketball || {}).days || []).find(x => x.date === d)?.matches || []) pool[m.id] = ['basketball', m];
    const legs = [], seen = new Set();
    for (const w of want) {
      const e = pool[String(w.id)]; if (!e) return J({ err: 'unknown' }, 400);
      const [sport, m] = e, mk = String(w.mk);
      if (seen.has(m.id)) return J({ err: 'samematch' }, 400); seen.add(m.id);
      const o = m.o && m.o[mk], p = m.p && m.p[mk]; if (!o || p == null) return J({ err: 'noodds' }, 400);
      if (String(m.time) <= hm) return J({ err: 'started', id: m.id }, 400);
      legs.push({ id: m.id, sport, mk, o: +o, p: +p, home: m.home, away: m.away, time: m.time, league: m.league, hl: m.hl, al: m.al });
    }
    const u = await env.LIGA.get('user:' + nk, 'json');
    const tk = { nick: u.nick, date: d, at: hm, stake: STAKE, odd: Math.round(legs.reduce((x, l) => x * l.o, 1) * 100) / 100, legs, r: null };
    await env.LIGA.put(key, JSON.stringify(tk));
    const list = (await env.LIGA.get('day:' + d, 'json')) || []; if (!list.includes(nk)) { list.push(nk); await env.LIGA.put('day:' + d, JSON.stringify(list)); }
    u.days = [d, ...(u.days || []).filter(x => x !== d)].slice(0, 120); await env.LIGA.put('user:' + nk, JSON.stringify(u));
    return J({ ok: 1, ticket: tk });
  }
  if (path === 'me') {
    const nk = await auth(); if (!nk) return J({ err: 'auth' }, 401);
    const u = await env.LIGA.get('user:' + nk, 'json'); if (!u) return J({ err: 'auth' }, 401);
    const tickets = [];
    for (const d of (u.days || []).slice(0, 30)) { const k = `tk:${d}:${nk}`; const tk = await env.LIGA.get(k, 'json'); if (!tk) continue; if (tk.r == null && env.API_KEY && await settleTicket(tk, env)) ctx.waitUntil(env.LIGA.put(k, JSON.stringify(tk))); tickets.push(tk); }
    const done = tickets.filter(t => t.r != null);
    return J({ nick: u.nick, since: u.created, today: nowSa().d, tickets, stats: { n: done.length, won: done.filter(t => t.r === 1).length, profit: Math.round(done.reduce((s, t) => s + (t.win || 0), 0) * 100) / 100 } });
  }
  if (path === 'league') {
    const p = url.searchParams.get('p') === 'month' ? 'month' : 'week';
    const c = caches.default, ck = new Request('https://totd-live.cache/league/' + p + '/' + nowSa().d);
    const hit = await c.match(ck); if (hit) return new Response(hit.body, { headers: { ...CORS, 'Cache-Control': 'no-store' } });
    const tks = await getTicketsFor(periodDates(p), env, ctx, true);
    const by = {};
    for (const t of tks) { const b = by[t.nick] = by[t.nick] || { nick: t.nick, n: 0, won: 0, profit: 0, best: 0, pending: 0 };
      if (t.r == null) { b.pending++; continue; } b.n++; if (t.r === 1) { b.won++; b.best = Math.max(b.best, t.odd); } b.profit = Math.round((b.profit + (t.win || 0)) * 100) / 100; }
    const min = p === 'month' ? 5 : 3;
    const rows = Object.values(by).sort((a, b) => b.profit - a.profit || b.won - a.won);
    const out = JSON.stringify({ p, min, from: periodDates(p)[0], rows: rows.filter(r => r.n >= min).slice(0, 100), others: rows.filter(r => r.n < min).map(r => ({ nick: r.nick, n: r.n, pending: r.pending })) });
    ctx.waitUntil(c.put(ck, new Response(out, { headers: { 'Cache-Control': 'max-age=300' } })));
    return new Response(out, { headers: { ...CORS, 'Cache-Control': 'no-store' } });
  }
  return J({ err: 'notfound' }, 404);
}

export default {
  async fetch(req, env, ctx) {
    const cache = caches.default;
    const url = new URL(req.url);
    if (url.pathname.startsWith('/api/')) return J({ err: 'off' }, 404);   // liga/nalozi ugaseni (Bilal, 29.9.)
    // /stats?ids=af1,af2 -> korneri i zuti kartoni za zavrsene utakmice (kes 1 dan po utakmici)
    if (url.pathname === '/stats') {
      const ids = (url.searchParams.get('ids') || '').split(',').filter(x => /^af\d+$/.test(x)).slice(0, 20);
      const res = {}, miss = [];
      for (const id of ids) { const c = await cache.match(new Request('https://totd-live.cache/st/' + id)); if (c) res[id] = await c.json(); else miss.push(id); }
      if (miss.length && env.API_KEY) {
        try {
          const r = await fetch('https://v3.football.api-sports.io/fixtures?ids=' + miss.map(x => x.slice(2)).join('-'), { headers: { 'x-apisports-key': env.API_KEY } });
          const j = await r.json();
          for (const f of (j.response || [])) {
            const id = 'af' + f.fixture.id;
            if (!['FT', 'AET', 'PEN'].includes(f.fixture.status.short)) continue;
            const st = (tid, type) => { const s = (f.statistics || []).find(z => z.team.id === tid); const v = s && (s.statistics.find(q => q.type === type) || {}).value; return v == null ? null : Number(v); };
            const hc = st(f.teams.home.id, 'Corner Kicks'), ac = st(f.teams.away.id, 'Corner Kicks');
            const e = (hc != null && ac != null && hc + ac > 0) ? { hc, ac, hy: st(f.teams.home.id, 'Yellow Cards') || 0, ay: st(f.teams.away.id, 'Yellow Cards') || 0 } : { none: 1 };
            res[id] = e;
            ctx.waitUntil(cache.put(new Request('https://totd-live.cache/st/' + id), new Response(JSON.stringify(e), { headers: { 'Cache-Control': 'max-age=' + (e.none ? 1800 : 86400) } })));
          }
        } catch (e) {}
      }
      return new Response(JSON.stringify(res), { headers: { ...CORS, 'Cache-Control': 'public, max-age=60' } });
    }
    const ck = new Request('https://totd-live.cache/v2');
    const hit = await cache.match(ck);
    if (hit) return new Response(hit.body, { headers: { ...CORS, 'Cache-Control': 'public, max-age=60' } });

    const pause = await cache.match(new Request('https://totd-live.cache/pause'));
    const out = { t: Date.now(), d: todaySarajevo(), f: {}, b: {}, paused: !!pause };
    if (env.API_KEY) {
      const H = { 'x-apisports-key': env.API_KEY };
      const d = out.d;
      // API-Sports iz Cloudflare-a cesto vrati "too many requests" (dijeljene IP adrese), pa za oba sporta:
      // do 4 pokusaja, a zadnji dobri rezultati se cuvaju u kes + KV (globalno) da rezultat nikad ne "nestane".
      async function grab(url, kvKey, parse, errKey) {
        let ok = false, res = {}, left = null;
        for (let i = 0; i < 4 && !ok; i++) {
          if (i) await new Promise(r => setTimeout(r, 700 * i));
          try {
            const r = await fetch(url, { headers: H });
            left = Number(r.headers.get('x-ratelimit-requests-remaining'));
            const j = await r.json();
            if (!j.results) { out[errKey] = j.errors; continue; }
            res = parse(j.response || []); ok = true; delete out[errKey];
          } catch (e) { out[errKey] = String(e).slice(0, 80); }
        }
        const ck2 = new Request('https://totd-live.cache/' + kvKey);
        if (ok && Object.keys(res).length) {
          const val = JSON.stringify({ d, t: Date.now(), v: res });
          ctx.waitUntil(cache.put(ck2, new Response(val, { headers: { 'Cache-Control': 'max-age=86400' } })));
          // KV: najvise jedan upis svakih 5 minuta po sportu (besplatni limit 1000 upisa dnevno)
          if (env.LIGA) ctx.waitUntil((async () => { const cur = await env.LIGA.get(kvKey, 'json'); if (!cur || cur.d !== d || Date.now() - cur.t > 300000) await env.LIGA.put(kvKey, val, { expirationTtl: 172800 }); })().catch(() => {}));
        }
        if (!ok) {
          let lb = null; const lh = await cache.match(ck2); if (lh) lb = await lh.json();
          if ((!lb || lb.d !== d) && env.LIGA) lb = await env.LIGA.get(kvKey, 'json').catch(() => null);
          if (lb && lb.d === d) { res = lb.v; out.old = 1; }
        }
        return { res, left, ok };
      }
      if (!pause) {   // kocnica vazi samo za fudbal; kosarka ima svoj limit
        const g = await grab(`https://v3.football.api-sports.io/fixtures?date=${d}&timezone=Europe/Sarajevo`, 'livef', arr => {
          const o = {}; for (const x of arr) { const s = x.fixture.status.short; if (s === 'NS' || s === 'TBD') continue; o['af' + x.fixture.id] = { s, m: x.fixture.status.elapsed, h: x.goals.home, a: x.goals.away }; } return o; }, 'fe');
        out.f = g.res; if (g.ok) out.left = g.left;
        if (g.ok && g.left && g.left < MIN_LEFT) ctx.waitUntil(cache.put(new Request('https://totd-live.cache/pause'), new Response('1', { headers: { 'Cache-Control': 'max-age=3600' } })));
      }
      const gb = await grab(`https://v1.basketball.api-sports.io/games?date=${d}&timezone=Europe/Sarajevo`, 'liveb2', arr => {
        const o = {}; for (const x of arr) { const s = x.status.short; if (s === 'NS' || s === 'TBD') continue; o['bb' + x.id] = { s, m: x.status.timer, h: x.scores.home.total, a: x.scores.away.total }; } return o; }, 'be');
      out.b = gb.res; out.bl = gb.left;
    }
    const body = JSON.stringify(out);
    // ako kosarka nije stigla, pokusaj ponovo vec za 45 s (inace 2 minute)
    ctx.waitUntil(cache.put(ck, new Response(body, { headers: { 'Cache-Control': `max-age=${out.old || out.be || out.fe ? 45 : TTL}` } })));
    return new Response(body, { headers: { ...CORS, 'Cache-Control': 'public, max-age=60' } });
  }
};
