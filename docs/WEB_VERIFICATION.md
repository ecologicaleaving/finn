# Verifiche web — 9 novembre 2026

## Aggiornamento 12 novembre — equilibrio 50/50 per categoria e totale (#89)

Il criterio confermato dall'utente è 50% per ciascuna delle due persone,
valido per tutte le categorie e per il totale. Costo netto individuale =
spese pagate − entrate ricevute − rimborsi ricevuti; quota = metà del netto
totale; scostamento = netto individuale − quota. Un valore positivo è sopra
quota, uno negativo sotto. Nell'esempio dell'utente (100 € pagati ciascuno,
40 € ricevuti da Giovanna), i netti sono 100/60, le quote 80/80 e gli
scostamenti +20/−20: per pareggiare il periodo, 20 € da Giovanna all'altra
persona. La compensazione non è l'intero divario di 40 €.

Il calcolo riusa spese e incassi del Report già caricati, senza nuove
richieste o percentuali dei budget. Le categorie sono l'unione di spese,
entrate e rimborsi, inclusi casi con sole entrate e categoria assente.
Rimborsi/entrate riducono il carico della persona destinataria nella
categoria registrata; nessuna associazione degli assegni alle Figlie viene
dedotta dal testo. Un totale in equilibrio può contenere categorie con
scostamenti opposti che si compensano: il dettaglio li mantiene distinti.

La coppia è selezionata per ID. Il destinatario del rimborso non è presente
nello schema: il confronto richiede un'attribuzione locale esplicita;
il pagante della spesa originale non viene assunto come destinatario.
Anche autore e pagante non sono confusi quando manca il pagante esplicito.
Movimenti non attribuiti o fuori dalla coppia impediscono un esito completo
nella categoria coinvolta e nel totale, senza nasconderne gli importi.
Le altre categorie complete restano analizzabili.

Quote e differenze sono calcolate in centesimi. I resti sono distribuiti
deterministicamente per ID e categoria, così le quote e gli scostamenti
delle categorie riconciliano esattamente il totale anche con centesimi
dispari e netti negativi. Le attribuzioni locali includono l'impronta del
movimento per impedirne il riuso dopo modifiche ai dati.

Le scelte sono locali al confronto e non creano trasferimenti o modifiche
nei dati. Il risultato riguarda i movimenti del periodo selezionato:
conguagli già scambiati e saldi iniziali vanno considerati a parte. Non
esiste un tipo specifico che distingua un trasferimento tra persone da una
generica entrata registrata.

Il giro finale del developer è terminato con **68 test Report passati,
0 saltati, exit 0**, inclusi 9 test puri (343 combinazioni firmate per i
resti), 8 widget della nuova sezione e l'integrazione Mese/Anno senza nuove
query. Il primo giro aveva rilevato un difetto reale delle sezioni
espandibili: una chiave non adatta al PageStorage le faceva leggere l'offset
di scroll come stato booleano. Le due sezioni ora usano chiavi PageStorage
distinte per tipo/scope/snapshot, isolate da `report-scroll`; le attribuzioni
restano vincolate all'impronta completa del movimento. Test iniziale e
successivo conservati separatamente.

Analisi finale dei sei file modificati/nuovi: **tutti exit 0, nessun errore
o warning**. Restano due informazioni sulle graffe nel nuovo dominio e una
nel test Report esistente; gli altri quattro file non hanno diagnostiche.
Esiti e log individuali in `build/balance89-analyze-*`, con codice generale
zero. Nessun controllo dell'intera cartella è stato ripetuto.

Verifica indipendente finale: **70 test passati, 0 saltati, 0 failure,
exit 0**, sessione 58914 (68 Report e 2 dashboard refresh), runner 55 s.
Il verificatore non ha rilievi residui e ha confermato anche l'integrazione
Mese/Anno dopo il fix PageStorage. Nessuna analisi o compilazione duplicata.

Build web release **exit 0 in 151,0 s**. Validati tutti i **222 file** del
manifest offline, i tre sorgenti applicativi invariati dopo la compilazione
e la sola configurazione client pubblica Supabase. SHA-256 JavaScript:
`f756e86f70b7c54f065f523eef13b21c05c53053d36ca667a3e18fc39697989f`.
Archivio di 17.218.199 byte, SHA-256
`5f2b1db321bfc9b13c8348b1290682185b1df986a0e8d2bce8447d086b2e457d`.
Il verificatore ha eseguito un solo giro indipendente e non ha ripetuto
l'analisi statica; la build release è stata eseguita una volta da root.

