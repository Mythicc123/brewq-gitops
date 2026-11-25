# 03 · Startup crash

## Goal

Observe a bad rollout while the previous release continues to serve.

## Before you start

Follow the [baseline checklist](README.md#before-any-drill). Check that at least two pods are Ready and that their current rollout has completed.

## Steps

Start the pod watch in a second terminal.

```bash
kubectl --context kind-brewq -n brewq get pods -l app.kubernetes.io/name=brewq --watch
```

From the GitOps checkout, review the diff and confirm the push.

```bash
make drill-03
make status
make alerts
```

`chaos.crashOnStart: "true"` makes each new pod exit during startup.

## What you should see

- **Alert** — `BrewqPodCrashLooping` (page) is expected after three restarts within 10 minutes or two continuous minutes in CrashLoopBackOff. Backoff, scheduling and metric evaluation affect the clock time.
- **Kubernetes** — Expect a new pod to restart and enter CrashLoopBackOff. The old ReplicaSet should keep its Ready pods because the rollout allows zero unavailable replicas. The menu should still return 200.
- **Argo CD** — Argo CD should show the bad revision as Synced and the Deployment as Progressing, then Degraded if it reaches the progress deadline.
- **Grafana** — In `brewq-overview`, watch restarts and Ready pod count. In `brewq-slo`, check whether availability stayed within budget.

```bash
kubectl --context kind-brewq -n brewq get replicasets
kubectl --context kind-brewq -n brewq get pods -o wide
# Enter the restarting pod name shown above.
printf 'Restarting pod: '
read -r pod
kubectl --context kind-brewq -n brewq logs "$pod" -c brewq --previous
curl -fsS http://brewq.localtest.me/menu
```

## Roll back

On current `main`, run `make rollback`. To run the Git rollback by hand, use these commands in place of the helper.

```bash
git pull --ff-only origin main
git revert --no-edit "$(git log -1 --format=%H --grep='^drill: 03-crashloop$' -- envs/local/brewq-values.yaml)"
git push origin HEAD:main
```

## Postmortem

Record the failed container exit, restarts, alert delay, number of old Ready pods, and any budget spent. Use the [incident template](../incidents/TEMPLATE.md) and Sydney time.

## Cleanup

In Argo CD, wait for the revert revision to sync. Confirm the Deployment has rolled out and check the alert state. The failing ReplicaSet should scale back to zero. Stop the pod watch with Ctrl-C.

```bash
kubectl --context kind-brewq -n brewq rollout status deployment/brewq --timeout=5m
make status
make alerts
```
