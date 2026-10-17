"""Arma portada.html (1200x630) para la vista previa al compartir el link de 48 HS.
Necesita las tipografías: npm install @fontsource/fraunces @fontsource/plus-jakarta-sans
y el catalogo.json (para los colores de los puntos). Después se captura con un navegador
(Playwright o captura de pantalla a 1200x630) y se guarda como portada.jpg."""
import json, math, base64
cat = json.load(open('catalogo.json', encoding='utf-8'))
COL = {'cultura':'#e8c37e','naturaleza':'#5bbf6c','paseos':'#f5943d','nautico':'#4aa8f0','gastronomia':'#e2574c','nocturna':'#b47af6','ninos':'#f06fb0','excursiones':'#9fb3c8'}
pts = [(x['coords'][0], x['coords'][1], COL.get((x.get('cats') or ['cultura'])[0], '#e8c37e')) for x in cat['lugares'] if x.get('coords')]
# solo la ciudad (sin los muy alejados)
pts = [p for p in pts if -27.43 < p[0] < -27.33 and -55.95 < p[1] < -55.84]
la0, la1 = min(p[0] for p in pts), max(p[0] for p in pts); lo0, lo1 = min(p[1] for p in pts), max(p[1] for p in pts)
k = math.cos(math.radians(27.37))
W, H = 1200, 630
# los puntos ocupan la mitad derecha, como el mapa de la app
# Puntos decorativos a los costados, con los colores de los lugares reales (misma proporción por categoría)
import random
rnd = random.Random(7)
colores = [c for _, _, c in pts]
rnd.shuffle(colores)
P = []
def libre(x, y):
    # fuera del bloque del texto (centro) y debajo del río
    return not (300 < x < 900 and 95 < y < 575) and y > 105
while len(P) < 54:
    x, y = rnd.uniform(30, 1170), rnd.uniform(110, 605)
    if not libre(x, y): continue
    if all(math.hypot(x - a, y - b) > 34 for a, b, _, _ in P):
        P.append([x, y, colores[len(P) % len(colores)], rnd.choice([8, 9, 10, 11])])
dots = ''.join(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="{c}" stroke="#fdf9f2" stroke-opacity=".85" stroke-width="2.4"/>' for x, y, c, r in P)
rio = '<path d="M-40 70 C 180 20, 330 95, 520 55 S 860 -5, 1010 40 S 1180 95, 1260 60" fill="none" stroke="#37b5a4" stroke-opacity=".38" stroke-width="46" stroke-linecap="round"/>' \
      '<path d="M-40 70 C 180 20, 330 95, 520 55 S 860 -5, 1010 40 S 1180 95, 1260 60" fill="none" stroke="#7fdccd" stroke-opacity=".35" stroke-width="3"/>'
f = lambda n: base64.b64encode(open(f'node_modules/@fontsource/{n}', 'rb').read()).decode()
html = f'''<!doctype html><html><head><meta charset="utf-8"><style>
@font-face {{ font-family: Fraunces; font-weight: 700; src: url(data:font/woff2;base64,{f('fraunces/files/fraunces-latin-700-normal.woff2')}); }}
@font-face {{ font-family: Fraunces; font-weight: 600; font-style: italic; src: url(data:font/woff2;base64,{f('fraunces/files/fraunces-latin-600-italic.woff2')}); }}
@font-face {{ font-family: Jakarta; font-weight: 700; src: url(data:font/woff2;base64,{f('plus-jakarta-sans/files/plus-jakarta-sans-latin-700-normal.woff2')}); }}
@font-face {{ font-family: Jakarta; font-weight: 800; src: url(data:font/woff2;base64,{f('plus-jakarta-sans/files/plus-jakarta-sans-latin-800-normal.woff2')}); }}
* {{ margin: 0; box-sizing: border-box; }}
body {{ width: {W}px; height: {H}px; overflow: hidden; background: #0f0b08; font-family: Jakarta, sans-serif; color: #fdf9f2; position: relative; }}
.cielo {{ position: absolute; inset: 0; background:
   radial-gradient(ellipse 80% 55% at 50% 112%, rgba(245,148,61,.6), rgba(226,87,76,.25) 45%, transparent 75%),
   radial-gradient(ellipse 50% 40% at 10% 0%, rgba(232,195,126,.10), transparent 70%); }}
.rio {{ position: absolute; left: -10%; right: -10%; bottom: -120px; height: 260px; border-radius: 50%;
   background: linear-gradient(to bottom, rgba(55,181,164,.0), rgba(55,181,164,.16) 40%, rgba(15,11,8,.0)); filter: blur(6px); }}
svg {{ position: absolute; inset: 0; }}
.texto {{ position: absolute; left: 0; right: 0; top: 0; bottom: 0; display: flex; flex-direction: column; justify-content: center; align-items: center; text-align: center; padding-top: 18px; }}
.marca {{ display: flex; align-items: center; gap: 12px; font-weight: 800; font-size: 19px; letter-spacing: 3px; text-transform: uppercase; color: #e8c37e; }}
.pin {{ width: 52px; height: 52px; border-radius: 14px; background: #1a130d; border: 2px solid rgba(232,195,126,.45); display: flex; align-items: center; justify-content: center; }}
h1 {{ font-family: Fraunces, serif; font-weight: 700; font-size: 168px; line-height: .9; margin-top: 18px; letter-spacing: -3px; }}
h1 em {{ font-style: italic; font-weight: 600; color: #f5943d; }}
p {{ margin-top: 22px; font-size: 27px; line-height: 1.3; color: #e9dccb; font-weight: 700; max-width: 540px; }}
.chips {{ display: flex; gap: 10px; margin-top: 26px; justify-content: center; }}
.chip {{ padding: 10px 18px; border-radius: 999px; background: rgba(15,11,8,.7); border: 1.5px solid rgba(255,255,255,.14); font-size: 20px; font-weight: 800; color: #fdf9f2; display: flex; align-items: center; gap: 9px; }}
.chip i {{ width: 12px; height: 12px; border-radius: 50%; display: inline-block; }}
.velo {{ position: absolute; inset: 0; background: radial-gradient(ellipse 34% 50% at 50% 54%, rgba(15,11,8,.85) 0%, rgba(15,11,8,.6) 60%, rgba(15,11,8,0) 100%); }}
</style></head><body>
<div class="cielo"></div><div class="rio"></div>
<svg width="{W}" height="{H}" viewBox="0 0 {W} {H}">{rio}{dots}</svg>
<div class="velo"></div>
<div class="texto">
  <div class="marca"><span class="pin"><svg width="30" height="30" viewBox="0 0 64 64" style="position:static"><path d="M32 6c-10 0-18 8-18 18 0 13.5 18 34 18 34s18-20.5 18-34c0-10-8-18-18-18zm0 24.6a6.6 6.6 0 110-13.2 6.6 6.6 0 010 13.2z" fill="#e8c37e"/></svg></span>Guía viva de Posadas</div>
  <h1>48 <em>HS</em></h1>
  <p>Qué hacer en Posadas: agenda, paseos guiados y el mapa en tu celular.</p>
  <div class="chips"><span class="chip"><i style="background:#f5943d"></i>Agenda</span><span class="chip"><i style="background:#4aa8f0"></i>Mapa</span><span class="chip"><i style="background:#5bbf6c"></i>Paseos</span></div>
</div>
</body></html>'''
open('portada.html', 'w', encoding='utf-8').write(html)
print(len(pts), 'puntos')
