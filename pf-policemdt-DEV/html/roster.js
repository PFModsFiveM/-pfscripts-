// ============================================================================
// POLICE MDT - Roster Module (Flexible Callsign System)
// ============================================================================

(function () {
    function normalizeString(s) {
        return String(s ?? '').trim();
    }

    function safeLower(s) {
        return normalizeString(s).toLowerCase();
    }

    function parseCallsign(callsignRaw) {
        const callsign = normalizeString(callsignRaw);
        const upper = callsign.toUpperCase();

        // Exact K-9 pattern
        let m = upper.match(/^(K-9)-(\d+)$/);
        if (m) {
            return { groupKey: 'K-9', suffixNum: Number(m[2]), sortKey: Number(m[2]) };
        }

        // Digits + Letters + - + Digits  (2A-12, 5D-01, 12AB-03)
        m = upper.match(/^(\d+)([A-Z]+)-(\d+)$/);
        if (m) {
            return { groupKey: `${m[1]}${m[2]}`, suffixNum: Number(m[3]), sortKey: Number(m[3]) };
        }

        // Letters + Digits + - + Digits (A1-01)
        m = upper.match(/^([A-Z]+)(\d+)-(\d+)$/);
        if (m) {
            return { groupKey: `${m[1]}${m[2]}`, suffixNum: Number(m[3]), sortKey: Number(m[3]) };
        }

        // Letters + - + Digits (Air-1, Marine-2, SRO-4, CP-6)
        m = callsign.match(/^([A-Za-z]+)\s*-\s*(\d+)$/);
        if (m) {
            return { groupKey: m[1].toUpperCase(), suffixNum: Number(m[2]), sortKey: Number(m[2]) };
        }

        // Numeric-only
        m = callsign.match(/^(\d+)$/);
        if (m) {
            return { groupKey: 'NUMERIC', suffixNum: Number(m[1]), sortKey: Number(m[1]) };
        }

        // Fallback
        return { groupKey: 'OTHER', suffixNum: null, sortKey: upper };
    }

    function toNumericDisplay(callsignRaw) {
        const callsign = normalizeString(callsignRaw);
        const upper = callsign.toUpperCase();

        // digit(s) + letters + - + digits
        let m = upper.match(/^(\d+)([A-Z]+)-(\d+)$/);
        if (m) {
            const prefixDigits = m[1];
            const suffix = String(Number(m[3])).padStart(2, '0');
            return `${prefixDigits}${suffix}`;
        }

        // letters + digit(s) + - + digits
        m = upper.match(/^([A-Z]+)(\d+)-(\d+)$/);
        if (m) {
            const prefixDigits = m[2];
            const suffix = String(Number(m[3])).padStart(2, '0');
            return `${prefixDigits}${suffix}`;
        }

        // otherwise leave unchanged
        return callsign;
    }

    const UNIT_TYPE_ORDER = [
        'Command / Administration',
        'Watch Command / Field Command',
        'Patrol Units',
        'Training Units',
        'Detectives / Investigations',
        'Traffic Unit',
        'K-9 Unit',
        'Narcotics Unit',
        'Gang Unit',
        'SWAT',
        'Support Units'
    ];

    function unitTypeSortIndex(unitType) {
        const i = UNIT_TYPE_ORDER.indexOf(unitType);
        return i === -1 ? 9999 : i;
    }

    function getUserInfo() {
        // In this MDT, `userInfo` is declared in app.js with `let`, which does
        // NOT become a `window.userInfo` property. Read from the global lexical
        // binding when available, and fall back to `window.userInfo`.
        try {
            // eslint-disable-next-line no-undef
            if (typeof userInfo !== 'undefined' && userInfo) return userInfo;
        } catch (_) {}
        return window.userInfo || null;
    }

    function canEditRoster() {
        const info = getUserInfo();
        return (Number(info?.rankLevel) || 0) >= 4;
    }

    function showToast(message) {
        // No browser popups: prefer global MDT toast.
        try {
            if (typeof mdtToast === 'function') {
                mdtToast(message, 'info');
                return;
            }
        } catch (_) {}
        console.log('[ROSTER]', message);
    }

    async function openNotesModal(title, initialValue, readOnly) {
        const value = normalizeString(initialValue);
        const ro = readOnly === true;

        return new Promise((resolve) => {
            const modalHTML = `
                <div class="roster-notes-backdrop" id="rosterNotesBackdrop">
                    <div class="roster-notes-modal">
                        <div class="roster-notes-header">
                            <div class="roster-notes-title">${escapeHtml(title)}</div>
                            <button class="roster-notes-close" id="rosterNotesClose">Close</button>
                        </div>
                        <div id="rosterNotesTextarea" style="flex: 1; overflow: hidden;"></div>
                        <div class="roster-notes-footer">
                            ${ro ? `<button class="roster-notes-btn" id="rosterNotesCancel">Close</button>` : `
                                <button class="roster-notes-btn" id="rosterNotesCancel">Cancel</button>
                                <button class="roster-notes-btn primary" id="rosterNotesSave">Save</button>
                            `}
                        </div>
                    </div>
                </div>
            `;

            document.body.insertAdjacentHTML('beforeend', modalHTML);
            const backdrop = document.getElementById('rosterNotesBackdrop');
            
            // Initialize RTE - with proper error handling
            let rte = null;
            try {
                if (typeof createRTE === 'function') {
                    rte = createRTE('rosterNotesTextarea', {
                        initialContent: value,
                        placeholder: 'Notes...',
                        readonly: ro,
                        minHeight: '150px',
                        maxHeight: '300px'
                    });
                } else {
                    // Fallback to textarea if RTE not available
                    const container = document.getElementById('rosterNotesTextarea');
                    if (container) {
                        const textarea = document.createElement('textarea');
                        textarea.id = 'rosterNotesTextarea_fallback';
                        textarea.style.width = '100%';
                        textarea.style.height = '100%';
                        textarea.style.padding = '10px';
                        textarea.style.border = '1px solid rgba(255,255,255,0.12)';
                        textarea.style.background = 'rgba(255,255,255,0.06)';
                        textarea.style.color = '#e0e6f2';
                        textarea.placeholder = 'Notes...';
                        textarea.readOnly = ro;
                        textarea.value = value;
                        container.appendChild(textarea);
                        rte = { 
                            getValue: () => textarea.value,
                            destroy: () => textarea.remove()
                        };
                    }
                }
            } catch (e) {
                console.error('[Roster] Failed to initialize RTE:', e);
            }

            const cleanup = (result) => {
                try { 
                    if (rte && typeof rte.destroy === 'function') {
                        rte.destroy();
                    }
                    if (typeof destroyRTE === 'function') {
                        destroyRTE('rosterNotesTextarea');
                    }
                    backdrop.remove(); 
                } catch (_) {}
                resolve(result);
            };

            document.getElementById('rosterNotesClose').onclick = () => cleanup(null);
            document.getElementById('rosterNotesCancel').onclick = () => cleanup(null);
            const saveBtn = document.getElementById('rosterNotesSave');
            if (saveBtn) saveBtn.onclick = () => cleanup(rte && rte.getValue ? rte.getValue() : '');
            backdrop.addEventListener('click', (e) => {
                if (e.target === backdrop) cleanup(null);
            });

            // Focus on the editor
            setTimeout(() => {
                try {
                    if (rte && typeof rte.focus === 'function') {
                        rte.focus();
                    } else {
                        const textareaFallback = document.getElementById('rosterNotesTextarea_fallback');
                        if (textareaFallback) textareaFallback.focus();
                    }
                } catch (_) {}
            }, 10);
        });
    }

    class RosterPage extends BasePage {
        constructor() {
            super('roster', 'Roster');
            this.rows = [];
            this.meta = { ranks: [], unitTypes: [], trainingStatuses: [], canEdit: false };
            this.filters = { search: '', rank: '', unit_type: '', training_status: '' };
            this.numericDisplay = false;
            this.refreshing = false;

            this.officerDirectory = null;
            this.officerDirectoryPromise = null;
        }

        async loadOfficerDirectory() {
            if (Array.isArray(this.officerDirectory)) return this.officerDirectory;
            if (this.officerDirectoryPromise) return this.officerDirectoryPromise;

            this.officerDirectoryPromise = new Promise((resolve) => {
                sendCallback('getRosterOfficerDirectory', {}, (res) => {
                    this.officerDirectoryPromise = null;
                    if (!res || !res.success) {
                        this.officerDirectory = [];
                        resolve(this.officerDirectory);
                        return;
                    }
                    const list = Array.isArray(res.officers) ? res.officers : [];
                    list.sort((a, b) => String(a?.name || '').localeCompare(String(b?.name || '')));
                    this.officerDirectory = list;
                    resolve(this.officerDirectory);
                });
            });

            return this.officerDirectoryPromise;
        }

        mount(root) {
            super.mount(root);
            root.innerHTML = `
                <div class="search-page-container charges-page roster-page">
                    <div class="search-page-header">
                        <div class="search-page-title-group">
                            <h2>Roster</h2>
                            <div class="search-page-subtitle">Department Registry</div>
                        </div>
                        <div class="roster-actions">
                            <button class="pagination-btn" id="rosterNumericToggle">Numeric Display: Off</button>
                            <button class="pagination-btn" id="rosterRefreshBtn">Refresh</button>
                        </div>
                    </div>

                    <div class="roster-filters">
                        <input type="text" id="rosterSearch" class="search-page-input" placeholder="Search callsign or name..." />
                        <select id="rosterFilterRank" class="roster-select"></select>
                        <select id="rosterFilterUnit" class="roster-select"></select>
                        <select id="rosterFilterTraining" class="roster-select"></select>
                    </div>

                    <div id="rosterGroups"></div>
                </div>
            `;

            this.attachListeners();
            this.loadMetaAndData();
        }

        attachListeners() {
            const search = document.getElementById('rosterSearch');
            const rank = document.getElementById('rosterFilterRank');
            const unit = document.getElementById('rosterFilterUnit');
            const training = document.getElementById('rosterFilterTraining');

            search?.addEventListener('input', (e) => {
                this.filters.search = e.target.value;
                this.render();
            });

            rank?.addEventListener('change', (e) => {
                this.filters.rank = e.target.value;
                this.render();
            });

            unit?.addEventListener('change', (e) => {
                this.filters.unit_type = e.target.value;
                this.render();
            });

            training?.addEventListener('change', (e) => {
                this.filters.training_status = e.target.value;
                this.render();
            });

            document.getElementById('rosterRefreshBtn')?.addEventListener('click', () => this.loadRoster());
            document.getElementById('rosterNumericToggle')?.addEventListener('click', () => {
                this.numericDisplay = !this.numericDisplay;
                const btn = document.getElementById('rosterNumericToggle');
                if (btn) btn.textContent = `Numeric Display: ${this.numericDisplay ? 'On' : 'Off'}`;
                this.render();
            });
        }

        async loadMetaAndData() {
            await this.loadMeta();
            await this.loadRoster();
        }

        async loadMeta() {
            return new Promise((resolve) => {
                sendCallback('getRosterMeta', {}, (res) => {
                    if (res && res.success) {
                        this.meta = {
                            ranks: res.ranks || [],
                            unitTypes: res.unitTypes || [],
                            trainingStatuses: res.trainingStatuses || [],
                            canEdit: res.canEdit === true
                        };
                        this.populateFilterOptions();
                    }
                    resolve();
                });
            });
        }

        populateFilterOptions() {
            const rank = document.getElementById('rosterFilterRank');
            const unit = document.getElementById('rosterFilterUnit');
            const training = document.getElementById('rosterFilterTraining');

            if (rank) {
                rank.innerHTML = `<option value="">Rank (All)</option>` + (this.meta.ranks || []).filter(r => r !== '').map(r => `<option value="${escapeHtml(r)}">${escapeHtml(r)}</option>`).join('');
            }
            if (unit) {
                unit.innerHTML = `<option value="">Unit Type (All)</option>` + (this.meta.unitTypes || []).filter(u => u !== '').map(u => `<option value="${escapeHtml(u)}">${escapeHtml(u)}</option>`).join('');
            }
            if (training) {
                training.innerHTML = `<option value="">Training (All)</option>` + (this.meta.trainingStatuses || []).map(t => `<option value="${escapeHtml(t)}">${escapeHtml(t)}</option>`).join('');
            }
        }

        async loadRoster() {
            if (this.refreshing) return;
            this.refreshing = true;

            return new Promise((resolve) => {
                sendCallback('getRoster', { ...this.filters }, (res) => {
                    this.refreshing = false;
                    if (!res || !res.success) {
                        showToast(res?.error ? `Failed to load roster: ${res.error}` : 'Failed to load roster');
                        resolve();
                        return;
                    }
                    this.rows = Array.isArray(res.rows) ? res.rows : [];
                    this.render();
                    resolve();
                });
            });
        }

        getFilteredRows() {
            const s = safeLower(this.filters.search);
            const rankFilter = normalizeString(this.filters.rank);
            const unitFilter = normalizeString(this.filters.unit_type);
            const trainingFilter = normalizeString(this.filters.training_status);

            return (this.rows || []).filter((r) => {
                if (rankFilter && normalizeString(r.rank) !== rankFilter) return false;
                if (unitFilter && normalizeString(r.unit_type) !== unitFilter) return false;
                if (trainingFilter && normalizeString(r.training_status) !== trainingFilter) return false;
                if (s) {
                    const hay = `${safeLower(r.callsign)} ${safeLower(r.officer_name)} ${safeLower(r.rank)} ${safeLower(r.unit_type)}`;
                    if (!hay.includes(s)) return false;
                }
                return true;
            });
        }

        groupRows(rows) {
            const byUnit = new Map();

            for (const row of rows) {
                const unitType = normalizeString(row.unit_type) || 'Other';
                if (!byUnit.has(unitType)) byUnit.set(unitType, []);
                byUnit.get(unitType).push(row);
            }

            // Within each unit type, group by derived prefix
            const result = [];
            for (const [unitType, unitRows] of byUnit.entries()) {
                const byGroup = new Map();
                for (const r of unitRows) {
                    const p = parseCallsign(r.callsign);
                    const key = p.groupKey;
                    if (!byGroup.has(key)) byGroup.set(key, []);
                    byGroup.get(key).push({ row: r, parsed: p });
                }

                const groups = [];
                for (const [groupKey, items] of byGroup.entries()) {
                    items.sort((a, b) => {
                        const ak = a.parsed.sortKey;
                        const bk = b.parsed.sortKey;
                        if (typeof ak === 'number' && typeof bk === 'number') return ak - bk;
                        return String(ak).localeCompare(String(bk));
                    });
                    groups.push({ groupKey, items });
                }
                groups.sort((a, b) => a.groupKey.localeCompare(b.groupKey));

                result.push({ unitType, groups });
            }

            result.sort((a, b) => {
                const ai = unitTypeSortIndex(a.unitType);
                const bi = unitTypeSortIndex(b.unitType);
                if (ai !== bi) return ai - bi;
                return a.unitType.localeCompare(b.unitType);
            });
            return result;
        }

        render() {
            const container = document.getElementById('rosterGroups');
            if (!container) return;

            const canEdit = canEditRoster() && this.meta.canEdit;
            const rows = this.getFilteredRows();
            const grouped = this.groupRows(rows);

            if (rows.length === 0) {
                container.innerHTML = `<div class="empty-message" style="padding: 30px;">No roster entries found</div>`;
                return;
            }

            container.innerHTML = grouped.map(section => {
                const unitHeader = `<div class="roster-unit-header">${escapeHtml(section.unitType)}</div>`;
                const groupsHtml = section.groups.map(g => {
                    const header = `
                        <div class="roster-group-header">
                            <div class="roster-group-title">${escapeHtml(g.groupKey)}</div>
                            ${canEdit ? `<button class="pagination-btn roster-add" data-unit="${escapeHtml(section.unitType)}" data-group="${escapeHtml(g.groupKey)}">+</button>` : ''}
                        </div>
                    `;

                    const body = `
                        <div class="charges-table-container">
                            <table class="charges-table roster-table">
                                <thead>
                                    <tr>
                                        <th>Callsign</th>
                                        <th>Rank</th>
                                        <th>Officer</th>
                                        <th>Unit Type</th>
                                        <th>Training</th>
                                        <th>Notes</th>
                                        <th>Status</th>
                                        ${canEdit ? '<th>Actions</th>' : ''}
                                    </tr>
                                </thead>
                                <tbody>
                                    ${g.items.map(({ row }) => this.renderRow(row, canEdit)).join('')}
                                </tbody>
                            </table>
                        </div>
                    `;

                    return `<div class="roster-group">${header}${body}</div>`;
                }).join('');

                return `<div class="roster-unit">${unitHeader}${groupsHtml}</div>`;
            }).join('');

            this.attachRowHandlers();
        }

        renderRow(row, canEdit) {
            const rawCallsign = normalizeString(row.callsign);
            const displayCallsign = this.numericDisplay ? toNumericDisplay(rawCallsign) : rawCallsign;

            const isOnline = row.isOnline === true;
            const statusHtml = isOnline ? `<span class="roster-badge online">Online</span>` : `<span class="roster-badge offline">Offline</span>`;

            const notesVal = normalizeString(row.notes);
            const notesShort = notesVal ? escapeHtml(notesVal.length > 24 ? notesVal.slice(0, 24) + '…' : notesVal) : '<span class="muted">—</span>';

            const protectedChief = ['CHIEF', 'CHIEF OF POLICE'].includes(normalizeString(row.rank).toUpperCase());

            return `
                <tr data-id="${row.id}">
                    <td class="roster-cell" data-field="callsign" data-edit="text">${escapeHtml(displayCallsign || '')}</td>
                    <td class="roster-cell" data-field="rank" data-edit="text">${escapeHtml(row.rank || '')}</td>
                    <td class="roster-cell" data-field="officer_name" data-edit="select-officer">${escapeHtml(row.officer_name || '')}</td>
                    <td class="roster-cell" data-field="unit_type" data-edit="select-unit">${escapeHtml(row.unit_type || '')}</td>
                    <td class="roster-cell" data-field="training_status" data-edit="select-training">${escapeHtml(row.training_status || 'NONE')}</td>
                    <td class="roster-notes-cell" data-field="notes">${notesShort}</td>
                    <td>${statusHtml}</td>
                    ${canEdit ? `<td>
                        <button class="btn-icon roster-delete" ${protectedChief ? 'disabled title="Protected"' : ''}>Delete</button>
                    </td>` : ''}
                </tr>
            `;
        }

        attachRowHandlers() {
            const canEdit = canEditRoster() && this.meta.canEdit;

            // Add-row buttons
            document.querySelectorAll('.roster-add').forEach(btn => {
                btn.addEventListener('click', async (e) => {
                    if (!canEdit) return;
                    const unit_type = e.currentTarget.dataset.unit || '';
                    const groupKey = e.currentTarget.dataset.group || '';
                    sendCallback('rosterAddRow', { unit_type, groupKey }, (res) => {
                        if (!res || !res.success) {
                            showToast(res?.error ? `Add failed: ${res.error}` : 'Add failed');
                            return;
                        }
                        this.loadRoster();
                    });
                });
            });

            // Inline edit cells
            document.querySelectorAll('.roster-cell').forEach(cell => {
                cell.addEventListener('click', (e) => {
                    if (!canEdit) return;
                    this.beginEditCell(e.currentTarget);
                });
            });

            // Notes cell
            document.querySelectorAll('.roster-notes-cell').forEach(cell => {
                cell.addEventListener('click', async (e) => {
                    const tr = e.currentTarget.closest('tr');
                    const id = Number(tr?.dataset?.id);
                    const row = this.rows.find(r => Number(r.id) === id);
                    if (!row) return;

                    const value = await openNotesModal(`Notes: ${row.callsign}`, row.notes, !canEdit);
                    if (value === null) return;

                    if (!canEdit) return;
                    await this.saveRowUpdate(id, { notes: value });
                });
            });

            // Delete
            document.querySelectorAll('.roster-delete').forEach(btn => {
                btn.addEventListener('click', async (e) => {
                    if (!canEdit) return;
                    const tr = e.currentTarget.closest('tr');
                    const id = Number(tr?.dataset?.id);
                    const row = this.rows.find(r => Number(r.id) === id);
                    if (!row) return;

                    if (normalizeString(row.rank) === 'Chief') {
                        showToast('Chief row is protected from deletion.');
                        return;
                    }

                    const ok = window.mdtConfirm ? await window.mdtConfirm(`Delete roster slot ${row.callsign}?`) : false;
                    if (!ok) return;

                    sendCallback('rosterDeleteRow', { id }, (res) => {
                        if (!res || !res.success) {
                            showToast(res?.error ? `Delete failed: ${res.error}` : 'Delete failed');
                            return;
                        }
                        this.loadRoster();
                    });
                });
            });
        }

        beginEditCell(cell) {
            const tr = cell.closest('tr');
            const id = Number(tr?.dataset?.id);
            const field = cell.dataset.field;
            const editType = cell.dataset.edit;

            if (!id || !field || !editType) return;
            if (cell.classList.contains('editing')) return;

            const row = this.rows.find(r => Number(r.id) === id);
            if (!row) return;

            const originalValue = row[field] ?? '';

            cell.classList.add('editing');

            const finish = async (newValue, cancelled) => {
                cell.classList.remove('editing');
                if (cancelled) {
                    this.render();
                    return;
                }
                if (String(newValue ?? '') === String(originalValue ?? '')) {
                    this.render();
                    return;
                }

                const patch = {};
                patch[field] = newValue;
                await this.saveRowUpdate(id, patch);
            };

            if (editType === 'select-officer') {
                const select = document.createElement('select');
                select.className = 'roster-inline-input';

                const addOption = (value, label, selected) => {
                    const opt = document.createElement('option');
                    opt.value = value;
                    opt.textContent = label;
                    if (selected) opt.selected = true;
                    select.appendChild(opt);
                };

                const currentCid = normalizeString(row.citizenid);
                addOption('', '— Unassigned —', currentCid === '');
                addOption('__loading__', 'Loading...', false);

                cell.innerHTML = '';
                cell.appendChild(select);
                select.focus();

                this.loadOfficerDirectory().then((dir) => {
                    select.innerHTML = '';
                    addOption('', '— Unassigned —', currentCid === '');
                    for (const o of dir || []) {
                        const cid = normalizeString(o?.citizenid);
                        if (!cid) continue;
                        const name = normalizeString(o?.name) || cid;
                        addOption(cid, `${name} (${cid})`, cid === currentCid);
                    }
                });

                const finishOfficer = async (cancelled) => {
                    cell.classList.remove('editing');
                    if (cancelled) {
                        this.render();
                        return;
                    }

                    const selectedCid = normalizeString(select.value);
                    if (selectedCid === '__loading__') {
                        this.render();
                        return;
                    }

                    if (selectedCid === currentCid) {
                        this.render();
                        return;
                    }

                    if (!selectedCid) {
                        await this.saveRowUpdate(id, { citizenid: null, officer_name: '' });
                        return;
                    }

                    const dir = Array.isArray(this.officerDirectory) ? this.officerDirectory : [];
                    const found = dir.find(x => normalizeString(x?.citizenid) === selectedCid);
                    const name = normalizeString(found?.name) || selectedCid;
                    await this.saveRowUpdate(id, { citizenid: selectedCid, officer_name: name });
                };

                select.addEventListener('keydown', (e) => {
                    if (e.key === 'Enter') finishOfficer(false);
                    if (e.key === 'Escape') finishOfficer(true);
                });
                select.addEventListener('blur', () => finishOfficer(false));
                return;
            }

            if (editType === 'text') {
                const input = document.createElement('input');
                input.type = 'text';
                input.className = 'roster-inline-input';
                input.value = String(originalValue ?? '');
                cell.innerHTML = '';
                cell.appendChild(input);
                input.focus();
                input.select();
                input.addEventListener('keydown', (e) => {
                    if (e.key === 'Enter') finish(input.value, false);
                    if (e.key === 'Escape') finish(originalValue, true);
                });
                input.addEventListener('blur', () => finish(input.value, false));
                return;
            }

            const select = document.createElement('select');
            select.className = 'roster-inline-input';

            const options = (() => {
                if (editType === 'select-rank') return this.meta.ranks || [];
                if (editType === 'select-unit') return this.meta.unitTypes || [];
                if (editType === 'select-training') return this.meta.trainingStatuses || [];
                return [];
            })();

            const normalizedOriginal = normalizeString(originalValue);
            const makeOption = (v) => {
                const opt = document.createElement('option');
                opt.value = v;
                opt.textContent = v === '' ? '—' : v;
                if (normalizeString(v) === normalizedOriginal) opt.selected = true;
                return opt;
            };

            for (const v of options) {
                select.appendChild(makeOption(String(v)));
            }

            cell.innerHTML = '';
            cell.appendChild(select);
            select.focus();

            select.addEventListener('keydown', (e) => {
                if (e.key === 'Enter') finish(select.value, false);
                if (e.key === 'Escape') finish(originalValue, true);
            });
            select.addEventListener('blur', () => finish(select.value, false));
        }

        async saveRowUpdate(id, patch) {
            const row = this.rows.find(r => Number(r.id) === id);
            if (!row) return;

            const payload = {
                id,
                callsign: row.callsign,
                rank: row.rank,
                officer_name: row.officer_name,
                citizenid: row.citizenid,
                unit_type: row.unit_type,
                training_status: row.training_status,
                notes: row.notes,
                ...patch
            };

            const doSend = (confirmDuplicate) => {
                const sendPayload = { ...payload, confirmDuplicate: confirmDuplicate === true };
                return new Promise((resolve) => {
                    sendCallback('rosterUpdateRow', sendPayload, (res) => resolve(res));
                });
            };

            let res = await doSend(false);

            if (res && res.requiresConfirm) {
                const conflict = res.conflict;
                const msg = conflict?.callsign ? `This citizen is already assigned to ${conflict.callsign}. Assign anyway?` : 'This citizen is already assigned. Assign anyway?';
                const ok = window.mdtConfirm ? await window.mdtConfirm(msg) : false;
                if (!ok) {
                    await this.loadRoster();
                    return;
                }
                res = await doSend(true);
            }

            if (!res || !res.success) {
                showToast(res?.error ? `Save failed: ${res.error}` : 'Save failed');
                await this.loadRoster();
                return;
            }

            await this.loadRoster();
        }
    }

    window.RosterPage = RosterPage;
    window.ToNumericDisplay = toNumericDisplay;

    // If the MDT opened before this script loaded, the router may have already
    // registered a placeholder roster page. Hot-swap it now.
    try {
        if (typeof router !== 'undefined' && router && typeof router.register === 'function') {
            const current = router.pages?.get?.('roster');
            const shouldReplace = !current || (typeof BasePage !== 'undefined' && current.constructor === BasePage);
            if (shouldReplace) {
                router.register('roster', new RosterPage(), 'Roster');
                if (router.current === 'roster') {
                    router.set('roster');
                }
            }
        }
    } catch (_) {}
})();
