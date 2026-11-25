SHELL := /bin/bash

ARGO_CHART_VERSION := 10.19.1
ARGO_CHART := argo-cd --repo https://argoproj.github.io/argo-helm --version $(ARGO_CHART_VERSION)
ARGO_VALUES := bootstrap/argocd-values.yaml
KUBE_CONTEXT ?= kind-brewq
KUBECTL := kubectl --context $(KUBE_CONTEXT)
SCHEMA_CATALOG := https://raw.githubusercontent.com/datreeio/CRDs-catalog/04af58d740718c4dc719441bf39fb284c784f4a8

.PHONY: help bootstrap password urls status alerts drill-01 drill-02 drill-03 drill-04 rollback lint uninstall

help:
	@printf '%s\n' \
	  'make bootstrap  Install Argo CD and apply the root Application after brewq-k8s make up' \
	  'make password   Print the initial Argo CD admin password' \
	  'make urls       List local routes' \
	  'make status     Show Application sync and health' \
	  'make alerts     Show firing Prometheus alerts' \
	  'make drill-01   Inject 30% errors' \
	  'make drill-02   Inject 400 ms latency' \
	  'make drill-03   Crash new pods on startup' \
	  'make drill-04   Inject a 40 MB/min memory leak' \
	  'make rollback   Revert and push the latest drill commit' \
	  'make lint       Parse YAML, validate manifests and render Argo CD' \
	  'make uninstall  Remove GitOps Applications and Argo CD'

bootstrap:
	@$(KUBECTL) -n traefik get gateway edge >/dev/null || { \
	  printf '%s\n' 'Cannot read Gateway traefik/edge. Run make up in brewq-k8s and check KUBECONFIG and KUBE_CONTEXT.' >&2; \
	  exit 1; \
	}
	helm upgrade --install argocd $(ARGO_CHART) --kube-context $(KUBE_CONTEXT) \
	  --namespace argocd --create-namespace --values $(ARGO_VALUES) --wait --timeout 5m
	$(KUBECTL) wait --for=condition=Established --timeout=60s crd/applications.argoproj.io
	@set -eu; set -o pipefail; \
	  $(KUBECTL) create namespace monitoring --dry-run=client -o yaml | $(KUBECTL) apply -f -; \
	  existing="$$( $(KUBECTL) -n monitoring get secret grafana-admin --ignore-not-found -o name )"; \
	  if [[ -z "$$existing" ]]; then \
	    password="$$(openssl rand -hex 24)"; \
	    printf '%s' "$$password" | $(KUBECTL) -n monitoring create secret generic grafana-admin \
	      --from-literal=admin-user=admin --from-file=admin-password=/dev/stdin; \
	  fi
	$(KUBECTL) apply -f bootstrap/root.yaml

password:
	@$(KUBECTL) -n argocd get secret argocd-initial-admin-secret \
	  -o 'go-template={{.data.password | base64decode}}{{"\n"}}'

urls:
	@printf '%s\n' http://argocd.localtest.me http://brewq.localtest.me \
	  http://grafana.localtest.me http://prometheus.localtest.me http://alertmanager.localtest.me

status:
	@$(KUBECTL) -n argocd get applications.argoproj.io \
	  -o 'custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'

alerts:
	@set -o pipefail; curl -fsS http://prometheus.localtest.me/api/v1/alerts | \
	  jq -e 'select(.status == "success") | [.data.alerts[] | select(.state == "firing")]'

drill-01:
	@./scripts/drill.sh 01-bad-release

drill-02:
	@./scripts/drill.sh 02-slow-release

drill-03:
	@./scripts/drill.sh 03-crashloop

drill-04:
	@./scripts/drill.sh 04-memory-leak

rollback:
	@./scripts/drill.sh rollback

lint:
	@find . \( -name .cache -o -name .git \) -prune -o -type f \( -name '*.yaml' -o -name '*.yml' \) \
	  -exec yq eval '.' {} + >/dev/null
	@for drill in 01-bad-release 02-slow-release 03-crashloop 04-memory-leak 05-node-drain 06-drift; do \
	  if [[ ! -s "drills/$$drill.md" ]]; then printf 'Missing runbook: drills/%s.md\n' "$$drill" >&2; exit 1; fi; \
	done
	kubeconform -strict -summary \
	  -schema-location '$(SCHEMA_CATALOG)/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
	  apps/ bootstrap/root.yaml
	helm template argocd $(ARGO_CHART) --namespace argocd --values $(ARGO_VALUES) \
	  --api-versions gateway.networking.k8s.io/v1 >/dev/null
	bash -n scripts/drill.sh
	@if command -v shellcheck >/dev/null; then shellcheck scripts/drill.sh; fi
	actionlint

uninstall:
	@set -eu; \
	  crd="$$( $(KUBECTL) get crd applications.argoproj.io --ignore-not-found -o name )"; \
	  if [[ -n "$$crd" ]]; then \
	    for app in root brewq-monitoring brewq kube-prometheus-stack; do \
	      $(KUBECTL) -n argocd delete application "$$app" --ignore-not-found --wait --timeout=5m; \
	    done; \
	  fi
	helm uninstall argocd --namespace argocd --kube-context $(KUBE_CONTEXT) --ignore-not-found --wait --timeout 5m
