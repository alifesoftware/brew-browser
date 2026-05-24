# landing

Static landing page for brew-browser, served at `brew-browser.zerologic.com` from umbp via Caddy.

## Files

- `index.html` — the page
- `style.css` — embedded design tokens matching the app (dark-first, warm amber, OKLCH)
- `brew-browser.svg` — the app icon (copy of `../docs/icon/brew-browser.svg`)
- `Caddyfile.snippet` — drop into `/etc/caddy/Caddyfile` on umbp

## Deploy to umbp

From this directory:

```sh
rsync -avz --delete \
  --exclude README.md --exclude Caddyfile.snippet \
  ./ michael@umbp:Sites/brew-browser/
```

Then on umbp:

```sh
# First time only — install the Caddyfile snippet
sudo cat Caddyfile.snippet >> /etc/caddy/Caddyfile
sudo caddy reload --config /etc/caddy/Caddyfile

# Subsequent updates — just rsync above, Caddy serves it directly
```

## Update flow

1. Edit `index.html` / `style.css` locally
2. View locally: `python3 -m http.server -d . 8080` then open `http://localhost:8080`
3. `rsync` to umbp when ready
