"""48h Posadas · portada para compartir el link (portada.jpg, 1200x630)

Arma la imagen que sale al compartir la web por WhatsApp, Facebook o X,
con la portada de la marca: el skyline de la costanera, el logo 48h Posadas,
la frase de la plataforma y "Creado por Posadas Turismo".

    pip install playwright && python -m playwright install chromium
    npm install @fontsource/be-vietnam-pro@5.0.8
    python herramientas/portada/armar_portada.py          (desde la carpeta del proyecto)
"""
import base64, pathlib
from playwright.sync_api import sync_playwright

RAIZ = pathlib.Path('.')
FUENTES = RAIZ / 'node_modules/@fontsource/be-vietnam-pro/files'
b64 = lambda p: base64.b64encode(pathlib.Path(p).read_bytes()).decode()
fuente = lambda w: f"@font-face{{font-family:'BVP';font-weight:{w};src:url(data:font/woff2;base64,{b64(FUENTES / f'be-vietnam-pro-latin-{w}-normal.woff2')})}}"

html = f'''<!doctype html><html><head><meta charset="utf-8"><style>
{fuente(300)}{fuente(700)}
* {{ margin: 0; box-sizing: border-box; }}
body {{ width: 1200px; height: 630px; overflow: hidden; position: relative; font-family: BVP, sans-serif; color: #f7f7f7;
        background: #0d1a22 url(data:image/jpeg;base64,{b64(RAIZ / 'marca/inicio.jpg')}) 50% 58% / cover no-repeat; }}
.sombra {{ position: absolute; inset: 0; background: linear-gradient(to bottom, rgba(10,18,24,.45), rgba(10,18,24,0) 45%, rgba(8,10,12,.55) 100%); }}
.centro {{ position: absolute; left: 0; right: 0; top: 92px; text-align: center; }}
.centro img {{ width: 560px; filter: drop-shadow(0 2px 14px rgba(0,0,0,.35)); }}
.centro p {{ margin: 22px auto 0; max-width: 760px; font-weight: 300; font-size: 27px; line-height: 1.4; text-shadow: 0 1px 12px rgba(0,0,0,.6); }}
.centro b {{ font-weight: 700; }}
.creado {{ position: absolute; left: 0; right: 0; bottom: 34px; display: flex; align-items: center; justify-content: center; gap: 14px; font-weight: 300; font-size: 19px; color: rgba(247,247,247,.85); }}
.creado img {{ width: 150px; }}
</style></head><body><div class="sombra"></div>
<div class="centro"><img src="data:image/svg+xml;base64,{b64(RAIZ / 'marca/logo-48h.svg')}">
<p>Planificá tus próximas <b>48 horas en Posadas</b> y descubrí todo lo que la ciudad tiene para ofrecerte.</p></div>
<div class="creado">Creado por <img src="data:image/svg+xml;base64,{b64(RAIZ / 'marca/logo-turismo.svg')}"></div>
</body></html>'''

with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page(viewport={'width': 1200, 'height': 630})
    pg.set_content(html); pg.wait_for_timeout(500)
    pg.screenshot(path=str(RAIZ / 'portada.jpg'), type='jpeg', quality=86)
    b.close()
print('portada.jpg lista (1200x630)')
