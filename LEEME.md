# PosadasVive · temporada de verano

## Cómo queda el repositorio

```
posadasvive/
├── index.html               ← la app                      (se publica)
├── sw.js                    ← modo sin conexión            (se publica)
├── catalogo.json            ← lugares de la Muni           (se publica)
├── reporte.html             ← reporte para Turismo         (se publica)
├── manifest.webmanifest     ← sin cambios                  (se publica)
├── iconos/                  ← los íconos que ya tenés      (se publica)
├── .vercelignore            ← lo que NO se publica
├── LEEME.md
├── herramientas/
│   └── importar_catalogo.py
├── supabase/
│   ├── temporada.sql
│   ├── cron.sql
│   └── functions/avisos/index.ts
└── datos/
    └── PosadasVive - Carga de datos.xlsx
```

Con la planilla en `datos/`, el importador se corre así:
`python herramientas/importar_catalogo.py "datos/PosadasVive - Carga de datos.xlsx" -o catalogo.json`

`.vercelignore` evita que se publiquen `herramientas/`, `supabase/`, `datos/` y la planilla. Es importante por `cron.sql`: cuando le pegues el secreto, ese archivo no puede quedar visible en la web.

## Qué se sube ahora (Vercel)

| Archivo | Qué es |
|---|---|
| `index.html` | La app |
| `sw.js` | Modo sin conexión (versión `pv-2026-10-17-8`) |
| `reporte.html` | Reporte de uso para la Casa de Turismo |
| `catalogo.json` | Los lugares de la planilla de la Muni (lo genera el importador) |
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

## Al entrar a la web

- **"¿Qué estás buscando hoy?"**: después de la pantalla de inicio, cada vez. Elegir una categoría filtra el mapa; las que no tienen lugares en el mapa (excursiones) abren la lista en la Agenda. Los enlaces directos a un lugar no la muestran.
- **Novedades de la versión**: una vez por versión, a quien ya había usado la web en ese teléfono (a quien entra por primera vez no le sale). Se vuelven a ver con el enlace "Novedades" al pie de la Agenda.
- **En cada actualización**: en `index.html`, en `NOVEDADES`, se reemplaza la lista por lo nuevo (no se acumula) y se cambia `version`. Los ítems marcados `'equipo'` solo los ve el equipo de Turismo.
- **Equipo de Turismo**: abrir una vez `?equipo=turismo` en cada teléfono. Ven también las novedades internas (planilla) y sus visitas no cuentan en el reporte. Se desactiva con `?equipo=no`.

## Cargar los datos de la Muni

1. La Muni completa `PosadasVive - Carga de datos.xlsx`:
   - una fila por lugar, con X en todas sus categorías;
   - las fechas de paseos y eventos, en la hoja Agenda;
   - **Video (link):** opcional, sale al tocar el lugar en el mapa. Sirve YouTube (también Shorts), reel de Instagram, TikTok, Vimeo, Google Drive público o un .mp4;
   - **Destacado:** "Sí" en las actividades más importantes. Salen en el panel de la izquierda del mapa, abierto al entrar; si no hay ninguna marcada, el panel muestra las próximas.
2. Cuando la devuelven, corrés:
   ```
   pip install openpyxl
   python herramientas/importar_catalogo.py "PosadasVive - Carga de datos.xlsx" -o catalogo.json
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
- **Categorías nuevas:** si la Muni pide una (por ejemplo "Cafés"), se agrega en `CATEGORIAS` de `importar_catalogo.py` y de `index.html`, con su texto en `TEXTOS`.

## Enlaces útiles

- **Mostrar el reporte a Turismo hoy:** `https://TU-DOMINIO/reporte.html?demo=1`
- **App en portugués:** `https://TU-DOMINIO/?lang=pt`
- **Carteles con QR:** cada cartel lleva su propio origen, así el reporte muestra cuál funciona.
  - `https://TU-DOMINIO/?src=qr-costanera`
  - `https://TU-DOMINIO/?src=qr-terminal&lang=pt` (por ejemplo, en la terminal, para turistas brasileños)
  - Solo minúsculas, números y guiones.
- **Abrir un lugar directo:** `https://TU-DOMINIO/?lugar=catamaran`

## Etapa Supabase (lo dejamos para el final)

1. **SQL:** en *SQL Editor*, correr `supabase/temporada.sql`.
2. **Clave del reporte:** en el mismo editor, correr esto con la clave que elijas:
   ```sql
   insert into public.reporte_acceso (id, clave_hash)
   values (1, extensions.crypt('ELEGIR-UNA-CLAVE', extensions.gen_salt('bf')))
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
     | `AVISOS_SECRET` | Una cadena larga al azar, la misma que va en `cron.sql` |
     | `RESEND_API_KEY` | La clave de Resend |
     | `REMITENTE` | `PosadasVive <avisos@tu-dominio>` |
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
   - Pegar el secreto en `supabase/cron.sql` y correrlo.
7. **Recordatorios del día anterior:**
   - Activar la PARTE 5 de `temporada.sql` con los nombres reales de tu tabla.
   - Después, en `index.html`, poner `recordatorios: true` en `CONFIG`. Así el texto de privacidad promete el aviso solo cuando de verdad se manda.

## Cargar contenido en portugués

En la tabla `lugares` hay columnas nuevas que terminan en `_pt`. Las que queden vacías se muestran en castellano. El catálogo de respaldo que está dentro de `index.html` ya viene traducido.
