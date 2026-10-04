# Handoff Finn — da completare in una sessione locale

Preparato il 04/10/2026, a chiusura della sessione cloud del 26/09/2026.
Repo: `ecologicaleaving/finn` · branch di sviluppo: `test` · produzione: `master`.
Flusso di riferimento: repo `ecologicaleaving/workflow` → `FLUSSO.md`. In finn al posto di `beta` si usa `test`.

---

## 1. Stato attuale

### Già unito in `test` (merge commit)
| PR | Issue | Contenuto |
|---|---|---|
| #62 | #61 | CI: Flutter fissato a 3.35.7, `build_runner --build-filter="lib/**"`, `rxdart` aggiunto, niente più `\|\| true` |
| #53 | #45 | Spese offline mai caricate sul server + descrizione assente nel dettaglio spesa |
| #58 | #47 | «Rimborsato» rifiutato dal DB (`reimbursed_at`) + chip del dettaglio |
| #56 | #51 | Grafico dashboard sui mesi precedenti, refresh, entrate nella vista mensile |
| #54 | #49 | Eliminazione categorie con spese dentro (+ migration) |
| #55 | #52 | Scanner con migliaia, virgola decimale, spese ricorrenti |
| #59 | #50 | Totali Budget (solo budget di gruppo, niente entrate/rimborsate, «Varie» a €0) (+ migration) |
| #60 | #48 | Filtri lista spese, modifica gruppo/pagatore, spese doppie o resuscitate |

Le issue #45, #47–#52 e #61 sono ancora **aperte**: `Closes #N` scatta solo con il merge su `master`.

### Ancora aperto
- **PR #57 → `test`** (issue #46): falla di sicurezza sui gruppi, più rimuovi membro, elimina gruppo ed elimina account. CI verde, nessun conflitto con `test` al 26/09. **Va unita solo dopo aver applicato le sue migration** (vedi §2, fase 2).

---

## 2. Migration Supabase da applicare

Progetto: `ofsnyaplaowbduujuucb`. SQL editor: https://supabase.com/dashboard/project/ofsnyaplaowbduujuucb/sql/new

Tutte le migration sono nuove e idempotenti (`CREATE OR REPLACE`, `DROP ... IF EXISTS`) e non modificano quelle esistenti.

### Fase 1 — subito (non rompono l'app in produzione)
1. `supabase/migrations/20260926_49_fix_category_expense_count_and_batch_reassign.sql` (branch `test`)
   - Ridefinisce `get_category_expense_count(TEXT)` e `batch_update_expense_category(UUID, TEXT, TEXT)` perché lavorino su `category_id` invece che sulla vecchia colonna `category`.
2. `supabase/migrations/20260926_50_budget_stats_group_only_exclude_income_reimbursed.sql` (branch `test`)
   - Ridefinisce `get_category_budget_stats`, `get_overall_group_budget_stats` e `ensure_altro_category_budget`: solo budget di gruppo, esclusione di entrate e spese rimborsate.

Verifica dopo l'applicazione:
```sql
SELECT proname FROM pg_proc WHERE proname IN
 ('get_category_expense_count','batch_update_expense_category',
  'get_category_budget_stats','get_overall_group_budget_stats','ensure_altro_category_budget');
```

### Fase 2 — insieme al rilascio della nuova app (PR #57)
⚠️ Dopo queste migration l'app oggi su `master` **non riesce più a creare gruppi né a entrarci**: scriveva `profiles.group_id` direttamente, e ora un trigger lo blocca. Quindi l'ordine è:

1. **Controllo preliminare.** Confronta le policy in produzione con quelle che la migration si aspetta: `"Users can update own profile"`, `"Anyone can validate invite codes"` e `"Users can use invites"` dalla 002, poi le policy admin della 004.
   ```sql
   SELECT tablename, policyname, cmd, qual, with_check FROM pg_policies
   WHERE schemaname='public' AND tablename IN ('profiles','invites') ORDER BY 1,2;
   SELECT tgname FROM pg_trigger WHERE tgrelid='public.profiles'::regclass AND NOT tgisinternal;
   ```
   Se trovi policy diverse o in più, leggi prima `20260926_46_secure_group_membership.sql` e adattala.
2. Applica, in quest'ordine (branch `feature/issue-46`):
   1. `supabase/migrations/20260926_46_secure_group_membership.sql`
   2. `supabase/migrations/20260926_46_account_deletion.sql`
3. Verifica:
   ```sql
   SELECT proname FROM pg_proc WHERE proname IN
    ('validate_invite_code','join_group_with_code','leave_group','remove_group_member',
     'delete_family_group','create_family_group','delete_my_account','prevent_profile_membership_change');
   SELECT tgname FROM pg_trigger WHERE tgname='trg_profiles_protect_membership';
   ```
4. Unisci la PR #57 in `test` con merge commit, mai squash.
5. Prova dal vivo sull'APK di `test`: crea un gruppo, genera un invito, entra con un secondo account, rimuovi il membro, poi lascia o elimina il gruppo ed elimina un account di prova.
6. Rilascia su `master` il prima possibile (§3): finché non c'è il rilascio, gli utenti con l'app vecchia non possono creare gruppi né entrarci.

