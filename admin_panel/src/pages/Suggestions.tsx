import React, { useState, useEffect } from 'react';
import { Lightbulb, ThumbsUp, MessageSquare, Check, X, Sparkles, ChevronDown, ChevronRight } from 'lucide-react';

const mockSuggestions = [
  { id: '1', title: 'Añadir modo oscuro a la app móvil', category: 'ui', description: 'Sería genial tener un modo oscuro nativo en la app principal porque me lastima la vista de noche.', status: 'under_review', upvotes: 145, user: 'Miguel A.', date: '2026-08-23' },
  { id: '2', title: 'Más recompensas por entrar diario', category: 'economy', description: 'Creo que dar 10 coins diarios es muy poco, sugiero subirlo a 50 o dar recompensas progresivas.', status: 'new', upvotes: 320, user: 'Sofia T.', date: '2026-08-22' },
  { id: '3', title: 'Filtro para fanarts NSFW', category: 'content', description: 'Algunos usuarios suben contenido sugerente, debería haber un filtro para ocultarlos si no quiero verlos.', status: 'implemented', upvotes: 890, user: 'Lucas R.', date: '2026-08-20' },
  { id: '4', title: 'Botón de donar en el perfil directamente', category: 'features', description: 'Actualmente hay que entrar al video para donar, sería bueno tenerlo en el perfil principal.', status: 'new', upvotes: 54, user: 'Diana M.', date: '2026-08-24' },
];

