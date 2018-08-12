    {% for img in imgs %}
    <div class="photo">
        <a href="/{{ img.small }}" rel="lightbox[page]">
            <img title="{{ "%s - %s" % (img.name[:-4], img.date) }}" src="/{{ img.thumb }}" />
	<div class="photo-caption">{{ img.caption }}</div>
        <a class="downloadlink" title="Télécharger la photo originale" href="/{{ img.path }}">&nbsp;</a>
        {% if vote %}
        <a class="favorite" title="Photo chouette"
        onclick="toggle_favorite($(this),'{{ img.name }}')" href="#">&nbsp;</a>
        {% endif %}
        </a>
    </div>
    {% endfor %}
