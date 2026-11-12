# Verifiche web — 9 novembre 2026

## Aggiornamento 12 novembre — pagina Report (#86)

Report è una nuova destinazione nella navigazione desktop/mobile e nella
rotta `/report`, con selezione del mese. Mostra totale, numero e importo
medio delle spese di gruppo, confronto con il periodo precedente, andamento
di sei mesi, categorie e quote pagate per persona. Gli insight riportano
categoria principale, giorno più oneroso e spesa maggiore apribile nel
dettaglio originale.

Sono incluse solo spese di gruppo sincronizzate, tipo expense o legacy null;
entrate e spese personali sono escluse. I rimborsi non cancellano la spesa
registrata e le quote pagate non sono debiti/conguagli fra membri. Il loader
dedicato carica l'intero periodo con pagine da 200, avanzando sulle righe
effettivamente ricevute fino alla pagina vuota, anche con un limite server
più basso. Un errore di pagina invalida l'intero caricamento, senza KPI parziali.

Gli importi sono sommati in centesimi. Per il mese corrente il totale va dal
primo a oggi, mentre il confronto usa lo stesso numero di giorni in entrambi
i mesi, limitato da quello più corto; le due date sono mostrate. I mesi
storici sono completi. Un precedente a zero non produce percentuali infinite.
I grafici riportano valori testuali e mantengono lo storico anche con mese
selezionato vuoto. La navigazione conserva lo stato dei tab già visitati,
carica Report soltanto all'apertura e lo aggiorna al rientro o dopo modifiche.

Verifica indipendente completata: **56 test passati, 0 saltati, exit 0** su
sette file, di cui 21 nuovi Report e 35 regressioni. Sono coperti 405 righe,
cap server 100, errore della seconda pagina, periodi/bisestile/cambio anno,
identità dei paganti, risposte tardive di account/gruppi, refresh e navigazione
reale, stati vuoto/errore e layout a 390/1440 px. Nessuna migrazione, nuova
dipendenza o scrittura backend introdotta.

Analisi completata usando un percorso per comando: nuova area Report,
test Report, navigazione principale e refresh condiviso terminano con exit 0.
Nel file delle rotte restano cinque import inutilizzati già presenti prima
della modifica (0 errori, exit 2 per i warning). Il primo tentativo con più
percorsi è stato interrotto senza esito e non è conteggiato come riuscito.

Build web release riuscita con exit 0 in 134,5 s. Verificati tutti i 222
file del manifest offline, i sette sorgenti applicativi modificati invariati
dopo la compilazione e la configurazione con soli URL/chiave pubblica client.
SHA-256 JavaScript:
`4daef6f2526adacc28d83ebdc8f5374ee2bf2cc158240b827d4e503b53c6323b`.

## Aggiornamento 11 novembre — pagante nel dettaglio categoria (#85)

Il dettaglio mensile della categoria mostra «Pagato da: Nome» sotto la data
di ogni spesa di gruppo. Il nome del pagante ha precedenza su quello di chi
ha inserito la spesa; il creatore è un fallback soltanto se il pagante manca
o ha lo stesso ID. Quando il nome non è disponibile compare «Non specificato».
Le righe personali non mostrano il pagante. Non sono aggiunte richieste al
backend, né modificati dati, importi o classificazione delle spese.

Passati 18 widget test del dettaglio mensile, di cui 7 nuovi per pagante e
autore diversi, righe personali/di gruppo miste, fallback storici e nomi
mancanti, più larghezza mobile 320 px. Restano coperti titoli, filtri, data,
importi e callback alla spesa originale. Analisi mirata dei due file: exit 0,
0 errori e 0 warning; due informazioni preesistenti su initializing formals.
Il verificatore ha rieseguito indipendentemente lo stesso file: 18/18
passati, 0 saltati, exit 0; AC1–6 verdi nel perimetro codice/widget.
Build web release riuscita (exit 0, compilazione 149,5 s), con 222 risorse
offline verificate e sola configurazione client pubblica. SHA-256 JavaScript:
`d360ccb86e489d8a68ef617dabf32c8aae456fbb0db4011a0610d010fcf6389c`.
Pubblicata la release `/var/www/finn/releases/20261111-0623e8c`, conservando
la precedente `20261111-1937b99`. Archivio di 17.190.949 byte, SHA-256
`084544f61145567d19ec5a98997346f4f5131e29cd0c510329b10a23278bc694`.
Attivazione atomica dopo controllo degli hash sul server; homepage e JavaScript
pubblici HTTP 200, bundle pubblico identico al locale, direttiva no-store
e Cloudflare BYPASS. Conferma visiva della nuova riga sul suo account da
completare dall'utente.

