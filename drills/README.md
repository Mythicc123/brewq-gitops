# Failure drills

Run one drill at a time on the local kind cluster. Keep the healthy 5 rps
traffic generator running throughout. Start with drill 01 for the first incident.

| Drill | What breaks | Expected alert | Expected time to fire | What to watch |
| --- | --- | --- | --- | --- |
| [01 · Bad release](01-bad-release.md) | 30% injected HTTP 500s | `BrewqAvailabilityBurnFast` | About 16½ min at full injection, including the hold | 5xx ratio and availability burn |
| [02 · Slow release](02-slow-release.md) | 400 ms added latency | `BrewqLatencyBurnFast` | About 10.6 min at full injection, including the hold | Latency percentiles and latency burn |
| [03 · Startup crash](03-crashloop.md) | New pods exit at startup | `BrewqPodCrashLooping` | A 2 min hold once the restart or CrashLoopBackOff condition is met, plus metrics delay | Old Ready pods, new pod restarts, Argo health |
| [04 · Memory leak](04-memory-leak.md) | New pods retain 40 MB/min | `BrewqPodOOMKilled` | About 2–4 min to the first OOM from container start, then a 1 min hold plus metrics delay | Memory limit, last termination reason, restarts |
| [05 · Node drain](05-node-drain.md) | A worker stops taking workloads | No SLO alert expected | No firing expected | PDB, evictions, rescheduling and target continuity |
| [06 · Drift](06-drift.md) | Live `CHAOS_LATENCY_MS` changes to 200 | No alert expected | No firing expected | Deployment environment and Argo self-heal at the same Git revision, with the HPA enabled |

## Before any drill

- Use the local `kind-brewq` cluster. Run `make bootstrap` and check that
  `make status` shows all apps Synced and Healthy. Confirm `make alerts`
  reports no firing Brewq alerts.
- Verify the route and the traffic generator. The previous drill's burn
  windows may still contain errors, so check the baseline in Grafana.

```bash
curl -fsS http://brewq.localtest.me/menu
kubectl --context kind-brewq -n monitoring rollout status deployment/brewq-traffic --timeout=2m
make status
make alerts
```

- Open [Argo CD](http://argocd.localtest.me), [Alertmanager](http://alertmanager.localtest.me),
  [brewq-overview](http://grafana.localtest.me/d/brewq-overview) and
  [brewq-slo](http://grafana.localtest.me/d/brewq-slo).
- For Git changes, start with a clean local `main` matching `origin/main`.
  Keep the deployment target local while the drill changes the shared branch.

## Burn rate and expected timing

With steady 5 requests per second and a full hour of healthy history, an
hour contains about 18,000 eligible requests. Burn rate is the bad-request
fraction divided by the SLO budget fraction.

| Fast alert | 1h and 5m threshold | Expected crossing of the 1h window |
| --- | --- | --- |
| Availability | 14.4 × 0.005 = 7.2% bad | 1,296 bad requests ÷ (5 × 0.30) = 864 s, or 14.4 min |
| Latency | 14.4 × 0.01 = 14.4% bad | 2,592 bad requests ÷ (5 × 1.0) = 518.4 s, or 8.64 min |

The 5m window crosses first in both drills. With six hours of healthy
history, the other fast branch applies a 6× threshold to the 6h and 30m
windows. Its longer window crosses at about 36 min for availability
and 21.6 min for latency. The 1h branch drives the earlier expectation.
The rules use a strict greater-than comparison and hold the condition for
two minutes before firing. A fresh cluster has fewer healthy requests in
the long windows, so the thresholds can be crossed much sooner.

These are expected times from full exposure. Rollout overlap, random errors,
changing pod series, partial traffic history, the 15-second scrape interval
and the rule evaluation interval can shift when an alert first fires.
The dated measurements in drills 01–04 used the manual Helm path.
Application recovery means the rollback rollout completed and the smoke
test passed. The alert can clear later as the affected traffic ages out.
Record actual timings during each drill.

The dated measurements in drills 05–06 used the GitOps path on a fresh
kind cluster. No Brewq SLO alert fired during either drill. The
14.26-second drain had zero failures across 14 public `/menu` probes.
Argo CD reverted the live latency setting in 0.80 seconds.
