    {% for img in imgs %}
    <div class="photo"><a href="{{ img.small }}" rel="lightbox[page]"><img title="{{ "%s - %s" % (img.name[:-4], img.date) }}" src="{{ img.thumb }}" /></a></div>
    {% endfor %}