## Aggiornamento 10 novembre — caricamento del gruppo (#84)

Segnalazione: dopo l'aggiornamento del sito, l'utente viene mostrato senza
gruppo. La verifica del codice ha trovato errori di lettura convertiti in
assenza del gruppo e un caricamento iniziale dipendente dall'apertura della
navigazione principale. Il profilo e il gruppo hanno tempi di caricamento
distinti: al completamento del profilo il provider del gruppo può essere
ricreato, perdendo la richiesta avviata dalla pagina.

La correzione carica il gruppo quando arriva l'ID dell'utente, anche dopo un
refresh su una pagina interna. Solo un `group_id` realmente nullo conferma
l'assenza; gli errori hanno un pulsante Riprova. Anche il primo caricamento
del profilo può essere ritentato. La lettura aggiorna soltanto il profilo in
memoria, così le spese usano lo stesso gruppo recuperato dall'interfaccia.
Le cache sono legate all'utente e al gruppo conosciuto; le risposte tardive
di una sessione precedente vengono ignorate. Nessuna operazione di creazione,
uscita, adesione o modifica del gruppo è parte della correzione.

Verifica indipendente: **43 test passati, 0 saltati**, su sette file. Sono
coperti arrivo ritardato del profilo, primo frame di MainNavigation, recupero
di `/no-group`, errori PGRST116 su profilo e gruppo, retry del profilo,
isolamento degli account/cache e risposte tardive. Passano anche i test di
pulizia al logout/sessione e tutti gli 11 test mensili della correzione #83.
I quattro file dei gruppi sono inclusi nella pipeline web.

Analisi mirata dei 14 file Dart: 0 errori e 6 warning preesistenti verificati
contro HEAD (import ed elementi inutilizzati nel riepilogo personale e
nei dettagli del gruppo). Il comando termina con exit 1 per questi warning;
non viene dichiarato un lint dell'intero repository privo di segnalazioni.

Build release generata il 10 novembre e verificata l'11 novembre: tutti i
222 file del manifest offline corrispondono ai rispettivi MD5, il bundle
contiene i nuovi percorsi di recupero e nessun sorgente applicativo è stato
modificato dopo la compilazione. La configurazione contiene soltanto URL e
chiave pubblica client del backend previsto. SHA-256 del JavaScript:
`c9470419c4d9d8646d5b91d14732d7bf19931f8d22761daa8a5e0c36a8d6c129`.

Pubblicata l'11 novembre la release `/var/www/finn/releases/20261111-1937b99`:
archivio da 17.190.734 byte, SHA-256
`8b0148bf3d1b2e25811563d9a8444a66dcc0a8cc95cebbfffa092d3f5d95f7ac`.
Il server ha verificato i 222 MD5 e l'hash del bundle prima del cambio atomico
di `/var/www/finn/current`. La release precedente `20261110-41f8ff4` è
conservata. HTTPS pubblico HTTP 200; JavaScript pubblico identico alla build,
con `no-store, no-cache, max-age=0, must-revalidate` e Cloudflare BYPASS.

Backend pubblico Auth verificato in sola lettura: HTTP 200 sul progetto
`ofsnyaplaowbduujuucb`. Questo controllo non dimostra l'appartenenza del
singolo account. L'utente ha confermato che sul telefono, con lo stesso
account, il gruppo è ancora visibile. L'11 novembre ha confermato anche sul
sito: «ora il gruppo c'è, vedo il nome delle spese». La CI web e APK sul
commit `f10867a` è completata con successo.
Il nuovo tentativo di controllo grafico dell'11 novembre è stato fermato
dallo strumento perché non riusciva a determinare con sufficiente affidabilità
l'URL corrente di Chrome. La conferma sul suo account è stata fornita
dall'utente, non dall'automazione grafica.

## Aggiornamento 10 novembre — titoli delle spese mensili (#83)

La lista della categoria usava soltanto il campo storico `merchant`, rimosso
dall'inserimento manuale. Ora mostra il primo testo non vuoto fra `notes`,
`merchant` e nome categoria, oppure l'etichetta neutra «Spesa». Il model e
i dati salvati restano invariati.

Passati 11 widget test del dettaglio mensile, inclusi 5 casi nuovi con righe
caricate tramite `ExpenseModel.fromJson`: note senza negozio, priorità delle
note, negozio storico, categoria e dati descrittivi assenti. La prova apre
realmente la categoria e controlla esclusione degli altri mesi/categorie e
navigazione alla spesa originale. Build web release riuscita.

Il test mensile è incluso anche nella pipeline web. La correzione condivisa
è disponibile per una futura release mobile; non viene pubblicato un nuovo
APK di produzione da questa lavorazione.

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
