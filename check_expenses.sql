-- Verifica le spese da 600 euro
SELECT 
  id,
  amount,
  created_by,
  paid_by,
  is_group_expense,
  date,
  category_id
FROM expenses
WHERE amount = 600
ORDER BY created_at DESC
LIMIT 5;
