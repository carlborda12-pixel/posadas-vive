/* 48h Posadas · importador de la planilla (en el navegador)
   ------------------------------------------------------------------
   Es la misma lógica que herramientas/importar_catalogo.py, para que
   Turismo suba la planilla desde cargar.html sin instalar nada.
   Si se cambia una regla acá, cambiarla también allá (y al revés).

   Incluye un lector de .xlsx propio (un .xlsx es un zip con XML): no
   depende de ninguna librería de afuera.

   Uso:
     const hojas = await Importador.leerXlsx(arrayBuffer);   // { lugares: [[...]], agenda: [[...]] }
     const r = Importador.armar(hojas.lugares, hojas.agenda, 'AAAA-MM-DD');
     // r = { lugares, pasadas, errores, avisos, resumen }
*/
(function(global){
'use strict';

// ---------------------------------------------------------------------
// Categorías (iguales a CATEGORIAS de index.html y del importador)
// ---------------------------------------------------------------------
const CATEGORIAS = [
  ['cultura',     'Cultura',       ['museos', 'salas']],
  ['naturaleza',  'Naturaleza',    []],
  ['paseos',      'Paseo guiado',  []],
  ['nautico',     'Náutico',       []],
  ['gastronomia', 'Gastronomía',   ['pescados', 'parrillas', 'vinos', 'internacional', 'cafes']],
  ['nocturna',    'Vida nocturna', ['bares', 'bowling']],
  ['ninos',       'Niños',         []],
  ['excursiones', 'Excursiones',   []],
];
const SUBCATEGORIAS = {
  museos: 'Museos', salas: 'Salas culturales',
  pescados: 'Pescados', parrillas: 'Galetos y parrillas', vinos: 'Vinos', internacional: 'Internacional', cafes: 'Café y té',
  bares: 'Bares', bowling: 'Bowling',
};
const SINONIMOS_SUB = {
  'museo': 'museos', 'museos': 'museos',
  'sala': 'salas', 'salas': 'salas', 'sala cultural': 'salas', 'salas culturales': 'salas',
  'pescado': 'pescados', 'pescados': 'pescados',
  'parrilla': 'parrillas', 'parrillas': 'parrillas', 'galeto': 'parrillas', 'galetos': 'parrillas',
  'galetos y parrillas': 'parrillas', 'galetos parrillas': 'parrillas',
  'vino': 'vinos', 'vinos': 'vinos',
  'internacional': 'internacional',
  'cafe': 'cafes', 'cafes': 'cafes', 'cafe y te': 'cafes', 'cafes y te': 'cafes', 'cafe te': 'cafes',
  'cafeteria': 'cafes', 'cafeterias': 'cafes', 'te': 'cafes', 'casa de te': 'cafes', 'casas de te': 'cafes',
  'bar': 'bares', 'bares': 'bares',
  'bowling': 'bowling',
};
const TIPOS = { lugar: 'lugar', actividad: 'evento', evento: 'evento', excursion: 'excursion', paquete: 'excursion' };
const LAT_MIN = -28.6, LAT_MAX = -25.4, LNG_MIN = -56.6, LNG_MAX = -53.5;

// ---------------------------------------------------------------------
// Normalización
// ---------------------------------------------------------------------
// Un valor de celda puede venir como texto, número, booleano o { fecha: 'AAAA-MM-DD', hora: 'HH:MM' }
const esFecha = v => v && typeof v === 'object' && 'serial' in v;

function plano(s){
  const t = String(s == null ? '' : (esFecha(s) ? texto(s) : s)).normalize('NFKD').replace(/[^\x00-\x7f]/g, '');
  return t.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
}

function texto(v){
  if(v == null) return '';
  if(esFecha(v)) return v.fecha;
  if(typeof v === 'number' && Number.isInteger(v)) v = String(v);
  return String(v).replace(/[\r\n]/g, ' ').replace(/\s+/g, ' ').trim();
}

function slug(s, largo = 40){
  s = plano(s).replace(/ /g, '-');
  return s.slice(0, largo).replace(/^-+|-+$/g, '') || 'lugar';
}

const esSi = v => ['x', 'si', 's', '1', 'true', 'verdadero', 'yes'].includes(plano(v)) || ['✓', '✔', '✅'].includes(texto(v));

function telefono(v){
  const t = texto(v).replace(/^[ /]+|[ /]+$/g, '');
  if(!t) return ['', null];
  const primero = t.slice(1).includes('/') ? t.split(/\s\/\s?|\s?\/\s/)[0] : t.replace(/^\/+/, '');
  let d = primero.replace(/\D/g, '');
  let movil = false;
  if(d.startsWith('54')){ d = d.slice(2); if(d.startsWith('9')){ movil = true; d = d.slice(1); } }
  if(d.startsWith('0')) d = d.slice(1);
  for(const la of [4, 3, 2]){
    const area = d.slice(0, la), resto = d.slice(la);
    if(resto.startsWith('15') && (area + resto).length === 12){ d = area + resto.slice(2); movil = true; break; }
  }
  for(const la of [4, 3, 2]){
    const area = d.slice(0, la);
    if(d.length === 10 + la && d.slice(la).startsWith(area)){ d = d.slice(la); break; }
  }
  if(d.length !== 10) return [t.replace(/^[/ ]+/, '').trim(), null];
  const la = d.startsWith('11') ? 2 : d.startsWith('376') ? 3 : 4;
  const area = d.slice(0, la), num = d.slice(la), corte = num.length - 4;
  const lindo = `+54 ${movil ? '9 ' : ''}${area} ${num.slice(0, corte)}-${num.slice(corte)}`;
  return [lindo, (movil ? '549' : '54') + d];
}

function instagram(v){
  const t = texto(v);
  if(!t) return '';
  const m = t.match(/instagram\.com\/([A-Za-z0-9._]{1,30})/) || t.match(/^@?([A-Za-z0-9._]{1,30})$/);
  return m ? `https://www.instagram.com/${m[1]}/` : '';
}

function url(v){
  const t = texto(v);
  return /^https?:\/\/\S+$/.test(t) ? t : '';
}

const VIDEO_FORMATOS = [
  /^https:\/\/(?:www\.|m\.)?youtube\.com\/(?:watch\?(?:[^#]*&)?v=|embed\/|shorts\/|live\/)[A-Za-z0-9_-]{11}/i,
  /^https:\/\/youtu\.be\/[A-Za-z0-9_-]{11}/i,
  /^https:\/\/(?:www\.)?instagram\.com\/(?:[A-Za-z0-9._]{1,30}\/)?(?:reels?|p|tv)\/[A-Za-z0-9_-]{5,40}/i,
  /^https:\/\/(?:www\.)?tiktok\.com\/@[A-Za-z0-9._-]{1,40}\/video\/\d{8,25}/i,
  /^https:\/\/(?:www\.|player\.)?vimeo\.com\/(?:video\/)?\d{6,12}/i,
  /^https:\/\/drive\.google\.com\/(?:file\/d\/|open\?id=)[A-Za-z0-9_-]{10,80}/i,
  /^https:\/\/[^\s"'<>()\\]+\.(?:mp4|webm)(?:\?[^\s"'<>()\\]*)?$/i,
];
function video(v){
  let t = texto(v);
  if(t.startsWith('http://')) t = 'https://' + t.slice(7);
  return VIDEO_FORMATOS.some(f => f.test(t)) ? t : '';
}

const r6 = x => Number(x.toFixed(6));   // igual que round(x, 6) de Python
function coordenadas(v, link){
  const t = texto(v);
  if(t){
    let par = null;
    const m = [...t.matchAll(/(\d+)°\s*(\d+)'\s*([\d.]+)"?\s*([NSEWO])/g)];
    if(m.length === 2){
      const g = x => { const val = +x[1] + +x[2] / 60 + parseFloat(x[3]) / 3600; return 'SWO'.includes(x[4]) ? -val : val; };
      par = [g(m[0]), g(m[1])];
    } else {
      const n = t.replace(/, /g, ' ').replace(/;/g, ' ').match(/-?\d+(?:[.,]\d+)?/g);
      if(n && n.length >= 2) par = [parseFloat(n[0].replace(',', '.')), parseFloat(n[1].replace(',', '.'))];
    }
    if(par) return [r6(par[0]), r6(par[1])];
  }
  const m = (link || '').match(/!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)/) || (link || '').match(/@(-?\d+\.\d+),(-?\d+\.\d+)/);
  return m ? [r6(parseFloat(m[1])), r6(parseFloat(m[2]))] : null;
}
const coordsOk = c => !!c && c[0] >= LAT_MIN && c[0] <= LAT_MAX && c[1] >= LNG_MIN && c[1] <= LNG_MAX;

// ---------------------------------------------------------------------
// Horarios "L a V 8-12.30 / 17-20 S 9-13" → "Lun a Vie 8 a 12:30 y 17 a 20 hs · Sáb 9 a 13 hs"
// ---------------------------------------------------------------------
const DIAS = { l: 0, lu: 0, lun: 0, lunes: 0, m: 1, ma: 1, mar: 1, martes: 1,
  mi: 2, mie: 2, miercoles: 2, x: 2, j: 3, ju: 3, jue: 3, jueves: 3,
  v: 4, vi: 4, vie: 4, viernes: 4, s: 5, sa: 5, sab: 5, sabado: 5, sabados: 5,
  d: 6, do: 6, dom: 6, domingo: 6, domingos: 6 };
const DIAS_ES = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
const DIAS_PT = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
const DIA = '(lunes|martes|miercoles|jueves|viernes|sabados?|domingos?|lun|mar|mie|jue|vie|sab|dom|mi|l|m|j|v|s|d|x)\\b';
const HORA = '(\\d{1,2})(?:[.:](\\d{2}))?';
const RANGO = HORA + '\\s*(?:-|a|al)\\s*' + HORA;

function horarioLegible(t){
  let s = t.normalize('NFKD').replace(/[^\x00-\x7f]/g, '').toLowerCase();
  s = s.replace(/([a-z])(\d)/g, '$1 $2');
  const grupos = [];
  let i = 0;
  const patDias = new RegExp('\\s*' + DIA + '(?:\\s*(a|al|-|y)\\s*' + DIA + ')?', 'y');
  const patHora = new RegExp('\\s*/?\\s*' + RANGO, 'y');
  while(i < s.length){
    if(!s.slice(i).replace(/[ /,·;]/g, '')) break;
    patDias.lastIndex = i;
    const m = patDias.exec(s);
    if(!m) return null;
    const d1 = DIAS[m[1]], sep = m[2], d2 = m[3] ? DIAS[m[3]] : null;
    i = patDias.lastIndex;
    const rangos = [];
    for(;;){
      patHora.lastIndex = i;
      const r = patHora.exec(s);
      if(!r) break;
      const h1 = +r[1], m1 = +(r[2] || 0), h2 = +r[3], m2 = +(r[4] || 0);
      if(h1 > 24 || h2 > 24 || m1 > 59 || m2 > 59) return null;
      rangos.push([h1, m1, h2, m2]); i = patHora.lastIndex;
    }
    if(!rangos.length) return null;
    grupos.push([d1, sep, d2, rangos]);
    while(i < s.length && ' /,;·'.includes(s[i])) i++;
  }
  if(!grupos.length) return null;
  const h = (hh, mm) => (hh === 0 || hh === 24) && mm === 0 ? '00' : `${hh}` + (mm ? `:${String(mm).padStart(2, '0')}` : '');
  const armarTxt = (nombres, y, a, sufijo) => grupos.map(([d1, sep, d2, rangos]) => {
    const dias = d2 === null ? nombres[d1] : sep === 'y' ? `${nombres[d1]} ${y} ${nombres[d2]}` : `${nombres[d1]} a ${nombres[d2]}`;
    const horas = rangos.map(([a1, b1, a2, b2]) => `${h(a1, b1)} ${a} ${h(a2, b2)}`).join(` ${y} `);
    return `${dias} ${horas} ${sufijo}`;
  }).join(' · ');
  return [armarTxt(DIAS_ES, 'y', 'a', 'hs'), armarTxt(DIAS_PT, 'e', 'às', 'h')];
}

// ---------------------------------------------------------------------
// Fechas, horas, números
// ---------------------------------------------------------------------
const ISO = /^(\d{4})-(\d{2})-(\d{2})$/;
function fechaValida(y, m, d){
  const f = new Date(Date.UTC(y, m - 1, d));
  return f.getUTCFullYear() === y && f.getUTCMonth() === m - 1 && f.getUTCDate() === d
    ? `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}` : null;
}
function fecha(v){
  if(esFecha(v)) return v.fecha;
  if(typeof v === 'number' && v > 20000 && v < 80000) return serialAFecha(v).fecha;
  const t = texto(v);
  let m;
  if((m = t.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/))) return fechaValida(+m[3], +m[2], +m[1]);
  if((m = t.match(/^(\d{1,2})\/(\d{1,2})\/(\d{2})$/))) return fechaValida(2000 + +m[3] - (+m[3] >= 69 ? 100 : 0), +m[2], +m[1]);
  if((m = t.match(ISO))) return fechaValida(+m[1], +m[2], +m[3]);
  if((m = t.match(/^(\d{1,2})-(\d{1,2})-(\d{4})$/))) return fechaValida(+m[3], +m[2], +m[1]);
  return null;
}
function hora(v){
  if(esFecha(v) && v.hora) return v.hora;
  if(typeof v === 'number' && v >= 0 && v < 1){
    const m = Math.round(v * 24 * 60);
    return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
  }
  const t = plano(v);
  const m = t.match(/^(\d{1,2})(?: (\d{2}))?(?: hs?)?$/);
  if(m && +m[1] < 24) return `${String(+m[1]).padStart(2, '0')}:${m[2] || '00'}`;
  return null;
}
function entero(v){
  const n = parseInt(parseFloat(texto(v).replace(',', '.')), 10);
  return Number.isFinite(n) && n > 0 ? n : null;
}
function precioNumero(t){
  const n = (t || '').match(/\d[\d.]*/g);
  if(n && n.length === 1){ const x = parseInt(n[0].replace(/\./g, ''), 10); return Number.isFinite(x) ? x : null; }
  return null;
}

// ---------------------------------------------------------------------
// Lectura de tablas
// ---------------------------------------------------------------------
const COLUMNAS_LUGARES = {
  id: ['id'], publicar: ['publicar'], tipo: ['tipo'], nombre: ['nombre'],
  subcategorias: ['subcategorias', 'subcategoria'], direccion: ['direccion'],
  coordenadas: ['coordenadas', 'coordenadas lat lng'],
  maps: ['link google maps', 'google maps', 'link de google maps', 'ubicacion'],
  telefono: ['telefono', 'contacto'], whatsapp: ['whatsapp', 'tiene whatsapp'],
  instagram: ['instagram', 'ig'], web: ['web mas info', 'web', 'mas info', 'info'],
  horario: ['horario', 'horarios'], precio: ['precio'], inscripcion: ['inscripcion'], cupo: ['cupo'],
  organiza: ['organiza', 'agencia'], descripcion: ['descripcion'], recomendacion: ['recomendacion'],
  foto: ['foto link', 'foto'], video: ['video link', 'video'], destacado: ['destacado', 'evento destacado'],
  nombre_pt: ['nombre portugues', 'nombre pt'], descripcion_pt: ['descripcion portugues', 'descripcion pt'],
};
const COLUMNAS_AGENDA = {
  fecha: ['fecha'], hora: ['hora', 'horario'], id: ['id', 'id actividad o lugar', 'id actividad'],
  evento: ['nombre del evento', 'nombre del evento solo eventos puntuales', 'evento'],
  estado: ['estado'], encuentro: ['punto de encuentro'], cupo: ['cupo'],
};

function leerTabla(filas){
  for(let i = 0; i < Math.min(10, filas.length); i++){
    const claves = (filas[i] || []).map(plano);
    if(claves.includes('nombre') || claves.includes('fecha')){
      const out = [];
      for(const g of filas.slice(i + 1)){
        if(!g || !g.some(x => texto(x))) continue;
        const o = {};
        for(let j = 0; j < Math.min(claves.length, g.length); j++) if(claves[j]) o[claves[j]] = g[j];
        out.push(o);
      }
      return out;
    }
  }
  return [];
}
function tomar(fila, alias){
  for(const a of alias) if(a in fila && texto(fila[a]) !== '') return fila[a];
  return null;
}

// ---------------------------------------------------------------------
// Armado del catálogo
// ---------------------------------------------------------------------
function armar(lugaresFilas, agendaFilas, hoy){
  const lugaresRaw = leerTabla(lugaresFilas || []), agendaRaw = leerTabla(agendaFilas || []);
  const errores = [], avisos = [];
  const colCat = {};
  CATEGORIAS.forEach(([cid, col]) => { colCat[plano(col)] = cid; });
  Object.assign(colCat, { 'paseos guiados': 'paseos', 'pg': 'paseos', 'paquetes': 'excursiones', 'ninos': 'ninos' });

  const lugares = [], ids = {};
  lugaresRaw.forEach((f, k) => {
    const n = k + 2;
    const nombre = texto(tomar(f, COLUMNAS_LUGARES.nombre));
    if(!nombre) return;
    const fila = `Lugares fila ${n} (${nombre})`;
    const pub = tomar(f, COLUMNAS_LUGARES.publicar);
    if(pub !== null && !esSi(pub)) return;

    let lid = texto(tomar(f, COLUMNAS_LUGARES.id)).toLowerCase() || slug(nombre);
    if(!/^[a-z0-9_-]{1,40}$/.test(lid)){
      avisos.push(`${fila}: el ID "${lid}" tiene caracteres no válidos; se usa "${slug(lid)}"`);
      lid = slug(lid);
    }
    if(lid in ids){ errores.push(`${fila}: el ID "${lid}" ya se usa en la fila ${ids[lid]}`); return; }
    ids[lid] = n;

    const tipoTxt = plano(tomar(f, COLUMNAS_LUGARES.tipo));
    const tipo = TIPOS[tipoTxt] || 'lugar';
    if(tipoTxt && !(tipoTxt in TIPOS)) avisos.push(`${fila}: tipo "${tipoTxt}" no reconocido; se toma como Lugar`);

    let cats = Object.entries(colCat).filter(([clave]) => clave in f && esSi(f[clave])).map(([, cid]) => cid);
    cats = CATEGORIAS.map(c => c[0]).filter(cid => cats.includes(cid));
    if(!cats.length) avisos.push(`${fila}: no tiene ninguna categoría marcada; no va a aparecer en los filtros`);

    const subs = [];
    texto(tomar(f, COLUMNAS_LUGARES.subcategorias)).split(/[,;/]/).forEach(s => {
      if(!plano(s)) return;
      const sid = SINONIMOS_SUB[plano(s)];
      if(!sid){ avisos.push(`${fila}: subcategoría "${s.trim()}" no reconocida (válidas: ${Object.values(SUBCATEGORIAS).join(', ')})`); return; }
      const madre = CATEGORIAS.find(c => c[2].includes(sid))[0];
      if(!cats.includes(madre)) cats.push(madre);
      if(!subs.includes(sid)) subs.push(sid);
    });

    const linkMaps = url(tomar(f, COLUMNAS_LUGARES.maps));
    let c = coordenadas(tomar(f, COLUMNAS_LUGARES.coordenadas), linkMaps);
    if(c && !coordsOk(c)){
      avisos.push(`${fila}: coordenadas [${c.join(', ')}] fuera de Misiones (¿lat y lng invertidas o sin el signo menos?); se ignoran`);
      c = null;
    }

    const [telTxt, tel] = telefono(tomar(f, COLUMNAS_LUGARES.telefono));
    if(telTxt && !tel) avisos.push(`${fila}: no se entiende el teléfono "${telTxt}"; se muestra como texto`);
    const wappRaw = tomar(f, COLUMNAS_LUGARES.whatsapp);
    let wapp = null;
    if(wappRaw !== null){
      if(esSi(wappRaw)){
        wapp = tel && tel.startsWith('549') ? tel : null;
        if(!wapp) avisos.push(`${fila}: marcado con WhatsApp pero el teléfono no es un celular`);
      } else if(!['no', 'n'].includes(plano(wappRaw))){
        wapp = telefono(wappRaw)[1];
      }
    }

    const igRaw = tomar(f, COLUMNAS_LUGARES.instagram);
    const ig = instagram(igRaw);
    if(igRaw !== null && !ig) avisos.push(`${fila}: Instagram "${texto(igRaw)}" no reconocido`);

    const insc = plano(tomar(f, COLUMNAS_LUGARES.inscripcion));
    const ticket = insc.startsWith('gratis') ? 'free_reg' : insc.startsWith('pag') ? 'paid' : null;
    const precio = texto(tomar(f, COLUMNAS_LUGARES.precio));
    const horario = texto(tomar(f, COLUMNAS_LUGARES.horario));

    const fotoRaw = tomar(f, COLUMNAS_LUGARES.foto);
    const foto = url(fotoRaw);
    if(fotoRaw !== null && !foto) avisos.push(`${fila}: la foto tiene que ser un enlace que empiece con http`);

    const videoRaw = tomar(f, COLUMNAS_LUGARES.video);
    const vid = video(videoRaw);
    if(videoRaw !== null && !vid) avisos.push(`${fila}: video "${texto(videoRaw)}" no reconocido (usar un enlace de YouTube, Instagram, TikTok, Vimeo, Google Drive o un .mp4)`);
    let destacado = esSi(tomar(f, COLUMNAS_LUGARES.destacado));
    if(destacado && tipo !== 'evento'){
      avisos.push(`${fila}: "Destacado" solo se usa en actividades (los lugares no tienen fecha); se ignora`);
      destacado = false;
    }

    const L = {
      id: lid, type: tipo, name: nombre,
      addr: texto(tomar(f, COLUMNAS_LUGARES.direccion)),
      coords: c, cats, subs,
      tel: telTxt || null, telLink: tel, whatsapp: wapp, ig: ig || null,
      web: url(tomar(f, COLUMNAS_LUGARES.web)) || null, maps: linkMaps || null,
      horario: horario || null, price: precio || null,
      ticketType: ticket, ticketPrice: ticket === 'paid' ? precioNumero(precio) : null,
      cupoTotal: ticket === 'free_reg' ? entero(tomar(f, COLUMNAS_LUGARES.cupo)) : null,
      org: texto(tomar(f, COLUMNAS_LUGARES.organiza)) || null,
      story: texto(tomar(f, COLUMNAS_LUGARES.descripcion)) || null,
      fact: texto(tomar(f, COLUMNAS_LUGARES.recomendacion)) || null,
      img: foto || null,
      video: vid || null,
      destacado: destacado ? true : null,
    };
    const pt = {};
    const nPt = texto(tomar(f, COLUMNAS_LUGARES.nombre_pt)), dPt = texto(tomar(f, COLUMNAS_LUGARES.descripcion_pt));
    if(nPt) pt.name = nPt;
    if(dPt) pt.story = dPt;
    if(Object.keys(pt).length) L.pt = pt;
    if(horario && tipo !== 'evento'){
      const leg = horarioLegible(horario);
      L.schedule = { kind: 'siempre', label: leg ? leg[0] : horario };
      if(leg) (L.pt = L.pt || {}).label = leg[1];
    }
    if(tipo === 'excursion' && !L.schedule) L.schedule = { kind: 'siempre', label: 'Consultar fechas' };
    lugares.push(L);
  });

  const porId = {};
  lugares.forEach(L => { porId[L.id] = L; });

  // ---------- Agenda ----------
  let pasadas = 0;
  const puntuales = [];
  agendaRaw.forEach((f, k) => {
    const fila = `Agenda fila ${k + 2}`;
    const fe = fecha(tomar(f, COLUMNAS_AGENDA.fecha));
    const rid = texto(tomar(f, COLUMNAS_AGENDA.id)).toLowerCase();
    if(!fe && !rid) return;
    if(!fe){ avisos.push(`${fila}: fecha "${texto(tomar(f, COLUMNAS_AGENDA.fecha))}" no válida (usar dd/mm/aaaa)`); return; }
    if(fe < hoy){ pasadas++; return; }
    const base = porId[rid];
    if(!base){ avisos.push(`${fila}: el ID "${rid}" no está en la hoja Lugares (o no se publica)`); return; }
    const hrRaw = tomar(f, COLUMNAS_AGENDA.hora);
    const hr = hora(hrRaw);
    if(hrRaw !== null && !hr && !plano(hrRaw).includes('confirmar')) avisos.push(`${fila}: hora "${texto(hrRaw)}" no válida (usar 17:00)`);
    const estado = plano(tomar(f, COLUMNAS_AGENDA.estado)).includes('confirmar') || !hr ? 'a_confirmar' : 'confirmado';
    const item = { fecha: fe, hora: hr, estado };
    const enc = texto(tomar(f, COLUMNAS_AGENDA.encuentro));
    if(enc) item.encuentro = enc;
    const cupo = entero(tomar(f, COLUMNAS_AGENDA.cupo));
    if(cupo) item.cupo = cupo;

    const evento = texto(tomar(f, COLUMNAS_AGENDA.evento));
    if(evento){
      let pid = `${slug(evento, 24)}-${fe.slice(5, 7)}${fe.slice(8, 10)}`;
      while(pid in porId) pid += 'b';
      const E = {};
      ['addr', 'coords', 'cats', 'subs', 'tel', 'telLink', 'whatsapp', 'ig', 'maps', 'img'].forEach(x => { if(x in base) E[x] = base[x]; });
      Object.assign(E, { id: pid, type: 'evento', name: evento, lugar: base.id, schedule: { kind: 'fechas', fechas: [item] } });
      if(item.encuentro) E.addr = item.encuentro;
      porId[pid] = E;
      puntuales.push(E);
    } else {
      if(base.type !== 'evento'){
        avisos.push(`${fila}: "${base.name}" es un ${base.type}, no una actividad; para un evento en ese lugar completar "Nombre del evento"`);
        return;
      }
      if(!base.schedule || base.schedule.kind !== 'fechas') base.schedule = { kind: 'fechas', fechas: [] };
      base.schedule.fechas.push(item);
    }
  });

  lugares.forEach(L => {
    const sc = L.schedule;
    if(sc && sc.kind === 'fechas') sc.fechas.sort((a, b) => a.fecha < b.fecha ? -1 : a.fecha > b.fecha ? 1 : (a.hora || '99') < (b.hora || '99') ? -1 : (a.hora || '99') > (b.hora || '99') ? 1 : 0);
  });

  const vacio = v => v === null || v === undefined || v === '' || (Array.isArray(v) && !v.length);
  const limpio = lugares.concat(puntuales).map(L => {
    const o = {};
    Object.keys(L).forEach(k => { if(!vacio(L[k])) o[k] = L[k]; });
    return o;
  });

  const porCat = {};
  CATEGORIAS.forEach(([cid]) => { porCat[cid] = limpio.filter(L => (L.cats || []).includes(cid)).length; });
  const resumen = {
    lugares: limpio.length,
    fechas: limpio.reduce((a, L) => a + ((L.schedule && L.schedule.fechas) || []).length, 0),
    pasadas,
    porCategoria: porCat,
    sinCoordenadas: limpio.filter(L => !L.coords && L.type !== 'excursion').map(L => L.name),
  };
  return { lugares: limpio, pasadas, errores, avisos, resumen };
}

// ---------------------------------------------------------------------
// Lector de .xlsx (zip + XML), sin librerías
// ---------------------------------------------------------------------
async function inflar(datos){
  const ds = new DecompressionStream('deflate-raw');
  const buf = await new Response(new Blob([datos]).stream().pipeThrough(ds)).arrayBuffer();
  return new Uint8Array(buf);
}

async function abrirZip(buffer){
  const b = new Uint8Array(buffer), dv = new DataView(buffer);
  if(b.length < 22 || dv.getUint32(0, true) !== 0x04034b50) throw new Error('El archivo no es un Excel (.xlsx).');
  let fin = -1;
  for(let i = b.length - 22; i >= Math.max(0, b.length - 66000); i--){ if(dv.getUint32(i, true) === 0x06054b50){ fin = i; break; } }
  if(fin < 0) throw new Error('El archivo .xlsx está dañado.');
  const total = dv.getUint16(fin + 10, true);
  let p = dv.getUint32(fin + 16, true);
  const archivos = {};
  const dec = new TextDecoder();
  for(let k = 0; k < total; k++){
    if(dv.getUint32(p, true) !== 0x02014b50) throw new Error('El archivo .xlsx está dañado.');
    const metodo = dv.getUint16(p + 10, true), comp = dv.getUint32(p + 20, true), real = dv.getUint32(p + 24, true);
    const ln = dv.getUint16(p + 28, true), le = dv.getUint16(p + 30, true), lc = dv.getUint16(p + 32, true);
    const local = dv.getUint32(p + 42, true);
    const nombre = dec.decode(b.subarray(p + 46, p + 46 + ln));
    archivos[nombre] = { metodo, comp, real, local };
    p += 46 + ln + le + lc;
  }
  return async nombre => {
    const a = archivos[nombre];
    if(!a) return null;
    if(a.real > 50e6) throw new Error('El archivo es demasiado grande.');
    const ini = a.local + 30 + dv.getUint16(a.local + 26, true) + dv.getUint16(a.local + 28, true);
    const datos = b.subarray(ini, ini + a.comp);
    const crudo = a.metodo === 0 ? datos : a.metodo === 8 ? await inflar(datos) : null;
    if(!crudo) throw new Error('El .xlsx usa una compresión que no se puede leer.');
    return dec.decode(crudo);
  };
}

const ENT = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" };
const desXml = s => s.replace(/&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot|apos);/gi, (_, e) =>
  e[0] === '#' ? String.fromCodePoint(e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10)) : ENT[e.toLowerCase()]);
const textoDe = xml => [...xml.matchAll(/<t(?:\s[^>]*)?>([\s\S]*?)<\/t>/g)].map(m => desXml(m[1])).join('');
const attr = (tag, nombre) => { const m = tag.match(new RegExp('\\s' + nombre + '="([^"]*)"')); return m ? desXml(m[1]) : null; };

function serialAFecha(n){
  const ms = Math.round((n - 25569) * 86400000);
  const d = new Date(ms);
  const fecha = d.toISOString().slice(0, 10);
  const minutos = Math.round((n % 1) * 1440);
  return { serial: n, fecha, hora: minutos ? `${String(Math.floor(minutos / 60) % 24).padStart(2, '0')}:${String(minutos % 60).padStart(2, '0')}` : null };
}

function colIndice(ref){
  const m = ref.match(/^([A-Z]+)/);
  let n = 0;
  for(const ch of m[1]) n = n * 26 + (ch.charCodeAt(0) - 64);
  return n - 1;
}

async function leerXlsx(buffer){
  const leer = await abrirZip(buffer);
  const libro = await leer('xl/workbook.xml');
  if(!libro) throw new Error('El archivo no es un Excel (.xlsx).');
  const rels = (await leer('xl/_rels/workbook.xml.rels')) || '';
  const destinos = {};
  for(const m of rels.matchAll(/<Relationship\b[^>]*>/g)) destinos[attr(m[0], 'Id')] = attr(m[0], 'Target');
  const compartidos = [];
  const ss = await leer('xl/sharedStrings.xml');
  if(ss) for(const m of ss.matchAll(/<si>([\s\S]*?)<\/si>/g)) compartidos.push(textoDe(m[1]));
  // estilos de fecha: los números con formato de fecha se convierten
  const estilos = (await leer('xl/styles.xml')) || '';
  const fmtFecha = new Set([14, 15, 16, 17, 22, 27, 30, 36, 45, 46, 47, 50, 57]);
  for(const m of estilos.matchAll(/<numFmt\b[^>]*>/g)){
    const codigo = (attr(m[0], 'formatCode') || '').replace(/"[^"]*"|\[[^\]]*\]/g, '');
    if(/[dy]/i.test(codigo) || /h/i.test(codigo)) fmtFecha.add(+attr(m[0], 'numFmtId'));
  }
  const xfs = [];
  const cellXfs = estilos.match(/<cellXfs\b[^>]*>([\s\S]*?)<\/cellXfs>/);
  if(cellXfs) for(const m of cellXfs[1].matchAll(/<xf\b[^>]*>/g)) xfs.push(fmtFecha.has(+(attr(m[0], 'numFmtId') || 0)));

  const hojas = {};
  for(const m of libro.matchAll(/<sheet\b[^>]*>/g)){
    const nombre = attr(m[0], 'name'), rid = attr(m[0], 'r:id');
    let destino = destinos[rid] || '';
    destino = destino.startsWith('/') ? destino.slice(1) : 'xl/' + destino.replace(/^\.\//, '');
    const xml = await leer(destino);
    if(!xml) continue;
    const filas = [];
    for(const fm of xml.matchAll(/<row\b[^>]*?(?:\/>|>([\s\S]*?)<\/row>)/g)){
      const r = +(attr(fm[0].slice(0, fm[0].indexOf('>') + 1), 'r') || filas.length + 1);
      const fila = [];
      for(const cm of (fm[1] || '').matchAll(/<c\b([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g)){
        const tag = '<c ' + cm[1] + '>', cuerpo = cm[2] || '';
        const ref = attr(tag, 'r'); if(!ref) continue;
        const t = attr(tag, 't'), s = +(attr(tag, 's') || 0);
        const v = (cuerpo.match(/<v>([\s\S]*?)<\/v>/) || [])[1];
        let val = null;
        if(t === 's') val = v != null ? compartidos[+v] : null;
        else if(t === 'inlineStr') val = textoDe(cuerpo);
        else if(t === 'str') val = v != null ? desXml(v) : null;
        else if(t === 'b') val = v === '1';
        else if(t === 'e') val = null;
        else if(v != null){
          const n = parseFloat(v);
          val = Number.isFinite(n) ? (xfs[s] ? (n < 1 ? n : serialAFecha(n)) : n) : desXml(v);
        }
        fila[colIndice(ref)] = val;
      }
      filas[r - 1] = Array.from(fila, x => x === undefined ? null : x);
    }
    hojas[plano(nombre)] = Array.from(filas, x => x || []);
  }
  if(!hojas.lugares) throw new Error('La planilla no tiene una hoja "Lugares" (tiene: ' + Object.keys(hojas).join(', ') + ').');
  return { lugares: hojas.lugares, agenda: hojas.agenda || [], nombres: Object.keys(hojas) };
}

global.Importador = { leerXlsx, armar, CATEGORIAS, SUBCATEGORIAS, _prueba: { telefono, coordenadas, horarioLegible, fecha, hora, slug, plano } };
})(typeof window !== 'undefined' ? window : globalThis);
