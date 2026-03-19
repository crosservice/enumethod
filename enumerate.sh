#!/usr/bin/env bash
# ==============================================================================
# enumerate.sh — Automated server enumeration chain
#
# Implements the 11-step attack chain from enumeration.md against a single
# target. Only use on systems you own or have explicit written authorization
# to test.
#
# Usage:
#   sudo ./enumerate.sh <TARGET_IP> [OPTIONS]
#
# Options:
#   -d, --domain DOMAIN     Domain name for passive recon (default: reverse DNS)
#   -o, --output DIR        Output directory (default: ./enum_<IP>_<timestamp>)
#   -s, --steps STEPS       Comma-separated steps to run: 1-11 or "all" (default: all)
#   -t, --timing TIMING     nmap timing template 0-5 (default: 4)
#   -w, --wordlist PATH     Directory wordlist override
#   --vpn CONFIG            Route all traffic through WireGuard (path to .conf file)
#   --vpn-iface NAME        WireGuard interface name (default: wg-enum)
#   --vpn-keep              Don't tear down the VPN tunnel on exit
#   --skip-udp              Skip UDP scanning (slow)
#   --skip-bruteforce       Skip directory/vhost brute-forcing
#   --dry-run               Print commands without executing
#   -h, --help              Show this help message
#
# Requirements: nmap (minimum). Missing tools are auto-installed via
#               apt/pip/go. If install fails, the step is noted and skipped.
# ==============================================================================

set -euo pipefail

# =============================================================================
# Color and formatting
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# =============================================================================
# Defaults
# =============================================================================
TARGET=""
DOMAIN=""
OUTPUT_DIR=""
STEPS="all"
TIMING=4
WORDLIST_DIR="/usr/share/seclists/Discovery/Web-Content/raft-medium-directories.txt"
WORDLIST_USERS="/usr/share/seclists/Usernames/top-usernames-shortlist.txt"
WORDLIST_SNMP="/usr/share/seclists/Discovery/SNMP/common-snmp-community-strings.txt"
WORDLIST_VHOSTS="/usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt"
VPN_CONF=""
VPN_IFACE="wg-enum"
VPN_KEEP=false
VPN_ACTIVE=false
SKIP_UDP=false
SKIP_BRUTEFORCE=false
DRY_RUN=false
# These get populated when --vpn is active, injected into tool commands
NMAP_IFACE_OPT=""
CURL_IFACE_OPT=""
OPEN_TCP_PORTS=""
OPEN_UDP_PORTS=""
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# =============================================================================
# Functions
# =============================================================================

usage() {
    sed -n '2,/^# =====/{ /^# =====/d; s/^# \?//; p }' "$0"
    exit 0
}

log_banner() {
    echo ""
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

log_step() {
    echo -e "${CYAN}[*]${NC} $1"
}

log_ok() {
    echo -e "${GREEN}[+]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[-]${NC} $1"
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
}

# Check if a command exists; return 0/1
has_cmd() {
    command -v "$1" &>/dev/null
}

# =============================================================================
# Auto-installation support
# =============================================================================
# Maps tool binary name → install method.
# Format: "apt:pkg" | "pip:pkg" | "go:module@version" | "snap:pkg" | "script:url"
# Multiple methods separated by ";" are tried in order.
declare -A TOOL_PKG_MAP=(
    # Passive recon
    [amass]="snap:amass;go:github.com/owasp-amass/amass/v4/...@master"
    [curl]="apt:curl"
    [dig]="apt:dnsutils"
    [whois]="apt:whois"
    [jq]="apt:jq"
    # Web
    [whatweb]="apt:whatweb"
    [testssl.sh]="apt:testssl"
    [feroxbuster]="apt:feroxbuster;snap:feroxbuster"
    [gobuster]="apt:gobuster;go:github.com/OJ/gobuster/v3@latest"
    [ffuf]="apt:ffuf;go:github.com/ffuf/ffuf/v2@latest"
    [nikto]="apt:nikto"
    [sslyze]="pip:sslyze"
    # Auth
    [ssh-audit]="apt:ssh-audit;pip:ssh-audit"
    # SMB
    [enum4linux-ng]="pip:enum4linux-ng"
    [smbclient]="apt:smbclient"
    [crackmapexec]="pip:crackmapexec"
    # Mail
    [smtp-user-enum]="apt:smtp-user-enum"
    # SNMP
    [onesixtyone]="apt:onesixtyone"
    [snmpwalk]="apt:snmp"
    [snmp-check]="apt:snmpcheck"
    # Database clients
    [mysql]="apt:default-mysql-client"
    [psql]="apt:postgresql-client"
    [redis-cli]="apt:redis-tools"
    [mongosh]="apt:mongosh"
    # NFS / LDAP
    [rpcinfo]="apt:rpcbind"
    [showmount]="apt:nfs-common"
    [ldapsearch]="apt:ldap-utils"
    # Vuln scanning
    [nuclei]="go:github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
    [searchsploit]="apt:exploitdb"
    [sqlmap]="apt:sqlmap"
    # Required
    [nmap]="apt:nmap"
    # VPN
    [wg]="apt:wireguard-tools"
    [wg-quick]="apt:wireguard-tools"
)

# Track tools that failed installation so we don't retry
declare -A INSTALL_FAILED=()

# Install a tool by its binary name. Returns 0 on success, 1 on failure.
install_tool() {
    local tool="$1"
    local methods="${TOOL_PKG_MAP[$tool]:-}"

    if [ -z "$methods" ]; then
        log_warn "No install method known for '$tool'"
        INSTALL_FAILED[$tool]=1
        return 1
    fi

    log_step "Attempting to install '$tool'..."

    # Try each method separated by ;
    IFS=';' read -ra METHOD_LIST <<< "$methods"
    for method in "${METHOD_LIST[@]}"; do
        local type="${method%%:*}"
        local pkg="${method#*:}"

        case "$type" in
            apt)
                log_step "  Trying: apt-get install -y $pkg"
                if apt-get install -y "$pkg" >> /tmp/enumerate_install.log 2>&1; then
                    if has_cmd "$tool"; then
                        log_ok "Installed '$tool' via apt ($pkg)"
                        return 0
                    fi
                fi
                ;;
            pip)
                log_step "  Trying: pip install $pkg"
                if pip install "$pkg" >> /tmp/enumerate_install.log 2>&1 || \
                   pip3 install "$pkg" >> /tmp/enumerate_install.log 2>&1; then
                    if has_cmd "$tool"; then
                        log_ok "Installed '$tool' via pip ($pkg)"
                        return 0
                    fi
                fi
                ;;
            go)
                if has_cmd go; then
                    log_step "  Trying: go install $pkg"
                    if go install "$pkg" >> /tmp/enumerate_install.log 2>&1; then
                        # go installs to $GOPATH/bin or ~/go/bin
                        export PATH="$PATH:${GOPATH:-$HOME/go}/bin"
                        if has_cmd "$tool"; then
                            log_ok "Installed '$tool' via go ($pkg)"
                            return 0
                        fi
                    fi
                fi
                ;;
            snap)
                if has_cmd snap; then
                    log_step "  Trying: snap install $pkg"
                    if snap install "$pkg" >> /tmp/enumerate_install.log 2>&1; then
                        if has_cmd "$tool"; then
                            log_ok "Installed '$tool' via snap ($pkg)"
                            return 0
                        fi
                    fi
                fi
                ;;
        esac
    done

    log_warn "Failed to install '$tool' (tried: $methods). Skipping related checks."
    log_warn "  Install log: /tmp/enumerate_install.log"
    INSTALL_FAILED[$tool]=1
    return 1
}

# Ensure a command is available: check → install → check again.
# Returns 0 if the tool is available (or was just installed), 1 if not.
ensure_cmd() {
    local tool="$1"
    has_cmd "$tool" && return 0
    # Already failed? Don't retry.
    [ "${INSTALL_FAILED[$tool]:-0}" = "1" ] && return 1
    install_tool "$tool"
}

# Install seclists wordlists if any are missing
ensure_wordlists() {
    local missing=false
    for wl in "$WORDLIST_DIR" "$WORDLIST_USERS" "$WORDLIST_SNMP" "$WORDLIST_VHOSTS"; do
        [ ! -f "$wl" ] && missing=true
    done
    if $missing; then
        log_step "SecLists wordlists missing. Attempting install..."
        if apt-get install -y seclists >> /tmp/enumerate_install.log 2>&1; then
            log_ok "SecLists installed"
        elif has_cmd git; then
            log_step "Falling back to git clone..."
            if [ ! -d /usr/share/seclists ]; then
                git clone --depth 1 https://github.com/danielmiessler/SecLists.git /usr/share/seclists \
                    >> /tmp/enumerate_install.log 2>&1 && log_ok "SecLists cloned" || \
                    log_warn "Failed to install SecLists. Brute-force steps may be skipped."
            fi
        else
            log_warn "Cannot install SecLists (no apt or git). Brute-force steps may be skipped."
        fi
    fi
}

