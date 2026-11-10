# 48 HS · seguridad

Revisión del 4 de noviembre de 2026 (versión `pv-2026-11-10-2`). Se revisó todo el repositorio: la web (`index.html`, `sw.js`, `reporte.html`), la base (`supabase/*.sql`), la función de avisos, las herramientas y la configuración de Vercel.

## Cómo se probó

- **Código de la web, línea por línea.** Se buscó:
  - lugares donde un dato se mete en la página sin filtrar;
  - enlaces peligrosos;
  - código que se arma a partir de texto;
  - accesos ocultos;
  - claves escritas en los archivos.
- **Ataques en vivo con datos maliciosos.** Se cargaron en:
  - cada campo del catálogo (planilla y Supabase);
  - `servicios.json`;
  - los parámetros de la dirección (`?lugar`, `?cancelar`, `?fecha`, `?lang`, `?equipo`, `?baja_espera`);
  - los datos guardados en el teléfono.

  Después se recorrieron todas las pantallas, ventanas y fichas, se tocaron los marcadores y se pasó el mouse por todo.
- **Base de datos, en un Postgres local.** Se probaron intentos de adivinar la clave del reporte, la inundación de estadísticas y la de lista de espera, y los nombres con enlaces.

## Resultado

**No se encontraron puertas traseras** (accesos ocultos, código que se baja de afuera y se ejecuta, envíos de datos a terceros) **ni claves secretas en los archivos.** La única clave que aparece es la "publishable" de Supabase, que está hecha para ser pública. La web ya escapaba bien casi todo: ningún ataque llegó a ejecutar código.

Lo que sí se encontró y se corrigió:

| # | Gravedad | Qué pasaba | Qué se hizo |
|---|---|---|---|
| 1 | Media | Leaflet (la librería del mapa) se bajaba de unpkg sin control: si ese servidor fuera atacado, podía meter código en la web. | **Integridad (SRI):** el navegador verifica la huella oficial del archivo y, si no coincide, no lo usa. |
| 2 | Media | No había cabeceras de seguridad: cualquier código inyectado podía cargar scripts, marcos u objetos de cualquier sitio, y otra página podía meter la web dentro de un marco. | **`vercel.json`** con política de contenido (CSP): solo scripts propios y de unpkg, videos solo de YouTube, Instagram, TikTok, Vimeo y Drive, sin objetos y sin marcos ajenos. Suma `nosniff`, `Referrer-Policy` y `Permissions-Policy`. |
| 3 | Media | La clave del reporte se podía probar sin límite. Cada error esperaba 0,8 s con `pg_sleep`, así que muchos pedidos juntos ocupaban todas las conexiones de la base. | **Bloqueo:** 10 errores en 15 minutos desde el mismo lugar, o 200 en total, y no responde más hasta que pasen los 15 minutos. Ya no se usa `pg_sleep`. El cifrado de la clave pasa a costo 10. |
| 4 | Media | La "sesión" de las estadísticas la inventa el teléfono: inventando miles se podía llenar la base. | **Tope general:** 3000 eventos por minuto. |
| 5 | Media | La lista de espera aceptaba nombres con enlaces. Como el nombre va dentro del email de aviso, servía para mandar mensajes engañosos a nombre de 48 HS a cualquier dirección. | **Filtro:** se rechazan nombres con enlaces o etiquetas, y hay un tope general de 300 anotados por hora. |
| 6 | Media | `cron.sql` pedía pegar el secreto de la función adentro del archivo: si el archivo se subía a GitHub, el secreto quedaba expuesto. | **Vault:** el secreto se guarda una sola vez en el Vault de Supabase (cifrado) y la tarea lo lee de ahí. |
| 7 | Baja | La foto de los destacados del mapa se metía en un estilo CSS: una dirección armada podía agregar estilos o cargar imágenes de otro sitio. | **Escape para CSS:** se escapan comillas y paréntesis. |
| 8 | Baja | `urlSegura` bloqueaba `javascript:` con una lista, y `java\tscript:` la salteaba. No había dónde explotarlo, pero era frágil. | **Lista de permitidos:** solo `http` y `https`, decidido por el mismo lector de direcciones del navegador. |
| 9 | Baja | El catálogo de Supabase no pasaba por los mismos controles que el de la planilla (tipo, subcategorías, coordenadas, entradas). Un lugar sin coordenadas quedaba en 0,0, frente a África. | **Mismos controles** que la planilla, y coordenadas validadas en los dos. |
| 10 | Baja | `reporte.html?clave=...` dejaba la clave en los registros de Vercel. | Ahora va después de `#` (`reporte.html#clave=...`), que no viaja al servidor. |
| 11 | Baja | La planilla de servicios copiaba textos de OpenStreetMap, que edita cualquiera: un nombre que empezara con `=` se volvía fórmula al abrir el Excel. | **Siempre texto:** se protege con un apóstrofo y el tipo de celda. |
| 12 | Baja | El archivo de calendario (.ics) no escapaba el retorno de carro: se podían agregar renglones al evento. | Escapado. |
| 13 | Baja | El service worker reconocía servidores por "contiene" (`unpkg.com.sitio-falso.net` pasaba). | **Nombres exactos.** |
| 14 | Baja | La función de avisos aceptaba cualquier método y un secreto de cualquier largo. | **Solo POST** y secreto de 24 caracteres o más. Si es más corto, no corre. |
| — | Error | Los horarios en portugués de la planilla se perdían al cargar el catálogo. | Corregido. |

