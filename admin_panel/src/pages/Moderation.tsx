import React, { useState } from 'react';
import { Check, X, Video, Image as ImageIcon, ExternalLink, AlertTriangle, MessageSquare } from 'lucide-react';

const mockContent = [
  { id: '1', type: 'video', title: 'Tutorial Golang 2026', author: 'DevMaster', thumbnail: 'https://via.placeholder.com/400x225/1a1a2e/6366f1?text=Video+Thumbnail', date: 'Hace 5 min' },
  { id: '2', type: 'fanart', title: 'Dibujo de Goku SSJ', author: 'ArtistX', thumbnail: 'https://via.placeholder.com/400x400/2d3748/f59e0b?text=Fanart', date: 'Hace 12 min' },
  { id: '3', type: 'video', title: 'Gameplay de prueba', author: 'Gamer99', thumbnail: 'https://via.placeholder.com/400x225/1a1a2e/10b981?text=Video+Thumbnail', date: 'Hace 30 min', reported: true, reportReason: 'Copyright' },
  { id: '4', type: 'fanart', title: 'Boceto original', author: 'DrawXYZ', thumbnail: 'https://via.placeholder.com/400x400/2d3748/ec4899?text=Fanart', date: 'Hace 1 hora' },
  { id: '5', type: 'comment', title: 'Comentario en "Gameplay de prueba"', author: 'ToxicPlayer', content: 'Entra a mi discord nitro gratis: http://free-nitro-scam.com eres basura', date: 'Hace 2 min', reported: true, reportReason: 'Enlace Phishing: Discord Nitro Falso' },
];

export const Moderation = () => {
  const [content, setContent] = useState(mockContent);
  const [animatingOut, setAnimatingOut] = useState<string | null>(null);
  
  const handleModerate = (id: string, action: 'approve' | 'reject') => {
    // Aplicamos una animación antes de quitarlo de la lista
    setAnimatingOut(id);
    setTimeout(() => {
      setContent(prev => prev.filter(c => c.id !== id));
      setAnimatingOut(null);
    }, 400); // 400ms dura la animación
  };

  return (
    <div className="animated">
      <div className="header" style={{ marginBottom: '32px' }}>
        <div>
          <h1>Cola de Moderación</h1>
          <p style={{ color: 'var(--text-secondary)', marginTop: '8px' }}>Aprueba o rechaza el contenido nuevo y reportado de forma ágil.</p>
        </div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(320px, 1fr))', gap: '32px' }}>
        {content.map(item => (
          <div 
            key={item.id} 
            className="glass-panel" 
            style={{ 
              display: 'flex', 
              flexDirection: 'column', 
              overflow: 'hidden',
              transform: animatingOut === item.id ? 'scale(0.9) translateY(20px)' : 'scale(1)',
              opacity: animatingOut === item.id ? 0 : 1,
              transition: 'all 0.4s cubic-bezier(0.4, 0, 0.2, 1)'
            }}
          >
            {/* Contenido Visual / Texto */}
            <div style={{ width: '100%', height: item.type === 'video' ? '180px' : item.type === 'comment' ? 'auto' : '260px', minHeight: item.type === 'comment' ? '180px' : 'auto', position: 'relative', background: item.type === 'comment' ? 'var(--bg-secondary)' : 'transparent', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              {item.type !== 'comment' ? (
                <img src={item.thumbnail} alt={item.title} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
              ) : (
                <div style={{ padding: '40px 24px', width: '100%', textAlign: 'center' }}>
                  <p style={{ fontSize: '16px', color: 'var(--text-primary)', fontStyle: 'italic', wordBreak: 'break-word' }}>"{item.content}"</p>
                </div>
              )}
              
              <div style={{ position: 'absolute', top: 12, left: 12, padding: '4px 8px', borderRadius: '4px', background: 'rgba(0,0,0,0.6)', backdropFilter: 'blur(4px)', display: 'flex', alignItems: 'center', gap: '6px', fontSize: 12, fontWeight: 600 }}>
                {item.type === 'video' ? <Video size={14} color="var(--accent-primary)" /> : item.type === 'comment' ? <MessageSquare size={14} color="var(--warning)" /> : <ImageIcon size={14} color="var(--warning)" />}
                <span style={{ textTransform: 'capitalize' }}>{item.type}</span>
              </div>

              {item.reported && (
                <div style={{ position: 'absolute', top: 12, right: 12, padding: '4px 8px', borderRadius: '4px', background: 'rgba(239, 68, 68, 0.9)', display: 'flex', alignItems: 'center', gap: '6px', fontSize: 12, fontWeight: 600, maxWidth: '200px', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }} title={item.reportReason}>
                  <AlertTriangle size={14} style={{ flexShrink: 0 }} /> <span style={{ overflow: 'hidden', textOverflow: 'ellipsis' }}>{item.reportReason}</span>
                </div>
              )}
            </div>

            {/* Metadatos */}
            <div style={{ padding: '20px', flex: 1, display: 'flex', flexDirection: 'column' }}>
              <h3 style={{ fontSize: '18px', marginBottom: '8px', lineHeight: 1.3 }}>{item.title}</h3>
              <p style={{ color: 'var(--text-secondary)', fontSize: '14px', display: 'flex', alignItems: 'center', gap: '6px' }}>
                Por <span style={{ color: 'var(--text-primary)', fontWeight: 500 }}>{item.author}</span> • {item.date}
              </p>
              
              <div style={{ flex: 1 }}></div>

              {/* Botones de acción Tinder-style */}
              <div style={{ display: 'flex', gap: '16px', marginTop: '24px' }}>
                <button 
                  onClick={() => handleModerate(item.id, 'reject')}
                  style={{ 
                    flex: 1, padding: '12px', borderRadius: 'var(--radius-md)', 
                    background: 'rgba(239, 68, 68, 0.1)', color: 'var(--danger)', 
                    border: '1px solid rgba(239, 68, 68, 0.2)', cursor: 'pointer', 
                    display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px', fontWeight: 600, transition: 'all 0.2s'
                  }}
                  onMouseOver={(e) => e.currentTarget.style.background = 'rgba(239, 68, 68, 0.2)'}
                  onMouseOut={(e) => e.currentTarget.style.background = 'rgba(239, 68, 68, 0.1)'}
                >
                  <X size={20} /> Rechazar
                </button>
                <button 
                  onClick={() => handleModerate(item.id, 'approve')}
                  style={{ 
                    flex: 1, padding: '12px', borderRadius: 'var(--radius-md)', 
                    background: 'rgba(16, 185, 129, 0.1)', color: 'var(--success)', 
                    border: '1px solid rgba(16, 185, 129, 0.2)', cursor: 'pointer', 
                    display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px', fontWeight: 600, transition: 'all 0.2s'
                  }}
                  onMouseOver={(e) => e.currentTarget.style.background = 'rgba(16, 185, 129, 0.2)'}
                  onMouseOut={(e) => e.currentTarget.style.background = 'rgba(16, 185, 129, 0.1)'}
                >
                  <Check size={20} /> Aprobar
                </button>
              </div>
            </div>
          </div>
        ))}

        {content.length === 0 && (
          <div style={{ gridColumn: '1 / -1', padding: '64px', textAlign: 'center', color: 'var(--text-secondary)' }}>
            <Check size={48} color="var(--success)" style={{ marginBottom: '16px', opacity: 0.5 }} />
            <h2>¡Todo al día!</h2>
            <p>No hay contenido pendiente de moderación.</p>
          </div>
        )}
      </div>
    </div>
  );
};