# =============================================================================
# WireGuard VPN tunnel management
# =============================================================================

# Bring up a WireGuard tunnel from a .conf file.
# Supports both wg-quick configs and raw WireGuard configs.
vpn_up() {
    local conf="$1"
    local iface="$2"

    if [ ! -f "$conf" ]; then
        log_error "WireGuard config not found: $conf"
        exit 1
    fi

    ensure_cmd wg || {
        log_error "WireGuard tools (wg) could not be installed. Cannot set up VPN."
        exit 1
    }

    # If the interface is already up, skip
    if ip link show "$iface" &>/dev/null; then
        log_warn "WireGuard interface '$iface' already exists — reusing it"
        VPN_ACTIVE=true
        return 0
    fi

    log_step "Bringing up WireGuard tunnel ($iface) from $conf"

    # Detect config type: wg-quick configs have Address/DNS lines, raw ones don't
    if grep -qiE '^\s*(Address|DNS|PostUp|PreDown)\s*=' "$conf" 2>/dev/null; then
        # wg-quick style config — use wg-quick with a custom interface name
        log_step "Detected wg-quick config format"

        # wg-quick uses the filename stem as the interface name, so we
        # symlink the config to /etc/wireguard/<iface>.conf
        local wg_dir="/etc/wireguard"
        mkdir -p "$wg_dir"
        local target_conf="$wg_dir/${iface}.conf"

        if [ "$(realpath "$conf" 2>/dev/null)" != "$(realpath "$target_conf" 2>/dev/null)" ]; then
            cp "$conf" "$target_conf"
            chmod 600 "$target_conf"
        fi

        if $DRY_RUN; then
            echo -e "  ${YELLOW}[DRY-RUN]${NC} wg-quick up $iface"
            VPN_ACTIVE=true
            return 0
        fi

        wg-quick up "$iface" 2>&1 | while IFS= read -r line; do
            log_step "  wg-quick: $line"
        done

    else
        # Raw WireGuard config — use ip + wg directly
        log_step "Detected raw WireGuard config format"

        if $DRY_RUN; then
            echo -e "  ${YELLOW}[DRY-RUN]${NC} ip link add $iface type wireguard && wg setconf $iface $conf"
            VPN_ACTIVE=true
            return 0
        fi

        ip link add "$iface" type wireguard
        wg setconf "$iface" "$conf"

        # Extract Address from config if present (some raw configs still have it as a comment)
        # Otherwise user must have routing set up already
        local addr
        addr=$(grep -oP '^\s*#?\s*Address\s*=\s*\K\S+' "$conf" 2>/dev/null | head -1 || true)
        if [ -n "$addr" ]; then
            ip addr add "$addr" dev "$iface"
        fi

        ip link set "$iface" up
    fi

    # Verify the interface came up
    if ip link show "$iface" &>/dev/null; then
        VPN_ACTIVE=true
        local endpoint
        endpoint=$(wg show "$iface" endpoints 2>/dev/null | awk '{print $2}' | head -1)
        local pub_ip
        pub_ip=$(wg show "$iface" 2>/dev/null | grep -oP 'endpoint:\s*\K[^:]+' || echo "$endpoint")
        log_ok "WireGuard tunnel UP on $iface"
        [ -n "$endpoint" ] && log_ok "  Endpoint: $endpoint"

        # Show the tunnel's public IP (what the target sees)
        if ! $DRY_RUN && ensure_cmd curl; then
            local my_ip
            my_ip=$(curl -s --max-time 5 --interface "$iface" https://ifconfig.me 2>/dev/null || \
                    curl -s --max-time 5 --interface "$iface" https://api.ipify.org 2>/dev/null || \
                    echo "(could not determine)")
            log_ok "  Your exit IP: $my_ip"
        fi
    else
        log_error "WireGuard interface '$iface' failed to come up"
        exit 1
    fi

    # Add a route for the target through the WireGuard interface
    # Only if AllowedIPs doesn't already cover it (0.0.0.0/0 = full tunnel)
    local allowed_ips
    allowed_ips=$(wg show "$iface" allowed-ips 2>/dev/null | awk '{print $2}')
    if echo "$allowed_ips" | grep -qE '0\.0\.0\.0/0|::/0'; then
        log_ok "  Full tunnel detected (0.0.0.0/0) — all traffic routed via VPN"
    else
        # Split tunnel — add an explicit route for the target
        log_step "  Split tunnel — adding route for $TARGET via $iface"
        ip route add "$TARGET/32" dev "$iface" 2>/dev/null || \
            log_warn "  Could not add route for $TARGET (may already exist)"
    fi
}

# Tear down the WireGuard tunnel
vpn_down() {
    local iface="$1"

    if ! $VPN_ACTIVE; then
        return 0
    fi

    if $VPN_KEEP; then
        log_warn "Leaving WireGuard tunnel '$iface' UP (--vpn-keep)"
        return 0
    fi

    log_step "Tearing down WireGuard tunnel ($iface)"

    # Try wg-quick first (if that's how it was brought up)
    if wg-quick down "$iface" 2>/dev/null; then
        log_ok "WireGuard tunnel '$iface' is DOWN (wg-quick)"
    else
        # Manual teardown
        ip link set "$iface" down 2>/dev/null || true
        ip link del "$iface" 2>/dev/null || true
        log_ok "WireGuard tunnel '$iface' is DOWN"
    fi

    # Clean up the config copy if we made one
    rm -f "/etc/wireguard/${iface}.conf" 2>/dev/null || true

    VPN_ACTIVE=false
}

# Verify connectivity to the target through the VPN
vpn_verify() {
    local iface="$1"

    if $DRY_RUN; then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} Connectivity check: ping -c1 -W3 -I $iface $TARGET"
        return 0
    fi

    log_step "Verifying connectivity to $TARGET via $iface"

    # Try ICMP first
    if ping -c1 -W3 -I "$iface" "$TARGET" &>/dev/null; then
        log_ok "Target $TARGET is reachable via $iface (ICMP)"
        return 0
    fi

    # ICMP might be blocked — try a TCP connection on a common port
    log_warn "ICMP blocked or no reply — trying TCP probe"
    if ensure_cmd nmap; then
        local result
        result=$(nmap -sn -e "$iface" "$TARGET" 2>/dev/null | grep -c "Host is up" || true)
        if [ "$result" -ge 1 ] 2>/dev/null; then
            log_ok "Target $TARGET is reachable via $iface (TCP probe)"
            return 0
        fi
    fi

    log_warn "Could not confirm connectivity to $TARGET via $iface"
    log_warn "Scan will proceed anyway — results may be incomplete if tunnel is misconfigured"
    return 0
}

# Run a command, log it, handle dry-run mode. Captures output to a file.
# Usage: run_cmd <description> <output_file> <command...>
run_cmd() {
    local desc="$1"
    local outfile="$2"
    shift 2

    log_step "$desc"

    if $DRY_RUN; then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} $*"
        return 0
    fi

    if eval "$@" >> "$outfile" 2>&1; then
        log_ok "Done → $outfile"
    else
        local rc=$?
        # Non-zero exit is common for scanning tools (e.g., no results found)
        if [ $rc -eq 1 ]; then
            log_warn "Completed with warnings → $outfile"
        else
            log_warn "Exited with code $rc → $outfile"
        fi
    fi
    return 0
}

# Run a command, auto-installing the tool if needed. Skips only if install fails.
# Usage: run_if <tool_name> <description> <output_file> <command...>
run_if() {
    local tool="$1"
    local desc="$2"
    local outfile="$3"
    shift 3

    if ensure_cmd "$tool"; then
        run_cmd "$desc" "$outfile" "$@"
    else
        log_skip "$desc (${tool} not available — install failed)"
    fi
}

# Check if a port is in the open TCP ports list
port_open() {
    local port="$1"
    echo ",$OPEN_TCP_PORTS," | grep -q ",$port,"
}

# Check if a UDP port is in the open UDP ports list
udp_port_open() {
    local port="$1"
    echo ",$OPEN_UDP_PORTS," | grep -q ",$port,"
}

# Check if a step should run
should_run() {
    local step="$1"
    if [ "$STEPS" = "all" ]; then
        return 0
    fi
    echo ",$STEPS," | grep -q ",$step,"
}

