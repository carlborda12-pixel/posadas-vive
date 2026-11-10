-- =====================================================================
-- 48 HS · temporada de verano
--
-- Se aplica en Supabase > SQL Editor, en la etapa Supabase.
-- Es ADITIVO: crea tablas y funciones nuevas, no modifica las que ya
-- existen (lugares, inscripciones, reservar, cancelar, cupos_estado).
-- Se puede correr más de una vez sin romper nada.
--
--   PARTE 1  Estadísticas anónimas        (registrar_eventos)
--   PARTE 2  Reporte para Turismo         (estadisticas_resumen)
--   PARTE 3  Lista de espera              (lista_espera_unirse / _baja)
--   PARTE 4  Columnas en portugués        (lugares.*_pt)
--   PARTE 5  Recordatorios                (plantilla: se ajusta con el
--                                           nombre real de tu tabla)
--   PARTE 6  Visitantes que ingresan      (visitante_ingresar / _baja)
--            con nombre y email
--   PARTE 7  Ajustes, resumen mensual     (topes y plazos editables,
--            y limpieza                    limpieza_diaria para cron)
--
-- Se puede volver a correr entero cuantas veces haga falta: no borra datos
-- y deja todo actualizado.
--
-- Las tareas programadas (avisos por email y limpieza) están en cron.sql.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;


-- =====================================================================
-- PARTE 1 · ESTADÍSTICAS ANÓNIMAS
-- Cuentan uso, no personas: no se guarda IP, ni email, ni nombre.
-- "sesion" es un número al azar que vive mientras la pestaña está
-- abierta, y sirve solo para no contar dos veces la misma visita.
-- =====================================================================

create table if not exists public.estadisticas_eventos (
  id      bigint generated always as identity primary key,
  creado  timestamptz not null default now(),
  tipo    text not null,
  lugar   text,
  idioma  text,
  sesion  text not null,
  origen  text,
  extra   jsonb
);
create index if not exists estadisticas_eventos_creado_idx on public.estadisticas_eventos (creado);
create index if not exists estadisticas_eventos_sesion_idx on public.estadisticas_eventos (sesion, creado);

-- Nadie lee ni escribe la tabla directo: solo a través de las funciones.
alter table public.estadisticas_eventos enable row level security;
revoke all on public.estadisticas_eventos from anon, authenticated;

-- Personas que ingresaron con nombre y email (PARTE 6). Va acá porque los
-- eventos de quien ingresó llevan su id. Si la persona pide la baja, se
-- borra su fila y sus eventos quedan anónimos (on delete set null).
create table if not exists public.visitantes (
  id        uuid primary key,
  creado    timestamptz not null default now(),
  ultimo    timestamptz not null default now(),
  nombre    text not null check (char_length(nombre) between 2 and 80),
  email     text not null check (char_length(email) <= 160),
  idioma    text not null default 'es' check (idioma in ('es','pt')),
  politica  text not null
);
create index if not exists visitantes_creado_idx on public.visitantes (creado);
create index if not exists visitantes_email_idx on public.visitantes (lower(email));
alter table public.visitantes enable row level security;
revoke all on public.visitantes from anon, authenticated;

alter table public.estadisticas_eventos
  add column if not exists visitante uuid references public.visitantes(id) on delete set null;

-- AJUSTES: topes y plazos en una tabla, para cambiarlos sin tocar el código.
-- Los valores de abajo son para el plan gratis de Supabase (500 MB). Con el
-- plan Pro se pueden subir (ver LEEME, "Escalar"). Para cambiar uno:
--   update public.ajustes set valor = 120 where clave = 'dias_eventos';
create table if not exists public.ajustes (
  clave text primary key,
  valor numeric not null check (valor >= 0),
  nota  text
);
alter table public.ajustes enable row level security;
revoke all on public.ajustes from anon, authenticated;
insert into public.ajustes (clave, valor, nota) values
  ('eventos_por_minuto',     600,   'Tope de estadísticas por minuto, de toda la web (frena a quien invente visitas para llenar la base).'),
  ('eventos_por_dia',        50000, 'Tope de estadísticas por día, de toda la web. Uso real esperado: menos de 20.000.'),
  ('eventos_por_sesion_dia', 500,   'Tope por visita (sesión) y día.'),
  ('dias_eventos',           62,    'Días que se guarda cada evento con detalle. Después queda solo el resumen del mes, sin datos personales.'),
  ('dias_resumen',           730,   'Días que se guardan los resúmenes mensuales (dos años, como dice la política).'),
  ('dias_visitantes',        730,   'Días sin usar la web tras los que se borra a quien ingresó.'),
  ('dias_lista_espera',      7,     'Días después de la actividad en que se borra la lista de espera.'),
  ('dias_inscripciones',     183,   'Días después de la actividad en que se borran las inscripciones (seis meses).')
