#!/usr/bin/env bash
# Sanitized public template for Oracle Free Tier Capacity Watcher.
# Requires: bash, OCI CLI, jq, flock, timeout.
set -Eeuo pipefail
umask 077

: "${OCI_CLI:?Set OCI_CLI in the local environment file}"
: "${OCI_CONFIG_FILE:?Set OCI_CONFIG_FILE in the local environment file}"
: "${REGION:?Set REGION in the local environment file}"
: "${COMPARTMENT_ID:?Set COMPARTMENT_ID locally}"
: "${INSTANCE_NAME:?Set INSTANCE_NAME in the local environment file}"
: "${SHAPE:?Set SHAPE in the local environment file}"
: "${OCPUS:?Set OCPUS in the local environment file}"
: "${MEMORY_GB:?Set MEMORY_GB in the local environment file}"
: "${BOOT_GB:?Set BOOT_GB in the local environment file}"
: "${IMAGE_ID:?Set IMAGE_ID locally}"
: "${SUBNET_ID:?Set SUBNET_ID locally}"
: "${SSH_PUBLIC_KEY_FILE:?Set SSH_PUBLIC_KEY_FILE locally}"
: "${LOG_DIR:?Set LOG_DIR in the local environment file}"
: "${STATE_DIR:?Set STATE_DIR in the local environment file}"

OCI_PROFILE="${OCI_PROFILE:-DEFAULT}"
RETRY_BASE_SECONDS="${RETRY_BASE_SECONDS:-120}"
RETRY_JITTER_SECONDS="${RETRY_JITTER_SECONDS:-30}"
API_THROTTLE_BACKOFF_SECONDS="${API_THROTTLE_BACKOFF_SECONDS:-600}"
CONFIG_ERROR_BACKOFF_SECONDS="${CONFIG_ERROR_BACKOFF_SECONDS:-1800}"
INSTANCE_LIST_ERROR_BACKOFF_SECONDS="${INSTANCE_LIST_ERROR_BACKOFF_SECONDS:-300}"
LAUNCH_TIMEOUT_SECONDS="${LAUNCH_TIMEOUT_SECONDS:-900}"
DRY_RUN="${DRY_RUN:-true}"
AVAILABILITY_DOMAINS="${AVAILABILITY_DOMAINS:-}"

for binary in "$OCI_CLI" jq flock timeout; do
  command -v "$binary" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$binary" >&2
    exit 127
  }
