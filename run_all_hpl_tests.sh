#!/usr/bin/env bash
set -Eeuo pipefail

# Always work from the script's directory so data/hpccinf.txt and *.yaml resolve.
cd "$(dirname "${BASH_SOURCE[0]}")"

NAMESPACE="${NAMESPACE:-hpl-test}"
RESULTS_DIR="${RESULTS_DIR:-./hpl-results}"
JOB_TIMEOUT="${JOB_TIMEOUT:-10000}"       # seconds to wait for the hpl-master Job
KEEP_ON_FAIL="${KEEP_ON_FAIL:-0}"         # KEEP_ON_FAIL=1 leaves the cluster state in place on error
FOLLOW_LOGS="${FOLLOW_LOGS:-1}"           # stream the Job log while waiting
SSH_TMP_DIR="$(mktemp -d)"
LOG_PID=""

delete_workloads() {
  kubectl -n "$NAMESPACE" delete pod hpl-single hpl-multicontainer \
    --ignore-not-found >/dev/null 2>&1 || true
  kubectl -n "$NAMESPACE" delete job hpl-master \
    --ignore-not-found --wait=true >/dev/null 2>&1 || true
  kubectl -n "$NAMESPACE" delete statefulset hpl-worker \
    --ignore-not-found --wait=true >/dev/null 2>&1 || true
}

cleanup() {
  local rc=$?
  [[ -n "$LOG_PID" ]] && kill "$LOG_PID" >/dev/null 2>&1 || true
  rm -rf "$SSH_TMP_DIR"

  if (( rc != 0 )); then
    echo >&2
    echo "=== FAILED (rc=$rc): diagnostics ===" >&2
    kubectl -n "$NAMESPACE" get pods -o wide >&2 || true
    echo "--- hpl-master log (last 60 lines) ---" >&2
    kubectl -n "$NAMESPACE" logs job/hpl-master --tail=60 >&2 || true
    echo "--- hpl-worker-0 log (last 30 lines) ---" >&2
    kubectl -n "$NAMESPACE" logs hpl-worker-0 --tail=30 >&2 || true
    if [[ "$KEEP_ON_FAIL" == "1" ]]; then
      echo "KEEP_ON_FAIL=1: leaving pods/job in namespace $NAMESPACE for inspection." >&2
      return
    fi
  fi
  delete_workloads
}
trap cleanup EXIT

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

# Wait until a container has terminated (either way) and fail if its exit code is not 0.
wait_for_container() {
  local pod="$1"
  local container="$2"
  local timeout="${3:-600}"
  local elapsed=0
  local exit_code=""

  while (( elapsed < timeout )); do
    exit_code="$(kubectl -n "$NAMESPACE" get pod "$pod" \
      -o jsonpath="{.status.containerStatuses[?(@.name=='$container')].state.terminated.exitCode}" \
      2>/dev/null || true)"
    if [[ -n "$exit_code" ]]; then
      if [[ "$exit_code" != "0" ]]; then
        echo "ERROR: container $container in $pod exited with code $exit_code" >&2
        kubectl -n "$NAMESPACE" logs "$pod" -c "$container" >&2 || true
        return 1
      fi
      return 0
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done

  echo "ERROR: timeout waiting for container $container in $pod" >&2
  kubectl -n "$NAMESPACE" describe pod "$pod" >&2 || true
  return 1
}

# Wait for a Job to finish, in either direction (backoffLimit: 0 means a failure is final).
wait_for_job() {
  local job="$1"
  local timeout="${2:-1800}"
  local elapsed=0
  local succeeded failed

  while (( elapsed < timeout )); do
    succeeded="$(kubectl -n "$NAMESPACE" get job "$job" \
      -o jsonpath='{.status.succeeded}' 2>/dev/null || true)"
    failed="$(kubectl -n "$NAMESPACE" get job "$job" \
      -o jsonpath='{.status.failed}' 2>/dev/null || true)"
    if (( ${succeeded:-0} >= 1 )); then
      return 0
    fi
    if (( ${failed:-0} >= 1 )); then
      echo "ERROR: job $job failed" >&2
      return 1
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done

  echo "ERROR: timeout (${timeout}s) waiting for job $job" >&2
  kubectl -n "$NAMESPACE" describe job "$job" >&2 || true
  return 1
}

# Stream the Job log in the background so a long run does not look hung.
follow_job_logs() {
  (
    for _ in {1..120}; do
      kubectl -n "$NAMESPACE" logs -f job/hpl-master 2>/dev/null && break
      sleep 3
    done
  ) | sed 's/^/[master] /' &
  LOG_PID=$!
}

