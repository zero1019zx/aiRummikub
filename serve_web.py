#!/usr/bin/env python3
"""本地 HTTPS 服务器测试 Web 版: python3 serve_web.py
手机连同一 WiFi, 访问打印出的 https 地址, 浏览器提示证书不受信任时选择"继续访问"。
(Godot 4 Web 版要求安全上下文, 局域网 IP 必须走 HTTPS)"""
import http.server
import os
import socket
import ssl
import subprocess
import functools

START_PORT = 8060
BASE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(BASE, "build", "web")
CERT_DIR = os.path.join(BASE, ".cert")
CERT = os.path.join(CERT_DIR, "cert.pem")
KEY = os.path.join(CERT_DIR, "key.pem")


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
    }

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def lan_ip() -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


def ensure_cert(ip: str) -> None:
    if os.path.exists(CERT) and os.path.exists(KEY):
        return
    os.makedirs(CERT_DIR, exist_ok=True)
    subprocess.run([
        "openssl", "req", "-x509", "-newkey", "rsa:2048",
        "-keyout", KEY, "-out", CERT, "-days", "825", "-nodes",
        "-subj", "/CN=rummi-lite",
        "-addext", f"subjectAltName=DNS:localhost,IP:127.0.0.1,IP:{ip}",
    ], check=True, capture_output=True)
    print(f"已生成自签证书: {CERT_DIR}/")


def entry_page() -> str:
    if os.path.exists(os.path.join(ROOT, "index.html")):
        return ""
    pages = sorted(p for p in os.listdir(ROOT) if p.endswith(".html"))
    return pages[0] if pages else ""


if __name__ == "__main__":
    if not os.path.isdir(ROOT):
        raise SystemExit(f"找不到 {ROOT} — 请先在 Godot 中导出 Web 版本")
    ip = lan_ip()
    ensure_cert(ip)
    handler = functools.partial(Handler, directory=ROOT)
    http.server.ThreadingHTTPServer.allow_reuse_address = True
    httpd = None
    port = START_PORT
    for port in range(START_PORT, START_PORT + 20):
        try:
            httpd = http.server.ThreadingHTTPServer(("0.0.0.0", port), handler)
            break
        except OSError:
            print(f"端口 {port} 被占用, 尝试 {port + 1} ...")
    if httpd is None:
        raise SystemExit("没有可用端口")
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(CERT, KEY)
    httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
    page = entry_page()
    print(f"本机访问:   https://localhost:{port}/{page}")
    print(f"手机访问:   https://{ip}:{port}/{page}  (同一WiFi, 证书警告选'继续访问')")
    httpd.serve_forever()
