# Internal deployment runbook

The internal test system (owner decisions 2026-10-23). Not for customers yet.

| Part | Where |
|---|---|
| Web app | Firebase Hosting, project `liqo-12a80`: https://liqo-12a80.web.app |
| API | This PC, `LIQo backend`, port 3100, `DB_DRIVER=firestore` |
| Way in to the API | Cloudflare **quick tunnel** (`https://<random words>.trycloudflare.com`), until the owner provides a domain |
| Database | Firestore (Native, Standard, `asia-southeast1`), Spark plan |
| Files | This PC: `LIQo backend/uploads/backdrops` (plans, drawings), `LIQo backend/data/maps` (map drafts and published versions) |
| Key | `FIREBASE_KEY_FILE` in `LIQo backend/.env` points to the service-account key outside the repository. Never copy it into the LIQo folder. |

The local development setup (SQL Server, `npm run dev` on 3000, `flutter run` on 5173) is separate and keeps running beside it.

## Start

In `LIQo backend`:

```
npm run serve:internal
```

It starts the API on Firestore, opens the tunnel, checks the API answers through it, and, when the tunnel's address is new, rebuilds the web app with that address and deploys it to Hosting (a few minutes). It ends with "LIQo is live at https://liqo-12a80.web.app". **Keep that window open.** Ctrl+C stops the API and the tunnel.

- The tunnel's address changes every time it starts, so every start redeploys the web app. During those minutes the web app cannot reach the API.
- Only one internal API may run (it refuses to start when port 3100 is taken). Two API processes on one Firestore database break map saving and AI credits (Blueprint trap 14).
- If the API or the tunnel stops, the script stops both. Start it again.
- The PC must stay on and awake. Turn off sleep while the system is in use.

## After changing code

- Server code: stop (Ctrl+C) and `npm run serve:internal` again.
- Web code: `npm run deploy:internal` (rebuilds and redeploys against the current address).
- Firestore rules or indexes (`firestore.rules`, `firestore.indexes.json` at the root): `npm run deploy:internal -- --rules`.

## First superadmin

Created once with `npm run seed:internal`: `admin@liqo.local` / `Admin@123`, which must be changed at the first sign-in (owner decision 2026-10-23). Sign in and change it straight away. Running the seed again changes nothing.

## Back-ups

Firestore holds the records; this PC holds the files. Back up `LIQo backend/uploads` and `LIQo backend/data` together, for example to a drive or a shared folder, after a day of use. Losing them loses plans and maps even though Firestore keeps the rest.

## Limits

- Spark: about 50,000 reads and 20,000 writes a day, 1 GB stored. See the Firebase console's Usage page. Lists and charts read whole collections; fine for a test with a few malls.
- DWG plans need ODA File Converter on this PC (`ODA_FILE_CONVERTER` in `.env`); without it they are refused clearly (`EXCEPTIONS.md` #4).
- AI floor-plan reading spends real IQGateway credits, as locally.
- Quick tunnels have no uptime promise from Cloudflare.

## Later: a fixed address

Phones (the shopper service, P1-07/P1-08) need an address that never changes. When the owner has a domain on a free Cloudflare account: `cloudflared tunnel login`, `cloudflared tunnel create liqo`, `cloudflared tunnel route dns liqo api.<domain>`, a `config.yml` sending it to `http://localhost:3100`, and `serve:internal` runs that tunnel instead of the quick one. The web app is then deployed once with `https://api.<domain>`.

## Going back

Nothing here changes the local system. To stop the internal test, stop `serve:internal`; the web app stays up but cannot reach the API. To remove it, disable Hosting in the Firebase console.
