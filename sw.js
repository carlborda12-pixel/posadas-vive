/* ===================================================================
   PosadasVive · service worker
   Subir a la misma carpeta que index.html.

   Al cambiar el contenido de la app hay que subir VERSION, si no los
   navegadores que ya la visitaron siguen mostrando la version vieja.
   =================================================================== */
const VERSION = 'pv-2026-09-13-2';

const CACHE_APP    = VERSION + '-app';     // la app en si
const CACHE_MAPA   = VERSION + '-mapa';    // tiles del mapa
const CACHE_FOTOS  = VERSION + '-fotos';   // imagenes de lugares
const CACHE_DATOS  = VERSION + '-datos';   // catalogo de Supabase

// Lo minimo para que la app abra sin conexion
const APP_SHELL = [
  './',
  './index.html',
  './manifest.webmanifest',
  './iconos/icono-192.png',
  './iconos/icono-512.png'
];

// Topes: sin esto el cache del mapa crece sin limite
const TOPES = { [CACHE_MAPA]: 320, [CACHE_FOTOS]: 60 };

async function podar(nombre){
  const tope = TOPES[nombre];
  if(!tope) return;
  const c = await caches.open(nombre);
  const claves = await c.keys();
  if(claves.length <= tope) return;
  // las mas viejas primero (keys() devuelve en orden de insercion)
  await Promise.all(claves.slice(0, claves.length - tope).map(k => c.delete(k)));
}

// ------------------------------------------------------------------
self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE_APP)
      .then(c => c.addAll(APP_SHELL))
      .then(() => self.skipWaiting())
      .catch(err => console.warn('[SW] precache incompleto:', err))
  );
});

self.addEventListener('activate', e => {
  e.waitUntil((async () => {
    const nombres = await caches.keys();
    await Promise.all(
      nombres.filter(n => !n.startsWith(VERSION)).map(n => caches.delete(n))
    );
    await self.clients.claim();
  })());
});

// Permite que la pagina fuerce la actualizacion
self.addEventListener('message', e => {
  if(e.data === 'actualizar') self.skipWaiting();
});

// ------------------------------------------------------------------
// Estrategias
// ------------------------------------------------------------------
async function cacheFirst(req, nombre){
  const c = await caches.open(nombre);
  const hit = await c.match(req);
  if(hit) return hit;
  const res = await fetch(req);
  if(res && (res.ok || res.type === 'opaque')){
    c.put(req, res.clone());
    podar(nombre);
  }
  return res;
}

async function networkFirst(req, nombre){
  const c = await caches.open(nombre);
  try {
    const res = await fetch(req);
    if(res && res.ok) c.put(req, res.clone());
    return res;
  } catch(err){
    const hit = await c.match(req);
    if(hit) return hit;
    throw err;
  }
}

// ------------------------------------------------------------------
self.addEventListener('fetch', e => {
  const req = e.request;
  if(req.method !== 'GET') return;                 // reservas y RPC: nunca al cache

  const url = new URL(req.url);

  // Navegacion: si no hay red, servimos la app guardada
  if(req.mode === 'navigate'){
    e.respondWith(
      fetch(req).catch(() => caches.match('./index.html', { ignoreSearch: true }))
    );
    return;
  }

  // Catalogo de lugares: primero la red, y si no hay, el ultimo que vimos.
  // Asi la agenda sigue visible sin conexion.
  if(url.pathname.includes('/rest/v1/lugares')){
    e.respondWith(networkFirst(req, CACHE_DATOS));
    return;
  }

  // El resto de Supabase (cupos, clima) necesita datos frescos: sin cache
  if(url.hostname.endsWith('.supabase.co') || url.hostname.endsWith('open-meteo.com')){
    return;
  }

  // Tiles del mapa
  if(url.hostname.includes('arcgisonline.com')){
    e.respondWith(cacheFirst(req, CACHE_MAPA));
    return;
  }

  // Fotos de lugares
  if(/\.(jpg|jpeg|png|webp|avif)$/i.test(url.pathname)){
    e.respondWith(cacheFirst(req, CACHE_FOTOS));
    return;
  }

  // Librerias y tipografias externas
  if(url.hostname.includes('unpkg.com') ||
     url.hostname.includes('fonts.googleapis.com') ||
     url.hostname.includes('fonts.gstatic.com')){
    e.respondWith(cacheFirst(req, CACHE_APP));
    return;
  }

  // Mismo origen: red primero, cache de respaldo
  if(url.origin === self.location.origin){
    e.respondWith(networkFirst(req, CACHE_APP));
  }
});
