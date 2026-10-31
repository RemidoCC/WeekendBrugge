// Service worker: de app opent snel en werkt ook zonder bereik.
// - De app zelf: eerst het netwerk (max. 3 s), anders de laatst bewaarde versie.
// - Lettertypes en de sleepbibliotheek: uit de cache, want die veranderen niet.
// - Database, weer en treinen: altijd live.
const CACHE = "brugge-v3";
const SCHIL = ["./", "./index.html", "./manifest.webmanifest", "./icoon.svg", "./icoon-192.png"];
const VAST = ["fonts.googleapis.com", "fonts.gstatic.com", "cdn.jsdelivr.net"];
self.addEventListener("install", e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(SCHIL)).then(() => self.skipWaiting())); });
self.addEventListener("activate", e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener("fetch", e => {
  if (e.request.method !== "GET") return;
  const u = new URL(e.request.url);
  if (VAST.includes(u.hostname)) {
    e.respondWith(caches.match(e.request).then(r => r || fetch(e.request).then(n => { const k = n.clone(); caches.open(CACHE).then(c => c.put(e.request, k)); return n; })));
    return;
  }
  if (u.origin !== location.origin) return;
  e.respondWith(new Promise(klaar => {
    let klaarGezet = false;
    const uitCache = () => caches.match(e.request, { ignoreSearch: true }).then(r => r || caches.match("./index.html"));
    const timer = setTimeout(() => uitCache().then(r => { if (r && !klaarGezet) { klaarGezet = true; klaar(r); } }), 3000);
    fetch(e.request).then(r => {
      clearTimeout(timer);
      const kopie = r.clone(); caches.open(CACHE).then(c => c.put(e.request, kopie));
      if (!klaarGezet) { klaarGezet = true; klaar(r); }
    }).catch(() => { clearTimeout(timer); uitCache().then(r => { if (!klaarGezet) { klaarGezet = true; klaar(r || Response.error()); } }); });
  }));
});
