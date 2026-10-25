// ============================================================================
// POLICE MDT - Extended Modules
// Citizen Search, Vehicle Search/Profile, Warrants, Incidents, Reports, FTO
// ============================================================================

function renderRteContent(content) {
    const raw = String(content || '');
    if (!raw) return '';
    const hasTag = /<\/?[a-z][\s\S]*?>/i.test(raw);
    if (hasTag) return (typeof sanitizeRteHtml === 'function') ? sanitizeRteHtml(raw) : escapeHtml(raw);
    const lines = raw.split(/\r?\n/);
    const cleaned = [];
    let skipping = true;
    for (const line of lines) {
        const t = line.trim();
        if (skipping && (t === '' || t === 'H1' || t === 'H2' || t === 'H3')) {
            continue;
        }
        skipping = false;
        cleaned.push(line);
    }
    return escapeHtml(cleaned.join('\n')).replace(/\n/g, '<br>');
}

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

function getColorInfo(colorId) {
    const fallback = { name: 'Unknown', rgb: [80, 80, 80], hex: '#505050' };
    const idNum = Number(colorId);
    if (!Number.isFinite(idNum)) return fallback;
    const entry = GTA_COLOR_PALETTE[idNum];
    if (!entry || !Array.isArray(entry.rgb)) return fallback;
    return { name: entry.name || 'Unknown', rgb: entry.rgb, hex: rgbToHex(entry.rgb[0], entry.rgb[1], entry.rgb[2]) };
}

// ============================================================================
// CUSTOM CONFIRM DIALOG
// ============================================================================
window.mdtConfirm = function(message) {
    return new Promise((resolve) => {
        const modalHTML = `
            <div class="mdt-confirm-backdrop" id="mdtConfirmBackdrop" style="position: fixed; inset: 0; background: rgba(0,0,0,0.7); display: flex; align-items: center; justify-content: center; z-index: 99999;">
                <div class="mdt-confirm-modal" style="background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); border-radius: 12px; padding: 24px; min-width: 400px; max-width: 500px; box-shadow: 0 25px 50px -12px rgba(0,0,0,0.5); border: 1px solid rgba(59,130,246,0.3);">
                    <div style="font-size: 18px; font-weight: 600; margin-bottom: 16px; color: #fff;">${escapeHtml(message)}</div>
                    <div style="display: flex; gap: 12px; justify-content: flex-end;">
                        <button id="mdtConfirmCancel" style="padding: 10px 20px; border-radius: 6px; border: 1px solid rgba(255,255,255,0.2); background: rgba(255,255,255,0.1); color: #fff; cursor: pointer; font-size: 14px; font-weight: 500;">Cancel</button>
                        <button id="mdtConfirmOk" style="padding: 10px 20px; border-radius: 6px; border: none; background: #3b82f6; color: #fff; cursor: pointer; font-size: 14px; font-weight: 500;">Confirm</button>
                    </div>
                </div>
            </div>
        `;
        
        document.body.insertAdjacentHTML('beforeend', modalHTML);
        const backdrop = document.getElementById('mdtConfirmBackdrop');
        
        const cleanup = (result) => {
            backdrop.remove();
            resolve(result);
        };
        
        document.getElementById('mdtConfirmOk').onclick = () => cleanup(true);
        document.getElementById('mdtConfirmCancel').onclick = () => cleanup(false);
        backdrop.addEventListener('click', (e) => {
            if (e.target === backdrop) cleanup(false);
        });
    });
};

// ============================================================================
// CUSTOM PROMPT DIALOG (NO BROWSER POPUPS)
// ============================================================================
window.mdtPrompt = function(message, options) {
    const opts = options && typeof options === 'object' ? options : {};
    const placeholder = String(opts.placeholder || '');
    const defaultValue = (opts.defaultValue === undefined || opts.defaultValue === null) ? '' : String(opts.defaultValue);
    const required = opts.required === true;
    const title = String(opts.title || 'Input');
    const okText = String(opts.okText || 'OK');
    const cancelText = String(opts.cancelText || 'Cancel');

    return new Promise((resolve) => {
        const modalHTML = `
            <div class="mdt-confirm-backdrop" id="mdtPromptBackdrop" style="position: fixed; inset: 0; background: rgba(0,0,0,0.7); display: flex; align-items: center; justify-content: center; z-index: 99999;">
                <div class="mdt-confirm-modal" style="background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); border-radius: 12px; padding: 24px; min-width: 420px; max-width: 560px; box-shadow: 0 25px 50px -12px rgba(0,0,0,0.5); border: 1px solid rgba(59,130,246,0.3);">
                    <div style="font-size: 16px; font-weight: 800; margin-bottom: 10px; color: #fff;">${escapeHtml(title)}</div>
                    <div style="font-size: 14px; font-weight: 600; margin-bottom: 12px; color: rgba(255,255,255,0.9);">${escapeHtml(message)}</div>
                    <textarea id="mdtPromptInput" placeholder="${escapeHtml(placeholder)}" style="width: 100%; min-height: 90px; resize: vertical; padding: 10px 12px; border-radius: 10px; border: 1px solid rgba(255,255,255,0.18); background: rgba(0,0,0,0.25); color: #fff; font-size: 13px; font-family: inherit; outline: none;">${escapeHtml(defaultValue)}</textarea>
                    <div style="display: flex; gap: 12px; justify-content: flex-end; margin-top: 14px;">
                        <button id="mdtPromptCancel" style="padding: 10px 20px; border-radius: 6px; border: 1px solid rgba(255,255,255,0.2); background: rgba(255,255,255,0.1); color: #fff; cursor: pointer; font-size: 14px; font-weight: 600;">${escapeHtml(cancelText)}</button>
                        <button id="mdtPromptOk" style="padding: 10px 20px; border-radius: 6px; border: none; background: #3b82f6; color: #fff; cursor: pointer; font-size: 14px; font-weight: 700;">${escapeHtml(okText)}</button>
                    </div>
                </div>
            </div>
        `;

        document.body.insertAdjacentHTML('beforeend', modalHTML);
        const backdrop = document.getElementById('mdtPromptBackdrop');
        const input = document.getElementById('mdtPromptInput');

        const cleanup = (value) => {
            try { backdrop.remove(); } catch (_) {}
            resolve(value);
        };

        const submit = () => {
            const val = String(input?.value || '').trim();
            if (required && !val) {
                if (typeof mdtToast === 'function') mdtToast('This field is required', 'error');
                return;
            }
            cleanup(val);
        };

        document.getElementById('mdtPromptOk').onclick = submit;
        document.getElementById('mdtPromptCancel').onclick = () => cleanup(null);
        backdrop.addEventListener('click', (e) => { if (e.target === backdrop) cleanup(null); });
        document.addEventListener('keydown', function onKey(e) {
            if (!document.getElementById('mdtPromptBackdrop')) {
                document.removeEventListener('keydown', onKey);
                return;
            }
            if (e.key === 'Escape') cleanup(null);
            if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') submit();
        });

        try { input?.focus(); input?.setSelectionRange(input.value.length, input.value.length); } catch (_) {}
    });
};

window.openManualEntryForm = function(options) {
    const cfg = (options && typeof options === 'object') ? options : {};
    const title = String(cfg.title || 'New Entry');
    const submitText = String(cfg.submitText || 'Save');
    const fields = Array.isArray(cfg.fields) ? cfg.fields : [];

    return new Promise((resolve) => {
        const fieldsHtml = fields.map((f) => {
            const key = String(f.key || 'field');
            const label = String(f.label || key);
            const type = String(f.type || 'text').toLowerCase();
            const placeholder = String(f.placeholder || '');
            const required = f.required === true;
            const value = f.value == null ? '' : String(f.value);

            if (type === 'textarea') {
                return `
                    <label class="form-row" style="margin-bottom:10px;">
                        <span>${escapeHtml(label)}${required ? ' *' : ''}</span>
                        <textarea data-manual-key="${escapeHtml(key)}" rows="3" placeholder="${escapeHtml(placeholder)}" ${required ? 'data-required="1"' : ''}>${escapeHtml(value)}</textarea>
                    </label>
                `;
            }

            return `
                <label class="form-row" style="margin-bottom:10px;">
                    <span>${escapeHtml(label)}${required ? ' *' : ''}</span>
                    <input data-manual-key="${escapeHtml(key)}" type="${escapeHtml(type)}" value="${escapeHtml(value)}" placeholder="${escapeHtml(placeholder)}" ${required ? 'data-required="1"' : ''} />
                </label>
            `;
        }).join('');

        const html = `
            <div id="mdtManualEntryBackdrop" class="mdt-confirm-backdrop" style="position: fixed; inset: 0; background: rgba(0,0,0,0.7); display: flex; align-items: center; justify-content: center; z-index: 100000;">
                <div class="mdt-confirm-modal" style="background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%); border-radius: 12px; padding: 18px; min-width: 520px; max-width: 700px; max-height: 88vh; overflow-y: auto; box-shadow: 0 25px 50px -12px rgba(0,0,0,0.5); border: 1px solid rgba(59,130,246,0.3);">
                    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px;">
                        <div style="font-size:18px; font-weight:800; color:#fff;">${escapeHtml(title)}</div>
                        <button id="mdtManualEntryClose" style="background:none; border:none; color:#fff; cursor:pointer; font-size:18px;">x</button>
                    </div>
                    <div id="mdtManualEntryError" style="display:none; margin-bottom:10px; color:#fecaca; font-size:12px;"></div>
                    <div>${fieldsHtml}</div>
                    <div style="display:flex; gap:10px; justify-content:flex-end; margin-top:10px;">
                        <button id="mdtManualEntryCancel" style="padding:10px 18px; border-radius:6px; border:1px solid rgba(255,255,255,0.2); background: rgba(255,255,255,0.1); color:#fff; cursor:pointer;">Cancel</button>
                        <button id="mdtManualEntrySave" style="padding:10px 18px; border-radius:6px; border:none; background:#3b82f6; color:#fff; cursor:pointer; font-weight:700;">${escapeHtml(submitText)}</button>
                    </div>
                </div>
            </div>
        `;

        document.body.insertAdjacentHTML('beforeend', html);
        const backdrop = document.getElementById('mdtManualEntryBackdrop');
        const errorEl = document.getElementById('mdtManualEntryError');

        const close = (value) => {
            try { backdrop.remove(); } catch (_) {}
            resolve(value);
        };

        const save = () => {
            const out = {};
            const inputs = backdrop.querySelectorAll('[data-manual-key]');
            for (const el of inputs) {
                const key = String(el.getAttribute('data-manual-key') || '');
                const val = String(el.value || '').trim();
                const required = el.getAttribute('data-required') === '1';
                if (required && !val) {
                    if (errorEl) {
                        errorEl.textContent = 'Please fill all required fields.';
                        errorEl.style.display = 'block';
                    }
                    return;
                }
                out[key] = val;
            }
            close(out);
        };

        document.getElementById('mdtManualEntryClose')?.addEventListener('click', () => close(null));
        document.getElementById('mdtManualEntryCancel')?.addEventListener('click', () => close(null));
        document.getElementById('mdtManualEntrySave')?.addEventListener('click', save);
        backdrop?.addEventListener('click', (e) => { if (e.target === backdrop) close(null); });
    });
};

// ============================================================================
// CITIZEN SEARCH PAGE
// ============================================================================
class CitizenSearchPage extends BasePage {
    constructor() {
        super('citizens', 'Citizen Search');
        this.currentPage = 1;
        this.pageSize = 9;
        this.searchQuery = '';
        this.citizens = [];
        this.totalCount = 0;
        this.searchTimeout = null;
        this.autoRefreshInterval = null;
        this.startAutoRefresh();
    }

    startAutoRefresh() {
        this.autoRefreshInterval = setInterval(() => {
            if (this.searchQuery.trim()) {
                console.log('[MDT AUTO-REFRESH] Refreshing citizen search');
                this.search();
            }
        }, 300000);
    }

    cleanup() {
        if (this.autoRefreshInterval) clearInterval(this.autoRefreshInterval);
        if (this.searchTimeout) clearTimeout(this.searchTimeout);
    }

    mount(root) {
        super.mount(root);
        const canCreateManual = !!(window.mdtConfig && window.mdtConfig.manualEntriesEnabled && userPermissions && userPermissions.allowed);
        root.innerHTML = `
            <div class="search-page-container charges-page weapons-page">
                <div class="search-page-header">
                    <div class="search-page-title-group">
                        <h2>Citizen Search</h2>
                        <div class="search-page-subtitle">Citizen Database</div>
                    </div>
                    ${canCreateManual ? '<button id="newCitizenEntryBtn" class="page-action-btn">+ New Entry</button>' : ''}
                </div>
                <div class="search-page-controls">
                    <input type="text" id="citizenSearchInput" class="search-page-input" placeholder="Search citizens by name, ID, or phone..." />
                </div>
                <div id="citizenGrid" class="results-grid"></div>
                <div class="pagination-footer">
                    <span id="citizenPaginationText">Showing 1 to 0 of 0 Citizens</span>
                    <div class="pagination-buttons">
                        <button id="citizenPrevBtn" class="pagination-btn">Previous</button>
                        <button id="citizenNextBtn" class="pagination-btn">Next</button>
                    </div>
                </div>
            </div>
        `;
        this.attachListeners();
        this.loadCitizens();
    }

    attachListeners() {
        const input = document.getElementById('citizenSearchInput');
        if (input) {
            input.addEventListener('input', (e) => {
                this.searchQuery = e.target.value;
                clearTimeout(this.searchTimeout);
                this.searchTimeout = setTimeout(() => {
                    this.currentPage = 1;
                    this.loadCitizens();
                }, 300);
            });
        }
        document.getElementById('citizenPrevBtn')?.addEventListener('click', () => {
            if (this.currentPage > 1) {
                this.currentPage--;
                this.loadCitizens();
            }
        });
        document.getElementById('citizenNextBtn')?.addEventListener('click', () => {
            const maxPage = Math.ceil(this.totalCount / this.pageSize);
            if (this.currentPage < maxPage) {
                this.currentPage++;
                this.loadCitizens();
            }
        });
        document.getElementById('newCitizenEntryBtn')?.addEventListener('click', () => this.openManualCitizenForm());
    }

    async openManualCitizenForm() {
        const values = await window.openManualEntryForm({
            title: 'New Citizen Entry',
            submitText: 'Create Citizen',
            fields: [
                { key: 'citizenId', label: 'Citizen ID', placeholder: 'Optional custom ID' },
                { key: 'firstname', label: 'First Name', required: true },
                { key: 'lastname', label: 'Last Name', required: true },
                { key: 'dob', label: 'Date of Birth', type: 'date' },
                { key: 'phone', label: 'Phone Number' },
                { key: 'nationality', label: 'Nationality' },
                { key: 'gender', label: 'Gender' },
                { key: 'job', label: 'Occupation' },
                { key: 'address', label: 'Address' },
                { key: 'profilePicture', label: 'Picture URL', placeholder: 'https://...' }
            ]
        });

        if (!values) return;

        sendCallback('createManualCitizen', values, (res) => {
            if (res && res.success) {
                if (typeof mdtToast === 'function') mdtToast('Citizen entry created', 'success');
                this.currentPage = 1;
                this.loadCitizens();
            } else {
                if (typeof mdtToast === 'function') mdtToast((res && res.error) ? String(res.error) : 'Failed to create citizen entry', 'error');
            }
        });
    }

    loadCitizens() {
        sendCallback('searchCitizens', {
            query: this.searchQuery,
            page: this.currentPage,
            pageSize: this.pageSize
        });
    }

    onMessage(data) {
        if (data.action === 'setCitizens') {
            this.citizens = data.citizens || [];
            this.totalCount = data.totalCount || 0;
            this.renderCitizens();
            this.updatePagination();
        }
    }

    renderCitizens() {
        const grid = document.getElementById('citizenGrid');
        if (!grid) return;

        if (this.citizens.length === 0) {
            grid.innerHTML = '<div class="empty-message" style="grid-column: 1/-1;">No citizens found</div>';
            return;
        }

        grid.innerHTML = this.citizens.map(citizen => {
            const warrant = citizen.hasWarrant ? '<div class="card-badge warrant-badge">Warrant</div>' : '';
            const dangerous = citizen.isDangerous ? '<div class="card-badge dangerous-badge">Dangerous</div>' : '';
            const licenseLabels = (() => {
                if (Array.isArray(citizen.licenses)) return citizen.licenses;
                const map = { driver: 'Driver License', weapon: 'Weapon License', business: 'Business License' };
                return Object.entries(citizen.licenses || {}).filter(([, v]) => v).map(([k]) => map[k] || k);
            })();
            const licenses = licenseLabels.slice(0, 3).join(', ') || 'No licenses';
            const licenseText = licenseLabels.length > 3 ? `+${licenseLabels.length - 3}` : '';

            return `
                <div class="citizen-card" onclick="router.openCitizenProfile('${citizen.citizenId}')">
                    ${warrant}${dangerous}
                    <div class="card-avatar"><span>${(citizen.name || 'N')[0]}</span></div>
                    <div class="card-name">${citizen.name || 'Unknown'}</div>
                    <div class="card-id">#${citizen.citizenId || ''}</div>
                    <div class="card-info-grid">
                        <div class="card-info-left">
                            <div class="info-row"><span class="label">Nationality:</span> <span>${citizen.nationality || 'Unknown'}</span></div>
                            <div class="info-row"><span class="label">Job:</span> <span>${citizen.job || 'Unknown'}</span></div>
                            <div class="info-row"><span class="label">Licenses:</span></div>
                            <div style="display: flex; gap: 4px; flex-wrap: wrap; margin-top: 4px;">
                                ${licenseLabels.slice(0, 3).map(lic => `<span class="license-badge">${lic}</span>`).join('')}
                                ${licenseText ? `<span class="license-badge">+${licenseText}</span>` : ''}
                            </div>
                        </div>
                        <div class="card-info-right">
                            <div class="info-row"><span class="label">DOB:</span> <span>${citizen.dob || 'Unknown'}</span></div>
                            <div class="info-row"><span class="label">Phone:</span> <span>${citizen.phone || 'Unknown'}</span></div>
                        </div>
                    </div>
                </div>
            `;
        }).join('');
    }

    updatePagination() {
        const maxPage = Math.ceil(this.totalCount / this.pageSize);
        const start = (this.currentPage - 1) * this.pageSize + 1;
        const end = Math.min(this.currentPage * this.pageSize, this.totalCount);
        document.getElementById('citizenPaginationText').textContent = `Showing ${start} to ${end} of ${this.totalCount} Citizens`;
        document.getElementById('citizenPrevBtn').disabled = this.currentPage <= 1;
        document.getElementById('citizenNextBtn').disabled = this.currentPage >= maxPage;
    }
}

// ============================================================================
// VEHICLE SEARCH PAGE
// ============================================================================
class VehicleSearchPage extends BasePage {
    constructor() {
        super('vehicles', 'Vehicle Database');
        this.currentPage = 1;
        this.pageSize = 18;
        this.searchQuery = '';
        this.vehicles = [];
        this.totalCount = 0;
        this.searchTimeout = null;
        this.autoRefreshInterval = null;
        this.mode = 'search'; // 'owned' or 'search'
        this.startAutoRefresh();
    }

    startAutoRefresh() {
        this.autoRefreshInterval = setInterval(() => {
            if (this.searchQuery.trim()) {
                console.log('[MDT AUTO-REFRESH] Refreshing vehicle search');
                this.loadVehicles();
            }
        }, 300000);
    }

    cleanup() {
        if (this.autoRefreshInterval) clearInterval(this.autoRefreshInterval);
        if (this.searchTimeout) clearTimeout(this.searchTimeout);
    }

    mount(root) {
        super.mount(root);
        const canCreateManual = !!(window.mdtConfig && window.mdtConfig.manualEntriesEnabled && userPermissions && userPermissions.allowed);
        root.innerHTML = `
            <div class="search-page-container">
                <div class="search-page-header">
                    <div class="search-page-title-group">
                        <h2>Vehicle Database</h2>
                        <div class="search-page-subtitle">Vehicle Search</div>
                    </div>
                    ${canCreateManual ? '<button id="newVehicleEntryBtn" class="page-action-btn">+ New Entry</button>' : ''}
                </div>
                <div class="search-page-controls">
                    <input type="text" id="vehicleSearchInput" class="search-page-input" placeholder="Search vehicles by plate, owner, model..." />
                </div>
                <div id="vehicleGrid" class="results-grid"></div>
                <div class="pagination-footer">
                    <span id="vehiclePaginationText">Showing 1 to 0 of 0 Vehicles</span>
                    <div class="pagination-buttons">
                        <button id="vehiclePrevBtn" class="pagination-btn">Previous</button>
                        <button id="vehicleNextBtn" class="pagination-btn">Next</button>
                    </div>
                </div>
            </div>
        `;
        this.attachListeners();
        this.loadVehicles();
    }

    attachListeners() {
        const input = document.getElementById('vehicleSearchInput');
        if (input) {
            input.addEventListener('input', (e) => {
                this.searchQuery = e.target.value;
                clearTimeout(this.searchTimeout);
                this.searchTimeout = setTimeout(() => {
                    this.currentPage = 1;
                    this.loadVehicles();
                }, 300);
            });
        }
        document.getElementById('vehiclePrevBtn')?.addEventListener('click', () => {
            if (this.currentPage > 1) {
                this.currentPage--;
                this.loadVehicles();
            }
        });
        document.getElementById('vehicleNextBtn')?.addEventListener('click', () => {
            const maxPage = Math.ceil(this.totalCount / this.pageSize);
            if (this.currentPage < maxPage) {
                this.currentPage++;
                this.loadVehicles();
            }
        });
        document.getElementById('newVehicleEntryBtn')?.addEventListener('click', () => this.openManualVehicleForm());
    }

    async openManualVehicleForm() {
        const values = await window.openManualEntryForm({
            title: 'New Vehicle Entry',
            submitText: 'Create Vehicle',
            fields: [
                { key: 'plate', label: 'Plate', required: true },
                { key: 'ownerCitizenId', label: 'Owner Citizen ID' },
                { key: 'ownerName', label: 'Owner Name' },
                { key: 'model', label: 'Model Key/Hash', required: true },
                { key: 'modelLabel', label: 'Display Model Name' },
                { key: 'brand', label: 'Brand' },
                { key: 'primaryColorId', label: 'Primary Color ID', type: 'number' },
                { key: 'secondaryColorId', label: 'Secondary Color ID', type: 'number' },
                { key: 'vehiclePhoto', label: 'Picture URL', placeholder: 'https://...' }
            ]
        });

        if (!values) return;

        sendCallback('createManualVehicle', values, (res) => {
            if (res && res.success) {
                if (typeof mdtToast === 'function') mdtToast('Vehicle entry created', 'success');
                this.currentPage = 1;
                this.loadVehicles();
            } else {
                if (typeof mdtToast === 'function') mdtToast((res && res.error) ? String(res.error) : 'Failed to create vehicle entry', 'error');
            }
        });
    }

    loadVehicles() {
        sendCallback('searchVehicles', {
            query: this.searchQuery,
            page: this.currentPage,
            pageSize: this.pageSize
        });
    }

