# -*- coding: UTF-8 -*-

import os
import copy
import glob
import Image
import random
import datetime

# EXIF orientation, from http://sylvana.net/jpegcrop/exif_orientation.html
NORMAL = 1
UPSIDEDOWN = 3
LEFT = 8
RIGHT = 6

STATIC_ROOT = "../static/"

thumbs_path = "" # default to None -> original image dir
THUMBS_DIR = "_thumbs/"
SMALL_DIR = ".small/"

SMALL_SIZE = (1200, 800)


THUMBS_SIZE_VERT = [(200, 200),
               (200, 400),
               (200, 300),
               (400, 400)]

THUMBS_SIZE_HORZ = [(200, 100),
               (400, 100),
               (400, 200)]

EXTENSIONS = ["jpg", "JPG", "png", "PNG"]

images = []

def _abspath(path):
    return STATIC_ROOT + path


class GuakamoleImage:

    def __init__(self, path):

        self.path = path
        self.dirname = os.path.dirname(path)

        self.abspath = _abspath(path)
        self.absdirname = _abspath(self.dirname)

        self.name = os.path.basename(path)


        self.img = Image.open(self.abspath)

        self.date = self._date()
        print("%s created at %s" % (self.name, self.date))

        self.thumbpath = (thumbs_path or (self.dirname + "/")) + THUMBS_DIR
        self.absthumbpath = _abspath(self.thumbpath)

        self.thumb = self.thumbpath + self.date + "~~" + self.name
        self.absthumb = self.absthumbpath + self.date + "~~" + self.name

        self.smallpath = self.dirname + "/" + SMALL_DIR
        self.abssmallpath = _abspath(self.smallpath)

        self.small = self.smallpath + self.name
        self.abssmall = self.abssmallpath + self.name


        self._make_thumb() # Attention! modifies self.img -> EXIF rotate
        self._make_small() # Attention! modifies self.img!

        self.img = None # release memory!

    # comparing on thumbs name to get the creation date in!
    def __eq__(self, other):
        self.date == other.date
    def __ne__(self, other):
        self.date != other.date
    def __lt__(self, other):
        self.date < other.date
    def __le__(self, other):
        self.date <= other.date
    def __gt__(self, other):
        self.date > other.date
    def __ge__(self, other):
        self.date >= other.date

    def _date(self):
        """ returns the date of the picture, as a string suitable for inclusion in the file name.

        Tries first EXIF. If not available, uses creation timestamp.
        """

        try:
            exif = self.img._getexif()
            if 36867 in exif: # exif -> DateTimeOriginal
                return exif[36867].replace(":","-").replace(" ", "-")

        except AttributeError:
            pass


        print("No EXIF date. Using file creation date instead.")
        return datetime.datetime.fromtimestamp(os.path.getctime(self.abspath)).strftime("%Y-%m-%d-%H-%M-%S")


    def _clear_old_thumbs(self):
        print("TODO: clear old thumbs!!")

    def _make_thumb(self):

        if os.path.exists(self.absthumb):
            return

        print("...creating thumb %s for %s" % (self.thumb, self.path))
        self.img = self._exif_rotate(self.img)

        self._clear_old_thumbs()
        self._extract_roi().save(self.absthumb)

    def _make_small(self):

        if os.path.exists(self.abssmall):
            return

        print("...creating small version of %s" % (self.name))

        # rely on _make_thumb to rotate the image if necessary
        self.img.thumbnail(SMALL_SIZE, Image.ANTIALIAS)
        self.img.save(self.abssmall)


    def _exif_rotate(self, img):

        try:
            exif = img._getexif()
        except AttributeError:
            return img

        if 274 in exif: # 274 -> orientation
            orientation = exif[274]
            if orientation == UPSIDEDOWN:
                print("Rotating the picture 180°")
                return img.rotate(180, expand = True)
            if orientation == LEFT:
                print("Rotating the picture 90°")
                return img.rotate(90, expand = True)
            if orientation == RIGHT:
                print("Rotating the picture -90°")
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


def list_images(filt = None):
        if not filt:
            return images
        else:
            return [i for i in images if filt in i.path]

def create_thumbnails(directory, to = None):
    """ Generate thumbnails of a giving directory, and cache them in ./_thumbs
    """
    global thumbs_path, images

    if to:
        thumbs_path = to

    thumb_path = (thumbs_path or directory) + THUMBS_DIR
    print("Storing thumbs in <%s>..." % thumb_path)
    try:
        os.mkdir(_abspath(thumb_path))
        print("Creating it...")

    except OSError:
        pass

    small_path = directory + SMALL_DIR
    print("Storing small versions in <%s>..." % small_path)
    try:
        os.mkdir(_abspath(small_path))
        print("Creating it...")

    except OSError:
        pass


    path = _abspath(directory)

    imgs = [os.path.join(directory, f) for f in os.listdir(path) if os.path.splitext(f)[1][1:] in EXTENSIONS]
    lenimg = len(imgs)

    for index, img in enumerate(imgs):
        print("Image %d/%d: %s" % (index + 1, lenimg, img))
        images.append(GuakamoleImage(img))

    images.sort() #sorts over the creation dates!
