/* ===== SWS Admin Dashboard – JavaScript ===== */
'use strict';

// ---- Navigation ----
const sections = document.querySelectorAll('.sws-section');
const navLinks  = document.querySelectorAll('.sws-nav-link[data-section]');

function showSection(id) {
  sections.forEach(s => { s.style.display = s.id === id ? '' : 'none'; });
  navLinks.forEach(a => a.classList.toggle('active', a.dataset.section === id));
  const titleEl  = document.getElementById('sws-page-title');
  const activeLink = document.querySelector(`.sws-nav-link[data-section="${id}"]`);
  if (titleEl && activeLink) titleEl.textContent = activeLink.textContent.trim();
  loaders[id]?.();
}

navLinks.forEach(a => a.addEventListener('click', e => {
  e.preventDefault();
  showSection(a.dataset.section);
}));

// ---- API helper ----
const CSRF_TOKEN = document.querySelector('meta[name="csrf-token"]')?.content ?? '';

async function api(path, method = 'GET', body = null) {
  const headers = { 'Content-Type': 'application/json' };
  if (['POST','PATCH','DELETE','PUT'].includes(method)) headers['X-CSRF-Token'] = CSRF_TOKEN;
  const opts = { method, headers };
  if (body) opts.body = JSON.stringify(body);
  const r = await fetch(`?action=api/${path}`, opts);
  return r.json();
}

// ---- Tabellen-Helper ----
function renderTable(targetId, columns, rows, actions) {
  const el = document.getElementById(targetId);
  if (!rows.length) { el.innerHTML = '<p class="fg-secondary">Keine Einträge.</p>'; return; }
  const head = columns.map(c => `<th>${c.label}</th>`).join('');
  const body = rows.map(row => {
    const cells = columns.map(c => `<td>${row[c.key] ?? ''}</td>`).join('');
    const btns  = actions.map(a => `<td><button class="btn-del" onclick="${a.fn}(${a.arg(row)})">${a.label}</button></td>`).join('');
    return `<tr>${cells}${btns}</tr>`;
  }).join('');
  el.innerHTML = `<table><thead><tr>${head}<th></th></tr></thead><tbody>${body}</tbody></table>`;
}

