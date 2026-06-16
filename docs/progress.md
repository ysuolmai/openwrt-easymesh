# OpenWrt EasyMesh Progress

Last updated: 2026-06-16
Repository: https://github.com/ysuolmai/openwrt-easymesh
Branch: `main`
Latest implementation commit: see `git log --oneline -1`.

## Current Snapshot - 2026-06-16

Repository: https://github.com/ysuolmai/openwrt-easymesh
Branch: `main`
Latest implementation commit: see `git log --oneline -1`.

Current direction:

- This is an AC + managed AP firmware project, not a decentralized per-router mesh plugin.
- AC owns the LuCI UI, global Wi-Fi/backhaul config, new-AP pairing gate, and config rendering.
- AP firmware includes LuCI with the shadcn theme for local access, but no EasyMesh management app; it runs `easymesh-agent`.
- AP first boot enters a safe bridge-only state: local DHCP is disabled, WAN/LAN are treated as the same L2 access side, and default OpenWrt/ImmortalWrt LAN AP SSIDs are removed.
- When `pairing_enabled=1`, a new AP registers and immediately pulls config from AC, creating client AP SSIDs plus 802.11s backhaul.
- When `pairing_enabled=0`, unknown APs cannot register; known APs can keep updating `last_seen` and pulling config.
- AC can run in `Bridge` mode or `Gateway` mode. AP always behaves as a bridge node.
- `easymesh-controller` can run as a controller-only plugin on no-wifi hardware. `easymesh-local-member` adds AC local mesh support for Wi-Fi hardware.
- IPQ managed AP images include `/etc/modules.d/ath11k` with `nss_offload=0` in the rootfs, so the module starts in mesh-compatible mode on first boot.
- AC defaults to controller/router-only mode with ath11k NSS offload enabled. When `local_member=1` and local Wi-Fi is detected, AC becomes a local mesh member and ath11k NSS offload is disabled; if ath11k is already loaded, the firmware schedules one reboot and resumes local apply after boot.

Latest implemented behavior:

- LuCI EasyMesh page now initializes form fields from real system UCI state, not just `/etc/config/easymesh` desired values.
- `Network mode` selector is initialized from actual active state when the device is clearly in bridge/gateway mode, so it should not show stale `bridge` while the box is actually still gateway.
- 2.4 GHz and 5 GHz client SSIDs are now separate fields: `ssid_2g` and `ssid_5g`.
- Legacy `ssid` remains as fallback for upgrades.
- 2.4 GHz / 5 GHz channel and htmode are LuCI dropdowns instead of free text.
- AC JSON config and AP apply logic both support split-band SSIDs.
- New read-only helper: `/usr/sbin/easymesh-status`.
- Managed APs now use automatic registration. LuCI shows online/offline and last seen time.
- AP agent skips reapplying an unchanged AC config only after local wireless state matches the desired mesh SSIDs/backhaul; stale or partially applied local state is repaired automatically.
- MT7981 radio detection now trusts explicit `band` first and no longer treats all `HE*` radios as 5 GHz, so 2.4 GHz 802.11ax radios keep the 2.4 GHz channel/htmode.
- 802.11s mesh backhaul is attached to `batman-adv` by real mesh interface name, not by the UCI alias `@mesh_backhaul`.
- AP images now include LuCI and `ysuolmai/luci-theme-shadcn`, matching AC theme source.
- Workflow release files are prefixed with the config target, for example `IPQ60XX-MESH-AC-*` and `IPQ60XX-MESH-AP-*`.
- LuCI uses runtime Wi-Fi detection from `easymesh-status`: no-wifi/controller-only AC hides local mesh member controls and active local Wi-Fi state.

Recent commits:

```text
7510bae Show active mesh state in LuCI
d4481f3 Add bridge and gateway mesh network modes
3094d6f Unify mesh AC apply action
b681b1a Use named wireless sections
3585c0a Fix local mesh apply
79f1346 Add OpenWrt build cache
7d40a17 Use personal shadcn theme fork
521e68c Improve home mesh onboarding
```

Validation run locally for latest commit:

```sh
sh -n package/easymesh-local-member/files/usr/sbin/easymesh-apply-local package/easymesh-controller/files/usr/sbin/easymesh-status package/easymesh-controller/files/www/cgi-bin/easymesh package/easymesh-agent/files/usr/sbin/easymesh-agent-apply
node --check package/luci-app-easymesh/htdocs/luci-static/resources/view/easymesh/overview.js
python3 -m json.tool package/luci-app-easymesh/root/usr/share/rpcd/acl.d/luci-app-easymesh.json
git diff --check
```

