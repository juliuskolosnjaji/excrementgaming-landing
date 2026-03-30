(function () {
  var list = document.getElementById('services-list');
  if (!list) return;

  fetch('services.json')
    .then(function (res) {
      if (!res.ok) throw new Error('Failed to load');
      return res.json();
    })
    .then(function (services) {
      if (!services.length) {
        list.innerHTML = '<p class="muted">No services configured.</p>';
        return;
      }

      list.innerHTML = '';

      services.forEach(function (svc) {
        var item = document.createElement('article');
        item.className = 'service-item';

        var hostname = '';
        try {
          hostname = new URL(svc.url).hostname;
        } catch (e) {
          hostname = svc.url;
        }

        var status = svc.status === 'online' ? 'online' : 'offline';
        var statusLabel = status === 'online' ? 'online' : 'offline';

        item.innerHTML =
          '<div class="service-info">' +
            '<div class="service-meta">' +
              '<span class="service-status ' + status + '">' + statusLabel + '</span>' +
              '<span class="service-name">' + esc(svc.name) + '</span>' +
            '</div>' +
            '<p class="service-desc">' + esc(svc.description) + '</p>' +
          '</div>' +
          '<a class="service-link" href="' + esc(svc.url) + '" target="_blank" rel="noopener noreferrer">' +
            esc(hostname) + ' ->' +
          '</a>';

        list.appendChild(item);
      });
    })
    .catch(function () {
      list.innerHTML = '<p class="muted">Could not load services.</p>';
    });

  function esc(str) {
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }
})();
