SID.R4D
=======

SID-SynthEngine-Treiber fuer R4OS.

Ziele:
- erzeugt eine gueltige SID.R4D-Datei mit Treibertyp synth
- wird aus Zig ueber Code/System/SDK/r4os und Code/build.zig gebaut
- nutzt seit 0.45.20 DriverApi-v12 `register_synth_engine_v2` ueber den
  SDK-Wrapper `registerSynthEngineEx`
- seit 0.45.23 besitzt SID.R4D die SID-Laufzeit-Engine selbst:
  6502/6510-Stepper, C64-Speicher, PSID/RSID-Ladedaten, Init-/Play-Routinen,
  SID-Registermodell, I/O-Spiegel, ADSR/Filter und Renderzustand
- sorgt dafuer, dass AUDIO eine registrierte externe Synth-Engine "SID"
  mit Statuswerten aus dem R4D anzeigen kann

PCM-Pfad:
- `sid_play_frame` fuehrt die C64-/SID-Laufzeit im Treiber aus.
- `sid_render_pcm` liefert danach den gerenderten 48-kHz-Stereo-s16le-Block
  an den Kernel zurueck, der ihn unveraendert an das aktive AudioBackend
  weitergibt.

Build:

    cd Code
    ..\DevTools\Zig\zig.exe build

Output:

    Code/zig-out/SID.R4D

Projektstruktur seit 0.51.22
--------------------------------

Dieses Verzeichnis ist ein eigenstaendiges R4OS-SDK-Projekt fuer SID.R4D.

Build:

    cd Code\System\Driver\SID
    ..\..\..\DevTools\Zig\zig.exe build

Artefakt:

    zig-out\SID.R4D

Manifest:

    module.R4MF

Image-Zielpfad: C:\R4OS\DRIVERS\SID.R4D