done
[[ -r "$OCI_CONFIG_FILE" ]] || { echo "OCI config file is not readable" >&2; exit 2; }
[[ -r "$SSH_PUBLIC_KEY_FILE" ]] || { echo "SSH public key is not readable" >&2; exit 2; }
[[ "$OCPUS" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "OCPUS must be numeric" >&2; exit 2; }
[[ "$MEMORY_GB" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "MEMORY_GB must be numeric" >&2; exit 2; }
[[ "$BOOT_GB" =~ ^[0-9]+$ ]] || { echo "BOOT_GB must be an integer" >&2; exit 2; }
[[ "$RETRY_BASE_SECONDS" =~ ^[0-9]+$ && "$RETRY_JITTER_SECONDS" =~ ^[0-9]+$ ]] || {
  echo "Retry intervals must be non-negative integers" >&2; exit 2;
}
[[ "$DRY_RUN" == "true" || "$DRY_RUN" == "false" ]] || {
  echo "DRY_RUN must be true or false" >&2; exit 2;
}
[[ "$REGION" != REPLACE_* && "$COMPARTMENT_ID" != *REPLACE* &&
   "$IMAGE_ID" != *REPLACE* && "$SUBNET_ID" != *REPLACE* ]] || {
  echo "Configuration still contains placeholders" >&2; exit 2;
}

mkdir -p "$LOG_DIR" "$STATE_DIR"
chmod 700 "$LOG_DIR" "$STATE_DIR"
LOG_FILE="$LOG_DIR/watcher.log"
STATE_FILE="$STATE_DIR/state"
LOCK_FILE="$STATE_DIR/watcher.lock"

log() { printf '%s %s\n' "$(date -Is)" "$*" | tee -a "$LOG_FILE"; }

exec 9>"$LOCK_FILE"
if ! flock -n 9; then log "WATCHER_ALREADY_RUNNING"; exit 0; fi

oci_cmd() {
  "$OCI_CLI" --config-file "$OCI_CONFIG_FILE" --profile "$OCI_PROFILE" "$@"
}

log "WATCHER_START region=$REGION shape=$SHAPE ocpus=$OCPUS memory_gb=$MEMORY_GB dry_run=$DRY_RUN"

# Space-separated availability domain names are local config only. If none are
# configured, use the first AD returned by OCI for this region.
ADS=()
if [[ -n "$AVAILABILITY_DOMAINS" ]]; then
  read -r -a ADS <<< "$AVAILABILITY_DOMAINS"
else
  AD_JSON=$(oci_cmd iam availability-domain list --compartment-id "$COMPARTMENT_ID" --region "$REGION" 2>>"$LOG_FILE") || {
    log "AVAILABILITY_DOMAIN_LOOKUP_ERROR"; exit 1;
  }
  mapfile -t ADS < <(printf '%s' "$AD_JSON" | jq -r '.data[]?.name')
fi
if [[ ${#ADS[@]} -eq 0 ]]; then log "NO_AVAILABILITY_DOMAINS"; exit 1; fi
AD_INDEX=0

while true; do
  if ! EXISTING=$(oci_cmd compute instance list --compartment-id "$COMPARTMENT_ID" --region "$REGION" \
      --all --display-name "$INSTANCE_NAME" 2>&1); then
    log "INSTANCE_LIST_ERROR"
    # Do not write unredacted CLI output to a public log; logs remain local.
    printf '%s\n' "$EXISTING" | tail -n 5 >> "$LOG_FILE"
    sleep "$INSTANCE_LIST_ERROR_BACKOFF_SECONDS"
    continue
  fi

  ID=$(printf '%s' "$EXISTING" | jq -r '.data[]? | select(."lifecycle-state" != "TERMINATED") | .id' | head -n1 || true)
  if [[ -n "$ID" ]]; then
    log "INSTANCE_EXISTS watcher_stopping=true"
    printf 'INSTANCE_EXISTS\n' > "$STATE_FILE"
    exit 0
  fi

  AD="${ADS[$AD_INDEX]}"
  AD_INDEX=$(( (AD_INDEX + 1) % ${#ADS[@]} ))
  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY_RUN_WOULD_LAUNCH ad_index=$((AD_INDEX + 1)) region=$REGION shape=$SHAPE"
  else
    log "LAUNCH_ATTEMPT ad_index=$((AD_INDEX + 1)) region=$REGION shape=$SHAPE"
    # Never log the full OCI response: it may include sensitive identifiers.
    if LAUNCH_JSON=$(timeout "$LAUNCH_TIMEOUT_SECONDS" oci_cmd compute instance launch \
        --availability-domain "$AD" --compartment-id "$COMPARTMENT_ID" \
        --display-name "$INSTANCE_NAME" --shape "$SHAPE" \
        --shape-config "{\"ocpus\":$OCPUS,\"memoryInGBs\":$MEMORY_GB}" \
        --subnet-id "$SUBNET_ID" --assign-public-ip true --image-id "$IMAGE_ID" \
        --boot-volume-size-in-gbs "$BOOT_GB" --ssh-authorized-keys-file "$SSH_PUBLIC_KEY_FILE" \
        --region "$REGION" --wait-for-state RUNNING --max-wait-seconds "$LAUNCH_TIMEOUT_SECONDS" 2>&1); then
      ID=$(printf '%s' "$LAUNCH_JSON" | jq -r '.data.id // empty' 2>/dev/null || true)
      if [[ -n "$ID" ]]; then
        log "INSTANCE_CREATED watcher_stopping=true"
        printf 'INSTANCE_CREATED\n' > "$STATE_FILE"
        exit 0
      fi
      log "LAUNCH_SUCCESS_WITHOUT_PARSEABLE_ID verify_on_next_cycle=true"
    else
      RC=$?
      if grep -Eqi 'out.of.host.capacity|out of host capacity|OutOfHostCapacity' <<<"$LAUNCH_JSON"; then
        log "OUT_OF_HOST_CAPACITY"
      elif grep -Eqi 'TooManyRequests|429|throttl' <<<"$LAUNCH_JSON"; then
        log "API_THROTTLED backoff_seconds=$API_THROTTLE_BACKOFF_SECONDS"
        sleep "$API_THROTTLE_BACKOFF_SECONDS"
        continue
      elif grep -Eqi 'NotAuthenticated|NotAuthorized|InvalidParameter|LimitExceeded|QuotaExceeded|InvalidConfiguration|Invalid image|Subnet.*not found' <<<"$LAUNCH_JSON"; then
        log "CONFIG_OR_PERMISSION_ERROR manual_review_required=true"
        sleep "$CONFIG_ERROR_BACKOFF_SECONDS"
        continue
      else
        log "LAUNCH_ERROR exit_code=$RC"
      fi
      # Do not log raw OCI error output; it may contain resource details.
    fi
  fi

  # Bounded retry interval with jitter.
  WAIT=$(( RETRY_BASE_SECONDS + RANDOM % (RETRY_JITTER_SECONDS + 1) ))
  log "RETRY_SLEEP seconds=$WAIT"
  sleep "$WAIT"
done
