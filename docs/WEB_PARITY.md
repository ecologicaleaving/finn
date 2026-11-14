# Finn nel browser

La versione web usa lo stesso `main.dart`, le stesse schermate e gli stessi
repository della versione mobile non ancora pubblicata **v1.6.1**, commit
`586eace` (`release/v1.6.1`). Non introduce un secondo database remoto.

## Account e dati

`SUPABASE_URL` e `SUPABASE_ANON_KEY` devono identificare lo stesso progetto
Supabase dell'app. La configurazione web arriva dai `--dart-define`; il browser
non carica il `.env` di sviluppo. La chiave anon è pubblica: le autorizzazioni
restano quelle di Supabase Auth e delle policy RLS già usate dall'app.

Anche gli asset Flutter possono contenere `.env`: usare sempre lo script di
build web che lo sostituisce temporaneamente con una configurazione pubblica.
Le chiavi di servizio e di OCR restano nelle Edge Function.

## Adattamenti al browser

- Drift usa SQLite WebAssembly con worker e archivio persistente OPFS/IndexedDB.
  `web/drift_worker.js` e `web/sqlite3.wasm` vanno aggiornati insieme alla
  versione Drift fissata nel `pubspec.yaml`. Il server deve servire WASM con
  `Content-Type: application/wasm`.
- Gli scontrini salvati offline vengono conservati in Hive/IndexedDB nel
  browser. La stessa coda dell'app li carica su Supabase e li rimuove dopo la
  sincronizzazione. Su telefono restano file nella directory dell'app.
- Il selettore di file usa già i byte del documento, senza richiedere un
  percorso nel filesystem. I PDF vengono visualizzati con PDFx e PDF.js:
  libreria, worker e mappe dei caratteri sono serviti dal sito e disponibili
  nella cache offline.
- Fotocamera e caricamento richiedono i permessi del browser e HTTPS; resta
  disponibile il caricamento di un'immagine o PDF quando manca una fotocamera.
- A partire da 900 px la navigazione principale usa una barra laterale; su
  schermi piccoli mantiene la barra inferiore. I moduli di accesso hanno una
  larghezza massima di 480 px.
- Widget della schermata home del telefono, intent di condivisione nativi e
  job Android non vengono inizializzati sul web. La generazione delle
  ricorrenze e la sincronizzazione in primo piano restano condivise.

## Verifica funzionale prima di dichiarare la parità

Usare un account di prova autorizzato sullo stesso backend dell'app e registrare
gli esiti; una build riuscita da sola non verifica questi passaggi.

1. Accedere con lo stesso account e confrontare gruppo, saldo e spese con l'app.
2. Creare una spesa dal sito, ritrovarla nell'app, modificarla ed eliminarla.
3. Provare entrate, filtri mensili, budget, categorie, metodi di pagamento,
   ricorrenze, rimborsi, profilo e gestione del gruppo.
4. Caricare uno scontrino immagine e uno PDF; aprirli nel dettaglio della spesa.
5. Salvare una spesa con scontrino mentre offline, ricaricare la pagina e poi
   riconnettersi: verificare una sola spesa sul server e il documento allegato.
6. Uscire e accedere con un secondo account: verificare che non compaiano i
   dati del precedente utente.
7. Ripetere navigazione e inserimento a 390 px e a 1440 px.

La cache locale appartiene al browser e all'origine del sito. La prima visita
richiede una connessione. Dopo il primo frame il sito invia `downloadOffline`
al service worker offline-first generato da Flutter 3.35.7, per precaricare in
background anche worker PDF e mappe dei caratteri. Il caricamento non blocca
l'interfaccia e richiede di restare online finché gli asset sono stati scaricati.
Cancellare i dati del sito elimina anche le spese non
ancora sincronizzate; i dati già salvati su Supabase restano sul server.
