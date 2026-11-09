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
- **Cloudflare Wrangler 4.158.0 dry-run riuscito**, senza login o deploy.
  Verificati 222 riferimenti della cache offline: nessun file mancante e
  nessun metafile Cloudflare richiesto come risorsa. Il bundle contiene solo
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

## Da provare dopo il deploy

L'accesso Cloudflare non è stato completato: nessun Worker, binding DNS o
certificato è dichiarato attivo da questa lavorazione. La configurazione e
le istruzioni sono in [CLOUDFLARE.md](CLOUDFLARE.md).

Restano da eseguire con un account di prova autorizzato: stesso login tra app
e sito, confronto dei dati, CRUD effettivo tra i due client, apertura PDF nel
viewer, navigazione completa e ricaricamento dell'app intera senza rete dopo
la preparazione della cache. Il test IndexedDB verifica la persistenza dello
store, non questi flussi autenticati. Vedi [WEB_PARITY.md](WEB_PARITY.md).
