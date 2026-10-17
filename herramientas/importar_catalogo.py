#!/usr/bin/env python3
"""
48 HS · importador de la planilla de la Municipalidad

Lee la planilla "48 HS - Carga de datos" (o sus hojas exportadas a
CSV), revisa los datos y genera catalogo.json, que la app carga sola.

Uso:
    python importar_catalogo.py planilla.xlsx
    python importar_catalogo.py planilla.xlsx -o ../catalogo.json
    python importar_catalogo.py --lugares Lugares.csv --agenda Agenda.csv

Para .xlsx hace falta openpyxl:  pip install openpyxl
Los CSV pueden venir separados por coma o por punto y coma (Excel en
castellano usa punto y coma).

Errores (no se genera nada): IDs repetidos, planilla sin hoja Lugares.
Avisos (se genera igual): coordenadas raras, teléfonos que no se
entienden, IDs de la Agenda que no existen, fechas mal escritas.
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import io
import json
import re
import sys
import unicodedata
from pathlib import Path

# ---------------------------------------------------------------------
# Categorías: las pestañas de la planilla original. Un lugar puede tener
# varias. Las subcategorías afinan la búsqueda dentro de una categoría.
# El orden y los ids tienen que coincidir con CATEGORIAS en index.html.
# ---------------------------------------------------------------------
CATEGORIAS = [
    # id, columna en la planilla, subcategorías válidas
    ('cultura',     'Cultura',       ['museos', 'salas']),
    ('naturaleza',  'Naturaleza',    []),
    ('paseos',      'Paseo guiado',  []),
    ('nautico',     'Náutico',       []),
    ('gastronomia', 'Gastronomía',   ['pescados', 'parrillas', 'vinos', 'internacional']),
    ('nocturna',    'Vida nocturna', ['bares', 'bowling']),
    ('ninos',       'Niños',         []),
    ('excursiones', 'Excursiones',   []),
]
SUBCATEGORIAS = {
    'museos': 'Museos', 'salas': 'Salas culturales',
    'pescados': 'Pescados', 'parrillas': 'Galetos y parrillas', 'vinos': 'Vinos', 'internacional': 'Internacional',
    'bares': 'Bares', 'bowling': 'Bowling',
}
# Formas en que puede venir escrita una subcategoría
SINONIMOS_SUB = {
    'museo': 'museos', 'museos': 'museos',
    'sala': 'salas', 'salas': 'salas', 'sala cultural': 'salas', 'salas culturales': 'salas',
    'pescado': 'pescados', 'pescados': 'pescados',
    'parrilla': 'parrillas', 'parrillas': 'parrillas', 'galeto': 'parrillas', 'galetos': 'parrillas',
    'galetos y parrillas': 'parrillas', 'galetos parrillas': 'parrillas',
    'vino': 'vinos', 'vinos': 'vinos',
    'internacional': 'internacional',
    'bar': 'bares', 'bares': 'bares',
    'bowling': 'bowling',
}
TIPOS = {'lugar': 'lugar', 'actividad': 'evento', 'evento': 'evento', 'excursion': 'excursion', 'paquete': 'excursion'}

# Misiones y alrededores: una coordenada fuera de este rango es un error de tipeo
LAT_MIN, LAT_MAX = -28.6, -25.4
LNG_MIN, LNG_MAX = -56.6, -53.5


# ---------------------------------------------------------------------
# Normalización
# ---------------------------------------------------------------------
def plano(s) -> str:
    """minúsculas, sin acentos ni signos: para comparar encabezados y valores"""
    s = unicodedata.normalize('NFKD', str(s or '')).encode('ascii', 'ignore').decode()
    return re.sub(r'[^a-z0-9]+', ' ', s.lower()).strip()


def texto(v) -> str:
    if v is None:
        return ''
    if isinstance(v, float) and v.is_integer():
        v = int(v)
    s = str(v).replace('\r', ' ').replace('\n', ' ')
    return re.sub(r'\s+', ' ', s).strip()


def slug(s: str, largo: int = 40) -> str:
    s = plano(s).replace(' ', '-')
    return s[:largo].strip('-') or 'lugar'


def es_si(v) -> bool:
    return plano(v) in ('x', 'si', 's', '1', 'true', 'verdadero', 'yes') or texto(v) in ('✓', '✔', '✅')


def telefono(v):
    """Devuelve (para mostrar, número internacional sin +) o (texto, None)
    si no se entiende. Acepta: /+54 9 (376) 15 5116237 · (0376) 442-5620 ·
    +5493764105135 · 376 4123456 · varios números separados por "/"."""
    t = texto(v).strip(' /')
    if not t:
        return '', None
    primero = re.split(r'\s/\s?|\s?/\s', t)[0] if '/' in t[1:] else t.lstrip('/')
    d = re.sub(r'\D', '', primero)
    movil = False
    if d.startswith('54'):
        d = d[2:]
        if d.startswith('9'):
            movil, d = True, d[1:]
    if d.startswith('0'):
        d = d[1:]
    # código de área de 2 a 4 cifras seguido de "15" (forma local del celular)
    for largo_area in (4, 3, 2):
        area, resto = d[:largo_area], d[largo_area:]
        if resto.startswith('15') and len(area + resto) == 12:
            d, movil = area + resto[2:], True
            break
    # el código de área repetido: (376) 3764145673
    for largo_area in (4, 3, 2):
        area = d[:largo_area]
        if len(d) == 10 + largo_area and d[largo_area:].startswith(area):
            d = d[largo_area:]
            break
    if len(d) != 10:
        return t.lstrip('/ ').strip(), None
    # Para mostrar, siempre igual: +54 9 376 463-5014 / +54 376 444-7373
    la = 2 if d.startswith('11') else 3 if d.startswith('376') else 4
    area, num = d[:la], d[la:]
    corte = len(num) - 4
    lindo = f'+54 {"9 " if movil else ""}{area} {num[:corte]}-{num[corte:]}'
    return lindo, ('549' if movil else '54') + d


def instagram(v):
    t = texto(v)
    if not t:
        return ''
    m = re.search(r'instagram\.com/([A-Za-z0-9._]{1,30})', t) or re.fullmatch(r'@?([A-Za-z0-9._]{1,30})', t)
    return f'https://www.instagram.com/{m.group(1)}/' if m else ''


def url(v):
    t = texto(v)
    return t if re.match(r'^https?://\S+$', t) else ''


# Los mismos formatos que reconoce la web (función videoDe de index.html)
VIDEO_FORMATOS = [
    r'^https://(?:www\.|m\.)?youtube\.com/(?:watch\?(?:[^#]*&)?v=|embed/|shorts/|live/)[A-Za-z0-9_-]{11}',
    r'^https://youtu\.be/[A-Za-z0-9_-]{11}',
    r'^https://(?:www\.)?instagram\.com/(?:[A-Za-z0-9._]{1,30}/)?(?:reels?|p|tv)/[A-Za-z0-9_-]{5,40}',
    r'^https://(?:www\.)?tiktok\.com/@[A-Za-z0-9._-]{1,40}/video/\d{8,25}',
    r'^https://(?:www\.|player\.)?vimeo\.com/(?:video/)?\d{6,12}',
    r'^https://drive\.google\.com/(?:file/d/|open\?id=)[A-Za-z0-9_-]{10,80}',
    r'^https://[^\s"\'<>()\\]+\.(?:mp4|webm)(?:\?[^\s"\'<>()\\]*)?$',
]


def video(v):
    t = texto(v)
    if t.startswith('http://'):
        t = 'https://' + t[7:]
    return t if any(re.match(f, t, re.I) for f in VIDEO_FORMATOS) else ''


def coordenadas(v, link=''):
    """'-27.36, -55.89' · '27°21'54.1"S 55°53'55.7"W' · o el link largo de Google Maps"""
    t = texto(v)
    if t:
        m = re.findall(r'(\d+)°\s*(\d+)\'\s*([\d.]+)"?\s*([NSEWO])', t)
        if len(m) == 2:
            def g(x):
                val = int(x[0]) + int(x[1]) / 60 + float(x[2]) / 3600
                return -val if x[3] in 'SWO' else val
            par = (g(m[0]), g(m[1]))
        else:
            n = re.findall(r'-?\d+(?:[.,]\d+)?', t.replace(', ', ' ').replace(';', ' '))
            par = (float(n[0].replace(',', '.')), float(n[1].replace(',', '.'))) if len(n) >= 2 else None
        if par:
            return [round(par[0], 6), round(par[1], 6)]
    m = re.search(r'!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)', link or '') or re.search(r'@(-?\d+\.\d+),(-?\d+\.\d+)', link or '')
    if m:
        return [round(float(m.group(1)), 6), round(float(m.group(2)), 6)]
    return None


