"""48h Posadas · mete los logos y las fotos de la marca dentro de index.html

Así la web se ve completa aunque se abra como archivo suelto (por ejemplo,
mandado por WhatsApp) o si falta subir la carpeta marca/. Las fuentes
originales quedan en marca/; este script las achica y las incrusta.

Cuándo correrlo: si se cambia algún archivo de marca/ (por ejemplo, una
foto de portada en mejor resolución con el mismo nombre).

    pip install pillow
    python herramientas/marca/incrustar_marca.py index.html
"""
import base64, io, re, sys
from pathlib import Path
from PIL import Image

INI, FIN = '/* MARCA:inicio (lo arma herramientas/marca/incrustar_marca.py) */', '/* MARCA:fin */'
RAIZ = Path(__file__).resolve().parents[2]
M = RAIZ / 'marca'

def svg(nombre):
    return 'data:image/svg+xml;base64,' + base64.b64encode((M / nombre).read_bytes()).decode()

def jpg(nombre, ancho, alto=None, calidad=76, foco=(0.5, 0.5)):
    """Achica (y si se pide alto, recorta alrededor del foco) y devuelve un data URI."""
    im = Image.open(M / nombre).convert('RGB')
    if alto:
        prop = ancho / alto
        w, h = im.size
        if w / h > prop:
            nw = int(h * prop); x = int((w - nw) * foco[0]); im = im.crop((x, 0, x + nw, h))
        else:
            nh = int(w / prop); y = int((h - nh) * foco[1]); im = im.crop((0, y, w, y + nh))
        im = im.resize((ancho, alto), Image.LANCZOS)
    elif im.width > ancho:
        im = im.resize((ancho, round(im.height * ancho / im.width)), Image.LANCZOS)
    b = io.BytesIO(); im.save(b, 'JPEG', quality=calidad, optimize=True, progressive=True)
    return 'data:image/jpeg;base64,' + base64.b64encode(b.getvalue()).decode()

def main(index):
    html = Path(index).read_text(encoding='utf-8')
    vars_ = {
        '--img-logo-48h': svg('logo-48h.svg'),
        '--img-logo-turismo': svg('logo-turismo.svg'),
        '--img-apextech': svg('apextech.svg'),
        # respaldo de la portada (la versión buena, marca/inicio-hd.webp, la carga la web desde el sitio)
        '--img-inicio': jpg('inicio-hd.jpg' if (M / 'inicio-hd.jpg').exists() else 'inicio.jpg', 1600, calidad=66),
        '--img-planificando': jpg('planificando.jpg', 400, 300, 62, foco=(0.5, 0.28)),
    }
    bloque = INI + '\n:root{' + ';'.join(f'{k}:url("{v}")' for k, v in vars_.items()) + '}\n' + FIN
    if INI not in html: sys.exit('No encontré la marca ' + INI)
    html = html[:html.index(INI)] + bloque + html[html.index(FIN) + len(FIN):]
    # favicon (no puede salir de una variable CSS)
    html = re.sub(r'<link rel="icon" href="[^"]*" type="image/svg\+xml">',
                  f'<link rel="icon" href="{svg("favicon.svg")}" type="image/svg+xml">', html, count=1)
    Path(index).write_text(html, encoding='utf-8')
    print('Marca incrustada:', ', '.join(f'{k} {len(v)//1024} KB' for k, v in vars_.items()))

if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else str(RAIZ / 'index.html'))
