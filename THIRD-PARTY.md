# Third-party components

AmneziaWG Go: https://github.com/amnezia-vpn/amneziawg-go,
v3.1.20260828, commit b5928efb6ca19f0153958460c3d141f04abc5c2e.
Its license is included in the application as AmneziaWG-LICENSE.txt.

Routing core: https://github.com/SagerNet/sing-box, v1.14.3,
commit 7054cac5124465ffdb145870d7c01885566711b1, GPL-3.0.
The full license is bundled as RoutingCore-LICENSE.txt. AutoTurn patches
and additional GPL-3.0 Go files are in third_party/routing-core-patches/.
scripts/prepare-routing-core.sh retrieves the pinned corresponding source,
applies these patches, runs sniffing tests, and builds both Darwin architectures
with Go 1.26.9 and CGO_ENABLED=0. The patches preserve DNS-derived names when
TLS or QUIC uses ECH, and conservatively distinguish unknown flows.
The patched source and build instructions must accompany a distributed release.

Service domain lists and catalog: https://github.com/Ground-Zerro/Geo-Aggregator.
Bundled seed lists are provided for initial use; updates download a single
pinned repository revision over HTTPS. Custom user additions remain separate.

The routing core is a separate executable, invoked with a generated configuration.
The production configuration opens a TUN interface, not a SOCKS/HTTP proxy port.
