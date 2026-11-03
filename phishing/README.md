# Phishing portal (Phase 3 — False Messenger)

Adversary-in-the-Middle (AiTM) credential harvester for the lab. A pixel clone of
the real House of Hades staff portal, run on the attacker box (Kali).

> ISOLATED LAB ONLY. Authorised red-team assessment.

## How it works

The attacker cannot reach the domain controller, so the fake login uses the **real
portal as its validation oracle**:

```
victim -> fake login (Kali:8080) -> relays creds to REAL login.py -> granted?
                                           | yes                  | no
                                  log it + redirect to real    show error, retry
```

- **Valid credential** -> written to `harvested.log`, victim redirected to the real
  portal (`REAL_PORTAL`) so nothing looks off.
- **Invalid credential** -> the form re-renders with an error, exactly like a real
  login, forcing the victim to retry (and type the correct one).

This is how real phishing proxies work (evilginx2 / Modlishka / EvilProxy).

## Run it (on Kali)

```bash
python3 phish_server.py
# then send victims to  http://<kali-ip>:8080/
```

Edit the config at the top of `phish_server.py` if your target IP differs:
- `REAL_LOGIN`  — the real portal's handler (validation oracle)
- `REAL_PORTAL` — where victims are redirected after capture
- `LISTEN_PORT` — default 8080

## Loot

Captured attempts (valid and invalid) are appended to `harvested.log`
(git-ignored):

```
<timestamp>  <victim-ip>  <username>  <password>  VALID|invalid
```

Only `VALID` rows are confirmed working AD credentials — ready for the pivot
(Phase 6: log into the victim's domain-joined workstation).
