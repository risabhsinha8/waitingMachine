# Losertown

A mobile-first Flutter app for projecting weight loss and holding yourself to
it. Tune calories and activity in the **Simulator**, lock in predictions, log
weigh-ins, and watch **The Arena** rank which timeline reality is actually
tracking.

- Mifflin-St Jeor BMR/TDEE, recalculated weekly as weight changes (7,700 kcal/kg)
- 7-day EMA trend weight and 14-day pace, with implied daily intake
- Up to 4 predictions compete in the Arena at once; the rest are archived with
  full history
- kg/lbs, light/dark, checkpoints, demo data

All data stays on the device: `shared_preferences` (browser `localStorage` on
the web). Nothing is sent anywhere.

## Run locally

```bash
flutter pub get
flutter run -d chrome --web-port=8080   # a fixed port keeps saved data between runs
flutter test
```

Built and tested on Flutter 3.32.6. `fl_chart` is capped below 1.1 until
Flutter is upgraded (see `pubspec.yaml`).

## Deploy to GitHub Pages

`.github/workflows/deploy-pages.yml` analyzes, tests, builds, and publishes
the web app on every push to `main` (or on demand from the Actions tab).

1. Create a GitHub repository and push this project's `main` branch to it.
2. In the repository, open **Settings → Pages** and set **Source** to
   **GitHub Actions**.
3. The next push (or **Actions → Deploy to GitHub Pages → Run workflow**)
   publishes to `https://<user>.github.io/<repo>/`.

The base path is worked out from the repository name: `/<repo>/` for a project
site, `/` for a `<user>.github.io` repository. For a custom domain, set a
repository variable `BASE_HREF` to `/` (**Settings → Secrets and variables →
Actions → Variables**).

To check a production build locally under the same sub-path:

```bash
flutter build web --release --base-href /loserTown/ --pwa-strategy=none
mkdir -p /tmp/pages && ln -sfn "$PWD/build/web" /tmp/pages/loserTown
python3 -m http.server 8000 --directory /tmp/pages   # open http://localhost:8000/loserTown/
```