Hardware status:

- Latest code is pushed, but this exact commit still needs a new firmware build and router flash test.
- Previous firmware may not include the LuCI active-state table or split-band SSID fields.
- Do not assume a router already has current behavior unless it was built from the latest `main`.

## AP Direct Debug Notes - No SSID After Connecting to AC

Short answer:

- If the AP is unknown and `Allow pairing` is off on the AC, no client SSID on `Network -> Wireless` is expected.
- After automatic registration and successful config pull/apply, seeing no AP SSID is not expected.

Expected AP phases:

1. Fresh AP boot before config:
   - uci-defaults runs `/usr/sbin/easymesh-agent-apply --network-only`.
   - Default LAN AP SSIDs are deleted.
   - LAN DHCP is disabled.
   - WAN/LAN are bridged for safe access.
   - `Network -> Wireless` may show no client SSID. This is normal.

2. Unknown AP while pairing is disabled:
   - `easymesh-agent` keeps trying to register.
   - AC returns `pairing-disabled`.
   - AP should still not advertise client SSIDs.

3. AP registered and config applied:
   - AP should create `wireless.mesh_ap_2g` and/or `wireless.mesh_ap_5g` if radios are detected.
   - AP should create `wireless.mesh_backhaul` for 802.11s.
   - Client SSIDs should appear on the AP.

Commands to run on the AP while directly connected:

```sh
logread | grep easymesh-agent
/etc/init.d/easymesh-agent status
uci show easymesh_agent
uci show wireless | grep -E 'mesh_ap|mesh_backhaul|ssid|mesh_id|device|mode|disabled'
uci show network | grep -E 'lan|wan|br_lan|bat0|batmesh'
cat /etc/easymesh-agent/config.json 2>/dev/null
cat /etc/easymesh-agent/ac_url 2>/dev/null
```

Useful connectivity checks from AP:

```sh
ip route
ubus call umdns browse
curl -fsS http://172.28.1.114/cgi-bin/easymesh
```

If AC is not discovered automatically, pin it temporarily on AP:

```sh
uci set easymesh_agent.main.ac_url='http://172.28.1.114/cgi-bin/easymesh'
uci set easymesh_agent.main.ac_discovery='static'
uci commit easymesh_agent
/etc/init.d/easymesh-agent restart
```

After registration, force one local apply cycle on AP if `/etc/easymesh-agent/config.json` exists:

```sh
/usr/sbin/easymesh-agent-apply /etc/easymesh-agent/config.json
wifi reload
```

What to look for:

- If `config.json` is missing, check AC discovery, `Allow pairing`, and AP registration.
- If `config.json` exists but `wireless.mesh_ap_2g` / `wireless.mesh_ap_5g` are missing, radio detection or apply likely failed.
- If wireless sections exist but are disabled or no SSID is broadcast, check `wifi status` and driver/radio errors in `logread`.
- If only `mesh_backhaul` exists, the AP may have found only the configured backhaul radio or failed to find client radios.

## Current Files To Inspect First

```text
package/easymesh-agent/files/etc/uci-defaults/90-easymesh-agent-enable
package/easymesh-agent/files/usr/sbin/easymesh-agent
package/easymesh-agent/files/usr/sbin/easymesh-agent-apply
package/easymesh-controller/files/www/cgi-bin/easymesh
package/easymesh-controller/files/usr/sbin/easymesh-status
package/easymesh-local-member/files/usr/sbin/easymesh-apply-local
package/luci-app-easymesh/htdocs/luci-static/resources/view/easymesh/overview.js
```

## Goal

Build an OpenWrt / ImmortalWrt based mesh system using an AC + managed AP model similar to commercial AC/AP systems. The initial platform was IPQ60XX; MT7981 support is being added through a separate workflow.

Current product direction:

