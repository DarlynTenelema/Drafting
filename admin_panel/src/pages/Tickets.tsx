import React, { useState, useEffect } from 'react';
import { Search, Filter, MessageSquare, CheckCircle, Clock, Bot, ExternalLink } from 'lucide-react';
import { apiClient } from '../services/apiClient';

export const Tickets = () => {
  const [tickets, setTickets] = useState<any[]>([]);
  const [selectedTicket, setSelectedTicket] = useState<any>(null);
  const [replyText, setReplyText] = useState('');
  const [messages, setMessages] = useState<any[]>([]);

  useEffect(() => {
    loadTickets();
  }, []);

  const loadTickets = async () => {
    try {
      const data = await apiClient.get('/admin_panel/tickets');
      setTickets(data || []);
    } catch (e) {
      console.error(e);
    }
  };

  const loadMessages = async (ticketId: string) => {
    try {
      const data = await apiClient.get(`/admin_panel/tickets/${ticketId}/messages`);
      setMessages(data || []);
    } catch (e) {
      console.error(e);
    }
  };

  const handleSelectTicket = (t: any) => {
    setSelectedTicket(t);
    loadMessages(t.ID);
  };

  const handleReply = async (isInternal: boolean = false) => {
    if (!replyText.trim() || !selectedTicket) return;
    try {
      await apiClient.post(`/admin_panel/tickets/${selectedTicket.ID}/reply`, {
        message: replyText,
        is_internal: isInternal
      });
      setReplyText('');
      loadMessages(selectedTicket.ID);
    } catch (e) {
      console.error(e);
    }
  };

  return (
    <div className="animated">
      <div className="header" style={{ marginBottom: '32px' }}>
        <div>
          <h1>Gestión de Reportes y Tickets</h1>
          <p style={{ color: 'var(--text-secondary)', marginTop: '8px' }}>Administra casos de fraude, bugs y soporte.</p>
        </div>
        
        <div style={{ display: 'flex', gap: '16px' }}>
          <div className="glass-panel" style={{ display: 'flex', alignItems: 'center', padding: '8px 16px', gap: '8px' }}>
            <Search size={18} color="var(--text-secondary)" />
            <input 
              type="text" 
              placeholder="Buscar ticket..." 
              style={{ background: 'transparent', border: 'none', color: 'white', outline: 'none' }}
            />
          </div>
          <button className="glass-panel" style={{ display: 'flex', alignItems: 'center', padding: '8px 16px', gap: '8px', cursor: 'pointer', color: 'white' }}>
            <Filter size={18} /> Filtrar
          </button>
        </div>
      </div>

      <div style={{ display: 'flex', gap: '24px' }}>
        {/* Tabla de Tickets */}
        <div className="glass-panel" style={{ flex: selectedTicket ? 2 : 1, transition: 'all 0.3s' }}>
          <div className="data-table-container">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Asunto</th>
                  <th>Usuario</th>
                  <th>Tipo</th>
                  <th>Estado</th>
                  <th>Fecha</th>
                </tr>
              </thead>
              <tbody>
                {tickets.map(t => (
                  <tr key={t.ID} onClick={() => handleSelectTicket(t)} style={{ background: selectedTicket?.ID === t.ID ? 'var(--bg-glass-hover)' : '' }}>
                    <td style={{ fontWeight: 500 }}>{t.Subject}</td>
                    <td style={{ color: 'var(--text-secondary)' }}>{t.UserID?.substring(0,8)}...</td>
                    <td><span className={`badge ${t.TicketType}`}>{t.TicketType}</span></td>
                    <td><span className={`badge ${t.Status}`}>{t.Status.replace('_', ' ')}</span></td>
                    <td style={{ color: 'var(--text-secondary)' }}>{new Date(t.CreatedAt).toLocaleDateString()}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        {/* Vista Detallada (Chat) */}
        {selectedTicket && (
          <div className="glass-panel animated" style={{ flex: 1, padding: '24px', display: 'flex', flexDirection: 'column' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '24px' }}>
              <div>
                <h3 style={{ marginBottom: '8px', display: 'flex', alignItems: 'center', gap: '8px' }}>
                  {selectedTicket.Subject}
                  {selectedTicket.Priority && (
                    <span title="Prioridad asignada" style={{ display: 'flex', alignItems: 'center', background: 'rgba(99, 102, 241, 0.15)', color: 'var(--accent-primary)', padding: '2px 8px', borderRadius: '12px', fontSize: '12px' }}>
                      <Bot size={14} style={{ marginRight: '4px' }}/> {selectedTicket.Priority.toUpperCase()}
                    </span>
                  )}
                </h3>
                <span className={`badge ${selectedTicket.TicketType}`}>{selectedTicket.TicketType}</span>
              </div>
              <button 
                onClick={() => setSelectedTicket(null)}
                style={{ background: 'transparent', border: 'none', color: 'var(--text-secondary)', cursor: 'pointer', fontSize: '20px' }}>
                &times;
              </button>
            </div>

            <div style={{ flex: 1, background: 'var(--bg-secondary)', borderRadius: 'var(--radius-md)', padding: '16px', marginBottom: '16px', minHeight: '300px', display: 'flex', flexDirection: 'column', gap: '16px', overflowY: 'auto' }}>
              {messages.map((m, idx) => (
                <div key={idx} style={{ display: 'flex', gap: '12px', marginBottom: '16px' }}>
                  <div style={{ width: 32, height: 32, borderRadius: '50%', background: m.IsInternalNote ? 'var(--warning)' : 'var(--accent-primary)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                    {m.IsInternalNote ? '!' : 'U'}
                  </div>
                  <div style={{ background: m.IsInternalNote ? 'rgba(245, 158, 11, 0.1)' : 'var(--bg-primary)', border: m.IsInternalNote ? '1px solid var(--warning)' : 'none', padding: '16px', borderRadius: '8px', borderTopLeftRadius: 0, flex: 1 }}>
                    {m.EvidenceURL && (
                      <div style={{ marginBottom: '16px' }}>
                        <p style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: '8px' }}>Evidencia Adjunta:</p>
                        <a href={m.EvidenceURL} target="_blank" rel="noreferrer">
                          <img src={m.EvidenceURL} alt="Evidencia" style={{ maxWidth: '100%', maxHeight: '250px', borderRadius: '8px', border: '1px solid var(--border-glass)' }} />
                        </a>
                      </div>
                    )}
                    <p style={{ fontSize: 14, whiteSpace: 'pre-wrap' }}>{m.Message}</p>
                    <span style={{ fontSize: 10, color: 'var(--text-secondary)', marginTop: '8px', display: 'block' }}>{new Date(m.CreatedAt).toLocaleString()}</span>
                  </div>
                </div>
              ))}
            </div>

            <div style={{ display: 'flex', gap: '12px', flexDirection: 'column' }}>
              <textarea 
                value={replyText}
                onChange={(e) => setReplyText(e.target.value)}
                placeholder="Escribe tu respuesta..." 
                style={{ width: '100%', padding: '12px', borderRadius: 'var(--radius-md)', background: 'var(--bg-secondary)', border: '1px solid var(--border-glass)', color: 'white', outline: 'none', resize: 'none', minHeight: '80px' }}
              />
              <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '12px' }}>
                <button onClick={() => handleReply(true)} className="badge in_progress" style={{ padding: '8px 16px', cursor: 'pointer', background: 'transparent' }}>
                  Nota Interna
                </button>
                <button onClick={() => handleReply(false)} style={{ padding: '8px 16px', borderRadius: 'var(--radius-sm)', background: 'var(--accent-primary)', color: 'white', border: 'none', cursor: 'pointer', fontWeight: 500 }}>
                  Responder
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};
