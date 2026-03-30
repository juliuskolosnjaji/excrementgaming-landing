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
        var item = document.createElement('div');
        item.className = 'service-item';

        var hostname = '';
        try { hostname = new URL(svc.url).hostname; } catch (e) { hostname = svc.url; }

        var status = svc.status === 'online' ? 'online' : 'offline';

        item.innerHTML =
          '<div class="service-info">' +
            '<span class="service-status ' + status + '" title="' + status + '"></span>' +
            '<span class="service-name">' + esc(svc.name) + '</span>' +
            '<span class="service-sep"> &mdash; </span>' +
            '<span class="service-desc">' + esc(svc.description) + '</span>' +
          '</div>' +
          '<a class="service-link" href="' + esc(svc.url) + '" target="_blank" rel="noopener noreferrer">' +
            esc(hostname) + ' &nearr;' +
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
