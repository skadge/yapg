#!/usr/bin/env python
# -*- coding: UTF-8 -*-

import logging; logger = logging.getLogger("main")
FORMAT = '%(asctime)s - %(levelname)s: %(message)s'
logging.basicConfig(format=FORMAT, level=logging.DEBUG)

import time
from itertools import imap

from cgi import escape
import sys, os
from flup.server.fcgi import WSGIServer
import urlparse
from jinja2 import Environment, PackageLoader
import json

from gallery.image_processing import *

MEDIA_BASE = u'media/'

PHOTOS_BASE = u'media/photos/'

recents = []
visited_path = {}

# this dictionary holds one dict {image -> votes} per path (ie, per gallery)
favorites_registery = {}

env = Environment(loader=PackageLoader('gallery', 'tpl'))
tpl = env.get_template('gallery.tpl')
items_tpl = env.get_template('photo_items.tpl')

def fixencoding(s):
    return s.encode("utf-8")

def make_gallery(path, options):

    content = ""
    fullpath= PHOTOS_BASE + path

    try:
        checksum = compute_checksum(fullpath) # compute a checksum of the path to detect changes
    except OSError:
        # the path does not exist!
        paths = path.split("/")[1:-1]
        title = (["/".join(paths[0:i+1]) for i in range(len(paths))], path.split("/")[-1])
        logger.info("Bad path! %s"%path)
        return imap(fixencoding, tpl.generate(title=title, path=path, badpath=True, dirs=None, hasimgs=False, recents=None))

    if (fullpath not in visited_path) or visited_path[fullpath] != checksum:
        create_thumbnails(fullpath, to = MEDIA_BASE)
        visited_path[fullpath] = checksum

    start = int(options.get("from", [0])[0])
    end = start + int(options.get("nb", [0])[0])

    logger.info("Building gallery with pictures %d to %d in %s" % (start, end, fullpath))

    imgs = list_images(fullpath)

    vote_enabled = False
    vote_path = absolute_media_path(os.path.normpath(os.path.join(fullpath, ".vote")))
    logger.info("Checking whether %s exists..." % vote_path)
    if os.path.exists(vote_path):
        vote_enabled = True
        logger.info("\".vote\" found: image voting enabled for this gallery")

        # load existing votes for this gallery from .votes.json
        if path not in favorites_registery:
            votes_json = absolute_media_path(os.path.normpath(os.path.join(fullpath, ".votes.json")))
            if os.path.exists(votes_json):
                with open(votes_json, "r") as f:
                    favorites_registery[path] = json.load(f)
            else:
                favorites_registery[path] = {}
                save_votes(path)

    if end - start != 0:
        if start >= len(imgs):
            logger.info("No more images")
            return ""
        if end > len(imgs):
            end = len(imgs)

        logger.info("Sending %d images" % (end - start))
        return imap(fixencoding, items_tpl.generate(imgs = imgs[start:end], vote=vote_enabled))

    else:

        parentdir = STATIC_ROOT + PHOTOS_BASE + path
        dirs_names = sorted([ name for name in os.listdir(parentdir) if os.path.isdir(os.path.join(parentdir, name)) and name[0] not in ['.', '_']], reverse=True)
        dirs = [ (name, os.path.join(path, name)) for name in dirs_names]

        paths = path.split("/")[1:-1]
        title = (["/".join(paths[0:i+1]) for i in range(len(paths))], path.split("/")[-1])
        logger.info("Sending base gallery")
        return imap(fixencoding, tpl.generate(title=title,
                                              path=path, 
                                              dirs=dirs, 
                                              hasimgs=(len(imgs) > 0), 
                                              imgs=imgs[start:end], 
                                              recents=recents, 
                                              vote=vote_enabled,
                                              counter=end))


def save_votes(path):
    fullpath= PHOTOS_BASE + path
    votes_json = absolute_media_path(os.path.normpath(os.path.join(fullpath, ".votes.json")))

    logger.info("Writing %s to %s" % (favorites_registery[path], votes_json))
    with open(votes_json, "w") as f:
        json.dump(favorites_registery[path], f, indent=2)

def toggle_favorite(action, path, options):
    global favorites_registery


    favorites = favorites_registery.setdefault(path, {})

    filename = options["img"][0]
    if action == "favorite":
        logger.info("Marking image %s/%s as a favourite" % (path, filename))
        votes = favorites.setdefault(img, 0)
        favorites[img] = votes + 1
    else:
        logger.info("Un-marking image %s/%s as a favourite" % (path, filename))
        if img in favorites:
            favorites[img] -= 1
    favorites_registery[path] = favorites
    save_votes(path)


def app(environ, start_response):

    logger.info("Incoming request!")
    start_response('200 OK', [('Content-Type', 'text/html')])

    path = environ["PATH_INFO"].decode("utf-8")

    options = urlparse.parse_qs(environ["QUERY_STRING"])

    action = options.get("action", "getimages")[0]

    logger.info("Got request with action <%s>" % action)
    if action in ["favorite", "unfavorite"]:
        toggle_favorite(action, path, options)
        return ""
    else:
        return make_gallery(path, options)

logger.info("Starting to serve...")
WSGIServer(app, bindAddress = ("127.0.0.1", 8080)).run()
logger.info("Bye bye.")
