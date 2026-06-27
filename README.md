Yet Another Photo Gallery
=========================

(designed to run on my raspberrypi :) )

This is essentially a pet project to get known with techniques like 'infinite
scrolling' and tools like nginx, server-side Python, jinja, FastCGI.

Server-side, a Python script list pictures from a directory, build 'cropped'
thumbnails and resize large picture (taking advantage of EXIF informations to
rotate them if necessary).  It outputs the gallery via jinja templates and
FastCGI.

Client-side, I use jquery + jquery masonery to display the pictures and load
asynchronously new ones when I reach the end of the page. lightbox is used to
display larger pictures.

To use
------

- create a virtual environment and install the dependencies:
```
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```
- make `static/media/photos` point to your photos
- run the app with [gunicorn](https://gunicorn.org/) (a single worker is
  required: the gallery keeps its thumbnail/vote caches in memory):
```
.venv/bin/gunicorn --chdir scripts --workers 1 --timeout 120 \
                   --bind 127.0.0.1:8083 photos:app
```
  (you might want to run that in a `screen`/`systemd` unit to keep it alive --
  see [`deploy/`](deploy/) for a ready-made systemd unit and nginx config).
  For quick local hacking you can also run the bundled development server:
  `python3 scripts/photos.py` (listens on `127.0.0.1:8083`, override with `PORT`).
- I use the following configuration for nginx, proxying to gunicorn:

```
server {

	listen 80;
	server_name your.photo.gallery.org;

	# static files
	location ~ ^/(images|javascript|js|css|flash|media|static)/ {
	    root /var/www/photos/static;
	    expires 30d;
	}
	 

	location / {
	    proxy_pass http://127.0.0.1:8083;
	    proxy_set_header Host $host;
	    proxy_set_header X-Real-IP $remote_addr;
	    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
	    proxy_set_header X-Forwarded-Proto $scheme;
	}
}
```


Captions
--------

YAPG can display captions for your pictures: simply rename the image file to
start with a `@` character: everything after this character (excluding file
extension!) will be used as a caption. Markdown syntax is even allowed!

(note that some characters are invalid in filenames, like `/`: in order to put
links in your captions, you might want to use `|` instead, which is replaced
automatically with `/` by YAPG).

Voting
------

Photo voting can be enabled per gallery by creating (touching) an empty `.vote` file in the desired photo directory.

A small, clickable star appears next to each image. Visitors can use it to
'favourite' one image. The vote tally per image is stored server-side in a file
called `.votes.json`, one file per directory.

Editing
-------

A `/edit` route mirrors the public gallery but lets you manage it: upload new
pictures, delete existing ones, edit captions and create subfolders. Browse to
`/edit` (or `/edit/<some/gallery>`) to enter edit mode.

It is gated behind HTTP Basic auth, with credentials taken from the
environment. Edit mode is **disabled** unless both are set:

```
export YAPG_EDIT_USER=admin
export YAPG_EDIT_PASSWORD=a-strong-password
```

(with systemd, set these via `Environment=` in the unit -- see
[`deploy/yapg.service`](deploy/yapg.service)).

Because Basic auth sends the password with every request, **only ever expose
`/edit` over HTTPS**. Editing a caption simply renames the file using the
`@caption` convention described above, so captions survive a switch back to
read-only mode.
