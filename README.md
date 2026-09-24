# PatchPilot

PatchPilot is a browser-based Oracle IAM and Fusion Middleware patch orchestration console. It coordinates SSH discovery, README-driven validation, backups, service gates, OPatch operations, SPBAT phases, post-install actions, rollback information, live logs, and final HTML reports.

PatchPilot does not replace Oracle patch documentation, OPatch, or SPBAT. The selected patch README and Oracle utility output remain the source of truth.

## Requirements

- A supported Linux host with `systemd`
- Python 3
- OpenSSH client
- `curl` and `tar`
- `sshpass` when password-based SSH is required
- Network access from the PatchPilot host to target servers
- Network access to GitHub for online installation and upgrades

PatchPilot should run on a controlled management host. It does not need to be installed in an Oracle home.

## Quick Install

The installer defaults to port `4128`, creates the `patchpilot` service account, installs a `systemd` service, and starts PatchPilot.

```bash
sudo bash -lc 'cd /tmp && rm -rf PatchPilot-main patchpilot-main.tar.gz && curl -L https://github.com/reply4ramesh/PatchPilot/archive/refs/heads/main.tar.gz -o patchpilot-main.tar.gz && tar -xzf patchpilot-main.tar.gz && bash /tmp/PatchPilot-main/server-app/install.sh'
```

To use a different port or skip OS package installation:

```bash
sudo bash /tmp/PatchPilot-main/server-app/install.sh --port 4128 --skip-os-packages
```

Enable the optional daily update timer during installation:

```bash
sudo bash /tmp/PatchPilot-main/server-app/install.sh --auto-update daily --auto-update-hour 2
```

Automatic updates are skipped while PatchPilot has active patch jobs.

## Private Repository Access

The one-command download works without credentials when the repository is public. For a private repository, provide a read-only GitHub token through the customer's approved secret-management process and configure `PATCHPILOT_GITHUB_TOKEN` in `/etc/patchpilot.env`. Do not put tokens in shell history or source control.

## Upgrade

Download the current GitHub package and run its upgrade script:

```bash
sudo bash -lc 'cd /tmp && rm -rf PatchPilot-main patchpilot-main.tar.gz && curl -L https://github.com/reply4ramesh/PatchPilot/archive/refs/heads/main.tar.gz -o patchpilot-main.tar.gz && tar -xzf patchpilot-main.tar.gz && bash /tmp/PatchPilot-main/server-app/upgrade.sh'
```

The upgrade process:

- Refuses to continue while a remote patch job is active
- Creates a timestamped backup under `/opt/patchpilot-backup`
- Validates the new Python backend
- Preserves `/etc/patchpilot.env`, state, and logs
- Restarts the service
- Checks `/healthz`
- Restores the previous version when the health check fails

Run the configured GitHub update check manually:

```bash
sudo systemctl start patchpilot-updater.service
sudo journalctl -u patchpilot-updater.service -n 100 --no-pager
```

## Configuration

| Item | Default |
| --- | --- |
| Application | `/opt/patchpilot` |
| Configuration | `/etc/patchpilot.env` |
| Runtime state | `/var/lib/patchpilot` |
| Logs | `/var/log/patchpilot` and the system journal |
| Service | `patchpilot.service` |
| Update service | `patchpilot-updater.service` |
| Update timer | `patchpilot-updater.timer` |
| Port | `4128` |

After changing `/etc/patchpilot.env`:

```bash
sudo systemctl restart patchpilot
```

Proxy variables such as `HTTPS_PROXY` and `NO_PROXY` may be added to `/etc/patchpilot.env` when the management host requires a proxy to reach GitHub.

## Service Commands

```bash
sudo systemctl status patchpilot --no-pager
sudo systemctl restart patchpilot
sudo journalctl -u patchpilot -f
curl -fsS http://127.0.0.1:4128/healthz
```

Then open:

```text
http://<patchpilot-host-or-ip>:4128/
```

## Concurrent Targets

Jobs for different SSH hosts may run concurrently. PatchPilot serializes mutating jobs for the same host to reduce Oracle inventory lock risk. Cluster operators must still follow the patch README and coordinate AdminServer, managed-server, shared-domain, and once-per-domain actions.

## Security

- Do not commit passwords, private keys, customer logs, reports, or host-specific files.
- Prefer SSH keys and strict host-key validation where customer policy permits.
- Place PatchPilot behind customer-approved HTTPS and authentication controls.
- Restrict access to the PatchPilot management host and port.
- Validate each PatchPilot release in a non-production environment before production use.
- Do not expose the service directly to the public internet.

## Uninstall

```bash
sudo systemctl disable --now patchpilot.service patchpilot-updater.timer 2>/dev/null || true
sudo rm -f /etc/systemd/system/patchpilot.service
sudo rm -f /etc/systemd/system/patchpilot-updater.service
sudo rm -f /etc/systemd/system/patchpilot-updater.timer
sudo systemctl daemon-reload
sudo rm -rf /opt/patchpilot
```

Remove `/etc/patchpilot.env`, `/var/lib/patchpilot`, `/var/log/patchpilot`, and `/opt/patchpilot-backup` only when their saved configuration, reports, logs, and rollback packages are no longer needed.