- AC provides LuCI management UI and global mesh configuration.
- AP firmware runs an agent and registers to AC after it is connected to the AC LAN.
- AC accepts new APs automatically while pairing is enabled, then pushes Wi-Fi/backhaul/roaming config.
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
2.4 GHz / 5 GHz client Wi-Fi SSID
```

Important design decision:

- AC can be the DHCP/NAT gateway, but it does not have to be.
- AP nodes should not default to DHCP/NAT/gateway behavior.
- AP nodes are intended to work as dumb managed APs.
- AC can also be a local mesh member when the AC hardware has Wi-Fi.
- AC local mesh member mode must preserve AC LAN/WAN/DHCP/firewall settings.

## Implemented Packages

### `easymesh-controller`

Path: `package/easymesh-controller/`

Provides:

- `/etc/config/easymesh`
- `/etc/init.d/easymesh-controller`
- `/www/cgi-bin/easymesh`
- `/usr/sbin/easymesh-list`
- `/usr/sbin/easymesh-status`

Current behavior:

- Stores global SSID, mesh backhaul, KVR and DAWN settings.
- Receives AP registration through CGI endpoint `/cgi-bin/easymesh/register`.
- Stores one JSON file per AP under `/etc/easymesh/nodes/`.
- New APs are accepted automatically while `pairing_enabled=1`.
- When `pairing_enabled=0`, unknown APs are rejected and known APs can continue to update `last_seen`.
- Known APs can fetch rendered config through `/cgi-bin/easymesh/config`.
- Does not depend on Wi-Fi, `easymesh-agent`, `batman-adv`, or DAWN. This package can be reused as a no-wifi/controller-only AC plugin.

Security status:

- Home-use pairing is tokenless: `pairing_enabled=1` allows new AP registration, while known APs can continue to fetch config after pairing is disabled.
- Future improvement can add a timed pairing window or per-AP credentials if stronger security is needed.

### `easymesh-local-member`

Path: `package/easymesh-local-member/`

Provides:

- `/usr/sbin/easymesh-apply-local`
- `/etc/uci-defaults/91-easymesh-local-member-enable`

Current behavior:

- Optional add-on for AC hardware with local Wi-Fi.
- Depends on `easymesh-agent`, so it can reuse the same apply helper as APs.
- Detects local Wi-Fi by checking `/etc/config/wireless`, `/sys/class/ieee80211`, or `iw phy`.
- Skips local apply on no-wifi hardware even if installed.
- Keeps ath11k NSS offload enabled while `local_member=0`; disables it while `local_member=1`, scheduling one reboot if ath11k was already loaded.

### `easymesh-agent`

Path: `package/easymesh-agent/`

Provides:

- `/etc/config/easymesh_agent`
- `/etc/init.d/easymesh-agent`
- `/usr/sbin/easymesh-agent`
- `/usr/sbin/easymesh-agent-apply`

Current behavior:

- Registers to configured AC URL.
- Default AC URL is `http://192.168.50.1/cgi-bin/easymesh`.
- Pulls AC config after registration.
- Applies OpenWrt UCI settings for:
  - 2.4 GHz / 5 GHz client AP SSID
  - 802.11k/v/r
  - 802.11s mesh backhaul
  - `batman-adv`
  - DAWN
- Supports `--preserve-lan` for AC local mesh member mode.
- The normal `easymesh-agent` procd service is disabled on AC images when `/etc/config/easymesh` exists.

Known limitation:

- AC auto-discovery now uses mDNS with gateway/default fallback (see "AC discovery" below).
- AP can still pin a specific AC by setting `easymesh_agent.main.ac_url`.

### `luci-app-easymesh`

Path: `package/luci-app-easymesh/`

Provides LuCI page:

```text
Services -> EasyMesh
```

Current UI:

- AC enable flag
- pairing enable flag
- AC local mesh member flag
- client SSID/password
- country
- mobility domain
- 802.11k/v/r flags
- mesh ID/key
- backhaul band/channel/mode
- DAWN options
- managed AP table
- online/offline and last seen display

## Build Targets

Current configs:

