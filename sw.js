/* ===================================================================
   48 HS · service worker
   Subir a la misma carpeta que index.html.

   Al cambiar el contenido de la app hay que subir VERSION, si no los
   navegadores que ya la visitaron siguen mostrando la version vieja.

   Actualizaciones: la version nueva se instala y QUEDA ESPERANDO. La
   pagina muestra "Hay una versión nueva" y recien cuando la persona toca
   "Actualizar" se activa. Antes se activaba sola (skipWaiting en install)
   y la pagina se recargaba en medio de una inscripcion.
   =================================================================== */
const VERSION = 'pv-2026-11-12-6';

const CACHE_APP    = VERSION + '-app';     // la app en si
const CACHE_MAPA   = VERSION + '-mapa';    // tiles del mapa
const CACHE_FOTOS  = VERSION + '-fotos';   // imagenes de lugares
const CACHE_DATOS  = VERSION + '-datos';   // catalogo de Supabase

// Sin esto la app no abre offline. Si falta alguno, la instalacion falla
// a proposito: es mejor que reintentar que quedar a medias.
const APP_SHELL = [
  './',
  './index.html',
  './manifest.webmanifest'
];

// Opcionales: si alguno no existe en el host, se avisa y se sigue.
// Antes iban en el mismo addAll y un icono faltante dejaba sin cache todo.
const OPCIONALES = [
  './iconos/icono-192.png',
  './iconos/icono-512.png',
  './iconos/icono-maskable-512.png',
  './iconos/apple-touch-icon.png',
  './privacidad.html',
  './marca/logo-48h.svg',
  './marca/logo-turismo.svg',
  './marca/apextech.svg',
  './marca/turi.svg',
  './marca/inicio-hd.webp',
  './libs/leaflet/leaflet.js',
  './libs/leaflet/leaflet.css',
  './libs/leaflet/images/layers.png',
  './libs/leaflet/images/layers-2x.png',
  './marca/favicon.svg',
  './fuentes/fuentes.css',
  './fuentes/be-vietnam-pro-latin-300-normal.woff2',
  './fuentes/be-vietnam-pro-latin-400-normal.woff2',
  './fuentes/be-vietnam-pro-latin-500-normal.woff2',
  './fuentes/be-vietnam-pro-latin-600-normal.woff2',
  './fuentes/be-vietnam-pro-latin-700-normal.woff2',
  './fuentes/be-vietnam-pro-latin-800-normal.woff2',
  './fuentes/be-vietnam-pro-latin-400-italic.woff2',
  './fuentes/be-vietnam-pro-latin-500-italic.woff2',
  './fuentes/be-vietnam-pro-latin-600-italic.woff2'
];

// Topes: sin esto el cache del mapa crece sin limite.
// Las fotos todavia llegan "opacas" desde el CDN externo y cada una pesa
// mucho en la cuota del navegador; por eso el tope es bajo. Al moverlas
// al mismo dominio (o a Supabase Storage con CORS) se puede subir.
const TOPES = { [CACHE_MAPA]: 320, [CACHE_FOTOS]: 40 };

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
  e.waitUntil((async () => {
    const c = await caches.open(CACHE_APP);
    await c.addAll(APP_SHELL);
    await Promise.all(OPCIONALES.map(u =>
      c.add(u).catch(() => console.warn('[SW] No se encontró ' + u + ' (opcional)'))
    ));
    // sin skipWaiting(): espera a que la pagina lo pida
  })());
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

// La pagina manda 'actualizar' cuando la persona toca el boton
self.addEventListener('message', e => {
  if(e.data === 'actualizar') self.skipWaiting();
});

// ------------------------------------------------------------------
// Estrategias
// ------------------------------------------------------------------

// aceptarOpacas: solo para lo que no se puede pedir con CORS (fotos del
// CDN externo, script de iconos). Las tiles ya vienen con CORS.
async function cacheFirst(req, nombre, aceptarOpacas){
  const c = await caches.open(nombre);
  const hit = await c.match(req);
  if(hit) return hit;
  const res = await fetch(req);
  if(res && (res.ok || (aceptarOpacas && res.type === 'opaque'))){
    c.put(req, res.clone()).then(() => podar(nombre)).catch(() => {});
  }
  return res;
}

async function networkFirst(req, nombre){
  const c = await caches.open(nombre);
  try {
    const res = await fetch(req);
    if(res && res.ok) c.put(req, res.clone()).catch(() => {});
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
      fetch(req).catch(async () =>
        (await caches.match('./index.html', { ignoreSearch: true })) ||
        (await caches.match('./', { ignoreSearch: true })) ||
        Response.error()
      )
    );
    return;
  }

  // Catalogo de lugares: primero la red, y si no hay, el ultimo que vimos.
  if(url.hostname.endsWith('.supabase.co') && url.pathname.startsWith('/rest/v1/lugares')){
    e.respondWith(networkFirst(req, CACHE_DATOS));
    return;
  }

  // Resto de Supabase, clima y ruteo: datos frescos, sin cache
  if(url.hostname.endsWith('.supabase.co') ||
     url.hostname === 'api.open-meteo.com' ||
     url.hostname === 'routing.openstreetmap.de'){
    return;
  }

  // Tiles del mapa (pedidas con CORS desde Leaflet)
  if(url.hostname === 'server.arcgisonline.com'){
    e.respondWith(cacheFirst(req, CACHE_MAPA, false));
    return;
  }

  // Fotos de lugares. Se reconocen por el tipo de pedido y no por la
  // extension: varias URLs del CDN no tienen extension y antes no se
  // guardaban nunca.
  if(req.destination === 'image' && url.origin !== self.location.origin){
    e.respondWith(cacheFirst(req, CACHE_FOTOS, true));
    return;
  }

  // Copia de respaldo de Leaflet (la principal está en libs/leaflet). Los íconos van
  // dentro de index.html y la tipografía se sirve desde el mismo sitio (fuentes/).
  // (nombre exacto: "includes" aceptaba también "unpkg.com.sitio-falso.net")
  if(url.hostname === 'unpkg.com'){
    e.respondWith(cacheFirst(req, CACHE_APP, true));
    return;
  }

  // Mismo origen: red primero, cache de respaldo
  if(url.origin === self.location.origin){
    e.respondWith(networkFirst(req, CACHE_APP));
  }
});