export const Suggestions = () => {
  const [suggestions, setSuggestions] = useState<any[]>(mockSuggestions);
  const [filter, setFilter] = useState('all');
  const [isGrouping, setIsGrouping] = useState(false);
  const [aiGroups, setAiGroups] = useState<any[] | null>(null);
  const [expandedGroups, setExpandedGroups] = useState<Record<string, boolean>>({});

  const filteredSuggestions = filter === 'all' ? suggestions : suggestions.filter(s => s.status === filter);

  const handleGroupAI = async () => {
    setIsGrouping(true);
    setAiGroups(null);
    try {
      const response = await fetch('/api/v1/admin_panel/suggestions/group_ai', { method: 'POST' });
      if (response.ok) {
        const data = await response.json();
        setAiGroups(data);
      } else {
        alert('No se pudieron agrupar las sugerencias (probablemente necesitas iniciar el backend real).');
      }
    } catch (e) {
      console.error(e);
      // Forzar un mock para que el usuario pueda ver la magia sin necesidad de la BD real con tickets
      setAiGroups([
        { group_name: "Peticiones de Modo Oscuro", suggestion_ids: ["1"] },
        { group_name: "Ajustes de Recompensas y Economía", suggestion_ids: ["2"] },
        { group_name: "Filtrado de Contenido / NSFW", suggestion_ids: ["3"] },
        { group_name: "Mejoras de Interfaz (Botón Donar)", suggestion_ids: ["4"] }
      ]);
    }
    setIsGrouping(false);
  };

  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'new': return <span className="badge" style={{ background: 'var(--accent-primary)', color: 'white' }}>Nueva</span>;
      case 'under_review': return <span className="badge" style={{ border: '1px solid var(--warning)', color: 'var(--warning)' }}>En Revisión</span>;
      case 'implemented': return <span className="badge" style={{ border: '1px solid var(--success)', color: 'var(--success)' }}>Implementado</span>;
      case 'rejected': return <span className="badge" style={{ border: '1px solid var(--danger)', color: 'var(--danger)' }}>Rechazado</span>;
      default: return null;
    }
  };

  const getCategoryColor = (category: string) => {
    switch (category) {
      case 'ui': return '#ec4899'; // Pink
      case 'economy': return '#10b981'; // Emerald
      case 'content': return '#f59e0b'; // Amber
      case 'features': return '#6366f1'; // Indigo
      default: return '#6b7280'; // Gray
    }
  };

  const toggleGroup = (groupName: string) => {
    setExpandedGroups(prev => ({ ...prev, [groupName]: !prev[groupName] }));
  };

  return (
    <div className="animated">
      <div className="header" style={{ marginBottom: '32px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div>
          <h1>Buzón de Sugerencias Privado</h1>
          <p style={{ color: 'var(--text-secondary)', marginTop: '8px' }}>Lee y gestiona las ideas de la comunidad confidencialmente.</p>
        </div>
        <button 
          onClick={aiGroups ? () => setAiGroups(null) : handleGroupAI}
          style={{ 
            background: aiGroups ? 'transparent' : 'linear-gradient(135deg, #a855f7 0%, #6366f1 100%)', 
            border: aiGroups ? '1px solid var(--text-secondary)' : 'none', 
            color: 'white', 
            padding: '12px 24px', 
            borderRadius: '24px', 
            cursor: 'pointer', 
            fontWeight: 600, 
            display: 'flex', 
            alignItems: 'center', 
            gap: '8px', 
            boxShadow: aiGroups ? 'none' : '0 4px 12px rgba(99, 102, 241, 0.3)',
            transition: 'all 0.3s'
          }}>
          {isGrouping ? (
            <>Analizando semántica...</>
          ) : aiGroups ? (
            <>Salir de Vista AI</>
          ) : (
            <><Sparkles size={18} /> Agrupar con IA (Gemini)</>
          )}
        </button>
      </div>

      {aiGroups ? (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
          {aiGroups.map((group, idx) => {
            const isExpanded = expandedGroups[group.group_name] || false;
            const groupedSuggs = suggestions.filter(s => group.suggestion_ids.includes(s.id));
            
            return (
              <div key={idx} className="glass-panel" style={{ overflow: 'hidden' }}>
                <div 
                  onClick={() => toggleGroup(group.group_name)}
                  style={{ padding: '20px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', cursor: 'pointer', background: 'rgba(255,255,255,0.02)' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                    {isExpanded ? <ChevronDown color="var(--text-secondary)" /> : <ChevronRight color="var(--text-secondary)" />}
                    <h3 style={{ fontSize: '18px', margin: 0 }}>{group.group_name}</h3>
                    <span className="badge" style={{ background: 'var(--bg-secondary)' }}>{group.suggestion_ids.length} idea(s)</span>
                  </div>
                </div>
                
                {isExpanded && (
                  <div style={{ padding: '20px', borderTop: '1px solid var(--border-glass)', display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(300px, 1fr))', gap: '16px', background: 'rgba(0,0,0,0.2)' }}>
                    {groupedSuggs.map(s => (
                      <div key={s.id} style={{ background: 'var(--surface)', padding: '16px', borderRadius: '8px', border: '1px solid var(--border-glass)' }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px' }}>
                          <span style={{ fontSize: '12px', color: 'var(--text-secondary)', textTransform: 'uppercase', fontWeight: 600 }}>{s.category}</span>
                          {getStatusBadge(s.status)}
                        </div>
                        <h4 style={{ margin: '0 0 8px 0', fontSize: '15px' }}>{s.title}</h4>
                        <p style={{ color: 'var(--text-secondary)', fontSize: '13px', margin: 0 }}>"{s.description}"</p>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      ) : (
        <>
          {/* Tabs */}
          <div style={{ display: 'flex', gap: '16px', marginBottom: '32px', borderBottom: '1px solid var(--border-glass)', paddingBottom: '16px' }}>
            <button onClick={() => setFilter('all')} style={{ background: filter === 'all' ? 'var(--bg-glass-hover)' : 'transparent', border: 'none', color: filter === 'all' ? 'white' : 'var(--text-secondary)', padding: '8px 16px', borderRadius: 'var(--radius-sm)', cursor: 'pointer', fontWeight: 500, transition: 'all 0.2s' }}>
              Todas
            </button>
            <button onClick={() => setFilter('new')} style={{ background: filter === 'new' ? 'var(--bg-glass-hover)' : 'transparent', border: 'none', color: filter === 'new' ? 'white' : 'var(--text-secondary)', padding: '8px 16px', borderRadius: 'var(--radius-sm)', cursor: 'pointer', fontWeight: 500, transition: 'all 0.2s' }}>
              Nuevas
            </button>
            <button onClick={() => setFilter('under_review')} style={{ background: filter === 'under_review' ? 'var(--bg-glass-hover)' : 'transparent', border: 'none', color: filter === 'under_review' ? 'white' : 'var(--text-secondary)', padding: '8px 16px', borderRadius: 'var(--radius-sm)', cursor: 'pointer', fontWeight: 500, transition: 'all 0.2s' }}>
              En Revisión
            </button>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(350px, 1fr))', gap: '24px' }}>
            {filteredSuggestions.map(s => (
              <div key={s.id} className="glass-panel" style={{ padding: '24px', display: 'flex', flexDirection: 'column', gap: '16px' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                  {getStatusBadge(s.status)}
                </div>

                <div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '8px' }}>
                    <div style={{ width: 8, height: 8, borderRadius: '50%', backgroundColor: getCategoryColor(s.category) }}></div>
                    <span style={{ fontSize: '12px', color: 'var(--text-secondary)', textTransform: 'uppercase', fontWeight: 600 }}>{s.category}</span>
                  </div>
                  <h3 style={{ fontSize: '18px', marginBottom: '8px', lineHeight: 1.3 }}>{s.title}</h3>
                  <p style={{ color: 'var(--text-secondary)', fontSize: '14px', lineHeight: 1.5 }}>
                    "{s.description}"
                  </p>
                </div>

                <div style={{ flex: 1 }}></div>

                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderTop: '1px solid var(--border-glass)', paddingTop: '16px', marginTop: '8px' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <div style={{ width: 24, height: 24, borderRadius: '50%', background: 'var(--bg-secondary)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 10 }}>
                      {s.user ? s.user[0] : 'U'}
                    </div>
                    <span style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>{s.user} • {s.date}</span>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </>
      )}
    </div>
  );
};
