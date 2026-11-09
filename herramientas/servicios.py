"""48 HS · servicios del mapa (farmacias, cajeros, estacionamientos, baños, hospitales, policía)

Dos usos:

  1) Armar la planilla para que Turismo revise los servicios:
       python herramientas/servicios.py planilla servicios.json "datos/48 HS - Servicios para revisar.xlsx"

  2) Volver a armar servicios.json con lo que Turismo corrigió:
       python herramientas/servicios.py importar "datos/48 HS - Servicios para revisar.xlsx" servicios.json

En la planilla, la columna "¿Está bien?" acepta: Sí / No (se quita del mapa) / Corregir
(se usan los datos corregidos de esa fila). Se pueden agregar filas nuevas al final.
Los datos vienen de OpenStreetMap (© colaboradores de OpenStreetMap, licencia ODbL).
"""
import json, re, sys
from datetime import date

TIPOS = {"i": "Informes turísticos", "h": "Hospital", "p": "Policía", "f": "Farmacia",
         "c": "Cajero automático", "e": "Estacionamiento", "b": "Baños públicos"}
POR_NOMBRE = {v.lower(): k for k, v in TIPOS.items()}
COLS = ["Tipo", "Nombre", "Dirección", "Horario", "Teléfono", "Latitud", "Longitud", "Ver en Google Maps", "¿Está bien?", "Observaciones"]


def texto_seguro(v):
    """Los datos vienen de OpenStreetMap, que edita cualquiera. Un texto que empieza
    con = + - @ podría ejecutarse como fórmula al abrir la planilla en Excel."""
    t = str(v or "")
    return "'" + t if t[:1] in ("=", "+", "-", "@", "\t", "\r") else t


def planilla(origen, destino):
    from openpyxl import Workbook
    from openpyxl.styles import Font, PatternFill, Alignment
    from openpyxl.worksheet.datavalidation import DataValidation
    d = json.load(open(origen, encoding="utf-8"))
    wb = Workbook(); ws = wb.active; ws.title = "Servicios"
    ws.append(COLS)
    orden = "ihpfceb"
    for it in sorted(d["items"], key=lambda x: (orden.index(x[0]), x[3] or "~", x[4])):
        cod, lat, lon, nom, dire, hor, tel = it
        ws.append([TIPOS[cod], texto_seguro(nom), texto_seguro(dire), texto_seguro(hor), texto_seguro(tel), lat, lon,
                   f"https://www.google.com/maps?q={lat},{lon}", "", ""])
        for c in ws[ws.max_row][1:5]:
            c.data_type = "s"   # siempre texto: un nombre que empiece con "=" no se vuelve fórmula
        c = ws.cell(ws.max_row, 8); c.hyperlink = c.value; c.value = "Abrir"; c.font = Font(color="1F5FBF", underline="single")
    for c in ws[1]:
        c.font = Font(bold=True, color="FFFFFF"); c.fill = PatternFill("solid", fgColor="3A2A1A"); c.alignment = Alignment(vertical="center")
    for col, ancho in zip("ABCDEFGHIJ", (20, 36, 34, 26, 20, 11, 11, 12, 13, 34)):
        ws.column_dimensions[col].width = ancho
    ws.freeze_panes = "A2"; ws.auto_filter.ref = f"A1:J{ws.max_row}"
    dv = DataValidation(type="list", formula1='"Sí,No,Corregir"', allow_blank=True); dv.add(f"I2:I{ws.max_row + 300}"); ws.add_data_validation(dv)
    dt = DataValidation(type="list", formula1='"' + ",".join(TIPOS.values()) + '"', allow_blank=False); dt.add(f"A2:A{ws.max_row + 300}"); ws.add_data_validation(dt)
    ay = wb.create_sheet("Cómo revisar")
    for fila in [
        ["Servicios que aparecen en el mapa de 48 HS al acercarse a nivel de calle."],
        ["Vienen de OpenStreetMap, el mapa público y gratuito; pueden faltar lugares o haber datos viejos."],
        [""],
        ["En la columna \"¿Está bien?\":"],
        ["  Sí: queda como está."],
        ["  No: se quita del mapa (cerró, no existe, es privado)."],
        ["  Corregir: cambiá en la misma fila lo que esté mal (nombre, dirección, horario, teléfono o ubicación)."],
        ["Para agregar uno que falta: una fila nueva al final, con tipo, nombre, dirección y la ubicación (latitud y longitud de Google Maps)."],
        ["Horario: como figura (ej.: Mo-Fr 08:00-13:00 = lunes a viernes de 8 a 13). Se puede escribir en castellano."],
        [""],
        ["Farmacias: solo zona centro, costanera y terminal. Policía: comisarías y destacamentos que atienden público."],
    ]:
        ay.append(fila)
    ay.column_dimensions["A"].width = 120; ay["A1"].font = Font(bold=True, size=12)
    wb.save(destino)
    print(f"{destino}: {ws.max_row - 1} servicios")


def numero(v):
    try: return round(float(str(v).replace(",", ".")), 6)
    except (TypeError, ValueError): return None


def importar(origen, destino):
    from openpyxl import load_workbook
    ws = load_workbook(origen, data_only=True)["Servicios"]
    cab = [str(c.value or "").strip() for c in ws[1]]
    idx = {n: cab.index(n) for n in COLS if n in cab}
    items, avisos = [], []
    for n, fila in enumerate(ws.iter_rows(min_row=2, values_only=True), start=2):
        if not any(fila): continue
        val = lambda col: fila[idx[col]] if col in idx and idx[col] < len(fila) else None
        if str(val("¿Está bien?") or "").strip().lower() == "no": continue
        cod = POR_NOMBRE.get(str(val("Tipo") or "").strip().lower())
        lat, lon = numero(val("Latitud")), numero(val("Longitud"))
        if not cod: avisos.append(f"fila {n}: tipo desconocido ({val('Tipo')})"); continue
        if lat is None or lon is None or not (-28.2 < lat < -26.9 and -56.3 < lon < -55.4):
            avisos.append(f"fila {n}: ubicación fuera de Posadas o vacía"); continue
        texto = lambda col: re.sub(r"\s+", " ", str(val(col) or "")).strip().lstrip("'")[:120]
        items.append([cod, lat, lon, texto("Nombre"), texto("Dirección"), texto("Horario"), texto("Teléfono")])
    out = {"fuente": "OpenStreetMap (© colaboradores de OpenStreetMap, licencia ODbL), revisado por Turismo",
           "fecha": date.today().isoformat(), "tipos": TIPOS,
           "campos": ["tipo", "lat", "lon", "nombre", "dirección", "horario", "teléfono"], "items": items}
    open(destino, "w", encoding="utf-8").write(json.dumps(out, ensure_ascii=False, separators=(",", ":")))
    print(f"{destino}: {len(items)} servicios")
    for a in avisos: print("  aviso:", a)


if __name__ == "__main__":
    if len(sys.argv) != 4 or sys.argv[1] not in ("planilla", "importar"):
        print(__doc__); sys.exit(1)
    (planilla if sys.argv[1] == "planilla" else importar)(sys.argv[2], sys.argv[3])
