export const API_BASE_URL = 'http://localhost:8080/api/v1';

export const apiClient = {
  async get(endpoint: string) {
    const token = localStorage.getItem('adminToken');
    const response = await fetch(`${API_BASE_URL}${endpoint}`, {
      headers: {
        'Authorization': `Bearer ${token}`
      }
    });
    if (!response.ok) throw new Error('API Request Failed');
    return response.json();
  },
  
  async post(endpoint: string, body: any) {
    const token = localStorage.getItem('adminToken');
    const response = await fetch(`${API_BASE_URL}${endpoint}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      },
      body: JSON.stringify(body)
    });
    if (!response.ok) throw new Error('API Request Failed');
    return response.json();
  },
  
  async put(endpoint: string, body?: any) {
    const token = localStorage.getItem('adminToken');
    const response = await fetch(`${API_BASE_URL}${endpoint}`, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      },
      body: body ? JSON.stringify(body) : undefined
    });
    if (!response.ok) throw new Error('API Request Failed');
    return response.json();
  }
};
