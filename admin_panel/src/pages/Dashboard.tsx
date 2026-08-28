import React, { useEffect, useState } from 'react';
import { Users, ShieldAlert, Video, Image as ImageIcon } from 'lucide-react';
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';

const data = [
  { name: 'Lun', reports: 4 },
  { name: 'Mar', reports: 3 },
  { name: 'Mie', reports: 12 },
  { name: 'Jue', reports: 7 },
  { name: 'Vie', reports: 5 },
  { name: 'Sab', reports: 15 },
  { name: 'Dom', reports: 8 },
];

export const Dashboard = () => {
  const [stats, setStats] = useState({
    total_users: 1245,
    active_reports: 12,
    total_videos: 145,
    total_fanarts: 56
  });

  // Mocking the fetch call for now since backend needs to run
  useEffect(() => {
    /* 
    fetch('/api/v1/admin_panel/dashboard_stats')
      .then(res => res.json())
      .then(data => setStats(data));
    */
  }, []);

  return (
    <div className="animated">
      <div className="header" style={{ marginBottom: '32px' }}>
        <div>
          <h1>Dashboard Principal</h1>
          <p style={{ color: 'var(--text-secondary)', marginTop: '8px' }}>Visión general de la plataforma.</p>
        </div>
      </div>

      <div className="kpi-grid" style={{ marginBottom: '32px' }}>
        <div className="glass-panel kpi-card">
          <div className="kpi-header">
            <span>Usuarios Totales</span>
            <div className="kpi-icon-wrapper indigo"><Users size={20} /></div>
          </div>
          <div className="kpi-value">{stats.total_users}</div>
        </div>
        
        <div className="glass-panel kpi-card">
          <div className="kpi-header">
            <span>Reportes Activos</span>
            <div className="kpi-icon-wrapper rose"><ShieldAlert size={20} /></div>
          </div>
          <div className="kpi-value">{stats.active_reports}</div>
        </div>

        <div className="glass-panel kpi-card">
          <div className="kpi-header">
            <span>Videos Subidos</span>
            <div className="kpi-icon-wrapper emerald"><Video size={20} /></div>
          </div>
          <div className="kpi-value">{stats.total_videos}</div>
        </div>

        <div className="glass-panel kpi-card">
          <div className="kpi-header">
            <span>Fanarts</span>
            <div className="kpi-icon-wrapper amber"><ImageIcon size={20} /></div>
          </div>
          <div className="kpi-value">{stats.total_fanarts}</div>
        </div>
      </div>

      <div className="charts-grid">
        <div className="glass-panel chart-card">
          <h3 className="chart-title">Volumen de Reportes (Últimos 7 días)</h3>
          <div style={{ width: '100%', height: 300 }}>
            <ResponsiveContainer>
              <AreaChart data={data} margin={{ top: 10, right: 30, left: 0, bottom: 0 }}>
                <defs>
                  <linearGradient id="colorReports" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="var(--accent-primary)" stopOpacity={0.8}/>
                    <stop offset="95%" stopColor="var(--accent-primary)" stopOpacity={0}/>
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="var(--border-glass)" vertical={false} />
                <XAxis dataKey="name" stroke="var(--text-secondary)" tickLine={false} axisLine={false} />
                <YAxis stroke="var(--text-secondary)" tickLine={false} axisLine={false} />
                <Tooltip 
                  contentStyle={{ backgroundColor: 'var(--bg-secondary)', border: '1px solid var(--border-glass)', borderRadius: '8px' }} 
                  itemStyle={{ color: 'var(--text-primary)' }}
                />
                <Area type="monotone" dataKey="reports" stroke="var(--accent-primary)" strokeWidth={3} fillOpacity={1} fill="url(#colorReports)" />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        </div>
        
        <div className="glass-panel chart-card">
          <h3 className="chart-title">Actividad Reciente</h3>
          <ul style={{ listStyle: 'none', display: 'flex', flexDirection: 'column', gap: '16px', color: 'var(--text-secondary)' }}>
            <li style={{ display: 'flex', gap: '12px', alignItems: 'center' }}>
              <div style={{ width: 8, height: 8, borderRadius: '50%', backgroundColor: 'var(--success)' }}></div>
              <div>
                <p style={{ color: 'var(--text-primary)', fontSize: 14 }}>Usuario suspendido</p>
                <p style={{ fontSize: 12 }}>Hace 5 minutos</p>
              </div>
            </li>
            <li style={{ display: 'flex', gap: '12px', alignItems: 'center' }}>
              <div style={{ width: 8, height: 8, borderRadius: '50%', backgroundColor: 'var(--warning)' }}></div>
              <div>
                <p style={{ color: 'var(--text-primary)', fontSize: 14 }}>Nuevo reporte de fraude</p>
                <p style={{ fontSize: 12 }}>Hace 1 hora</p>
              </div>
            </li>
            <li style={{ display: 'flex', gap: '12px', alignItems: 'center' }}>
              <div style={{ width: 8, height: 8, borderRadius: '50%', backgroundColor: 'var(--accent-primary)' }}></div>
              <div>
                <p style={{ color: 'var(--text-primary)', fontSize: 14 }}>Video aprobado</p>
                <p style={{ fontSize: 12 }}>Hace 2 horas</p>
              </div>
            </li>
          </ul>
        </div>
      </div>
    </div>
  );
};
