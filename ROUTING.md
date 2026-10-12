# Routing development

The default remains full VPN. In Settings, console, menu, and routing themes
are independent. The Routes page supports service recognition, manual domains,
IP/CIDR rules, daily catalog updates, manual refresh, and JSON import/export.
Import/export includes no VPN profiles or keys.

Rules mode runs a separate TUN core in front of AmneziaWG. DNS fake addresses
preserve each destination name per flow, instead of changing a global host route
for a shared CDN address. Domain rules use the most specific suffix; equally
specific VPN rules take priority. Static IP rules are the fallback. Identified
unlisted domains and opaque connections go direct. Only matched VPN domains
or IP ranges use VPN. Service lists may mix domains and IPv4/IPv6 CIDRs; these
are stored separately, including migration of old mixed baseDomains values.
Manual additions are preserved when the service base is refreshed.

Browser DoH does not automatically expose destination names. Readable TLS/QUIC
names can be classified; ECH without a local DNS mapping can only match IP
rules. The presence of the ECH extension is treated as opaque, including GREASE:
the outer server name cannot identify the inner destination. With the requested
direct default, a domain-only VPN rule cannot cover an opaque DoH/ECH flow.
Use the application's DNS for domain classification, or IP ranges for those
flows. Do not claim fail-closed coverage of a selected domain that is hidden.

The routing TUN advertises IPv6 only when the AWG profile has an IPv6 address.
Advertising IPv6 for an IPv4-only profile made Chrome choose endpoints that
the VPN could not reach. Dual-stack profiles also receive a scoped IPv6 AWG
route. Actual dual-stack traffic still needs a profile and a live test.

DNS real-address cache follows DNS expiry, capped at six hours in the patched
core. The earlier host-route cache prototype is not the active mechanism. Persistent fake addresses map
names, not permanent external server IP routes. No user certificates are installed.

The helper creates a scoped AWG route and binds core outbounds to either the
physical interface or AWG. PF allows the root-owned core's physical sockets;
ordinary application traffic enters the routing TUN. Home/Off releases PF before
stopping both tunnels. An unavailable VPN outbound must not fall back to direct.

Build:

```sh
bash scripts/prepare-routing-core.sh # Go 1.26.9
bash scripts/test.sh
bash scripts/build.sh
bash scripts/smoke.sh
```

Explicit live diagnostic, only with an idle installed helper and a test profile:

```sh
/Applications/AutoTurn.app/Contents/MacOS/AutoTurn --routing-live-check /path/test.conf
```

It changes service memory, never Keychain or saved user settings. It tests real
TUN HTTPS and cleanup, then a simulated trusted home SSID on the same physical
interface, full VPN compatibility, and Off. Always stops the test VPN at exit.
Real Wi-Fi switching, DoH/ECH in actual browsers, core process failure, and IPv6
must be checked separately. Cross compilation is not a physical M1 test.

## IP list additions and service selection

The routing detail imports a UTF-8 IP/CIDR text list from a file or direct HTTPS URL
into the existing rule. Domains and previous IP additions remain; duplicates are skipped.
HydraRoute Classic/Neo `ip.list` groups are recognized; disabled groups are skipped,
and multiple active groups require choosing one before importing. `geoip:` directives
require exporting concrete IP/CIDR addresses and are rejected with a clear message.
The confirmation shows the number of new entries and the current rule destination.
These imported addresses are manual additions and survive service database refreshes.

The add dialog filters services while typing, recognizes domain aliases, and allows
multiple checked services/custom rules. Selections persist when changing the search.
The catalog is in a 330-point scroll area. Bulk additions are validated atomically.

Modal informational and confirmation dialogs close the status panel first so it cannot
cover the connection-check result.

## Network recovery

Helper replacement previously left orphaned routing/AWG processes alive. On startup,
only root-owned processes with the exact AutoTurn executable and argument list are
terminated before DNS/endpoint-journal recovery. PF remains in place until policy
determines whether direct traffic is allowed. An unsuccessful cleanup reports error.

“Восстановить обычный интернет” is available in every console/menu theme. It saves
Off, then uses authenticated recover RPC to release protection and stop engines
(including any orphans), remove own DNS/journal routes and remain Off. It retains
profiles/home networks/routing rules. Unavailable IPC falls back to the installed
root-owned helper's --emergency-recover, with standard macOS admin authorization.
That independent path stops only the AutoTurn launchd service and its exact engines,
releases its PF anchor/token, recovers DNS/endpoint journal and restarts the service.
Router settings and other VPN processes are untouched.
