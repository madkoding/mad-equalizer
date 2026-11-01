// MAD Equalizer para Windows: interfaz de Equalizer APO.
// El ecualizado lo hace Equalizer APO en el sistema; esta app escribe su configuración (MAD.txt)
// y mide el audio de salida con una captura loopback.
const { app, BrowserWindow, ipcMain, session, desktopCapturer, shell, protocol, net, screen } = require('electron');
const path = require('path');
const fs = require('fs');
const { execFile } = require('child_process');
const { pathToFileURL } = require('url');

const WIN = process.platform === 'win32';
// Fuera de Windows (o con --demo) no hay Equalizer APO: la configuración va a una carpeta local
// y el audio es una señal de prueba. Sirve para desarrollar y revisar la interfaz.
const DEMO = !WIN || process.argv.includes('--demo');
const WIDTH = 1120, HEIGHT = 802;
const CONFIG_FILE = 'MAD.txt';
const INCLUDE_LINE = `Include: ${CONFIG_FILE}`;

protocol.registerSchemesAsPrivileged([
  { scheme: 'app', privileges: { standard: true, secure: true, supportFetchAPI: true, corsEnabled: true } },
]);

if (!app.requestSingleInstanceLock()) app.quit();

function regValue(key, name) {
  return new Promise((resolve) => {
    execFile('reg', ['query', key, '/v', name], { windowsHide: true }, (err, out) => {
      if (err) return resolve(null);
      const m = out.match(new RegExp(`${name}\\s+REG_\\w+\\s+(.+)`));
      resolve(m ? m[1].trim() : null);
    });
  });
}

let apoCache = null;
async function apoInfo() {
  if (apoCache) return apoCache;
  if (DEMO) {
    const configPath = path.join(app.getPath('userData'), 'demo-config');
    fs.mkdirSync(configPath, { recursive: true });
    apoCache = { installed: true, demo: true, configPath, installPath: null };
  } else {
    const configPath = await regValue('HKLM\\SOFTWARE\\EqualizerAPO', 'ConfigPath');
    const installPath = await regValue('HKLM\\SOFTWARE\\EqualizerAPO', 'InstallPath');
    apoCache = { installed: !!configPath && fs.existsSync(configPath), demo: false, configPath, installPath };
  }
  return apoCache;
}

/** Escribe MAD.txt de forma atómica y se asegura de que config.txt lo incluya. */
async function writeConfig(text) {
  const info = await apoInfo();
  if (!info.installed) return { ok: false, error: 'EQUALIZER APO NO INSTALADO' };
  try {
    const target = path.join(info.configPath, CONFIG_FILE);
    const tmp = target + '.tmp';
    fs.writeFileSync(tmp, text, 'utf8');
    fs.renameSync(tmp, target);
    const main = path.join(info.configPath, 'config.txt');
    const current = fs.existsSync(main) ? fs.readFileSync(main, 'utf8') : '';
    if (!current.split(/\r?\n/).some(l => l.trim().toLowerCase() === INCLUDE_LINE.toLowerCase())) {
      fs.writeFileSync(main, current + (current && !current.endsWith('\n') ? '\r\n' : '') + INCLUDE_LINE + '\r\n', 'utf8');
    }
    return { ok: true, path: target };
  } catch (e) {
    return { ok: false, error: e.code === 'EPERM' || e.code === 'EACCES' ? 'SIN PERMISO PARA ESCRIBIR LA CONFIGURACION' : String(e.message).toUpperCase() };
  }
}

function createWindow() {
  const area = screen.getPrimaryDisplay().workAreaSize;
  // Con escalado alto de Windows (125–150 %) la ventana podría no caber: se reduce entera.
  const zoom = Math.min(1, (area.width - 24) / WIDTH, (area.height - 24) / HEIGHT);
  const win = new BrowserWindow({
    width: Math.round(WIDTH * zoom),
    height: Math.round(HEIGHT * zoom),
    useContentSize: true,
    resizable: false,
    maximizable: false,
    fullscreenable: false,
    title: 'MAD Equalizer',
    backgroundColor: '#0a0b0d',
    icon: path.join(__dirname, 'assets', 'icon.png'),
    titleBarStyle: 'hidden',
    titleBarOverlay: WIN ? { color: '#0a0b0d', symbolColor: '#c9ced6', height: Math.round(30 * zoom) } : undefined,
    trafficLightPosition: { x: 12, y: 9 },
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      sandbox: false,
      backgroundThrottling: false,
      additionalArguments: [`--mad-platform=${process.platform}`, ...(DEMO ? ['--mad-demo'] : [])],
    },
  });
  win.setMenuBarVisibility(false);
  win.webContents.on('did-finish-load', () => win.webContents.setZoomFactor(zoom));
  win.loadURL('app://mad/index.html');
}

app.whenReady().then(() => {
  protocol.handle('app', (req) => {
    const rel = decodeURIComponent(new URL(req.url).pathname);
    const file = path.normalize(path.join(__dirname, 'renderer', rel));
    if (!file.startsWith(path.join(__dirname, 'renderer'))) return new Response('', { status: 403 });
    return net.fetch(pathToFileURL(file).toString());
  });

  // Captura loopback: Windows entrega una copia del audio que suena, sólo para los medidores.
  session.defaultSession.setDisplayMediaRequestHandler((req, callback) => {
    desktopCapturer.getSources({ types: ['screen'] })
      .then(sources => callback({ video: sources[0], audio: 'loopback' }))
      .catch(() => callback({}));
  });

  ipcMain.handle('apo:status', () => apoInfo());
  ipcMain.handle('apo:write', (_e, text) => writeConfig(String(text)));
  ipcMain.handle('apo:devices', async () => {
    const info = await apoInfo();
    const exe = info.installPath && path.join(info.installPath, 'DeviceSelector.exe');
    if (exe && fs.existsSync(exe)) return shell.openPath(exe);
    return 'NO DISPONIBLE';
  });
  ipcMain.handle('sys:sound', () => (WIN ? shell.openExternal('ms-settings:sound') : null));

  createWindow();
});

app.on('second-instance', () => {
  const w = BrowserWindow.getAllWindows()[0];
  if (w) { if (w.isMinimized()) w.restore(); w.focus(); }
});
app.on('window-all-closed', () => app.quit());
