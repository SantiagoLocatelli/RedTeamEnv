# Blue Team — Detection Mapping (House of Hades)

> ISOLATED LAB ONLY. Authorised assessment — "assess defensive controls".

Qué log / evento levanta cada técnica de la cadena, y dónde lo ve el Blue Team en
**Splunk (192.168.1.6)**. Cadena cubierta (Fase 5-6):
RCE Apache → sesión meterpreter → pivot `portfwd` → RDP a .103 como `persephone` →
privesc Windows → movimiento al DC.

## 1) Gatehouse (Ubuntu / Apache) — Sysmon for Linux + logs nativos

| Técnica | Sysmon-for-Linux EID | Nativo | Qué matchear |
|---|---|---|---|
| Explotación CVE (path traversal) | — | Apache access/error log | `/cgi-bin/.%2e/`, `%2e%2e`, 200 en rutas raras, POST a cgi-bin |
| Apache lanza shell (RCE) | **EID 1** Process Create | auditd execve | `ParentImage` = apache2/httpd, `Image` = sh/bash/python3/nc/whoami/id |
| Payload meterpreter en disco | **EID 11** File Create + **EID 23** File Delete | — | Chain `base64 -d > /tmp/xxxx; chmod +x; /tmp/xxxx; rm -f` (ver screenshot Stage 4 del playbook) |
| C2 meterpreter saliente | **EID 3** Network Connection | — | `DestinationIp` = Kali, `DestinationPort` = 4444 (LPORT) |
| **Pivot portfwd → RDP** | **EID 3** Network Connection | auditd connect() | web server → `192.168.1.103:3389` (un server de la DMZ no debería hacer RDP a la interna) |
| Ping sweep / nmap interno | **EID 1** (ping/nmap/loop) + **EID 3** ráfaga | — | Muchas conexiones a IPs internas en pocos segundos |

Firma más limpia: el **chain de `/tmp` (EID 11 → 1 → 23)** — crear, +x, ejecutar y borrar
un binario en milisegundos = payload en memoria.

## 2) pfSense / red

- **DMZ → interna 3389** (gatehouse → .103) y **barrido hacia la LAN**: el indicador
  de pivot más fuerte. Un web server de la DMZ iniciando RDP/escaneo hacia la interna
  no tiene justificación de negocio.
- C2 saliente DMZ → externa en puerto no estándar (4444) en los fw logs / netflow.

## 3) Workstation .103 (Windows) — Security + Sysmon → Splunk (Universal Forwarder)

Es **por-acción**: cada paso emite su evento.

| Lo que hace el atacante | Windows EID | Sysmon EID |
|---|---|---|
| **RDP lateral (persephone)** | **4624 Logon Type 10** (RemoteInteractive); 4778/4779; 1149; TS-LocalSessionManager 21/25 | EID 3 |
| RDP fallido | **4625** Type 10 | — |
| Correr tool/comando (winPEAS, whoami /priv…) | **4688** (c/ command line) — uno por proceso | **EID 1** |
| Dump de credenciales **on-host** (LSASS) *(condicional)* | 4656/4663 (si hay SACL) | **EID 10** (handle a lsass.exe) |
| Token admin obtenido | **4672** | — |
| Crear admin / add a Administrators | **4720**, **4732** | — |
| Privesc por servicio (unquoted path/permisos) *(condicional)* | **7045 / 4697** | EID 13 (HKLM\...\Services) |
| SeImpersonate (PrintSpoofer/GodPotato) *(condicional)* | **4673** + 4688 (hijo SYSTEM) | EID 1 |
| Persistencia / payload (Stage 9) *(condicional)* | **4698** (tarea), **1074** (shutdown) | EID 13 (Run key) |
| Movimiento al DC (PsExec/WinRM con hades) | **4648** (cred explícita) | EID 1 |

**Source IP del 4624 Type 10** = IP interna del **gatehouse** (el salto sale del Ubuntu vía
portfwd), no Kali → una workstation recibiendo RDP desde un server de la DMZ es anomalía fuerte.

**Caveat / hallazgo:** 4688-con-command-line y Sysmon dependen de config (GPO "Audit Process
Creation" + "Include command line", y Sysmon instalado). Sin eso, **todo el privesc es invisible
salvo el RDP**. Esa brecha de logging es parte del informe de controles defensivos.

**Detecciones condicionales (dependen de técnica aún no definida):**
- **LSASS/EID 10:** la cred de persephone es por **phishing** (off-host) → sin log en Windows (solo `harvested.log` en Kali). EID 10 aplica **solo si** hay un dump on-host posterior (p. ej. sacar la cred de `hades` para saltar al DC).
- **Privesc por servicio / SeImpersonate:** dependen de qué camino de escalada use el Stage 6. SeImpersonate es de **cuentas de servicio**; persephone es usuario **interactivo** normal → probablemente **no aplica**.
- **Persistencia / Stage 9:** depende de cómo se implemente el payload (tarea programada vs Run key vs servicio). Stages 6 (en versión Windows/AD) y 8-9 **no están cerrados** en el playbook, así que estas filas son candidatas, no confirmadas.

## 4) DC .100 (Windows)

| Técnica | EID |
|---|---|
| Auth de persephone (Kerberos/NTLM) | **4768** (TGT), **4769** (ticket), **4776** (NTLM) |
| Movimiento al DC con `hades` | **4624 Type 3**, **4662** (replicación/DCSync) |
| Password spray / reuse fallido | ráfaga **4625**, **4740** (lockout) |

## 5) SPL de ejemplo (Splunk 192.168.1.6)

```spl
RDP lateral:   index=wineventlog EventCode=4624 Logon_Type=10
LSASS access:  index=sysmon EventCode=10 TargetImage=*lsass.exe
Shell de apache: index=linux EventCode=1 ParentImage=*apache2 Image IN (*sh,*bash,*nc,*python*)
/tmp payload:  index=linux EventCode=11 TargetFilename=/tmp/* | ... EventCode=23 (mismo file)
Nuevo admin:   index=wineventlog EventCode=4732 Group_Name="Administrators"
Pivot RDP:     (pfSense) src_zone=DMZ dest=192.168.1.103 dest_port=3389
```

## 6) Nota: la elección de pivot cambia el rastro

- `ssh -D` por el gatehouse → deja `Accepted password/publickey` en `/var/log/auth.log` (login SSH claro).
- `portfwd` de meterpreter → **NO** deja login; va sobre la sesión C2 existente → más silencioso en el gatehouse. Lo que el Blue tiene que cazar ahí es la **sesión meterpreter** (proceso inyectado + C2 saliente), no un login.

Misma meta de acceso, distinto rastro — buen punto para el informe.

## 7) Top-3 detecciones de mayor señal (priorizar)
1. **4624 Type 10 en .103 con origen = servidor de la DMZ**.
2. **pfSense: DMZ → interna 3389 / barrido**.
3. **Sysmon EID 10 sobre LSASS** en la workstation.