```text
configs/IPQ60XX-MESH-AC.txt
configs/IPQ60XX-MESH-AP.txt
configs/MT7981-MESH-AC.txt
configs/MT7981-MESH-AP.txt
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

Current MT7981 device whitelist follows upstream `OpenWRT-CI/Scripts/diy.sh`:

```text
sx_7981r128
nokia_ea0326gmp
cmcc_rax3000m
```

`nokia_ea0326gmp` and `cmcc_rax3000m` are source profiles in `VIKINGYFY/immortalwrt` `owrt`. `sx_7981r128` is injected during `scripts/prepare-openwrt.sh`, using the upstream DTS/profile mechanism from OpenWRT-CI.

## GitHub Actions

Workflows:

```text
.github/workflows/build.yml
.github/workflows/build-mtk.yml
.github/workflows/clean.yml
```

Current behavior:

- Manual `workflow_dispatch` only.
- `Build IPQ EasyMesh` runs both IPQ AC and AP builds using matrix:
  - `IPQ60XX-MESH-AC`
  - `IPQ60XX-MESH-AP`
- `Build MTK EasyMesh` runs both MT7981 AC and AP builds using matrix:
  - `MT7981-MESH-AC`
  - `MT7981-MESH-AP`
- Inputs:
  - `source_repo`
  - `source_branch` (`main` for IPQ, `owrt` for MTK)
  - `test_config_only`
- Default source repo is `https://github.com/VIKINGYFY/immortalwrt.git`.
- AC and AP images clone `ysuolmai/luci-theme-shadcn` during prepare and select `CONFIG_PACKAGE_luci-theme-shadcn=y`.
- This repo's AC targets select `easymesh-local-member` for full AC behavior. Other projects can select only `easymesh-controller` + `luci-app-easymesh` for a no-wifi/controller-only AC plugin.
- Build cache is enabled for non-config-only runs, following upstream OpenWRT-CI: `.ccache`, `staging_dir/host*`, and `staging_dir/tool*` are cached and toolchain stamp files are refreshed after restore.
- `config_name` manual selection was removed.
- After `make defconfig`, workflow runs `scripts/check-openwrt-config.sh` to verify required device profiles, Wi-Fi driver/firmware symbols, source-side support files, KVR-capable `wpad-openssl`, DAWN, uMDNS, `batman-adv`, and the shadcn LuCI theme on AC/AP images.
- Full firmware release collection follows the upstream OpenWRT-CI packaging style by collecting files from `bin/targets` while pruning package repositories. This keeps IPQ NAND factory outputs such as Redmi AX5 and ZN M2 `factory.ubi` without relying on a filename-extension whitelist.
- `Clean Artifacts` deletes completed workflow runs, deletes config-only releases, and keeps only the latest full firmware release per config target.

Validation already done:

- Matrix workflow was triggered with `test_config_only=true`.
- Both AC and AP jobs passed through `make defconfig`.
- This confirms package injection and config selection work at defconfig level.

Recent successful config-only releases:

```text
IPQ60XX-MESH-AC-ea53cef-9
IPQ60XX-MESH-AP-ea53cef-9
```

Recent successful config-only workflow run:

```text
https://github.com/ysuolmai/openwrt-easymesh/actions/runs/27468404699
```

Full firmware build has not yet been run after the latest changes.

## Recently Implemented: AC Local Member

User asked whether the AC itself can also be a mesh member if the AC hardware has Wi-Fi.

Implemented design:

- `/etc/config/easymesh` has `option local_member '0'` by default.
- LuCI shows `Enable AC local mesh member` only when local Wi-Fi is detected and `/usr/sbin/easymesh-apply-local` is installed.
- `/usr/sbin/easymesh-apply-local` renders AC config into the same JSON structure used by managed APs.
- It calls `/usr/sbin/easymesh-agent-apply --local-ac /tmp/easymesh-local-config.json` when local member mode is enabled.
- `easymesh-agent-apply --local-ac` applies Wi-Fi APs, 802.11s backhaul, `batman-adv`, and DAWN while preserving AC LAN/WAN/DHCP/firewall behavior. It removes existing LAN AP Wi-Fi interfaces such as the default `ImmortalWrt` SSID so the AC only advertises the configured mesh client SSID.
- Normal managed AP agent service is disabled on AC images so AC does not register to itself as a normal AP.
- Local mesh member mode is explicit through LuCI or `/usr/sbin/easymesh-apply-local`; first boot does not broadcast placeholder Wi-Fi credentials automatically.
- IPQ AP builds write `ath11k nss_offload=0 frame_mode=2` into the image rootfs before build, so AP first boot does not depend on uci-defaults racing the driver load order.
- AC keeps ath11k NSS offload enabled while `local_member=0`, and disables it while `local_member=1` because ath11k NSS offload breaks 802.11s mesh point interfaces on this target. If the ath11k module was already loaded, the system schedules one reboot so `nss_offload=0` is applied from module load time, then resumes local mesh apply.

Important safety rule:

```text
AC local member mode must not rewrite network.lan.proto, network.lan.ipaddr, network.wan, firewall zones, or DHCP server settings.
```

Validation done locally:

```sh
bash -n package/easymesh-agent/files/usr/sbin/easymesh-agent-apply
bash -n package/easymesh-local-member/files/usr/sbin/easymesh-apply-local
bash -n package/easymesh-agent/files/etc/init.d/easymesh-agent
bash -n package/easymesh-agent/files/etc/uci-defaults/90-easymesh-agent-enable
bash -n package/easymesh-controller/files/etc/uci-defaults/90-easymesh-controller-enable
bash -n scripts/check-openwrt-config.sh
git diff --check
```

## Current MTK Work

Implemented locally for MT7981 support:

