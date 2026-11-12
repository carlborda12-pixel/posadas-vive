# 48 HS (antes PosadasVive) · temporada de verano

## Cómo queda el repositorio

```
48hs/
├── index.html               ← la app                      (se publica)
├── sw.js                    ← modo sin conexión            (se publica)
├── catalogo.json            ← lugares de la Muni           (se publica)
├── servicios.json           ← farmacias, cajeros, etc.     (se publica)
├── portada.jpg              ← foto al compartir el link    (se publica)
├── marca/                   ← logos, foto de portada, favicon (se publica)
├── reporte.html             ← reporte para Turismo         (se publica)
├── manifest.webmanifest     ← sin cambios                  (se publica)
├── iconos/                  ← íconos de la app (48h)       (se publica)
├── vercel.json              ← cabeceras de seguridad       (lo lee Vercel)
├── .vercelignore            ← lo que NO se publica
├── LEEME.md
├── SEGURIDAD.md             ← revisión de seguridad y reglas
├── herramientas/
│   ├── importar_catalogo.py
│   ├── servicios.py
│   └── iconos/armar_iconos.py
├── supabase/
│   ├── temporada.sql
│   ├── cron.sql
│   ├── auditoria.sql        ← control de seguridad de la base (solo lee)
│   ├── salud.sql            ← estado de la base: espacio, uso, intentos de clave (solo lee)
│   └── functions/avisos/index.ts
└── datos/
    ├── 48 HS - Carga de datos.xlsx
    └── 48 HS - Servicios para revisar.xlsx
```

Con la planilla en `datos/`, el importador se corre así:
`python herramientas/importar_catalogo.py "datos/48 HS - Carga de datos.xlsx" -o catalogo.json`

`.vercelignore` evita que se publiquen `herramientas/`, `supabase/`, `datos/` y la planilla. Es importante por `cron.sql`: cuando le pegues el secreto, ese archivo no puede quedar visible en la web.

## Qué se sube ahora (Vercel)

**Versión plana para subir arrastrando** (`48hs-para-subir.zip`): los mismos archivos públicos pero todos sueltos, sin carpetas (29 archivos), con las rutas ya ajustadas. Sirve cuando GitHub desarma las carpetas al arrastrar. No lleva `supabase/`, `herramientas/` ni `datos/`, así que no hace falta `.vercelignore`. Esta carpeta (`48hs/`) sigue siendo la fuente para trabajar; la versión plana se arma a partir de ella en cada entrega.


| Archivo | Qué es |
|---|---|
| `index.html` | La app |
| `sw.js` | Modo sin conexión (versión `pv-2026-11-10-3`) |
| `reporte.html` | Reporte de uso para la Casa de Turismo |
| `cargar.html` | Panel de carga para Turismo (con clave): sube la planilla, carga rápida de un evento, descarga de la planilla y publicación. Ver "Panel de carga" |
| `libs/importador.js` | El importador de la planilla para el navegador (mismas reglas que `herramientas/importar_catalogo.py`) |
| `privacidad.html` | Política de privacidad y condiciones de uso (español y portugués). **Antes de publicar, completar los datos del responsable** (ver "Privacidad y condiciones") |
| `libs/leaflet/` | La librería del mapa (Leaflet 1.9.4), servida desde el mismo sitio. Si falta, la web usa la copia de unpkg |
| `fuentes/` | La tipografía Be Vietnam Pro, servida desde el mismo sitio (con su licencia `OFL.txt`) |
| `marca/` | Logos y favicon (los usa `privacidad.html`; `index.html` los lleva incrustados) |
| `catalogo.json` | Los lugares de la planilla de la Muni (lo genera el importador) |
| `servicios.json` | Farmacias, cajeros, estacionamientos, baños, hospitales y policía que aparecen al acercar el mapa a nivel de calle |
| `vercel.json` | Cabeceras de seguridad (qué puede cargar la página). Va en la raíz del proyecto; Vercel lo lee y no lo publica. Ver `SEGURIDAD.md` |
| `manifest.webmanifest` | Sin cambios |
| `portada.jpg` | La foto que sale al compartir el link (1200×630). Cuando esté el dominio, poner su dirección completa en `og:image` y `twitter:image` de `index.html` |

Las carpetas `supabase/` y `herramientas/` y la planilla **no se suben a Vercel**.

Con solo subir estos archivos ya funcionan:

- **Elegir la fecha:** los paseos semanales se pueden reservar hasta 120 días hacia adelante.
- **Mis planes:** guardados e inscripciones, que quedan en el teléfono.
- **Agregar al calendario:** Google Calendar o archivo .ics.
- **Portugués:** botón ES/PT, que también detecta el idioma del teléfono.
- **Reporte con datos de ejemplo:** `reporte.html?demo=1`.

Lo que depende de la base se activa solo cuando aplicamos el SQL. Hasta entonces:

- **Lista de espera:** el pedido se manda por WhatsApp.
- **Estadísticas:** la app deja de intentar enviarlas, sin errores.
- **Reporte con datos reales:** avisa que las estadísticas todavía no están instaladas.

## Mapa: referencias y servicios