def coords_ok(c):
    return bool(c) and LAT_MIN <= c[0] <= LAT_MAX and LNG_MIN <= c[1] <= LNG_MAX


def fecha(v):
    if isinstance(v, dt.datetime):
        return v.date()
    if isinstance(v, dt.date):
        return v
    t = texto(v)
    for fmt in ('%d/%m/%Y', '%d/%m/%y', '%Y-%m-%d', '%d-%m-%Y'):
        try:
            return dt.datetime.strptime(t, fmt).date()
        except ValueError:
            pass
    return None


def hora(v):
    if isinstance(v, dt.time):
        return f'{v.hour:02d}:{v.minute:02d}'
    if isinstance(v, dt.datetime):
        return f'{v.hour:02d}:{v.minute:02d}'
    if isinstance(v, float) and 0 <= v < 1:            # Excel guarda la hora como fracción del día
        m = round(v * 24 * 60)
        return f'{m // 60:02d}:{m % 60:02d}'
    t = plano(v)
    m = re.match(r'^(\d{1,2})(?: (\d{2}))?(?: hs?)?$', t)
    if m and int(m.group(1)) < 24:
        return f'{int(m.group(1)):02d}:{m.group(2) or "00"}'
    return None


def entero(v):
    try:
        n = int(float(texto(v).replace(',', '.')))
        return n if n > 0 else None
    except ValueError:
        return None


