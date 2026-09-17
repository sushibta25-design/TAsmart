TAsmart v0.1.1 recovery

Purpose:
- Remove all CarPlay.app and SpringBoard injection.
- Restore CarPlay connectivity before any further MiniBridge experiments.
- Inject only into com.sushibta.a510player and write /var/mobile/TAsmartRecovery.log.

Test:
1. Replace the four project files with this ZIP and build.
2. Uninstall the currently installed TAsmart package first if possible.
3. Install the new 0.1.1-recovery DEB and respring.
4. Confirm CarPlay connects normally.
5. Open TAsmart/A510Player once and optionally check /var/mobile/TAsmartRecovery.log.

Do not continue to v0.2-safe.
