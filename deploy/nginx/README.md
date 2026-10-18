# Public clipboard routing

Install `transfer-clipboard-locations.conf` as
`/etc/nginx/snippets/transfer-clipboard-locations.conf` and include it inside the
`breeze.qzz.io` server block in `/etc/nginx/sites-available/breeze.qzz.io`:

```nginx
include snippets/transfer-clipboard-locations.conf;
```

The existing `/api/clips` and `/api/clips/:id` addresses proxy to port 3001.
Other `/api/` routes continue to use the diary backend on port 3000.
The existing `/transfer-api/` proxy also exposes the clipboard routes.
Direct static requests to either backend source or data directory return 404.

Move the existing `backend/clips` directory to `transfer-backend/clips` while
clipboard writes are paused. Start the transfer backend with clipboard support
before activating the proxy. Validate with `nginx -t` before reloading Nginx.