Cambi di comportamento della #57, da comunicare:
- L'admin non può lasciare il gruppo se ci sono altri membri. Se è rimasto solo, uscire elimina il gruppo.
- «Elimina gruppo» funziona solo se l'admin è l'ultimo membro rimasto.
- «Elimina account» cancella davvero l'utente da `auth.users`. Le sue spese restano nel gruppo, con l'autore a NULL e anonimizzate se richiesto.

---

## 3. Rilascio in produzione (`test` → `master`)
Segui la skill `dev-workflow` / `.claude/commands/dev-workflow.md` del repo (versioning MAJOR.MINOR.PATCH+BUILD, tag) e FLUSSO §6:
- PR `test` → `master` con tutti i `Closes #45 #46 #47 #48 #49 #50 #51 #52 #61`, merge con `--merge`.
- Aggiorna `PROJECT.md`: versione e nota «Flutter fissato a 3.35.7 in CI».
- Su push a `master` la CI produce l'APK release (flavor `production`) e la GitHub Release.

---

## 4. Note tecniche importanti
- **Flutter / build_runner**: `pubspec.lock` è in `.gitignore`, quindi le dipendenze vengono risolte a ogni build. Con Flutter ≥ 3.38 circa (Dart ≥ 3.10), l'analyzer 7.x usato da `riverpod_generator` 2.x **si blocca**. Per generare il codice in locale usa **Flutter 3.35.7**, come la CI. La soluzione definitiva è passare a Riverpod 3 / `riverpod_generator` 3+: da aprire come issue a parte.
- `build_runner` va lanciato con `--build-filter="lib/**"`. Due test obsoleti in `test/features/budgets/personal/` hanno `@GenerateMocks` non validi (importano `package:fin/...`).
- **Test che falliscono già su `test`** (obsoleti, non regressioni): `expense_tabs_screen_test` (5), `expense_detail_screen_test`, `expense_list_offline_test`, `receipt_image_viewer_test`, e più file in `test/features/budgets/wizard|personal` che non si caricano per mock mancanti.
- In `lib/` restano circa 235 errori dell'analyzer, in codice non raggiungibile da `main.dart`: per esempio `lib/app/background_tasks.dart` e alcuni DAO. L'app compila (`flutter build bundle` ok).

---

## 5. Bug noti non ancora corretti (priorità 3 del check generale del 26/09)
Da trasformare in issue con AC taggati (FLUSSO §1) e passare al dev-loop:
1. **Cambio account sullo stesso telefono**: il widget home e la cache del gruppo in secure storage (`cached_group_data`) possono mostrare i dati dell'utente precedente. Nessuna pulizia al logout.
2. **Cambio nome nel profilo**: `groupProvider` fa `ref.watch(authProvider)` e si azzera a ogni cambio di auth, quindi il gruppo «sparisce» dalla dashboard fino al riavvio.
3. **Paginazione lista spese**: con spese non ancora sincronizzate le pagine contengono doppioni e saltano righe (`_mergeWithPendingCachedExpenses` aggiunge le pending a ogni pagina). Manca anche un ordinamento secondario stabile (ordina solo per `date`).
4. **Cache Hive**: le spese eliminate da un altro membro ricompaiono offline, perché `cacheExpenses` non rimuove mai nulla.
5. **Fonti di entrata eliminate su un altro device** restano nella cache Drift (`getIncomeSources`).
6. **Mezzanotte**: il `CHECK (date <= CURRENT_DATE)` è valutato in UTC, quindi tra 00:00 e 02:00 italiane una spesa con data di oggi viene rifiutata. **Issue #66: lato codice risolto (helper `toServerDate`, test); migration `20261004_66_expenses_date_check_europe_rome.sql` in attesa di essere applicata a mano da Davide.** Le spese rifiutate restano in coda e passano da sole.
7. **Scontrini PDF** salvati come `.jpg`/`image/jpeg`, poi non si aprono. Un salvataggio offline perde l'immagine dello scontrino.
8. **Riquadro «GRUPPO»** nella schermata Budget = budget categorie − entrate, che può dare un valore negativo (`budget_overview_card.dart`).
9. **Spese ricorrenti**:
   - lo scheduler in background (`BackgroundTasks.registerAllTasks`) non viene mai registrato;
   - le istanze generate non vengono messe in coda per la sync;
   - i template esistono solo in locale (Drift) e non arrivano mai su Supabase;
   - la riserva budget è quasi sempre 0.
10. **Migration storiche rischiose** (045/047/061): solo documentare, non riapplicare.
11. **Sync offline di update/delete**: le RPC `batch_update_expenses`/`batch_delete_expenses` (migration 044) usano la colonna `user_id`, che non esiste più. Oggi l'app non le usa.

---

## 6. Pulizia
- Il branch `claude/upbeat-planck-vnal0m` è già unito (PR #53): si può eliminare. Idem `feature/issue-47..52`, `feature/issue-61` dopo i merge.
- Il Kanban GitHub non è stato aggiornato: spostare le issue unite in «Test».
