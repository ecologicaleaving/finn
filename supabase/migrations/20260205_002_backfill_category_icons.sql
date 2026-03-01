-- Migration: Backfill category icons using Italian keyword matching
-- Feature: 014-category-icons
-- Date: 2026-02-05
-- Purpose: Automatically assign appropriate icons to existing categories

-- Backfill icons using Italian keyword matching
UPDATE public.expense_categories
SET icon_name = CASE
  WHEN LOWER(name) LIKE '%spesa%' OR LOWER(name) LIKE '%alimentari%' THEN 'shopping_cart'
  WHEN LOWER(name) LIKE '%ristorante%' OR LOWER(name) LIKE '%cibo%' THEN 'restaurant'
  WHEN LOWER(name) LIKE '%benzina%' OR LOWER(name) LIKE '%carburante%' THEN 'local_gas_station'
  WHEN LOWER(name) LIKE '%trasporti%' OR LOWER(name) LIKE '%taxi%' THEN 'directions_bus'
  WHEN LOWER(name) LIKE '%casa%' OR LOWER(name) LIKE '%affitto%' THEN 'home'
  WHEN LOWER(name) LIKE '%bollette%' OR LOWER(name) LIKE '%utenze%' THEN 'receipt_long'
  WHEN LOWER(name) LIKE '%salute%' OR LOWER(name) LIKE '%farmacia%' THEN 'medical_services'
  WHEN LOWER(name) LIKE '%sport%' OR LOWER(name) LIKE '%palestra%' THEN 'fitness_center'
  WHEN LOWER(name) LIKE '%svago%' OR LOWER(name) LIKE '%divertimento%' THEN 'celebration'
  WHEN LOWER(name) LIKE '%abbigliamento%' OR LOWER(name) LIKE '%vestiti%' THEN 'checkroom'
  WHEN LOWER(name) LIKE '%tecnologia%' OR LOWER(name) LIKE '%elettronica%' THEN 'devices'
  WHEN LOWER(name) LIKE '%istruzione%' OR LOWER(name) LIKE '%scuola%' THEN 'school'
  WHEN LOWER(name) LIKE '%viaggio%' OR LOWER(name) LIKE '%vacanza%' THEN 'flight'
  WHEN LOWER(name) LIKE '%regalo%' THEN 'card_giftcard'
  WHEN LOWER(name) LIKE '%animali%' OR LOWER(name) LIKE '%pet%' THEN 'pets'
  ELSE 'category'
END
WHERE icon_name IS NULL;
