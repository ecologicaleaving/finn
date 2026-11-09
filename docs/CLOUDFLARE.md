# Finn su VPS con DNS Cloudflare

Indirizzo: **https://finn.8020solutions.org**. La build Flutter viene servita da
Nginx sul VPS; Cloudflare gestisce DNS e proxy. Account e dati rimangono nel
progetto Supabase usato dall'app.

Il sito è online dal 9 novembre 2026. HTTPS restituisce 200 sia tramite il
proxy Cloudflare sia contattando direttamente l'origine con il nome corretto.
La verifica dei flussi autenticati è separata ed è registrata in
[WEB_VERIFICATION.md](WEB_VERIFICATION.md).

## Destinazione

| Campo | Valore |
| --- | --- |
| Zona DNS | `8020solutions.org` |
| Record creato dall'utente | `A finn → 46.225.60.101` |
| Proxy Cloudflare | Attivo, TTL automatico |
| Origine | VPS `46.225.60.101`, Nginx 1.24 |
| Directory delle release | `/var/www/finn/releases/` |
| Radice pubblicata | Symlink `/var/www/finn/current` |
| Release iniziale | `/var/www/finn/releases/20261109-db42319` |
| Certificato origine | `/etc/letsencrypt/live/finn.8020solutions.org/` |
| Webroot ACME | `/var/www/letsencrypt` |

La precedente configurazione Wrangler è stata rimossa per mantenere una sola
destinazione di deploy. Le configurazioni Nginx dedicate al dominio sono in
[`deploy/nginx`](../deploy/nginx/).

## Build

Usare **Flutter 3.35.7**, come la CI, dalla radice del checkout:

```powershell
flutter pub get
dart run build_runner build --delete-conflicting-outputs --build-filter="lib/**"
./scripts/build-web.ps1 -SourceEnv .env
```

Il file sorgente fornisce `SUPABASE_URL` e `SUPABASE_ANON_KEY` dello stesso
progetto dell'app. Si possono anche impostare queste variabili nell'ambiente.
Lo script include solo i valori client pubblici e ripristina il `.env`
originale al termine; rifiuta chiavi di servizio e token utente.
Con un SDK fuori dal PATH usare `-Flutter C:/percorso/bin/flutter.bat`.

L'output è `build/web`. La pipeline **Build Finn Web** produce lo stesso
output come artifact `finn-web`; il deploy sul VPS è manuale.

La build include CanvasKit, SQLite e PDF.js locali. Il service worker Flutter
offline-first precarica gli asset dopo il primo frame. Lo script
`prepare-cloudflare-web.ps1` esclude `_headers`, `_redirects` e `.assetsignore`
dal manifest offline; le configurazioni Nginx ne impediscono il download.
Il nome dello script rimane per compatibilità con la pipeline esistente.

## Installazione Nginx e HTTPS

Questi sono i file del sito, da copiare sul VPS preservando le altre
configurazioni Nginx:

| File nel repo | Destinazione sul VPS |
| --- | --- |
| `deploy/nginx/finn-static.conf` | `/etc/nginx/snippets/finn-static.conf` |
| `deploy/nginx/finn-http.conf` | `/etc/nginx/sites-available/finn.8020solutions.org` nella fase ACME |
| `deploy/nginx/finn-https.conf` | `/etc/nginx/sites-available/finn.8020solutions.org` dopo l'emissione del certificato |

Il sito è abilitato da `/etc/nginx/sites-enabled/finn.8020solutions.org`. La configurazione HTTP
iniziale serve solo `/.well-known/acme-challenge/`; le altre richieste
restituiscono 404 fino all'attivazione di HTTPS.

1. Creare `/var/www/letsencrypt/.well-known/acme-challenge/`, installare la
   configurazione HTTP, eseguire `nginx -t` e poi ricaricare Nginx.
2. Verificare che un file di prova ACME sia raggiungibile via HTTP sul dominio.
3. Emettere il certificato con l'account Certbot esistente:

   ```sh
   certbot certonly --non-interactive --webroot \
     --webroot-path /var/www/letsencrypt \
     --domain finn.8020solutions.org
   ```

4. Installare `finn-static.conf` e la configurazione HTTPS, eseguire `nginx -t`
   e ricaricare Nginx. Il certificato deve esistere prima di questa fase.
5. Verificare la connessione Cloudflare→origine con **Full (strict)** e il
   rinnovo Certbot. Il percorso ACME resta disponibile su HTTP anche dopo il
   passaggio al redirect HTTPS.

