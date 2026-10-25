// ============================================================================
// EMS MDT - Extended Modules
// Patient profile rendering and remaining shared helpers
// ============================================================================

// ============================================================================
// GTA Paint Color Palette (static; no natives used)
// Minimal but extensible mapping; fallbacks provided for unknown IDs
// ============================================================================
const GTA_COLOR_PALETTE = {
    0:  { name: 'Black',             rgb: [11, 11, 11] },
    1:  { name: 'Graphite',          rgb: [29, 33, 41] },
    2:  { name: 'Black Steel',       rgb: [45, 49, 56] },
    3:  { name: 'Dark Steel',        rgb: [72, 76, 80] },
    4:  { name: 'Silver',            rgb: [192, 191, 190] },
    5:  { name: 'Bluish Silver',     rgb: [196, 199, 210] },
    6:  { name: 'Rolled Steel',      rgb: [108, 122, 136] },
    7:  { name: 'Shadow Silver',     rgb: [90, 98, 104] },
    8:  { name: 'Stone Silver',      rgb: [150, 156, 168] },
    9:  { name: 'Midnight Silver',   rgb: [60, 60, 60] },
    10: { name: 'Cast Iron Silver',  rgb: [50, 56, 61] },
    11: { name: 'Red',               rgb: [192, 14, 26] },
    12: { name: 'Torino Red',        rgb: [218, 25, 24] },
    13: { name: 'Formula Red',       rgb: [221, 34, 24] },
    14: { name: 'Blaze Red',         rgb: [165, 30, 35] },
    15: { name: 'Grace Red',         rgb: [125, 27, 32] },
    16: { name: 'Garnet Red',        rgb: [99, 19, 26] },
    17: { name: 'Sunset Red',        rgb: [207, 63, 32] },
    18: { name: 'Cabernet Red',      rgb: [78, 17, 20] },
    19: { name: 'Wine Red',          rgb: [73, 10, 20] },
    20: { name: 'Candy Red',         rgb: [224, 14, 42] },
    21: { name: 'Hot Pink',          rgb: [237, 85, 130] },
    22: { name: 'Pfister Pink',      rgb: [254, 93, 133] },
    23: { name: 'Salmon Pink',       rgb: [244, 143, 149] },
    24: { name: 'Sunrise Orange',    rgb: [243, 112, 32] },
    25: { name: 'Orange',            rgb: [255, 123, 0] },
    26: { name: 'Bright Orange',     rgb: [255, 145, 0] },
    27: { name: 'Gold',              rgb: [122, 101, 40] },
    28: { name: 'Bronze',            rgb: [127, 95, 53] },
    30: { name: 'Yellow',            rgb: [255, 195, 0] },
    31: { name: 'Race Yellow',       rgb: [255, 223, 0] },
    32: { name: 'Dew Yellow',        rgb: [231, 231, 76] },
    33: { name: 'Dark Green',        rgb: [22, 46, 33] },
    34: { name: 'Racing Green',      rgb: [32, 57, 46] },
    35: { name: 'Sea Green',         rgb: [51, 95, 74] },
    37: { name: 'Olive Green',       rgb: [105, 110, 68] },
    38: { name: 'Bright Green',      rgb: [38, 153, 42] },
    41: { name: 'Gasoline Green',    rgb: [58, 132, 113] },
    42: { name: 'Lime Green',        rgb: [144, 209, 62] },
    54: { name: 'Dark Blue',         rgb: [11, 22, 53] },
    61: { name: 'Midnight Blue',     rgb: [8, 15, 40] },
    62: { name: 'Blue',              rgb: [28, 54, 93] },
    64: { name: 'Mariner Blue',      rgb: [49, 89, 146] },
    68: { name: 'Harbor Blue',       rgb: [76, 104, 142] },
    73: { name: 'Diamond Blue',      rgb: [175, 207, 230] },
    74: { name: 'Surf Blue',         rgb: [46, 147, 187] },
    75: { name: 'Nautical Blue',     rgb: [52, 101, 164] },
    79: { name: 'Ultra Blue',        rgb: [0, 91, 255] },
    82: { name: 'Light Blue',        rgb: [114, 181, 216] },
    88: { name: 'Chocolate Brown',   rgb: [53, 35, 24] },
    89: { name: 'Bison Brown',       rgb: [67, 43, 34] },
    90: { name: 'Creeen Brown',      rgb: [85, 60, 45] },
    94: { name: 'Saddle Brown',      rgb: [88, 44, 22] },
    96: { name: 'Straw Brown',       rgb: [196, 164, 132] },
    97: { name: 'Moss Brown',        rgb: [95, 92, 62] },
    98: { name: 'Sandy Brown',       rgb: [199, 172, 125] },
    99: { name: 'Bleached Brown',    rgb: [223, 203, 170] },
    112:{ name: 'Pure White',        rgb: [255, 255, 255] },
    113:{ name: 'Frost White',       rgb: [235, 235, 235] },
    117:{ name: 'Matte Black',       rgb: [15, 15, 15] },
    118:{ name: 'Matte Gray',        rgb: [64, 64, 64] },
    120:{ name: 'Matte White',       rgb: [230, 230, 230] },
    121:{ name: 'Matte Blue',        rgb: [39, 90, 124] },
    122:{ name: 'Matte Midnight',    rgb: [10, 16, 31] },
    123:{ name: 'Matte Purple',      rgb: [107, 31, 123] },
    124:{ name: 'Matte Dark Purple', rgb: [43, 21, 43] },
    125:{ name: 'Matte Red',         rgb: [146, 16, 22] },
    126:{ name: 'Matte Dark Red',    rgb: [86, 17, 24] },
    127:{ name: 'Matte Orange',      rgb: [204, 113, 19] },
    128:{ name: 'Matte Yellow',      rgb: [214, 188, 33] },
    129:{ name: 'Matte Green',       rgb: [66, 125, 54] },
    130:{ name: 'Matte Frost Green', rgb: [97, 133, 97] },
    131:{ name: 'Met Black',         rgb: [13, 13, 13] },
    134:{ name: 'Met Dark Blue',     rgb: [25, 38, 66] },
    135:{ name: 'Met Midnight Blue', rgb: [12, 18, 45] },
    136:{ name: 'Met Gun Metal',     rgb: [50, 56, 61] },
    137:{ name: 'Met Anthracite',    rgb: [29, 33, 41] },
    141:{ name: 'Brushed Steel',     rgb: [107, 116, 123] },
    142:{ name: 'Brushed Black Steel',rgb:[58, 64, 69] },
    143:{ name: 'Brushed Aluminum',  rgb: [155, 160, 168] },
    144:{ name: 'Chrome',            rgb: [220, 220, 220] },
    156:{ name: 'Lava Red',          rgb: [191, 25, 25] }
};

function rgbToHex(r, g, b) {
    const c = (n) => Math.max(0, Math.min(255, Math.round(n || 0))).toString(16).padStart(2, '0');
    return `#${c(r)}${c(g)}${c(b)}`;
}
/*
// Profile rendering and message handling (EMS-only) [DISABLED]
// This block became corrupted during PD-module removal; the active EMS-only
// patient profile renderer lives further below.
(function profilesModule(){
    const safe = (v) => (typeof escapeHtml === 'function') ? escapeHtml(String(v ?? '')) : String(v ?? '');

    function setActiveTab(modal, tabId){
        modal.querySelectorAll('.tab').forEach(t => t.classList.toggle('active', t.dataset.tab === tabId));
        const content = modal.querySelector('#citizenProfileContent');
        if (!content) return;
        content.querySelectorAll('[data-view]').forEach(v => {
            v.style.display = (v.dataset.view === tabId ? 'block' : 'none');
        });
    }

    function wireTabsOnce(modal){
        if (!modal || modal.dataset.tabsWired === '1') return;
        modal.dataset.tabsWired = '1';
        modal.querySelectorAll('.tab').forEach((btn) => {
            btn.addEventListener('click', () => setActiveTab(modal, btn.dataset.tab));
        });
    }

    function renderCitizenProfile(data){
        const modal = document.getElementById('citizenProfileModal');
        if (!modal) return;
        modal.classList.remove('hidden');

        wireTabsOnce(modal);

        const name = String(data.name || 'Patient Profile');
        const citizenId = String(data.citizenId || '');
        const dob = String(data.dob || '');
        const age = (typeof data.age === 'number' && data.age >= 0) ? data.age : 'N/A';
        const gender = String(data.gender || 'Unknown');
        const nationality = String(data.nationality || 'Unknown');
        const phone = String(data.phone || 'N/A');
        const job = String(data.job || 'Unemployed');
        const bloodtype = String(data.bloodtype || 'Unknown');
        const pcrCount = Number(data.pcrCount || 0);
        const injuries = Array.isArray(data.injuries) ? data.injuries : [];
        const notes = Array.isArray(data.notes) ? data.notes : [];

        const nameEl = document.getElementById('citizenProfileName');
        if (nameEl) nameEl.textContent = name;

        const identityHeader = document.getElementById('citizenIdentityHeader');
        if (identityHeader) {
            identityHeader.innerHTML = `
                <div class="citizen-header">
                    <div class="citizen-header-main">
                        <div class="citizen-name-row">
                            <div class="citizen-name">${safe(name)}</div>
                            ${citizenId ? `<span class="citizen-id-pill">${safe(citizenId)}</span>` : ''}
                        </div>
                        <div class="citizen-kv-grid">
                            <div class="citizen-kv"><span class="citizen-k">DOB</span><span class="citizen-v">${safe(dob || 'N/A')}</span></div>
                            <div class="citizen-kv"><span class="citizen-k">Age</span><span class="citizen-v">${safe(age)}</span></div>
                            <div class="citizen-kv"><span class="citizen-k">Gender</span><span class="citizen-v">${safe(gender)}</span></div>
                            <div class="citizen-kv"><span class="citizen-k">Nationality</span><span class="citizen-v">${safe(nationality)}</span></div>
                            <div class="citizen-kv"><span class="citizen-k">Phone</span><span class="citizen-v">${safe(phone)}</span></div>
                            <div class="citizen-kv"><span class="citizen-k">Job</span><span class="citizen-v">${safe(job)}</span></div>
                        </div>
                    </div>
                </div>
            `;
        }

        const summaryBar = document.getElementById('citizenSummaryBar');
        if (summaryBar) {
            summaryBar.innerHTML = `
                <div style="display:grid; grid-template-columns: repeat(3, 1fr); gap: 12px;">
                    <div class="summary-card"><div class="summary-value">${safe(pcrCount)}</div><div class="summary-label">PCR Records</div></div>
                    <div class="summary-card"><div class="summary-value">${safe(injuries.length)}</div><div class="summary-label">Injuries</div></div>
                    <div class="summary-card"><div class="summary-value">${safe(notes.length)}</div><div class="summary-label">Notes</div></div>
                </div>
            `;
        }

        const content = document.getElementById('citizenProfileContent');
        if (!content) return;

        const injuriesHtml = injuries.length
            ? injuries.map((inj) => {
                const label = safe(inj.label || inj.name || inj.type || 'Injury');
                const severity = safe(inj.severity || inj.level || '');
                const when = safe(inj.time || inj.timestamp || inj.createdAt || inj.created_at || '');
                return `<div class="report-card"><div style="font-weight:700;">${label}</div><div class="muted" style="margin-top:4px;">${[severity, when].filter(Boolean).join(' • ')}</div></div>`;
            }).join('')
            : '<div class="empty-message">No injuries recorded</div>';

        const notesHtml = notes.length
            ? notes.map((n) => {
                const text = safe(n.text || n.note || '');
                const meta = safe([n.author, n.createdAt, n.created_at].filter(Boolean).join(' • '));
                return `<div class="note-row"><div>${text}</div><div style="font-size:11px;color:rgba(255,255,255,0.6)">${meta}</div></div>`;
            }).join('')
            : '<div class="empty-message">No notes</div>';

        content.innerHTML = `
            <div data-view="c-overview">
                <div class="form-section">
                    <div class="muted" style="font-size:12px; margin-bottom:8px;">Patient overview</div>
                // ============================================================================
                // PD-only (warrants/weapons registry and related pickers) removed for EMS MDT.
                // ============================================================================

        window.__chargesCatalog = window.__chargesCatalog || [];
        window.__selectedWarrantCharges = new Set();
        let shouldShowDropdown = false;

        const renderChips = () => {
            const items = Array.from(window.__selectedWarrantCharges);
            list.innerHTML = items.map(c => `<span class="charge-chip" style="cursor:pointer;" data-charge="${c}">${c} ✕</span>`).join('');
        };
        const buildChargeLabels = () => {
            const catalog = Array.isArray(window.__chargesCatalog) ? window.__chargesCatalog : [];
            const labels = catalog.map(c => {
                const label = [c.code, c.name].filter(Boolean).join(' - ');
                return (label || c.code || c.name || 'Charge').trim();
            }).filter(Boolean);
            return Array.from(new Set(labels)).sort();
        };
        const showDropdown = (items) => {
            if (!shouldShowDropdown) { dropdown.classList.add('hidden'); return; }
            if (!items || items.length === 0) { dropdown.classList.add('hidden'); dropdown.innerHTML=''; return; }
            dropdown.classList.remove('hidden');
            dropdown.innerHTML = items.slice(0, 80).map(c => {
                const encoded = encodeURIComponent(c);
                return `<div class="dropdown-item" data-pick="${encoded}">${c}</div>`;
            }).join('');
        };
        const filter = (q) => {
            const base = buildChargeLabels();
            const query = (q||'').toLowerCase();
            const matches = query ? base.filter(s => s.toLowerCase().includes(query)) : base;
            showDropdown(matches);
        };

        // Request charges if empty
        if (!window.__chargesCatalog || window.__chargesCatalog.length === 0) {
            try { 
                sendCallback('getCharges', {}, (result) => {
                    if (result && result.charges && Array.isArray(result.charges)) {
                        window.__chargesCatalog = result.charges;
                        console.log('[MDT DEBUG] Loaded charges for warrant picker:', window.__chargesCatalog.length);
                    }
                }); 
            } catch(_) {}
        }

        input.addEventListener('focus', () => {
            shouldShowDropdown = true;
            filter(input.value);
        });
        input.addEventListener('click', (e) => {
            e.stopPropagation();
            shouldShowDropdown = true;
            filter(input.value);
        });
        input.addEventListener('input', () => {
            shouldShowDropdown = true;
            filter(input.value);
        });
        input.addEventListener('keydown', (e) => {
            if (e.key === 'Enter') {
                e.preventDefault();
                const val = input.value.trim();
                if (val) { 
                    window.__selectedWarrantCharges.add(val); 
                    renderChips(); 
                    input.value=''; 
                    shouldShowDropdown = false;
                    dropdown.classList.add('hidden');
                }
            }
        });

        dropdown.addEventListener('click', (e) => {
            e.stopPropagation();
            const raw = e.target.closest('[data-pick]')?.getAttribute('data-pick');
            if (!raw) return;
            const pick = decodeURIComponent(raw);
            if (window.__selectedWarrantCharges.has(pick)) window.__selectedWarrantCharges.delete(pick); else window.__selectedWarrantCharges.add(pick);
            renderChips();
            input.value='';
            shouldShowDropdown = false;
            dropdown.classList.add('hidden');
        });

        list.addEventListener('click', (e) => {
            const chip = e.target.closest('[data-charge]');
            if (!chip) return;
            const name = chip.getAttribute('data-charge');
            window.__selectedWarrantCharges.delete(name);
            renderChips();
        });

        // Global click handler to hide dropdown
        document.addEventListener('click', () => {
            shouldShowDropdown = false;
            dropdown.classList.add('hidden');
        });

        // Observe messages to capture charges catalog
        window.addEventListener('message', (e) => {
            const d = e.data; if (!d) return;
            if (d.action === 'setCharges') {
                window.__chargesCatalog = Array.isArray(d.charges) ? d.charges : [];
            }
        });

        // Reset selections handled explicitly when opening modal (openNewWarrantModal)
    };
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', ensure); else ensure();
    const obs = new MutationObserver(ensure);
    obs.observe(document.documentElement, { childList: true, subtree: true });
})();
*/

// Officers picker for the warrant modal
(function setupWarrantOfficerPicker(){
    let wired = false;
    const ensure = () => {
        if (wired) return;
        const input = document.getElementById('warrantOfficerInput');
        const dropdown = document.getElementById('warrantOfficerDropdown');
        const list = document.getElementById('warrantOfficersList');
        if (!input || !dropdown || !list) return;
        wired = true;

        window.__officerCatalog = window.__officerCatalog || [];
        window.__selectedWarrantOfficers = new Set();
        let shouldShowDropdown = false;

        const renderChips = () => {
            const items = Array.from(window.__selectedWarrantOfficers);
            list.innerHTML = items.map(o => `<span class="charge-chip" style="cursor:pointer;" data-officer="${escapeHtml(o)}">${escapeHtml(o)} ✕</span>`).join('');
        };

        const buildOfficerLabels = () => {
            const catalog = Array.isArray(window.__officerCatalog) ? window.__officerCatalog : [];
            const allowed = (window.Config && window.Config.AllowedJobs) || {};
            const labels = catalog
                .filter(o => {
                    const jobName = (o.job && o.job.name) || o.job || o.department || '';
                    return allowed[jobName] === true || String(jobName).toLowerCase().includes('police');
                })
                .map(o => {
                    const name = o.name || o.fullname || o.label || 'Officer';
                    const callsign = o.callsign ? ` (${o.callsign})` : '';
                    return (name + callsign).trim();
                })
                .filter(Boolean);
            return Array.from(new Set(labels)).sort();
        };

        const showDropdown = (items) => {
            if (!shouldShowDropdown) { dropdown.classList.add('hidden'); return; }
            if (!items || items.length === 0) { dropdown.classList.add('hidden'); dropdown.innerHTML=''; return; }
            dropdown.classList.remove('hidden');
            dropdown.innerHTML = items.slice(0, 80).map(o => `<div class="dropdown-item" data-pick="${escapeHtml(o)}">${escapeHtml(o)}</div>`).join('');
        };

        const filter = (q) => {
            const base = buildOfficerLabels();
            const query = (q||'').toLowerCase();
            const matches = query ? base.filter(o => o.toLowerCase().includes(query)) : base;
            showDropdown(matches);
        };

        let officersFetched = false;
        const ensureOfficers = () => {
            if (officersFetched) return;
            officersFetched = true;
            try {
                sendCallback('getPoliceOfficers', {}, (res) => {
                    window.__officerCatalog = Array.isArray(res) ? res : [];
                    filter(input.value);
                });
            } catch (_) {
                // ignore fetch errors; fallback will keep dropdown empty
            }
        };

        input.addEventListener('focus', () => {
            shouldShowDropdown = true;
            filter(input.value);
        });
        input.addEventListener('click', (e) => {
            e.stopPropagation();
            shouldShowDropdown = true;
            filter(input.value);
        });
        input.addEventListener('input', () => {
            shouldShowDropdown = true;
            filter(input.value);
        });
        input.addEventListener('keydown', (e) => {
            if (e.key === 'Enter') {
                e.preventDefault();
                const val = input.value.trim();
                if (val) { 
                    window.__selectedWarrantOfficers.add(val); 
                    renderChips(); 
                    input.value=''; 
                    shouldShowDropdown = false;
                    dropdown.classList.add('hidden');
                }
            }
        });

        dropdown.addEventListener('click', (e) => {
            e.stopPropagation();
            const pick = e.target.closest('[data-pick]')?.getAttribute('data-pick');
            if (!pick) return;
            if (window.__selectedWarrantOfficers.has(pick)) window.__selectedWarrantOfficers.delete(pick); else window.__selectedWarrantOfficers.add(pick);
            renderChips();
            input.value='';
            shouldShowDropdown = false;
            dropdown.classList.add('hidden');
        });

        list.addEventListener('click', (e) => {
            const chip = e.target.closest('[data-officer]');
            if (!chip) return;
            const name = chip.getAttribute('data-officer');
            window.__selectedWarrantOfficers.delete(name);
            renderChips();
        });

        // Global click handler to hide dropdown
        document.addEventListener('click', () => {
            shouldShowDropdown = false;
            dropdown.classList.add('hidden');
        });

        input.addEventListener('focus', ensureOfficers);
        input.addEventListener('click', ensureOfficers);
        input.addEventListener('keydown', ensureOfficers);
        ensureOfficers();

        // Reset selections when modal is opened
        window.addEventListener('click', () => {
            const modal = document.getElementById('newWarrantModal');
            if (modal && !modal.classList.contains('hidden')) {
                renderChips();
            }
        }, true);
    };
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', ensure); else ensure();
    const obs = new MutationObserver(ensure);
    obs.observe(document.documentElement, { childList: true, subtree: true });
})();

// Witness picker for the warrant modal
(function setupWarrantWitnessPicker(){
    let wired = false;
    const ensure = () => {
        if (wired) return;
        const nameInput = document.getElementById('warrantWitnessNameInput');
        const phoneInput = document.getElementById('warrantWitnessPhoneInput');
        const statementInput = document.getElementById('warrantWitnessStatementInput');
        const dropdown = document.getElementById('warrantWitnessDropdown');
        const addSelect = document.getElementById('warrantAddWitnessDropdown');
        const list = document.getElementById('warrantWitnessesList');
        if (!nameInput || !addSelect || !list || !dropdown) return;
        wired = true;

        window.__selectedWitnesses = window.__selectedWitnesses || [];
        window.__witnessCatalog = window.__witnessCatalog || [];
        let shouldShowDropdown = false;
        let playersFetched = false;

        const renderWitnesses = () => {
            list.innerHTML = window.__selectedWitnesses.map((w, i) => `
                <div style="padding:8px; background:rgba(255,255,255,0.05); border-radius:6px; display:flex; justify-content:space-between; align-items:center;">
                    <div>
                        <div style="font-weight:500;">${escapeHtml(w.name)}</div>
                        <div style="font-size:11px; color:rgba(255,255,255,0.6);">${escapeHtml(w.phone || 'No phone')}</div>
                        <div style="font-size:11px; color:rgba(255,255,255,0.5); margin-top:4px;">${escapeHtml(w.statement || 'No statement')}</div>
                    </div>
                    <button style="cursor:pointer; color:#ff6b6b; border:none; background:transparent; font-size:16px;" onclick="window.__removeWitness(${i})">✕</button>
                </div>
            `).join('');
        };

        window.__removeWitness = (index) => {
            window.__selectedWitnesses.splice(index, 1);
            renderWitnesses();
        };

        const buildWitnessLabels = () => {
            return (Array.isArray(window.__witnessCatalog) ? window.__witnessCatalog : [])
                .map(w => {
                    const name = w.name || 'Unknown';
                    return name;
                })
                .filter(Boolean);
        };

        const showDropdown = (items) => {
            if (!shouldShowDropdown) { dropdown.classList.add('hidden'); return; }
            if (!items || items.length === 0) { dropdown.classList.add('hidden'); dropdown.innerHTML=''; return; }
            dropdown.classList.remove('hidden');
            dropdown.innerHTML = items.slice(0, 80).map(name => `<div class="dropdown-item" data-pick="${escapeHtml(name)}">${escapeHtml(name)}</div>`).join('');
        };

        const filter = (q) => {
            const base = buildWitnessLabels();
            const query = (q||'').toLowerCase();
            const matches = query ? base.filter(n => n.toLowerCase().includes(query)) : base;
            showDropdown(matches);
        };

        const ensureWitnesses = () => {
            if (playersFetched) return;
            playersFetched = true;
            try {
                sendCallback('getAllPlayers', {}, (res) => {
                    window.__witnessCatalog = Array.isArray(res) ? res : [];
                    filter(nameInput.value);
                    populateSelect();
                });
            } catch (_) {}
        };

        nameInput.addEventListener('focus', () => {
            shouldShowDropdown = true;
            ensureWitnesses();
            filter(nameInput.value);
        });
        nameInput.addEventListener('click', (e) => {
            e.stopPropagation();
            shouldShowDropdown = true;
            ensureWitnesses();
            filter(nameInput.value);
        });
        nameInput.addEventListener('input', () => {
            shouldShowDropdown = true;
            filter(nameInput.value);
        });

        dropdown.addEventListener('click', (e) => {
            e.stopPropagation();
            const pick = e.target.closest('[data-pick]')?.getAttribute('data-pick');
            if (!pick) return;
            nameInput.value = pick;
            shouldShowDropdown = false;
            dropdown.classList.add('hidden');
        });

        document.addEventListener('click', () => {
            shouldShowDropdown = false;
            dropdown.classList.add('hidden');
        });

        const populateSelect = () => {
            const base = Array.isArray(window.__witnessCatalog) ? window.__witnessCatalog : [];
            addSelect.innerHTML = '<option value="">Select witness to add...</option>' + base.map(w => {
                const name = w.name || 'Unknown';
                return `<option value="${escapeHtml(w.citizenid || '')}">${escapeHtml(name)}</option>`;
            }).join('');
        };

        addSelect.addEventListener('focus', () => { ensureWitnesses(); populateSelect(); });
        addSelect.addEventListener('click', () => { ensureWitnesses(); populateSelect(); });
        addSelect.addEventListener('change', () => {
            const cid = addSelect.value;
            if (!cid) return;
            const base = Array.isArray(window.__witnessCatalog) ? window.__witnessCatalog : [];
            const found = base.find(w => String(w.citizenid) === String(cid));
            const name = found?.name || (nameInput.value || '').trim();
            if (!name) return;
            const phone = (found?.charinfo?.phone) || (found?.charinfo?.phone_number) || found?.phone || '';
            const statement = (statementInput.value || '').trim();
            window.__selectedWitnesses.push({ name, phone, statement });
            nameInput.value = '';
            phoneInput.value = '';
            statementInput.value = '';
            addSelect.value = '';
            dropdown.classList.add('hidden');
            renderWitnesses();
        });
    };
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', ensure); else ensure();
    const obs = new MutationObserver(ensure);
    obs.observe(document.documentElement, { childList: true, subtree: true });
})();

