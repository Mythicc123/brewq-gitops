# 06 · Replica drift

## Goal

Change live Deployment replicas by hand and watch Argo CD restore the
Git value.

## Before you start

Follow the [baseline checklist](README.md#before-any-drill). Start with
autoscaling enabled and run the commands in Bash from the GitOps checkout.
Keep that terminal open so the preparation commit is available for cleanup.

## Steps

Prepare a fixed desired replica count. The HPA normally controls this field.

```bash
git switch main
git pull --ff-only origin main
yq -i '.autoscaling.enabled = false | .replicaCount = 2' envs/local/brewq-values.yaml
git diff -- envs/local/brewq-values.yaml
git add -- envs/local/brewq-values.yaml
git commit -m 'drill: 06-drift prep'
prep_commit=$(git rev-parse HEAD)
git push origin HEAD:main
```

Wait for this revision to sync in Argo CD. Confirm the Brewq HPA is gone and
the Deployment has two replicas before scaling it.

```bash
kubectl --context kind-brewq -n brewq get hpa
kubectl --context kind-brewq -n brewq rollout status deployment/brewq --timeout=5m
kubectl --context kind-brewq -n brewq get deployment brewq \
  -o 'custom-columns=NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas'
```

Start this watch in a second terminal before applying the live change.

```bash
kubectl --context kind-brewq -n brewq get deployment brewq --watch \
  -o 'custom-columns=NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas'
```

```bash
kubectl --context kind-brewq -n brewq scale deployment/brewq --replicas=3
make status
make alerts
```

## What you should see

- **Alert** — No alert is expected. Requests continue through the replica change.
- **Kubernetes** — The Deployment's desired replicas briefly change to three and return to two. The third pod may never become Ready.
- **Argo CD** — The application can briefly show OutOfSync or a self-heal operation, then return to Synced at the same Git revision. Use the Kubernetes watch if the UI refresh misses the transition.
- **Grafana** — In `brewq-overview`, check pod count and request continuity. In `brewq-slo`, check the burn and budget for both SLOs. A short replica change can fall between scrapes.

## Roll back

Once Git's two replicas are restored by self-heal, revert the preparation
commit to restore normal HPA control.

```bash
git pull --ff-only origin main
git revert --no-edit "$prep_commit"
git push origin HEAD:main
```

## Postmortem

Record the manual scale time, the time desired replicas returned to two,
the Argo revision and operation, the HPA state and any observed SLO impact.
Use the [incident template](../incidents/TEMPLATE.md) and Sydney time.

## Cleanup

In Argo CD, wait for the revert revision to sync. Confirm the HPA is present
and the pods are Ready. Stop the Deployment watch with Ctrl-C.

```bash
kubectl --context kind-brewq -n brewq get hpa
kubectl --context kind-brewq -n brewq rollout status deployment/brewq --timeout=5m
make status
make alerts
```
