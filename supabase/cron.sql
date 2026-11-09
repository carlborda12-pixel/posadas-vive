-- =====================================================================
-- 48 HS · tareas programadas
--
-- Se aplica DESPUÉS de temporada.sql y de publicar la función "avisos".
-- Antes, en Supabase > Database > Extensions, habilitar pg_cron y pg_net.
--
-- El secreto de la función NO se escribe en este archivo: se guarda una sola
-- vez en el Vault de Supabase (queda cifrado en la base) y la tarea lo lee de
-- ahí. Así este archivo se puede guardar o compartir sin exponer nada.
--
-- PASO 1 (una sola vez, en el SQL Editor, con el mismo valor que cargaste
-- como secreto AVISOS_SECRET de la función; no lo guardes en ningún archivo):
--
--   select vault.create_secret('EL-SECRETO-LARGO', 'avisos_secret');
--
-- Para cambiarlo más adelante:
--   select vault.update_secret((select id from vault.secrets where name = 'avisos_secret'), 'EL-NUEVO');
--
-- PASO 2: correr este archivo tal cual.
-- =====================================================================

-- Avisos: cada hora a los 5 minutos. La función decide qué hacer según
-- la hora de Posadas:
--   · lista de espera  → en cada corrida
--   · recordatorios    → a las 10 de la mañana
--   · reporte mensual  → el día 1 a las 9
select cron.schedule(
  '48hs-avisos',
  '5 * * * *',
  $$
  select net.http_post(
    url     := 'https://vqkjldyqgitzrhksiofd.supabase.co/functions/v1/avisos',
    headers := jsonb_build_object(
                 'Content-Type',  'application/json',
                 'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'avisos_secret')),
    body    := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
  $$
);

-- Inscripciones: la política de privacidad promete borrarlas seis meses
-- después de la actividad. La tabla "inscripciones" es anterior a este
-- repositorio y no sabemos con certeza cómo se llama su columna de fecha,
-- así que la función la busca. Si no encuentra ninguna, no borra nada y
-- lo avisa (aparece en cron.job_run_details): en ese caso, agregar el
-- nombre correcto a la lista "candidatas".
create or replace function public.limpiar_inscripciones()
returns integer
language plpgsql
set search_path = public
as $$
declare
  candidatas text[] := array['fecha_evento', 'fecha', 'fecha_actividad', 'dia'];
  v_col text;
  v_n   integer := 0;
begin
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
    'delete from public.inscripciones where %I::date < (now() at time zone ''America/Argentina/Buenos_Aires'')::date - 183',
    v_col);
  get diagnostics v_n = row_count;
  return v_n;
end $$;
revoke all on function public.limpiar_inscripciones() from public, anon, authenticated;

-- Limpieza diaria (3:30 de Posadas = 6:30 UTC):
--   · las inscripciones se borran seis meses después de la actividad
--   · los visitantes que ingresaron se borran tras dos años sin usar la web
--   · la lista de espera se borra una semana después de la actividad,
--     como promete el texto de privacidad
--   · las estadísticas se guardan dos años, para comparar temporadas
--   · los intentos de clave del reporte, un día
select cron.schedule(
  '48hs-limpieza',
  '30 6 * * *',
  $$
  select public.limpiar_inscripciones();
  -- quien ingresó y no volvió a usar la web en dos años
  delete from public.visitantes where ultimo < now() - interval '2 years';
  delete from public.lista_espera
   where fecha_evento < (now() at time zone 'America/Argentina/Buenos_Aires')::date - 7;
  delete from public.estadisticas_eventos
   where creado < now() - interval '25 months';
  delete from public.reporte_intentos
   where creado < now() - interval '1 day';
  $$
);

-- Para ver si corren:   select * from cron.job_run_details order by start_time desc limit 20;
-- Para sacarlas:        select cron.unschedule('48hs-avisos');