# Extract open TCP ports from nmap gnmap output
extract_tcp_ports() {
    local gnmap_file="$1"
    if [ -f "$gnmap_file" ]; then
        grep -oP '\d+/open/tcp' "$gnmap_file" | cut -d/ -f1 | sort -un | tr '\n' ',' | sed 's/,$//'
    fi
}

# Extract open UDP ports from nmap gnmap output
extract_udp_ports() {
    local gnmap_file="$1"
    if [ -f "$gnmap_file" ]; then
        grep -oP '\d+/open/udp' "$gnmap_file" | cut -d/ -f1 | sort -un | tr '\n' ',' | sed 's/,$//'
    fi
}

# =============================================================================
# Argument parsing
# =============================================================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--domain)    DOMAIN="$2"; shift 2 ;;
        -o|--output)    OUTPUT_DIR="$2"; shift 2 ;;
        -s|--steps)     STEPS="$2"; shift 2 ;;
        -t|--timing)    TIMING="$2"; shift 2 ;;
        -w|--wordlist)  WORDLIST_DIR="$2"; shift 2 ;;
        --vpn)          VPN_CONF="$2"; shift 2 ;;
        --vpn-iface)    VPN_IFACE="$2"; shift 2 ;;
        --vpn-keep)     VPN_KEEP=true; shift ;;
        --skip-udp)     SKIP_UDP=true; shift ;;
        --skip-bruteforce) SKIP_BRUTEFORCE=true; shift ;;
        --dry-run)      DRY_RUN=true; shift ;;
        -h|--help)      usage ;;
        -*)             log_error "Unknown option: $1"; usage ;;
        *)
            if [ -z "$TARGET" ]; then
                TARGET="$1"
            else
                log_error "Unexpected argument: $1"
                usage
            fi
            shift
            ;;
    esac
done

if [ -z "$TARGET" ]; then
    log_error "No target specified."
    echo ""
    usage
fi

# =============================================================================
# Cleanup trap — ensure VPN tunnel is torn down on exit/interrupt
# =============================================================================
cleanup() {
    if $VPN_ACTIVE && [ -n "$VPN_IFACE" ]; then
        echo ""
        vpn_down "$VPN_IFACE"
    fi
}
trap cleanup EXIT INT TERM

# =============================================================================
# WireGuard VPN setup (if --vpn specified)
# =============================================================================
if [ -n "$VPN_CONF" ]; then
    log_banner "WireGuard VPN Setup"
    vpn_up "$VPN_CONF" "$VPN_IFACE"
    vpn_verify "$VPN_IFACE"

    # Set interface options for tools that support source binding
    NMAP_IFACE_OPT="-e $VPN_IFACE "
    CURL_IFACE_OPT="--interface $VPN_IFACE "
    log_ok "Tools will bind to interface: $VPN_IFACE"
    echo ""
fi

# =============================================================================
# Setup
# =============================================================================

# Resolve domain from reverse DNS if not provided
if [ -z "$DOMAIN" ]; then
    if ensure_cmd dig; then
        DOMAIN=$(dig +short -x "$TARGET" +timeout=3 +tries=1 2>/dev/null | grep -v '^;' | head -1 | sed 's/\.$//' | awk -F. '{if(NF>=2) print $(NF-1)"."$NF}' || true)
    fi
    if [ -z "$DOMAIN" ]; then
        DOMAIN="$TARGET"
        log_warn "No domain resolved from reverse DNS. Using IP as domain. Pass -d to set manually."
    else
        log_ok "Resolved domain from rDNS: $DOMAIN"
    fi
fi

# Output directory
if [ -z "$OUTPUT_DIR" ]; then
    OUTPUT_DIR="./enum_${TARGET}_${TIMESTAMP}"
fi

mkdir -p "$OUTPUT_DIR"/{passive,ports,web,auth,smb,mail,snmp,db,nfs,vulns,report}

# Root check
if [ "$(id -u)" -ne 0 ] && ! $DRY_RUN; then
    log_warn "Not running as root. SYN scans, OS detection, and some tools will fail."
    log_warn "Re-run with: sudo $0 $TARGET $*"
    echo ""
fi

# =============================================================================
# Pre-flight: tool detection and auto-installation
# =============================================================================
log_banner "Pre-flight Check"

# Update apt cache once if we'll need to install anything
APT_UPDATED=false
preflight_apt_update() {
    if ! $APT_UPDATED; then
        log_step "Updating apt package cache..."
        apt-get update -qq >> /tmp/enumerate_install.log 2>&1 || true
        APT_UPDATED=true
    fi
}

REQUIRED_TOOLS=(nmap)
OPTIONAL_TOOLS=(
    curl dig whois jq                                                # passive (amass installed on-demand)
    whatweb nikto                                                     # web
    ssh-audit                                                        # auth
    smbclient                                                        # smb
    snmpwalk                                                         # snmp
    ldapsearch                                                       # nfs/ldap
)

# Install required tools first
for tool in "${REQUIRED_TOOLS[@]}"; do
    if has_cmd "$tool"; then
        log_ok "$tool found"
    else
        log_warn "$tool not found — attempting install..."
        preflight_apt_update
        if install_tool "$tool"; then
            log_ok "$tool installed successfully"
        else
            log_error "$tool is REQUIRED and could not be installed. Aborting."
            exit 1
        fi
    fi
done

# Pre-install common optional tools (the rest install on-demand during steps)
INSTALLED_COUNT=0
FAILED_COUNT=0
for tool in "${OPTIONAL_TOOLS[@]}"; do
    if has_cmd "$tool"; then
        echo -e "  ${GREEN}✓${NC} $tool"
    else
        preflight_apt_update
        if install_tool "$tool"; then
            echo -e "  ${GREEN}✓${NC} $tool (just installed)"
            ((INSTALLED_COUNT++)) || true
        else
            echo -e "  ${RED}✗${NC} $tool (install failed — will skip)"
            ((FAILED_COUNT++)) || true
        fi
    fi
done

# Install wordlists
ensure_wordlists

if [ "$INSTALLED_COUNT" -gt 0 ]; then
    log_ok "$INSTALLED_COUNT tools installed during pre-flight"
fi
if [ "$FAILED_COUNT" -gt 0 ]; then
    log_warn "$FAILED_COUNT tools could not be installed. Related steps will run on-demand or be skipped."
fi

echo ""
log_step "Target:  $TARGET"
log_step "Domain:  $DOMAIN"
log_step "Output:  $OUTPUT_DIR"
log_step "Timing:  T${TIMING}"
log_step "Steps:   $STEPS"
echo ""

# Write run metadata
cat > "$OUTPUT_DIR/report/run_info.txt" <<EOF
Enumeration Run
===============
Target:     $TARGET
Domain:     $DOMAIN
Output:     $OUTPUT_DIR
Timing:     T${TIMING}
Steps:      $STEPS
Started:    $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Skip UDP:   $SKIP_UDP
Skip Brute: $SKIP_BRUTEFORCE
Dry Run:    $DRY_RUN
VPN Config: ${VPN_CONF:-none}
VPN Iface:  ${VPN_ACTIVE:+$VPN_IFACE}${VPN_ACTIVE:-none}
Run As:     $(whoami)
EOF

