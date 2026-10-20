#!/usr/bin/env bash
# Local integration smoke tests. All OCI responses are simulated; no network,
# credentials, or cloud resources are used.
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/log" "$TMP/state"
printf 'not-a-real-key\n' > "$TMP/fake-key"
printf 'ssh-ed25519 AAAATEST fake-test-key\n' > "$TMP/fake-public-key"
chmod 600 "$TMP/fake-key" "$TMP/fake-public-key"
printf '[DEFAULT]\nkey_file=%s\n' "$TMP/fake-key" > "$TMP/oci-config"
chmod 600 "$TMP/oci-config"

cat > "$TMP/bin/oci" <<'MOCK_OCI'
#!/usr/bin/env bash
set -Eeuo pipefail
args="$*"
if [[ "$args" == *"iam availability-domain list"* ]]; then
  printf '{"data":[{"name":"AD-1"}]}\n'
elif [[ "$args" == *"compute instance list"* ]]; then
  if [[ "${MOCK_EXISTING:-false}" == "true" ]]; then
    printf '{"data":[{"lifecycle-state":"RUNNING"}]}\n'
  else
    printf '{"data":[]}\n'
  fi
elif [[ "$args" == *"compute compute-capacity-report create"* ]]; then
  printf 'capacity-check\n' >> "$MOCK_CALLS"
  printf '{"data":{"shape-availabilities":[{"availability-status":"%s"}]}}\n' "${MOCK_CAPACITY_STATUS:-AVAILABLE}"
elif [[ "$args" == *"compute instance launch"* ]]; then
  printf 'launch-called\n' >> "$MOCK_CALLS"
  printf '{"data":{}}\n'
else
  printf 'unexpected mocked OCI command\n' >&2
  exit 64
fi
MOCK_OCI
cat > "$TMP/bin/sleep" <<'MOCK_SLEEP'
#!/usr/bin/env bash
# Stop the watcher after one loop so each test remains deterministic.
exit 99
MOCK_SLEEP
chmod 700 "$TMP/bin/oci" "$TMP/bin/sleep"

export OCI_CLI="$TMP/bin/oci"
export OCI_CONFIG_FILE="$TMP/oci-config"
export OCI_PROFILE="DEFAULT"
export REGION="us-test-1"
export COMPARTMENT_ID="ocid1.compartment.oc1.fake"
export INSTANCE_NAME="watcher-test-instance"
export SHAPE="VM.Standard.A1.Flex"
export OCPUS="2"
export MEMORY_GB="12"
export BOOT_GB="50"
export IMAGE_ID="ocid1.image.oc1.fake"
export SUBNET_ID="ocid1.subnet.oc1.fake"
export SSH_PUBLIC_KEY_FILE="$TMP/fake-public-key"
export LOG_DIR="$TMP/log"
export STATE_DIR="$TMP/state"
export RETRY_BASE_SECONDS="1"
export RETRY_JITTER_SECONDS="0"
export API_THROTTLE_BACKOFF_SECONDS="1"
export CAPACITY_CHECK_TIMEOUT_SECONDS="2"
export CONFIG_ERROR_BACKOFF_SECONDS="1"
export INSTANCE_LIST_ERROR_BACKOFF_SECONDS="1"
export LAUNCH_TIMEOUT_SECONDS="2"
export DRY_RUN="true"
export AVAILABILITY_DOMAINS="AD-1"
export MOCK_CALLS="$TMP/calls"
PATH="$TMP/bin:$PATH"
export PATH

run_until_mock_sleep() {
  local rc=0
  "$ROOT/src/oracle-free-tier-watcher.sh" || rc=$?
  [[ "$rc" -eq 99 ]] || {
    printf 'Expected mocked sleep to stop the watcher with exit 99; got %s\n' "$rc" >&2
    return 1
  }
}

# Case 1: capacity AVAILABLE => dry-run records intent; never calls launch.
: > "$MOCK_CALLS"
: > "$TMP/log/watcher.log"
export MOCK_EXISTING="false" MOCK_CAPACITY_STATUS="AVAILABLE"
run_until_mock_sleep
grep -q 'DRY_RUN_WOULD_LAUNCH' "$TMP/log/watcher.log"
grep -q '^capacity-check$' "$MOCK_CALLS"
! grep -q '^launch-called$' "$MOCK_CALLS"

# Case 2: no capacity => no launch attempt.
rm -f "$TMP/state/watcher.lock"
: > "$MOCK_CALLS"
: > "$TMP/log/watcher.log"
export MOCK_CAPACITY_STATUS="NOT_AVAILABLE"
run_until_mock_sleep
grep -q 'NO_CAPACITY' "$TMP/log/watcher.log"
! grep -q '^launch-called$' "$MOCK_CALLS"

# Case 3: existing instance => stop before asking for capacity.
rm -f "$TMP/state/watcher.lock"
: > "$MOCK_CALLS"
: > "$TMP/log/watcher.log"
export MOCK_EXISTING="true"
"$ROOT/src/oracle-free-tier-watcher.sh"
grep -q 'INSTANCE_EXISTS' "$TMP/log/watcher.log"
! grep -q '^capacity-check$' "$MOCK_CALLS"
! grep -q '^launch-called$' "$MOCK_CALLS"

printf 'PASS: mocked OCI capacity, dry-run, and existing-instance scenarios\n'
