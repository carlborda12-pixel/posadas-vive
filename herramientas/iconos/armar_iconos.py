"""48 HS · íconos livianos

La web usaba la librería completa de íconos Phosphor: 6 estilos y más de
1.500 íconos (cerca de 500 KB por la red, de los que se usan unos 110).
Este script arma dos fuentes solo con los íconos que aparecen en la web y
las mete dentro de index.html (unos 25 KB, sin pedidos externos):

  - Phosphor-Light: línea fina, para toda la web (botones, pantallas, agenda).
  - Phosphor-Fill:  relleno, para lo que va sobre el mapa (pines, referencias,
                    servicios), donde los íconos son chicos.

Qué estilo se ve dónde lo decide el CSS de index.html (buscar "Estilo de
íconos"). En el código se puede seguir escribiendo class="ph ph-x" o
class="ph-fill ph-x": el dibujo es el mismo, cambia solo el trazo.

Cuándo correrlo: si se agrega un ícono nuevo (por ejemplo "ph-tent") en
index.html o en el importador. Si no se corre, ese ícono sale en blanco.

    npm install @phosphor-icons/web@2.1.2        (una sola vez, en cualquier carpeta)
    pip install fonttools brotli
    python herramientas/iconos/armar_iconos.py index.html --phosphor node_modules/@phosphor-icons/web/src
"""
import argparse, base64, io, re, sys
from pathlib import Path
from fontTools import subset
from fontTools.ttLib import TTFont

FUENTES = {  # familia → (carpeta, archivo)
    'Phosphor-Light': ('light', 'Phosphor-Light.woff2'),
    'Phosphor-Fill':  ('fill',  'Phosphor-Fill.woff2'),
}
CLASES = ('ph', 'ph-fill', 'ph-bold', 'ph-light')   # cualquiera de estas marca un ícono
INI, FIN = '/* ICONOS:inicio (lo arma herramientas/iconos/armar_iconos.py) */', '/* ICONOS:fin */'
BASE = ('{sel}{{speak:never;font-style:normal;font-weight:normal;font-variant:normal;text-transform:none;'
        'line-height:1;letter-spacing:0;-webkit-font-smoothing:antialiased;-moz-osx-font-smoothing:grayscale}}')

def nombres(textos):
    vistos = set()
    for t in textos:
        for n in re.findall(r'(?<![\w-])ph-([a-z0-9]+(?:-[a-z0-9]+)*)', t):
            if n not in ('fill', 'bold', 'light'): vistos.add(n)
    return vistos

def codigos(css):
    # el código de cada ícono es el mismo en todos los estilos de Phosphor
    return {m.group(1): m.group(2) for m in re.finditer(r'\.ph-light\.ph-([a-z0-9-]+):before\s*\{\s*content:\s*"\\([0-9a-f]+)"', css)}

def armar(index, phosphor, extras):
    html = Path(index).read_text(encoding='utf-8')
    # lo ya armado no cuenta: así un ícono que se dejó de usar sale de la fuente
    propio = re.sub(re.escape(INI) + '.*?' + re.escape(FIN), '', html, flags=re.S)
    textos = [propio] + [Path(e).read_text(encoding='utf-8') for e in extras if Path(e).exists()]
    usados = nombres(textos)
    mapa = codigos((Path(phosphor) / 'light' / 'style.css').read_text(encoding='utf-8'))
    lista = sorted(n for n in usados if n in mapa)
    desconocidos = usados - set(lista)
    css_out, total = [], 0
    for familia, (carpeta, archivo) in FUENTES.items():
        f = TTFont(str(Path(phosphor) / carpeta / archivo))
        op = subset.Options(); op.flavor = 'woff2'; op.layout_features = []; op.name_IDs = []; op.notdef_outline = False
        op.hinting = False; op.desubroutinize = True
        s = subset.Subsetter(op); s.populate(unicodes=[int(mapa[n], 16) for n in lista]); s.subset(f)
        buf = io.BytesIO(); f.flavor = 'woff2'; f.save(buf); datos = buf.getvalue(); total += len(datos)
        css_out.append(f'@font-face{{font-family:"{familia}";src:url(data:font/woff2;base64,{base64.b64encode(datos).decode()}) format("woff2");font-display:block}}')
    sel = ','.join('.' + c for c in CLASES)
    css_out.append(BASE.format(sel=sel))
    css_out.append(''.join(f':is({sel}).ph-{n}:before{{content:"\\{mapa[n]}"}}' for n in lista))
    bloque = INI + '\n' + '\n'.join(css_out) + '\n' + FIN
    if INI not in html:
        sys.exit('No encontré la marca ' + INI + ' en ' + index)
    html = html[:html.index(INI)] + bloque + html[html.index(FIN) + len(FIN):]
    Path(index).write_text(html, encoding='utf-8')
    print(f'{len(lista)} íconos, {total/1024:.1f} KB de fuentes')
    if desconocidos: print('Nombres que no son íconos de Phosphor (revisar si son errores de tipeo):', ', '.join(sorted(desconocidos)))

if __name__ == '__main__':
    a = argparse.ArgumentParser(); a.add_argument('index'); a.add_argument('--phosphor', required=True)
    a.add_argument('--extra', nargs='*', default=['catalogo.json', 'herramientas/importar_catalogo.py'])
    x = a.parse_args(); armar(x.index, x.phosphor, x.extra)