- **Lugares de referencia** (Costanera, puente, Anfiteatro, Terminal, Informes y Encarnación): están escritos dentro de `index.html`, en `REFERENCIAS`. Para agregar uno hace falta nombre, descripción corta y ubicación.
- **Playa El Mirador:** no figura en OpenStreetMap, así que no está. Cuando Turismo pase el punto exacto se agrega a `REFERENCIAS`.
- **Servicios** (`servicios.json`): 380 puntos sacados de OpenStreetMap (© colaboradores de OpenStreetMap, licencia ODbL; el mapa ya muestra el crédito). Farmacias solo de la zona centro, costanera y terminal. Aparecen recién a nivel de calle para no cargar el mapa.
- **Revisión de Turismo:** la planilla `datos/48 HS - Servicios para revisar.xlsx` tiene una fila por servicio con link a Google Maps y la columna "¿Está bien?" (Sí / No / Corregir). Cuando la devuelvan:
  `python herramientas/servicios.py importar "datos/48 HS - Servicios para revisar.xlsx" servicios.json`
  Para volver a armar la planilla desde el JSON: `python herramientas/servicios.py planilla servicios.json "datos/48 HS - Servicios para revisar.xlsx"`
- **Mapa de fondo:** calles de Esri con un filtro de color cálido; el satelital sigue en el botón de capas. Antes de un uso con mucho tráfico conviene revisar las condiciones de uso de los mapas de Esri (hay una nota `REVISAR` en el código).

## Identidad: 48h Posadas

La web usa la identidad del manual de Posadas Turismo ("48h Posadas · Propuesta"):

- **Dentro de la página:** los logos y las fotos van incrustados en `index.html`, así la web se ve completa aunque se abra como archivo suelto (por ejemplo, mandado por WhatsApp). Si se cambia algo de `marca/`, correr `python herramientas/marca/incrustar_marca.py`.
- **Fotos que no cargan:** si una foto de un lugar no carga, sale el fondo con ícono en vez del dibujo de imagen rota.
- **Logos:** en `marca/`, extraídos del PDF como vectores, así se ven nítidos en cualquier tamaño:
  - `logo-48h.svg`: 48h Posadas · Ciudad de experiencias, blanco con el arco rosa.
  - `logo-turismo.svg`: Posadas Turismo, blanco.
  - `marca-48h.svg`: solo "48h", para íconos.
- **Colores:**

  | Color | Código | Uso |
  |---|---|---|
  | Verde (principal) | `#05A36F` | Botones, filtros activos, "Llegar", enlaces |
  | Verde oscuro (principal) | `#003A28` | Fondos, íconos de la app, encabezado del reporte y los emails |
  | Rosa (acento) | `#F23179` | "Hoy", contadores, el arco del logo, la palabra resaltada de los títulos |
  | Blanco (acento) | `#F7F7F7` | Textos |

  En el CSS están en `:root`. Los nombres viejos se conservan: `--gold` y `--gold-deep` son el verde, `--sunset` y `--sunset-deep` son el rosa. Regla: el verde manda; el rosa solo marca lo que tiene que llamar la atención.
- **Tipografía:** Be Vietnam Pro, de Google Fonts.
- **Pantalla de inicio:** la foto de la costanera de noche (`marca/inicio.jpg`), el logo y "Creado por Posadas Turismo". La foto del PDF mide 1920×980: si Turismo tiene el original en más resolución, conviene reemplazarla con el mismo nombre.
- **Íconos de la app** (`iconos/`), `portada.jpg` y favicon: salen del logo, sobre verde oscuro `#003A28`. Para volver a armar la portada: `python herramientas/portada/armar_portada.py`.
- **Lo que no cambió:** los colores de las categorías del mapa, porque distinguen cultura, gastronomía, etc. Tampoco cambiaron los nombres internos de archivos y claves (`48 HS - Carga de datos.xlsx`, `pv-...`).

## Portada

La foto de fondo (`marca/inicio.jpg`) viene del PDF de la marca: es chica (1920×980) y muy comprimida. Para que se vea mejor:

- **`marca/inicio-hd.jpg`**: la misma foto limpiada de la compresión y agrandada al doble con inteligencia artificial (3840×1960). La web la carga desde el sitio.
- **Respaldo incrustado**: la versión de `--img-inicio` en `index.html` se usa si se abre el archivo suelto (WhatsApp) o mientras carga la buena.
- **Si Turismo consigue la foto original**, reemplazar `marca/inicio.jpg` y `marca/inicio-hd.jpg` por esa foto y correr `python herramientas/marca/incrustar_marca.py index.html`.

## Firma de ApexTech

En la esquina inferior izquierda hay un botón redondo con el logo de ApexTech, a la altura del menú, y en la portada dice "Desarrollado por ApexTech" (también en el pie de `privacidad.html`). Todo lleva a https://www.instagram.com/apex_sec/.

El logo actual (`marca/apextech.svg`) es **provisorio**. Para poner el oficial:
1. Reemplazar `marca/apextech.svg` por la versión para fondos oscuros, con el mismo nombre.
2. Correr `python herramientas/marca/incrustar_marca.py index.html`.

## Privacidad y condiciones

La web la presenta un organismo público y junta datos personales (inscripciones y personas que ingresan), así que tiene que cumplir la **Ley 25.326 de Protección de Datos Personales**. La autoridad de control es la Agencia de Acceso a la Información Pública (AAIP).

