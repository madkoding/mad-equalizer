// MAD Equalizer para Windows: interfaz de Equalizer APO.
// El ecualizado lo hace Equalizer APO en el sistema; esta app escribe su configuración (MAD.txt)
// y mide el audio de salida con una captura loopback.
const { app, BrowserWindow, ipcMain, session, desktopCapturer, shell, protocol, net, screen } = require('electron');
const path = require('path');
const fs = require('fs');
const { execFile } = require('child_process');
const { pathToFileURL } = require('url');

const WIN = process.platform === 'win32';
// --screenshot=<archivo.png>: abre la app en modo demo, elige un preset, guarda una captura y sale.
// Sirve para generar las imágenes del README y de la página web desde CI.
const SHOT = (process.argv.find(a => a.startsWith('--screenshot=')) || '').slice('--screenshot='.length);
// Fuera de Windows (o con --demo) no hay Equalizer APO: la configuración va a una carpeta local
// y el audio es una señal de prueba. Sirve para desarrollar y revisar la interfaz.
const DEMO = !WIN || process.argv.includes('--demo') || !!SHOT;
const WIDTH = 1120, HEIGHT = 802;
const CONFIG_FILE = 'MAD.txt';
const INCLUDE_LINE = `Include: ${CONFIG_FILE}`;

// Perfil limpio para que la captura no dependa de preferencias guardadas.
if (SHOT) app.commandLine.appendSwitch('force-device-scale-factor', '2');
if (SHOT) app.setPath('userData', fs.mkdtempSync(path.join(require('os').tmpdir(), 'mad-shot-')));

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

// Ventana redimensionable con la proporción fija: el contenido se escala con el zoom.
// El tamaño mínimo es el 60 % del original; el máximo, lo que cabe en la pantalla (hasta 200 %).
const MIN_ZOOM = 0.6;
const prefsFile = () => path.join(app.getPath('userData'), 'prefs.json');
function readZoom() {
  try {
    const z = JSON.parse(fs.readFileSync(prefsFile(), 'utf8')).zoom;
    return typeof z === 'number' && isFinite(z) ? z : null;
  } catch { return null; }
}
function writeZoom(zoom) {
  try { fs.writeFileSync(prefsFile(), JSON.stringify({ zoom })); } catch { /* sin preferencia guardada */ }
}

let mainWin = null;

// Con escalado alto de Windows (125–150 %) la ventana podría no caber: se reduce entera.
function fitZoom() {
  const area = screen.getPrimaryDisplay().workAreaSize;
  return Math.min((area.width - 24) / WIDTH, (area.height - 24) / HEIGHT);
}
const maxZoom = () => Math.max(MIN_ZOOM, Math.min(2, fitZoom()));
const clampZoom = (z) => Math.min(maxZoom(), Math.max(MIN_ZOOM, z));
const startZoom = () => clampZoom(readZoom() ?? Math.min(1, fitZoom()));

function applyZoom(win, zoom) {
  win.webContents.setZoomFactor(zoom);
  if (WIN) win.setTitleBarOverlay({ color: '#0a0b0d', symbolColor: '#c9ced6', height: Math.max(1, Math.round(30 * zoom)) });
}

function createWindow() {
  const zoom = startZoom();
  const win = new BrowserWindow({
    width: Math.round(WIDTH * zoom),
    height: Math.round(HEIGHT * zoom),
    useContentSize: true,
    minWidth: Math.round(WIDTH * MIN_ZOOM),
    minHeight: Math.round(HEIGHT * MIN_ZOOM),
    resizable: true,
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
  mainWin = win;
  win.setAspectRatio(WIDTH / HEIGHT);
  win.setMaximumSize(Math.round(WIDTH * maxZoom()), Math.round(HEIGHT * maxZoom()));
  win.webContents.on('did-finish-load', () => applyZoom(win, startZoom()));
  // El contenido sigue al tamaño de la ventana; la preferencia se guarda al dejar de redimensionar.
  let saveTimer = null;
  win.on('resize', () => {
    const zoom = clampZoom(win.getContentSize()[0] / WIDTH);
    applyZoom(win, zoom);
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => writeZoom(zoom), 400);
  });
  win.loadURL('app://mad/index.html');
  if (SHOT) takeScreenshot(win, SHOT);
}

function takeScreenshot(win, file) {
  win.webContents.once('did-finish-load', async () => {
    try {
      await new Promise(r => setTimeout(r, 1500));
      // Un preset con curva marcada y el equipo encendido (ya lo está por defecto).
      await win.webContents.executeJavaScript("[...document.querySelectorAll('#rowPreset button')].find(b => b.textContent === 'ROCK')?.click()");
      await new Promise(r => setTimeout(r, 4000));
      const image = await win.webContents.capturePage();
      fs.mkdirSync(path.dirname(path.resolve(file)), { recursive: true });
      fs.writeFileSync(file, image.toPNG());
      console.log('Captura guardada:', file);
      app.exit(0);
    } catch (e) {
      console.error(e);
      app.exit(1);
    }
  });
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