# =============================================================================
# STEP 1: Passive Intelligence Gathering
# =============================================================================
if should_run 1; then
    log_banner "Step 1/11: Passive Intelligence Gathering"

    P="$OUTPUT_DIR/passive"

    run_if whois "WHOIS lookup on domain" "$P/whois_domain.txt" \
        "whois '$DOMAIN'"

    run_if whois "WHOIS lookup on IP" "$P/whois_ip.txt" \
        "whois '$TARGET'"

    run_if dig "DNS ANY records" "$P/dns_any.txt" \
        "dig any '$DOMAIN' +noall +answer"

    run_if dig "DNS TXT records" "$P/dns_txt.txt" \
        "dig txt '$DOMAIN' +noall +answer"

    run_if dig "DNS MX records" "$P/dns_mx.txt" \
        "dig mx '$DOMAIN' +noall +answer"

    run_if dig "DNS NS records" "$P/dns_ns.txt" \
        "dig ns '$DOMAIN' +noall +answer"

    # Zone transfer attempt against each name server
    if ensure_cmd dig; then
        log_step "Attempting zone transfers"
        if ! $DRY_RUN; then
            for ns in $(dig ns "$DOMAIN" +short 2>/dev/null); do
                log_step "  Zone transfer via $ns"
                dig axfr "$DOMAIN" "@$ns" >> "$P/zone_transfer.txt" 2>&1 || true
            done
            if [ -s "$P/zone_transfer.txt" ]; then
                log_ok "Zone transfer results → $P/zone_transfer.txt"
            else
                log_warn "Zone transfers failed (expected — most servers block this)"
            fi
        fi
    fi

    run_if amass "Passive subdomain enumeration (amass)" "$P/amass_subs.txt" \
        "amass enum -passive -d '$DOMAIN' -timeout 5"

    # Certificate transparency via crt.sh
    if ensure_cmd curl && ensure_cmd jq; then
        run_cmd "Certificate transparency lookup (crt.sh)" "$P/ct_subs.txt" \
            "curl -s $CURL_IFACE_OPT'https://crt.sh/?q=%25.$DOMAIN&output=json' | jq -r '.[].name_value' 2>/dev/null | sort -u"
    fi

    # Combine and deduplicate subdomains
    if ! $DRY_RUN; then
        cat "$P"/amass_subs.txt "$P"/ct_subs.txt 2>/dev/null | \
            grep -v "^$" | sort -u > "$P/all_subs.txt" 2>/dev/null || true
        local_count=$(wc -l < "$P/all_subs.txt" 2>/dev/null || echo 0)
        log_ok "Combined ${local_count} unique subdomains → $P/all_subs.txt"

        # Resolve subdomains
        if [ -s "$P/all_subs.txt" ] && ensure_cmd dig; then
            log_step "Resolving discovered subdomains"
            while IFS= read -r sub; do
                ip=$(dig +short "$sub" 2>/dev/null | head -1)
                [ -n "$ip" ] && echo "$sub -> $ip"
            done < "$P/all_subs.txt" > "$P/resolved_hosts.txt" 2>/dev/null || true
            log_ok "Resolved hosts → $P/resolved_hosts.txt"
        fi
    fi
fi

# =============================================================================
# STEP 2: Active Host Discovery and Port Scanning
# =============================================================================
if should_run 2; then
    log_banner "Step 2/11: Port Scanning"

    S="$OUTPUT_DIR/ports"

    # Full TCP SYN scan
    run_cmd "TCP SYN scan — all 65535 ports" "$S/tcp_scan.log" \
        "nmap $NMAP_IFACE_OPT-sS -p- --min-rate 10000 -T${TIMING} '$TARGET' -oA '$S/tcp_all_ports'"

    # Extract open ports
    if ! $DRY_RUN; then
        OPEN_TCP_PORTS=$(extract_tcp_ports "$S/tcp_all_ports.gnmap")
        if [ -n "$OPEN_TCP_PORTS" ]; then
            log_ok "Open TCP ports: $OPEN_TCP_PORTS"
            echo "$OPEN_TCP_PORTS" > "$S/open_tcp_ports.txt"
        else
            log_warn "No open TCP ports found"
        fi
    fi

    # Detailed service scan on open ports
    if [ -n "$OPEN_TCP_PORTS" ] || $DRY_RUN; then
        run_cmd "Service version detection + NSE scripts" "$S/detailed_scan.log" \
            "nmap $NMAP_IFACE_OPT-sV -sC -O -p '${OPEN_TCP_PORTS:-1-1000}' -T${TIMING} '$TARGET' -oA '$S/detailed_scan'"
    fi

    # UDP scan
    if ! $SKIP_UDP; then
        run_cmd "UDP scan — top 50 ports" "$S/udp_scan.log" \
            "nmap $NMAP_IFACE_OPT-sU --top-ports 50 -T${TIMING} '$TARGET' -oA '$S/udp_scan'"

        if ! $DRY_RUN; then
            OPEN_UDP_PORTS=$(extract_udp_ports "$S/udp_scan.gnmap")
            if [ -n "$OPEN_UDP_PORTS" ]; then
                log_ok "Open UDP ports: $OPEN_UDP_PORTS"
                echo "$OPEN_UDP_PORTS" > "$S/open_udp_ports.txt"
            fi
        fi
    else
        log_skip "UDP scan (--skip-udp)"
    fi

    # OS fingerprinting
    run_cmd "OS fingerprinting" "$S/os_fingerprint.log" \
        "nmap $NMAP_IFACE_OPT-O --osscan-guess -T${TIMING} '$TARGET' -oA '$S/os_fingerprint'"
fi

# Reload ports from disk if running selective steps
if [ -z "$OPEN_TCP_PORTS" ] && [ -f "$OUTPUT_DIR/ports/open_tcp_ports.txt" ]; then
    OPEN_TCP_PORTS=$(cat "$OUTPUT_DIR/ports/open_tcp_ports.txt")
fi
if [ -z "$OPEN_UDP_PORTS" ] && [ -f "$OUTPUT_DIR/ports/open_udp_ports.txt" ]; then
    OPEN_UDP_PORTS=$(cat "$OUTPUT_DIR/ports/open_udp_ports.txt")
fi

# =============================================================================
# STEP 3: Web Service Enumeration (80/443)
# =============================================================================
if should_run 3; then
    log_banner "Step 3/11: Web Service Enumeration"

    W="$OUTPUT_DIR/web"

    # Determine which web ports are open
    WEB_PORTS=""
    for p in 80 443 8080 8443 8000 8888 3000 5000 9443; do
        if port_open "$p"; then
            WEB_PORTS="${WEB_PORTS:+$WEB_PORTS,}$p"
        fi
    done

    if [ -z "$WEB_PORTS" ] && ! $DRY_RUN; then
        log_skip "No web ports detected in open ports list"
    else
        # Determine base URL (prefer HTTPS)
        if port_open 443 || $DRY_RUN; then
            BASE_URL="https://$TARGET"
        else
            BASE_URL="http://$TARGET"
        fi

        run_if whatweb "Technology fingerprinting (whatweb)" "$W/whatweb.txt" \
            "whatweb -a 3 '$BASE_URL' 2>&1"

        # TLS audit (only if 443 is open)
        if port_open 443 || $DRY_RUN; then
            run_if testssl.sh "TLS configuration audit" "$W/tls_audit.txt" \
                "testssl.sh --quiet --color 0 '$TARGET'"

            run_if sslyze "TLS scan (sslyze)" "$W/sslyze.txt" \
                "sslyze '$TARGET'"
        fi

        # Sensitive file checks
        if ensure_cmd curl && ! $DRY_RUN; then
            log_step "Checking for sensitive file exposure"
            SENSITIVE_PATHS=(
                "/.git/HEAD" "/.env" "/robots.txt" "/sitemap.xml"
                "/.DS_Store" "/server-status" "/server-info"
                "/wp-config.php.bak" "/web.config" "/.htaccess"
                "/crossdomain.xml" "/clientaccesspolicy.xml"
                "/.well-known/security.txt" "/phpinfo.php"
                "/elmah.axd" "/trace.axd"
            )
            for path in "${SENSITIVE_PATHS[@]}"; do
                code=$(curl -sk $CURL_IFACE_OPT-o /dev/null -w "%{http_code}" --max-time 5 "${BASE_URL}${path}" 2>/dev/null || echo "000")
                status=""
                if [ "$code" = "200" ]; then
                    status="${GREEN}200 FOUND${NC}"
                elif [ "$code" = "403" ]; then
                    status="${YELLOW}403 FORBIDDEN${NC}"
                else
                    status="$code"
                fi
                echo -e "  $path → $status"
                echo "$path → $code" >> "$W/sensitive_files.txt"
            done
        fi

        # Directory brute-force
        if ! $SKIP_BRUTEFORCE; then
            if ensure_cmd feroxbuster; then
                run_cmd "Directory brute-force (feroxbuster)" "$W/feroxbuster.log" \
                    "feroxbuster -u '$BASE_URL' -w '$WORDLIST_DIR' -x php,html,txt,bak,json,xml -t 20 --rate-limit 100 -k --no-state -q -o '$W/ferox_dirs.txt' 2>&1"
            elif ensure_cmd gobuster; then
                run_cmd "Directory brute-force (gobuster)" "$W/gobuster.txt" \
                    "gobuster dir -u '$BASE_URL' -w '$WORDLIST_DIR' -x php,html,txt,bak -t 20 -k -q 2>&1"
            else
                log_skip "Directory brute-force (feroxbuster/gobuster — install failed)"
            fi

            # Virtual host enumeration
            if [ -f "$WORDLIST_VHOSTS" ]; then
                run_if ffuf "Virtual host enumeration" "$W/vhost_results.txt" \
                    "ffuf -u '$BASE_URL' -H 'Host: FUZZ.$DOMAIN' -w '$WORDLIST_VHOSTS' -fc 301,302,404 -mc all -fs 0 -o '$W/vhost_results.json' 2>&1"
            fi
        else
            log_skip "Directory and vhost brute-force (--skip-bruteforce)"
        fi

        # Nikto
        run_if nikto "Web vulnerability scan (nikto)" "$W/nikto.txt" \
            "nikto -h '$BASE_URL' -nointeractive -maxtime 300s -output '$W/nikto_results.txt' 2>&1"

        # Nuclei web-specific
        run_if nuclei "Web template scan (nuclei)" "$W/nuclei_web.txt" \
            "nuclei -u '$BASE_URL' -t http/ -t misconfigurations/ -t exposures/ -severity critical,high,medium -nc -o '$W/nuclei_web_results.txt' 2>&1"
    fi
