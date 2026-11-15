#!/usr/bin/env python3
"""Snapshot selected lines from a public third-party ArcGIS map layer.

Run only when reviewing a catalogue update. The app itself works offline.
Station order is checked against the operators' published line diagrams; the
geometry is approximate and is not official operator track geometry.
"""
import json
import math
import subprocess
import urllib.parse
from pathlib import Path

BASE = ("https://services5.arcgis.com/tj2c2sBQpCvO7ufK/ArcGIS/rest/services/"
        "%C4%B0stanbul_Rayl%C4%B1_Sistemler_Kronoloji_Haritas%C4%B1_WFL1/FeatureServer")
ROOT = Path(__file__).resolve().parents[1]

ORDER = {
    "B1": "Halkalı|Mustafa Kemal|Küçükçekmece|Florya|Florya Akvaryum|Yeşilköy|Yeşilyurt|Ataköy|Bakırköy|Yenimahalle|Zeytinburnu|Kazlıçeşme|Yenikapı|Sirkeci|Üsküdar|Ayrılıkçeşmesi|Söğütlüçeşme|Feneryolu|Göztepe|Erenköy|Suadiye|Bostancı|Küçükyalı|İdealtepe|Süreyya Plajı|Maltepe|Cevizli|Atalar|Başak|Kartal|Yunus|Pendik|Kaynarca|Tersane|Güzelyalı|Aydıntepe|İçmeler|Tuzla|Çayırova|GTÜ-Fatih|Osmangazi|Darıca|Gebze".split("|"),
    "M2": "Yenikapı|Vezneciler-İÜ|Haliç|Şişhane-Zemin İstanbul|Taksim|Osmanbey|Şişli-Mecidiyeköy|Gayrettepe|Levent|4. Levent|Sanayi Mahallesi|İTÜ-Ayazağa|Atatürk Oto Sanayi|Darüşşafaka|Hacıosman".split("|"),
    "M6": "Levent|Nispetiye|Etiler|Boğaziçi Üniversitesi-Hisarüstü".split("|"),
}
SHAPES = {"B1": [117, 118, 58], "M2": [91, 92, 93, 25, 96, 94], "M6": [24]}


def fetch(layer):
    params = urllib.parse.urlencode({
        "where": "KOD IN ('B1','M2','M6') AND DURUM='1'", "outFields": "*",
        "outSR": 4326, "f": "geojson"})
    data = subprocess.check_output(["curl", "--fail", "--silent", "--show-error",
                                    "--location", "--max-time", "30",
                                    f"{BASE}/{layer}/query?{params}"])
    return json.loads(data)["features"]


def distance(a, b):
    return math.hypot((a[0]-b[0])*85000, (a[1]-b[1])*111000)


def main():
    lines, stations = fetch(0), fetch(1)
    by_id = {f["properties"]["OBJECTID"]: f for f in lines}
    result = {"ok": True, "source": BASE, "lines": []}
    for code, names in ORDER.items():
        by_name = {f["properties"]["AD"]: f for f in stations if f["properties"]["KOD"] == code}
        assert all(name in by_name for name in names), f"Missing station on {code}"
        assert len(by_name) == len(names) + (1 if code == "M2" else 0), f"Unexpected station on {code}"
        shape = []
        for object_id in SHAPES[code]:
            segment = by_id[object_id]["geometry"]["coordinates"]
            if code == "B1": segment = list(reversed(segment))
            if shape and distance(shape[-1], segment[0]) > 10:
                # The source omits the short Sişhane–Taksim tunnel geometry.
                assert code == "M2" and object_id == 92
            shape.extend(segment if not shape else segment[1:] if distance(shape[-1], segment[0]) < 10 else segment)
        indices = []
        for name in names:
            coord = by_name[name]["geometry"]["coordinates"]
            indices.append(min(range(len(shape)), key=lambda i: distance(coord, shape[i])))
        assert indices == sorted(indices), f"Unexpected geometry order on {code}: {indices}"
        route_stations = []
        for i, name in enumerate(names):
            lon, lat = by_name[name]["geometry"]["coordinates"]
            entry = {"id": f"{code}-{i}", "name": name, "latitude": round(lat, 7),
                     "longitude": round(lon, 7)}
            if i + 1 < len(names):
                following = by_name[names[i+1]]["geometry"]["coordinates"]
                section = [[round(y, 7), round(x, 7)] for x, y in shape[indices[i]:indices[i+1]+1]]
                entry["pathToNext"] = [[round(lat, 7), round(lon, 7)]] + section + [[round(following[1], 7), round(following[0], 7)]]
                if code == "M2" and name == "Şişhane-Zemin İstanbul":
                    entry["geometryApproximate"] = True
            route_stations.append(entry)
        result["lines"].append({"id": code, "name": {"B1": "Marmaray", "M2": "Yenikapı–Hacıosman", "M6": "Levent–Boğaziçi Ü./Hisarüstü"}[code],
                                "stations": route_stations})
    destination = ROOT / "Web" / "istanbul-rail.json"
    destination.write_text(json.dumps(result, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(destination, destination.stat().st_size, "bytes")


if __name__ == "__main__": main()
