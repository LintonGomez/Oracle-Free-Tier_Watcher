# Security Policy

## Scope

This is a public repository containing infrastructure automation that can create OCI resources. Treat any change that affects authentication, resource creation, retries, stop conditions, logs, or systemd privileges as security-sensitive.

## Reporting a vulnerability

Do not open a public issue with credentials, private keys, real OCIDs, IP addresses, unredacted logs, or a working exploit. Use GitHub's private vulnerability reporting / Security Advisories for this repository if enabled. If private reporting is unavailable, contact the repository owner privately through a trusted channel and share only the minimum necessary information.

## Secret exposure

If a credential or private key is exposed:
1. Revoke or rotate it immediately in the relevant provider.
2. Inspect audit logs for unauthorized use.
3. Remove the exposed material from the current tree and coordinate history cleanup; a later deletion commit is not sufficient.
4. Review forks, caches, Actions logs and artifacts where applicable.

## Security expectations

- Keep OCI configuration, API private keys, SSH private keys, resource identifiers, logs and runtime state out of Git.
- Keep the watcher in dry-run mode until local configuration and permissions have been reviewed.
- Use a dedicated OS account and least-privilege OCI IAM policies.
- Do not grant repository workflows write permissions unless strictly required.
- Pin GitHub Actions to immutable commit SHAs.
- Verify the stop-on-success path and automatic-start behavior before production use.