## Segunda revisión (9 de noviembre de 2026)

Se revisó otra vez todo, con el ingreso, las recomendaciones, las consultas en Mis planes, la auditoría real de Supabase y la librería del mapa.

**Claves y accesos.** No hay claves secretas en ningún archivo. Las únicas que aparecen son la dirección del proyecto de Supabase y su clave "publishable", que están hechas para ir en la web.

**Lo que se encontró y se corrigió:**

| # | Gravedad | Qué pasaba | Qué se hizo |
|---|---|---|---|
| 15 | Alta | Las vistas `panel_*` de Supabase (agenda, inscripciones, ocupación…) se podían leer con la clave pública: cualquiera podía ver nombres y emails de inscriptos. | Las vistas ahora respetan la seguridad por filas y el público no las puede leer. (Corregido en Supabase el 9/11.) |
| 16 | Media | El público podía llamar a `depurar_datos`, `ip_hash_actual` y `sync_actividades`, y tenía permiso de escritura directa en `actividades`, `cupos`, `inscripciones` y `lugares`. Lo frenaba la seguridad por filas, pero si alguien la desactivaba quedaba todo abierto. | Se le sacaron esos permisos. La web solo usa sus funciones. (Corregido en Supabase el 9/11.) |
| 17 | Media | Con la clave pública alguien podía mandar 3000 estadísticas falsas por minuto (más de 4 millones por día) y llenar en horas los 500 MB del plan gratis. Al llenarse, dejan de andar las inscripciones. | Topes por minuto, por día y por visita en la tabla `ajustes` (600, 50.000 y 500). El tope diario usa un contador, así no hay que contar la tabla en cada pedido. |
| 18 | Media | Aun sin ataques, guardar cada evento con detalle durante dos años no entra en el plan gratis con tráfico real. | El detalle se guarda 62 días. Antes de borrarlo, queda el resumen de cada mes (sin nombres ni emails) y el reporte de meses viejos se ve igual. |
| 19 | Baja | El mapa dependía de unpkg. | Leaflet se sirve desde el sitio (`libs/leaflet`), con la misma huella. unpkg queda solo de respaldo. |
| 20 | Baja | Un dato guardado en el teléfono con la clave `__proto__` podía alterar objetos de la app. | Esas claves se descartan. |
| 21 | Baja | Faltaba `Strict-Transport-Security`. | Agregado en `vercel.json`. |

**Ataques probados sin éxito.** Datos guardados con código (nombre, email, consultas, intereses, códigos de inscripción armados) y nombres con enlaces en el ingreso. La base no deja que el público lea visitantes, ajustes ni resúmenes, ni que llame al cálculo del reporte o a la limpieza.

**Riesgo aceptado.** La política de contenido permite conexiones a cualquier sitio `https:`, porque el service worker guarda en caché fotos que pueden venir de cualquier dirección cargada en la planilla. Si alguien lograra meter código en la página, podría mandar datos afuera. Por eso todo dato se escapa al mostrarse, y los ataques no ejecutaron nada.

## Panel de carga (10 de noviembre de 2026)

- **Clave propia** (`carga_acceso`), distinta de la del reporte, guardada cifrada. Tiene el mismo bloqueo: 10 errores en 15 minutos desde el mismo lugar. La clave queda solo en la pestaña (`sessionStorage`) y se borra al tocar "Salir".
- **La base vuelve a controlar todo lo que llega**, aunque alguien llame a la función a mano: formato, entre 1 y 5000 lugares, hasta 3 MB, IDs válidos, nombres de hasta 200 caracteres y hasta 60 publicaciones por hora. El público solo puede leer la versión publicada (`catalogo_actual`), no el historial ni la clave.
- **La web limpia cada lugar al cargarlo** (`limpiarLugar`), sin importar de dónde venga: enlaces solo `http`/`https`, coordenadas válidas, textos escapados. Una planilla con código no ejecuta nada.
- **El Excel se lee sin librerías de afuera:** el lector de `.xlsx` está en `libs/importador.js`. Así no hay dependencias con fallas conocidas (como las versiones viejas de SheetJS) y no se carga código de otros sitios.
- **Riesgo propio del modelo:** quien tenga la clave puede cambiar todo lo que muestra la web. Se puede volver atrás con el historial (últimas 30 versiones).

