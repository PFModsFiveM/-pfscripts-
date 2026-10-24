// pf-jobgarages NUI script

const RESOURCE_NAME = typeof GetParentResourceName === 'function'
  ? GetParentResourceName()
  : 'pf-jobgarages';

// -----------------------------------------------------
// Utilities
// -----------------------------------------------------

function $(sel) {
    return document.querySelector(sel);
}

function $all(sel) {
    return Array.from(document.querySelectorAll(sel));
}

function playSound(id) {
    try {
        const el = document.getElementById(id);
        if (!el) return;
        el.currentTime = 0;
        el.play().catch(() => {});
    } catch (e) {
        // ignore audio errors
    }
}

function escapeHtml(str) {
    if (str === null || str === undefined) return '';
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}

// Simple global toast helper
function showToast(msg, ms = 2000) {
    const t = document.getElementById('toast');
    if (!t) return;
    t.textContent = msg || '';
    t.classList.remove('hidden');
    setTimeout(() => { t.classList.add('hidden'); }, ms);
}

// Image helpers: try multiple extensions, then fallback
function buildVehicleImageCandidates(model) {
    const m = (model || 'unknown').toLowerCase();
    return [
        `images/vehicles/${m}.webp`,
        `images/vehicles/${m}.png`,
        `images/vehicles/${m}.jpg`,
        `images/vehicles/${m}.jpeg`
    ];
}

function swapImgOnError(imgEl) {
    try {
        const fallbackImg = 'images/no-image.webp';
        const listJson = imgEl.getAttribute('data-img-list');
        let idx = parseInt(imgEl.getAttribute('data-img-idx')) || 0;
        const list = listJson ? JSON.parse(listJson) : [];
        idx += 1;
        if (Array.isArray(list) && idx < list.length) {
            imgEl.setAttribute('data-img-idx', String(idx));
            imgEl.src = list[idx];
        } else {
            imgEl.onerror = null;
            imgEl.src = fallbackImg;
        }
    } catch (e) {
        imgEl.onerror = null;
        imgEl.src = 'images/no-image.webp';
    }
}

function formatSince(value) {
    if (!value) return 'Unknown';

    let date;
    if (typeof value === 'number') {
        const ms = value > 1e12 ? value : value * 1000;
        date = new Date(ms);
    } else {
        date = new Date(value);
    }
    if (isNaN(date.getTime())) return String(value);

    const now = new Date();
    const diffMs = now - date;
    const diffSec = Math.floor(diffMs / 1000);
    const diffMin = Math.floor(diffSec / 60);
    const diffHr  = Math.floor(diffMin / 60);
    const diffDay = Math.floor(diffHr / 24);

    if (diffSec < 60) return 'Just now';
    if (diffMin < 60) return `${diffMin} min ago`;
    if (diffHr  < 24) return `${diffHr} h ago`;
    if (diffDay < 7)  return `${diffDay} d ago`;

    return date.toLocaleString();
}

function parseDateOrNull(val) {
    if (!val) return null;
    const d = new Date(val);
    if (isNaN(d.getTime())) return null;
    return d;
}

// Very simple model → category mapping (used only for sort order)
function getVehicleCategory(model) {
    if (!model) return 'Other';
    model = model.toLowerCase();

    const sports = ['t20', 'adder', 'comet', 'elegy', 'ninef', 'jester', 'pariah', 'italgto', 'zentorno'];
    const muscle = ['dominator', 'dominator7', 'gauntlet', 'gauntlet2', 'dukes', 'sabregt'];
    const utility = ['towtruck', 'towtruck2', 'flatbed', 'utillitruck', 'utillitruck2', 'bison', 'bison2'];

    if (sports.some(m => model.startsWith(m))) return 'Sports';
    if (muscle.some(m => model.startsWith(m))) return 'Muscle';
    if (utility.some(m => model.startsWith(m))) return 'Utility';
    return 'Other';
}

// -----------------------------------------------------
// State
// -----------------------------------------------------

