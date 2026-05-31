/* ===== SWS Admin Dashboard – JavaScript ===== */
'use strict';

// ---- Navigation ----
const sections = document.querySelectorAll('.section');
const navLinks  = document.querySelectorAll('.nav-link[data-section]');

function showSection(id) {
  sections.forEach(s => s.classList.toggle('hidden', s.id !== id));
  navLinks.forEach(a => a.classList.toggle('active', a.dataset.section === id));
  loaders[id]?.();
}

navLinks.forEach(a => a.addEventListener('click', e => {
  e.preventDefault();
  showSection(a.dataset.section);
}));

// ---- API helper ----
async function api(path, method = 'GET', body = null) {
  const opts = { method, headers: { 'Content-Type': 'application/json' } };
  if (body) opts.body = JSON.stringify(body);
  const r = await fetch(`?action=api/${path}`, opts);
  return r.json();
}

// ---- Tabellen-Helper ----
function renderTable(targetId, columns, rows, actions) {
  const el = document.getElementById(targetId);
  if (!rows.length) { el.innerHTML = '<p style="color:var(--muted)">Keine Einträge.</p>'; return; }
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
  renderTable('stations-table',
    [{key:'id',label:'ID'},{key:'slug',label:'Slug'},{key:'name',label:'Name'},{key:'created_at',label:'Erstellt'}],
    rows,
    [{label:'Löschen', fn:'deleteStation', arg: r => r.id}]
  );
  // Live-Station-Dropdown befüllen
  const sel = document.getElementById('live-station');
  sel.innerHTML = rows.map(r => `<option value="${r.slug}">${r.name}</option>`).join('');
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
  document.getElementById('modal').classList.remove('hidden');
}

function closeModal() { document.getElementById('modal').classList.add('hidden'); }

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
  renderTable('users-table',
    [{key:'id',label:'ID'},{key:'email',label:'E-Mail'},{key:'created_at',label:'Erstellt'}],
    rows,
    [{label:'Löschen', fn:'deleteUser', arg: r => r.id}]
  );
}

async function deleteUser(id) {
  if (!confirm('Benutzer wirklich löschen?')) return;
  await api(`users&id=${id}`, 'DELETE');
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

async function loadLive() {
  const slug = document.getElementById('live-station').value;
  const d = await api(`live&station=${encodeURIComponent(slug)}`);
  const grid = document.getElementById('live-data');
  if (d.error) { grid.innerHTML = `<p style="color:var(--muted)">${d.error}</p>`; return; }
  grid.innerHTML = d.values.map(v =>
    `<div class="live-card">
      <div class="val">${parseFloat(v.value).toLocaleString('de-DE', {maximumFractionDigits:2})}</div>
      <div class="unit">${v.unit ?? ''}</div>
      <div class="lbl">${v.label ?? v.metric_key}</div>
    </div>`
  ).join('');
}

document.getElementById('live-station')?.addEventListener('change', loadLive);

// ---- Loader-Map ----
const loaders = {
  stations:    loadStations,
  metrics:     loadMetrics,
  users:       loadUsers,
  invites:     loadInvites,
  live:        () => { loadStations().then(loadLive); clearInterval(liveTimer); liveTimer = setInterval(loadLive, 30_000); },
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
    msg.innerHTML = '<div class="msg-err">Admin-Passwörter stimmen nicht überein.</div>';
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
    msg.innerHTML = `<div class="msg-ok">✅ Gespeichert: ${changed} – ${res.rotated_at}</div>`;
    f.reset();
  } else {
    msg.innerHTML = `<div class="msg-err">❌ ${res.error ?? 'Unbekannter Fehler'}</div>`;
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
  if (!rows.length) { el.innerHTML = '<p style="color:var(--muted)">Keine Einträge.</p>'; return; }

  const badgeClass = lvl => ({ error:'badge-error', warning:'badge-warning', info:'badge-info' }[lvl] ?? '');
  el.innerHTML = `<table><thead><tr>
    <th>Zeit</th><th>Station</th><th>Level</th><th>Code</th><th>Nachricht</th><th>Kontext</th>
  </tr></thead><tbody>` +
  rows.map(r => `<tr>
    <td style="white-space:nowrap;font-size:.8rem">${r.created_at ?? ''}</td>
    <td>${r.station_slug ?? r.station_id ?? ''}</td>
    <td><span class="badge ${badgeClass(r.level)}">${r.level}</span></td>
    <td style="font-family:monospace;font-size:.82rem">${r.code}</td>
    <td>${r.message}</td>
    <td style="font-size:.78rem;color:var(--muted)">${r.context ? JSON.stringify(r.context) : ''}</td>
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
    cards.innerHTML = '<p style="color:var(--muted)">Keine Firmware-Ordner gefunden.<br>Ordner unter <code>api/ota/firmware/{sketch-id}/</code> anlegen.</p>';
    sel.innerHTML   = '<option value="">Keine Sketches gefunden</option>';
    return;
  }

  // Karten rendern
  cards.innerHTML = `<div class="ota-grid">${sketches.map(s => {
    const mtime = s.firmware_mtime
      ? new Date(s.firmware_mtime * 1000).toLocaleString('de-DE')
      : null;
    const size  = s.firmware_size ? (s.firmware_size / 1024).toFixed(1) + '\u202fKB' : null;
    const hasFw = size !== null;
    return `
    <div class="ota-card">
      <div class="ota-card-title">&#x1F4DF; ${s.sketch}</div>
      <div class="ota-card-version">${s.version ?? '–'}</div>
      <div class="ota-card-meta">
        ${hasFw
          ? `${size} &nbsp;·&nbsp; ${mtime}<br>Pfad: <code>${s.sketch_path}firmware.bin</code>`
          : '<span class="ota-card-no-fw">&#x26A0;&#xFE0F; Noch keine Firmware hochgeladen</span>'}
      </div>
    </div>`;
  }).join('')}</div>`;

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
  const uploadRes = await fetch('?action=api/ota/upload', { method: 'POST', body: fd }).then(r => r.json());
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

// Start
showSection('stations');
populateErrStations();
