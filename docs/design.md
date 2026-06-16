# Design

## v0.1 Topology

```text
Main router / AC
        |
     Ethernet
        |
Managed AP 1  )) 802.11s fallback ))  Managed AP 2
```

The AC can be the main router, but it does not have to be. It only needs to be
reachable by AP agents during pairing and config pulls.

## AC Responsibilities

- store global Wi-Fi, backhaul, KVR and DAWN settings
- receive AP registration
- accept new AP registration while pairing is enabled
- render AP config as JSON
- provide LuCI UI

## AP Agent Responsibilities

- register with AC while pairing is enabled
- pull config after registration
- apply OpenWrt UCI wireless/network/DAWN settings
- keep last config locally

## Backhaul Policy

v0.1 prepares both:

- Ethernet LAN path
- 802.11s wireless backhaul over `batman-adv`

The intended policy is wired-first and wireless-fallback. A later watchdog will
make this explicit by checking Ethernet carrier and adjusting active backhaul.
