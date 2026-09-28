// Tips of the Day - rezultati uživo (Cloudflare Worker, besplatno).
// Jedan poziv za sve današnje fudbalske i jedan za sve košarkaške utakmice, keš 2 minute za sve posjetioce.
// Kočnica: ako API-Football ostane ispod 2500 poziva za danas, uživo se pauzira sat vremena (tipovi i tiket nikad ne ostanu bez podataka).
const TTL = 120, MIN_LEFT = 2500;
const CORS = { 'Access-Control-Allow-Origin': '*', 'Content-Type': 'application/json; charset=utf-8' };

function todaySarajevo() {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Sarajevo', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
}

export default {
  async fetch(req, env, ctx) {
    const cache = caches.default;
    const url = new URL(req.url);
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
    if (!pause && env.API_KEY) {
      const H = { 'x-apisports-key': env.API_KEY };
      const d = out.d;
      try {
        const r = await fetch(`https://v3.football.api-sports.io/fixtures?date=${d}&timezone=Europe/Sarajevo`, { headers: H });
        const left = Number(r.headers.get('x-ratelimit-requests-remaining'));
        const j = await r.json();
        for (const x of (j.response || [])) {
          const s = x.fixture.status.short;
          if (s === 'NS' || s === 'TBD') continue;
          out.f['af' + x.fixture.id] = { s, m: x.fixture.status.elapsed, h: x.goals.home, a: x.goals.away };
        }
        out.left = left;
        if (!j.results) out.fe = j.errors;   // za dijagnozu ako API nista ne vrati
        if (left && left < MIN_LEFT) ctx.waitUntil(cache.put(new Request('https://totd-live.cache/pause'), new Response('1', { headers: { 'Cache-Control': 'max-age=3600' } })));
      } catch (e) { out.ferr = 1; }
      try {
        const r = await fetch(`https://v1.basketball.api-sports.io/games?date=${d}&timezone=Europe/Sarajevo`, { headers: H });
        const j = await r.json();
        for (const g of (j.response || [])) {
          const s = g.status.short;
          if (s === 'NS' || s === 'TBD') continue;
          out.b['bb' + g.id] = { s, m: g.status.timer, h: g.scores.home.total, a: g.scores.away.total };
        }
      } catch (e) { out.berr = 1; }
    }
    const body = JSON.stringify(out);
    ctx.waitUntil(cache.put(ck, new Response(body, { headers: { 'Cache-Control': `max-age=${TTL}` } })));
    return new Response(body, { headers: { ...CORS, 'Cache-Control': 'public, max-age=60' } });
  }
};
