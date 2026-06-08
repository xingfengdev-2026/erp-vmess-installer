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

Use the same command for both Linux run modes. If you run it from a **root**
shell, the installer uses **systemd**. If you run it as a normal user, it uses
**tmux** under `~/.local/share/erp-vmess`.

```sh
curl -fsSL https://raw.githubusercontent.com/xingfengdev-2026/erp-vmess-installer/main/install_vmess_erp.sh | bash -s -- --server YOUR_SERVER_HOST:6000 --token 19890604 --remote-port 10086
```

Replace the server address, token, and port with your own values. Non-root mode
needs `tmux` available on the machine.

### Windows — elevated PowerShell one-liner

Open **PowerShell as Administrator**, then:

```powershell
$bat = "$env:TEMP\install_vmess_erp_windows.bat"; Invoke-WebRequest -UseBasicParsing -Uri https://raw.githubusercontent.com/xingfengdev-2026/erp-vmess-installer/main/install_vmess_erp_windows.bat -OutFile $bat; & $bat --server YOUR_SERVER_HOST:6000 --token 19890604 --remote-port 10088
```

When it finishes, copy the printed `vmess://` link into your client
(v2rayN, v2rayNG, etc.).

---

## Download then run (recommended if you want to read it first)

### Linux

```sh
curl -fsSL -o install_vmess_erp.sh https://raw.githubusercontent.com/xingfengdev-2026/erp-vmess-installer/main/install_vmess_erp.sh
chmod +x install_vmess_erp.sh

# Interactive — prompts for every value:
./install_vmess_erp.sh --interactive

# Or non-interactive:
./install_vmess_erp.sh --server YOUR_SERVER_HOST:6000 --token 19890604 --remote-port 10086
```

Run these commands from a root shell for systemd mode, or from a normal user
shell for tmux mode.

### Windows

Download `install_vmess_erp_windows.bat`, then in an **Administrator** prompt:

```bat
install_vmess_erp_windows.bat --interactive
:: or
install_vmess_erp_windows.bat --server YOUR_SERVER_HOST:6000 --token 19890604 --remote-port 10088
```

---

## Options

Both installers accept the same core options. Every option also has a matching
environment variable.

| Flag | Env var | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `--server ADDR` | `ERP_SERVER_ADDR` | **yes** | — | erp server control address `host:port`. |
| `--remote-port PORT` | `ERP_REMOTE_PORT` | **yes** | — | Public TCP port opened on the erp server for this node. |
| `--token TOKEN` | `ERP_TOKEN` | **yes** | — | erp shared token. Must match your server. |
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

### GitHub accelerator

If GitHub releases are slow or blocked on your network, point the installer at a
GitHub accelerator with `--github-proxy-prefix`.

> **Only [`github-proxy`](https://github.com/xingfengdev-2026/github-proxy)-style
> accelerators are supported.** That is, a proxy where you request
> `http(s)://<your-server>/<full-GitHub-URL>` and the server fetches the target
> for you (following the 302 redirects that release assets use). Deploy your own
> instance from <https://github.com/xingfengdev-2026/github-proxy> and pass its
> base URL — e.g. `--github-proxy-prefix https://proxy.example.com:8080`. The
> installer prepends that prefix to every GitHub download URL. Leave it unset to
> download from GitHub directly.

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

**Linux (systemd, root shell):**

```sh
systemctl disable --now xray.service erp-client.service
rm -f /etc/systemd/system/xray.service /etc/systemd/system/erp-client.service
systemctl daemon-reload
rm -rf /usr/local/etc/xray /etc/erp /var/log/erp-vmess
rm -f /usr/local/bin/xray /usr/local/bin/erp
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
- The example token `19890604` is only a placeholder — set `--token` to match
  your own server. The installer has no default token.

## License

Provided as-is, for use with your own erp server. No warranty.
