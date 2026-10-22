# Maison relay

The only part of Maison that runs outside the household. It stores nothing: it holds credentials that can't ship in the app and forwards requests.

Today it has one job planned in the roadmap (push notifications) and one the app already calls: reading electricity from the grid operator. The app finds the relay through the build setting `MAISON_RELAY_URL` (an `https` address). While it is empty, the app offers no grid operator and falls back to a meter reader or the bill.

## Grid operator data

The app knows one source, "the grid operator", and a table of operators by country (`GridOperator.byCountry`). Each supported operator is a path prefix on the relay. Only Enedis (France) is supported so far.

### Enedis Data Connect

Prerequisite: Maison is registered as a Data Connect partner with Enedis, which gives a client id and secret, and the relay's callback is declared as the redirect URI. Only the relay knows them.

| Route | What it does |
|---|---|
| `GET /enedis/authorize?state=…` | Redirects to Enedis's consent page (`mon-compte-particulier.enedis.fr/dataconnect/v1/oauth2/authorize`) with the client id, `response_type=code`, a duration of one year, and the `state` unchanged. |
| `GET /enedis/callback?code=…&state=…&usage_point_id=…` | Redirects to `maison://grid/enedis?usage_point_id=…&state=…`. The app checks the state and keeps the meter id (PRM). |
| `GET /enedis/consumption_load_curve?usage_point_id=…&start=…&end=…` | Gets a client-credentials token, calls `/metering_data_clc/v5/consumption_load_curve`, and returns Enedis's JSON as is. Dates are `YYYY-MM-DD`, French time. Enedis's 403 or 404 when the household never turned the load curve on is passed through unchanged: the app then asks for the daily total. |
| `GET /enedis/daily_consumption?usage_point_id=…&start=…&end=…` | Same with `/metering_data_dc/v5/daily_consumption`. |

The relay keeps no meter id, token or reading. Enedis checks at random that partners hold the consent they claim: the consent is the person's approval on Enedis's own page, before the callback.

### What the app does with it

Each refresh, as an administrator, the app asks for the days not imported yet (a month back the first time) and writes them into Home Assistant's long-term statistics as `maison:grid_consumption` (`recorder/import_statistics`). Home Assistant stays the memory; the Energy score reads that statistic like any meter, and scores the previous day, whole.

### Other countries

Known and waiting for a connector, with the same three routes under their own prefix: Datadis (Spain), Eloverblik (Denmark), Elhub (Norway), Fingrid Datahub (Finland), Estfeed (Estonia), EDSN (Netherlands), EDA (Austria), Portale Consumi (Italy), the DCC (Great Britain), the Consumer Data Right (Australia). Each needs its own registration with the operator first.
