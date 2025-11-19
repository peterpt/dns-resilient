# Dns-resilient
A self-healing, accumulating local DNS server that builds a permanent, local "Phone Book" of the internet as you browse. It ensures you can connect to websites, mail servers, chat services, and infrastructure even if public DNS providers fail.

## Notes
Due to current days dns issues worldwide been incresing , i and google ai we made a script that collects all
your dns requests to s phonebook file , this script is monitoring your http /https and other services for the domains you ask
and then checks their ips and stores them on a phonebook , when you request that same domain again in future then the proxy
will forward you to the valid ip in phonebook even if global dns servers are down , this app will store only the sites you visit
, this means that if global dns are down and you never visited previously a specific site with this app active then you will not
be able to access that website because it is not in your local dns database .

## phonebook structure by this script
<img width="1024" height="709" alt="image" src="https://github.com/user-attachments/assets/491b5d5d-f7e7-4842-8a04-b4dbfcb14a9e" />


## 🚀 The Concept: "Accumulation vs Caching"
Standard DNS servers forget IPs after the TTL (Time To Live) expires.  
**Resilient DNS Proxy remembers everything.**

If you visit a site like **YouTube** or **GitHub**, they often rotate through dozens of IP addresses. This script:
1.  **Collects** every IP it ever sees for a domain.
2.  **Tests** them constantly using "Heavy Duty" port scanning.
3.  **Serves** only the living IPs to your computer.

If the DNS system crashes or an IP range goes down, your computer simply switches to the other IPs stored in your local Phone Book.

## ⚡ Features

*   **Universal Support:** Handles **Web** (HTTP/S), **Email** (SMTP/MX), **Chat** (IRC/WhatsApp/XMPP), and **Admin** (SSH/RDP/FTP).
*   **Smart Health Checks:** Before giving you an IP, it verifies if the server is actually listening on relevant ports (80, 443, 25, 587, 6667, etc.).
*   **IPv6 Blocking:** Silently blocks AAAA requests to force IPv4 connection speeds on non-IPv6 networks (prevents timeouts).
*   **Thread-Safe:** Handles high-load environments (Torrents, 4K Streaming) without crashing.
*   **Zero-Config Service:** Runs as a system service (Systemd or SysVinit) automatically.

## 📦 Installation (Linux)

**1. Clone the repository:**
```bash
git clone https://github.com/peterpt/resilient-dns-proxy.git
cd resilient-dns-proxy

  

2. Run the Manager Script (Root required):
code Bash

    
sudo ./install.sh

  

3. Select Option 1:
code Text

    
1) Install

  

The script will install Python dependencies, configure /etc/resolv.conf, persist settings in DHCP, and start the background service.
⚠️ Crucial Browser Configuration

Firefox (and some other browsers) bypass system DNS by default. You must disable "DNS over HTTPS" for this proxy to work.

    Go to Settings -> Privacy & Security.

    Scroll down to DNS over HTTPS.

    Select Off (Use default DNS resolver).

If you do not do this, Firefox will ignore the proxy and your "Phone Book" will not grow.
📋 Management

The install.sh script is also your manager.

To Update or Reinstall:
code Bash

    
sudo ./install.sh
# Select Option 1

  

To Uninstall:
code Bash

    
sudo ./install.sh
# Select Option 2

  

Uninstalling will stop the service, remove the files, and restore your original network configuration automatically.
🖥️ Supported Platforms

    Linux: Debian, Ubuntu, Devuan, Alpine, Arch, etc. (Supports Systemd & SysVinit/OpenRC).

    Windows: Coming Soon (.exe version in development).

📝 Logs

Watch your Phone Book grow in real-time:
code Bash

    
tail -f /var/log/resilient-dns.log


## Credits
**Maintained by peterpt**  
*Developed with the assistance of Google AI*

 📜 License

MIT License - Free to use, modify, and distribute.
