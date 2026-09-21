# xalarm — signing keys

Every release APK/AAB must be signed, and Android only installs an update
over an existing install when both are signed with the **same** key. That
makes the key the single most sensitive file in the project: whoever holds
it can ship a build that every existing install accepts as a legitimate
update. No key is committed to this repository, ever.

There are two channels, each with its own key:

| Channel | Key file | Application id | Built by |
|---------|----------|----------------|----------|
| Google Play | `~/xalarm-keys/upload.jks` + `key.properties` | `com.xalarm` | `build-play.sh` |
| Self-hosted (sideload) | `~/xalarm-keys/sideload.jks` + `sideload.properties` | `com.xalarm.sideload` | `update.sh` / Docker |

The sideload build gets its own application id so it can be installed next
to the Play build; the two can never upgrade each other anyway because their
keys differ. Set `XALARM_APP_ID_SUFFIX=` (empty) before `update.sh` if you
would rather keep a single id.

## Sideload key (self-hosted download site)

`update.sh` generates the key on its first run and writes it to
`XALARM_KEYS_DIR` (default `~/xalarm-keys`, resolved for the real user even
under `sudo`):

```
~/xalarm-keys/sideload.jks
~/xalarm-keys/sideload.properties   # storeFile=/keys/sideload.jks + passwords
```

Both files are mounted into the Docker build as BuildKit secrets, so they
never land in an image layer. **Back this directory up.** If it is lost,
every phone with the app installed has to uninstall before it can take a new
build.

To supply your own key instead, create the two files yourself before the
first run; `storeFile` must be the in-container path `/keys/sideload.jks`.

## Play upload key

Unchanged from before — see the header of `build-play.sh`. `key.properties`
is copied into `android/` for the duration of the build and removed after.

## Local builds

With neither properties file present, `flutter build apk --release` signs
with the debug key and Gradle prints a warning. That build is fine for a
test device but cannot be installed over a real release, and a real release
cannot be installed over it.

## History

Versions up to 1.5.0 shipped with a keystore committed to this public
repository (`android/app/xalarm-release.p12`, password in `build.gradle.kts`).
That key is compromised by definition and is no longer used. Installs signed
with it must be uninstalled once before installing 1.6.0 or later from the
download site (the Play build was never signed with it). The file remains in
git history; rewriting history is optional since the key is retired either
way.
