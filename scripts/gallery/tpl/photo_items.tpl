    {% for img in imgs %}
    <div class="photo">
        <a href="/{{ img.small }}" rel="lightbox[page]"><img title="{{ "%s - %s" % (img.name[:-4], img.date) }}" src="/{{ img.thumb }}" /></a>
        <a class="downloadlink" title="Télécharger la photo originale" href="/{{ img.path }}">&nbsp;</a>
	<div class="photo-caption">{{ img.caption }}</div>
    </div>
    {% endfor %}