// ---- Stationen ----
async function loadStations() {
  const rows = await api('stations');
  const el = document.getElementById('stations-table');
  if (!rows.length) { el.innerHTML = '<p class="fg-secondary">Keine Einträge.</p>'; return; }
  el.innerHTML = `<table>
    <thead><tr><th>ID</th><th>Slug</th><th>Name</th><th>MAC</th><th>Letzte Aktivit&#228;t</th><th>Firmware</th><th>Erstellt</th><th></th><th></th></tr></thead>
    <tbody>${rows.map(r => `<tr>
      <td>${r.id}</td>
      <td><code>${r.slug}</code></td>
      <td>${r.name}</td>
      <td class="fg-secondary" style="font-size:.82rem;font-family:monospace">${r.mac ?? '–'}</td>
      <td class="fg-secondary" style="font-size:.85rem">${r.last_seen ?? '–'}</td>
      <td style="font-size:.82rem">${r.fw_version ? '<code>'+r.fw_version+'</code>' : '–'}</td>
      <td class="fg-secondary" style="font-size:.85rem">${r.created_at ?? ''}</td>
      <td><button class="btn-edit" onclick="editStation(${r.id},'${r.slug.replace(/'/g,"\\'")}','${r.name.replace(/'/g,"\\'")}','${(r.mac??'').replace(/'/g,"\\'")}')">Bearbeiten</button></td>
      <td><button class="btn-del"  onclick="deleteStation(${r.id})">Löschen</button></td>
    </tr>`).join('')}</tbody></table>`;
  // Live-Station-Dropdown und History-Station-Dropdown befüllen
  const sel = document.getElementById('live-station');
  sel.innerHTML = rows.map(r => `<option value="${r.slug}">${r.name}</option>`).join('');
  const selH = document.getElementById('history-station');
  if (selH) selH.innerHTML = sel.innerHTML;
}

function openAddStation() {
  openEditModal('Neue Station', [
    { label: 'Name',  name: 'name',  value: '', type: 'text' },
    { label: 'Slug',  name: 'slug',  value: '', type: 'text', hint: 'Nur a\u2013z, 0\u20139, Bindestrich (z.\u202fB.\u00a0sws-garten)' },
  ], async data => {
    const res = await api('stations', 'POST', { name: data.name, slug: data.slug });
    if (res.error) throw new Error(res.error);
    loadStations();
  });
}

function editStation(id, slug, name, mac = '') {
  openEditModal('Station bearbeiten', [
    { label: 'Name',  name: 'name',  value: name, type: 'text' },
    { label: 'Slug',  name: 'slug',  value: slug, type: 'text', hint: 'Nur a–z, 0–9, Bindestrich' },
    { label: 'MAC',   name: 'mac',   value: mac,  type: 'text', hint: 'Wird automatisch von der Station gesetzt', required: false },
  ], async data => {
    const body = { id, name: data.name, slug: data.slug };
    if (data.mac !== undefined) body.mac = data.mac || null;
    const res = await api('stations', 'PATCH', body);
    if (!res.ok) throw new Error(res.error ?? 'Fehler');
    loadStations();
  });
}

async function deleteStation(id) {
  if (!confirm('Station wirklich löschen?')) return;
  await api(`stations&id=${id}`, 'DELETE');
  loadStations();
}

// ---- Metriken ----
async function loadMetrics() {
  const rows = await api('metrics');
  renderTable('metrics-table',
    [{key:'metric_key',label:'Key'},{key:'label',label:'Bezeichnung'},
     {key:'unit',label:'Einheit'},{key:'display_order',label:'Reihenfolge'},
     {key:'chart_color',label:'Farbe'}],
    rows,
    [{label:'Löschen', fn:'deleteMetric', arg: r => `'${r.metric_key}'`}]
  );
}

async function deleteMetric(key) {
  if (!confirm(`Metrik "${key}" wirklich löschen?`)) return;
  await api(`metrics&key=${key}`, 'DELETE');
  loadMetrics();
}

function openAddMetric(existing = null) {
  document.getElementById('modal-title').textContent = existing ? 'Metrik bearbeiten' : 'Metrik hinzufügen';
  const f = document.getElementById('metric-form');
  f.reset();
  if (existing) {
    f.metric_key.value       = existing.metric_key;
    f.metric_key.readOnly    = true;
    f.metric_key_orig.value  = existing.metric_key;
    f.label.value            = existing.label;
    f.unit.value             = existing.unit;
    f.display_order.value    = existing.display_order;
    f.chart_color.value      = existing.chart_color;
  } else {
    f.metric_key.readOnly = false;
  }
  document.getElementById('modal').style.display = '';
}

function closeModal() { document.getElementById('modal').style.display = 'none'; }

document.getElementById('metric-form')?.addEventListener('submit', async e => {
  e.preventDefault();
  const f = e.target;
  await api('metrics', 'POST', {
    metric_key:    f.metric_key.value,
    label:         f.label.value,
    unit:          f.unit.value,
    display_order: parseInt(f.display_order.value, 10),
    chart_color:   f.chart_color.value,
  });
  closeModal();
  loadMetrics();
});

// ---- Benutzer ----
async function loadUsers() {
  const rows = await api('users');
  const el = document.getElementById('users-table');
  if (!Array.isArray(rows) || !rows.length) { el.innerHTML = '<p class="fg-secondary">Keine Einträge.</p>'; return; }
  el.innerHTML = `<table>
    <thead><tr><th>ID</th><th>E-Mail</th><th>Rolle</th><th>Erstellt</th><th></th><th></th></tr></thead>
    <tbody>${rows.map(r => `<tr>
      <td>${r.id}</td>
      <td>${r.email}</td>
      <td><span class="role-badge role-${r.role ?? 'user'}">${r.role ?? 'user'}</span></td>
      <td class="fg-secondary" style="font-size:.85rem">${r.created_at ?? ''}</td>
      <td><button class="btn-edit" onclick="editUser(${r.id},'${r.email.replace(/'/g,"\\'")  }','${(r.role??'user').replace(/'/g,"\\'")}')">Bearbeiten</button></td>
      <td>${r.role !== 'admin' ? `<button class="btn-del" onclick="deleteUser(${r.id})">Löschen</button>` : ''}</td>
    </tr>`).join('')}</tbody></table>`;
}

