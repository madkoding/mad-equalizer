; Instalador de MAD Equalizer para Windows (NSIS 3).
; Instala la app y, si hace falta, el instalador oficial de Equalizer APO, que hace el ecualizado.
Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"

!define APPNAME "MAD Equalizer"
!ifndef VERSION
  !define VERSION "0.0.0"
!endif
!define EAPO "EqualizerAPO-x64-1.4.2.exe"
!define UNINSTKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\MADEqualizer"
!define BACKUP "config.before-MAD.txt"

Name "${APPNAME}"
OutFile "../out/MAD-Equalizer-${VERSION}-Setup.exe"
InstallDir "$PROGRAMFILES64\${APPNAME}"
InstallDirRegKey HKLM "Software\MADEqualizer" "InstallDir"
RequestExecutionLevel admin
SetCompressor /SOLID lzma
BrandingText "MAD Equalizer ${VERSION}"

VIProductVersion "${VERSION}.0"
VIAddVersionKey /LANG=1033 "ProductName" "${APPNAME}"
VIAddVersionKey /LANG=1033 "FileDescription" "${APPNAME} Setup"
VIAddVersionKey /LANG=1033 "FileVersion" "${VERSION}"
VIAddVersionKey /LANG=1033 "ProductVersion" "${VERSION}"
VIAddVersionKey /LANG=1033 "LegalCopyright" "MAD Equalizer"

!define MUI_ICON "../assets/icon.ico"
!define MUI_UNICON "../assets/icon.ico"
!define MUI_WELCOMEFINISHPAGE_BITMAP "wizard.bmp"
!define MUI_UNWELCOMEFINISHPAGE_BITMAP "wizard.bmp"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\MADEqualizer.exe"
!define MUI_FINISHPAGE_SHOWREADME "$INSTDIR\$(README_FILE)"
!define MUI_FINISHPAGE_SHOWREADME_NOTCHECKED

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; El primero es el idioma por defecto; NSIS elige el del sistema si está en la lista.
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "Spanish"

LangString README_FILE ${LANG_ENGLISH} "README.txt"
LangString README_FILE ${LANG_SPANISH} "LEEME.txt"
LangString NEED64 ${LANG_ENGLISH} "MAD Equalizer requires 64-bit Windows 10 or 11."
LangString NEED64 ${LANG_SPANISH} "MAD Equalizer necesita Windows 10 u 11 de 64 bits."
LangString APO_INTRO ${LANG_ENGLISH} "MAD Equalizer uses Equalizer APO (free) to process your PC's audio. Its installer will open now.$\r$\n$\r$\nIMPORTANT: when the Configurator appears, CHECK THE DEVICES YOU LISTEN ON (headphones, speakers...) and click OK."
LangString APO_INTRO ${LANG_SPANISH} "MAD Equalizer usa Equalizer APO (gratuito) para procesar el audio del PC. Ahora se abrirá su instalador.$\r$\n$\r$\nIMPORTANTE: cuando aparezca el Configurator, MARCA LOS DISPOSITIVOS DONDE ESCUCHAS (audífonos, altavoces...) y pulsa OK."
LangString APO_MISSING ${LANG_ENGLISH} "Equalizer APO was not installed. MAD Equalizer will open, but it can't equalize until Equalizer APO is installed. See the README."
LangString APO_MISSING ${LANG_SPANISH} "Equalizer APO no quedó instalado. MAD Equalizer se abrirá, pero no podrá ecualizar hasta instalarlo. Revisa el LEEME."
LangString APO_REPLACE ${LANG_ENGLISH} "Equalizer APO already has its own configuration.$\r$\n$\r$\nReplace it with MAD Equalizer's? (Recommended. A backup is kept and restored if you uninstall MAD.)$\r$\n$\r$\nIf you choose No, both configurations will be applied one after the other."
LangString APO_REPLACE ${LANG_SPANISH} "Equalizer APO ya tiene su propia configuración.$\r$\n$\r$\n¿Reemplazarla por la de MAD Equalizer? (Recomendado. Se guarda una copia y se restaura si desinstalas MAD.)$\r$\n$\r$\nSi eliges No, se aplicarán ambas configuraciones una tras otra."

Var ConfigPath
Var FreshAPO

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_OK|MB_ICONSTOP "$(NEED64)"
    Abort
  ${EndIf}
  SetRegView 64
  InitPluginsDir
FunctionEnd

Function un.onInit
  SetRegView 64
FunctionEnd