let nuiOpen = false;
let currentGarageId = null;
let ownedVehiclesCache = [];

let garageState = {
    label: '',
    playerGrade: 0,
    isManager: false,
    playerCid: null,
    fleet: [],
    outVehicles: [],
    permissions: null,
    logs: [],
    sortMode: 'default',   // 'default', 'recent', 'alpha'
    showMineOnly: false    // "My Assigned Vehicles Only"
};

// -----------------------------------------------------
// NUI show/hide
// -----------------------------------------------------

function showApp() {
    nuiOpen = true;
    const app = $('#app');
    if (app) {
        app.classList.remove('hidden');
        app.style.display = 'flex';
    }
}

function hideApp() {
    nuiOpen = false;
    currentGarageId = null;
    const app = $('#app');
    if (app) {
        app.classList.add('hidden');
        app.style.display = 'none';
    }
}

// -----------------------------------------------------
// Modal confirm helper (avoids window.confirm focus bugs)
// -----------------------------------------------------
function confirmModal(message, onOk) {
    const modal = document.getElementById('modal');
    const msgEl = document.getElementById('modal-message');
    const okBtn = document.getElementById('modal-ok');
    const cancelBtn = document.getElementById('modal-cancel');
    if (!modal || !msgEl || !okBtn || !cancelBtn) return;

    msgEl.textContent = message || 'Are you sure?';
    modal.classList.remove('hidden');

    const cleanup = () => {
        modal.classList.add('hidden');
        okBtn.onclick = null;
        cancelBtn.onclick = null;
    };

    cancelBtn.onclick = cleanup;
    okBtn.onclick = () => {
        try { if (typeof onOk === 'function') onOk(); } catch (e) {}
        cleanup();
    };
}

// -----------------------------------------------------
// Message handler from Lua
// -----------------------------------------------------

window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data || !data.action) return;

    switch (data.action) {
        case 'open':
            handleOpen(data.data);
            break;
        case 'update':
            handleUpdate(data.data);
            break;
        case 'close':
            hideApp();
            break;
        case 'stored':
            // vehicle successfully stored – play soft success sound
            playSound('snd-store');
            break;
    }
});

// -----------------------------------------------------
// Header / tabs
// -----------------------------------------------------

function updateHeader() {
    const titleEl = $('#garageTitle');
    if (titleEl) titleEl.textContent = garageState.label || 'Job Garage';

    const gradeEl = $('#playerGradeLabel');
    if (gradeEl) gradeEl.textContent = `Grade ${garageState.playerGrade || 0}`;
}

function setActiveTab(tabKey) {
    const tabMap = {
        garage: 'tab-garage',
        manage: 'tab-manage',
        permissions: 'tab-permissions',
        assignments: 'tab-assignments',
        out: 'tab-out',
        logs: 'tab-logs',
    };

    const targetId = tabMap[tabKey] || 'tab-garage';

    // Switch visible page
    $all('.tab').forEach(p => p.classList.remove('active'));
    const page = document.getElementById(targetId);
    if (page) page.classList.add('active');

    // Highlight active sidebar button
    $all('.nav-btn').forEach(btn => {
        const t = btn.dataset.tab;
        if (t === tabKey) btn.classList.add('active');
        else btn.classList.remove('active');
    });
}

// -----------------------------------------------------
// OPEN / UPDATE handlers
// -----------------------------------------------------