function editUser(id, email, role) {
  openEditModal('Benutzer bearbeiten', [
    { label: 'E-Mail',         name: 'email',    value: email, type: 'email' },
    { label: 'Rolle',          name: 'role',     value: role,  type: 'select', options: ['user','admin'] },
    { label: 'Neues Passwort', name: 'password', value: '',    type: 'password', hint: 'Leer lassen = nicht ändern', required: false },
  ], async data => {
    const body = { id };
    if (data.email)    body.email    = data.email;
    if (data.role)     body.role     = data.role;
    if (data.password) body.password = data.password;
    const res = await api('users', 'PATCH', body);
    if (!res.ok) throw new Error(res.error ?? 'Fehler');
    loadUsers();
  });
}

async function deleteUser(id) {
  if (!confirm('Benutzer wirklich löschen?')) return;
  const res = await api(`users&id=${id}`, 'DELETE');
  if (res.error) { alert(res.error); return; }
  loadUsers();
}

// ---- Einladungen ----
async function loadInvites() {
  const rows = await api('invites');
  renderTable('invites-table',
    [{key:'id',label:'ID'},{key:'code',label:'Code'},
     {key:'created_at',label:'Erstellt'},{key:'used_at',label:'Verwendet'}],
    rows,
    [{label:'Löschen', fn:'deleteInvite', arg: r => r.id}]
  );
}

async function createInvite() {
  const res = await api('invites', 'POST');
  alert(`Neuer Code: ${res.code}`);
  loadInvites();
}

async function deleteInvite(id) {
  if (!confirm('Einladung wirklich löschen?')) return;
  await api(`invites&id=${id}`, 'DELETE');
  loadInvites();
}

// ---- Live-Daten ----
let liveTimer = null;

// Metriken die als Gauge dargestellt werden (key → {min, max})
// Metro gauge: data-value ist der absolute Wert zwischen data-min und data-max
const GAUGE_METRICS = {
  // Temperatur: -30°C blau → 18-24°C grün (angenehm) → 28°C gelb → 60°C rot
  temperature:         { min: -30, max: 60,  colorClass: 'gauge-temp' },
  pool_temperature:    { min: -10, max: 50,  colorClass: 'gauge-pool' },
  heat_index:          { min: -30, max: 60,  colorClass: 'gauge-temp' },
  dewpoint:            { min: -10, max: 30,  colorClass: 'gauge-dew'  },
  // Luftfeuchte: <30% blau (trocken) → 40-60% grün → >70% rot (feucht)
  humidity:            { min: 0,   max: 100, colorClass: 'gauge-hum'  },
  // Batterie: 0% rot → 50% gelb → 100% grün
  battery_pct:         { min: 0,   max: 100, colorClass: 'gauge-bat'  },
};

function renderGauge(value, min, max, unit, label, colorClass) {
  // Wert auf 1 Nachkommastelle runden (Metro zeigt den Rohwert an)
  const rounded = Math.round(value * 10) / 10;
  const clamped = Math.max(min, Math.min(max, rounded));
  const suffix   = unit ? ` ${unit}` : '';
  const cls = colorClass || '';
  return `<div class="sws-gauge-box ${cls}">
    <div data-role="gauge"
         data-value="${clamped}"
         data-min="${min}"
         data-max="${max}"
         data-label-min="${min}"
         data-label-max="${max}"
         data-suffix="${suffix}"
         data-label="${label}"
         data-values="5"
         data-segments="10"
         data-size="200"></div>
  </div>`;
}

