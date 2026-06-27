{% for img in imgs %}
<figure class="photo" data-w="{{ img.thumb_w }}" data-h="{{ img.thumb_h }}"
        data-large="/{{ img.small }}" data-original="/{{ img.path }}"
        data-name="{{ img.name|e }}"{% if img.caption %} data-caption="{{ img.caption|e }}"{% endif %}>
    <img loading="lazy" src="/{{ img.thumb }}" alt="{{ img.name[:-4]|e }}" title="{{ "%s - %s" % (img.name[:-4], img.date) }}" />
    {% if img.caption %}<figcaption class="photo-caption">{{ img.caption }}</figcaption>{% endif %}
    <a class="downloadlink" title="Télécharger la photo originale" href="/{{ img.path }}" download aria-label="Télécharger l'original">&nbsp;</a>
    {% if vote %}
    <button type="button" class="favorite" title="Photo chouette" id="fav_{{ img.name }}" aria-label="Mettre en favori">&nbsp;</button>
    {% endif %}
</figure>
{% endfor %}