function handleOpen(data) {
    // Ignore bogus / empty open calls
    if (
        !data ||
        (!data.garageId && !data.garage_id && !data.id)
    ) {
        return;
    }

    currentGarageId = data.garageId || data.garage_id || data.id || currentGarageId;
        function showToast(msg, ms = 2000) {
            const t = document.getElementById('toast');
            if (!t) return;
            t.textContent = msg || '';
            t.classList.remove('hidden');
            setTimeout(() => { t.classList.add('hidden'); }, ms);
        }
    garageState.label       = data.garageLabel || data.label || 'Job Garage';
    garageState.playerGrade = data.jobGrade || data.playerGrade || 0;
    garageState.isManager   = !!data.isManager;
    garageState.playerCid   = data.playerCid || null;
    garageState.fleet       = data.fleet || [];
    garageState.outVehicles = data.outVehicles || [];
    garageState.permissions = data.permissions || null;
    garageState.logs        = data.logs || [];
    garageState.themeColor  = data.themeColor || '#53a2ff';

    // default tab: main garage
    setActiveTab('garage');

    // Apply theme color to CSS variable
    try {
        document.documentElement.style.setProperty('--accent-color', garageState.themeColor);
    } catch (e) {}

    updateHeader();
    renderFleet();
    renderManageList();
    renderOwnedVehicles(ownedVehiclesCache || []);
    renderPermissions();
    renderAssignments();
    renderOutList();
    renderLogs();

    // Only show UI after state is valid
    showApp();

    // Auto-load owned vehicles the first time the UI opens
    try { loadOwnedVehicles(); } catch (e) {}
}

function handleUpdate(data) {
    if (!data) return;

    garageState.fleet       = data.fleet       || garageState.fleet;
    garageState.outVehicles = data.outVehicles || garageState.outVehicles;
    garageState.permissions = data.permissions || garageState.permissions;
    garageState.logs        = data.logs        || garageState.logs;

    renderFleet();
    renderManageList();
    renderAssignments();
    renderOutList();
    renderLogs();
}

