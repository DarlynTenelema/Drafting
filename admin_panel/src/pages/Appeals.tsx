import React, { useState, useEffect } from 'react';
import { AlertCircle, CheckCircle, Ban, Clock } from 'lucide-react';

export const Appeals = () => {
  const [appeals, setAppeals] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(false);

  useEffect(() => {
    fetchAppeals();
  }, []);

  const fetchAppeals = async () => {
    setIsLoading(true);
    try {
      const response = await fetch('/api/v1/admin_panel/appeals');
      if (response.ok) {
        const data = await response.json();
        setAppeals(data || []);
      }
    } catch (e) {
      console.error('Failed to fetch appeals', e);
      // Fallback mock if backend is down
      setAppeals([
        { id: '1', user: { Email: 'juan@lol.com' }, message: 'Por favor, no fue mi intención insultar, solo me frustré en la ranked. Perdonen.', status: 'pending', created_at: new Date().toISOString() },
        { id: '2', user: { Email: 'toxic_boy@lol.com' }, message: 'Me da igual, háganlo.', status: 'rejected', created_at: new Date().toISOString() }
      ]);
    } finally {
      setIsLoading(false);
    }
  };

  const resolveAppeal = async (id: string, status: string) => {
    try {
      const response = await fetch(`/api/v1/admin_panel/appeals/${id}/resolve`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status })
      });
      if (response.ok) {
        fetchAppeals();
      }
    } catch (e) {
      console.error(e);
      // Simulate frontend change if mock
      setAppeals(prev => prev.map(a => a.id === id ? { ...a, status } : a));
    }
  };

  return (
    <div className="animated">
      <div className="header" style={{ marginBottom: '32px' }}>
        <div>
          <h1>Apelaciones de Ban (7 Días)</h1>
          <p style={{ color: 'var(--text-secondary)', marginTop: '8px' }}>Revisa las justificaciones de usuarios con 3 strikes antes del baneo definitivo.</p>
        </div>
      </div>

      {isLoading ? (
        <div style={{ color: 'white' }}>Cargando...</div>
      ) : (
        <div style={{ display: 'grid', gridTemplateColumns: '1fr', gap: '24px' }}>
          {appeals.length === 0 && <div style={{ color: 'var(--text-secondary)' }}>No hay apelaciones pendientes.</div>}
          
          {appeals.map(a => {
            const isPending = a.status === 'pending';
            return (
              <div key={a.id} className="glass-panel" style={{ padding: '24px', borderLeft: isPending ? '4px solid var(--warning)' : '4px solid var(--border-glass)' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                    <div style={{ width: 40, height: 40, borderRadius: '50%', background: 'var(--bg-secondary)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                      <AlertCircle color="var(--warning)" />
                    </div>
                    <div>
                      <h3 style={{ margin: 0, fontSize: '16px' }}>{a.user?.Email || 'Usuario Desconocido'}</h3>
                      <span style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>
                        <Clock size={12} style={{ display: 'inline', verticalAlign: 'middle', marginRight: 4 }} />
                        Enviada: {new Date(a.created_at).toLocaleDateString()}
                      </span>
                    </div>
                  </div>
                  
                  {isPending ? (
                    <span className="badge" style={{ background: 'var(--warning)', color: '#000', fontWeight: 'bold' }}>Requiere Veredicto</span>
                  ) : (
                    <span className="badge" style={{ border: '1px solid var(--text-secondary)', color: 'var(--text-secondary)' }}>
                      {a.status === 'approved' ? 'Perdonado' : 'Baneado'}
                    </span>
                  )}
                </div>

                <div style={{ background: 'rgba(0,0,0,0.2)', padding: '16px', borderRadius: '8px', border: '1px solid var(--border-glass)' }}>
                  <p style={{ color: 'white', fontStyle: 'italic', margin: 0 }}>"{a.message}"</p>
                </div>

                {isPending && (
                  <div style={{ display: 'flex', gap: '16px', marginTop: '24px' }}>
                    <button 
                      onClick={() => resolveAppeal(a.id, 'rejected')}
                      style={{ flex: 1, padding: '12px', borderRadius: '8px', background: 'rgba(239, 68, 68, 0.1)', color: 'var(--danger)', border: '1px solid rgba(239, 68, 68, 0.2)', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px', fontWeight: 600 }}>
                      <Ban size={18} /> Rechazar y Banear Permanentemente
                    </button>
                    <button 
                      onClick={() => resolveAppeal(a.id, 'approved')}
                      style={{ flex: 1, padding: '12px', borderRadius: '8px', background: 'rgba(16, 185, 129, 0.1)', color: 'var(--success)', border: '1px solid rgba(16, 185, 129, 0.2)', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px', fontWeight: 600 }}>
                      <CheckCircle size={18} /> Perdonar (Restaurar Cuenta)
                    </button>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};
