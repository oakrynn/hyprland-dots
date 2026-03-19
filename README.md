I'll build this out for you systematically. Let me read the skill files first, then lay out the full config.
Let me give you the complete configuration guide — since Packet Tracer files are binary and can't be generated as text, I'll give you the exact step-by-step build with all commands, so you can replicate it in PT in under an hour.Here's the full build guide. The topology diagram first, then complete IOS configs.Now the full IOS configuration for every device.
[ASSUMPTION CHECK]
You're probably planning to configure each device in isolation and test at the end. Wrong order — configure WAN + routing first, verify ping end-to-end, then apply VLANs, then ACLs. Applying ACLs before routing works = 2 hours of debugging phantom failures.
Router-A — Full Config

! ===== ROUTER-A =====
enable
configure terminal

hostname Router-A
enable secret cicsoenpa55
service password-encryption

line console 0
 password ciscoconpa55
 login

banner motd #
*************************************
* UNAUTHORIZED ACCESS IS PROHIBITED *
*************************************
#

! WAN interface (to Router-B)
interface GigabitEthernet0/0
 ip address 10.10.10.1 255.255.255.252
 no shutdown
 description WAN-to-RouterB

! LAN interface (trunk to Switch-A)
interface GigabitEthernet0/1
 no shutdown
 description LAN-Trunk-to-SwitchA

! Sub-interfaces for inter-VLAN routing (router-on-a-stick)
interface GigabitEthernet0/1.10
 encapsulation dot1Q 10
 ip address 192.168.10.1 255.255.255.0
 description Admin-LAN-GW

interface GigabitEthernet0/1.20
 encapsulation dot1Q 20
 ip address 192.168.20.1 255.255.255.128
 description Staff-LAN-GW

interface GigabitEthernet0/1.30
 encapsulation dot1Q 30
 ip address 192.168.30.1 255.255.255.192
 description Wireless-LAN-GW

! Static routes to Branch B networks
ip route 0.0.0.0 0.0.0.0 10.10.10.2

end
write memory

Router-B — Full Config

! ===== ROUTER-B =====
enable
configure terminal

hostname Router-B
enable secret cicsoenpa55
service password-encryption

line console 0
 password ciscoconpa55
 login

banner motd #
*************************************
* UNAUTHORIZED ACCESS IS PROHIBITED *
*************************************
#

! WAN interface
interface GigabitEthernet0/0
 ip address 10.10.10.2 255.255.255.252
 no shutdown
 description WAN-to-RouterA

! LAN to Switch-B (server lives here, reachable via Admin subnet)
interface GigabitEthernet0/1
 ip address 192.168.10.254 255.255.255.0
 no shutdown
 description LAN-to-SwitchB-Server

! Static route back to Branch A
ip route 192.168.10.0 255.255.255.0 10.10.10.1
ip route 192.168.20.0 255.255.255.128 10.10.10.1
ip route 192.168.30.0 255.255.255.192 10.10.10.1

end
write memory

    Note on server placement: The server gets IP 192.168.10.10 (in the Admin subnet range). This keeps ACL logic clean — Admin LAN and the server share a subnet on Router-B's side.

Switch-A — Full Config (VLANs + Security)

! ===== SWITCH-A =====
enable
configure terminal

hostname Switch-A
enable secret cicsoenpa55
service password-encryption

line console 0
 password ciscoconpa55
 login

banner motd #
*************************************
* UNAUTHORIZED ACCESS IS PROHIBITED *
*************************************
#

! Create VLANs
vlan 10
 name Admin
vlan 20
 name Staff
vlan 30
 name Wireless
vlan 99
 name UNUSED

! Trunk port to Router-A (G0/1 on router side)
interface GigabitEthernet0/1
 description Trunk-to-RouterA
 switchport mode trunk
 switchport trunk allowed vlan 10,20,30
 no shutdown

! Admin LAN ports (Fa0/1–Fa0/2) — VLAN 10
interface range FastEthernet0/1 - 2
 description Admin-PC
 switchport mode access
 switchport access vlan 10
 switchport port-security
 switchport port-security maximum 1
 switchport port-security violation restrict
 switchport port-security mac-address sticky
 no shutdown

! Staff LAN ports (Fa0/3–Fa0/4) — VLAN 20
interface range FastEthernet0/3 - 4
 description Staff-PC
 switchport mode access
 switchport access vlan 20
 switchport port-security
 switchport port-security maximum 1
 switchport port-security violation restrict
 switchport port-security mac-address sticky
 no shutdown

! Wireless AP port (Fa0/5) — VLAN 30
interface FastEthernet0/5
 description Wireless-AP
 switchport mode access
 switchport access vlan 30
 switchport port-security
 switchport port-security maximum 1
 switchport port-security violation restrict
 switchport port-security mac-address sticky
 no shutdown

! Shutdown ALL unused ports and dump to VLAN 99
interface range FastEthernet0/6 - 24
 description UNUSED
 switchport mode access
 switchport access vlan 99
 shutdown

end
write memory

Switch-B — Full Config (Server side)

! ===== SWITCH-B =====
enable
configure terminal

hostname Switch-B
enable secret cicsoenpa55
service password-encryption