- **`privacidad.html`:** política de privacidad y condiciones de uso con el deslinde de responsabilidad, en español y portugués. Cuenta qué datos se usan, para qué, cuánto tiempo se guardan, con qué proveedores y cómo pedir verlos, corregirlos o borrarlos. Incluye las dos leyendas que exige la ley: el acceso gratuito cada seis meses y la AAIP como órgano de control.
- **Datos a completar:** el bloque `DATOS`, al final de `privacidad.html`, con el nombre legal del organismo, el domicilio y un email para consultas de datos personales. Mientras falte alguno, la página muestra una franja amarilla de BORRADOR.
- **Revisión legal:** el texto está escrito para lo que hace la web hoy, pero lo tiene que revisar Asuntos Jurídicos de la Municipalidad antes de publicarlo. Hay cuatro puntos para ellos:
  1. La creación del banco de datos de inscripciones: para un organismo público, la ley pide una norma publicada en el Boletín Oficial (art. 22).
  2. Los contratos con Supabase, Vercel y Resend, que tienen servidores fuera del país (art. 12; cláusulas modelo de la AAIP).
  3. La jurisdicción.
  4. En Misiones hay un proyecto de ley provincial de datos personales (junio de 2026). Si se aprueba, revisar la política.
- **En la app:**
  - enlaces en la portada, en "Mis planes" y en las notas de los formularios;
  - en la inscripción (y en la lista de espera, cuando vaya por email), una casilla obligatoria "Leí y acepto la política de privacidad" (por WhatsApp no hace falta, porque los datos los manda la persona misma);
  - en "Mis planes", el botón "Borrar mis datos de este teléfono" (dos toques).
- **Lo que la política promete y quién lo cumple:**

  | Promesa | Quién lo cumple |
  |---|---|
  | Inscripciones: se borran a los 6 meses de la actividad | `limpiar_inscripciones()` en `cron.sql` |
  | Lista de espera: se borra a la semana | La limpieza diaria de `cron.sql` |
  | Estadísticas: se guardan 2 años | La limpieza diaria de `cron.sql` |
  | Sin estadísticas con "No rastrear" o GPC | `index.html` |

  Si cambia alguno de estos plazos, cambiar también el texto de `privacidad.html` y las notas `priv.*` de `index.html`.
- **WhatsApp:** las reservas pagas y las consultas llegan al número de `CONFIG.wapp`. Mientras sea un número personal, esos datos personales van a un teléfono particular. Hay que cambiarlo por el de la Casa de Turismo antes de publicar.

## Seguridad

La revisión completa, lo que se corrigió y las reglas para que siga seguro están en `SEGURIDAD.md`. En resumen:

- Datos en la página: siempre con `esc()` y `urlSegura()`.
- Librerías externas: con `integrity`.
- Secretos: nunca en archivos.
- Base: correr `supabase/auditoria.sql` antes de cada temporada.
- Base: correr `supabase/salud.sql` una vez por semana en temporada (o si la web anda lenta). Cada fila dice ok, atención o revisar, y qué hacer.
- Asistente con IA: la clave de Gemini va **solo** en los secretos de Supabase (Edge Functions → Secrets).
- Reporte: el enlace con clave va con `#` (`reporte.html#clave=...`), no con `?`.

## Íconos

Los íconos (Phosphor, licencia MIT) van **dentro de `index.html`**: solo los que usa la web, unos 110, en 24 KB. Antes se bajaba la librería entera desde otro servidor (unos 500 KB por la red).

**Estilo:** línea fina en toda la web y relleno solo sobre el mapa (pines, referencias y servicios), donde son chicos. Se decide en el CSS de `index.html` (buscar "Estilo de íconos"). En el código se sigue escribiendo `ph` o `ph-fill`: el dibujo es el mismo, cambia el trazo. En pantalla no se usan emojis; en los mensajes de WhatsApp sí.

Si se agrega un ícono nuevo (por ejemplo `ph-tent`) en `index.html` o en el importador, hay que volver a armar la fuente; si no, ese ícono sale en blanco:

```
npm install @phosphor-icons/web@2.1.2
pip install fonttools brotli
python herramientas/iconos/armar_iconos.py index.html --phosphor node_modules/@phosphor-icons/web/src
```

El script avisa si algún nombre no existe en Phosphor (por un error de tipeo, por ejemplo). Los íconos se buscan en https://phosphoricons.com.

## Rendimiento (prueba de carga del 4/11)

Medido en un celular de gama media simulado (procesador 4 veces más lento que una computadora):

- **Con el catálogo real (108 lugares):** se probaron 120 acciones seguidas (abrir lugares, filtrar, acercar, cambiar idioma, agenda) y 6 horas de uso con el reloj adelantado. La memoria y los elementos de la página quedan estables y no hay errores.
- **Con catálogos grandes:** con 2.000 lugares, el mapa antes se colgaba 10 segundos al abrir y 18 al hacer zoom. Ahora la traba más larga es de medio segundo. Con 5.000 lugares, antes no llegaba a abrir y ahora funciona.
- **Datos rotos:** se probaron un catálogo que no es JSON, un catálogo vacío o con basura, una copia guardada corrupta, `servicios.json` roto y la falta de internet. La web sigue usable en todos los casos.

Qué cambió para lograrlo:

- **Reparto de puntos:** cada punto se compara solo con sus vecinos (antes, todos contra todos).
- **Con más de 600 lugares:** los puntos van en canvas.
- **Búsqueda de lugares por id:** usa un índice.
- **Hora de Argentina:** se calcula una vez por minuto.
- **Agenda:** muestra 20 actividades por grupo, con "Ver más" para el resto.
- **Rutas temáticas:** se quitó su código. Ya no tenían botón; si se quieren recuperar, están en las versiones anteriores.

