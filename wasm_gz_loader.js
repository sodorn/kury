/*
 * Build webowy lezy na hostingu, ktory przyjmuje pliki do 20 MB i serwuje
 * tylko wybrane rozszerzenia (.pck ani .bin nie przechodza). Dlatego:
 *
 *   index.wasm (ok. 39 MB)  ->  engine.txt  (gzip, ok. 10 MB)
 *   index.pck               ->  pack.txt    (bez kompresji)
 *
 * Ten skrypt podmienia pobieranie silnika: przechwytuje adres konczacy sie na
 * index.wasm, pobiera engine.txt i rozpakowuje go w przegladarce.
 * Pakiet z gra (pack.txt) wskazujemy silnikowi wprost, polem mainPack
 * w konfiguracji w index.html — tam podmianka nie jest potrzebna.
 *
 * Rozpakowany silnik skladamy w calosci do bufora, zamiast podawac strumien.
 * Wersja strumieniowa nie uruchamiala gry (ekran ladowania, bez bledu
 * w konsoli), wersja z buforem dziala.
 *
 * Oba pliki tworzy skrypt tools/build_web.sh i on tez kopiuje tu ten loader.
 */
(function () {
	"use strict";

	if (typeof DecompressionStream === "undefined" || typeof window.fetch !== "function") {
		return;
	}

	var originalFetch = window.fetch.bind(window);

	window.fetch = function (input, init) {
		var url = typeof input === "string" ? input : (input && input.url) || "";
		if (!/index\.wasm$/.test(url)) {
			return originalFetch(input, init);
		}
		var engineUrl = url.replace(/index\.wasm$/, "engine.txt");
		return originalFetch(engineUrl, init).then(function (response) {
			if (!response.ok || !response.body) {
				return response;
			}
			var unpacked = response.body.pipeThrough(new DecompressionStream("gzip"));
			return new Response(unpacked).arrayBuffer().then(function (buffer) {
				return new Response(buffer, {
					status: 200,
					headers: {
						"Content-Type": "application/wasm",
						"Content-Length": String(buffer.byteLength),
					},
				});
			});
		});
	};
})();
