<!DOCTYPE html>

<html lang="fr">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="theme-color" content="#000000" />
    <link rel="stylesheet" href="/css/style.css" />
    <title>Guakamole : Fotos Y Takos</title>
</head>

<body{% if edit %} class="edit-mode"{% endif %}>
{% set prefix = '/edit' if edit else '' %}
<header id="header">
    <h1><a href="{{ prefix if prefix else '/' }}" aria-label="Retour à la page d'accueil"><img alt="Accueil" src="/images/maison.svg" /></a>
    {% for part in title[0] %}
    <span class="sep">&rsaquo;</span> <a href="{{ prefix + "/" + part }}">{{part.split("/")[-1]}}</a>
    {% endfor %}
    <span class="sep">&rsaquo;</span> {{title[1]}}
    {% if edit %}<span class="edit-badge">édition</span>{% endif %}
    </h1>
</header>

{% if badpath %}
<p class="message">Pas de photos à cette adresse ! <a href="/">Retour à la page d'accueil</a>.</p>
{% endif %}

{% if dirs %}
<nav id="directories">
    {% for d in dirs %}
    <a href="{{ prefix + d[1] }}">{{ d[0] }}</a>
    {% endfor %}
</nav>
{% endif %}

{% if edit %}
<div id="edit-toolbar">
    <label class="edit-btn" for="upload-input">➕ Ajouter des photos</label>
    <input id="upload-input" type="file" accept="image/jpeg,image/png" multiple class="sr-only" />
    <span class="edit-newfolder">
        <input id="newfolder-name" type="text" placeholder="Nom du dossier" />
        <button id="newfolder-btn" class="edit-btn" type="button">📁 Créer</button>
    </span>
    <span id="edit-status" role="status"></span>
</div>
{% endif %}

{% if hasimgs or edit %}
<div id="gallery"></div>
<div id="spinner" hidden></div>

<!-- Lightbox -->
<div id="lightbox" hidden aria-hidden="true" role="dialog" aria-modal="true">
    <button class="lb-close" type="button" aria-label="Fermer">&times;</button>
    <button class="lb-prev" type="button" aria-label="Précédent">&lsaquo;</button>
    <button class="lb-next" type="button" aria-label="Suivant">&rsaquo;</button>
    <figure class="lb-content">
        <img class="lb-image" alt="" />
        <figcaption class="lb-caption"></figcaption>
    </figure>
    <a class="lb-download" download aria-label="Télécharger l'original">Télécharger l'original</a>
</div>

