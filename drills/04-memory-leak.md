# 04 · Memory leak

## Goal

Follow memory growth through a container restart and verify the OOM alert.

## Before you start

Follow the [baseline checklist](README.md#before-any-drill). Check the 128 MiB memory limit and baseline memory usage in Grafana.

## Steps

Start the pod watch in a second terminal.

```bash
kubectl --context kind-brewq -n brewq get pods -l app.kubernetes.io/name=brewq --watch
```

From the GitOps checkout, review the diff and confirm the push.

```bash
make drill-04
make status
make alerts
```

`chaos.leakMbPerMin: "40"` makes each new pod allocate and retain 40 MB per minute.

## What you should see

- **Alert** — `BrewqPodOOMKilled` (ticket) is expected after the first OOM termination and the next metric evaluations. Roughly 2–4 minutes from a new container start is a planning estimate, based on allocating 40 MB/min against 128 MiB minus baseline memory. Use the observed startup RSS for a better estimate.
- **Kubernetes** — New pods can become Ready before their memory limit is hit. Look for `OOMKilled` in the last termination state and a rising restart count. Watch the request path for errors as pods restart.
- **Argo CD** — Argo CD should sync the values revision. Deployment health can fluctuate as readiness changes across restarts.
- **Grafana** — In `brewq-overview`, watch memory against the limit, then pod restarts and 5xx. In `brewq-slo`, check availability, latency and budget impact.

```bash
kubectl --context kind-brewq -n brewq top pods
kubectl --context kind-brewq -n brewq get pods -l app.kubernetes.io/name=brewq \
  -o 'custom-columns=NAME:.metadata.name,LAST-REASON:.status.containerStatuses[0].lastState.terminated.reason,RESTARTS:.status.containerStatuses[0].restartCount'
curl -fsS http://brewq.localtest.me/menu
```

## Roll back

On current `main`, run `make rollback`. To run the Git rollback by hand, use these commands in place of the helper.

```bash
git pull --ff-only origin main
git revert --no-edit "$(git log -1 --format=%H --grep='^drill: 04-memory-leak$' -- envs/local/brewq-values.yaml)"
git push origin HEAD:main
```

## Postmortem

Record baseline and peak memory, time to the first OOM, last termination reason, restart cadence and budget spent. Use the [incident template](../incidents/TEMPLATE.md) and Sydney time.

## Cleanup

In Argo CD, wait for the revert revision to sync. Confirm the Deployment has rolled out and check the alert state. Some burn windows retain the failure after healthy traffic resumes. Stop the pod watch with Ctrl-C.

```bash
kubectl --context kind-brewq -n brewq rollout status deployment/brewq --timeout=5m
make status
make alerts
```
