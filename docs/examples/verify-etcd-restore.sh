#!/usr/bin/env bash

set -uo pipefail

KUBE_CLUSTER_NAME="${1:-default}"
CHECK_NAMESPACE="${2:-etcd-restore-check}"
ETCD_MANAGER=/cm/local/apps/cmd/scripts/cm-etcd-manage

pass_count=0
fail_count=0

pass() {
  pass_count=$((pass_count + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  fail_count=$((fail_count + 1))
  printf 'FAIL: %s\n' "$1" >&2
}

if ready_output=$(kubectl get --raw='/readyz' 2>&1); then
  pass "Kubernetes API readyz (${ready_output})"
else
  fail "Kubernetes API readyz: ${ready_output}"
fi

if kubectl wait --for=condition=Ready nodes --all --timeout=180s >/dev/null 2>&1; then
  pass 'all Kubernetes nodes are Ready'
else
  fail 'one or more Kubernetes nodes did not become Ready within 180 seconds'
fi

if [ -x "$ETCD_MANAGER" ]; then
  if "$ETCD_MANAGER" --kube-cluster "$KUBE_CLUSTER_NAME" status; then
    pass "BCM etcd status for cluster ${KUBE_CLUSTER_NAME}"
  else
    fail "BCM etcd status for cluster ${KUBE_CLUSTER_NAME}"
  fi
else
  fail "${ETCD_MANAGER} is not executable"
fi

if kubectl get namespace "$CHECK_NAMESPACE" >/dev/null 2>&1; then
  pass "namespace ${CHECK_NAMESPACE} exists"
else
  fail "namespace ${CHECK_NAMESPACE} is missing"
fi

checkpoint=$(kubectl -n "$CHECK_NAMESPACE" get configmap before-backup \
  -o jsonpath='{.data.checkpoint}' 2>/dev/null || true)
if [ "$checkpoint" = 'before-backup' ]; then
  pass 'ConfigMap value returned to before-backup'
else
  fail "ConfigMap checkpoint is '${checkpoint:-<missing>}'"
fi

for resource in serviceaccount/before-backup service/before-backup deployment.apps/before-backup; do
  if kubectl -n "$CHECK_NAMESPACE" get "$resource" >/dev/null 2>&1; then
    pass "$resource was restored"
  else
    fail "$resource is missing"
  fi
done

replicas=$(kubectl -n "$CHECK_NAMESPACE" get deployment before-backup \
  -o jsonpath='{.spec.replicas}' 2>/dev/null || true)
if [ "$replicas" = '0' ]; then
  pass 'Deployment replicas returned to 0'
else
  fail "Deployment replicas is '${replicas:-<missing>}'"
fi

service_ip=$(kubectl -n "$CHECK_NAMESPACE" get service before-backup \
  -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
if [ -n "$service_ip" ] && [ "$service_ip" != 'None' ]; then
  pass 'Service has a restored ClusterIP'
else
  fail 'Service ClusterIP is missing'
fi

post_output=$(kubectl -n "$CHECK_NAMESPACE" get configmap after-backup 2>&1)
post_status=$?
if [ "$post_status" -eq 0 ]; then
  fail 'ConfigMap after-backup still exists'
elif printf '%s\n' "$post_output" | grep -q 'NotFound'; then
  pass 'ConfigMap created after the snapshot is absent'
else
  fail "could not determine whether ConfigMap after-backup exists: ${post_output}"
fi

printf '\nNon-running, non-completed Pods (informational):\n'
kubectl get pods -A \
  --field-selector='status.phase!=Running,status.phase!=Succeeded' \
  -o wide 2>&1 || true

printf '\nSUMMARY: pass=%d fail=%d\n' "$pass_count" "$fail_count"
if [ "$fail_count" -ne 0 ]; then
  exit 1
fi
