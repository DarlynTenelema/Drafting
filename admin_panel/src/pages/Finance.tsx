import React, { useState } from 'react';
import { Activity, AlertTriangle, ShieldCheck, Ban, DollarSign } from 'lucide-react';

const mockTransactions = [
  { id: '1', user: 'carlos@example.com', txId: 'ch_1Mxyz...', amount: 450.00, type: 'chargeback', reason: 'El usuario solicitó un contracargo en el banco tras donar a un creador.', status: 'pending', date: '2026-08-24 10:00 AM' },
  { id: '2', user: 'hacker_boy', txId: 'wd_88Aas...', amount: 12000.00, type: 'mass_withdrawal', reason: 'Intento de retiro inusualmente grande de GoldenCoins en una cuenta nueva.', status: 'pending', date: '2026-08-23 22:15 PM' },
  { id: '3', user: 'ana.creadora@example.com', txId: 'pi_3Axyz...', amount: 15.00, type: 'suspicious_payment', reason: 'Múltiples intentos fallidos de tarjeta antes de aprobarse.', status: 'resolved_refunded', date: '2026-08-22 14:30 PM' },
];

export const Finance = () => {
  const [transactions, setTransactions] = useState(mockTransactions);

  const handleResolve = (id: string, newStatus: string) => {
    setTransactions(prev => prev.map(t => t.id === id ? { ...t, status: newStatus } : t));
  };

  const getTypeStyle = (type: string) => {
    switch(type) {
      case 'chargeback': return { icon: <AlertTriangle size={16} />, color: 'var(--danger)', label: 'Contracargo' };
      case 'mass_withdrawal': return { icon: <DollarSign size={16} />, color: 'var(--warning)', label: 'Retiro Masivo' };
      case 'suspicious_payment': return { icon: <Activity size={16} />, color: 'var(--accent-secondary)', label: 'Pago Sospechoso' };
      default: return { icon: <Activity size={16} />, color: 'white', label: type };
    }
  };

  return (
    <div className="animated">
      <div className="header" style={{ marginBottom: '32px' }}>
        <div>
          <h1>Auditoría Financiera y Fraude</h1>
          <p style={{ color: 'var(--text-secondary)', marginTop: '8px' }}>Monitorea y resuelve contracargos o retiros inusuales para proteger la economía.</p>
        </div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(400px, 1fr))', gap: '24px' }}>
        {transactions.map(t => {
          const typeInfo = getTypeStyle(t.type);
          const isPending = t.status === 'pending';

          return (
            <div key={t.id} className="glass-panel" style={{ padding: '24px', borderLeft: `4px solid ${typeInfo.color}` }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '16px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px', color: typeInfo.color, fontWeight: 600 }}>
                  {typeInfo.icon}
                  {typeInfo.label}
                </div>
                {isPending ? (
                  <span className="badge" style={{ background: 'var(--accent-primary)', color: 'white' }}>Requiere Acción</span>
                ) : (
                  <span className="badge" style={{ border: '1px solid var(--text-secondary)', color: 'var(--text-secondary)' }}>Resuelto</span>
                )}
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px', marginBottom: '16px', background: 'var(--bg-secondary)', padding: '16px', borderRadius: 'var(--radius-md)' }}>
                <div>
                  <div style={{ fontSize: 12, color: 'var(--text-secondary)' }}>Usuario</div>
                  <div style={{ fontWeight: 500 }}>{t.user}</div>
                </div>
                <div>
                  <div style={{ fontSize: 12, color: 'var(--text-secondary)' }}>Monto Involucrado</div>
                  <div style={{ fontWeight: 700, fontSize: 16 }}>${t.amount.toFixed(2)} USD</div>
                </div>
                <div style={{ gridColumn: '1 / -1' }}>
                  <div style={{ fontSize: 12, color: 'var(--text-secondary)' }}>Motivo de Alarma</div>
                  <div style={{ color: 'var(--warning)', fontSize: 14 }}>{t.reason}</div>
                </div>
              </div>

              {isPending && (
                <div style={{ display: 'flex', gap: '12px', marginTop: '24px' }}>
                  <button 
                    onClick={() => handleResolve(t.id, 'resolved_banned')}
                    style={{ flex: 1, padding: '10px', borderRadius: 'var(--radius-sm)', background: 'rgba(239, 68, 68, 0.15)', color: 'var(--danger)', border: 'none', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px', fontWeight: 600, transition: 'all 0.2s' }}>
                    <Ban size={18} /> Banear y Retener
                  </button>
                  <button 
                    onClick={() => handleResolve(t.id, 'resolved_refunded')}
                    style={{ flex: 1, padding: '10px', borderRadius: 'var(--radius-sm)', background: 'rgba(16, 185, 129, 0.15)', color: 'var(--success)', border: 'none', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px', fontWeight: 600, transition: 'all 0.2s' }}>
                    <ShieldCheck size={18} /> Reembolsar
                  </button>
                </div>
              )}
            </div>
          )
        })}
      </div>
    </div>
  );
};
