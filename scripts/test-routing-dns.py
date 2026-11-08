#!/usr/bin/env python3
"""Real core/fake-IP regression on loopback; no system DNS, routes or PF edits."""
import copy
import http.server
import json
from pathlib import Path
import socket
import socketserver
import struct
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parent.parent
CORE = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "third_party/routing-core/sing-box"
FIXTURE = ROOT / ".build/routing-dns-fixture"
queries = []


def read_exact(connection, count):
    result = b""
    while len(result) < count:
        value = connection.recv(count - len(result))
        if not value:
            raise EOFError()
        result += value
    return result


class Resolver(socketserver.BaseRequestHandler):
    def handle(self):
        try:
            while True:
                size = struct.unpack("!H", read_exact(self.request, 2))[0]
                data = read_exact(self.request, size)
                offset, labels = 12, []
                while data[offset]:
                    length = data[offset]
                    labels.append(data[offset + 1:offset + 1 + length].decode())
                    offset += length + 1
                end = offset + 5
                host = ".".join(labels)
                queries.append(host)
                qtype, qclass = struct.unpack("!HH", data[end - 4:end])
                answer = b""
                if qtype == 1 and qclass == 1:
                    answer = b"\xc0\x0c" + struct.pack("!HHIH", 1, 1, 30, 4) + socket.inet_aton("127.0.0.1")
                response = data[:2] + struct.pack("!HHHHH", 0x8180, 1, bool(answer), 0, 0) + data[12:end] + answer
                self.request.sendall(struct.pack("!H", len(response)) + response)
        except (EOFError, OSError):
            pass


class ResolverServer(socketserver.ThreadingTCPServer):
    daemon_threads = True


class Page(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"autoturn-dns-fixture"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


def free_port(kind=socket.SOCK_STREAM):
    with socket.socket(socket.AF_INET, kind) as reservation:
        reservation.bind(("127.0.0.1", 0))
        return reservation.getsockname()[1]


def fake_address(port, hostname):
    name = b"".join(bytes([len(label)]) + label.encode() for label in hostname.split(".")) + b"\0"
    query = struct.pack("!HHHHHH", 1234, 0x0100, 1, 0, 0, 0) + name + struct.pack("!HH", 1, 1)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
        client.settimeout(3)
        client.sendto(query, ("127.0.0.1", port))
        response, _ = client.recvfrom(4096)
    assert struct.unpack("!H", response[6:8])[0] == 1, "Fake DNS returned no answer"
    address = socket.inet_ntoa(response[-4:])
    assert address.startswith(("198.18.", "198.19.")), address
    return address


def exercise(offline, resolver_port, page_port, directory, previous=None):
    production = json.loads(subprocess.check_output([str(FIXTURE)] + (["--offline"] if offline else [])))
    config = copy.deepcopy(production)
    proxy_port, dns_port = free_port(), free_port(socket.SOCK_DGRAM)
    config["inbounds"] = [
        {"type": "mixed", "tag": "routing-in", "listen": "127.0.0.1", "listen_port": proxy_port},
        {"type": "direct", "tag": "fixture-dns", "listen": "127.0.0.1", "listen_port": dns_port,
         "network": "udp", "override_address": "172.29.255.2", "override_port": 53},
    ]
    config["route"]["rules"].insert(0, {"inbound": ["fixture-dns"], "action": "hijack-dns"})
    config["route"].pop("default_interface", None)
    for outbound in config["outbounds"]:
        outbound.pop("bind_interface", None)
    for server in config["dns"]["servers"]:
        if server["tag"] == "secure-dns":
            server["server_port"] = resolver_port
            server.pop("bind_interface", None)
    config["experimental"]["cache_file"]["path"] = str(Path(directory) / "fakeip.db")
    path = Path(directory) / "config.json"
    path.write_text(json.dumps(config))
    subprocess.run([str(CORE), "check", "-c", str(path)], check=True, capture_output=True)
    process = subprocess.Popen([str(CORE), "run", "-c", str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        for _ in range(50):
            if process.poll() is not None:
                raise AssertionError(process.stderr.read().decode())
            try:
                with socket.create_connection(("127.0.0.1", proxy_port), timeout=0.1):
                    break
            except OSError:
                time.sleep(0.1)
        else:
            raise AssertionError("Core did not listen")
        addresses = {}
        for host, expected in [("vpn.autoturn.test", not offline), ("direct.autoturn.test", True)]:
            address = fake_address(dns_port, host)
            addresses[host] = address
            if previous:
                assert address == previous[host], "Fake-IP mapping changed across VPN switch"
            before = len(queries)
            result = subprocess.run([
                "/usr/bin/curl", "-q", "--silent", "--fail", "--socks5", f"127.0.0.1:{proxy_port}",
                "--noproxy", "", "--connect-timeout", "2", "--max-time", "3",
                f"http://{address}:{page_port}/"], capture_output=True)
            worked = result.returncode == 0 and result.stdout == b"autoturn-dns-fixture"
            assert worked == expected, f"offline={offline}: {host} curl={result.returncode} body={result.stdout!r}"
            if offline and host.startswith("vpn."):
                assert host not in queries[before:], "Protected flow queried upstream while VPN was unavailable"
            print(f"PASS VPN {'unavailable' if offline else 'available'}: {host} {'loads' if worked else 'blocked before upstream DNS'}")
        return addresses
    finally:
        process.terminate()
        try:
            process.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.communicate(timeout=3)


with ResolverServer(("127.0.0.1", 0), Resolver) as resolver, http.server.ThreadingHTTPServer(("127.0.0.1", 0), Page) as page:
    for server in [resolver, page]:
        threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        with tempfile.TemporaryDirectory(prefix="autoturn-dns-") as directory:
            addresses = exercise(False, resolver.server_address[1], page.server_address[1], directory)
            exercise(True, resolver.server_address[1], page.server_address[1], directory, addresses)
            exercise(False, resolver.server_address[1], page.server_address[1], directory, addresses)
    finally:
        resolver.shutdown()
        page.shutdown()
print("Routing DNS regression passed: VPN -> outage -> VPN, persistent fake IPs; no system networking changes")