def precio_numero(t):
    n = re.findall(r'\d[\d.]*', t or '')
    if len(n) == 1:
        try:
            return int(n[0].replace('.', ''))
        except ValueError:
            return None
    return None


# ---------------------------------------------------------------------
# Lectura
# ---------------------------------------------------------------------
COLUMNAS_LUGARES = {
    'id': ['id'],
    'publicar': ['publicar'],
    'tipo': ['tipo'],
    'nombre': ['nombre'],
    'subcategorias': ['subcategorias', 'subcategoria'],
    'direccion': ['direccion'],
    'coordenadas': ['coordenadas', 'coordenadas lat lng'],
    'maps': ['link google maps', 'google maps', 'link de google maps', 'ubicacion'],
    'telefono': ['telefono', 'contacto'],
    'whatsapp': ['whatsapp', 'tiene whatsapp'],
    'instagram': ['instagram', 'ig'],
    'web': ['web mas info', 'web', 'mas info', 'info'],
    'horario': ['horario', 'horarios'],
    'precio': ['precio'],
    'inscripcion': ['inscripcion'],
    'cupo': ['cupo'],
    'organiza': ['organiza', 'agencia'],
    'descripcion': ['descripcion'],
    'recomendacion': ['recomendacion'],
    'foto': ['foto link', 'foto'],
    'video': ['video link', 'video'],
    'destacado': ['destacado', 'evento destacado'],
    'nombre_pt': ['nombre portugues', 'nombre pt'],
    'descripcion_pt': ['descripcion portugues', 'descripcion pt'],
}
COLUMNAS_AGENDA = {
    'fecha': ['fecha'],
    'hora': ['hora', 'horario'],
    'id': ['id', 'id actividad o lugar', 'id actividad'],
    'evento': ['nombre del evento', 'nombre del evento solo eventos puntuales', 'evento'],
    'estado': ['estado'],
    'encuentro': ['punto de encuentro'],
    'cupo': ['cupo'],
}


