#!/usr/bin/env bash
# Oracle Free Tier Capacity Watcher — public, sanitized template.
# Requirements: Bash 4+, OCI CLI, jq, flock, timeout, coreutils.
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }
need() { [[ -n "${!1:-}" ]] || die "Required setting is missing: $1"; }

for name in OCI_CLI OCI_CONFIG_FILE REGION COMPARTMENT_ID INSTANCE_NAME SHAPE OCPUS MEMORY_GB BOOT_GB IMAGE_ID SUBNET_ID SSH_PUBLIC_KEY_FILE LOG_DIR STATE_DIR; do
  need "$name"
done

OCI_PROFILE="${OCI_PROFILE:-DEFAULT}"
RETRY_BASE_SECONDS="${RETRY_BASE_SECONDS:-120}"
RETRY_JITTER_SECONDS="${RETRY_JITTER_SECONDS:-30}"
API_THROTTLE_BACKOFF_SECONDS="${API_THROTTLE_BACKOFF_SECONDS:-600}"
CAPACITY_CHECK_TIMEOUT_SECONDS="${CAPACITY_CHECK_TIMEOUT_SECONDS:-60}"
CONFIG_ERROR_BACKOFF_SECONDS="${CONFIG_ERROR_BACKOFF_SECONDS:-1800}"
INSTANCE_LIST_ERROR_BACKOFF_SECONDS="${INSTANCE_LIST_ERROR_BACKOFF_SECONDS:-300}"
LAUNCH_TIMEOUT_SECONDS="${LAUNCH_TIMEOUT_SECONDS:-900}"
DRY_RUN="${DRY_RUN:-true}"
AVAILABILITY_DOMAINS="${AVAILABILITY_DOMAINS:-}"

# Fail closed: require absolute paths and regular readable/executable files.
[[ "$OCI_CLI" == /* && -x "$OCI_CLI" ]] || die "OCI_CLI must be an absolute executable path"
[[ "$OCI_CONFIG_FILE" == /* && -f "$OCI_CONFIG_FILE" && -r "$OCI_CONFIG_FILE" ]] || die "OCI_CONFIG_FILE must be an absolute readable regular file"
[[ "$SSH_PUBLIC_KEY_FILE" == /* && -f "$SSH_PUBLIC_KEY_FILE" && -r "$SSH_PUBLIC_KEY_FILE" ]] || die "SSH_PUBLIC_KEY_FILE must be an absolute readable regular file"
for path in "$OCI_CONFIG_FILE" "$SSH_PUBLIC_KEY_FILE"; do
  [[ ! -L "$path" ]] || die "Symlinks are not allowed for sensitive configuration inputs"
done
[[ "$OCI_PROFILE" =~ ^[a-zA-Z0-9_-]+$ ]] || die "Invalid OCI_PROFILE syntax"

# Require an explicit absolute private-key path in the selected OCI profile.
# Do not print the path or contents. ProtectHome=true in the unit means this
# key should live under /etc/oracle-free-tier-watcher, not under a home folder.
KEY_FILE=$(awk -v profile="$OCI_PROFILE" '
  /^[[:space:]]*#/ { next }
  /^[[:space:]]*\\[/ {
    section=$0
    gsub(/^[[:space:]]*\\[|\\][[:space:]]*$/, "", section)
    active=(section == profile)
    next
  }
  active && /^[[:space:]]*key_file[[:space:]]*=/ {
    sub(/^[^=]*=[[:space:]]*/, "")
    gsub(/[[:space:]]+$/, "")
    print
    exit
  }
