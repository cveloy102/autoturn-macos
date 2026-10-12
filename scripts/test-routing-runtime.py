#!/usr/bin/env python3
"""Loopback routing core integration; never changes system DNS/routes/PF."""
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import tempfile
import time

root = Path(__file__).resolve().parent.parent
engine = Path(sys.argv[1]) if len(sys.argv) > 1 else root / 'dist/AutoTurn.app/Contents/Resources/routing-core'
route = subprocess.check_output(['/sbin/route', '-n', 'get', 'default'], text=True)
interface = re.search(r'interface: ((?:en|bridge|eth)\d+)', route)
gateway = re.search(r'gateway: (\d+\.\d+\.\d+\.\d+)', route)
if not interface or not gateway:
    sys.exit('Physical IPv4 uplink required for this integration test')
with socket.socket() as reservation:
    reservation.bind(('127.0.0.1', 0))
    port = reservation.getsockname()[1]
config = {
    'log': {'disabled': True},
    'inbounds': [{'type': 'mixed', 'tag': 'audit', 'listen': '127.0.0.1', 'listen_port': port}],
    'outbounds': [
        {'type': 'direct', 'tag': 'direct', 'bind_interface': interface.group(1)},
        {'type': 'direct', 'tag': 'vpn', 'bind_interface': 'utun1999'}],
    'dns': {'servers': [{'type': 'udp', 'tag': 'physical', 'server': gateway.group(1), 'detour': 'direct'}], 'final': 'physical'},
    'route': {'default_domain_resolver': 'physical', 'rules': [{'domain_suffix': ['cloudflare.com'], 'action': 'route', 'outbound': 'vpn'}], 'final': 'direct'}}
with tempfile.TemporaryDirectory(prefix='autoturn-core-audit-') as directory:
    path = Path(directory) / 'config.json'
    path.write_text(json.dumps(config))
    subprocess.run([str(engine), 'check', '-c', str(path)], check=True)
    process = subprocess.Popen([str(engine), 'run', '-c', str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(50):
            if process.poll() is not None:
                sys.exit('Core exited before listening')
            try:
                with socket.create_connection(('127.0.0.1', port), timeout=0.1):
                    break
            except OSError:
                time.sleep(0.1)
        else:
            sys.exit('Loopback proxy did not start')
        for label, url, expected in [
            ('direct before VPN failure', 'https://www.apple.com/library/test/success.html', True),
            ('selected VPN fails closed', 'https://www.cloudflare.com/cdn-cgi/trace', False),
            ('direct after VPN failure', 'https://www.apple.com/library/test/success.html', True)]:
            result = subprocess.run(['/usr/bin/curl', '--silent', '--fail', '--proxy', f'http://127.0.0.1:{port}', '--noproxy', '', '--connect-timeout', '4', '--max-time', '8', url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if (result.returncode == 0) != expected:
                sys.exit(f'FAIL: {label} (curl={result.returncode})')
            print(f'PASS: {label}')
    finally:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)
print('Loopback runtime integration passed; system DNS/routes/PF unchanged')
