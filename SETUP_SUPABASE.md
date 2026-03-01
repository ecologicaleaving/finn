# Finn - Setup Supabase

## 🎯 Configurazione

Finn usa **Supabase Cloud** (production) per uso personale/famiglia.

| Ambiente | URL | Note |
|----------|-----|------|
| **Production** | `https://ofsnyaplaowbduujuucb.supabase.co` | Supabase Cloud |
| **Dev locale** | `http://localhost:54321` | `supabase start` sul PC |

---

## 🔑 Credenziali

Le credenziali **NON** vanno nel repo. Sono gestite tramite:
- **GitHub Secrets**: `SUPABASE_URL` + `SUPABASE_ANON_KEY` → iniettate nel `.env` dal CI
- **Locale**: crea manualmente il file `.env` (vedi sotto)

### Setup locale PC

```bash
# Chiedi le credenziali a Davide o recuperale da:
# https://supabase.com/dashboard/project/ofsnyaplaowbduujuucb/settings/api
cat > .env << 'EOF'
SUPABASE_URL=https://ofsnyaplaowbduujuucb.supabase.co
SUPABASE_ANON_KEY=<anon key dal dashboard Supabase>
EOF
flutter run
```

---

## 🔍 Database

- **Dashboard**: https://supabase.com/dashboard/project/ofsnyaplaowbduujuucb
- **Project ID**: `ofsnyaplaowbduujuucb`
- **Backup**: automatico (gestito da Supabase Cloud)

---

## ⚠️ Regole workflow

1. **Mai** committare il file `.env` (è in `.gitignore`)
2. **Sempre** aggiornare i GitHub Secrets se le credenziali cambiano
3. Il CI inietta automaticamente le credenziali nel `.env` prima del build APK
4. Se il progetto Supabase Cloud viene sostituito → aggiornare:
   - GitHub Secrets (`SUPABASE_URL`, `SUPABASE_ANON_KEY`)
   - Questo file (`SETUP_SUPABASE.md`)
   - Il campo `Database` in `PROJECT.md`