async function loadLive() {
  const slug = document.getElementById('live-station').value;
  const d = await api(`live&station=${encodeURIComponent(slug)}`);
  const grid = document.getElementById('live-data');
  if (d.error) { grid.innerHTML = `<p class="fg-secondary">${d.error}</p>`; return; }

  const ts = d.created_at
    ? (() => {
        // Server liefert UTC ohne Timezone-Kennzeichnung – als UTC parsen
        const utc = d.created_at.replace(' ', 'T') + 'Z';
        const dt  = new Date(utc);
        const fmt = dt.toLocaleString('de-DE', {
          timeZone:    'Europe/Berlin',
          day:         '2-digit',
          month:       '2-digit',
          year:        'numeric',
          hour:        '2-digit',
          minute:      '2-digit',
          second:      '2-digit',
        });
        return `<p class="sws-live-ts"><span class="mif-clock"></span> Letzte Messung: ${fmt} Uhr</p>`;
      })()
    : '';

  const gauges = [];
  const cards  = [];

  d.values.forEach(v => {
    const key    = v.metric_key;
    const num    = parseFloat(v.value);
    const isNum  = !isNaN(num) && String(v.value).trim() !== '';
    const gaugeCfg = GAUGE_METRICS[key];
    const label  = (v.label ?? key).trim();
    const unit   = (v.unit ?? '').trim();

    if (isNum && gaugeCfg) {
      gauges.push(renderGauge(num, gaugeCfg.min, gaugeCfg.max, unit, label, gaugeCfg.colorClass));
    } else {
      const display = isNum
        ? num.toLocaleString('de-DE', { maximumFractionDigits: 1 })
        : (v.value ?? '\u2013');
      cards.push(`<div class="sws-live-box">
        <div class="val${isNum ? '' : ' text'}">${display}</div>
        <div class="unit">${unit}</div>
        <div class="lbl">${label}</div>
      </div>`);
    }
  });

  const gaugeRow = gauges.length
    ? `<div class="sws-live-grid" style="margin-bottom:18px">${gauges.join('')}</div>`
    : '';
  const cardRow  = cards.length
    ? `<div class="sws-live-grid">${cards.join('')}</div>`
    : '';

  grid.innerHTML = ts + gaugeRow + cardRow;

  // Metro-Gauges initialisieren (kurz warten bis DOM gerendert ist)
  if (gauges.length && window.Metro) {
    setTimeout(() => {
      grid.querySelectorAll('[data-role="gauge"]').forEach(el => {
        if (!el.dataset.metroComponent) Metro.makePlugin(el, 'gauge');
      });
    }, 50);
  }
}

document.getElementById('live-station')?.addEventListener('change', loadLive);

// ---- Historie ----
const historyCharts = {};   // metric_key → Chart-Instanz

const HISTORY_COLORS = {
  temperature:      '#e15759',
  pool_temperature: '#4e79a7',
  humidity:         '#59a14f',
  rel_pressure:     '#9c755f',
  battery_pct:      '#f28e2b',
};

function tsToLocal(utcStr) {
  // Server liefert UTC ohne Timezone-Kennzeichnung
  return new Date(utcStr.replace(' ', 'T') + 'Z');
}

