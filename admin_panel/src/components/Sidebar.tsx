import React from 'react';
import { NavLink } from 'react-router-dom';
import { 
  LayoutDashboard, 
  ShieldAlert, 
  Lightbulb, 
  Video, 
  Users, 
  Activity, 
  Settings,
  AlertCircle
} from 'lucide-react';

export const Sidebar = () => {
  return (
    <aside className="sidebar">
      <div className="brand">
        <ShieldAlert size={28} color="var(--accent-primary)" />
        <span>Admin Control</span>
      </div>
      
      <ul className="nav-menu">
        <NavLink to="/dashboard" className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}>
          <LayoutDashboard size={20} />
          <span>Dashboard</span>
        </NavLink>
        <NavLink to="/tickets" className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}>
          <ShieldAlert size={20} />
          <span>Reportes & Tickets</span>
        </NavLink>
        <NavLink to="/suggestions" className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}>
          <Lightbulb size={20} />
          <span>Sugerencias</span>
        </NavLink>
        <NavLink to="/moderation" className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}>
          <Video size={20} />
          <span>Moderación</span>
        </NavLink>
        <NavLink to="/users" className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}>
          <Users size={20} />
          <span>Usuarios</span>
        </NavLink>
        <NavLink to="/appeals" className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}>
          <AlertCircle size={20} />
          <span>Apelaciones</span>
        </NavLink>
        <NavLink to="/finance" className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}>
          <Activity size={20} />
          <span>Fraude</span>
        </NavLink>
        <div style={{ flex: 1 }}></div>
        <li className="nav-item">
          <Settings size={20} />
          <span>Configuración</span>
        </li>
      </ul>
    </aside>
  );
};