function renderFleet() {
    const container = $('#fleetList');
    if (!container) return;
    container.innerHTML = '';

    let fleet = Array.isArray(garageState.fleet) ? garageState.fleet : [];
    if (!fleet.length) {
        container.innerHTML = '<p>No vehicles in this garage.</p>';
        return;
    }

    const playerCid = garageState.playerCid;

    // Filter: My Assigned Vehicles Only (strict filter)
    if (garageState.showMineOnly && playerCid) {
        fleet = fleet.filter(v =>
            v.assignment_type === 'citizenid' &&
            v.assigned_citizenid &&
            v.assigned_citizenid === playerCid
        );
        if (!fleet.length) {
            container.innerHTML = '<p>You have no vehicles assigned to you in this garage.</p>';
            return;
        }
    }

    const mode = garageState.sortMode || 'default';
    const sorted = [...fleet];

    // Normal sort modes (recent / alpha / category)
    if (mode === 'recent') {
        sorted.sort((a, b) => {
            const da = parseDateOrNull(a.last_used_at) || parseDateOrNull(a.out_since) || new Date(0);
            const db = parseDateOrNull(b.last_used_at) || parseDateOrNull(b.out_since) || new Date(0);
            return db - da;
        });
    } else if (mode === 'alpha') {
        sorted.sort((a, b) => {
            const la = (a.label || a.model || '').toLowerCase();
            const lb = (b.label || b.model || '').toLowerCase();
            if (la < lb) return -1;
            if (la > lb) return 1;
            return 0;
        });
    } else {
        sorted.sort((a, b) => {
            const ca = getVehicleCategory(a.model || '').toLowerCase();
            const cb = getVehicleCategory(b.model || '').toLowerCase();
            if (ca < cb) return -1;
            if (ca > cb) return 1;

            const la = (a.label || a.model || '').toLowerCase();
            const lb = (b.label || b.model || '').toLowerCase();
            if (la < lb) return -1;
            if (la > lb) return 1;
            return 0;
        });
    }

    // Extra: when NOT filtering "mine only", float "Assigned to You" to the top
    if (!garageState.showMineOnly && playerCid) {
        sorted.sort((a, b) => {
            const aMine = (a.assignment_type === 'citizenid' &&
                           a.assigned_citizenid === playerCid) ? 1 : 0;
            const bMine = (b.assignment_type === 'citizenid' &&
                           b.assigned_citizenid === playerCid) ? 1 : 0;
            if (aMine > bMine) return -1;
            if (aMine < bMine) return 1;
            return 0;
        });
    }

    container.innerHTML = '';

    sorted.forEach(v => {
        const label = v.label || v.model || 'Unknown';
        const plate = v.plate || '';
        const model = v.model || 'unknown';
        const imgCandidates = buildVehicleImageCandidates(model);
        const firstImg = imgCandidates[0];

        const minGrade = (v.min_grade !== undefined && v.min_grade !== null)
            ? v.min_grade
            : (v.min_grade_use || 0);

        const isMine =
            v.assignment_type === 'citizenid' &&
            v.assigned_citizenid &&
            playerCid &&
            v.assigned_citizenid === playerCid;

        const assignmentType = v.assignment_type || 'none';

        // When grade assignment exists, prefer that for the text
        const gradeNum = (v.assigned_grade !== undefined && v.assigned_grade !== null)
            ? v.assigned_grade
            : minGrade || 0;

        // Build the main assignment pill (Style B, strong bar)
        let assignmentPillHtml = '';
        if (isMine) {
            assignmentPillHtml =
                '<span class="pill pill-mine">Assigned to You</span>';
        } else if (assignmentType === 'citizenid') {
            const name = v.assigned_name || 'Assigned Vehicle';
            assignmentPillHtml =
                `<span class="pill pill-assigned">Assigned: ${escapeHtml(name)}</span>`;
        } else if (assignmentType === 'grade') {
            assignmentPillHtml =
                `<span class="pill pill-grade">Reserved: Grade ${gradeNum}+ </span>`;
        } else {
            assignmentPillHtml =
                '<span class="pill pill-open">Open to All</span>';
        }

        // Optional "recent use" info
        const sinceDate = parseDateOrNull(v.last_used_at) || parseDateOrNull(v.out_since);
        const recentText = sinceDate ? formatSince(sinceDate.toISOString()) : '';
        const recentTag = recentText
            ? `<span class="pill pill-small">${escapeHtml(recentText)}</span>`
            : '';

        const card = document.createElement('div');
        card.className = 'vehicle-card';

        card.innerHTML = `
            <div class="vehicle-assignment-bar">
                ${assignmentPillHtml}
                ${recentTag}
            </div>

            <div class="vehicle-thumb">
                <img src="${firstImg}" alt="${escapeHtml(model)}" data-img-list='${JSON.stringify(imgCandidates)}' data-img-idx="0"
                     onerror="swapImgOnError(this)">
            </div>

            <div class="vehicle-info">
                <div class="vehicle-label">${escapeHtml(label)}</div>
                <div class="vehicle-plate">${escapeHtml(plate)}</div>
            </div>

            <div class="vehicle-badges">
                <span class="badge badge-model">${escapeHtml(model)}</span>
                <span class="badge badge-grade">Grade ${gradeNum || 0}+</span>
            </div>

            <div class="vehicle-actions">
                <button class="btn-blue take-btn">Take</button>
            </div>
        `;

        const btn = card.querySelector('.take-btn');
        if (btn) {
            btn.addEventListener('click', () => {
                // tiny confirm sound
                playSound('snd-take');
                takeVehicle(v.id);
            });
        }

        container.appendChild(card);
    });
}

function takeVehicle(id) {
    fetch(`https://pf-jobgarages/takeVehicle`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id: id, garageId: currentGarageId })
    }).catch(e => console.error(e));
}

// -----------------------------------------------------
// Manage tab (existing fleet list with remove buttons)
// -----------------------------------------------------