## Lo que queda por decidir (no es código)

- **Registro de usuarios de Supabase:** la web no usa cuentas, pero Supabase deja que cualquiera cree usuarios con la clave pública, y los emails de confirmación salen a nombre de tu proyecto. Desactivarlo en *Authentication → Sign In / Providers → Allow new users to sign up*.
- **Comprobar lo que publica Vercel:** `https://mundial-mapa-posadas.vercel.app/supabase/cron.sql`, `/LEEME.md` y `/datos/` tienen que dar 404.

- **WhatsApp personal:** `CONFIG.wapp` apunta a un número personal. Las consultas de turistas llegan ahí. Antes de publicar en serio, reemplazarlo por el de la Casa de Turismo.
- **Funciones viejas de Supabase:** `reservar`, `cancelar`, `cupos_estado` y las tablas `lugares` e `inscripciones` estaban antes de este repositorio y no están en estos archivos. Hay que correr `supabase/auditoria.sql` en el SQL Editor. Revisa:
  - RLS en todas las tablas;
  - que el público no pueda escribir ni leer inscripciones;
  - que solo vea lugares publicados;
  - qué funciones puede llamar;
  - el search_path de las funciones;
  - las vistas;
  - las carpetas de archivos;
  - el secreto de las tareas.

  Lo que salga FALLA, arreglarlo antes de abrir las inscripciones.
- **`?equipo=turismo`:** no es un acceso. Solo hace que no se cuenten las visitas de ese teléfono. Cualquiera puede activarlo.
- **Personas que ingresan (nombre y email):** la tabla `visitantes` no la puede leer ni escribir el público (RLS y sin permisos). Solo se escribe con `visitante_ingresar` (con topes contra abuso y filtro de enlaces en el nombre) y se borra con `visitante_baja`, que pide el id al azar que solo conoce el teléfono. La lista solo sale por `estadisticas_resumen`, con la clave del reporte. La web nunca pide el historial a la base: escribir un email ajeno no muestra nada. El email no se verifica (no se manda un enlace de confirmación), así que la lista puede tener emails mal escritos o de otras personas.
- **CSV del reporte:** las celdas que empiezan con `=`, `+`, `-` o `@` se protegen para que un nombre armado como fórmula no se ejecute en Excel.
- **Fotos en servidores ajenos:** las fotos y la imagen de respaldo para compartir están en `public.youware.com`, el servicio donde se armó el prototipo. Si ese servicio las cambia o las borra, cambian en la web. Conviene pasarlas al mismo dominio o a Supabase Storage.
- **Privacidad:** la política está en `privacidad.html`. Hasta completar los datos del responsable y tener la revisión de Asuntos Jurídicos, la página muestra BORRADOR. Ver "Privacidad y condiciones" en `LEEME.md`.
- **Tipografía:** ahora se sirve desde el mismo sitio (`fuentes/`). Ya no se le pasa a Google la IP de cada visita, y la política de contenido ya no permite `fonts.googleapis.com` ni `fonts.gstatic.com`.
- **Planillas que llegan de afuera:** al leer Excel de terceros, instalar `pip install defusedxml`. openpyxl lo usa solo y evita archivos armados para colgar la computadora.

## Para que siga así

1. **Datos nuevos en la página:** siempre con `esc()` (texto) y `urlSegura()` (enlaces e imágenes), nunca un dato crudo dentro de `innerHTML`. Para estilos, `urlCSS()`.
2. **Ids:** los que van dentro de `onclick="..."` tienen que pasar por `idValido()`.
3. **Librería externa nueva:** versión fija, con `integrity` y `crossorigin="anonymous"`, y agregar su dominio a la política de `vercel.json`.
4. **Videos de otro sitio:** agregarlo a `frame-src` en `vercel.json`. Si no, el navegador lo bloquea.
5. **Secretos:** nunca en archivos del repositorio. Van en los Secrets de las Edge Functions o en el Vault.
6. **Antes de cada temporada:** correr `supabase/auditoria.sql`.
7. **Clave del reporte:** 12 caracteres o más, cargada con `gen_salt('bf', 10)`. Cambiarla si alguien deja el equipo.
