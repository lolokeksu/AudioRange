# Testing protocol

After installation and reboot:

```sh
su -c audiorange check
su -c audiorange doctor
su -c audiorange report
```

A profile is confirmed only when the requested value, `ro.config.media_vol_steps` and the maximum reported by `cmd media_session volume --stream 3 --get` agree.

For a new device, attach the report with personal identifiers reviewed. Do not force repeated automatic reboots or patch framework JAR files.
