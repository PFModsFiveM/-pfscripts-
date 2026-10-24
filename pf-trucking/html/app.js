(() => {
  const $ = (id) => document.getElementById(id);

  const params = new URLSearchParams(window.location.search);
  const embed = params.get('embed') === '1';
  const mock = params.get('mock') === '1';
  const device = String(params.get('device') || 'computer').toLowerCase();
  const theme = params.get('theme');
  if (theme && document.body) document.body.setAttribute('data-theme', theme);

  // Embed-only guard: this UI should only be visible inside pf-computer's iframe.
  if (!embed) {
    document.documentElement.style.background = 'transparent';
    if (document.body) {
      document.body.style.background = 'transparent';
      document.body.innerHTML = '';
    }
    return;
  }

  if (document.body) document.body.style.display = 'block';

  const STATUS_STAGES = [
    'Assigned',
    'En Route to Pickup',
    'Loading',
    'In Transit',
    'Delivering',
    'Completed',
  ];

  const state = {
    online: false,
    lastConnectionError: '',
    page: 'find', // dashboard | find | loads | route | messages | settings

    device,

    profile: {
      name: 'Driver',
      ownsTruck: null, // true | false | null (unknown)
    },

    feeds: {
      contracts: false,
      vehicle: false,
      profile: false,
    },

    contracts: [],
    selectedContractId: null,

    filters: {
      pickup: '',
      within: '',
      trailer: '',
      search: '',
    },

    playerVehicle: {
      name: 'Unknown',
      capacity: 0,
      trailerType: '',
      canTow: true,
    },

    workTruck: null, // { name, plate } | null
    workTruckCfg: {
      enabled: false,
      rentalFee: 0,
    },

    activeJob: null,
    history: [],

    overlay: {
      mode: null, // details | info | loading | delivery | completion
      progress: 0,
      data: null,
    },

    widget: {
      visible: false,
      minimized: false,
    },

    messages: [],
    selectedMessageId: null,

    settings: {
      showWidget: true,
      autoOpenLoadsOnAccept: true,
    },
  };

  function pad2(n) {
    return String(n).padStart(2, '0');
  }

  function updateClock() {
    const d = new Date();
    const hh = pad2(d.getHours());
    const mm = pad2(d.getMinutes());
    const el = $('clock');
    if (el) el.textContent = `${hh}:${mm}`;
  }

  function fmtMoney(n) {
    const v = Number(n || 0);
    return `$${v.toLocaleString()}`;
  }

  function fmtDistance(mi) {
    const v = Number(mi || 0);
    return `${v.toFixed(1)} mi`;
  }

  function setText(id, value) {
    const el = $(id);
    if (el) el.textContent = String(value ?? '—');
  }

  function setTextMany(ids, value) {
    (ids || []).forEach((id) => setText(id, value));
  }

  function escapeHtml(s) {
    return String(s ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  function loadPersisted() {
    try {
      const raw = localStorage.getItem('pf-trucking:history');
      if (raw) state.history = JSON.parse(raw) || [];
    } catch (_) {
      state.history = [];
    }

    try {
      const raw = localStorage.getItem('pf-trucking:messages');
      if (raw) state.messages = JSON.parse(raw) || [];
    } catch (_) {
      state.messages = [];
    }

    try {
      const raw = localStorage.getItem('pf-trucking:settings');
      if (raw) {
        const s = JSON.parse(raw) || {};
        state.settings.showWidget = s.showWidget == null ? state.settings.showWidget : !!s.showWidget;
        state.settings.autoOpenLoadsOnAccept = s.autoOpenLoadsOnAccept == null ? state.settings.autoOpenLoadsOnAccept : !!s.autoOpenLoadsOnAccept;
      }
    } catch (_) {}

    try {
      const raw = localStorage.getItem('pf-trucking:widget');
      if (raw) {
        const w = JSON.parse(raw) || {};
        state.widget.minimized = !!w.minimized;
      }
    } catch (_) {}

    if (!Array.isArray(state.messages)) state.messages = [];
  }

  function saveHistory() {
    try {
      localStorage.setItem('pf-trucking:history', JSON.stringify(state.history.slice(0, 100)));
    } catch (_) {}
  }

  function saveMessages() {
    try {
      localStorage.setItem('pf-trucking:messages', JSON.stringify((state.messages || []).slice(0, 200)));
    } catch (_) {}
  }

  function saveSettings() {
    try {
      localStorage.setItem('pf-trucking:settings', JSON.stringify(state.settings || {}));
    } catch (_) {}
  }

  function saveWidget() {
    try {
      localStorage.setItem('pf-trucking:widget', JSON.stringify({ minimized: state.widget.minimized }));
    } catch (_) {}
  }

  function addMessage({ title, body, type = 'system' }) {
    const msg = {
      id: `m-${Date.now()}-${Math.floor(Math.random() * 10000)}`,
      type,
      title: String(title || 'Message'),
      body: String(body || ''),
      when: Date.now(),
    };
    state.messages = [msg, ...(state.messages || [])].slice(0, 200);
    saveMessages();
  }

  function fmtWhen(ts) {
    const d = new Date(Number(ts || Date.now()));
    const hh = pad2(d.getHours());
    const mm = pad2(d.getMinutes());
    return `${hh}:${mm}`;
  }

  function setOnline(online) {
    state.online = !!online;
    const pill = $('status-pill');
    if (!pill) return;

    if (state.online) {
      pill.textContent = 'Connected';
      pill.classList.add('ok');
      pill.title = 'Connected';
    } else {
      pill.textContent = 'Offline';
      pill.classList.remove('ok');
      pill.title = state.lastConnectionError ? `Offline: ${state.lastConnectionError}` : 'Offline';
    }
  }

  function updateDriverHeader() {
    const name = String(state.profile?.name || 'Driver');
    const el = $('user-name');
    if (el) el.textContent = name;
    const av = $('user-avatar');
    if (av) {
      const parts = name.trim().split(/\s+/).filter(Boolean);
      const initials = (parts[0]?.[0] || 'P') + (parts[1]?.[0] || 'F');
      av.textContent = String(initials).toUpperCase();
    }
  }

  function isTabletLocked() {
    if (state.device !== 'tablet') return false;
    return state.profile.ownsTruck !== true;
  }

  function renderAccessNotice() {
    const bar = $('access-notice');
    if (!bar) return;

    const locked = isTabletLocked();
    bar.classList.toggle('hidden', !locked);

    const nav = $('nav');
    if (nav) {
      nav.querySelectorAll('.nav-item').forEach((b) => {
        const p = b.getAttribute('data-page');
        b.disabled = locked && p !== 'dashboard';
      });
    }

    if (!locked) return;
    setText('access-title', 'Tablet Locked');
    setText('access-sub', 'Tablet access requires an owned truck. Use the depot computer to source a work truck and take contracts.');
    const pill = $('access-pill');
    if (pill) {
      pill.textContent = 'Locked';
      pill.classList.remove('ok');
    }
  }

  function renderDepotCard() {
    const card = $('depot-card');
    if (!card) return;

    const show = state.device === 'computer' && state.profile.ownsTruck === false;
    card.classList.toggle('hidden', !show);
    if (!show) return;

    const hasTruck = !!state.workTruck;
    setText('depot-truck', hasTruck ? (state.workTruck.name || 'Work Truck') : '—');
    setText('depot-plate', hasTruck ? (state.workTruck.plate || '—') : '—');

    const pill = $('depot-pill');
    if (pill) {
      pill.textContent = hasTruck ? 'Assigned' : 'No truck';
      pill.classList.toggle('ok', hasTruck);
    }

    const btnReq = $('btn-worktruck-request');
    const busy = !!state.activeJob;
    if (btnReq) btnReq.disabled = true;

    if (!hasTruck) setText('depot-sub', 'Renting happens when you accept a load');
    else if (busy) setText('depot-sub', 'Work truck assigned for this contract');
    else setText('depot-sub', 'Work truck will be returned after delivery');
  }

  function seedContracts() {
    // UI-only mock data (can be overwritten by NUI messages)
    state.contracts = [
      {
        id: 'LS-1021',
        title: 'Food Freight',
        cargoType: 'Refrigerated goods',
        cargoQuantity: 16,
        pickup: 'Docks (Elysian Island)',
        dropoff: 'Vespucci',
        distanceMi: 6.4,
        payout: 820,
        requiredTrailer: 'Box Trailer',
        stops: [
          { label: 'Stop 1 – Pickup', kind: 'Pickup', location: 'Docks (Elysian Island)' },
          { label: 'Stop 2 – Delivery', kind: 'Delivery', location: 'Vespucci' },
        ],
      },
      {
        id: 'LS-2044',
        title: 'Construction Supply',
        cargoType: 'Cement pallets',
        cargoQuantity: 26,
        pickup: 'Quarry',
        dropoff: 'Downtown',
        distanceMi: 14.2,
        payout: 1650,
        requiredTrailer: 'Flatbed',
        stops: [
          { label: 'Stop 1 – Pickup', kind: 'Pickup', location: 'Quarry' },
          { label: 'Stop 2 – Delivery', kind: 'Delivery', location: 'Downtown' },
        ],
      },
      {
        id: 'LS-3310',
        title: 'Fuel Transfer',
        cargoType: 'Diesel (regulated)',
        cargoQuantity: 30,
        pickup: 'Oil Refinery',
        dropoff: 'Sandy Shores',
        distanceMi: 22.8,
        payout: 2450,
        requiredTrailer: 'Tanker',
        stops: [
          { label: 'Stop 1 – Pickup', kind: 'Pickup', location: 'Oil Refinery' },
          { label: 'Stop 2 – Delivery', kind: 'Delivery', location: 'Sandy Shores' },
        ],
      },
      {
        id: 'LS-4418',
        title: 'Retail Restock',
        cargoType: 'General cargo',
        cargoQuantity: 22,
        pickup: 'Warehouse (La Mesa)',
        dropoff: 'Paleto Bay',
        distanceMi: 33.5,
        payout: 3350,
        requiredTrailer: 'Box Trailer',
        stops: [
          { label: 'Stop 1 – Pickup', kind: 'Pickup', location: 'Warehouse (La Mesa)' },
          { label: 'Stop 2 – Delivery', kind: 'Delivery', location: 'Paleto Bay' },
        ],
      },
      {
        id: 'LS-5092',
        title: 'Medical Logistics',
        cargoType: 'Medical crates',
        cargoQuantity: 10,
        pickup: 'Pillbox Loading',
        dropoff: 'Mount Zonah',
        distanceMi: 9.1,
        payout: 1275,
        requiredTrailer: 'Box Trailer',
        stops: [
          { label: 'Stop 1 – Pickup', kind: 'Pickup', location: 'Pillbox Loading' },
          { label: 'Stop 2 – Delivery', kind: 'Delivery', location: 'Mount Zonah' },
        ],
      },
    ];
  }

  function seedPlayerVehicle() {
    state.playerVehicle = {
      name: 'Mule (Mock)',
      capacity: 24,
      trailerType: 'Box Trailer',
      canTow: true,
    };
  }

  function getNuiResourceName() {
    // Prefer host-derived resource name in iframe/embed contexts.
    // In some environments GetParentResourceName may report the parent app (e.g. pf-computer).
    try {
      const host = (window.location && window.location.host) ? String(window.location.host) : '';
      if (/^cfx-nui-/i.test(host)) {
        const cleaned = host.replace(/^cfx-nui-/i, '').split(':')[0];
        if (cleaned) {
          const lowered = cleaned.toLowerCase();
          if (lowered !== 'nui-frame-app' && lowered !== 'nui-game-internal') return cleaned;
        }
      }
    } catch (_) {}

    try {
      if (typeof GetParentResourceName === 'function') {
        const name = GetParentResourceName();
        if (name && typeof name === 'string') {
          const lowered = name.toLowerCase();
          if (lowered !== 'nui-frame-app' && lowered !== 'nui-game-internal') return name;
        }
      }
    } catch (_) {}

    try {
      const host = (window.location && window.location.host) ? String(window.location.host) : '';
      const cleaned = host.replace(/^cfx-nui-/i, '').split(':')[0];
      if (cleaned) {
        const lowered = cleaned.toLowerCase();
        if (lowered !== 'nui-frame-app' && lowered !== 'nui-game-internal') return cleaned;
      }
    } catch (_) {}

    return 'pf-trucking';
  }

  async function nuiPost(name, payload) {
    const resource = getNuiResourceName();
    const endpoints = [
      `https://${resource}/${name}`,
      `https://cfx-nui-${resource}/${name}`,
    ];

    const xhrPostJson = (url, body) => new Promise((resolve, reject) => {
      try {
        const xhr = new XMLHttpRequest();
        xhr.open('POST', url, true);
        xhr.setRequestHeader('Content-Type', 'application/json; charset=UTF-8');
        xhr.onreadystatechange = () => {
          if (xhr.readyState !== 4) return;
          resolve({ ok: xhr.status >= 200 && xhr.status < 300, status: xhr.status, text: xhr.responseText || '' });
        };
        xhr.onerror = () => reject(new Error('xhr_network_error'));
        xhr.send(JSON.stringify(body || {}));
      } catch (e) {
        reject(e);
      }
    });

    let lastErr = null;
    for (const url of endpoints) {
      try {
        const res = await fetch(url, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json; charset=UTF-8' },
          body: JSON.stringify(payload || {}),
        });
        const text = await res.text();
        if (!res.ok) throw new Error(`http_${res.status}:${text ? text.slice(0, 80) : ''}`);
        if (!text) throw new Error('empty_response');
        return JSON.parse(text);
      } catch (e) {
        try {
          const xr = await xhrPostJson(url, payload || {});
          if (!xr.ok) throw new Error(`http_${xr.status}:${xr.text ? String(xr.text).slice(0, 80) : ''}`);
          if (!xr.text) throw new Error('empty_response');
          return JSON.parse(xr.text);
        } catch (e2) {
          lastErr = e2;
        }
      }
    }

    const message = lastErr && lastErr.message ? lastErr.message : 'nui_request_failed';
    try { console.error('[pf-trucking] NUI request failed:', name, message, window.location && window.location.href); } catch (_) {}
    return { ok: false, error: message };
  }

  async function fetchContracts({ silent = false } = {}) {
    const res = await nuiPost('pf-trucking:getContracts', {});
    if (!res || !res.ok) {
      state.lastConnectionError = (res && res.error) ? String(res.error) : 'request_failed';
      if (!silent && res && res.error) {
        // keep this subtle (no spam), but useful when debugging
        addMessage({ title: 'Connection', body: `Dispatch feed unreachable (${res.error}).`, type: 'system' });
      }
      if (!silent) setOnline(false);
      return false;
    }

    state.lastConnectionError = '';

    if (res.profile) {
      state.profile = {
        name: res.profile.name || state.profile.name,
        ownsTruck: res.profile.ownsTruck === true ? true : (res.profile.ownsTruck === false ? false : state.profile.ownsTruck),
      };
      state.feeds.profile = true;
      updateDriverHeader();
    }

    if (res.workTruck) {
      state.workTruckCfg = {
        enabled: res.workTruck.enabled === true,
        rentalFee: Number(res.workTruck.rentalFee || 0) || 0,
      };
    }

    if (Array.isArray(res.contracts)) {
      state.contracts = res.contracts;
      state.feeds.contracts = true;
      renderFilterOptions();
    }

    if (res.activeJob) {
      // Only adopt server activeJob if UI doesn't already have one.
      if (!state.activeJob) state.activeJob = res.activeJob;
    }

    setOnline(true);
    render();
    return true;
  }

  function fmtStops(stops) {
    const arr = Array.isArray(stops) ? stops : [];
    if (arr.length === 0) return '—';
    if (arr.length === 1) return arr[0].label || '1 stop';
    const labels = arr
      .map((s) => {
        const label = s && s.label ? String(s.label) : '';
        const loc = s && s.location ? String(s.location) : '';
        if (label && loc) return `${label}: ${loc}`;
        return label || loc;
      })
      .filter(Boolean);
    return labels.length ? labels.join(' • ') : `${arr.length} stops`;
  }

  function computeCompatibility(contract) {
    if (!contract) return { compatible: false, reason: 'No load selected' };

    if (isTabletLocked()) return { compatible: false, reason: 'Tablet access locked (requires owned truck)' };
    if (state.device === 'computer' && state.profile.ownsTruck === false && !state.workTruck) {
      const fee = Number(state.workTruckCfg?.rentalFee || 0) || 0;
      const feeText = fee > 0 ? ` (rental fee: ${fmtMoney(fee)})` : '';
      return { compatible: true, reason: `A work truck will be rented for this load${feeText}` };
    }

    const pv = state.playerVehicle || {};
    const requiredTrailer = contract.requiredTrailer || '';
    const cargoQty = Number(contract.cargoQuantity || 0);
    const capacity = Number(pv.capacity || 0);

    if (!pv.name) return { compatible: false, reason: 'No vehicle data' };
    if (state.activeJob) return { compatible: false, reason: 'You already have an active load' };

    if (cargoQty > 0 && capacity > 0 && capacity < cargoQty) {
      return { compatible: false, reason: 'Insufficient capacity' };
    }

    // Trailer requirements are informational at accept time: players often attach the trailer at pickup.
    if (requiredTrailer) {
      if (!pv.canTow) return { compatible: false, reason: 'Vehicle cannot tow a trailer' };
    }

    return { compatible: true, reason: 'Compatible' };
  }

  function buildTracker(currentStatus) {
    const idx = Math.max(0, STATUS_STAGES.indexOf(currentStatus || STATUS_STAGES[0]));
    return `
      <div class="steps">
        ${STATUS_STAGES.map((s, i) => {
          const cls = i < idx ? 'step done' : i === idx ? 'step active' : 'step';
          const label = escapeHtml(s);
          return `<div class="${cls}"><div class="dot"></div><div class="step-label">${label}</div></div>`;
        }).join('')}
      </div>
    `;
  }

  function setPage(page) {
    const locked = isTabletLocked();
    const nextPage = locked && page !== 'dashboard' ? 'dashboard' : page;
    state.page = nextPage;
    const title = $('page-title');

    const nav = $('nav');
    if (nav) {
      nav.querySelectorAll('.nav-item').forEach((btn) => {
        const p = btn.getAttribute('data-page');
        btn.classList.toggle('active', p === nextPage);
      });
    }

    const pages = ['dashboard', 'find', 'loads', 'route', 'messages', 'settings'];
    pages.forEach((p) => {
      const el = $(`page-${p}`);
      if (el) el.classList.toggle('hidden', p !== nextPage);
    });

    const titleMap = {
      dashboard: 'Dashboard',
      find: 'Find Jobs',
      loads: 'My Loads',
      route: 'Route Planner',
      messages: 'Messages',
      settings: 'Settings',
    };
    if (title) title.textContent = titleMap[nextPage] || 'Trucker';

    render();
  }

  function getSelectedContract() {
    return state.contracts.find((x) => x.id === state.selectedContractId) || null;
  }

  function openDetails(contractId) {
    state.selectedContractId = contractId;
    setOverlay('details', { contractId });
  }

  function getFilteredContracts() {
    const f = state.filters;
    const pickup = String(f.pickup || '');
    const trailer = String(f.trailer || '');
    const within = f.within ? Number(f.within) : null;
    const search = String(f.search || '').trim().toLowerCase();

    return (state.contracts || []).filter((c) => {
      if (pickup && c.pickup !== pickup) return false;
      if (trailer && c.requiredTrailer !== trailer) return false;
      if (within != null && Number(c.distanceMi || 0) > within) return false;

      if (search) {
        const hay = `${c.id} ${c.title} ${c.pickup} ${c.dropoff} ${c.cargoType} ${c.requiredTrailer}`.toLowerCase();
        if (!hay.includes(search)) return false;
      }

      return true;
    });
  }

  function renderFilterOptions() {
    const pickupSel = $('f-pickup');
    const trailerSel = $('f-trailer');
    if (pickupSel) {
      const pickups = Array.from(new Set(state.contracts.map((c) => c.pickup).filter(Boolean))).sort();
      pickupSel.innerHTML = `<option value="">Any</option>` + pickups.map((x) => `<option value="${escapeHtml(x)}">${escapeHtml(x)}</option>`).join('');
      pickupSel.value = state.filters.pickup;
    }
    if (trailerSel) {
      const trailers = Array.from(new Set(state.contracts.map((c) => c.requiredTrailer).filter(Boolean))).sort();
      trailerSel.innerHTML = `<option value="">Any</option>` + trailers.map((x) => `<option value="${escapeHtml(x)}">${escapeHtml(x)}</option>`).join('');
      trailerSel.value = state.filters.trailer;
    }
  }

  function renderContractList() {
    const list = $('contract-list');
    const sub = $('results-sub');
    if (!list) return;

    const contracts = getFilteredContracts();
    if (sub) {
      if (!state.contracts.length && !state.feeds.contracts) sub.textContent = 'Awaiting dispatch feed';
      else sub.textContent = contracts.length ? `Showing ${contracts.length} loads` : 'No loads match your filters';
    }

    list.innerHTML = '';
    if (!contracts.length) {
      const div = document.createElement('div');
      div.className = 'empty';
      if (!state.contracts.length && !state.feeds.contracts) {
        div.innerHTML = `<div class="empty-title">No job feed yet</div><div class="empty-sub">Jobs come from the server. If you're offline, press Refresh or check that the resource is started.</div>`;
      } else {
        div.innerHTML = `<div class="empty-title">No loads found</div><div class="empty-sub">Try adjusting filters or refresh.</div>`;
      }
      list.appendChild(div);
      return;
    }

    contracts.forEach((c) => {
      const div = document.createElement('div');
      div.className = 'load';
      div.innerHTML = `
        <div class="load-main">
          <div class="load-route">${escapeHtml(c.pickup)} → ${escapeHtml(c.dropoff)}</div>
          <div class="load-sub">${escapeHtml(c.id)} • ${escapeHtml(c.title)}</div>
          <div class="load-meta">${escapeHtml(c.cargoType)} • ${escapeHtml(c.requiredTrailer || 'No trailer')} • ${escapeHtml(fmtDistance(c.distanceMi))}</div>
        </div>
        <div class="load-side">
          <div class="load-pay">${escapeHtml(fmtMoney(c.payout))}</div>
          <button class="btn" type="button" data-action="details" data-id="${escapeHtml(c.id)}">Load Details</button>
        </div>
      `;
      list.appendChild(div);
    });
  }

  function renderActive() {
    const sub = $('active-sub');
    const empty = $('active-empty');
    const grid = $('active-grid');
    const tracker = $('status-tracker');
    const btnGps = $('btn-setgps');
    const btnCancel = $('btn-cancel');

    const j = state.activeJob;
    if (!j) {
      if (sub) sub.textContent = 'No active contract';
      if (empty) empty.classList.remove('hidden');
      if (grid) grid.classList.add('hidden');
      if (tracker) tracker.classList.add('hidden');
      if (btnGps) btnGps.disabled = true;
      if (btnCancel) btnCancel.disabled = true;
      return;
    }

    if (sub) sub.textContent = `${j.id} • ${j.title}`;
    if (empty) empty.classList.add('hidden');
    if (grid) grid.classList.remove('hidden');
    if (tracker) tracker.classList.remove('hidden');
    if (btnGps) btnGps.disabled = false;
    if (btnCancel) btnCancel.disabled = false;

    setText('a-id', j.id);
    setText('a-cargo', `${j.cargoType} • Qty ${j.cargoQuantity}`);
    setText('a-pickup', j.pickup);
    setText('a-dropoff', j.dropoff);
    setText('a-distance', fmtDistance(j.distanceRemainingMi));
    setText('a-payout', fmtMoney(j.estimatedPayout));
    setText('a-trailer', j.requiredTrailer || 'None');
    setText('a-stops', fmtStops(j.stops));
    setText('a-status', j.status);

    if (tracker) tracker.innerHTML = buildTracker(j.status);
  }

  function renderHistory() {
    const list = $('history-list');
    if (!list) return;
    list.innerHTML = '';

    if (!state.history.length) {
      const div = document.createElement('div');
      div.className = 'empty';
      div.innerHTML = `<div class="empty-title">No history yet</div><div class="empty-sub">Complete (or cancel) a job to add it here.</div>`;
      list.appendChild(div);
      return;
    }

    state.history.forEach((h) => {
      const div = document.createElement('div');
      div.className = 'load';
      div.innerHTML = `
        <div class="load-main">
          <div class="load-route">${escapeHtml(h.pickup)} → ${escapeHtml(h.dropoff)}</div>
          <div class="load-sub">${escapeHtml(h.id)} • ${escapeHtml(h.title)}</div>
          <div class="load-meta">${escapeHtml(h.status || '—')} • ${escapeHtml(h.requiredTrailer || 'No trailer')} • ${escapeHtml(fmtDistance(h.distanceMi || 0))}</div>
        </div>
        <div class="load-side">
          <div class="load-pay">${escapeHtml(fmtMoney(h.finalPayout || 0))}</div>
        </div>
      `;
      list.appendChild(div);
    });
  }

  function updateWidget() {
    const widget = $('widget');
    const body = $('widget-body');
    if (!widget || !body) return;

    if (!state.settings.showWidget) {
      widget.classList.add('hidden');
      return;
    }

    const j = state.activeJob;
    const shouldShow = !!j && (j.status === 'In Transit' || j.status === 'Delivering');
    state.widget.visible = shouldShow;
    widget.classList.toggle('hidden', !shouldShow);

    if (!shouldShow) return;

    const minimized = !!state.widget.minimized;
    body.classList.toggle('hidden', minimized);
    const btn = $('widget-toggle');
    if (btn) btn.textContent = minimized ? '+' : '—';

    setText('w-dest', j.dropoff);
    setText('w-distance', fmtDistance(j.distanceRemainingMi));
    setText('w-eta', j.eta || '—');
    setText('w-cargo', j.cargoStatus || '—');
    setText('w-payout', fmtMoney(j.currentPayout || j.estimatedPayout));

    const bar = $('w-bar');
    if (bar) {
      const total = Number(j.totalDistanceMi || 0) || Number(j.distanceRemainingMi || 0) || 1;
      const remaining = Number(j.distanceRemainingMi || 0);
      const pct = Math.max(0, Math.min(100, ((total - remaining) / total) * 100));
      bar.style.width = `${pct.toFixed(0)}%`;
    }
  }

  function setOverlay(mode, data) {
    state.overlay.mode = mode;
    state.overlay.data = data || null;
    if (data && typeof data.progress === 'number') state.overlay.progress = data.progress;
    renderOverlay();
  }

  function hideOverlay() {
    state.overlay.mode = null;
    state.overlay.data = null;
    state.overlay.progress = 0;
    renderOverlay();
  }

  function renderOverlay() {
    const overlay = $('overlay');
    if (!overlay) return;
    const title = $('overlay-title');
    const sub = $('overlay-sub');
    const grid = $('overlay-grid');
    const actions = $('overlay-actions');
    const barWrap = $('overlay-bar');
    const barFill = $('overlay-bar-fill');

    const mode = state.overlay.mode;
    overlay.classList.toggle('hidden', !mode);
    if (!mode) return;

    const mkKV = (k, v) => `
      <div class="kv"><div class="k">${escapeHtml(k)}</div><div class="v">${escapeHtml(v)}</div></div>
    `;

    if (mode === 'info') {
      if (title) title.textContent = state.overlay.data?.title || 'Info';
      if (sub) sub.textContent = state.overlay.data?.message || '';
      if (grid) grid.innerHTML = '';
      if (barWrap) barWrap.classList.add('hidden');
      if (actions) {
        actions.innerHTML = `<button class="btn btn-primary" id="ol-close" type="button">Close</button>`;
        const close = $('ol-close');
        if (close) close.onclick = () => hideOverlay();
      }
      return;
    }

    if (mode === 'confirm') {
      if (title) title.textContent = state.overlay.data?.title || 'Confirm';
      if (sub) sub.textContent = state.overlay.data?.message || '';
      if (grid) grid.innerHTML = '';
      if (barWrap) barWrap.classList.add('hidden');
      if (actions) {
        actions.innerHTML = `
          <button class="btn" id="ol-cancel" type="button">Cancel</button>
          <button class="btn btn-primary" id="ol-confirm" type="button">Confirm</button>
        `;
        const cancel = $('ol-cancel');
        const confirm = $('ol-confirm');
        if (cancel) cancel.onclick = () => {
          try { state.overlay.data?.onCancel?.(); } catch (_) {}
          hideOverlay();
        };
        if (confirm) confirm.onclick = async () => {
          if (confirm) confirm.disabled = true;
          if (cancel) cancel.disabled = true;
          if (confirm) confirm.textContent = 'Working…';
          try {
            await Promise.resolve(state.overlay.data?.onConfirm?.());
          } catch (e) {
            setOverlay('info', { title: 'Error', message: String(e && e.message ? e.message : e) });
          }
        };
      }
      return;
    }

    if (mode === 'details') {
      const c = getSelectedContract();
      if (!c) {
        if (title) title.textContent = 'Load Details';
        if (sub) sub.textContent = 'No load selected';
        if (grid) grid.innerHTML = '';
        if (barWrap) barWrap.classList.add('hidden');
        if (actions) {
          actions.innerHTML = `<button class="btn btn-primary" id="ol-close" type="button">Close</button>`;
          const close = $('ol-close');
          if (close) close.onclick = () => hideOverlay();
        }
        return;
      }

      const comp = computeCompatibility(c);
      if (title) title.textContent = `${c.id} • ${c.title}`;
      if (sub) sub.textContent = comp.reason;
      if (grid) {
        grid.innerHTML =
          mkKV('Pickup', c.pickup) +
          mkKV('Dropoff', c.dropoff) +
          mkKV('Distance', fmtDistance(c.distanceMi)) +
          mkKV('Payout', fmtMoney(c.payout)) +
          mkKV('Cargo', `${c.cargoType} • Qty ${c.cargoQuantity}`) +
          mkKV('Trailer', c.requiredTrailer || 'None') +
          mkKV('Stops', fmtStops(c.stops));
      }
      if (barWrap) barWrap.classList.add('hidden');
      if (actions) {
        const acceptDisabled = !comp.compatible;
        actions.innerHTML = `
          <button class="btn" id="ol-close" type="button">Close</button>
          <button class="btn btn-primary" id="ol-accept" type="button" ${acceptDisabled ? 'disabled' : ''}>Accept Load</button>
        `;
        const close = $('ol-close');
        const accept = $('ol-accept');
        if (close) close.onclick = () => hideOverlay();
        if (accept) accept.onclick = () => acceptContract();
      }
      return;
    }

    // Remaining overlay modes are tied to an active job.
    const j = state.activeJob;
    if (!j) {
      if (title) title.textContent = 'No active job';
      if (sub) sub.textContent = '';
      if (grid) grid.innerHTML = '';
      if (actions) actions.innerHTML = `<button class="btn btn-primary" id="ol-close" type="button">Close</button>`;
      if (barWrap) barWrap.classList.add('hidden');
      const close = $('ol-close');
      if (close) close.onclick = () => hideOverlay();
      return;
    }

    if (mode === 'loading') {
      if (title) title.textContent = 'Loading Cargo';
      if (sub) sub.textContent = `Pickup: ${j.pickup}`;
      if (grid) {
        grid.innerHTML =
          mkKV('Pickup location', j.pickup) +
          mkKV('Cargo type', j.cargoType) +
          mkKV('Cargo quantity', String(j.cargoQuantity)) +
          mkKV('Required trailer', j.requiredTrailer || 'None');
      }
      if (barWrap) barWrap.classList.remove('hidden');
      if (barFill) barFill.style.width = `${Math.max(0, Math.min(100, state.overlay.progress))}%`;
      if (actions) {
        actions.innerHTML = `
          <button class="btn btn-primary" id="ol-start" type="button">Start Loading</button>
          <button class="btn btn-danger" id="ol-cancel" type="button">Cancel Contract</button>
        `;
        const start = $('ol-start');
        const cancel = $('ol-cancel');
        if (start) start.onclick = () => startLoading();
        if (cancel) cancel.onclick = () => cancelJob();
      }
      return;
    }

    if (mode === 'delivery') {
      if (title) title.textContent = 'Delivery';
      if (sub) sub.textContent = `Dropoff: ${j.dropoff}`;
      if (grid) {
        grid.innerHTML =
          mkKV('Dropoff location', j.dropoff) +
          mkKV('Cargo summary', `${j.cargoType} • Qty ${j.cargoQuantity}`) +
          mkKV('Delivery status', j.status) +
          mkKV('Bonus indicators', j.bonusSummary || '—') +
          mkKV('Base pay', fmtMoney(j.payBreakdown?.base || j.estimatedPayout)) +
          mkKV('Distance bonus', fmtMoney(j.payBreakdown?.distanceBonus || 0)) +
          mkKV('Time bonus', fmtMoney(j.payBreakdown?.timeBonus || 0)) +
          mkKV('Damage penalty', fmtMoney(j.payBreakdown?.damagePenalty || 0));
      }
      if (barWrap) barWrap.classList.add('hidden');
      if (actions) {
        actions.innerHTML = `
          <button class="btn btn-primary" id="ol-deliver" type="button">Deliver Cargo</button>
          <button class="btn btn-danger" id="ol-cancel" type="button">Cancel Contract</button>
        `;
        const deliver = $('ol-deliver');
        const cancel = $('ol-cancel');
        if (deliver) deliver.onclick = () => deliverCargo();
        if (cancel) cancel.onclick = () => cancelJob();
      }
      return;
    }

    if (mode === 'completion') {
      if (title) title.textContent = 'Job Complete';
      if (sub) sub.textContent = 'Completion Summary';
      if (grid) {
        const payout = fmtMoney(j.finalPayout || j.currentPayout || j.estimatedPayout);
        grid.innerHTML =
          mkKV('Final payout', payout) +
          mkKV('Contract ID', j.id) +
          mkKV('Route', `${j.pickup} → ${j.dropoff}`) +
          mkKV('Distance traveled', fmtDistance(j.distanceTraveledMi || j.totalDistanceMi || 0)) +
          mkKV('Time taken', j.timeTaken || '—') +
          mkKV('Bonuses', j.bonusSummary || '—') +
          mkKV('Status', j.status);
      }
      if (barWrap) barWrap.classList.add('hidden');
      if (actions) {
        actions.innerHTML = `<button class="btn btn-primary" id="ol-close" type="button">Close</button>`;
        const close = $('ol-close');
        if (close) close.onclick = () => {
          hideOverlay();
          setPage('loads');
        };
      }
      return;
    }
  }

  function syncOverlayToJobStatus() {
    const mode = state.overlay.mode;
    if (mode === 'details' || mode === 'info') return;

    const j = state.activeJob;
    if (!j) {
      if (mode) hideOverlay();
      return;
    }

    if (j.status === 'Loading') {
      if (mode !== 'loading') setOverlay('loading', { progress: state.overlay.progress || 0 });
      return;
    }

    if (j.status === 'Delivering') {
      if (mode !== 'delivery') setOverlay('delivery', {});
      return;
    }

    if (j.status === 'Completed') {
      if (mode !== 'completion') setOverlay('completion', {});
      return;
    }

    if (mode) hideOverlay();
  }

  function acceptContract() {
    const c = getSelectedContract();
    if (!c) return;
    const comp = computeCompatibility(c);
    if (!comp.compatible) return;

    const needsRental = state.device === 'computer' && state.profile.ownsTruck === false && !state.workTruck;

    const claim = async () => {
      const res = await nuiPost('pf-trucking:acceptContract', { contract: c });
      if (!res || !res.ok) {
        setOverlay('info', { title: 'Unable to accept', message: res?.error || 'Contract could not be claimed.' });
        return;
      }

      if (Array.isArray(res.contracts)) {
        state.contracts = res.contracts;
        state.feeds.contracts = true;
        renderFilterOptions();
      }

      const job = res.job || c;
      const payoutNet = Number(job.payoutNet ?? job.payout ?? c.payout ?? 0) || 0;
      const payoutGross = Number(job.payoutGross ?? c.payout ?? payoutNet) || 0;
      const rentalFee = Number(job.rentalFee ?? 0) || 0;

      state.activeJob = {
        id: job.id,
        title: job.title,
        cargoType: job.cargoType,
        cargoQuantity: job.cargoQuantity,
        cargoStatus: 'Secured',
        pickup: job.pickup,
        dropoff: job.dropoff,
        totalDistanceMi: job.distanceMi,
        distanceRemainingMi: job.distanceMi,
        estimatedPayout: payoutNet,
        currentPayout: payoutNet,
        requiredTrailer: job.requiredTrailer,
        status: 'Assigned',
        stops: job.stops,
        eta: '—',
        payoutGross,
        rentalFee,
        payBreakdown: { base: payoutNet, distanceBonus: 0, timeBonus: 0, damagePenalty: 0 },
        bonusSummary: rentalFee > 0 ? `Includes rental fee (-${fmtMoney(rentalFee)})` : '—',
      };

      const feeLine = rentalFee > 0 ? `\nRental fee: -${fmtMoney(rentalFee)}` : '';
      addMessage({
        title: 'Load accepted',
        body: `${job.id} • ${job.title}\n${job.pickup} → ${job.dropoff}\nPayout: ${fmtMoney(payoutNet)}${feeLine}`,
        type: 'job',
      });

      hideOverlay();
      if (state.settings.autoOpenLoadsOnAccept) setPage('loads');
      else render();
    };

    if (needsRental) {
      const fee = Number(state.workTruckCfg?.rentalFee || 0) || 0;
      const feeText = fee > 0 ? `This will deduct ${fmtMoney(fee)} from the contract payout.` : 'The contract payout will be adjusted.';
      setOverlay('confirm', {
        title: 'Rent Work Truck',
        message: `You don't own a truck. Rent a work truck for this load? ${feeText}`,
        onConfirm: async () => {
          const res = await Promise.race([
            nuiPost('pf-trucking:requestWorkTruck', {}),
            new Promise((resolve) => setTimeout(() => resolve({ ok: false, error: 'request_timeout' }), 12000)),
          ]);
          if (!res || !res.ok) {
            setOverlay('info', { title: 'Depot', message: res?.error || 'Unable to issue a work truck.' });
            return;
          }
          await claim();
        },
        onCancel: () => {},
      });
      return;
    }

    (async () => {
      await claim();
    })();

    return;
  }

  function setGps() {
    const j = state.activeJob;
    if (!j) return;
    nuiPost('pf-trucking:setGps', { job: j });
  }

  function cancelJob() {
    const j = state.activeJob;
    if (!j) return;

    (async () => {
      const res = await nuiPost('pf-trucking:cancelJob', { job: j });
      if (!res || !res.ok) {
        setOverlay('info', { title: 'Unable to cancel', message: res?.error || 'Cancel failed.' });
        return;
      }
      if (Array.isArray(res.contracts)) {
        state.contracts = res.contracts;
        state.feeds.contracts = true;
        renderFilterOptions();
      }

      state.history.unshift({
        id: j.id,
        title: j.title,
        cargoType: j.cargoType,
        cargoQuantity: j.cargoQuantity,
        pickup: j.pickup,
        dropoff: j.dropoff,
        distanceMi: j.totalDistanceMi,
        requiredTrailer: j.requiredTrailer,
        finalPayout: 0,
        status: 'Canceled',
        rating: 'Canceled',
        stops: j.stops,
        when: Date.now(),
      });
      saveHistory();

      addMessage({ title: 'Load canceled', body: `${j.id} • ${j.title}\n${j.pickup} → ${j.dropoff}`, type: 'job' });
      state.activeJob = null;
      hideOverlay();
      setPage('loads');
    })();

    return;

  }

  let loadingTimer = null;
  function startLoading() {
    const j = state.activeJob;
    if (!j) return;
    nuiPost('pf-trucking:startLoading', { job: j });

    if (loadingTimer) clearInterval(loadingTimer);
    state.overlay.progress = 0;
    setOverlay('loading', { progress: 0 });

    loadingTimer = setInterval(() => {
      state.overlay.progress = Math.min(100, (state.overlay.progress || 0) + 4);
      setOverlay('loading', { progress: state.overlay.progress });
      if (state.overlay.progress >= 100) {
        clearInterval(loadingTimer);
        loadingTimer = null;
        if (state.activeJob) state.activeJob.status = 'In Transit';
        hideOverlay();
        render();
      }
    }, 200);
  }

  function deliverCargo() {
    const j = state.activeJob;
    if (!j) return;

    (async () => {
      const res = await nuiPost('pf-trucking:deliverCargo', { job: j });
      if (!res || !res.ok) {
        setOverlay('info', { title: 'Unable to complete', message: res?.error || 'Completion failed.' });
        return;
      }
      if (Array.isArray(res.contracts)) {
        state.contracts = res.contracts;
        state.feeds.contracts = true;
        renderFilterOptions();
      }

      const final = Number(res.finalPayout ?? j.finalPayout ?? j.currentPayout ?? j.estimatedPayout ?? 0);
      state.activeJob.status = 'Completed';
      state.activeJob.finalPayout = final;

      state.history.unshift({
        id: j.id,
        title: j.title,
        cargoType: j.cargoType,
        cargoQuantity: j.cargoQuantity,
        pickup: j.pickup,
        dropoff: j.dropoff,
        distanceMi: j.totalDistanceMi,
        requiredTrailer: j.requiredTrailer,
        finalPayout: final,
        status: 'Completed',
        rating: 'Completed',
        stops: j.stops,
        when: Date.now(),
      });
      saveHistory();

      addMessage({
        title: 'Load completed',
        body: `${j.id} • ${j.title}\nFinal payout: ${fmtMoney(final)}`,
        type: 'job',
      });

      setOverlay('completion', {});
      render();
    })();
  }

  function estimateHoursFromHistory() {
    const completed = (state.history || []).filter((h) => h.status === 'Completed');
    const miles = completed.reduce((sum, h) => sum + Number(h.distanceMi || 0), 0);
    // Simple estimate at 35 mph; keeps it deterministic without inventing per-job times.
    return miles > 0 ? miles / 35 : 0;
  }

  function setPillState(el, { text, tone }) {
    if (!el) return;
    el.textContent = String(text ?? '—');
    el.classList.toggle('ok', tone === 'ok');
    el.classList.toggle('bad', tone === 'bad');
  }

  function renderSystemStatus() {
    if (isTabletLocked()) setText('sys-sub', 'Tablet access locked');
    else setText('sys-sub', state.feeds.contracts || state.feeds.vehicle || state.feeds.profile || state.activeJob ? 'Live data available' : 'Awaiting data');

    const profilePill = $('sys-profile-pill');
    if (state.profile.ownsTruck === true) {
      setText('sys-profile-sub', state.feeds.profile ? 'Owner operator' : 'Owner operator (unconfirmed)');
      setPillState(profilePill, { text: 'Owner', tone: 'ok' });
    } else if (state.profile.ownsTruck === false) {
      setText('sys-profile-sub', 'Contract driver (depot required)');
      setPillState(profilePill, { text: 'Contract', tone: null });
    } else {
      setText('sys-profile-sub', 'Profile not loaded');
      setPillState(profilePill, { text: 'Unknown', tone: null });
    }

    const dispatchPill = $('sys-dispatch-pill');
    const vehiclePill = $('sys-vehicle-pill');
    const jobPill = $('sys-job-pill');

    setText('sys-dispatch-sub', state.contracts.length ? `${state.contracts.length} load(s) received` : 'No loads received');
    setPillState(dispatchPill, {
      text: state.feeds.contracts ? 'Connected' : 'No data',
      tone: state.feeds.contracts ? 'ok' : null,
    });

    setText('sys-vehicle-sub', state.feeds.vehicle ? (state.playerVehicle.name || 'Vehicle linked') : 'No vehicle data');
    setPillState(vehiclePill, {
      text: state.feeds.vehicle ? 'Linked' : 'No data',
      tone: state.feeds.vehicle ? 'ok' : null,
    });

    setText('sys-job-sub', state.activeJob ? `${state.activeJob.id} • ${state.activeJob.status || 'Active'}` : 'No active job');
    setPillState(jobPill, {
      text: state.activeJob ? 'Active' : 'Idle',
      tone: state.activeJob ? 'ok' : null,
    });
  }

  function renderDashboard() {
    renderSystemStatus();

    // Active load summary
    const dashSub = $('dash-active-sub');
    const dashEmpty = $('dash-active-empty');
    const dashGrid = $('dash-active-grid');
    const dashTracker = $('dash-tracker');
    const dashBtnRoute = $('dash-btn-route');

    const j = state.activeJob;
    if (!j) {
      if (dashSub) dashSub.textContent = 'No active load';
      if (dashEmpty) dashEmpty.classList.remove('hidden');
      if (dashGrid) dashGrid.classList.add('hidden');
      if (dashTracker) dashTracker.classList.add('hidden');
      if (dashBtnRoute) dashBtnRoute.disabled = true;
    } else {
      if (dashSub) dashSub.textContent = `${j.id} • ${j.title}`;
      if (dashEmpty) dashEmpty.classList.add('hidden');
      if (dashGrid) dashGrid.classList.remove('hidden');
      if (dashTracker) dashTracker.classList.remove('hidden');
      if (dashBtnRoute) dashBtnRoute.disabled = false;

      setText('da-id', `${j.id} • ${j.title}`);
      setText('da-route', `${j.pickup} → ${j.dropoff}`);
      setText('da-status', j.status || '—');
      setText('da-distance', fmtDistance(j.distanceRemainingMi || 0));
      if (dashTracker) dashTracker.innerHTML = buildTracker(j.status);
    }

    // Recommended loads (uses current filters)
    const recList = $('dash-loads-list');
    const recSub = $('dash-loads-sub');
    if (recList) {
      const contracts = getFilteredContracts().slice(0, 5);
      if (recSub) {
        if (!state.contracts.length && !state.feeds.contracts) recSub.textContent = 'Waiting for dispatch feed';
        else recSub.textContent = contracts.length ? `Showing ${contracts.length} load(s)` : 'No loads match your filters';
      }

      recList.innerHTML = '';
      if (!contracts.length) {
        const div = document.createElement('div');
        div.className = 'empty';
        if (!state.contracts.length && !state.feeds.contracts) {
          div.innerHTML = `<div class="empty-title">No dispatch data yet</div><div class="empty-sub">When contracts are pushed from your dispatch script, recommendations will show up here.</div>`;
        } else {
          div.innerHTML = `<div class="empty-title">No recommendations</div><div class="empty-sub">Adjust filters in Find Jobs, then come back.</div>`;
        }
        recList.appendChild(div);
      } else {
        contracts.forEach((c) => {
          const div = document.createElement('div');
          div.className = 'load';
          div.innerHTML = `
            <div class="load-main">
              <div class="load-route">${escapeHtml(c.pickup)} → ${escapeHtml(c.dropoff)}</div>
              <div class="load-sub">${escapeHtml(c.id)} • ${escapeHtml(c.title)}</div>
              <div class="load-meta">${escapeHtml(c.cargoType)} • ${escapeHtml(c.requiredTrailer || 'No trailer')} • ${escapeHtml(fmtDistance(c.distanceMi))}</div>
            </div>
            <div class="load-side">
              <div class="load-pay">${escapeHtml(fmtMoney(c.payout))}</div>
              <button class="btn" type="button" data-action="details" data-id="${escapeHtml(c.id)}">Details</button>
            </div>
          `;
          recList.appendChild(div);
        });
      }
    }

    const list = $('activity-list');
    if (list) {
      const events = [];
      (state.messages || []).slice(0, 5).forEach((m) => {
        events.push({ when: m.when, title: m.title, sub: fmtWhen(m.when) });
      });
      (state.history || []).slice(0, 5).forEach((h) => {
        events.push({ when: h.when || Date.now(), title: `${h.status}: ${h.id}`, sub: `${h.pickup} → ${h.dropoff}` });
      });
      events.sort((a, b) => Number(b.when) - Number(a.when));

      list.innerHTML = '';
      if (!events.length) {
        list.innerHTML = `<div class="activity-item"><div class="activity-title">No activity yet</div><div class="activity-sub">Accept a load to start tracking.</div></div>`;
      } else {
        events.slice(0, 8).forEach((e) => {
          const div = document.createElement('div');
          div.className = 'activity-item';
          div.innerHTML = `<div class="activity-title">${escapeHtml(e.title)}</div><div class="activity-sub">${escapeHtml(e.sub)}</div>`;
          list.appendChild(div);
        });
      }
    }

    const hours = estimateHoursFromHistory();
    setTextMany(['m-hours', 'm-hours-2'], hours ? hours.toFixed(1) : '0');
    setTextMany(['m-mpg', 'm-mpg-2'], '—');
    const completed = (state.history || []).filter((h) => h.status === 'Completed').length;
    setTextMany(['m-ontime', 'm-ontime-2'], completed ? '100%' : '0%');

    renderCharts();
  }

  function renderCharts() {
    const completed = (state.history || []).filter((h) => h.status === 'Completed');
    const points = completed
      .slice(0, 10)
      .map((h) => Number(h.finalPayout || 0))
      .reverse();

    const makePath = (vals) => {
      const w = 300;
      const h = 120;
      if (!vals.length) {
        return { line: '', area: '' };
      }
      const min = Math.min(...vals);
      const max = Math.max(...vals);
      const span = Math.max(1, max - min);
      const stepX = vals.length === 1 ? 0 : w / (vals.length - 1);
      const pts = vals.map((v, i) => {
        const x = i * stepX;
        const y = h - ((v - min) / span) * (h - 10) - 5;
        return { x, y };
      });
      const line = `M ${pts.map((p) => `${p.x.toFixed(2)} ${p.y.toFixed(2)}`).join(' L ')}`;
      const area = `${line} L ${w} ${h} L 0 ${h} Z`;
      return { line, area };
    };

    const paths = makePath(points);
    const ids = [
      { line: 'chart-line', area: 'chart-area' },
      { line: 'chart-line-2', area: 'chart-area-2' },
    ];
    ids.forEach((x) => {
      const lineEl = $(x.line);
      const areaEl = $(x.area);
      if (lineEl) lineEl.setAttribute('d', paths.line);
      if (areaEl) areaEl.setAttribute('d', paths.area);
    });
  }

  function renderRoutePlanner() {
    const j = state.activeJob;
    const sub = $('route-sub');
    const empty = $('route-empty');
    const grid = $('route-grid');
    const stopsList = $('stops-list');
    const stopsSub = $('stops-sub');
    const btnGps = $('btn-route-gps');

    if (stopsList) stopsList.innerHTML = '';

    if (!j) {
      if (sub) sub.textContent = 'No active load';
      if (empty) empty.classList.remove('hidden');
      if (grid) grid.classList.add('hidden');
      if (stopsSub) stopsSub.textContent = '—';
      if (btnGps) btnGps.disabled = true;
      if (stopsList) {
        const div = document.createElement('div');
        div.className = 'empty';
        div.innerHTML = `<div class="empty-title">No stops</div><div class="empty-sub">Accept a load to view stops.</div>`;
        stopsList.appendChild(div);
      }
      return;
    }

    if (sub) sub.textContent = `${j.id} • ${j.title}`;
    if (empty) empty.classList.add('hidden');
    if (grid) grid.classList.remove('hidden');

    setText('r-id', j.id);
    setText('r-pickup', j.pickup);
    setText('r-dropoff', j.dropoff);
    setText('r-stops', fmtStops(j.stops));
    setText('r-distance', fmtDistance(j.totalDistanceMi || 0));
    setText('r-payout', fmtMoney(j.estimatedPayout || 0));

    const stops = Array.isArray(j.stops) ? j.stops : [];
    if (stopsSub) stopsSub.textContent = stops.length ? `${stops.length} stop(s)` : 'No stops';

    const nextStopIndex = (() => {
      if (!stops.length) return null;
      if (j.status === 'In Transit' || j.status === 'Delivering' || j.status === 'Completed') return Math.min(1, stops.length - 1);
      return 0;
    })();

    if (btnGps) {
      btnGps.disabled = nextStopIndex == null;
      btnGps.onclick = () => {
        if (nextStopIndex == null) return;
        nuiPost('pf-trucking:setGps', { job: j, stopIndex: nextStopIndex });
      };
    }

    if (stopsList) {
      if (!stops.length) {
        const div = document.createElement('div');
        div.className = 'empty';
        div.innerHTML = `<div class="empty-title">Stops unavailable</div><div class="empty-sub">This load does not define stops.</div>`;
        stopsList.appendChild(div);
      } else {
        stops.forEach((s, idx) => {
          const div = document.createElement('div');
          div.className = 'load';
          const label = s.label || `Stop ${idx + 1}`;
          const loc = s.location || '—';
          const tag = idx === nextStopIndex ? 'Next stop' : (s.kind || 'Stop');
          div.innerHTML = `
            <div class="load-main">
              <div class="load-route">${escapeHtml(label)}</div>
              <div class="load-sub">${escapeHtml(loc)}</div>
              <div class="load-meta">${escapeHtml(tag)}</div>
            </div>
            <div class="load-side">
              <button class="btn" type="button" data-action="gps" data-idx="${idx}">Set GPS</button>
            </div>
          `;
          stopsList.appendChild(div);
        });
      }
    }
  }

  function getSelectedMessage() {
    return (state.messages || []).find((m) => m.id === state.selectedMessageId) || null;
  }

  function renderMessages() {
    const list = $('msg-list');
    const sub = $('msg-sub');
    const empty = $('msg-empty');
    const body = $('msg-body');
    const title = $('msg-title');
    const meta = $('msg-meta');

    const msgs = state.messages || [];
    if (sub) sub.textContent = msgs.length ? `${msgs.length} message(s)` : 'No messages';

    if (list) {
      list.innerHTML = '';
      if (!msgs.length) {
        const div = document.createElement('div');
        div.className = 'empty';
        div.innerHTML = `<div class="empty-title">Inbox empty</div><div class="empty-sub">System messages will appear here.</div>`;
        list.appendChild(div);
      } else {
        msgs.slice(0, 50).forEach((m) => {
          const div = document.createElement('div');
          div.className = 'load';
          div.setAttribute('role', 'button');
          div.tabIndex = 0;
          div.setAttribute('data-id', m.id);
          div.innerHTML = `
            <div class="load-main">
              <div class="load-route">${escapeHtml(m.title)}</div>
              <div class="load-sub">${escapeHtml(fmtWhen(m.when))} • ${escapeHtml(m.type || 'system')}</div>
              <div class="load-meta">${escapeHtml(String(m.body || '').split('\n')[0] || '')}</div>
            </div>
            <div class="load-side">
              <div class="pill">Open</div>
            </div>
          `;
          list.appendChild(div);
        });
      }
    }

    const selected = getSelectedMessage();
    if (!selected) {
      if (title) title.textContent = 'Message';
      if (meta) meta.textContent = '—';
      if (empty) empty.classList.remove('hidden');
      if (body) {
        body.classList.add('hidden');
        body.textContent = '';
      }
      return;
    }

    if (title) title.textContent = selected.title;
    if (meta) meta.textContent = `${fmtWhen(selected.when)} • ${selected.type || 'system'}`;
    if (empty) empty.classList.add('hidden');
    if (body) {
      body.classList.remove('hidden');
      body.textContent = selected.body || '';
    }
  }

  function renderSettings() {
    const sWidget = $('s-widget');
    const sAuto = $('s-autoopen');
    if (sWidget) sWidget.checked = !!state.settings.showWidget;
    if (sAuto) sAuto.checked = !!state.settings.autoOpenLoadsOnAccept;

    setText('sv-name', state.playerVehicle.name || '—');
    setText('sv-cap', state.playerVehicle.capacity ? String(state.playerVehicle.capacity) : '—');
    setText('sv-trailer', state.playerVehicle.trailerType || '—');
    setText('sv-tow', state.playerVehicle.canTow ? 'Yes' : 'No');
  }

  function renderStats() {
    // Minimal: keep the duplicated stat cards in sync.
    const completed = state.history.filter((h) => h.status === 'Completed');
    const completedCount = completed.length;
    const totalEarned = completed.reduce((sum, h) => sum + Number(h.finalPayout || 0), 0);

    setTextMany(['loads-completed', 'loads-completed-2'], completedCount);
    setTextMany(['earn-week', 'earn-week-2'], fmtMoney(totalEarned));
    setTextMany(['earn-month', 'earn-month-2'], fmtMoney(totalEarned));
  }

  function render() {
    renderAccessNotice();
    renderDepotCard();
    renderStats();

    if (state.page === 'dashboard') {
      renderDashboard();
    }

    if (state.page === 'find') {
      renderFilterOptions();
      renderContractList();
    }

    if (state.page === 'loads') {
      renderActive();
      renderHistory();
    }

    if (state.page === 'route') {
      renderRoutePlanner();
    }

    if (state.page === 'messages') {
      renderMessages();
    }

    if (state.page === 'settings') {
      renderSettings();
    }

    updateWidget();
    syncOverlayToJobStatus();
    renderOverlay();
  }

  function boot() {
    updateClock();
    setInterval(updateClock, 5000);

    loadPersisted();
    if (mock) {
      seedPlayerVehicle();
      seedContracts();
      state.feeds.contracts = true;
      state.feeds.vehicle = true;
      state.profile.ownsTruck = true;
      state.feeds.profile = true;
      setOnline(true);
    } else {
      setOnline(false);
    }
    updateDriverHeader();
    renderFilterOptions();

    // Embedded inside pf-computer: keep background transparent.
    document.documentElement.style.background = 'transparent';
    document.body.style.background = 'transparent';

    // Sidebar navigation
    const nav = $('nav');
    if (nav) {
      nav.addEventListener('click', (e) => {
        const btn = e.target.closest('.nav-item');
        if (!btn) return;
        const page = btn.getAttribute('data-page');
        if (!page) return;
        setPage(page);
      });
    }

    // Find Jobs - filters
    const fPickup = $('f-pickup');
    const fWithin = $('f-within');
    const fTrailer = $('f-trailer');
    const fSearch = $('f-search');
    const btnSearch = $('btn-search');

    const applyFilters = () => {
      if (fPickup) state.filters.pickup = fPickup.value;
      if (fWithin) state.filters.within = fWithin.value;
      if (fTrailer) state.filters.trailer = fTrailer.value;
      if (fSearch) state.filters.search = fSearch.value;
      render();
    };

    if (fPickup) fPickup.onchange = applyFilters;
    if (fWithin) fWithin.onchange = applyFilters;
    if (fTrailer) fTrailer.onchange = applyFilters;
    if (fSearch) fSearch.addEventListener('input', applyFilters);
    if (btnSearch) btnSearch.onclick = applyFilters;

    const btnAdvanced = $('btn-advanced');
    if (btnAdvanced) {
      btnAdvanced.onclick = () => {
        setOverlay('info', { title: 'Advanced Filters', message: 'Not available in this UI yet.' });
      };
    }

    const btnRefresh = $('btn-refresh');
    if (btnRefresh) {
      btnRefresh.onclick = () => {
        if (mock) {
          seedContracts();
          renderFilterOptions();
          render();
          return;
        }

        fetchContracts();
      };
    }

    // Depot (computer, non-owner)
    const btnWorkTruckReq = $('btn-worktruck-request');
    if (btnWorkTruckReq) {
      btnWorkTruckReq.onclick = async () => {
        setOverlay('info', { title: 'Depot', message: 'Renting a work truck now happens when you accept a load.' });
      };
    }

    const contractList = $('contract-list');
    if (contractList) {
      contractList.addEventListener('click', (e) => {
        const btn = e.target.closest('button[data-action]');
        if (!btn) return;
        const action = btn.getAttribute('data-action');
        const id = btn.getAttribute('data-id');
        if (action === 'details' && id) openDetails(id);
      });
    }

    // Dashboard quick actions
    const dashBtnLoads = $('dash-btn-loads');
    if (dashBtnLoads) dashBtnLoads.onclick = () => setPage('loads');
    const dashBtnRoute = $('dash-btn-route');
    if (dashBtnRoute) dashBtnRoute.onclick = () => setPage('route');
    const dashBtnFind = $('dash-btn-find');
    if (dashBtnFind) dashBtnFind.onclick = () => setPage('find');

    const dashLoadsList = $('dash-loads-list');
    if (dashLoadsList) {
      dashLoadsList.addEventListener('click', (e) => {
        const btn = e.target.closest('button[data-action]');
        if (!btn) return;
        const action = btn.getAttribute('data-action');
        const id = btn.getAttribute('data-id');
        if (action === 'details' && id) openDetails(id);
      });
    }

    const stopsList = $('stops-list');
    if (stopsList) {
      stopsList.addEventListener('click', (e) => {
        const btn = e.target.closest('button[data-action="gps"]');
        if (!btn) return;
        const idx = Number(btn.getAttribute('data-idx'));
        const j = state.activeJob;
        if (!j || Number.isNaN(idx)) return;
        nuiPost('pf-trucking:setGps', { job: j, stopIndex: idx });
      });
    }

    // My Loads actions
    const btnGps = $('btn-setgps');
    if (btnGps) btnGps.onclick = () => setGps();
    const btnCancel = $('btn-cancel');
    if (btnCancel) btnCancel.onclick = () => cancelJob();

    // Widget
    const widgetToggle = $('widget-toggle');
    if (widgetToggle) {
      widgetToggle.onclick = () => {
        state.widget.minimized = !state.widget.minimized;
        saveWidget();
        updateWidget();
      };
    }

    // Messages
    const msgList = $('msg-list');
    if (msgList) {
      msgList.addEventListener('click', (e) => {
        const row = e.target.closest('[data-id]');
        if (!row) return;
        const id = row.getAttribute('data-id');
        if (!id) return;
        state.selectedMessageId = id;
        render();
      });
    }

    const btnMsgClear = $('btn-msg-clear');
    if (btnMsgClear) {
      btnMsgClear.onclick = () => {
        state.messages = [];
        state.selectedMessageId = null;
        saveMessages();
        render();
      };
    }

    // Settings
    const sWidget = $('s-widget');
    if (sWidget) {
      sWidget.onchange = () => {
        state.settings.showWidget = !!sWidget.checked;
        saveSettings();
        render();
      };
    }

    const sAuto = $('s-autoopen');
    if (sAuto) {
      sAuto.onchange = () => {
        state.settings.autoOpenLoadsOnAccept = !!sAuto.checked;
        saveSettings();
        render();
      };
    }

    const btnResetHistory = $('btn-reset-history');
    if (btnResetHistory) {
      btnResetHistory.onclick = () => {
        state.history = [];
        saveHistory();
        render();
      };
    }

    const btnResetMessages = $('btn-reset-messages');
    if (btnResetMessages) {
      btnResetMessages.onclick = () => {
        state.messages = [];
        state.selectedMessageId = null;
        render();
      };
    }

    // Future hook: allow parent (pf-computer) to push player/job state
    window.addEventListener('message', (e) => {
      const d = e.data || {};
      if (d.action === 'pf-trucking:setStatus') setOnline(!!d.online);

      if (d.action === 'pf-trucking:setProfile' && d.profile) {
        state.profile = {
          name: d.profile.name || state.profile.name,
          ownsTruck: (d.profile.ownsTruck === true) ? true : (d.profile.ownsTruck === false ? false : state.profile.ownsTruck),
        };
        state.feeds.profile = true;
        updateDriverHeader();
        render();
        return;
      }

      if (d.action === 'pf-trucking:setWorkTruck') {
        state.workTruck = d.truck || null;
        // If depot assigns a truck, treat it as vehicle data for compatibility.
        if (state.workTruck && state.device === 'computer' && state.profile.ownsTruck === false) {
          state.playerVehicle = { ...state.playerVehicle, name: state.workTruck.name || 'Work Truck' };
          state.feeds.vehicle = true;
        }
        render();
        return;
      }

      if (d.action === 'pf-trucking:setPlayerVehicle' && d.vehicle) {
        state.playerVehicle = {
          name: d.vehicle.name || state.playerVehicle.name,
          capacity: Number(d.vehicle.capacity ?? state.playerVehicle.capacity),
          trailerType: d.vehicle.trailerType || d.vehicle.trailer || state.playerVehicle.trailerType,
          canTow: d.vehicle.canTow == null ? state.playerVehicle.canTow : !!d.vehicle.canTow,
        };
        state.feeds.vehicle = true;
        if (!state.online) setOnline(true);
        render();
      }

      if (d.action === 'pf-trucking:setContracts' && Array.isArray(d.contracts)) {
        state.contracts = d.contracts;
        state.feeds.contracts = true;
        if (!state.online) setOnline(true);
        renderFilterOptions();
        render();
      }

      if (d.action === 'pf-trucking:setActiveJob') {
        state.activeJob = d.job || null;
        if (state.activeJob) setPage('loads');
        render();
      }

      if (d.action === 'pf-trucking:updateActiveJob' && state.activeJob) {
        state.activeJob = { ...state.activeJob, ...(d.job || {}) };
        if (state.activeJob.status === 'Loading') setOverlay('loading', { progress: d.progress ?? state.overlay.progress });
        if (state.activeJob.status === 'Delivering') setOverlay('delivery', {});
        if (state.activeJob.status === 'Completed') setOverlay('completion', {});
        render();
      }

      if (d.action === 'pf-trucking:setOverlay') {
        if (d.mode) setOverlay(d.mode, d);
        else hideOverlay();
      }
    });

    // Default page is Find Jobs (matches HTML)
    if (!mock) fetchContracts({ silent: false });
    setPage(state.device === 'tablet' ? 'dashboard' : 'find');
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