fi

# =============================================================================
# STEP 4: Authentication Service Enumeration (SSH, FTP, RDP)
# =============================================================================
if should_run 4; then
    log_banner "Step 4/11: Authentication Service Enumeration"

    A="$OUTPUT_DIR/auth"

    # SSH
    if port_open 22 || $DRY_RUN; then
        run_if ssh-audit "SSH configuration audit" "$A/ssh_audit.txt" \
            "ssh-audit '$TARGET'"

        run_cmd "SSH nmap scripts" "$A/ssh_nmap.txt" \
            "nmap $NMAP_IFACE_OPT--script ssh2-enum-algos,ssh-auth-methods -p 22 -T${TIMING} '$TARGET'"
    else
        log_skip "SSH (port 22 not open)"
    fi

    # FTP
    if port_open 21 || $DRY_RUN; then
        run_cmd "FTP enumeration (anonymous check)" "$A/ftp_nmap.txt" \
            "nmap $NMAP_IFACE_OPT--script ftp-anon,ftp-syst,ftp-vsftpd-backdoor -p 21 -T${TIMING} '$TARGET'"
    else
        log_skip "FTP (port 21 not open)"
    fi

    # RDP
    if port_open 3389 || $DRY_RUN; then
        run_cmd "RDP enumeration" "$A/rdp_nmap.txt" \
            "nmap $NMAP_IFACE_OPT--script rdp-enum-encryption,rdp-ntlm-info -p 3389 -T${TIMING} '$TARGET'"
    else
        log_skip "RDP (port 3389 not open)"
    fi

    # Telnet
    if port_open 23; then
        run_cmd "Telnet banner grab" "$A/telnet_nmap.txt" \
            "nmap $NMAP_IFACE_OPT--script telnet-ntlm-info -p 23 -T${TIMING} '$TARGET'"
    fi
fi

# =============================================================================
# STEP 5: SMB / Windows Enumeration (139/445)
# =============================================================================
if should_run 5; then
    log_banner "Step 5/11: SMB / Windows Enumeration"

    S="$OUTPUT_DIR/smb"

    if port_open 445 || port_open 139 || $DRY_RUN; then
        run_if enum4linux-ng "Full SMB enumeration (enum4linux-ng)" "$S/enum4linux.txt" \
            "enum4linux-ng -A '$TARGET'"

        run_if smbclient "List SMB shares (null session)" "$S/smbclient.txt" \
            "smbclient -L '//$TARGET' -N"

        run_if crackmapexec "SMB share enumeration (crackmapexec)" "$S/cme_shares.txt" \
            "crackmapexec smb '$TARGET' --shares -u '' -p ''"

        run_cmd "SMB vulnerability scan (nmap)" "$S/smb_vulns.txt" \
            "nmap $NMAP_IFACE_OPT--script smb-vuln-ms17-010,smb-vuln-ms08-067,smb-vuln-cve-2020-0796,smb-enum-shares,smb-enum-users -p 445 -T${TIMING} '$TARGET'"

        run_if crackmapexec "RID brute-force (user enumeration)" "$S/rid_brute.txt" \
            "crackmapexec smb '$TARGET' -u '' -p '' --rid-brute"
    else
        log_skip "SMB (ports 139/445 not open)"
    fi
fi

# =============================================================================
# STEP 6: Mail Enumeration (SMTP 25/465/587)
# =============================================================================
if should_run 6; then
    log_banner "Step 6/11: Mail Service Enumeration"

    M="$OUTPUT_DIR/mail"

    if port_open 25 || port_open 465 || port_open 587 || $DRY_RUN; then
        # Determine SMTP port
        SMTP_PORT=25
        port_open 25 && SMTP_PORT=25
        port_open 587 && SMTP_PORT=587

        if ensure_cmd smtp-user-enum && [ -f "$WORDLIST_USERS" ]; then
            run_cmd "SMTP user enumeration (VRFY)" "$M/smtp_vrfy.txt" \
                "smtp-user-enum -M VRFY -U '$WORDLIST_USERS' -t '$TARGET' -p '$SMTP_PORT'"

            run_cmd "SMTP user enumeration (RCPT TO)" "$M/smtp_rcpt.txt" \
                "smtp-user-enum -M RCPT -U '$WORDLIST_USERS' -t '$TARGET' -p '$SMTP_PORT'"
        else
            log_skip "SMTP user enumeration (smtp-user-enum unavailable or wordlist missing)"
        fi

        run_cmd "SMTP open relay and banner" "$M/smtp_nmap.txt" \
            "nmap $NMAP_IFACE_OPT--script smtp-open-relay,smtp-commands,smtp-ntlm-info -p 25,465,587 -T${TIMING} '$TARGET'"
    else
        log_skip "SMTP (ports 25/465/587 not open)"
    fi
fi

# =============================================================================
# STEP 7: SNMP Enumeration (161/UDP)
# =============================================================================
if should_run 7; then
    log_banner "Step 7/11: SNMP Enumeration"

    SN="$OUTPUT_DIR/snmp"
    COMMUNITY_STRING=""

    if udp_port_open 161 || $DRY_RUN; then
        # Brute-force community strings
        if ensure_cmd onesixtyone && [ -f "$WORDLIST_SNMP" ]; then
            run_cmd "SNMP community string brute-force" "$SN/onesixtyone.txt" \
                "onesixtyone -c '$WORDLIST_SNMP' '$TARGET'"

            # Try to extract a found community string
            if ! $DRY_RUN && [ -s "$SN/onesixtyone.txt" ]; then
                COMMUNITY_STRING=$(grep -oP '\[\K[^\]]+' "$SN/onesixtyone.txt" | head -1 || echo "public")
                log_ok "Found community string: $COMMUNITY_STRING"
            fi
        fi

        [ -z "$COMMUNITY_STRING" ] && COMMUNITY_STRING="public"

        run_if snmpwalk "SNMP full MIB walk" "$SN/snmpwalk_full.txt" \
            "snmpwalk -v2c -c '$COMMUNITY_STRING' '$TARGET' 2>&1"

        # Targeted OID walks
        if ensure_cmd snmpwalk && ! $DRY_RUN; then
            log_step "Targeted SNMP OID walks"
            declare -A OIDS=(
                ["system_info"]="1.3.6.1.2.1.1"
                ["running_processes"]="1.3.6.1.2.1.25.4.2"
                ["tcp_connections"]="1.3.6.1.2.1.6.13"
                ["installed_software"]="1.3.6.1.2.1.25.6.3"
                ["interfaces"]="1.3.6.1.2.1.2.2"
            )
            for name in "${!OIDS[@]}"; do
                snmpwalk -v2c -c "$COMMUNITY_STRING" "$TARGET" "${OIDS[$name]}" \
                    > "$SN/snmp_${name}.txt" 2>&1 || true
            done
            log_ok "OID walk results → $SN/snmp_*.txt"
        fi

        run_if snmp-check "Automated SNMP enumeration" "$SN/snmpcheck.txt" \
            "snmp-check '$TARGET' -c '$COMMUNITY_STRING'"
    else
        log_skip "SNMP (UDP port 161 not detected as open)"
        log_warn "UDP scanning may have missed it. Run manually: snmpwalk -v2c -c public $TARGET"
    fi
fi

