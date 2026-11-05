MAD EQUALIZER @VERSION@
16-band stereo graphic equalizer for all of your Mac's audio
=====================================================================

REQUIREMENTS
  • macOS 14.4 (Sonoma) or later
  • Apple Silicon or Intel Mac
  • No BlackHole or any other audio driver needed


INSTALLATION
  1. Drag "MAD Equalizer" into the Applications folder.
  2. Open the app from Applications (not from the DMG).
  3. Press POWER. The first time, macOS will ask for permission to record
     system audio: click "Allow". Without that permission you won't hear
     anything while the equalizer is on.


WON'T OPEN? ("IS DAMAGED" / "CANNOT VERIFY THE DEVELOPER")
  The app isn't notarized by Apple, so macOS blocks it after downloading.
  To remove that block (the "quarantine"):

  1. Open the Terminal app (Applications > Utilities > Terminal).
  2. Copy and paste this command and press Return:

       xattr -dr com.apple.quarantine "/Applications/MAD Equalizer.app"

  3. Open MAD Equalizer again.

  Without Terminal: try to open the app once, then go to
  System Settings > Privacy & Security, scroll down to the message about
  "MAD Equalizer" and click "Open Anyway".


NO SOUND WITH THE APP ON
  Check the audio permission:
  System Settings > Privacy & Security >
  Screen & System Audio Recording > "System Audio Recording Only"
  and turn on MAD Equalizer. Then switch POWER off and on.

  If there's still no sound, quit the app (audio goes back to normal) and
  restart the audio service with this command in Terminal (it asks for
  your password):

       sudo killall coreaudiod


QUICK GUIDE
  • Volume: use your Mac's volume keys as usual.
  • Output: pick your headphones or speakers in the macOS sound menu, or
    click "OUTPUT" on the display; the equalizer follows automatically.
  • Faders: drag the cap or click the track. Double-click = 0 dB.
  • Knobs: drag up or down. Double-click = default value.
  • STORE + M1–M4 saves a curve; M1–M4 recalls it. A/B compares two.
  • LUFS I: click the number to reset the measurement.
  • APPS: check the apps you want to hear without EQ (for example,
    video calls).
  • Closing the window quits the app and audio goes back to normal.


UNINSTALL
  Drag "MAD Equalizer" from Applications to the Trash.
  To also delete saved settings, run in Terminal:

       defaults delete local.eq16