## Nombre

La web se llama **48 HS** (antes PosadasVive). Por dentro quedan algunos nombres técnicos con el prefijo `pv-` (lo que guarda cada teléfono y el caché del modo sin conexión): se dejaron así a propósito para que nadie pierda sus planes guardados ni sus inscripciones al actualizar.

## Ingreso y recomendaciones

- **Ingreso opcional**: al tocar "Explorar la ciudad" aparece un panel con nombre, email y la casilla "Acepto…" (con enlace a la política). Se puede tocar "Seguir sin ingresar" y usar toda la web igual. No vuelve a preguntar: quien lo salteó tiene el botón "Ingresar" en Mis planes y una invitación que se puede cerrar en la Agenda.
- **Qué se guarda en el teléfono** (`pv-usuario`, `pv-intereses`): nombre, email y puntos por categoría según lo que la persona mira, guarda, filtra, pide "Cómo llegar" o donde se inscribe. Los puntos valen la mitad cada 30 días, así pesa más lo reciente.
- **"Para vos, {nombre}"**: arriba de la Agenda, hasta 8 eventos (y lugares si hay pocos eventos) ordenados por esos puntos, cada uno con su motivo ("Te interesa Naturaleza"). Se calculan en el teléfono.
- **En la base** (cuando esté Supabase): la persona se registra con `visitante_ingresar` y sus eventos llevan su id. La web nunca lee esos datos, así que escribir el email de otra persona no muestra nada de ella.
- **Para Turismo**: en `reporte.html`, la sección "Personas que ingresaron" muestra cuántas ingresaron, qué les interesa por categoría y la lista con nombre, email, fechas y los tres lugares que más les interesaron. Se puede bajar en CSV.
- **Salir**: "Salir y borrar" en Mis planes, o "Borrar mis datos de este teléfono", borra todo en el teléfono y le pide a la base que borre a la persona. Sus estadísticas quedan, pero anónimas.
- **Lo que no se hace**: no se mandan emails con esto (la política lo promete). Para mandar emails habría que agregar una casilla aparte y cambiar la política.

## Al entrar a la web

- **"¿Qué estás buscando hoy?"**: después de la pantalla de inicio, cada vez. Elegir una categoría filtra el mapa; las que no tienen lugares en el mapa (excursiones) abren la lista en la Agenda. Los enlaces directos a un lugar no la muestran.
- **Panel de ingreso**: al tocar "Explorar la ciudad", la primera vez, aparece antes de "¿Qué estás buscando hoy?". Ver "Ingreso y recomendaciones".
- **Aviso de novedades**: se sacó para la presentación (8/11). Queda solo el aviso "Hay una versión nueva de la guía · Actualizar", que aparece cuando se sube una versión nueva a Vercel.
- **Equipo de Turismo**: abrir una vez `?equipo=turismo` en cada teléfono, así sus visitas no cuentan en el reporte. Se desactiva con `?equipo=no`.

## Panel de carga: Turismo actualiza la web solo

`cargar.html` es una página con clave (distinta de la del reporte) para que Turismo actualice lugares y agenda sin pasar por vos:

1. Suben la planilla **"48 HS - Carga de datos"** (`.xlsx`, con las hojas Lugares y Agenda).
2. La página la revisa en el navegador, con las mismas reglas que `herramientas/importar_catalogo.py` (`libs/importador.js`; probado: da el mismo resultado). Muestra:
   - errores, que no dejan publicar (por ejemplo, IDs repetidos);
   - avisos (coordenadas raras, teléfonos que no se entienden, fechas mal escritas);
   - qué lugares son nuevos, cuáles cambian y cuáles salen;
   - qué lugares no tienen coordenadas.
3. **Publicar** guarda la versión en Supabase (`catalogo_versiones`). La web la lee al abrirse (`catalogo_actual`) y, si no hay nada publicado o la base no responde, usa `catalogo.json`.
4. **Historial:** las últimas 30 versiones. "Volver a esta" la publica de nuevo.
5. **Freno:** si una planilla saca más del 20 % de los lugares, pide confirmar (suele ser una planilla incompleta).
6. **Descargar la planilla:** cada versión guarda su `.xlsx` en la base. "Descargar la planilla (Excel)" baja la de la versión que está en la web; el historial tiene un botón "Planilla" por versión. Si Turismo pierde el archivo, baja ese, lo modifica y lo sube.
7. **Carga rápida:** para un evento de último momento, sin abrir el Excel. Dos opciones:
   - **Evento nuevo:** nombre, categorías, dónde (se puede elegir un lugar de la web y se completan dirección y coordenadas), fecha, hora, precio, inscripción y descripción; opcional: organiza, teléfono, Instagram, web, foto, destacado.
   - **Otra fecha de una actividad:** elige la actividad, fecha, hora, punto de encuentro y cupo. No deja repetir una fecha ya cargada ni cargar fechas pasadas.

   La página agrega las filas a la planilla guardada (Lugares y Agenda, con la observación "Carga rápida desde el panel") y la pasa por el mismo importador, así que tiene las mismas revisiones. Lo publicado queda en la planilla, y la próxima vez que bajen la planilla ya viene incluido. Si después suben una planilla vieja, el panel avisa que lo cargado rápido se perdería.

