-- financial_fraud.sql
-- Fase 6: Monitor de Fraude Financiero y Disputas

CREATE TABLE IF NOT EXISTS public.suspicious_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    transaction_id VARCHAR(255), -- Referencia opcional a un ID de pago o retiro en Stripe/PlayStore
    amount DECIMAL(10, 2) NOT NULL,
    transaction_type VARCHAR(50) NOT NULL, -- 'chargeback', 'mass_withdrawal', 'suspicious_payment'
    status VARCHAR(50) NOT NULL DEFAULT 'pending', -- 'pending', 'resolved_refunded', 'resolved_banned', 'ignored'
    reason TEXT NOT NULL, -- Detalle del por qué se marcó como sospechoso
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_suspicious_user_id ON public.suspicious_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_suspicious_status ON public.suspicious_transactions(status);

-- Trigger para updated_at (asume que la función update_updated_at_column() ya existe en schema.sql)
DROP TRIGGER IF EXISTS update_suspicious_updated_at ON public.suspicious_transactions;
CREATE TRIGGER update_suspicious_updated_at
BEFORE UPDATE ON public.suspicious_transactions
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();
