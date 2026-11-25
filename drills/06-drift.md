# 06 · Deployment drift

## Goal

Change the live Deployment's latency setting and watch Argo CD restore the
value declared in Git while the HPA continues to manage replicas.

## Before you start

Follow the [baseline checklist](README.md#before-any-drill). Confirm that the
Brewq Application is Synced and Healthy, automated self-heal is enabled,
and Git declares `chaos.latencyMs: "0"`. Record the synced Git revision.

## Steps

Start this watch in a second terminal before applying the live change.

```bash
kubectl --context kind-brewq -n brewq get deployment/brewq --watch \
  --output-watch-events -o json |
  jq --unbuffered -r '.object.spec.template.spec.containers[]? |
    select(.name == "brewq") | .env[] | select(.name == "CHAOS_LATENCY_MS") | .value'
```

Change the live environment variable.

```bash
kubectl --context kind-brewq -n brewq set env deployment/brewq CHAOS_LATENCY_MS=200
make status
make alerts
```

## What you should see

- **Kubernetes** — The watch shows the value move from 0 to 200 and back to 0.
  Each pod template change can start a rollout.
- **Argo CD** — The Application can briefly show OutOfSync or a self-heal
  operation, then return to Synced at the same Git revision. Argo CD manages
  this environment variable because the chart declares it.
  Repeating the drill on the same revision can increase the recovery time
  because Argo CD backs off between successive self-heal syncs.
- **Grafana** — If a changed pod serves traffic before self-heal, request
  latency can briefly rise. The added 200 ms is below the 300 ms SLO
  threshold on an otherwise healthy service, so no SLO alert is expected.

**Measured on a fresh kind cluster, 25 Nov 2026** (AEDT) — the Deployment
watch showed `200` at 18:42:27.987 and `0` at 18:42:28.786. Argo CD reverted
the drift in 0.80 seconds at the same Git revisions. The HPA stayed enabled,
the rollout succeeded and Watchdog was the only firing alert at recovery.

## Recovery

Wait for self-heal and confirm the watch shows 0 again. The drill requires
no Git changes. Autoscaling stays enabled throughout.

```bash
kubectl --context kind-brewq -n brewq rollout status deployment/brewq --timeout=5m
kubectl --context kind-brewq -n brewq get hpa brewq
make status
make alerts
```

Stop the Deployment watch with Ctrl-C. Use the
[incident template](../incidents/TEMPLATE.md) to record the drift time,
self-heal time, Git revision and any SLO impact in Sydney time.