    onMessage(data) {
        if (data.action === 'setVehicles') {
            this.vehicles = data.vehicles || [];
            this.totalCount = data.totalCount || 0;
            this.renderVehicles();
            this.updatePagination();
        }
    }

    renderVehicles() {
        const grid = document.getElementById('vehicleGrid');
        if (!grid) return;

        if (this.vehicles.length === 0) {
            grid.innerHTML = '<div class="empty-message" style="grid-column: 1/-1;">No vehicles found</div>';
            return;
        }

        const isHashLike = (val) => {
            const s = String(val ?? '').trim();
            if (!s) return false;
            if (/^0x[0-9a-f]+$/i.test(s)) return true;
            // hashes are commonly stored as signed ints, sometimes with trailing .0
            if (/^[+-]?\d+(?:\.0+)?$/.test(s)) return true;
            return false;
        };

        grid.innerHTML = this.vehicles.map(vehicle => {
            const name = 
                (vehicle.modelLabel && vehicle.modelLabel !== 'NULL' && vehicle.modelLabel.trim() && !isHashLike(vehicle.modelLabel)) ? vehicle.modelLabel :
                (vehicle.model && String(vehicle.model).trim() && !isHashLike(vehicle.model)) ? vehicle.model :
                `Unknown Model (${vehicle.plate})`;
            const brand = vehicle.brand && vehicle.brand.trim() ? vehicle.brand : null;
            const displayName = brand ? `${brand} ${name}` : name;

            const activeFlag = String(vehicle.activeFlag || '').trim();
            const flagBadge = (() => {
                if (!activeFlag) return '';
                const low = activeFlag.toLowerCase();
                // Reuse existing badge styles (no new colors):
                if (low.includes('danger')) return `<div class="card-badge dangerous-badge">${escapeHtml(activeFlag)}</div>`;
                if (low.includes('stolen')) return `<div class="card-badge status-badge status-stolen">${escapeHtml(activeFlag)}</div>`;
                if (low.includes('bolo')) return `<div class="card-badge status-badge status-bolo">${escapeHtml(activeFlag)}</div>`;
                return `<div class="card-badge status-badge status-bolo">${escapeHtml(activeFlag)}</div>`;
            })();

            // Color chips from mods.color1 / mods.color2
            const pInfo = getColorInfo(vehicle.primaryColorId);
            const sInfo = getColorInfo(vehicle.secondaryColorId);
            const colorChips = `
                <div style="display:flex; align-items:center; gap:8px;">
                    <div title="Primary: ${escapeHtml(pInfo.name)}" style="width:14px;height:14px;border-radius:3px;border:1px solid rgba(255,255,255,0.35); background:${pInfo.hex}"></div>
                    <div title="Secondary: ${escapeHtml(sInfo.name)}" style="width:14px;height:14px;border-radius:3px;border:1px solid rgba(255,255,255,0.35); background:${sInfo.hex}"></div>
                    <div class="muted" style="font-size:11px;opacity:.8;">Primary / Secondary</div>
                </div>`;
            
            return `
                <div class="vehicle-card" style="padding: 16px; background: rgba(255,255,255,0.02); border: 1px solid rgba(255,255,255,0.1); border-radius: 8px; cursor: pointer; transition: all 0.2s;" onmouseover="this.style.background='rgba(255,255,255,0.05)'; this.style.borderColor='rgba(255,255,255,0.2)'" onmouseout="this.style.background='rgba(255,255,255,0.02)'; this.style.borderColor='rgba(255,255,255,0.1)'" onclick="router.openVehicleProfile('${vehicle.plate}')">
                    ${flagBadge}
                    <div style="display: flex; gap: 12px; margin-bottom: 12px;">
                        <div style="flex-shrink: 0;">
                            <div style="width: 60px; height: 60px; border-radius: 50%; background: rgba(255,255,255,0.1); display: flex; align-items: center; justify-content: center; border: 2px solid rgba(255,255,255,0.2); overflow: hidden;">
                                <img src="${vehicle.photo || 'data:image/svg+xml,%3Csvg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22%3E%3Ccircle cx=%2250%22 cy=%2250%22 r=%2250%22 fill=%22%23666%22/%3E%3Cpath d=%22M30 70 Q50 50 70 70 M35 35 Q50 25 65 35 Q65 45 50 50 Q35 45 35 35%22 fill=%22%23999%22 stroke=%22none%22/%3E%3C/svg%3E' || ''}" alt="Vehicle" style="width: 100%; height: 100%; object-fit: cover;">
                            </div>
                        </div>
                        <div style="flex: 1;">
                            <div style="font-weight: bold; font-size: 16px; margin-bottom: 4px;">${displayName}</div>
                            <div style="font-size: 12px; color: rgba(255,255,255,0.6); margin-bottom: 8px;">
                                <div style="margin-bottom: 2px;">Plate: <strong style="color: rgba(255,255,255,0.9);">${vehicle.plate || 'N/A'}</strong></div>
                                ${colorChips}
                            </div>
                        </div>
                    </div>
                    <div style="font-size: 12px; color: rgba(255,255,255,0.6); padding-top: 8px; border-top: 1px solid rgba(255,255,255,0.1);">
                        <div>Owner: ${vehicle.ownerName || 'Unknown'}</div>
                    </div>
                </div>
            `;
        }).join('');
    }

    updatePagination() {
        const maxPage = Math.ceil(this.totalCount / this.pageSize);
        const start = (this.currentPage - 1) * this.pageSize + 1;
        const end = Math.min(this.currentPage * this.pageSize, this.totalCount);
        document.getElementById('vehiclePaginationText').textContent = `Showing ${start} to ${end} of ${this.totalCount} Vehicles`;
        document.getElementById('vehiclePrevBtn').disabled = this.currentPage <= 1;
        document.getElementById('vehicleNextBtn').disabled = this.currentPage >= maxPage;
    }
}

// ============================================================================
// WARRANT SEARCH PAGE
// ============================================================================
class WarrantSearchPage extends BasePage {
    constructor() {
        super('warrant', 'Warrant');
        this.currentPage = 1;
        this.pageSize = 18;
        this.searchQuery = '';
        this.warrants = [];
        this.totalCount = 0;
        this.searchTimeout = null;
    }

    mount(root) {
        super.mount(root);
        root.innerHTML = `
            <div class="search-page-container">
                <div class="search-page-header">
                    <div class="search-page-title-group">
                        <h2>Warrant</h2>
                        <div class="search-page-subtitle">Wanted Individuals</div>
                    </div>
                    <button class="page-action-btn" onclick="openNewWarrantModal()">+ New Warrant</button>
                </div>
                <div class="search-page-controls">
                    <input type="text" id="warrantSearchInput" class="search-page-input" placeholder="Search suspects by name, warrant ID, or charges..." />
                </div>
                <div id="warrantGrid" class="results-grid"></div>
                <div class="pagination-footer">
                    <span id="warrantPaginationText">Showing 1 to 0 of 0 Warrants</span>
                    <div class="pagination-buttons">
                        <button id="warrantPrevBtn" class="pagination-btn">Previous</button>
                        <button id="warrantNextBtn" class="pagination-btn">Next</button>
                    </div>
                </div>
            </div>
        `;
        this.attachListeners();
        this.loadWarrants();
    }

    attachListeners() {
        const input = document.getElementById('warrantSearchInput');
        if (input) {
            input.addEventListener('input', (e) => {
                this.searchQuery = e.target.value;
                clearTimeout(this.searchTimeout);
                this.searchTimeout = setTimeout(() => {
                    this.currentPage = 1;
                    this.loadWarrants();
                }, 300);
            });
        }
        document.getElementById('warrantPrevBtn')?.addEventListener('click', () => {
            if (this.currentPage > 1) {
                this.currentPage--;
                this.loadWarrants();
            }
        });
        document.getElementById('warrantNextBtn')?.addEventListener('click', () => {
            const maxPage = Math.ceil(this.totalCount / this.pageSize);
            if (this.currentPage < maxPage) {
                this.currentPage++;
                this.loadWarrants();
            }
        });
    }

    loadWarrants() {
        sendCallback('searchWarrants', {
            query: this.searchQuery,
            page: this.currentPage,
            pageSize: this.pageSize
        });
    }

    onMessage(data) {
        if (data.action === 'setWarrants') {
            this.warrants = data.warrants || [];
            this.totalCount = data.totalCount || 0;
            this.renderWarrants();
            this.updatePagination();
        } else if (data.action === 'selectWarrant' && data.warrant) {
            // When a warrant is clicked from dashboard, open its details
            openWarrantDetails(
                data.warrant.id,
                data.warrant.issuedBy || 'Unknown',
                data.warrant.createdAt || '',
                data.warrant.narrative || '',
                JSON.stringify(data.warrant.charges || []),
                data.warrant.status || 'unknown',
                data.warrant.suspectName || 'Unknown',
                data.warrant.title || '',
                JSON.stringify(data.warrant.officers || []),
                JSON.stringify(data.warrant.witnesses || [])
            );
        }
    }

    renderWarrants() {
        const grid = document.getElementById('warrantGrid');
        if (!grid) return;

        if (this.warrants.length === 0) {
            grid.innerHTML = '<div class="empty-message" style="grid-column: 1/-1;">No warrants found</div>';
            return;
        }

        grid.innerHTML = this.warrants.map(warrant => {
            const statusBadge = warrant.status === 'active' ? '<span class="warrant-status active">Active</span>' : 
                               warrant.status === 'expired' ? '<span class="warrant-status expired">Expired</span>' : 
                               '<span class="warrant-status cleared">Cleared</span>';
            const chargesArr = (warrant.charges || []).map(formatLabel);
            const chargesDisplay = chargesArr.slice(0, 2).map(c => `<span class="charge-chip">${c}</span>`).join('');
            const chargesMore = chargesArr.length > 2 ? `<span class="charge-chip">+${chargesArr.length - 2}</span>` : '';
            const chargesPayload = encodeURIComponent(JSON.stringify(chargesArr));
            const officersPayload = encodeURIComponent(JSON.stringify(warrant.officers || []));
            const witnessesPayload = encodeURIComponent(JSON.stringify(warrant.witnesses || []));
            const cleanNarrative = warrant.narrative || '';
            const narrativePayload = encodeURIComponent(cleanNarrative);
            const title = warrant.title || '';
            const titlePayload = encodeURIComponent(title);
            const issuedByPayload = encodeURIComponent(warrant.issuedBy || 'Unknown');
            const issuedAtPayload = encodeURIComponent(warrant.issuedAt || '');
            const suspectPayload = encodeURIComponent(warrant.suspectName || 'Unknown');
            const statusPayload = encodeURIComponent(warrant.status || '');
            const formattedIssuedDate = warrant.issuedAt ? formatDateTime(warrant.issuedAt) : 'Unknown';

            return `
                <div class="warrant-card">
                    <div class="warrant-header">
                        <span class="warrant-id">${warrant.warrantId}</span>
                        ${statusBadge}
                    </div>
                    <div class="warrant-suspect">${warrant.suspectName}</div>
                    <div class="warrant-meta">
                        <div>Issued: ${formattedIssuedDate}</div>
                        <div>By: ${warrant.issuedBy || 'Unknown'}</div>
                    </div>
                    <div class="warrant-charges">
                        ${chargesDisplay}${chargesMore}
                    </div>
                    <div style="margin-top:10px;">
                        <button class="btn" onclick="openWarrantDetails('${warrant.warrantId}', '${warrant.issuedBy || 'Unknown'}', '${warrant.issuedAt || ''}', decodeURIComponent('${narrativePayload}'), decodeURIComponent('${chargesPayload}'), decodeURIComponent('${statusPayload}'), decodeURIComponent('${suspectPayload}'), decodeURIComponent('${titlePayload}'), decodeURIComponent('${officersPayload}'), decodeURIComponent('${witnessesPayload}')); return false;">Details</button>
                    </div>
                </div>
            `;
        }).join('');
    }

    updatePagination() {
        const maxPage = Math.ceil(this.totalCount / this.pageSize);
        const start = (this.currentPage - 1) * this.pageSize + 1;
        const end = Math.min(this.currentPage * this.pageSize, this.totalCount);
        document.getElementById('warrantPaginationText').textContent = `Showing ${start} to ${end} of ${this.totalCount} Warrants`;
        document.getElementById('warrantPrevBtn').disabled = this.currentPage <= 1;
        document.getElementById('warrantNextBtn').disabled = this.currentPage >= maxPage;
    }
}

// ============================================================================
// INCIDENTS PAGE
// ============================================================================
class IncidentsPage extends BasePage {
    constructor() {
        super('incidents', 'Incidents');
        this.incidents = [];
        this.currentPage = 1;
        this.pageSize = 18;
        this.searchQuery = '';
        this.statusFilter = '';
        this.totalCount = 0;
        // Store reference globally for modal access
        window._incidentsPageInstance = this;
    }

    mount(root) {
        super.mount(root);
        root.innerHTML = `
            <div class="search-page-container">
                <div class="search-page-header">
                    <div class="search-page-title-group">
                        <h2>Incidents</h2>
                    </div>
                    <button class="page-action-btn" onclick="openNewIncidentModal()">+ New Incident</button>
                </div>
                <div class="search-page-controls" style="display:flex; gap:8px;">
                    <input type="text" id="incidentSearchInput" class="search-page-input" placeholder="Search incidents by title, ID, or location..." />
                    <select id="incidentStatusFilter" style="padding: 8px; border-radius: 6px; border: 1px solid rgba(59,130,246,0.3); background: rgba(59,130,246,0.1); color: #fff; max-width: 180px;">
                        <option value="">All Statuses</option>
                        <option value="active">Active</option>
                        <option value="closed">Closed</option>
                    </select>
                </div>
                <div id="incidentGrid" class="results-grid"></div>
                <div class="pagination-footer">
                    <span id="incidentPaginationText">Showing 1 to 0 of 0 Incidents</span>
                    <div class="pagination-buttons">
                        <button id="incidentPrevBtn" class="pagination-btn">Previous</button>
                        <button id="incidentNextBtn" class="pagination-btn">Next</button>
                    </div>
                </div>
            </div>
        `;
        const input = document.getElementById('incidentSearchInput');
        if (input) {
            input.addEventListener('input', (e) => {
                this.searchQuery = e.target.value;
                clearTimeout(this._deb);
                this._deb = setTimeout(() => { this.currentPage = 1; this.loadIncidents(); }, 300);
            });
        }
        const statusSel = document.getElementById('incidentStatusFilter');
        if (statusSel) {
            statusSel.addEventListener('change', (e) => {
                this.statusFilter = e.target.value || '';
                this.currentPage = 1;
                this.loadIncidents();
            });
        }
        // Pagination controls
        document.getElementById('incidentPrevBtn')?.addEventListener('click', () => {
            if (this.currentPage > 1) {
                this.currentPage--;
                this.loadIncidents();
            }
        });
        document.getElementById('incidentNextBtn')?.addEventListener('click', () => {
            const maxPage = Math.ceil(this.totalCount / this.pageSize);
            if (this.currentPage < maxPage) {
                this.currentPage++;
                this.loadIncidents();
            }
        });
        this.loadIncidents();
        
        // Event delegation for incident grid clicks
        const grid = document.getElementById('incidentGrid');
        if (grid) {
            grid.addEventListener('click', (e) => {
                const btn = e.target.closest('.incident-details-btn');
                if (btn) {
                    e.preventDefault();
                    e.stopPropagation();
                    const card = btn.closest('.incident-card');
                    const incidentId = card?.getAttribute('data-incident-id');
                    if (incidentId) {
                        console.log('[Incidents] Opening incident:', incidentId);
                        window.openIncidentDetailsModal(incidentId);
                    }
                }
            });
        }
        
        // Auto-refresh while on Incidents page
        this._autoTimer = setInterval(() => { this.loadIncidents(); }, 5000);
    }

    unmount() {
        try { if (this._autoTimer) clearInterval(this._autoTimer); } catch (_) {}
        super.unmount();
    }

    loadIncidents() {
        sendCallback('searchIncidents', { query: this.searchQuery, status: this.statusFilter, page: this.currentPage, pageSize: this.pageSize });
    }

    onMessage(data) {
        if (data.action === 'setIncidents') {
            this.incidents = data.incidents || [];
            this.totalCount = data.totalCount || this.incidents.length || 0;
            this.renderIncidents();
            this.updatePagination();
        }
    }

    renderIncidents() {
        const grid = document.getElementById('incidentGrid');
        if (!grid) return;
        
        grid.innerHTML = this.incidents.map(incident => {
            const citizens = (Array.isArray(incident.involvedCitizens) ? incident.involvedCitizens : []).map(formatLabel);
            return `
            <div class="incident-card" data-incident-id="${incident.id}">
                <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 8px;">
                    <div style="flex: 1;">
                        <div class="incident-id">INC-${String(incident.id).padStart(5, '0')}</div>
                        <div class="incident-title">${incident.title}</div>
                    </div>
                    <div class="incident-status status-${incident.status || 'active'}">${String(incident.status || 'active').toUpperCase()}</div>
                </div>
                <div class="incident-divider"></div>
                <div class="incident-meta">
                    <div><span class="meta-label">📅</span> ${formatDateTime(incident.dateTime || incident.createdAt) || 'Unknown'}</div>
                    <div><span class="meta-label">📍</span> ${incident.location || 'Unknown'}</div>
                    <div><span class="meta-label">👮</span> ${incident.reportingOfficer || 'Unassigned'}</div>
                    ${(citizens.length) ? `<div><span class="meta-label">👤</span> ${citizens.slice(0, 2).join(', ')}${citizens.length > 2 ? ' +' + (citizens.length - 2) : ''}</div>` : ''}
                </div>
                <button class="incident-details-btn">VIEW DETAILS</button>
            </div>
        `}).join('') || '<div class="empty-message" style="grid-column: 1/-1;">No incidents</div>';
    }

    updatePagination() {
        const maxPage = Math.ceil(this.totalCount / this.pageSize) || 1;
        const start = (this.currentPage - 1) * this.pageSize + 1;
        const end = Math.min(this.currentPage * this.pageSize, this.totalCount);
        const textEl = document.getElementById('incidentPaginationText');
        if (textEl) textEl.textContent = `Showing ${this.totalCount ? start : 0} to ${this.totalCount ? end : 0} of ${this.totalCount} Incidents`;
        const prevBtn = document.getElementById('incidentPrevBtn');
        const nextBtn = document.getElementById('incidentNextBtn');
        if (prevBtn) prevBtn.disabled = this.currentPage <= 1;
        if (nextBtn) nextBtn.disabled = this.currentPage >= maxPage;
    }
}