La primera vez que se usa la carga rápida (o si la versión publicada no tiene planilla guardada), el formulario pide elegir la planilla ahí mismo; después queda guardada y no la pide más.

**Dos personas a la vez:** si alguien publica mientras otra persona prepara un cambio, la segunda publicación se rechaza con un aviso y el panel trae lo nuevo. Así nadie borra sin querer lo que cargó otro.

**Respaldo:** `catalogo.json` es lo que muestra la web si nunca se publicó nada desde el panel. Conviene actualizarlo cada tanto: en el panel, al pie, "copia del catálogo en JSON", y reemplazar `catalogo.json` en el repositorio.

**Reservas:** las actividades gratis con cupo que se cargan desde el panel se piden por WhatsApp (la base de inscripciones todavía no las conoce). Ver SEGURIDAD.md, punto 24.

**Accesos directos** (los usa la guía de Turismo): `cargar.html#evento` abre el formulario de evento nuevo, `#fecha` el de otra fecha, y `#planilla`, `#subir` e `#historial` llevan a esa parte. Si no se entró, van ahí después de poner la clave.

**Al cambiar `libs/importador.js`:** cambiar el número de `?v=` en `cargar.html` (línea del `<script src="libs/importador.js?v=...">`).

**Para activarlo (una vez):**
1. Correr `supabase/temporada.sql` (PARTE 8). Si ya estaba corrido, correrlo de nuevo cuando haya cambios en la PARTE 8 (por ejemplo, la descarga de la planilla y la carga rápida, del 10/11).
2. Cargar la clave del panel, de 14 caracteres o más:
   ```sql
   insert into public.carga_acceso (id, clave_hash)
   values (1, extensions.crypt('ELEGIR-OTRA-CLAVE', extensions.gen_salt('bf', 10)))
   on conflict (id) do update set clave_hash = excluded.clave_hash;
   ```
3. Pasarle a Turismo el link (`https://…/cargar.html`), la clave (por separado) y la planilla `datos/48 HS - Carga de datos.xlsx`, que es la que tienen que usar siempre.

Quien tiene la clave puede cambiar todo lo que muestra la web: dársela solo a quien carga datos y cambiarla si alguien deja el equipo. El importador de Python sigue sirviendo para regenerar `catalogo.json` (el respaldo). Si se cambia una regla de importación, cambiarla en los dos archivos.

## Agenda Ciudad: los eventos del WordPress de Turismo

Turismo carga la agenda semanal con su propio "Cargador Agenda Ciudad" en su WordPress (`agenda.turismoposadas.tur.ar`). La web 48h la toma de ahí sola: **no hay que cargar dos veces.**

- **Cómo funciona:** cada 30 minutos la base pide a la API pública de su WordPress los eventos publicados de los próximos 60 días y guarda una copia (`temporada.sql`, PARTE 9; tarea `48hs-agenda-wp` en `cron.sql`). La web lee esa copia con `agenda_externa()`. **No usa contraseñas** y los visitantes nunca se conectan a su WordPress.
- **Lo que se ve:** cada evento sale en la agenda con su flyer (entero si es vertical), recinto, día y hora, categoría y "Más info" a la página oficial del evento. Los eventos de varios días salen en cada día (hasta 30).
- **Categorías:** las de su WordPress se pasan a las de la web (`CATS_WP` en `index.html`). Música, shows y folklore van a **Noche** si empiezan a las 21 o más tarde; si no, a **Cultura**. Lo que no tiene equivalente va a Cultura.
- **Mapa:** su WordPress no tiene coordenadas de los recintos. Se toman de nuestro catálogo: los recintos de `RECINTOS_WP` (IMAX, Parque del Conocimiento, Sala Tempo, Mandové Pedrozo, Parque Paraguayo) y los que tengan el mismo nombre que un lugar nuestro. Los demás salen en la agenda pero no en el mapa. Para sumar uno: agregar `id del recinto en WordPress: 'id del lugar nuestro'` en `RECINTOS_WP`.
- **Sin duplicados:** si un evento también está en el catálogo propio con el mismo nombre y la misma fecha, se muestra solo el propio.
- **Si su sitio se cae:** queda la última copia buena. Lo que borran o despublican en WordPress desaparece en la próxima sincronización completa.
- **Controlarlo:** `supabase/salud.sql` tiene la fila "Agenda Ciudad (WordPress de Turismo)" con la última actualización, la cantidad de eventos y el error, si hay. Para forzar una sincronización: `select public.agenda_externa_sync();` dos veces, con un minuto de diferencia (la primera pide, la segunda guarda).
- **Apagarlo:** `agendaWP: false` en `CONFIG` (`index.html`) y `select cron.unschedule('48hs-agenda-wp');`.

**Para activarlo:** correr `temporada.sql` entero, habilitar **pg_net** (Database → Extensions) si no está, y correr `cron.sql`.

## Asistente con IA: "Preguntale a Turi" (Gemini)

En la Agenda hay un cuadro donde el turista escribe qué tiene ganas de hacer ("algo para ir con chicos", "¿qué hago hoy a la noche?") y la IA le sugiere de 1 a 4 eventos o lugares **de lo que está cargado** (catálogo publicado + Agenda Ciudad de los próximos 7 días). Las sugerencias salen como tarjetas que abren la ficha.

