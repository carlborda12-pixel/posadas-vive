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
| `sw.js` | Modo sin conexión (versión `pv-2026-11-10-1`) |
| `reporte.html` | Reporte de uso para la Casa de Turismo |
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