# =============================================================================
# STEP 8: Database Enumeration
# =============================================================================
if should_run 8; then
    log_banner "Step 8/11: Database Enumeration"

    D="$OUTPUT_DIR/db"

    # MySQL (3306)
    if port_open 3306 || $DRY_RUN; then
        run_cmd "MySQL nmap scripts" "$D/mysql_nmap.txt" \
            "nmap $NMAP_IFACE_OPT--script mysql-info,mysql-enum,mysql-empty-password -p 3306 -T${TIMING} '$TARGET'"

        run_if mysql "MySQL anonymous/root access check" "$D/mysql_access.txt" \
            "mysql -h '$TARGET' -u root --password='' -e 'SELECT user,host FROM mysql.user; SHOW DATABASES;' 2>&1"
    else
        log_skip "MySQL (port 3306 not open)"
    fi

    # PostgreSQL (5432)
    if port_open 5432 || $DRY_RUN; then
        run_cmd "PostgreSQL nmap scripts" "$D/pgsql_nmap.txt" \
            "nmap $NMAP_IFACE_OPT--script pgsql-brute -p 5432 -T${TIMING} '$TARGET'"

        run_if psql "PostgreSQL default credentials check" "$D/pgsql_access.txt" \
            "PGPASSWORD='' psql -h '$TARGET' -U postgres -c '\\l' 2>&1"
    else
        log_skip "PostgreSQL (port 5432 not open)"
    fi

    # MSSQL (1433)
    if port_open 1433 || $DRY_RUN; then
        run_cmd "MSSQL nmap scripts" "$D/mssql_nmap.txt" \
            "nmap $NMAP_IFACE_OPT--script ms-sql-info,ms-sql-ntlm-info,ms-sql-empty-password -p 1433 -T${TIMING} '$TARGET'"
    else
        log_skip "MSSQL (port 1433 not open)"
    fi

    # Redis (6379)
    if port_open 6379 || $DRY_RUN; then
        run_cmd "Redis nmap scripts" "$D/redis_nmap.txt" \
            "nmap $NMAP_IFACE_OPT--script redis-info -p 6379 -T${TIMING} '$TARGET'"

        if ensure_cmd redis-cli && ! $DRY_RUN; then
            log_step "Redis unauthenticated access check"
            {
                echo "=== INFO server ==="
                redis-cli -h "$TARGET" INFO server 2>&1 || true
                echo ""
                echo "=== CONFIG GET dir ==="
                redis-cli -h "$TARGET" CONFIG GET dir 2>&1 || true
                echo ""
                echo "=== DBSIZE ==="
                redis-cli -h "$TARGET" DBSIZE 2>&1 || true
            } > "$D/redis_access.txt"
            log_ok "Done → $D/redis_access.txt"
        fi
    else
        log_skip "Redis (port 6379 not open)"
    fi

    # MongoDB (27017)
    if port_open 27017 || $DRY_RUN; then
        run_cmd "MongoDB nmap scripts" "$D/mongo_nmap.txt" \
            "nmap $NMAP_IFACE_OPT--script mongodb-info,mongodb-databases -p 27017 -T${TIMING} '$TARGET'"

        run_if mongosh "MongoDB unauthenticated access check" "$D/mongo_access.txt" \
            "mongosh --host '$TARGET' --quiet --eval 'db.adminCommand(\"listDatabases\")' 2>&1"
    else
        log_skip "MongoDB (port 27017 not open)"
    fi
fi

# =============================================================================
# STEP 9: NFS, RPC, and LDAP Enumeration
# =============================================================================
if should_run 9; then
    log_banner "Step 9/11: NFS / RPC / LDAP Enumeration"

    N="$OUTPUT_DIR/nfs"

    # RPC (111)
    if port_open 111 || $DRY_RUN; then
        run_if rpcinfo "RPC service enumeration" "$N/rpcinfo.txt" \
            "rpcinfo -p '$TARGET'"

        run_cmd "NFS nmap scripts" "$N/nfs_nmap.txt" \
            "nmap $NMAP_IFACE_OPT--script nfs-ls,nfs-showmount,nfs-statfs -p 111,2049 -T${TIMING} '$TARGET'"
    else
        log_skip "RPC (port 111 not open)"
    fi

    # NFS (2049)
    if port_open 2049 || port_open 111 || $DRY_RUN; then
        run_if showmount "NFS export list" "$N/showmount.txt" \
            "showmount -e '$TARGET'"
    fi

    # LDAP (389/636)
    if port_open 389 || port_open 636 || $DRY_RUN; then
        LDAP_PROTO="ldap"
        LDAP_PORT=389
        if port_open 636; then
            LDAP_PROTO="ldaps"
            LDAP_PORT=636
        fi

        if ensure_cmd ldapsearch; then
            run_cmd "LDAP naming contexts" "$N/ldap_base.txt" \
                "ldapsearch -x -H '${LDAP_PROTO}://$TARGET:${LDAP_PORT}' -b '' -s base namingContexts 2>&1"

            # Extract base DN and do a broader search
            if ! $DRY_RUN; then
                BASE_DN=$(grep -oP 'namingContexts: \K.*' "$N/ldap_base.txt" | head -1 || echo "")
                if [ -n "$BASE_DN" ]; then
                    run_cmd "LDAP full directory dump" "$N/ldap_dump.txt" \
                        "ldapsearch -x -H '${LDAP_PROTO}://$TARGET:${LDAP_PORT}' -b '$BASE_DN' '(objectClass=*)' 2>&1"

                    run_cmd "LDAP user enumeration" "$N/ldap_users.txt" \
                        "ldapsearch -x -H '${LDAP_PROTO}://$TARGET:${LDAP_PORT}' -b '$BASE_DN' '(objectClass=person)' cn sAMAccountName mail 2>&1"
                fi
            fi
        else
            log_skip "LDAP enumeration (ldapsearch — install failed)"
        fi

        run_cmd "LDAP nmap scripts" "$N/ldap_nmap.txt" \
            "nmap $NMAP_IFACE_OPT--script ldap-rootdse,ldap-search -p 389,636 -T${TIMING} '$TARGET'"
    else
        log_skip "LDAP (ports 389/636 not open)"
    fi
fi

# =============================================================================
# STEP 10: Automated Vulnerability Scanning
# =============================================================================
if should_run 10; then
    log_banner "Step 10/11: Vulnerability Scanning"

    V="$OUTPUT_DIR/vulns"

    # Nuclei full scan
    if ensure_cmd nuclei; then
        NUCLEI_TARGETS=""
        # Build target list: web URLs + raw IP
        for p in 80 443 8080 8443; do
            if port_open "$p"; then
                proto="http"
                [ "$p" = "443" ] || [ "$p" = "8443" ] && proto="https"
                NUCLEI_TARGETS="${NUCLEI_TARGETS}${proto}://${TARGET}:${p}\n"
            fi
        done
        if [ -n "$NUCLEI_TARGETS" ]; then
            echo -e "$NUCLEI_TARGETS" > "$V/nuclei_targets.txt"
            run_cmd "Nuclei vulnerability scan" "$V/nuclei.log" \
                "nuclei -l '$V/nuclei_targets.txt' -t cves/ -t misconfigurations/ -t exposures/ -severity critical,high,medium -nc -o '$V/nuclei_results.txt' 2>&1"
        fi
    else
        log_skip "Nuclei scan (nuclei — install failed)"
    fi

    # Nmap vuln scripts across all open ports
    if [ -n "$OPEN_TCP_PORTS" ] || $DRY_RUN; then
        run_cmd "Nmap vulnerability scripts" "$V/nmap_vuln.log" \
            "nmap $NMAP_IFACE_OPT--script vuln -p '${OPEN_TCP_PORTS:-1-1000}' -T${TIMING} '$TARGET' -oA '$V/vuln_scan'"
    fi

    # searchsploit correlation from detailed scan
    if ensure_cmd searchsploit && [ -f "$OUTPUT_DIR/ports/detailed_scan.nmap" ]; then
        log_step "Correlating service versions with searchsploit"
        if ! $DRY_RUN; then
            grep -E "^\d+/tcp\s+open" "$OUTPUT_DIR/ports/detailed_scan.nmap" 2>/dev/null | while IFS= read -r line; do
                service=$(echo "$line" | awk '{for(i=3;i<=NF;i++) printf $i " "; print ""}' | sed 's/[[:space:]]*$//')
                if [ -n "$service" ]; then
                    echo "=== $service ===" >> "$V/searchsploit_results.txt"
                    searchsploit "$service" >> "$V/searchsploit_results.txt" 2>&1 || true
                    echo "" >> "$V/searchsploit_results.txt"
                fi
            done
            log_ok "searchsploit correlation → $V/searchsploit_results.txt"
        fi
    else
        log_skip "searchsploit correlation (searchsploit unavailable or no scan data)"
    fi
fi

