"""Wspolne wczytywanie danych gry dla narzedzi w tools/.

Od 12.22 poziomy budynkow (nazwy, ceny, czasy budowy, pojemnosci, pasza,
plot i pies) sa w data/rozbudowy.json - pliku do recznej edycji. Gra
przepisuje go na uklad balance.json w GameData.apply_upgrades; ta funkcja
robi dokladnie to samo, zeby generatory dokumentacji widzialy te same liczby
co gra.
"""

import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA = ROOT / "data"


def load_json(name: str):
    return json.loads((DATA / name).read_text(encoding="utf-8"))


def rozbudowy() -> dict:
    return load_json("rozbudowy.json")


def _common(lv: dict) -> dict:
    return {"name": lv["nazwa"], "price": float(lv.get("cena", 0)),
            "build_minutes": float(lv.get("budowa_min", 0))}


def apply_upgrades(bal: dict, plik: dict) -> dict:
    b = bal.setdefault("buildings", {})
    eco = bal.setdefault("economy", {})
    inc = bal.setdefault("incubator", {})
    per_chick = max(1, int(inc.get("eggs_per_chick", 3)))

    k = plik["kurnik"]
    coop = b.setdefault("coop", {})
    coop.update(name=k[0]["nazwa"], capacity=int(k[0]["miejsc"]))
    coop["upgrades"] = [dict(_common(lv), capacity=int(lv["miejsc"])) for lv in k[1:]]

    m = plik["magazyn"]
    st = b.setdefault("storage", {})
    st.update(name=m[0]["nazwa"], egg_capacity=int(m[0]["jaj"]))
    base = float(plik["pasza_zl_kg"])
    eco["feed_price_kg"] = base
    eco["feed_options"] = [{"unit": o["nazwa"], "size": float(o["kg"]),
                            "discount": float(o.get("znizka_proc", 0)) / 100.0,
                            "per_kg": base * (1 - float(o.get("znizka_proc", 0)) / 100.0)}
                           for o in plik["pasza_do_kupienia"]]
    eco["feed_pack_size"] = eco["feed_options"][0]["size"]
    eco["feed_pack_price"] = eco["feed_pack_size"] * eco["feed_options"][0]["per_kg"]
    st["upgrades"] = [dict(_common(lv), egg_capacity=int(lv["jaj"])) for lv in m[1:]]

    i = plik["inkubator"]
    inc.update(name=i[0]["nazwa"], slots=max(1, int(i[0]["jaj"]) // per_chick), eggs=int(i[0]["jaj"]))
    inc["upgrades"] = [dict(_common(lv), slots=max(1, int(lv["jaj"]) // per_chick), eggs=int(lv["jaj"]))
                       for lv in i[1:]]

    b.setdefault("guard", {})["upgrades"] = [
        {"name": lv["nazwa"], "price": float(lv["cena"]),
         "block_chance": float(lv["lis_zawraca_proc"]) / 100.0} for lv in plik["plot"]]
    b.setdefault("dog", {})["upgrades"] = [
        {"name": lv["nazwa"], "price": float(lv["cena"]), "interval": float(lv["probuje_co_s"]),
         "chance": float(lv["przegania_proc"]) / 100.0,
         "kill_chance": float(lv["zagryza_proc"]) / 100.0,
         "damage_min": int(lv["obrazenia_min"]), "damage_max": int(lv["obrazenia_max"]),
         "deaf_chance": float(lv["nie_slyszy_proc"]) / 100.0,
         "quit_chance": float(lv["tchorzy_proc"]) / 100.0, "quit_after": float(lv["tchorzy_po_s"]),
         "life_days_min": float(lv["zyje_dni_min"]), "life_days_max": float(lv["zyje_dni_max"])}
        for lv in plik["pies"]]
    return bal


def load_balance() -> dict:
    """balance.json z nalozonymi poziomami z rozbudowy.json - tak jak w grze."""
    return apply_upgrades(load_json("balance.json"), rozbudowy())


def weight(kg: float) -> str:
    if kg < 1000:
        return "%d kg" % round(kg)
    t = round(kg / 100.0)
    return ("%d t" % (t // 10)) if t % 10 == 0 else ("%d,%d t" % (t // 10, t % 10))
