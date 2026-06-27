# -*- coding: UTF-8 -*-

"""Edit mode: authentication and filesystem operations for managing galleries.

Editing is gated behind HTTP Basic auth. Credentials come from the environment
(YAPG_EDIT_USER / YAPG_EDIT_PASSWORD); when either is unset, edit mode is
disabled entirely.

All write operations are confined to the photos root and validate every path
component, so a request can never escape it.
"""

import logging; logger = logging.getLogger("main")
import os
import glob
import hmac
import base64

from .image_processing import (STATIC_ROOT, EXTENSIONS, THUMBS_DIR, SMALL_DIR,
                               absolute_media_path)

# Absolute filesystem path of the photos root.
PHOTOS_ROOT = os.path.normpath(absolute_media_path("media/photos"))
# Shared thumbnails directory (see image_processing.create_thumbnails).
THUMBS_ROOT = os.path.normpath(absolute_media_path(os.path.join("media", THUMBS_DIR)))

MAX_FILENAME_BYTES = 255


# ---------------------------------------------------------------------------
# authentication
# ---------------------------------------------------------------------------

def _credentials():
    return os.environ.get("YAPG_EDIT_USER"), os.environ.get("YAPG_EDIT_PASSWORD")


def edit_enabled():
    user, password = _credentials()
    return bool(user and password)


def check_auth(environ):
    """True if the request carries valid HTTP Basic credentials."""
    user, password = _credentials()
    if not (user and password):
        return False

    header = environ.get("HTTP_AUTHORIZATION", "")
    if not header.startswith("Basic "):
        return False
    try:
        decoded = base64.b64decode(header[6:]).decode("utf-8")
    except Exception:
        return False
    req_user, sep, req_password = decoded.partition(":")
    if not sep:
        return False

    # constant-time comparison to avoid leaking credentials via timing
    ok_user = hmac.compare_digest(req_user, user)
    ok_password = hmac.compare_digest(req_password, password)
    return ok_user and ok_password


# ---------------------------------------------------------------------------
# path safety
# ---------------------------------------------------------------------------

def gallery_dir(path):
    """Resolve a gallery path ('/foo/bar') to an existing directory inside the
    photos root, or None if it escapes the root or is not a directory."""
    target = os.path.normpath(os.path.join(PHOTOS_ROOT, path.lstrip("/")))
    if target != PHOTOS_ROOT and not target.startswith(PHOTOS_ROOT + os.sep):
        logger.warning("Rejected out-of-root gallery path: %s", path)
        return None
    if not os.path.isdir(target):
        return None
    return target


def _safe_child(dirpath, name):
    """Return the absolute path of a direct child `name` of `dirpath`, or None
    if `name` contains path separators / traversal."""
    name = os.path.basename(name or "")
    if not name or name in (".", ".."):
        return None
    child = os.path.normpath(os.path.join(dirpath, name))
    if os.path.dirname(child) != dirpath:
        return None
    return child


def _is_image(name):
    return os.path.splitext(name)[1][1:] in EXTENSIONS


def _unique(dirpath, filename):
    """Return `filename`, or a non-clashing variant '<base> (n)<ext>'."""
    base, ext = os.path.splitext(filename)
    candidate, i = filename, 1
    while os.path.exists(os.path.join(dirpath, candidate)):
        candidate = "%s (%d)%s" % (base, i, ext)
        i += 1
    return candidate


# ---------------------------------------------------------------------------
# operations  (each returns (ok: bool, message: str))
# ---------------------------------------------------------------------------

def upload(path, filename, stream, length):
    """Stream an uploaded image (raw body) into the gallery directory."""
    directory = gallery_dir(path)
    if directory is None:
        return False, "Invalid gallery"
    if not _is_image(os.path.basename(filename or "")):
        return False, "Unsupported file type"

    dest_name = _unique(directory, os.path.basename(filename))
    dest = _safe_child(directory, dest_name)
    if dest is None:
        return False, "Invalid file name"

    written = 0
    remaining = length
    try:
        with open(dest, "wb") as out:
            while remaining > 0:
                chunk = stream.read(min(65536, remaining))
                if not chunk:
                    break
                out.write(chunk)
                written += len(chunk)
                remaining -= len(chunk)
    except OSError as e:
        logger.error("Upload of %s failed: %s", dest, e)
        return False, "Could not save file"

    logger.info("Uploaded %d bytes to %s", written, dest)
    return True, dest_name


def delete(path, name):
    """Delete an image and its derived thumbnail/small versions."""
    directory = gallery_dir(path)
    if directory is None:
        return False, "Invalid gallery"
    target = _safe_child(directory, name)
    if target is None or not os.path.isfile(target):
        return False, "No such image"

    try:
        os.remove(target)
    except OSError as e:
        logger.error("Could not delete %s: %s", target, e)
        return False, "Could not delete image"
    _remove_derived(directory, os.path.basename(name))
    logger.info("Deleted %s", target)
    return True, "deleted"


def set_caption(path, name, caption):
    """Change an image's caption by renaming it (captions live in the filename:
    '@caption.ext', with '/' encoded as '|')."""
    directory = gallery_dir(path)
    if directory is None:
        return False, "Invalid gallery"
    src = _safe_child(directory, name)
    if src is None or not os.path.isfile(src):
        return False, "No such image"

    ext = os.path.splitext(os.path.basename(name))[1]
    caption = (caption or "").replace("/", "|").strip()
    # strip control characters that have no place in a filename
    caption = "".join(c for c in caption if c >= " ")

    if caption:
        budget = MAX_FILENAME_BYTES - len((b"@" + ext.encode("utf-8")))
        caption = caption.encode("utf-8")[:budget].decode("utf-8", "ignore")
        new_name = "@" + caption + ext
    else:
        # caption cleared: fall back to a neutral, non-'@' name
        new_name = "photo" + ext

    if new_name == os.path.basename(name):
        return True, new_name

    new_name = _unique(directory, new_name)
    dest = _safe_child(directory, new_name)
    if dest is None:
        return False, "Invalid caption"

    try:
        os.rename(src, dest)
    except OSError as e:
        logger.error("Could not rename %s -> %s: %s", src, dest, e)
        return False, "Could not update caption"
    # derived files are keyed on the old name; drop them so they regenerate
    _remove_derived(directory, os.path.basename(name))
    logger.info("Renamed %s -> %s", src, dest)
    return True, new_name


def make_subdir(path, name):
    """Create a new subfolder inside the gallery."""
    directory = gallery_dir(path)
    if directory is None:
        return False, "Invalid gallery"
    name = os.path.basename((name or "").strip())
    if not name or name in (".", ".."):
        return False, "Invalid folder name"
    if name[0] in (".", "_"):
        return False, "Folder names cannot start with '.' or '_'"
    target = _safe_child(directory, name)
    if target is None:
        return False, "Invalid folder name"
    if os.path.exists(target):
        return False, "Folder already exists"

    try:
        os.mkdir(target)
    except OSError as e:
        logger.error("Could not create %s: %s", target, e)
        return False, "Could not create folder"
    logger.info("Created folder %s", target)
    return True, name


def _remove_derived(directory, name):
    """Best-effort removal of the thumbnail(s) and small version of `name`."""
    small = os.path.join(directory, SMALL_DIR.rstrip("/"), name)
    try:
        os.remove(small)
    except OSError:
        pass
    # thumbnails are named '<date>~~<name>' in the shared thumbs directory
    for thumb in glob.glob(os.path.join(THUMBS_ROOT, "*~~" + glob.escape(name))):
        try:
            os.remove(thumb)
        except OSError:
            pass
