# Verifiche web — 9 novembre 2026

Base richiesta: `release/v1.6.1`, commit `586eace`, versione dell'app non ancora
pubblicata. Toolchain locale: Flutter 3.35.7 / Dart 3.9.2.

## Esiti locali

- **22 test mirati passati, 0 saltati**: navigazione a 390 e 1440 px, archivio
  scontrini nativo, raggiungibilità Supabase prima del login, salvataggio offline,
  tentativi di upload e pulizia degli allegati, upgrade Drift v4→v5, pulizia di
  sessione e selezione dell'utente per la sincronizzazione.
- **1 test Chrome passato, 0 saltati**: scrittura di due PDF in IndexedDB,
  chiusura e riapertura dell'archivio, lettura degli stessi byte, eliminazione
  del primo e verifica che il secondo rimanga disponibile dopo un'altra
  riapertura. Il test iniziale ha rilevato la perdita dei generici delle liste
  al ripristino; l'implementazione ora converte esplicitamente gli elementi.
- **Build web release riuscita** con risorse locali per CanvasKit, SQLite e
  PDF.js, service worker offline-first e soli valori client pubblici Supabase.
- **Pacchetto statico verificato**: 222 riferimenti della cache offline,
  nessun file mancante e nessun metafile di hosting richiesto come risorsa.
  Il bundle contiene solo
  `SUPABASE_URL` e `SUPABASE_ANON_KEY` come configurazione d'ambiente.
- **Analisi dei file Dart modificati: 0 errori**. Restano 3 warning preesistenti
  per import/campi/variabili non utilizzati e segnalazioni informative nel
  codice condiviso. Non è una dichiarazione di analisi pulita dell'intero repo.
- **Backend reale, sola lettura**: impostazioni pubbliche Auth HTTP 200 con
  `Access-Control-Allow-Origin: https://finn.8020solutions.org`; preflight
  `scan-receipt` HTTP 200 con CORS abilitato.

La prova Chrome usa `dart test` sullo store browser effettivo, separato con
export condizionale dall'implementazione nativa. Il primo tentativo con
`flutter test --platform chrome` non ha eseguito il test per un timeout del
bootstrap grafico; non viene conteggiato come test superato.

## Deploy e prove residue

La destinazione è Nginx sul VPS `46.225.60.101`, con Cloudflare come DNS e
proxy. L'utente ha creato `A finn → 46.225.60.101`, proxy attivo e TTL automatico.
La release iniziale è `/var/www/finn/releases/20261109-db42319`, pubblicata
tramite il symlink `/var/www/finn/current`. L'estrazione dell'archivio Windows
normalizza i separatori delle entry e verifica il contenimento nella release.

La CI web [42679724414](https://github.com/ecologicaleaving/finn/actions/runs/42679724414)
è riuscita. Archivio locale `finn-web-v1.6.1-issue81.zip`: 17.313.974 byte,
SHA-256 `DC437CCF632B17CD5490D82E2F8220967F8F2E3899660DFF8424ADD369A59C96`.

Configurazioni HTTP iniziale, HTTPS e snippet statico sono in
[`deploy/nginx`](../deploy/nginx/). Certbot ha emesso il certificato per Finn,
con scadenza 2027-02-07; il timer di rinnovo risulta attivo. L'hook dedicato
[`finn-nginx-reload.sh`](../deploy/certbot/finn-nginx-reload.sh) ricarica Nginx
solo per questa lineage dopo `nginx -t`.

Il sito è online: HTTPS restituisce HTTP 200 tramite Cloudflare e HTTP 200
direttamente sull'origine, con validazione TLS riuscita. Nginx ha caricato la
configurazione HTTPS dopo `nginx -t`. La configurazione del repository allinea
HTTP/2 ai virtual host già presenti sul VPS.

Verifiche sul deploy completate:

- `nginx -t` e reload riusciti; i warning residui appartengono a configurazioni
  preesistenti di altri host.
- Rinnovo simulato del solo certificato Finn con `--dry-run --run-deploy-hooks
  --no-random-sleep-on-renew`: uscita 0, tutti i rinnovi simulati riusciti;
  anche `nginx -t` e il reload dell'hook sono riusciti.
- Tutti i 222 file del manifest offline sul VPS hanno MD5 uguale alla build.
- Asset critici HTTP 200 con MIME corretti, inclusi moduli PDF.js, SQLite e
  CanvasKit; `main.dart.js` e il service worker hanno le direttive
  `no-store, no-cache, max-age=0, must-revalidate` e Cloudflare `BYPASS`.
- HTTP reindirizza con 301 a HTTPS; il vecchio app-hub continua a rispondere 200.
- Controllo indipendente: metafile di hosting, `/.env` e asset JavaScript
  inesistente restituiscono 404; `/assets/.env` pubblico e la rotta SPA
  `/expenses` restituiscono 200.

Le istruzioni sono in [CLOUDFLARE.md](CLOUDFLARE.md). La prova grafica completa
non è stata eseguita perché l'host di automazione UI non era disponibile.

Restano da eseguire con un account di prova autorizzato: stesso login tra app
e sito, confronto dei dati, CRUD effettivo tra i due client, apertura PDF nel
viewer, navigazione completa e ricaricamento dell'app intera senza rete dopo
la preparazione della cache. Il test IndexedDB verifica la persistenza dello
store, non questi flussi autenticati. Vedi [WEB_PARITY.md](WEB_PARITY.md).