function renderManageList() {
    const container = $('#manageList');
    if (!container) return;
    const list = Array.isArray(garageState.fleet) ? garageState.fleet : [];
    if (!list.length) {
        container.innerHTML = '<p>No vehicles in this garage.</p>';
        return;
    }

    let html = '';
    list.forEach(v => {
        const label = v.label || v.model || 'Unknown';
        const plate = v.plate || '';
        const model = v.model || 'unknown';
        const minGrade = (v.min_grade !== undefined && v.min_grade !== null)
            ? v.min_grade
            : (v.min_grade_use || 0);

        html += `
            <div class="vehicle-card small" data-id="${v.id}">
                <div class="vehicle-info">
                    <div class="vehicle-label">${escapeHtml(label)}</div>
                    <div class="vehicle-plate">${escapeHtml(plate)} &mdash; ${escapeHtml(model)}</div>
                </div>
                <div class="vehicle-badges">
                    <span class="badge badge-grade">Grade ${minGrade || 0}+</span>
                </div>
                <div class="vehicle-actions">
                    <button class="btn-red remove-btn">Remove</button>
                </div>
            </div>
        `;
    });

    container.innerHTML = html;

    container.querySelectorAll('.vehicle-card').forEach(card => {
        const id = parseInt(card.getAttribute('data-id'));
        const btn = card.querySelector('.remove-btn');
        if (!btn || !id) return;

        btn.addEventListener('click', () => {
            if (!currentGarageId) return;

            // Use in-NUI modal to avoid FiveM focus issues
            confirmModal('Remove this vehicle from the job fleet?', () => {
                fetch(`https://${RESOURCE_NAME}/removeVehicle`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        id: id,
                        garageId: currentGarageId
                    })
                }).catch(e => console.error(e));
            });
        });
    });
}

// -----------------------------------------------------
// Owned vehicles tab (Load My Vehicles → Add to Fleet)
// De-duped against current fleet, so you can't add twice
// -----------------------------------------------------

function renderOwnedVehicles(list) {
    const container = $('#ownedList');
    if (!container) return;
    const owned = Array.isArray(list) ? list : [];

    // Build a set of plates that are already in this garage's fleet
    const fleet = Array.isArray(garageState.fleet) ? garageState.fleet : [];
    const fleetPlates = new Set(
        fleet
            .map(v => (v.plate || '').toUpperCase().trim())
            .filter(p => p !== '')
    );

    // Filter out any owned vehicles that are already in the fleet
    const available = owned.filter(v => {
        const plate = (v.plate || '').toUpperCase().trim();
        return plate !== '' && !fleetPlates.has(plate);
    });

    if (!available.length) {
        container.innerHTML = '<p>No owned vehicles available to add. Either you own none, or all of them are already in this garage fleet.</p>';
        return;
    }

    let html = '';
    available.forEach(v => {
        const label = v.label || v.model || 'Unknown';
        const plate = v.plate || '';
        const model = v.model || 'unknown';

        html += `
            <div class="vehicle-card small" data-plate="${escapeHtml(plate)}" data-model="${escapeHtml(model)}">
                <div class="vehicle-info">
                    <div class="vehicle-label">${escapeHtml(label)}</div>
                    <div class="vehicle-plate">${escapeHtml(plate)} &mdash; ${escapeHtml(model)}</div>
                </div>
                <div class="vehicle-actions">
                    <button class="btn-blue add-fleet-btn">Add to Fleet</button>
                </div>
            </div>
        `;
    });

    container.innerHTML = html;

    // Button events
    container.querySelectorAll('.vehicle-card').forEach(card => {
        const btn = card.querySelector('.add-fleet-btn');
        if (!btn) return;

        btn.addEventListener('click', () => {
            if (!currentGarageId) return;

            const plate   = card.getAttribute('data-plate');
            const model   = card.getAttribute('data-model');
            const labelEl = card.querySelector('.vehicle-label');
            const label   = labelEl ? labelEl.textContent : model;

            const minGradeInput = $('#ownedMinGrade');
            const minGrade = minGradeInput ? parseInt(minGradeInput.value) || 0 : 0;

            // Tell Lua to add this vehicle to the fleet
            fetch(`https://${RESOURCE_NAME}/addVehicle`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    garageId: currentGarageId,
                    plate: plate,
                    model: model,
                    label: label,
                    min_grade: minGrade
                })
            }).catch(e => console.error(e));

            // Optimistically remove this card from the list so it can't be added again
            card.remove();

            // Also update our local cache so future re-renders keep it gone
            if (ownedVehiclesCache && Array.isArray(ownedVehiclesCache)) {
                const norm = plate.toUpperCase().trim();
                ownedVehiclesCache = ownedVehiclesCache.filter(v => {
                    const p = (v.plate || '').toUpperCase().trim();
                    return p !== norm;
                });
            }
        });
    });
}

