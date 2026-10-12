package sniff

import "github.com/sagernet/sing-box/adapter"

// AutoTurn must preserve a domain identified by its own DNS mapping. An ECH
// outer SNI is not the destination and must never authorize direct egress.
func autoTurnDomain(metadata *adapter.InboundContext, serverName string, extensions []uint16) string {
	if metadata.FakeIP {
		return metadata.Destination.Fqdn
	}
	for _, extension := range extensions {
		if extension == 0xfe0d {
			return ""
		}
	}
	return serverName
}
