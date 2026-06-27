Deployment
==========

Sample configuration to run YAPG in production as a systemd-managed gunicorn
backend behind nginx. The examples assume the checkout lives in
`/var/www/photos` and is served by the `www-data` user — adjust the paths and
user in both files to match your setup.

1. Get the code and a virtualenv in place
-----------------------------------------

```
sudo git clone <repo> /var/www/photos
cd /var/www/photos
sudo python3 -m venv .venv
sudo .venv/bin/pip install -r requirements.txt
```

Point `static/media/photos` at your photo library, and make sure the service
user can write to `static/media` (thumbnails and `.votes.json` are created
there):

```
sudo chown -R www-data:www-data /var/www/photos/static/media
```

2. Start the backend (systemd)
------------------------------

```
sudo cp deploy/yapg.service /etc/systemd/system/yapg.service
# edit paths/User in the unit if needed
sudo systemctl daemon-reload
sudo systemctl enable --now yapg.service
```

To enable the `/edit` management UI, uncomment and set `YAPG_EDIT_USER` /
`YAPG_EDIT_PASSWORD` in the unit (edit mode stays disabled while they are
unset). Only expose `/edit` over HTTPS -- the nginx sample already redirects
HTTP to HTTPS.

The backend now listens on `127.0.0.1:8083`. Useful commands:

```
systemctl status yapg.service
journalctl -u yapg.service -f
```

3. Front it with nginx
----------------------

```
sudo cp deploy/nginx.conf /etc/nginx/sites-available/yapg
sudo ln -s /etc/nginx/sites-available/yapg /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

Remember to set `server_name` (and add TLS, e.g. with certbot) to taste.
