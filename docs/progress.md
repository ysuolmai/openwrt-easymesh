# OpenWrt IPQ Mesh AC Progress

Last updated: 2026-06-13
Repository: https://github.com/ysuolmai/openwrt-ipq-mesh
Branch: `main`
Latest pushed commit before current work: `e4e4698 Add project handoff progress`

## Goal

Build an OpenWrt / ImmortalWrt based IPQ60XX mesh system using an AC + managed AP model similar to commercial AC/AP systems.

Current product direction:

- AC provides LuCI management UI and global mesh configuration.
- AP firmware runs an agent and registers to AC after it is connected to the AC LAN.
- AC approves APs and pushes Wi-Fi/backhaul/roaming config.
- AP keeps last config and should continue working if AC is offline.
- First pairing is intended to happen over Ethernet.
- After pairing, AP can use wireless 802.11s backhaul.
- When Ethernet is plugged in again, the intended behavior is wired backhaul first and wireless as fallback.

This replaced the earlier fully decentralized idea. DAWN is still used, but as a roaming/client steering component rather than the main control plane.

## Current Architecture

```text
Main router / AC
    |
    | Ethernet LAN, pairing and preferred backhaul
    |
Managed AP 1  )) 802.11s wireless backhaul ))  Managed AP 2
    |
Client Wi-Fi SSID
```

Important design decision:

- AC can be the DHCP/NAT gateway, but it does not have to be.
- AP nodes should not default to DHCP/NAT/gateway behavior.
- AP nodes are intended to work as dumb managed APs.
- AC can also be a local mesh member when the AC hardware has Wi-Fi.
- AC local mesh member mode must preserve AC LAN/WAN/DHCP/firewall settings.

## Implemented Packages

### `mesh-ac`

Path: `package/mesh-ac/`

Provides:

- `/etc/config/mesh_ac`
- `/etc/init.d/mesh-ac`
- `/www/cgi-bin/mesh-ac`
- `/usr/sbin/mesh-ac-approve`
- `/usr/sbin/mesh-ac-list`
- `/usr/sbin/mesh-ac-apply-local`

Current behavior:

- Stores global SSID, mesh backhaul, KVR and DAWN settings.
- Receives AP registration through CGI endpoint `/cgi-bin/mesh-ac/register`.
- Stores one JSON file per AP under `/etc/mesh-ac/nodes/`.
- APs are unapproved by default.
- `mesh-ac-approve <node-id>` marks AP as approved.
- Approved APs can fetch rendered config through `/cgi-bin/mesh-ac/config`.
- `mesh-ac-apply-local` renders local AC config to JSON and calls `mesh-agent-apply --preserve-lan`.
- AC package depends on `mesh-agent` so the shared apply helper is present.

Security status:

- MVP uses a shared pairing token.
- Token defaults are placeholders and must be changed before real use.
- Future improvement should add pairing window and per-AP credentials.

### `mesh-agent`

Path: `package/mesh-agent/`

Provides:

- `/etc/config/mesh_agent`
- `/etc/init.d/mesh-agent`
- `/usr/sbin/mesh-agent`
- `/usr/sbin/mesh-agent-apply`

Current behavior:

- Registers to configured AC URL.
- Default AC URL is `http://192.168.50.1/cgi-bin/mesh-ac`.
- Pulls AC config after approval.
- Applies OpenWrt UCI settings for:
  - client AP SSID
  - 802.11k/v/r
  - 802.11s mesh backhaul
  - `batman-adv`
  - DAWN
- Supports `--preserve-lan` for AC local mesh member mode.
- The normal `mesh-agent` procd service is disabled on AC images when `/etc/config/mesh_ac` exists.

Known limitation:

- AC auto-discovery is not implemented yet.
- AP needs `mesh_agent.main.ac_url` changed manually if AC is not `192.168.50.1`.

### `luci-app-mesh-ac`

Path: `package/luci-app-mesh-ac/`

Provides LuCI page:

```text
Services -> Mesh AC
```

Current UI:

- AC enable flag
- pairing enable flag
- AC local mesh member flag
- local apply button
- pairing token
- client SSID/password
- country
- mobility domain
- 802.11k/v/r flags
- mesh ID/key
- backhaul band/channel/mode
- DAWN options
- managed AP table
- approve button

## Build Targets

Current configs:

```text
configs/IPQ60XX-MESH-AC.txt
configs/IPQ60XX-MESH-AP.txt
```

Current supported IPQ60XX device entries:

```text
redmi_ax5
redmi_ax5-jdcloud
jdcloud_re-ss-01
qihoo_360v6
zn_m2
```

`zn_m2` is supported through the VIKINGYFY/immortalwrt fork profile and `ipq-wifi-zn_m2` package.

## GitHub Actions

Workflow:

```text
.github/workflows/build.yml
```

Current behavior:

- Manual `workflow_dispatch` only.
- One trigger runs both AC and AP builds using matrix:
  - `IPQ60XX-MESH-AC`
  - `IPQ60XX-MESH-AP`
- Inputs:
  - `source_repo`
  - `source_branch` (default `main`)
  - `test_config_only`
- Default source repo is `https://github.com/VIKINGYFY/immortalwrt.git` because it contains `redmi_ax5`, `redmi_ax5-jdcloud`, and `zn_m2` profiles.
- `config_name` manual selection was removed.
- After `make defconfig`, workflow runs `scripts/check-openwrt-config.sh` to verify required device profiles, Wi-Fi driver/firmware/BDF packages, KVR-capable `wpad-openssl`, DAWN, uMDNS, and `batman-adv` packages.

Validation already done:

- Matrix workflow was triggered with `test_config_only=true`.
- Both AC and AP jobs passed through `make defconfig`.
- This confirms package injection and config selection work at defconfig level.

Recent successful config-only releases:

```text
IPQ60XX-MESH-AC-f95f557-5
IPQ60XX-MESH-AP-f95f557-5
```

Older successful config-only releases also exist:

```text
IPQ60XX-MESH-AC-f95f557-4
IPQ60XX-MESH-AP-f95f557-4
IPQ60XX-MESH-AC-f95f557-1
IPQ60XX-MESH-AP-f95f557-2
```

Full firmware build has not yet been run after the latest changes.

## Current User Request Implemented Locally

User asked whether the AC itself can also be a mesh member if the AC hardware has Wi-Fi.

Implemented design:

- `/etc/config/mesh_ac` has `option local_member '1'`.
- LuCI has `Enable AC local mesh member` and `Apply local mesh config` controls.
- `/usr/sbin/mesh-ac-apply-local` renders AC config into the same JSON structure used by managed APs.
- It calls `/usr/sbin/mesh-agent-apply --preserve-lan /tmp/mesh-ac-local-config.json`.
- `mesh-agent-apply --preserve-lan` applies Wi-Fi APs, 802.11s backhaul, `batman-adv`, and DAWN while preserving AC LAN/WAN/DHCP/firewall behavior.
- Normal managed AP agent service is disabled on AC images so AC does not register to itself as a normal AP.
- Local apply is explicit through LuCI or `/usr/sbin/mesh-ac-apply-local`; first boot does not broadcast placeholder Wi-Fi credentials automatically.

Important safety rule:

```text
AC local member mode must not rewrite network.lan.proto, network.lan.ipaddr, network.wan, firewall zones, or DHCP server settings.
```

Validation done locally:

```sh
bash -n package/mesh-agent/files/usr/sbin/mesh-agent-apply
bash -n package/mesh-ac/files/usr/sbin/mesh-ac-apply-local
bash -n package/mesh-agent/files/etc/init.d/mesh-agent
bash -n package/mesh-agent/files/etc/uci-defaults/90-mesh-agent-enable
bash -n package/mesh-ac/files/etc/uci-defaults/90-mesh-ac-enable
bash -n scripts/check-openwrt-config.sh
git diff --check
```

## Important Known Issues / TODO

### 1. Wired-first / wireless-fallback is not fully implemented

Current code prepares wireless mesh and `batman-adv`, but there is no mature watchdog yet.

Need a watchdog that:

- checks Ethernet carrier / default route / AC reachability
- prefers wired backhaul when available
- falls back to 802.11s when wire is removed
- avoids layer-2 loops

### 2. AC discovery is not implemented

Current AP agent default:

```text
http://192.168.50.1/cgi-bin/mesh-ac
```

Need one of:

- uMDNS service discovery
- DHCP option
- broadcast discovery
- QR/token based onboarding

### 3. Pairing security is primitive

Current shared token is only MVP-level.

Future:

- pairing window
- per-node key
- certificate or signed token
- reject unknown AP after pairing window closes

### 4. Full firmware compile not verified

Only `test_config_only=true` was validated before AC-local member and required-package checks.

Next config-only workflow should be run after pushing current changes. Full build should be run manually because it consumes more GitHub Actions time.

## Useful Commands

Check local repo:

```sh
git status --short --branch
git log --oneline --decorate -5
```

Run config-only workflow:

```sh
gh workflow run build.yml -R ysuolmai/openwrt-ipq-mesh -f test_config_only=true
```

Watch a run:

```sh
gh run watch <run-id> -R ysuolmai/openwrt-ipq-mesh --exit-status
```

List releases:

```sh
gh release list -R ysuolmai/openwrt-ipq-mesh --limit 8
```

## Handoff Notes

Remote `main` currently contains stable scaffold and validated matrix config workflow.

Local workspace at handoff has WIP changes for AC-local member support that are intentionally not pushed unless the next agent chooses to complete and validate them.

If continuing from GitHub only, start from commit:

```text
087a4e1 Build AC and AP targets together
```

Then implement AC local mesh member mode following the section above.