function loadOwnedVehicles() {
    // this hits RegisterNUICallback('getOwnedVehicles', ...) on the client
    fetch(`https://${RESOURCE_NAME}/getOwnedVehicles`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    })
    .then(res => {
        if (!res.ok) {
            console.error('getOwnedVehicles HTTP error', res.status, res.statusText);
            throw new Error('HTTP ' + res.status);
        }
        return res.json();
    })
    .then(data => {
        ownedVehiclesCache = data || [];
        renderOwnedVehicles(ownedVehiclesCache);
        if (ownedVehiclesCache.length) {
            showToast(`Loaded ${ownedVehiclesCache.length} vehicles.`);
        } else {
            showToast('No owned vehicles found for this character.');
        }
    })
    .catch(e => { console.error(e); showToast('Failed to load owned vehicles.'); });
}

// -----------------------------------------------------
// Permissions tab
// -----------------------------------------------------

function renderPermissions() {
    const container = $('#permissionsPanel');
    if (!container) return;

    const perms = garageState.permissions;
    const isManager = !!garageState.isManager;

    if (!perms) {
        container.innerHTML = '<p>No permissions configured yet for this garage.</p>';
        return;
    }

    const minUse = perms.min_grade_use ?? 0;
    const minManage = perms.min_grade_manage ?? 0;

    if (!isManager) {
        container.innerHTML = `
            <div class="setting-row">
                <span>Minimum grade to use vehicles:</span>
                <span style="margin-left:auto;font-weight:600;">${minUse}</span>
            </div>
            <div class="setting-row">
                <span>Minimum grade to manage fleet:</span>
                <span style="margin-left:auto;font-weight:600;">${minManage}</span>
            </div>
            <p class="hint">Only managers can change permissions.</p>
        `;
        return;
    }

    container.innerHTML = `
        <div class="setting-row">
            <label>Minimum grade to use vehicles:</label>
            <input id="permUseInput" type="number" min="0" value="${minUse}">
        </div>
        <div class="setting-row">
            <label>Minimum grade to manage fleet:</label>
            <input id="permManageInput" type="number" min="0" value="${minManage}">
        </div>
        <div class="actions">
            <button id="savePermsBtn" class="btn-blue">Save Permissions</button>
        </div>
        <p class="hint">Changes apply only to this garage.</p>
    `;

    const saveBtn = document.getElementById('savePermsBtn');
    if (saveBtn) {
        saveBtn.addEventListener('click', () => {
            const useVal = document.getElementById('permUseInput').value;
            const manageVal = document.getElementById('permManageInput').value;

            fetch(`https://${RESOURCE_NAME}/savePermissions`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    min_grade_use: parseInt(useVal) || 0,
                    min_grade_manage: parseInt(manageVal) || 0
                })
            }).catch(e => console.error(e));
        });
    }
}

// -----------------------------------------------------
// Assignments tab
// -----------------------------------------------------