**Turi** es la cara del asistente: un tucán de la selva misionera (dibujo propio, `marca/turi.svg`). Responde en primera persona y con voseo. Para cambiar el dibujo alcanza con reemplazar ese archivo por otro SVG cuadrado; para cambiar su forma de hablar, editar `INSTRUCCIONES` en `supabase/functions/asistente/index.ts` y volver a desplegar la función.

**Turi en el mapa.** En la pantalla del mapa, abajo a la derecha, está Turi chiquito. Cada tanto salta y dice una frase en un globo. Esas frases **no son IA** (no gastan nada): están escritas en `TURI_FRASES` dentro de `index.html`, en español y portugués, y se eligen según la hora, el clima y si hay eventos hoy. Algunas, al tocarlas, llevan a "Preguntale a Turi", a la agenda o a Filtros. Reglas para no molestar: la primera a los 12 segundos, después como mínimo cada 100 segundos, hasta 5 por visita; no habla si hay una ficha, un panel o un menú abierto; si la persona cierra el globo dos veces, no habla más ese día. Esos números se cambian en `CONFIG.turi`; `turi: false` lo saca del mapa. Para agregar una frase, copiar una línea de `TURI_FRASES` con un `id` nuevo.

**Cómo está armado (y por qué no gasta de más):**
- La web **no tiene la clave de Gemini**. Llama a la función `asistente` de Supabase (`supabase/functions/asistente/index.ts`), que tiene la clave como secreto, arma la lista de eventos y le pregunta a Gemini.
- Modelo: `gemini-3.1-flash-lite` (el más barato), sin "razonamiento", respuesta de hasta 450 tokens. Cada pregunta cuesta **unos USD 0,002**.
- **Topes** (tabla `ajustes`, se cambian sin tocar código):

| Ajuste | Valor | Qué hace |
|---|---|---|
| `ia_activa` | 1 | 0 = apagado al instante (la web sugiere con lo que ya sabe, sin IA) |
| `ia_por_persona_dia` | 6 | preguntas por teléfono por día |
| `ia_por_red_dia` | 30 | preguntas por día desde una misma IP (hotel, datos móviles) |
| `ia_por_dia` | 300 | preguntas por día entre todos: **el gasto máximo es unos USD 0,60 por día** (≈ USD 18 por mes si se llenara todos los días) |
| `ia_por_minuto` | 20 | entre todos; frena a un bot |
| `ia_cache_horas` | 6 | una pregunta repetida (las rápidas, por ejemplo) se responde de la memoria: gratis y no gasta cupo |

  Ejemplos: `update public.ajustes set valor = 0 where clave = 'ia_activa';` (apagar) · `update public.ajustes set valor = 500 where clave = 'ia_por_dia';`
- Cuando no hay respuesta (tope, demanda, apagado, sin conexión), la web lo dice y muestra sugerencias propias, calculadas en el teléfono.
- Solo responde desde la web oficial (`ORIGENES`). Pedidos de otros sitios o de scripts sueltos se rechazan.
- No se guardan preguntas ni IPs: solo contadores con hash (se borran al día siguiente) y las respuestas por 6 horas.
- Controlarlo: `salud.sql` tiene la fila "Asistente Turi hoy", y el reporte mensual muestra "Preguntas a Turi".

**Para activarlo (una sola vez, unos 15 minutos):**

1. **Clave de Gemini.** Entrar a https://aistudio.google.com/apikey con la cuenta de Google de ApexTech o de Turismo → **Create API key**. Copiarla (empieza con `AIza…`). **No pegarla en ningún archivo, ni en el chat, ni en el repo.**
2. **Activar facturación en esa clave** (en AI Studio, "Set up billing" al lado de la clave). Es importante: en el plan gratis Google puede usar las preguntas para mejorar sus productos, y la política de privacidad dice que no. Con facturación no las usa, y el gasto lo controlan nuestros topes.
3. **Alerta de gasto en Google Cloud:** https://console.cloud.google.com/billing → Presupuestos y alertas → Crear presupuesto de USD 10 por mes, con avisos al 50, 90 y 100 %. (La alerta avisa por email; el freno real son los topes de arriba.)
4. **Base:** correr `supabase/temporada.sql` entero (crea la PARTE 10).
5. **Función:** Supabase → **Edge Functions** → **Deploy a new function** → **Via Editor**. Nombre: `asistente` (exacto). Borrar el ejemplo, pegar todo `supabase/functions/asistente/index.ts` y tocar **Deploy**.
6. En la función recién creada → **Details** (o Settings): **desactivar "Enforce JWT verification" / "Verify JWT"** y guardar. Si queda activado, la web recibe error 401 y muestra "no está disponible".
7. **Secretos:** Edge Functions → **Secrets** → agregar:
   - `GEMINI_API_KEY` = la clave del paso 1.
   - `IA_SAL` = un texto largo al azar. Para generarlo: SQL Editor → `select encode(gen_random_bytes(24), 'hex');` y copiar el resultado.
   - (cuando haya dominio propio) `ORIGENES` = `https://mundial-mapa-posadas.vercel.app,https://el-dominio-nuevo` (separados por coma).
8. Subir la web nueva (`index.html`, `sw.js`, `privacidad.html`). Entrar a la Agenda, tocar "¿Qué hago hoy a la noche?" y ver que responde.