async function loadHistory() {
  const slug  = document.getElementById('history-station').value;
  const hours = document.getElementById('history-hours').value;
  const grid  = document.getElementById('history-charts');
  if (!slug) return;

  grid.innerHTML = '<p class="fg-secondary">Lade…</p>';

  const d = await api(`history&station=${encodeURIComponent(slug)}&hours=${hours}`);
  if (d.error) { grid.innerHTML = `<p class="fg-secondary">${d.error}</p>`; return; }
  if (!d.series?.length) { grid.innerHTML = '<p class="fg-secondary">Keine Daten im gewählten Zeitraum.</p>'; return; }

  // Alte Charts zerstören
  Object.values(historyCharts).forEach(c => c.destroy());
  Object.keys(historyCharts).forEach(k => delete historyCharts[k]);

  grid.innerHTML = d.series.map(s =>
    `<div class="sws-history-card">
       <div class="sws-history-title">${s.label}${s.unit ? ' (' + s.unit + ')' : ''}</div>
       <canvas id="hc-${s.label.replace(/\W/g,'_')}"></canvas>
     </div>`
  ).join('');

  d.series.forEach(s => {
    const canvasId = `hc-${s.label.replace(/\W/g,'_')}`;
    const ctx = document.getElementById(canvasId)?.getContext('2d');
    if (!ctx) return;

    const key   = d.series.indexOf(s); // Fallback-Index für Farbe
    const color = Object.values(HISTORY_COLORS)[key] ?? '#76b7b2';

    historyCharts[canvasId] = new Chart(ctx, {
      type: 'line',
      data: {
        datasets: [{
          label:            s.label,
          data:             s.points.map(p => ({ x: tsToLocal(p.t), y: p.v })),
          borderColor:      color,
          backgroundColor:  color + '22',
          borderWidth:      2,
          pointRadius:      s.points.length > 200 ? 0 : 2,
          fill:             true,
          tension:          0.3,
        }],
      },
      options: {
        animation:   false,
        responsive:  true,
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: {
              label: ctx => `${ctx.parsed.y.toLocaleString('de-DE', { maximumFractionDigits: 1 })} ${s.unit}`,
              title: ctx => {
                const d = ctx[0].parsed.x;
                return new Date(d).toLocaleString('de-DE', { timeZone: 'Europe/Berlin', day:'2-digit', month:'2-digit', year:'numeric', hour:'2-digit', minute:'2-digit' });
              },
            },
          },
        },
        scales: {
          x: {
            type:   'time',
            time:   {
              displayFormats: {
                hour:  'dd.MM HH:mm',
                day:   'dd.MM',
              },
            },
            ticks:  { color: '#888', maxTicksLimit: 8 },
            grid:   { color: '#2a2a2a' },
          },
          y: {
            ticks: { color: '#888', callback: v => v.toLocaleString('de-DE', { maximumFractionDigits: 1 }) + ' ' + s.unit },
            grid:  { color: '#2a2a2a' },
          },
        },
      },
    });
  });
}

document.getElementById('history-station')?.addEventListener('change', loadHistory);
document.getElementById('history-hours')?.addEventListener('change', loadHistory);

// ---- Loader-Map ----
const loaders = {
  stations:    loadStations,
  metrics:     loadMetrics,
  users:       loadUsers,
  invites:     loadInvites,
  live:        () => { loadStations().then(loadLive); clearInterval(liveTimer); liveTimer = setInterval(loadLive, 30_000); },
  history:     () => loadStations().then(loadHistory),
  credentials: () => {},   // kein Vorladen nötig
  errorlog:    loadErrorLog,
  ota:         loadOta,
};

// ---- Credentials-Formular ----
document.getElementById('cred-form')?.addEventListener('submit', async e => {
  e.preventDefault();
  const f   = e.target;
  const msg = document.getElementById('cred-msg');

  // Client-seitige Validierung
  const ap  = f.admin_pass.value;
  const ap2 = f.admin_pass_confirm.value;
  if (ap && ap !== ap2) {
    msg.innerHTML = '<div class="sws-msg-err">Admin-Passwörter stimmen nicht überein.</div>';
    return;
  }

  const body = { admin_password: f.admin_password.value };
  if (f.api_user.value)   body.api_user   = f.api_user.value;
  if (f.api_pass.value)   body.api_pass   = f.api_pass.value;
  if (ap)                 body.admin_pass = ap;
  if (f.jwt_secret.value) body.jwt_secret = f.jwt_secret.value;

  const btn = document.getElementById('cred-submit');
  btn.disabled = true;
  btn.textContent = 'Speichere…';

  const res = await api('credentials', 'POST', body);
  btn.disabled = false;
  btn.textContent = 'Credentials speichern';

  if (res.success) {
    const changed = (res.rotated ?? []).join(', ');
    msg.innerHTML = `<div class="sws-msg-ok">✅ Gespeichert: ${changed} – ${res.rotated_at}</div>`;
    f.reset();
  } else {
    msg.innerHTML = `<div class="sws-msg-err">❌ ${res.error ?? 'Unbekannter Fehler'}</div>`;
  }
});

