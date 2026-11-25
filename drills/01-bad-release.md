# 01 · Bad release

## Goal

See the availability SLO burn when a release injects HTTP 500 responses.

## Before you start

Follow the [baseline checklist](README.md#before-any-drill). Let 5 requests per second build six hours of healthy traffic to reproduce both window pairs in the estimate below.

## Steps

Start the pod watch in a second terminal.

```bash
kubectl --context kind-brewq -n brewq get pods -l app.kubernetes.io/name=brewq --watch
```

From the GitOps checkout, review the diff and confirm the push.

```bash
make drill-01
make status
make alerts
```

`chaos.errorRate: "0.3"` injects 500s on menu and order requests.

## What you should see

- **Alert** — With six hours of healthy history, `BrewqAvailabilityBurnFast` (page) is expected about 16½ minutes after full exposure to 30% errors. The 1h window crosses at about 14.4 minutes and the rule holds for two more minutes. Scrapes and evaluations add a small delay. A fresh cluster has fewer healthy requests in the long windows, so the bad traffic pushes the ratio over threshold sooner.
- **Kubernetes** — Kubernetes should show Ready pods and a completed rollout. A sample of menu requests should contain both 200 and 500 responses.
- **Argo CD** — Argo CD should show the new revision as Synced and Healthy after rollout. The probes stay healthy while eligible requests fail.
- **Grafana** — In `brewq-overview`, watch the 5xx ratio. In `brewq-slo`, check the 5m and 1h availability burn and budget remaining.

**Measured on a fresh kind cluster, 25 Nov 2026** (AEDT) — applied 17:53:58, first nonzero 5xx ratio 17:54:46, pending 17:55:46, firing and rollback 17:57:47, application recovery confirmed by `make smoke` at 17:58:11 after an initial timeout. The 5m error ratio returned to zero at 18:02:47 while longer windows continued to fire. The page fired 3m49s after the change because Prometheus had only about 15 minutes of traffic history at injection, so the 6h/30m pair crossed its 3% threshold with fewer errors.

```bash
for i in {1..20}; do
  curl -sS -o /dev/null -w '%{http_code}\n' http://brewq.localtest.me/menu
done
```

## Roll back

On current `main`, run `make rollback`. To run the Git rollback by hand, use these commands in place of the helper.

```bash
git pull --ff-only origin main
git revert --no-edit "$(git log -1 --format=%H --grep='^drill: 01-bad-release$' -- envs/local/brewq-values.yaml)"
git push origin HEAD:main
```

## Postmortem

Record the revision, the observed 5xx fraction, the time of the first firing alert, and the availability budget spent. Use the [incident template](../incidents/TEMPLATE.md) and Sydney time.

## Cleanup

In Argo CD, wait for the revert revision to sync. Confirm the Deployment has rolled out and check the alert state. Some burn windows retain the failure after healthy traffic resumes. Stop the pod watch with Ctrl-C.

```bash
kubectl --context kind-brewq -n brewq rollout status deployment/brewq --timeout=5m
make status
make alerts
```
