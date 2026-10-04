-- Issue #66: il vincolo inline `CHECK (date <= CURRENT_DATE)` su public.expenses
-- (001_initial_schema.sql, nome automatico expenses_date_check) usa il TimeZone
-- della sessione Supabase (UTC): tra 00:00 e 02:00 italiane rifiuta le spese
-- del giorno locale con 23514 check_violation.
-- Fix: lo sostituisce con un controllo sulla data di Europe/Rome.
-- Idempotente. Nessun UPDATE/DELETE/VALIDATE: le righe esistenti non si toccano.
-- APPLICAZIONE MANUALE (Davide).
-- Rollback: ALTER TABLE public.expenses DROP CONSTRAINT IF EXISTS expenses_date_not_future_rome;
--   e, per il vecchio comportamento:
--   ALTER TABLE public.expenses ADD CONSTRAINT expenses_date_check CHECK (date <= CURRENT_DATE) NOT VALID;

BEGIN;

DO $$
DECLARE
  c record;
BEGIN
  FOR c IN
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'public.expenses'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%CURRENT_DATE%'
  LOOP
    EXECUTE format('ALTER TABLE public.expenses DROP CONSTRAINT IF EXISTS %I', c.conname);
  END LOOP;
END $$;

ALTER TABLE public.expenses DROP CONSTRAINT IF EXISTS expenses_date_check;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.expenses'::regclass
      AND conname = 'expenses_date_not_future_rome'
  ) THEN
    ALTER TABLE public.expenses
      ADD CONSTRAINT expenses_date_not_future_rome
      CHECK (date <= (now() AT TIME ZONE 'Europe/Rome')::date) NOT VALID;
  END IF;
END $$;

COMMIT;
