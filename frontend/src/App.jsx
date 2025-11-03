import React, { useState, useEffect, useCallback } from 'react';
import { Server, Plus, Wifi, Loader, LogOut, CheckCircle, XCircle, Download, QrCode, Trash2, Link as LinkIcon } from 'lucide-react';

const API_BASE = '/api';

export default function TunnelPlatform() {
  const [currentView, setCurrentView] = useState('login');
  const [token, setToken] = useState(localStorage.getItem('token') || '');
  const [instances, setInstances] = useState([]);
  const [selectedInstance, setSelectedInstance] = useState(null);
  const [peers, setPeers] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');
  const [showQR, setShowQR] = useState(false);
  const [qrData, setQrData] = useState(null);

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [newInstanceRegion, setNewInstanceRegion] = useState('us-east-1');
  const [newInstanceType, setNewInstanceType] = useState('t2.micro');
  const [newPeerName, setNewPeerName] = useState('');
  const [newPeerDevice, setNewPeerDevice] = useState('phone');

  const getHeaders = () => ({
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json'
  });

  const apiFetch = async (endpoint, options = {}) => {
    const res = await fetch(`${API_BASE}${endpoint}`, {
      ...options,
      headers: { ...getHeaders(), ...options.headers }
    });
    if (!res.ok) {
      const data = await res.json().catch(() => ({ detail: 'Network error' }));
      throw new Error(data.detail || 'API error');
    }
    return res.json();
  };

  const fetchInstances = useCallback(async () => {
    if (!token) return;
    try {
      const data = await apiFetch('/instances');
      setInstances(data);
    } catch (err) {
      console.error('Fetch instances error:', err);
    }
  }, [token]);

  const fetchPeers = useCallback(async (id) => {
    if (!token || !id) return;
    try {
      const data = await apiFetch(`/instances/${id}/peers`);
      setPeers(data);
    } catch (err) {
      console.error('Fetch peers error:', err);
    }
  }, [token]);

  useEffect(() => {
    if (token) {
      fetchInstances();
      const interval = setInterval(fetchInstances, 10000);
      return () => clearInterval(interval);
    }
  }, [token, fetchInstances]);

  useEffect(() => {
    if (selectedInstance && token) {
      fetchPeers(selectedInstance.id);
      const interval = setInterval(() => fetchPeers(selectedInstance.id), 10000);
      return () => clearInterval(interval);
    }
  }, [selectedInstance, token, fetchPeers]);

  // Auto-select first running instance
  useEffect(() => {
    if (instances.length > 0 && !selectedInstance) {
      const running = instances.find(i => i.state === 'running');
      if (running) setSelectedInstance(running);
    }
  }, [instances]);

  const handleAuth = async (isRegister) => {
    setLoading(true);
    setError('');
    setSuccess('');
    
    try {
      if (isRegister) {
        await apiFetch('/auth/register', {
          method: 'POST',
          body: JSON.stringify({ email, password })
        });
        setSuccess('Account created! Now login.');
      } else {
        const form = new URLSearchParams();
        form.append('username', email);
        form.append('password', password);
        
        const res = await fetch(`${API_BASE}/auth/login`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: form
        });
        
        if (!res.ok) {
          const data = await res.json();
          throw new Error(data.detail);
        }
        
        const data = await res.json();
        setToken(data.access_token);
        localStorage.setItem('token', data.access_token);
        setCurrentView('dashboard');
        setSuccess('Logged in! 🎉');
      }
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const handleLogout = () => {
    setToken('');
    localStorage.removeItem('token');
    setCurrentView('login');
    setInstances([]);
    setSelectedInstance(null);
    setPeers([]);
    setEmail('');
    setPassword('');
  };

  const createInstance = async () => {
    setLoading(true);
    setError('');
    
    try {
      await apiFetch('/instances', {
        method: 'POST',
        body: JSON.stringify({ 
          region: newInstanceRegion, 
          instance_type: newInstanceType 
        })
      });
      setSuccess('Instance launching... This may take 2-3 minutes ⏳');
      setCurrentView('dashboard');
      fetchInstances();
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const deleteInstance = async (id) => {
    if (!confirm('Delete this instance? This will terminate the AWS EC2 instance.')) return;
    
    try {
      await apiFetch(`/instances/${id}`, { method: 'DELETE' });
      setSuccess('Instance deleted!');
      if (selectedInstance?.id === id) {
        setSelectedInstance(null);
        setPeers([]);
      }
      fetchInstances();
    } catch (err) {
      setError(err.message);
    }
  };

  const createPeer = async () => {
    if (!newPeerName.trim()) {
      setError('Please enter a peer name');
      return;
    }
    
    setLoading(true);
    setError('');
    
    try {
      const res = await apiFetch(`/instances/${selectedInstance.id}/peers`, {
        method: 'POST',
        body: JSON.stringify({ 
          name: newPeerName.trim(), 
          device_type: newPeerDevice 
        })
      });
      
      setSuccess('Peer created! 🎉');
      setNewPeerName('');
      setCurrentView('dashboard');
      fetchPeers(selectedInstance.id);
      
      // Auto-show QR code
      const qr = await apiFetch(`/peers/${res.peer_id}/qr`);
      setQrData(qr);
      setShowQR(true);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const deletePeer = async (id) => {
    if (!confirm('Delete this peer?')) return;
    
    try {
      await apiFetch(`/peers/${id}`, { method: 'DELETE' });
      setSuccess('Peer deleted!');
      fetchPeers(selectedInstance.id);
    } catch (err) {
      setError(err.message);
    }
  };

  const downloadConfig = async (peerId, peerName) => {
    try {
      const data = await apiFetch(`/peers/${peerId}/config`);
      const blob = new Blob([data.config], { type: 'text/plain' });
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `${peerName.replace(/\s+/g, '-')}.conf`;
      a.click();
      window.URL.revokeObjectURL(url);
      setSuccess('Config downloaded!');
    } catch (err) {
      setError('Download failed');
    }
  };

  const showQRCode = async (peerId) => {
    try {
      const data = await apiFetch(`/peers/${peerId}/qr`);
      setQrData(data);
      setShowQR(true);
    } catch (err) {
      setError('QR generation failed');
    }
  };

  const connectToPeer = async (peerId, peerName) => {
    // Try WireGuard deep link for mobile
    if (/Android|iPhone|iPad/i.test(navigator.userAgent)) {
      try {
        const data = await apiFetch(`/peers/${peerId}/config`);
        const blob = new Blob([data.config], { type: 'text/plain' });
        const url = window.URL.createObjectURL(blob);
        window.location.href = `wireguard://importprofile?url=${encodeURIComponent(url)}`;
        
        setTimeout(() => {
          setSuccess('Opening WireGuard app... Or scan QR code below');
          showQRCode(peerId);
        }, 1000);
      } catch (err) {
        showQRCode(peerId);
      }
    } else {
      // Desktop: show QR and download
      downloadConfig(peerId, peerName);
      showQRCode(peerId);
    }
  };

  const Alert = ({ type, message }) => (
    <div className={`p-4 rounded-lg flex items-center gap-3 ${
      type === 'error' ? 'bg-red-50 border border-red-200 text-red-800' : 'bg-green-50 border border-green-200 text-green-800'
    }`}>
      {type === 'error' ? <XCircle className="w-5 h-5" /> : <CheckCircle className="w-5 h-5" />}
      <span className="flex-1">{message}</span>
      <button 
        onClick={() => type === 'error' ? setError('') : setSuccess('')}
        className="text-lg hover:opacity-70"
      >
        ×
      </button>
    </div>
  );

  // LOGIN VIEW
  if (currentView === 'login') {
    return (
      <div className="min-h-screen bg-gradient-to-br from-blue-500 via-purple-500 to-pink-500 flex items-center justify-center p-4">
        <div className="max-w-md w-full bg-white/95 backdrop-blur rounded-2xl shadow-2xl p-8">
          <div className="text-center mb-8">
            <div className="w-20 h-20 bg-gradient-to-br from-blue-600 to-purple-600 rounded-full flex items-center justify-center mx-auto mb-4 shadow-lg">
              <Wifi className="w-10 h-10 text-white" />
            </div>
            <h1 className="text-3xl font-bold text-gray-800 mb-2">Tunnel Platform</h1>
            <p className="text-gray-600">Your Personal VPN Manager</p>
          </div>

          <div className="space-y-4">
            <input
              type="email"
              value={email}
              onChange={e => setEmail(e.target.value)}
              placeholder="you@example.com"
              className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none transition"
            />
            <input
              type="password"
              value={password}
              onChange={e => setPassword(e.target.value)}
              placeholder="••••••••"
              onKeyPress={e => e.key === 'Enter' && !loading && email && password && handleAuth(false)}
              className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none transition"
            />

            <button
              onClick={() => handleAuth(false)}
              disabled={loading || !email || !password}
              className="w-full bg-gradient-to-r from-blue-600 to-blue-700 text-white py-3 rounded-lg font-semibold hover:from-blue-700 hover:to-blue-800 disabled:opacity-50 disabled:cursor-not-allowed transition-all shadow-lg hover:shadow-xl"
            >
              {loading ? <Loader className="w-5 h-5 animate-spin mx-auto" /> : 'Sign In'}
            </button>

            <button
              onClick={() => handleAuth(true)}
              disabled={loading || !email || !password}
              className="w-full bg-gradient-to-r from-green-600 to-green-700 text-white py-3 rounded-lg font-semibold hover:from-green-700 hover:to-green-800 disabled:opacity-50 disabled:cursor-not-allowed transition-all shadow-lg hover:shadow-xl"
            >
              {loading ? <Loader className="w-5 h-5 animate-spin mx-auto" /> : 'Create Account'}
            </button>
          </div>

          {error && <div className="mt-4"><Alert type="error" message={error} /></div>}
          {success && <div className="mt-4"><Alert type="success" message={success} /></div>}
        </div>
      </div>
    );
  }

  // DASHBOARD VIEW
  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <header className="bg-white shadow-sm border-b sticky top-0 z-40">
        <div className="max-w-7xl mx-auto px-4 py-4 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 bg-gradient-to-br from-blue-600 to-purple-600 rounded-lg flex items-center justify-center">
              <Wifi className="w-6 h-6 text-white" />
            </div>
            <div>
              <h1 className="text-xl font-bold text-gray-800">Tunnel Platform</h1>
              <p className="text-xs text-gray-500">VPN Management</p>
            </div>
          </div>
          <button
            onClick={handleLogout}
            className="flex items-center gap-2 text-red-600 hover:bg-red-50 px-4 py-2 rounded-lg transition"
          >
            <LogOut className="w-5 h-5" />
            <span className="hidden sm:inline">Logout</span>
          </button>
        </div>
      </header>

      <div className="max-w-7xl mx-auto px-4 py-8">
        {/* Alerts */}
        {error && <div className="mb-6"><Alert type="error" message={error} /></div>}
        {success && <div className="mb-6"><Alert type="success" message={success} /></div>}

        {/* Instances Section */}
        <div className="mb-8">
          <div className="flex items-center justify-between mb-6">
            <h2 className="text-2xl font-bold text-gray-800">VPN Instances</h2>
            <button
              onClick={() => setCurrentView('new-instance')}
              className="bg-gradient-to-r from-blue-600 to-blue-700 text-white px-6 py-3 rounded-lg font-semibold hover:from-blue-700 hover:to-blue-800 flex items-center gap-2 transition shadow-lg hover:shadow-xl"
            >
              <Plus className="w-5 h-5" />
              New Instance
            </button>
          </div>

          {instances.length === 0 ? (
            <div className="text-center py-20 bg-white rounded-xl shadow-lg">
              <Server className="w-20 h-20 text-gray-300 mx-auto mb-4" />
              <h3 className="text-xl font-semibold text-gray-700 mb-2">No instances yet</h3>
              <p className="text-gray-500 mb-6">Create your first VPN server to get started</p>
              <button
                onClick={() => setCurrentView('new-instance')}
                className="bg-blue-600 text-white px-8 py-3 rounded-lg font-semibold hover:bg-blue-700 transition inline-flex items-center gap-2"
              >
                <Plus className="w-5 h-5" />
                Create First Instance
              </button>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              {instances.map(inst => (
                <div
                  key={inst.id}
                  className={`bg-white rounded-xl shadow-lg p-6 border-l-4 transition-all hover:shadow-xl ${
                    inst.state === 'running' ? 'border-green-500' : 
                    inst.state === 'launching' ? 'border-yellow-500' : 
                    'border-red-500'
                  }`}
                >
                  <div className="flex items-center justify-between mb-4">
                    <h3 className="text-lg font-bold text-gray-800">Instance #{inst.id}</h3>
                    <div className="flex items-center gap-2">
                      <span className={`px-3 py-1 rounded-full text-xs font-semibold ${
                        inst.state === 'running' ? 'bg-green-100 text-green-800' : 
                        inst.state === 'launching' ? 'bg-yellow-100 text-yellow-800' : 
                        'bg-red-100 text-red-800'
                      }`}>
                        {inst.state}
                      </span>
                      <button
                        onClick={() => deleteInstance(inst.id)}
                        className="text-red-600 hover:bg-red-50 p-2 rounded-lg transition"
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                  </div>

                  <div className="space-y-2 text-sm mb-4">
                    <div className="flex justify-between">
                      <span className="text-gray-600">Region:</span>
                      <span className="font-medium">{inst.region}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-gray-600">Type:</span>
                      <span className="font-medium">{inst.instance_type}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-gray-600">IP:</span>
                      <span className="font-mono text-xs">{inst.public_ip || 'Pending...'}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-gray-600">Peers:</span>
                      <span className="font-medium">{inst.peer_count || 0}</span>
                    </div>
                  </div>

                  <button
                    onClick={() => setSelectedInstance(inst)}
                    disabled={inst.state !== 'running'}
                    className="w-full bg-gradient-to-r from-blue-600 to-blue-700 text-white py-3 rounded-lg font-medium hover:from-blue-700 hover:to-blue-800 disabled:from-gray-400 disabled:to-gray-400 disabled:cursor-not-allowed flex items-center justify-center gap-2 transition"
                  >
                    <Wifi className="w-5 h-5" />
                    Manage Peers
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Peers Section */}
        {selectedInstance && (
          <div className="bg-white rounded-xl shadow-lg p-8">
            <div className="flex items-center justify-between mb-8">
              <h3 className="text-2xl font-bold text-gray-800">
                Peers - Instance #{selectedInstance.id}
              </h3>
              <button
                onClick={() => setCurrentView('new-peer')}
                className="bg-gradient-to-r from-green-600 to-green-700 text-white px-6 py-3 rounded-lg font-semibold hover:from-green-700 hover:to-green-800 flex items-center gap-2 transition shadow-lg hover:shadow-xl"
              >
                <Plus className="w-5 h-5" />
                Add Peer
              </button>
            </div>

            {peers.length === 0 ? (
              <div className="text-center py-12">
                <Wifi className="w-16 h-16 text-gray-300 mx-auto mb-4" />
                <p className="text-gray-500 mb-4">No peers yet. Add devices to connect.</p>
                <button
                  onClick={() => setCurrentView('new-peer')}
                  className="bg-green-600 text-white px-6 py-3 rounded-lg font-semibold hover:bg-green-700 transition"
                >
                  Add First Peer
                </button>
              </div>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {peers.map(p => (
                  <div key={p.id} className="border-2 border-gray-200 rounded-xl p-5 hover:shadow-lg transition bg-gradient-to-br from-white to-gray-50">
                    <div className="flex items-center justify-between mb-3">
                      <h4 className="font-bold text-lg text-gray-800">{p.name}</h4>
                      <button
                        onClick={() => deletePeer(p.id)}
                        className="text-red-600 hover:bg-red-50 p-2 rounded-lg transition"
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                    <p className="text-sm text-gray-600 capitalize mb-1">{p.device_type}</p>
                    <p className="font-mono text-xs text-gray-500 bg-gray-100 px-2 py-1 rounded mb-4">{p.assigned_ip}</p>
                    
                    <div className="space-y-2">
                      <button
                        onClick={() => connectToPeer(p.id, p.name)}
                        className="w-full bg-gradient-to-r from-green-600 to-green-700 text-white px-4 py-3 rounded-lg text-sm font-semibold hover:from-green-700 hover:to-green-800 flex items-center justify-center gap-2 transition shadow-md hover:shadow-lg"
                      >
                        <LinkIcon className="w-4 h-4" />
                        Connect
                      </button>
                      
                      <div className="grid grid-cols-2 gap-2">
                        <button
                          onClick={() => downloadConfig(p.id, p.name)}
                          className="bg-blue-600 text-white px-3 py-2 rounded-lg text-xs hover:bg-blue-700 flex items-center justify-center gap-1 transition"
                        >
                          <Download className="w-3 h-3" />
                          Config
                        </button>
                        <button
                          onClick={() => showQRCode(p.id)}
                          className="bg-purple-600 text-white px-3 py-2 rounded-lg text-xs hover:bg-purple-700 flex items-center justify-center gap-1 transition"
                        >
                          <QrCode className="w-3 h-3" />
                          QR
                        </button>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}
      </div>

      {/* Modals */}
      {currentView === 'new-instance' && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center p-4 z-50 animate-fadeIn">
          <div className="bg-white rounded-2xl shadow-2xl p-8 max-w-md w-full">
            <h3 className="text-2xl font-bold mb-6 text-gray-800">Launch New Instance</h3>
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-semibold text-gray-700 mb-2">Region</label>
                <select
                  value={newInstanceRegion}
                  onChange={e => setNewInstanceRegion(e.target.value)}
                  className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 outline-none"
                >
                  <option value="us-east-1">🇺🇸 US East (Virginia)</option>
                  <option value="us-west-2">🇺🇸 US West (Oregon)</option>
                  <option value="eu-west-1">🇪🇺 EU West (Ireland)</option>
                  <option value="ap-southeast-1">🌏 Asia Pacific (Singapore)</option>
                </select>
              </div>
              <div>
                <label className="block text-sm font-semibold text-gray-700 mb-2">Instance Type</label>
                <select
                  value={newInstanceType}
                  onChange={e => setNewInstanceType(e.target.value)}
                  className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 outline-none"
                >
                  <option value="t2.micro">t2.micro (Free Tier) - 1 vCPU, 1GB RAM</option>
                  <option value="t3.small">t3.small ($0.02/hr) - 2 vCPU, 2GB RAM</option>
                </select>
              </div>
            </div>
            <div className="flex gap-3 mt-8">
              <button
                onClick={createInstance}
                disabled={loading}
                className="flex-1 bg-gradient-to-r from-blue-600 to-blue-700 text-white py-3 rounded-lg font-semibold hover:from-blue-700 hover:to-blue-800 disabled:opacity-50 flex items-center justify-center gap-2 transition shadow-lg"
              >
                {loading ? <Loader className="w-5 h-5 animate-spin" /> : 'Launch'}
              </button>
              <button
                onClick={() => setCurrentView('dashboard')}
                className="px-6 py-3 bg-gray-200 text-gray-700 rounded-lg hover:bg-gray-300 transition font-semibold"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}

      {currentView === 'new-peer' && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center p-4 z-50 animate-fadeIn">
          <div className="bg-white rounded-2xl shadow-2xl p-8 max-w-md w-full">
            <h3 className="text-2xl font-bold mb-6 text-gray-800">Add New Peer</h3>
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-semibold text-gray-700 mb-2">Device Name</label>
                <input
                  type="text"
                  value={newPeerName}
                  onChange={e => setNewPeerName(e.target.value)}
                  placeholder="e.g., My iPhone"
                  className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 outline-none"
                />
              </div>
              <div>
                <label className="block text-sm font-semibold text-gray-700 mb-2">Device Type</label>
                <select
                  value={newPeerDevice}
                  onChange={e => setNewPeerDevice(e.target.value)}
                  className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 outline-none"
                >
                  <option value="phone">📱 Phone</option>
                  <option value="laptop">💻 Laptop</option>
                  <option value="tablet">📲 Tablet</option>
                </select>
              </div>
            </div>
            <div className="flex gap-3 mt-8">
              <button
                onClick={createPeer}
                disabled={loading || !newPeerName.trim()}
                className="flex-1 bg-gradient-to-r from-green-600 to-green-700 text-white py-3 rounded-lg font-semibold hover:from-green-700 hover:to-green-800 disabled:opacity-50 flex items-center justify-center gap-2 transition shadow-lg"
              >
                {loading ? <Loader className="w-5 h-5 animate-spin" /> : 'Create'}
              </button>
              <button
                onClick={() => setCurrentView('dashboard')}
                className="px-6 py-3 bg-gray-200 text-gray-700 rounded-lg hover:bg-gray-300 transition font-semibold"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}

      {showQR && qrData && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4 z-50 animate-fadeIn" onClick={() => setShowQR(false)}>
          <div className="bg-white rounded-2xl shadow-2xl p-8 max-w-sm w-full text-center" onClick={e => e.stopPropagation()}>
            <h3 className="text-xl font-bold mb-4 text-gray-800">Scan with WireGuard</h3>
            <div className="bg-white p-4 rounded-xl border-4 border-gray-200 mb-4">
              <img src={qrData.qr_code} alt="QR Code" className="w-full" />
            </div>
            <p className="text-sm text-gray-600 mb-2">
              Open WireGuard app → Tap "+" → Scan QR code
            </p>
            <p className="font-semibold text-gray-800 mb-4">{qrData.peer_name}</p>
            <button
              onClick={() => setShowQR(false)}
              className="bg-gradient-to-r from-blue-600 to-blue-700 text-white px-8 py-3 rounded-lg font-semibold hover:from-blue-700 hover:to-blue-800 transition shadow-lg w-full"
            >
              Close
            </button>
          </div>
        </div>
      )}
    </div>
  );
}