def leer_tabla(filas):
    """filas: lista de listas. Busca la fila de encabezados (la primera que
    tenga 'nombre' o 'fecha') y devuelve lista de dicts por encabezado plano."""
    for i, f in enumerate(filas[:10]):
        claves = [plano(x) for x in f]
        if 'nombre' in claves or 'fecha' in claves:
            enc = claves
            out = []
            for g in filas[i + 1:]:
                if not any(texto(x) for x in g):
                    continue
                out.append({enc[j]: g[j] for j in range(min(len(enc), len(g))) if enc[j]})
            return out
    return []


def tomar(fila, alias):
    for a in alias:
        if a in fila and texto(fila[a]) != '':
            return fila[a]
    return None


def leer_xlsx(ruta):
    try:
        import openpyxl
    except ImportError:
        sys.exit('Para leer .xlsx hace falta openpyxl:  pip install openpyxl')
    wb = openpyxl.load_workbook(ruta, data_only=True)
    hojas = {plano(ws.title): ws for ws in wb.worksheets}
    if 'lugares' not in hojas:
        sys.exit(f'ERROR: la planilla no tiene una hoja "Lugares" (tiene: {", ".join(ws.title for ws in wb.worksheets)})')
    tab = lambda ws: [list(r) for r in ws.iter_rows(values_only=True)]
    return leer_tabla(tab(hojas['lugares'])), leer_tabla(tab(hojas['agenda'])) if 'agenda' in hojas else []


def leer_csv(ruta):
    crudo = Path(ruta).read_bytes()
    for cod in ('utf-8-sig', 'cp1252', 'latin-1'):
        try:
            txt = crudo.decode(cod)
            break
        except UnicodeDecodeError:
            continue
    try:
        dialecto = csv.Sniffer().sniff(txt[:4000], delimiters=';,\t')
    except csv.Error:
        dialecto = csv.excel
    return leer_tabla([r for r in csv.reader(io.StringIO(txt), dialecto)])


# ---------------------------------------------------------------------
# Armado del catálogo
# ---------------------------------------------------------------------
class Informe:
    def __init__(self):
        self.errores, self.avisos = [], []

    def error(self, m):
        self.errores.append(m)

    def aviso(self, m):
        self.avisos.append(m)