**Si algo no anda:** Supabase → Edge Functions → asistente → **Logs**. "Gemini HTTP 400/403" = clave mal copiada o sin facturación; "HTTP 429" = cupo de Google; "apagado" en la web = falta `GEMINI_API_KEY` o `ia_activa` está en 0.

**Cambiar la clave** (si se filtró o cada tanto): crear una nueva en AI Studio, reemplazar el secreto `GEMINI_API_KEY` y borrar la vieja en AI Studio. No hay que tocar la web.

**Apagarlo del todo:** `ia_activa = 0` en la base (inmediato) y, si es para siempre, `asistente: false` en `CONFIG` (`index.html`).

## Cargar los datos de la Muni

1. La Muni completa `48 HS - Carga de datos.xlsx`:
   - una fila por lugar, con X en todas sus categorías;
   - las fechas de paseos y eventos, en la hoja Agenda;
   - **Video (link):** opcional, sale al tocar el lugar en el mapa. Sirve YouTube (también Shorts), reel de Instagram, TikTok, Vimeo, Google Drive público o un .mp4;
   - **Destacado:** "Sí" en las actividades más importantes. Salen en el panel de la izquierda del mapa, abierto al entrar; si no hay ninguna marcada, el panel muestra las próximas.
2. Cuando la devuelven, corrés:
   ```
   pip install openpyxl
   python herramientas/importar_catalogo.py "48 HS - Carga de datos.xlsx" -o catalogo.json
   ```
   - Si mandan CSV en lugar del .xlsx: `--lugares Lugares.csv --agenda Agenda.csv`.
   - Avisos: el importador lista lo que hay que corregir (coordenadas fuera de Misiones, teléfonos raros, IDs de la Agenda que no existen, enlaces de video que no reconoce).
   - Errores: si hay un ID repetido, no genera nada.
   - Fechas viejas: las que ya pasaron se ignoran solas.
3. Subís `catalogo.json` a Vercel. No hace falta tocar `index.html`.

La app junta el catálogo con la lista que trae adentro:

- **El catálogo manda:** lo que no está o tiene Publicar = No, no se muestra.
- **De la lista interna hereda** fotos, textos y traducciones de los lugares que ya existían, si la planilla no los trae.
- **Actividades sin fechas próximas:** no se muestran, salvo que ya tuvieran un horario fijo en la app.
- **Categorías y subcategorías nuevas:** se agregan en `CATEGORIAS` de `importar_catalogo.py` y de `index.html`, con su texto en `TEXTOS` (español y portugués). Así se sumó **Café y té** (subcategoría de Gastronomía): en la planilla se escribe "Café y té" en Subcategorías; también se acepta "Cafés", "Cafetería" o "Té".
- **Subcategorías con ícono propio:** las que están en `SUB_PROPIAS` de `index.html` (hoy, Café y té: taza y color caramelo) tienen su propio pin en el mapa y aparecen como opción en "¿Qué estás buscando hoy?", al lado de su categoría.
- **Horarios:** si se escriben como "L a V 8-12.30 / 17-20 S 9-13", la web los muestra "Lun a Vie 8 a 12:30 y 17 a 20 hs · Sáb 9 a 13 hs", y los traduce al portugués. Los días son L, M (martes), Mi, J, V, S y D. Lo que no siga ese formato ("Todos los días · Entrada libre") se muestra tal cual.
- **Coordenadas:** los links cortos de Google Maps (maps.app.goo.gl) no traen las coordenadas adentro: hay que copiarlas en la columna Coordenadas (en Google Maps, tocar el lugar y copiar los números que aparecen arriba).

## Enlaces útiles

- **Mostrar el reporte a Turismo hoy:** `https://TU-DOMINIO/reporte.html?demo=1`
- **App en portugués:** `https://TU-DOMINIO/?lang=pt`
- **Carteles con QR:** cada cartel lleva su propio origen, así el reporte muestra cuál funciona.
  - `https://TU-DOMINIO/?src=qr-costanera`
  - `https://TU-DOMINIO/?src=qr-terminal&lang=pt` (por ejemplo, en la terminal, para turistas brasileños)
  - Solo minúsculas, números y guiones.
- **Abrir un lugar directo:** `https://TU-DOMINIO/?lugar=catamaran`

## Emails (todavía no: no hay dominio)

Para mandar emails a cualquier persona hace falta un dominio propio verificado en Resend. Con la dirección `.vercel.app` no se puede, porque ese dominio es de Vercel y no se pueden cargar sus registros. Mientras no haya dominio (`CONFIG.avisosEmail: false` en `index.html`):

- **Lista de espera:** va por WhatsApp a Turismo. La web arma el mensaje y no guarda nada en la base.
- **Recordatorio del día anterior:** apagado. La persona tiene el botón "Agregar al calendario".
- **Reporte mensual:** Turismo entra a `reporte.html` con la clave.
- **La tarea `48hs-avisos` de `cron.sql` no se programa.** Si quedó programada: `select cron.unschedule('48hs-avisos');`.

