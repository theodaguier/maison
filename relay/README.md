# Maison relay

The only part of Maison that runs outside the household. It stores nothing: it holds credentials that can't ship in the app and forwards requests. Its only state is the operator's access token, in memory.

Today it reads electricity from the grid operator. Push notifications, planned in the roadmap, will live here too. The app finds the relay through the build setting `MAISON_RELAY_URL` (an `https` address). While it is empty, the app offers no grid operator and falls back to a meter reader or the bill.

Go, standard library only: one static binary, no dependency to keep up to date.

## Grid operator data

The app knows one source, "the grid operator", and a table of operators by country (`GridOperator.byCountry` in the app). Each supported operator is a path prefix on the relay. Only Enedis (France) is supported so far.

### Enedis Data Connect

Prerequisite: Maison is registered as a Data Connect partner with Enedis, which gives a client id and secret, and `https://<relay>/enedis/callback` is declared as the redirect address. Only the relay knows the credentials.

| Route | What it does |
|---|---|
| `GET /enedis/authorize?state=…` | Redirects to Enedis's consent page with the client id, `response_type=code`, the consent duration (one year) and the `state` unchanged. |
| `GET /enedis/callback?state=…&usage_point_id=…` | Enedis's redirect after the consent. Redirects to `maison://grid/enedis?usage_point_id=…&access=…&state=…`. A refusal comes back as `error=…`. The authorization code is not passed on: data access uses Maison's own client-credentials token. |
| `GET /enedis/consumption_load_curve?usage_point_id=…&start=…&end=…` | Calls `/metering_data_clc/v5/consumption_load_curve` and returns Enedis's status and JSON unchanged. Days are `YYYY-MM-DD`, French time. When the household never turned the load curve on, Enedis's 403 or 404 reaches the app, which then asks for daily totals. |
| `GET /enedis/daily_consumption?usage_point_id=…&start=…&end=…` | Same with `/metering_data_dc/v5/daily_consumption`. |
| `GET /healthz` | `204` when the process runs. |

**The access key.** A meter id (PRM) is printed on every bill. So the data routes don't take it alone: they require `Authorization: Bearer <access>`, where `access` is HMAC-SHA256(`RELAY_SIGNING_KEY`, `"enedis:" + PRM`), handed to the app only in the callback, after the person approved Maison on Enedis's page. Nothing is stored: the relay recomputes the key on each request. Changing `RELAY_SIGNING_KEY` unlinks every home; each person then links their account again from the Energy fiche.

Requests are logged with their route, status and duration, never their query: it carries meter ids.

### What the app does with it

Each refresh, as an administrator, the app asks for the days not imported yet (a month back the first time) and writes them into Home Assistant's long-term statistics as `maison:grid_consumption` (`recorder/import_statistics`). Home Assistant stays the memory; the Energy score reads that statistic like any meter, and scores the previous day, whole.

### Other countries

Known and waiting for a connector, with the same routes under their own prefix: Datadis (Spain), Eloverblik (Denmark), Elhub (Norway), Fingrid Datahub (Finland), Estfeed (Estonia), EDSN (Netherlands), EDA (Austria), Portale Consumi (Italy), the DCC (Great Britain), the Consumer Data Right (Australia). Each needs its own registration with the operator first.

## Run it

| Variable | |
|---|---|
| `RELAY_SIGNING_KEY` | Required, 32 characters or more: `openssl rand -base64 48`. |
| `ENEDIS_CLIENT_ID`, `ENEDIS_CLIENT_SECRET` | Required, from Enedis's partner space. |
| `ENEDIS_API_URL` | `https://ext.prod.api.enedis.fr` by default; `https://ext.prod-sandbox.api.enedis.fr` while testing. |
| `ENEDIS_AUTHORIZE_URL` | Enedis's consent page, production by default. |
| `ENEDIS_CONSENT_DURATION` | `P1Y` by default. |
| `APP_CALLBACK` | `maison://grid` by default. |
| `PORT` | `8080` by default. |

The relay refuses to start when a required variable is missing or an Enedis address isn't `https`.

```sh
go test -race ./...
RELAY_SIGNING_KEY=… ENEDIS_CLIENT_ID=… ENEDIS_CLIENT_SECRET=… go run .
```

### On Dokploy

1. New Compose application from this repository, compose path `relay/compose.yaml`.
2. Set the variables of `.env.example` in its environment.
3. Give it a public domain on port 8080, with HTTPS (Traefik). It has to be public: Enedis redirects the person's browser to it, and the app calls it away from home.
4. Declare `https://<that domain>/enedis/callback` as the redirect address in Enedis's partner space.
5. Build the app with `MAISON_RELAY_URL = https:/$()/<that domain>` in `Config/Secrets.xcconfig` (in an xcconfig, `//` starts a comment), or pass it to `xcodebuild`.

The image is a static binary on distroless (`nonroot`), read-only, limited to 64 MB of memory.

## To check against Enedis's documentation

These come from the public Data Connect material, not from a partner account yet: the consent page's address and parameters, the data paths (`/metering_data_clc/v5/…`, `/metering_data_dc/v5/…`), the token route (`/oauth2/v3/token`, client credentials), and the status Enedis returns when the load curve isn't collected.
