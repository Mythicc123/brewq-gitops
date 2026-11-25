# 02 · Slow release

## Goal

See the latency SLO burn when healthy pods take longer than 300 ms to answer.

## Before you start

Follow the [baseline checklist](README.md#before-any-drill). Let 5 requests per second build six hours of healthy traffic to reproduce the expected timing below.

## Steps

Start the pod watch in a second terminal.

```bash
kubectl --context kind-brewq -n brewq get pods -l app.kubernetes.io/name=brewq --watch
```

From the GitOps checkout, review the diff and confirm the push.

```bash
make drill-02
make status
make alerts
```

`chaos.latencyMs: "400"` adds a 400 ms delay to menu and order requests.

## What you should see

- **Alert** — With a full hour of healthy history, the 1h window crosses after about 8.6 minutes of full exposure, assuming almost every eligible request exceeds 300 ms. `BrewqLatencyBurnFast` (page) then holds for two minutes before firing, plus scrape and evaluation delay. With less than six hours of history, the 6h/30m pair can cross earlier.
- **Kubernetes** — The rollout should complete with Ready pods. Menu requests should still return 200 and take about 400 ms or more with the extra delay.
- **Argo CD** — Argo CD should show the new revision as Synced and Healthy after rollout. Readiness and liveness use separate endpoints.
- **Grafana** — In `brewq-overview`, watch p50, p90 and p99 move up. In `brewq-slo`, watch 5m and 1h latency burn and the latency budget.

**Measured on a fresh kind cluster, 25 Nov 2026** (AEDT) — applied 17:50:13, first latency rise observed at 17:51:17 from the evaluation that made the alert pending at 17:51:16, firing 17:53:49, rollback 17:53:50, application recovered 17:53:58. The 5m latency error ratio returned to zero at 17:58:47 while longer windows continued to fire. `/menu` returned 200 in about 405 ms during injection. The first rollback smoke returned 502 while Traefik still had an old endpoint. The chart now gives endpoint updates time to propagate before a pod shuts down.

```bash
curl -sS -o /dev/null -w 'HTTP %{http_code}, %{time_total}s\n' http://brewq.localtest.me/menu
```

## Roll back

On current `main`, run `make rollback`. To run the Git rollback by hand, use these commands in place of the helper.

```bash
git pull --ff-only origin main
git revert --no-edit "$(git log -1 --format=%H --grep='^drill: 02-slow-release$' -- envs/local/brewq-values.yaml)"
git push origin HEAD:main
```

## Postmortem

Record the revision, the fraction above 300 ms, alert delay, and latency budget spent. Use the [incident template](../incidents/TEMPLATE.md) and Sydney time.

## Cleanup

In Argo CD, wait for the revert revision to sync. Confirm the Deployment has rolled out and check the alert state. Some burn windows retain the failure after healthy traffic resumes. Stop the pod watch with Ctrl-C.

```bash
kubectl --context kind-brewq -n brewq rollout status deployment/brewq --timeout=5m
make status
make alerts
```
