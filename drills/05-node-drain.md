# 05 · Node drain

## Goal

Evict workloads from one worker and observe how the Brewq PDB and replica
placement protect the request path.

## Before you start

Follow the [baseline checklist](README.md#before-any-drill). Check that two
Brewq pods are Ready, the PDB allows a disruption and the other nodes are
Ready. Run the drain in a Bash terminal and keep it open for cleanup.

## Steps

Watch pods across namespaces from a second terminal.

```bash
kubectl --context kind-brewq get pods -A -o wide --watch
```

Select a worker currently hosting a Brewq pod. If the check finds no worker,
stop and check pod placement before continuing.

```bash
kubectl --context kind-brewq get nodes
kubectl --context kind-brewq -n brewq get pdb
worker=$(kubectl --context kind-brewq -n brewq get pods -l app.kubernetes.io/name=brewq \
  -o 'jsonpath={range .items[*]}{.spec.nodeName}{"\n"}{end}' | awk '/^brewq-worker/ && !seen++')
test -n "$worker" && kubectl --context kind-brewq drain "$worker" \
  --ignore-daemonsets --delete-emptydir-data --timeout=5m
```

## What you should see

- **Alert** — No SLO burn alert is expected. `BrewqTargetDown` requires no successful Brewq scrape target for two minutes. Check the remaining target and record any scrape or monitoring gaps.
- **Kubernetes** — The PDB keeps at least one Brewq pod available through voluntary evictions. Look for replacements on schedulable nodes. The drain can pause while availability is restored. Singleton observability pods on the worker can briefly restart.
- **Argo CD** — The Git revision remains Synced. Deployment health can fluctuate while pods reschedule.
- **Grafana** — In `brewq-overview`, watch Ready pods, traffic, errors and restarts. In `brewq-slo`, check burn and budget through the drain.

```bash
curl -fsS http://brewq.localtest.me/menu
make status
make alerts
```

## Roll back

This drill changes node scheduling state through Kubernetes. Git has no
drill commit to revert. Restore scheduling even if the drain times out.

```bash
test -n "$worker" && kubectl --context kind-brewq uncordon "$worker"
```

## Postmortem

Record which pods moved, how long the eviction took, the minimum number of
Ready Brewq pods, any monitoring gap and the measured impact on each SLO.
Use the [incident template](../incidents/TEMPLATE.md) and Sydney time.

## Cleanup

Confirm all nodes are schedulable and the app is Ready. Stop the pod watch
with Ctrl-C.

```bash
kubectl --context kind-brewq get nodes
kubectl --context kind-brewq -n brewq rollout status deployment/brewq --timeout=5m
make status
make alerts
```
