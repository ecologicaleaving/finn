# Finn - Development Workflow Quick Reference

This project uses a dual-repository workflow with build flavors for parallel development and production.

## Quick Start

```bash
# Daily development
flutter run --flavor dev -d <device-id>

# Commit and push to test
git add . && git commit -m "message"
git push origin test

# Create production release
# See full workflow in .claude/commands/dev-workflow.md
```

## Repository Setup

- **Development (origin)**: ecologicaleaving/finn → `test` branch
- **Production (production)**: 80-20Solutions/finn → `master` branch

## Build Flavors

Two apps can coexist on the same device:
- **Fin** (production): `com.ecologicaleaving.fin` - Stable version for users
- **Fin Dev** (development): `com.ecologicaleaving.fin.dev` - Testing version

```bash
# Install dev version (daily testing)
flutter run --flavor dev -d <device-id>

# Install production version (stable)
flutter run --flavor production -d <device-id>
```

## Branching Strategy

```
origin (ecologicaleaving/finn)
├── test (main development)
├── feature/* (feature branches)
└── hotfix/* (hotfix branches)

production (80-20Solutions/finn)
└── master (stable releases only)
```

## Custom Skill

For detailed workflow instructions, use the custom skill:

```
/dev-workflow
```

Or refer to: `.claude/commands/dev-workflow.md`

This skill provides step-by-step guidance for:
- Daily development commits
- Creating production releases
- Semantic versioning
- Hotfix workflow
- Troubleshooting

## Firma release Android

La release di produzione (`--flavor production`) si firma con la chiave dedicata e MAI con quella di debug: senza firma configurata la build fallisce. Il flavor dev ripiega sulla chiave di debug.

- Locale: `android/key.properties` (vedi `android/key.properties.example`) oppure variabili `ANDROID_KEYSTORE_FILE`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
- CI (push su master): secret `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. Opzionale: repo variable `ANDROID_CERT_SHA256`.
- Base64 su una riga (PowerShell): `[Convert]::ToBase64String([IO.File]::ReadAllBytes('...\finn-release.p12'))`. Mai `certutil -encode` (aggiunge intestazioni).
- Se si perde il keystore l'app non si aggiorna piu: tenere un backup in un secondo posto sicuro.

## Important Rules

⚠️ **ALWAYS use `--flavor dev` for development**
⚠️ **NEVER push directly to production/master**
⚠️ **Test thoroughly on test branch before production release**

---

**Brand**: Finn - AI-powered family budget assistant
**Version**: See `pubspec.yaml`