# =============================================================================
# STEP 11: Consolidate and Report
# =============================================================================
if should_run 11; then
    log_banner "Step 11/11: Consolidation and Reporting"

    R="$OUTPUT_DIR/report"

    if $DRY_RUN; then
        log_step "[DRY-RUN] Would generate summary report"
    else
        log_step "Generating consolidated HTML report"
        HTML="$R/report.html"
        REPORT_DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

        # Update run info with end time
        echo "Completed:  ${REPORT_DATE}" >> "$R/run_info.txt"

        # ── Collect structured data ──────────────────────────────────────

        # Service summary from detailed nmap scan
        html_services=""
        if [ -f "$OUTPUT_DIR/ports/detailed_scan.nmap" ]; then
            while IFS= read -r line; do
                port_proto=$(echo "$line" | awk '{print $1}')
                state=$(echo "$line" | awk '{print $2}')
                service=$(echo "$line" | awk '{$1=$2=""; print $0}' | sed 's/^ *//')
                html_services+="<tr><td>${port_proto}</td><td>${state}</td><td>${service}</td></tr>"
            done < <(grep -E "^\d+/(tcp|udp)\s+open" "$OUTPUT_DIR/ports/detailed_scan.nmap" 2>/dev/null | sort -t/ -k1 -n)
        fi

        # Open ports
        html_tcp=""
        if [ -n "$OPEN_TCP_PORTS" ]; then
            while IFS= read -r port; do
                html_tcp+="<tr><td>${port}</td><td>TCP</td></tr>"
            done <<< "$(echo "$OPEN_TCP_PORTS" | tr ',' '\n')"
        fi
        html_udp=""
        if [ -n "$OPEN_UDP_PORTS" ]; then
            while IFS= read -r port; do
                html_udp+="<tr><td>${port}</td><td>UDP</td></tr>"
            done <<< "$(echo "$OPEN_UDP_PORTS" | tr ',' '\n')"
        fi

        # Vulnerability counts
        nuclei_critical=0; nuclei_high=0; nuclei_medium=0; nuclei_low=0
        if [ -f "$OUTPUT_DIR/vulns/nuclei_results.txt" ] && [ -s "$OUTPUT_DIR/vulns/nuclei_results.txt" ]; then
            nuclei_critical=$(grep -ci "critical" "$OUTPUT_DIR/vulns/nuclei_results.txt" 2>/dev/null || echo 0)
            nuclei_high=$(grep -ci "high" "$OUTPUT_DIR/vulns/nuclei_results.txt" 2>/dev/null || echo 0)
            nuclei_medium=$(grep -ci "medium" "$OUTPUT_DIR/vulns/nuclei_results.txt" 2>/dev/null || echo 0)
            nuclei_low=$(grep -ci "low" "$OUTPUT_DIR/vulns/nuclei_results.txt" 2>/dev/null || echo 0)
        fi

        # Key findings
        html_findings=""
        if [ -f "$OUTPUT_DIR/smb/cme_shares.txt" ] && grep -qi "READ" "$OUTPUT_DIR/smb/cme_shares.txt" 2>/dev/null; then
            html_findings+='<tr><td class="sev-high">HIGH</td><td>SMB shares accessible via null session</td></tr>'
        fi
        if [ -f "$OUTPUT_DIR/smb/smb_vulns.txt" ] && grep -qi "VULNERABLE" "$OUTPUT_DIR/smb/smb_vulns.txt" 2>/dev/null; then
            html_findings+='<tr><td class="sev-crit">CRITICAL</td><td>SMB vulnerabilities detected (EternalBlue / SMBGhost)</td></tr>'
        fi
        if [ -f "$OUTPUT_DIR/auth/ftp_nmap.txt" ] && grep -qi "Anonymous" "$OUTPUT_DIR/auth/ftp_nmap.txt" 2>/dev/null; then
            html_findings+='<tr><td class="sev-high">HIGH</td><td>FTP anonymous access enabled</td></tr>'
        fi
        if [ -f "$OUTPUT_DIR/db/redis_access.txt" ] && grep -qi "redis_version" "$OUTPUT_DIR/db/redis_access.txt" 2>/dev/null; then
            html_findings+='<tr><td class="sev-high">HIGH</td><td>Redis accessible without authentication</td></tr>'
        fi
        if [ -f "$OUTPUT_DIR/mail/smtp_nmap.txt" ] && grep -qi "open-relay" "$OUTPUT_DIR/mail/smtp_nmap.txt" 2>/dev/null; then
            html_findings+='<tr><td class="sev-high">HIGH</td><td>SMTP open relay detected</td></tr>'
        fi

        # Sensitive files
        html_sensitive=""
        if [ -f "$OUTPUT_DIR/web/sensitive_files.txt" ]; then
            while IFS= read -r line; do
                html_sensitive+="<tr><td class=\"sev-high\">EXPOSED</td><td>${line}</td></tr>"
            done < <(grep "200$" "$OUTPUT_DIR/web/sensitive_files.txt" 2>/dev/null || true)
        fi

        # ── Collect raw tool output into sections ────────────────────────

        # Helper: read a file, HTML-escape it, return as <pre> block
        html_file_block() {
            local filepath="$1"
            if [ -f "$filepath" ] && [ -s "$filepath" ]; then
                echo '<pre class="raw-output">'
                sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' < "$filepath"
                echo '</pre>'
            else
                echo '<p class="empty">No output captured.</p>'
            fi
        }

        # Define all sections: id|label|dir_glob
        # We walk each subdirectory and include every .txt/.nmap/.json file

        build_section() {
            local section_id="$1"
            local section_label="$2"
            local section_dir="$3"
            local has_files=false

            if [ ! -d "$section_dir" ]; then
                return
            fi

            local files
            files=$(find "$section_dir" -maxdepth 1 -type f \( -name "*.txt" -o -name "*.nmap" -o -name "*.json" \) 2>/dev/null | sort)
            [ -z "$files" ] && return

            echo "<h2 id=\"${section_id}\">${section_label}</h2>"
            while IFS= read -r f; do
                [ -z "$f" ] && continue
                local fname
                fname=$(basename "$f")
                local size
                size=$(du -h "$f" 2>/dev/null | awk '{print $1}')
                echo "<details><summary>${fname} <span class=\"file-size\">(${size})</span></summary>"
                html_file_block "$f"
                echo "</details>"
            done <<< "$files"
        }

        # Build all raw output sections into a variable
        raw_sections=""
        raw_sections+=$(build_section "passive" "Step 1: Passive Intelligence" "$OUTPUT_DIR/passive")
        raw_sections+=$(build_section "ports" "Step 2: Port Scanning" "$OUTPUT_DIR/ports")
        raw_sections+=$(build_section "web" "Step 3: Web Enumeration" "$OUTPUT_DIR/web")
        raw_sections+=$(build_section "smb" "Step 4: SMB / NetBIOS" "$OUTPUT_DIR/smb")
        raw_sections+=$(build_section "snmp" "Step 5: SNMP" "$OUTPUT_DIR/snmp")
        raw_sections+=$(build_section "mail" "Step 6: Mail Services" "$OUTPUT_DIR/mail")
        raw_sections+=$(build_section "db" "Step 7: Database Services" "$OUTPUT_DIR/db")
        raw_sections+=$(build_section "auth" "Step 8: Authentication" "$OUTPUT_DIR/auth")
        raw_sections+=$(build_section "vulns" "Step 9: Vulnerability Scanning" "$OUTPUT_DIR/vulns")
        raw_sections+=$(build_section "nfs" "Step 10: NFS / LDAP / RPC" "$OUTPUT_DIR/nfs")

        # Build table of contents entries for raw sections that exist
        toc_raw=""
        [ -d "$OUTPUT_DIR/passive" ] && [ -n "$(ls "$OUTPUT_DIR/passive"/*.txt 2>/dev/null)" ] && toc_raw+='<li><a href="#passive">Passive Intelligence</a></li>'
        [ -d "$OUTPUT_DIR/ports" ]   && [ -n "$(ls "$OUTPUT_DIR/ports"/*.txt "$OUTPUT_DIR/ports"/*.nmap 2>/dev/null)" ] && toc_raw+='<li><a href="#ports">Port Scanning</a></li>'
        [ -d "$OUTPUT_DIR/web" ]     && [ -n "$(ls "$OUTPUT_DIR/web"/*.txt 2>/dev/null)" ] && toc_raw+='<li><a href="#web">Web Enumeration</a></li>'
        [ -d "$OUTPUT_DIR/smb" ]     && [ -n "$(ls "$OUTPUT_DIR/smb"/*.txt 2>/dev/null)" ] && toc_raw+='<li><a href="#smb">SMB / NetBIOS</a></li>'
        [ -d "$OUTPUT_DIR/snmp" ]    && [ -n "$(ls "$OUTPUT_DIR/snmp"/*.txt 2>/dev/null)" ] && toc_raw+='<li><a href="#snmp">SNMP</a></li>'
        [ -d "$OUTPUT_DIR/mail" ]    && [ -n "$(ls "$OUTPUT_DIR/mail"/*.txt 2>/dev/null)" ] && toc_raw+='<li><a href="#mail">Mail Services</a></li>'
        [ -d "$OUTPUT_DIR/db" ]      && [ -n "$(ls "$OUTPUT_DIR/db"/*.txt 2>/dev/null)" ] && toc_raw+='<li><a href="#db">Database Services</a></li>'
        [ -d "$OUTPUT_DIR/auth" ]    && [ -n "$(ls "$OUTPUT_DIR/auth"/*.txt 2>/dev/null)" ] && toc_raw+='<li><a href="#auth">Authentication</a></li>'
        [ -d "$OUTPUT_DIR/vulns" ]   && [ -n "$(ls "$OUTPUT_DIR/vulns"/*.txt 2>/dev/null)" ] && toc_raw+='<li><a href="#vulns">Vulnerability Scanning</a></li>'
        [ -d "$OUTPUT_DIR/nfs" ]     && [ -n "$(ls "$OUTPUT_DIR/nfs"/*.txt 2>/dev/null)" ] && toc_raw+='<li><a href="#nfs">NFS / LDAP / RPC</a></li>'

        # ── Write HTML ───────────────────────────────────────────────────

        cat > "$HTML" <<HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Enumeration Report — ${TARGET}</title>