// Global incident details modal - Professional, structured layout
window.openIncidentDetailsModal = function(incidentId) {
    console.log('[Incident Modal] Opening incident:', incidentId);
    
    // Try to get the incidents page instance from global reference first
    let page = window._incidentsPageInstance;
    
    // Fallback: try to get from router
    if (!page) {
        page = window.router?.pages?.get('incidents');
    }
    
    if (!page) {
        console.error('[Incident Modal] Could not find incidents page');
        return;
    }
    
    let inc = (page && page.incidents || []).find(i => String(i.id) === String(incidentId));
    
    if (!inc) {
        console.error('[Incident Modal] Incident not found:', incidentId, 'Available IDs:', (page.incidents || []).map(i => i.id));
        return;
    }

    const renderIncidentDetails = (inc) => {
        console.log('[Incident Modal] Rendering incident data:', inc);

        const ensureArray = (val) => {
            if (!val) return [];
            if (Array.isArray(val)) return val;
            if (typeof val === 'string') {
                try {
                    const parsed = JSON.parse(val);
                    return Array.isArray(parsed) ? parsed : [parsed];
                } catch (_) {
                    return [];
                }
            }
            return [];
        };

        const mapReadable = (arr) => (ensureArray(arr)).map(formatLabel);

        const _formatIncidentVehicle = (entry) => {
            if (entry == null) return '';

            if (typeof entry === 'object') {
                const plate = String(entry.plate ?? entry.vehiclePlate ?? entry.plateText ?? entry.plate_number ?? '').trim();
                const name = String(entry.name ?? entry.modelLabel ?? entry.vehicleName ?? entry.label ?? '').trim();
                if (plate && name) return `${plate} - ${name}`;
                if (plate) return plate;
                if (name) return name;
                return '';
            }

            let s = String(entry).trim();
            if (!s) return '';
            if (/^unknown$/i.test(s)) return '';

            // Remove obvious multi-line / concatenated payloads early.
            if (s.includes('\n')) s = s.split('\n')[0].trim();
            if (s.includes('|')) s = s.split('|')[0].trim();

            // If this is raw JSON, try to parse it (some legacy rows stored full props).
            if (s.startsWith('{') || s.startsWith('[')) {
                try {
                    const parsed = JSON.parse(s);
                    if (Array.isArray(parsed)) {
                        return parsed.map(_formatIncidentVehicle).filter(Boolean).join(', ');
                    }
                    return _formatIncidentVehicle(parsed);
                } catch (_) {
                    // fallthrough
                }
            }

            // Legacy format: "PLATE - { ...vehicle props... }" or similar.
            const braceIdx = s.indexOf('{');
            const bracketIdx = s.indexOf('[');
            const cutJsonIdx = (braceIdx >= 0 && bracketIdx >= 0) ? Math.min(braceIdx, bracketIdx) : Math.max(braceIdx, bracketIdx);
            if (cutJsonIdx > 0) {
                const left = s.slice(0, cutJsonIdx).trim();
                if (left) s = left;
            }

            // If it looks like "PLATE - ..." but the right side is clearly props/dump, keep just plate.
            const dashParts = s.split(' - ');
            if (dashParts.length >= 2) {
                const left = dashParts[0].trim();
                const right = dashParts.slice(1).join(' - ').trim();
                if (left && /^unknown$/i.test(right)) return left;
                const rightLooksLikeDump = right.length > 40 && (/[\{\}\[\]]/.test(right) || /[:,]/.test(right) || /\b(mods?|modifications|color\d?|pearlescent|wheel|engine|turbo)\b/i.test(right));
                if (left && rightLooksLikeDump) return left;
            }

            // If the string contains obvious JSON-ish noise, try to extract plate.
            if (/[\{\}\[\]"]/.test(s) || s.length > 60) {
                const m = s.match(/\"plate\"\s*:\s*\"([^\"]+)\"/i);
                if (m && m[1]) return String(m[1]).trim();
            }

            // If it's a long key/value dump without braces, attempt to capture a leading plate-like token.
            if (s.length > 60 && /[:,]/.test(s)) {
                const m1 = s.match(/^\s*([A-Za-z0-9 ]{2,12})\s*[-,:]/);
                if (m1 && m1[1]) return String(m1[1]).trim();
                const m2 = s.match(/^\s*([A-Za-z0-9 ]{2,12})\s+/);
                if (m2 && m2[1]) return String(m2[1]).trim();
            }

            // Strip any trailing "mods" / "modifications" dumps.
            const lower = s.toLowerCase();
            const modsPos = lower.indexOf('mods');
            const modifPos = lower.indexOf('modifications');
            const cutPos = (modsPos >= 0 && modifPos >= 0) ? Math.min(modsPos, modifPos) : Math.max(modsPos, modifPos);
            if (cutPos > 0) s = s.slice(0, cutPos).trim();

            return s;
        };

        inc.involvedCitizens = mapReadable(inc.involvedCitizens);
        inc.involvedVictims = mapReadable(inc.involvedVictims);
        inc.involvedOfficers = mapReadable(inc.involvedOfficers);
        inc.involvedVehicles = ensureArray(inc.involvedVehicles).map(_formatIncidentVehicle).filter(Boolean);
        inc.charges = mapReadable(inc.charges);
        inc.evidence_ids = mapReadable(inc.evidence_ids);

        const modalHTML = `
        <div class="modal-backdrop" id="incidentBackdrop">
            <div class="incident-details-modal">
                <div class="incident-modal-header">
                    <div class="incident-modal-title">
                        <div class="incident-modal-icon">🛡️</div>
                        <div>
                            <h2>Incident #${String(inc.id).padStart(5, '0')}</h2>
                            <p class="incident-modal-subtitle">View all information about this incident</p>
                        </div>
                    </div>
                    <button class="incident-modal-close" id="incidentModalClose">
                        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <line x1="18" y1="6" x2="6" y2="18"></line>
                            <line x1="6" y1="6" x2="18" y2="18"></line>
                        </svg>
                    </button>
                </div>

                <div class="incident-modal-body">
                    <!-- Information Section -->
                    <div class="incident-section">
                        <h3 class="incident-section-title">Information</h3>
                        <p class="incident-section-desc">${String(inc.status || 'active').toLowerCase() === 'closed' ? 'This incident is closed and read-only' : 'You can view and edit the information of this incident'}</p>
                        
                        <div class="incident-info-grid">
                            <div class="incident-info-item">
                                <span class="incident-info-label">Name</span>
                                <input type="text" id="incidentEditTitle" class="incident-info-value incident-editable" value="${escapeHtml(inc.title || '')}" ${String(inc.status || 'active').toLowerCase() === 'closed' ? 'disabled' : ''} />
                            </div>
                            <div class="incident-info-item">
                                <span class="incident-info-label">Created at</span>
                                <span class="incident-info-value">${formatDateTime(inc.dateTime || inc.createdAt)} (${getTimeAgo(inc.dateTime || inc.createdAt)})</span>
                            </div>
                        </div>

                        <div class="incident-info-item" style="grid-column: 1 / -1;">
                            <span class="incident-info-label">Description</span>
                            <div id="incidentEditDesc" class="incident-editable" style="margin-top: 6px;"></div>
                        </div>

                        <div class="incident-info-grid">
                            <div class="incident-info-item">
                                <span class="incident-info-label">Status</span>
                                <select id="incidentEditStatus" class="incident-editable" style="width: 100%; padding: 6px; border-radius: 6px; border: 1px solid rgba(255,255,255,0.1); background: rgba(0,0,0,0.2); color: #fff;" ${String(inc.status || 'active').toLowerCase() === 'closed' ? 'disabled' : ''}>
                                    <option value="active" ${String(inc.status||'').toLowerCase()==='active'?'selected':''}>Active</option>
                                    <option value="closed" ${String(inc.status||'').toLowerCase()==='closed'?'selected':''}>Closed</option>
                                </select>
                            </div>
                            <div class="incident-info-item">
                                <span class="incident-info-label">Location</span>
                                <input type="text" id="incidentEditLocation" class="incident-editable" value="${escapeHtml(inc.location || '')}" style="width: 100%; padding: 6px; border-radius: 6px; border: 1px solid rgba(255,255,255,0.1); background: rgba(0,0,0,0.2); color: #fff;" ${String(inc.status || 'active').toLowerCase() === 'closed' ? 'disabled' : ''} />
                            </div>
                        </div>
                    </div>

                    <div class="incident-divider-section"></div>

                    <!-- Evidence Photos -->
                    <div class="incident-section">
                        <h3 class="incident-section-title">📸 Evidence Photos</h3>
                        <p class="incident-section-desc">Capture and view evidence photos for this incident</p>
                        ${String(inc.status || 'active').toLowerCase() === 'closed' ? '' : `<button class="incident-btn incident-btn-primary" id="evidenceTakePhotoBtn" style="margin-bottom: 12px;">📷 Take Evidence Photo</button>`}
                        <div id="evidencePhotosList" class="evidence-photos-grid" style="display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 12px; margin-top: 12px;">
                            <div style="grid-column: 1/-1; color: rgba(255,255,255,0.5); font-size: 12px; text-align: center; padding: 20px;">Loading evidence...</div>
                        </div>
                    </div>

                    <div class="incident-divider-section"></div>

                    <!-- Suspects Involved -->
                    <div class="incident-section">
                        <h3 class="incident-section-title">⚠️ Suspects Involved</h3>
                        <p class="incident-section-desc">View and edit suspects attached to the record</p>
                        <div class="incident-involved-list">
                            ${(Array.isArray(inc.involvedCitizens) && inc.involvedCitizens.length) ? 
                                inc.involvedCitizens.map(name => `<div class="incident-involved-chip">👤 ${escapeHtml(name)}</div>`).join('') 
                                : '<div class="empty-list-item">No suspects added</div>'}
                        </div>
                    </div>

                    <!-- Victims Involved -->
                    <div class="incident-section">
                        <h3 class="incident-section-title">🚨 Victims Involved</h3>
                        <p class="incident-section-desc">View and edit victims attached to the record</p>
                        <div class="incident-involved-list">
                            ${(Array.isArray(inc.involvedVictims) && inc.involvedVictims.length) ? 
                                inc.involvedVictims.map(name => `<div class="incident-involved-chip">🚨 ${escapeHtml(name)}</div>`).join('') 
                                : '<div class="empty-list-item">No victims added</div>'}
                        </div>
                    </div>

                    <!-- Officers Involved -->
                    <div class="incident-section">
                        <h3 class="incident-section-title">👮 Officers Involved</h3>
                        <p class="incident-section-desc">View and edit officers attached to the record</p>
                        <div class="incident-involved-list">
                            ${(Array.isArray(inc.involvedOfficers) && inc.involvedOfficers.length) ? 
                                inc.involvedOfficers.map(name => `<div class="incident-involved-chip">👮 ${escapeHtml(name)}</div>`).join('') 
                                : '<div class="empty-list-item">No officers added</div>'}
                        </div>
                    </div>

                    <!-- Vehicles Involved -->
                    <div class="incident-section">
                        <h3 class="incident-section-title">🚔 Vehicles Involved</h3>
                        <p class="incident-section-desc">View and edit vehicles attached to the record</p>
                        <div id="incidentVehiclesDisplay" class="incident-involved-list">
                            ${(Array.isArray(inc.involvedVehicles) && inc.involvedVehicles.length) ? 
                                inc.involvedVehicles.map(plate => `<div class="incident-involved-chip">🚔 ${escapeHtml(plate)}</div>`).join('') 
                                : '<div class="empty-list-item">No vehicles added</div>'}
                        </div>
                    </div>

                    <!-- Charges Applied -->
                    <div class="incident-section">
                        <h3 class="incident-section-title">⚖️ Charges Applied</h3>
                        <p class="incident-section-desc">View and edit charges attached to the record</p>
                        <div id="incidentChargesDisplay" class="incident-involved-list">
                            ${(Array.isArray(inc.charges) && inc.charges.length) ? 
                                inc.charges.map(charge => `<div class="incident-involved-chip">⚖️ ${escapeHtml(charge)}</div>`).join('') 
                                : '<div class="empty-list-item">No charges added</div>'}
                        </div>
                    </div>

                    <!-- Evidence -->
                    <div class="incident-section">
                        <h3 class="incident-section-title">📦 Evidences</h3>
                        <p class="incident-section-desc">View and edit evidences attached to the record</p>
                        <div id="incidentEvidenceDisplay" class="incident-involved-list">
                            <div class="empty-list-item">Loading evidence...</div>
                        </div>
                    </div>
                </div>

                <div class="incident-modal-footer">
                    ${String(inc.status || 'active').toLowerCase() === 'closed' ? 
                        '<div style="padding: 8px; color: rgba(255,255,255,0.6); font-size: 12px;">This incident is closed</div>' :
                        '<button class="incident-btn incident-btn-primary" id="incidentSaveBtn">💾 Save Changes</button><button class="incident-btn incident-btn-danger" id="incidentCloseBtn">🔒 Close Incident</button>' + ((typeof window.playerGrade !== 'undefined' && window.playerGrade >= 4) ? '<button class="incident-btn" id="incidentDeleteBtn" style="background: linear-gradient(135deg, rgba(244,67,54,0.4), rgba(211,47,47,0.4)); border-color: rgba(244,67,54,0.6); color: rgba(255,107,107,1);">🗑️ Delete</button>' : '')
                    }
                </div>
            </div>
        </div>
    `;

        document.getElementById('incidentDetailsModal')?.remove();
        document.body.insertAdjacentHTML('beforeend', modalHTML);
        
        const backdrop = document.getElementById('incidentBackdrop');
        const modal = backdrop.querySelector('.incident-details-modal');
        const closeBtn = document.getElementById('incidentModalClose');

        const isClosed = String(inc.status || 'active').toLowerCase() === 'closed';
        const descContent = String(inc.narrative || inc.description || '');
        if (typeof createRTE === 'function') {
            window.__rteIncidentEditDesc = createRTE('incidentEditDesc', {
                placeholder: 'Detailed description of the incident...',
                initialContent: renderRteContent(descContent),
                minHeight: '120px',
                maxHeight: '40vh',
                readonly: isClosed,
                showToolbar: !isClosed
            });
        }
    
        // Load linked evidence
        let evidenceIds = inc.evidence_ids || inc.evidenceIds || [];
        evidenceIds = ensureArray(evidenceIds);

        const evidenceDisplay = document.getElementById('incidentEvidenceDisplay');
        const renderLinkedEvidence = (allEvidence) => {
            if (!evidenceDisplay) return;
            const list = Array.isArray(allEvidence) ? allEvidence : [];
            const linkedEvidence = evidenceIds
                .map(id => list.find(e =>
                    String(e.evidence_number) === String(id) ||
                    String(e.id) === String(id) ||
                    String(e.evidence_id) === String(id)
                ))
                .filter(Boolean);

            if (linkedEvidence.length > 0) {
                evidenceDisplay.innerHTML = linkedEvidence.map(ev => `
                    <div class="incident-involved-chip" style="cursor: pointer;" onclick="openEvidenceDetails('${ev.evidence_number}'); return false;">
                        📦 Evidence #${ev.evidence_number} - ${escapeHtml(ev.title)}
                    </div>
                `).join('');
            } else {
                evidenceDisplay.innerHTML = '<div class="empty-list-item">No evidence added</div>';
            }
        };

        if (evidenceDisplay) evidenceDisplay.innerHTML = '<div class="empty-list-item">No evidence added</div>';

        if (evidenceIds.length > 0 && evidenceDisplay) {
            evidenceDisplay.innerHTML = '<div class="empty-list-item">Loading evidence...</div>';
            const evidencePage = window._evidencePageInstance || window.router?.pages?.get('evidence');
            const cachedEvidence = (evidencePage && Array.isArray(evidencePage.evidence) && evidencePage.evidence.length) ? evidencePage.evidence : null;

            if (cachedEvidence) {
                renderLinkedEvidence(cachedEvidence);
            } else {
                // Fetch evidence list so incidents can resolve linked evidence even if the Evidence page wasn't opened.
                try {
                    sendCallback('pf_mdt:searchEvidence', { query: '', page: 1, pageSize: 500, limit: 500 }, (res) => {
                        renderLinkedEvidence(res?.evidence || []);
                    });
                } catch (e) {
                    console.warn('[Incident Modal] Failed to fetch evidence list:', e);
                    if (evidenceDisplay) evidenceDisplay.innerHTML = '<div class="empty-list-item">No evidence added</div>';
                }
            }
        }
    
        // Close on X button
        if (closeBtn) closeBtn.onclick = () => backdrop.remove();
    
        // Close on backdrop click
        backdrop.addEventListener('click', (e) => {
            if (e.target === backdrop) backdrop.remove();
        });
    
        // Prevent modal click from closing
        modal.addEventListener('click', (e) => e.stopPropagation());
    
        // Close on ESC
        const handleEsc = (e) => {
            if (e.key === 'Escape') backdrop.remove();
        };
        document.addEventListener('keydown', handleEsc);
    
        // Only attach save/close handlers if incident is NOT closed
        if (!isClosed) {
        // Save handler
        const saveBtnEl = document.getElementById('incidentSaveBtn');
        if (saveBtnEl) {
            saveBtnEl.onclick = () => {
                const payload = {
                    id: inc.id,
                    title: document.getElementById('incidentEditTitle').value.trim(),
                    narrative: (window.__rteIncidentEditDesc ? window.__rteIncidentEditDesc.getValue() : document.getElementById('incidentEditDesc')?.textContent || '').trim(),
                    status: document.getElementById('incidentEditStatus').value,
                    location: document.getElementById('incidentEditLocation').value.trim()
                };
                sendCallback('updateIncident', payload, (res) => {
                    if (res && res.success) {
                        backdrop.remove();
                        setTimeout(() => {
                            const page = window._incidentsPageInstance || window.router?.pages?.get('incidents');
                            page?.loadIncidents?.();
                        }, 300);
                    } else {
                        if (typeof mdtToast === 'function') mdtToast('Failed to save incident', 'error');
                    }
                });
            };
        }
        
        // Close incident handler
        const closeIncidentBtn = document.getElementById('incidentCloseBtn');
        if (closeIncidentBtn) {
            closeIncidentBtn.onclick = async () => {
                if (!await window.mdtConfirm('Are you sure you want to close this incident?')) return;
                sendCallback('closeIncident', { id: inc.id }, (res) => {
                    if (res && res.success) {
                        backdrop.remove();
                        setTimeout(() => {
                            const page = window._incidentsPageInstance || window.router?.pages?.get('incidents');
                            page?.loadIncidents?.();
                        }, 300);
                    } else {
                        if (typeof mdtToast === 'function') mdtToast('Failed to close incident', 'error');
                    }
                });
            };
        }

        // Delete incident handler
        const deleteIncidentBtn = document.getElementById('incidentDeleteBtn');
        if (deleteIncidentBtn) {
            deleteIncidentBtn.onclick = async () => {
                if (!await window.mdtConfirm('Are you sure you want to DELETE this incident? This cannot be undone.')) return;
                fetch('https://' + window.resName + '/pf_mdt:deleteIncident', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                    body: JSON.stringify({ incidentId: inc.incidentId })
                }).then(res => res.json()).then(data => {
                    backdrop.remove();
                    setTimeout(() => {
                        const page = window._incidentsPageInstance || window.router?.pages?.get('incidents');
                        page?.loadIncidents?.();
                    }, 300);
                    if (typeof mdtToast === 'function') mdtToast('Incident deleted', 'success');
                }).catch(err => {
                    if (typeof mdtToast === 'function') mdtToast('Failed to delete incident', 'error');
                });
            };
        }
        }
    
        // Load evidence photos
        loadIncidentEvidence(inc.id);
    
        // Evidence photo button handler
        const photoBtn = document.getElementById('evidenceTakePhotoBtn');
        if (photoBtn) {
            photoBtn.onclick = () => {
                sendCallback('mdt:evidenceTakePhoto', { incidentId: inc.id }, (res) => {
                    if (res && res.success) {
                        // Reload evidence after capture
                        loadIncidentEvidence(inc.id);
                    }
                });
            };
        }
    };

    // Fetch full incident record, then render
    sendCallback('getIncident', { incidentId }, (result) => {
        if (result && result.success && result.incident) {
            renderIncidentDetails(result.incident);
        } else {
            console.warn('[Incident Modal] getIncident failed; falling back to list data', result);
            renderIncidentDetails(inc);
        }
    });
};

// Load and display evidence for an incident
function loadIncidentEvidence(incidentId) {
    sendCallback('mdt:getIncidentEvidence', { incidentId }, (result) => {
        const list = document.getElementById('evidencePhotosList');
        if (!list) return;
        
        if (!result || !result.success || !result.evidence || result.evidence.length === 0) {
            list.innerHTML = '<div style="grid-column: 1/-1; color: rgba(255,255,255,0.5); font-size: 12px; text-align: center; padding: 20px;">No evidence photos</div>';
            return;
        }
        
        list.innerHTML = result.evidence.map(e => `
            <div class="evidence-photo-card" style="position: relative; border-radius: 8px; overflow: hidden; background: rgba(0,0,0,0.3); border: 1px solid rgba(255,255,255,0.1);">
                <div style="aspect-ratio: 1; background-image: url('${escapeHtml(e.image_url)}'); background-size: cover; background-position: center; cursor: pointer;" onclick="if (window.showImageLightbox) { window.showImageLightbox('${String(e.image_url).replace(/'/g, "\\'")}'); }"></div>
                <div style="padding: 8px; font-size: 11px;">
                    <div style="font-weight: 600; margin-bottom: 4px;">Evidence #${e.evidence_number}</div>
                    <div style="color: rgba(255,255,255,0.6);">By: ${escapeHtml(e.created_by_name)}</div>
                    <div style="color: rgba(255,255,255,0.5); font-size: 10px; margin-top: 4px;">${formatDateTime(e.created_at)}</div>
                </div>
            </div>
        `).join('');
    });
}

// NUI Message Handler for hideUIForScreenshot
window.addEventListener('message', (event) => {
    const data = event.data;
    if (data.action === 'hideUIForScreenshot') {
        const mdtApp = document.getElementById('mdt-app');
        if (mdtApp) {
            if (data.hidden) {
                mdtApp.classList.add('ui-hidden');
            } else {
                mdtApp.classList.remove('ui-hidden');
            }
        }
    }
    
    // Refresh evidence after photo added
    if (data.action === 'refreshIncidentEvidence' && data.incidentId) {
        loadIncidentEvidence(data.incidentId);
    }
});

// Helper function to calculate time ago
function getTimeAgo(date) {
    if (!date) return '';
    const d = new Date(typeof date === 'string' ? date.replace(' ', 'T') : date);
    if (isNaN(d.getTime())) return '';
    const now = new Date();
    const seconds = Math.floor((now - d) / 1000);
    if (seconds < 60) return 'less than a minute ago';
    const minutes = Math.floor(seconds / 60);
    if (minutes < 60) return minutes === 1 ? '1 minute ago' : minutes + ' minutes ago';
    const hours = Math.floor(minutes / 60);
    if (hours < 24) return hours === 1 ? '1 hour ago' : hours + ' hours ago';
    const days = Math.floor(hours / 24);
    return days === 1 ? '1 day ago' : days + ' days ago';
}

// OLD function name for backwards compatibility (will be removed)
function openIncidentDetails(incidentId) {
    window.openIncidentDetailsModal(incidentId);
}

// ============================================================================
// REPORTS PAGE
// ============================================================================
class ReportsPage extends BasePage {
    constructor() {
        super('reports', 'Reports');
        this.reports = [];
        this.currentPage = 1;
        this.pageSize = 18;
        this.totalCount = 0;
        this.searchQuery = '';
    }

    mount(root) {
        super.mount(root);
        root.innerHTML = `
            <div class="search-page-container">
                <div class="search-page-header">
                    <div class="search-page-title-group">
                        <h2>Reports</h2>
                    </div>
                    <button class="page-action-btn" onclick="openNewReportModal()">+ New Report</button>
                </div>
                <div class="search-page-controls">
                    <input type="text" id="reportSearchInput" class="search-page-input" placeholder="Search reports..." />
                </div>
                <div id="reportGrid" class="results-grid"></div>
                <div class="pagination-footer">
                    <span id="reportPaginationText">Showing 1 to 0 of 0 Reports</span>
                    <div class="pagination-buttons">
                        <button id="reportPrevBtn" class="pagination-btn">Previous</button>
                        <button id="reportNextBtn" class="pagination-btn">Next</button>
                    </div>
                </div>
            </div>
        `;
        const input = document.getElementById('reportSearchInput');
        if (input) {
            input.addEventListener('input', (e) => {
                clearTimeout(this._deb);
                this.searchQuery = e.target.value || '';
                this._deb = setTimeout(() => {
                    this.currentPage = 1;
                    this.loadReports();
                }, 300);
            });
        }
        // Pagination controls
        document.getElementById('reportPrevBtn')?.addEventListener('click', () => {
            if (this.currentPage > 1) {
                this.currentPage--;
                this.loadReports();
            }
        });
        document.getElementById('reportNextBtn')?.addEventListener('click', () => {
            const maxPage = Math.ceil(this.totalCount / this.pageSize);
            if (this.currentPage < maxPage) {
                this.currentPage++;
                this.loadReports();
            }
        });
        this.loadReports();
    }

    loadReports() {
        sendCallback('searchReports', { query: this.searchQuery || '', page: this.currentPage, pageSize: this.pageSize });
    }

    onMessage(data) {
        if (data.action === 'setReports') {
            this.reports = data.reports || [];
            this.totalCount = data.totalCount || this.reports.length || 0;
            this.renderReports();
            this.updatePagination();
        }
    }

    renderReports() {
        const grid = document.getElementById('reportGrid');
        if (!grid) return;
        const titleCase = (s) => String(s || 'Custom').replace(/\w\S*/g, t => t.charAt(0).toUpperCase() + t.slice(1).toLowerCase());
        grid.innerHTML = (this.reports || []).map(report => {
            const typeLabel = titleCase(report.type);
            const created = formatDateTime(report.createdAt);
            const id = report.id;
            return `
                <div class="report-card">
                    <div class="report-type-badge">${escapeHtml(typeLabel || 'Custom')}</div>
                    <div class="report-id">#${escapeHtml(id)}</div>
                    <div class="report-title">${escapeHtml(report.title || 'Report')}</div>
                    <div class="report-meta">
                        <div>Officer: ${escapeHtml(report.officer || 'Unknown')}</div>
                        <div>Created: ${escapeHtml(created)}</div>
                    </div>
                    <div class="report-actions" style="margin-top:8px;">
                        <button class="modal-btn" onclick="openReportDetails('${String(id).replace(/'/g, "\\'")}')">View</button>
                    </div>
                </div>
            `;
        }).join('') || '<div class="empty-message" style="grid-column: 1/-1;">No reports</div>';
    }

    updatePagination() {
        const maxPage = Math.ceil(this.totalCount / this.pageSize) || 1;
        const start = (this.currentPage - 1) * this.pageSize + 1;
        const end = Math.min(this.currentPage * this.pageSize, this.totalCount);
        const textEl = document.getElementById('reportPaginationText');
        if (textEl) textEl.textContent = `Showing ${this.totalCount ? start : 0} to ${this.totalCount ? end : 0} of ${this.totalCount} Reports`;
        const prevBtn = document.getElementById('reportPrevBtn');
        const nextBtn = document.getElementById('reportNextBtn');
        if (prevBtn) prevBtn.disabled = this.currentPage <= 1;
        if (nextBtn) nextBtn.disabled = this.currentPage >= maxPage;
    }
}

// ============================================================================
// FTO REPORTS PAGE
// ============================================================================
class FTOReportsPage extends BasePage {
    constructor() {
        super('fto', 'FTO Reports');
        this.reports = [];
        this.totalCount = 0;
        this.currentPage = 1;
        this.pageSize = 12;
        this.searchQuery = '';
    }

    mount(root) {
        super.mount(root);
        root.innerHTML = `
            <div class="search-page-container">
                <div class="search-page-header">
                    <div class="search-page-title-group">
                        <h2>FTO Reports</h2>
                        <div class="search-page-subtitle">Training evaluations with draft/submit/review workflow</div>
                    </div>
                    <button class="page-action-btn" onclick="openFtoReportEditor()">+ New FTO Report</button>
                </div>
                <div class="search-page-controls">
                    <input type="text" id="ftoSearchInput" class="search-page-input" placeholder="Search by trainee, author, UID, status..." />
                </div>
                <div id="ftoGrid" class="results-grid"></div>
                <div class="pagination-footer">
                    <span id="ftoPaginationText">Showing 0 to 0 of 0 Reports</span>
                    <div class="pagination-buttons">
                        <button id="ftoPrevBtn" class="pagination-btn">Previous</button>
                        <button id="ftoNextBtn" class="pagination-btn">Next</button>
                    </div>
                </div>
            </div>
        `;
        const input = document.getElementById('ftoSearchInput');
        if (input) {
            input.addEventListener('input', (e) => {
                clearTimeout(this._deb);
                this._deb = setTimeout(() => {
                    this.searchQuery = e.target.value || '';
                    this.currentPage = 1;
                    this.loadReports();
                }, 300);
            });
        }
        document.getElementById('ftoPrevBtn')?.addEventListener('click', () => {
            if (this.currentPage > 1) {
                this.currentPage--;
                this.loadReports();
            }
        });
        document.getElementById('ftoNextBtn')?.addEventListener('click', () => {
            const maxPage = Math.ceil((this.totalCount || 0) / this.pageSize) || 1;
            if (this.currentPage < maxPage) {
                this.currentPage++;
                this.loadReports();
            }
        });
        this.loadReports();
    }

    loadReports() {
        console.log('[FTO PAGE] loadReports called, page:', this.currentPage, 'search:', this.searchQuery);
        // v2 list API (server filters drafts appropriately)
        sendCallback('getFtoReportsList', {
            search: this.searchQuery || '',
            page: this.currentPage,
            limit: this.pageSize
        }, (res) => {
            console.log('[FTO PAGE] getFtoReportsList response:', res);
            if (!res || res.success === false) {
                // If the v2 endpoint isn't available yet (mixed versions / no restart), fall back.
                console.warn('[FTO PAGE] v2 failed, using fallback');
                try {
                    mdtToast('FTO list v2 failed; using fallback list', 'error');
                } catch (_) {}
                sendCallback('searchFTOReports', {
                    query: this.searchQuery || '',
                    page: this.currentPage,
                    pageSize: this.pageSize
                });
                return;
            }
            // Support either direct callback response or legacy SendNUIMessage flow
            this.reports = res.reports || [];
            this.totalCount = res.totalCount || this.reports.length || 0;
            console.log('[FTO PAGE] Set reports count:', this.reports.length, 'total:', this.totalCount);
            this.renderReports();
            this.updatePagination();
        });
    }

    onMessage(data) {
        console.log('[FTO PAGE] onMessage:', data && data.action, 'reports:', data && data.reports ? data.reports.length : 'n/a', 'total:', data && data.totalCount);
        if (data.action === 'setFTOReports') {
            this.reports = data.reports || [];
            this.totalCount = data.totalCount || this.reports.length || 0;
            console.log('[FTO PAGE] onMessage set reports count:', this.reports.length, 'total:', this.totalCount);
            this.renderReports();
            this.updatePagination();
        }
    }

    renderReports() {
        const grid = document.getElementById('ftoGrid');
        if (!grid) return;

        const normalize = (r) => {
            // Support both v2 and legacy-mapped shapes
            const uid = r.report_uid || r.reportUid || r.report_id || r.reportId || '';
            const trainee = r.trainee_name || r.traineeName || 'Unknown';
            const author = r.author_name || r.ftoName || r.authorName || 'Unknown';
            const phase = r.phase || 1;
            const shift = r.shift || 'Morning';
            const status = (r.status || 'DRAFT').toUpperCase();
            const rideDate = r.ride_date || r.date || r.rideDate;
            const rating = (r.overall_rating ?? r.rating ?? null);
            const canEdit = !!r.canEdit;
            return { uid, trainee, author, phase, shift, status, rideDate, rating, canEdit };
        };

        const rows = (this.reports || []).map(normalize);
        grid.innerHTML = rows.map(r => {
            const status = String(r.status || 'DRAFT').toUpperCase();

            const statusLabel = status === 'APPROVED'
                ? 'Approved'
                : (status === 'REJECTED' ? 'Rejected' : '');
            const statusBadge = (status === 'APPROVED' || status === 'REJECTED')
                ? `<div class="fto-status-badge fto-status-${status.toLowerCase()}">${escapeHtml(statusLabel)}</div>`
                : '';

            const ratingNum = (r.rating === null || r.rating === undefined) ? null : Number(r.rating);
            const hasRating = Number.isFinite(ratingNum);
            const safeRating = hasRating ? Math.max(0, Math.min(5, ratingNum)) : 0;
            const ratingPct = hasRating ? Math.round((safeRating / 5) * 100) : 0;
            const ratingBar = (status !== 'DRAFT' && hasRating)
                ? `
                    <div class="fto-rating-row">
                        <div class="fto-rating-bar" aria-label="Overall rating ${safeRating.toFixed(1)} out of 5">
                            <div class="fto-rating-fill" style="width:${ratingPct}%;"></div>
                        </div>
                        <div class="fto-rating-value">${escapeHtml(safeRating.toFixed(1))}</div>
                    </div>
                `
                : '';
            const uidLine = r.uid ? `<div class="muted" style="font-size: 11px; opacity: 0.75;">${escapeHtml(r.uid)}</div>` : '';
            const dateLine = r.rideDate ? `<div>📅 ${escapeHtml(formatDateTime(r.rideDate))}</div>` : '<div>📅 Unknown</div>';
            return `
                <div class="incident-card fto-card" style="position: relative;">
                    ${statusBadge}
                    ${uidLine}
                    <div class="incident-title" style="margin-top: 4px;">${escapeHtml(r.trainee)}</div>
                    <div class="incident-divider"></div>
                    <div class="incident-meta">
                        <div>👮 FTO: ${escapeHtml(r.author)}</div>
                        <div>🧩 Phase: ${escapeHtml(String(r.phase))} · ${escapeHtml(String(r.shift))}</div>
                        ${dateLine}
                    </div>
                    ${ratingBar}
                    <div style="display:flex; gap:8px; margin-top: 10px;">
                        <button class="incident-details-btn" onclick="openFtoReportDetails('${String(r.uid).replace(/'/g, "\\'")}'); return false;">VIEW DETAILS</button>
                        ${r.canEdit ? `<button class="incident-details-btn" style="background: linear-gradient(135deg, rgba(255,200,100,0.25), rgba(255,200,100,0.15)); border-color: rgba(255,200,100,0.45); color: rgba(255,214,140,1);" onclick="openFtoReportEditor('${String(r.uid).replace(/'/g, "\\'")}'); return false;">EDIT</button>` : ''}
                    </div>
                </div>
            `;
        }).join('') || '<div class="empty-message" style="grid-column: 1/-1;">No FTO reports</div>';
    }

    updatePagination() {
        const maxPage = Math.ceil((this.totalCount || 0) / this.pageSize) || 1;
        const start = (this.currentPage - 1) * this.pageSize + 1;
        const end = Math.min(this.currentPage * this.pageSize, this.totalCount || 0);
        const textEl = document.getElementById('ftoPaginationText');
        if (textEl) textEl.textContent = `Showing ${this.totalCount ? start : 0} to ${this.totalCount ? end : 0} of ${this.totalCount} Reports`;
        const prevBtn = document.getElementById('ftoPrevBtn');
        const nextBtn = document.getElementById('ftoNextBtn');
        if (prevBtn) prevBtn.disabled = this.currentPage <= 1;
        if (nextBtn) nextBtn.disabled = this.currentPage >= maxPage;
    }
}

// ============================================================================
// FTO REPORTS MODALS + HELPERS
// ============================================================================

function mdtToast(message, type) {
    const msg = String(message || '');
    if (!msg) return;
    const existing = document.getElementById('mdtToast');
    if (existing) existing.remove();
    const t = (type || 'info').toLowerCase();
    const bg = t === 'success' ? 'rgba(76,175,80,0.22)' : (t === 'error' ? 'rgba(244,67,54,0.22)' : 'rgba(33,150,243,0.22)');
    const br = t === 'success' ? 'rgba(76,175,80,0.4)' : (t === 'error' ? 'rgba(244,67,54,0.4)' : 'rgba(33,150,243,0.4)');
    const el = document.createElement('div');
    el.id = 'mdtToast';
    el.style.cssText = `position: fixed; right: 18px; bottom: 18px; z-index: 20000; padding: 10px 14px; border-radius: 10px; border: 1px solid ${br}; background: ${bg}; color: #e0e6f2; font-weight: 700; font-size: 12px; box-shadow: 0 12px 32px rgba(0,0,0,0.45); max-width: 420px;`;
    el.textContent = msg;
    document.body.appendChild(el);
    setTimeout(() => { try { el.remove(); } catch (_) {} }, 2200);
}

const FTO_EVAL_CATEGORIES = [
    'OfficerSafety',
    'RadioComms',
    'Driving',
    'SceneManagement',
    'LegalKnowledge',
    'DecisionMaking',
    'UseOfForceJudgment',
    'Professionalism',
    'ReportWriting'
];

function ensureFtoEvalShape(evaluation) {
    const obj = (evaluation && typeof evaluation === 'object') ? evaluation : {};
    const out = {};
    FTO_EVAL_CATEGORIES.forEach(k => {
        const v = obj[k] || {};
        out[k] = {
            rating: Number.isFinite(Number(v.rating)) ? Number(v.rating) : '',
            comment: String(v.comment || '')
        };
    });
    return out;
}

window.openFtoReportDetails = function(reportUid) {
    if (!reportUid) return;
    sendCallback('getFtoReport', { report_uid: reportUid }, (res) => {
        if (!res || !res.success) {
            mdtToast('Failed to load report', 'error');
            return;
        }
        const r = res.report || {};
        const perms = res.permissions || {};
        const audit = res.audit || [];
        const evalObj = ensureFtoEvalShape(r.evaluation);

        const status = String(r.status || 'DRAFT').toUpperCase();
        const isLocked = status === 'APPROVED' || status === 'REJECTED';
        const canEdit = !!perms.canEdit;
        const isCommand = !!perms.isCommand;

        const prettyEvalLabel = (k) => String(k || '').replace(/([a-z])([A-Z])/g, '$1 $2');
        const evalRatings = FTO_EVAL_CATEGORIES.map(k => {
            const v = evalObj[k] || {};
            const n = Number(v.rating);
            return Number.isFinite(n) ? n : 0;
        });
        const totalScore = evalRatings.reduce((a, b) => a + b, 0);
        const maxScore = (FTO_EVAL_CATEGORIES.length || 0) * 5;
        const overallPct = (maxScore > 0) ? Math.round((totalScore / maxScore) * 100) : 0;

        const modalHTML = `
            <div class="modal-backdrop" id="ftoDetailsBackdrop" style="z-index: 10040;">
                <div class="incident-details-modal" style="max-width: 1200px;">
                    <div class="incident-modal-header">
                        <div class="incident-modal-title">
                            <div class="incident-modal-icon">🎓</div>
                            <div>
                                <h2>${escapeHtml(String(r.trainee_name || 'Trainee'))} - Phase ${escapeHtml(String(r.phase || 1))}</h2>
                                <p class="incident-modal-subtitle">FTO: ${escapeHtml(String(r.author_name || 'Unknown'))} | Date: ${escapeHtml(formatDateTime(r.ride_date))} | Shift: ${escapeHtml(String(r.shift || 'Morning'))}</p>
                                ${status === 'REJECTED' && r.review_note ? `<p class="incident-modal-subtitle" style="color: rgba(244,67,54,0.9); font-weight: 700;">Rejection Reason: ${escapeHtml(String(r.review_note || ''))}</p>` : ''}
                            </div>
                        </div>
                        ${(status === 'APPROVED' || status === 'REJECTED') ? `<div class="fto-status-badge fto-status-${status.toLowerCase()}">${escapeHtml(status === 'APPROVED' ? 'Approved' : 'Rejected')}</div>` : ''}
                        <button class="incident-modal-close" id="ftoDetailsClose">
                            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                <line x1="18" y1="6" x2="6" y2="18"></line>
                                <line x1="6" y1="6" x2="18" y2="18"></line>
                            </svg>
                        </button>
                    </div>

                    <div class="incident-modal-body">
                        <div class="fto-details-grid">
                            <div class="fto-panel">
                                <div class="fto-panel-title">Performance Evaluation</div>
                                <div class="fto-eval-list">
                                    ${FTO_EVAL_CATEGORIES.map((k) => {
                                        const v = evalObj[k] || {};
                                        const n = Number(v.rating);
                                        const rating = Number.isFinite(n) ? n : 0;
                                        const pct = Math.round((Math.max(0, Math.min(5, rating)) / 5) * 100);
                                        return `
                                            <div class="fto-eval-item">
                                                <div class="fto-eval-label">${escapeHtml(prettyEvalLabel(k))}</div>
                                                <div class="fto-eval-bar">
                                                    <div class="fto-eval-fill" style="width:${pct}%;"></div>
                                                </div>
                                                <div class="fto-eval-value">${escapeHtml((rating ? rating.toFixed(1) : '—'))}</div>
                                            </div>
                                        `;
                                    }).join('')}
                                </div>
                            </div>

                            <div class="fto-panel">
                                <div class="fto-panel-title">Overall Assessment</div>

                                <div class="fto-overall-block">
                                    <div class="fto-overall-label">Overall Performance</div>
                                    <div class="fto-overall-bar">
                                        <div class="fto-overall-fill" style="width:${overallPct}%;"></div>
                                    </div>
                                    <div class="fto-overall-value">${escapeHtml(String(totalScore.toFixed(0)))}/${escapeHtml(String(maxScore))}</div>
                                </div>

                                <div class="fto-overall-sections">
                                    <div class="fto-overall-section">
                                        <div class="fto-overall-section-title">Strengths</div>
                                        <div class="fto-overall-section-body rte-view">${renderRteContent(String(r.strengths || 'No strengths provided'))}</div>
                                    </div>
                                    <div class="fto-overall-section">
                                        <div class="fto-overall-section-title">Areas for Improvement</div>
                                        <div class="fto-overall-section-body rte-view">${renderRteContent(String(r.improvements || 'No improvements provided'))}</div>
                                    </div>
                                    <div class="fto-overall-section">
                                        <div class="fto-overall-section-title">Additional Comments</div>
                                        <div class="fto-overall-section-body rte-view">${renderRteContent(String(r.ride_description || 'No additional comments'))}</div>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>

                    <div class="incident-modal-footer">
                        ${canEdit && !isLocked ? `<button class="incident-btn incident-btn-primary" id="ftoEditBtn">✏️ Edit</button>` : ''}
                        ${isCommand && status === 'SUBMITTED' ? `<button class="incident-btn incident-btn-primary" id="ftoApproveBtn">✅ Approve</button><button class="incident-btn incident-btn-danger" id="ftoRejectBtn">⛔ Reject</button>` : ''}
                    </div>
                </div>
            </div>
        `;

        document.getElementById('ftoDetailsBackdrop')?.remove();
        document.body.insertAdjacentHTML('beforeend', modalHTML);

        const backdrop = document.getElementById('ftoDetailsBackdrop');
        const closeBtn = document.getElementById('ftoDetailsClose');
        if (closeBtn) closeBtn.onclick = () => backdrop.remove();
        backdrop.addEventListener('click', (e) => { if (e.target === backdrop) backdrop.remove(); });

        document.getElementById('ftoEditBtn')?.addEventListener('click', () => {
            backdrop.remove();
            openFtoReportEditor(reportUid);
        });

        document.getElementById('ftoApproveBtn')?.addEventListener('click', async () => {
            const note = (typeof window.mdtPrompt === 'function')
                ? (await window.mdtPrompt('Approve note (optional):', { title: 'Approve', required: false, placeholder: 'Optional note...' }))
                : '';
            if (note === null) return;
            sendCallback('reviewFtoReport', { report_uid: reportUid, action: 'APPROVE', review_note: note }, (rr) => {
                if (rr && rr.success) {
                    mdtToast('Approved', 'success');
                    backdrop.remove();
                    const page = router?.pages?.get('fto');
                    page?.loadReports?.();
                } else {
                    mdtToast('Approve failed', 'error');
                }
            });
        });
        document.getElementById('ftoRejectBtn')?.addEventListener('click', async () => {
            const note = (typeof window.mdtPrompt === 'function')
                ? (await window.mdtPrompt('Reject reason (required):', { title: 'Reject', required: true, placeholder: 'Reason...' }))
                : null;
            if (note === null) return;
            sendCallback('reviewFtoReport', { report_uid: reportUid, action: 'REJECT', review_note: note }, (rr) => {
                if (rr && rr.success) {
                    mdtToast('Rejected', 'success');
                    backdrop.remove();
                    const page = router?.pages?.get('fto');
                    page?.loadReports?.();
                } else {
                    mdtToast('Reject failed', 'error');
                }
            });
        });
    });
};

window.openFtoReportEditor = function(reportUid) {
    const openWith = (report, perms) => {
        const r = report || {};
        const status = String(r.status || 'DRAFT').toUpperCase();
        const isLocked = status === 'APPROVED' || status === 'REJECTED';
        const canEdit = reportUid ? !!(perms && perms.canEdit) : true;
        if (reportUid && (!canEdit || isLocked)) {
            mdtToast('This report is locked/read-only', 'error');
            return;
        }

        const evalObj = ensureFtoEvalShape(r.evaluation);
        const safe = (v) => escapeHtml(String(v ?? ''));

        const maxPhase = 4;

        const modalHTML = `
            <div class="modal-backdrop" id="ftoEditBackdrop" style="z-index: 10045;">
                <div class="incident-details-modal" style="max-width: 950px;">
                    <div class="incident-modal-header">
                        <div class="incident-modal-title">
                            <div class="incident-modal-icon">📝</div>
                            <div>
                                <h2>${reportUid ? 'Edit FTO Report' : 'New FTO Report'}</h2>
                                <p class="incident-modal-subtitle">Save as Draft or Submit when complete</p>
                            </div>
                        </div>
                        <button class="incident-modal-close" id="ftoEditClose">
                            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                <line x1="18" y1="6" x2="6" y2="18"></line>
                                <line x1="6" y1="6" x2="18" y2="18"></line>
                            </svg>
                        </button>
                    </div>
                    <div class="incident-modal-body">

                        <div style="display:grid; grid-template-columns: 1fr 1fr; gap: 12px;">
                            <div>
                                <div class="muted" style="font-size: 12px; margin-bottom: 6px;">Trainee (required for draft)</div>
                                <select id="ftoTraineeSelect" style="height: 44px; padding: 10px 12px; font-size: 14px;"></select>
                                <input id="ftoTraineeCid" type="hidden" value="${safe(r.trainee_cid || '')}" />
                                <input id="ftoTraineeName" type="hidden" value="${safe(r.trainee_name || '')}" />
                                <input id="ftoTraineeCallsign" type="hidden" value="${safe(r.trainee_callsign || '')}" />
                                <div id="ftoTraineeSelected" class="muted" style="margin-top: 8px; font-size: 12px;">${r.trainee_name ? ('Selected: ' + safe(r.trainee_name) + (r.trainee_callsign ? (' (' + safe(r.trainee_callsign) + ')') : '')) : 'No trainee selected'}</div>
                            </div>
                            <div>
                                <div class="muted" style="font-size: 12px; margin-bottom: 6px;">Ride Date (required for submit)</div>
                                <input id="ftoRideDate" type="datetime-local" style="height: 44px; padding: 10px 12px; font-size: 14px;" value="${(() => {
                                    try {
                                        const raw = r.ride_date;
                                        // New report: auto-fill date
                                        if (!raw && !reportUid) {
                                            const now = new Date();
                                            const tzOffset = now.getTimezoneOffset();
                                            const localNow = new Date(now.getTime() - tzOffset * 60000);
                                            return localNow.toISOString().slice(0, 16);
                                        }
                                        if (!raw) return '';
                                        const d = new Date(String(raw).replace(' ', 'T'));
                                        if (Number.isNaN(d.getTime())) return '';
                                        const tzOffset = d.getTimezoneOffset();
                                        const local = new Date(d.getTime() - tzOffset * 60000);
                                        return local.toISOString().slice(0,16);
                                    } catch (_) { return ''; }
                                })()}" />
                            </div>
                            <div>
                                <div class="muted" style="font-size: 12px; margin-bottom: 6px;">Phase</div>
                                <select id="ftoPhase" style="height: 44px; padding: 10px 12px; font-size: 14px;">
                                    ${Array.from({length: maxPhase}).map((_,i) => {
                                        const v = i+1;
                                        return `<option value="${v}" ${Number(r.phase||1)===v?'selected':''}>${v}</option>`;
                                    }).join('')}
                                </select>
                            </div>
                            <div>
                                <div class="muted" style="font-size: 12px; margin-bottom: 6px;">Shift</div>
                                <select id="ftoShift" style="height: 44px; padding: 10px 12px; font-size: 14px;">
                                    ${['Morning','Evening','Night'].map(s => `<option value="${s}" ${String(r.shift||'Morning')===s?'selected':''}>${s}</option>`).join('')}
                                </select>
                            </div>
                        </div>

                        <div style="margin-top: 14px;">
                            <div class="muted" style="font-size: 12px; margin-bottom: 6px;">Ride Description</div>
                            <div id="ftoRideDescription" data-initial="${encodeURIComponent(String(r.ride_description || ''))}" style="margin-top: 6px;"></div>
                        </div>

                        <div style="margin-top: 14px;">
                            <div class="muted" style="font-size: 12px; margin-bottom: 6px;">Evaluation Categories (ratings required for submit)</div>
                            <div style="display:grid; grid-template-columns: 1fr; gap: 10px;">
                                ${FTO_EVAL_CATEGORIES.map(k => {
                                    const v = evalObj[k] || {};
                                    const label = String(k || '').replace(/([a-z])([A-Z])/g, '$1 $2');
                                    const current = Number.isFinite(Number(v.rating)) ? Number(v.rating) : 0;
                                    return `
                                        <div style="padding: 12px; border-radius: 10px; border: 1px solid rgba(255,255,255,0.08); background: rgba(255,255,255,0.03);">
                                            <div class="fto-editor-eval-row">
                                                <div class="fto-editor-eval-label">${escapeHtml(label)}</div>
                                                <div class="fto-editor-eval-sliderwrap">
                                                    <input class="fto-editor-eval-slider" type="range" min="0" max="5" step="1" value="${escapeHtml(String(current))}" data-fto-eval-rating="${escapeHtml(k)}" />
                                                    <div class="fto-editor-eval-track"><div class="fto-editor-eval-fill" style="width:${Math.round((current/5)*100)}%;"></div></div>
                                                </div>
                                                <div class="fto-editor-eval-value" data-fto-eval-value="${escapeHtml(k)}">${current ? escapeHtml(String(current.toFixed(1))) : '—'}</div>
                                            </div>
                                            <div id="ftoEvalComment_${escapeHtml(k)}" data-fto-eval-comment="${escapeHtml(k)}" data-initial="${encodeURIComponent(String(v.comment || ''))}" style="margin-top: 8px;"></div>
                                        </div>
                                    `;
                                }).join('')}
                            </div>
                        </div>

                        <div style="display:grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-top: 14px;">
                            <div>
                                <div class="muted" style="font-size: 12px; margin-bottom: 6px;">Strengths</div>
                                <div id="ftoStrengths" data-initial="${encodeURIComponent(String(r.strengths || ''))}" style="margin-top: 6px;"></div>
                            </div>
                            <div>
                                <div class="muted" style="font-size: 12px; margin-bottom: 6px;">Improvements</div>
                                <div id="ftoImprovements" data-initial="${encodeURIComponent(String(r.improvements || ''))}" style="margin-top: 6px;"></div>
                            </div>
                        </div>

                        <div style="display:grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-top: 14px;">
                            <div>
                                <div class="muted" style="font-size: 12px; margin-bottom: 6px;">Recommendation</div>
                                <select id="ftoRecommendation" style="height: 44px; padding: 10px 12px; font-size: 14px;">
                                    <option value="">Select...</option>
                                    ${['ADVANCE','REMAIN','REMEDIAL','TERMINATION'].map(x => `<option value="${x}" ${String(r.recommendation||'')===x?'selected':''}>${x}</option>`).join('')}
                                </select>
                            </div>
                            <div>
                                <div class="muted" style="font-size: 12px; margin-bottom: 6px;">Safety Concern</div>
                                <div style="display:flex; gap: 10px; align-items: center;">
                                    <input id="ftoSafetyConcern" type="checkbox" ${r.safety_concern ? 'checked' : ''} />
                                    <div class="muted" style="font-size: 12px;">If checked, notes are required for submit</div>
                                </div>
                            </div>
                        </div>

                        <div style="margin-top: 10px;">
                            <div class="muted" style="font-size: 12px; margin-bottom: 6px;">Safety Concern Notes</div>
                            <div id="ftoSafetyNotes" data-initial="${encodeURIComponent(String(r.safety_concern_notes || ''))}" style="margin-top: 6px;"></div>
                        </div>
                    </div>
                    <div class="incident-modal-footer">
                        <button class="incident-btn incident-btn-primary" id="ftoSaveDraftBtn">💾 Save as Draft</button>
                        <button class="incident-btn incident-btn-danger" id="ftoSubmitBtn">📨 Submit Report</button>
                    </div>
                </div>
            </div>
        `;

        document.getElementById('ftoEditBackdrop')?.remove();
        document.body.insertAdjacentHTML('beforeend', modalHTML);

        const initRteField = (id, placeholder, minHeight, maxHeight) => {
            const el = document.getElementById(id);
            if (!el || typeof createRTE !== 'function') return null;
            const initial = el.getAttribute('data-initial') ? decodeURIComponent(el.getAttribute('data-initial')) : '';
            return createRTE(id, {
                placeholder,
                initialContent: initial,
                minHeight,
                maxHeight
            });
        };

        window.__rteFtoRideDescription = initRteField('ftoRideDescription', 'Ride details...', '90px', '30vh');
        window.__rteFtoStrengths = initRteField('ftoStrengths', 'Strengths...', '80px', '30vh');
        window.__rteFtoImprovements = initRteField('ftoImprovements', 'Improvements...', '80px', '30vh');
        window.__rteFtoSafetyNotes = initRteField('ftoSafetyNotes', 'Safety concern notes...', '70px', '30vh');

        // Initialize evaluation comment fields
        FTO_EVAL_CATEGORIES.forEach(k => {
            const id = `ftoEvalComment_${k}`;
            initRteField(id, 'Comment...', '54px', '25vh');
        });

        const backdrop = document.getElementById('ftoEditBackdrop');
        document.getElementById('ftoEditClose')?.addEventListener('click', () => backdrop.remove());
        backdrop.addEventListener('click', (e) => { if (e.target === backdrop) backdrop.remove(); });

        const setSelectedTrainee = (t) => {
            document.getElementById('ftoTraineeCid').value = String(t.cid || '');
            document.getElementById('ftoTraineeName').value = String(t.name || '');
            document.getElementById('ftoTraineeCallsign').value = String(t.callsign || '');
            const el = document.getElementById('ftoTraineeSelected');
            if (el) el.textContent = t.name ? (`Selected: ${t.name}${t.callsign ? ' (' + t.callsign + ')' : ''}`) : 'No trainee selected';
        };

        // Pre-fill trainee selection if editing
        if (r.trainee_cid && r.trainee_name) {
            setSelectedTrainee({ cid: r.trainee_cid, name: r.trainee_name, callsign: r.trainee_callsign });
        }

        const traineeSelect = document.getElementById('ftoTraineeSelect');
        if (traineeSelect) {
            traineeSelect.innerHTML = `<option value="">Select trainee...</option>`;

            // Load all officers into dropdown (bounded server-side)
            sendCallback('searchTrainees', { query: '', limit: 200 }, (rr) => {
                const list = (rr && rr.success && Array.isArray(rr.trainees)) ? rr.trainees : [];
                traineeSelect.innerHTML = `<option value="">Select trainee...</option>` + list.map(t => {
                    const label = `${t.name} (${t.cid}${t.callsign ? ' · ' + t.callsign : ''})`;
                    const selected = (String(t.cid) === String(r.trainee_cid || '')) ? 'selected' : '';
                    return `<option value="${escapeHtml(String(t.cid))}" data-name="${escapeHtml(String(t.name))}" data-callsign="${escapeHtml(String(t.callsign||''))}" ${selected}>${escapeHtml(label)}</option>`;
                }).join('');

                // If editing, set hidden selection
                if (r.trainee_cid) {
                    const opt = traineeSelect.querySelector(`option[value="${CSS.escape(String(r.trainee_cid))}"]`);
                    if (opt) {
                        setSelectedTrainee({ cid: r.trainee_cid, name: r.trainee_name, callsign: r.trainee_callsign });
                    }
                }
            });

            traineeSelect.addEventListener('change', () => {
                const cid = traineeSelect.value;
                const opt = traineeSelect.options[traineeSelect.selectedIndex];
                const name = opt?.getAttribute('data-name') || '';
                const callsign = opt?.getAttribute('data-callsign') || '';
                if (!cid) {
                    setSelectedTrainee({ cid: '', name: '', callsign: '' });
                    return;
                }
                setSelectedTrainee({ cid, name, callsign });
            });
        }

        // Slider UI sync for evaluation ratings
        const syncEvalSlider = (k, val) => {
            const valueEl = document.querySelector(`[data-fto-eval-value="${k}"]`);
            if (valueEl) valueEl.textContent = (val >= 1 && val <= 5) ? val.toFixed(1) : '—';
            const sliderEl = document.querySelector(`input.fto-editor-eval-slider[data-fto-eval-rating="${k}"]`);
            const card = sliderEl ? sliderEl.closest('.fto-editor-eval-row') : null;
            const fillEl = card ? card.querySelector('.fto-editor-eval-fill') : null;
            if (fillEl) {
                const pct = (val >= 0 && val <= 5) ? Math.round((val / 5) * 100) : 0;
                fillEl.style.width = `${pct}%`;
            }
        };
        FTO_EVAL_CATEGORIES.forEach(k => {
            const sliderEl = document.querySelector(`input.fto-editor-eval-slider[data-fto-eval-rating="${k}"]`);
            if (!sliderEl) return;
            const initial = Number(sliderEl.value) || 0;
            syncEvalSlider(k, initial);
            sliderEl.addEventListener('input', () => {
                syncEvalSlider(k, Number(sliderEl.value) || 0);
            });
        });

        const buildPayload = () => {
            const getRteHtml = (id) => {
                const rte = (typeof getRTE === 'function') ? getRTE(id) : null;
                return rte ? String(rte.getValue() || '') : (document.getElementById(id)?.textContent || '');
            };
            const traineeCid = document.getElementById('ftoTraineeCid').value;
            const traineeName = document.getElementById('ftoTraineeName').value;
            const traineeCallsign = document.getElementById('ftoTraineeCallsign').value;
            let rideDate = document.getElementById('ftoRideDate').value;
            // Auto-fill ride date with now if left empty
            if (!rideDate) {
                try {
                    const now = new Date();
                    const tzOffset = now.getTimezoneOffset();
                    const local = new Date(now.getTime() - tzOffset * 60000);
                    rideDate = local.toISOString().slice(0, 16);
                    const rideInput = document.getElementById('ftoRideDate');
                    if (rideInput) rideInput.value = rideDate;
                } catch (_) { /* ignore */ }
            }
            const phase = Number(document.getElementById('ftoPhase').value) || 1;
            const shift = document.getElementById('ftoShift').value;
            const rideDescription = getRteHtml('ftoRideDescription');
            const strengths = getRteHtml('ftoStrengths');
            const improvements = getRteHtml('ftoImprovements');
            const recommendation = document.getElementById('ftoRecommendation').value;
            const safetyConcern = document.getElementById('ftoSafetyConcern').checked;
            const safetyNotes = getRteHtml('ftoSafetyNotes');
            const evaluation = {};
            FTO_EVAL_CATEGORIES.forEach(k => {
                const ratingEl = document.querySelector(`[data-fto-eval-rating="${k}"]`);
                const commentId = `ftoEvalComment_${k}`;
                const raw = ratingEl ? Number(ratingEl.value) : 0;
                const ratingOut = (Number.isFinite(raw) && raw >= 1 && raw <= 5) ? raw : '';
                evaluation[k] = {
                    rating: ratingOut,
                    comment: getRteHtml(commentId)
                };
            });

            const payload = {
                report_uid: reportUid || (r.report_uid || ''),
                trainee_cid: traineeCid,
                trainee_name: traineeName,
                trainee_callsign: traineeCallsign || null,
                ride_date: rideDate || null,
                phase,
                shift,
                ride_description: rideDescription || null,
                evaluation_json: evaluation,
                strengths: strengths || null,
                improvements: improvements || null,
                recommendation: recommendation || null,
                safety_concern: safetyConcern ? 1 : 0,
                safety_concern_notes: safetyNotes || null
            };
            if (!payload.report_uid) delete payload.report_uid;
            return payload;
        };

        document.getElementById('ftoSaveDraftBtn')?.addEventListener('click', () => {
            const p = buildPayload();
            if (!p.trainee_cid) {
                mdtToast('Select a trainee first', 'error');
                return;
            }
            sendCallback('saveFtoDraft', p, (rr) => {
                if (rr && rr.success) {
                    mdtToast('Draft saved', 'success');
                    backdrop.remove();
                    const page = router?.pages?.get('fto');
                    page?.loadReports?.();
                    if (!reportUid && rr.report_uid) {
                        // allow user to re-open editor on the newly created draft
                        setTimeout(() => openFtoReportEditor(rr.report_uid), 100);
                    }
                } else {
                    mdtToast('Draft save failed', 'error');
                }
            });
        });

        document.getElementById('ftoSubmitBtn')?.addEventListener('click', () => {
            const p = buildPayload();
            sendCallback('submitFtoReport', p, (rr) => {
                if (rr && rr.success) {
                    mdtToast('Submitted', 'success');
                    backdrop.remove();
                    const page = router?.pages?.get('fto');
                    page?.loadReports?.();
                } else {
                    const err = (rr && rr.errors && rr.errors.length) ? rr.errors.join(', ') : (rr && rr.error) || 'Submit failed';
                    mdtToast(err, 'error');
                }
            });
        });
    };

    if (reportUid) {
        sendCallback('getFtoReport', { report_uid: reportUid }, (res) => {
            if (!res || !res.success) {
                mdtToast('Failed to load report', 'error');
                return;
            }
            openWith(res.report || {}, res.permissions || {});
        });
    } else {
        openWith({}, { canEdit: true });
    }
};


// ============================================================================
// CHARGES MANAGEMENT PAGE (Supervisors Only)
// ============================================================================
// Close modals on close button
document.addEventListener('click', (e) => {
    const closeBtn = e.target.closest && e.target.closest('.close-modal');
    if (closeBtn) {
        closeBtn.closest('.modal')?.classList.add('hidden');
    }
});

// ============================================================================
// CRIMINAL CODE (Read-only reference)
// ============================================================================
class CriminalCodePage extends BasePage {
    constructor() {
        super('criminalcode', 'Criminal Code');
        this.searchQuery = '';
        this.selectedCategory = 'all';
        this.selectedSeverity = 'all';
        this.charges = [];
        this.searchTimeout = null;
        this.currentPage = 1;
        this.pageSize = 18;
    }

    cleanup() {
        if (this.searchTimeout) clearTimeout(this.searchTimeout);
    }

    mount(root) {
        super.mount(root);
        root.innerHTML = `
            <div class="search-page-container">
                <div class="search-page-header">
                    <div class="search-page-title-group">
                        <h2>Criminal Code</h2>
                        <div class="search-page-subtitle">Legal reference for consistent charge application</div>
                    </div>
                </div>

                <div class="search-page-controls" style="flex-wrap:wrap; align-items:center;">
                    <input type="text" id="ccSearchInput" class="search-page-input" placeholder="Search by code, name, category, or description..." style="min-width: 260px;" />

                    <select id="ccCategorySelect" class="search-page-input" style="width: 220px; flex: 0 0 auto;">
                        <option value="all">All Categories</option>
                    </select>

                    <select id="ccSeveritySelect" class="search-page-input" style="width: 220px; flex: 0 0 auto;">
                        <option value="all">All Severities</option>
                        <option value="Infraction">Infraction</option>
                        <option value="Misdemeanor">Misdemeanor</option>
                        <option value="Felony">Felony</option>
                    </select>
                </div>

                <div class="muted" style="margin-top: 4px;">
                    Read-only reference. Command staff can manage charges in the Charges page.
                </div>

                <div id="ccList" class="results-grid"></div>
                <div class="pagination-footer" style="margin-top: 10px;">
                    <span id="ccPaginationText">Showing 0 to 0 of 0 Offenses</span>
                    <div class="pagination-buttons">
                        <button id="ccPrevBtn" class="pagination-btn">Previous</button>
                        <button id="ccNextBtn" class="pagination-btn">Next</button>
                    </div>
                </div>
            </div>
        `;

        this.attachListeners();
        this.loadCharges();
    }

    attachListeners() {
        const input = document.getElementById('ccSearchInput');
        input?.addEventListener('input', (e) => {
            this.searchQuery = String(e.target.value || '');
            clearTimeout(this.searchTimeout);
            this.searchTimeout = setTimeout(() => {
                this.currentPage = 1;
                this.render();
            }, 150);
        });

        document.getElementById('ccCategorySelect')?.addEventListener('change', (e) => {
            this.selectedCategory = String(e.target.value || 'all');
            this.currentPage = 1;
            this.render();
        });

        document.getElementById('ccSeveritySelect')?.addEventListener('change', (e) => {
            this.selectedSeverity = String(e.target.value || 'all');
            this.currentPage = 1;
            this.render();
        });

        document.getElementById('ccPrevBtn')?.addEventListener('click', () => {
            if (this.currentPage > 1) {
                this.currentPage--;
                this.renderList();
            }
        });
        document.getElementById('ccNextBtn')?.addEventListener('click', () => {
            const total = this.filterCharges().length;
            const maxPage = Math.max(1, Math.ceil(total / this.pageSize));
            if (this.currentPage < maxPage) {
                this.currentPage++;
                this.renderList();
            }
        });
    }

    loadCharges() {
        sendCallback('pf_mdt:getAllCharges', {}, (res) => {
            this.charges = Array.isArray(res) ? res : [];
            this.populateCategorySelect();
            this.render();
        });
    }

    populateCategorySelect() {
        const sel = document.getElementById('ccCategorySelect');
        if (!sel) return;

        const cats = new Set();
        (this.charges || []).forEach((c) => {
            const cat = (c && c.category) ? String(c.category) : '';
            if (cat.trim()) cats.add(cat.trim());
        });
        const list = Array.from(cats).sort((a, b) => a.localeCompare(b));

        sel.innerHTML = `<option value="all">All Categories</option>` +
            list.map((c) => `<option value="${escapeHtml(c)}">${escapeHtml(c)}</option>`).join('');
        sel.value = this.selectedCategory;
    }

    getSeverity(charge) {
        const fine = Number(charge?.fineAmount || 0);
        const jail = Number(charge?.prisonTime || 0);
        if (jail >= 120 || fine >= 20000) return 'Felony';
        if (jail > 0 || fine >= 1000) return 'Misdemeanor';
        return 'Infraction';
    }

    parseDescription(text) {
        const raw = String(text || '').trim();
        const out = {
            definition: '',
            explanation: '',
            elements: [],
            notes: ''
        };

        if (!raw) return out;

        const lines = raw.split(/\r?\n/);
        let section = null;
        const pushLine = (target, line) => {
            const v = String(line || '').trim();
            if (!v) return;
            target.push(v);
        };

        const defLines = [];
        const expLines = [];
        const noteLines = [];
        const elementLines = [];

        for (const line of lines) {
            const l = String(line || '').trim();
            if (!l) continue;

            const m = l.match(/^(definition|formal definition|plain|plain-language|plain language|explanation|elements|checklist|notes|enforcement notes|stacking guidance)\s*:\s*(.*)$/i);
            if (m) {
                const key = m[1].toLowerCase();
                const rest = (m[2] || '').trim();
                if (key.includes('definition')) section = 'definition';
                else if (key.includes('plain') || key.includes('explanation')) section = 'explanation';
                else if (key.includes('elements') || key.includes('checklist')) section = 'elements';
                else section = 'notes';

                if (rest) {
                    if (section === 'definition') pushLine(defLines, rest);
                    else if (section === 'explanation') pushLine(expLines, rest);
                    else if (section === 'elements') pushLine(elementLines, rest);
                    else pushLine(noteLines, rest);
                }
                continue;
            }

            if (section === 'elements') {
                const cleaned = l.replace(/^[-*]\s+/, '').replace(/^\[[ xX]\]\s+/, '');
                pushLine(elementLines, cleaned);
            } else if (section === 'definition') {
                pushLine(defLines, l);
            } else if (section === 'explanation') {
                pushLine(expLines, l);
            } else if (section === 'notes') {
                pushLine(noteLines, l);
            } else {
                pushLine(defLines, l);
            }
        }

        out.definition = defLines.join('\n');
        out.explanation = expLines.join('\n');
        out.elements = elementLines;
        out.notes = noteLines.join('\n');

        if (!out.explanation) out.explanation = out.definition;
        return out;
    }

    filterCharges() {
        const q = (this.searchQuery || '').toLowerCase().trim();
        return (this.charges || []).filter((c) => {
            if (!c) return false;
            const cat = String(c.category || '').trim();
            if (this.selectedCategory !== 'all' && cat !== this.selectedCategory) return false;

            const sev = this.getSeverity(c);
            if (this.selectedSeverity !== 'all' && sev !== this.selectedSeverity) return false;

            if (!q) return true;
            const hay = [c.code, c.name, c.category, c.description].map((x) => String(x || '')).join(' ').toLowerCase();
            return hay.includes(q);
        });
    }

    render() {
        this.renderList();
    }

    renderList() {
        const root = document.getElementById('ccList');
        if (!root) return;

        const rows = this.filterCharges();
        const total = rows.length;

        const paginationText = document.getElementById('ccPaginationText');
        const prevBtn = document.getElementById('ccPrevBtn');
        const nextBtn = document.getElementById('ccNextBtn');

        const maxPage = Math.max(1, Math.ceil(total / this.pageSize));
        if (this.currentPage > maxPage) this.currentPage = maxPage;
        const startIdx = (this.currentPage - 1) * this.pageSize;
        const endIdx = Math.min(startIdx + this.pageSize, total);

        if (paginationText) {
            paginationText.textContent = total
                ? `Showing ${startIdx + 1} to ${endIdx} of ${total} Offenses`
                : 'Showing 0 to 0 of 0 Offenses';
        }
        if (prevBtn) prevBtn.disabled = this.currentPage <= 1;
        if (nextBtn) nextBtn.disabled = this.currentPage >= maxPage;

        if (total === 0) {
            root.innerHTML = `<div class="empty-message">No offenses match your search/filters.</div>`;
            return;
        }

        const pageRows = rows.slice(startIdx, endIdx);
        root.innerHTML = pageRows.map((c) => {
            const fine = Number(c.fineAmount || 0);
            const jail = Number(c.prisonTime || 0);
            const sev = this.getSeverity(c);
            const cat = String(c.category || 'General');
            const desc = String(c.description || '').trim();
            return `
                <div class="report-card">
                    <div style="display:flex; justify-content:space-between; align-items:flex-start; gap:10px;">
                        <div>
                            <div style="font-weight:800;">${escapeHtml(c.code || '')} — ${escapeHtml(c.name || '')}</div>
                            <div class="muted" style="margin-top:2px;">${escapeHtml(cat)} • ${escapeHtml(sev)}</div>
                            <div class="muted" style="margin-top:8px; white-space: pre-wrap; overflow:hidden; display:-webkit-box; -webkit-line-clamp:3; -webkit-box-orient: vertical;">${escapeHtml(desc || 'Not provided.')}</div>
                        </div>
                        <div style="text-align:right; font-size:12px;">
                            <div><strong>$${fine.toLocaleString()}</strong> fine</div>
                            <div><strong>${jail}</strong> min jail</div>
                        </div>
                    </div>
                </div>
            `;
        }).join('');
    }
}

// ============================================================================
// WEAPONS REGISTRY (Dedicated registry-style page)
// ============================================================================
class WeaponsRegistryPage extends BasePage {
    constructor() {
        super('weapons', 'Weapons');
        this.weapons = [];
        this.filteredWeapons = [];
        this.searchQuery = '';
        this.selectedModel = 'all';
        this.weaponModels = [];
        this.ownerResults = [];
        this.selectedOwner = null;
        this.selectedWeaponModel = null;
        this.serialCheckTimeout = null;
        this.ownerSearchTimeout = null;
        this.serialAvailable = null;
        this.serverNowText = '';
    }

    cleanup() {
        if (this.serialCheckTimeout) clearTimeout(this.serialCheckTimeout);
        if (this.ownerSearchTimeout) clearTimeout(this.ownerSearchTimeout);
    }

    mount(root) {
        super.mount(root);
        const canRegister = !!(window.mdtConfig && window.mdtConfig.manualEntriesEnabled && userPermissions && userPermissions.allowed);

        root.innerHTML = `
            <div class="search-page-container">
                <div class="search-page-header">
                    <div class="search-page-title-group">
                        <h2>Weapons Registry</h2>
                        <div class="search-page-subtitle">Registered firearms and weapon serials</div>
                    </div>
                    ${canRegister ? `<button id="openRegisterWeaponBtn" class="page-action-btn">+ New Entry</button>` : ''}
                </div>

                <div class="search-page-controls" style="display:flex; gap:8px;">
                    <input type="text" id="weaponsSearchInput" class="search-page-input" placeholder="Search serial, owner, or weapon..." />
                    <select id="weaponsModelSelect" style="padding: 8px; border-radius: 6px; border: 1px solid rgba(59,130,246,0.3); background: rgba(59,130,246,0.1); color: #fff; max-width: 240px;">
                        <option value="all">All Weapon Models</option>
                    </select>
                </div>

                <div id="weaponGrid" class="results-grid"></div>

                <div id="registerWeaponModal" class="modal hidden">
                    <div class="modal-card" style="width: 760px; max-height: 90vh; overflow-y: auto;">
                        <div class="modal-header">
                            <h3>New Weapon Entry</h3>
                            <button class="modal-btn close-modal" title="Close">
                                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="18" y1="6" x2="6" y2="18"></line><line x1="6" y1="6" x2="18" y2="18"></line></svg>
                            </button>
                        </div>
                        <div class="modal-body">
                            <div class="form-section">
                                <h4>Owner</h4>
                                <label class="form-row">
                                    <span>Search Owner</span>
                                    <input type="text" id="weaponOwnerSearch" placeholder="Type a name or citizen ID to search..." />
                                    <div id="weaponOwnerResults" class="dropdown hidden" style="max-height: 220px; overflow-y: auto; margin-top: 4px;"></div>
                                </label>
                                <div id="weaponOwnerSelected" class="muted" style="margin-top: 6px;"></div>
                            </div>

                            <div class="form-section">
                                <h4>Details</h4>
                                <div style="display:grid; grid-template-columns: 1fr 1fr; gap:12px;">
                                    <label class="form-row">
                                        <span>Registration Date</span>
                                        <input type="text" id="weaponRegisterDate" readonly />
                                    </label>
                                    <label class="form-row">
                                        <span>Serial Number</span>
                                        <input type="text" id="weaponSerialInput" placeholder="Enter unique serial..." />
                                        <div id="weaponSerialStatus" class="muted" style="margin-top: 6px;"></div>
                                    </label>
                                </div>
                            </div>

                            <div class="form-section">
                                <h4>Weapon</h4>
                                <label class="form-row">
                                    <span>Weapon Model</span>
                                    <input type="text" id="weaponModelSearch" placeholder="Type to search (e.g., glock, pistol)..." />
                                    <div id="weaponModelResults" class="dropdown hidden" style="max-height: 220px; overflow-y: auto; margin-top: 4px;"></div>
                                </label>
                                <div id="weaponModelSelected" class="muted" style="margin-top: 6px;"></div>
                            </div>

                            <div class="form-section">
                                <h4>Notes</h4>
                                <label class="form-row">
                                    <span>Notes (optional)</span>
                                    <textarea id="weaponNotesInput" rows="3" placeholder="Recovered during traffic stop, purchased legally, etc."></textarea>
                                </label>
                            </div>
                        </div>

                        <div class="modal-footer">
                            <button id="registerWeaponCancelBtn" class="modal-btn">Cancel</button>
                            <button id="registerWeaponSubmitBtn" class="modal-btn primary">Create Entry</button>
                        </div>
                    </div>
                </div>
            </div>
        `;

        // IMPORTANT:
        // The MDT app container uses transforms for centering, which can cause
        // position:fixed modals to behave like they are "fixed" to that container
        // instead of the real viewport. Move this modal to <body> so it centers
        // correctly without changing any IDs (keeps the script stable).
        const registerModal = document.getElementById('registerWeaponModal');
        if (registerModal && registerModal.parentElement !== document.body) {
            document.body.appendChild(registerModal);
        }

        this.attachListeners();
        this.loadWeaponModels();
        this.loadWeapons();
    }

    attachListeners() {
        document.getElementById('weaponsSearchInput')?.addEventListener('input', (e) => {
            this.searchQuery = String(e.target.value || '');
            this.applyFilters();
        });

        document.getElementById('weaponsModelSelect')?.addEventListener('change', (e) => {
            this.selectedModel = String(e.target.value || 'all');
            this.applyFilters();
        });

        document.getElementById('openRegisterWeaponBtn')?.addEventListener('click', () => this.openRegisterModal());
        document.getElementById('registerWeaponCancelBtn')?.addEventListener('click', () => this.closeRegisterModal());
        document.getElementById('registerWeaponSubmitBtn')?.addEventListener('click', () => this.submitRegistration());

        document.getElementById('weaponOwnerSearch')?.addEventListener('input', (e) => {
            const q = String(e.target.value || '').trim();
            clearTimeout(this.ownerSearchTimeout);
            this.ownerSearchTimeout = setTimeout(() => this.searchOwners(q), 200);
        });

        document.getElementById('weaponModelSearch')?.addEventListener('input', (e) => {
            const q = String(e.target.value || '').trim().toLowerCase();
            this.renderWeaponModelResults(q);
        });

        document.getElementById('weaponSerialInput')?.addEventListener('input', (e) => {
            const serial = String(e.target.value || '').trim();
            this.serialAvailable = null;
            this.renderSerialStatus();
            clearTimeout(this.serialCheckTimeout);
            this.serialCheckTimeout = setTimeout(() => this.checkSerial(serial), 200);
        });

        // Close dropdowns when clicking elsewhere
        document.addEventListener('click', (e) => {
            const ownerResults = document.getElementById('weaponOwnerResults');
            const modelResults = document.getElementById('weaponModelResults');
            if (!ownerResults || !modelResults) return;

            const ownerSearch = document.getElementById('weaponOwnerSearch');
            const modelSearch = document.getElementById('weaponModelSearch');

            if (ownerSearch && !ownerSearch.contains(e.target) && !ownerResults.contains(e.target)) {
                ownerResults.classList.add('hidden');
            }
            if (modelSearch && !modelSearch.contains(e.target) && !modelResults.contains(e.target)) {
                modelResults.classList.add('hidden');
            }
        });
    }

    loadWeapons() {
        sendCallback('getWeaponRegistry', {}, (res) => {
            if (res && res.success) {
                this.weapons = Array.isArray(res.weapons) ? res.weapons : [];
            } else {
                this.weapons = [];
            }
            this.applyFilters();
        });
    }

    loadWeaponModels() {
        sendCallback('getWeaponModels', {}, (res) => {
            const list = (res && res.success && Array.isArray(res.models)) ? res.models : [];
            this.weaponModels = list;
            this.populateModelFilter();
        });
    }

    populateModelFilter() {
        const sel = document.getElementById('weaponsModelSelect');
        if (!sel) return;
        const opts = this.weaponModels
            .slice()
            .sort((a, b) => String(a.label || '').localeCompare(String(b.label || '')))
            .map((m) => `<option value="${escapeHtml(String(m.weapon || ''))}">${escapeHtml(String(m.label || m.weapon || ''))}</option>`);
        sel.innerHTML = `<option value="all">All Weapon Models</option>` + opts.join('');
        sel.value = this.selectedModel;
    }

    applyFilters() {
        const q = (this.searchQuery || '').toLowerCase().trim();
        const model = this.selectedModel;
        this.filteredWeapons = (this.weapons || []).filter((w) => {
            if (!w) return false;
            if (model !== 'all' && String(w.weapon || '') !== model) return false;
            if (!q) return true;
            const hay = [w.serial, w.weaponLabel, w.weapon, w.ownerName, w.ownerCitizenId].map((x) => String(x || '')).join(' ').toLowerCase();
            return hay.includes(q);
        });
        this.renderGrid();
    }

    renderGrid() {
        const grid = document.getElementById('weaponGrid');
        if (!grid) return;

        if (!this.filteredWeapons || this.filteredWeapons.length === 0) {
            grid.innerHTML = `<div class="empty-message" style="grid-column: 1/-1;">No weapons found</div>`;
            return;
        }

        grid.innerHTML = this.filteredWeapons.map((w) => {
            const serial = String(w.serial || '').trim();
            const weaponLabel = String(w.weaponLabel || w.weapon || '').trim();
            const weaponKey = String(w.weapon || '').trim();
            const ownerName = String(w.ownerName || '').trim();
            const ownerCid = String(w.ownerCitizenId || '').trim();
            const whenRaw = w.registeredAt || w.registered_at || '';
            const whenPretty = (typeof formatDateTime === 'function') ? (formatDateTime(whenRaw) || String(whenRaw || '')) : String(whenRaw || '');
            const ownerPretty = ownerName ? `${ownerName}${ownerCid ? ` (${ownerCid})` : ''}` : (ownerCid || 'Unknown');

            return `
                <div class="incident-card">
                    <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 8px;">
                        <div style="flex: 1;">
                            <div class="incident-id">${escapeHtml(serial || 'UNKNOWN')}</div>
                            <div class="incident-title">${escapeHtml(weaponLabel || weaponKey || 'Unknown Weapon')}</div>
                        </div>
                        <div class="incident-status status-active">REGISTERED</div>
                    </div>
                    <div class="incident-divider"></div>
                    <div class="incident-meta">
                        <div><span class="meta-label">👤</span> ${escapeHtml(ownerPretty)}</div>
                        <div><span class="meta-label">🔫</span> ${escapeHtml(weaponKey || 'Unknown')}</div>
                        <div><span class="meta-label">📅</span> ${escapeHtml(whenPretty || 'Unknown')}</div>
                    </div>
                </div>
            `;
        }).join('');
    }

    openRegisterModal() {
        this.selectedOwner = null;
        this.selectedWeaponModel = null;
        this.serialAvailable = null;
        this.ownerResults = [];

        const modal = document.getElementById('registerWeaponModal');
        if (!modal) return;
        modal.classList.remove('hidden');

        const ownerSearch = document.getElementById('weaponOwnerSearch');
        const ownerSelected = document.getElementById('weaponOwnerSelected');
        const modelSearch = document.getElementById('weaponModelSearch');
        const modelSelected = document.getElementById('weaponModelSelected');
        const serialInput = document.getElementById('weaponSerialInput');
        const notesInput = document.getElementById('weaponNotesInput');
        const ownerResults = document.getElementById('weaponOwnerResults');
        const modelResults = document.getElementById('weaponModelResults');

        if (ownerSearch) ownerSearch.value = '';
        if (modelSearch) modelSearch.value = '';
        if (serialInput) serialInput.value = '';
        if (notesInput) notesInput.value = '';
        if (ownerSelected) ownerSelected.textContent = '';
        if (modelSelected) modelSelected.textContent = '';
        if (ownerResults) { ownerResults.innerHTML = ''; ownerResults.classList.add('hidden'); }
        if (modelResults) { modelResults.innerHTML = ''; modelResults.classList.add('hidden'); }

        this.renderSerialStatus();
        this.loadServerTime();
        this.updateSubmitState();
    }

    closeRegisterModal() {
        document.getElementById('registerWeaponModal')?.classList.add('hidden');
    }

    loadServerTime() {
        sendCallback('getServerTime', {}, (res) => {
            const text = (res && res.success && res.now) ? String(res.now) : '';
            this.serverNowText = text;
            const input = document.getElementById('weaponRegisterDate');
            if (input) input.value = text || 'Auto-set on save';
        });
    }

    searchOwners(query) {
        const box = document.getElementById('weaponOwnerResults');
        if (!box) return;

        if (!query || query.length < 2) {
            this.ownerResults = [];
            box.classList.add('hidden');
            return;
        }

        sendCallback('searchWeaponOwners', { query }, (res) => {
            const data = (res && Array.isArray(res.data)) ? res.data : (res && Array.isArray(res.citizens) ? res.citizens : []);
            this.ownerResults = data;
            this.renderOwnerResults();
        });
    }

    renderOwnerResults() {
        const box = document.getElementById('weaponOwnerResults');
        if (!box) return;

        if (!this.ownerResults || this.ownerResults.length === 0) {
            box.innerHTML = `<div class="dropdown-item" style="cursor: default;">No matches.</div>`;
            box.classList.remove('hidden');
            return;
        }

        box.innerHTML = this.ownerResults.slice(0, 20).map((c) => {
            const name = c.name || c.fullname || c.fullName || '';
            const cid = c.citizenid || c.citizenId || c.citizen_id || '';
            return `
                <div class="dropdown-item" data-cid="${escapeHtml(String(cid))}" data-name="${escapeHtml(String(name))}">
                    <div style="font-weight: 700;">${escapeHtml(String(name))}</div>
                    <div class="muted" style="margin-top: 2px;">CID: ${escapeHtml(String(cid))}</div>
                </div>
            `;
        }).join('');

        box.classList.remove('hidden');

        box.querySelectorAll('.dropdown-item').forEach((el) => {
            el.addEventListener('click', () => {
                const cid = el.getAttribute('data-cid');
                const name = el.getAttribute('data-name');
                this.selectedOwner = { citizenid: cid, name: name };
                document.getElementById('weaponOwnerSelected').textContent = `Selected: ${name} (${cid})`;
                document.getElementById('weaponOwnerSearch').value = `${name}`;
                box.classList.add('hidden');
                this.updateSubmitState();
            });
        });
    }

    renderWeaponModelResults(queryLower) {
        const box = document.getElementById('weaponModelResults');
        if (!box) return;

        const q = String(queryLower || '').trim();
        const list = this.weaponModels || [];
        const results = q
            ? list.filter((m) => {
                const hay = `${m.weapon || ''} ${m.label || ''}`.toLowerCase();
                return hay.includes(q);
            })
            : list;

        const shown = results.slice(0, 30);
        if (shown.length === 0) {
            box.innerHTML = `<div class="dropdown-item" style="cursor: default;">No matches.</div>`;
            box.classList.remove('hidden');
            return;
        }

        box.innerHTML = shown.map((m) => `
            <div class="dropdown-item" data-weapon="${escapeHtml(String(m.weapon || ''))}" data-label="${escapeHtml(String(m.label || m.weapon || ''))}">
                <div style="font-weight: 700;">${escapeHtml(String(m.label || m.weapon || ''))}</div>
                <div class="muted" style="margin-top: 2px;">${escapeHtml(String(m.weapon || ''))}</div>
            </div>
        `).join('');

        box.classList.remove('hidden');

        box.querySelectorAll('.dropdown-item').forEach((el) => {
            el.addEventListener('click', () => {
                const weapon = el.getAttribute('data-weapon');
                const label = el.getAttribute('data-label');
                this.selectedWeaponModel = { weapon, label };
                document.getElementById('weaponModelSelected').textContent = `Selected: ${label}`;
                document.getElementById('weaponModelSearch').value = label;
                box.classList.add('hidden');
                this.updateSubmitState();
            });
        });
    }

    checkSerial(serial) {
        if (!serial) {
            this.serialAvailable = null;
            this.renderSerialStatus();
            this.updateSubmitState();
            return;
        }

        sendCallback('checkWeaponSerial', { serial }, (res) => {
            if (res && res.success) {
                this.serialAvailable = !res.exists;
            } else {
                this.serialAvailable = null;
            }
            this.renderSerialStatus();
            this.updateSubmitState();
        });
    }

    renderSerialStatus() {
        const el = document.getElementById('weaponSerialStatus');
        if (!el) return;
        const serial = String(document.getElementById('weaponSerialInput')?.value || '').trim();
        if (!serial) {
            el.textContent = 'Serial must be unique.';
            return;
        }
        if (this.serialAvailable === null) {
            el.textContent = 'Checking serial...';
            return;
        }
        el.textContent = this.serialAvailable ? 'Serial is available.' : 'Serial already exists.';
    }

    updateSubmitState() {
        const btn = document.getElementById('registerWeaponSubmitBtn');
        if (!btn) return;
        const serial = String(document.getElementById('weaponSerialInput')?.value || '').trim();
        const ok = !!(this.selectedOwner && this.selectedOwner.citizenid && this.selectedWeaponModel && this.selectedWeaponModel.weapon && serial && this.serialAvailable === true);
        btn.disabled = !ok;
    }

    submitRegistration() {
        const btn = document.getElementById('registerWeaponSubmitBtn');
        if (btn && btn.disabled) return;

        const serial = String(document.getElementById('weaponSerialInput')?.value || '').trim();
        const notes = String(document.getElementById('weaponNotesInput')?.value || '').trim();

        if (!this.selectedOwner || !this.selectedWeaponModel || !serial) {
            mdtToast('Missing required fields', 'error');
            return;
        }

        sendCallback('createManualWeapon', {
            ownerCitizenId: this.selectedOwner.citizenid,
            ownerName: this.selectedOwner.name,
            weapon: this.selectedWeaponModel.weapon,
            weaponLabel: this.selectedWeaponModel.label,
            serial: serial,
            notes: notes
        }, (res) => {
            if (res && res.success) {
                this.closeRegisterModal();
                this.loadWeapons();
                mdtToast('Weapon entry created', 'success');
            } else {
                mdtToast((res && res.error) ? String(res.error) : 'Failed to create weapon entry', 'error');
            }
        });
    }
}

// Expose classes on window for Router discovery and hot-registration
window.CitizenSearchPage = CitizenSearchPage;
window.VehicleSearchPage = VehicleSearchPage;
window.WarrantSearchPage = WarrantSearchPage;
window.IncidentsPage = IncidentsPage;
window.ReportsPage = ReportsPage;
window.FTOReportsPage = FTOReportsPage;
window.ChargesPage = ChargesPage;
window.CriminalCodePage = CriminalCodePage;
window.WeaponsRegistryPage = WeaponsRegistryPage;

// Hot-register extended pages if router already exists (race-condition safe)
function registerExtendedPagesIfPossible() {
    const r = window.router;
    if (!r || !r.register) return;
    const mapping = [
        ['citizens', CitizenSearchPage, 'Citizens'],
        ['vehicles', VehicleSearchPage, 'Vehicles'],
        ['warrant', WarrantSearchPage, 'Warrant'],
        ['incidents', IncidentsPage, 'Incidents'],
        ['reports', ReportsPage, 'Reports'],
        ['fto', FTOReportsPage, 'FTO Reports'],
        ['charges', ChargesPage, 'Charges'],
        ['criminalcode', CriminalCodePage, 'Criminal Code'],
        ['weapons', WeaponsRegistryPage, 'Weapons']
    ];
    let needsRemount = false;
    const current = r.current;
    mapping.forEach(([key, Cls, title]) => {
        const existing = r.pages.get(key);
        if (!(existing instanceof Cls)) {
            try { r.register(key, new Cls(), title); } catch (_) {}
            if (current === key) needsRemount = true;
        }
    });
    if (needsRemount) r.set(current);
}

if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', registerExtendedPagesIfPossible);
} else {
    registerExtendedPagesIfPossible();
}

// Open new warrant modal and reset form
window.openNewWarrantModal = function() {
    const modal = document.getElementById('newWarrantModal');
    if (!modal) return;
    
    // Reset all form fields
    document.getElementById('warrantCodeInput').value = 'W' + Math.floor(10000 + Math.random()*90000).toString();
    document.getElementById('warrantOfficerAuto').value = (window.userInfo && window.userInfo.name) ? window.userInfo.name : 'Officer';
    document.getElementById('warrantSuspectInput').value = '';
    document.getElementById('warrantTitleInput').value = '';
    document.getElementById('warrantChargeInput').value = '';
    document.getElementById('warrantOfficerInput').value = '';
    document.getElementById('warrantChargesList').innerHTML = '';
    document.getElementById('warrantSuspectChip').innerHTML = '';
    
    // Initialize RTEs
    if (!window.__rteWarrantWitnessStatement) {
        window.__rteWarrantWitnessStatement = createRTE('warrantWitnessStatementInput', {
            placeholder: 'Witness statement...',
            minHeight: '100px',
            maxHeight: '35vh'
        });
    } else {
        window.__rteWarrantWitnessStatement.clear();
    }
    
    if (!window.__rteWarrantNarrative) {
        window.__rteWarrantNarrative = createRTE('warrantNarrativeInput', {
            placeholder: 'Warrant narrative and details...',
            minHeight: '150px',
            maxHeight: '40vh'
        });
    } else {
        window.__rteWarrantNarrative.clear();
    }
    
    // Reset selections
    window.__selectedWarrantCharges = new Set();
    window.__selectedWarrantOfficers = new Set();
    window.__selectedWitnesses = [];
    window.__currentCitizenIdForWarrant = null;
    
    // Show modal
    modal.classList.remove('hidden');
};

// Wire warrant create button once when modal opens
(function setupWarrantModalHandlers(){
    let wired = false;
    const ensure = () => {
        if (wired) return;
        const createBtn = document.getElementById('warrantCreateBtn');
        if (!createBtn) return;
        wired = true;
        createBtn.addEventListener('click', () => {
            const suspectText = (document.getElementById('warrantSuspectInput')?.value || '').trim();
            const title = (document.getElementById('warrantTitleInput')?.value || '').trim();
            // Get narrative from RTE if available, fallback to textarea value
            let narrative = '';
            if (window.__rteWarrantNarrative) {
                narrative = window.__rteWarrantNarrative.getPlainText().trim();
            } else {
                narrative = (document.getElementById('warrantNarrativeInput')?.value || '').trim();
            }
            const warrantId = (document.getElementById('warrantCodeInput')?.value || '').trim();
            // Gather selected charges (chips) or fallback to comma-separated input
            let charges = [];
            if (window.__selectedWarrantCharges && window.__selectedWarrantCharges.size > 0) {
                charges = Array.from(window.__selectedWarrantCharges);
            } else {
                charges = (document.getElementById('warrantChargeInput')?.value || '')
                    .split(',').map(x=>x.trim()).filter(Boolean);
            }
            let officers = [];
            if (window.__selectedWarrantOfficers && window.__selectedWarrantOfficers.size > 0) {
                officers = Array.from(window.__selectedWarrantOfficers);
            } else {
                officers = (document.getElementById('warrantOfficerInput')?.value || '')
                    .split(',').map(x=>x.trim()).filter(Boolean);
            }
            const witnesses = window.__selectedWitnesses || [];
            console.log('[MDT DEBUG] Creating warrant with witnesses:', witnesses);
            sendCallback('createWarrant', {
                suspect: suspectText,
                title,
                charges,
                officers,
                narrative,
                witnesses,
                warrantId
            });
            const modal = document.getElementById('newWarrantModal');
            if (modal) modal.classList.add('hidden');
            
            // Auto-refresh warrants list
            setTimeout(() => {
                const router = window.router;
                const page = router?.pages?.get('warrant');
                if (page && page.loadWarrants) {
                    page.loadWarrants();
                }
                
                // If warrant was created from citizen profile, refresh that profile
                if (window.__currentCitizenIdForWarrant) {
                    sendCallback('openCitizen', { citizenId: window.__currentCitizenIdForWarrant });
                    window.__currentCitizenIdForWarrant = null;
                }
            }, 500);
        });
    };
    // Try now and also when DOM changes
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', ensure);
    } else {
        ensure();
    }
    // Mutation observer fallback
    const obs = new MutationObserver(ensure);
    obs.observe(document.documentElement, { childList: true, subtree: true });
})();

// Lightweight charges picker for the warrant modal
(function setupWarrantChargesPicker(){
    let wired = false;
    const ensure = () => {
        if (wired) return;
        const input = document.getElementById('warrantChargeInput');
        const dropdown = document.getElementById('warrantChargeDropdown');
        const list = document.getElementById('warrantChargesList');
        if (!input || !dropdown || !list) return;
        wired = true;

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
            list.innerHTML = items.map(o => `<span class="charge-chip" style="cursor:pointer;" data-officer="${o}">${o} ✕</span>`).join('');
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
            dropdown.innerHTML = items.slice(0, 80).map(o => `<div class="dropdown-item" data-pick="${o.replace(/"/g,'&quot;')}">${o}</div>`).join('');
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
                        <div style="font-weight:500;">${w.name}</div>
                        <div style="font-size:11px; color:rgba(255,255,255,0.6);">${w.phone || 'No phone'}</div>
                        <div style="font-size:11px; color:rgba(255,255,255,0.5); margin-top:4px;">${w.statement || 'No statement'}</div>
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
            dropdown.innerHTML = items.slice(0, 80).map(name => `<div class="dropdown-item" data-pick="${name.replace(/"/g,'&quot;')}">${name}</div>`).join('');
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
                return `<option value="${(w.citizenid || '')}">${name}</option>`;
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
                        <div class="citizen-photo" id="citizenProfilePhoto" style="${profilePicUrl ? 'background-image: url(' + profilePicUrl + ');' : ''}">
                            ${profilePicUrl ? '' : escapeHtml(initials)}
                        </div>
                        <div class="citizen-photo-actions">
                            <button class="btn small" onclick="openProfilePictureModal('${data.citizenId}')">Change Photo</button>
                            <button class="btn small" onclick="takeProfilePhoto('${data.citizenId}')">📷 Take Photo</button>
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
                            <div class="citizen-kv"><span class="citizen-k">Age</span><span class="citizen-v">${typeof data.age === 'number' && data.age >= 0 ? data.age : 'N/A'}</span></div>
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
                        <div class="summary-value">${data.warrantCount}</div>
                        <div class="summary-label">Active Warrants</div>
                    </div>
                    <div class="summary-card">
                        <div class="summary-value">${data.convictionCount}</div>
                        <div class="summary-label">Convictions</div>
                    </div>
                    <div class="summary-card">
                        <div class="summary-value">${data.vehicleCount}</div>
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
                return `<span class="flag-chip" style="cursor:pointer;" onclick="openFlagRemoveModal(decodeURIComponent('${payloadEnc}'))" title="Click to remove">${lbl}</span>`;
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
                }).replace(/\"/g, '&quot;');
                
                if (isActive) {
                    return `<span class="license-badge" style="cursor:pointer;" onclick="openLicenseModal('${licData}')" title="Click to manage">${licenseType}</span>`;
                } else if (isSuspended) {
                    return `<span class="license-badge" style="cursor:pointer; opacity:0.5; border-color: rgba(239,68,68,0.5);" onclick="openLicenseModal('${licData}')" title="Suspended - Click to manage">🚫 ${licenseType}</span>`;
                }
                return '';
            }).filter(Boolean);
            licenses = licenseElements.length > 0 ? licenseElements.join('') : '<span class="license-badge">None</span>';
        } else {
            licenses = '<span class="license-badge">None</span>';
        }
        const notes = (data.notes || []).map(n => `<div class="note-row"><div>${n.text}</div><div style="font-size:11px;color:rgba(255,255,255,0.6)">${n.author||''} • ${n.createdAt||''}</div></div>`).join('') || '<div class="empty-message">No notes</div>';

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
                const escAttr = (s) => String(s ?? '').replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\n/g, '\\n');
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
                const detailsBtn = `<button class=\"btn\" onclick=\"event.stopPropagation(); openWarrantDetails('${escAttr(w.warrantId)}','${escAttr(w.issuedBy)}','${escAttr(w.createdAt)}','${escAttr(cleanNarrative)}', decodeURIComponent('${chargesPayload}'), '${escAttr(w.status)}','${escAttr(w.suspectName || data.name)}','${escAttr(w.title || '')}', decodeURIComponent('${officersPayload}'), decodeURIComponent('${witnessesPayload}'));\">Details</button>`;
                const actions = w.status === 'active' ? `
                    <div style=\"display:flex; gap:8px; margin-top:8px;\">
                        <button class=\"btn success\" onclick=\"event.stopPropagation(); sendCallback('updateWarrantStatus', { warrantId: '${w.warrantId}', status: 'served', citizenId: '${data.citizenId}' }); setTimeout(()=>sendCallback('openCitizen', { citizenId: '${data.citizenId}' }), 300);\">Mark as Served</button>
                        <button class=\"btn danger\" onclick=\"event.stopPropagation(); sendCallback('updateWarrantStatus', { warrantId: '${w.warrantId}', status: 'removed', citizenId: '${data.citizenId}' }); setTimeout(()=>sendCallback('openCitizen', { citizenId: '${data.citizenId}' }), 300);\">Remove</button>
                        ${detailsBtn}
                    </div>` : `<div style=\"margin-top:8px;\">${detailsBtn}</div>`;
                const warrantDisplay = w.warrantId;
                return `
                <div class=\"warrant-item\" style=\"padding: 12px; background: rgba(255,255,255,0.03); border-radius: 6px; margin-bottom: 8px;\">
                    <div style=\"display: flex; justify-content: space-between; margin-bottom: 8px;\">
                        <span style=\"font-weight: bold;\">${warrantDisplay}</span>
                        <span class=\"status-badge ${w.status === 'active' ? 'warrant-active' : 'status-other'}\">${w.status}</span>
                    </div>
                    <div style=\"font-size: 12px; color: rgba(255,255,255,0.7); margin-bottom: 8px;\">
                        Issued by: ${w.issuedBy} • ${formatDateTime(w.createdAt)}
                    </div>
                    <div style=\"display: flex; gap: 6px; flex-wrap: wrap;\">
                        ${(w.charges || []).map(c => `<span class=\"charge-chip\">${c}</span>`).join('')}
                    </div>
                    ${cleanNarrative ? `<div style=\"margin-top: 8px; font-size: 12px; font-style: italic; color: rgba(255,255,255,0.6);\">${cleanNarrative}</div>` : ''}
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
                const colorDisplay = `<div style="display:flex; align-items:center; gap:6px;"><div title="Primary: ${escapeHtml(pInfo.name)}" style="width:12px;height:12px;border-radius:2px;border:1px solid rgba(255,255,255,0.35); background:${pInfo.hex}"></div><div title="Secondary: ${escapeHtml(sInfo.name)}" style="width:12px;height:12px;border-radius:2px;border:1px solid rgba(255,255,255,0.35); background:${sInfo.hex}"></div></div>`;
                return `
                    <div class="vehicle-item" style="padding: 12px; background: rgba(255,255,255,0.03); border-radius: 6px; margin-bottom: 8px; display: flex; justify-content: space-between; align-items: center;">
                        <div>
                            <div style="font-weight: bold;">${displayName}</div>
                            <div style="font-size: 12px; color: rgba(255,255,255,0.7); display: flex; align-items: center; gap: 8px;">Plate: ${v.plate} • ${colorDisplay}</div>
                        </div>
                        <button class="btn small" onclick="event.stopPropagation(); router.openVehicleProfile('${v.plate || ''}');">View</button>
                    </div>
                `;
            }).join('')
            : '<div class="empty-message">No vehicles</div>';
        
        // Incidents list
        const incidentsHtml = (data.incidents || []).length > 0
            ? (data.incidents || []).map(i => `
                <div class="incident-item" onclick="openIncidentDetails('${i.incidentId}')" style="cursor:pointer; padding: 12px; background: rgba(255,255,255,0.03); border-radius: 6px; margin-bottom: 8px;">
                    <div style="display: flex; justify-content: space-between; margin-bottom: 4px;">
                        <span style="font-weight: bold;">${escapeHtml(i.incidentId)}</span>
                        <span class="status-badge">${escapeHtml(i.status || 'active')}</span>
                    </div>
                    <div style="font-size: 14px; margin-bottom: 4px;">${escapeHtml(i.title || '')}</div>
                    <div style="font-size: 12px; color: rgba(255,255,255,0.6);">
                        ${escapeHtml(i.location || 'Unknown location')} • ${formatDateTime(i.createdAt)}
                    </div>
                </div>
            `).join('')
            : '<div class="empty-message">No incidents</div>';
        
        // Reports list
        const reportsHtml = (data.reports || []).length > 0
            ? (data.reports || []).map(r => `
                <div class="report-item" style="padding: 12px; background: rgba(255,255,255,0.03); border-radius: 6px; margin-bottom: 8px;">
                    <div style="display: flex; justify-content: space-between; margin-bottom: 4px;">
                        <span style="font-weight: bold;">${r.reportId}</span>
                        <span class="status-badge">${r.type}</span>
                    </div>
                    <div style="font-size: 14px; margin-bottom: 4px;">${r.title}</div>
                    <div style="font-size: 12px; color: rgba(255,255,255,0.6);">
                        Officer: ${r.officer} • ${r.createdAt}
                    </div>
                </div>
            `).join('')
            : '<div class="empty-message">No reports</div>';
        
        content.innerHTML = `
            <div data-view="c-overview">
                <h4 style="margin-bottom: 12px;">Personal Information</h4>
                <div style="display: grid; grid-template-columns: repeat(2, 1fr); gap: 12px; margin-bottom: 20px;">
                    <div class="info-row"><span class="label">Full Name:</span> <span>${data.name}</span></div>
                    <div class="info-row"><span class="label">Citizen ID:</span> <span>${data.citizenId}</span></div>
                    <div class="info-row"><span class="label">Date of Birth:</span> <span>${data.dob}</span></div>
                    <div class="info-row"><span class="label">Age:</span> <span>${typeof data.age === 'number' && data.age >= 0 ? data.age : 'N/A'}</span></div>
                    <div class="info-row"><span class="label">Gender:</span> <span>${data.gender || 'Unknown'}</span></div>
                    <div class="info-row"><span class="label">Nationality:</span> <span>${data.nationality || 'Unknown'}</span></div>
                    <div class="info-row"><span class="label">Phone:</span> <span>${data.phone || 'N/A'}</span></div>
                    <div class="info-row"><span class="label">Job:</span> <span>${data.job || 'Unemployed'}</span></div>
                </div>
                
                <h4 style="margin-bottom: 12px;">Physical Appearance</h4>
                <div style="display: grid; grid-template-columns: repeat(2, 1fr); gap: 12px; margin-bottom: 20px;">
                    <div class="info-row"><span class="label">Skin Tone:</span> <span>${skinToneLabel}</span></div>
                    <div class="info-row"><span class="label">Hair Color:</span> <span>${hairColorLabel}</span></div>
                    <div class="info-row"><span class="label">Eye Color:</span> <span>${eyeColorLabel}</span></div>
                    <div class="info-row"><span class="label">Hair Highlight:</span> <span>${hairHighlightLabel || 'Not recorded'}</span></div>
                    <div class="info-row"><span class="label">Gender:</span> <span>${genderLabel}</span></div>
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
                    <button class="btn primary" onclick="openNewWarrantForCitizen('${data.citizenId}', '${(data.name||'').replace(/'/g, "\\'")}')">Create Warrant</button>
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
                <h4 style="margin-bottom: 12px;">Owned Vehicles (${data.vehicleCount})</h4>
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
                    <button class="btn primary" onclick="openNewReportForCitizen('${data.citizenId}', '${(data.name||'').replace(/'/g, "\\'")}')">+ Create Report</button>
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
                const fineStatusBadge = (sentence) => {
                    const fine = Number(sentence && sentence.fineAmount || 0);
                    if (!(fine > 0)) return '';

                    const paid = Number(sentence && sentence.fineSuccess || 0) === 1;
                    if (paid) {
                        return '<span class="status-badge" style="background: rgba(76,175,80,0.22); border:1px solid rgba(76,175,80,0.45); color:#9cf3a1; margin-top:6px;">Fine Paid</span>';
                    }

                    return '<span class="status-badge" style="background: rgba(244,67,54,0.22); border:1px solid rgba(244,67,54,0.45); color:#ff9c9c; margin-top:6px;">Fine Unpaid</span>';
                };
                el.innerHTML = items.map(s => {
                    const when = s.createdAt ? formatDateTime(s.createdAt) : '';
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
                    const canPrint = !!(rowId && fine > 0);
                    const match = (activeId != null && rowId != null) ? (activeId === rowId) : false;
                    const showBail = isActive && (match || (activeId == null && items[0] === s)) && Number(activeJail?.bailAmount || 0) > 0;
                    const bailBtn = showBail
                        ? `<button class="btn" style="margin-top:6px;" onclick="openPostBailModal('${data.citizenId}', '${(data.name||'').replace(/'/g, "\\'")}', ${rowId || 'null'}, ${Number(activeJail.bailAmount || 0)})">Bail</button>`
                        : '';
                    const printBtn = canPrint
                        ? `<button class="btn" style="margin-top:6px;" onclick="printCitationPaper(${rowId})">Print Citation</button>`
                        : '';
                    return `
                        <div style="padding: 12px; background: rgba(255,255,255,0.03); border-radius: 6px; margin-bottom: 8px;">
                            <div style="display:flex; justify-content:space-between; align-items:center; gap:10px;">
                                <div style="font-weight:700;">${title}</div>
                                <div style="display:flex; flex-direction:column; align-items:flex-end;">
                                    ${badge(s.sentenceType)}
                                    ${fineStatusBadge(s)}
                                    ${printBtn}
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

        window.printCitationPaper = function(sentenceId) {
            const sid = Number(sentenceId || 0);
            if (!(sid > 0)) {
                if (typeof mdtToast === 'function') mdtToast('Invalid sentence record', 'error');
                return;
            }

            sendCallback('printCitationPaper', { sentenceId: sid }, (res) => {
                if (res && res.success) {
                    if (typeof mdtToast === 'function') mdtToast(`Citation printed (${res.citationUid || 'ready'})`, 'success');
                } else {
                    if (typeof mdtToast === 'function') mdtToast(res?.error || 'Failed to print citation', 'error');
                }
            });
        };
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
                <span onclick="removeSentenceCharge('${escapeHtml(c.code)}')" style="margin-left: 8px; cursor: pointer; opacity: 0.7;">✕</span>
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
        if (t) t.value = '';
        
        // Initialize/reset RTE for description
        if (!window.__rteSentenceDescription) {
            window.__rteSentenceDescription = createRTE('sentenceDescriptionInput', {
                placeholder: 'Sentencing description...',
                minHeight: '80px',
                maxHeight: '30vh'
            });
        } else {
            window.__rteSentenceDescription.clear();
        }

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
                const description = window.__rteSentenceDescription ? 
                    window.__rteSentenceDescription.getPlainText().trim() : 
                    (document.getElementById('sentenceDescriptionInput')?.textContent || '').trim();
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
        console.log('[MDT DEBUG] Warrant details witnesses:', witnesses);
        const st = String(status || '').toLowerCase();
        const statusClass = st === 'active' ? 'warrant-active' : 'status-other';
        const formattedDate = createdAt ? formatDateTime(createdAt) : 'Unknown';
        body.innerHTML = `
            <div style="display:grid; grid-template-columns: 1fr 1fr; gap:12px; margin-bottom:12px;">
                <div><div style="font-size:11px;color:rgba(255,255,255,0.6)">Warrant Code</div><div style="font-weight:700;">${warrantId}</div></div>
                <div><div style="font-size:11px;color:rgba(255,255,255,0.6)">Officer</div><div>${issuedBy||'Unknown'}</div></div>
                <div><div style="font-size:11px;color:rgba(255,255,255,0.6)">Date Filed</div><div>${formattedDate}</div></div>
                <div><div style="font-size:11px;color:rgba(255,255,255,0.6)">Suspect</div><div>${suspectName||'Unknown'}</div></div>
                <div><div style="font-size:11px;color:rgba(255,255,255,0.6)">Status</div><div><span class="status-badge ${statusClass}">${status||''}</span></div></div>
            </div>
            ${title ? `<div style="margin-bottom:8px;"><div style=\"font-size:11px;color:rgba(255,255,255,0.6)\">Title</div><div style=\"font-weight:700\">${title}</div></div>` : ''}
            <div style="margin-bottom:8px;"><div style="font-size:11px;color:rgba(255,255,255,0.6)">Description</div><div>${(desc||'').replace(/\n/g,'<br/>')}</div></div>
            <div style="margin-bottom:8px;"><div style="font-size:11px;color:rgba(255,255,255,0.6)">Charges</div><div style="display:flex;gap:6px;flex-wrap:wrap;">${charges.map(c=>`<span class=\"charge-chip\">${c}</span>`).join('') || 'None'}</div></div>
            <div style="margin-bottom:8px;"><div style="font-size:11px;color:rgba(255,255,255,0.6)">Officers</div><div style="display:flex;gap:6px;flex-wrap:wrap;">${officers.map(o=>`<span class=\"charge-chip\">${o}</span>`).join('') || 'None'}</div></div>
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

        const flags = flagsArr.map(f => `<span class="flag-chip">${f}</span>`).join('') || '<span class="flag-chip">None</span>';
        const notes = (data.notes || []).map(n => `<div class="note-row"><div>${n.text}</div><div style="font-size:11px;color:rgba(255,255,255,0.6)">${n.author||''} • ${n.createdAt||''}</div></div>`).join('') || '<div class="empty-message">No notes</div>';
        const strikes = strikesArr.map(s => `<div class="strike-row"><div>${s.reason||'Strike'}</div><div style="font-size:11px;color:rgba(255,255,255,0.6)">${s.createdAt||''}</div></div>`).join('') || '<div class="empty-message">No strikes</div>';

        const statusCard = flagsArr.length === 0
            ? `<div style="padding:12px;border-radius:8px;border:1px solid rgba(255,255,255,0.08);background:rgba(76,175,80,0.08);color:#a5d6a7;">This vehicle has no active alerts or flags.</div>`
            : `<div style="padding:12px;border-radius:8px;border:1px solid rgba(255,255,255,0.08);background:rgba(255,179,71,0.08);color:#ffb347;">This vehicle has active alerts or flags.</div>`;

        content.innerHTML = `
            <div data-view="v-overview">
                <div style="display:grid; grid-template-columns: 340px 1fr; gap:16px; align-items:start;">
                    <div style="padding:16px; border-radius:10px; border:1px solid rgba(255,255,255,0.08); background:rgba(255,255,255,0.03);">
                        <div style="display:flex; flex-direction:column; align-items:center; gap:10px;">
                            <div style="width:120px;height:120px;border-radius:999px;background:${data.vehiclePhoto ? `url('${data.vehiclePhoto}')` : 'rgba(255,255,255,0.06)'};background-size:cover;background-position:center;display:flex;align-items:center;justify-content:center;">
                                ${data.vehiclePhoto ? '' : '<svg width="60" height="60" viewBox="0 0 24 24" fill="none" stroke="#4dd0e1" stroke-width="2"><circle cx="18" cy="18" r="3"></circle><circle cx="6" cy="18" r="3"></circle><path d="M18 15h-12v-9h12z"></path></svg>'}
                            </div>
                            <button class="btn small" style="margin-top: 4px; width: 100%; font-size: 11px;" onclick="takeVehiclePhoto('${data.plate}')">📷 Take Photo</button>
                            <div style="font-size:22px;font-weight:700;">${data.plate||''}</div>
                            <div style="font-size:12px;color:rgba(255,255,255,0.7)">Owner: ${data.ownerName||''}</div>
                            <div style="font-size:12px;color:rgba(255,255,255,0.7)">Model: ${data.model||'Vehicle'}</div>
                            <div style="font-size:12px;color:rgba(255,255,255,0.7)">Color: ${data.color||'Unknown'}</div>
                            <div style="font-size:12px;color:rgba(255,255,255,0.7)">Last Seen: ${lastSeen}</div>
                        </div>
                    </div>
                    <div>
                        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px;">
                            <div>
                                <div style="font-size:24px;font-weight:700;">${data.plate||''}</div>
                                <div style="font-size:12px;color:rgba(255,255,255,0.7)">Owner: ${data.ownerName||''}</div>
                            </div>
                            <div style="display:flex; gap:8px; align-items:center;">
                                <span class="chip info">#${(data.plate||'').toString().slice(0,6)}</span>
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
                    <div style="font-size: 12px; color: rgba(255,255,255,0.6); margin-top: 4px;">Expires: ${formatDateTime(suspensionExpiry)}</div>
                </div>
            `;
            // Escape for JavaScript strings in onclick (not HTML entities)
            const escJs = (s) => String(s ?? '').replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\n/g, '\\n');
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
            const escJs = (s) => String(s ?? '').replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\n/g, '\\n');
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

        const escJs = (s) => String(s ?? '').replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\n/g, '\\n');

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
    const dateTimeInput = document.getElementById('incidentDateTimeInput');
    const officerInput = document.getElementById('incidentReportingOfficerInput');
    const locInput = document.getElementById('incidentLocationInput');
    
    if (titleInput) titleInput.value = '';
    
    // Initialize/reset RTE for description
    if (!window.__rteIncidentDescription) {
        window.__rteIncidentDescription = createRTE('incidentDescriptionInput', {
            placeholder: 'Detailed description of the incident...',
            minHeight: '100px',
            maxHeight: '40vh'
        });
    } else {
        window.__rteIncidentDescription.clear();
    }
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
    sendCallback('pf_mdt:searchEvidence', { query: '', page: 1, pageSize: 100, limit: 100 }, (response) => {
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
            <span onclick="removeIncidentInvolvedCitizen('${escapeHtml(c.id)}')" style="margin-left: 8px; cursor: pointer; opacity: 0.7;">✕</span>
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
            <span onclick="removeIncidentInvolvedOfficer('${escapeHtml(o.id)}')" style="margin-left: 8px; cursor: pointer; opacity: 0.7;">✕</span>
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
            <span onclick="removeIncidentInvolvedVictim('${escapeHtml(v.id)}')" style="margin-left: 8px; cursor: pointer; opacity: 0.7;">✕</span>
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
            <span onclick="removeIncidentVehicle('${escapeHtml(v.id)}')" style="margin-left: 8px; cursor: pointer; opacity: 0.7;">✕</span>
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
            <span onclick="removeIncidentCharge('${escapeHtml(c.code)}')" style="margin-left: 8px; cursor: pointer; opacity: 0.7;">✕</span>
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
            <span onclick="removeIncidentEvidence('${escapeHtml(e.id)}')" style="margin-left: 8px; cursor: pointer; opacity: 0.7;">✕</span>
        </div>
    `).join('');
    list.innerHTML = html || '<div style="color: rgba(255,255,255,0.5); font-size: 12px;">No evidence attached</div>';
}

function submitIncident() {
    const title = document.getElementById('incidentTitleInput')?.value?.trim() || '';
    // Get description from RTE if available, fallback to textarea value
    let descriptionHtml = '';
    let descriptionText = '';
    if (window.__rteIncidentDescription) {
        descriptionHtml = window.__rteIncidentDescription.getValue().trim();
        descriptionText = window.__rteIncidentDescription.getPlainText().trim();
    } else if (window.__mdtRTEManager) {
        const rte = window.__mdtRTEManager.get('incidentDescriptionInput');
        descriptionHtml = rte ? rte.getValue().trim() : '';
        descriptionText = rte ? rte.getPlainText().trim() : (document.getElementById('incidentDescriptionInput')?.textContent || '').trim();
    } else {
        descriptionText = document.getElementById('incidentDescriptionInput')?.value?.trim() || '';
    }
    const dateTime = document.getElementById('incidentDateTimeInput')?.value || '';
    const reportingOfficer = document.getElementById('incidentReportingOfficerInput')?.value?.trim() || '';
    const location = document.getElementById('incidentLocationInput')?.value?.trim() || '';
    
    if (!title || !descriptionText) {
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
    
    console.log('[INCIDENTS] Submitting:', { title, description: descriptionText, dateTime, reportingOfficer, location, citizenIds, victimIds, officerIds, vehicleIds, charges, evidenceIds });
    
    sendCallback('createIncident', {
        title,
        description: descriptionHtml || descriptionText,
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
    const dateInput = document.getElementById('reportDateInput');
    const typeSelect = document.getElementById('reportTypeSelect');
    const catInput = document.getElementById('reportCategoryInput');
    
    if (titleInput) titleInput.value = '';
    if (dateInput) dateInput.value = new Date().toISOString().split('T')[0];
    if (typeSelect) typeSelect.value = '';
    if (catInput) catInput.value = '';

    if (!window.__rteReportDescription) {
        window.__rteReportDescription = createRTE('reportDescriptionInput', {
            placeholder: 'Detailed description of the report...',
            minHeight: '100px',
            maxHeight: '40vh'
        });
    } else {
        window.__rteReportDescription.clear();
    }
    
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
            <div class="modal-card" style="width: 920px; max-height: 90vh; overflow-y: auto;">
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
                            <div id="reportDescriptionInput" style="margin-top: 6px;"></div>
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

    const escJs = (s) => String(s ?? '').replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\n/g, ' ');
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

    const escJs = (s) => String(s ?? '').replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\n/g, ' ');
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
    const descriptionHtml = window.__rteReportDescription ? window.__rteReportDescription.getValue().trim() : '';
    const descriptionText = window.__rteReportDescription ? window.__rteReportDescription.getPlainText().trim() : (document.getElementById('reportDescriptionInput')?.textContent || '').trim();
    const date = document.getElementById('reportDateInput')?.value || '';
    const reportType = document.getElementById('reportTypeSelect')?.value || '';
    const category = document.getElementById('reportCategoryInput')?.value?.trim() || '';
    
    if (!title || !descriptionText || !reportType) {
        console.log('[REPORTS] Missing required fields');
        return;
    }
    
    const involved = Array.isArray(window.__selectedReportInvolved) ? window.__selectedReportInvolved : [];
    const officers = Array.isArray(window.__selectedReportOfficers) ? window.__selectedReportOfficers : [];
    const photos = Array.isArray(window.__selectedReportPhotos) ? window.__selectedReportPhotos : [];
    const linkedCitizens = involved
        .map(p => ({ citizenid: String(p?.citizenid || ''), name: String(p?.name || '').trim() }))
        .filter(p => p.citizenid);
    
    console.log('[REPORTS] Submitting:', { title, description: descriptionText, date, reportType, category, involved, officers, photos });
    
    sendCallback('createReport', {
        title,
        narrative: descriptionHtml || descriptionText,
        content: descriptionHtml || descriptionText,
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
            if (!url) return '';
            return `
                <div class="evidence-item" style="display:inline-block;margin:6px;">
                    <img src="${escapeHtml(url)}" alt="Evidence" style="width:140px;height:100px;object-fit:cover;border-radius:8px;cursor:pointer;border:1px solid rgba(255,255,255,0.15)" onclick="showImageLightbox('${String(url).replace(/'/g, "\\'")}')" />
                    ${title ? `<div class="muted" style="font-size:12px;margin-top:4px;">${escapeHtml(title)}</div>` : ''}
                </div>
            `;
        }).join('') : '<div class="empty-message">No photos</div>';

        const html = `
            <div class="modal" id="reportDetailsModal">
                <div class="modal-card" style="width: 920px; max-height: 80vh; overflow-y: auto;">
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
                            <div class="rte-view">${renderRteContent(r.narrative || r.content || '')}</div>
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
                    <img src="${escapeHtml(url)}" alt="Photo" style="max-width: 100%; max-height: 70vh; width: auto; height: auto; object-fit: contain; border-radius: 8px; background: rgba(0,0,0,0.3);" />
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
        sendCallback('pf_mdt:searchEvidence', {
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
            const statusBadge = ev.status ? `<span class="evidence-status status-${ev.status.toLowerCase()}">${ev.status.toUpperCase()}</span>` : '';
            return `
                <div class="evidence-card">
                    <div class="evidence-image" 
                         style="background-image: url('${escapeHtml(ev.image_url)}'); background-size: cover; background-position: center; height: 160px; border-radius: 8px 8px 0 0; cursor: pointer; position: relative;">
                        ${statusBadge}
                    </div>
                    <div style="padding: 12px; display: flex; flex-direction: column; gap: 8px;">
                        <div>
                            <div class="evidence-id" style="font-size: 12px; color: rgba(255,255,255,0.7); margin-bottom: 4px;">Evidence #${ev.evidence_number}</div>
                            <div class="evidence-title" style="font-size: 14px; font-weight: 600; margin-bottom: 8px; line-height: 1.3;">${escapeHtml(ev.title)}</div>
                            <div class="evidence-meta" style="font-size: 11px; color: rgba(255,255,255,0.5);">
                                <div>👮 ${escapeHtml(ev.created_by_name || 'Unknown')}</div>
                                <div>📅 ${formatDateTime(ev.created_at)}</div>
                            </div>
                        </div>
                        <button class="incident-details-btn" onclick="openEvidenceDetails('${ev.evidence_number}'); return false;">VIEW DETAILS</button>
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
                            <h2>Evidence #${String(ev.evidence_number)}</h2>
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
                    <div style="font-weight: 600; font-size: 16px;">Evidence #${ev.evidence_number}</div>
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
                        <div>${formatDateTime(ev.created_at)}</div>
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
                    <div id="evidenceDescEdit" style="margin-top: 6px;"></div>
                </div>
                
                <!-- Evidence Media -->
                <div style="margin-bottom: 16px;">
                    <div style="font-size: 12px; color: rgba(255,255,255,0.6); margin-bottom: 8px; text-transform: uppercase;">Evidence Media</div>
                    <img src="${escapeHtml(ev.image_url)}" onclick="if(window.enlargeImage){window.enlargeImage('${escapeHtml(ev.image_url)}')}" style="width: 100%; max-height: 400px; object-fit: contain; border-radius: 8px; cursor: pointer; background: rgba(0,0,0,0.3);" />
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
                        ${ev.tags.split(',').map(tag => `<span style="padding: 4px 10px; border-radius: 4px; background: rgba(100,116,139,0.3); font-size: 11px;">${escapeHtml(tag.trim())}</span>`).join('')}
                    </div>
                </div>
                ` : ''}
                
                <!-- Chain of Custody -->
                <div style="margin-bottom: 16px; padding: 12px; background: rgba(0,0,0,0.2); border-radius: 8px; border: 1px solid rgba(255,255,255,0.1);">
                    <div style="font-size: 12px; color: rgba(255,255,255,0.6); margin-bottom: 8px; text-transform: uppercase;">🔒 Chain of Custody</div>
                    <div style="font-size: 12px; color: rgba(255,255,255,0.8);">
                        <div>Added by: ${escapeHtml(ev.collected_by)}</div>
                        <div>Created: ${formatDateTime(ev.created_at)}</div>
                        ${ev.modified_at ? `<div>Last Modified: ${formatDateTime(ev.modified_at)}</div>` : ''}
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

    if (typeof createRTE === 'function') {
        window.__rteEvidenceDescEdit = createRTE('evidenceDescEdit', {
            placeholder: 'Detailed description of the evidence...',
            initialContent: renderRteContent(String(ev.description || '')),
            minHeight: '120px',
            maxHeight: '40vh',
            readonly: !canEdit,
            showToolbar: !!canEdit
        });
    }
    
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
                    description: (window.__rteEvidenceDescEdit ? window.__rteEvidenceDescEdit.getValue() : document.getElementById('evidenceDescEdit')?.textContent || '').trim(),
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
            <div class="modal-card" style="width: 920px; max-height: 90vh; overflow-y: auto; pointer-events: auto;">
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
                            <div id="evidenceDescriptionInput" style="margin-top: 6px;"></div>
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
                            <div id="evidenceWeaponDescInput" style="margin-top: 6px;"></div>
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

    if (!window.__rteEvidenceDescription) {
        window.__rteEvidenceDescription = createRTE('evidenceDescriptionInput', {
            placeholder: 'Detailed description of the evidence...',
            minHeight: '100px',
            maxHeight: '40vh'
        });
    } else {
        window.__rteEvidenceDescription.clear();
    }

    if (!window.__rteEvidenceWeaponDesc) {
        window.__rteEvidenceWeaponDesc = createRTE('evidenceWeaponDescInput', {
            placeholder: "Describe non-registered weapons (e.g. 'black pistol w/ filed serial', 'kitchen knife')...",
            minHeight: '80px',
            maxHeight: '30vh'
        });
    } else {
        window.__rteEvidenceWeaponDesc.clear();
    }
    
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
    sendCallback('pf_mdt:getAllIncidents', {}, (res) => {
        allIncidents = Array.isArray(res) ? res : [];
        const select = document.getElementById('evidenceIncidentInput');
        if (select) {
            select.innerHTML = '<option value="">No Incident</option>' + 
                allIncidents.map(i => `<option value="${escapeHtml(i.incidentId)}">${escapeHtml(i.incidentId)} - ${escapeHtml(i.title)}</option>`).join('');
        }
    });
    
    sendCallback('pf_mdt:getAllCitizens', {}, (res) => {
        allCitizens = Array.isArray(res) ? res : [];
    });
    
    sendCallback('pf_mdt:getAllVehicles', {}, (res) => {
        allVehicles = Array.isArray(res) ? res : [];
    });
    
    sendCallback('pf_mdt:getAllCharges', {}, (res) => {
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
        const description = window.__rteEvidenceDescription ? window.__rteEvidenceDescription.getPlainText().trim() : (document.getElementById('evidenceDescriptionInput')?.textContent || '').trim();
        const btn = document.getElementById('evidenceCreateBtn');
        if (btn) {
            btn.disabled = !(title && description && capturedImageUrl);
        }
    }

    if (window.__rteEvidenceDescription && window.__rteEvidenceDescription.editor) {
        window.__rteEvidenceDescription.editor.addEventListener('input', checkFormValidity);
    }
    
    document.getElementById('evidenceTitleInput')?.addEventListener('input', checkFormValidity);
    document.getElementById('evidenceDescriptionInput')?.addEventListener('input', checkFormValidity);
    
    // Create button handler
    document.getElementById('evidenceCreateBtn')?.addEventListener('click', () => {
        const title = document.getElementById('evidenceTitleInput')?.value?.trim();
        const descriptionHtml = window.__rteEvidenceDescription ? window.__rteEvidenceDescription.getValue().trim() : '';
        const descriptionText = window.__rteEvidenceDescription ? window.__rteEvidenceDescription.getPlainText().trim() : (document.getElementById('evidenceDescriptionInput')?.textContent || '').trim();
        const incidentId = document.getElementById('evidenceIncidentInput')?.value?.trim() || null;
        const tags = document.getElementById('evidenceTagsInput')?.value?.trim() || '';
        const locationDetails = document.getElementById('evidenceLocationInput')?.value?.trim() || '';
        const status = document.getElementById('evidenceStatusInput')?.value || 'Collected';
        const weaponDesc = window.__rteEvidenceWeaponDesc ? window.__rteEvidenceWeaponDesc.getPlainText().trim() : (document.getElementById('evidenceWeaponDescInput')?.textContent || '').trim();
        
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
        
        if (!title || !descriptionText) {
            if (typeof mdtToast === 'function') mdtToast('Title and Description are required', 'error');
            return;
        }
        
        if (!capturedImageUrl) {
            if (typeof mdtToast === 'function') mdtToast('Photo is required', 'error');
            return;
        }
        
        // Non-registered notes are optional; registered selection is optional.
        
        sendCallback('pf_mdt:createEvidence', {
            title,
            description: descriptionHtml || descriptionText,
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

// ============================================================================
// Templates
// ============================================================================

class TemplatesPage extends BasePage {
    constructor() {
        super('templates', 'Templates');
        this.templates = [];
    }

    mount(root) {
        super.mount(root);
        root.innerHTML = `
            <div class="search-page-container">
                <div class="search-page-header">
                    <div class="search-page-title-group">
                        <h2>Templates</h2>
                        <div class="search-page-subtitle">Reusable report/incident templates</div>
                    </div>
                    <button class="page-action-btn" id="templateCreateBtn">+ Create Template</button>
                </div>
                <div id="templatesGrid" class="results-grid"></div>
            </div>
        `;

        document.getElementById('templateCreateBtn')?.addEventListener('click', () => {
            openTemplateEditor();
        });

        this.loadTemplates();
    }

    loadTemplates() {
        if (window.__mdtTemplateStore && window.__mdtTemplateStore.refresh) {
            window.__mdtTemplateStore.refresh((list) => {
                this.templates = list || [];
                this.renderTemplates();
            });
        }
    }

    renderTemplates() {
        const grid = document.getElementById('templatesGrid');
        if (!grid) return;
        const list = this.templates || [];
        if (list.length === 0) {
            grid.innerHTML = '<div class="empty-message" style="grid-column: 1/-1;">No templates available</div>';
            return;
        }
        const myCid = window.userInfo?.citizenid || window.userInfo?.citizenId || '';
        grid.innerHTML = list.map(t => {
            const canEdit = String(t.author_cid || '') === String(myCid || '');
            return `
                <div class="report-card">
                    <div class="report-type-badge">${escapeHtml(String(t.visibility || 'private').toUpperCase())}</div>
                    <div class="report-title">${escapeHtml(t.title || 'Template')}</div>
                    <div class="report-meta">
                        <div>Author: ${escapeHtml(t.author_name || 'Officer')}</div>
                        <div>Updated: ${escapeHtml(String(t.updated_at || ''))}</div>
                    </div>
                    <div class="report-actions" style="margin-top:8px; display:flex; gap:8px; flex-wrap:wrap;">
                        <button class="modal-btn" onclick='openTemplateViewerById(${Number(t.id)})'>View</button>
                        ${canEdit ? `<button class="modal-btn" onclick='openTemplateEditorById(${Number(t.id)})'>Edit</button>` : ''}
                        ${canEdit ? `<button class="modal-btn" onclick='deleteTemplate(${Number(t.id)})'>Delete</button>` : ''}
                    </div>
                </div>
            `;
        }).join('');
    }
}

window.TemplatesPage = TemplatesPage;

window.__mdtTemplateStore = {
    templates: [],
    refresh: function(cb) {
        sendCallback('getTemplates', {}, (res) => {
            const list = res && res.templates ? res.templates : (Array.isArray(res) ? res : []);
            this.templates = list || [];
            if (typeof cb === 'function') cb(this.templates);
        });
    },
    getTemplates: function() {
        return this.templates || [];
    }
};

function findTemplateById(id) {
    const list = window.__mdtTemplateStore?.getTemplates?.() || [];
    return list.find(t => String(t.id) === String(id));
}

function openTemplateViewerById(id) {
    const tpl = findTemplateById(id);
    if (!tpl) return;
    openTemplateViewer(tpl);
}

function openTemplateEditorById(id) {
    const tpl = findTemplateById(id);
    if (!tpl) return;
    openTemplateEditor(tpl);
}

function openTemplateViewer(tpl) {
    if (!tpl) return;
    const html = `
        <div class="modal" id="templateViewModal">
            <div class="modal-card" style="width: 920px; max-height: 85vh; overflow-y: auto;">
                <div class="modal-header" style="display:flex;justify-content:space-between;align-items:center;">
                    <h3>Template: ${escapeHtml(tpl.title || 'Template')}</h3>
                    <button class="modal-btn" onclick="closeTemplateModal('templateViewModal')">Close</button>
                </div>
                <div class="modal-body">
                    <div class="rte-view">${renderRteContent(tpl.body_html || tpl.body || '')}</div>
                </div>
            </div>
        </div>
    `;
    document.getElementById('templateViewModal')?.remove();
    document.body.insertAdjacentHTML('beforeend', html);
}

function openTemplateEditor(tpl) {
    const isEdit = !!tpl;
    const html = `
        <div class="modal" id="templateEditModal">
            <div class="modal-card" style="width: 920px; max-height: 85vh; overflow-y: auto;">
                <div class="modal-header" style="display:flex;justify-content:space-between;align-items:center;">
                    <h3>${isEdit ? 'Edit' : 'Create'} Template</h3>
                    <button class="modal-btn" onclick="closeTemplateModal('templateEditModal')">Close</button>
                </div>
                <div class="modal-body">
                    <div class="form-section">
                        <label class="form-row">
                            <span>Title</span>
                            <input id="templateTitleInput" type="text" placeholder="Template title..." value="${escapeHtml(tpl?.title || '')}" />
                        </label>
                    </div>
                    <div class="form-section">
                        <label class="form-row">
                            <span>Visibility</span>
                            <select id="templateVisibilitySelect">
                                <option value="private">Private (only you)</option>
                                <option value="public">Public (all officers)</option>
                                <option value="grades">Grades (select ranks)</option>
                                <option value="officers">Officers (select individuals)</option>
                            </select>
                        </label>
                    </div>
                    <div class="form-section" id="templateGradesSection" style="display:none;">
                        <div class="muted" style="font-size:12px; margin-bottom:6px;">Allowed Grades</div>
                        <div id="templateGradesList" style="display:flex; flex-wrap:wrap; gap:8px;"></div>
                    </div>
                    <div class="form-section" id="templateOfficersSection" style="display:none;">
                        <div class="muted" style="font-size:12px; margin-bottom:6px;">Allowed Officers</div>
                        <div id="templateOfficersList" style="display:flex; flex-wrap:wrap; gap:8px; max-height:200px; overflow-y:auto;"></div>
                    </div>
                    <div class="form-section">
                        <label class="form-row">
                            <span>Template Body</span>
                            <div id="templateBodyInput" style="margin-top: 6px;"></div>
                        </label>
                    </div>
                </div>
                <div class="modal-footer">
                    <button class="modal-btn" id="templateSaveBtn">${isEdit ? 'Update' : 'Create'} Template</button>
                </div>
            </div>
        </div>
    `;
    document.getElementById('templateEditModal')?.remove();
    document.body.insertAdjacentHTML('beforeend', html);

    const visSelect = document.getElementById('templateVisibilitySelect');
    if (visSelect) visSelect.value = tpl?.visibility || 'private';

    const rte = createRTE('templateBodyInput', {
        placeholder: 'Template content...',
        initialContent: tpl?.body_html || '' ,
        minHeight: '160px',
        maxHeight: '50vh'
    });

    const gradeSection = document.getElementById('templateGradesSection');
    const officerSection = document.getElementById('templateOfficersSection');

    const updateVisibility = () => {
        const v = visSelect?.value || 'private';
        if (gradeSection) gradeSection.style.display = v === 'grades' ? '' : 'none';
        if (officerSection) officerSection.style.display = v === 'officers' ? '' : 'none';
    };
    updateVisibility();
    visSelect?.addEventListener('change', updateVisibility);

    const gradesList = document.getElementById('templateGradesList');
    const allowedGrades = Array.isArray(tpl?.allowed_grades) ? tpl.allowed_grades : [];
    if (gradesList) {
        gradesList.innerHTML = Array.from({length: 11}).map((_,i) => {
            const checked = allowedGrades.includes(i) ? 'checked' : '';
            return `<label class="chip" style="background: rgba(100,200,255,0.2); border:1px solid rgba(100,200,255,0.4); padding:4px 8px; border-radius:12px;">
                <input type="checkbox" value="${i}" ${checked} /> Grade ${i}
            </label>`;
        }).join('');
    }

    const officersList = document.getElementById('templateOfficersList');
    const allowedOfficers = Array.isArray(tpl?.allowed_officers) ? tpl.allowed_officers : [];
    sendCallback('getPoliceOfficers', {}, (list) => {
        if (!officersList) return;
        const rows = Array.isArray(list) ? list : [];
        officersList.innerHTML = rows.map(o => {
            const cid = o.citizenid || o.citizenId || '';
            const checked = allowedOfficers.includes(cid) ? 'checked' : '';
            return `<label class="chip" style="background: rgba(255,255,255,0.08); border:1px solid rgba(255,255,255,0.12); padding:4px 8px; border-radius:12px;">
                <input type="checkbox" value="${escapeHtml(String(cid))}" ${checked} /> ${escapeHtml(o.name || 'Officer')} ${o.callsign ? '(' + escapeHtml(o.callsign) + ')' : ''}
            </label>`;
        }).join('');
    });

    document.getElementById('templateSaveBtn')?.addEventListener('click', () => {
        const title = document.getElementById('templateTitleInput')?.value?.trim() || '';
        const visibility = visSelect?.value || 'private';
        const bodyHtml = rte ? rte.getValue().trim() : '';
        if (!title || !bodyHtml) return;

        const selectedGrades = Array.from(document.querySelectorAll('#templateGradesList input[type="checkbox"]:checked')).map(i => Number(i.value));
        const selectedOfficers = Array.from(document.querySelectorAll('#templateOfficersList input[type="checkbox"]:checked')).map(i => String(i.value));

        const payload = {
            id: tpl?.id,
            title,
            body_html: bodyHtml,
            visibility,
            allowed_grades: selectedGrades,
            allowed_officers: selectedOfficers
        };

        const cbName = isEdit ? 'updateTemplate' : 'createTemplate';
        sendCallback(cbName, payload, (res) => {
            if (res && res.success) {
                closeTemplateModal('templateEditModal');
                window.__mdtTemplateStore?.refresh?.();
                const page = window.router?.pages?.get('templates');
                page?.loadTemplates?.();
            }
        });
    });
}

function deleteTemplate(id) {
    if (!id) return;
    sendCallback('deleteTemplate', { id }, (res) => {
        if (res && res.success) {
            window.__mdtTemplateStore?.refresh?.();
            const page = window.router?.pages?.get('templates');
            page?.loadTemplates?.();
        }
    });
}

function closeTemplateModal(id) {
    document.getElementById(id)?.remove();
}

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

// Expose Evidence Page
window.EvidencePage = EvidencePage;

// Register Evidence Page if router exists
function registerEvidencePage() {
    const r = window.router;
    if (!r || !r.register) return;
    
    const existing = r.pages.get('evidence');
    if (!(existing instanceof EvidencePage)) {
        try {
            r.register('evidence', new EvidencePage(), 'Evidence');
        } catch (_) {}
    }
}

// Auto-register on DOM ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', registerEvidencePage);
} else {
    registerEvidencePage();
}

// Report Photos helpers
function renderReportPhotos() {
    const grid = document.getElementById('reportPhotosGrid');
    if (!grid) return;
    const photos = Array.isArray(window.__selectedReportPhotos) ? window.__selectedReportPhotos : [];
    if (!photos.length) {
        grid.innerHTML = '<div class="empty-message" style="grid-column:1/-1;">No photos</div>';
        return;
    }
    const escJs = (s) => String(s ?? '').replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\n/g, ' ');
    grid.innerHTML = photos.map((p, i) => {
        const url = String(p?.url || '');
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