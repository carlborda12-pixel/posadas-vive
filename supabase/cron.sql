-- =====================================================================
-- 48 HS · tareas programadas
--
-- Se aplica DESPUÉS de temporada.sql y de publicar la función "avisos".
-- Antes, en Supabase > Database > Extensions, habilitar pg_cron y pg_net.
--
-- Reemplazar:
--   PEGAR-AVISOS_SECRET   por el mismo valor que cargaste como secreto
--                         AVISOS_SECRET en la función (ver LEEME.md)
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
                 'Authorization', 'Bearer PEGAR-AVISOS_SECRET'),
    body    := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
  $$
);

-- Limpieza diaria (3:30 de Posadas = 6:30 UTC):
--   · la lista de espera se borra una semana después de la actividad,
--     como promete el texto de privacidad
--   · las estadísticas se guardan dos años, para comparar temporadas
select cron.schedule(
  '48hs-limpieza',
  '30 6 * * *',
  $$
  delete from public.lista_espera
   where fecha_evento < (now() at time zone 'America/Argentina/Buenos_Aires')::date - 7;
  delete from public.estadisticas_eventos
   where creado < now() - interval '25 months';
  $$
);

-- Para ver si corren:   select * from cron.job_run_details order by start_time desc limit 20;
-- Para sacarlas:        select cron.unschedule('48hs-avisos');
