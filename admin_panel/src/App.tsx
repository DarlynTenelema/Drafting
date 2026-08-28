import React from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { Sidebar } from './components/Sidebar';
import { Dashboard } from './pages/Dashboard';
import { Tickets } from './pages/Tickets';
import { Suggestions } from './pages/Suggestions';
import { Moderation } from './pages/Moderation';
import { Users } from './pages/Users';
import { Finance } from './pages/Finance';
import { Appeals } from './pages/Appeals';

function App() {
  return (
    <BrowserRouter>
      <div className="app-container">
        <Sidebar />
        <main className="main-content">
          <Routes>
            <Route path="/" element={<Navigate to="/dashboard" replace />} />
            <Route path="/dashboard" element={<Dashboard />} />
            <Route path="/tickets" element={<Tickets />} />
            <Route path="/suggestions" element={<Suggestions />} />
            <Route path="/moderation" element={<Moderation />} />
            <Route path="/users" element={<Users />} />
            <Route path="/finance" element={<Finance />} />
            <Route path="/appeals" element={<Appeals />} />
          </Routes>
        </main>
      </div>
    </BrowserRouter>
  );
}

export default App;