Il certificato iniziale è stato emesso il 9 novembre 2026 e scade il
7 febbraio 2027. Il timer Certbot risulta attivo. Installare
`deploy/certbot/finn-nginx-reload.sh` come
`/etc/letsencrypt/renewal-hooks/deploy/finn-nginx-reload`, con permessi 0755:
l'hook controlla il percorso `RENEWED_LINEAGE` e, solo per il certificato di
Finn, esegue `nginx -t` prima di ricaricare Nginx. Gli altri certificati non
attivano questa operazione. Validare il file con `sh -n` e provare il rinnovo
del solo certificato Finn con Certbot in modalità dry-run.

Il rinnovo simulato con esecuzione dell'hook è riuscito, con uscita 0:

```sh
certbot renew --cert-name finn.8020solutions.org --dry-run \
  --run-deploy-hooks --no-random-sleep-on-renew
```

`nginx -t` e il reload dell'hook sono riusciti. I warning rimasti riguardano
configurazioni preesistenti di altri domini sul VPS.

Le regole di cache Cloudflare devono rispettare `Cache-Control` dell'origine.
Le modalità TLS e i requisiti del certificato sono descritti nella
[documentazione Cloudflare](https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/full-strict/).

La configurazione condivisa imposta i MIME corretti per `.wasm` e `.mjs`,
abilita gzip sugli asset comprimibili e restituisce 404 per gli asset mancanti.
I percorsi dell'app usano il fallback a `index.html`. Tutti i file della build
hanno `Cache-Control: no-store, no-cache, max-age=0, must-revalidate`: i nomi
non contengono una versione e devono essere rivalidati dopo un aggiornamento;
la cache offline del service worker
rimane separata dalla cache HTTP.

## Release atomiche

Pubblicare il solo contenuto di `build/web`, usando una nuova directory per ogni
release. Conservare la precedente per poter ripristinare il symlink.

**Lo ZIP Windows di questa lavorazione contiene separatori `\` nei nomi delle
entry.** L'estrazione sul VPS deve normalizzarli in `/` e verificare che ogni
percorso risolto rimanga nella directory della nuova release. Il deploy iniziale
usa Python 3 per questa estrazione; un semplice `unzip` non produce la struttura
corretta per questo archivio. Rifiutare percorsi assoluti, `..` e collegamenti
simbolici nell'archivio. Applicare permessi 755 alle directory e 644 ai file.

Controllare hash dell'archivio e presenza di `index.html`, `main.dart.js`,
`flutter_service_worker.js`, `sqlite3.wasm` e `pdfjs/pdf.min.mjs`. La directory
pubblicata non contiene il sorgente del progetto o chiavi di servizio.

Dopo l'estrazione e le verifiche, un aggiornamento del symlink è atomico:

```sh
release=/var/www/finn/releases/NOME_RELEASE_VERIFICATA
nginx -t
ln -s "$release" /var/www/finn/current.next
mv -Tf /var/www/finn/current.next /var/www/finn/current
```

`current.next` deve essere libero prima dell'operazione. Un cambio della sola
release statica non richiede il riavvio di Nginx. Per tornare indietro si usa
lo stesso procedimento con la directory della release precedente.

## Verifica dopo il deploy

Controllare tramite il dominio pubblico:

- HTTPS e certificato valido; HTTP reindirizza a HTTPS.
- `/`, `/index.html` e una rotta dell'app restituiscono il documento Flutter.
- `sqlite3.wasm` ha MIME `application/wasm`; `pdfjs/pdf.min.mjs` ha MIME JavaScript.
- Bootstrap, `main.dart.js`, index e service worker conservano anche tramite
  Cloudflare `no-store, no-cache, max-age=0, must-revalidate`.
- Un nome di asset inesistente restituisce 404.

Nel deploy iniziale questi controlli sono riusciti: gli asset critici
restituiscono 200 con MIME corretti e Cloudflare riporta `BYPASS` per
`main.dart.js` e il service worker con le direttive di cache sopra indicate.
Tutti i 222 file del manifest offline sul VPS hanno MD5 uguale alla build.

La prova diretta dell'origine, dopo l'installazione del certificato, usa:

```sh
curl --resolve finn.8020solutions.org:443:46.225.60.101 \
  --head https://finn.8020solutions.org/
```

Eseguire quindi [WEB_PARITY.md](WEB_PARITY.md) con un account di prova
autorizzato. Compilazione e test dello store non certificano il login reale o
il confronto delle modifiche con l'app. Per conferme email e recupero account,
verificare i redirect ammessi in Supabase → Authentication → URL Configuration
per il nuovo dominio. Lo stato delle prove è in [WEB_VERIFICATION.md](WEB_VERIFICATION.md).
