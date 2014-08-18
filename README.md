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

- install `python-imaging`, `python-flup` and `python-jinja2` if necessary
- make `/static/media/photos` to point to your photos
- I use the following configuration for nginx:

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
	    fastcgi_pass 127.0.0.1:8080;
	    fastcgi_param SERVER_NAME $server_name;
	    fastcgi_param SERVER_PORT $server_port;
	    fastcgi_param SERVER_PROTOCOL $server_protocol;
	    fastcgi_param PATH_INFO $fastcgi_script_name;
	    fastcgi_param REQUEST_METHOD $request_method;
	    fastcgi_param QUERY_STRING $query_string;
	    fastcgi_param CONTENT_TYPE $content_type;
	    fastcgi_param CONTENT_LENGTH $content_length;
	    fastcgi_pass_header Authorization;
	    fastcgi_intercept_errors off;
	}
}
```
