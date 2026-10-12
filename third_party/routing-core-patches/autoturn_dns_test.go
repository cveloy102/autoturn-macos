package dns

import (
    "testing"
    "github.com/miekg/dns"
)

func TestAutoTurnDNSLeaseCeiling(t *testing.T) {
    for _, pair := range [][2]uint32{{90000,21600},{30,30},{0,0}} {
        message := &dns.Msg{Answer: []dns.RR{&dns.A{Hdr:dns.RR_Header{Name:"test.example.",Rrtype:dns.TypeA,Class:dns.ClassINET,Ttl:pair[0]}}}}
        if got := computeTimeToLive(message); got != pair[1] { t.Fatalf("TTL %d produced %d, want %d",pair[0],got,pair[1]) }
    }
    negative := &dns.Msg{Ns: []dns.RR{&dns.SOA{Hdr:dns.RR_Header{Name:"example.",Rrtype:dns.TypeSOA,Class:dns.ClassINET,Ttl:90000},Minttl:80000}}}
    if got := computeTimeToLive(negative); got != 21600 { t.Fatalf("negative TTL exceeded ceiling: %d",got) }
}
