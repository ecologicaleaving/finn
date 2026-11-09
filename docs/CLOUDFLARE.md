# Pubblicare Finn su Cloudflare

Destinazione richiesta: **https://finn.8020solutions.org**.
Hosting predisposto: Cloudflare Worker con asset statici, nome **`finn-web`**.
La configurazione è in `wrangler.jsonc`. Il backend rimane Supabase dell'app.

## Dominio e DNS

| Campo | Valore |
| --- | --- |
| Zona Cloudflare | `8020solutions.org` |
| Nome del sottodominio | `finn` |
| Host completo | `finn.8020solutions.org` |
| Servizio destinatario | Worker `finn-web` |
| Collegamento | Custom Domain del Worker |
| Record DNS e certificato HTTPS | Creati e gestiti da Cloudflare al collegamento |

Il Worker deve essere prima pubblicato nell'account che possiede la zona.
Dal pannello: **Workers & Pages → finn-web → Settings → Domains & Routes →
Add → Custom Domain**, quindi inserire `finn.8020solutions.org`.

Il deploy con il file Wrangler già predisposto effettua anche il collegamento.
Non occorre scegliere un IP, creare un record A o indovinare un CNAME.
Un CNAME preesistente sullo stesso host impedisce di aggiungere il Custom Domain:
controllare che il nome sia libero prima del collegamento.

Riferimento: [Cloudflare Custom Domains](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/).

## Build

Usare **Flutter 3.35.7**, come la CI. Dalla radice del checkout:

```powershell
flutter pub get
dart run build_runner build --delete-conflicting-outputs --build-filter="lib/**"
./scripts/build-web.ps1 -SourceEnv .env
```

Il file sorgente deve fornire `SUPABASE_URL` e `SUPABASE_ANON_KEY` dello stesso
progetto dell'app. In alternativa, impostare queste due variabili nell'ambiente.
Lo script include solo questi valori pubblici e ripristina il `.env` originale
al termine. Rifiuta chiavi `service_role`, token utente e chiavi segrete.
Con un SDK fuori dal PATH passare anche `-Flutter C:/percorso/bin/flutter.bat`.

L'output è `build/web`. La pipeline **Build Finn Web** produce lo stesso
output come artifact `finn-web`; non pubblica automaticamente il sito.

## Deploy

Richiede un accesso Cloudflare autorizzato nell'account della zona:

```powershell
npx --yes wrangler@4.158.0 login --use-keyring
npx --yes wrangler@4.158.0 deploy
```

`--use-keyring` conserva le credenziali cifrate nel portachiavi del sistema.
Il flusso device richiede anche `--device`; un codice scaduto va rigenerato.
Il deploy carica solo `build/web`, non il codice sorgente né il `.env` locale.

Per validare il pacchetto senza pubblicare:

```powershell
npx --yes wrangler@4.158.0 deploy --dry-run
```

La build usa il service worker Flutter offline-first e risorse locali per
CanvasKit, SQLite e PDF.js. Dopo la prima apertura online, viene richiesta
la cache completa degli asset; attendere che il primo caricamento termini
prima della prova offline.
Lo script di build esclude dal manifest offline i file di configurazione
`_headers`, `_redirects` e `.assetsignore`: Cloudflare li interpreta e non li
serve come risorse scaricabili.

## Verifica dopo il deploy

Verificare HTTPS e apertura del sito, poi eseguire i passaggi in
[WEB_PARITY.md](WEB_PARITY.md) con un account di prova autorizzato.
Login e confronto delle modifiche con l'app richiedono una prova reale:
test unitari e compilazione non certificano da soli la parità funzionale.

Per i link di conferma email e recupero account, verificare anche i redirect
consentiti nel progetto Supabase (Authentication → URL Configuration) per il
nuovo dominio. L'accesso email/password riusa le credenziali già esistenti.
