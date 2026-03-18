# WireGuard Cybersecurity Resources

> A curated collection of WireGuard-based tools, repos, and platforms for offensive security, defensive operations, and secure infrastructure. Last updated March 2026.

---

## Table of Contents

- [Offensive Security / Red Team C2](#offensive-security--red-team-c2)
- [Pivoting & Tunneling](#pivoting--tunneling)
- [OPSEC / Obfuscation / Anti-DPI](#opsec--obfuscation--anti-dpi)
- [Proxy & Routing Utilities](#proxy--routing-utilities)
- [Disposable / Ephemeral VPN Infrastructure](#disposable--ephemeral-vpn-infrastructure)
- [Production-Grade WireGuard Platforms](#production-grade-wireguard-platforms)
- [Mesh & Overlay Networks](#mesh--overlay-networks)
- [Defensive / Threat Hunting](#defensive--threat-hunting)
- [Bug Bounty Tools](#bug-bounty-tools)
- [Reference & Cheatsheets](#reference--cheatsheets)
- [Notable Research](#notable-research)
- [Security Advisories](#security-advisories)

---

## Offensive Security / Red Team C2

| Project | Stars | Description |
|---------|:-----:|-------------|
| [BishopFox/sliver](https://github.com/BishopFox/sliver) | ~10.8k | Adversary emulation / C2 framework with **native WireGuard transport**. Supports reverse SOCKS5 and port forwarding over WireGuard tunnels. Dynamic per-binary code generation with compile-time obfuscation. |
| [sandialabs/wiretap](https://github.com/sandialabs/wiretap) | ~1.1k | Built by **Sandia National Labs**. Transparent VPN-like proxy via WireGuard. No root/admin required on agent side. Multi-hop server chaining for deep network pivoting. |
| [Yeeb1/SockTail](https://github.com/Yeeb1/SockTail) | New | Drop-and-run SOCKS5 proxy using Tailscale (WireGuard-based). One-shot red team tool — no persistence, no daemon. XOR-based auth key obfuscation. Connection drops when binary exits. |
| [sensepost/wiresocks](https://github.com/sensepost/wiresocks) | — | **SensePost / Orange Cyberdefense**. Docker-compose WireGuard + SOCKS proxy for red team ops. Full network route with working DNS resolution. |
| [nikosch86/investiGator](https://github.com/nikosch86/investiGator) | — | Scriptlet to stand up investigation/attack infra. Deploys WireGuard, Shadowsocks, SOCKS5 + ProxyChains config. Supports DigitalOcean, GCP, SporeStack. |

---

## Pivoting & Tunneling

| Project | Stars | Description |
|---------|:-----:|-------------|
| [nicocha30/ligolo-ng](https://github.com/nicocha30/ligolo-ng) | Popular | **De facto standard for pentest pivoting.** Creates TUN interfaces using WireGuard's Wintun driver on Windows. No SOCKS needed. Multi-hop support. Multiplayer web UI. Now in official Kali repos. |
| [t3l3machus/pentest-pivoting](https://github.com/t3l3machus/pentest-pivoting) | — | Compact guide to network pivoting for pentests & CTFs. Covers Chisel, SSH tunnels, proxychains, and dynamic port forwarding. |
| [juanjoSanz/aws-pentesting-lab](https://github.com/juanjoSanz/aws-pentesting-lab) | — | Terraform-deployed pentest lab on AWS. Kali Linux accessible via WireGuard VPN, with vulnerable target instances in a private subnet. |

---

## OPSEC / Obfuscation / Anti-DPI

| Project | Stars | Description |
|---------|:-----:|-------------|
| [ARAS-Workspace/phantom-wg](https://github.com/ARAS-Workspace/phantom-wg) | — | **Ghost Mode** — disguises WireGuard traffic as standard HTTPS to bypass DPI. Multi-hop with dual encryption layers. Combined mode for maximum privacy. Interactive UI + API. |
| [a904guy/VPN-Chainer](https://github.com/a904guy/VPN-Chainer) | — | Dynamically chains multiple WireGuard VPNs with rotation + speed testing. Example: `5-hop: Singapore -> Germany -> Netherlands -> Canada -> Japan`. Systemd service support. |
| [ClusterM/wg-obfuscator](https://github.com/ClusterM/wg-obfuscator) | — | Disguises WireGuard traffic as random data or STUN protocol. Works as an external wrapper — independent of WireGuard client/server. Cross-platform: Linux, Windows, macOS, OpenWRT, Android. |
| [infinet/xt_wgobfs](https://github.com/infinet/xt_wgobfs) | — | **Kernel-level** iptables extension for WireGuard packet obfuscation. Also has a cross-platform CLI companion (`rs-wgobfs`) for Windows/Mac/BSDs. |
| [apernet/mwgp](https://github.com/apernet/mwgp) | — | Multiple WireGuard Proxy — port multiplexing (many instances on one UDP port) + built-in traffic obfuscator. Compatible with official WireGuard clients. |
| [moparisthebest/wireguard-proxy](https://github.com/moparisthebest/wireguard-proxy) | — | Tunnels WireGuard UDP over TCP or TLS connections. Essential for environments that block UDP traffic. |

---

## Proxy & Routing Utilities

| Project | Stars | Description |
|---------|:-----:|-------------|
| [pufferffish/wireproxy](https://github.com/pufferffish/wireproxy) | ~5.4k | Userspace WireGuard client exposing SOCKS5/HTTP proxy. **No root required**, no network interface changes. Great for routing specific tools through WireGuard. |
| [kizzx2/docker-wireguard-socks-proxy](https://github.com/kizzx2/docker-wireguard-socks-proxy) | — | WireGuard-to-SOCKS5 in a Docker container. Run multiple containers for multiple tunnels on different ports. Ideal for per-app VPN routing. |

---

## Disposable / Ephemeral VPN Infrastructure

| Project | Stars | Description |
|---------|:-----:|-------------|
| [trailofbits/algo](https://github.com/trailofbits/algo) | ~29k | **By Trail of Bits** (cybersecurity firm). One-command personal WireGuard VPN via Ansible. Supports Linode, AWS, Azure, GCP, Vultr, Hetzner, and more. Strong security defaults. Designed to be disposable. |
| [trailofbits/algo-ng](https://github.com/trailofbits/algo-ng) | — | Experimental Terraform-based rewrite of Algo VPN. |
| [P0ssuidao/terraguard](https://github.com/P0ssuidao/terraguard) | — | **One-command create/destroy** WireGuard VPN via Terraform. Supports AWS, DigitalOcean, GCP. Perfect for engagement-based offensive ops. |
| [michaelbeaumont/livewire](https://github.com/michaelbeaumont/livewire) | — | Ephemeral WireGuard VPN on GCP. Private key is generated and stays on the VM — never exported. |
| [ravikiranvm/CloudVPN](https://github.com/ravikiranvm/CloudVPN) | — | WireGuard on AWS Free Tier via Terraform. Auto-generates client configs and uploads to S3. Zero-cost solution. |
| [mantvydasb/Red-Team-Infrastructure-Automation](https://github.com/mantvydasb/Red-Team-Infrastructure-Automation) | — | Disposable, resilient **red team infrastructure** with Terraform. |
| [dazzyddos/HSC24RedTeamInfra](https://github.com/dazzyddos/HSC24RedTeamInfra) | — | Workshop slides and code for red team infrastructure automation (2024). |
| [TendTo/IAC-VPN](https://github.com/TendTo/IAC-VPN) | — | All-in-one WireGuard VPN with Terraform + Ansible. Supports OpenStack, Oracle Cloud, GCP. |
| [cusable/automated-wireguard-vpn](https://github.com/cusable/automated-wireguard-vpn) | — | Automated WireGuard deployment on Scaleway Cloud with Terraform + Ansible. |

---

## Production-Grade WireGuard Platforms

| Project | Stars | Description |
|---------|:-----:|-------------|
| [netbirdio/netbird](https://github.com/netbirdio/netbird) | ~23.6k | WireGuard mesh overlay with SSO, MFA, and granular access controls. Zero-trust networking. Post-quantum crypto via Rosenpass. Backed by German federal security research (CISPA). |
| [juanfont/headscale](https://github.com/juanfont/headscale) | ~25k | Self-hosted, open-source Tailscale control server. Full compatibility with Tailscale clients. |
| [tailscale/tailscale](https://github.com/tailscale/tailscale) | ~20k+ | WireGuard-based mesh VPN with 2FA. Note: ACLs are inbound-only and client-enforced — a compromised client can bypass them ([Pulse Security research](https://pulsesecurity.co.nz/articles/some-tailscale-tricks)). |
| [firezone/firezone](https://github.com/firezone/firezone) | ~19k | Enterprise zero-trust access platform on WireGuard. 3-4x faster than OpenVPN. Granular group-based policies, SSO, MFA. Peer-to-peer encrypted tunnels. |
| [gravitl/netmaker](https://github.com/gravitl/netmaker) | ~10k+ | Automated WireGuard virtual networks. Peer-to-peer, site-to-site, Kubernetes, zero-trust. Uses kernel WireGuard for max performance. |
| [wg-easy/wg-easy](https://github.com/wg-easy/wg-easy) | Very high | Simplest WireGuard server + web admin UI. One Docker command. Easy client management with create/edit/delete/enable/disable. |
| [freifunkMUC/wg-access-server](https://github.com/freifunkMUC/wg-access-server) | — | All-in-one WireGuard VPN with web UI, user auth, 1-click device registration, QR codes. Golang + React. Active fork with IPv6. |
| [subspacecommunity/subspace](https://github.com/subspacecommunity/subspace) | — | Simple WireGuard VPN server GUI. SSO/SAML support, QR code generation, Docker deployment. Community-maintained fork. |

---

## Mesh & Overlay Networks

| Project | Stars | Description |
|---------|:-----:|-------------|
| [slackhq/nebula](https://github.com/slackhq/nebula) | ~14k+ | **Slack / Defined Networking**. Overlay networking on the Noise Protocol Framework (same crypto foundations as WireGuard). Mutual PKI auth, certificate-based security groups, AES-256-GCM. |
| [EasyTier/EasyTier](https://github.com/EasyTier/EasyTier) | Growing | Decentralized mesh VPN with WireGuard support. Cross-platform including MIPS/ARM. AES-GCM or WireGuard encryption modes. |
| [k4yt3x/wg-meshconf](https://github.com/k4yt3x/wg-meshconf) | — | WireGuard full mesh configuration generator. Simplifies creating configs for many-peer mesh networks. |

---

## Defensive / Threat Hunting

| Project | Stars | Description |
|---------|:-----:|-------------|
| [RaynardWaits46/threat-detection-homelab](https://github.com/RaynardWaits46/threat-detection-homelab) | — | SOC lab using WireGuard tunnels to securely isolate and transport honeypot logs for SIEM-based threat detection. Tests detection rules with Atomic Red Team. (Jan 2026) |

---

## Bug Bounty Tools

| Project | Stars | Description |
|---------|:-----:|-------------|
| [honoki/bugbounty-openvpn-socks](https://github.com/honoki/bugbounty-openvpn-socks) | — | Run multiple VPN profiles in parallel, each exposed as a local SOCKS proxy. Docker-based. Integrates with Burp Suite, nuclei, ffuf, BBRF. Architecture applicable to WireGuard setups. |

---

## Reference & Cheatsheets

| Resource | Description |
|----------|-------------|
| [cedrickchee/awesome-wireguard](https://github.com/cedrickchee/awesome-wireguard) | **The master list** — comprehensive curated collection of all WireGuard tools, projects, and resources with activity status indicators. |
| [bluscreenofjeff/Red-Team-Infrastructure-Wiki](https://github.com/bluscreenofjeff/Red-Team-Infrastructure-Wiki) | Definitive wiki on red team infrastructure hardening. Covers WireGuard for operator VPN connectivity. |
| [RistBS/Awesome-RedTeam-Cheatsheet](https://github.com/RistBS/Awesome-RedTeam-Cheatsheet) | Red team cheatsheet with OPSEC guide that specifically recommends WireGuard. |
| [WesleyWong420/OPSEC-Tradecraft](https://github.com/WesleyWong420/OPSEC-Tradecraft) | Collection of OPSEC tradecraft and TTPs for red team operations, including VPN/tunneling recommendations. |
| [infosecn1nja/Red-Teaming-Toolkit](https://github.com/infosecn1nja/Red-Teaming-Toolkit) | Cutting-edge open-source security tools for red teamers and threat hunters. |
| [tcostam/awesome-command-control](https://github.com/tcostam/awesome-command-control) | Curated collection of C2 frameworks, tools, and resources for post-exploitation. |
| [thezakman/CTF-Heaven](https://github.com/thezakman/CTF-Heaven) | Large collection of pentest tools including reverse shells, post-exploitation agents, and pivoting utilities for CTFs. |

---

## Notable Research

| Resource | Description |
|----------|-------------|
| [WireGuard as a Stealth C2 Channel](https://medium.com/@cyberlpz777/wireguard-as-a-stealth-c2-channel-abuse-of-modern-vpns-evasion-and-detection-a4663a2df874) | (Dec 2025) Deep analysis of WireGuard's offensive potential. Covers userland WireGuard (`boringtun`/`wireguard-go`), Linux network namespace isolation for invisible tunnels, ESP32 IoT deployment, and detection strategies. |
| [Pulse Security: Tailscale Pentest Tricks](https://pulsesecurity.co.nz/articles/some-tailscale-tricks) | Practical security testing guidance for Tailscale deployments. Notes that ACLs are inbound-only and client-enforced — a compromised client can bypass them. |
| [Red Team Infrastructure (HackMD)](https://hackmd.io/@Drag0nR3b0rn/r1UUtaRvV) | Comprehensive document on red team infra. References WireGuard, `boringtun`, and Streisand for operator VPN setups. |

---

## Security Advisories

| Advisory | Project | Description |
|----------|---------|-------------|
| [GHSA-q8j9-34qf-7vq7](https://github.com/BishopFox/sliver/security/advisories) | Sliver C2 (Oct 2025) | WireGuard netstack did not isolate traffic between clients. **Patched in v1.5.44.** |
| [CVE-2026-29196](https://github.com/gravitl/netmaker) | Netmaker | Platform-user role could retrieve WireGuard private keys via API endpoints. **Fixed in v1.5.0.** |

---

## Quick-Start Recommendations

| Use Case | Recommended Tool |
|----------|-----------------|
| **Simple VPS proxy** (just route traffic through a server) | [trailofbits/algo](https://github.com/trailofbits/algo) or [wg-easy/wg-easy](https://github.com/wg-easy/wg-easy) |
| **Disposable / burn-after-use VPN** | [P0ssuidao/terraguard](https://github.com/P0ssuidao/terraguard) |
| **Pentest pivoting** | [nicocha30/ligolo-ng](https://github.com/nicocha30/ligolo-ng) + [sandialabs/wiretap](https://github.com/sandialabs/wiretap) |
| **Full C2 framework with WireGuard** | [BishopFox/sliver](https://github.com/BishopFox/sliver) |
| **DPI evasion / censorship bypass** | [ARAS-Workspace/phantom-wg](https://github.com/ARAS-Workspace/phantom-wg) or [ClusterM/wg-obfuscator](https://github.com/ClusterM/wg-obfuscator) |
| **Multi-hop VPN chaining** | [a904guy/VPN-Chainer](https://github.com/a904guy/VPN-Chainer) |
| **Per-app proxy routing (no root)** | [pufferffish/wireproxy](https://github.com/pufferffish/wireproxy) |
| **Zero-trust team access** | [netbirdio/netbird](https://github.com/netbirdio/netbird) or [firezone/firezone](https://github.com/firezone/firezone) |
| **Self-hosted Tailscale** | [juanfont/headscale](https://github.com/juanfont/headscale) |

---

*This document is maintained as a living reference. Contributions and updates welcome.*
