'use strict';
// Reproductor activo en Windows vía SMTC (System Media Transport Controls), la misma fuente del
// panel de volumen: Spotify, Tidal, Apple Music, navegadores, VLC… Se consulta con PowerShell
// (WinRT) para no depender de módulos nativos.
const { spawn, execFile } = require('child_process');
const readline = require('readline');

const PREAMBLE = `
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation\`1' })[0]
function Await($op, $t) { $task = $asTask.MakeGenericMethod($t).Invoke($null, @($op)); [void]$task.Wait(-1); $task.Result }
$tM = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
$tP = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties, Windows.Media.Control, ContentType = WindowsRuntime]
$mgr = Await ($tM::RequestAsync()) $tM
function Pick() {
  $all = @($mgr.GetSessions())
  foreach ($s in $all) { if ($s.GetPlaybackInfo().PlaybackStatus -eq 'Playing') { return $s } }
  $c = $mgr.GetCurrentSession(); if ($c) { return $c }
  if ($all.Count) { return $all[0] }
  return $null
}
`;

const POLL = PREAMBLE + `
while ($true) {
  try {
    $s = Pick
    if ($null -eq $s) { 'null' } else {
      $p = Await ($s.TryGetMediaPropertiesAsync()) $tP
      $tl = $s.GetTimelineProperties()
      $playing = $s.GetPlaybackInfo().PlaybackStatus -eq 'Playing'
      $pos = $tl.Position.TotalSeconds
      if ($playing) { $pos += ([DateTimeOffset]::UtcNow - $tl.LastUpdatedTime).TotalSeconds }
      $dur = ($tl.EndTime - $tl.StartTime).TotalSeconds
      if ($dur -gt 0 -and $pos -gt $dur) { $pos = $dur }
      if ($pos -lt 0 -or $pos -gt 360000) { $pos = 0 }
      [pscustomobject]@{ id = $s.SourceAppUserModelId; title = $p.Title; artist = $p.Artist; album = $p.AlbumTitle; position = $pos; duration = $dur; playing = $playing } | ConvertTo-Json -Compress
    }
  } catch { 'null' }
  Start-Sleep -Milliseconds 1500
}
`;

const KEYS = { previous: 0xB1, toggle: 0xB3, next: 0xB0 };
const METHOD = { previous: 'TrySkipPreviousAsync', toggle: 'TryTogglePlayPauseAsync', next: 'TrySkipNextAsync' };

function commandScript(cmd) {
  return PREAMBLE + `
$s = Pick
if ($s) { [void](Await ($s.${METHOD[cmd]}()) ([bool])) } else {
  Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, uint f, UIntPtr e);' -Name K -Namespace W
  [W.K]::keybd_event(${KEYS[cmd]}, 0, 0, [UIntPtr]::Zero); [W.K]::keybd_event(${KEYS[cmd]}, 0, 2, [UIntPtr]::Zero)
}
`;
}

const enc = (s) => Buffer.from(s, 'utf16le').toString('base64');
const PS = ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand'];

const NAMES = [
  [/spotify/i, 'Spotify'], [/tidal/i, 'TIDAL'], [/applemusic|apple\.music|itunes/i, 'Apple Music'],
  [/zunemusic|music\.ui|media\.player/i, 'Reproductor'], [/chrome/i, 'Chrome'], [/msedge/i, 'Edge'],
  [/firefox/i, 'Firefox'], [/brave/i, 'Brave'], [/vlc/i, 'VLC'], [/deezer/i, 'Deezer'],
  [/amazon.*music/i, 'Amazon Music'], [/foobar/i, 'foobar2000'], [/musicbee/i, 'MusicBee'],
];

/** "Spotify.exe", "SpotifyAB.SpotifyMusic_zpdnekdrzrea0!Spotify" → nombre legible. */
function appName(id) {
  id = String(id || '');
  for (const [re, name] of NAMES) if (re.test(id)) return name;
  const base = id.split('!').pop().replace(/\.exe$/i, '');
  return base ? base[0].toUpperCase() + base.slice(1) : 'Reproductor';
}

function toInfo(o) {
  if (!o) return null;
  return {
    app: appName(o.id), title: o.title || '', artist: o.artist || '', album: o.album || '',
    position: Number(o.position) || 0, duration: Number(o.duration) || 0, playing: !!o.playing,
  };
}

/** Empieza a emitir `onInfo(info|null)` cada ~1,5 s. Devuelve una función para detenerlo. */
function watch(onInfo) {
  let child = null, stopped = false, last = '';
  const start = () => {
    child = spawn('powershell.exe', [...PS, enc(POLL)], { windowsHide: true, stdio: ['ignore', 'pipe', 'ignore'] });
    readline.createInterface({ input: child.stdout }).on('line', (line) => {
      let info = null;
      try { info = toInfo(JSON.parse(line)); } catch { /* línea inválida */ }
      const key = JSON.stringify(info);
      if (key !== last) { last = key; onInfo(info); }
    });
    child.on('error', () => {});
    child.on('exit', () => { if (!stopped) setTimeout(start, 5000); });
  };
  start();
  return () => { stopped = true; child?.kill(); };
}

function command(cmd) {
  if (!METHOD[cmd]) return Promise.resolve(false);
  return new Promise((resolve) => {
    execFile('powershell.exe', [...PS, enc(commandScript(cmd))], { windowsHide: true, timeout: 10000 },
      (err) => resolve(!err));
  });
}

module.exports = { watch, command, appName, toInfo };
