# 48 HS · seguridad

Revisión del 4 de noviembre de 2026 (versión actual: `pv-2026-11-10-3`). Se revisó todo el repositorio: la web (`index.html`, `sw.js`, `reporte.html`), la base (`supabase/*.sql`), la función de avisos, las herramientas y la configuración de Vercel.

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
- **Planilla guardada y carga rápida:** la planilla (.xlsx) de cada versión se guarda en `catalogo_versiones.planilla`, que el público no puede leer. Solo la devuelve `catalogo_planilla`, con la clave del panel. La base acepta solo un .xlsx (empieza con la firma de zip) de hasta 5 MB. La carga rápida escribe las filas en el navegador como texto (una descripción que empieza con `=` no se convierte en fórmula) y el resultado pasa por el mismo importador y las mismas revisiones que una planilla subida.

## Tercera revisión (10 de noviembre de 2026, después del panel y la carga rápida)

Se leyó de nuevo todo el código (web, panel, importador, base, service worker y configuración de Vercel) y se corrieron las 11 pruebas de navegador y las 4 de base. No aparecieron claves secretas en el código ni textos de la base que lleguen a la pantalla sin escapar. Sí aparecieron estos problemas, ya corregidos (cada uno con su prueba en `prueba_revision.py`, `prueba_rapida.py` o `sql4.mjs`):

| # | Gravedad | Qué pasaba | Cómo quedó |
|---|----------|-----------|------------|
| 22 | Alta | Si Supabase no respondía (sin conexión, base pausada o caída), la web volvía a `catalogo.json` y además pisaba la copia guardada en el teléfono: desaparecía todo lo publicado desde el panel. | Si el teléfono ya tiene una versión publicada, se queda con esa. `catalogo.json` solo se usa cuando no hay nada publicado o es la primera visita. El pedido tiene un tope de 8 segundos. |
| 23 | Alta | El navegador guardaba `libs/importador.js` una semana. Después de una actualización, el panel podía quedar con el importador viejo (sin carga rápida) y fallar. | `cargar.html` lo pide con un número de versión (`?v=`) y Vercel lo sirve sin caché larga. Al cambiar `importador.js` hay que cambiar ese número. |
| 24 | Media | Una actividad gratis con cupo cargada desde el panel mostraba "Reservar", pero la base de inscripciones (`reservar`, anterior a este repositorio) no la conoce y respondía "ya no está tomando inscripciones". | El pedido sale por WhatsApp y queda en Mis planes como consulta. La solución de fondo (que publicar dé de alta la actividad para reservar) está en "Lo que queda por decidir". |
| 25 | Media | Dos personas publicando a la vez: la segunda borraba sin aviso lo que cargó la primera (cada una partía de la planilla que tenía a la vista). | `catalogo_publicar` recibe la versión de base (`p_base`) y rechaza con "desactualizado" si ya no es la última. El panel avisa, trae lo nuevo y conserva el formulario. |
| 26 | Media | El freno de intentos de clave (reporte y panel) contaba por `x-forwarded-for`, que quien llama puede inventar: cambiándolo en cada pedido se esquivaba el bloqueo por origen (quedaba solo el tope general). | `origen_pedido()` usa la dirección que informa la red de Supabase (`cf-connecting-ip` / `x-real-ip`) y deja `x-forwarded-for` como respaldo. |
| 27 | Media | Un enlace compartido (`?lugar=...`) a algo que no está en la lista incluida en la página no abría nada en la primera visita. Afectaba a todo lo cargado desde el panel. | Se vuelve a intentar cuando termina de bajar el catálogo. |
| 28 | Baja | Con la pestaña abierta, un evento de último momento no aparecía hasta recargar. | Al volver a la pestaña se pregunta si hay versión nueva (como mucho cada 5 minutos; si no cambió, la respuesta es mínima). |
| 29 | Baja | La imagen para compartir (`og:image`) tenía ruta corta: WhatsApp y otras apps necesitan la dirección completa. | Dirección completa de `mundial-mapa-posadas.vercel.app`. Al cambiar de dominio hay que actualizarla (está anotado en `index.html`). |
| 30 | Baja | Si se publicaba bien pero fallaba la actualización de la pantalla del panel, se mostraba como error de publicación. "Borrar mis datos" no borraba el aviso de invitación cerrado. | Corregidos. |

