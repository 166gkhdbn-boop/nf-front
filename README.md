# nf-front

A standalone XHTTP front, self-hosted on your own server. It replaces the
Netlify edge front: no Netlify, Cloudflare, or Azion sits behind it. This
server IS the front.

How it works: the client sends XHTTP requests to one path. The front reads
the backend address from the request's `x-host` header, streams the request
to that backend over plain HTTP, and streams the response back. It has no
auth of its own — the backend VLESS UUID is the auth.

## Requirements

- An Ubuntu/Debian server, installed as root.
- A domain whose DNS A record already points at this server.
- Ports 80 and 443 reachable (Caddy needs port 80 for Let's Encrypt).
- A backend XHTTP server (Xray) serving plain HTTP, with a matching UUID,
  path, and padding settings.

## Quick install

```bash
curl -fsSL https://raw.githubusercontent.com/166gkhdbn-boop/nf-front/main/install.sh \
  | bash -s -- --domain front.example.com --backend 203.0.113.10:444 --uuid 00000000-0000-0000-0000-000000000000
```

The installer sets up Node.js 20 + Caddy + a systemd service (`nf-front`),
then prints your ready-to-import VLESS link. Re-running it updates the
code and restarts the service.

## Config structure

The printed link has exactly this shape (values shown are placeholders):

```
vless://YOUR-VLESS-UUID@front.example.com:443?mode=auto&path=%2Fnf-953693fb%2F&security=tls&alpn=h2%2Chttp%2F1.1&encryption=none&extra={"xPaddingBytes":"1-1","xPaddingObfsMode":true,"scMaxEachPostBytes":"1000000","xPaddingKey":"iran","xPaddingHeader":"iran","headers":{"x-host":"203.0.113.10:444"}}&insecure=0&host=front.example.com&fp=chrome&type=xhttp&allowInsecure=0&sni=front.example.com#nf-front
```

- `type=xhttp`, `mode=auto`, `path=/nf-953693fb/` (only this path is
  forwarded; everything else returns 404).
- TLS is terminated by Caddy with an automatic Let's Encrypt certificate
  for your domain, so `sni` and `host` are both your domain.
- The `x-host` header inside `extra` tells the front which backend to
  reach; the backend itself is plain HTTP on the given `host:port`.

## Files

- `server.js` — the front (Node.js, zero dependencies, true streaming
  both ways). Reads `PORT` (default 8080) and `FRONT_PATH`
  (default `/nf-953693fb/`) from the environment.
- `install.sh` — the quick installer described above.

## Checks after install

```bash
curl https://front.example.com/nf-953693fb/                                # expect: Missing x-host
curl https://front.example.com/nf-953693fb/ -H 'x-host: 203.0.113.10:444' # expect: backend's own 400
systemctl status nf-front
journalctl -u nf-front -f
```

## Notes

- Your real UUID and backend are passed on the install command line only;
  they are never stored in this repo.
- The front forwards to plain-HTTP backends only (like the Netlify front
  did). If your backend serves HTTPS, put its plain-HTTP XHTTP port here.
