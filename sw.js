// Eenvoudige service worker: de app opent ook zonder bereik.
// Eerst het netwerk, bij geen verbinding de laatst bewaarde versie.
const CACHE = "brugge-v1";
const SCHIL = ["./", "./index.html", "./manifest.webmanifest", "./icoon.svg", "./icoon-192.png"];
self.addEventListener("install", e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(SCHIL)).then(() => self.skipWaiting())); });
self.addEventListener("activate", e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener("fetch", e => {
  const u = new URL(e.request.url);
  if (e.request.method !== "GET" || u.origin !== location.origin) return; // database en weer altijd live
  e.respondWith(fetch(e.request).then(r => { const kopie = r.clone(); caches.open(CACHE).then(c => c.put(e.request, kopie)); return r; })
    .catch(() => caches.match(e.request).then(r => r || caches.match("./index.html"))));
});
