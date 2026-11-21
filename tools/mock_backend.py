#!/usr/bin/env python3
"""Atrapa serwera zapisow, zgodna z tym fragmentem REST-a Supabase,
ktorego uzywa gra (services/cloud.gd).

Sluzy wylacznie do testow: pozwala sprawdzic w prawdziwej przegladarce,
ze gra wysyla i pobiera stan przez siec, bez zakladania konta w chmurze.

    python3 tools/mock_backend.py [port] [plik_ze_stanem]

Endpointy:
    POST /rest/v1/saves?on_conflict=player_id   zapis (upsert) listy rekordow
    GET  /rest/v1/saves?player_id=eq.<id>       odczyt rekordu gracza
    GET  /_dump                                 podglad calej bazy (test)
"""
import json
import time
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8899
STORE_PATH = sys.argv[2] if len(sys.argv) > 2 else "/tmp/mock_saves.json"
# Sztuczne opoznienie odpowiedzi, w sekundach. Bez niego atrapa odpowiada
# natychmiast i nie da sie odtworzyc bledow zwiazanych z tym, ze jedno
# zapytanie jeszcze trwa, gdy zaczyna sie drugie.
DELAY = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0


def read_store() -> dict:
    try:
        with open(STORE_PATH, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return {}


def write_store(store: dict) -> None:
    with open(STORE_PATH, "w", encoding="utf-8") as handle:
        json.dump(store, handle)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):  # cisza w konsoli
        pass

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PATCH, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "apikey, authorization, content-type, prefer")

    def _send(self, code: int, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self._cors()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _wait(self):
        if DELAY > 0.0:
            time.sleep(DELAY)

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        self._wait()
        url = urlparse(self.path)
        store = read_store()
        if url.path == "/_dump":
            self._send(200, store)
            return
        if not url.path.startswith("/rest/v1/"):
            self._send(404, {"message": "not found"})
            return
        query = parse_qs(url.query)
        wanted = query.get("player_id", [""])[0].removeprefix("eq.")
        row = store.get(wanted)
        self._send(200, [row] if row else [])

    def do_POST(self):
        self._wait()
        url = urlparse(self.path)
        if not url.path.startswith("/rest/v1/"):
            self._send(404, {"message": "not found"})
            return
        length = int(self.headers.get("Content-Length", "0"))
        try:
            rows = json.loads(self.rfile.read(length) or b"[]")
        except ValueError:
            self._send(400, {"message": "bad json"})
            return
        if isinstance(rows, dict):
            rows = [rows]
        store = read_store()
        for row in rows:
            player_id = str(row.get("player_id", ""))
            if player_id:
                store[player_id] = {
                    "player_id": player_id,
                    "payload": row.get("payload", {}),
                    "updated_at": row.get("updated_at", 0),
                }
        write_store(store)
        self._send(201, [])


if __name__ == "__main__":
    write_store(read_store())
    print("atrapa serwera zapisow na porcie %d, baza: %s" % (PORT, STORE_PATH))
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
