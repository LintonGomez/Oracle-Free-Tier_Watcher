# Operations

## Before running

1. Verify the target host, OCI CLI path, local OCI config/profile, selected region, compartment, image, subnet, SSH public key and compute shape.
2. Verify that the target instance name does not refer to a different or important instance.
3. Confirm quotas, free-tier eligibility and possible charges.
4. Start in dry-run mode and inspect logs.

## Service lifecycle

The systemd unit example is intentionally not enabled automatically. After adapting its user, paths, environment file and permissions, install and inspect it manually.

Check status:

```bash
systemctl status oracle-free-tier-watcher.service --no-pager
systemctl is-enabled oracle-free-tier-watcher.service
systemctl is-active oracle-free-tier-watcher.service
```

Stop now and prevent automatic starts:

```bash
sudo systemctl disable --now oracle-free-tier-watcher.service
```

Verify the results. Expected output is `disabled` and `inactive`. Also check for a systemd timer or other scheduler separately if one was installed. The example unit is sandboxed and does not auto-restart; a separate timer must be reviewed explicitly before enabling it.

## Logs and state

Keep logs and runtime state outside the checkout, with restrictive filesystem permissions. Avoid sharing unredacted logs publicly: OCI CLI error responses can contain identifiers and other infrastructure details.

## Failure handling

Transient capacity errors may be retried with bounded backoff. Authentication, authorization, quota, invalid configuration, missing resources, and throttling errors should not lead to rapid repeated launch calls. Review logs privately and correct the underlying cause before enabling retries. The watcher intentionally suppresses raw OCI CLI responses because they can contain resource identifiers; diagnose OCI failures locally and never paste unredacted output into public issues. Malformed instance-list JSON causes a fail-closed backoff rather than a launch attempt.
