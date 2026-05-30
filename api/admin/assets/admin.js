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
  stations: loadStations,
  metrics:  loadMetrics,
  users:    loadUsers,
  invites:  loadInvites,
  live:     () => { loadStations().then(loadLive); clearInterval(liveTimer); liveTimer = setInterval(loadLive, 30_000); },
};

// Start
showSection('stations');
