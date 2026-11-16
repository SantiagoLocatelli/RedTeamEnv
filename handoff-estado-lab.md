# House of Hades — Red Team Lab · Handoff / Estado

Resumen para retomar en otro chat sin arrastrar toda la conversación.

## Qué es
Assessment de red team del TAFE (Cert IV Cyber Security), temática mitología griega
("House of Hades" / Sísifo). Repo **público**: `github.com/SantiagoLocatelli/VictimWeb`.
Todo corre en **Nutanix** (VMs accedidas por noVNC).

## Topología de red
```
Kali (atacante) ──[pfSense]── gatehouse DMZ (Ubuntu) [IP varía por env: 10.1.1.10 / .5]
                                    │        Apache 2.4.49 + PostgreSQL + la web
                              Red interna 192.168.1.x
                              - olympus-dc (target, olympus.net) + hades-dc (mail, hades.underworld, aparte) [IPs varían]
                              - persephone-ws (Windows, unida a olympus.net, Blue Team/víctima) [p.ej. .103]
                              - splunk [p.ej. .6]
```
Solo el gatehouse es alcanzable desde Kali; la red interna está detrás del pfSense.
El gatehouse es dual-homed (DMZ 10.1.1.10 + pata interna en 192.168.1.x) → es el puente.

## Nomenclatura y environments
Hay **varios environments** y las IPs varían, así que nos referimos a las máquinas por **rol**, no por IP:

| Alias | Máquina |
|---|---|
| **kali** | atacante |
| **gatehouse** | Ubuntu DMZ, Apache 2.4.49, dual-homed (IP varía: 10.1.1.10 / 10.1.1.5) |
| **olympus-dc** | DC Olympus (`olympus.net`) — target; al que se une persephone-ws |
| **hades-dc** | DC Hades (`hades.underworld`) — hostea el email server; aparte, no se ataca |
| **persephone-ws** | workstation Windows de persephone, unida a olympus-dc |
| **splunk** | Splunk |

Auth/UPN = `olympus.net`; emails de usuarios = `@hades.underworld` (mailboxes en hades-dc). Las IPs de ejemplo en los docs (`.100`, `.103`, `.6`) son referencia — cambian por environment.

## Datos clave
- **AD:** dominio **`olympus.net`** (olympus-dc, target; emails siguen `@hades.underworld` vía hades-dc). Usuarios (todos domain users **normales**, ninguno admin): `charon`, `cerberus`, `minos`, `hades`, `persephone`. Password **`Ferryman1!`** para todos **excepto `persephone` = `Demeter01!`**. **La víctima del phishing ahora es `persephone`** (email `persephone@hades.underworld`). Como ningún warden es admin, para elevar en Windows se usa el **Administrator local** de la workstation, o se hace Domain Admin a `hades`.
- **Login web** (`cgi-bin/login.py`): hace **LDAP bind** contra el DC (no guarda passwords, no es SQLi). `AD_HOST` + `AD_DOMAIN` configurables arriba del archivo.
- **DB:** PostgreSQL `underworld`, rol `hades_app`/`styx`. Tablas `souls` (público) y `wardens` (directorio de staff, SIN passwords — la SQLi roba emails para targeting).
- **pfSense:** alias `AD_DC_Ports` (53,88,123,135,389,445,464,636,3268,3269,49152:65535) + alias host `DC`, regla DMZ→DC (TCP/UDP). Ya funciona.

## Estado de las fases
- ✅ **1 — Recon:** nmap + gobuster. Clave: `admissions.py` está en `/cgi-bin/` (403, no linkeado) → se encuentra escaneando **`/cgi-bin/` directo** con wordlist que tenga "admissions" (gobuster no recursa).
- ✅ **2 — SQLi** en `admissions.py` (`?q=`): detección con `'`, enum con `information_schema`, dump con `UNION`. Funciona.
- ✅ **3 — Phishing:** `phishing/phish_server.py` — clon **AiTM** temática **Olympus** (pretexto: cuenta inactiva +6 meses, revalidación). Valida reenviando al login real; `VALID`→redirige al portal real, guarda en `harvested.log`. Corre en Kali (puerto 8080). Víctima objetivo: `persephone`.
- ✅ **4 — CVE Apache (Forgotten Gatehouse: identificar + explotar)** 2.4.49 (CVE-2021-41773/42013): RCE con `apache_normalize_path_rce`. **Requiere:** `mod_cgid` + **`Require all granted`** en `<Directory />`. `install_apache.sh` ya lo setea. **Sesión meterpreter obtenida** (como `daemon`).
- ✅ **5 — Breach of Hades (pivot + RDP lateral):** FUNCIONANDO (runbook en `docs/phase5-6-pivot-escalation.md`).
  - ✅ Workstation Win10/11 levantada, unida a `olympus.net`, IP **192.168.1.103** (p.ej.), RDP habilitado, `persephone` en "Remote Desktop Users".
  - ✅ Recon interno (ping sweep): vivos = **.100 (DC)** y **.103 (workstation)**. Splunk .6.
  - ✅ Pivot `portfwd` de meterpreter: `portfwd add -l 13389 -p 3389 -r 192.168.1.103` (reenvía RDP de la .103 a `127.0.0.1:13389` en Kali). Va sobre la sesión C2 de la Fase 4 — **sin bloqueante de cred SSH**.
  - ✅ RDP lateral como `persephone / Demeter01!` (con NLA off + `/sec:tls` — ver Gotchas).
- 🟡 **6 — Keys of the Gods (privesc):** vector definido (**AlwaysInstallElevated** → MSI como SYSTEM → admin local); falta correr/escribir el write-up (Step 5 de `docs/phase5-6-pivot-escalation.md`).
- ⏳ **7-9:** exfil (fotos de rocas + cifrado acróstico, "Cretan Labyrinth"), descifrar imágenes → clave del payload, payload final con countdown + apagado.

