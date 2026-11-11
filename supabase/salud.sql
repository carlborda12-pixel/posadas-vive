-- =====================================================================
-- 48h Posadas · Estado de la base (solo lee, no cambia nada)
--
-- Cómo usarlo: Supabase → SQL Editor → pegar TODO este archivo → Run.
-- Devuelve una tabla con cada indicador, su valor, el límite y si está bien.
-- Conviene mirarlo una vez por semana en temporada, o si la web anda lenta.
--
--   ok       → todo bien
--   atención → mirarlo pronto (se acerca a un límite)
--   revisar  → hay que hacer algo (ver la columna "que_hacer")
--
-- Las consultas más pesadas están al final, en una segunda parte aparte.
-- =====================================================================

with
lim as (
  select
    500 * 1024 * 1024::bigint                                          as tope_base,      -- plan gratuito: 500 MB
    public.ajuste('eventos_por_dia', 50000)                            as tope_dia,
    public.ajuste('eventos_por_minuto', 600)                           as tope_min
),
base as (
  select pg_database_size(current_database()) as bytes
),
hoy as (
  select coalesce((select eventos from public.estadisticas_contador
                    where dia = (now() at time zone 'America/Argentina/Cordoba')::date), 0) as eventos
),
pico as (
  select coalesce(max(n), 0) as por_minuto from (
    select count(*) n from public.estadisticas_eventos
     where creado > now() - interval '24 hours'
     group by date_trunc('minute', creado)) x
),
intentos as (
  select
    count(*) filter (where rol = 'carga')   as carga,
    count(*) filter (where rol = 'reporte') as reporte,
    count(distinct origen)                  as origenes
  from public.reporte_intentos where creado > now() - interval '24 hours'
),
limpieza as (
  select max(d.start_time) as ultima,
         (array_agg(d.status order by d.start_time desc))[1] as estado
    from cron.job_run_details d join cron.job j on j.jobid = d.jobid
   where j.jobname = '48hs-limpieza'
),
publicado as (
  select max(creado) as ultima, count(*) as versiones,
         coalesce(sum(octet_length(planilla)), 0) as bytes_planillas
    from public.catalogo_versiones
),
conexiones as (
  select count(*) as n, (select setting::int from pg_settings where name = 'max_connections') as tope
    from pg_stat_activity where datname = current_database()
)
select indicador, valor, limite, estado, que_hacer from (
  select 1 orden, 'Espacio usado por la base' indicador,
         pg_size_pretty(b.bytes) valor, pg_size_pretty(l.tope_base) limite,
         case when b.bytes > l.tope_base * 0.85 then 'revisar' when b.bytes > l.tope_base * 0.6 then 'atención' else 'ok' end estado,
         case when b.bytes > l.tope_base * 0.6 then 'Bajar dias_eventos en la tabla ajustes (ver LEEME, "Escalar") o pasar a Supabase Pro.' else '' end que_hacer
    from base b, lim l
  union all
  select 2, 'Eventos de estadística hoy', h.eventos::text, l.tope_dia::text,
         case when h.eventos >= l.tope_dia then 'revisar' when h.eventos > l.tope_dia * 0.7 then 'atención' else 'ok' end,
         case when h.eventos >= l.tope_dia then 'Se llegó al tope: hoy se dejan de contar visitas (la web sigue andando). Si es tráfico real, subir eventos_por_dia.' else '' end
    from hoy h, lim l
  union all
  select 3, 'Pico de eventos por minuto (24 h)', p.por_minuto::text, l.tope_min::text,
         case when p.por_minuto >= l.tope_min then 'revisar' when p.por_minuto > l.tope_min * 0.7 then 'atención' else 'ok' end,
         case when p.por_minuto >= l.tope_min then 'Hubo un pico al límite: puede ser un evento grande o un bot.' else '' end
    from pico p, lim l
  union all
  select 4, 'Claves equivocadas en el panel (24 h)', i.carga::text, '100 en 15 min bloquean el panel',
         case when i.carga >= 50 then 'revisar' when i.carga >= 15 then 'atención' else 'ok' end,
         case when i.carga >= 15 then 'Muchos intentos: si no fue alguien de Turismo, cambiar la clave del panel.' else '' end
    from intentos i
  union all
  select 5, 'Claves equivocadas en el reporte (24 h)', i.reporte::text, '200 en 15 min bloquean el reporte',
         case when i.reporte >= 80 then 'revisar' when i.reporte >= 20 then 'atención' else 'ok' end,
         case when i.reporte >= 20 then 'Muchos intentos: si no fue alguien de Turismo, cambiar la clave del reporte.' else '' end
    from intentos i
  union all
  select 6, 'Limpieza nocturna (48hs-limpieza)',
         coalesce(to_char(lp.ultima at time zone 'America/Argentina/Cordoba', 'DD/MM HH24:MI') || ' · ' || lp.estado, 'nunca corrió'),
         'todos los días 03:30',
         case when lp.ultima is null or lp.ultima < now() - interval '36 hours' or lp.estado <> 'succeeded' then 'revisar' else 'ok' end,
         case when lp.ultima is null or lp.ultima < now() - interval '36 hours' or lp.estado <> 'succeeded'
              then 'No está corriendo: volver a correr supabase/cron.sql.' else '' end
    from limpieza lp
  union all
  select 7, 'Última publicación desde el panel',
         coalesce(to_char(pu.ultima at time zone 'America/Argentina/Cordoba', 'DD/MM/YYYY HH24:MI') || ' · ' || pu.versiones || ' versiones guardadas', 'nunca'),
         '30 versiones', 'ok', ''
    from publicado pu
  union all
  select 8, 'Planillas guardadas', pg_size_pretty(pu.bytes_planillas), '≈ 150 MB',
         case when pu.bytes_planillas > 150 * 1024 * 1024 then 'atención' else 'ok' end,
         case when pu.bytes_planillas > 150 * 1024 * 1024 then 'Las planillas pesan mucho: sacarles imágenes o pestañas que no se usan.' else '' end
    from publicado pu
  union all
  select 9, 'Conexiones abiertas ahora', c.n::text, c.tope::text,
         case when c.n > c.tope * 0.8 then 'revisar' when c.n > c.tope * 0.5 then 'atención' else 'ok' end, ''
    from conexiones c
  union all
  select 10, 'Visitantes registrados', (select count(*) from public.visitantes)::text, '', 'ok', ''
  union all
  select 12, 'Agenda Ciudad (WordPress de Turismo)',
         coalesce(to_char(ae.ultimo_ok at time zone 'America/Argentina/Cordoba', 'DD/MM HH24:MI') || ' · ', 'nunca · ')
           || (select count(*) from public.agenda_externa) || ' eventos', 'cada 30 min',
         case when ae.ultimo_ok is null or ae.ultimo_ok < now() - interval '3 hours' then 'revisar' else 'ok' end,
         case when ae.ultimo_ok is null or ae.ultimo_ok < now() - interval '3 hours'
              then 'No se actualiza' || coalesce(' (' || ae.ultimo_error || ')', '') || '. Revisar que pg_net esté activo y correr supabase/cron.sql; si el error es HTTP, el sitio de Turismo puede estar caído.' else '' end
    from public.agenda_externa_estado ae where ae.id = 1
  union all
  select 11, 'Tablas abiertas al público (deberían ser 0)',
         (select count(*) from pg_tables t where t.schemaname = 'public' and not t.rowsecurity)::text, '0',
         case when exists (select 1 from pg_tables t where t.schemaname = 'public' and not t.rowsecurity) then 'revisar' else 'ok' end,
         case when exists (select 1 from pg_tables t where t.schemaname = 'public' and not t.rowsecurity)
              then 'Hay una tabla sin RLS: correr supabase/auditoria.sql para ver cuál.' else '' end
) x
order by orden;


-- =====================================================================
-- SEGUNDA PARTE (opcional): las 10 consultas que más tiempo le llevan a la base.
-- Seleccionar desde acá hasta el final y tocar Run (solo esta parte).
-- Si una función de 48hs aparece arriba con muchos milisegundos promedio,
-- mandarle la captura a soporte.
-- =====================================================================
-- select left(regexp_replace(query, '\s+', ' ', 'g'), 120)      as consulta,
--        calls                                                  as veces,
--        round(mean_exec_time::numeric, 1)                      as ms_promedio,
--        round(total_exec_time::numeric / 1000, 1)              as segundos_total
--   from extensions.pg_stat_statements
--  where query not ilike '%pg_stat_statements%'
--  order by total_exec_time desc
--  limit 10;
