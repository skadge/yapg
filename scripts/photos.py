#!/usr/bin/env python
# -*- coding: UTF-8 -*-

import time

from cgi import escape
import sys, os
from flup.server.fcgi import WSGIServer
import urlparse
from jinja2 import Environment, PackageLoader

from gallery.image_processing import *

MEDIA_BASE = "media/"

PHOTOS_BASE = "media/photos/"

visited_path = []

env = Environment(loader=PackageLoader('gallery', 'tpl'))
items_tpl = env.get_template('photo_items.tpl')

def make_gallery(path, options):


    starttime = time.time()

    content = ""
    fullpath= PHOTOS_BASE + path


    if fullpath not in visited_path:
        create_thumbnails(fullpath, to = MEDIA_BASE)
        visited_path.append(fullpath)

    start = int(options.get("from", [0])[0])
    end = start + int(options.get("nb", [0])[0])

    print("Building gallery with pictures %d to %d in %s" % (start, end, fullpath))



    tpl = env.get_template('gallery.tpl')

    imgs = list_images(path)

    if start != 0:
        if start >= len(imgs):
            print("No more images")
            return ""
        if end > len(imgs):
            end = len(imgs)

        print("Sending %d images" % (end - start))
        content = str(items_tpl.render(imgs = list_images(path)[start:end]))

    else:
        print("Sending gallery with %d images" % (end - start))
        return tpl.generate(title = path, path = path, imgs = list_images(path)[start:end], counter = end)


    print("Spent %.2fs in make_gallery." % (time.time() - starttime))
    return content


def app(environ, start_response):

    start_response('200 OK', [('Content-Type', 'text/html')])

    path = environ["PATH_INFO"] + "/"

    options = urlparse.parse_qs(environ["QUERY_STRING"])


    return make_gallery(path, options)

print("Starting to serve...")
WSGIServer(app, bindAddress = ("127.0.0.1", 8080)).run()