on conflict (clave) do nothing;

create or replace function public.ajuste(p_clave text, p_defecto numeric)
returns numeric
language sql
stable
set search_path = public, pg_temp
as $$ select coalesce((select valor from public.ajustes where clave = p_clave), p_defecto) $$;
revoke all on function public.ajuste(text, numeric) from public, anon, authenticated;

-- Contador de eventos por día: así el tope diario no tiene que contar
-- toda la tabla en cada pedido (escala con mucho tráfico).
create table if not exists public.estadisticas_contador (
  dia     date primary key,
  eventos integer not null default 0
);
alter table public.estadisticas_contador enable row level security;
revoke all on public.estadisticas_contador from anon, authenticated;
create index if not exists estadisticas_eventos_visitante_idx
  on public.estadisticas_eventos (visitante, creado) where visitante is not null;

create or replace function public.registrar_eventos(p_eventos jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  e        jsonb;
  x        jsonb;
  v_sesion text;
  v_tipo   text;
  v_hoy    int;
  v_min    int;
  v_vis    uuid;
  v_dia    date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  v_ins    int := 0;
  v_tope_s numeric := ajuste('eventos_por_sesion_dia', 500);
  v_tipos  text[] := array['visita','vista_lugar','como_llegar','inscripcion_inicio','inscripcion_ok',
                           'lista_espera','whatsapp','compartir','guardar','ruta','filtro','idioma',
                           'instalada','cancelacion','calendario','contacto','video'];
begin
  if p_eventos is null or jsonb_typeof(p_eventos) <> 'array' then return; end if;
  -- la app manda lotes de hasta 25; más que eso no viene de la app
  if jsonb_array_length(p_eventos) > 30 then return; end if;

  -- topes generales: la "sesión" la inventa el teléfono, así que alguien podría
  -- inventar miles y llenar la base. Los valores están en la tabla "ajustes".
  if coalesce((select eventos from estadisticas_contador where dia = v_dia), 0) >= ajuste('eventos_por_dia', 50000) then
    return;
  end if;
  select count(*) into v_min from estadisticas_eventos where creado > now() - interval '1 minute';
  if v_min >= ajuste('eventos_por_minuto', 600) then return; end if;

  -- quien ingresó con nombre y email: todo el lote es del mismo teléfono.
  -- Solo se acepta un id que exista (lo crea visitante_ingresar).
  select v.id into v_vis from visitantes v
   where v.id = (select (j.value->>'v')::uuid from jsonb_array_elements(p_eventos) j
                  where j.value->>'v' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' limit 1);
  if v_vis is not null then update visitantes set ultimo = now() where id = v_vis; end if;

  for e in select value from jsonb_array_elements(p_eventos) loop
    continue when jsonb_typeof(e) <> 'object';
    v_sesion := e->>'s';
    v_tipo   := e->>'t';
    continue when v_sesion is null or v_sesion !~ '^[0-9a-f]{16}$';
    continue when v_tipo is null or not (v_tipo = any(v_tipos));

    -- tope por sesión: una persona real no genera 500 eventos en un día
    if v_hoy is null then
      select count(*) into v_hoy from estadisticas_eventos
       where sesion = v_sesion and creado > now() - interval '1 day';
    end if;
    exit when v_hoy >= v_tope_s;

    -- una sola "visita" por sesión
    continue when v_tipo = 'visita' and exists (
      select 1 from estadisticas_eventos where sesion = v_sesion and tipo = 'visita');

    -- extra: solo las claves que usa la app, con formato controlado
    x := case when jsonb_typeof(e->'x') = 'object' then e->'x' else '{}'::jsonb end;

    insert into estadisticas_eventos (tipo, lugar, idioma, sesion, origen, extra, visitante)
    values (
      v_tipo,
      case when e->>'l' ~ '^[a-z0-9_-]{1,40}$' then e->>'l' end,
      case when e->>'i' in ('es','pt') then e->>'i' end,
      v_sesion,
      case when e->>'o' ~ '^[a-z0-9_-]{1,40}$' then e->>'o' end,
      nullif(jsonb_strip_nulls(jsonb_build_object(
        'n',    case when x->>'n' ~ '^[0-9]{1,2}$' then (x->>'n')::int end,
        'inst', case when x->>'inst' in ('0','1') then (x->>'inst')::int end,
        'm',    case when x->>'m' ~ '^[a-z_-]{1,20}$' then x->>'m' end,
        'r',    case when x->>'r' ~ '^[a-z_-]{1,20}$' then x->>'r' end,
        'k',    case when x->>'k' ~ '^[a-z_-]{1,20}$' then x->>'k' end,
        'a',    case when x->>'a' in ('es','pt') then x->>'a' end,
        'f',    case when x->>'f' ~ '^\d{4}-\d{2}-\d{2}$' then x->>'f' end
      )), '{}'::jsonb),
      v_vis
    );
    v_hoy := v_hoy + 1;
    v_ins := v_ins + 1;
  end loop;

  if v_ins > 0 then
    insert into estadisticas_contador (dia, eventos) values (v_dia, v_ins)
    on conflict (dia) do update set eventos = estadisticas_contador.eventos + excluded.eventos;
  end if;
end;
$$;

revoke all on function public.registrar_eventos(jsonb) from public;
grant execute on function public.registrar_eventos(jsonb) to anon, authenticated;


-- =====================================================================
-- PARTE 2 · REPORTE PARA TURISMO
-- Devuelve solo números agregados. Pide una clave para que el reporte
-- no quede público.
--
-- Para definir o cambiar la clave (cambiar el texto entre comillas):
--
--   insert into public.reporte_acceso (id, clave_hash)
--   values (1, extensions.crypt('ELEGIR-UNA-CLAVE', extensions.gen_salt('bf', 10)))
--   on conflict (id) do update set clave_hash = excluded.clave_hash;
--
-- La clave: 12 caracteres o más, que no se use en otro lado.
-- =====================================================================

create table if not exists public.reporte_acceso (
  id         int primary key default 1 check (id = 1),
  clave_hash text not null
);
alter table public.reporte_acceso enable row level security;
revoke all on public.reporte_acceso from anon, authenticated;

-- Intentos fallidos de clave. Se guarda un resumen (hash) de la conexión, no la IP.
-- Antes cada error esperaba 0,8 s con pg_sleep: muchos pedidos juntos dejaban
-- la base sin conexiones libres. Ahora se cuenta y se bloquea.
create table if not exists public.reporte_intentos (
  creado  timestamptz not null default now(),
  origen  text not null
);
create index if not exists reporte_intentos_idx on public.reporte_intentos (creado);
alter table public.reporte_intentos enable row level security;
revoke all on public.reporte_intentos from anon, authenticated;

create or replace function public.estadisticas_resumen(p_clave text, p_desde date, p_hasta date)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_tz     constant text := 'America/Argentina/Buenos_Aires';
  v_hash   text;
  v_ini    timestamptz;
  v_fin    timestamptz;
  v_origen text;
  r        jsonb;
begin
  -- quién pregunta, resumido: el hash de la IP con la que llega el pedido
  v_origen := encode(digest(coalesce(
    split_part(current_setting('request.headers', true)::json->>'x-forwarded-for', ',', 1), 'sin-ip'), 'sha256'), 'hex');

  -- 10 errores en 15 minutos desde el mismo lugar, o 200 en total: se bloquea
  if (select count(*) from reporte_intentos where origen = v_origen and creado > now() - interval '15 minutes') >= 10
     or (select count(*) from reporte_intentos where creado > now() - interval '15 minutes') >= 200 then
    return jsonb_build_object('ok', false, 'motivo', 'bloqueado');
  end if;

  select clave_hash into v_hash from reporte_acceso where id = 1;
  if v_hash is null or p_clave is null or char_length(p_clave) > 200 or crypt(p_clave, v_hash) <> v_hash then
    insert into reporte_intentos (origen) values (v_origen);
    return jsonb_build_object('ok', false, 'motivo', 'clave');
  end if;
  if p_desde is null or p_hasta is null or p_hasta < p_desde or p_hasta - p_desde > 366 then
    return jsonb_build_object('ok', false, 'motivo', 'rango');
  end if;

  -- Meses viejos: el detalle de cada evento se borra a los "dias_eventos" días
  -- (ver PARTE 7) y queda el resumen guardado del mes. La lista de personas
  -- que ingresaron se calcula siempre en vivo (no se guarda en el resumen).
  if p_desde = date_trunc('month', p_desde)::date
     and p_hasta = (date_trunc('month', p_desde) + interval '1 month - 1 day')::date
     and p_desde < (now() at time zone v_tz)::date - ajuste('dias_eventos', 62)::int then
    select datos into r from reporte_mensual where mes = p_desde;
    if r is not null then
      return r || jsonb_build_object('visitantes_lista', resumen_periodo(p_desde, p_hasta)->'visitantes_lista',
                                     'guardado', true);
    end if;
  end if;

  return resumen_periodo(p_desde, p_hasta);
end;
$$;

revoke all on function public.estadisticas_resumen(text, date, date) from public;
grant execute on function public.estadisticas_resumen(text, date, date) to anon, authenticated;

-- El cálculo del reporte. Es interno: no lo puede llamar la web (no pide clave).
create or replace function public.resumen_periodo(p_desde date, p_hasta date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_tz  constant text := 'America/Argentina/Buenos_Aires';
  v_ini timestamptz;
  v_fin timestamptz;
  r     jsonb;
begin
  -- los días son de Posadas, no de UTC
  v_ini := p_desde::timestamp at time zone v_tz;
  v_fin := (p_hasta + 1)::timestamp at time zone v_tz;

  with ev as materialized (
    select * from estadisticas_eventos where creado >= v_ini and creado < v_fin
  )
  select jsonb_build_object(
    'ok', true,
    'desde', p_desde,
    'hasta', p_hasta,

    'totales', (select jsonb_build_object(
        'visitas',       count(*) filter (where tipo = 'visita'),
        'visitas_pt',    count(*) filter (where tipo = 'visita' and idioma = 'pt'),
        'visitas_app',   count(*) filter (where tipo = 'visita' and (extra->>'inst') = '1'),
        'vistas',        count(*) filter (where tipo = 'vista_lugar'),
        'inscripciones', count(*) filter (where tipo = 'inscripcion_ok'),
        'personas',      coalesce(sum((extra->>'n')::int) filter (where tipo = 'inscripcion_ok'), 0),
        'lista_espera',  count(*) filter (where tipo = 'lista_espera'),
        'cancelaciones', count(*) filter (where tipo = 'cancelacion'),
        'whatsapp',      count(*) filter (where tipo = 'whatsapp'),
        'como_llegar',   count(*) filter (where tipo = 'como_llegar'),
        'compartidos',   count(*) filter (where tipo = 'compartir'),
        'guardados',     count(*) filter (where tipo = 'guardar'),
        'calendario',    count(*) filter (where tipo = 'calendario'),
        'videos',        count(*) filter (where tipo = 'video'),
        'instaladas',    count(*) filter (where tipo = 'instalada'))
      from ev),

    -- el período anterior de la misma duración, para comparar
    'anterior', (select jsonb_build_object(
        'visitas',  count(*) filter (where tipo = 'visita'),
        'personas', coalesce(sum((extra->>'n')::int) filter (where tipo = 'inscripcion_ok'), 0))
      from estadisticas_eventos
      where creado >= v_ini - (v_fin - v_ini) and creado < v_ini),

    'por_dia', (select coalesce(jsonb_agg(jsonb_build_object('dia', d::date, 'visitas', coalesce(c.n, 0)) order by d), '[]'::jsonb)
      from generate_series(p_desde::timestamp, p_hasta::timestamp, interval '1 day') d
      left join (select (creado at time zone v_tz)::date dia, count(*) n
                   from ev where tipo = 'visita' group by 1) c on c.dia = d::date),

    'por_hora', (select coalesce(jsonb_agg(jsonb_build_object('hora', h, 'visitas', coalesce(c.n, 0)) order by h), '[]'::jsonb)
      from generate_series(0, 23) h
      left join (select extract(hour from creado at time zone v_tz)::int hora, count(*) n
                   from ev where tipo = 'visita' group by 1) c on c.hora = h),

    'lugares', (select coalesce(jsonb_agg(jsonb_build_object('lugar', lugar, 'vistas', vistas, 'como_llegar', llegar)
                                          order by vistas desc, lugar), '[]'::jsonb)
      from (select lugar,
                   count(*) filter (where tipo = 'vista_lugar') vistas,
                   count(*) filter (where tipo = 'como_llegar') llegar
              from ev where lugar is not null and tipo in ('vista_lugar', 'como_llegar')
             group by lugar order by 2 desc, lugar limit 15) s),

    'actividades', (select coalesce(jsonb_agg(jsonb_build_object('lugar', lugar, 'inscripciones', ins,
                                              'personas', pers, 'lista_espera', esp)
                                              order by pers desc, lugar), '[]'::jsonb)
      from (select lugar,
                   count(*) filter (where tipo = 'inscripcion_ok') ins,
                   coalesce(sum((extra->>'n')::int) filter (where tipo = 'inscripcion_ok'), 0) pers,
                   count(*) filter (where tipo = 'lista_espera') esp
              from ev where lugar is not null and tipo in ('inscripcion_ok', 'lista_espera')
             group by lugar order by 3 desc, lugar limit 15) s),

    'origenes', (select coalesce(jsonb_agg(jsonb_build_object('origen', origen, 'visitas', n) order by n desc, origen), '[]'::jsonb)
      from (select origen, count(*) n from ev where tipo = 'visita'
             group by origen order by 2 desc limit 12) s),

    -- Personas que ingresaron con nombre y email (aceptaron la política)
    'visitantes', (select jsonb_build_object(
        'nuevos',  (select count(*) from visitantes where creado >= v_ini and creado < v_fin),
        'activos', (select count(distinct visitante) from ev where visitante is not null),
        'total',   (select count(*) from visitantes where creado < v_fin))),

    -- Lista para Turismo: hasta 300, los más recientes primero, con los
    -- tres lugares o actividades que más les interesaron en el período
    'visitantes_lista', (select coalesce(jsonb_agg(jsonb_build_object(
          'nombre', v.nombre, 'email', v.email, 'idioma', v.idioma,
          'creado', v.creado, 'ultimo', v.ultimo,
          'intereses', coalesce((select jsonb_agg(lugar order by n desc, lugar) from (
              select lugar, count(*) n from ev
               where visitante = v.id and lugar is not null
                 and tipo in ('vista_lugar','guardar','como_llegar','inscripcion_ok','lista_espera','calendario','contacto','whatsapp')
               group by lugar order by 2 desc, lugar limit 3) i), '[]'::jsonb))
        order by v.ultimo desc), '[]'::jsonb)
      from (select * from visitantes
             where creado < v_fin
               and (creado >= v_ini or id in (select visitante from ev where visitante is not null))
             order by ultimo desc limit 300) v),

    -- Qué les interesa a quienes ingresaron (para agrupar por categoría en el reporte)
    'visitantes_lugares', (select coalesce(jsonb_agg(jsonb_build_object('lugar', lugar, 'n', n) order by n desc, lugar), '[]'::jsonb)
      from (select lugar, count(*) n from ev
             where visitante is not null and lugar is not null
               and tipo in ('vista_lugar','guardar','como_llegar','inscripcion_ok','lista_espera','calendario','contacto','whatsapp')
             group by lugar order by 2 desc, lugar limit 60) s)
  ) into r;

  return r;
end;
$$;

revoke all on function public.resumen_periodo(date, date) from public, anon, authenticated;


-- =====================================================================
-- PARTE 3 · LISTA DE ESPERA
-- Cuando una fecha se llena, la persona deja su email. Si alguien
-- cancela, la función "avisos" le escribe al primero de la lista con un
-- enlace para reservar. El aviso NO reserva el lugar: gana quien
-- complete la inscripción primero.
-- =====================================================================

create table if not exists public.lista_espera (
  id            uuid primary key default gen_random_uuid(),
  creado        timestamptz not null default now(),
  actividad_id  text not null,
  fecha_evento  date not null,
  nombre        text not null check (char_length(nombre) between 2 and 120),
  email         text not null check (char_length(email) <= 200),
  telefono      text check (telefono is null or char_length(telefono) <= 40),
  cantidad      int  not null check (cantidad between 1 and 10),
  idioma        text not null default 'es' check (idioma in ('es','pt')),
  estado        text not null default 'esperando' check (estado in ('esperando','avisado','baja')),
  avisado_en    timestamptz
);
create unique index if not exists lista_espera_unica
  on public.lista_espera (actividad_id, fecha_evento, lower(email)) where estado = 'esperando';
create index if not exists lista_espera_pendientes
  on public.lista_espera (estado, fecha_evento, creado);

alter table public.lista_espera enable row level security;
revoke all on public.lista_espera from anon, authenticated;

create or replace function public.lista_espera_unirse(
  p_actividad text, p_fecha date, p_nombre text, p_email text,
  p_telefono text default null, p_cantidad int default 1,
  p_idioma text default 'es', p_trampa text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_hoy   date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  v_pos   int;
  v_n     int;
begin
  -- campo trampa completo = bot. Le respondemos "ok" para que no insista.
  if coalesce(p_trampa, '') <> '' then
    return jsonb_build_object('ok', true, 'posicion', 1);
  end if;

  p_nombre   := btrim(coalesce(p_nombre, ''));
  p_email    := lower(btrim(coalesce(p_email, '')));
  p_telefono := nullif(btrim(coalesce(p_telefono, '')), '');

  if char_length(p_nombre) < 2 or char_length(p_nombre) > 120 then
    return jsonb_build_object('ok', false, 'motivo', 'datos_invalidos'); end if;
  -- el nombre va dentro del email de aviso: sin enlaces ni etiquetas, así nadie
  -- usa la lista para mandar mensajes engañosos a nombre de 48 HS
  if p_nombre ~* '(https?:|www\.|://|[<>{}\\]|\.(com|net|org|ar|io|xyz)\y)' then
    return jsonb_build_object('ok', false, 'motivo', 'datos_invalidos'); end if;
  if char_length(p_email) > 200 or p_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    return jsonb_build_object('ok', false, 'motivo', 'email_invalido'); end if;
  if p_cantidad is null or p_cantidad < 1 or p_cantidad > 10 then
    return jsonb_build_object('ok', false, 'motivo', 'cantidad_invalida'); end if;
  if p_telefono is not null and char_length(p_telefono) > 40 then
    return jsonb_build_object('ok', false, 'motivo', 'datos_invalidos'); end if;
  if p_fecha is null or p_fecha < v_hoy or p_fecha > v_hoy + 180 then
    return jsonb_build_object('ok', false, 'motivo', 'fecha_invalida'); end if;
  if p_idioma is null or p_idioma not in ('es','pt') then p_idioma := 'es'; end if;

  if not exists (select 1 from lugares where id = p_actividad and publicado and cupo is not null) then
    return jsonb_build_object('ok', false, 'motivo', 'actividad_inexistente'); end if;

  -- frenos contra abuso
  select count(*) into v_n from lista_espera
   where lower(email) = p_email and creado > now() - interval '1 hour';
  if v_n >= 5 then return jsonb_build_object('ok', false, 'motivo', 'demasiadas'); end if;

  -- tope general: con emails inventados alguien podría anotar a cientos de
  -- personas que después reciben avisos que no pidieron
  select count(*) into v_n from lista_espera where creado > now() - interval '1 hour';
  if v_n >= 300 then return jsonb_build_object('ok', false, 'motivo', 'demasiadas'); end if;

  select count(*) into v_n from lista_espera
   where actividad_id = p_actividad and fecha_evento = p_fecha and estado = 'esperando';
  if v_n >= 200 then return jsonb_build_object('ok', false, 'motivo', 'rechazado'); end if;

  if exists (select 1 from lista_espera
              where actividad_id = p_actividad and fecha_evento = p_fecha
                and lower(email) = p_email and estado = 'esperando') then
    return jsonb_build_object('ok', false, 'motivo', 'ya_en_lista');
  end if;

  insert into lista_espera (actividad_id, fecha_evento, nombre, email, telefono, cantidad, idioma)
  values (p_actividad, p_fecha, p_nombre, p_email, p_telefono, p_cantidad, p_idioma);

  select count(*) into v_pos from lista_espera
   where actividad_id = p_actividad and fecha_evento = p_fecha and estado = 'esperando';

  return jsonb_build_object('ok', true, 'posicion', v_pos);
exception
  when unique_violation then
    return jsonb_build_object('ok', false, 'motivo', 'ya_en_lista');
end;
$$;

revoke all on function public.lista_espera_unirse(text, date, text, text, text, int, text, text) from public;
grant execute on function public.lista_espera_unirse(text, date, text, text, text, int, text, text) to anon, authenticated;

-- Salir de la lista desde el enlace del email (?baja_espera=<id>).
-- El id es un uuid al azar: no se puede adivinar el de otra persona.
create or replace function public.lista_espera_baja(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update lista_espera set estado = 'baja'
   where id = p_id and estado in ('esperando', 'avisado');
  return jsonb_build_object('ok', found);
end;
$$;

revoke all on function public.lista_espera_baja(uuid) from public;
grant execute on function public.lista_espera_baja(uuid) to anon, authenticated;


-- =====================================================================
-- PARTE 4 · COLUMNAS EN PORTUGUÉS
-- Opcionales: si quedan vacías, la app muestra el texto en castellano.
-- =====================================================================

alter table public.lugares
  add column if not exists nombre_pt           text,
  add column if not exists direccion_pt        text,
  add column if not exists historia_pt         text,
  add column if not exists dato_pt             text,
  add column if not exists precio_pt           text,
  add column if not exists horario_etiqueta_pt text,
  add column if not exists horario_detalle_pt  text,
  add column if not exists etiquetas_pt        jsonb,   -- ["🌅 Pôr do sol", "🍵 Ideal para mate"]
  add column if not exists audio_pt            text,
  add column if not exists audio_url           text,    -- audioguía (castellano)
  add column if not exists audio_url_pt        text;    -- audioguía (portugués)


-- =====================================================================
-- PARTE 5 · RECORDATORIOS (plantilla)
-- La función "avisos" lee esta vista a las 10 de la mañana y le escribe
-- a quien tiene una actividad al día siguiente.
--
-- Está comentada porque depende de tu tabla de inscripciones, que no
-- tengo. En la etapa Supabase reemplazamos TABLA_INSCRIPCIONES y los
-- nombres de columnas por los reales y la activamos.
-- =====================================================================

/*
alter table public.TABLA_INSCRIPCIONES
  add column if not exists recordatorio_enviado timestamptz;

create or replace view public.recordatorios_pendientes
with (security_invoker = true) as
select i.id,
       i.nombre,
       i.email,
       i.cantidad,
       i.fecha_evento,
       l.id        as actividad_id,
       l.nombre    as actividad,
       l.direccion,
       l.horario_hora as hora
  from public.TABLA_INSCRIPCIONES i
  join public.lugares l on l.id = i.actividad_id
 where i.cancelada is not true                      -- AJUSTAR: cómo marca tu tabla las canceladas
   and i.recordatorio_enviado is null
   and i.fecha_evento = (now() at time zone 'America/Argentina/Buenos_Aires')::date + 1;

revoke all on public.recordatorios_pendientes from anon, authenticated;
*/


-- =====================================================================
-- PARTE 6 · VISITANTES QUE INGRESAN CON NOMBRE Y EMAIL
-- El ingreso es opcional (la web se puede usar sin ingresar). Quien
-- ingresa acepta la política de privacidad, y sus eventos llevan su id
-- para que Turismo sepa quién visita y qué le interesó.
-- El id lo genera el teléfono (uuid al azar) y solo lo conoce ese
-- teléfono. La web NUNCA lee estos datos: las recomendaciones se
-- calculan en el teléfono. Así, escribir el email de otra persona no
-- muestra nada de ella.
-- La tabla "visitantes" se crea en la PARTE 1.
-- =====================================================================

create or replace function public.visitante_ingresar(
  p_id uuid, p_nombre text, p_email text,
  p_idioma text default 'es', p_politica text default null, p_trampa text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_n int;
begin
  -- campo trampa completo = bot. Le respondemos "ok" para que no insista.
  if coalesce(p_trampa, '') <> '' then return jsonb_build_object('ok', true); end if;
  if p_id is null then return jsonb_build_object('ok', false, 'motivo', 'datos_invalidos'); end if;

  p_nombre := regexp_replace(btrim(coalesce(p_nombre, '')), '\s+', ' ', 'g');
  p_email  := lower(btrim(coalesce(p_email, '')));
  if char_length(p_nombre) < 2 or char_length(p_nombre) > 80 then
    return jsonb_build_object('ok', false, 'motivo', 'datos_invalidos'); end if;
  if p_nombre ~* '(https?:|www\.|://|[<>{}\\]|\.(com|net|org|ar|io|xyz)\y)' then
    return jsonb_build_object('ok', false, 'motivo', 'datos_invalidos'); end if;
  if char_length(p_email) > 160 or p_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    return jsonb_build_object('ok', false, 'motivo', 'email_invalido'); end if;
  if p_idioma is null or p_idioma not in ('es','pt') then p_idioma := 'es'; end if;
  if p_politica is null or p_politica !~ '^\d{4}-\d{2}-\d{2}$' then
    return jsonb_build_object('ok', false, 'motivo', 'sin_consentimiento'); end if;

  -- frenos contra abuso: el mismo email muchas veces en una hora, o una
  -- avalancha general (alguien inventando personas para llenar la base)
  select count(*) into v_n from visitantes where lower(email) = p_email and creado > now() - interval '1 hour';
  if v_n >= 5 then return jsonb_build_object('ok', false, 'motivo', 'demasiadas'); end if;
  select count(*) into v_n from visitantes where creado > now() - interval '1 hour';
  if v_n >= 1000 then return jsonb_build_object('ok', false, 'motivo', 'demasiadas'); end if;

  insert into visitantes (id, nombre, email, idioma, politica)
  values (p_id, p_nombre, p_email, p_idioma, p_politica)
  on conflict (id) do update
     set nombre = excluded.nombre, email = excluded.email, idioma = excluded.idioma,
         politica = excluded.politica, ultimo = now();

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.visitante_ingresar(uuid, text, text, text, text, text) from public;
grant execute on function public.visitante_ingresar(uuid, text, text, text, text, text) to anon, authenticated;

-- "Salir y borrar" en Mis planes. Borra a la persona; sus estadísticas
-- quedan, pero anónimas. El id es un uuid al azar: no se puede adivinar.
create or replace function public.visitante_baja(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  delete from visitantes where id = p_id;
  return jsonb_build_object('ok', found);
end;
$$;

revoke all on function public.visitante_baja(uuid) from public;
grant execute on function public.visitante_baja(uuid) to anon, authenticated;

-- Pedidos de acceso o borrado que lleguen por email (Ley 25.326):
--   select * from public.visitantes where lower(email) = lower('persona@ejemplo.com');
--   delete from public.visitantes where lower(email) = lower('persona@ejemplo.com');


-- =====================================================================
-- PARTE 7 · RESUMEN MENSUAL Y LIMPIEZA (para que la base no se llene)
-- Cada evento con detalle se guarda "dias_eventos" días (62 en el plan
-- gratis). Antes de borrarlos, se guarda el resumen de cada mes cerrado
-- en "reporte_mensual" (solo números y lugares, sin nombres ni emails),
-- así el reporte de meses viejos se sigue viendo igual.
-- La tarea diaria de cron.sql llama a limpieza_diaria().
-- =====================================================================

create table if not exists public.reporte_mensual (
  mes     date primary key check (mes = date_trunc('month', mes)::date),
  creado  timestamptz not null default now(),
  datos   jsonb not null
);
alter table public.reporte_mensual enable row level security;
revoke all on public.reporte_mensual from anon, authenticated;

-- Guarda (o actualiza) el resumen de un mes. Sin la lista de personas.
create or replace function public.guardar_resumen_mes(p_mes date)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_desde date := date_trunc('month', p_mes)::date;
  v_hasta date := (date_trunc('month', p_mes) + interval '1 month - 1 day')::date;
begin
  insert into reporte_mensual (mes, datos)
  values (v_desde, resumen_periodo(v_desde, v_hasta) - 'visitantes_lista')
  on conflict (mes) do update set datos = excluded.datos, creado = now();
end;
$$;
revoke all on function public.guardar_resumen_mes(date) from public, anon, authenticated;

-- Inscripciones: la política de privacidad promete borrarlas seis meses
-- después de la actividad. La tabla "inscripciones" es anterior a este
-- repositorio y no sabemos con certeza cómo se llama su columna de fecha,
-- así que la función la busca. Si no encuentra ninguna, no borra nada y
-- lo avisa (aparece en cron.job_run_details): en ese caso, agregar el
-- nombre correcto a la lista "candidatas".
create or replace function public.limpiar_inscripciones()
returns integer
language plpgsql
set search_path = public, pg_temp
as $$
declare
  candidatas text[] := array['fecha_evento', 'fecha', 'fecha_actividad', 'dia'];
  v_col text;
  v_n   integer := 0;
begin
  if to_regclass('public.inscripciones') is null then return 0; end if;
  select c.column_name into v_col
    from information_schema.columns c
   where c.table_schema = 'public' and c.table_name = 'inscripciones'
     and c.column_name = any(candidatas)
     and c.data_type in ('date', 'timestamp with time zone', 'timestamp without time zone')
   order by array_position(candidatas, c.column_name::text)
   limit 1;
  if v_col is null then
    raise warning '48hs-limpieza: no encontré la columna de fecha de public.inscripciones; no se borró nada';
    return 0;
  end if;
  execute format(
    'delete from public.inscripciones where %I::date < (now() at time zone ''America/Argentina/Buenos_Aires'')::date - %s',
    v_col, ajuste('dias_inscripciones', 183)::int);
  get diagnostics v_n = row_count;
  return v_n;
end $$;
revoke all on function public.limpiar_inscripciones() from public, anon, authenticated;

-- Todo lo que hay que borrar cada día, con los plazos de "ajustes".
-- Devuelve qué hizo, para verlo en cron.job_run_details o a mano:
--   select public.limpieza_diaria();
create or replace function public.limpieza_diaria()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tz    constant text := 'America/Argentina/Buenos_Aires';
  v_hoy   date := (now() at time zone v_tz)::date;
  v_corte timestamptz := now() - make_interval(days => ajuste('dias_eventos', 62)::int);
  v_mes   date;
  v_res   int := 0;
  v_ev    int;
  v_vis   int;
  v_esp   int;
  v_ins   int;
begin
  -- 1) resumen de cada mes cerrado que todavía tenga eventos con detalle
  --    (se rehace mientras haya detalle, así queda completo)
  for v_mes in
    select distinct date_trunc('month', creado at time zone v_tz)::date
      from estadisticas_eventos
     where creado < date_trunc('month', v_hoy)::timestamp at time zone v_tz
  loop
    perform guardar_resumen_mes(v_mes);
    v_res := v_res + 1;
  end loop;

  -- 2) borrar el detalle viejo (solo de meses que ya tienen resumen)
  delete from estadisticas_eventos e
   where e.creado < v_corte
     and exists (select 1 from reporte_mensual m
                  where m.mes = date_trunc('month', e.creado at time zone v_tz)::date);
  get diagnostics v_ev = row_count;

  delete from reporte_mensual where mes < v_hoy - ajuste('dias_resumen', 730)::int;
  delete from estadisticas_contador where dia < v_hoy - 7;

  -- 3) datos personales, con los plazos de la política de privacidad
  delete from visitantes where ultimo < now() - make_interval(days => ajuste('dias_visitantes', 730)::int);
  get diagnostics v_vis = row_count;
  delete from lista_espera where fecha_evento < v_hoy - ajuste('dias_lista_espera', 7)::int;
  get diagnostics v_esp = row_count;
  v_ins := limpiar_inscripciones();
  delete from reporte_intentos where creado < now() - interval '1 day';

  return jsonb_build_object('meses_resumidos', v_res, 'eventos_borrados', v_ev,
    'visitantes_borrados', v_vis, 'lista_espera_borrada', v_esp, 'inscripciones_borradas', v_ins);
end;
$$;
revoke all on function public.limpieza_diaria() from public, anon, authenticated;

-- Para ver cuánto ocupa la base (el plan gratis tiene 500 MB):
--   select pg_size_pretty(pg_database_size(current_database())) as base_total,
--          pg_size_pretty(pg_total_relation_size('public.estadisticas_eventos')) as estadisticas;