// Profile rendering and message handling
(function profilesModule(){
    function setActiveTab(container, tabIdPrefix, tabId){
        container.querySelectorAll('.tab').forEach(t => t.classList.toggle('active', t.dataset.tab === tabId));
        const content = container.querySelector('[id$="Content"]');
        if (!content) return;
        content.querySelectorAll('[data-view]').forEach(v => v.style.display = (v.dataset.view === tabId ? 'block' : 'none'));
    }

    function renderCitizenWeaponsList(citizenId) {
        const listEl = document.getElementById('citizenWeaponsList');
        const countEl = document.getElementById('citizenWeaponsCount');
        if (!listEl) return;

        listEl.innerHTML = '<div class="empty-message">Loading...</div>';
        if (countEl) countEl.textContent = '0';

        try {
            sendCallback('getCitizenWeapons', { citizenId }, (res) => {
                const items = (res && res.success && Array.isArray(res.weapons)) ? res.weapons : [];
                if (countEl) countEl.textContent = String(items.length);

                if (!items.length) {
                    listEl.innerHTML = '<div class="empty-message">No registered weapons</div>';
                    return;
                }

                listEl.innerHTML = items.map((w) => {
                    const serial = escapeHtml(String(w.serial || ''));
                    const label = escapeHtml(String(w.weaponLabel || w.weapon || ''));
                    const model = escapeHtml(String(w.weapon || ''));
                    const whenRaw = w.registeredAt || w.registered_at || '';
                    const when = (typeof formatDateTime === 'function') ? (formatDateTime(whenRaw) || String(whenRaw || '')) : String(whenRaw || '');
                    return `
                        <div style="padding: 12px; background: rgba(255,255,255,0.03); border-radius: 6px; margin-bottom: 8px;">
                            <div style="display:flex; justify-content:space-between; align-items:center; gap:10px;">
                                <div style="font-weight:700;">${serial || 'UNKNOWN'}</div>
                                <span class="status-badge">Registered</span>
                            </div>
                            <div style="font-size: 14px; margin-top: 6px;">${label || 'Unknown Weapon'}</div>
                            <div style="font-size: 12px; color: rgba(255,255,255,0.6); margin-top: 4px;">
                                ${model ? `Model: ${model} • ` : ''}${escapeHtml(when)}
                            </div>
                        </div>
                    `;
                }).join('');
            });
        } catch (_) {
            listEl.innerHTML = '<div class="empty-message">Failed to load weapons</div>';
        }
    }

    function renderCitizenProfile(data){
        const modal = document.getElementById('citizenProfileModal');
        if (!modal) return;
        modal.classList.remove('hidden');

        const appearance = data.appearance || {};
        const skinToneLabel = appearance.skinToneLabel || data.skin || 'Not recorded';
        const hairColorLabel = appearance.hairColorLabel || data.hairColor || 'Not recorded';
        const eyeColorLabel = appearance.eyeColorLabel || data.eyeColor || 'Not recorded';
        const hairHighlightLabel = appearance.hairHighlightLabel || null;
        const genderLabel = data.gender || 'Not recorded';
        
        // Set title
        const nameEl = document.getElementById('citizenProfileName');
        if (nameEl) nameEl.textContent = data.name || 'Citizen Profile';
        
        const properties = Array.isArray(data.properties) ? data.properties : [];
        const propAddrList = Array.from(new Set(
            properties
                .map(p => (p && p.address != null) ? String(p.address).trim() : '')
                .filter(a => a && a.toLowerCase() !== 'unknown')
        ));
        const displayAddress = (data.address && String(data.address).trim())
            ? String(data.address).trim()
            : (propAddrList[0] || 'No address on file');

        // Identity Header with photo, basic info, and status flags
        const identityHeader = document.getElementById('citizenIdentityHeader');
        if (identityHeader) {
            const warrantBadge = data.hasWarrant ? '<span class="status-flag warrant-flag">ACTIVE WARRANT</span>' : '';
            const boloBadge = data.isBOLO ? '<span class="status-flag bolo-flag">BOLO</span>' : '';
            const dangerBadge = data.isDangerous ? '<span class="status-flag danger-flag">DANGEROUS</span>' : '';
            const profilePicUrl = data.profilePicture || '';

            const initials = ((data.firstname || 'U')[0] || 'U') + ((data.lastname || 'N')[0] || 'N');

            identityHeader.innerHTML = `
                <div class="citizen-header">
                    <div class="citizen-header-left">
                        <div class="citizen-photo" id="citizenProfilePhoto" style="${safeCssUrl(profilePicUrl) ? escapeHtml('background-image: url(\'' + safeCssUrl(profilePicUrl) + '\');') : ''}">
                            ${profilePicUrl ? '' : escapeHtml(initials)}
                        </div>
                        <div class="citizen-photo-actions">
                            <button class="btn small" onclick="openProfilePictureModal('${escapeJsAttr(data.citizenId)}')">Change Photo</button>
                            <button class="btn small" onclick="takeProfilePhoto('${escapeJsAttr(data.citizenId)}')">📷 Take Photo</button>
                        </div>
                    </div>

                    <div class="citizen-header-main">
                        <div class="citizen-name-row">
                            <div class="citizen-name">${escapeHtml(data.name || 'Unknown')}</div>
                            <span class="citizen-id-pill">${escapeHtml(data.citizenId || '')}</span>
                        </div>

                        <div class="citizen-flag-row">${warrantBadge}${boloBadge}${dangerBadge}</div>

                        <div class="citizen-kv-grid">
                            <div class="citizen-kv"><span class="citizen-k">DOB</span><span class="citizen-v">${escapeHtml(data.dob || 'N/A')}</span></div>
                            <div class="citizen-kv"><span class="citizen-k">Age</span><span class="citizen-v">${typeof data.age === 'number' && data.age >= 0 ? escapeHtml(data.age) : 'N/A'}</span></div>
                            <div class="citizen-kv"><span class="citizen-k">Gender</span><span class="citizen-v">${escapeHtml(data.gender || 'Unknown')}</span></div>
                            <div class="citizen-kv"><span class="citizen-k">Phone</span><span class="citizen-v">${escapeHtml(data.phone || 'N/A')}</span></div>
                            <div class="citizen-kv"><span class="citizen-k">Job</span><span class="citizen-v">${escapeHtml(data.job || 'Unemployed')}</span></div>
                            <div class="citizen-kv"><span class="citizen-k">Address</span><span class="citizen-v">${escapeHtml(displayAddress)}</span></div>
                        </div>
                    </div>
                </div>
            `;
        }
        
        // Quick Summary Bar
        const summaryBar = document.getElementById('citizenSummaryBar');
        if (summaryBar) {
            const propCount = Number(data.propertyCount || (Array.isArray(data.properties) ? data.properties.length : 0) || 0);
            summaryBar.innerHTML = `
                <div style="display: grid; grid-template-columns: repeat(5, 1fr); gap: 12px;">
                    <div class="summary-card">
                        <div class="summary-value">${escapeHtml(data.warrantCount)}</div>
                        <div class="summary-label">Active Warrants</div>
                    </div>
                    <div class="summary-card">
                        <div class="summary-value">${escapeHtml(data.convictionCount)}</div>
                        <div class="summary-label">Convictions</div>
                    </div>
                    <div class="summary-card">
                        <div class="summary-value">${escapeHtml(data.vehicleCount)}</div>
                        <div class="summary-label">Vehicles</div>
                    </div>
                    <div class="summary-card">
                        <div class="summary-value">${propCount}</div>
                        <div class="summary-label">Properties</div>
                    </div>
                    <div class="summary-card">
                        <div class="summary-value">${(data.incidents || []).length}</div>
                        <div class="summary-label">Incidents</div>
                    </div>
                </div>
            `;
        }
        
        const content = document.getElementById('citizenProfileContent');
        if (!content) return;
        
        const flagsArr = Array.isArray(data.flags) ? data.flags : [];
        const flags = flagsArr.length
            ? flagsArr.map(f => {
                const lbl = escapeHtml(String(f || ''));
                const payloadEnc = encodeURIComponent(JSON.stringify({ citizenId: data.citizenId, citizenName: data.name || '', flag: String(f || '') }));
                return `<span class="flag-chip" style="cursor:pointer;" onclick="openFlagRemoveModal(decodeURIComponent('${escapeJsAttr(payloadEnc)}'))" title="Click to remove">${lbl}</span>`;
            }).join('')
            : '<span class="flag-chip">None</span>';
        const licenseMap = { driver: 'Driver License', weapon: 'Weapon License', business: 'Business License' };
        const suspensions = data.licenseSuspensions || {};
        
        // Get all possible licenses (active or suspended)
        const allLicenseKeys = new Set([...Object.keys(data.licenses || {}), ...Object.keys(suspensions)]);
        let licenses = '';
        if (allLicenseKeys.size > 0) {
            const licenseElements = Array.from(allLicenseKeys).map(k => {
                const isActive = data.licenses && data.licenses[k] === true;
                const isSuspended = suspensions[k] !== undefined && suspensions[k] !== null;
                const licenseType = licenseMap[k] || k;
                const licData = JSON.stringify({ 
                    type: licenseType, 
                    key: k, 
                    citizenId: data.citizenId, 
                    citizenName: data.name,
                    isSuspended: isSuspended,
                    suspensionExpiry: isSuspended ? suspensions[k] : null
                });
                const licDataAttr = escapeJsAttr(licData);
                const licenseTypeHtml = escapeHtml(licenseType);
                
                if (isActive) {
                    return `<span class="license-badge" style="cursor:pointer;" onclick="openLicenseModal('${licDataAttr}')" title="Click to manage">${licenseTypeHtml}</span>`;
                } else if (isSuspended) {
                    return `<span class="license-badge" style="cursor:pointer; opacity:0.5; border-color: rgba(239,68,68,0.5);" onclick="openLicenseModal('${licDataAttr}')" title="Suspended - Click to manage">🚫 ${licenseTypeHtml}</span>`;
                }
                return '';
            }).filter(Boolean);
            licenses = licenseElements.length > 0 ? licenseElements.join('') : '<span class="license-badge">None</span>';
        } else {
            licenses = '<span class="license-badge">None</span>';
        }
        const notes = (data.notes || []).map(n => `<div class="note-row"><div>${escapeHtml(n.text)}</div><div style="font-size:11px;color:rgba(255,255,255,0.6)">${escapeHtml(n.author||'')} • ${escapeHtml(n.createdAt||'')}</div></div>`).join('') || '<div class="empty-message">No notes</div>';

        const propertiesHtml = properties.length
            ? properties.map(p => {
                const src = escapeHtml(String(p.source || 'property'));
                const nm = escapeHtml(String(p.name || 'Unknown'));
                const addr = escapeHtml(String(p.address || p.name || 'Unknown'));

                const coords = (p && p.coords && typeof p.coords === 'object') ? p.coords : null;
                const hasCoords = !!(coords && typeof coords.x === 'number' && typeof coords.y === 'number');
                const coordsPayload = hasCoords ? encodeURIComponent(JSON.stringify({ x: coords.x, y: coords.y, z: (typeof coords.z === 'number' ? coords.z : 0) })) : '';

                const gpsBtn = hasCoords
                    ? `<button class="btn small" onclick="event.stopPropagation(); sendCallback('setWaypoint', { coords: JSON.parse(decodeURIComponent('${coordsPayload}')) });">Set GPS</button>`
                    : `<button class="btn small" style="opacity:0.55; cursor:not-allowed;" onclick="event.stopPropagation(); showToast('No GPS location available for this property', 'info');">Set GPS</button>`;

                return `
                    <div class="citizen-asset-row">
                        <div class="citizen-asset-main">
                            <div class="citizen-asset-name">${nm}</div>
                            <div class="citizen-asset-meta">${addr}</div>
                            <div class="citizen-asset-meta" style="margin-top:2px;">Source: ${src}</div>
                        </div>
                        <div class="citizen-asset-actions">${gpsBtn}</div>
                    </div>
                `;
            }).join('')
            : '<div class="empty-message">No properties found</div>';

        const insurancePanelEnabled = data.insurancePanelEnabled === true;
        const insuranceActive = !!(data.insurance && data.insurance.active);
        const insuranceLabel = (data.insurance && (data.insurance.label || data.insurance.provider)) ? String(data.insurance.label || data.insurance.provider) : '';
        const insuranceExpiresAt = (data.insurance && data.insurance.expiresAt) ? String(data.insurance.expiresAt) : '';
        const insuranceHtml = insuranceActive
            ? `
                <div class="citizen-insurance-card">
                    <div class="citizen-insurance-title">Active Insurance</div>
                    <div class="citizen-insurance-line"><span class="citizen-ins-k">Plan</span><span class="citizen-ins-v">${escapeHtml(insuranceLabel || 'Active')}</span></div>
                    <div class="citizen-insurance-line"><span class="citizen-ins-k">Expires</span><span class="citizen-ins-v">${escapeHtml(insuranceExpiresAt || 'Unknown')}</span></div>
                </div>
            `
            : `
                <div class="citizen-insurance-card">
                    <div class="citizen-insurance-title">Insurance</div>
                    <div class="citizen-insurance-muted">No active insurance</div>
                </div>
            `;
        
        // Warrants list
        const warrantsHtml = (data.warrants || []).length > 0 
            ? (data.warrants || []).map(w => {
                // Escape data for inline handler to avoid breaking attributes
                const escAttr = (s) => escapeJsAttr(s); // JS-string + HTML-attribute safe (see app.js)
                const chargesPayload = encodeURIComponent(JSON.stringify(w.charges || []));
                const officersPayload = encodeURIComponent(JSON.stringify(w.officers || []));
                const witnessesPayload = encodeURIComponent(JSON.stringify(w.witnesses || []));
                const rawNarrative = w.narrative || '';
                const cleanNarrative = (() => {
                    if (rawNarrative.indexOf('[TITLE]') === 0) {
                        const nl = rawNarrative.indexOf('\n');
                        return nl >= 0 ? rawNarrative.substring(nl + 1) : '';
                    }
                    return rawNarrative;
                })();
                const detailsBtn = `<button class=\"btn\" onclick=\"event.stopPropagation(); openWarrantDetails('${escAttr(w.warrantId)}','${escAttr(w.issuedBy)}','${escAttr(w.createdAt)}','${escAttr(cleanNarrative)}', decodeURIComponent('${escAttr(chargesPayload)}'), '${escAttr(w.status)}','${escAttr(w.suspectName || data.name)}','${escAttr(w.title || '')}', decodeURIComponent('${escAttr(officersPayload)}'), decodeURIComponent('${escAttr(witnessesPayload)}'));\">Details</button>`;
                const actions = w.status === 'active' ? `
                    <div style=\"display:flex; gap:8px; margin-top:8px;\">
                        <button class=\"btn success\" onclick=\"event.stopPropagation(); sendCallback('updateWarrantStatus', { warrantId: '${escAttr(w.warrantId)}', status: 'served', citizenId: '${escAttr(data.citizenId)}' }); setTimeout(()=>sendCallback('openCitizen', { citizenId: '${escAttr(data.citizenId)}' }), 300);\">Mark as Served</button>
                        <button class=\"btn danger\" onclick=\"event.stopPropagation(); sendCallback('updateWarrantStatus', { warrantId: '${escAttr(w.warrantId)}', status: 'removed', citizenId: '${escAttr(data.citizenId)}' }); setTimeout(()=>sendCallback('openCitizen', { citizenId: '${escAttr(data.citizenId)}' }), 300);\">Remove</button>
                        ${detailsBtn}
                    </div>` : `<div style=\"margin-top:8px;\">${detailsBtn}</div>`;
                const warrantDisplay = w.warrantId;
                return `
                <div class=\"warrant-item\" style=\"padding: 12px; background: rgba(255,255,255,0.03); border-radius: 6px; margin-bottom: 8px;\">
                    <div style=\"display: flex; justify-content: space-between; margin-bottom: 8px;\">
                        <span style=\"font-weight: bold;\">${escapeHtml(warrantDisplay)}</span>
                        <span class=\"status-badge ${w.status === 'active' ? 'warrant-active' : 'status-other'}\">${escapeHtml(w.status)}</span>
                    </div>
                    <div style=\"font-size: 12px; color: rgba(255,255,255,0.7); margin-bottom: 8px;\">
                        Issued by: ${escapeHtml(w.issuedBy)} • ${escapeHtml(formatDateTime(w.createdAt))}
                    </div>
                    <div style=\"display: flex; gap: 6px; flex-wrap: wrap;\">
                        ${(w.charges || []).map(c => `<span class=\"charge-chip\">${escapeHtml(c)}</span>`).join('')}
                    </div>
                    ${cleanNarrative ? `<div style=\"margin-top: 8px; font-size: 12px; font-style: italic; color: rgba(255,255,255,0.6);\">${escapeHtml(cleanNarrative)}</div>` : ''}
                    ${actions}
                </div>`;
            }).join('')
            : '<div class=\"empty-message\">No warrants</div>';
        
        // Vehicles list
        const vehiclesHtml = (data.vehicles || []).length > 0
            ? (data.vehicles || []).map(v => {
                const isHashLike = (val) => {
                    const s = String(val ?? '').trim();
                    if (!s) return false;
                    if (/^0x[0-9a-f]+$/i.test(s)) return true;
                    if (/^[+-]?\d+(?:\.0+)?$/.test(s)) return true;
                    return false;
                };

                const name = 
                    (v.modelLabel && v.modelLabel !== 'NULL' && v.modelLabel.trim() && !isHashLike(v.modelLabel)) ? v.modelLabel :
                    (v.model && String(v.model).trim() && !isHashLike(v.model)) ? v.model :
                    `Unknown Model (${v.plate})`;
                const brand = v.brand && v.brand.trim() ? v.brand : null;
                const displayName = brand ? `${brand} ${name}` : name;
                // Color chips from mods.color1 / mods.color2
                const pInfo = getColorInfo(v.primaryColorId);
                const sInfo = getColorInfo(v.secondaryColorId);
                const colorDisplay = `<div style="display:flex; align-items:center; gap:6px;"><div title="Primary: ${escapeHtml(pInfo.name)}" style="width:12px;height:12px;border-radius:2px;border:1px solid rgba(255,255,255,0.35); background:${escapeHtml(pInfo.hex)}"></div><div title="Secondary: ${escapeHtml(sInfo.name)}" style="width:12px;height:12px;border-radius:2px;border:1px solid rgba(255,255,255,0.35); background:${escapeHtml(sInfo.hex)}"></div></div>`;
                return `
                    <div class="vehicle-item" style="padding: 12px; background: rgba(255,255,255,0.03); border-radius: 6px; margin-bottom: 8px; display: flex; justify-content: space-between; align-items: center;">
                        <div>
                            <div style="font-weight: bold;">${escapeHtml(displayName)}</div>
                            <div style="font-size: 12px; color: rgba(255,255,255,0.7); display: flex; align-items: center; gap: 8px;">Plate: ${escapeHtml(v.plate)} • ${colorDisplay}</div>
                        </div>
                        <button class="btn small" onclick="event.stopPropagation(); router.openVehicleProfile('${escapeJsAttr(v.plate || '')}');">View</button>
                    </div>
                `;
            }).join('')
            : '<div class="empty-message">No vehicles</div>';
        
        // Incidents list
        const incidentsHtml = (data.incidents || []).length > 0
            ? (data.incidents || []).map(i => `
                <div class="incident-item" onclick="openIncidentDetails('${escapeJsAttr(i.incidentId)}')" style="cursor:pointer; padding: 12px; background: rgba(255,255,255,0.03); border-radius: 6px; margin-bottom: 8px;">
                    <div style="display: flex; justify-content: space-between; margin-bottom: 4px;">
                        <span style="font-weight: bold;">${escapeHtml(i.incidentId)}</span>
                        <span class="status-badge">${escapeHtml(i.status || 'active')}</span>
                    </div>
                    <div style="font-size: 14px; margin-bottom: 4px;">${escapeHtml(i.title || '')}</div>
                    <div style="font-size: 12px; color: rgba(255,255,255,0.6);">
                        ${escapeHtml(i.location || 'Unknown location')} • ${escapeHtml(formatDateTime(i.createdAt))}
                    </div>
                </div>
            `).join('')
            : '<div class="empty-message">No incidents</div>';
        
        // Reports list
        const reportsHtml = (data.reports || []).length > 0
            ? (data.reports || []).map(r => `
                <div class="report-item" style="padding: 12px; background: rgba(255,255,255,0.03); border-radius: 6px; margin-bottom: 8px;">
                    <div style="display: flex; justify-content: space-between; margin-bottom: 4px;">
                        <span style="font-weight: bold;">${escapeHtml(r.reportId)}</span>
                        <span class="status-badge">${escapeHtml(r.type)}</span>
                    </div>
                    <div style="font-size: 14px; margin-bottom: 4px;">${escapeHtml(r.title)}</div>
                    <div style="font-size: 12px; color: rgba(255,255,255,0.6);">
                        Officer: ${escapeHtml(r.officer)} • ${escapeHtml(r.createdAt)}
                    </div>
                </div>
            `).join('')
            : '<div class="empty-message">No reports</div>';
        
        content.innerHTML = `
            <div data-view="c-overview">
                <h4 style="margin-bottom: 12px;">Personal Information</h4>
                <div style="display: grid; grid-template-columns: repeat(2, 1fr); gap: 12px; margin-bottom: 20px;">
                    <div class="info-row"><span class="label">Full Name:</span> <span>${escapeHtml(data.name)}</span></div>
                    <div class="info-row"><span class="label">Citizen ID:</span> <span>${escapeHtml(data.citizenId)}</span></div>
                    <div class="info-row"><span class="label">Date of Birth:</span> <span>${escapeHtml(data.dob)}</span></div>
                    <div class="info-row"><span class="label">Age:</span> <span>${typeof data.age === 'number' && data.age >= 0 ? escapeHtml(data.age) : 'N/A'}</span></div>
                    <div class="info-row"><span class="label">Gender:</span> <span>${escapeHtml(data.gender || 'Unknown')}</span></div>
                    <div class="info-row"><span class="label">Nationality:</span> <span>${escapeHtml(data.nationality || 'Unknown')}</span></div>
                    <div class="info-row"><span class="label">Phone:</span> <span>${escapeHtml(data.phone || 'N/A')}</span></div>
                    <div class="info-row"><span class="label">Job:</span> <span>${escapeHtml(data.job || 'Unemployed')}</span></div>
                </div>
                
                <h4 style="margin-bottom: 12px;">Physical Appearance</h4>
                <div style="display: grid; grid-template-columns: repeat(2, 1fr); gap: 12px; margin-bottom: 20px;">
                    <div class="info-row"><span class="label">Skin Tone:</span> <span>${escapeHtml(skinToneLabel)}</span></div>
                    <div class="info-row"><span class="label">Hair Color:</span> <span>${escapeHtml(hairColorLabel)}</span></div>
                    <div class="info-row"><span class="label">Eye Color:</span> <span>${escapeHtml(eyeColorLabel)}</span></div>
                    <div class="info-row"><span class="label">Hair Highlight:</span> <span>${escapeHtml(hairHighlightLabel || 'Not recorded')}</span></div>
                    <div class="info-row"><span class="label">Gender:</span> <span>${escapeHtml(genderLabel)}</span></div>
                </div>
                
                <h4 style="margin-bottom: 12px;">Address</h4>
                <div style="margin-bottom: 20px;">
                    <div class="info-row" style="margin-bottom: 10px;"><span>${escapeHtml(displayAddress)}</span></div>
                    ${propAddrList.length ? `
                        <div style="padding: 12px; background: rgba(255,255,255,0.03); border-radius: 6px;">
                            <div style="font-size: 12px; color: rgba(255,255,255,0.65); margin-bottom: 8px;">Properties</div>
                            ${propAddrList.map(a => `<div style="font-size: 12px; color: rgba(255,255,255,0.85); padding: 4px 0; border-top: 1px solid rgba(255,255,255,0.06);">${escapeHtml(a)}</div>`).join('')}
                        </div>
                    ` : ''}
                </div>
            </div>

            <div data-view="c-assets" style="display:none;">
                <h4 style="margin-bottom: 12px;">Assets</h4>

                <div class="citizen-asset-card">
                    <div class="citizen-asset-card-title">Properties (${properties.length})</div>
                    <div>${propertiesHtml}</div>
                </div>
            </div>

            <div data-view="c-insurance" style="display:none;">
                <h4 style="margin-bottom: 12px;">Insurance</h4>
                ${insuranceHtml}
            </div>
            
            <div data-view="c-licenses" style="display:none;">
                <h4 style="margin-bottom: 12px;">Active Licenses</h4>
                <div style="display:flex; gap:8px; flex-wrap:wrap;">${licenses}</div>
            </div>
            
            <div data-view="c-warrants" style="display:none;">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px;">
                    <h4>Warrants (${(data.warrants || []).length})</h4>
                    <button class="btn primary" onclick="openNewWarrantForCitizen('${escapeJsAttr(data.citizenId)}', '${escapeJsAttr(data.name||'')}')">Create Warrant</button>
                </div>
                ${warrantsHtml}
            </div>

            <div data-view="c-sentences" style="display:none;">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px;">
                    <h4>Sentencing History</h4>
                    <button class="btn primary" id="openNewSentenceBtn">New Sentence</button>
                </div>
                <div id="citizenSentencesList"><div class="empty-message">Loading...</div></div>
            </div>
            
            <div data-view="c-vehicles" style="display:none;">
                <h4 style="margin-bottom: 12px;">Owned Vehicles (${escapeHtml(data.vehicleCount)})</h4>
                ${vehiclesHtml}
            </div>

            <div data-view="c-weapons" style="display:none;">
                <h4 style="margin-bottom: 12px;">Registered Weapons (<span id="citizenWeaponsCount">0</span>)</h4>
                <div id="citizenWeaponsList"><div class="empty-message">Loading...</div></div>
            </div>
            
            <div data-view="c-incidents" style="display:none;">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px;">
                    <h4 style="margin: 0;">Incidents Involving Citizen (${(data.incidents || []).length})</h4>
                    <span style="font-size:12px; color: rgba(255,255,255,0.6);">Read-only</span>
                </div>
                ${incidentsHtml}
            </div>
            
            <div data-view="c-reports" style="display:none;">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px;">
                    <h4 style="margin: 0;">Reports (${(data.reports || []).length})</h4>
                    <button class="btn primary" onclick="openNewReportForCitizen('${escapeJsAttr(data.citizenId)}', '${escapeJsAttr(data.name||'')}')">+ Create Report</button>
                </div>
                ${reportsHtml}
            </div>
            
            <div data-view="c-notes" style="display:none;">
                <div class="form-inline" style="margin-bottom:12px;">
                    <textarea id="cNoteInput" placeholder="Add an officer note..."></textarea>
                    <button class="btn primary" id="cNoteAddBtn">Add Note</button>
                </div>
                <h4 style="margin-bottom: 12px;">Officer Notes (${(data.notes || []).length})</h4>
                <div id="cNotesList">${notes}</div>
            </div>
            
            <div data-view="c-flags" style="display:none;">
                <div class="form-inline" style="margin-bottom:12px;">
                    <input id="cFlagInput" placeholder="Add a flag (e.g. Dangerous, BOLO)" />
                    <button class="btn primary" id="cFlagAddBtn">Add Flag</button>
                </div>
                <h4 style="margin-bottom: 12px;">Status Flags (${(data.flags || []).length})</h4>
                <div id="cFlagsList">${flags}</div>
            </div>
        `;

        // Weapons tab: load registered weapons for this citizen
        renderCitizenWeaponsList(data.citizenId);

        // Sentences tab: load on render
        try {
            const listEl = document.getElementById('citizenSentencesList');
            if (listEl) listEl.innerHTML = '<div class="empty-message">Loading...</div>';
            sendCallback('getCitizenSentences', { citizenId: data.citizenId }, (res) => {
                const el = document.getElementById('citizenSentencesList');
                if (!el) return;
                const items = (res && res.success && Array.isArray(res.sentences)) ? res.sentences : [];
                const activeJail = (res && res.activeJail) ? res.activeJail : null;
                if (!items.length) {
                    el.innerHTML = '<div class="empty-message">No prior sentencing</div>';
                    return;
                }
                const badge = (t) => {
                    const type = String(t || '').toLowerCase();
                    if (type === 'fine') return '<span class="status-badge" style="background: rgba(59,130,246,0.2); border:1px solid rgba(59,130,246,0.35);">Fine</span>';
                    if (type === 'sentence') return '<span class="status-badge" style="background: rgba(245,158,11,0.2); border:1px solid rgba(245,158,11,0.35);">Sentence</span>';
                    return '<span class="status-badge" style="background: rgba(16,185,129,0.18); border:1px solid rgba(16,185,129,0.35);">Fine + Sentence</span>';
                };
                el.innerHTML = items.map(s => {
                    const when = s.createdAt ? escapeHtml(formatDateTime(s.createdAt)) : '';
                    const title = escapeHtml(s.title || 'Sentence');
                    const officer = escapeHtml(s.officerName || 'Officer');
                    const fine = Number(s.fineAmount || 0);
                    const time = Number(s.prisonTime || 0);
                    const desc = escapeHtml(s.description || '');
                    const err = s.error ? `<div style="margin-top:6px; font-size:12px; color:#ff6b6b;">${escapeHtml(s.error)}</div>` : '';
                    const totalsLine = `<div style="font-size:12px; color: rgba(255,255,255,0.7); margin-top:6px;">${fine > 0 ? `Fine: $${fine.toLocaleString()}` : ''}${(fine>0 && time>0) ? ' • ' : ''}${time > 0 ? `Time: ${time} months` : ''}</div>`;

                    const isActive = !!(activeJail && activeJail.active);
                    const activeId = activeJail && activeJail.sentenceId != null ? Number(activeJail.sentenceId) : null;
                    const rowId = s.id != null ? Number(s.id) : null;
                    const match = (activeId != null && rowId != null) ? (activeId === rowId) : false;
                    const showBail = isActive && (match || (activeId == null && items[0] === s)) && Number(activeJail?.bailAmount || 0) > 0;
                    const bailBtn = showBail
                        ? `<button class="btn" style="margin-top:6px;" onclick="openPostBailModal('${escapeJsAttr(data.citizenId)}', '${escapeJsAttr(data.name||'')}', ${Number(rowId) || 'null'}, ${Number(activeJail.bailAmount || 0)})">Bail</button>`
                        : '';
                    return `
                        <div style="padding: 12px; background: rgba(255,255,255,0.03); border-radius: 6px; margin-bottom: 8px;">
                            <div style="display:flex; justify-content:space-between; align-items:center; gap:10px;">
                                <div style="font-weight:700;">${title}</div>
                                <div style="display:flex; flex-direction:column; align-items:flex-end;">
                                    ${badge(s.sentenceType)}
                                    ${bailBtn}
                                </div>
                            </div>
                            <div style="font-size: 12px; color: rgba(255,255,255,0.6); margin-top:4px;">${officer}${when ? ` • ${when}` : ''}</div>
                            ${totalsLine}
                            ${desc ? `<div style="margin-top:8px; font-size:12px; color: rgba(255,255,255,0.65);">${desc}</div>` : ''}
                            ${err}
                        </div>
                    `;
                }).join('');
            });
        } catch (_) {}
        
        // Tabs
        const header = modal.querySelector('.tabs');
        if (header){
            header.querySelectorAll('.tab').forEach(btn => btn.onclick = () => setActiveTab(modal, 'c-', btn.dataset.tab));
            setActiveTab(modal, 'c-', 'c-overview');
        }
        
        // Actions
        document.getElementById('cNoteAddBtn')?.addEventListener('click', () => {
            const txt = document.getElementById('cNoteInput').value.trim(); if (!txt) return;
            sendCallback('addCitizenNote', { citizenId: data.citizenId, text: txt });
            document.getElementById('cNoteInput').value = '';
            sendCallback('openCitizen', { citizenId: data.citizenId });
        });
        document.getElementById('cFlagAddBtn')?.addEventListener('click', () => {
            const flag = document.getElementById('cFlagInput').value.trim(); if (!flag) return;
            sendCallback('addCitizenFlag', { citizenId: data.citizenId, flag });
            document.getElementById('cFlagInput').value = '';
            sendCallback('openCitizen', { citizenId: data.citizenId });
        });
        
        // Report button only; incidents tab is read-only
        const reportBtn = modal?.querySelector('[onclick*="openNewReportForCitizen"]');
        if (reportBtn) {
            reportBtn.onclick = () => openNewReportForCitizen(data.citizenId, data.name);
        }

        // New Sentence button
        const newSentenceBtn = document.getElementById('openNewSentenceBtn');
        if (newSentenceBtn) {
            newSentenceBtn.onclick = () => window.openNewSentenceForCitizen(data.citizenId, data.name);
        }
    }

    // ==========================
    // Sentencing UI helpers
    // ==========================
    window.__selectedSentenceCharges = [];
    window.__selectedSentenceReductions = [];
    window.__sentenceType = 'sentence';

    function setSentenceType(t) {
        window.__sentenceType = t;
        const fineBtn = document.getElementById('sentenceTypeFine');
        const jailBtn = document.getElementById('sentenceTypeJail');
        const bothBtn = document.getElementById('sentenceTypeBoth');
        if (fineBtn) fineBtn.classList.toggle('primary', t === 'fine');
        if (jailBtn) jailBtn.classList.toggle('primary', t === 'sentence');
        if (bothBtn) bothBtn.classList.toggle('primary', t === 'fine+sentence');
        const exec = document.getElementById('sentenceExecuteBtn');
        if (exec) exec.textContent = (t === 'fine') ? 'Fine' : (t === 'sentence' ? 'Sentence' : 'Fine + Sentence');
        recalcSentenceTotals();
    }

    function loadSentenceChargesOptions() {
        const sel = document.getElementById('sentenceChargeSelect');
        if (!sel) return;
        sel.innerHTML = '<option value="">Select a charge...</option>';
        try {
            sendCallback('mdt:getAllCharges', {}, (charges) => {
                const list = Array.isArray(charges) ? charges : (Array.isArray(charges?.charges) ? charges.charges : []);
                list.forEach(ch => {
                    const opt = document.createElement('option');
                    opt.value = ch.code || ch.id || ch.name;
                    opt.setAttribute('data-name', ch.name || ch.code || '');
                    opt.setAttribute('data-fine', ch.fineAmount != null ? ch.fineAmount : (ch.fine_amount != null ? ch.fine_amount : 0));
                    opt.setAttribute('data-time', ch.prisonTime != null ? ch.prisonTime : (ch.jail_time != null ? ch.jail_time : 0));
                    opt.textContent = ch.code ? `${ch.code} - ${ch.name || ch.code}` : (ch.name || 'Unknown');
                    sel.appendChild(opt);
                });
            });
        } catch (e) {
            console.error('[SENTENCE] Failed to load charges', e);
        }
    }

    window.addSentenceCharge = function() {
        const sel = document.getElementById('sentenceChargeSelect');
        const code = sel?.value?.trim() || '';
        if (!code) return;
        const opt = sel.selectedOptions?.[0];
        const name = opt?.getAttribute('data-name') || opt?.textContent || '';
        const fine = Number(opt?.getAttribute('data-fine') || 0);
        const time = Number(opt?.getAttribute('data-time') || 0);
        if (!window.__selectedSentenceCharges) window.__selectedSentenceCharges = [];
        if (window.__selectedSentenceCharges.some(c => c.code === code)) { sel.value = ''; return; }
        window.__selectedSentenceCharges.push({ code, name, fineAmount: fine, prisonTime: time });
        sel.value = '';
        renderSentenceCharges();
        recalcSentenceTotals();
    }

    window.removeSentenceCharge = function(code) {
        if (!window.__selectedSentenceCharges) window.__selectedSentenceCharges = [];
        window.__selectedSentenceCharges = window.__selectedSentenceCharges.filter(c => c.code !== code);
        renderSentenceCharges();
        recalcSentenceTotals();
    }

    function renderSentenceCharges() {
        const list = document.getElementById('sentenceChargesList');
        if (!list) return;
        const arr = window.__selectedSentenceCharges || [];
        list.innerHTML = arr.length ? arr.map(c => `
            <div class="chip" style="display:inline-block; padding: 6px 12px; border-radius: 20px; background: rgba(255, 100, 100, 0.2); border: 1px solid rgba(255, 100, 100, 0.4); margin: 4px; cursor: pointer;">
                ⚖️ ${escapeHtml(c.code)} - ${escapeHtml(c.name)}
                <span onclick="removeSentenceCharge('${escapeJsAttr(c.code)}')" style="margin-left: 8px; cursor: pointer; opacity: 0.7;">✕</span>
            </div>
        `).join('') : '<div style="color: rgba(255,255,255,0.5); font-size: 12px;">No charges added</div>';
    }

    function renderSentenceReductions() {
        const wrap = document.getElementById('sentenceReductions');
        if (!wrap) return;
        const reductions = (window.mdtConfig && window.mdtConfig.sentencing && Array.isArray(window.mdtConfig.sentencing.reductions)) ? window.mdtConfig.sentencing.reductions : [];
        if (!reductions.length) {
            wrap.innerHTML = '<div style="color: rgba(255,255,255,0.5); font-size: 12px;">No reductions configured</div>';
            return;
        }
        wrap.innerHTML = reductions.map(r => {
            const key = escapeHtml(r.key || '');
            const label = escapeHtml(r.label || r.key || '');
            const pct = Number(r.percent || 0);
            return `
                <label style="display:flex; gap:10px; align-items:center; font-size: 13px;">
                    <input type="checkbox" data-reduction-key="${key}" data-reduction-percent="${pct}" />
                    <span>${label} (-${pct}%)</span>
                </label>
            `;
        }).join('');

        wrap.querySelectorAll('input[type="checkbox"]').forEach(cb => {
            cb.addEventListener('change', () => {
                const selected = [];
                wrap.querySelectorAll('input[type="checkbox"]:checked').forEach(x => selected.push(x.getAttribute('data-reduction-key')));
                window.__selectedSentenceReductions = selected;
                recalcSentenceTotals();
            });
        });
    }

    function recalcSentenceTotals() {
        const charges = window.__selectedSentenceCharges || [];
        const type = window.__sentenceType || 'sentence';
        const totalFineRaw = charges.reduce((s, c) => s + (Number(c.fineAmount) || 0), 0);
        const totalTimeRaw = charges.reduce((s, c) => s + (Number(c.prisonTime) || 0), 0);

        const fineEl = document.getElementById('sentenceTotalFine');
        const timeEl = document.getElementById('sentenceTotalTime');
        const reducedEl = document.getElementById('sentenceReducedTime');

        const reductions = (window.mdtConfig && window.mdtConfig.sentencing && Array.isArray(window.mdtConfig.sentencing.reductions)) ? window.mdtConfig.sentencing.reductions : [];
        const selectedKeys = window.__selectedSentenceReductions || [];
        let pct = 0;
        selectedKeys.forEach(k => {
            const found = reductions.find(r => r.key === k);
            if (found) pct += Number(found.percent || 0);
        });
        if (pct > 100) pct = 100;
        const reducedTime = Math.floor(totalTimeRaw * (1 - (pct / 100)));

        const showFine = (type === 'fine' || type === 'fine+sentence');
        const showTime = (type === 'sentence' || type === 'fine+sentence');

        if (fineEl) fineEl.textContent = showFine ? `$${totalFineRaw.toLocaleString()}` : '$0';
        if (timeEl) timeEl.textContent = showTime ? `${totalTimeRaw} months` : '0 months';
        if (reducedEl) reducedEl.textContent = showTime ? `${reducedTime} months` : '0 months';
    }

    window.openNewSentenceForCitizen = function(citizenId, citizenName) {
        const modal = document.getElementById('newSentenceModal');
        if (!modal) return;
        modal.classList.remove('hidden');

        document.getElementById('sentenceCitizenId').value = citizenId || '';
        document.getElementById('sentenceCitizenName').value = citizenName || '';
        const t = document.getElementById('sentenceTitleInput');
        const d = document.getElementById('sentenceDescriptionInput');
        if (t) t.value = '';
        if (d) d.value = '';

        window.__selectedSentenceCharges = [];
        window.__selectedSentenceReductions = [];
        window.__sentenceType = 'sentence';

        renderSentenceCharges();
        loadSentenceChargesOptions();
        renderSentenceReductions();
        setSentenceType('sentence');

        const fineBtn = document.getElementById('sentenceTypeFine');
        const jailBtn = document.getElementById('sentenceTypeJail');
        const bothBtn = document.getElementById('sentenceTypeBoth');
        if (fineBtn) fineBtn.onclick = () => setSentenceType('fine');
        if (jailBtn) jailBtn.onclick = () => setSentenceType('sentence');
        if (bothBtn) bothBtn.onclick = () => setSentenceType('fine+sentence');

        const execBtn = document.getElementById('sentenceExecuteBtn');
        if (execBtn) {
            // Prevent stacked handlers
            const clone = execBtn.cloneNode(true);
            execBtn.parentNode.replaceChild(clone, execBtn);
            clone.onclick = () => {
                const cid = document.getElementById('sentenceCitizenId').value;
                const cname = document.getElementById('sentenceCitizenName').value;
                const title = document.getElementById('sentenceTitleInput').value.trim();
                const description = document.getElementById('sentenceDescriptionInput').value.trim();
                const charges = (window.__selectedSentenceCharges || []).map(c => c.code);
                const reductions = window.__selectedSentenceReductions || [];
                const sentenceType = window.__sentenceType || 'sentence';
                if (!title) { if (typeof mdtToast === 'function') mdtToast('Title is required', 'error'); return; }
                if (!charges.length) { if (typeof mdtToast === 'function') mdtToast('Select at least one charge', 'error'); return; }

                sendCallback('createSentence', { citizenId: cid, citizenName: cname, title, description, sentenceType, charges, reductions }, (res) => {
                    if (res && res.success) {
                        modal.classList.add('hidden');
                        sendCallback('openCitizen', { citizenId: cid });
                    } else {
                        if (typeof mdtToast === 'function') mdtToast(res?.error || 'Failed to sentence', 'error');
                    }
                });
            };
        }
    }

    // ==========================
    // Bail UI helpers
    // ==========================
    window.openPostBailModal = function(prisonerCitizenId, prisonerName, sentenceId, bailAmount) {
        const modal = document.getElementById('postBailModal');
        if (!modal) return;

        const prisonerIdEl = document.getElementById('bailPrisonerCitizenId');
        const sentenceIdEl = document.getElementById('bailSentenceId');
        const prisonerNameEl = document.getElementById('bailPrisonerName');
        const bailAmountEl = document.getElementById('bailAmountDisplay');
        const payerSel = document.getElementById('bailPayerSelect');

        if (prisonerIdEl) prisonerIdEl.value = prisonerCitizenId || '';
        if (sentenceIdEl) sentenceIdEl.value = (sentenceId != null ? String(sentenceId) : '');
        if (prisonerNameEl) prisonerNameEl.textContent = prisonerName || prisonerCitizenId || 'Prisoner';
        if (bailAmountEl) bailAmountEl.textContent = `$${Number(bailAmount || 0).toLocaleString()}`;

        if (payerSel) {
            payerSel.innerHTML = '<option value="">Select a player...</option>';
            sendCallback('getAllPlayers', {}, (list) => {
                const arr = Array.isArray(list) ? list : [];
                arr.forEach(p => {
                    const opt = document.createElement('option');
                    opt.value = p.citizenid || '';
                    opt.textContent = `${p.name || p.citizenid || 'Player'}${p.citizenid ? ` (${p.citizenid})` : ''}`;
                    payerSel.appendChild(opt);
                });
            });
        }

        const confirmBtn = document.getElementById('postBailConfirmBtn');
        if (confirmBtn) {
            confirmBtn.onclick = () => {
                const payerCitizenId = payerSel ? payerSel.value : '';
                if (!payerCitizenId) {
                    if (typeof mdtToast === 'function') {
                        mdtToast('Select a player to charge bail to.', 'error');
                    }
                    return;
                }
                confirmBtn.disabled = true;
                sendCallback('postBail', {
                    prisonerCitizenId,
                    sentenceId: sentenceId != null ? Number(sentenceId) : null,
                    payerCitizenId
                }, (resp) => {
                    confirmBtn.disabled = false;
                    if (resp && resp.success) {
                        modal.classList.add('hidden');
                        if (typeof mdtToast === 'function') {
                            mdtToast('Bail posted', 'success');
                        }
                        sendCallback('openCitizen', { citizenId: prisonerCitizenId });
                    } else {
                        if (typeof mdtToast === 'function') {
                            mdtToast((resp && resp.error) ? String(resp.error) : 'Failed to post bail', 'error');
                        }
                    }
                });
            };
        }

        modal.classList.remove('hidden');
    };

    // Open details modal for a warrant
    window.openWarrantDetails = function(warrantId, issuedBy, createdAt, narrative, chargesEncoded, status, suspectName, title, officersEncoded, witnessesEncoded){
        if (typeof mdtToast === 'function') mdtToast('This feature is not available in EMS MDT', 'error');
        return;
        const modal = document.getElementById('warrantDetailsModal');
        const body = document.getElementById('warrantDetailsBody');
        if (!modal || !body) return;
        let desc = (narrative || '').replace(/\n/g, '\n');
        if (desc && desc.indexOf('[TITLE]') === 0) {
            const nl = desc.indexOf('\n');
            desc = nl >= 0 ? desc.substring(nl + 1) : '';
        }
        let charges = [];
        if (Array.isArray(chargesEncoded)) {
            charges = chargesEncoded;
        } else if (typeof chargesEncoded === 'string') {
            try {
                charges = JSON.parse(chargesEncoded);
            } catch (_) {
                charges = [];
            }
        }
        let officers = [];
        if (Array.isArray(officersEncoded)) {
            officers = officersEncoded;
        } else if (typeof officersEncoded === 'string') {
            try { officers = JSON.parse(officersEncoded); } catch (_) { officers = []; }
        }
        let witnesses = [];
        if (Array.isArray(witnessesEncoded)) {
            witnesses = witnessesEncoded;
        } else if (typeof witnessesEncoded === 'string') {
            try { witnesses = JSON.parse(witnessesEncoded); } catch (_) { witnesses = []; }
        }
        // (warrants are not supported in EMS MDT)
        const st = String(status || '').toLowerCase();
        const statusClass = st === 'active' ? 'warrant-active' : 'status-other';
        const formattedDate = createdAt ? formatDateTime(createdAt) : 'Unknown';
        body.innerHTML = `
            <div style="display:grid; grid-template-columns: 1fr 1fr; gap:12px; margin-bottom:12px;">
                <div><div style="font-size:11px;color:rgba(255,255,255,0.6)">Warrant Code</div><div style="font-weight:700;">${escapeHtml(warrantId)}</div></div>
                <div><div style="font-size:11px;color:rgba(255,255,255,0.6)">Officer</div><div>${escapeHtml(issuedBy||'Unknown')}</div></div>
                <div><div style="font-size:11px;color:rgba(255,255,255,0.6)">Date Filed</div><div>${escapeHtml(formattedDate)}</div></div>
                <div><div style="font-size:11px;color:rgba(255,255,255,0.6)">Suspect</div><div>${escapeHtml(suspectName||'Unknown')}</div></div>
                <div><div style="font-size:11px;color:rgba(255,255,255,0.6)">Status</div><div><span class="status-badge ${statusClass}">${escapeHtml(status||'')}</span></div></div>
            </div>
            ${title ? `<div style="margin-bottom:8px;"><div style=\"font-size:11px;color:rgba(255,255,255,0.6)\">Title</div><div style=\"font-weight:700\">${escapeHtml(title)}</div></div>` : ''}
            <div style="margin-bottom:8px;"><div style="font-size:11px;color:rgba(255,255,255,0.6)">Description</div><div>${escapeHtml(desc||'').replace(/\n/g,'<br/>')}</div></div>
            <div style="margin-bottom:8px;"><div style="font-size:11px;color:rgba(255,255,255,0.6)">Charges</div><div style="display:flex;gap:6px;flex-wrap:wrap;">${charges.map(c=>`<span class=\"charge-chip\">${escapeHtml(c)}</span>`).join('') || 'None'}</div></div>
            <div style="margin-bottom:8px;"><div style="font-size:11px;color:rgba(255,255,255,0.6)">Officers</div><div style="display:flex;gap:6px;flex-wrap:wrap;">${officers.map(o=>`<span class=\"charge-chip\">${escapeHtml(o)}</span>`).join('') || 'None'}</div></div>
            <div><div style="font-size:11px;color:rgba(255,255,255,0.6)">Witnesses</div><div style="display:flex;flex-direction:column;gap:6px; margin-top:6px;">
                ${witnesses.length ? witnesses.map(w => {
                    const witnessObj = typeof w === 'string' ? { name: w, phone: '', statement: '' } : w;
                    const name = escapeHtml(witnessObj.name || 'Unknown');
                    const stmt = escapeHtml(witnessObj.statement || '');
                    const statementHtml = stmt ? `<div style=\"font-size:12px; color:rgba(255,255,255,0.7); margin-top:4px; font-style:italic;\">${stmt}</div>` : '';
                    return `<div style=\"padding:8px; background:rgba(255,255,255,0.04); border-radius:6px;\"><div style=\"font-weight:600;\">${name}</div>${statementHtml}</div>`;
                }).join('') : 'None'}
            </div></div>
        `;
        modal.classList.remove('hidden');
    }

    // Pre-fill and open create warrant for a specific citizen
    window.openNewWarrantForCitizen = function(citizenId, name){
        openNewWarrantModal();
        const suspect = document.getElementById('warrantSuspectInput');
        if (suspect) suspect.value = name || '';
        
        // Store citizen ID for refresh after creation
        window.__currentCitizenIdForWarrant = citizenId;
        
        try {
            const code = 'W' + Math.floor(10000 + Math.random()*90000).toString();
            const officer = (window.userInfo && window.userInfo.name) ? window.userInfo.name : 'Officer';
            const codeEl = document.getElementById('warrantCodeInput'); if (codeEl) codeEl.value = code;
            const offEl = document.getElementById('warrantOfficerAuto'); if (offEl) offEl.value = officer;
        } catch(_) {}
    }

    function renderVehicleProfile(data){
        const modal = document.getElementById('vehicleProfileModal');
        if (!modal) {
            console.error('[MDT ERROR] vehicleProfileModal element not found in DOM!');
            console.log('[MDT DOM CHECK] All modals:', document.querySelectorAll('.modal').length);
            return;
        }
        
        // Ensure modal is visible
        modal.style.display = 'flex';
        modal.classList.remove('hidden');
        modal.style.zIndex = '10001';
        const titleEl = document.getElementById('vehicleProfileTitle');
        if (titleEl) titleEl.textContent = `${data.plate||''} • ${data.model||'Vehicle'}`;
        const content = document.getElementById('vehicleProfileContent');
        if (!content) return;

        const flagsArr = data.flags || [];
        const strikesArr = data.strikes || [];
        const activeStrikes = strikesArr.length;
        const riskText = activeStrikes >= 3 ? 'High' : (activeStrikes >= 1 ? 'Medium' : 'Clear');
        const riskClass = activeStrikes >= 3 ? 'warn' : (activeStrikes >= 1 ? 'info' : 'success');
        const points = activeStrikes * 4; // simple placeholder scoring
        const lastSeen = 'N/A'; // placeholder until we have telemetry

        const flags = flagsArr.map(f => `<span class="flag-chip">${escapeHtml(f)}</span>`).join('') || '<span class="flag-chip">None</span>';
        const notes = (data.notes || []).map(n => `<div class="note-row"><div>${escapeHtml(n.text)}</div><div style="font-size:11px;color:rgba(255,255,255,0.6)">${escapeHtml(n.author||'')} • ${escapeHtml(n.createdAt||'')}</div></div>`).join('') || '<div class="empty-message">No notes</div>';
        const strikes = strikesArr.map(s => `<div class="strike-row"><div>${escapeHtml(s.reason||'Strike')}</div><div style="font-size:11px;color:rgba(255,255,255,0.6)">${escapeHtml(s.createdAt||'')}</div></div>`).join('') || '<div class="empty-message">No strikes</div>';

        const statusCard = flagsArr.length === 0
            ? `<div style="padding:12px;border-radius:8px;border:1px solid rgba(255,255,255,0.08);background:rgba(76,175,80,0.08);color:#a5d6a7;">This vehicle has no active alerts or flags.</div>`
            : `<div style="padding:12px;border-radius:8px;border:1px solid rgba(255,255,255,0.08);background:rgba(255,179,71,0.08);color:#ffb347;">This vehicle has active alerts or flags.</div>`;

        content.innerHTML = `
            <div data-view="v-overview">
                <div style="display:grid; grid-template-columns: 340px 1fr; gap:16px; align-items:start;">
                    <div style="padding:16px; border-radius:10px; border:1px solid rgba(255,255,255,0.08); background:rgba(255,255,255,0.03);">
                        <div style="display:flex; flex-direction:column; align-items:center; gap:10px;">
                            <div style="width:120px;height:120px;border-radius:999px;background:${safeCssUrl(data.vehiclePhoto) ? escapeHtml(`url('${safeCssUrl(data.vehiclePhoto)}')`) : 'rgba(255,255,255,0.06)'};background-size:cover;background-position:center;display:flex;align-items:center;justify-content:center;">
                                ${safeCssUrl(data.vehiclePhoto) ? '' : '<svg width="60" height="60" viewBox="0 0 24 24" fill="none" stroke="#4dd0e1" stroke-width="2"><circle cx="18" cy="18" r="3"></circle><circle cx="6" cy="18" r="3"></circle><path d="M18 15h-12v-9h12z"></path></svg>'}
                            </div>
                            <button class="btn small" style="margin-top: 4px; width: 100%; font-size: 11px;" onclick="takeVehiclePhoto('${escapeJsAttr(data.plate)}')">📷 Take Photo</button>
                            <div style="font-size:22px;font-weight:700;">${escapeHtml(data.plate||'')}</div>
                            <div style="font-size:12px;color:rgba(255,255,255,0.7)">Owner: ${escapeHtml(data.ownerName||'')}</div>
                            <div style="font-size:12px;color:rgba(255,255,255,0.7)">Model: ${escapeHtml(data.model||'Vehicle')}</div>
                            <div style="font-size:12px;color:rgba(255,255,255,0.7)">Color: ${escapeHtml(data.color||'Unknown')}</div>
                            <div style="font-size:12px;color:rgba(255,255,255,0.7)">Last Seen: ${lastSeen}</div>
                        </div>
                    </div>
                    <div>
                        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px;">
                            <div>
                                <div style="font-size:24px;font-weight:700;">${escapeHtml(data.plate||'')}</div>
                                <div style="font-size:12px;color:rgba(255,255,255,0.7)">Owner: ${escapeHtml(data.ownerName||'')}</div>
                            </div>
                            <div style="display:flex; gap:8px; align-items:center;">
                                <span class="chip info">#${escapeHtml((data.plate||'').toString().slice(0,6))}</span>
                                <span class="chip ${riskClass}">${riskText}</span>
                                <button class="btn primary" id="vStrikeAddBtnHeader">Add Strike</button>
                            </div>
                        </div>
                        <div class="kpi-grid">
                            <div class="kpi-card"><div class="kpi-title">Total Points (Active)</div><div class="kpi-value">${points}</div></div>
                            <div class="kpi-card"><div class="kpi-title">Risk Level (Active)</div><div class="kpi-value">${riskText}</div></div>
                            <div class="kpi-card"><div class="kpi-title">Active Strikes</div><div class="kpi-value">${activeStrikes}</div></div>
                        </div>
                        <div style="margin-top:16px;">
                            <h4 style="margin-bottom:8px;">Strike History</h4>
                            <div id="vStrikesList">${strikes}</div>
                            <div class="form-inline" style="margin-top:8px;">
                                <input id="vStrikeInput" placeholder="Strike reason..." />
                                <button class="btn primary" id="vStrikeAddBtn">Add Strike</button>
                                <button class="btn danger" id="vStrikesClearBtn">Clear All</button>
                            </div>
                        </div>
                        <div style="margin-top:16px;">
                            <h4 style="margin-bottom:8px;">Status</h4>
                            ${statusCard}
                            <div style="margin-top:8px;">${flags}</div>
                            <div class="form-inline" style="margin-top:8px;">
                                <input id="vFlagInput" placeholder="Add a flag (e.g. BOLO)" />
                                <button class="btn primary" id="vFlagAddBtn">Add Flag</button>
                            </div>
                        </div>
                        <div style="margin-top:16px;">
                            <h4 style="margin-bottom:8px;">Notes</h4>
                            <div id="vNotesList">${notes}</div>
                            <div class="form-inline" style="margin-top:8px;">
                                <textarea id="vNoteInput" placeholder="Add a note..."></textarea>
                                <button class="btn primary" id="vNoteAddBtn">Add</button>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            <div data-view="v-notes" style="display:none;">
                <div class="form-inline" style="margin-bottom:8px;">
                    <textarea id="vNoteInputAlt" placeholder="Add a note..."></textarea>
                    <button class="btn primary" id="vNoteAddBtnAlt">Add</button>
                </div>
                <div>${notes}</div>
            </div>
            <div data-view="v-flags" style="display:none;">
                <div class="form-inline" style="margin-bottom:8px;">
                    <input id="vFlagInputAlt" placeholder="Add a flag (e.g. BOLO)" />
                    <button class="btn primary" id="vFlagAddBtnAlt">Add</button>
                </div>
                <div>${flags}</div>
            </div>
            <div data-view="v-strikes" style="display:none;">
                <div>${strikes}</div>
                <div class="form-inline" style="margin-top:8px;">
                    <input id="vStrikeInputAlt" placeholder="Strike reason..." />
                    <button class="btn primary" id="vStrikeAddBtnAlt">Add Strike</button>
                    <button class="btn danger" id="vStrikesClearBtnAlt">Clear All</button>
                </div>
            </div>
        `;
        const header = modal.querySelector('.tabs');
        if (header){
            header.querySelectorAll('.tab').forEach(btn => btn.onclick = () => setActiveTab(modal, 'v-', btn.dataset.tab));
            setActiveTab(modal, 'v-', 'v-overview');
        }
        document.getElementById('vNoteAddBtn')?.addEventListener('click', () => {
            const txt = document.getElementById('vNoteInput').value.trim(); if (!txt) return;
            sendCallback('addVehicleNote', { plate: data.plate, text: txt });
            document.getElementById('vNoteInput').value = '';
            sendCallback('openVehicle', { plate: data.plate });
        });
        document.getElementById('vNoteAddBtnAlt')?.addEventListener('click', () => {
            const txt = document.getElementById('vNoteInputAlt').value.trim(); if (!txt) return;
            sendCallback('addVehicleNote', { plate: data.plate, text: txt });
            document.getElementById('vNoteInputAlt').value = '';
            sendCallback('openVehicle', { plate: data.plate });
        });
        document.getElementById('vFlagAddBtn')?.addEventListener('click', () => {
            const flag = document.getElementById('vFlagInput').value.trim(); if (!flag) return;
            sendCallback('addVehicleFlag', { plate: data.plate, flag });
            document.getElementById('vFlagInput').value = '';
            sendCallback('openVehicle', { plate: data.plate });
        });
        document.getElementById('vFlagAddBtnAlt')?.addEventListener('click', () => {
            const flag = document.getElementById('vFlagInputAlt').value.trim(); if (!flag) return;
            sendCallback('addVehicleFlag', { plate: data.plate, flag });
            document.getElementById('vFlagInputAlt').value = '';
            sendCallback('openVehicle', { plate: data.plate });
        });
        document.getElementById('vStrikeAddBtn')?.addEventListener('click', () => {
            const reason = document.getElementById('vStrikeInput').value.trim(); if (!reason) return;
            sendCallback('addVehicleStrike', { plate: data.plate, reason });
            document.getElementById('vStrikeInput').value = '';
            sendCallback('openVehicle', { plate: data.plate });
        });
        document.getElementById('vStrikeAddBtnAlt')?.addEventListener('click', () => {
            const reason = document.getElementById('vStrikeInputAlt').value.trim(); if (!reason) return;
            sendCallback('addVehicleStrike', { plate: data.plate, reason });
            document.getElementById('vStrikeInputAlt').value = '';
            sendCallback('openVehicle', { plate: data.plate });
        });
        document.getElementById('vStrikeAddBtnHeader')?.addEventListener('click', async () => {
            const reason = (typeof window.mdtPrompt === 'function')
                ? (await window.mdtPrompt('Enter strike reason', { title: 'Add Strike', required: true, placeholder: 'Reason...' }))
                : null;
            if (!reason) return;
            sendCallback('addVehicleStrike', { plate: data.plate, reason });
            sendCallback('openVehicle', { plate: data.plate });
        });
        document.getElementById('vStrikesClearBtn')?.addEventListener('click', () => {
            sendCallback('clearVehicleStrikes', { plate: data.plate });
            sendCallback('openVehicle', { plate: data.plate });
        });
        document.getElementById('vStrikesClearBtnAlt')?.addEventListener('click', () => {
            sendCallback('clearVehicleStrikes', { plate: data.plate });
            sendCallback('openVehicle', { plate: data.plate });
        });
    }

    // Profile Picture Modal Handler
    window.openProfilePictureModal = function(citizenId) {
        const modal = document.getElementById('profilePictureModal');
        if (modal) {
            modal.classList.remove('hidden');
            document.getElementById('profilePictureCitizenId').value = citizenId;
            document.getElementById('profilePictureUrlInput').value = '';
        }
    };

    window.takeProfilePhoto = function(citizenId) {
        sendCallback('mdt:takeEvidencePhoto', {}, (result) => {
            if (result && result.success && result.imageUrl) {
                sendCallback('updateProfilePicture', { 
                    citizenId: citizenId, 
                    url: result.imageUrl 
                }, (response) => {
                    if (response && response.success) {
                        setTimeout(() => sendCallback('openCitizen', { citizenId }), 500);
                    }
                });
            }
        }, { timeoutMs: 120000 });
    };

    window.takeVehiclePhoto = function(plate) {
        // Support both explicit plate parameter and global currentVehicleInfo
        const vehiclePlate = plate || (window.currentVehicleInfo && window.currentVehicleInfo.plate);
        if (!vehiclePlate) {
            console.error('[MDT ERROR] No vehicle plate available for photo');
            return;
        }
        sendCallback('mdt:takeEvidencePhoto', {}, (result) => {
            if (result && result.success && result.imageUrl) {
                sendCallback('updateVehiclePhoto', { 
                    plate: vehiclePlate, 
                    url: result.imageUrl 
                }, (response) => {
                    if (response && response.success) {
                        setTimeout(() => sendCallback('openVehicle', { plate: vehiclePlate }), 500);
                    }
                });
            }
        }, { timeoutMs: 120000 });
    };

    // Wire profile picture update button
    (function setupProfilePictureHandler() {
        let wired = false;
        const ensure = () => {
            if (wired) return;
            const btn = document.getElementById('profilePictureUpdateBtn');
            if (!btn) return;
            wired = true;
            btn.addEventListener('click', () => {
                const citizenId = document.getElementById('profilePictureCitizenId').value;
                const url = document.getElementById('profilePictureUrlInput').value.trim();
                if (!url) {
                    if (typeof mdtToast === 'function') mdtToast('Please enter an image URL', 'error');
                    return;
                }
                sendCallback('updateProfilePicture', { citizenId, url });
                document.getElementById('profilePictureModal').classList.add('hidden');
                setTimeout(() => sendCallback('openCitizen', { citizenId }), 500);
            });
        };
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', ensure);
        } else {
            ensure();
        }
        const obs = new MutationObserver(ensure);
        obs.observe(document.documentElement, { childList: true, subtree: true });
    })();

    window.addEventListener('message', (e) => {
        const d = e.data;
        if (!d || !d.action) return;
        if (d.action === 'setCitizenProfile') renderCitizenProfile(d.profile || {});
        // Note: setVehicleProfile is now handled by app.js via openVehicleDetail()
        // Legacy renderVehicleProfile is disabled to avoid duplicate modals
    });
})();

// ============================================================================
// License Management Modal
// ============================================================================
function openLicenseModal(licenseDataStr) {
    console.log('[LICENSE] openLicenseModal called with:', licenseDataStr);
    try {
        const licenseData = JSON.parse(licenseDataStr);
        console.log('[LICENSE] Parsed license data:', licenseData);
        const citizenId = licenseData.citizenId;
        const licenseType = licenseData.type;
        const licenseKey = licenseData.key;
        const citizenName = licenseData.citizenName;
        const isSuspended = licenseData.isSuspended || false;
        const suspensionExpiry = licenseData.suspensionExpiry;
        
        let statusHtml = '';
        let actionsHtml = '';
        
        if (isSuspended && suspensionExpiry) {
            // License is suspended
            statusHtml = `
                <div style="margin-bottom: 20px;">
                    <div style="font-size: 11px; color: rgba(255,255,255,0.5); margin-bottom: 4px;">STATUS</div>
                    <div style="font-weight: 600; font-size: 14px; color: #ef4444;">🚫 Suspended</div>
                    <div style="font-size: 12px; color: rgba(255,255,255,0.6); margin-top: 4px;">Expires: ${escapeHtml(formatDateTime(suspensionExpiry))}</div>
                </div>
            `;
            // Escape for JavaScript strings in onclick (not HTML entities)
            const escJs = (s) => escapeJsAttr(s); // JS-string + HTML-attribute safe (see app.js)
            actionsHtml = `
                <div style="border-top: 1px solid rgba(255,255,255,0.1); padding-top: 16px; margin-bottom: 16px;">
                    <button class="btn success" style="width: 100%;" onclick="unsuspendLicense('${escJs(citizenId)}', '${escJs(licenseKey)}', '${escJs(licenseType)}');">✓ Lift Suspension (Restore License)</button>
                </div>
                
                <div style="border-top: 1px solid rgba(255,255,255,0.1); padding-top: 16px;">
                    <button class="btn danger" style="width: 100%;" onclick="removeLicense('${escJs(citizenId)}', '${escJs(licenseKey)}', '${escJs(licenseType)}');">🗑️ Remove License Permanently</button>
                </div>
            `;
        } else {
            // License is active
            statusHtml = `
                <div style="margin-bottom: 20px;">
                    <div style="font-size: 11px; color: rgba(255,255,255,0.5); margin-bottom: 4px;">STATUS</div>
                    <div style="font-weight: 600; font-size: 14px; color: #00e676;">✓ Active</div>
                </div>
            `;
            // Escape for JavaScript strings in onclick (not HTML entities)
            const escJs = (s) => escapeJsAttr(s); // JS-string + HTML-attribute safe (see app.js)
            actionsHtml = `
                <div style="border-top: 1px solid rgba(255,255,255,0.1); padding-top: 16px; margin-bottom: 16px;">
                    <div style="margin-bottom: 12px;">
                        <label style="font-size: 12px; color: rgba(255,255,255,0.7); display: block; margin-bottom: 8px;">Suspend License for:</label>
                        <select id="suspendDurationSelect" style="width: 100%; padding: 8px; border-radius: 6px; border: 1px solid rgba(59,130,246,0.3); background: rgba(59,130,246,0.1); color: #fff; font-size: 12px;">
                            <option value="">-- Select Duration --</option>
                            <option value="1">1 Day</option>
                            <option value="2">2 Days</option>
                            <option value="3">3 Days</option>
                            <option value="4">4 Days</option>
                            <option value="5">5 Days</option>
                            <option value="7">1 Week</option>
                            <option value="14">2 Weeks</option>
                            <option value="21">3 Weeks</option>
                            <option value="30">1 Month</option>
                            <option value="60">2 Months</option>
                            <option value="90">3 Months</option>
                        </select>
                    </div>
                    <button class="btn primary" style="width: 100%;" onclick="suspendLicense('${escJs(citizenId)}', '${escJs(licenseKey)}', '${escJs(licenseType)}');">⏸️ Suspend License</button>
                </div>
                
                <div style="border-top: 1px solid rgba(255,255,255,0.1); padding-top: 16px;">
                    <button class="btn danger" style="width: 100%;" onclick="removeLicense('${escJs(citizenId)}', '${escJs(licenseKey)}', '${escJs(licenseType)}');">🗑️ Remove License Permanently</button>
                </div>
            `;
        }
        
        const modalHTML = `
            <div class="modal" id="licenseManagementModal" style="z-index: 10016;">
                <div class="modal-card" style="width: 500px; max-width: 90vw;">
                    <div class="modal-header">
                        <h3 style="margin: 0;">📋 ${escapeHtml(licenseType)}</h3>
                        <button class="modal-btn" id="licenseModalClose" title="Close">
                            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                <line x1="18" y1="6" x2="6" y2="18"></line>
                                <line x1="6" y1="6" x2="18" y2="18"></line>
                            </svg>
                        </button>
                    </div>
                    <div class="modal-body" style="padding: 16px;">
                        <div style="margin-bottom: 16px;">
                            <div style="font-size: 11px; color: rgba(255,255,255,0.5); margin-bottom: 4px;">CITIZEN</div>
                            <div style="font-weight: 600; font-size: 14px;">${escapeHtml(citizenName)}</div>
                        </div>
                        
                        <div style="margin-bottom: 16px;">
                            <div style="font-size: 11px; color: rgba(255,255,255,0.5); margin-bottom: 4px;">LICENSE TYPE</div>
                            <div style="font-weight: 600; font-size: 14px;">${escapeHtml(licenseType)}</div>
                        </div>
                        
                        ${statusHtml}
                        
                        ${actionsHtml}
                    </div>
                </div>
            </div>
        `;
        
        // Remove existing modal if present
        const existing = document.getElementById('licenseManagementModal');
        if (existing) existing.remove();
        
        // Insert modal into DOM
        document.body.insertAdjacentHTML('beforeend', modalHTML);
        
        // Close on background click
        const modal = document.getElementById('licenseManagementModal');
        modal.addEventListener('click', (e) => {
            if (e.target === modal) closeLicenseModal();
        });
        
        // Close on header X click
        const closeBtn = document.getElementById('licenseModalClose');
        if (closeBtn) closeBtn.onclick = closeLicenseModal;
        
        // Close on ESC key
        const handleEsc = (e) => {
            if (e.key === 'Escape') {
                const m = document.getElementById('licenseManagementModal');
                if (m) closeLicenseModal();
            }
        };
        document.addEventListener('keydown', handleEsc, { once: true });
    } catch (e) {
        console.error('[MDT] Failed to parse license data:', e);
    }
}

function closeLicenseModal() {
    try {
        const modal = document.getElementById('licenseManagementModal');
        if (modal) modal.remove();
    } catch (e) {
        console.error('[LICENSE] Error closing modal:', e);
        // Force remove any modals if there's an error
        try {
            document.querySelectorAll('#licenseManagementModal').forEach(m => m.remove());
        } catch (_) {}
    }
}

// ============================================================================
// Status Flag Removal Modal
// ============================================================================
function openFlagRemoveModal(flagPayloadStr) {
    try {
        const payload = JSON.parse(flagPayloadStr);
        const citizenId = payload.citizenId;
        const citizenName = payload.citizenName || '';
        const flag = payload.flag || '';
        if (!citizenId || !flag) return;

        const escJs = (s) => escapeJsAttr(s); // JS-string + HTML-attribute safe (see app.js)

        const modalHTML = `
            <div class="modal" id="flagRemoveModal" style="z-index: 10016;">
                <div class="modal-card" style="width: 460px; max-width: 90vw;">
                    <div class="modal-header">
                        <h3 style="margin: 0;">Remove Flag</h3>
                        <button class="modal-btn" id="flagRemoveModalClose" title="Close">
                            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                <line x1="18" y1="6" x2="6" y2="18"></line>
                                <line x1="6" y1="6" x2="18" y2="18"></line>
                            </svg>
                        </button>
                    </div>
                    <div class="modal-body" style="padding: 16px;">
                        <div style="font-size: 12px; color: rgba(255,255,255,0.65); margin-bottom: 6px;">CITIZEN</div>
                        <div style="font-weight: 700; margin-bottom: 12px;">${escapeHtml(citizenName || citizenId)}</div>

                        <div style="font-size: 12px; color: rgba(255,255,255,0.65); margin-bottom: 6px;">FLAG</div>
                        <div style="display:inline-flex; align-items:center; gap:8px; padding: 8px 10px; background: rgba(255,255,255,0.04); border: 1px solid rgba(255,255,255,0.08); border-radius: 999px; font-weight: 700;">
                            ${escapeHtml(flag)}
                        </div>

                        <div style="margin-top: 14px; font-size: 12px; color: rgba(255,255,255,0.6);">
                            This will remove the status flag from the citizen profile.
                        </div>

                        <div style="display:flex; gap:10px; margin-top: 16px;">
                            <button class="btn" style="flex:1;" onclick="closeFlagRemoveModal();">Cancel</button>
                            <button class="btn danger" style="flex:1;" onclick="confirmRemoveFlag('${escJs(citizenId)}','${escJs(flag)}');">Remove</button>
                        </div>
                    </div>
                </div>
            </div>
        `;

        const existing = document.getElementById('flagRemoveModal');
        if (existing) existing.remove();
        document.body.insertAdjacentHTML('beforeend', modalHTML);

        const modal = document.getElementById('flagRemoveModal');
        modal.addEventListener('click', (e) => {
            if (e.target === modal) closeFlagRemoveModal();
        });
        const closeBtn = document.getElementById('flagRemoveModalClose');
        if (closeBtn) closeBtn.onclick = closeFlagRemoveModal;

        const handleEsc = (e) => {
            if (e.key === 'Escape') {
                const m = document.getElementById('flagRemoveModal');
                if (m) closeFlagRemoveModal();
            }
        };
        document.addEventListener('keydown', handleEsc, { once: true });
    } catch (e) {
        console.error('[FLAGS] Failed to open remove modal', e);
    }
}

function closeFlagRemoveModal() {
    try {
        const modal = document.getElementById('flagRemoveModal');
        if (modal) modal.remove();
    } catch (e) {
        console.error('[FLAGS] Error closing modal', e);
        try { document.querySelectorAll('#flagRemoveModal').forEach(m => m.remove()); } catch (_) {}
    }
}

function confirmRemoveFlag(citizenId, flag) {
    try {
        sendCallback('removeCitizenFlag', { citizenId, flag });
        closeFlagRemoveModal();
        setTimeout(() => sendCallback('openCitizen', { citizenId }), 250);
    } catch (e) {
        console.error('[FLAGS] Failed to remove flag', e);
    }
}

function suspendLicense(citizenId, licenseKey, licenseType) {
    console.log('[LICENSE] suspendLicense called:', { citizenId, licenseKey, licenseType });
    
    try {
        const durationSelect = document.getElementById('suspendDurationSelect');
        const duration = durationSelect ? durationSelect.value : '';
        
        console.log('[LICENSE] Duration selected (raw):', duration, 'Type:', typeof duration);
        
        if (!duration || duration === '') {
            console.warn('[LICENSE] No duration selected');
            closeLicenseModal();
            return;
        }
        
        const durationDays = parseFloat(duration);
        console.log('[LICENSE] Duration parsed:', durationDays, 'Type:', typeof durationDays);
        
        if (isNaN(durationDays) || durationDays <= 0) {
            console.error('[LICENSE] Invalid duration value:', durationDays);
            closeLicenseModal();
            return;
        }
        
        console.log('[LICENSE] Sending suspend callback with durationDays:', durationDays);
        sendCallback('suspendLicense', {
            citizenId: citizenId,
            licenseType: licenseKey,
            durationDays: durationDays
        }, (response) => {
            console.log('[LICENSE] Suspend response received:', JSON.stringify(response));
            try {
                if (response && response.success) {
                    closeLicenseModal();
                    // Refresh the citizen profile
                    setTimeout(() => {
                        sendCallback('openCitizen', { citizenId: citizenId });
                    }, 300);
                } else {
                    console.error('[LICENSE] Failed to suspend license:', response?.error || 'Unknown error');
                    closeLicenseModal();
                }
            } catch (e) {
                console.error('[LICENSE] Error handling suspend response:', e);
                closeLicenseModal();
            }
        });
    } catch (e) {
        console.error('[LICENSE] Error in suspendLicense:', e);
        closeLicenseModal();
    }
}

async function removeLicense(citizenId, licenseKey, licenseType) {
    console.log('[LICENSE] removeLicense called:', { citizenId, licenseKey, licenseType });
    
    try {
        if (!await window.mdtConfirm(`Are you sure you want to remove the ${licenseType} from ${citizenId}? This action cannot be undone.`)) {
            console.log('[LICENSE] User cancelled removal');
            return;
        }
        
        console.log('[LICENSE] Sending remove callback...');
        sendCallback('removeLicense', {
            citizenId: citizenId,
            licenseType: licenseKey
        }, (response) => {
            console.log('[LICENSE] Remove response:', response);
            try {
                if (response && response.success) {
                    closeLicenseModal();
                    // Refresh the citizen profile
                    setTimeout(() => {
                        sendCallback('openCitizen', { citizenId: citizenId });
                    }, 300);
                } else {
                    console.error('[LICENSE] Failed to remove license:', response?.error || 'Unknown error');
                    closeLicenseModal();
                }
            } catch (e) {
                console.error('[LICENSE] Error handling remove response:', e);
                closeLicenseModal();
            }
        });
    } catch (e) {
        console.error('[LICENSE] Error in removeLicense:', e);
        closeLicenseModal();
    }
}

function unsuspendLicense(citizenId, licenseKey, licenseType) {
    console.log('[LICENSE] unsuspendLicense called:', { citizenId, licenseKey, licenseType });
    
    try {
        console.log('[LICENSE] Lifting suspension on', licenseType);
        
        console.log('[LICENSE] Sending unsuspend callback...');
        sendCallback('unsuspendLicense', {
            citizenId: citizenId,
            licenseType: licenseKey
        }, (response) => {
            console.log('[LICENSE] Unsuspend response:', response);
            try {
                if (response && response.success) {
                    closeLicenseModal();
                    // Refresh the citizen profile
                    setTimeout(() => {
                        sendCallback('openCitizen', { citizenId: citizenId });
                    }, 300);
                } else {
                    console.error('[LICENSE] Failed to unsuspend license:', response?.error || 'Unknown error');
                    closeLicenseModal();
                }
            } catch (e) {
                console.error('[LICENSE] Error handling unsuspend response:', e);
                closeLicenseModal();
            }
        });
    } catch (e) {
        console.error('[LICENSE] Error in unsuspendLicense:', e);
        closeLicenseModal();
    }
}

// Expose license management functions to window for onclick handlers
window.openLicenseModal = openLicenseModal;
window.closeLicenseModal = closeLicenseModal;
window.suspendLicense = suspendLicense;
window.removeLicense = removeLicense;
window.unsuspendLicense = unsuspendLicense;

// ============================================================================
// INCIDENTS MODAL
// ============================================================================

function openNewIncidentModal() {
    let modal = document.getElementById('newIncidentModal');
    
    if (!modal) {
        console.error('[INCIDENTS] Failed to find modal');
        return;
    }
    
    // Remove any stray backdrops that could darken the screen
    document.querySelectorAll('.modal-backdrop, #incidentBackdrop, #mdtConfirmBackdrop').forEach(el => {
        try { el.remove(); } catch (_) {}
    });


    // Force display with all transparency settings
    modal.classList.remove('hidden');
    
    // Also ensure the modal-card is displayed properly
    const modalCard = modal.querySelector('.modal-card');
    if (modalCard) {
        modalCard.style.pointerEvents = 'auto';
    }
    
    // Reset form
    const titleInput = document.getElementById('incidentTitleInput');
    const descInput = document.getElementById('incidentDescriptionInput');
    const dateTimeInput = document.getElementById('incidentDateTimeInput');
    const officerInput = document.getElementById('incidentReportingOfficerInput');
    const locInput = document.getElementById('incidentLocationInput');
    
    if (titleInput) titleInput.value = '';
    if (descInput) descInput.value = '';
    // Prefill Date/Time (current time) as local datetime-local value
    if (dateTimeInput) {
        try {
            const now = new Date();
            const tzOffset = now.getTimezoneOffset();
            const local = new Date(now.getTime() - tzOffset * 60000);
            dateTimeInput.value = local.toISOString().slice(0,16);
        } catch (_) { dateTimeInput.value = ''; }
    }
    // Prefill Reporting Officer
    if (officerInput) {
        try {
            officerInput.value = (typeof formatOfficerLabel === 'function') ? formatOfficerLabel() : (window.userInfo?.name || 'Officer');
        } catch (_) {
            officerInput.value = window.userInfo?.name || 'Officer';
        }
    }
    // Prefill Location from last known player position if available
    if (locInput) {
        const pos = window.__lastPlayerPos;
        if (pos && typeof pos.x === 'number' && typeof pos.y === 'number') {
            const x = Number(pos.x).toFixed(1);
            const y = Number(pos.y).toFixed(1);
            locInput.value = `X: ${x}, Y: ${y}`;
            // Try to resolve a street label from server
            try {
                sendCallback('getStreetLabel', { coords: pos }, (res) => {
                    if (res && (res.label || res.street)) {
                        locInput.value = res.label || res.street;
                    }
                });
            } catch (_) {}
        } else {
            locInput.value = '';
        }
    }
    
    const citizensList = document.getElementById('incidentInvolvedCitizensList');
    const victimsList = document.getElementById('incidentInvolvedVictimsList');
    const officersList = document.getElementById('incidentInvolvedOfficersList');
    const vehiclesList = document.getElementById('incidentInvolvedVehiclesList');
    const chargesList = document.getElementById('incidentChargesList');
    const evidenceList = document.getElementById('incidentEvidenceList');
    if (citizensList) citizensList.innerHTML = '';
    if (victimsList) victimsList.innerHTML = '';
    if (officersList) officersList.innerHTML = '';
    if (vehiclesList) vehiclesList.innerHTML = '';
    if (chargesList) chargesList.innerHTML = '';
    if (evidenceList) evidenceList.innerHTML = '';
    
    // Reset selections
    window.__selectedIncidentCitizens = [];
    window.__selectedIncidentVictims = [];
    window.__selectedIncidentOfficers = [];
    window.__selectedIncidentVehicles = [];
    window.__selectedIncidentCharges = [];
    window.__selectedIncidentEvidence = [];
    
    // Load evidence dropdown options
    loadIncidentEvidenceOptions();
    
    // Note: populateIncidentDropdowns() is called via wrapper function at bottom of file
    // which handles citizens, victims, officers, vehicles, and charges dropdowns
    
    console.log('[INCIDENTS] Modal opened');
}

function loadIncidentEvidenceOptions() {
    sendCallback('pf_emsmdt:searchEvidence', { query: '', page: 1, pageSize: 100, limit: 100 }, (response) => {
        const evidenceSelect = document.getElementById('incidentEvidenceSelect');
        if (!evidenceSelect) return;
        
        evidenceSelect.innerHTML = '<option value="">Select evidence...</option>';
        
        if (response && response.evidence && response.evidence.length > 0) {
            response.evidence.forEach(ev => {
                const option = document.createElement('option');
                // Prefer evidence_number for incident linking (used by openEvidenceDetails)
                option.value = (ev.evidence_number != null) ? ev.evidence_number : ev.id;
                option.setAttribute('data-evidence-id', ev.evidence_id);
                option.setAttribute('data-evidence-number', (ev.evidence_number != null) ? ev.evidence_number : '');
                option.setAttribute('data-evidence-db-id', ev.id);
                option.textContent = `${ev.evidence_id} - ${ev.title}`;
                evidenceSelect.appendChild(option);
            });
        }
    });
}

function loadIncidentVehicleOptions() {
    const vehicleSelect = document.getElementById('incidentVehicleSelect');
    if (!vehicleSelect) return;
    
    vehicleSelect.innerHTML = '<option value="">Select a vehicle...</option>';
    
    try {
        sendCallback('mdt:getAllVehicles', {}, (response) => {
            if (!response) return;
            
            const vehicles = Array.isArray(response) ? response : (Array.isArray(response?.vehicles) ? response.vehicles : []);
            
            if (vehicles.length === 0) return;
            
            const isHashLike = (val) => {
                const s = String(val ?? '').trim();
                if (!s) return false;
                if (/^0x[0-9a-f]+$/i.test(s)) return true;
                if (/^[+-]?\d+(?:\.0+)?$/.test(s)) return true;
                return false;
            };

            const isDumpLike = (val) => {
                const s = String(val ?? '').trim();
                if (!s) return false;
                if (s.length > 60) return true;
                if (s.startsWith('{') || s.startsWith('[')) return true;
                if (/[\{\}\[\]\n]/.test(s)) return true;
                if (/\b(mods?|modifications|pearlescent|wheel|engine|turbo)\b/i.test(s)) return true;
                return false;
            };

            const cleanPlate = (val, fallbackText) => {
                let s = String(val ?? '').trim();
                if (!s) s = String(fallbackText ?? '').trim();
                if (!s) return '';
                // Common formats: "PLATE - Name", "PLATE - {json}", "PLATE {json}", etc.
                const braceIdx = s.indexOf('{');
                const bracketIdx = s.indexOf('[');
                const cutJsonIdx = (braceIdx >= 0 && bracketIdx >= 0) ? Math.min(braceIdx, bracketIdx) : Math.max(braceIdx, bracketIdx);
                if (cutJsonIdx > 0) s = s.slice(0, cutJsonIdx).trim();
                if (s.includes(' - ')) s = s.split(' - ')[0].trim();
                if (s.includes('|')) s = s.split('|')[0].trim();
                if (s.includes('\n')) s = s.split('\n')[0].trim();
                return s;
            };

            vehicles.forEach(veh => {
                const option = document.createElement('option');
                option.value = veh.id || veh.plate;
                const plateClean = cleanPlate(veh.plate, veh.id || '');
                option.setAttribute('data-plate', plateClean);

                let displayName = '';
                if (veh.modelLabel && veh.modelLabel !== 'NULL' && !isHashLike(veh.modelLabel) && !isDumpLike(veh.modelLabel)) {
                    displayName = String(veh.modelLabel).trim();
                } else if (veh.brand && !isDumpLike(veh.brand)) {
                    displayName = String(veh.brand).trim();
                } else if (veh.model && !isHashLike(veh.model) && !isDumpLike(veh.model)) {
                    displayName = String(veh.model).trim();
                } else {
                    displayName = 'Unknown';
                }

                if (String(displayName).toLowerCase() === 'unknown') {
                    option.textContent = `${plateClean || (veh.plate || 'Unknown')}`;
                } else {
                    option.textContent = `${plateClean || (veh.plate || 'Unknown')} - ${displayName}`;
                }
                vehicleSelect.appendChild(option);
            });
        });
    } catch(e) {
        console.error('[INCIDENTS] Error loading vehicles:', e);
    }
}

function loadIncidentChargesOptions() {
    const chargeSelect = document.getElementById('incidentChargeSelect');
    if (!chargeSelect) return;
    
    chargeSelect.innerHTML = '<option value="">Select a charge...</option>';
    
    try {
        sendCallback('mdt:getAllCharges', {}, (response) => {
            if (!response) return;
            
            const charges = Array.isArray(response) ? response : (Array.isArray(response?.charges) ? response.charges : []);
            
            if (charges.length === 0) return;
            
            charges.forEach(charge => {
                const option = document.createElement('option');
                option.value = charge.code || charge.id || charge.name;
                option.setAttribute('data-name', charge.name || charge.code || '');
                const text = charge.code ? `${charge.code} - ${charge.name || charge.code}` : (charge.name || 'Unknown');
                option.textContent = text;
                chargeSelect.appendChild(option);
            });
        });
    } catch(e) {
        console.error('[INCIDENTS] Error loading charges:', e);
    }
}

function loadIncidentVictimOptions() {
    const victimSelect = document.getElementById('incidentVictimSelect');
    if (!victimSelect) return;
    
    victimSelect.innerHTML = '<option value="">Select a victim...</option>';
    
    try {
        sendCallback('getAllPlayers', {}, (res) => {
            if (!res) return;
            
            const list = Array.isArray(res) ? res : (Array.isArray(res?.players) ? res.players : []);
            list.forEach(p => {
                const id = String(p.citizenid || p.id || '').trim();
                const name = p.name || p.fullname || `${p.firstname||''} ${p.lastname||''}`.trim() || 'Unknown';
                if (!id || !name) return;
                const opt = document.createElement('option');
                opt.value = id;
                opt.textContent = name;
                victimSelect.appendChild(opt);
            });
        });
    } catch(e) {
        console.error('[INCIDENTS] Error loading victims:', e);
    }
}

// createIncidentModal() - DEPRECATED: Modal is now in static HTML (index.html)
// The newIncidentModal is defined in index.html with class="modal hidden"
function createIncidentModal() {
    console.warn('[INCIDENTS] createIncidentModal() called but modal is now static in HTML');
}


function closeNewIncidentModal() {
    const modal = document.getElementById('newIncidentModal');
    if (modal) {
        modal.classList.add('hidden');
    }
}

function openNewIncidentForCitizen(citizenId, citizenName) {
    console.log('[INCIDENTS] openNewIncidentForCitizen called with:', citizenId, citizenName);
    
    // Open the same global incident modal without auto-attaching any entities
    openNewIncidentModal();
    // Keep context if needed, but do NOT auto-attach citizen
    window.__currentIncidentCitizenId = citizenId;
    console.log('[INCIDENTS] Modal opened from citizen profile; no auto-attachments');
}

function addIncidentInvolvedCitizen() {
    const citizenSelect = document.getElementById('incidentCitizenSelect');
    const id = citizenSelect?.value?.trim();
    const name = citizenSelect?.selectedOptions?.[0]?.text || '';
    if (!id) {
        console.log('[INCIDENTS] No citizen selected');
        return;
    }
    if (!window.__selectedIncidentCitizens) window.__selectedIncidentCitizens = [];
    if (window.__selectedIncidentCitizens.some(c => c.id === id)) {
        console.log('[INCIDENTS] Citizen already added');
        return;
    }
    window.__selectedIncidentCitizens.push({ id, name });
    renderIncidentInvolvedCitizens();
    citizenSelect.value = '';
}

function removeIncidentInvolvedCitizen(id) {
    if (!window.__selectedIncidentCitizens) window.__selectedIncidentCitizens = [];
    window.__selectedIncidentCitizens = window.__selectedIncidentCitizens.filter(c => c.id !== id);
    renderIncidentInvolvedCitizens();
}

function renderIncidentInvolvedCitizens() {
    const list = document.getElementById('incidentInvolvedCitizensList');
    if (!window.__selectedIncidentCitizens) window.__selectedIncidentCitizens = [];
    const html = window.__selectedIncidentCitizens.map(c => `
        <div class="chip" style="display: inline-block; padding: 6px 12px; border-radius: 20px; background: rgba(100, 200, 255, 0.2); border: 1px solid rgba(100, 200, 255, 0.4); margin: 4px; cursor: pointer;">
            👤 ${escapeHtml(c.name)}
            <span onclick="removeIncidentInvolvedCitizen('${escapeJsAttr(c.id)}')" style="margin-left: 8px; cursor: pointer; opacity: 0.7;">✕</span>
        </div>
    `).join('');
    list.innerHTML = html || '<div style="color: rgba(255,255,255,0.5); font-size: 12px;">No citizens added</div>';
}

function addIncidentInvolvedOfficer() {
    const officerSelect = document.getElementById('incidentOfficerSelect');
    const id = officerSelect?.value?.trim();
    const name = officerSelect?.selectedOptions?.[0]?.text || '';
    if (!id) {
        console.log('[INCIDENTS] No officer selected');
        return;
    }
    if (!window.__selectedIncidentOfficers) window.__selectedIncidentOfficers = [];
    if (window.__selectedIncidentOfficers.some(o => o.id === id)) {
        console.log('[INCIDENTS] Officer already added');
        return;
    }
    window.__selectedIncidentOfficers.push({ id, name });
    renderIncidentInvolvedOfficers();
    officerSelect.value = '';
}

function removeIncidentInvolvedOfficer(id) {
    if (!window.__selectedIncidentOfficers) window.__selectedIncidentOfficers = [];
    window.__selectedIncidentOfficers = window.__selectedIncidentOfficers.filter(o => o.id !== id);
    renderIncidentInvolvedOfficers();
}

function renderIncidentInvolvedOfficers() {
    const list = document.getElementById('incidentInvolvedOfficersList');
    if (!window.__selectedIncidentOfficers) window.__selectedIncidentOfficers = [];
    const html = window.__selectedIncidentOfficers.map(o => `
        <div class="chip" style="display: inline-block; padding: 6px 12px; border-radius: 20px; background: rgba(100, 200, 255, 0.2); border: 1px solid rgba(100, 200, 255, 0.4); margin: 4px; cursor: pointer;">
            👮 ${escapeHtml(o.name)}
            <span onclick="removeIncidentInvolvedOfficer('${escapeJsAttr(o.id)}')" style="margin-left: 8px; cursor: pointer; opacity: 0.7;">✕</span>
        </div>
    `).join('');
    list.innerHTML = html || '<div style="color: rgba(255,255,255,0.5); font-size: 12px;">No officers added</div>';
}

function addIncidentInvolvedVictim() {
    const victimSelect = document.getElementById('incidentVictimSelect');
    const id = victimSelect?.value?.trim();
    const name = victimSelect?.selectedOptions?.[0]?.text || '';
    if (!id) {
        console.log('[INCIDENTS] No victim selected');
        return;
    }
    if (!window.__selectedIncidentVictims) window.__selectedIncidentVictims = [];
    if (window.__selectedIncidentVictims.some(v => v.id === id)) {
        console.log('[INCIDENTS] Victim already added');
        return;
    }
    window.__selectedIncidentVictims.push({ id, name });
    renderIncidentInvolvedVictims();
    victimSelect.value = '';
}

function removeIncidentInvolvedVictim(id) {
    if (!window.__selectedIncidentVictims) window.__selectedIncidentVictims = [];
    window.__selectedIncidentVictims = window.__selectedIncidentVictims.filter(v => v.id !== id);
    renderIncidentInvolvedVictims();
}

function renderIncidentInvolvedVictims() {
    const list = document.getElementById('incidentInvolvedVictimsList');
    if (!window.__selectedIncidentVictims) window.__selectedIncidentVictims = [];
    const html = window.__selectedIncidentVictims.map(v => `
        <div class="chip" style="display: inline-block; padding: 6px 12px; border-radius: 20px; background: rgba(255, 150, 100, 0.2); border: 1px solid rgba(255, 150, 100, 0.4); margin: 4px; cursor: pointer;">
            🚨 ${escapeHtml(v.name)}
            <span onclick="removeIncidentInvolvedVictim('${escapeJsAttr(v.id)}')" style="margin-left: 8px; cursor: pointer; opacity: 0.7;">✕</span>
        </div>
    `).join('');
    list.innerHTML = html || '<div style="color: rgba(255,255,255,0.5); font-size: 12px;">No victims added</div>';
}

function addIncidentVehicle() {
    const vehicleSelect = document.getElementById('incidentVehicleSelect');
    const id = vehicleSelect?.value?.trim();
    const rawPlate = vehicleSelect?.selectedOptions?.[0]?.getAttribute('data-plate') || '';
    const name = vehicleSelect?.selectedOptions?.[0]?.text || '';
    if (!id) {
        console.log('[INCIDENTS] No vehicle selected');
        return;
    }

    const cleanPlate = (val, fallbackText) => {
        let s = String(val ?? '').trim();
        if (!s) s = String(fallbackText ?? '').trim();
        if (!s) return '';
        const braceIdx = s.indexOf('{');
        const bracketIdx = s.indexOf('[');
        const cutJsonIdx = (braceIdx >= 0 && bracketIdx >= 0) ? Math.min(braceIdx, bracketIdx) : Math.max(braceIdx, bracketIdx);
        if (cutJsonIdx > 0) s = s.slice(0, cutJsonIdx).trim();
        if (s.includes(' - ')) s = s.split(' - ')[0].trim();
        if (s.includes('|')) s = s.split('|')[0].trim();
        if (s.includes('\n')) s = s.split('\n')[0].trim();
        return s;
    };

    const plate = cleanPlate(rawPlate, name);

    if (!window.__selectedIncidentVehicles) window.__selectedIncidentVehicles = [];
    if (window.__selectedIncidentVehicles.some(v => v.id === id)) {
        console.log('[INCIDENTS] Vehicle already added');
        return;
    }
    window.__selectedIncidentVehicles.push({ id, plate, name });
    renderIncidentVehicles();
    vehicleSelect.value = '';
}

function removeIncidentVehicle(id) {
    if (!window.__selectedIncidentVehicles) window.__selectedIncidentVehicles = [];
    window.__selectedIncidentVehicles = window.__selectedIncidentVehicles.filter(v => v.id !== id);
    renderIncidentVehicles();
}

function renderIncidentVehicles() {
    const list = document.getElementById('incidentInvolvedVehiclesList');
    if (!window.__selectedIncidentVehicles) window.__selectedIncidentVehicles = [];
    const html = window.__selectedIncidentVehicles.map(v => `
        <div class="chip" style="display: inline-block; padding: 6px 12px; border-radius: 20px; background: rgba(150, 200, 100, 0.2); border: 1px solid rgba(150, 200, 100, 0.4); margin: 4px; cursor: pointer;">
            🚔 ${escapeHtml(v.plate)}
            <span onclick="removeIncidentVehicle('${escapeJsAttr(v.id)}')" style="margin-left: 8px; cursor: pointer; opacity: 0.7;">✕</span>
        </div>
    `).join('');
    list.innerHTML = html || '<div style="color: rgba(255,255,255,0.5); font-size: 12px;">No vehicles added</div>';
}

function addIncidentCharge() {
    const chargeSelect = document.getElementById('incidentChargeSelect');
    const code = chargeSelect?.value?.trim() || '';
    const name = chargeSelect?.selectedOptions?.[0]?.getAttribute('data-name') || chargeSelect?.selectedOptions?.[0]?.text || '';
    if (!code) {
        console.log('[INCIDENTS] No charge selected');
        return;
    }
    if (!window.__selectedIncidentCharges) window.__selectedIncidentCharges = [];
    if (window.__selectedIncidentCharges.some(c => c.code === code)) {
        console.log('[INCIDENTS] Charge already added');
        return;
    }
    window.__selectedIncidentCharges.push({ code, name });
    renderIncidentCharges();
    chargeSelect.value = '';
}

function removeIncidentCharge(code) {
    if (!window.__selectedIncidentCharges) window.__selectedIncidentCharges = [];
    window.__selectedIncidentCharges = window.__selectedIncidentCharges.filter(c => c.code !== code);
    renderIncidentCharges();
}

function renderIncidentCharges() {
    const list = document.getElementById('incidentChargesList');
    if (!window.__selectedIncidentCharges) window.__selectedIncidentCharges = [];
    const html = window.__selectedIncidentCharges.map(c => `
        <div class="chip" style="display: inline-block; padding: 6px 12px; border-radius: 20px; background: rgba(255, 100, 100, 0.2); border: 1px solid rgba(255, 100, 100, 0.4); margin: 4px; cursor: pointer;">
            ⚖️ ${escapeHtml(c.code)} - ${escapeHtml(c.name)}
            <span onclick="removeIncidentCharge('${escapeJsAttr(c.code)}')" style="margin-left: 8px; cursor: pointer; opacity: 0.7;">✕</span>
        </div>
    `).join('');
    list.innerHTML = html || '<div style="color: rgba(255,255,255,0.5); font-size: 12px;">No charges added</div>';
}

function addIncidentEvidence() {
    const evidenceSelect = document.getElementById('incidentEvidenceSelect');
    const id = evidenceSelect?.value?.trim();
    const evidenceId = evidenceSelect?.selectedOptions?.[0]?.getAttribute('data-evidence-id') || '';
    const evidenceNumber = evidenceSelect?.selectedOptions?.[0]?.getAttribute('data-evidence-number') || '';
    const dbId = evidenceSelect?.selectedOptions?.[0]?.getAttribute('data-evidence-db-id') || '';
    const title = evidenceSelect?.selectedOptions?.[0]?.text || '';
    if (!id) {
        console.log('[INCIDENTS] No evidence selected');
        return;
    }
    if (!window.__selectedIncidentEvidence) window.__selectedIncidentEvidence = [];
    if (window.__selectedIncidentEvidence.some(e => e.id === id)) {
        console.log('[INCIDENTS] Evidence already attached');
        return;
    }
    window.__selectedIncidentEvidence.push({ id, evidenceId, evidenceNumber, dbId, title });
    renderIncidentEvidence();
    evidenceSelect.value = '';
}

function removeIncidentEvidence(id) {
    if (!window.__selectedIncidentEvidence) window.__selectedIncidentEvidence = [];
    window.__selectedIncidentEvidence = window.__selectedIncidentEvidence.filter(e => e.id !== id);
    renderIncidentEvidence();
}

function renderIncidentEvidence() {
    const list = document.getElementById('incidentEvidenceList');
    if (!window.__selectedIncidentEvidence) window.__selectedIncidentEvidence = [];
    const html = window.__selectedIncidentEvidence.map(e => `
        <div class="chip" style="display: inline-block; padding: 6px 12px; border-radius: 20px; background: rgba(255, 200, 100, 0.2); border: 1px solid rgba(255, 200, 100, 0.4); margin: 4px; cursor: pointer;">
            📷 ${escapeHtml(e.evidenceId)} - ${escapeHtml(e.title)}
            <span onclick="removeIncidentEvidence('${escapeJsAttr(e.id)}')" style="margin-left: 8px; cursor: pointer; opacity: 0.7;">✕</span>
        </div>
    `).join('');
    list.innerHTML = html || '<div style="color: rgba(255,255,255,0.5); font-size: 12px;">No evidence attached</div>';
}

function submitIncident() {
    const title = document.getElementById('incidentTitleInput')?.value?.trim() || '';
    const description = document.getElementById('incidentDescriptionInput')?.value?.trim() || '';
    const dateTime = document.getElementById('incidentDateTimeInput')?.value || '';
    const reportingOfficer = document.getElementById('incidentReportingOfficerInput')?.value?.trim() || '';
    const location = document.getElementById('incidentLocationInput')?.value?.trim() || '';
    
    if (!title || !description) {
        console.log('[INCIDENTS] Missing required fields');
        return;
    }
    
    const citizenObjs = window.__selectedIncidentCitizens || [];
    const victimObjs = window.__selectedIncidentVictims || [];
    const officerObjs = window.__selectedIncidentOfficers || [];
    const vehicleObjs = window.__selectedIncidentVehicles || [];
    const chargeList = window.__selectedIncidentCharges || [];
    const evidenceObjs = window.__selectedIncidentEvidence || [];
    const citizens = citizenObjs.map(c => c.name);
    const victims = victimObjs.map(v => v.name);
    const officers = officerObjs.map(o => o.name);

    const vehicles = vehicleObjs.map(v => {
        const plate = String(v.plate || '').trim();
        const raw = String(v.name || '').trim();
        if (!plate) return '';

        // `v.name` is usually option text like "PLATE - Vehicle Name".
        let nameOnly = raw;
        if (nameOnly.startsWith(plate)) {
            const rest = nameOnly.slice(plate.length).trim();
            nameOnly = rest.startsWith('-') ? rest.slice(1).trim() : rest;
        }

        if (!nameOnly || /^unknown$/i.test(nameOnly)) return plate;
        return `${plate} - ${nameOnly}`;
    }).filter(Boolean);
    const charges = chargeList.map(c => c.code || c.name);
    const citizenIds = citizenObjs.map(c => c.id);
    const victimIds = victimObjs.map(v => v.id);
    const officerIds = officerObjs.map(o => o.id);
    const vehicleIds = vehicleObjs.map(v => v.id);
    // Evidence linking expects evidence_number for details modal; fall back to legacy id/evidence_id.
    const evidenceIds = evidenceObjs.map(e => e.evidenceNumber || e.id || e.evidenceId).filter(Boolean);
    
    console.log('[INCIDENTS] Submitting:', { title, description, dateTime, reportingOfficer, location, citizenIds, victimIds, officerIds, vehicleIds, charges, evidenceIds });
    
    sendCallback('createIncident', {
        title,
        description,
        dateTime,
        reportingOfficer,
        location,
        involvedCitizens: citizens,
        involvedVictims: victims,
        involvedOfficers: officers,
        involvedVehicles: vehicles,
        charges: charges,
        involvedCitizenIds: citizenIds,
        involvedVictimIds: victimIds,
        involvedOfficerIds: officerIds,
        involvedVehicleIds: vehicleIds,
        evidenceIds: evidenceIds
    }, (response) => {
        if (response && response.success) {
            console.log('[INCIDENTS] Incident created successfully');
            closeNewIncidentModal();
            
            // Refresh incidents page if it's open
            setTimeout(() => {
                const router = window.router;
                const page = router?.pages?.get('incidents');
                if (page && page.loadIncidents) {
                    page.loadIncidents();
                }
            }, 300);
        } else {
            console.error('[INCIDENTS] Failed to create incident:', response?.error);
        }
    });
}

// ============================================================================
// REPORTS MODAL
// ============================================================================

function openNewReportModal() {
    let modal = document.getElementById('newReportModal');
    
    if (!modal) {
        console.warn('[REPORTS] Modal not found, creating it');
        // Create the modal if it doesn't exist
        createReportModal();
        modal = document.getElementById('newReportModal');
    }
    
    if (!modal) {
        console.error('[REPORTS] Failed to create modal');
        return;
    }
    
    modal.classList.remove('hidden');
    
    // Reset form
    const titleInput = document.getElementById('reportTitleInput');
    const descInput = document.getElementById('reportDescriptionInput');
    const dateInput = document.getElementById('reportDateInput');
    const typeSelect = document.getElementById('reportTypeSelect');
    const catInput = document.getElementById('reportCategoryInput');
    
    if (titleInput) titleInput.value = '';
    if (descInput) descInput.value = '';
    if (dateInput) dateInput.value = new Date().toISOString().split('T')[0];
    if (typeSelect) typeSelect.value = '';
    if (catInput) catInput.value = '';
    
    const involvedList = document.getElementById('reportInvolvedList');
    if (involvedList) involvedList.innerHTML = '';
    
    // Reset selections
    window.__selectedReportInvolved = [];
    window.__selectedReportOfficers = [];
    // Reset photos
    window.__selectedReportPhotos = [];
    const photosGrid = document.getElementById('reportPhotosGrid');
    if (photosGrid) photosGrid.innerHTML = '<div class="empty-message" style="grid-column:1/-1;">No photos</div>';
    // Render photos grid
    if (typeof renderReportPhotos === 'function') renderReportPhotos();
    
    console.log('[REPORTS] Modal opened');
}

function createReportModal() {
    const html = `
        <div id="newReportModal" class="modal hidden">
            <div class="modal-card" style="width: 680px; max-height: 90vh; overflow-y: auto;">
                <div class="modal-header" style="display: flex; justify-content: space-between; align-items: center;">
                    <h3 style="margin: 0;">Create New Report</h3>
                    <button class="modal-btn close-modal" title="Close" style="background: rgba(255,255,255,0.12); color: #fff; padding: 6px 8px; border-radius: 4px; border: none; cursor: pointer;">
                        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="18" y1="6" x2="6" y2="18"></line><line x1="6" y1="6" x2="18" y2="18"></line></svg>
                    </button>
                </div>
                <div class="modal-body">
                    <div class="form-section">
                        <label class="form-row">
                            <span>Report Title</span>
                            <input id="reportTitleInput" type="text" placeholder="Title of the report..." />
                        </label>
                    </div>

                    <div class="form-section">
                        <label class="form-row">
                            <span>Report Type</span>
                            <select id="reportTypeSelect" style="padding: 8px; border-radius: 6px; border: 1px solid rgba(59,130,246,0.3); background: rgba(59,130,246,0.1); color: #fff;">
                                <option value="">Select a type...</option>
                                <option value="traffic_citation">Traffic Citation</option>
                                <option value="arrest">Arrest Report</option>
                                <option value="incident">Incident Report</option>
                                <option value="use_of_force">Use of Force</option>
                                <option value="pursuit">Pursuit Report</option>
                                <option value="accident">Accident Report</option>
                                <option value="seizure">Seizure Report</option>
                            </select>
                        </label>
                    </div>

                    <div class="form-section">
                        <label class="form-row">
                            <span>Category</span>
                            <input id="reportCategoryInput" type="text" placeholder="e.g., General, Criminal, Traffic..." />
                        </label>
                    </div>

                    <div class="form-section">
                        <label class="form-row">
                            <span>Description</span>
                            <textarea id="reportDescriptionInput" placeholder="Detailed description of the report..." style="height: 100px;"></textarea>
                        </label>
                    </div>

                    <div class="form-section">
                        <label class="form-row">
                            <span>Date</span>
                            <input id="reportDateInput" type="date" />
                        </label>
                    </div>

                    <div class="form-section">
                        <h4>Involved Parties</h4>
                        <label class="form-row">
                            <span>Add Person</span>
                            <select id="reportInvolvedSelect" style="padding: 8px; border-radius: 6px; border: 1px solid rgba(59,130,246,0.3); background: rgba(59,130,246,0.1); color: #fff;">
                                <option value="">Select a person...</option>
                            </select>
                        </label>
                        <button type="button" class="modal-btn" onclick="addReportInvolved()" style="margin-top: 8px; width: 100%;">+ Add Person</button>
                        <div id="reportInvolvedList" style="margin-top: 12px;"></div>
                    </div>
                    <div class="form-section">
                        <h4>Officers Involved</h4>
                        <label class="form-row">
                            <span>Add Officer</span>
                            <select id="reportOfficersSelect" style="padding: 8px; border-radius: 6px; border: 1px solid rgba(59,130,246,0.3); background: rgba(59,130,246,0.1); color: #fff;">
                                <option value="">Select an officer...</option>
                            </select>
                        </label>
                        <button type="button" class="modal-btn" onclick="addReportOfficer()" style="margin-top: 8px; width: 100%;">+ Add Officer</button>
                        <div id="reportOfficersList" style="margin-top: 12px;"></div>
                    </div>
                    <div class="form-section">
                        <h4>Photos</h4>
                        <div style="display:flex; gap:8px; flex-wrap:wrap; margin-bottom:8px;">
                            <button type="button" class="modal-btn" onclick="takeReportPhoto()">📷 Take Photo</button>
                            <div style="display:flex; gap:6px; align-items:center; flex:1;">
                                <input id="reportPhotoUrlInput" type="text" placeholder="Paste image URL (https://...)" style="flex:1;" />
                                <button type="button" class="modal-btn" onclick="addReportPhotoFromUrl()">+ Add</button>
                            </div>
                        </div>
                        <div id="reportPhotosGrid" style="display:grid; grid-template-columns: repeat(auto-fill, minmax(140px, 1fr)); gap:10px;">
                            <div class="empty-message" style="grid-column:1/-1;">No photos</div>
                        </div>
                    </div>
                </div>
                <div class="modal-footer">
                    <button class="modal-btn" onclick="submitReport()">Create Report</button>
                </div>
            </div>
        </div>
    `;
    
    document.body.insertAdjacentHTML('beforeend', html);
    const modal = document.getElementById('newReportModal');
    const closeBtn = modal?.querySelector('.close-modal');
    if (closeBtn) {
        closeBtn.addEventListener('click', closeNewReportModal);
    }
}


function closeNewReportModal() {
    const modal = document.getElementById('newReportModal');
    if (modal) modal.classList.add('hidden');
}

function openNewReportForCitizen(citizenId, citizenName) {
    console.log('[REPORTS] openNewReportForCitizen called with:', citizenId, citizenName);
    
    // Open modal and pre-populate with citizen
    openNewReportModal();
    
    // Add citizen to involved list
    if (!Array.isArray(window.__selectedReportInvolved)) window.__selectedReportInvolved = [];
    const already = window.__selectedReportInvolved.some(p => String(p?.citizenid) === String(citizenId));
    if (!already) {
        window.__selectedReportInvolved.push({ citizenid: String(citizenId), name: String(citizenName || '').trim() || 'Citizen' });
        renderReportInvolvedParties();
    }
    
    // Store citizen ID for reference
    window.__currentReportCitizenId = citizenId;
    // Reset report photos and render
    window.__selectedReportPhotos = [];
    renderReportPhotos();
    
    console.log('[REPORTS] Modal opened for citizen:', citizenName, 'Involved array:', window.__selectedReportInvolved);
}

function addReportInvolved() {
    const involvedSelect = document.getElementById('reportInvolvedSelect');
    const involvedCitizenId = involvedSelect?.value?.trim();
    
    if (!involvedCitizenId) {
        console.log('[REPORTS] No person selected');
        return;
    }
    
    if (!Array.isArray(window.__selectedReportInvolved)) window.__selectedReportInvolved = [];
    const already = window.__selectedReportInvolved.some(p => String(p?.citizenid) === String(involvedCitizenId));
    if (already) {
        console.log('[REPORTS] Person already added');
        return;
    }

    const catalog = Array.isArray(window.__reportPeopleCatalog) ? window.__reportPeopleCatalog : [];
    const found = catalog.find(p => String(p.citizenid) === String(involvedCitizenId));
    const name = (found?.name || '').trim() || 'Citizen';

    window.__selectedReportInvolved.push({ citizenid: String(involvedCitizenId), name });
    renderReportInvolvedParties();
    involvedSelect.value = '';
}

function removeReportInvolved(citizenid) {
    if (!Array.isArray(window.__selectedReportInvolved)) window.__selectedReportInvolved = [];
    window.__selectedReportInvolved = window.__selectedReportInvolved.filter(p => String(p?.citizenid) !== String(citizenid));
    renderReportInvolvedParties();
}

function renderReportInvolvedParties() {
    const list = document.getElementById('reportInvolvedList');
    if (!Array.isArray(window.__selectedReportInvolved)) window.__selectedReportInvolved = [];

    const escJs = (s) => escapeJsAttr(s); // JS-string + HTML-attribute safe (see app.js)
    const html = window.__selectedReportInvolved.map(p => {
        const cid = String(p?.citizenid || '');
        const name = String(p?.name || 'Citizen');
        return `
            <div class="chip" style="display: inline-block; padding: 6px 12px; border-radius: 20px; background: rgba(100, 200, 255, 0.2); border: 1px solid rgba(100, 200, 255, 0.4); margin: 4px; cursor: default;">
                👤 ${escapeHtml(name)}
                <span onclick="removeReportInvolved('${escJs(cid)}')" style="margin-left: 8px; cursor: pointer; opacity: 0.7;">✕</span>
            </div>
        `;
    }).join('');
    
    list.innerHTML = html || '<div style="color: rgba(255,255,255,0.5); font-size: 12px;">No people added</div>';
}

function addReportOfficer() {
    const officersSelect = document.getElementById('reportOfficersSelect');
    if (!officersSelect || !officersSelect.value) {
        console.log('[REPORTS] No officer selected');
        return;
    }

    const officerName = officersSelect.value.trim();
    if (!officerName) {
        console.log('[REPORTS] Officer name is empty');
        return;
    }

    if (!Array.isArray(window.__selectedReportOfficers)) window.__selectedReportOfficers = [];
    const already = window.__selectedReportOfficers.some(o => String(o?.name) === String(officerName));
    if (already) {
        console.log('[REPORTS] Officer already added');
        return;
    }

    window.__selectedReportOfficers.push({ name: officerName });
    renderReportOfficers();
    officersSelect.value = '';
}

function removeReportOfficer(name) {
    if (!Array.isArray(window.__selectedReportOfficers)) window.__selectedReportOfficers = [];
    window.__selectedReportOfficers = window.__selectedReportOfficers.filter(o => String(o?.name) !== String(name));
    renderReportOfficers();
}

function renderReportOfficers() {
    const list = document.getElementById('reportOfficersList');
    if (!Array.isArray(window.__selectedReportOfficers)) window.__selectedReportOfficers = [];

    const escJs = (s) => escapeJsAttr(s); // JS-string + HTML-attribute safe (see app.js)
    const html = window.__selectedReportOfficers.map(o => {
        const name = String(o?.name || 'Officer');
        return `
            <div class="chip" style="display: inline-block; padding: 6px 12px; border-radius: 20px; background: rgba(100, 200, 255, 0.2); border: 1px solid rgba(100, 200, 255, 0.4); margin: 4px; cursor: default;">
                👮 ${escapeHtml(name)}
                <span onclick="removeReportOfficer('${escJs(name)}')" style="margin-left: 8px; cursor: pointer; opacity: 0.7;">✕</span>
            </div>
        `;
    }).join('');
    
    list.innerHTML = html || '<div style="color: rgba(255,255,255,0.5); font-size: 12px;">No officers added</div>';
}

function submitReport() {
    const title = document.getElementById('reportTitleInput')?.value?.trim() || '';
    const description = document.getElementById('reportDescriptionInput')?.value?.trim() || '';
    const date = document.getElementById('reportDateInput')?.value || '';
    const reportType = document.getElementById('reportTypeSelect')?.value || '';
    const category = document.getElementById('reportCategoryInput')?.value?.trim() || '';
    
    if (!title || !description || !reportType) {
        console.log('[REPORTS] Missing required fields');
        return;
    }
    
    const involved = Array.isArray(window.__selectedReportInvolved) ? window.__selectedReportInvolved : [];
    const officers = Array.isArray(window.__selectedReportOfficers) ? window.__selectedReportOfficers : [];
    const photos = Array.isArray(window.__selectedReportPhotos) ? window.__selectedReportPhotos : [];
    const linkedCitizens = involved
        .map(p => ({ citizenid: String(p?.citizenid || ''), name: String(p?.name || '').trim() }))
        .filter(p => p.citizenid);
    
    console.log('[REPORTS] Submitting:', { title, description, date, reportType, category, involved, officers, photos });
    
    sendCallback('createReport', {
        title,
        narrative: description,
        content: description,
        timestamp: date,
        type: reportType || 'Custom',
        category,
        linkedCitizens,
        linkedOfficers: officers.map(o => ({ name: String(o?.name || '') })).filter(o => o.name),
        linkedEvidence: photos.map(p => ({ url: String(p.url || ''), title: String(p.title || '') })).filter(p => p.url)
    }, (response) => {
        if (response && response.success) {
            console.log('[REPORTS] Report created successfully');
            closeNewReportModal();
            
            // Refresh reports page if it's open
            setTimeout(() => {
                const router = window.router;
                const page = router?.pages?.get('reports');
                if (page && page.loadReports) {
                    page.loadReports();
                }
            }, 300);

            // Refresh citizen profile if this report was created for a citizen
            if (window.__currentReportCitizenId) {
                setTimeout(() => {
                    sendCallback('openCitizen', { citizenId: window.__currentReportCitizenId });
                }, 350);
            }
        } else {
            console.error('[REPORTS] Failed to create report:', response?.error);
        }
    });
}

// Report details modal
function openReportDetails(reportId) {
    if (!reportId) return;
    sendCallback('getReport', { id: String(reportId) }, (resp) => {
        if (!resp || !resp.success || !resp.report) {
            console.error('[REPORTS] Failed to fetch report', resp && resp.error);
            return;
        }
        const r = resp.report;
        const titleCase = (s) => String(s || 'Custom').replace(/\w\S*/g, t => t.charAt(0).toUpperCase() + t.slice(1).toLowerCase());
        const typeLabel = titleCase(r.type);
        const created = formatDateTime(r.createdAt || r.timestamp);
        const evidenceList = Array.isArray(r.linkedEvidence) ? r.linkedEvidence : [];
        const evidenceHtml = evidenceList.length ? evidenceList.map(ev => {
            const url = typeof ev === 'string' ? ev : (ev.url || ev.image_url || ev.imageUrl || '');
            const title = typeof ev === 'object' ? (ev.title || '') : '';
            if (!safeUrl(url)) return '';
            return `
                <div class="evidence-item" style="display:inline-block;margin:6px;">
                    <img src="${escapeHtml(safeUrl(url))}" alt="Evidence" style="width:140px;height:100px;object-fit:cover;border-radius:8px;cursor:pointer;border:1px solid rgba(255,255,255,0.15)" onclick="showImageLightbox('${escapeJsAttr(safeUrl(url))}')" />
                    ${title ? `<div class="muted" style="font-size:12px;margin-top:4px;">${escapeHtml(title)}</div>` : ''}
                </div>
            `;
        }).join('') : '<div class="empty-message">No photos</div>';

        const html = `
            <div class="modal" id="reportDetailsModal">
                <div class="modal-card" style="max-width:860px;">
                    <div class="modal-header" style="display: flex; justify-content: space-between; align-items: center;">
                        <h3>Report Details</h3>
                        <button class="incident-modal-close" onclick="closeReportDetails()" style="background: none; border: none; color: rgba(255,255,255,0.6); cursor: pointer; padding: 4px; display: flex; align-items: center; justify-content: center; transition: all 0.2s ease;">
                            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                <line x1="18" y1="6" x2="6" y2="18"></line>
                                <line x1="6" y1="6" x2="18" y2="18"></line>
                            </svg>
                        </button>
                    </div>
                    <div class="modal-body">
                        <div style="margin-bottom:12px;">
                            <div class="muted">Type</div>
                            <div>${escapeHtml(typeLabel)}</div>
                        </div>
                        <div style="margin-bottom:12px;display:grid;grid-template-columns:1fr 1fr;gap:12px;">
                            <div>
                                <div class="muted">Title</div>
                                <div>${escapeHtml(r.title || '')}</div>
                            </div>
                            <div>
                                <div class="muted">Officer</div>
                                <div>${escapeHtml(r.officer || 'Unknown')}</div>
                            </div>
                            <div>
                                <div class="muted">Created</div>
                                <div>${escapeHtml(created)}</div>
                            </div>
                            <div>
                                <div class="muted">Location</div>
                                <div>${escapeHtml(r.location || 'Unknown')}</div>
                            </div>
                        </div>
                        <div style="margin-bottom:12px;">
                            <div class="muted">Narrative</div>
                            <div>${escapeHtml(r.narrative || r.content || '')}</div>
                        </div>
                        ${(() => {
                            let citizens = [];
                            if (r.involvedParties && typeof r.involvedParties === 'object') {
                                citizens = Array.isArray(r.involvedParties.citizens) ? r.involvedParties.citizens : [];
                            }
                            if (citizens.length > 0) {
                                return `<div style="margin-bottom:12px;"><div class="muted">Involved Parties</div><div style="display: flex; flex-wrap: wrap; gap: 6px;">${citizens.map(c => {
                                    const name = typeof c === 'string' ? c : (c.name || c.citizenid || 'Unknown');
                                    return `<span class="charge-chip">${escapeHtml(name)}</span>`;
                                }).join('')}</div></div>`;
                            }
                            return '';
                        })()}
                        ${(() => {
                            let officers = [];
                            if (r.involvedParties && typeof r.involvedParties === 'object') {
                                officers = Array.isArray(r.involvedParties.officers) ? r.involvedParties.officers : [];
                            }
                            if (officers.length > 0) {
                                return `<div style="margin-bottom:12px;"><div class="muted">Officers Involved</div><div style="display: flex; flex-wrap: wrap; gap: 6px;">${officers.map(o => {
                                    const name = typeof o === 'string' ? o : (o.name || 'Unknown');
                                    return `<span class="charge-chip">${escapeHtml(name)}</span>`;
                                }).join('')}</div></div>`;
                            }
                            return '';
                        })()}
                        <div style="margin-bottom:12px;">
                            <div class="muted">Photos</div>
                            <div>${evidenceHtml}</div>
                        </div>
                    </div>
                    <div class="modal-footer">
                        <button class="modal-btn" onclick="closeReportDetails()">Close</button>
                    </div>
                </div>
            </div>
        `;
        // Remove existing and insert
        const existing = document.getElementById('reportDetailsModal');
        if (existing) existing.remove();
        document.body.insertAdjacentHTML('beforeend', html);
    });
}

function closeReportDetails() {
    const m = document.getElementById('reportDetailsModal');
    if (m) m.remove();
}

function showImageLightbox(url) {
    if (!url) return;
    // Remove any existing lightbox variants
    closeImageLightbox();
    document.getElementById('imageEnlargeBackdrop')?.remove();

    const html = `
        <div class="modal-backdrop" id="imageLightboxBackdrop" style="z-index: 10050;">
            <div class="incident-details-modal" style="max-width: 1200px; width: 85vw;">
                <div class="incident-modal-header">
                    <div class="incident-modal-title">
                        <div class="incident-modal-icon">🖼️</div>
                        <div>
                            <h2>Photo</h2>
                            <p class="incident-modal-subtitle">Preview</p>
                        </div>
                    </div>
                    <button class="incident-modal-close" id="imageLightboxClose">
                        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <line x1="18" y1="6" x2="6" y2="18"></line>
                            <line x1="6" y1="6" x2="18" y2="18"></line>
                        </svg>
                    </button>
                </div>
                <div class="incident-modal-body" style="display: flex; align-items: center; justify-content: center;">
                    <img src="${escapeHtml(safeUrl(url))}" alt="Photo" style="max-width: 100%; max-height: 70vh; width: auto; height: auto; object-fit: contain; border-radius: 8px; background: rgba(0,0,0,0.3);" />
                </div>
            </div>
        </div>
    `;

    document.body.insertAdjacentHTML('beforeend', html);
    const backdrop = document.getElementById('imageLightboxBackdrop');
    const closeBtn = document.getElementById('imageLightboxClose');

    if (closeBtn) closeBtn.onclick = (e) => { e.stopPropagation(); closeImageLightbox(); };
    if (backdrop) backdrop.addEventListener('click', (e) => { if (e.target === backdrop) closeImageLightbox(); });

    // Close on ESC
    window.__lightboxEscHandler = function(ev) { if (ev.key === 'Escape') closeImageLightbox(); };
    document.addEventListener('keydown', window.__lightboxEscHandler);
}

function closeImageLightbox() {
    const m1 = document.getElementById('imageLightboxBackdrop');
    const m2 = document.getElementById('imageLightboxModal');
    if (m1) m1.remove();
    if (m2) m2.remove();
    if (window.__lightboxEscHandler) {
        document.removeEventListener('keydown', window.__lightboxEscHandler);
        window.__lightboxEscHandler = null;
    }
}

// Expose functions to window
window.openNewIncidentModal = openNewIncidentModal;
window.closeNewIncidentModal = closeNewIncidentModal;
window.openNewIncidentForCitizen = openNewIncidentForCitizen;
window.addIncidentInvolvedCitizen = addIncidentInvolvedCitizen;
window.removeIncidentInvolvedCitizen = removeIncidentInvolvedCitizen;
window.addIncidentInvolvedOfficer = addIncidentInvolvedOfficer;
window.removeIncidentInvolvedOfficer = removeIncidentInvolvedOfficer;
window.submitIncident = submitIncident;

window.openNewReportModal = openNewReportModal;
window.closeNewReportModal = closeNewReportModal;
window.openNewReportForCitizen = openNewReportForCitizen;
window.addReportInvolved = addReportInvolved;
window.removeReportInvolved = removeReportInvolved;
window.addReportOfficer = addReportOfficer;
window.removeReportOfficer = removeReportOfficer;
window.renderReportOfficers = renderReportOfficers;
window.submitReport = submitReport;
window.renderReportPhotos = renderReportPhotos;
window.addReportPhotoFromUrl = addReportPhotoFromUrl;
window.removeReportPhoto = removeReportPhoto;
window.takeReportPhoto = takeReportPhoto;
window.openReportDetails = openReportDetails;
window.closeReportDetails = closeReportDetails;
window.showImageLightbox = showImageLightbox;
window.closeImageLightbox = closeImageLightbox;
// Initialize modal close buttons
document.addEventListener('DOMContentLoaded', function() {
    // Incident modal close buttons
    const incidentModal = document.getElementById('newIncidentModal');
    if (incidentModal) {
        const closeButtons = incidentModal.querySelectorAll('.close-modal');
        closeButtons.forEach(btn => {
            btn.addEventListener('click', closeNewIncidentModal);
        });
    }
    
    // Report modal close buttons
    const reportModal = document.getElementById('newReportModal');
    if (reportModal) {
        const closeButtons = reportModal.querySelectorAll('.close-modal');
        closeButtons.forEach(btn => {
            btn.addEventListener('click', closeNewReportModal);
        });
    }
});

// Mock data for dropdowns - replace with real data from server
function populateIncidentDropdowns() {
    const citizenSelect = document.getElementById('incidentCitizenSelect');
    const victimSelect = document.getElementById('incidentVictimSelect');
    const officerSelect = document.getElementById('incidentOfficerSelect');
    const vehicleSelect = document.getElementById('incidentVehicleSelect');
    const chargeSelect = document.getElementById('incidentChargeSelect');
    
    // Clear existing options (keep first empty option)
    if (citizenSelect) {
        while (citizenSelect.options.length > 1) { citizenSelect.remove(1); }
    }
    if (victimSelect) {
        while (victimSelect.options.length > 1) { victimSelect.remove(1); }
    }
    if (officerSelect) {
        while (officerSelect.options.length > 1) { officerSelect.remove(1); }
    }
    if (vehicleSelect) {
        vehicleSelect.innerHTML = '<option value="">Select a vehicle...</option>';
    }
    if (chargeSelect) {
        chargeSelect.innerHTML = '<option value="">Select a charge...</option>';
    }
    
    // Fetch all players for citizens and victims
    try {
        sendCallback('getAllPlayers', {}, (res) => {
            const list = Array.isArray(res) ? res : (Array.isArray(res?.players) ? res.players : []);
            list.forEach(p => {
                const id = String(p.citizenid || p.id || '').trim();
                const name = p.name || p.fullname || `${p.firstname||''} ${p.lastname||''}`.trim() || 'Unknown';
                if (!id || !name) return;
                
                // Add to citizens
                if (citizenSelect) {
                    const opt = document.createElement('option');
                    opt.value = id;
                    opt.textContent = name;
                    citizenSelect.appendChild(opt);
                }
                
                // Add to victims
                if (victimSelect) {
                    const opt = document.createElement('option');
                    opt.value = id;
                    opt.textContent = name;
                    victimSelect.appendChild(opt);
                }
            });
        });
    } catch(_) {}
    
    // Fetch officers from server
    try {
        sendCallback('getPoliceOfficers', {}, (res) => {
            const list = Array.isArray(res) ? res : (Array.isArray(res?.officers) ? res.officers : []);
            list.forEach(o => {
                const id = String(o.citizenid || o.id || '').trim();
                const name = o.name || o.fullname || o.label || 'Officer';
                const callsign = o.callsign ? ` (${o.callsign})` : '';
                const opt = document.createElement('option');
                opt.value = id || name; // fallback to name if no id
                opt.textContent = (name + callsign).trim();
                officerSelect.appendChild(opt);
            });
        });
    } catch(_) {}
    
    // Fetch vehicles
    if (vehicleSelect) {
        try {
            sendCallback('mdt:getAllVehicles', {}, (response) => {
                if (!response) return;
                
                const vehicles = Array.isArray(response) ? response : (Array.isArray(response?.vehicles) ? response.vehicles : []);
                
                vehicles.forEach(veh => {
                    const isHashLike = (val) => {
                        const s = String(val ?? '').trim();
                        if (!s) return false;
                        if (/^0x[0-9a-f]+$/i.test(s)) return true;
                        if (/^[+-]?\d+(?:\.0+)?$/.test(s)) return true;
                        return false;
                    };
                    const isDumpLike = (val) => {
                        const s = String(val ?? '').trim();
                        if (!s) return false;
                        if (s.length > 60) return true;
                        if (s.startsWith('{') || s.startsWith('[')) return true;
                        if (/[\{\}\[\]\n]/.test(s)) return true;
                        if (/\b(mods?|modifications|pearlescent|wheel|engine|turbo)\b/i.test(s)) return true;
                        return false;
                    };
                    const cleanPlate = (val) => {
                        let s = String(val ?? '').trim();
                        if (!s) return '';
                        const braceIdx = s.indexOf('{');
                        const bracketIdx = s.indexOf('[');
                        const cutJsonIdx = (braceIdx >= 0 && bracketIdx >= 0) ? Math.min(braceIdx, bracketIdx) : Math.max(braceIdx, bracketIdx);
                        if (cutJsonIdx > 0) s = s.slice(0, cutJsonIdx).trim();
                        if (s.includes(' - ')) s = s.split(' - ')[0].trim();
                        if (s.includes('|')) s = s.split('|')[0].trim();
                        if (s.includes('\n')) s = s.split('\n')[0].trim();
                        return s;
                    };

                    const option = document.createElement('option');
                    const plateClean = cleanPlate(veh.plate);
                    option.value = veh.id || plateClean || veh.plate;
                    option.setAttribute('data-plate', plateClean);

                    let displayName = '';
                    if (veh.modelLabel && veh.modelLabel !== 'NULL' && !isHashLike(veh.modelLabel) && !isDumpLike(veh.modelLabel)) {
                        displayName = String(veh.modelLabel).trim();
                    } else if (veh.model && !isHashLike(veh.model) && !isDumpLike(veh.model)) {
                        displayName = String(veh.model).trim();
                    } else {
                        displayName = 'Unknown';
                    }

                    if (String(displayName).toLowerCase() === 'unknown') {
                        option.textContent = `${plateClean || (veh.plate || 'Unknown')}`;
                    } else {
                        option.textContent = `${plateClean || (veh.plate || 'Unknown')} - ${displayName}`;
                    }
                    vehicleSelect.appendChild(option);
                });
            });
        } catch(_) {}
    }
    
    // Fetch charges
    if (chargeSelect) {
        try {
            sendCallback('mdt:getAllCharges', {}, (response) => {
                if (!response) return;
                
                const charges = Array.isArray(response) ? response : (Array.isArray(response?.charges) ? response.charges : []);
                
                charges.forEach(charge => {
                    const option = document.createElement('option');
                    option.value = charge.code || charge.id || charge.name;
                    option.setAttribute('data-name', charge.name || charge.code || '');
                    const text = charge.code ? `${charge.code} - ${charge.name || charge.code}` : (charge.name || 'Unknown');
                    option.textContent = text;
                    chargeSelect.appendChild(option);
                });
            });
        } catch(_) {}
    }
}

function populateReportDropdowns() {
    const involvedSelect = document.getElementById('reportInvolvedSelect');
    const officersSelect = document.getElementById('reportOfficersSelect');
    
    if (!involvedSelect && !officersSelect) return;
    
    // Clear existing options for involved people (keep first empty option)
    if (involvedSelect) {
        while (involvedSelect.options.length > 1) {
            involvedSelect.remove(1);
        }
    }
    
    // Clear existing options for officers (keep first empty option)
    if (officersSelect) {
        while (officersSelect.options.length > 1) {
            officersSelect.remove(1);
        }
    }
    
    // Fetch citizens from server (database-backed)
    try {
        sendCallback('getAllPlayers', {}, (res) => {
            const list = Array.isArray(res) ? res : (Array.isArray(res?.players) ? res.players : []);
            window.__reportPeopleCatalog = list;
            
            // Populate involved people dropdown
            if (involvedSelect) {
                list.forEach(p => {
                    const id = String(p.citizenid || p.id || '').trim();
                    const name = (p.name || p.fullname || `${p.firstname||''} ${p.lastname||''}`.trim() || 'Citizen').trim();
                    if (!id) return;
                    const opt = document.createElement('option');
                    opt.value = id;
                    opt.textContent = name;
                    involvedSelect.appendChild(opt);
                });
            }
        });
    } catch (_) {}
    
    // Fetch officers from server
    try {
        sendCallback('getPoliceOfficers', {}, (res) => {
            const list = Array.isArray(res) ? res : [];
            window.__reportOfficersCatalog = list;
            
            // Populate officers dropdown
            if (officersSelect) {
                list.forEach(o => {
                    const name = (o.name || o.fullname || `${o.firstname||''} ${o.lastname||''}`.trim() || 'Officer').trim();
                    const callsign = o.callsign ? ` (${o.callsign})` : '';
                    const displayName = name + callsign;
                    const opt = document.createElement('option');
                    opt.value = name;
                    opt.textContent = displayName;
                    officersSelect.appendChild(opt);
                });
            }
        });
    } catch (_) {}
}

// Update dropdown population when modals open
const originalOpenIncidentModal = openNewIncidentModal;
openNewIncidentModal = function() {
    originalOpenIncidentModal();
    populateIncidentDropdowns();
};

const originalOpenReportModal = openNewReportModal;
openNewReportModal = function() {
    originalOpenReportModal();
    populateReportDropdowns();
};

window.openNewIncidentModal = openNewIncidentModal;
window.openNewReportModal = openNewReportModal;

// Capture last player position for location prefill
window.__lastPlayerPos = window.__lastPlayerPos || null;
window.addEventListener('message', (e) => {
    const d = e.data;
    if (d && d.action === 'playerPos' && d.coords) {
        window.__lastPlayerPos = d.coords;
    }
});

// ============================================================================
// EVIDENCE PAGE
// ============================================================================
class EvidencePage extends BasePage {
    constructor() {
        super('evidence', 'Evidence');
        this.evidence = [];
        this.currentPage = 1;
        this.pageSize = 18;
        this.searchQuery = '';
        this.totalCount = 0;
    }

    mount(root) {
        super.mount(root);
        console.log('[EVIDENCE] Page mounted. openNewEvidenceModal exists:', typeof window.openNewEvidenceModal);
        root.innerHTML = `
            <div class="search-page-container">
                <div class="search-page-header">
                    <div class="search-page-title-group">
                        <h2>Evidence</h2>
                        <div class="search-page-subtitle">Evidence Management System</div>
                    </div>
                    <button class="page-action-btn" onclick="openNewEvidenceModal()">+ New Evidence</button>
                </div>
                <div class="search-page-controls">
                    <input type="text" id="evidenceSearchInput" class="search-page-input" placeholder="Search evidence by title, ID, tags..." />
                </div>
                <div id="evidenceGrid" class="results-grid"></div>
                <div class="pagination-footer">
                    <span id="evidencePaginationText">Showing 1 to 0 of 0 Evidence</span>
                    <div class="pagination-buttons">
                        <button id="evidencePrevBtn" class="pagination-btn">Previous</button>
                        <button id="evidenceNextBtn" class="pagination-btn">Next</button>
                    </div>
                </div>
            </div>
        `;
        
        const input = document.getElementById('evidenceSearchInput');
        if (input) {
            input.addEventListener('input', (e) => {
                this.searchQuery = e.target.value;
                clearTimeout(this._deb);
                this._deb = setTimeout(() => {
                    this.currentPage = 1;
                    this.loadEvidence();
                }, 300);
            });
        }
        
        document.getElementById('evidencePrevBtn')?.addEventListener('click', () => {
            if (this.currentPage > 1) {
                this.currentPage--;
                this.loadEvidence();
            }
        });
        
        document.getElementById('evidenceNextBtn')?.addEventListener('click', () => {
            const maxPage = Math.ceil(this.totalCount / this.pageSize);
            if (this.currentPage < maxPage) {
                this.currentPage++;
                this.loadEvidence();
            }
        });
        
        // Store reference globally for modal access
        window._evidencePageInstance = this;
        
        this.loadEvidence();
    }

    loadEvidence() {
        sendCallback('pf_emsmdt:searchEvidence', {
            query: this.searchQuery,
            page: this.currentPage,
            pageSize: this.pageSize
        });
    }

    onMessage(data) {
        if (data.action === 'setEvidence') {
            this.evidence = data.evidence || [];
            this.totalCount = data.totalCount || 0;
            this.renderEvidence();
            this.updatePagination();
        } else if (data.action === 'refreshEvidence') {
            this.loadEvidence();
        }
    }

    renderEvidence() {
        const grid = document.getElementById('evidenceGrid');
        if (!grid) return;

        if (this.evidence.length === 0) {
            grid.innerHTML = '<div class="empty-message" style="grid-column: 1/-1;">No evidence found</div>';
            return;
        }

        grid.innerHTML = this.evidence.map(ev => {
            const statusBadge = ev.status ? `<span class="evidence-status status-${escapeHtml(String(ev.status).toLowerCase())}">${escapeHtml(String(ev.status).toUpperCase())}</span>` : '';
            return `
                <div class="evidence-card">
                    <div class="evidence-image" 
                         style="background-image: url('${escapeHtml(safeCssUrl(ev.image_url))}'); background-size: cover; background-position: center; height: 160px; border-radius: 8px 8px 0 0; cursor: pointer; position: relative;">
                        ${statusBadge}
                    </div>
                    <div style="padding: 12px; display: flex; flex-direction: column; gap: 8px;">
                        <div>
                            <div class="evidence-id" style="font-size: 12px; color: rgba(255,255,255,0.7); margin-bottom: 4px;">Evidence #${escapeHtml(ev.evidence_number)}</div>
                            <div class="evidence-title" style="font-size: 14px; font-weight: 600; margin-bottom: 8px; line-height: 1.3;">${escapeHtml(ev.title)}</div>
                            <div class="evidence-meta" style="font-size: 11px; color: rgba(255,255,255,0.5);">
                                <div>👮 ${escapeHtml(ev.created_by_name || 'Unknown')}</div>
                                <div>📅 ${escapeHtml(formatDateTime(ev.created_at))}</div>
                            </div>
                        </div>
                        <button class="incident-details-btn" onclick="openEvidenceDetails('${escapeJsAttr(ev.evidence_number)}'); return false;">VIEW DETAILS</button>
                    </div>
                </div>
            `;
        }).join('');
    }

    updatePagination() {
        const maxPage = Math.ceil(this.totalCount / this.pageSize) || 1;
        const start = (this.currentPage - 1) * this.pageSize + 1;
        const end = Math.min(this.currentPage * this.pageSize, this.totalCount);
        const textEl = document.getElementById('evidencePaginationText');
        if (textEl) textEl.textContent = `Showing ${this.totalCount ? start : 0} to ${this.totalCount ? end : 0} of ${this.totalCount} Evidence`;
        const prevBtn = document.getElementById('evidencePrevBtn');
        const nextBtn = document.getElementById('evidenceNextBtn');
        if (prevBtn) prevBtn.disabled = this.currentPage <= 1;
        if (nextBtn) nextBtn.disabled = this.currentPage >= maxPage;
    }
}

// Evidence Details Modal
window.openEvidenceDetails = function(evidenceNumber) {
    console.log('[Evidence Modal] Opening evidence:', evidenceNumber);
    
    // Try to get the evidence page instance from global reference first
    let page = window._evidencePageInstance;
    
    // Fallback: try to get from router
    if (!page) {
        page = window.router?.pages?.get('evidence');
    }
    
    if (!page) {
        console.error('[Evidence Modal] Evidence page not found');
        return;
    }
    
    console.log('[Evidence Modal] Available evidence:', page.evidence);
    const ev = page.evidence.find(e => String(e.evidence_number) === String(evidenceNumber));
    if (!ev) {
        console.error('[Evidence Modal] Evidence not found:', evidenceNumber);
        return;
    }
    
    console.log('[Evidence Modal] Found evidence:', ev);
    
    const canEdit = userInfo.rankLevel === 4;
    const isEditable = canEdit ? '' : 'disabled';
    const safeArray = (val) => {
        if (!val) return [];
        if (Array.isArray(val)) return val;
        try {
            const parsed = JSON.parse(val);
            return Array.isArray(parsed) ? parsed : [];
        } catch (e) {
            console.warn('[Evidence] Failed to parse array field', e);
            return [];
        }
    };
    const citizens = safeArray(ev.citizens_involved);
    const vehicles = safeArray(ev.vehicles_involved);
    const weapons = safeArray(ev.weapons_involved);
    const charges = safeArray(ev.related_charges);
    
    const modalHTML = `
        <div class="modal-backdrop" id="evidenceBackdrop">
            <div class="incident-details-modal">
                <div class="incident-modal-header">
                    <div class="incident-modal-title">
                        <div class="incident-modal-icon">📦</div>
                        <div>
                            <h2>Evidence #${escapeHtml(String(ev.evidence_number))}</h2>
                            <p class="incident-modal-subtitle">In-depth details and chain of custody</p>
                        </div>
                    </div>
                    <button class="incident-modal-close" id="evidenceDetailsClose">
                        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <line x1="18" y1="6" x2="6" y2="18"></line>
                            <line x1="6" y1="6" x2="18" y2="18"></line>
                        </svg>
                    </button>
                </div>
                <div class="incident-modal-body">
                
                <!-- Evidence Identifier -->
                <div style="margin-bottom: 16px;">
                    <div style="font-size: 12px; color: rgba(255,255,255,0.6); margin-bottom: 4px; text-transform: uppercase;">Evidence Number</div>
                    <div style="font-weight: 600; font-size: 16px;">Evidence #${escapeHtml(ev.evidence_number)}</div>
                </div>
                
                ${ev.incident_id ? `
                <div style="margin-bottom: 16px;">
                    <div style="font-size: 12px; color: rgba(255,255,255,0.6); margin-bottom: 4px; text-transform: uppercase;">Linked Incident</div>
                    <div style="font-weight: 600;">${escapeHtml(ev.incident_id)}</div>
                </div>
                ` : ''}
                
                <!-- Created Date & Collected By -->
                <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-bottom: 16px;">
                    <div>
                        <div style="font-size: 12px; color: rgba(255,255,255,0.6); margin-bottom: 4px; text-transform: uppercase;">Created Date & Time</div>
                        <div>${escapeHtml(formatDateTime(ev.created_at))}</div>
                    </div>
                    <div>
                        <div style="font-size: 12px; color: rgba(255,255,255,0.6); margin-bottom: 4px; text-transform: uppercase;">Collected By</div>
                        <div>👮 ${escapeHtml(ev.collected_by)}</div>
                    </div>
                </div>
                
                <!-- Evidence Title -->
                <div style="margin-bottom: 16px;">
                    <div style="font-size: 12px; color: rgba(255,255,255,0.6); margin-bottom: 4px; text-transform: uppercase;">Evidence Title *</div>
                    <input type="text" id="evidenceTitleEdit" value="${escapeHtml(ev.title)}" ${isEditable} style="width: 100%; padding: 8px; border-radius: 6px; border: 1px solid rgba(255,255,255,0.2); background: rgba(0,0,0,0.3); color: #fff; font-size: 14px;" />
                </div>
                
                <!-- Evidence Description -->
                <div style="margin-bottom: 16px;">
                    <div style="font-size: 12px; color: rgba(255,255,255,0.6); margin-bottom: 4px; text-transform: uppercase;">Evidence Description *</div>
                    <textarea id="evidenceDescEdit" ${isEditable} style="width: 100%; min-height: 100px; padding: 8px; border-radius: 6px; border: 1px solid rgba(255,255,255,0.2); background: rgba(0,0,0,0.3); color: #fff; font-size: 13px; font-family: inherit;">${escapeHtml(ev.description || '')}</textarea>
                </div>
                
                <!-- Evidence Media -->
                <div style="margin-bottom: 16px;">
                    <div style="font-size: 12px; color: rgba(255,255,255,0.6); margin-bottom: 8px; text-transform: uppercase;">Evidence Media</div>
                    <img src="${escapeHtml(safeUrl(ev.image_url))}" onclick="if(window.enlargeImage){window.enlargeImage('${escapeJsAttr(safeUrl(ev.image_url))}')}" style="width: 100%; max-height: 400px; object-fit: contain; border-radius: 8px; cursor: pointer; background: rgba(0,0,0,0.3);" />
                </div>
                
                <!-- Citizens Involved -->
                ${citizens.length ? `
                <div style="margin-bottom: 16px;">
                    <div style="font-size: 12px; color: rgba(255,255,255,0.6); margin-bottom: 8px; text-transform: uppercase;">Citizens Involved</div>
                    <div style="display: flex; flex-wrap: wrap; gap: 8px;">
                        ${citizens.map(c => `<span class="incident-involved-chip">${escapeHtml(c.name)}${c.role ? ` (${escapeHtml(c.role)})` : ''}</span>`).join('')}
                    </div>
                </div>
                ` : ''}
                
                <!-- Vehicles Involved -->
                ${vehicles.length ? `
                <div style="margin-bottom: 16px;">
                    <div style="font-size: 12px; color: rgba(255,255,255,0.6); margin-bottom: 8px; text-transform: uppercase;">Vehicles Involved</div>
                    <div style="display: flex; flex-wrap: wrap; gap: 8px;">
                        ${vehicles.map(v => `<span class="incident-involved-chip">${escapeHtml(v.plate)}</span>`).join('')}
                    </div>
                </div>
                ` : ''}
                
                <!-- Weapons Involved -->
                ${weapons.length ? `
                <div style="margin-bottom: 16px;">
                    <div style="font-size: 12px; color: rgba(255,255,255,0.6); margin-bottom: 8px; text-transform: uppercase;">Weapons Involved</div>
                    <div style="display: flex; flex-wrap: wrap; gap: 8px;">
                        ${weapons.map(w => `<span class="incident-involved-chip">${escapeHtml(w.type)}${w.serial ? ` - SN: ${escapeHtml(w.serial)}` : ''}</span>`).join('')}
                    </div>
                </div>
                ` : ''}
                
                <!-- Related Charges -->
                ${charges.length ? `
                <div style="margin-bottom: 16px;">
                    <div style="font-size: 12px; color: rgba(255,255,255,0.6); margin-bottom: 8px; text-transform: uppercase;">Related Charges</div>
                    <div style="display: flex; flex-wrap: wrap; gap: 8px;">
                        ${charges.map(ch => `<span class="incident-involved-chip">${escapeHtml(ch)}</span>`).join('')}
                    </div>
                </div>
                ` : ''}
                
                <!-- Evidence Status -->
                <div style="margin-bottom: 16px;">
                    <div style="font-size: 12px; color: rgba(255,255,255,0.6); margin-bottom: 4px; text-transform: uppercase;">Evidence Status *</div>
                    <select id="evidenceStatusEdit" ${isEditable} style="width: 100%; padding: 8px; border-radius: 6px; border: 1px solid rgba(255,255,255,0.2); background: rgba(0,0,0,0.3); color: #fff; font-size: 14px;">
                        <option value="Collected" ${ev.status === 'Collected' ? 'selected' : ''}>Collected</option>
                        <option value="Logged" ${ev.status === 'Logged' ? 'selected' : ''}>Logged</option>
                        <option value="Submitted" ${ev.status === 'Submitted' ? 'selected' : ''}>Submitted</option>
                        <option value="Released" ${ev.status === 'Released' ? 'selected' : ''}>Released</option>
                        <option value="Destroyed" ${ev.status === 'Destroyed' ? 'selected' : ''}>Destroyed</option>
                    </select>
                </div>
                
                <!-- Evidence Location Details -->
                ${ev.location_details ? `
                <div style="margin-bottom: 16px;">
                    <div style="font-size: 12px; color: rgba(255,255,255,0.6); margin-bottom: 4px; text-transform: uppercase;">Location Details</div>
                    <textarea id="evidenceLocationEdit" ${isEditable} style="width: 100%; min-height: 60px; padding: 8px; border-radius: 6px; border: 1px solid rgba(255,255,255,0.2); background: rgba(0,0,0,0.3); color: #fff; font-size: 13px; font-family: inherit;">${escapeHtml(ev.location_details || '')}</textarea>
                </div>
                ` : ''}
                
                <!-- Tags / Keywords -->
                ${ev.tags ? `
                <div style="margin-bottom: 16px;">
                    <div style="font-size: 12px; color: rgba(255,255,255,0.6); margin-bottom: 8px; text-transform: uppercase;">Tags / Keywords</div>
                    <div style="display: flex; flex-wrap: wrap; gap: 8px;">
                        ${String(ev.tags).split(',').map(tag => `<span style="padding: 4px 10px; border-radius: 4px; background: rgba(100,116,139,0.3); font-size: 11px;">${escapeHtml(tag.trim())}</span>`).join('')}
                    </div>
                </div>
                ` : ''}
                
                <!-- Chain of Custody -->
                <div style="margin-bottom: 16px; padding: 12px; background: rgba(0,0,0,0.2); border-radius: 8px; border: 1px solid rgba(255,255,255,0.1);">
                    <div style="font-size: 12px; color: rgba(255,255,255,0.6); margin-bottom: 8px; text-transform: uppercase;">🔒 Chain of Custody</div>
                    <div style="font-size: 12px; color: rgba(255,255,255,0.8);">
                        <div>Added by: ${escapeHtml(ev.collected_by)}</div>
                        <div>Created: ${escapeHtml(formatDateTime(ev.created_at))}</div>
                        ${ev.modified_at ? `<div>Last Modified: ${escapeHtml(formatDateTime(ev.modified_at))}</div>` : ''}
                    </div>
                </div>
                
                ${canEdit ? `
                <div style="margin-top: 24px; display: flex; gap: 12px; justify-content: flex-end;">
                    <button id="evidenceSaveBtn" style="padding: 10px 20px; border-radius: 6px; border: none; background: #3b82f6; color: #fff; cursor: pointer; font-weight: 600;">💾 Save Changes</button>
                </div>
                ` : ''}
                </div>
                <div class="incident-modal-footer">
                    ${canEdit ? `<button id="evidenceSaveBtn" class="incident-btn incident-btn-primary">💾 Save Changes</button>` : ''}
                </div>
            </div>
        </div>
    `;
    
    document.body.insertAdjacentHTML('beforeend', modalHTML);
    
    const backdrop = document.getElementById('evidenceBackdrop');
    const closeBtn = document.getElementById('evidenceDetailsClose');
    
    if (closeBtn) closeBtn.onclick = () => backdrop.remove();
    backdrop.addEventListener('click', (e) => {
        if (e.target === backdrop) backdrop.remove();
    });
    
    if (canEdit) {
        const saveBtn = document.getElementById('evidenceSaveBtn');
        if (saveBtn) {
            saveBtn.onclick = () => {
                const payload = {
                    evidence_number: ev.evidence_number,
                    title: document.getElementById('evidenceTitleEdit').value.trim(),
                    description: document.getElementById('evidenceDescEdit').value.trim(),
                    status: document.getElementById('evidenceStatusEdit').value,
                    location_details: document.getElementById('evidenceLocationEdit')?.value?.trim() || null
                };
                
                sendCallback('updateEvidence', payload, (res) => {
                    if (res && res.success) {
                        backdrop.remove();
                        const evidencePage = window.router?.pages?.get('evidence');
                        if (evidencePage) evidencePage.loadEvidence();
                    } else {
                        if (typeof mdtToast === 'function') mdtToast('Failed to update evidence', 'error');
                    }
                });
            };
        }
    }
};

// Image Enlarge Modal
window.enlargeImage = function(imageUrl) {
    // Keep legacy entrypoint for evidence details, but use the incident-styled lightbox.
    showImageLightbox(imageUrl);
};

// Create Evidence Modal
window.openNewEvidenceModal = function() {
    console.log('[EVIDENCE] Opening new evidence modal...');
    
    // Remove any existing backdrop to prevent black screen
    document.querySelectorAll('.modal-backdrop, #newEvidenceBackdrop, #newEvidenceModal').forEach(el => {
        try { el.remove(); } catch (_) {}
    });
    
    const modalHTML = `
        <div class="modal" id="newEvidenceModal" style="position: fixed; top: 0; left: 0; width: 100vw; height: 100vh; display: flex; align-items: center; justify-content: center; z-index: 10001; pointer-events: none;">
            <div class="modal-card" style="width: 700px; max-height: 90vh; overflow-y: auto; pointer-events: auto;">
                <div class="modal-header">
                    <h3>📦 Create New Evidence</h3>
                    <button class="modal-btn close-modal" onclick="closeNewEvidenceModal()">
                        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <line x1="18" y1="6" x2="6" y2="18"></line>
                            <line x1="6" y1="6" x2="18" y2="18"></line>
                        </svg>
                    </button>
                </div>
                <div class="modal-body">
                    <!-- Incident Link (Optional) -->
                    <div class="form-section">
                        <label class="form-row">
                            <span>Link to Incident (Optional)</span>
                            <select id="evidenceIncidentInput" style="min-height: 50px;">
                                <option value="">No Incident</option>
                            </select>
                        </label>
                    </div>
                    
                    <!-- Title (Required) -->
                    <div class="form-section">
                        <label class="form-row">
                            <span>Evidence Title *</span>
                            <input id="evidenceTitleInput" type="text" placeholder="e.g. Blood-stained knife, Vehicle damage photo..." />
                        </label>
                    </div>
                    
                    <!-- Description (Required) -->
                    <div class="form-section">
                        <label class="form-row">
                            <span>Evidence Description *</span>
                            <textarea id="evidenceDescriptionInput" placeholder="Detailed description of the evidence..." style="height: 100px;"></textarea>
                        </label>
                    </div>
                    
                    <!-- Photo (Required) -->
                    <div class="form-section">
                        <label class="form-row">
                            <span>Evidence Media * (Photograph)</span>
                            <button id="evidencePhotoBtn" class="modal-btn" style="width: 100%; padding: 12px; margin-top: 8px; background: rgba(59,130,246,0.2); border: 1px solid rgba(59,130,246,0.3);">📷 Take Photo</button>
                        </label>
                        <div id="evidencePhotoPreview" style="margin-top: 12px; display: none;">
                            <img id="evidencePhotoImg" style="width: 100%; border-radius: 8px;" />
                        </div>
                    </div>
                    
                    <!-- Citizens Involved -->
                    <div class="form-section">
                        <label class="form-row">
                            <span>Citizens Involved</span>
                            <input id="evidenceCitizensSearch" type="text" placeholder="Search citizens..." autocomplete="off" />
                            <div id="evidenceCitizensDropdown" class="dropdown hidden" style="max-height: 200px; overflow-y: auto; margin-top: 4px; border: 1px solid rgba(255,255,255,0.1); border-radius: 8px; background: rgba(0,0,0,0.5);"></div>
                        </label>
                        <div id="evidenceCitizensList" style="display: flex; gap: 8px; flex-wrap: wrap; margin-top: 8px;"></div>
                    </div>
                    
                    <!-- Vehicles Involved -->
                    <div class="form-section">
                        <label class="form-row">
                            <span>Vehicles Involved</span>
                            <input id="evidenceVehiclesSearch" type="text" placeholder="Search vehicles..." autocomplete="off" />
                            <div id="evidenceVehiclesDropdown" class="dropdown hidden" style="max-height: 200px; overflow-y: auto; margin-top: 4px; border: 1px solid rgba(255,255,255,0.1); border-radius: 8px; background: rgba(0,0,0,0.5);"></div>
                        </label>
                        <div id="evidenceVehiclesList" style="display: flex; gap: 8px; flex-wrap: wrap; margin-top: 8px;"></div>
                    </div>
                    
                    <!-- Weapons Involved -->
                    <div class="form-section">
                        <label class="form-row">
                            <span>Weapons Involved</span>
                            <input id="evidenceWeaponsSearch" type="text" placeholder="Search registered weapons (serial, owner, model)..." autocomplete="off" />
                            <div id="evidenceWeaponsDropdown" class="dropdown hidden" style="max-height: 200px; overflow-y: auto; margin-top: 4px; border: 1px solid rgba(255,255,255,0.1); border-radius: 8px; background: rgba(0,0,0,0.5);"></div>
                        </label>
                        <div id="evidenceWeaponsList" style="display: flex; gap: 8px; flex-wrap: wrap; margin-top: 8px;"></div>
                        <label class="form-row" style="margin-top: 8px;">
                            <span>Non-Registered Weapon Notes (optional)</span>
                            <textarea id="evidenceWeaponDescInput" placeholder="Describe non-registered weapons (e.g. 'black pistol w/ filed serial', 'kitchen knife')..." style="height: 60px;"></textarea>
                        </label>
                    </div>
                    
                    <!-- Related Charges -->
                    <div class="form-section">
                        <label class="form-row">
                            <span>Related Charges</span>
                            <input id="evidenceChargesSearch" type="text" placeholder="Search charges..." autocomplete="off" />
                            <div id="evidenceChargesDropdown" class="dropdown hidden" style="max-height: 200px; overflow-y: auto; margin-top: 4px; border: 1px solid rgba(255,255,255,0.1); border-radius: 8px; background: rgba(0,0,0,0.5);"></div>
                        </label>
                        <div id="evidenceChargesList" style="display: flex; gap: 8px; flex-wrap: wrap; margin-top: 8px;"></div>
                    </div>
                    
                    <!-- Evidence Status -->
                    <div class="form-section">
                        <label class="form-row">
                            <span>Evidence Status *</span>
                            <select id="evidenceStatusInput">
                                <option value="Collected" selected>Collected</option>
                                <option value="Logged">Logged</option>
                                <option value="Submitted">Submitted</option>
                                <option value="Released">Released</option>
                                <option value="Destroyed">Destroyed</option>
                            </select>
                        </label>
                    </div>
                    
                    <!-- Location Details -->
                    <div class="form-section">
                        <label class="form-row">
                            <span>Location Details</span>
                            <textarea id="evidenceLocationInput" placeholder="Exact location, room/area description..." style="height: 60px;"></textarea>
                        </label>
                    </div>
                    
                    <!-- Tags -->
                    <div class="form-section">
                        <label class="form-row">
                            <span>Tags / Keywords (comma-separated)</span>
                            <input id="evidenceTagsInput" type="text" placeholder="knife, blood, crime scene, suspect..." />
                        </label>
                    </div>
                </div>
                <div class="modal-footer">
                    <button class="modal-btn" id="evidenceCreateBtn" disabled style="background: #3b82f6; color: #fff; font-weight: 600;">Create Evidence</button>
                </div>
            </div>
        </div>
    `;
    
    document.body.insertAdjacentHTML('beforeend', modalHTML);
    
    let capturedImageUrl = null;
    
    let allIncidents = [];
    let allCitizens = [];
    let allVehicles = [];
    let allCharges = [];
    let allRegisteredWeapons = [];
    let selectedCitizens = [];
    let selectedVehicles = [];
    let selectedCharges = [];
    
    // Load all data
    sendCallback('pf_emsmdt:getAllIncidents', {}, (res) => {
        allIncidents = Array.isArray(res) ? res : [];
        const select = document.getElementById('evidenceIncidentInput');
        if (select) {
            select.innerHTML = '<option value="">No Incident</option>' + 
                allIncidents.map(i => `<option value="${escapeHtml(i.incidentId)}">${escapeHtml(i.incidentId)} - ${escapeHtml(i.title)}</option>`).join('');
        }
    });
    
    sendCallback('pf_emsmdt:getAllCitizens', {}, (res) => {
        allCitizens = Array.isArray(res) ? res : [];
    });
    
    sendCallback('pf_emsmdt:getAllVehicles', {}, (res) => {
        allVehicles = Array.isArray(res) ? res : [];
    });
    
    sendCallback('pf_emsmdt:getAllCharges', {}, (res) => {
        allCharges = Array.isArray(res) ? res : [];
    });

    // Load weapon registry for evidence (registered + non-registered support)
    sendCallback('getWeaponRegistry', {}, (res) => {
        const rows = (res && res.success && Array.isArray(res.weapons)) ? res.weapons : [];
        allRegisteredWeapons = rows.map(w => {
            return {
                serial: w.serial || w.serialNumber || w.weaponSerial || w.serial_number || '',
                weaponLabel: w.weaponLabel || w.weapon_label || w.weapon || w.weaponHash || '',
                ownerName: w.ownerName || w.owner_name || w.owner || w.firstname || w.lastname || '',
                citizenId: w.ownerCitizenId || w.owner_citizenid || w.citizenid || ''
            };
        }).filter(w => w.serial);
    });
    
    // Citizens search and selection
    const citizensSearch = document.getElementById('evidenceCitizensSearch');
    const citizensDropdown = document.getElementById('evidenceCitizensDropdown');
    const citizensList = document.getElementById('evidenceCitizensList');
    
    citizensSearch?.addEventListener('input', (e) => {
        const query = e.target.value.toLowerCase();
        if (!query) {
            citizensDropdown.classList.add('hidden');
            return;
        }
        const filtered = allCitizens.filter(c => 
            c.name.toLowerCase().includes(query) || c.citizenId.toLowerCase().includes(query)
        );
        if (filtered.length > 0) {
            citizensDropdown.innerHTML = filtered.map(c => 
                `<div class="dropdown-item" data-id="${escapeHtml(c.citizenId)}" data-name="${escapeHtml(c.name)}" style="padding: 8px; cursor: pointer; border-bottom: 1px solid rgba(255,255,255,0.05);">${escapeHtml(c.name)}</div>`
            ).join('');
            citizensDropdown.classList.remove('hidden');
        } else {
            citizensDropdown.classList.add('hidden');
        }
    });
    
    citizensDropdown?.addEventListener('click', (e) => {
        const item = e.target.closest('.dropdown-item');
        if (!item) return;
        const id = item.dataset.id;
        const name = item.dataset.name;
        if (!selectedCitizens.find(c => c.id === id)) {
            selectedCitizens.push({ id, name });
            citizensList.innerHTML += `<span class="chip" data-id="${escapeHtml(id)}" style="background: rgba(59,130,246,0.2); padding: 4px 8px; border-radius: 4px; display: inline-flex; align-items: center; gap: 4px;">${escapeHtml(name)}<button onclick="this.parentElement.remove()" style="background: none; border: none; color: #fff; cursor: pointer; padding: 0 4px;">×</button></span>`;
        }
        citizensSearch.value = '';
        citizensDropdown.classList.add('hidden');
    });
    
    // Vehicles search and selection
    const vehiclesSearch = document.getElementById('evidenceVehiclesSearch');
    const vehiclesDropdown = document.getElementById('evidenceVehiclesDropdown');
    const vehiclesList = document.getElementById('evidenceVehiclesList');
    
    vehiclesSearch?.addEventListener('input', (e) => {
        const query = e.target.value.toLowerCase();
        if (!query) {
            vehiclesDropdown.classList.add('hidden');
            return;
        }
        const isHashLike = (val) => {
            const s = String(val ?? '').trim();
            if (!s) return false;
            if (/^0x[0-9a-f]+$/i.test(s)) return true;
            if (/^[+-]?\d+(?:\.0+)?$/.test(s)) return true;
            return false;
        };
        const getVehicleName = (v) => {
            const ml = v?.modelLabel;
            const m = v?.model;
            if (ml && String(ml).trim() && !isHashLike(ml) && ml !== 'NULL') return String(ml);
            if (m && String(m).trim() && !isHashLike(m) && m !== 'NULL') return String(m);
            return 'Unknown';
        };

        const filtered = allVehicles.filter(v => {
            const plate = String(v.plate || '').toLowerCase();
            const name = getVehicleName(v).toLowerCase();
            return plate.includes(query) || name.includes(query);
        });
        if (filtered.length > 0) {
            vehiclesDropdown.innerHTML = filtered.map(v => 
                `<div class="dropdown-item" data-plate="${escapeHtml(v.plate)}" data-model="${escapeHtml(getVehicleName(v))}" style="padding: 8px; cursor: pointer; border-bottom: 1px solid rgba(255,255,255,0.05);">${escapeHtml(v.plate)} - ${escapeHtml(getVehicleName(v))}</div>`
            ).join('');
            vehiclesDropdown.classList.remove('hidden');
        } else {
            vehiclesDropdown.classList.add('hidden');
        }
    });
    
    vehiclesDropdown?.addEventListener('click', (e) => {
        const item = e.target.closest('.dropdown-item');
        if (!item) return;
        const plate = item.dataset.plate;
        const model = item.dataset.model;
        if (!selectedVehicles.find(v => v.plate === plate)) {
            selectedVehicles.push({ plate });
            vehiclesList.innerHTML += `<span class="chip" data-plate="${escapeHtml(plate)}" style="background: rgba(59,130,246,0.2); padding: 4px 8px; border-radius: 4px; display: inline-flex; align-items: center; gap: 4px;">${escapeHtml(plate)}<button onclick="this.parentElement.remove()" style="background: none; border: none; color: #fff; cursor: pointer; padding: 0 4px;">×</button></span>`;
        }
        vehiclesSearch.value = '';
        vehiclesDropdown.classList.add('hidden');
    });
    
    // Charges search and selection
    const chargesSearch = document.getElementById('evidenceChargesSearch');
    const chargesDropdown = document.getElementById('evidenceChargesDropdown');
    const chargesList = document.getElementById('evidenceChargesList');
    
    chargesSearch?.addEventListener('input', (e) => {
        const query = e.target.value.toLowerCase();
        if (!query) {
            chargesDropdown.classList.add('hidden');
            return;
        }
        const filtered = allCharges.filter(ch => 
            ch.code.toLowerCase().includes(query) || ch.name.toLowerCase().includes(query)
        );
        if (filtered.length > 0) {
            chargesDropdown.innerHTML = filtered.map(ch => 
                `<div class="dropdown-item" data-code="${escapeHtml(ch.code)}" data-name="${escapeHtml(ch.name)}" style="padding: 8px; cursor: pointer; border-bottom: 1px solid rgba(255,255,255,0.05);">${escapeHtml(ch.code)} - ${escapeHtml(ch.name)}</div>`
            ).join('');
            chargesDropdown.classList.remove('hidden');
        } else {
            chargesDropdown.classList.add('hidden');
        }
    });
    
    chargesDropdown?.addEventListener('click', (e) => {
        const item = e.target.closest('.dropdown-item');
        if (!item) return;
        const code = item.dataset.code;
        const name = item.dataset.name;
        if (!selectedCharges.find(ch => ch === code)) {
            selectedCharges.push(code);
            chargesList.innerHTML += `<span class="chip" data-code="${escapeHtml(code)}" style="background: rgba(59,130,246,0.2); padding: 4px 8px; border-radius: 4px; display: inline-flex; align-items: center; gap: 4px;">${escapeHtml(code)} - ${escapeHtml(name)}<button onclick="this.parentElement.remove()" style="background: none; border: none; color: #fff; cursor: pointer; padding: 0 4px;">×</button></span>`;
        }
        chargesSearch.value = '';
        chargesDropdown.classList.add('hidden');
    });
    
    // Registered weapons search and selection
    const weaponsSearch = document.getElementById('evidenceWeaponsSearch');
    const weaponsDropdown = document.getElementById('evidenceWeaponsDropdown');
    const weaponsList = document.getElementById('evidenceWeaponsList');

    weaponsSearch?.addEventListener('input', (e) => {
        const query = String(e.target.value || '').toLowerCase().trim();
        if (!query) {
            weaponsDropdown?.classList.add('hidden');
            return;
        }
        const filtered = allRegisteredWeapons
            .filter(w => (w.serial && w.serial.toLowerCase().includes(query)) || (w.weaponLabel && String(w.weaponLabel).toLowerCase().includes(query)) || (w.ownerName && String(w.ownerName).toLowerCase().includes(query)) || (w.citizenId && String(w.citizenId).toLowerCase().includes(query)))
            .slice(0, 25);

        if (filtered.length > 0 && weaponsDropdown) {
            weaponsDropdown.innerHTML = filtered.map(w => {
                const label = `${escapeHtml(w.serial)}${w.weaponLabel ? ' - ' + escapeHtml(w.weaponLabel) : ''}${w.ownerName ? ' (' + escapeHtml(w.ownerName) + ')' : ''}`;
                return `<div class="dropdown-item" data-serial="${escapeHtml(w.serial)}" data-label="${escapeHtml(w.weaponLabel || '')}" style="padding: 8px; cursor: pointer; border-bottom: 1px solid rgba(255,255,255,0.05);">${label}</div>`;
            }).join('');
            weaponsDropdown.classList.remove('hidden');
        } else {
            weaponsDropdown?.classList.add('hidden');
        }
    });

    weaponsDropdown?.addEventListener('click', (e) => {
        const item = e.target.closest('.dropdown-item');
        if (!item) return;
        const serial = item.dataset.serial;
        const label = item.dataset.label || '';
        if (!serial) return;

        // prevent duplicates
        const existing = Array.from(document.querySelectorAll('#evidenceWeaponsList .chip')).some(chip => chip.dataset.serial === serial);
        if (!existing && weaponsList) {
            weaponsList.innerHTML += `<span class="chip" data-serial="${escapeHtml(serial)}" style="background: rgba(59,130,246,0.2); padding: 4px 8px; border-radius: 4px; display: inline-flex; align-items: center; gap: 4px;">${escapeHtml(serial)}${label ? ' - ' + escapeHtml(label) : ''}<button onclick="this.parentElement.remove()" style="background: none; border: none; color: #fff; cursor: pointer; padding: 0 4px;">×</button></span>`;
        }
        weaponsSearch.value = '';
        weaponsDropdown.classList.add('hidden');
    });
    
    // Photo button handler
    document.getElementById('evidencePhotoBtn')?.addEventListener('click', () => {
        sendCallback('mdt:takeEvidencePhoto', {}, (result) => {
            if (result && result.success && result.imageUrl) {
                capturedImageUrl = result.imageUrl;
                const preview = document.getElementById('evidencePhotoPreview');
                const img = document.getElementById('evidencePhotoImg');
                if (preview && img) {
                    img.src = result.imageUrl;
                    preview.style.display = 'block';
                }
                checkFormValidity();
            }
        }, { timeoutMs: 120000 });
    });
    
    // Form validation
    function checkFormValidity() {
        const title = document.getElementById('evidenceTitleInput')?.value?.trim();
        const description = document.getElementById('evidenceDescriptionInput')?.value?.trim();
        const btn = document.getElementById('evidenceCreateBtn');
        if (btn) {
            btn.disabled = !(title && description && capturedImageUrl);
        }
    }
    
    document.getElementById('evidenceTitleInput')?.addEventListener('input', checkFormValidity);
    document.getElementById('evidenceDescriptionInput')?.addEventListener('input', checkFormValidity);
    
    // Create button handler
    document.getElementById('evidenceCreateBtn')?.addEventListener('click', () => {
        const title = document.getElementById('evidenceTitleInput')?.value?.trim();
        const description = document.getElementById('evidenceDescriptionInput')?.value?.trim();
        const incidentId = document.getElementById('evidenceIncidentInput')?.value?.trim() || null;
        const tags = document.getElementById('evidenceTagsInput')?.value?.trim() || '';
        const locationDetails = document.getElementById('evidenceLocationInput')?.value?.trim() || '';
        const status = document.getElementById('evidenceStatusInput')?.value || 'Collected';
        const weaponDesc = document.getElementById('evidenceWeaponDescInput')?.value?.trim() || '';
        
        // Gather selected items from chips
        const citizensInvolved = Array.from(document.querySelectorAll('#evidenceCitizensList .chip')).map(chip => ({
            id: chip.dataset.id,
            name: chip.textContent.replace('×', '').trim()
        }));
        
        const vehiclesInvolved = Array.from(document.querySelectorAll('#evidenceVehiclesList .chip')).map(chip => ({
            plate: chip.dataset.plate
        }));
        
        const relatedCharges = Array.from(document.querySelectorAll('#evidenceChargesList .chip')).map(chip => chip.dataset.code);

        // Handle weapons (registered serials + optional non-registered notes)
        const registeredSerials = Array.from(document.querySelectorAll('#evidenceWeaponsList .chip')).map(chip => chip.dataset.serial).filter(Boolean);
        let weaponsInvolved = '';
        if (registeredSerials.length > 0) {
            weaponsInvolved += `Registered: ${registeredSerials.join(', ')}`;
        }
        if (weaponDesc) {
            weaponsInvolved += (weaponsInvolved ? ' | ' : '') + `Non-Registered: ${weaponDesc}`;
        }
        
        if (!title || !description) {
            if (typeof mdtToast === 'function') mdtToast('Title and Description are required', 'error');
            return;
        }
        
        if (!capturedImageUrl) {
            if (typeof mdtToast === 'function') mdtToast('Photo is required', 'error');
            return;
        }
        
        // Non-registered notes are optional; registered selection is optional.
        
        sendCallback('pf_emsmdt:createEvidence', {
            title,
            description,
            incidentId,
            tags,
            locationDetails,
            status,
            imageUrl: capturedImageUrl,
            citizensInvolved,
            vehiclesInvolved,
            weaponsInvolved,
            relatedCharges
        }, (result) => {
            if (result && result.success) {
                closeNewEvidenceModal();
                if (typeof mdtToast === 'function') mdtToast('Evidence created: #' + result.evidenceNumber, 'success');
                const evidencePage = window.router?.pages?.get('evidence');
                if (evidencePage) evidencePage.loadEvidence();
            } else {
                if (typeof mdtToast === 'function') mdtToast('Failed to create evidence: ' + (result?.error || 'Unknown error'), 'error');
            }
        });
    });
    
    // Close handlers
    const backdrop = document.getElementById('newEvidenceBackdrop');
    backdrop?.addEventListener('click', (e) => {
        if (e.target === backdrop) closeNewEvidenceModal();
    });
};

window.closeNewEvidenceModal = function() {
    document.getElementById('newEvidenceModal')?.remove();
};

// NUI Message handlers for MDT close/restore
window.addEventListener('message', (event) => {
    const data = event.data;
    
    if (data.action === 'closeMDTForScreenshot') {
        // Store current page state and modal visibility
        const allModals = document.querySelectorAll('.modal, .modal-backdrop, [id*="Modal"]');
        const visibleModals = [];
        
        allModals.forEach(modal => {
            // Skip the incident modal (it uses inline styles, not the .modal class system)
            if (modal.id === 'newIncidentModal') return;
            
            if (modal && !modal.classList.contains('hidden') && modal.style.display !== 'none') {
                visibleModals.push({
                    id: modal.id,
                    className: modal.className
                });
                modal.style.display = 'none';
            }
        });
        
        window.__mdtScreenshotState = {
            currentPage: window.router?.current || 'dashboard',
            visibleModals: visibleModals,
            tabletWasHidden: document.getElementById('tabletFrame')?.classList.contains('hidden') === true
        };
        
        // Hide the MDT completely (including tablet frame)
        const app = document.getElementById('app');
        if (app) app.classList.add('hidden');

        const tablet = document.getElementById('tabletFrame');
        if (tablet) tablet.classList.add('hidden');
    }
    
    if (data.action === 'restoreMDTAfterScreenshot') {
        // Show the MDT again
        const app = document.getElementById('app');
        if (app) app.classList.remove('hidden');

        // Restore tablet frame visibility
        const tablet = document.getElementById('tabletFrame');
        if (tablet) {
            const shouldStayHidden = window.__mdtScreenshotState && window.__mdtScreenshotState.tabletWasHidden === true;
            if (!shouldStayHidden) tablet.classList.remove('hidden');
        }
        
        // Restore modals that were visible
        if (window.__mdtScreenshotState && window.__mdtScreenshotState.visibleModals) {
            setTimeout(() => {
                window.__mdtScreenshotState.visibleModals.forEach(modalInfo => {
                    if (modalInfo.id) {
                        const modal = document.getElementById(modalInfo.id);
                        if (modal) {
                            modal.style.display = '';
                        }
                    }
                });
                
                // Ensure no residual black backgrounds
                document.querySelectorAll('.modal, .modal-backdrop').forEach(el => {
                    if (!el.classList.contains('hidden')) {
                        el.style.backgroundColor = 'transparent !important';
                        el.style.background = 'none !important';
                    }
                });
            }, 100);
        }
        
        // Restore previous page if stored
        if (window.__mdtScreenshotState && window.__mdtScreenshotState.currentPage) {
            const page = window.__mdtScreenshotState.currentPage;
            if (window.router && window.router.navigate) {
                window.router.navigate(page);
            }
        }
    }
});

// EMS MDT: Evidence/PD modules are disabled; do not expose/register EvidencePage.

// Report Photos helpers
function renderReportPhotos() {
    const grid = document.getElementById('reportPhotosGrid');
    if (!grid) return;
    const photos = Array.isArray(window.__selectedReportPhotos) ? window.__selectedReportPhotos : [];
    if (!photos.length) {
        grid.innerHTML = '<div class="empty-message" style="grid-column:1/-1;">No photos</div>';
        return;
    }
    const escJs = (s) => escapeJsAttr(s); // JS-string + HTML-attribute safe (see app.js)
    grid.innerHTML = photos.map((p, i) => {
        const url = safeUrl(p?.url);
        const title = String(p?.title || '').trim();
        return `
            <div class="photo-thumb" style="position:relative;">
                <img src="${escapeHtml(url)}" alt="Report Photo" style="width:100%;height:100px;object-fit:cover;border-radius:8px;cursor:pointer;border:1px solid rgba(255,255,255,0.15)" onclick="showImageLightbox('${escJs(url)}')" />
                <button class="modal-btn" style="position:absolute;top:6px;right:6px;padding:4px 8px;" onclick="removeReportPhoto(${i})">✕</button>
                ${title ? `<div class="muted" style="font-size:12px;margin-top:4px;">${escapeHtml(title)}</div>` : ''}
            </div>
        `;
    }).join('');
}

function addReportPhotoFromUrl() {
    const input = document.getElementById('reportPhotoUrlInput');
    const url = String(input?.value || '').trim();
    if (!url) return;
    if (!/^https?:\/\//i.test(url)) {
        if (typeof mdtToast === 'function') mdtToast('Please enter a valid http(s) image URL', 'error');
        return;
    }
    if (!Array.isArray(window.__selectedReportPhotos)) window.__selectedReportPhotos = [];
    window.__selectedReportPhotos.push({ url, title: '' });
    if (input) input.value = '';
    renderReportPhotos();
}

function removeReportPhoto(index) {
    if (!Array.isArray(window.__selectedReportPhotos)) window.__selectedReportPhotos = [];
    window.__selectedReportPhotos = window.__selectedReportPhotos.filter((_, i) => i !== Number(index));
    renderReportPhotos();
}

function takeReportPhoto() {
    // Reuse the evidence photo capture pipeline
    sendCallback('mdt:takeEvidencePhoto', {}, (result) => {
        if (result && result.success && result.imageUrl) {
            if (!Array.isArray(window.__selectedReportPhotos)) window.__selectedReportPhotos = [];
            window.__selectedReportPhotos.push({ url: result.imageUrl, title: '' });
            renderReportPhotos();
        } else {
            if (typeof mdtToast === 'function') mdtToast((result && result.error) ? String(result.error) : 'Failed to capture photo', 'error');
        }
    }, { timeoutMs: 120000 });
}