// ---- Fehler-Log ----
async function loadErrorLog() {
  const level   = document.getElementById('err-level')?.value   ?? '';
  const station = document.getElementById('err-station')?.value ?? '';
  const params  = new URLSearchParams({ action: 'api/errorlog' });
  if (level)   params.set('level',   level);
  if (station) params.set('station', station);

  const res = await fetch(`index.php?${params}`, { credentials: 'same-origin' });
  const data = await res.json();
  const rows = Array.isArray(data) ? data : (data.rows ?? []);

  const el = document.getElementById('errorlog-table');
  if (!rows.length) { el.innerHTML = '<p class="fg-secondary">Keine Einträge.</p>'; return; }

  const badgeClass = lvl => ({ error:'badge-error', warning:'badge-warning', info:'badge-info' }[lvl] ?? '');
  el.innerHTML = `<table><thead><tr>
    <th>Zeit</th><th>Station</th><th>Level</th><th>Code</th><th>Nachricht</th><th>Kontext</th>
  </tr></thead><tbody>` +
  rows.map(r => `<tr>
    <td class="fg-secondary" style="white-space:nowrap;font-size:.8rem">${r.created_at ?? ''}</td>
    <td>${r.station_slug ?? r.station_id ?? ''}</td>
    <td><span class="badge ${badgeClass(r.level)}">${r.level}</span></td>
    <td style="font-family:monospace;font-size:.82rem">${r.code}</td>
    <td>${r.message}</td>
    <td class="fg-secondary" style="font-size:.78rem">${r.context ? JSON.stringify(r.context) : ''}</td>
  </tr>`).join('') + '</tbody></table>';
}

// Stationen auch in Fehler-Log-Filter laden
async function populateErrStations() {
  const rows = await api('stations');
  const sel  = document.getElementById('err-station');
  if (!sel || !Array.isArray(rows)) return;
  rows.forEach(s => {
    const o = document.createElement('option');
    o.value       = s.slug;
    o.textContent = s.name;
    sel.appendChild(o);
  });
}

