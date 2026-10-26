# Maison relay

The only part of Maison meant to run outside the household. The push relay planned in the roadmap will live here: it stores nothing. For now it only answers its health check.

Go, standard library only: one static binary, no dependency to keep up to date.

| Route | What it does |
|---|---|
| `GET /healthz` | `204` when the process runs. |

Requests are logged with their route, status and duration, never their query.

## Run it

| Variable | |
|---|---|
| `PORT` | `8080` by default. |

```sh
go test -race ./...
go run .
```

### On Dokploy

1. New Compose application from this repository, compose path `relay/compose.yaml`.
2. Give it a domain on port 8080, with HTTPS (Traefik).

The image is a static binary on distroless (`nonroot`), read-only, limited to 64 MB of memory.
