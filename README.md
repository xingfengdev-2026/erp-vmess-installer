# erp-vmess-installer

One-command installers that set up a **VMess (Xray)** node behind an
[**erp**](https://github.com/xingfengdev-2026/erp) reverse-tunnel client, for
both **Linux** and **Windows**.

What the scripts do:

1. Download the latest **Xray-core** and **erp** release binaries from GitHub.
2. Run a local **Xray VMess** inbound on `127.0.0.1:<xray-port>` (TCP, no TLS).
3. Run the **erp client**, which tunnels that local port out to a public
   `remote_port` on your erp server.
4. Keep both running (systemd / tmux on Linux, Scheduled Tasks on Windows).
5. Print a ready-to-import `vmess://` link and the matching JSON.

> You bring your own **erp server**. The scripts contain **no** server address,
> token, or proxy host baked in — you supply those yourself (see below).

---

## Requirements

- A running **erp server** you control, reachable at `HOST:CONTROL_PORT`
  (e.g. `your.server.com:6000`), and its shared **token**.
- A public **remote port** on that server to expose this node (e.g. `10086`).
  It must be different from the erp control port.
- **Linux:** x86_64, with `curl` + `unzip` (the script installs them for you when
  run as root). `tmux` is used for the non-root run mode.
- **Windows:** 64-bit, PowerShell 5.1+ (built in). Run the `.bat` **as
  Administrator** to register the auto-start Scheduled Tasks.

---

## Quick start

### Linux — `curl … | sh`

Run as **root** (or with passwordless `sudo`). Replace the server address and
port with your own:

```sh
curl -fsSL https://raw.githubusercontent.com/xingfengdev-2026/erp-vmess-installer/main/install_vmess_erp.sh \
  | sudo bash -s -- --server YOUR_SERVER_HOST:6000 --remote-port 10086
```

Already root? Drop the `sudo`:

```sh
curl -fsSL https://raw.githubusercontent.com/xingfengdev-2026/erp-vmess-installer/main/install_vmess_erp.sh \
  | bash -s -- --server YOUR_SERVER_HOST:6000 --remote-port 10086
```

> If your `sudo` asks for a password it can't read it from the pipe — either run
> as root, or download the script first and then run it (see below).

### Windows — elevated PowerShell one-liner

Open **PowerShell as Administrator**, then:

```powershell
$bat = "$env:TEMP\install_vmess_erp_windows.bat"
Invoke-WebRequest -UseBasicParsing -Uri https://raw.githubusercontent.com/xingfengdev-2026/erp-vmess-installer/main/install_vmess_erp_windows.bat -OutFile $bat
& $bat --server YOUR_SERVER_HOST:6000 --remote-port 23456
```

When it finishes, copy the printed `vmess://` link into your client
(v2rayN, v2rayNG, etc.).

---

## Download then run (recommended if you want to read it first)

### Linux

```sh
curl -fsSL -o install_vmess_erp.sh \
  https://raw.githubusercontent.com/xingfengdev-2026/erp-vmess-installer/main/install_vmess_erp.sh
chmod +x install_vmess_erp.sh

# Interactive — prompts for every value:
sudo ./install_vmess_erp.sh --interactive

# Or non-interactive:
sudo ./install_vmess_erp.sh --server YOUR_SERVER_HOST:6000 --remote-port 10086
```

### Windows

Download `install_vmess_erp_windows.bat`, then in an **Administrator** prompt:

```bat
install_vmess_erp_windows.bat --interactive
:: or
install_vmess_erp_windows.bat --server YOUR_SERVER_HOST:6000 --remote-port 23456
```

---

## Options

Both installers accept the same core options. Every option also has a matching
environment variable.

| Flag | Env var | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `--server ADDR` | `ERP_SERVER_ADDR` | **yes** | — | erp server control address `host:port`. |
| `--remote-port PORT` | `ERP_REMOTE_PORT` | **yes** | — | Public TCP port opened on the erp server for this node. |
| `--token TOKEN` | `ERP_TOKEN` | no | `19890604` | erp shared token. Must match your server. |
| `--transport NAME` | `ERP_TRANSPORT` | no | `raw` | erp transport (only `raw` is implemented). |
| `--xray-port PORT` | `XRAY_LOCAL_PORT` | no | `10086` | Local Xray VMess port (loopback only). |
| `--uuid UUID` | `XRAY_UUID` | no | auto-generated | VMess client UUID. |
| `--client-id ID` | `CLIENT_ID` | no | hostname | erp client id. |
| `--github-proxy-prefix URL` | `GITHUB_PROXY_PREFIX` | no | none | Optional GitHub download accelerator/mirror prefix (see below). |
| `--interactive` | `INTERACTIVE=1` | no | off | Prompt for the main parameters. |
| `-h`, `--help` | — | — | — | Show help. |

**Linux only**

| Flag | Env var | Default | Description |
| --- | --- | --- | --- |
| `--run-mode MODE` | `RUN_MODE` | `auto` | `auto`, `systemd`, or `tmux`. `auto` = systemd if root, else tmux. |
| `--install-root PATH` | `INSTALL_ROOT` | see below | Install location (tmux/non-root default: `~/.local/share/erp-vmess`). |

**Windows only**

| Flag | Env var | Default | Description |
| --- | --- | --- | --- |
| `--install-root PATH` | `INSTALL_ROOT` | `%ProgramData%\erp-vmess` | Install location. |
| `--no-tasks` | — | off | Install files only; don't create/start Scheduled Tasks. |

> **GitHub accelerator:** if GitHub releases are slow or blocked on your network,
> pass `--github-proxy-prefix https://your-mirror.example/` (a prefix that is
> prepended to each GitHub URL). Leave it unset to download directly from GitHub.

---

## Run modes & management

### Linux (root → systemd)

Two services are created: `xray.service` and `erp-client.service`.

```sh
systemctl status xray --no-pager
systemctl status erp-client --no-pager
journalctl -u xray -u erp-client --no-pager -n 100
```

### Linux (non-root → tmux)

Installs under `~/.local/share/erp-vmess` and runs in two tmux sessions.

```sh
tmux ls
tmux attach -t erp-vmess-xray
tmux attach -t erp-vmess-client
tail -n 100 ~/.local/share/erp-vmess/logs/erp-client.log
```

### Windows (Scheduled Tasks)

Two tasks run at startup as `SYSTEM`: `erp-vmess-xray` and `erp-vmess-client`.

```bat
schtasks /Query /TN erp-vmess-xray /V /FO LIST
schtasks /Query /TN erp-vmess-client /V /FO LIST
schtasks /End  /TN erp-vmess-xray
schtasks /End  /TN erp-vmess-client
```

---

## What you get

After a successful run the installer prints:

```
erp server:      YOUR_SERVER_HOST:6000
erp remote port: 10086
Xray local:      127.0.0.1:10086
VMess UUID:      <uuid>
transport:       vmess + tcp + no TLS, erp raw

VMess link:
vmess://<base64…>
```

Import the `vmess://` link into any VMess-capable client. The node address is
your erp server host; the port is the `remote-port` you chose.

---

## Uninstall

**Linux (systemd):**

```sh
sudo systemctl disable --now xray.service erp-client.service
sudo rm -f /etc/systemd/system/xray.service /etc/systemd/system/erp-client.service
sudo systemctl daemon-reload
sudo rm -rf /usr/local/etc/xray /etc/erp /var/log/erp-vmess
sudo rm -f /usr/local/bin/xray /usr/local/bin/erp
```

**Linux (tmux):**

```sh
tmux kill-session -t erp-vmess-xray
tmux kill-session -t erp-vmess-client
rm -rf ~/.local/share/erp-vmess
```

**Windows (Administrator):**

```bat
schtasks /Delete /TN erp-vmess-xray /F
schtasks /Delete /TN erp-vmess-client /F
rmdir /s /q "%ProgramData%\erp-vmess"
```

---

## Notes & limitations

- VMess runs over **plain TCP with no TLS**; security relies on the erp tunnel
  and the VMess UUID. Use it accordingly.
- Architecture: **Linux x86_64** and **64-bit Windows** only (the upstream `erp`
  release has no Linux arm64 binary).
- The default token `19890604` is only a placeholder — set `--token` to match
  your own server.

## License

Provided as-is, for use with your own erp server. No warranty.