function renderAssignments() {
    const container = $('#assignmentsPanel');
    if (!container) return;

    const isManager = !!garageState.isManager;
    const base = garageState.fleet || [];
    const out  = garageState.outVehicles || [];

    const map = {};
    base.forEach(v => { map[v.id] = v; });
    out.forEach(v => { map[v.id] = v; });

    const list = Object.values(map);

    if (!list.length) {
        container.innerHTML = '<p>No vehicles in this garage.</p>';
        return;
    }

    let html = '';

    list.forEach(v => {
        const label = v.label || v.model || 'Unknown';
        const plate = v.plate || '';
        const model = v.model || 'unknown';
        const aType = v.assignment_type || 'none';

        let assignmentText = 'Unassigned';
        if (aType === 'citizenid') {
            assignmentText = 'Assigned to: ' + (v.assigned_name || v.assigned_citizenid || 'Unknown');
        } else if (aType === 'grade') {
            assignmentText = 'Reserved for grade ' + (v.assigned_grade ?? 0) + '+';
        }

        html += `
            <div class="vehicle-card small assignment-card" data-id="${v.id}">
                <div class="vehicle-info">
                    <div class="vehicle-label">${escapeHtml(label)}</div>
                    <div class="vehicle-plate">${escapeHtml(plate)} &mdash; ${escapeHtml(model)}</div>
                </div>
                <div class="vehicle-meta">
                    <div>${escapeHtml(assignmentText)}</div>
                </div>
        `;

        if (isManager) {
            html += `
                <div class="assignment-edit">
                    <label>Assign type:</label>
                    <select class="assign-type">
                        <option value="none" ${aType === 'none' ? 'selected' : ''}>None</option>
                        <option value="player" ${aType === 'citizenid' ? 'selected' : ''}>Specific Player</option>
                        <option value="grade" ${aType === 'grade' ? 'selected' : ''}>Minimum Grade</option>
                    </select>
                    <input class="assign-target" type="text" placeholder="Server ID or Grade" value="${aType === 'grade' ? (v.assigned_grade ?? '') : ''}">
                    <button class="btn-blue assign-save">Save</button>
                </div>
            `;
        }

        html += `</div>`;
    });

    container.innerHTML = html;

    if (!isManager) return;

    container.querySelectorAll('.assignment-card').forEach(card => {
        const id = parseInt(card.getAttribute('data-id'));

        const typeSel = card.querySelector('.assign-type');
        const targetInput = card.querySelector('.assign-target');
        const saveBtn = card.querySelector('.assign-save');

        if (!saveBtn || !typeSel || !targetInput || !id) return;

        typeSel.addEventListener('change', () => {
            const val = typeSel.value;
            if (val === 'player') {
                targetInput.placeholder = 'Server ID (online)';
            } else if (val === 'grade') {
                targetInput.placeholder = 'Minimum grade number';
            } else {
                targetInput.placeholder = 'Server ID or Grade';
            }
        });

        saveBtn.addEventListener('click', () => {
            const type = typeSel.value;
            const target = targetInput.value.trim();

            fetch(`https://${RESOURCE_NAME}/saveAssignment`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    id: id,
                    type: type,
                    target: target
                })
            }).catch(e => console.error(e));
        });
    });
}

// -----------------------------------------------------
// Vehicles Out tab
// -----------------------------------------------------

function renderOutList() {
    const container = $('#outList');
    if (!container) return;
    container.innerHTML = '';

    const list = garageState.outVehicles || [];

    if (!list.length) {
        container.innerHTML = '<p>No vehicles currently out.</p>';
        return;
    }

    const isManager = !!garageState.isManager;

    list.forEach(v => {
        const div = document.createElement('div');
        div.className = 'vehicle-card';

        const label = v.label || v.model || 'Unknown';
        const plate = v.plate || '';
        const who   = v.out_name || v.out_citizenid || 'Unknown';
        const sinceText = formatSince(v.out_since);

        let actionsHtml = '';
        if (isManager) {
            actionsHtml = `
                <div class="vehicle-actions">
                    <button class="btn-red force-return-btn">Force Return</button>
                </div>
            `;
        }

        div.innerHTML = `
            <div class="vehicle-info">
                <div class="vehicle-label">${escapeHtml(label)}</div>
                <div class="vehicle-plate">${escapeHtml(plate)}</div>
            </div>
            <div class="vehicle-meta">
                <div>Signed out by: ${escapeHtml(who)}</div>
                <div>Since: ${escapeHtml(sinceText)}</div>
            </div>
            ${actionsHtml}
        `;

        if (isManager) {
            const btn = div.querySelector('.force-return-btn');
            if (btn) {
                btn.addEventListener('click', () => {
                    fetch(`https://${RESOURCE_NAME}/forceReturn`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ id: v.id })
                    }).catch(e => console.error(e));
                });
            }
        }

        container.appendChild(div);
    });
}

