    {% for img in imgs %}
    <div class="photo"><a href="{{ img.small }}" rel="lightbox"><img title="{{ "%s - %s" % (img.name, img.date) }}" src="{{ img.thumb }}" /></a></div>
    {% endfor %}
