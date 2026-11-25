# 02 · Slow release

## Goal

See the latency SLO burn when healthy pods take longer than 300 ms to answer.

## Before you start

Follow the [baseline checklist](README.md#before-any-drill). Let 5 requests per second build an hour of healthy traffic for the expected timing below.

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

- **Alert** — `BrewqLatencyBurnFast` (page) is expected about 8.6 minutes after the new pods carry full traffic, plus the scrape and evaluation delay. The estimate assumes almost every eligible request exceeds 300 ms.
- **Kubernetes** — The rollout should complete with Ready pods. Menu requests should still return 200 and take about 400 ms or more with the extra delay.
- **Argo CD** — Argo CD should show the new revision as Synced and Healthy after rollout. Readiness and liveness use separate endpoints.
- **Grafana** — In `brewq-overview`, watch p50, p90 and p99 move up. In `brewq-slo`, watch 5m and 1h latency burn and the latency budget.

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
