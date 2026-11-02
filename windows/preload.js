const { contextBridge, ipcRenderer } = require('electron');

const arg = (name) => process.argv.find(a => a.startsWith(`--${name}`));

contextBridge.exposeInMainWorld('mad', {
  demo: !!arg('mad-demo'),
  platform: (arg('mad-platform=') || '').split('=')[1] || '',
  status: () => ipcRenderer.invoke('apo:status'),
  write: (text) => ipcRenderer.invoke('apo:write', text),
  openDevices: () => ipcRenderer.invoke('apo:devices'),
  half: (value) => ipcRenderer.invoke('window:half', value),
  openSoundSettings: () => ipcRenderer.invoke('sys:sound'),
});
