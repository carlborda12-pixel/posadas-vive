// =====================================================================
// 48 HS · función "avisos" (Supabase Edge Function)
//
// La llama cron.sql una vez por hora. Según la hora de Posadas:
//   · lista de espera  → en cada corrida: si se liberó lugar, le escribe
//                        al primero de la lista con un enlace para reservar
//   · recordatorios    → a las 10: a quien tiene actividad mañana
//   · reporte mensual  → el día 1 a las 9: resumen del mes anterior
//
// Para probar a mano sin mandar nada:
//   curl -X POST "https://<proyecto>.supabase.co/functions/v1/avisos?tarea=lista&prueba=1" \
//        -H "Authorization: Bearer <AVISOS_SECRET>"
//   tarea = lista | recordatorios | reporte | todas
//
// Secretos (Supabase > Edge Functions > Secrets): ver LEEME.md
// =====================================================================

const env = (k: string, def = '') => (Deno.env.get(k) ?? def).trim();

const SB_URL      = env('SUPABASE_URL');
const SB_KEY      = env('SUPABASE_SERVICE_ROLE_KEY') || env('SERVICE_KEY');
const SECRETO     = env('AVISOS_SECRET');
const RESEND_KEY  = env('RESEND_API_KEY');
const RESEND_URL  = env('RESEND_URL', 'https://api.resend.com/emails');
const REMITENTE   = env('REMITENTE', '48 HS <avisos@example.com>');
const APP_URL     = env('APP_URL').replace(/\/?$/, '/');
const REPORTE_PARA  = env('REPORTE_DESTINATARIOS').split(',').map((s) => s.trim()).filter(Boolean);
const REPORTE_CLAVE = env('REPORTE_CLAVE');
const TABLA_INSCRIPCIONES = env('INSCRIPCIONES_TABLA', 'inscripciones');
const TZ = 'America/Argentina/Buenos_Aires';

// ---------------------------------------------------------------------
// Utilidades
// ---------------------------------------------------------------------
type Fila = Record<string, unknown>;

const esc = (s: unknown) => String(s ?? '').replace(/[&<>"']/g,
  (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!));

// Comparación en tiempo constante, para el secreto
function igual(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  let d = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) d |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return d === 0;
}

// Fecha y hora de Posadas
function ahoraPosadas() {
  const p: Record<string, string> = {};
  new Intl.DateTimeFormat('en-CA', {
    timeZone: TZ, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit',
  }).formatToParts(new Date()).forEach((x) => (p[x.type] = x.value));
  return { fecha: `${p.year}-${p.month}-${p.day}`, hora: Number(p.hour) % 24, dia: Number(p.day) };
}

const DIAS = {
  es: ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado'],
  pt: ['domingo', 'segunda-feira', 'terça-feira', 'quarta-feira', 'quinta-feira', 'sexta-feira', 'sábado'],
};
const MESES = {
  es: ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'],
  pt: ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'],
};
function fechaLarga(iso: string, hora: string | null, lang: 'es' | 'pt' = 'es') {
  const [y, m, d] = iso.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  const dia = DIAS[lang][dt.getUTCDay()];
  const h = hora ? (lang === 'pt' ? ` · ${hora.slice(0, 5).replace(/:00$/, '')}h` : ` · ${hora.slice(0, 5).replace(/:00$/, '')} hs`) : '';
  return `${dia[0].toUpperCase()}${dia.slice(1)} ${d} de ${MESES[lang][m - 1]}${h}`;
}

// PostgREST con la clave de servicio (no pasa por RLS)
async function rest(ruta: string, init: RequestInit = {}) {
  const headers: Record<string, string> = {
    apikey: SB_KEY, 'Content-Type': 'application/json', ...(init.headers as Record<string, string> ?? {}),
  };
  // Las claves nuevas (sb_secret_...) no son JWT: van solo en "apikey"
  if (SB_KEY.startsWith('eyJ')) headers.Authorization = `Bearer ${SB_KEY}`;
  const r = await fetch(`${SB_URL}/rest/v1/${ruta}`, { ...init, headers });
  const txt = await r.text();
  if (!r.ok) {
    const e = new Error(`PostgREST ${r.status}: ${txt.slice(0, 300)}`) as Error & { status?: number };
    e.status = r.status;
    throw e;
  }
  return txt ? JSON.parse(txt) : null;
}

type Correo = { para: string[]; asunto: string; html: string };

