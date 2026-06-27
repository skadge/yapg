#!/usr/bin/env python3
# -*- coding: UTF-8 -*-

import logging; logger = logging.getLogger("main")
FORMAT = '%(asctime)s - %(levelname)s: %(message)s'
logging.basicConfig(format=FORMAT, level=logging.DEBUG)

import time

import sys, os
from urllib.parse import parse_qs
from jinja2 import Environment, PackageLoader
import json

from gallery.image_processing import *
from gallery import edit

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

def safe_gallery_path(path):
    """Confine a requested gallery path to the photos root.

    Anchoring with a leading '/' before normpath() collapses any '..' that
    would climb above the root, so the result always stays within
    media/photos/ (e.g. '/../../etc' becomes '/etc')."""
    return os.path.normpath('/' + path.lstrip('/'))

def make_gallery(path, options, edit_mode=False):

    content = ""
    fullpath= PHOTOS_BASE + path

    try:
        checksum = compute_checksum(fullpath) # compute a checksum of the path to detect changes
    except OSError as e:
        # the path does not exist!
        paths = path.split("/")[1:-1]
        title = (["/".join(paths[0:i+1]) for i in range(len(paths))], path.split("/")[-1])
        logger.info("Bad path! %s"%path)
        logger.error(str(e))
        return map(fixencoding, tpl.generate(title=title, path=path, badpath=True, dirs=None, hasimgs=False, recents=None, edit=edit_mode, edit_available=edit.edit_enabled()))

    if (fullpath not in visited_path) or visited_path[fullpath] != checksum:
        create_thumbnails(fullpath, to = MEDIA_BASE)
        visited_path[fullpath] = checksum

    start = int(options.get("from", [0])[0])
    end = start + int(options.get("nb", [0])[0])

    logger.info("Building gallery with pictures %d to %d in %s" % (start, end, fullpath))

    imgs = list_images(fullpath)
    imgs = apply_manual_order(fullpath, imgs)

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
                logger.info("Loading existing votes for gallery %s:" % path)
                with open(votes_json, "r") as f:
                    favorites_registery[path] = json.load(f)
                logger.info(str(favorites_registery))
            else:
                logger.info("No previous .votes.json. Creating it.")
                favorites_registery[path] = {}
                save_votes(path)

    if end - start != 0:
        if start >= len(imgs):
            logger.info("No more images")
            return ""
        if end > len(imgs):
            end = len(imgs)

        logger.info("Sending %d images" % (end - start))
        return map(fixencoding, items_tpl.generate(imgs = imgs[start:end], vote=vote_enabled, edit=edit_mode))

    else:

        parentdir = STATIC_ROOT + PHOTOS_BASE + path
        dirs_names = sorted([ name for name in os.listdir(parentdir) if os.path.isdir(os.path.join(parentdir, name)) and name[0] not in ['.', '_']], reverse=True)
        dirs = [ (name, os.path.join(path, name)) for name in dirs_names]

        paths = path.split("/")[1:-1]
        title = (["/".join(paths[0:i+1]) for i in range(len(paths))], path.split("/")[-1])
        logger.info("Sending base gallery")
        return map(fixencoding, tpl.generate(title=title,
                                              path=path,
                                              dirs=dirs,
                                              hasimgs=(len(imgs) > 0),
                                              imgs=imgs[start:end],
                                              recents=recents,
                                              vote=vote_enabled,
                                              counter=end,
                                              edit=edit_mode,
                                              edit_available=edit.edit_enabled()))


def load_order(fullpath):
    """Return the manual ordering (list of filenames) from .order.json, or None."""
    order_json = absolute_media_path(os.path.normpath(os.path.join(fullpath, ".order.json")))
    if os.path.exists(order_json):
        try:
            with open(order_json, "r") as f:
                return json.load(f)
        except (OSError, ValueError) as e:
            logger.error("Could not read %s: %s" % (order_json, e))
    return None


def apply_manual_order(fullpath, imgs):
    """Reorder `imgs` (already date-sorted) according to .order.json: listed
    files first in that order, any remaining files after them by date."""
    order = load_order(fullpath)
    if not order:
        return imgs
    rank = {name: i for i, name in enumerate(order)}
    listed = sorted((im for im in imgs if im.name in rank), key=lambda im: rank[im.name])
    rest = [im for im in imgs if im.name not in rank]
    return listed + rest


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
        votes = favorites.setdefault(filename, 0)
        favorites[filename] = votes + 1
    else:
        logger.info("Un-marking image %s/%s as a favourite" % (path, filename))
        if filename in favorites:
            favorites[filename] -= 1
    favorites_registery[path] = favorites
    save_votes(path)