// ---- OTA-Verwaltung ----
async function loadOta() {
  const sketches = await api('ota');
  const sel      = document.getElementById('ota-sketch-select');
  const cards    = document.getElementById('ota-cards');

  if (!Array.isArray(sketches) || !sketches.length) {
    cards.innerHTML = '<p class="fg-secondary">Keine Firmware-Ordner gefunden.<br>Ordner unter <code>api/ota/firmware/{sketch-id}/</code> anlegen.</p>';
    sel.innerHTML   = '<option value="">Keine Sketches gefunden</option>';
    return;
  }

  // Karten rendern
  cards.innerHTML = sketches.map(s => {
    const mtime = s.firmware_mtime
      ? new Date(s.firmware_mtime * 1000).toLocaleString('de-DE', { timeZone: 'Europe/Berlin', day:'2-digit', month:'2-digit', year:'numeric', hour:'2-digit', minute:'2-digit' })
      : null;
    const size  = s.firmware_size ? (s.firmware_size / 1024).toFixed(1) + '\u202fKB' : null;
    const hasFw = size !== null;
    return `
    <div class="sws-ota-card">
      <h4><span class="mif-embed2"></span> ${s.sketch}</h4>
      <div class="sws-ota-version">${s.version ?? '–'}</div>
      ${hasFw
        ? `<div class="sws-ota-meta">${size}&nbsp;·&nbsp;${mtime}</div>
           <div class="sws-ota-path">ota/firmware/${s.sketch}/firmware.bin</div>`
        : `<div class="sws-ota-warn">&#x26A0; Noch keine Firmware hochgeladen</div>`}
    </div>`;
  }).join('');

  // Dropdown befüllen
  sel.innerHTML = sketches.map(s =>
    `<option value="${s.sketch}">${s.sketch}</option>`
  ).join('');
}

async function otaUpload(e) {
  e.preventDefault();
  const form = e.target;
  const msg  = document.getElementById('ota-upload-msg');
  const btn  = document.getElementById('ota-submit-btn');

  const sketch  = form.elements.sketch.value;
  const version = form.elements.version.value.trim();
  const file    = form.elements.firmware.files[0];

  btn.disabled  = true;
  msg.textContent = 'Wird hochgeladen…';

  // 1. Firmware hochladen
  const fd = new FormData();
  fd.append('sketch',   sketch);
  fd.append('firmware', file);
  const uploadRes = await fetch('?action=api/ota/upload', {
    method: 'POST',
    headers: { 'X-CSRF-Token': CSRF_TOKEN },
    body: fd,
  }).then(r => r.json());
  if (!uploadRes.ok) {
    msg.textContent = `❌ Upload fehlgeschlagen: ${uploadRes.error}`;
    btn.disabled = false;
    return;
  }

  // 2. Version setzen
  const verRes = await api('ota/version', 'POST', { sketch, version });
  if (!verRes.ok) {
    msg.textContent = `⚠️ Firmware hochgeladen, Version konnte nicht gesetzt werden: ${verRes.error}`;
    btn.disabled = false;
    loadOta();
    return;
  }

  msg.textContent = `✅ ${sketch} v${verRes.version} bereitgestellt (${(uploadRes.size / 1024).toFixed(1)} KB).`;
  btn.disabled = false;
  form.elements.firmware.value = '';
  loadOta();
}

// ---- Generisches Edit-Modal ----
function openEditModal(title, fields, onSave) {
  const modal   = document.getElementById('edit-modal');
  const titleEl = document.getElementById('edit-modal-title');
  const form    = document.getElementById('edit-modal-form');
  const msgEl   = document.getElementById('edit-modal-msg');

  titleEl.textContent = title;
  msgEl.textContent   = '';
  form.innerHTML = fields.map(f => {
    const req = f.required === false ? '' : 'required';
    if (f.type === 'select') {
      const opts = f.options.map(o => `<option value="${o}"${o === f.value ? ' selected' : ''}>${o}</option>`).join('');
      return `<div class="form-group mt-2"><label>${f.label}</label><select name="${f.name}" class="select" ${req}>${opts}</select>${f.hint ? `<span class="remark">${f.hint}</span>` : ''}</div>`;
    }
    return `<div class="form-group mt-2"><label>${f.label}</label>
      <input type="${f.type ?? 'text'}" name="${f.name}" class="metro-input" value="${f.value ?? ''}" ${req}>
      ${f.hint ? `<span class="remark">${f.hint}</span>` : ''}
    </div>`;
  }).join('');

  modal.style.display = '';

  form.onsubmit = async e => {
    e.preventDefault();
    const data = Object.fromEntries(new FormData(form));
    try {
      await onSave(data);
      modal.style.display = 'none';
    } catch (err) {
      msgEl.textContent = err.message;
    }
  };
}

document.getElementById('edit-modal-close')?.addEventListener('click',
  () => { document.getElementById('edit-modal').style.display = 'none'; });

// Migrations-Button Handler
document.getElementById('btn-migrate')?.addEventListener('click', async () => {
  const email = prompt('Admin E-Mail (z.B. admin@example.com):');
  if (!email) return;
  const pass  = prompt('Admin Passwort (mind. 8 Zeichen):');
  if (!pass) return;
  const res = await fetch('?action=api/migrate', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': CSRF_TOKEN },
    body: JSON.stringify({ email, password: pass }),
  }).then(r => r.json());
  alert(res.ok ? '✅ Migration OK:\n' + res.log.join('\n') : '❌ Fehler: ' + res.error);
  if (res.ok) loadUsers();
});

// Start
showSection('stations');
populateErrStations();
