import React, { useState, useEffect } from 'react';
import { ShieldAlert, CheckCircle, Ban, ExternalLink, Clock } from 'lucide-react';

export const Verifications = () => {
  const [requests, setRequests] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(false);

  useEffect(() => {
    fetchVerifications();
  }, []);

  const fetchVerifications = async () => {
    setIsLoading(true);
    try {
      const response = await fetch('/api/v1/admin_panel/verifications');
      if (response.ok) {
        const data = await response.json();
        setRequests(data || []);
      } else {
        throw new Error('Failed to fetch');
      }
    } catch (e) {
      console.error('Failed to fetch verification requests', e);
      // Fallback mock
      setRequests([
        { 
          id: 'v-1', 
          channelId: 'ch_youtube_star', 
          channelName: 'El Rubius OMG', 
          proof_url: 'https://youtube.com/watch?v=unlisted_video_1',
          status: 'pending', 
          created_at: new Date().toISOString() 
        },
        { 
          id: 'v-2', 
          channelId: 'ch_gamer_pro', 
          channelName: 'Gamer Pro', 
          proof_url: 'https://drive.google.com/file/d/xxxxx/view',
          status: 'pending', 
          created_at: new Date().toISOString() 
        }
      ]);
    } finally {
      setIsLoading(false);
    }
  };

  const resolveRequest = async (id: string, status: 'approved' | 'rejected') => {
    try {
      const response = await fetch(`/api/v1/admin_panel/verifications/${id}/resolve`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status })
      });
      if (response.ok) {
        fetchVerifications();
      } else {
        throw new Error('Failed to resolve');
      }
    } catch (e) {
      console.error(e);
      // Simulate frontend change if mock
      setRequests(prev => prev.map(r => r.id === id ? { ...r, status } : r));
    }
  };

  return (
    <div className="animated">
      <div className="header" style={{ marginBottom: '32px' }}>
        <div>
          <h1>Verificaciones de Identidad</h1>
          <p style={{ color: 'var(--text-secondary)', marginTop: '8px' }}>
            Revisa los videos de prueba de canales grandes (+100k subs) y aprueba sus cuentas.
          </p>
        </div>
      </div>

      {isLoading ? (
        <div style={{ color: 'white' }}>Cargando...</div>
      ) : (
        <div style={{ display: 'grid', gridTemplateColumns: '1fr', gap: '24px' }}>
          {requests.filter(r => r.status === 'pending').length === 0 && (
            <div style={{ color: 'var(--text-secondary)' }}>No hay solicitudes de verificación pendientes.</div>
          )}
          
          {requests.filter(r => r.status === 'pending').map(req => (
            <div key={req.id} className="glass-panel" style={{ padding: '24px', borderLeft: '4px solid var(--warning)' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                  <div style={{ width: 40, height: 40, borderRadius: '50%', background: 'var(--bg-secondary)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                    <ShieldAlert color="var(--warning)" />
                  </div>
                  <div>
                    <h3 style={{ margin: 0, fontSize: '18px' }}>{req.channelName}</h3>
                    <span style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>
                      <Clock size={12} style={{ display: 'inline', verticalAlign: 'middle', marginRight: 4 }} />
                      Enviada: {new Date(req.created_at).toLocaleDateString()}
                    </span>
                  </div>
                </div>
                
                <span className="badge" style={{ background: 'var(--warning)', color: '#000', fontWeight: 'bold' }}>
                  Pendiente de Revisión
                </span>
              </div>

              <div style={{ background: 'rgba(0,0,0,0.2)', padding: '16px', borderRadius: '8px', border: '1px solid var(--border-glass)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <div>
                  <p style={{ color: 'var(--text-secondary)', fontSize: '12px', margin: '0 0 4px 0' }}>Enlace del Video de Prueba:</p>
                  <a href={req.proof_url} target="_blank" rel="noopener noreferrer" style={{ color: 'var(--accent-primary)', textDecoration: 'underline', display: 'flex', alignItems: 'center', gap: '4px' }}>
                    {req.proof_url} <ExternalLink size={14} />
                  </a>
                </div>
              </div>

              <div style={{ display: 'flex', gap: '16px', marginTop: '24px' }}>
                <button 
                  onClick={() => resolveRequest(req.id, 'rejected')}
                  style={{ flex: 1, padding: '12px', borderRadius: '8px', background: 'rgba(239, 68, 68, 0.1)', color: 'var(--danger)', border: '1px solid rgba(239, 68, 68, 0.2)', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px', fontWeight: 600 }}>
                  <Ban size={18} /> Rechazar Solicitud
                </button>
                <button 
                  onClick={() => resolveRequest(req.id, 'approved')}
                  style={{ flex: 1, padding: '12px', borderRadius: '8px', background: 'rgba(16, 185, 129, 0.1)', color: 'var(--success)', border: '1px solid rgba(16, 185, 129, 0.2)', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px', fontWeight: 600 }}>
                  <CheckCircle size={18} /> Aprobar (Verificar Canal)
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};
