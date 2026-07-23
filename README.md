# New Event Cloud Service

A microservices platform for browsing events/programs and registering for them, built for RGU's
CMM707 Cloud Computing coursework. Deploys to Amazon EKS behind a single Ingress endpoint, with
blue-green CI/CD, a shared RDS PostgreSQL database, self-hosted ClickHouse for web analytics and
observability telemetry, and a Prometheus/Grafana + OpenTelemetry observability stack.

## Architecture

```
Browser → Ingress (ingress-nginx) → Frontend / Event / Program / Registration / Analytics Service
                                          ↓                              ↓
                                   RDS PostgreSQL                  ClickHouse (web_events)
```

- **Frontend** — static site (Nginx) + `analytics.js` beaconing page/click/scroll events.
- **Event / Program / Registration Service** — Ballerina microservices, each deployed blue-green,
  sharing one RDS PostgreSQL instance with per-service tables. Registration Service calls Event
  Service synchronously to reserve seats before persisting a registration; when an event's
  remaining seats drop below 10 it fires a notification to the `seat-threshold-notifier` Lambda
  (SES email).
- **Analytics Service** — Ballerina; the only service writing to ClickHouse's `web_events` table.
- **ClickHouse** — self-hosted (StatefulSet + EBS PVC) in its own `data` namespace; also stores
  OTel logs/traces alongside web analytics.
- **Observability** — kube-prometheus-stack (Prometheus + Grafana + Alertmanager), an OpenTelemetry
  Collector, and Fluent Bit, all in their own `observability` namespace. Traces/logs land in
  ClickHouse; metrics are scraped directly by Prometheus via `PodMonitor`.
- **Serverless** — `seat-threshold-notifier` (API Gateway + Lambda + SES) and
  `clickhouse-quicksight-export` (scheduled Lambda rolling ClickHouse data up to S3 for
  Athena/QuickSight).

## Repository layout

```
services/            Ballerina microservices (event, program, registration, analytics)
frontend/             Static site + Nginx config
helm/                 One Helm chart per service, plus clickhouse/ingress/observability charts
lambda/                seat-threshold-notifier, clickhouse-quicksight-export
infra/                 eksctl cluster config, gp3 StorageClass
iam-policies/          Scoped IAM policy documents used to set up this project's AWS access
grafana-dashboards/    Exported Grafana dashboard JSON (backup / re-import)
postman/               API test collection (run via Newman in CI/CD verification)
local/                 docker-compose.yml + SQL init scripts for local development
.github/workflows/     CI/CD — see below
```

## Local development

```bash
cd local
docker compose up --build
```
Brings up all four Ballerina services, the frontend, and Postgres against `local/init.sql` for
schema bootstrap — no AWS account needed for local iteration.

## CI/CD

- **Per-service workflows** (`event-service.yml`, `program-service.yml`, `registration-service.yml`,
  `analytics-service.yml`, `frontend.yml`) — on push to `main`, build and push a Docker image to
  GHCR, then deploy via the shared reusable workflow below. The four Ballerina-backed services also
  open an automated PR bumping their `Ballerina.toml` patch version.
- **`deploy-service.yml`** — reusable blue-green deploy: rolls the new image out to whichever slot
  isn't currently live, waits for it to be Ready, smoke-tests it directly (bypassing the stable
  Service), and only then flips the stable Service's selector to cut traffic over. The previous
  slot is left running as an instant rollback path.
- **`observability.yml`** — on push to `helm/observability/**`, validates all three charts render
  before touching the cluster, then upgrades kube-prometheus-stack, the OTel Collector, and Fluent
  Bit in sequence.
- **`pr-checks.yml`** — on every pull request into `main`: builds (never pushes) each service's
  Docker image and validates the observability Helm charts, with no AWS credentials required.
  Intended as a required status check gating merges to `main`.

Authentication is via GitHub OIDC → an IAM role scoped to this repository's `main` branch — no
long-lived AWS credentials are stored in GitHub.

## Testing

```bash
INGRESS_HOST=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
npx newman run postman/new-event-api.postman_collection.json --env-var "baseUrl=http://$INGRESS_HOST"
```

## License

See [LICENSE](LICENSE).