line console 0
 password ciscoconpa55
 login

banner motd #
*************************************
* UNAUTHORIZED ACCESS IS PROHIBITED *
*************************************
#

vlan 10
 name Admin
vlan 99
 name UNUSED

! Uplink to Router-B
interface GigabitEthernet0/1
 description Uplink-to-RouterB
 switchport mode access
 switchport access vlan 10
 no shutdown

! Server port
interface FastEthernet0/1
 description Server
 switchport mode access
 switchport access vlan 10
 switchport port-security
 switchport port-security maximum 1
 switchport port-security violation restrict
 switchport port-security mac-address sticky
 no shutdown

! Unused ports
interface range FastEthernet0/2 - 24
 description UNUSED
 switchport mode access
 switchport access vlan 99
 shutdown

end
write memory

ACLs — Apply on Router-A (the traffic chokepoint)

! ===== ACLs on Router-A =====
configure terminal

! ACL 100: Applied INBOUND on G0/1.30 (Wireless)
! - Block wireless from reaching Admin LAN entirely
! - Allow only HTTP (80) and HTTPS (443) to server
! - Deny everything else

ip access-list extended WIRELESS-IN
 deny   ip 192.168.30.0 0.0.0.63 192.168.10.0 0.0.0.255
 permit tcp 192.168.30.0 0.0.0.63 host 192.168.10.10 eq 80
 permit tcp 192.168.30.0 0.0.0.63 host 192.168.10.10 eq 443
 deny   ip any any

! ACL 101: Applied INBOUND on G0/1.20 (Staff)
! - Block FTP to server, allow HTTP/HTTPS only

ip access-list extended STAFF-IN
 deny   tcp 192.168.20.0 0.0.0.127 host 192.168.10.10 eq 21
 permit tcp 192.168.20.0 0.0.0.127 host 192.168.10.10 eq 80
 permit tcp 192.168.20.0 0.0.0.127 host 192.168.10.10 eq 443
 permit ip 192.168.20.0 0.0.0.127 192.168.10.0 0.0.0.255
 deny   ip any any

! Admin LAN (VLAN 10) — no restrictions, full access
! (no ACL on G0/1.10 needed, or apply permit all)

! Apply ACLs to subinterfaces
interface GigabitEthernet0/1.30
 ip access-group WIRELESS-IN in

interface GigabitEthernet0/1.20
 ip access-group STAFF-IN in

end
write memory

Port Security Violation Demo
To trigger a violation for your demonstration:

    On Switch-A, connect a second PC to Fa0/1 (which already has sticky MAC learned from PC-Admin-1)
    That second PC sends traffic → violation triggers
    Run: show port-security interface FastEthernet0/1 — you'll see SecurityViolation counter increment and status change to secure-restrict (or err-disabled if you used shutdown mode — use restrict for a non-disruptive demo)

! To reset a port after err-disabled:
interface FastEthernet0/1
 shutdown
 no shutdown

IP Addressing Table
Device
	
Interface
	
IP
	
Gateway
Router-A
	
Gi0/0
	
10.10.10.1/30
	
—
Router-A
	
Gi0/1.10
	
192.168.10.1/24
	
—
Router-A
	
Gi0/1.20
	
192.168.20.1/25
	
—
Router-A
	
Gi0/1.30
	
192.168.30.1/26
	
—
Router-B
	
Gi0/0
	
10.10.10.2/30
	
—
Router-B
	
Gi0/1
	
192.168.10.254/24
	
—
PC-Admin-1
	
NIC
	
192.168.10.2/24
	
192.168.10.1
PC-Admin-2
	
NIC
	
192.168.10.3/24
	
192.168.10.1
PC-Staff-1
	
NIC
	
192.168.20.2/25
	
192.168.20.1
PC-Staff-2
	
NIC
	
192.168.20.3/25
	
192.168.20.1
Laptop (WiFi)
	
NIC
	
192.168.30.2/26
	
192.168.30.1
Server
	
NIC
	
192.168.10.10/24
	
192.168.10.254
Wireless Configuration (WPA2 Personal in PT)
In Packet Tracer, drop a WRT300N or Access Point device:

    Click AP → GUI tab
    SSID: CompanyWiFi
    Security: WPA2 Personal
    Passphrase: Secure@1234
    Connect it via Fa0 port to Switch-A Fa0/5 (already configured VLAN 30)
    On the Laptop: click → Config → Wireless → set same SSID + passphrase

    WPA2 Enterprise requires a RADIUS server config in PT — it's finicky and often graded as optional. WPA2 Personal is fully acceptable here.

Server Config (in PT GUI)

    Click Server → Services tab
    Enable: HTTP, HTTPS, FTP
    FTP: add a user (admin / admin) for testing
    IP: 192.168.10.10, gateway 192.168.10.254

[WATCH OUT]
[WATCH OUT] Router-on-a-stick sub-interfaces won't work unless the physical parent interface (Gi0/1) has no shutdown with no IP address on it — Packet Tracer sometimes silently ignores sub-interface traffic if the parent has a misconfigured IP. Also: PT's ACL engine processes deny ip any any implicitly at the end anyway, but you need it explicitly written for the examiner to see it in show run.