- Added `configs/MT7981-MESH-AC.txt` and `configs/MT7981-MESH-AP.txt`.
- Added `.github/workflows/build-mtk.yml` with default source branch `owrt`, matching upstream `MTK-ALL.yml`.
- Added MTK whitelist filtering in `scripts/prepare-openwrt.sh`: `sx_7981r128`, `nokia_ea0326gmp`, `cmcc_rax3000m`.
- Added `target/mediatek/dts/mt7981b-sx-7981r128.dts`.
- Added SX 7981R128 injection into `target/linux/mediatek/image/filogic.mk`, `board.d/02_network`, and a first-boot uci-defaults script.
- Updated `scripts/check-openwrt-config.sh` with separate IPQ and MTK validation paths.

Validation still needed after push:

```sh
gh workflow run build-mtk.yml -R ysuolmai/openwrt-easymesh -f test_config_only=true
```

## Important Known Issues / TODO

### 1. Wired-first / wireless-fallback

Current state: both backhauls coexist. The wireless 802.11s link is a
batman-adv hardif (`batmesh` -> `bat0`), `bat0` is bridged into `br-lan`, and
the Ethernet backhaul port is also a `br-lan` member. Loops are handled by
batman-adv `bridge_loop_avoidance` (`bat0.bridge_loop_avoidance=1`). `Prefer wired backhaul` now enables `easymesh-backhaul`, which monitors wired bridge-port carrier changes, flushes local bridge FDB/neighbor state, and sends LAN renew/ping traffic to accelerate upstream relearning. The wireless mesh remains attached to batman-adv at all times.

A previous attempt added a watchdog that detached the wireless mesh from
batman-adv (`batctl if del`) whenever a wire was up and no mesh peer was
present. It was removed because it is both harmful and pointless:

- A wired AP whose downstream wireless AP goes offline drops its mesh peer
  count to zero and detaches its wireless backhaul. When the downstream AP
  returns it cannot re-peer (the detached mesh netdev stops beaconing on many
  drivers), and the wired AP only re-attaches after it sees the peer — a
  deadlock. This is the classic commercial-mesh "B can't rejoin after a
  reboot" failure.
- The only case where it actually detaches (one wired AP, zero mesh peers) is
  precisely the case with no loop to avoid. In the real loop case (two wired
  APs that also mesh wirelessly) it sees a peer and does nothing.

Correct fix (future, must be validated on hardware): make the Ethernet
backhaul a batman-adv hardif too (instead of bridging eth directly into
br-lan), and bias batman toward wired with `hop_penalty` on the wireless
hardif. Then batman natively prefers wired, and node leave/rejoin is handled by
batman without any external watchdog or deadlock.

### 2. AC discovery via mDNS (implemented)

AP agents resolve the AC through `ac_discovery` mode (`auto` by default):

1. explicit `easymesh_agent.main.ac_url` if set and reachable
2. mDNS service `_easymesh._tcp` advertised by the AC (umdns)
3. default-gateway probe (AC acting as router)
4. last known good URL (cached at `/etc/easymesh-agent/ac_url`)
5. hardcoded `192.168.50.1` as final fallback

Each candidate is validated by probing the AC root endpoint for
`{"service":"easymesh"}` before use, and the resolved AC is reused until it
becomes unreachable. AC side advertises through `/etc/umdns/easymesh.json` and
enables `umdns` in its uci-defaults.

Possible later improvement:

- DHCP option based hint
- QR/token based onboarding

### 3. Pairing security is intentionally simple

For home use, AP onboarding no longer uses a shared token. New APs can register only while `pairing_enabled` is on. Known APs can keep pulling config after pairing is turned off.

Future, if stronger onboarding is needed:

- timed pairing window
- per-node key
- certificate or signed token
- reject unknown AP after pairing window closes with clearer LuCI messaging

### 4. Full firmware compile not verified

Only `test_config_only=true` was validated before AC-local member and required-package checks.

Next config-only workflow should be run after pushing current changes, including both IPQ and MTK if possible. Full build should be run manually because it consumes more GitHub Actions time.

## Useful Commands

Check local repo:

```sh
git status --short --branch
git log --oneline --decorate -5
```

Run config-only workflow:

```sh
gh workflow run build.yml -R ysuolmai/openwrt-easymesh -f test_config_only=true
gh workflow run build-mtk.yml -R ysuolmai/openwrt-easymesh -f test_config_only=true
```

Watch a run:

```sh
gh run watch <run-id> -R ysuolmai/openwrt-easymesh --exit-status
```

List releases:

```sh
gh release list -R ysuolmai/openwrt-easymesh --limit 8
```

## Handoff Notes

Remote `main` contains the stable AC/AP scaffold, AC-local member support, IPQ config validation, and after this work should contain MT7981 workflow/config support. MTK full firmware builds still need real CI and hardware validation.