def armar(lugares_raw, agenda_raw, hoy: dt.date, inf: Informe):
    col_cat = {plano(col): cid for cid, col, _ in CATEGORIAS}
    col_cat.update({'paseos guiados': 'paseos', 'pg': 'paseos', 'paquetes': 'excursiones', 'ninos': 'ninos'})

    lugares, ids = [], {}
    for n, f in enumerate(lugares_raw, start=2):
        nombre = texto(tomar(f, COLUMNAS_LUGARES['nombre']))
        if not nombre:
            continue
        fila = f'Lugares fila {n} ({nombre})'
        pub = tomar(f, COLUMNAS_LUGARES['publicar'])
        if pub is not None and not es_si(pub):
            continue

        lid = texto(tomar(f, COLUMNAS_LUGARES['id'])).lower() or slug(nombre)
        if not re.fullmatch(r'[a-z0-9_-]{1,40}', lid):
            inf.aviso(f'{fila}: el ID "{lid}" tiene caracteres no válidos; se usa "{slug(lid)}"')
            lid = slug(lid)
        if lid in ids:
            inf.error(f'{fila}: el ID "{lid}" ya se usa en la fila {ids[lid]}')
            continue
        ids[lid] = n

        tipo_txt = plano(tomar(f, COLUMNAS_LUGARES['tipo']))
        tipo = TIPOS.get(tipo_txt, 'lugar')
        if tipo_txt and tipo_txt not in TIPOS:
            inf.aviso(f'{fila}: tipo "{tipo_txt}" no reconocido; se toma como Lugar')

        cats = [cid for clave, cid in col_cat.items() if clave in f and es_si(f[clave])]
        cats = list(dict.fromkeys(cid for cid, _, _ in CATEGORIAS if cid in cats))
        if not cats:
            inf.aviso(f'{fila}: no tiene ninguna categoría marcada; no va a aparecer en los filtros')

        subs = []
        for s in re.split(r'[,;/]', texto(tomar(f, COLUMNAS_LUGARES['subcategorias']))):
            if not plano(s):
                continue
            sid = SINONIMOS_SUB.get(plano(s))
            if not sid:
                inf.aviso(f'{fila}: subcategoría "{s.strip()}" no reconocida (válidas: {", ".join(SUBCATEGORIAS.values())})')
                continue
            madre = next(cid for cid, _, ss in CATEGORIAS if sid in ss)
            if madre not in cats:
                cats.append(madre)
            if sid not in subs:
                subs.append(sid)

        link_maps = url(tomar(f, COLUMNAS_LUGARES['maps']))
        c = coordenadas(tomar(f, COLUMNAS_LUGARES['coordenadas']), link_maps)
        if c and not coords_ok(c):
            inf.aviso(f'{fila}: coordenadas {c} fuera de Misiones (¿lat y lng invertidas o sin el signo menos?); se ignoran')
            c = None

        tel_txt, tel = telefono(tomar(f, COLUMNAS_LUGARES['telefono']))
        if tel_txt and not tel:
            inf.aviso(f'{fila}: no se entiende el teléfono "{tel_txt}"; se muestra como texto')
        wapp_raw = tomar(f, COLUMNAS_LUGARES['whatsapp'])
        wapp = None
        if wapp_raw is not None:
            if es_si(wapp_raw):
                wapp = tel if tel and tel.startswith('549') else None
                if not wapp:
                    inf.aviso(f'{fila}: marcado con WhatsApp pero el teléfono no es un celular')
            elif plano(wapp_raw) not in ('no', 'n'):
                _, wapp = telefono(wapp_raw)

        ig_raw = tomar(f, COLUMNAS_LUGARES['instagram'])
        ig = instagram(ig_raw)
        if ig_raw and not ig:
            inf.aviso(f'{fila}: Instagram "{texto(ig_raw)}" no reconocido')

        insc = plano(tomar(f, COLUMNAS_LUGARES['inscripcion']))
        ticket = 'free_reg' if insc.startswith('gratis') else 'paid' if insc.startswith('pag') else None
        precio = texto(tomar(f, COLUMNAS_LUGARES['precio']))
        horario = texto(tomar(f, COLUMNAS_LUGARES['horario']))

        foto_raw = tomar(f, COLUMNAS_LUGARES['foto'])
        foto = url(foto_raw)
        if foto_raw and not foto:
            inf.aviso(f'{fila}: la foto tiene que ser un enlace que empiece con http')

        video_raw = tomar(f, COLUMNAS_LUGARES['video'])
        vid = video(video_raw)
        if video_raw and not vid:
            inf.aviso(f'{fila}: video "{texto(video_raw)}" no reconocido (usar un enlace de YouTube, Instagram, TikTok, Vimeo, Google Drive o un .mp4)')
        destacado = es_si(tomar(f, COLUMNAS_LUGARES['destacado']))
        if destacado and tipo != 'evento':
            inf.aviso(f'{fila}: "Destacado" solo se usa en actividades (los lugares no tienen fecha); se ignora')
            destacado = False

        L = {
            'id': lid, 'type': tipo, 'name': nombre,
            'addr': texto(tomar(f, COLUMNAS_LUGARES['direccion'])),
            'coords': c, 'cats': cats, 'subs': subs,
            'tel': tel_txt or None, 'telLink': tel, 'whatsapp': wapp, 'ig': ig or None,
            'web': url(tomar(f, COLUMNAS_LUGARES['web'])) or None, 'maps': link_maps or None,
            'horario': horario or None, 'price': precio or None,
            'ticketType': ticket, 'ticketPrice': precio_numero(precio) if ticket == 'paid' else None,
            'cupoTotal': entero(tomar(f, COLUMNAS_LUGARES['cupo'])) if ticket == 'free_reg' else None,
            'org': texto(tomar(f, COLUMNAS_LUGARES['organiza'])) or None,
            'story': texto(tomar(f, COLUMNAS_LUGARES['descripcion'])) or None,
            'fact': texto(tomar(f, COLUMNAS_LUGARES['recomendacion'])) or None,
            'img': foto or None,
            'video': vid or None,
            'destacado': True if destacado else None,
        }
        pt = {'name': texto(tomar(f, COLUMNAS_LUGARES['nombre_pt'])), 'story': texto(tomar(f, COLUMNAS_LUGARES['descripcion_pt']))}
        pt = {k: v for k, v in pt.items() if v}
        if pt:
            L['pt'] = pt
        if horario and tipo != 'evento':
            L['schedule'] = {'kind': 'siempre', 'label': horario}
        if tipo == 'excursion' and 'schedule' not in L:
            L['schedule'] = {'kind': 'siempre', 'label': 'Consultar fechas'}
        lugares.append(L)

    por_id = {L['id']: L for L in lugares}

    # ---------- Agenda ----------
    pasadas = 0
    puntuales = []
    for n, f in enumerate(agenda_raw, start=2):
        fila = f'Agenda fila {n}'
        fe = fecha(tomar(f, COLUMNAS_AGENDA['fecha']))
        rid = texto(tomar(f, COLUMNAS_AGENDA['id'])).lower()
        if not fe and not rid:
            continue
        if not fe:
            inf.aviso(f'{fila}: fecha "{texto(tomar(f, COLUMNAS_AGENDA["fecha"]))}" no válida (usar dd/mm/aaaa)')
            continue
        if fe < hoy:
            pasadas += 1
            continue
        base = por_id.get(rid)
        if not base:
            inf.aviso(f'{fila}: el ID "{rid}" no está en la hoja Lugares (o no se publica)')
            continue
        hr_raw = tomar(f, COLUMNAS_AGENDA['hora'])
        hr = hora(hr_raw)
        if hr_raw is not None and not hr and 'confirmar' not in plano(hr_raw):
            inf.aviso(f'{fila}: hora "{texto(hr_raw)}" no válida (usar 17:00)')
        estado = 'a_confirmar' if 'confirmar' in plano(tomar(f, COLUMNAS_AGENDA['estado'])) or not hr else 'confirmado'
        item = {'fecha': fe.isoformat(), 'hora': hr, 'estado': estado}
        if texto(tomar(f, COLUMNAS_AGENDA['encuentro'])):
            item['encuentro'] = texto(tomar(f, COLUMNAS_AGENDA['encuentro']))
        cupo = entero(tomar(f, COLUMNAS_AGENDA['cupo']))
        if cupo:
            item['cupo'] = cupo

        evento = texto(tomar(f, COLUMNAS_AGENDA['evento']))
        if evento:
            # evento puntual en un lugar (un show, una feria): es un ítem nuevo
            pid = f'{slug(evento, 24)}-{fe.strftime("%m%d")}'
            while pid in por_id:
                pid += 'b'
            E = {k: v for k, v in base.items() if k in ('addr', 'coords', 'cats', 'subs', 'tel', 'telLink', 'whatsapp', 'ig', 'maps', 'img')}
            E.update({'id': pid, 'type': 'evento', 'name': evento, 'lugar': base['id'],
                      'schedule': {'kind': 'fechas', 'fechas': [item]}})
            if item.get('encuentro'):
                E['addr'] = item['encuentro']
            por_id[pid] = E
            puntuales.append(E)
        else:
            if base['type'] != 'evento':
                inf.aviso(f'{fila}: "{base["name"]}" es un {base["type"]}, no una actividad; para un evento en ese lugar completar "Nombre del evento"')
                continue
            sc = base.setdefault('schedule', {'kind': 'fechas', 'fechas': []})
            if sc.get('kind') != 'fechas':
                base['schedule'] = sc = {'kind': 'fechas', 'fechas': []}
            sc['fechas'].append(item)

    for L in lugares:
        sc = L.get('schedule')
        if sc and sc.get('kind') == 'fechas':
            sc['fechas'].sort(key=lambda x: (x['fecha'], x['hora'] or '99'))

    todos = lugares + puntuales
    # sin valores vacíos: el JSON queda más chico y la app completa lo que falta
    limpio = [{k: v for k, v in L.items() if v not in (None, [], '')} for L in todos]
    return limpio, pasadas


