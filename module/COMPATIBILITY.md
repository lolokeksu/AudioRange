# Compatibility

Compatibility is established by the actual Android `AudioService` range after reboot, not by the brand name or Android version alone.

| Environment | Root | Status | Verified result |
|---|---|---|---|
| Realme GT Neo 5 SE / RMX3700 / Android 13 / Realme UI 4.0 | APatch | Verified beta target | `STREAM_MUSIC 0–30` |
| Other Realme, OPPO and OnePlus firmware | Any supported root | Experimental | Exact fingerprint starts unverified |
| Samsung, Xiaomi, Pixel and other OEMs | Any supported root | Experimental | Runtime calibration required |
| Android 14–16 | APatch / KernelSU / Magisk | Code-supported, not hardware-verified | Device report required |

The bundled limit of 30 is matched only against the exact researched RMX3700 fingerprint. It is never treated as a global Realme/Oplus limit.
