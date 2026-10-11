package sniff

import (
	"github.com/sagernet/sing-box/adapter"
	M "github.com/sagernet/sing/common/metadata"
	"testing"
)

func TestAutoTurnDomain(t *testing.T) {
	for _, test := range []struct {
		fake        bool
		domain, sni string
		extensions  []uint16
		want        string
	}{
		{true, "youtube.com", "cloudflare-ech.com", []uint16{0xfe0d}, "youtube.com"},
		{false, "", "cloudflare-ech.com", []uint16{0xfe0d}, ""},
		{false, "", "youtube.com", nil, "youtube.com"},
		{true, "example.com", "unrelated.example", nil, "example.com"},
	} {
		metadata := &adapter.InboundContext{FakeIP: test.fake, Destination: M.Socksaddr{Fqdn: test.domain}}
		if got := autoTurnDomain(metadata, test.sni, test.extensions); got != test.want {
			t.Fatalf("domain=%q, want %q", got, test.want)
		}
	}
}