**Límite conocido del bloqueo de claves:** 100 intentos fallidos en 15 minutos (panel) o 200 (reporte) bloquean a todos, también a quien tiene la clave correcta. Es a propósito: cada intento le cuesta trabajo a la base, y sin ese tope alguien podría dejarla sin recursos. La consecuencia es que un ataque sostenido puede dejar el panel sin acceso mientras dure.

## Agenda Ciudad desde WordPress (11 de noviembre de 2026)

La web suma los eventos que Turismo publica en `agenda.turismoposadas.tur.ar`.

- **Sin credenciales:** se lee la API pública de eventos (lo mismo que ve cualquiera en su sitio). La contraseña de aplicación de su WordPress no se usa ni se guarda en ningún lado de este proyecto. **La que se compartió en `PASS_API.txt` hay que revocarla y crear otra.**
- **Quién pide:** la base, con `pg_net`, a una dirección fija escrita en `agenda_externa_sync()`. Nadie de afuera puede cambiar a dónde se pide, ni disparar la sincronización (la función no es pública).
- **Datos de afuera, tratados como tales:** en la base se descartan borradores, eventos ocultos, ids y fechas inválidos, y se recorta todo a un largo máximo. En la web, títulos y descripciones se pasan a texto plano con un documento inerte (sin scripts, estilos ni iframes) y después van por `limpiarLugar`, como todo el catálogo. Imágenes y links solo se aceptan si son de `https://agenda.turismoposadas.tur.ar/`. Probado con código metido en el título, una imagen `javascript:` y un link a otro sitio (`prueba_agenda_wp.py`).
- **Disponibilidad:** si su sitio se cae o responde algo raro, queda la última copia buena; solo se borra lo que falta cuando llegaron todas las páginas bien (`sql6.mjs`).
- **Carga sobre su servidor:** como mucho 2 a 4 pedidos cada 30 minutos, sin importar cuánta gente use la web.

