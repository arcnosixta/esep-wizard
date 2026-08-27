-- ============================================================
-- ESEP: XPayment интеграциясы (xpayment.kz → Kaspi Pay API)
-- Supabase SQL Editor-де бір рет іске қосу.
--
-- payments кестесінің CHECK-шектеулерін кеңейтеміз:
--   method   += 'bank', 'kaspi_online', 'xpayment'
--   provider += 'kaspi', 'xpayment'
-- ============================================================

ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_method_check;
ALTER TABLE payments ADD CONSTRAINT payments_method_check
  CHECK (method IN ('kaspi', 'kaspi_online', 'xpayment', 'bank', 'card', 'manual'));

ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_provider_check;
ALTER TABLE payments ADD CONSTRAINT payments_provider_check
  CHECK (provider IN ('manual', 'paybox', 'kaspi_api', 'kaspi', 'xpayment'));

CREATE INDEX IF NOT EXISTS idx_payments_provider_tx ON payments(provider_tx_id);

-- Аудиторский след
INSERT INTO activity_logs (user_id, action, details)
SELECT NULL, 'migration',
       '{"message": "payments constraints extended for xpayment (method/provider)",
         "source": "supabase_xpayment.sql"}'::jsonb
WHERE NOT EXISTS (
  SELECT 1 FROM activity_logs
  WHERE action = 'migration'
    AND details->>'message' LIKE '%constraints extended for xpayment%'
);