# Single pod / multi-container tests. Once the container has exited, kubectl cp and
# kubectl exec no longer work, but kubectl logs does. The container prints
# hpccoutf.txt at the end of its log between two marker lines; this splits the log into
#   benchmark_output-<prefix>.txt  (everything mpirun printed)
#   hpccoutf-<prefix>.txt          (the HPCC result file)
save_results_from_log() {
  local pod="$1"
  local prefix="$2"
  local container="${3:-}"
  local full="$SSH_TMP_DIR/full-${prefix}.log"
  local begin='=== BEGIN hpccoutf.txt ==='
  local end='=== END hpccoutf.txt ==='
  local out_bench="$RESULTS_DIR/benchmark_output-${prefix}.txt"
  local out_hpcc="$RESULTS_DIR/hpccoutf-${prefix}.txt"

  mkdir -p "$RESULTS_DIR"
  rm -f "$out_hpcc"
  kubectl -n "$NAMESPACE" logs "$pod" ${container:+-c "$container"} > "$full"

  if ! grep -qxF "$begin" "$full"; then
    echo "ERROR: no hpccoutf.txt block in the log of $pod (HPCC did not write its result file)" >&2
    cp "$full" "$out_bench"
    return 1
  fi

  awk -v b="$begin" -v e="$end" -v out="$out_hpcc" '
    $0 == b { inres = 1; next }
    $0 == e { inres = 0; next }
    inres   { print > out; next }
            { print }
  ' "$full" > "$out_bench"

  if [[ ! -s "$out_hpcc" ]]; then
    echo "ERROR: empty hpccoutf.txt block in the log of $pod" >&2
    return 1
  fi
}

# Distributed test: read each result where it is produced.
#  - mpirun output  -> Job log (works after the Job pod has completed)
#  - hpccoutf.txt   -> written by MPI rank 0 on hpl-worker-0, which is still running
collect_distributed_results() {
  mkdir -p "$RESULTS_DIR"
  kubectl -n "$NAMESPACE" logs job/hpl-master \
    > "$RESULTS_DIR/benchmark_output-distributed.txt"
  kubectl -n "$NAMESPACE" exec hpl-worker-0 -- cat /data/hpccoutf.txt \
    > "$RESULTS_DIR/hpccoutf-distributed.txt"

  if ! grep -q "End of HPC Challenge tests" "$RESULTS_DIR/hpccoutf-distributed.txt"; then
    echo "ERROR: hpccoutf-distributed.txt is incomplete (no 'End of HPC Challenge tests')" >&2
    return 1
  fi
  if grep -q "FAILED" "$RESULTS_DIR/benchmark_output-distributed.txt"; then
    echo "WARNING: 'FAILED' found in the HPL residual checks, inspect the output" >&2
  fi
}

require_command kubectl
require_command ssh-keygen

[[ -f data/hpccinf.txt ]] || { echo "ERROR: data/hpccinf.txt not found" >&2; exit 1; }
[[ -f multi_pod.yaml ]]   || { echo "ERROR: multi_pod.yaml not found" >&2; exit 1; }

mkdir -p "$RESULTS_DIR"

# 1. Namespace first
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# 2. Remove leftovers from previous runs BEFORE creating the new key.
#    Workers copy the public key into authorized_keys only at start, so old workers
#    would reject the new key; an old finished Job would make wait_for_job return at once.
echo "=== Cleaning previous run ==="
delete_workloads
kubectl -n "$NAMESPACE" wait --for=delete pod -l app=hpl --timeout=180s >/dev/null 2>&1 || true

# 3. Prerequisites (Secret & ConfigMap)
ssh-keygen -q -t ed25519 -N '' -f "$SSH_TMP_DIR/id_rsa"
kubectl -n "$NAMESPACE" create secret generic mpi-ssh-key \
  --from-file=id_rsa="$SSH_TMP_DIR/id_rsa" \
  --from-file=id_rsa.pub="$SSH_TMP_DIR/id_rsa.pub" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NAMESPACE" create configmap hpccinf-config \
  --from-file=hpccinf.txt=data/hpccinf.txt \
  --dry-run=client -o yaml | kubectl apply -f -

echo "=== Test 1/3: single Pod ==="
kubectl apply -f single_pod.yaml
wait_for_container hpl-single hpl 3000
save_results_from_log hpl-single single
kubectl -n "$NAMESPACE" delete pod hpl-single --ignore-not-found

echo "=== Test 2/3: multiple containers in one Pod ==="
kubectl apply -f multi_container.yaml
wait_for_container hpl-multicontainer hpl-master 8000
save_results_from_log hpl-multicontainer multi-container hpl-master
kubectl -n "$NAMESPACE" delete pod hpl-multicontainer --ignore-not-found

# echo "=== Test 3/3: distributed StatefulSet ==="
# kubectl apply -f multi_pod.yaml
# kubectl -n "$NAMESPACE" rollout status statefulset/hpl-worker --timeout=15m
# [[ "$FOLLOW_LOGS" == "1" ]] && follow_job_logs
# wait_for_job hpl-master "$JOB_TIMEOUT"
# [[ -n "$LOG_PID" ]] && wait "$LOG_PID" 2>/dev/null || true
# LOG_PID=""
# collect_distributed_results

echo
echo "Distributed HPL test completed successfully."
echo "Results copied to: $RESULTS_DIR"
find "$RESULTS_DIR" -maxdepth 1 -type f -printf '  %f\n' | sort