**Arreglo de paso (#31):** la foto de la ficha no se mostraba nunca. La etiqueta `<img src="">` vacía disparaba el aviso de "foto rota" al abrir la página y la dejaba oculta para siempre. Pasaba lo mismo en la ventana de inscripción. Corregido: cada ficha empieza de cero.

## Los 20 puntos antes de lanzar (11 de noviembre de 2026)

Revisión contra la lista habitual de "20 cosas antes de lanzar una app", con la prueba de cada una.

| # | Punto | Estado | Cómo está |
|---|-------|--------|-----------|
| 1 | Ocultar las claves API | ✅ | En la web solo está la clave pública de Supabase (`sb_publishable_…`), hecha para estar a la vista. Ninguna clave secreta en el código. |
| 2 | Sacar secretos de Git | ✅ | Escaneo con gitleaks de los 69 commits del repositorio: solo aparece la clave pública y el texto de ejemplo `AVISOS_SECRET`. Ver la nota sobre el repositorio público abajo. |
| 3 | Clave pública de la base | ✅ | `anonKey` es la publicable; la `service_role` no se usa en ningún lado. |
| 4 | RLS activado | ✅ | Todas las tablas con RLS y sin permisos para `anon`; se entra solo por funciones. `auditoria.sql` y `salud.sql` lo verifican. |
| 5 | Cifrar datos sensibles | ✅ | Claves del panel y del reporte con bcrypt; IP solo como hash; la base cifra el disco (Supabase, AES-256). Nombre y email de quien ingresa quedan legibles porque el reporte los muestra. |
| 6 | Autenticación en el servidor | ✅ | Cada función con clave la verifica en la base (`carga_verificar`, `estadisticas_resumen`); la página no decide nada. |
| 7 | Restringir acceso a registros | ✅ | Ninguna tabla se lee directo. El que reserva no puede ver reservas de otros; el ingreso no devuelve datos aunque se escriba un email ajeno. |
| 8 | Bloquear manipulación de campos | ⚠️ | En todo lo de este repositorio, sí (las funciones ignoran campos de más y validan cada uno). Faltan `reservar`, `cancelar`, `cupos_estado` y `sync_actividades`, que están en la base desde antes y no en el repositorio. |
| 9 | Proteger cookies de sesión | ✅ | No hay cookies ni cuentas. Las claves del panel y del reporte quedan en `sessionStorage` (se borran al cerrar la pestaña) y la CSP impide cargar scripts de afuera. |
| 10 | Hashear contraseñas | ✅ | bcrypt (`crypt` + `gen_salt('bf')`). |
| 11 | Limitar intentos de inicio | ✅ | 10 intentos fallidos por conexión en 15 minutos; tope general de 100 (panel) y 200 (reporte). Cuenta por la dirección real, no por `x-forwarded-for` (punto 26). |
| 12 | Protección contra bots | ✅ | Campo trampa en el ingreso y en las reservas; topes por minuto, por día y por sesión en estadísticas; tope por hora en publicaciones. Sin CAPTCHA (ver abajo). |
| 13 | Monitorear la base | ✅ | Nuevo `supabase/salud.sql`: espacio, uso del día, picos, claves equivocadas, limpieza nocturna, conexiones, tablas sin RLS y las consultas más pesadas. |
| 14 | Validar todas las entradas | ✅ | En la base (largos, formatos, rangos) y otra vez en la página. El catálogo se valida campo por campo al cargarse (`limpiarLugar`). |
| 15 | Escapar contenido del usuario | ✅ | `esc()` / `textContent` en todo; probado con `prueba_panel_xss.py`. La vulnerabilidad de Leaflet CVE-2025-69993 (`bindPopup` sin escapar) no aplica: todo lo que va a los popups se escapa. |
| 16 | Restringir subida de archivos | ✅ | Solo `.xlsx`, hasta 20 MB para revisar y 5 MB para guardar; la base controla que sea un zip de verdad. La planilla se lee en el navegador de quien la sube, nunca se ejecuta. |
| 17 | Limitar respuestas de la API | ✅ | Cada función devuelve solo lo necesario y con tope (historial: 30; reporte: 15, 60 y 300 filas). Las tablas no se pueden listar. |
| 18 | Cabeceras de seguridad | ✅ | CSP, HSTS, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy, COOP (`vercel.json`). |
| 19 | Forzar HTTPS | ✅ | Vercel redirige siempre a HTTPS y HSTS lo fija por dos años. |
| 20 | Escanear dependencias | ✅ | No hay paquetes npm en la web. Leaflet 1.9.4 (con huella SRI): su única vulnerabilidad conocida no aplica (punto 15). Fuentes e íconos son archivos estáticos. |

**Repositorio público.** `carlborda12-pixel/posadas-vive` es público. No tiene secretos, pero cualquiera puede ver la planilla (con notas internas y lugares sin publicar), la estructura de la base y este documento, que describe los riesgos que quedan. Se recomienda hacerlo privado (GitHub → Settings → General → Danger Zone → Change visibility). Vercel Hobby despliega igual desde un repositorio privado de una cuenta personal. Los commits también muestran el email del autor; para ocultarlo, activar "Keep my email addresses private" en GitHub.

**CAPTCHA.** No se agregó: las protecciones de arriba alcanzan para el tráfico esperado. Si aparecen bots reales (se vería en `salud.sql`: picos por minuto o muchas reservas raras), la opción es Cloudflare Turnstile, que es gratis y no le pide nada a la gente; necesita una cuenta de Cloudflare y una función en Supabase.

## Lo que queda por decidir (no es código)

- **Reservas con cupo de lo que se carga desde el panel:** hoy esos pedidos van por WhatsApp (punto 24). Para que se reserven con cupo como los paseos, hay que ver cómo están hechas `reservar`, `cupos_estado` y `sync_actividades` en la base (no están en este repositorio) y hacer que publicar las mantenga al día.

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