<script>
(function () {
    "use strict";

    // Base URL for AJAX calls: the current path, so edit mode (/edit/...)
    // keeps routing through the authenticated prefix.
    var BASE = window.location.pathname;
    var VOTE = {{ (vote or false)|tojson }};
    var EDIT = {{ (edit or false)|tojson }};
    var BATCH = 20;
    var GUTTER = 8;
    var TARGET_COL = 240;          // desired column width (px) on large screens

    var gallery = document.getElementById('gallery');
    var spinner = document.getElementById('spinner');

    var counter = 0;
    var loading = false;
    var noMore = false;

    var columns = [];
    var colHeights = [];

    /* ---------- responsive masonry (shortest-column placement) ---------- */

    var MAX_COL = 5;               // cap so photos don't get too small on wide screens

    function columnCount() {
        var w = gallery.clientWidth;
        if (w < 480) return 2;
        if (w < 760) return 3;
        return Math.min(MAX_COL, Math.max(4, Math.floor((w + GUTTER) / (TARGET_COL + GUTTER))));
    }

    function buildColumns() {
        var photos = Array.prototype.slice.call(gallery.querySelectorAll('.photo'));
        var n = columnCount();
        gallery.textContent = '';
        columns = [];
        colHeights = [];
        for (var i = 0; i < n; i++) {
            var col = document.createElement('div');
            col.className = 'col';
            gallery.appendChild(col);
            columns.push(col);
            colHeights.push(0);
        }
        photos.forEach(placePhoto);
    }

    function shortestColumn() {
        var min = 0;
        for (var i = 1; i < colHeights.length; i++) {
            if (colHeights[i] < colHeights[min]) min = i;
        }
        return min;
    }

    function placePhoto(photo) {
        var w = parseFloat(photo.getAttribute('data-w')) || 1;
        var h = parseFloat(photo.getAttribute('data-h')) || 1;
        photo.style.aspectRatio = w + ' / ' + h;
        var i = shortestColumn();
        columns[i].appendChild(photo);
        var colWidth = columns[i].clientWidth || 1;
        colHeights[i] += colWidth * (h / w) + GUTTER;
    }

    /* ---------- infinite scroll ---------- */

    function getMore() {
        loading = true;
        spinner.hidden = false;
        fetch(BASE + '?action=getimages&from=' + counter + '&nb=' + BATCH)
            .then(function (r) { return r.text(); })
            .then(function (html) {
                if (!html.trim()) {
                    noMore = true;
                    spinner.hidden = true;
                    return;
                }
                counter += BATCH;
                var tmp = document.createElement('div');
                tmp.innerHTML = html;
                var fresh = Array.prototype.slice.call(tmp.querySelectorAll('.photo'));
                fresh.forEach(function (photo) {
                    photo.classList.add('loading');
                    placePhoto(photo);
                    var img = photo.querySelector('img');
                    if (img.complete) {
                        photo.classList.remove('loading');
                    } else {
                        img.addEventListener('load', function () { photo.classList.remove('loading'); });
                        img.addEventListener('error', function () { photo.classList.remove('loading'); });
                    }
                });
                if (VOTE) applyStoredFavorites();
                loading = false;
                spinner.hidden = true;
                maybeLoadMore();
            })
            .catch(function () { loading = false; spinner.hidden = true; });
    }

    function maybeLoadMore() {
        if (loading || noMore) return;
        var nearBottom = window.innerHeight + window.scrollY >
                         document.body.offsetHeight - 600;
        if (nearBottom) getMore();
    }

    window.addEventListener('scroll', maybeLoadMore, { passive: true });

    var resizeTimer;
    window.addEventListener('resize', function () {
        clearTimeout(resizeTimer);
        resizeTimer = setTimeout(function () {
            // Only rebuild when the column count actually changes. Mobile
            // browsers fire 'resize' on scroll (the address bar shows/hides,
            // changing the viewport height); rebuilding then would reshuffle
            // the columns and jump back to the top.
            if (columnCount() !== columns.length) buildColumns();
            maybeLoadMore();
        }, 150);
    });

    /* ---------- voting ---------- */

    function favKey(name) { return 'fav:' + name; }

    function applyStoredFavorites() {
        gallery.querySelectorAll('.photo').forEach(function (photo) {
            var name = photo.getAttribute('data-name');
            if (localStorage.getItem(favKey(name))) photo.classList.add('selected');
        });
    }

    function toggleFavorite(photo) {
        var name = photo.getAttribute('data-name');
        var selected = photo.classList.toggle('selected');
        var action = selected ? 'favorite' : 'unfavorite';
        if (selected) localStorage.setItem(favKey(name), '1');
        else localStorage.removeItem(favKey(name));
        fetch(BASE + '?action=' + action + '&img=' + encodeURIComponent(name));
    }

    /* ---------- lightbox ---------- */

    var lb = document.getElementById('lightbox');
    var lbImg = lb.querySelector('.lb-image');
    var lbCaption = lb.querySelector('.lb-caption');
    var lbDownload = lb.querySelector('.lb-download');
    var lbIndex = -1;

    function photoList() {
        return Array.prototype.slice.call(gallery.querySelectorAll('.photo'));
    }

    // On touch devices, use the whole screen for the lightbox. Triggered from
    // a tap (a user gesture), so requestFullscreen is allowed; degrades quietly
    // where it isn't supported (e.g. iOS Safari only allows it on <video>).
    var wantFullscreen = window.matchMedia('(hover: none)').matches;

    function enterFullscreen() {
        if (!wantFullscreen || document.fullscreenElement) return;
        var fn = lb.requestFullscreen || lb.webkitRequestFullscreen;
        if (fn) { try { var p = fn.call(lb); if (p && p.catch) p.catch(function () {}); } catch (e) {} }
    }

    function exitFullscreen() {
        var el = document.fullscreenElement || document.webkitFullscreenElement;
        if (!el) return;
        var fn = document.exitFullscreen || document.webkitExitFullscreen;
        if (fn) { try { var p = fn.call(document); if (p && p.catch) p.catch(function () {}); } catch (e) {} }
    }

    function openLightbox(photo) {
        lbIndex = photoList().indexOf(photo);
        showLightbox();
        lb.hidden = false;
        lb.setAttribute('aria-hidden', 'false');
        document.body.classList.add('lb-open');
        enterFullscreen();
    }

    function showLightbox() {
        var photos = photoList();
        if (lbIndex < 0 || lbIndex >= photos.length) return;
        var photo = photos[lbIndex];
        lbImg.src = photo.getAttribute('data-large');
        var caption = photo.getAttribute('data-caption');
        lbCaption.innerHTML = caption || '';
        lbCaption.hidden = !caption;
        lbDownload.href = photo.getAttribute('data-original');
    }

    function closeLightbox() {
        exitFullscreen();
        lb.hidden = true;
        lb.setAttribute('aria-hidden', 'true');
        lbImg.removeAttribute('src');
        document.body.classList.remove('lb-open');
    }

    // Closing fullscreen (e.g. system back/gesture) should close the lightbox.
    document.addEventListener('fullscreenchange', function () {
        if (!document.fullscreenElement && !lb.hidden) closeLightbox();
    });

    function navLightbox(delta) {
        var photos = photoList();
        var next = lbIndex + delta;
        if (next < 0 || next >= photos.length) return;
        lbIndex = next;
        showLightbox();
    }

    lb.querySelector('.lb-close').addEventListener('click', closeLightbox);
    lb.querySelector('.lb-prev').addEventListener('click', function () { navLightbox(-1); });
    lb.querySelector('.lb-next').addEventListener('click', function () { navLightbox(1); });
    lb.addEventListener('click', function (e) {
        if (e.target === lb || e.target.classList.contains('lb-content')) closeLightbox();
    });

    document.addEventListener('keydown', function (e) {
        if (lb.hidden) return;
        if (e.key === 'Escape') closeLightbox();
        else if (e.key === 'ArrowLeft') navLightbox(-1);
        else if (e.key === 'ArrowRight') navLightbox(1);
    });

    // touch swipe inside the lightbox
    var touchX = null;
    lb.addEventListener('touchstart', function (e) { touchX = e.changedTouches[0].clientX; }, { passive: true });
    lb.addEventListener('touchend', function (e) {
        if (touchX === null) return;
        var dx = e.changedTouches[0].clientX - touchX;
        if (Math.abs(dx) > 50) navLightbox(dx < 0 ? 1 : -1);
        touchX = null;
    }, { passive: true });

    /* ---------- editing ---------- */

    function editPost(query, body, contentType) {
        var opts = { method: 'POST', headers: { 'X-YAPG-Edit': '1' } };
        if (body !== undefined) {
            opts.body = body;
            opts.headers['Content-Type'] = contentType || 'application/octet-stream';
        }
        return fetch(BASE + query, opts).then(function (r) { return r.json(); });
    }

    function setStatus(msg) {
        var el = document.getElementById('edit-status');
        if (el) el.textContent = msg || '';
    }

    function rawCaption(photo) {
        var name = photo.getAttribute('data-name') || '';
        if (name.charAt(0) !== '@') return '';
        var dot = name.lastIndexOf('.');
        var base = dot > 0 ? name.slice(1, dot) : name.slice(1);
        return base.replace(/\|/g, '/');
    }

    function uploadFiles(files) {
        if (!files.length) return;
        var done = 0, failed = 0;
        function next(i) {
            if (i >= files.length) {
                if (failed) setStatus(failed + ' échec(s) sur ' + files.length);
                window.location.reload();
                return;
            }
            var f = files[i];
            setStatus('Envoi ' + (i + 1) + '/' + files.length + ' : ' + f.name);
            editPost('?action=upload&name=' + encodeURIComponent(f.name),
                     f, f.type || 'application/octet-stream')
                .then(function (res) { if (!res.ok) failed++; })
                .catch(function () { failed++; })
                .then(function () { done++; next(i + 1); });
        }
        next(0);
    }

    function deletePhoto(photo) {
        var name = photo.getAttribute('data-name');
        if (!window.confirm('Supprimer cette photo ?\n' + name)) return;
        editPost('?action=delete&img=' + encodeURIComponent(name))
            .then(function (res) {
                if (res.ok) window.location.reload();
                else setStatus('Suppression impossible : ' + (res.msg || ''));
            });
    }

    function editCaption(photo) {
        var name = photo.getAttribute('data-name');
        var current = rawCaption(photo);
        var caption = window.prompt('Légende (vide pour supprimer) :', current);
        if (caption === null) return;
        editPost('?action=setcaption&img=' + encodeURIComponent(name) +
                 '&caption=' + encodeURIComponent(caption))
            .then(function (res) {
                if (res.ok) window.location.reload();
                else setStatus('Légende non modifiée : ' + (res.msg || ''));
            });
    }

    if (EDIT) {
        var uploadInput = document.getElementById('upload-input');
        if (uploadInput) {
            uploadInput.addEventListener('change', function () {
                uploadFiles(Array.prototype.slice.call(this.files));
            });
        }
        var newFolderBtn = document.getElementById('newfolder-btn');
        var newFolderName = document.getElementById('newfolder-name');
        if (newFolderBtn) {
            newFolderBtn.addEventListener('click', function () {
                var name = (newFolderName.value || '').trim();
                if (!name) return;
                editPost('?action=mkdir&name=' + encodeURIComponent(name))
                    .then(function (res) {
                        if (res.ok) window.location.reload();
                        else setStatus('Dossier non créé : ' + (res.msg || ''));
                    });
            });
        }
    }

    /* ---------- delegated clicks on the gallery ---------- */

    gallery.addEventListener('click', function (e) {
        if (EDIT) {
            var del = e.target.closest('.edit-delete');
            if (del) { e.preventDefault(); deletePhoto(del.closest('.photo')); return; }
            var cap = e.target.closest('.edit-caption');
            if (cap) { e.preventDefault(); editCaption(cap.closest('.photo')); return; }
        }
        var fav = e.target.closest('.favorite');
        if (fav) { e.preventDefault(); toggleFavorite(fav.closest('.photo')); return; }
        if (e.target.closest('.downloadlink')) return; // let the download happen
        var photo = e.target.closest('.photo');
        if (photo) { e.preventDefault(); openLightbox(photo); }
    });

    /* ---------- go ---------- */

    buildColumns();
    getMore();
})();
</script>
{% endif %}
</body>
</html>
