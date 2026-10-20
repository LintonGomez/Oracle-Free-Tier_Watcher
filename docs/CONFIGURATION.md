# Configuration and security

## Never store secrets in Git

The repository is public. Keep all of the following outside the checkout:
- OCI API private keys, SSH private keys, auth tokens and session tokens.
- Real tenancy, compartment, image, subnet and instance OCIDs.
- Production logs, CLI output and state files.
- Any local configuration containing infrastructure identifiers.

Use OCI CLI's local configuration/key-file mechanism or an approved secret manager. Never paste private key material into issues, pull requests, Actions logs or this repository. The example file contains only placeholders. The selected profile must define an absolute `key_file` path outside any home directory; the watcher checks that the OCI config and private key are not accessible by group/other users. Use `chmod 600` for both files and make the dedicated `oracle-watcher` account the owner of the private key and keep it mode `0600`.

## Local setup

Create a protected configuration directory on the target Linux host, copy `config/watcher.env.example` to that directory, replace the placeholder values, and set owner and mode appropriately (for example, root-owned mode `0600` when used by a root-managed service).

Verify that the OCI CLI profile can list the intended compartment and that the referenced image, subnet, shape, and availability domain are valid in the selected region. Confirm whether the image accepts the configured shape and whether quotas are available.

The service account should have only the OCI IAM permissions required for its intended actions. Do not grant tenancy-wide administration just to make the watcher work. Install the OCI CLI at `/usr/local/bin/oci` (or update the local configuration to a verified absolute path) because the example systemd unit hides home directories and uses a dedicated `oracle-watcher` account. Place the OCI config, its private key, SSH public key, and environment file under `/etc/oracle-free-tier-watcher/` with restrictive ownership and permissions.

## Dry-run first

Keep `DRY_RUN=true`. Confirm instance detection, configuration loading, logging and shutdown. Only set `DRY_RUN=false` after reviewing the command and verifying that each launch parameter is correct. Launching an instance changes cloud resources and may incur charges outside eligible free quotas.

## Public-repository hygiene

Before every commit, inspect staged content and run a secret scanner. Do not commit generated logs or state. If a real credential is exposed, revoke/rotate it. Removing a file in a later commit does not erase earlier versions from Git history.

## Recovery note

The original production script contained resource OCIDs inline. Those literal values are intentionally not reproduced here; configure the required identifiers directly on the target server. The original service stopped itself after detecting an existing instance, but the systemd unit remained enabled. Confirm the operational service is disabled independently; do not assume that script exit disables systemd.
