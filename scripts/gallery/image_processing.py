# -*- coding: UTF-8 -*-

import logging; logger = logging.getLogger("main")
import os
import copy
import glob
from PIL import Image
import random
import datetime
import markdown 

# EXIF orientation, from http://sylvana.net/jpegcrop/exif_orientation.html
NORMAL = 1
UPSIDEDOWN = 3
LEFT = 8
RIGHT = 6

STATIC_ROOT = u"../static/"

thumbs_path = u"" # default to None -> original image dir
THUMBS_DIR = u"_thumbs/"
SMALL_DIR = u".small/"

SMALL_SIZE = (1200, 800)


THUMBS_SIZE_VERT = [(200, 200),
               (200, 400),
               (200, 300),
               (400, 400)]

THUMBS_SIZE_HORZ = [(200, 100),
               (400, 100),
               (400, 200)]

EXTENSIONS = ["jpg", "JPG", "png", "PNG"]

images = {}

def absolute_media_path(path):
    return STATIC_ROOT + path


class GuakamoleImage:

    def __init__(self, path):

        self.path = path
        self.dirname = os.path.dirname(path)

        self.abspath = absolute_media_path(path)
        self.absdirname = absolute_media_path(self.dirname)

        self.name = os.path.basename(path)


        self.img = Image.open(self.abspath)

        if self.img is None:
            logger.error("Failed to open <%s>. Skipping." % self.abspath)
            return

        self.date = self._date()
        logger.info("%s created at %s" % (self.name, self.date))

        self.thumbpath = (thumbs_path or (self.dirname + "/")) + THUMBS_DIR
        self.absthumbpath = absolute_media_path(self.thumbpath)

        self.thumb = self.thumbpath + self.date + "~~" + self.name
        self.absthumb = self.absthumbpath + self.date + "~~" + self.name

        self.smallpath = self.dirname + "/" + SMALL_DIR
        self.abssmallpath = absolute_media_path(self.smallpath)

        self.small = self.smallpath + self.name
        self.abssmall = self.abssmallpath + self.name

        self.caption = ""
        if self.name.startswith("@"):
            self.caption = markdown.markdown(self.name[1:-4].replace("|","/"))


        self._make_thumb() # Attention! modifies self.img -> EXIF rotate
        self._make_small() # Attention! modifies self.img!

        self.img = None # release memory!

    # comparing on thumbs name to get the creation date in!
    def __eq__(self, other):
        return self.date == other.date
    def __ne__(self, other):
        return self.date != other.date
    def __lt__(self, other):
        return self.date < other.date
    def __le__(self, other):
        return self.date <= other.date
    def __gt__(self, other):
        return self.date > other.date
    def __ge__(self, other):
        return self.date >= other.date

    def _date(self):
        """ returns the date of the picture, as a string suitable for inclusion in the file name.

        Tries first EXIF. If not available, uses creation timestamp.
        """

        exif = self.img._getexif()
        if exif and 36867 in exif: # exif -> DateTimeOriginal
            return exif[36867].replace(":","-").replace(" ", "-")



        logger.warning("No EXIF date. Using file creation date instead.")
        return datetime.datetime.fromtimestamp(os.path.getctime(self.abspath)).strftime("%Y-%m-%d-%H-%M-%S")


    def _clear_old_thumbs(self):
        logger.debug("TODO: clear old thumbs!!")

    def _make_thumb(self):

        if os.path.exists(self.absthumb):
            return

        logger.info("...creating thumb %s for %s" % (self.thumb, self.path))
        self.img = self._exif_rotate(self.img)

        self._clear_old_thumbs()
        self._extract_roi().save(self.absthumb)

    def _make_small(self):

        if os.path.exists(self.abssmall):
            return

        logger.info("...creating small version of %s" % (self.name))

        # rely on _make_thumb to rotate the image if necessary
        self.img.thumbnail(SMALL_SIZE, Image.ANTIALIAS)
        self.img.save(self.abssmall)


    def _exif_rotate(self, img):

        exif = img._getexif()

        if not exif:
            return img

        if 274 in exif: # 274 -> orientation
            orientation = exif[274]
            if orientation == UPSIDEDOWN:
                logger.info("Rotating the picture 180°")
                return img.rotate(180, expand = True)
            if orientation == LEFT:
                logger.info("Rotating the picture 90°")
                return img.rotate(90, expand = True)
            if orientation == RIGHT:
                logger.info("Rotating the picture -90°")
                return img.rotate(-90, expand = True)

        return img

    def _extract_roi(self):


        img = copy.copy(self.img)
        width, height = img.size


        if width > height:
            size = random.choice(THUMBS_SIZE_HORZ)
            img.thumbnail((size[0], size[0]), Image.ANTIALIAS)
            width, height = img.size
            box = (0, int((height - size[1]) / 2),
                   width, int((height + size[1]) / 2) )
        else:
            size = random.choice(THUMBS_SIZE_VERT)
            img.thumbnail((size[1], size[1]), Image.ANTIALIAS)
            width, height = img.size
            box = (int((width - size[0]) / 2), 0,
                   int((width + size[0]) / 2), height)


        return img.crop(box)

    def __repr__(self):
        return "%s - %s" % (self.name.encode("utf-8"), self.date)


def list_images(path):
    
    path = os.path.normpath(path)
    if path not in images:
        return []

    return images[path]


def compute_checksum(path):

    path = absolute_media_path(os.path.normpath(path))
    files = tuple(f for f in os.listdir(path) if os.path.splitext(f)[1][1:] in EXTENSIONS)
    return hash(files)


def create_thumbnails(directory, to = None):
    """ Generate thumbnails of a giving directory, and cache them in ./_thumbs
    """
    global thumbs_path, images

    directory = os.path.normpath(directory)

    if to:
        thumbs_path = to

    thumb_path = os.path.join(thumbs_path or directory, THUMBS_DIR)
    logger.info("Storing thumbs in <%s>..." % thumb_path)
    try:
        os.mkdir(absolute_media_path(thumb_path))
        logger.info("Creating it...")

    except OSError:
        pass

    small_path = os.path.join(directory, SMALL_DIR)
    logger.info("Storing small versions in <%s>..." % small_path)
    try:
        os.mkdir(absolute_media_path(small_path))
        logger.info("Creating it...")

    except OSError:
        pass


    path = absolute_media_path(directory)

    imgs = []
    files = [os.path.join(directory, f) for f in os.listdir(path) if os.path.splitext(f)[1][1:] in EXTENSIONS]
    nb_imgs = len(files)

    for index, img in enumerate(files):
        logger.info("Image %d/%d: %s" % (index + 1, nb_imgs, img))
        imgs.append(GuakamoleImage(img))

    imgs.sort() #sorts over the creation dates!

    images[directory] = imgs