Pubblicata la release `/var/www/finn/releases/20261112-95d1932`, sorgente
`95d1932e40e59b8d27e000194084290cafce1259`; precedente `20261112-4c86722`
conservata. Il server ha verificato SHA dell'archivio, 222 MD5 del manifest
e SHA del bundle prima dell'attivazione atomica. Homepage e JavaScript
pubblici HTTPS 200, MIME JavaScript corretto, no-store e Cloudflare BYPASS;
SHA pubblico identico alla build sopra indicata. Il verificatore ha anche
confrontato le tre patch applicative remote della PR82 con i file locali
testati: corrispondenza integrale, normalizzando CRLF.

Il confronto sui dati del conto reale nel browser resta da verificare
dall'utente: Ctrl+F5, Report, Equilibrio 50/50, scelta della coppia e
Tutte le categorie. I rimborsi non attribuiti richiedono di indicare chi
li ha ricevuti, senza modificare i movimenti originali.

## Aggiornamento 12 novembre — bilancio con entrate e rimborsi (#88)

Il bilancio del Report mensile/annuale distingue spese lorde, entrate
registrate e rimborsi ricevuti. Il saldo del periodo è la somma di entrate e
rimborsi meno le spese; non è un saldo bancario. Categorie e quote pagate
rimangono calcolate sulle spese lorde, con riepiloghi separati delle entrate.
Gli aiuti statali sono movimenti `income` con descrizione/categoria originali:
nessuna classificazione per parole chiave o attribuzione a beneficiari non
presenti nei dati. Le fonti personali previste in `income_sources` non sono
incassi e restano escluse.

Il loader legge due dataset paginati e li unisce per ID: movimenti per `date`
e sole spese rimborsate per `reimbursed_at`, indipendentemente dalla data
originaria della spesa. I confini dei rimborsi sono mezzanotti locali
convertite in UTC, con termine finale esclusivo; il timestamp viene sempre
convertito in locale, anche a mezzanotte UTC. Un errore in qualsiasi pagina
impedisce di mostrare un bilancio parziale.

Il modello esistente registra solo stato e data del rimborso: l'importo
conteggiato è quello integrale della spesa alla data di marcatura. Una
entrata distinta non ha un collegamento al flag di rimborso; il testo nel
Report chiede di registrare ogni incasso una sola volta, senza deduplicare
arbitrariamente righe diverse per importo o nome. I rimborsi attesi sono
solo quelli delle spese del periodo nello stato attuale `reimbursable` e
restano fuori dal saldo; non ricostruiscono un credito storico a fine mese.

Il dettaglio degli incassi mostra data, descrizione, categoria, persona
associata e importo, permette ricerca e filtro entrate/rimborsi e apre il
movimento originale. Il collegamento per aggiungere un'entrata riusa il
modulo esistente. Nessuna scrittura automatica, migrazione o nuova dipendenza.

Al ritorno dal movimento originale il Report viene invalidato se non è già
stato aggiornato dal refresh condiviso. Questo copre il cambio dello stato
rimborso nel dettaglio, che prima non influenzava i KPI del Report; i
controlli su mounted, richiesta, account e gruppo impediscono di riaprire
una richiesta fuori scope. Il salvataggio di nuove entrate riusa il refresh
comune delle altre mutazioni.

Primo giro finale: **50 test passati, 0 saltati, exit 0**. Sono coperti il
saldo di controllo 1.000/300/100 = −600, rimborsi di spese precedenti,
timestamp locali e confini mese/ora legale, deduplica per ID, incassi
distinti, due query paginate con errori e cambio account, ricerca su 45
movimenti, paginazione fino all'ultima riga, casi senza spese, layout a
390/1440 px e aggiornamento al ritorno dal dettaglio e da Aggiungi entrata.
La prima prova del nuovo test di navigazione è fallita per un'asserzione
sull'URI esposto da GoRouter; corretta per verificare la schermata aperta,
senza modificare il comportamento applicativo. Log dei tentativi conservati.

Verifica indipendente: **52 test passati, 0 saltati, 0 failure, exit 0**,
sessione 8725 (50 Report e 2 dashboard refresh), senza rilievi bloccanti sugli
11 criteri. Runner 1m06s oltre al caricamento iniziale rallentato. Analisi
applicativa finale: ciascuno dei quattro file Report modificati termina con
exit 0, nessuna diagnostica (0 errori, warning e informazioni). L'analisi dei
test termina con exit 0, 0 errori/warning e due sole informazioni sulle
graffe nelle fixture. Il precedente controllo dell'intera cartella codice
è stato interrotto per timeout e non viene contato come riuscito; log e
codice 124 restano distinti dagli esiti finali dei singoli file.

Build web release **exit 0 in 231,0 s**. Verificate tutte le **222 risorse**
del manifest offline, i quattro sorgenti invariati dopo la compilazione e
la sola configurazione client pubblica Supabase. JavaScript SHA-256:
`0e017e5006f892ceae2d65322e813634dea59da74d44183d7f8cc20e959aed7b`.
L'output della build è arrivato soltanto al termine: il ritardo iniziale
non era un errore o un timeout della compilazione.

