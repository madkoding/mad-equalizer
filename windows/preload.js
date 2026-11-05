const { contextBridge, ipcRenderer } = require('electron');

const arg = (name) => process.argv.find(a => a.startsWith(`--${name}`));

contextBridge.exposeInMainWorld('mad', {
  demo: !!arg('mad-demo'),
  platform: (arg('mad-platform=') || '').split('=')[1] || '',
  status: () => ipcRenderer.invoke('apo:status'),
  write: (text) => ipcRenderer.invoke('apo:write', text),
  openDevices: () => ipcRenderer.invoke('apo:devices'),
  // Reproductor de música detectado por el sistema (lo alimenta el proceso principal).
  media: {
    onUpdate: (cb) => ipcRenderer.on('media:update', (_e, info) => cb(info)),
    command: (cmd) => ipcRenderer.invoke('media:command', cmd),
  },
  openSoundSettings: () => ipcRenderer.invoke('sys:sound'),
});
