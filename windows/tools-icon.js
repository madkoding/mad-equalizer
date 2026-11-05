// Pone el icono y los datos de versión al .exe de Windows (resedit es JavaScript puro: no necesita Wine).
const ResEdit = require('resedit');
const fs = require('fs');
const path = require('path');

const exePath = process.argv[2];
// VERSION viene de pack.sh (1.2.3); se completa a cuatro números para el recurso de versión.
const version = process.env.VERSION || require('./package.json').version;
const [vMajor, vMinor, vPatch] = [...version.split(/[.-]/).map((n) => parseInt(n, 10) || 0), 0, 0, 0];
const exe = ResEdit.NtExecutable.from(fs.readFileSync(exePath));
const res = ResEdit.NtExecutableResource.from(exe);
const ico = ResEdit.Data.IconFile.from(fs.readFileSync(path.join(__dirname, 'assets', 'icon.ico')));
ResEdit.Resource.IconGroupEntry.replaceIconsForResource(res.entries, 1, 1033, ico.icons.map(i => i.data));
const vi = ResEdit.Resource.VersionInfo.fromEntries(res.entries)[0];
vi.setStringValues({ lang: 1033, codepage: 1200 }, {
  ProductName: 'MAD Equalizer', FileDescription: 'MAD Equalizer', CompanyName: 'MAD',
  OriginalFilename: 'MADEqualizer.exe', InternalName: 'MADEqualizer', LegalCopyright: 'MAD Equalizer',
  ProductVersion: version, FileVersion: version,
});
vi.setFileVersion(vMajor, vMinor, vPatch, 0, 1033);
vi.setProductVersion(vMajor, vMinor, vPatch, 0, 1033);
vi.outputToResourceEntries(res.entries);
res.outputResource(exe);
fs.writeFileSync(exePath, Buffer.from(exe.generate()));
console.log('Icono y versión aplicados:', path.basename(exePath));