def main():
    ap = argparse.ArgumentParser(description='Importa la planilla de 48 HS y genera catalogo.json')
    ap.add_argument('planilla', nargs='?', help='planilla .xlsx')
    ap.add_argument('--lugares', help='hoja Lugares exportada a CSV')
    ap.add_argument('--agenda', help='hoja Agenda exportada a CSV')
    ap.add_argument('-o', '--salida', default='catalogo.json')
    ap.add_argument('--hoy', help='fecha de referencia AAAA-MM-DD (para pruebas)')
    a = ap.parse_args()

    if a.planilla:
        lug, age = leer_xlsx(a.planilla)
    elif a.lugares:
        lug, age = leer_csv(a.lugares), leer_csv(a.agenda) if a.agenda else []
    else:
        ap.error('pasá la planilla .xlsx o --lugares Lugares.csv')

    hoy = dt.date.fromisoformat(a.hoy) if a.hoy else dt.datetime.now(dt.timezone(dt.timedelta(hours=-3))).date()
    inf = Informe()
    lugares, pasadas = armar(lug, age, hoy, inf)

    print(f'\n48 HS · importación ({hoy:%d/%m/%Y})')
    print('-' * 52)
    if inf.errores:
        print('\nERRORES (no se generó el catálogo):')
        for e in inf.errores:
            print('  ✗', e)
        sys.exit(1)

    salida = {'version': 1, 'generado': dt.datetime.now(dt.timezone.utc).isoformat(timespec='seconds'), 'lugares': lugares}
    Path(a.salida).write_text(json.dumps(salida, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')

    por_cat = {cid: sum(1 for L in lugares if cid in L.get('cats', [])) for cid, _, _ in CATEGORIAS}
    fechas = sum(len(L.get('schedule', {}).get('fechas', [])) for L in lugares)
    sin_coords = [L['name'] for L in lugares if not L.get('coords') and L.get('type') != 'excursion']
    print(f'\n✓ {len(lugares)} lugares y actividades → {a.salida}')
    print('  ' + ' · '.join(f'{col}: {por_cat[cid]}' for cid, col, _ in CATEGORIAS))
    print(f'  {fechas} fechas próximas en la agenda' + (f' ({pasadas} fechas ya pasadas, ignoradas)' if pasadas else ''))
    if sin_coords:
        print(f'\n  Sin coordenadas (no aparecen en el mapa ni en "Cerca"): {len(sin_coords)}')
        for s in sin_coords:
            print('   ·', s)
    if inf.avisos:
        print(f'\nAVISOS ({len(inf.avisos)}):')
        for m in inf.avisos:
            print('  !', m)
    print()


if __name__ == '__main__':
    main()
