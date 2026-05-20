# YubiHSM 2 — One-Time Setup

Installation and connector configuration. Read only when bootstrapping a new host. Routine operations do not need this file.

## SDK Install

Detect OS:

```bash
uname -s   # Linux or Darwin
```

### Linux (Debian/Ubuntu)

```bash
sudo dpkg -i \
  ./libyubihsm-usb1_*.deb \
  ./libyubihsm-http1_*.deb \
  ./libyubihsm1_*.deb \
  ./yubihsm-shell_*.deb \
  ./yubihsm-connector_*.deb
```

### Linux (RHEL/CentOS)

```bash
sudo yum install ./yubihsm-shell-*.rpm ./yubihsm-connector-*.rpm
```

### macOS

Install from the official YubiHSM SDK `.pkg` download (Yubico downloads page). The `.pkg` installs `yubihsm-shell`, `yubihsm-connector`, and the libraries to `/usr/local/`.

## udev Rules (Linux only)

Required so the connector daemon (or `libyubihsm-usb1` for direct USB) can claim the device without root.

```bash
sudo tee /etc/udev/rules.d/99-yubihsm2.rules <<'EOF'
ACTION!="add|change", GOTO="yubihsm2_end"
SUBSYSTEM=="usb", ATTRS{idVendor}=="1050", ATTRS{idProduct}=="0030", OWNER="yubihsm-connector"
LABEL="yubihsm2_end"
EOF
sudo udevadm control --reload-rules && sudo udevadm trigger
```

For USB-direct mode (no connector daemon), replace `OWNER="yubihsm-connector"` with `MODE="0660", GROUP="plugdev"` (or whichever group the operator user belongs to).

## Connector Daemon (HTTP transport)

Only needed when remote clients will talk to the HSM over HTTP/HTTPS. Skip entirely if everything runs locally and you use `yhusb://` direct transport.

Config file: `/etc/yubihsm-connector.yaml`

```yaml
listen: localhost:12345    # Change to 0.0.0.0:12345 for network access
serial: ""                 # Specify if multiple devices attached
syslog: false
cert: /etc/yubihsm-connector/cert.pem   # Optional — enables HTTPS
key:  /etc/yubihsm-connector/key.pem
```

Start and verify:

```bash
# systemd
sudo systemctl enable --now yubihsm-connector

# or run directly
yubihsm-connector -d

# verify reachable
curl -sf http://127.0.0.1:12345/connector/status
# Must contain: status=OK
```

For HTTPS connector, generate or provision a cert+key pair, set `cert:` / `key:` above, and clients pass `--cacert <ca.pem>` on every `yubihsm-shell` call.

## Direct USB (no daemon)

If only the host attached to the HSM ever needs to talk to it, skip the connector daemon entirely. `yubihsm-shell` calls `libyubihsm-usb1` directly when given `--connector yhusb://`.

Verify the device is enumerated:

```bash
# Linux
lsusb -d 1050:0030

# macOS
system_profiler SPUSBDataType | grep -A4 -i yubihsm
```

Then test:

```bash
yubihsm-shell --connector yhusb:// --authkey 1 -p password -a get-device-info
```

If multiple HSMs are plugged into the same host, disambiguate by serial:

```bash
yubihsm-shell --connector "yhusb://serial=0123456789" ...
```
