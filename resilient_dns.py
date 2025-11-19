#!/usr/bin/env python3
# ------------------------------------------------------------------------------
# Project: Resilient DNS Proxy (Internet Survival Kit)
# Purpose: Self-healing, accumulating, local DNS proxy with health-checks.
#
# Author:  peterpt
# Co-Author: Google AI
# License: MIT
# ------------------------------------------------------------------------------

import json
import socket
import threading
import time
from dnslib import DNSRecord, DNSHeader, RR, A, MX, QTYPE, RCODE
from dnslib.server import DNSServer, BaseResolver
import dns.resolver

# --- CONFIGURATION ---
# The persistent storage location
PHONE_BOOK_FILE = '/usr/local/share/dns-proxy/phone_book.json'
UPSTREAM_DNS = '8.8.8.8'
LOCAL_IP = '127.0.0.1'
PORT = 53
TIMEOUT = 0.4 
# ---------------------

class SilentLogger:
    """Suppress all standard DNS log messages."""
    def log_pass(self, *args): pass
    def log_prefix(self, *args): pass
    def log_recv(self, *args): pass
    def log_send(self, *args): pass
    def log_request(self, *args): pass
    def log_reply(self, *args): pass
    def log_truncated(self, *args): pass
    def log_error(self, *args): pass
    def log_data(self, *args): pass

class PhoneBook:
    def __init__(self, filepath):
        self.filepath = filepath
        self.lock = threading.Lock()
        self.cache = self._load()

    def _load(self):
        try:
            with open(self.filepath, 'r') as f:
                return json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            return {}

    def get(self, key):
        with self.lock:
            return list(self.cache.get(key, []))

    def update(self, key, new_data):
        with self.lock:
            existing = set(self.cache.get(key, []))
            incoming = set(new_data)
            
            # Calculate what is strictly NEW
            freshly_added = incoming - existing
            
            if not freshly_added:
                return

            # Merge old and new
            combined = list(existing | incoming)
            self.cache[key] = combined
            
            # Save immediately
            try:
                with open(self.filepath, 'w') as f:
                    json.dump(self.cache, f, indent=4)
            except Exception as e:
                pass
            
            # Print only new entries (Flush ensures it hits the log immediately)
            formatted = ", ".join([str(x) for x in freshly_added])
            print(f"{key} -> {formatted} - registered", flush=True)

class UniversalResolver(BaseResolver):
    def __init__(self):
        self.phone_book = PhoneBook(PHONE_BOOK_FILE)
        self.upstream = dns.resolver.Resolver()
        self.upstream.nameservers = [UPSTREAM_DNS]

    def check_ip_health(self, ip):
        """
        Universal Heavy Duty Health Check.
        Scans Web, Mail, Chat, and Admin ports.
        """
        # Phase 1: Web (Most common)
        if self.try_connect(ip, [443, 80]): return True
        # Phase 2: Messaging (WhatsApp, XMPP, ICQ, IRC)
        if self.try_connect(ip, [5222, 5223, 5190, 6667, 6697]): return True
        # Phase 3: Mail (SMTP, IMAP)
        if self.try_connect(ip, [25, 465, 587, 993, 995]): return True
        # Phase 4: Infrastructure (SSH, RDP, FTP, MQTT, DNS-TCP)
        if self.try_connect(ip, [22, 3389, 1883, 21, 53]): return True
        
        return False

    def try_connect(self, ip, ports):
        for port in ports:
            try:
                with socket.create_connection((ip, port), timeout=TIMEOUT):
                    return True
            except OSError:
                continue
        return False

    def resolve(self, request, handler):
        qname = str(request.q.qname)
        domain = qname.rstrip('.')
        qtype = request.q.qtype
        
        reply = request.reply()

        # --- 1. BLOCK IPv6 (AAAA) ---
        if qtype == QTYPE.AAAA:
            reply.header.rcode = RCODE.NOERROR
            return reply

        # --- 2. HANDLE WEB BROWSING / HOSTNAMES (A Records) ---
        if qtype == QTYPE.A:
            valid_ips = []
            cached_ips = self.phone_book.get(domain)
            
            if cached_ips:
                for ip in cached_ips:
                    if self.check_ip_health(ip):
                        valid_ips.append(ip)
            
            if not valid_ips:
                try:
                    answers = self.upstream.resolve(domain, 'A')
                    new_ips = [str(r) for r in answers]
                    if new_ips:
                        self.phone_book.update(domain, new_ips)
                        valid_ips = new_ips
                except Exception:
                    pass
            
            if valid_ips:
                for ip in valid_ips:
                    reply.add_answer(RR(qname, QTYPE.A, rdata=A(ip), ttl=60))
            else:
                reply.header.rcode = RCODE.SERVFAIL

        # --- 3. HANDLE EMAIL (MX Records) ---
        elif qtype == QTYPE.MX:
            key = f"MX:{domain}"
            cached_mx = self.phone_book.get(key)
            
            if not cached_mx:
                try:
                    answers = self.upstream.resolve(domain, 'MX')
                    new_mx = [f"{r.preference}:{r.exchange}" for r in answers]
                    if new_mx:
                        self.phone_book.update(key, new_mx)
                        cached_mx = new_mx
                except Exception:
                    pass

            if cached_mx:
                for entry in cached_mx:
                    try:
                        pref, exchange = entry.split(':', 1)
                        reply.add_answer(RR(qname, QTYPE.MX, rdata=MX(exchange, int(pref)), ttl=60))
                    except: pass
            else:
                reply.header.rcode = RCODE.NOERROR

        # --- 4. IGNORE OTHERS ---
        else:
            reply.header.rcode = RCODE.NOERROR

        return reply

if __name__ == '__main__':
    resolver = UniversalResolver()
    logger = SilentLogger()

    udp_server = DNSServer(resolver, port=PORT, address=LOCAL_IP, tcp=False, logger=logger)

    print(f"[*] Resilient DNS (Web+Mail+Chat+Admin) running on {LOCAL_IP}:{PORT}", flush=True)

    try:
        udp_server.start_thread()
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        pass
    finally:
        udp_server.stop()
