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
