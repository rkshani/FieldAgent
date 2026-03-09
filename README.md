# field_agents

TCL Field Agents Flutter app – login, orders, invoices, and local data sync.

## Getting Started

### Run the app

```bash
flutter pub get
flutter run
```

Select a device (e.g. Android) when prompted.

### Login (Android parity)

- **Session check on start:** If already logged in, app opens Home; otherwise Login screen.
- **Normal login:** POST to base URL with `check_login=1`, username, password, and device params.
- **Special path:** For `zeeshanjaved` / `123456`, request uses `check_login_for_google_test=1`.
- **Responses:** `success` → save user + navigate Home; `contact` → verification popup; `showDialog` → new device dialog (Yes → `update_device=1`); `false` → show server `data` as error.
- **Credential cache:** Username/password stored only when that username is not already in local cache (insert-only parity).

### Change base URL

Edit `lib/services/api_service.dart`:

- Login/device endpoint: `loginApiUrl` (default `https://www.hisaab.org/tclorder_apis/new.php`).

### Firebase Messaging (optional)

To use FCM token in login (e.g. for push):

1. Add `firebase_core` and `firebase_messaging` to `pubspec.yaml`.
2. Follow [FlutterFire setup](https://firebase.flutter.dev/docs/overview).
3. Get the token and pass it into `ApiService.login(..., fcmToken: token)`.

Without Firebase, `tokenid` is sent as an empty string.
