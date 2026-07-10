# xalarm — Play Store release runbook

The repo is Play-ready: the applicationId is `com.xalarm`, Play builds strip
the self-update flow (Play policy forbids it), the launcher icon and store
graphics are generated, and `build-play.sh` produces a signed App Bundle via
Docker with no local Flutter install.

## 0. One-time: create your upload key (keep it PRIVATE)

The committed `android/app/xalarm-release.p12` is only for the self-hosted
sideload channel. Play uploads use a separate private key.

On the server (or any machine with a JDK):

```bash
mkdir -p ~/xalarm-keys && cd ~/xalarm-keys
keytool -genkeypair -v -keystore upload.jks -alias upload \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=xalarm, O=xattribution"
```

No JDK? openssl works too:

```bash
mkdir -p ~/xalarm-keys && cd ~/xalarm-keys
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem \
  -days 10000 -nodes -subj "/CN=xalarm/O=xattribution"
openssl pkcs12 -export -in cert.pem -inkey key.pem \
  -out upload.jks -name upload            # prompts for a password
rm key.pem cert.pem
```

Then create `~/xalarm-keys/key.properties`:

```properties
storeFile=/keys/upload.jks
storePassword=YOUR_PASSWORD
keyAlias=upload
keyPassword=YOUR_PASSWORD
```

Back up `~/xalarm-keys/` somewhere safe (password manager attachment,
encrypted drive). With Play App Signing, Google can rotate a lost upload key,
but it's a support process you don't want.

## 1. Build the bundle

```bash
cd ~/dockerapps/xalarm        # the update.sh clone
XALARM_KEYS_DIR=~/xalarm-keys ./build-play.sh
# → dist/xalarm-1.5.0+7.aab
```

Every new upload needs a higher versionCode (the `+N` in pubspec.yaml's
`version:` — bumped with each release here already).

## 2. Play Console: create the app

play.google.com/console → Create app:
- Name **xalarm**, default language, **App**, **Free**.
- The package name (`com.xalarm`) is taken from your first uploaded bundle
  and is permanent after that.

### Store listing
- Short description (≤80 chars), e.g.
  *Alarms built for shift work — Panama & rotating schedules, zen timer, sync.*
- Full description: lead with rotating-shift alarms (Panama 2-2-3, 4-on/2-off,
  DuPont, custom cycles, per-day start times), then world clock, stopwatch,
  timer, zen mode, home-screen widgets.
- Graphics (in `deploy/store-assets/`): `play-icon-512.png`,
  `feature-graphic.png`. Screenshots: at least 2 phone screenshots — take
  them on your device (alarm list with a shift alarm, the shift schedule
  library, zen mode mid-flow are the money shots).
- **Privacy policy URL**: `https://xalarm.tinbadger.com/privacy`
  (served by the web container after the next `update.sh`).

### App content section (the questionnaires)
- **Privacy policy**: URL above.
- **Ads**: No.
- **App access**: all functionality available without special access (no
  login).
- **Content rating (IARC)**: utility app, no objectionable content →
  Everyone.
- **Target audience**: 18+ or 13+ (not designed for children either way).
- **Data safety**: No data collected, no data shared. (Time Sync transmits a
  display name ephemerally through your own relay and stores nothing —
  Google's form counts "collected" as leaving the device to the developer
  with storage; we store nothing. Answering "no collection" is accurate.)
- **Government app / News app / COVID app**: No.

### Permission declarations (Policy → App content → sensitive permissions)
- **Alarms & reminders (`USE_EXACT_ALARM`)**: declare the app's core purpose
  is an alarm clock — that permission is reserved for exactly this category,
  so it's an approval, not a fight.
- **Full-screen intent (`USE_FULL_SCREEN_INTENT`)**: same rationale — the
  ring screen for alarms/timers.
- **Foreground service (`FOREGROUND_SERVICE_MEDIA_PLAYBACK`)**: used to play
  the alarm sound while ringing. If asked for a video, screen-record an alarm
  firing to the ring screen.

## 3. Release path

1. **Internal testing** (Testing → Internal testing): create a release,
   upload the AAB, accept enrollment in **Play App Signing** when prompted
   (mandatory; Google signs what users install, your upload key just
   authenticates uploads). Add your own Google account as a tester, install
   from the opt-in link, confirm everything works.
   - Note: the Play-installed app is a different signature from your
     sideloads — uninstall the sideloaded xalarm first on that device.
2. **Closed testing**: promote the release, create an email list with your
   ~12 testers, send them the opt-in link. Personal accounts must run this
   with 12+ testers **continuously for 14 days** before production unlocks.
   Push updated AABs during the period freely (fixes don't reset the clock;
   dropping below 12 testers does).
3. **Production**: after the 14 days, the console unlocks "apply for
   production" — answer the short questionnaire about your test learnings,
   then create the production release. First review typically takes 1–7
   days. Consider a staged rollout (20% → 100%).

## 4. Ongoing releases

- Bump `version:` in pubspec.yaml (both name and `+versionCode`).
- `./build-play.sh` → upload the new AAB to the track of your choice.
- The self-hosted channel keeps working unchanged (`update.sh` builds sign
  with the committed sideload key and keep the in-app updater). The two
  channels are separate installs; a device follows whichever installed it.

## Channel differences at a glance

| | Sideload (tinbadger.com) | Play Store |
|---|---|---|
| Signing key | committed p12 | private upload key + Play App Signing |
| Format | APK | AAB |
| In-app updater | yes | compiled out (`PLAY_STORE=true`) |
| Updates | in-app check → download | Google Play |