<style>
  :root { --bg: #0d1117; --card: #161b22; --border: #30363d; --text: #e6edf3;
          --muted: #8b949e; --accent: #58a6ff; --green: #3fb950; --yellow: #d29922;
          --orange: #db6d28; --red: #f85149; }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
         background: var(--bg); color: var(--text); line-height: 1.6; padding: 2rem; max-width: 1200px; margin: 0 auto; }
  a { color: var(--accent); text-decoration: none; }
  a:hover { text-decoration: underline; }
  h1 { font-size: 1.8rem; margin-bottom: .25rem; }
  .subtitle { color: var(--muted); margin-bottom: 1.5rem; }
  h2 { font-size: 1.2rem; color: var(--accent); margin: 2.5rem 0 .75rem; border-bottom: 1px solid var(--border);
       padding-bottom: .4rem; }
  .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 1rem; margin-bottom: 1rem; }
  .card { background: var(--card); border: 1px solid var(--border); border-radius: 8px; padding: 1rem; text-align: center; }
  .card .num { font-size: 2rem; font-weight: 700; }
  .card .label { color: var(--muted); font-size: .85rem; }
  .card.crit .num { color: var(--red); }
  .card.high .num { color: var(--orange); }
  .card.med  .num { color: var(--yellow); }
  .card.low  .num { color: var(--green); }
  table { width: 100%; border-collapse: collapse; margin-bottom: 1rem; }
  th, td { text-align: left; padding: .5rem .75rem; border-bottom: 1px solid var(--border); font-size: .9rem; }
  th { color: var(--muted); font-weight: 600; background: var(--card); }
  tr:hover td { background: var(--card); }
  .sev-crit { color: var(--red); font-weight: 700; }
  .sev-high { color: var(--orange); font-weight: 700; }
  .sev-med  { color: var(--yellow); font-weight: 700; }
  .sev-low  { color: var(--green); font-weight: 700; }
  .empty { color: var(--muted); font-style: italic; padding: 1rem 0; }

  /* Table of contents */
  .toc { background: var(--card); border: 1px solid var(--border); border-radius: 8px; padding: 1.25rem 1.5rem; margin-bottom: 1rem; }
  .toc h3 { font-size: 1rem; color: var(--muted); margin-bottom: .75rem; font-weight: 600; }
  .toc ul { list-style: none; columns: 2; column-gap: 2rem; }
  .toc li { padding: .2rem 0; font-size: .9rem; }
  .toc li::before { content: ""; }

  /* Collapsible raw output sections */
  details { margin-bottom: .5rem; border: 1px solid var(--border); border-radius: 6px; overflow: hidden; }
  details summary { padding: .6rem 1rem; background: var(--card); cursor: pointer; font-size: .9rem;
                    font-weight: 600; user-select: none; display: flex; align-items: center; justify-content: space-between; }
  details summary:hover { background: #1c2333; }
  details summary::marker { color: var(--accent); }
  .file-size { color: var(--muted); font-weight: 400; font-size: .8rem; }
  .raw-output { padding: 1rem; background: var(--bg); font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace;
                font-size: .78rem; line-height: 1.5; overflow-x: auto; white-space: pre-wrap; word-break: break-all;
                color: var(--muted); max-height: 600px; overflow-y: auto; margin: 0; }

  /* Run info */
  .run-info { background: var(--card); border: 1px solid var(--border); border-radius: 8px; padding: 1rem 1.25rem;
              font-size: .85rem; color: var(--muted); margin-bottom: 1.5rem; display: grid;
              grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: .5rem; }
  .run-info span { display: block; }
  .run-info strong { color: var(--text); }

  footer { margin-top: 3rem; color: var(--muted); font-size: .8rem; border-top: 1px solid var(--border); padding-top: 1rem; }
</style>
</head>
<body>

<h1>Enumeration Report</h1>
<p class="subtitle">Target: <strong>${TARGET}</strong> &mdash; Domain: <strong>${DOMAIN:-N/A}</strong> &mdash; ${REPORT_DATE}</p>

<div class="run-info">
  <span><strong>Target:</strong> ${TARGET}</span>
  <span><strong>Domain:</strong> ${DOMAIN:-N/A}</span>
  <span><strong>Timing:</strong> T${TIMING}</span>
  <span><strong>Steps:</strong> ${STEPS}</span>
  <span><strong>Started:</strong> $(grep 'Started:' "$R/run_info.txt" 2>/dev/null | sed 's/.*: *//' || echo 'N/A')</span>
  <span><strong>Completed:</strong> ${REPORT_DATE}</span>
</div>

<div class="toc">
  <h3>Contents</h3>
  <ul>
    <li><a href="#vuln-overview">Vulnerability Overview</a></li>
    <li><a href="#open-ports">Open Ports</a></li>
    <li><a href="#services">Service Versions</a></li>
    <li><a href="#findings">Key Findings</a></li>
    <li><a href="#sensitive">Sensitive Files</a></li>
    ${toc_raw}
  </ul>
</div>

<h2 id="vuln-overview">Vulnerability Overview</h2>
<div class="cards">
  <div class="card crit"><div class="num">${nuclei_critical}</div><div class="label">Critical</div></div>
  <div class="card high"><div class="num">${nuclei_high}</div><div class="label">High</div></div>
  <div class="card med"><div class="num">${nuclei_medium}</div><div class="label">Medium</div></div>
  <div class="card low"><div class="num">${nuclei_low}</div><div class="label">Low</div></div>
</div>

<h2 id="open-ports">Open Ports</h2>
$(if [ -n "$html_tcp" ] || [ -n "$html_udp" ]; then
    echo '<table><tr><th>Port</th><th>Protocol</th></tr>'
    echo "${html_tcp}${html_udp}"
    echo '</table>'
else
    echo '<p class="empty">No open ports detected or scan not run.</p>'
fi)

<h2 id="services">Service Versions</h2>
$(if [ -n "$html_services" ]; then
    echo '<table><tr><th>Port</th><th>State</th><th>Service / Version</th></tr>'
    echo "$html_services"
    echo '</table>'
else
    echo '<p class="empty">Detailed scan not available.</p>'
fi)

<h2 id="findings">Key Findings</h2>
$(if [ -n "$html_findings" ]; then
    echo '<table><tr><th>Severity</th><th>Finding</th></tr>'
    echo "$html_findings"
    echo '</table>'
else
    echo '<p class="empty">No critical findings flagged.</p>'
fi)

<h2 id="sensitive">Sensitive Files</h2>
$(if [ -n "$html_sensitive" ]; then
    echo '<table><tr><th>Status</th><th>Path</th></tr>'
    echo "$html_sensitive"
    echo '</table>'
else
    echo '<p class="empty">No exposed sensitive files detected.</p>'
fi)

${raw_sections}

<footer>
  Generated by <strong>enumethod</strong> &mdash; ${REPORT_DATE}
</footer>

</body>
</html>
HTMLEOF

        log_ok "HTML report → $R/report.html"
    fi
fi

# =============================================================================
# Done
# =============================================================================
echo ""
log_banner "Enumeration Complete"
log_ok "All results saved to: $OUTPUT_DIR/"
log_step "Open report: $OUTPUT_DIR/report/report.html"
echo ""