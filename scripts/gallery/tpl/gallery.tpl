<!DOCTYPE html>

<html>
<head>
    <meta charset="utf-8" />
    <script src="https://ajax.googleapis.com/ajax/libs/jquery/1.7.1/jquery.min.js"></script>
    <script src="/js/jquery.masonry.min.js"></script>
    <script src="/js/lightbox.js"></script>
    <link rel="stylesheet" href="/css/style.css" />
    <link rel="stylesheet" href="/css/lightbox.css" />
    <title>Guakamole : Fotos Y Takos</title>
</head>

<body>
<div id="header">
    <h1><a href="/"><img alt="Retour à la page d'accueil" src="/images/maison.svg" /></a>
    {% for part in title[0] %}
    &gt; <a href="{{ "/" + part }}">{{part.split("/")[-1]}}</a>
    {% endfor %}
    &gt; {{title[1]}}
    </h1>
</div>
{% if recents %}
<div id="recent">
{% for img in recents %}
    <div class="photo"><a href="/{{ img.small }}" rel="lightbox[page]"><img title="{{ "%s - %s" % (img.name[:-4], img.date) }}" src="/{{ img.thumb }}" /></a></div>
    {% endfor %}
</div>
{% endif %}
{% if badpath %}
Pas de photos à cette adresse ! <a href="/">Retour à la page d'accueil</a>.
{% endif %}
{% if dirs %}
<div id="directories">
    {% for d in dirs %}
    <a href="{{ d[1] }}">{{ d[0] }}</a>
    {% endfor %}
</div>
{% endif %}
{% if hasimgs %}
<div id="gallery">
{% include 'photo_items.tpl' %}
</div>

<div id="spinner"></div>

<script>
img_counter = {{ counter }};

batch_size = 20;

loading = true;
nomoreimages = false;

$container = $('#gallery');

$container.masonry({
        itemSelector : '.photo',
        columnWidth: 210,
        isAnimated: true,
        isFitWidth: true
  });

$(document).ready(function() {
    get_more();
});

function get_more() {
    $.get('{{ path }}?action=getimages&from=' + img_counter + '&nb=' + batch_size, function(data) {
            if (data == "") {
                $('#spinner').animate({ opacity: 0 });
                nomoreimages = true;
                return;
            }
            img_counter += batch_size;
            var $newElems = $(data).filter('div'); /*parse string into DOM structure and keep divs*/

            $newElems.css({ opacity: 0 });
            $container.append($newElems);
            $newElems.imagesLoaded(function(){
            $newElems.animate({ opacity: 1 });
{% if vote %}
            set_previous_favorites();
{% endif %}
            $container.masonry( 'appended', $newElems, true );
            loading = false;
            $('#spinner').animate({ opacity: 0 });
            });
    });
}

$(window).scroll(function(){
        if  (!loading && !nomoreimages &&
             $(window).scrollTop() > $(document).height() - $(window).height() - 300){
            loading = true;
            $('#spinner').animate({ opacity: 1 });
            get_more();
        }
});

{% if vote %}
function set_previous_favorites() {
    for(i=0; i < localStorage.length; i++){
        $("#fav_"+ localStorage.key(i).replace(".", "\\.")).parent().addClass("selected");
    }
}

function toggle_favorite(star, img) {
    // unmark favourite
    if ($(star).parent().hasClass("selected")) {
        $(star).parent().removeClass("selected");
        $.get('{{ path }}?img=' + img + '&action=unfavorite', function(data) {});
        localStorage.removeItem(img)
    }
    // mark favourite
    else {
        $(star).parent().addClass("selected");
        $.get('{{ path }}?img=' + img + '&action=favorite', function(data) {});
        localStorage.setItem(img, true)
    }
}
{% endif %}

</script>

{% endif %}
</body>
</html>
