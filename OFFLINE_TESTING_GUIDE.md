# Guida Test Offline — Issue #30

## T15: Test su device reale in airplane mode

### Prerequisiti
- Device Android fisico (emulatore non è affidabile per timeout test)
- App installata in modalità debug (`flutter run --debug`) o release
- Account Supabase con almeno una spesa già caricata

---

## Test Procedure

### Test 1: Avvio in Airplane Mode (AC primario)

1. Apri l'app mentre sei **online** → aspetta che carichi completamente
2. Vai in **Impostazioni > Airplane Mode ON**
3. Chiudi l'app completamente (swipe up dal task switcher)
4. Riapri l'app

**Atteso:**
- App si apre entro 2-3 secondi (Supabase.initialize() fa timeout dopo 10s ma runApp() parte subito)
- Schermata principale visibile senza spinner infinito
- Le spese dalla cache locale sono visibili
- Banner arancione "Offline - X spese in attesa" NON compare (a meno che non ci siano spese offline)

**Fallimento:**
- Spinner infinito dopo 10+ secondi → T1 o T2 non funziona
- App crasha → controllare log con `adb logcat | grep flutter`
- Redirect a login → T2 fallback Hive non funziona

---

### Test 2: Aggiunta Spesa Offline

1. Continua con Airplane Mode ON
2. Premi il bottone "+" e aggiungi una nuova spesa
3. Completa il form e salva

**Atteso:**
- La spesa viene salvata localmente (Drift DB)
- Compare banner arancione "Offline - 1 spesa in attesa di sync"
- La spesa appare nella lista (dalla cache offline)

**Fallimento:**
- Errore durante salvataggio → T8 write-through non funziona
- Banner non compare → T10 non integrato

---

### Test 3: Sync al Ritorno Online

1. Con la spesa offline in coda, **disabilita Airplane Mode**
2. Aspetta 5-10 secondi

**Atteso:**
- Banner cambia a "Sincronizzazione in corso..."
- Dopo sync completato, banner scompare
- La spesa è ora visibile su altri device con lo stesso account

**Fallimento:**
- Sync non parte automaticamente → T9 SyncTrigger non funziona
- La spesa non arriva su Supabase → BatchSyncService ha errori

---

### Test 4: Riavvio App in Airplane Mode

1. Con Airplane Mode ON, aggiungi 2-3 spese offline
2. Chiudi l'app completamente
3. Riapri

**Atteso:**
- Le spese offline persistono (Drift database)
- Banner mostra "Offline - 2-3 spese in attesa"
- Riconnettiti → sync automatico

---

### Test 5: Categorie Offline

1. Apri app online → vai alla schermata aggiungi spesa
2. Attiva Airplane Mode
3. Prova ad aggiungere una spesa → verifica che le categorie siano presenti

**Atteso:**
- Categorie visibili (dalla cache Drift, T6)
- Nessun errore "categorie non disponibili"

---

## Comandi Utili per Debug

```bash
# Log flutter in real-time
adb logcat -s flutter

# Filtra solo messaggi offline
adb logcat -s flutter | grep -i "offline\|timeout\|cache\|sync"

# Svuota cache app (per test fresh start)
adb shell pm clear com.yourpackage.finn
```

---

## Checklist Acceptance Criteria

- [ ] App avviata in airplane mode mostra le spese cachate — nessuno spinner
- [ ] Aggiunta spesa offline → salvata localmente con stato "pending sync"
- [ ] Al ritorno della connessione → sync automatico con Supabase
- [ ] Categorie disponibili anche offline (cache Drift)
- [ ] Indicatore visivo chiaro per stato offline e spese in attesa
- [ ] Riavvio app in airplane mode → si apre normalmente
- [ ] Nessuna query Supabase senza timeout
