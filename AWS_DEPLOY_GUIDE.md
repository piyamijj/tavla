# Cyber Tavla Realtime Server — AWS EC2 (Ubuntu) Deployment Guide

Target host: `ubuntu@13.53.56.176` (you already have `anahtar.pem` and SSH access).
Everything below is based on the actual code in `server/` right now:
- `server/package.json`: `engines.node >= 18.0.0`, start script is `node src/index.js`, dependencies are `express`, `socket.io`, `cors` only.
- `server/src/index.js`: reads exactly two environment variables — `PORT` (defaults to `3000`) and `CORS_ORIGIN` (defaults to `*`). Health check endpoint is `GET /health` → returns `ok`.

Run all commands after `ssh -i anahtar.pem ubuntu@13.53.56.176`.

---

## 1) Install Node.js (v20 LTS satisfies the `>=18` requirement)

```bash
sudo apt update && sudo apt upgrade -y
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs git
node -v   # should print v20.x.x
npm -v
```

## 2) Get the code onto the server

The repo is public, so a plain clone works — no token needed.

```bash
cd ~
git clone https://github.com/piyamijj/tavla.git
cd tavla/server
```

## 3) Install dependencies

```bash
npm install
```

## 4) Quick manual smoke test (optional but recommended before wiring systemd)

```bash
PORT=3000 node src/index.js
```
You should see: `Cyber Tavla server dinlemede: port 3000`. Press `Ctrl+C` to stop it once confirmed — the next step runs it properly as a daemon.

## 5) Run it persistently and reboot-safe with systemd

Create the unit file:

```bash
sudo nano /etc/systemd/system/cyber-tavla.service
```

Paste exactly this:

```ini
[Unit]
Description=Cyber Tavla Realtime Server
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/tavla/server
ExecStart=/usr/bin/node src/index.js
Restart=always
RestartSec=5
Environment=PORT=3000
Environment=CORS_ORIGIN=*
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
```

Save and exit (Ctrl+O, Enter, Ctrl+X), then:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now cyber-tavla
sudo systemctl status cyber-tavla     # should show "active (running)"
journalctl -u cyber-tavla -f          # live logs; Ctrl+C to exit
```

It will now start automatically on every reboot and restart itself if it crashes.

## 6) Open the correct ports

**A) AWS Security Group (do this in the AWS Console — I cannot do this for you):**
1. AWS Console → EC2 → Instances → select this instance.
2. "Security" tab → click the Security Group link shown there.
3. "Edit inbound rules" → "Add rule":
   - Type: Custom TCP, Port range: `3000`, Source: `0.0.0.0/0` (for the raw connectivity test in step 7).
   - Type: HTTP, Port range: `80`, Source: `0.0.0.0/0` (needed for step 8, certbot/nginx).
   - Type: HTTPS, Port range: `443`, Source: `0.0.0.0/0` (needed for step 8, the real app connection).
4. Save rules.

**B) ufw (Ubuntu's firewall), if enabled:**

```bash
sudo ufw status
```
If it says "inactive", skip this. If it says "active":

```bash
sudo ufw allow OpenSSH      # do this FIRST or you can lock yourself out
sudo ufw allow 3000/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw reload
```

## 7) Verify from outside (raw server check)

From your own machine (not the server):

```bash
curl http://13.53.56.176:3000/health
# expect: ok

curl "http://13.53.56.176:3000/socket.io/?EIO=4&transport=polling"
# expect something like: 0{"sid":"...","upgrades":["websocket"],...}
```

If both work, the Node server itself is correctly reachable from the internet. This confirms the server — it does **not** yet confirm the Flutter app can use it (see next section).

## 8) Does the Flutter app need wss:// (secure WebSocket)? — Yes.

**Checked directly against the current app code:** the Android build is produced by `flutter create --platforms=android .` fresh in every CI run (the `android/` folder is not committed to the repo), which generates Flutter's stock manifest with no cleartext-traffic override. Modern Android (API 28+, which is what current Flutter APKs target) **blocks plain HTTP/WS ("cleartext") network traffic by default** unless the app explicitly opts in for that address — and this app currently does not.

**Practical consequence:** a plain `http://13.53.56.176:3000` or `ws://13.53.56.176:3000` will work fine from `curl`/a browser dev tool, but the installed Android app itself will refuse to connect to it — the OS blocks the connection before it even leaves the device. So step 7 passing does **not** mean the app will connect.

**What's actually needed:** a domain (or subdomain) pointed at `13.53.56.176`, an nginx reverse proxy, and a free TLS certificate via certbot — the same shape Render was already providing for you automatically. Once that's in place, the app connects over `https://` (which Socket.io upgrades to `wss://` automatically), exactly like it does today with the Render URL.

*(The alternative — patching the Android manifest to explicitly whitelist cleartext traffic to this one raw IP — is technically possible but is not being done now, since you asked not to touch app config yet, and it's not something I'd recommend for a public game long-term anyway.)*

### 8a) Point a domain at the server

Pick a domain/subdomain you own (e.g. `tavla.yourdomain.com`) and create an **A record** pointing it to `13.53.56.176`. This has to be done in your domain registrar/DNS provider — I can't do this for you. Wait for DNS to propagate (usually a few minutes, sometimes longer) before continuing; you can check with `nslookup tavla.yourdomain.com` from your own machine.

### 8b) Install and configure nginx as a reverse proxy

```bash
sudo apt install -y nginx
sudo nano /etc/nginx/sites-available/cyber-tavla
```

Paste (replace `YOUR_DOMAIN_HERE` with your actual domain):

```nginx
server {
    listen 80;
    server_name YOUR_DOMAIN_HERE;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_cache_bypass $http_upgrade;
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/cyber-tavla /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### 8c) Get a free TLS certificate with certbot

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d YOUR_DOMAIN_HERE
```

Follow the prompts (enter an email, agree to terms, choose to redirect HTTP → HTTPS when asked). Certbot edits the nginx config automatically to add the certificate and sets up automatic renewal.

### 8d) Verify the real, app-usable endpoint

```bash
curl https://YOUR_DOMAIN_HERE/health
# expect: ok

curl "https://YOUR_DOMAIN_HERE/socket.io/?EIO=4&transport=polling"
# expect: 0{"sid":"...","upgrades":["websocket"],...}
```

Once both of these succeed over `https://`, the server is genuinely ready for the Flutter app to use — the app's server URL would become `https://YOUR_DOMAIN_HERE` (no port number). **Do not change the app's default server URL yet** — that's a deliberate follow-up step once you confirm this is live and reachable.

---

## Summary checklist

- [ ] Node 20 installed, `node -v` shows v20.x
- [ ] Repo cloned to `~/tavla`, `npm install` completed in `~/tavla/server`
- [ ] `cyber-tavla.service` created, `systemctl status cyber-tavla` shows active
- [ ] AWS Security Group allows inbound 3000, 80, 443
- [ ] `ufw` (if active) allows OpenSSH, 3000, 80, 443
- [ ] `curl http://13.53.56.176:3000/health` → `ok`
- [ ] Domain's A record points to `13.53.56.176`
- [ ] nginx reverse proxy configured and `nginx -t` passes
- [ ] certbot issued a certificate successfully
- [ ] `curl https://YOUR_DOMAIN_HERE/health` → `ok`