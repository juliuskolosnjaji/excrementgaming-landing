(function () {
  var list = document.getElementById('services-list');
  if (!list) return;

  var SECTION_TITLES = {
    projects: 'Projects',
    services: 'Services'
  };

  fetch('services.json')
    .then(function (res) {
      if (!res.ok) throw new Error('Failed to load');
      return res.json();
    })
    .then(function (entries) {
      if (!entries.length) {
        list.innerHTML = '<p class="muted">No services configured.</p>';
        return;
      }

      list.innerHTML = '';

      var grouped = entries.reduce(function (acc, entry) {
        var group = entry.category === 'projects' ? 'projects' : 'services';
        if (!acc[group]) acc[group] = [];
        acc[group].push(entry);
        return acc;
      }, {});

      var grid = document.createElement('div');
      grid.className = 'host-grid';

      ['projects', 'services'].forEach(function (groupKey) {
        var groupEntries = grouped[groupKey];
        if (!groupEntries || !groupEntries.length) return;

        var section = document.createElement('section');
        section.className = 'host-group';

        var title = document.createElement('h3');
        title.className = 'host-group-title';
        title.textContent = SECTION_TITLES[groupKey];
        section.appendChild(title);

        var table = document.createElement('div');
        table.className = 'host-table';

        groupEntries.forEach(function (svc) {
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

          table.appendChild(item);
        });

        section.appendChild(table);
        grid.appendChild(section);
      });

      list.appendChild(grid);
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