## Próximos pasos (Fases 5-6) — runbook completo en `docs/phase5-6-pivot-escalation.md`
1. ✅ **Workstation unida al dominio** — .103, RDP arriba, persephone autorizada. (Gotcha: el perfil de red quedó en **Public** → el firewall tiraba todo a `filtered`; se arregla con `Set-NetConnectionProfile -InterfaceAlias "Ethernet" -NetworkCategory Private`.)
2. ✅ **Recon interno** (ping sweep, nmap a la /24 tarda ~1h): `for i in $(seq 1 254); do ping -c 1 -W 1 192.168.1.$i | grep "bytes from"; done`. ICMP puede fallar en Windows → fallback `/dev/tcp` a 445/3389. Vivos: .100 y .103.
3. ✅ **Pivot `portfwd` de meterpreter** (sobre la sesión C2 de la Fase 4, sin cred SSH): `meterpreter > portfwd add -l 13389 -p 3389 -r 192.168.1.103`. Abre `127.0.0.1:13389` en Kali → túnel por el gatehouse dual-homed → `.103:3389`.
4. ✅ **RDP lateral** (funcionando): `xfreerdp3 /u:persephone /d:olympus.net /p:'Demeter01!' /v:127.0.0.1:13389 /cert:ignore +clipboard /sec:tls`. **Requiere NLA off en la ws** (ver Gotchas); forward local de Kali.
5. 🔜 **Escalar a admin local** (Stage 6 — **AlwaysInstallElevated**: MSI de msfvenom como SYSTEM → admin local; detalle en Step 5 del runbook) → luego WinRM/PsExec hacia el DC con `hades`.
6. 🔜 **Blue/Splunk:** mapear detección (RDP = evento **4624 Type 10** con origen = IP interna del gatehouse, etc.) — parte "assess defensive controls". Nota: un sweep `-T4` es ruidoso y muy visible al Blue Team.

## Gotchas Fase 5 (RDP por pivot)
Para armar la ws rápido: **`windows/setup-workstation.ps1`** (hace todo esto). Lecciones del primer run:
- **Habilitar RDP de verdad:** `fDenyTSConnections=0` + `Start-Service TermService` + `Enable-NetFirewallRule -DisplayGroup "Remote Desktop"`. Si `echo > /dev/tcp/<ws>/3389` desde el gatehouse da **CLOSED**, es esto (no el túnel).
- **NLA off obligatorio** para el pivot: Kali no es del dominio y no llega al KDC por el túnel (+ SPN/clock skew con Kerberos sobre `127.0.0.1`) → la auth NLA cuelga con *"Cannot find KDC for realm"*. Fix: `UserAuthentication=0` en `...\WinStations\RDP-Tcp` + `/sec:tls` en el cliente.
- **`Add-LocalGroupMember` tira "Object reference not set..."** con cuentas de dominio → usar `net localgroup "Remote Desktop Users" "OLYMPUS\persephone" /add`.
- NLA-off es un **finding realista** — documentarlo en el informe, no esconderlo.

## Estructura del repo
```
htdocs/login.html              portal real (form → login.py)
cgi-bin/login.py               LDAP bind a AD (no SQLi)
cgi-bin/admissions.py          búsqueda vulnerable a SQLi (UNION)
db/schema.sql, setup_db.sh     PostgreSQL + datos
install_apache.sh              compila Apache 2.4.49 + mod_cgid + Require all granted + nmap
deploy.sh                      copia htdocs/ y cgi-bin/ a /opt/apache-2.4.49/
docs/attack-plan.md            plan completo de las 9 fases
docs/phase5-6-pivot-escalation.md           runbook Fases 5-6 (pivot `portfwd` + RDP + escalación)
docs/active-directory-setup.md guía de olympus-dc (+ hades-dc)
windows/setup-dc.ps1           setup del DC scripteado (2 fases, con transcript)
windows/setup-workstation.ps1  setup de la ws: RDP + NLA off + autoriza al user
tools/ad_bind_test.py          test de LDAP bind al DC
phishing/phish_server.py       clon AiTM (Olympus)
```

## Comandos clave
```bash
# Setup gatehouse (máquina limpia):
sudo ./install_apache.sh && sudo ./deploy.sh && sudo ./db/setup_db.sh

# Test del login contra AD (desde el gatehouse):
python3 tools/ad_bind_test.py IP_OLYMPUS_DC olympus.net persephone 'Demeter01!'   # -> BIND OK

# SQLi (en el buscador de admissions.py o por ?q=):
zzz' UNION SELECT username, email, role FROM wardens--

# Recon interno desde el foothold (ping sweep; nmap a la /24 tarda demasiado):
for i in $(seq 1 254); do ping -c 1 -W 1 192.168.1.$i | grep "bytes from"; done
```

## Pendientes administrativos
- **Sin commitear** — reestructuración Olympus (dos DCs) tocó scripts (`setup-dc.ps1`, `login.py`, `ad_bind_test.py`) y docs (`active-directory-setup.md`, `phase5-6-pivot-escalation.md`, `attack-plan.md`, `handoff`), más `README.md`. Corré `git status` para el detalle. (`git push` previo hecho; `main` estaba sincronizado.)
- `.git/objects/maintenance.lock` colgado (mantenimiento de git) — limpiar antes de un commit/pull.
- pfSense del environment: reglas del DC ya creadas con alias.
- **DCs:** `olympus-dc` (`olympus.net`, target, lo arma `setup-dc.ps1`) + `hades-dc` (`hades.underworld`, email server, aparte/no se toca). `login.py` apunta a olympus-dc; UPN `@olympus.net`, emails `@hades.underworld`.
