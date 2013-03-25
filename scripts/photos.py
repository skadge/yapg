#!/usr/bin/env python
# -*- coding: UTF-8 -*-

import time
from itertools import imap

from cgi import escape
import sys, os
from flup.server.fcgi import WSGIServer
import urlparse
from jinja2 import Environment, PackageLoader

from gallery.image_processing import *

MEDIA_BASE = u'media/'

PHOTOS_BASE = u'media/photos/'

visited_path = {}

env = Environment(loader=PackageLoader('gallery', 'tpl'))
tpl = env.get_template('gallery.tpl')
items_tpl = env.get_template('photo_items.tpl')

def fixencoding(s):
    return s.encode("utf-8")

def make_gallery(path, options):

    content = ""
    fullpath= PHOTOS_BASE + path


    checksum = compute_checksum(fullpath) # compute a checksum of the path to detect changes
    if (fullpath not in visited_path) or visited_path[fullpath] != checksum:
        create_thumbnails(fullpath, to = MEDIA_BASE)
        visited_path[fullpath] = checksum

    start = int(options.get("from", [0])[0])
    end = start + int(options.get("nb", [0])[0])

    print("Building gallery with pictures %d to %d in %s" % (start, end, fullpath))

    imgs = list_images(fullpath)

    if end - start != 0:
        if start >= len(imgs):
            print("No more images")
            return ""
        if end > len(imgs):
            end = len(imgs)

        print("Sending %d images" % (end - start))
        return imap(fixencoding, items_tpl.generate(imgs = imgs[start:end]))

    else:

        parentdir = STATIC_ROOT + PHOTOS_BASE + path
        dirs_names = [ name for name in os.listdir(parentdir) if os.path.isdir(os.path.join(parentdir, name)) and name[0] not in ['.', '_']]
        dirs = [ (name, os.path.join(path, name)) for name in dirs_names]

        title = (path.split("/")[1:-1], path.split("/")[-1])
        print("Sending base gallery")
        #import pdb;pdb.set_trace()
        return imap(fixencoding, tpl.generate(title = title, path = path, dirs = dirs, imgs = imgs[start:end], counter = end))


def app(environ, start_response):

    start_response('200 OK', [('Content-Type', 'text/html')])

    path = environ["PATH_INFO"].decode("utf-8")

    options = urlparse.parse_qs(environ["QUERY_STRING"])


    return make_gallery(path, options)

print("Starting to serve...")
WSGIServer(app, bindAddress = ("127.0.0.1", 8080)).run()
