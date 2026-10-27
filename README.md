# VictimWeb

Página web de prueba para un laboratorio de ciberseguridad **aislado**,
servida por Apache 2.4.49 compilado desde fuente en `/opt/apache-2.4.49`.

> ⚠️ Apache 2.4.49 es vulnerable (CVE-2021-41773 / CVE-2021-42013).
> Usar solo en una VM en red host-only. No exponer a Internet.

## Estructura

| Carpeta | Destino en la VM |
|---|---|
| `htdocs/` | `/opt/apache-2.4.49/htdocs/` |
| `cgi-bin/` | `/opt/apache-2.4.49/cgi-bin/` |

## Despliegue en la VM

```bash
cd ~
git clone https://github.com/USUARIO/VictimWeb.git   # primera vez
cd VictimWeb
# o para actualizar:  git pull

sudo ./deploy.sh
```

## Credenciales de prueba

`admin` / `lab123` (hardcodeadas en `cgi-bin/login.py`, solo demo).

## Probar

```bash
curl http://localhost/login.html
curl -X POST -d "username=admin&password=lab123" http://localhost/cgi-bin/login.py
```
