<!DOCTYPE html>

<html lang="fr">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="theme-color" content="#000000" />
    <link rel="icon" href="/images/favicon.svg" type="image/svg+xml" />
    <link rel="alternate icon" href="/images/favicon.png" />
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
    {% if edit %}
    <a class="mode-toggle mode-exit" href="{{ path }}">&times;&nbsp;Quitter l'édition</a>
    {% elif edit_available %}
    <a class="mode-toggle mode-enter" href="{{ '/edit' + path }}" title="Passer en mode édition" aria-label="Passer en mode édition">&#9998;</a>
    {% endif %}
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
    <button id="reorder-btn" class="edit-btn" type="button">↕️ Réorganiser</button>
    <span id="edit-status" role="status"></span>
</div>

<div id="reorder" hidden>
    <div class="reorder-bar">
        <strong>Réorganiser la galerie</strong>
        <span id="reorder-status" class="reorder-status"></span>
        <span class="reorder-actions">
            <button id="reorder-cancel" type="button">Annuler</button>
            <button id="reorder-save" class="edit-btn" type="button">Enregistrer l'ordre</button>
        </span>
    </div>
    <ul id="reorder-list"></ul>
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
    var allPhotos = [];            // every photo in true sequence (server order)

    /* ---------- responsive masonry (shortest-column placement) ---------- */

    var MAX_COL = 5;               // cap so photos don't get too small on wide screens

    function columnCount() {
        var w = gallery.clientWidth;
        if (w < 480) return 2;
        if (w < 760) return 3;
        return Math.min(MAX_COL, Math.max(4, Math.floor((w + GUTTER) / (TARGET_COL + GUTTER))));
    }

    function buildColumns() {
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
        allPhotos.forEach(placePhoto);   // re-place in true order, not DOM order
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
                    allPhotos.push(photo);
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
    var lbCurrent = null;

    function photoList() {
        return allPhotos;   // true sequence, not column-major DOM order
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
        lbCurrent = photo;
        resetZoom();
        lbImg.src = photo.getAttribute('data-large');
        var caption = photo.getAttribute('data-caption');
        lbCaption.innerHTML = caption || '';
        lbCaption.hidden = !caption;
        lbDownload.href = photo.getAttribute('data-original');
    }

    function closeLightbox() {
        exitFullscreen();
        resetZoom();
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

    // touch swipe to navigate — only when the image isn't zoomed in
    var touchX = null;
    lb.addEventListener('touchstart', function (e) {
        touchX = (e.touches.length === 1 && lbScale <= 1.01) ? e.changedTouches[0].clientX : null;
    }, { passive: true });
    lb.addEventListener('touchend', function (e) {
        if (touchX === null || lbScale > 1.01) { touchX = null; return; }
        var dx = e.changedTouches[0].clientX - touchX;
        if (Math.abs(dx) > 50) navLightbox(dx < 0 ? 1 : -1);
        touchX = null;
    }, { passive: true });

    /* pinch / pan / double-tap zoom on the fullscreen image (page UI zoom is
       disabled via touch-action; here we transform only the image) */

    var lbScale = 1, lbTx = 0, lbTy = 0;
    var zMode = null, zStartDist = 0, zStartScale = 1;
    var zPanX = 0, zPanY = 0, zTx0 = 0, zTy0 = 0, zLastTap = 0;

    function resetZoom() {
        lbScale = 1; lbTx = 0; lbTy = 0; zMode = null;
        lbImg.style.transition = '';
        lbImg.style.transform = '';
    }

    function applyZoom() {
        lbImg.style.transform =
            'translate(' + lbTx + 'px,' + lbTy + 'px) scale(' + lbScale + ')';
    }

    function touchDist(t) {
        var dx = t[0].clientX - t[1].clientX, dy = t[0].clientY - t[1].clientY;
        return Math.sqrt(dx * dx + dy * dy);
    }

    lbImg.addEventListener('touchstart', function (e) {
        if (e.touches.length === 2) {
            zMode = 'pinch';
            zStartDist = touchDist(e.touches);
            zStartScale = lbScale;
            lbImg.style.transition = 'none';
            e.preventDefault();
        } else if (e.touches.length === 1 && lbScale > 1.01) {
            zMode = 'pan';
            zPanX = e.touches[0].clientX; zPanY = e.touches[0].clientY;
            zTx0 = lbTx; zTy0 = lbTy;
            lbImg.style.transition = 'none';
            e.preventDefault();
        }
    }, { passive: false });

    lbImg.addEventListener('touchmove', function (e) {
        if (zMode === 'pinch' && e.touches.length === 2) {
            lbScale = Math.min(6, Math.max(1, zStartScale * touchDist(e.touches) / zStartDist));
            applyZoom();
            e.preventDefault();
        } else if (zMode === 'pan' && e.touches.length === 1) {
            lbTx = zTx0 + (e.touches[0].clientX - zPanX);
            lbTy = zTy0 + (e.touches[0].clientY - zPanY);
            applyZoom();
            e.preventDefault();
        }
    }, { passive: false });

    lbImg.addEventListener('touchend', function (e) {
        lbImg.style.transition = '';
        // double-tap toggles zoom
        if (e.changedTouches.length === 1 && zMode === null) {
            var now = Date.now();
            if (now - zLastTap < 300) {
                if (lbScale > 1.01) resetZoom();
                else { lbScale = 2.5; applyZoom(); }
                e.preventDefault();
                zLastTap = 0;
                return;
            }
            zLastTap = now;
        }
        if (lbScale <= 1.01) resetZoom();
        if (e.touches.length === 0) {
            zMode = null;
        } else if (e.touches.length === 1 && lbScale > 1.01) {
            zMode = 'pan';            // released to one finger -> keep panning
            zPanX = e.touches[0].clientX; zPanY = e.touches[0].clientY;
            zTx0 = lbTx; zTy0 = lbTy;
        }
    }, { passive: false });

    /* native share: where the device supports sharing files, the download
       button becomes a "Partager" button that opens the OS share sheet with
       the actual image; otherwise it stays a plain download link */

    var SHARE_ICON = '<svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor" aria-hidden="true"><path d="M18 16.08c-.76 0-1.44.3-1.96.77L8.91 12.7c.05-.23.09-.46.09-.7s-.04-.47-.09-.7l7.05-4.11c.54.5 1.25.81 2.04.81 1.66 0 3-1.34 3-3s-1.34-3-3-3-3 1.34-3 3c0 .24.04.47.09.7L8.04 9.81C7.5 9.31 6.79 9 6 9c-1.66 0-3 1.34-3 3s1.34 3 3 3c.79 0 1.5-.31 2.04-.81l7.12 4.16c-.05.21-.08.43-.08.65 0 1.61 1.31 2.92 2.92 2.92s2.92-1.31 2.92-2.92-1.31-2.92-2.92-2.92z"/></svg>';

    function canShareFiles() {
        try {
            return !!(navigator.canShare && navigator.share &&
                navigator.canShare({ files: [new File([], 'x.jpg', { type: 'image/jpeg' })] }));
        } catch (e) { return false; }
    }

    function sharePhoto() {
        if (!lbCurrent) return;
        var url = lbCurrent.getAttribute('data-original');
        var name = lbCurrent.getAttribute('data-name') || 'photo.jpg';
        var caption = rawCaption(lbCurrent);
        lbDownload.classList.add('busy');
        fetch(url).then(function (r) { return r.blob(); }).then(function (blob) {
            var file = new File([blob], name, { type: blob.type || 'image/jpeg' });
            var data = { files: [file], title: caption || name };
            if (caption) data.text = caption;    // include the caption when there is one
            if (navigator.canShare && navigator.canShare(data)) {
                return navigator.share(data);
            }
            window.location.href = url;          // fallback: open the original
        }).catch(function (err) {
            if (!err || err.name !== 'AbortError') window.open(url, '_blank');
        }).then(function () { lbDownload.classList.remove('busy'); });
    }

    if (canShareFiles()) {
        lbDownload.innerHTML = SHARE_ICON + '<span>Partager</span>';
        lbDownload.setAttribute('aria-label', 'Partager');
        lbDownload.removeAttribute('download');
        lbDownload.addEventListener('click', function (e) { e.preventDefault(); sharePhoto(); });
    }

    /* ---------- editing ---------- */

    function editPost(query, body, contentType) {
        var opts = { method: 'POST', headers: { 'X-YAPG-Edit': '1' } };
        if (body !== undefined) {
            opts.body = body;
            opts.headers['Content-Type'] = contentType || 'application/octet-stream';
        }
        return fetch(BASE + query, opts).then(function (r) {
            // A non-JSON response (e.g. an nginx "413 Request Entity Too Large"
            // HTML page) still yields a useful, visible error message.
            return r.json().catch(function () {
                return { ok: false, msg: 'HTTP ' + r.status +
                         (r.status === 413 ? ' (fichier trop volumineux)' : '') };
            });
        }).catch(function () {
            return { ok: false, msg: 'réseau' };
        });
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
        var failures = [];
        function next(i) {
            if (i >= files.length) {
                if (failures.length) {
                    // keep the error on screen (don't reload) so it can be read
                    setStatus('Échec : ' + failures.join(' ; '));
                } else {
                    window.location.reload();
                }
                return;
            }
            var f = files[i];
            setStatus('Envoi ' + (i + 1) + '/' + files.length + ' : ' + f.name);
            editPost('?action=upload&name=' + encodeURIComponent(f.name),
                     f, f.type || 'application/octet-stream')
                .then(function (res) {
                    if (!res.ok) failures.push(f.name + ' — ' + (res.msg || '?'));
                })
                .then(function () { next(i + 1); });
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

    /* ---------- reorder ---------- */

    var reorderPanel = document.getElementById('reorder');

    function setReorderStatus(msg) {
        var el = document.getElementById('reorder-status');
        if (el) el.textContent = msg || '';
    }

    function reorderLabel(photo) {
        return rawCaption(photo) || photo.getAttribute('data-name');
    }

    function openReorder() {
        var list = document.getElementById('reorder-list');
        list.textContent = '';
        setReorderStatus('Chargement…');
        reorderPanel.hidden = false;
        // load the full list (independent of how far the gallery has scrolled)
        fetch(BASE + '?action=getimages&from=0&nb=100000')
            .then(function (r) { return r.text(); })
            .then(function (html) {
                var tmp = document.createElement('div');
                tmp.innerHTML = html;
                var photos = Array.prototype.slice.call(tmp.querySelectorAll('.photo'));
                photos.forEach(function (p) {
                    var li = document.createElement('li');
                    li.className = 'reorder-item';
                    li.setAttribute('data-name', p.getAttribute('data-name'));

                    var handle = document.createElement('span');
                    handle.className = 'reorder-handle';
                    handle.textContent = '☰';

                    var img = document.createElement('img');
                    img.src = p.querySelector('img').getAttribute('src');
                    img.loading = 'lazy';

                    var label = document.createElement('span');
                    label.className = 'reorder-label';
                    label.textContent = reorderLabel(p);

                    li.appendChild(handle);
                    li.appendChild(img);
                    li.appendChild(label);
                    list.appendChild(li);
                });
                setReorderStatus(photos.length + ' photos — glissez la poignée pour réordonner');
            })
            .catch(function () { setReorderStatus('Erreur de chargement'); });
    }

    function closeReorder() { reorderPanel.hidden = true; }

    function saveOrder() {
        var names = Array.prototype.map.call(
            document.querySelectorAll('#reorder-list .reorder-item'),
            function (li) { return li.getAttribute('data-name'); });
        setReorderStatus('Enregistrement…');
        editPost('?action=reorder', JSON.stringify(names), 'application/json')
            .then(function (res) {
                if (res.ok) window.location.reload();
                else setReorderStatus('Échec : ' + (res.msg || ''));
            });
    }

    function makeSortable(listEl) {
        var dragging = null;
        listEl.addEventListener('pointerdown', function (e) {
            var handle = e.target.closest('.reorder-handle');
            if (!handle) return;
            dragging = handle.closest('.reorder-item');
            if (!dragging) return;
            e.preventDefault();
            dragging.classList.add('dragging');
            listEl.setPointerCapture(e.pointerId);
        });
        listEl.addEventListener('pointermove', function (e) {
            if (!dragging) return;
            e.preventDefault();
            var others = Array.prototype.slice.call(
                listEl.querySelectorAll('.reorder-item:not(.dragging)'));
            var before = null;
            for (var i = 0; i < others.length; i++) {
                var r = others[i].getBoundingClientRect();
                if (e.clientY < r.top + r.height / 2) { before = others[i]; break; }
            }
            if (before) listEl.insertBefore(dragging, before);
            else listEl.appendChild(dragging);
        });
        function endDrag() {
            if (dragging) { dragging.classList.remove('dragging'); dragging = null; }
        }
        listEl.addEventListener('pointerup', endDrag);
        listEl.addEventListener('pointercancel', endDrag);
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
        var reorderBtn = document.getElementById('reorder-btn');
        if (reorderBtn) reorderBtn.addEventListener('click', openReorder);
        var reorderCancel = document.getElementById('reorder-cancel');
        if (reorderCancel) reorderCancel.addEventListener('click', closeReorder);
        var reorderSave = document.getElementById('reorder-save');
        if (reorderSave) reorderSave.addEventListener('click', saveOrder);
        if (reorderPanel) makeSortable(document.getElementById('reorder-list'));
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
