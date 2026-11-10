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

-- Limpieza diaria (3:30 de Posadas = 6:30 UTC). Hace todo lo de
-- public.limpieza_diaria() (está en temporada.sql, PARTE 7):
--   · guarda el resumen de cada mes cerrado y borra el detalle viejo
--   · borra inscripciones, lista de espera y visitantes con los plazos de
--     la política de privacidad (se cambian en la tabla "ajustes")
-- Esta parte NO necesita la función de avisos: se puede activar ya, solo
-- con la extensión pg_cron.
select cron.schedule(
  '48hs-limpieza',
  '30 6 * * *',
  $$ select public.limpieza_diaria(); $$
);

-- Para ver si corren:   select * from cron.job_run_details order by start_time desc limit 20;
-- Para sacarlas:        select cron.unschedule('48hs-avisos');