Pubblicata la release `/var/www/finn/releases/20261112-4c86722`, sorgente
`4c86722d3c5e26d131fd1b5e49fdcb1bab17f252`. Archivio di **17.211.633 byte**,
SHA-256 `ff9e53b485ef47c38eb4eec9fb9a4ef268e8266a102a8126c2ac87052725d833`.
Il server ha verificato hash archivio, 222 MD5 del manifest e SHA del bundle
prima dell'attivazione atomica; precedente `20261112-982c1d0` conservata.
Homepage e JavaScript pubblici HTTPS 200, MIME JavaScript corretto,
no-store e Cloudflare BYPASS; hash pubblico uguale alla build sopra indicata.
Il browser autenticato reale resta da provare con l'account dell'utente:
Ctrl+F5, Report, Mese/Anno e Dettaglio entrate e rimborsi. Gli assegni
familiari devono essere movimenti Entrata del gruppo effettivamente
registrati; nessuna fonte prevista o dato personale è stato convertito
automaticamente in incasso.

## Aggiornamento 12 novembre — anno e pagamenti dei componenti (#87)

Il selettore Mese/Anno mantiene le rispettive selezioni. L'anno corrente
copre 1 gennaio–oggi, gli anni storici gennaio–dicembre; il confronto mostra
le date dell'anno precedente e gestisce il 29 febbraio senza attribuire un
numero uguale di giorni a calendari diversi. Il grafico annuale ha dodici
mesi: quelli futuri sono distinti con «Non ancora trascorso» e «—», mentre
il mese corrente è parziale. Sono disponibili aggregazioni e insight annuali,
compreso il mese più oneroso.

Come richiesto esplicitamente dall'utente, il riepilogo riporta quanto ha
pagato ciascuno, con importo, quota percentuale e numero di spese; non calcola
quote uguali o differenze da compensare. Usa i membri già disponibili nel
gruppo per includere quelli a zero, conserva paganti storici/non associati
e distingue le persone per ID. Le percentuali arrotondate ai decimi sommano
100,0% quando ci sono spese, restando a zero quando il totale è zero.
L'aggiornamento dell'elenco dei membri non ricarica le spese.

Verifica indipendente: **35 test passati, 0 saltati, exit 0**, inclusi tutti
i test mensili precedenti e casi annuali/bisestile, roster, omonimi, dati
storici, cambio modalità con anchor gennaio coincidente, invalidazione di
entrambe le modalità e widget a 390/1440 px. Nessuna nuova richiesta per i
membri, migrazione, dipendenza o scrittura introdotta.

Analisi finale in formato macchina: exit 0, 0 errori e 0 warning; una sola
informazione non fatale sulle graffe in `group_report.dart`. I test sono
analizzati senza problemi; il tentativo ordinario dell'area codice è stato
interrotto senza esito, seguito dal controllo macchina concluso. Build web
release exit 0 in 214,4 s, tutti i 222 file offline validati. SHA-256 JS:
`1e02d8567191ab6dfb3e60de3cd92a004764f4db25492abe30b74906c92a5e0e`.

Pubblicata la release `/var/www/finn/releases/20261112-982c1d0`, conservando
la precedente `20261112-df9eccd`. Archivio di 17.209.146 byte, SHA-256
`685fab41c4dfeb64491f5d1f6900f7dbb15925c88406c23cc7de69b49201be2e`.
Il server ha verificato i 222 MD5 e l'hash del bundle prima dell'attivazione
atomica. Homepage e JavaScript HTTPS 200; bundle pubblico uguale al locale,
no-store e Cloudflare BYPASS. L'utente ha poi confermato positivamente il
Report («ottimo !!!»), chiedendo l'estensione alle entrate della #88.
La CI web e APK sul commit documentale `1db4211` è completata con successo.

## Aggiornamento 12 novembre — pagina Report (#86)

Report è una nuova destinazione nella navigazione desktop/mobile e nella
rotta `/report` (URL web `/#/report`), con selezione del mese. Mostra totale, numero e importo
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

Pubblicata il 12 novembre la release `/var/www/finn/releases/20261112-df9eccd`,
conservando `20261111-0623e8c`. Archivio di 17.196.619 byte, SHA-256
`6047a0d1ff83937a359955bcc87499a4808d8fc7ed8d6d2c5bf28d089534f17e`.
Tutti i 222 hash sono verificati sul server prima del cambio atomico del
symlink. Homepage e JavaScript pubblici HTTP 200; bundle pubblico identico
alla build, direttive no-store e Cloudflare BYPASS. La prova con i dati del
suo account nel browser reale resta da completare dall'utente.

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