**Cuando haya dominio** (por ejemplo, comprado en Vercel):
1. En Resend, agregar el subdominio `avisos.` del dominio y copiar sus registros DNS en Vercel (Domains → DNS Records). Después, Verify.
2. Publicar la función `supabase/functions/avisos` y cargar sus datos secretos en Supabase: `RESEND_API_KEY`, `AVISOS_SECRET` (24 caracteres o más), `REMITENTE` (`48h Posadas <avisos@avisos.tu-dominio>`), `APP_URL` y, si se quiere el reporte mensual, `REPORTE_DESTINATARIOS` y `REPORTE_CLAVE`.
3. Guardar el mismo `AVISOS_SECRET` en el Vault como `avisos_secret` y correr la parte de avisos de `cron.sql`.
4. En `index.html`, poner `avisosEmail: true` (y `recordatorios: true` si se quieren).
5. En `privacidad.html`, volver a agregar la lista de espera por email, el recordatorio y a Resend como proveedor.

## Etapa Supabase (lo dejamos para el final)

1. **SQL:** en *SQL Editor*, correr `supabase/temporada.sql`. Incluye la PARTE 6 (personas que ingresan con nombre y email).
2. **Clave del reporte:** en el mismo editor, correr esto con la clave que elijas:
   ```sql
   insert into public.reporte_acceso (id, clave_hash)
   values (1, extensions.crypt('ELEGIR-UNA-CLAVE', extensions.gen_salt('bf', 10)))
   on conflict (id) do update set clave_hash = excluded.clave_hash;
   ```
3. **Emails (Resend):**
   - Crear una cuenta en Resend y verificar el dominio desde el que se va a enviar.
   - Sin dominio verificado, Resend solo deja mandar al email de la propia cuenta.
4. **Función `avisos`:**
   - Publicarla con `supabase functions deploy avisos --no-verify-jwt`. La función se protege con su propio secreto, no con el login de Supabase.
   - Cargar estos secretos en *Edge Functions → Secrets*:

     | Secreto | Valor |
     |---|---|
     | `AVISOS_SECRET` | Una cadena larga al azar (24 caracteres o más), la misma que se guarda en el Vault (paso 6) |
     | `RESEND_API_KEY` | La clave de Resend |
     | `REMITENTE` | `48 HS <avisos@tu-dominio>` |
     | `APP_URL` | `https://TU-DOMINIO/` |
     | `REPORTE_DESTINATARIOS` | Emails de Turismo, separados por coma |
     | `REPORTE_CLAVE` | La misma clave del paso 2 |
     | `INSCRIPCIONES_TABLA` | Nombre real de tu tabla de inscripciones (por defecto `inscripciones`) |
5. **Probar sin enviar nada:**
   ```
   curl -X POST "https://vqkjldyqgitzrhksiofd.supabase.co/functions/v1/avisos?tarea=todas&prueba=1" -H "Authorization: Bearer AVISOS_SECRET"
   ```
6. **Tareas programadas:**
   - Habilitar `pg_cron` y `pg_net` en *Database → Extensions*.
   - Guardar el secreto en el Vault, una sola vez y sin escribirlo en ningún archivo: `select vault.create_secret('EL-SECRETO', 'avisos_secret');`
   - Correr `supabase/cron.sql` tal cual (lee el secreto del Vault).
8. **Auditoría:** correr `supabase/auditoria.sql` en el SQL Editor y arreglar lo que diga FALLA (ver `SEGURIDAD.md`). Repetirla antes de cada temporada.
7. **Recordatorios del día anterior:**
   - Activar la PARTE 5 de `temporada.sql` con los nombres reales de tu tabla.
   - Después, en `index.html`, poner `recordatorios: true` en `CONFIG`. Así el texto de privacidad promete el aviso solo cuando de verdad se manda.

## Escalar (cuando haya más tráfico o se pase a planes pagos)

Los topes y plazos de la base están en la tabla `ajustes` (Supabase → Table Editor → `ajustes`, o con SQL). Se cambian sin tocar el código:

| Ajuste | Plan gratis | Con Supabase Pro | Qué hace |
|---|---|---|---|
| `eventos_por_minuto` | 600 | 3000 | Estadísticas por minuto de toda la web |
| `eventos_por_dia` | 50.000 | 300.000 | Estadísticas por día de toda la web |
| `eventos_por_sesion_dia` | 500 | 500 | Por visita |
| `dias_eventos` | 62 | 400 | Días con el detalle de cada evento (después queda el resumen del mes) |
| `dias_resumen` | 730 | 730 | Resúmenes mensuales (lo que promete la política) |
| `dias_visitantes`, `dias_lista_espera`, `dias_inscripciones` | 730, 7, 183 | igual | Plazos de la política de privacidad: si se cambian, cambiar también `privacidad.html` |

```sql
update public.ajustes set valor = 400 where clave = 'dias_eventos';
```

- **Cuánto ocupa la base:** el comando está al final de `temporada.sql`. Revisarlo una vez por semana en temporada.
- **La limpieza diaria** (`limpieza_diaria()`, programada en `cron.sql`) guarda el resumen de cada mes cerrado, borra el detalle viejo y aplica los plazos de la política. A mano: `select public.limpieza_diaria();`.
- **La web:** son archivos fijos servidos desde la red de Vercel, y el catálogo es un JSON. Aguanta mucho tráfico sin cambios. Lo que se mide en el plan gratis de Vercel es la transferencia (100 GB por mes, más de 100.000 visitas nuevas).
- **Catálogos grandes:** el mapa ya se probó con 5000 lugares (ver "Rendimiento").

## Cargar contenido en portugués

En la tabla `lugares` hay columnas nuevas que terminan en `_pt`. Las que queden vacías se muestran en castellano. El catálogo de respaldo que está dentro de `index.html` ya viene traducido.
