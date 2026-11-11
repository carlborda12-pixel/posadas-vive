-- =====================================================================
-- 48 HS · auditoría de seguridad de la base (solo LEE, no cambia nada)
--
-- Supabase > SQL Editor > pegar todo > Run. Devuelve una tabla con cada
-- control y su resultado: OK, REVISAR o FALLA. Conviene correrla después
-- de cada cambio en la base y antes de cada temporada.
--
-- Revisa también lo que ya estaba antes de este repositorio (lugares,
-- inscripciones, reservar, cancelar, cupos_estado), que no está en estos
-- archivos y por eso no se pudo revisar línea por línea.
-- =====================================================================

create temp table if not exists _auditoria (orden int, control text, resultado text, detalle text) on commit preserve rows;
truncate _auditoria;

do $$
declare
  v_txt  text;
  v_n    bigint;
  v_err  text;
  t      text;
begin
  -- 1. Tablas sin RLS: cualquiera con la clave pública podría leerlas o escribirlas
  select string_agg(tablename, ', ' order by tablename) into v_txt
    from pg_tables where schemaname = 'public' and not rowsecurity;
  insert into _auditoria values (1, 'Todas las tablas tienen RLS (seguridad por filas)',
    case when v_txt is null then 'OK' else 'FALLA' end, coalesce('Sin RLS: ' || v_txt, ''));

  -- 2. Permisos de escritura directos para el público (anon)
  select string_agg(table_name || ' (' || privs || ')', '; ') into v_txt from (
    select table_name, string_agg(privilege_type, ',' order by privilege_type) privs
      from information_schema.role_table_grants
     where table_schema = 'public' and grantee = 'anon'
       and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')
     group by table_name) x;
  insert into _auditoria values (2, 'El público no puede escribir tablas directamente',
    case when v_txt is null then 'OK' else 'REVISAR' end,
    coalesce(v_txt || '. Con RLS bien hecha no pasa nada, pero lo más seguro es revocar: revoke insert, update, delete on <tabla> from anon;', ''));

  -- 3. Políticas que dejan escribir a cualquiera
  select string_agg(tablename || '.' || policyname || ' (' || cmd || ')', '; ') into v_txt
    from pg_policies
   where schemaname = 'public' and cmd in ('INSERT', 'UPDATE', 'DELETE', 'ALL')
     and ('anon' = any(roles) or 'public' = any(roles))
     and (coalesce(qual, 'true') = 'true' or coalesce(with_check, 'true') = 'true');
  insert into _auditoria values (3, 'Ninguna política deja escribir sin condiciones',
    case when v_txt is null then 'OK' else 'FALLA' end, coalesce(v_txt, ''));

  -- 4. Funciones "security definer" sin search_path fijo (se pueden engañar con objetos falsos)
  select string_agg(p.proname, ', ' order by p.proname) into v_txt
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%');
  insert into _auditoria values (4, 'Funciones con permisos elevados fijan su search_path',
    case when v_txt is null then 'OK' else 'FALLA' end,
    coalesce(v_txt || '. Agregar: alter function <nombre> set search_path = public, pg_temp;', ''));

  -- 5. Qué funciones puede llamar el público (para revisar que sean las esperadas)
  select string_agg(p.proname || case when p.prosecdef then ' (elevada)' else '' end, ', ' order by p.proname) into v_txt
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute');
  insert into _auditoria values (5, 'Funciones que el público puede llamar', 'REVISAR',
    coalesce(v_txt, '(ninguna)') || '. Esperadas: reservar, cancelar, cupos_estado, registrar_eventos, estadisticas_resumen, lista_espera_unirse, lista_espera_baja, visitante_ingresar, visitante_baja, catalogo_actual, catalogo_publicar, catalogo_historial, catalogo_restaurar, catalogo_planilla, agenda_externa. Cualquier otra: revoke execute on function <nombre> from anon, public;');

  -- 6. Vistas que saltean la RLS (sin security_invoker)
  select string_agg(c.relname, ', ') into v_txt
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'v'
     and not coalesce(c.reloptions::text like '%security_invoker=true%', false)
     and has_table_privilege('anon', c.oid, 'select');
  insert into _auditoria values (6, 'Las vistas públicas respetan la RLS',
    case when v_txt is null then 'OK' else 'FALLA' end,
    coalesce(v_txt || '. Agregar: alter view <nombre> set (security_invoker = true); o revocar el select a anon.', ''));

  -- 7 a 11. Lo que realmente ve el público, probado como "anon"
  foreach t in array array['inscripciones', 'lista_espera', 'estadisticas_eventos', 'reporte_acceso', 'reporte_intentos'] loop
    if to_regclass('public.' || t) is null then continue; end if;
    v_err := null; v_n := null;
    begin
      execute 'set local role anon';
      execute format('select count(*) from public.%I', t) into v_n;
      execute 'reset role';
    exception when others then
      v_err := sqlerrm; execute 'reset role';
    end;
    insert into _auditoria values (7, 'El público no ve la tabla ' || t,
      case when v_err is not null or v_n = 0 then 'OK' else 'FALLA' end,
      case when v_err is not null then 'Acceso denegado (bien)'
           when v_n = 0 then 'No ve filas'
           else 'Ve ' || v_n || ' filas: pueden ser datos personales' end);
  end loop;

  if to_regclass('public.lugares') is not null then
    v_err := null; v_n := null;
    begin
      execute 'set local role anon';
      execute 'select count(*) from public.lugares where not coalesce(publicado, false)' into v_n;
      execute 'reset role';
    exception when others then v_err := sqlerrm; execute 'reset role';
    end;
    insert into _auditoria values (8, 'El público ve solo los lugares publicados',
      case when v_err is not null or v_n = 0 then 'OK' else 'REVISAR' end,
      case when v_err is not null then 'No puede leer la tabla directamente: ' || v_err
           when v_n = 0 then 'No ve lugares sin publicar'
           else 'Ve ' || v_n || ' lugares sin publicar (borradores)' end);
  end if;

  -- 12. Clave del reporte: que exista y con costo de cifrado suficiente
  if to_regclass('public.reporte_acceso') is not null then
    select clave_hash into v_txt from public.reporte_acceso where id = 1;
    insert into _auditoria values (12, 'Clave del reporte',
      case when v_txt is null then 'REVISAR' when v_txt ~ '^\$2[aby]\$(0[0-9])\$' then 'REVISAR' else 'OK' end,
      case when v_txt is null then 'No hay clave cargada: el reporte no abre'
           when v_txt ~ '^\$2[aby]\$(0[0-9])\$' then 'Cifrado con costo bajo (' || substr(v_txt, 5, 2) || '). Volver a cargarla con gen_salt(''bf'', 10)'
           else 'Cargada (costo ' || substr(v_txt, 5, 2) || ')' end);
  end if;

  -- 13. Archivos (Storage): buckets públicos
  if to_regclass('storage.buckets') is not null then
    execute 'select string_agg(id, '', '') from storage.buckets where public' into v_txt;
    insert into _auditoria values (13, 'Carpetas de archivos públicas', case when v_txt is null then 'OK' else 'REVISAR' end,
      coalesce('Públicas: ' || v_txt || '. Está bien solo si son fotos para la web.', 'Ninguna'));
  end if;

  -- 14. Tareas programadas con el secreto escrito a la vista
  if to_regclass('cron.job') is not null then
    execute $q$select string_agg(jobname, ', ') from cron.job where command ~* 'bearer [a-z0-9_-]{12,}' and command !~* 'vault'$q$ into v_txt;
    insert into _auditoria values (14, 'El secreto de "avisos" no está escrito en las tareas', case when v_txt is null then 'OK' else 'FALLA' end,
      coalesce('Con el secreto a la vista: ' || v_txt || '. Pasarlo al Vault (ver cron.sql).', ''));
  end if;
end $$;

select orden, control, resultado, detalle from _auditoria order by orden, control;
