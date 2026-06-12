# OpenWrt IPQ Mesh AC

OpenWrt/ImmortalWrt based mesh AC + managed AP firmware for IPQ60XX devices.

This project is intentionally not fully decentralized in v0.1. It follows the
common AC/AP model:

- one router or OpenWrt node runs the AC component
- AP nodes run the agent component
- APs first pair over wired LAN, then keep a saved wireless backhaul config
- APs prefer wired backhaul when available and fall back to wireless backhaul
- APs keep their last applied config if the AC is offline

## Components

- `mesh-ac`: AC service, node database, config rendering, simple CGI API
- `mesh-agent`: AP-side discovery, registration, config pull, UCI apply
- `luci-app-mesh-ac`: LuCI page for AC settings and managed AP list

## Build Targets

- `IPQ60XX-MESH-AC`: AC firmware with LuCI AC app and agent tools
- `IPQ60XX-MESH-AP`: managed AP firmware with mesh agent

The build workflow is manual only to avoid burning GitHub Actions cache.

## First Use

1. Flash one device with the AC image.
2. Flash other devices with the AP image.
3. Connect an AP to the AC LAN with Ethernet.
4. Open LuCI on the AC and go to `Services -> Mesh AC`.
5. Configure SSID, password, mesh backhaul settings, KVR and DAWN options.
6. Confirm newly registered APs.
7. After config is applied, the AP can be unplugged and will use wireless
   backhaul. Reconnecting Ethernet should make it prefer wired backhaul again.

## Security Note

The MVP uses a shared pairing token stored in `/etc/config/mesh_ac` and
`/etc/config/mesh_agent`. Change it before real use. A later version should add
a pairing window and per-node credentials.

## Status

This is a v0.1 scaffold. It is designed to compile as OpenWrt packages and
provide a clear iteration point, not to be production-ready yet.