// -----------------------------------------------------
// Logs tab
// -----------------------------------------------------

function renderLogs() {
    const container = $('#logsPanel');
    if (!container) return;

    const logs = garageState.logs || [];
    if (!logs.length) {
        container.innerHTML = '<p>No recent activity for this garage.</p>';
        return;
    }

    let html = '';

    logs.forEach(log => {
        const action = log.action || 'unknown';
        const actor  = log.actor_name || 'Unknown';
        const target = log.target_name || '';
        const plate  = log.plate || '';
        const model  = log.model || '';
        const when   = formatSince(log.created_at);

        let actionLabel = '';

        switch (action) {
            case 'take':
                actionLabel = 'took vehicle';
                break;
            case 'store':
                actionLabel = 'stored vehicle';
                break;
            case 'add_vehicle':
                actionLabel = 'added vehicle to fleet';
                break;
            case 'remove_vehicle':
                actionLabel = 'removed vehicle from fleet';
                break;
            case 'update_permissions':
                actionLabel = 'updated permissions';
                break;
            case 'assign_player':
                actionLabel = 'assigned vehicle to ' + (target || 'someone');
                break;
            case 'assign_grade':
                actionLabel = 'reserved vehicle for a grade';
                break;
            case 'clear_assignment':
                actionLabel = 'cleared assignment';
                break;
            case 'force_return':
                actionLabel = 'force-returned vehicle';
                break;
            default:
                actionLabel = action;
                break;
        }

        html += `
            <div class="log-entry">
                <div class="log-main">
                    <span class="log-actor">${escapeHtml(actor)}</span>
                    <span class="log-action">${escapeHtml(actionLabel)}</span>
                    ${(plate || model) ? `<span class="log-vehicle">[${escapeHtml(plate)} ${escapeHtml(model)}]</span>` : ''}
                </div>
                <div class="log-meta">
                    <span>${escapeHtml(when)}</span>
                    ${target && ['assign_player'].includes(action) ? `<span>Target: ${escapeHtml(target)}</span>` : ''}
                </div>
            </div>
        `;
    });

    container.innerHTML = html;
}

// -----------------------------------------------------
// DOM Ready: wire buttons, tabs, filters
// -----------------------------------------------------

document.addEventListener('DOMContentLoaded', () => {
    // Close button
    const closeBtn = $('#closeBtn');
    if (closeBtn) {
        closeBtn.addEventListener('click', () => {
            fetch(`https://${RESOURCE_NAME}/close`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({})
            }).catch(e => console.error(e));
        });
    }

    // Tabs
    $all('.nav-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            const tabKey = btn.dataset.tab;
            if (tabKey) setActiveTab(tabKey);
        });
    });

    document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' || e.key === 'Esc') {
            // Tell Lua to close NUI
            fetch(`https://${RESOURCE_NAME}/close`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({})
            }).catch(e => console.error(e));
        }
    });

    // Load owned vehicles button
    const loadOwnedBtn = $('#loadOwnedBtn');
    if (loadOwnedBtn) {
        loadOwnedBtn.addEventListener('click', () => {
            loadOwnedVehicles();
        });
    }

    // Fleet sort & filter
    const sortSel = $('#fleetSort');
    const mineCb  = $('#filterMine');

    if (sortSel) {
        sortSel.addEventListener('change', () => {
            garageState.sortMode = sortSel.value || 'default';
            renderFleet();
        });
    }

    if (mineCb) {
        mineCb.addEventListener('change', () => {
            garageState.showMineOnly = mineCb.checked;
            renderFleet();
        });
    }

    // Hide app by default
    hideApp();
});

