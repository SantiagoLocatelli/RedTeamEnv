#!/usr/bin/env python3
# ad_bind_test.py - test an LDAP bind against the AD domain controller.
# Confirms that a warden credential authenticates, before wiring the portal.
#
# Usage:
#   python3 tools/ad_bind_test.py <DC_IP> <DNSRoot> <username> <password>
# Example:
#   python3 tools/ad_bind_test.py 192.168.1.10 elan.local charon 'Ferryman1!'
import sys

try:
    from ldap3 import Server, Connection, ALL
except ImportError:
    print("ldap3 not installed.  Run: sudo apt install -y python3-ldap3")
    sys.exit(1)

if len(sys.argv) != 5:
    print("Usage: python3 tools/ad_bind_test.py <DC_IP> <DNSRoot> <username> <password>")
    print("Example: python3 tools/ad_bind_test.py 192.168.1.10 elan.local charon 'Ferryman1!'")
    sys.exit(1)

dc, domain, user, password = sys.argv[1:5]

try:
    server = Server("ldap://%s" % dc, get_info=ALL)
    conn = Connection(server, user="%s@%s" % (user, domain),
                      password=password, auto_bind=True)
    print("BIND OK - '%s@%s' authenticated against the DC at %s" % (user, domain, dc))
    conn.unbind()
except Exception as e:
    print("ERROR: %s - %s" % (type(e).__name__, e))
    print("")
    print("Common causes:")
    print("  invalidCredentials  -> user doesn't exist in AD, or wrong password")
    print("  socket/timeout      -> DMZ can't reach the DC on TCP 389 (pfSense rule)")
    print("  LDAPInvalidDn...    -> wrong DNSRoot (check (Get-ADDomain).DNSRoot on the DC)")
    sys.exit(1)