HTML_HEADERS = [('Content-Type', 'text/html; charset=utf-8')]

EDIT_ACTIONS = ("upload", "delete", "setcaption", "mkdir", "reorder")


def handle_edit_action(action, path, options, environ, start_response):
    """Perform a write operation and return a small JSON status."""

    # Only same-origin requests issued by our own JS carry this header; it
    # cannot be set by a cross-site form, which gives us simple CSRF protection.
    if environ.get("HTTP_X_YAPG_EDIT") != "1" or environ.get("REQUEST_METHOD") != "POST":
        start_response('400 Bad Request', [('Content-Type', 'application/json; charset=utf-8')])
        return [b'{"ok": false, "msg": "Bad request"}']

    if action == "upload":
        length = int(environ.get("CONTENT_LENGTH") or 0)
        ok, msg = edit.upload(path, options.get("name", [""])[0],
                              environ["wsgi.input"], length)
    elif action == "delete":
        ok, msg = edit.delete(path, options.get("img", [""])[0])
    elif action == "setcaption":
        ok, msg = edit.set_caption(path, options.get("img", [""])[0],
                                   options.get("caption", [""])[0])
    elif action == "mkdir":
        ok, msg = edit.make_subdir(path, options.get("name", [""])[0])
    elif action == "reorder":
        length = int(environ.get("CONTENT_LENGTH") or 0)
        raw = environ["wsgi.input"].read(length) if length > 0 else b""
        try:
            names = json.loads(raw.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            names = None
        ok, msg = edit.reorder(path, names)
    else:
        ok, msg = False, "Unknown action"

    status = '200 OK' if ok else '400 Bad Request'
    start_response(status, [('Content-Type', 'application/json; charset=utf-8')])
    return [json.dumps({"ok": ok, "msg": msg}).encode("utf-8")]


def app(environ, start_response):

    logger.info("Incoming request!")

    # PEP 3333: PATH_INFO is a native string decoded from the raw bytes via
    # latin-1; re-encode to recover the original UTF-8 (accented gallery names).
    raw_path = environ["PATH_INFO"].encode('latin-1').decode('utf_8')

    options = parse_qs(environ["QUERY_STRING"])
    action = options.get("action", ["getimages"])[0]
    logger.info("Got request with action <%s>" % action)

    # ---- edit mode (gated behind HTTP Basic auth) --------------------------
    edit_mode = raw_path == "/edit" or raw_path.startswith("/edit/")
    if edit_mode:
        if not edit.edit_enabled():
            start_response('404 Not Found', HTML_HEADERS)
            return [b"Edit mode is disabled. Set YAPG_EDIT_USER and "
                    b"YAPG_EDIT_PASSWORD to enable it."]
        if not edit.check_auth(environ):
            start_response('401 Unauthorized', HTML_HEADERS + [
                ('WWW-Authenticate', 'Basic realm="YAPG edit", charset="UTF-8"')])
            return [b"Authentication required."]

        path = safe_gallery_path(raw_path[len("/edit"):])
        if action in EDIT_ACTIONS:
            return handle_edit_action(action, path, options, environ, start_response)
        start_response('200 OK', HTML_HEADERS)
        return make_gallery(path, options, edit_mode=True)

    # ---- normal (read-only) mode -------------------------------------------
    path = safe_gallery_path(raw_path)
    if action in ["favorite", "unfavorite"]:
        toggle_favorite(action, path, options)
        start_response('200 OK', HTML_HEADERS)
        return ""
    start_response('200 OK', HTML_HEADERS)
    return make_gallery(path, options)

if __name__ == "__main__":
    # Lightweight development server. In production, serve `photos:app` with
    # gunicorn instead (see README.md).
    from wsgiref.simple_server import make_server
    port = int(os.environ.get("PORT", 8083))
    logger.info("Starting development server on http://127.0.0.1:%d ..." % port)
    try:
        make_server("127.0.0.1", port, app).serve_forever()
    except KeyboardInterrupt:
        logger.info("Bye bye.")
