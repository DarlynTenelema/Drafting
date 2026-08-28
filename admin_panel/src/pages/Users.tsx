import React, { useState, useEffect } from 'react';
import { Search, ShieldAlert, Ban, AlertOctagon, CheckCircle2, Smartphone } from 'lucide-react';
import { apiClient } from '../services/apiClient';

export const Users = () => {
  const [users, setUsers] = useState<any[]>([]);
  const [selectedUser, setSelectedUser] = useState<any>(null);

  useEffect(() => {
    loadUsers();
  }, []);

  const loadUsers = async () => {
    try {
      const data = await apiClient.get('/admin_panel/users');
      setUsers(data || []);
    } catch (e) {
      console.error(e);
    }
  };

  const handleStrike = async (id: string) => {
    try {
      await apiClient.post(`/admin_panel/users/${id}/strike`, {});
      loadUsers();
      if (selectedUser?.ID === id) {
        setSelectedUser((prev: any) => ({ ...prev, Strikes: prev.Strikes + 1, IsPendingBan: prev.Strikes + 1 >= 3 ? true : prev.IsPendingBan }));
      }
    } catch (e) {
      console.error(e);
    }
  };

  const handleBan = async (id: string) => {
    try {
      await apiClient.put(`/admin_panel/users/${id}/ban`, {});
      loadUsers();
      if (selectedUser?.ID === id) {
        setSelectedUser((prev: any) => ({ ...prev, Banned: !prev.Banned }));
      }
    } catch (e) {
      console.error(e);
    }
  };

  return (
    <div className="animated">
      <div className="header" style={{ marginBottom: '32px' }}>
        <div>
          <h1>Gestor de Usuarios</h1>
          <p style={{ color: 'var(--text-secondary)', marginTop: '8px' }}>Búsqueda global y control disciplinario.</p>
        </div>
        
        <div className="glass-panel" style={{ display: 'flex', alignItems: 'center', padding: '8px 16px', gap: '8px', minWidth: '300px' }}>
          <Search size={18} color="var(--text-secondary)" />
          <input 
            type="text" 
            placeholder="Buscar por email o ID..." 
            style={{ background: 'transparent', border: 'none', color: 'white', outline: 'none', width: '100%' }}
          />
        </div>
      </div>

      <div style={{ display: 'flex', gap: '24px' }}>
        {/* Tabla de Usuarios */}
        <div className="glass-panel" style={{ flex: selectedUser ? 1.5 : 1, transition: 'all 0.3s' }}>
          <div className="data-table-container">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Email</th>
                  <th>Rol</th>
                  <th>Strikes</th>
                  <th>Estado</th>
                </tr>
              </thead>
              <tbody>
                {users.map(u => (
                  <tr key={u.ID} onClick={() => setSelectedUser(u)} style={{ background: selectedUser?.ID === u.ID ? 'var(--bg-glass-hover)' : '' }}>
                    <td style={{ fontWeight: 500 }}>{u.Email}</td>
                    <td style={{ textTransform: 'capitalize', color: 'var(--text-secondary)' }}>{u.Role}</td>
                    <td>
                      <span style={{ color: u.Strikes >= 2 ? 'var(--danger)' : u.Strikes === 1 ? 'var(--warning)' : 'var(--text-secondary)' }}>
                        {u.Strikes}/3
                      </span>
                    </td>
                    <td>
                      {u.Banned ? (
                        <span className="badge" style={{ background: 'rgba(239, 68, 68, 0.15)', color: 'var(--danger)' }}>Baneado</span>
                      ) : u.IsPendingBan ? (
                        <span className="badge" style={{ background: 'rgba(245, 158, 11, 0.15)', color: 'var(--warning)' }}>En Riesgo de Ban</span>
                      ) : (
                        <span className="badge" style={{ background: 'rgba(16, 185, 129, 0.15)', color: 'var(--success)' }}>Activo</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        {/* Perfil del Usuario (God Mode) */}
        {selectedUser && (
          <div className="glass-panel animated" style={{ flex: 1, padding: '32px', display: 'flex', flexDirection: 'column' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '24px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
                <div style={{ width: 64, height: 64, borderRadius: '50%', background: 'var(--accent-primary)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 24, fontWeight: 700 }}>
                  {selectedUser.Email[0].toUpperCase()}
                </div>
                <div>
                  <h3 style={{ marginBottom: '4px', fontSize: 20 }}>{selectedUser.Email}</h3>
                  <span style={{ color: 'var(--text-secondary)', textTransform: 'capitalize' }}>Rol: {selectedUser.Role}</span>
                </div>
              </div>
              <button 
                onClick={() => setSelectedUser(null)}
                style={{ background: 'transparent', border: 'none', color: 'var(--text-secondary)', cursor: 'pointer', fontSize: '24px' }}>
                &times;
              </button>
            </div>

            {selectedUser.Banned && (
              <div style={{ background: 'rgba(239, 68, 68, 0.1)', border: '1px solid rgba(239, 68, 68, 0.3)', padding: '16px', borderRadius: 'var(--radius-md)', marginBottom: '24px', display: 'flex', alignItems: 'center', gap: '12px' }}>
                <ShieldAlert color="var(--danger)" size={24} />
                <div>
                  <h4 style={{ color: 'var(--danger)', marginBottom: '4px' }}>El hardware de este dispositivo está en la lista negra</h4>
                  <p style={{ fontSize: '13px', color: 'var(--text-secondary)' }}>Cualquier intento de registro desde el dispositivo <strong>{selectedUser.DeviceID || 'Desconocido'}</strong> será bloqueado automáticamente.</p>
                </div>
              </div>
            )}

            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '16px', marginBottom: '32px' }}>
              <div style={{ background: 'var(--bg-secondary)', padding: '16px', borderRadius: 'var(--radius-md)' }}>
                <p style={{ color: 'var(--text-secondary)', fontSize: 14, marginBottom: 8 }}>Fecha Registro</p>
                <p style={{ fontWeight: 600 }}>{new Date(selectedUser.CreatedAt).toLocaleDateString()}</p>
              </div>
              <div style={{ background: 'var(--bg-secondary)', padding: '16px', borderRadius: 'var(--radius-md)' }}>
                <p style={{ color: 'var(--text-secondary)', fontSize: 14, marginBottom: 8 }}>Advertencias</p>
                <p style={{ fontWeight: 600, color: selectedUser.Strikes > 0 ? 'var(--warning)' : 'white' }}>{selectedUser.Strikes} / 3</p>
              </div>
              <div style={{ background: 'var(--bg-secondary)', padding: '16px', borderRadius: 'var(--radius-md)' }}>
                <p style={{ color: 'var(--text-secondary)', fontSize: 14, marginBottom: 8 }}>Device ID</p>
                <p style={{ fontWeight: 600, display: 'flex', alignItems: 'center', gap: '6px' }}>
                  <Smartphone size={16} color="var(--text-secondary)"/> {selectedUser.DeviceID || 'N/A'}
                </p>
              </div>
            </div>

            <h4 style={{ marginBottom: '16px', color: 'var(--text-secondary)' }}>Acciones Disciplinarias</h4>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
              <button 
                onClick={() => handleStrike(selectedUser.ID)}
                disabled={selectedUser.Banned || selectedUser.IsPendingBan}
                style={{ 
                  padding: '16px', borderRadius: 'var(--radius-md)', 
                  background: (selectedUser.Banned || selectedUser.IsPendingBan) ? 'var(--bg-secondary)' : 'rgba(245, 158, 11, 0.1)', 
                  color: (selectedUser.Banned || selectedUser.IsPendingBan) ? 'var(--text-tertiary)' : 'var(--warning)', 
                  border: `1px solid ${(selectedUser.Banned || selectedUser.IsPendingBan) ? 'transparent' : 'rgba(245, 158, 11, 0.2)'}`, 
                  cursor: (selectedUser.Banned || selectedUser.IsPendingBan) ? 'not-allowed' : 'pointer', 
                  display: 'flex', alignItems: 'center', gap: '12px', fontWeight: 600, transition: 'all 0.2s', textAlign: 'left'
                }}
              >
                <AlertOctagon size={20} /> 
                <div>
                  <div style={{ marginBottom: 4 }}>Aplicar Strike (Advertencia)</div>
                  <div style={{ fontSize: 12, fontWeight: 400, opacity: 0.8 }}>Al llegar a 3 strikes, la cuenta se suspenderá automáticamente.</div>
                </div>
              </button>
              
              <button 
                onClick={() => handleBan(selectedUser.ID)}
                style={{ 
                  padding: '16px', borderRadius: 'var(--radius-md)', 
                  background: selectedUser.Banned ? 'rgba(16, 185, 129, 0.1)' : 'rgba(239, 68, 68, 0.1)', 
                  color: selectedUser.Banned ? 'var(--success)' : 'var(--danger)', 
                  border: `1px solid ${selectedUser.Banned ? 'rgba(16, 185, 129, 0.2)' : 'rgba(239, 68, 68, 0.2)'}`, 
                  cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '12px', fontWeight: 600, transition: 'all 0.2s', textAlign: 'left'
                }}
              >
                {selectedUser.Banned ? <CheckCircle2 size={20} /> : <Ban size={20} />}
                <div>
                  <div style={{ marginBottom: 4 }}>{selectedUser.Banned ? 'Quitar Suspensión' : 'Suspender Cuenta Inmediatamente'}</div>
                  <div style={{ fontSize: 12, fontWeight: 400, opacity: 0.8 }}>{selectedUser.Banned ? 'Permitirá al usuario acceder nuevamente.' : 'Bloquea el acceso y retira su contenido público.'}</div>
                </div>
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};
