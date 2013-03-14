<!DOCTYPE html>

<html>
<head>
    <meta charset="utf-8" />
    <script src="http://ajax.googleapis.com/ajax/libs/jquery/1.7.1/jquery.min.js"></script>
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
    &gt; <a href={{ "/" + part }}>{{part}}</a>
    {% endfor %}
    &gt; {{title[1]}}
    </h1>
</div>

<div id="directories">
    {% for d in dirs %}
    <a href="{{ d[1] }}">{{ d[0] }}</a>
    {% endfor %}
</div>

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
    $.get('{{ path }}?from=' + img_counter + '&nb=' + batch_size, function(data) {
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

</script>

</body>
</html>