' "$OCI_CONFIG_FILE")
[[ "$KEY_FILE" == /* && -f "$KEY_FILE" && -r "$KEY_FILE" && ! -L "$KEY_FILE" ]] || die "Selected OCI profile must reference an absolute, readable, non-symlink key_file"
if command -v stat >/dev/null 2>&1; then
  key_mode=$(stat -c '%a' "$KEY_FILE" 2>/dev/null || true)
  if [[ "$key_mode" =~ ^[0-7]{3,4}$ ]]; then
    key_perms=$((8#$key_mode))
    (( (key_perms & 077) == 0 )) || die "OCI private key permissions are too broad; use chmod 600"
  fi
fi
unset KEY_FILE
[[ "$REGION" =~ ^[a-zA-Z0-9-]+$ ]] || die "Invalid REGION syntax"
[[ "$COMPARTMENT_ID" =~ ^ocid1\.(tenancy|compartment)\.oc1\..+$ ]] || die "COMPARTMENT_ID must be a local tenancy/compartment OCID"
[[ "$IMAGE_ID" =~ ^ocid1\.image\.oc1\..+$ ]] || die "IMAGE_ID must be a local image OCID"
[[ "$SUBNET_ID" =~ ^ocid1\.subnet\.oc1\..+$ ]] || die "SUBNET_ID must be a local subnet OCID"
[[ "$INSTANCE_NAME" =~ ^[a-zA-Z0-9._-]{1,100}$ ]] || die "INSTANCE_NAME contains unsupported characters"
[[ "$SHAPE" =~ ^[a-zA-Z0-9._-]{1,100}$ ]] || die "Invalid SHAPE syntax"
[[ "$OCPUS" =~ ^[0-9]+([.][0-9]+)?$ && "$MEMORY_GB" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "OCPUS and MEMORY_GB must be numeric"
[[ "$BOOT_GB" =~ ^[0-9]+$ ]] || die "BOOT_GB must be an integer"
for name in RETRY_BASE_SECONDS RETRY_JITTER_SECONDS API_THROTTLE_BACKOFF_SECONDS CAPACITY_CHECK_TIMEOUT_SECONDS CONFIG_ERROR_BACKOFF_SECONDS INSTANCE_LIST_ERROR_BACKOFF_SECONDS LAUNCH_TIMEOUT_SECONDS; do
  [[ "${!name}" =~ ^[0-9]+$ ]] || die "$name must be a non-negative integer"
done
[[ "$RETRY_BASE_SECONDS" -ge 1 && "$LAUNCH_TIMEOUT_SECONDS" -ge 1 && "$CAPACITY_CHECK_TIMEOUT_SECONDS" -ge 1 ]] || die "Retry base, capacity timeout, and launch timeout must be at least 1 second"
[[ "$DRY_RUN" == "true" || "$DRY_RUN" == "false" ]] || die "DRY_RUN must be true or false"
[[ "$REGION" != REPLACE_* && "$COMPARTMENT_ID" != *REPLACE* && "$IMAGE_ID" != *REPLACE* && "$SUBNET_ID" != *REPLACE* ]] || die "Configuration still contains placeholders"

for binary in jq flock timeout; do command -v "$binary" >/dev/null 2>&1 || die "Missing required command: $binary"; done
# The OCI CLI config may contain profile metadata and a path to a private key.
# Enforce no group/world access when the GNU stat interface is available.
if command -v stat >/dev/null 2>&1; then
  mode=$(stat -c '%a' "$OCI_CONFIG_FILE" 2>/dev/null || true)
  if [[ "$mode" =~ ^[0-7]{3,4}$ ]]; then
    perms=$((8#$mode))
    (( (perms & 077) == 0 )) || die "OCI config permissions are too broad; use chmod 600"
  fi
fi

mkdir -p -- "$LOG_DIR" "$STATE_DIR"
chmod 700 -- "$LOG_DIR" "$STATE_DIR"
LOG_FILE="$LOG_DIR/watcher.log"
STATE_FILE="$STATE_DIR/state"
LOCK_FILE="$STATE_DIR/watcher.lock"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"
log() { printf '%s %s\n' "$(date -Is)" "$*" >> "$LOG_FILE"; }
# Never log raw OCI CLI output, OCIDs, key paths, or credentials.

exec 9>"$LOCK_FILE"
if ! flock -n 9; then log "WATCHER_ALREADY_RUNNING"; exit 0; fi

oci_cmd() {
  "$OCI_CLI" --config-file "$OCI_CONFIG_FILE" --profile "$OCI_PROFILE" "$@"
}
stop_successfully() {
  local reason="$1"
  log "$reason watcher_stopping=true"
  printf '%s\n' "$reason" > "$STATE_FILE"
  chmod 600 "$STATE_FILE"
  exit 0
}

log "WATCHER_START region=$REGION shape=$SHAPE ocpus=$OCPUS memory_gb=$MEMORY_GB dry_run=$DRY_RUN"

ADS=()
if [[ -n "$AVAILABILITY_DOMAINS" ]]; then
  IFS=' ' read -r -a ADS <<< "$AVAILABILITY_DOMAINS"
else
  if ! AD_JSON=$(oci_cmd iam availability-domain list --compartment-id "$COMPARTMENT_ID" --region "$REGION" 2>/dev/null); then
    log "AVAILABILITY_DOMAIN_LOOKUP_ERROR; inspect local OCI CLI configuration"
    exit 1
  fi
  mapfile -t ADS < <(printf '%s' "$AD_JSON" | jq -r '.data[]?.name')
  unset AD_JSON
fi
[[ ${#ADS[@]} -gt 0 ]] || die "No availability domains were found or configured"
for ad in "${ADS[@]}"; do [[ "$ad" =~ ^[a-zA-Z0-9._:-]+$ ]] || die "Invalid availability-domain syntax"; done
AD_INDEX=0

while true; do
  if ! EXISTING=$(oci_cmd compute instance list --compartment-id "$COMPARTMENT_ID" --region "$REGION" --all --display-name "$INSTANCE_NAME" 2>/dev/null); then
    log "INSTANCE_LIST_ERROR; retrying after backoff"
    sleep "$INSTANCE_LIST_ERROR_BACKOFF_SECONDS"
    continue
  fi

  # Fail closed if OCI returns malformed/unexpected JSON. Never launch on
  # an unreadable instance-list response, because that can create duplicates.
  if ! printf '%s' "$EXISTING" | jq -e '.data | type == "array"' >/dev/null 2>&1; then
    unset EXISTING
    log "INSTANCE_LIST_INVALID_RESPONSE; refusing to launch"
    sleep "$INSTANCE_LIST_ERROR_BACKOFF_SECONDS"
    continue
  fi
  # Any non-terminated instance with the target display name is treated as
  # success. Never put its OCID into logs/state.
  if printf '%s' "$EXISTING" | jq -e '.data[]? | select(."lifecycle-state" != "TERMINATED")' >/dev/null; then
    unset EXISTING
    stop_successfully "INSTANCE_EXISTS"
  fi
  unset EXISTING

  # Reproduce the proven capacity-first procedure: query each configured AD
  # and launch only when OCI explicitly reports AVAILABLE. Never log raw API
  # output; it may contain OCIDs and infrastructure metadata.
  FOUND_AD=""
  CAPACITY_ERROR=false
  for AD in "${ADS[@]}"; do
    if CAPACITY_JSON=$(timeout "$CAPACITY_CHECK_TIMEOUT_SECONDS" oci_cmd compute compute-capacity-report create \
        --availability-domain "$AD" --compartment-id "$COMPARTMENT_ID" \
        --shape-availabilities "[{\"instanceShape\":\"$SHAPE\",\"instanceShapeConfig\":{\"ocpus\":$OCPUS,\"memoryInGBs\":$MEMORY_GB}}]" \
        --region "$REGION" 2>&1); then
      STATUS=$(printf '%s' "$CAPACITY_JSON" | jq -r '.data["shape-availabilities"][0]["availability-status"] // "UNKNOWN"' 2>/dev/null || printf 'UNKNOWN')
      unset CAPACITY_JSON
      if [[ "$STATUS" == "AVAILABLE" ]]; then
        FOUND_AD="$AD"
        break
      fi
    else
      RC=$?
      if grep -Eqi 'TooManyRequests|429|throttl' <<<"${CAPACITY_JSON:-}"; then
        unset CAPACITY_JSON
        log "CAPACITY_API_THROTTLED backoff_seconds=$API_THROTTLE_BACKOFF_SECONDS"
        sleep "$API_THROTTLE_BACKOFF_SECONDS"
        CAPACITY_ERROR=true
        break
      fi
      unset CAPACITY_JSON
      CAPACITY_ERROR=true
      log "CAPACITY_CHECK_ERROR exit_code=$RC; raw response suppressed"
    fi
  done

  if [[ -z "$FOUND_AD" ]]; then
    if [[ "$CAPACITY_ERROR" == "true" ]]; then
      WAIT="$INSTANCE_LIST_ERROR_BACKOFF_SECONDS"
      log "CAPACITY_UNCONFIRMED retry_seconds=$WAIT"
    else
      WAIT=$(( RETRY_BASE_SECONDS + RANDOM % (RETRY_JITTER_SECONDS + 1) ))
      log "NO_CAPACITY retry_seconds=$WAIT"
    fi
    sleep "$WAIT"
    continue
  fi

  log "CAPACITY_CONFIRMED ad_index=$((AD_INDEX + 1)); attempting launch"
  AD_INDEX=$(( (AD_INDEX + 1) % ${#ADS[@]} ))
  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY_RUN_WOULD_LAUNCH region=$REGION shape=$SHAPE"
  else
    log "LAUNCH_ATTEMPT region=$REGION shape=$SHAPE"
    if LAUNCH_JSON=$(timeout "$LAUNCH_TIMEOUT_SECONDS" oci_cmd compute instance launch \
        --availability-domain "$FOUND_AD" --compartment-id "$COMPARTMENT_ID" \
        --display-name "$INSTANCE_NAME" --shape "$SHAPE" \
        --shape-config "{\"ocpus\":$OCPUS,\"memoryInGBs\":$MEMORY_GB}" \
        --subnet-id "$SUBNET_ID" --assign-public-ip true --image-id "$IMAGE_ID" \
        --boot-volume-size-in-gbs "$BOOT_GB" --ssh-authorized-keys-file "$SSH_PUBLIC_KEY_FILE" \
        --region "$REGION" --wait-for-state RUNNING --max-wait-seconds "$LAUNCH_TIMEOUT_SECONDS" 2>&1); then
      unset LAUNCH_JSON
      stop_successfully "INSTANCE_CREATE_ACCEPTED"
    else
      RC=$?
      if grep -Eqi 'out.of.host.capacity|out of host capacity|OutOfHostCapacity' <<<"${LAUNCH_JSON:-}"; then
        log "OUT_OF_HOST_CAPACITY"
      elif grep -Eqi 'TooManyRequests|429|throttl' <<<"${LAUNCH_JSON:-}"; then
        unset LAUNCH_JSON
        log "API_THROTTLED backoff_seconds=$API_THROTTLE_BACKOFF_SECONDS"
        sleep "$API_THROTTLE_BACKOFF_SECONDS"
        continue
      elif grep -Eqi 'NotAuthenticated|NotAuthorized|InvalidParameter|LimitExceeded|QuotaExceeded|InvalidConfiguration|Invalid image|Subnet.*not found' <<<"${LAUNCH_JSON:-}"; then
        unset LAUNCH_JSON
        log "CONFIG_OR_PERMISSION_ERROR manual_review_required=true"
        sleep "$CONFIG_ERROR_BACKOFF_SECONDS"
        continue
      else
        log "LAUNCH_ERROR exit_code=$RC; raw response suppressed"
      fi
      unset LAUNCH_JSON
    fi
  fi

  WAIT=$(( RETRY_BASE_SECONDS + RANDOM % (RETRY_JITTER_SECONDS + 1) ))
  log "RETRY_SLEEP seconds=$WAIT"
  sleep "$WAIT"
done
