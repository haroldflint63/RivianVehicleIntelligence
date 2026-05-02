# Hosting — Render (backend) + Vercel (Flutter web)

The Rivian backend is a Python WebSocket server (long-lived); Vercel
serverless functions can't host it. The Flutter web build is plain
static assets and is perfect for Vercel.

```
[ Vercel: Flutter web ]  ─── wss:// ──▶  [ Render: Python WS server ]
      (static)                                (web service)
```

---

## 1 · Backend → Render

1. Push this repo to GitHub.
2. Go to https://dashboard.render.com → **New +** → **Blueprint**.
3. Pick your repo. Render reads `render.yaml` and proposes
   `rivian-vehicle-intelligence-backend` as a Web Service (free plan,
   Oregon region, Python 3.11).
4. Click **Apply**.
5. After the first deploy, open the service → **Environment** and set:
   - `GROQ_API_KEY` = `gsk_…` (your Groq key)
6. Trigger a redeploy. Your URL will be:
   `https://rivian-vehicle-intelligence-backend.onrender.com`
7. Test:
   ```bash
   curl https://rivian-vehicle-intelligence-backend.onrender.com/
   # {"status":"ok","service":"rivian-vehicle-intelligence","version":"3.0"}
   ```
   The same host accepts WebSocket connections at `wss://…onrender.com`.

> **Free-plan note:** the service sleeps after 15 min of inactivity and
> takes ~30 s to wake. For an always-on instance, upgrade to Starter.

---

## 2 · Flutter web → Vercel

1. Same repo. Go to https://vercel.com/new → import the repo.
2. Framework preset: **Other** (Vercel will use `vercel.json`).
3. **Environment Variables** → add:
   - `WS_URL` = `wss://rivian-vehicle-intelligence-backend.onrender.com`
4. Deploy. The build:
   - Downloads the Flutter SDK (~3 min on the first build, cached after).
   - Runs `flutter build web --release --dart-define=WS_URL=$WS_URL`.
   - Serves `flutter_app/build/web/`.

Local preview of the exact same build:

```bash
WS_URL=wss://rivian-vehicle-intelligence-backend.onrender.com bash build.sh
cd flutter_app/build/web && python3 -m http.server 8080
open http://localhost:8080
```

---

## 3 · Configure-at-build summary

| Variable | Where | Example |
|---|---|---|
| `GROQ_API_KEY` | Render env | `gsk_…` |
| `PORT` | Render (auto) | `10000` |
| `WS_URL` | Vercel env | `wss://….onrender.com` |
| `FLUTTER_VERSION` | Vercel env (optional) | `3.24.5` |

The Flutter app reads `WS_URL` at build time via
`String.fromEnvironment('WS_URL')` in
[flutter_app/lib/main.dart](flutter_app/lib/main.dart). Without
`--dart-define`, it falls back to `ws://localhost:8765`.
