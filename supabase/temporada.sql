-- =====================================================================
-- PosadasVive · temporada de verano
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
  v_tipos  text[] := array['visita','vista_lugar','como_llegar','inscripcion_inicio','inscripcion_ok',
                           'lista_espera','whatsapp','compartir','guardar','ruta','filtro','idioma',
                           'instalada','cancelacion','calendario','contacto','video'];
begin
  if p_eventos is null or jsonb_typeof(p_eventos) <> 'array' then return; end if;
  -- la app manda lotes de hasta 25; más que eso no viene de la app
  if jsonb_array_length(p_eventos) > 30 then return; end if;

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
    exit when v_hoy >= 500;

    -- una sola "visita" por sesión
    continue when v_tipo = 'visita' and exists (
      select 1 from estadisticas_eventos where sesion = v_sesion and tipo = 'visita');

    -- extra: solo las claves que usa la app, con formato controlado
    x := case when jsonb_typeof(e->'x') = 'object' then e->'x' else '{}'::jsonb end;

    insert into estadisticas_eventos (tipo, lugar, idioma, sesion, origen, extra)
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
      )), '{}'::jsonb)
    );
    v_hoy := v_hoy + 1;
  end loop;
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
--   values (1, extensions.crypt('ELEGIR-UNA-CLAVE', extensions.gen_salt('bf')))
--   on conflict (id) do update set clave_hash = excluded.clave_hash;
-- =====================================================================

create table if not exists public.reporte_acceso (
  id         int primary key default 1 check (id = 1),
  clave_hash text not null
);
alter table public.reporte_acceso enable row level security;
revoke all on public.reporte_acceso from anon, authenticated;

create or replace function public.estadisticas_resumen(p_clave text, p_desde date, p_hasta date)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_tz   constant text := 'America/Argentina/Buenos_Aires';
  v_hash text;
  v_ini  timestamptz;
  v_fin  timestamptz;
  r      jsonb;
begin
  select clave_hash into v_hash from reporte_acceso where id = 1;
  if v_hash is null or p_clave is null or crypt(p_clave, v_hash) <> v_hash then
    perform pg_sleep(0.8);   -- frena a quien prueba claves a ciegas
    return jsonb_build_object('ok', false, 'motivo', 'clave');
  end if;
  if p_desde is null or p_hasta is null or p_hasta < p_desde or p_hasta - p_desde > 366 then
    return jsonb_build_object('ok', false, 'motivo', 'rango');
  end if;

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
             group by origen order by 2 desc limit 12) s)
  ) into r;

  return r;
end;
$$;

revoke all on function public.estadisticas_resumen(text, date, date) from public;
grant execute on function public.estadisticas_resumen(text, date, date) to anon, authenticated;


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