Section "MAD Equalizer"
  SetShellVarContext all
  SetOutPath "$INSTDIR"
  File /r "../dist/MAD Equalizer/*.*"
  File "README.txt" "LEEME.txt" "THIRD-PARTY-NOTICES.txt"
  SetOutPath "$INSTDIR\licenses"
  File "licenses/*.txt"
  SetOutPath "$INSTDIR"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  CreateShortcut "$SMPROGRAMS\${APPNAME}.lnk" "$INSTDIR\MADEqualizer.exe"
  CreateShortcut "$DESKTOP\${APPNAME}.lnk" "$INSTDIR\MADEqualizer.exe"

  WriteRegStr HKLM "Software\MADEqualizer" "InstallDir" "$INSTDIR"
  WriteRegStr HKLM "${UNINSTKEY}" "DisplayName" "${APPNAME}"
  WriteRegStr HKLM "${UNINSTKEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKLM "${UNINSTKEY}" "Publisher" "MAD"
  WriteRegStr HKLM "${UNINSTKEY}" "DisplayIcon" "$INSTDIR\MADEqualizer.exe"
  WriteRegStr HKLM "${UNINSTKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINSTKEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegDWORD HKLM "${UNINSTKEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINSTKEY}" "NoRepair" 1
  WriteRegDWORD HKLM "${UNINSTKEY}" "EstimatedSize" 280000

  ; ---- Equalizer APO ----
  StrCpy $FreshAPO "0"
  ReadRegStr $ConfigPath HKLM "SOFTWARE\EqualizerAPO" "ConfigPath"
  ${If} $ConfigPath == ""
    MessageBox MB_OK|MB_ICONINFORMATION "$(APO_INTRO)"
    SetOutPath "$PLUGINSDIR"
    File "../vendor/${EAPO}"
    ExecWait '"$PLUGINSDIR\${EAPO}"'
    SetOutPath "$INSTDIR"
    ReadRegStr $ConfigPath HKLM "SOFTWARE\EqualizerAPO" "ConfigPath"
    ${If} $ConfigPath == ""
      MessageBox MB_OK|MB_ICONEXCLAMATION "$(APO_MISSING)"
    ${Else}
      StrCpy $FreshAPO "1"
      SetRebootFlag true
    ${EndIf}
  ${EndIf}

  ${If} $ConfigPath != ""
    ; MAD escribe su configuración como usuario normal: la carpeta debe ser editable por "Usuarios".
    nsExec::ExecToLog 'icacls "$ConfigPath" /grant *S-1-5-32-545:(OI)(CI)M /T /Q'
    ; El config.txt de ejemplo de Equalizer APO trae filtros de prueba: se sustituye por el de MAD.
    ${If} $FreshAPO == "1"
      Call ReplaceConfig
    ${ElseIfNot} ${FileExists} "$ConfigPath\${BACKUP}"
      MessageBox MB_YESNO|MB_ICONQUESTION "$(APO_REPLACE)" IDNO keep
      Call ReplaceConfig
      keep:
    ${EndIf}
  ${EndIf}
SectionEnd

Function ReplaceConfig
  ${If} ${FileExists} "$ConfigPath\config.txt"
  ${AndIfNot} ${FileExists} "$ConfigPath\${BACKUP}"
    CopyFiles /SILENT "$ConfigPath\config.txt" "$ConfigPath\${BACKUP}"
  ${EndIf}
  FileOpen $0 "$ConfigPath\config.txt" w
  FileWrite $0 "Include: MAD.txt$\r$\n"
  FileClose $0
  FileOpen $0 "$ConfigPath\MAD.txt" w
  FileWrite $0 "# MAD Equalizer$\r$\n"
  FileClose $0
FunctionEnd

Section "Uninstall"
  SetShellVarContext all
  ; Equalizer APO queda instalado: se restaura su configuración anterior o se deja sin efecto.
  ReadRegStr $ConfigPath HKLM "SOFTWARE\EqualizerAPO" "ConfigPath"
  ${If} $ConfigPath != ""
    ${If} ${FileExists} "$ConfigPath\${BACKUP}"
      Delete "$ConfigPath\config.txt"
      Rename "$ConfigPath\${BACKUP}" "$ConfigPath\config.txt"
    ${EndIf}
    FileOpen $0 "$ConfigPath\MAD.txt" w
    FileWrite $0 "# MAD Equalizer uninstalled$\r$\n"
    FileClose $0
  ${EndIf}
  Delete "$SMPROGRAMS\${APPNAME}.lnk"
  Delete "$DESKTOP\${APPNAME}.lnk"
  RMDir /r "$INSTDIR"
  DeleteRegKey HKLM "${UNINSTKEY}"
  DeleteRegKey HKLM "Software\MADEqualizer"
SectionEnd
