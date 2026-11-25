# 01 · Bad release

## Goal

See the availability SLO burn when a release injects HTTP 500 responses.

## Before you start

Follow the [baseline checklist](README.md#before-any-drill). Let 5 requests per second build an hour of healthy traffic for the expected timing below.

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

- **Alert** — `BrewqAvailabilityBurnFast` (page) is expected about 14.4 minutes after the new pods carry full traffic, plus the scrape and evaluation delay. During rollout the aggregate error fraction ramps up.
- **Kubernetes** — Kubernetes should show Ready pods and a completed rollout. A sample of menu requests should contain both 200 and 500 responses.
- **Argo CD** — Argo CD should show the new revision as Synced and Healthy after rollout. The probes stay healthy while eligible requests fail.
- **Grafana** — In `brewq-overview`, watch the 5xx ratio. In `brewq-slo`, check the 5m and 1h availability burn and budget remaining.

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