async function enviar(c: Correo, prueba: boolean, enviados: Correo[]) {
  enviados.push(c);
  if (prueba) return;
  if (!RESEND_KEY) throw new Error('Falta RESEND_API_KEY');
  const r = await fetch(RESEND_URL, {
    method: 'POST',
    headers: { Authorization: `Bearer ${RESEND_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: REMITENTE, to: c.para, subject: c.asunto, html: c.html }),
  });
  if (!r.ok) throw new Error(`Resend ${r.status}: ${(await r.text()).slice(0, 300)}`);
}

// Plantilla común: sobria, se lee bien en cualquier cliente de correo
function plantilla(titulo: string, cuerpo: string, pie: string) {
  return `<!doctype html><html><body style="margin:0;background:#f4efe8;padding:24px 12px;font-family:Arial,Helvetica,sans-serif;color:#2a1f17">
  <table role="presentation" width="100%" style="max-width:520px;margin:0 auto;background:#ffffff;border-radius:14px;overflow:hidden">
    <tr><td style="background:#1e1712;padding:18px 24px;color:#e8c37e;font-weight:bold;font-size:15px;letter-spacing:.5px">48 HS</td></tr>
    <tr><td style="padding:24px">
      <h1 style="font-size:20px;margin:0 0 14px;color:#1e1712">${titulo}</h1>
      ${cuerpo}
    </td></tr>
    <tr><td style="padding:14px 24px 22px;color:#8a7c6d;font-size:12px;line-height:1.5;border-top:1px solid #eee5da">${pie}</td></tr>
  </table></body></html>`;
}
const boton = (href: string, txt: string) =>
  `<p style="margin:22px 0"><a href="${esc(href)}" style="background:#f5943d;color:#2a1405;text-decoration:none;font-weight:bold;padding:13px 20px;border-radius:10px;display:inline-block">${esc(txt)}</a></p>`;
const parrafo = (s: string) => `<p style="font-size:15px;line-height:1.55;margin:0 0 12px">${s}</p>`;

// ---------------------------------------------------------------------
// 1. Lista de espera
// ---------------------------------------------------------------------
async function tareaListaEspera(prueba: boolean, enviados: Correo[]) {
  const { fecha: hoy } = ahoraPosadas();
  const filas: Fila[] = await rest(
    `lista_espera?select=*&estado=eq.esperando&fecha_evento=gte.${hoy}&order=creado.asc&limit=1000`);
  if (!filas.length) return { avisados: 0 };

  // Disponibilidad con la misma función que usa la app
  const claves = [...new Set(filas.map((f) => `${f.actividad_id}|${f.fecha_evento}`))];
  const cupos: Fila[] = await rest('rpc/cupos_estado', {
    method: 'POST',
    body: JSON.stringify({ p_items: claves.map((k) => ({ id: k.split('|')[0], fecha: k.split('|')[1] })) }),
  });
  const libres = new Map<string, number>();
  cupos.forEach((c) => libres.set(`${c.actividad_id}|${c.fecha_evento}`, Number(c.disponibles) || 0));

  const ids = [...new Set(filas.map((f) => String(f.actividad_id)))];
  const lugares: Fila[] = await rest(`lugares?select=*&id=in.(${ids.map(encodeURIComponent).join(',')})`);
  const lugar = new Map(lugares.map((l) => [String(l.id), l]));

  const avisar: Fila[] = [];
  for (const k of claves) {
    let disp = libres.get(k) ?? 0;
    if (disp <= 0) continue;
    // en orden de llegada; si a alguien no le alcanza, se saltea
    for (const f of filas.filter((x) => `${x.actividad_id}|${x.fecha_evento}` === k)) {
      if (Number(f.cantidad) <= disp) { avisar.push(f); disp -= Number(f.cantidad); }
      if (disp <= 0) break;
    }
  }

  for (const f of avisar) {
    const l = lugar.get(String(f.actividad_id)) ?? {};
    const pt = f.idioma === 'pt';
    const nombreAct = String((pt && l.nombre_pt) || l.nombre || f.actividad_id);
    const cuando = fechaLarga(String(f.fecha_evento), (l.horario_hora as string) ?? null, pt ? 'pt' : 'es');
    const reservar = `${APP_URL}?lugar=${encodeURIComponent(String(f.actividad_id))}&fecha=${f.fecha_evento}&reservar=1${pt ? '&lang=pt' : ''}`;
    const baja = `${APP_URL}?baja_espera=${f.id}${pt ? '&lang=pt' : ''}`;
    const html = pt
      ? plantilla('Uma vaga foi liberada',
          parrafo(`Olá, ${esc(f.nombre)}! Alguém cancelou e há vaga em <b>${esc(nombreAct)}</b>, ${esc(cuando)}.`) +
          parrafo('O aviso <b>não reserva</b> a vaga: quem completar a inscrição primeiro fica com ela.') +
          boton(reservar, 'Reservar minha vaga'),
          `Você recebeu este e-mail porque entrou na lista de espera do 48 HS. <a href="${esc(baja)}" style="color:#8a7c6d">Sair da lista</a>.`)
      : plantilla('Se liberó un lugar',
          parrafo(`¡Hola, ${esc(f.nombre)}! Alguien canceló y hay lugar en <b>${esc(nombreAct)}</b>, ${esc(cuando)}.`) +
          parrafo('El aviso <b>no reserva</b> el lugar: se lo queda quien complete la inscripción primero.') +
          boton(reservar, 'Reservar mi lugar'),
          `Te llegó este email porque te anotaste en la lista de espera de 48 HS. <a href="${esc(baja)}" style="color:#8a7c6d">Salir de la lista</a>.`);
    await enviar({ para: [String(f.email)], asunto: pt ? `Vaga liberada: ${nombreAct}` : `Se liberó un lugar: ${nombreAct}`, html }, prueba, enviados);
    if (!prueba) {
      await rest(`lista_espera?id=eq.${f.id}`, {
        method: 'PATCH', headers: { Prefer: 'return=minimal' },
        body: JSON.stringify({ estado: 'avisado', avisado_en: new Date().toISOString() }),
      });
    }
  }
  return { avisados: avisar.length };
}

// ---------------------------------------------------------------------
// 2. Recordatorios del día anterior
//    Lee la vista recordatorios_pendientes (PARTE 5 de temporada.sql).
//    Mientras no exista, la tarea se saltea sin error.
// ---------------------------------------------------------------------
async function tareaRecordatorios(prueba: boolean, enviados: Correo[]) {
  let filas: Fila[];
  try {
    filas = await rest('recordatorios_pendientes?select=*&limit=500');
  } catch (e) {
    const st = (e as { status?: number }).status;
    if (st === 404 || st === 400) return { salteada: 'falta la vista recordatorios_pendientes' };
    throw e;
  }
  for (const f of filas) {
    const codigo = String(f.id).replace(/-/g, '').slice(0, 8).toUpperCase();
    const cancelar = `${APP_URL}?cancelar=${codigo}`;
    const cuando = fechaLarga(String(f.fecha_evento), (f.hora as string) ?? null);
    const html = plantilla(`Mañana: ${esc(f.actividad)}`,
      parrafo(`¡Hola, ${esc(f.nombre)}! Te esperamos mañana.`) +
      parrafo(`📅 ${esc(cuando)}<br>📌 ${esc(f.direccion)}<br>🎟️ ${esc(f.cantidad)} ${Number(f.cantidad) === 1 ? 'persona' : 'personas'} · Código <b>${codigo}</b>`) +
      parrafo('Si al final no podés ir, liberá tu lugar así lo aprovecha alguien de la lista de espera:') +
      boton(cancelar, 'Liberar mi lugar'),
      'Te llegó este recordatorio porque te inscribiste en una actividad de 48 HS.');
    await enviar({ para: [String(f.email)], asunto: `Mañana: ${f.actividad}`, html }, prueba, enviados);
    if (!prueba) {
      await rest(`${TABLA_INSCRIPCIONES}?id=eq.${f.id}`, {
        method: 'PATCH', headers: { Prefer: 'return=minimal' },
        body: JSON.stringify({ recordatorio_enviado: new Date().toISOString() }),
      });
    }
  }
  return { enviados: filas.length };
}

// ---------------------------------------------------------------------
// 3. Reporte mensual para Turismo
// ---------------------------------------------------------------------
async function tareaReporte(prueba: boolean, enviados: Correo[]) {
  if (!REPORTE_PARA.length || !REPORTE_CLAVE) return { salteada: 'faltan REPORTE_DESTINATARIOS o REPORTE_CLAVE' };
  const { fecha } = ahoraPosadas();
  const [y, m] = fecha.split('-').map(Number);
  const ini = new Date(Date.UTC(m === 1 ? y - 1 : y, (m + 10) % 12, 1));
  const fin = new Date(Date.UTC(y, m - 1, 0));
  const iso = (d: Date) => d.toISOString().slice(0, 10);
  const r = await rest('rpc/estadisticas_resumen', {
    method: 'POST', body: JSON.stringify({ p_clave: REPORTE_CLAVE, p_desde: iso(ini), p_hasta: iso(fin) }),
  });
  if (!r?.ok) throw new Error('estadisticas_resumen: ' + (r?.motivo ?? 'sin respuesta'));

  const lugares: Fila[] = await rest('lugares?select=id,nombre');
  const nombre = new Map(lugares.map((l) => [String(l.id), String(l.nombre)]));
  const T = r.totales, A = r.anterior;
  const mes = `${MESES.es[ini.getUTCMonth()]} ${ini.getUTCFullYear()}`;
  const num = (n: number) => Number(n).toLocaleString('es-AR');
  const delta = (a: number, b: number) => b ? ` (${a >= b ? '+' : ''}${Math.round((a - b) / b * 100)}% vs. mes anterior)` : '';
  const fila = (k: string, v: string) => `<tr><td style="padding:7px 0;color:#5c5047">${k}</td><td style="padding:7px 0;text-align:right;font-weight:bold">${v}</td></tr>`;
  const top = (r.lugares as Fila[]).slice(0, 5)
    .map((l, i) => `${i + 1}. ${esc(nombre.get(String(l.lugar)) ?? l.lugar)} · ${num(Number(l.vistas))}`).join('<br>');

  const html = plantilla(`Reporte de ${mes}`,
    `<table role="presentation" width="100%" style="font-size:14px;border-collapse:collapse">
      ${fila('Visitas', num(T.visitas) + delta(T.visitas, A.visitas))}
      ${fila('Personas inscriptas', num(T.personas) + delta(T.personas, A.personas))}
      ${fila('Fichas de lugares vistas', num(T.vistas))}
      ${fila('Pedidos de "Cómo llegar"', num(T.como_llegar))}
      ${fila('Consultas por WhatsApp', num(T.whatsapp))}
      ${fila('Anotados en lista de espera', num(T.lista_espera))}
      ${fila('Visitas en portugués', T.visitas ? Math.round(T.visitas_pt / T.visitas * 100) + '%' : '—')}
    </table>` +
    (top ? parrafo(`<br><b>Lo más visto</b><br>${top}`) : '') +
    boton(`${APP_URL}reporte.html?mes=${iso(ini).slice(0, 7)}`, 'Ver el reporte completo'),
    'Datos anónimos de uso de la app: no incluyen nombres, emails ni ubicación de las personas.');
  await enviar({ para: REPORTE_PARA, asunto: `48 HS · Reporte de ${mes}`, html }, prueba, enviados);
  return { mes };
}

// ---------------------------------------------------------------------
Deno.serve(async (req) => {
  if (!SECRETO || !igual(req.headers.get('authorization') ?? '', `Bearer ${SECRETO}`)) {
    return new Response('no autorizado', { status: 401 });
  }
  const u = new URL(req.url);
  const pedida = u.searchParams.get('tarea');
  const prueba = u.searchParams.get('prueba') === '1';
  const { hora, dia } = ahoraPosadas();
  const correr = (t: string, cuando: boolean) => pedida === t || pedida === 'todas' || (!pedida && cuando);

  const resultado: Record<string, unknown> = { hora, prueba };
  const enviados: Correo[] = [];
  const tareas: [string, boolean, () => Promise<unknown>][] = [
    ['lista', true, () => tareaListaEspera(prueba, enviados)],
    ['recordatorios', hora === 10, () => tareaRecordatorios(prueba, enviados)],
    ['reporte', dia === 1 && hora === 9, () => tareaReporte(prueba, enviados)],
  ];
  // Cada tarea va aislada: si una falla, las otras siguen
  for (const [nombre, cuando, fn] of tareas) {
    if (!correr(nombre, cuando)) continue;
    try { resultado[nombre] = await fn(); }
    catch (e) { resultado[nombre] = { error: (e as Error).message }; console.error(`[avisos] ${nombre}:`, e); }
  }
  if (prueba) resultado.correos = enviados.map((c) => ({ para: c.para, asunto: c.asunto }));
  return Response.json(resultado);
});
