(function(){
class OfficersManagementPage extends BasePage {
    constructor() {
        super('officers','Officers Management');
        this.officers = [];
        this.filtered = [];
        this.selectedCid = null;
        this.selected = null;
        this.search = '';
        this.filters = { rank: '', unit: '', training: '', onlineOnly: false };
        this._searchTimer = null;
        this._fireModalBound = false;
    }

    canManage() {
        return (userInfo && (userInfo.rankLevel || 0) >= 4) || (userPermissions && userPermissions.isOwner);
    }

    mount(root) {
        super.mount(root);
        root.innerHTML = `
            <div class="officers-page">
                <div class="officers-topbar">
                    <div class="officers-filter-row">
                        <div class="officers-search-wrap">
                            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"></circle><path d="m21 21-4.35-4.35"></path></svg>
                            <input id="officersSearch" type="text" placeholder="Search (name, callsign, rank, duty)..." autocomplete="off" />
                        </div>
                        <select id="officersRankFilter" class="officers-select"><option value="">All Ranks</option></select>
                        <select id="officersUnitFilter" class="officers-select"><option value="">All Units</option></select>
                        <select id="officersTrainingFilter" class="officers-select"><option value="">All Training</option></select>
                        <label class="officers-toggle"><input id="officersOnlineOnly" type="checkbox" /> Online Only</label>
                    </div>
                    <div class="officers-actions">
                        <button id="officersRefreshBtn" class="sop-btn ghost">Refresh</button>
                    </div>
                </div>

                <div class="officers-layout">
                    <div class="officers-list" id="officersList"><div class="empty-message">Loading officers...</div></div>
                    <div class="officers-detail" id="officersDetail"><div class="empty-message">Select an officer to view profile.</div></div>
                </div>
            </div>
        `;

        this.ensureFireModal();
        this.bindEvents();
        this.loadList();
    }

    unmount() {
        try {
            const modal = document.getElementById('officerFireModal');
            if (modal) modal.remove();
        } catch (_) {}
        super.unmount();
    }

    ensureFireModal() {
        if (document.getElementById('officerFireModal')) return;

        const modal = document.createElement('div');
        modal.id = 'officerFireModal';
        modal.className = 'modal hidden';
        modal.innerHTML = `
            <div class="modal-card" style="width: 520px; max-width: 92vw;">
                <div class="modal-header">
                    <h3>Fire Officer</h3>
                    <button class="modal-btn close-modal" title="Close" id="officerFireClose">✕</button>
                </div>
                <div class="modal-body">
                    <div style="color: rgba(255,255,255,0.85); line-height: 1.4;">
                        <div id="officerFireSummary" style="margin-bottom: 12px;"></div>
                        <label style="display:block; font-size: 13px; font-weight: 700; margin-bottom: 6px; color: rgba(255,255,255,0.85);">Reason (optional)</label>
                        <input id="officerFireReason" type="text" style="width: 100%; padding: 10px 12px; border-radius: 10px; border: 1px solid rgba(255,255,255,0.12); background: rgba(255,255,255,0.06); color: #e0e6f2; outline: none;" />
                        <div id="officerFireError" style="margin-top: 10px; color: #ffb3b3; font-weight: 700; display:none;"></div>
                    </div>
                </div>
                <div class="modal-footer">
                    <button class="modal-btn" id="officerFireCancel">Cancel</button>
                    <button class="modal-btn danger" id="officerFireConfirm">Fire</button>
                </div>
            </div>
        `;
        document.body.appendChild(modal);

        if (!this._fireModalBound) {
            this._fireModalBound = true;
            const close = () => this.closeFireModal();

            modal.addEventListener('click', (e) => {
                if (e.target === modal) close();
            });

            const closeBtn = modal.querySelector('#officerFireClose');
            const cancelBtn = modal.querySelector('#officerFireCancel');
            const confirmBtn = modal.querySelector('#officerFireConfirm');
            if (closeBtn) closeBtn.addEventListener('click', close);
            if (cancelBtn) cancelBtn.addEventListener('click', close);
            if (confirmBtn) confirmBtn.addEventListener('click', () => this.confirmFireOfficer());
        }
    }

    openFireModal() {
        const modal = document.getElementById('officerFireModal');
        if (!modal) return;
        const summary = modal.querySelector('#officerFireSummary');
        const reasonInput = modal.querySelector('#officerFireReason');
        const errEl = modal.querySelector('#officerFireError');
        if (errEl) { errEl.style.display = 'none'; errEl.textContent = ''; }

        const officerName = (this.selected && this.selected.name) ? String(this.selected.name) : String(this.selectedCid || '');
        if (summary) {
            summary.innerHTML = `
                <div style="font-weight: 900; color: #fff; margin-bottom: 6px;">${escapeHtml(officerName)}</div>
                <div class="muted">This will remove them from roster, set job to unemployed (grade 0), and hide them from Officer Management.</div>
            `;
        }

        const inlineReason = (document.getElementById('om_fire_reason') || {}).value || '';
        if (reasonInput) reasonInput.value = inlineReason;

        modal.classList.remove('hidden');
        try { reasonInput && reasonInput.focus(); } catch (_) {}
    }

    closeFireModal() {
        const modal = document.getElementById('officerFireModal');
        if (!modal) return;
        modal.classList.add('hidden');
    }

    confirmFireOfficer() {
        if (!this.selectedCid) return;
        const modal = document.getElementById('officerFireModal');
        if (!modal) return;
        const reason = (modal.querySelector('#officerFireReason') || {}).value || '';
        const errEl = modal.querySelector('#officerFireError');
        const confirmBtn = modal.querySelector('#officerFireConfirm');
        if (errEl) { errEl.style.display = 'none'; errEl.textContent = ''; }
        if (confirmBtn) confirmBtn.disabled = true;

        sendCallback('fireOfficer', { citizenid: this.selectedCid, reason }, (res) => {
            if (confirmBtn) confirmBtn.disabled = false;
            if (!res || !res.success) {
                const msg = (res && res.error) ? String(res.error) : 'Failed to fire officer';
                if (errEl) { errEl.textContent = msg; errEl.style.display = 'block'; }
                return;
            }
            this.closeFireModal();
            this.selectedCid = null;
            this.selected = null;
            this.loadList();
            this.renderDetail();
        });
    }

    bindEvents() {
        const searchEl = document.getElementById('officersSearch');
        if (searchEl) {
            searchEl.addEventListener('input', () => {
                clearTimeout(this._searchTimer);
                this._searchTimer = setTimeout(() => {
                    this.search = searchEl.value || '';
                    this.applyFilters();
                }, 200);
            });
        }

        const rankEl = document.getElementById('officersRankFilter');
        const unitEl = document.getElementById('officersUnitFilter');
        const trainingEl = document.getElementById('officersTrainingFilter');
        const onlineEl = document.getElementById('officersOnlineOnly');

        const onFilter = () => {
            this.filters.rank = rankEl ? (rankEl.value || '') : '';
            this.filters.unit = unitEl ? (unitEl.value || '') : '';
            this.filters.training = trainingEl ? (trainingEl.value || '') : '';
            this.filters.onlineOnly = onlineEl ? onlineEl.checked === true : false;
            this.applyFilters();
        };

        if (rankEl) rankEl.addEventListener('change', onFilter);
        if (unitEl) unitEl.addEventListener('change', onFilter);
        if (trainingEl) trainingEl.addEventListener('change', onFilter);
        if (onlineEl) onlineEl.addEventListener('change', onFilter);

        const refreshBtn = document.getElementById('officersRefreshBtn');
        if (refreshBtn) refreshBtn.addEventListener('click', () => this.loadList());

        const listEl = document.getElementById('officersList');
        if (listEl) {
            listEl.addEventListener('click', (e) => {
                const item = e.target.closest('.officer-item');
                if (!item) return;
                const cid = item.getAttribute('data-cid');
                if (!cid) return;
                this.selectOfficer(cid);
            });
        }
    }

    loadList() {
        const listEl = document.getElementById('officersList');
        if (listEl) listEl.innerHTML = '<div class="empty-message">Loading officers...</div>';

        sendCallback('getOfficersList', {}, (res) => {
            if (!res || !res.success) {
                const err = (res && res.error) ? String(res.error) : 'Failed to load officers';
                if (listEl) listEl.innerHTML = `<div class="empty-message">Failed to load officers: ${escapeHtml(err)}</div>`;
                return;
            }
            this.officers = Array.isArray(res.officers) ? res.officers : [];
            this.buildFilterOptions();
            this.applyFilters(true);
        });
    }

    buildFilterOptions() {
        const ranks = new Set();
        const units = new Set();
        const trainings = new Set();
        (this.officers || []).forEach(o => {
            if (o.rank) ranks.add(String(o.rank));
            if (o.unit_type) units.add(String(o.unit_type));
            if (o.training_status) trainings.add(String(o.training_status));
        });

        const setOptions = (el, values, label) => {
            if (!el) return;
            const current = el.value || '';
            const sorted = Array.from(values).sort((a,b) => a.localeCompare(b));
            el.innerHTML = `<option value="">${label}</option>` + sorted.map(v => `<option value="${escapeHtml(v)}" ${v === current ? 'selected' : ''}>${escapeHtml(v)}</option>`).join('');
        };

        setOptions(document.getElementById('officersRankFilter'), ranks, 'All Ranks');
        setOptions(document.getElementById('officersUnitFilter'), units, 'All Units');
        setOptions(document.getElementById('officersTrainingFilter'), trainings, 'All Training');
    }

    officerMatches(o, qLower) {
        const name = String(o.name || '').toLowerCase();
        const callsign = String(o.callsign || '').toLowerCase();
        const rank = String(o.rank || '').toLowerCase();
        const unit = String(o.unit_type || '').toLowerCase();
        const duty = (o.online && o.working) ? 'on duty' : (o.online ? 'online off duty' : 'offline');
        return name.includes(qLower) || callsign.includes(qLower) || rank.includes(qLower) || unit.includes(qLower) || duty.includes(qLower);
    }

    applyFilters(keepSelection) {
        const q = String(this.search || '').trim();
        const qLower = q.toLowerCase();

        this.filtered = (this.officers || []).filter(o => {
            if (this.filters.onlineOnly && !o.online) return false;
            if (this.filters.rank && String(o.rank || '') !== this.filters.rank) return false;
            if (this.filters.unit && String(o.unit_type || '') !== this.filters.unit) return false;
            if (this.filters.training && String(o.training_status || '') !== this.filters.training) return false;
            if (qLower && !this.officerMatches(o, qLower)) return false;
            return true;
        });

        if (!keepSelection && this.selectedCid && !this.filtered.some(o => String(o.citizenid) === String(this.selectedCid))) {
            this.selectedCid = null;
            this.selected = null;
        }

        this.renderList();

        if (!this.selectedCid && this.filtered.length > 0) {
            this.selectOfficer(this.filtered[0].citizenid, false);
        } else {
            this.renderDetail();
        }
    }

    renderList() {
        const listEl = document.getElementById('officersList');
        if (!listEl) return;

        if (!this.filtered || this.filtered.length === 0) {
            listEl.innerHTML = '<div class="empty-message">No officers found.</div>';
            return;
        }

        listEl.innerHTML = this.filtered.map(o => {
            const active = String(o.citizenid) === String(this.selectedCid) ? 'active' : '';
            const status = o.online ? (o.working ? 'On Duty' : 'Online (Not Working)') : 'Offline';
            const statusClass = o.online ? (o.working ? 'badge-good' : 'badge-warn') : 'badge-muted';

            // Generate avatar
            const avatarHtml = o.avatarUrl 
                ? `<img src="${escapeHtml(o.avatarUrl)}" class="officer-item-avatar" alt="${escapeHtml(o.name || 'Officer')}">`
                : `<div class="officer-item-avatar officer-item-avatar-fallback">${escapeHtml((o.name || 'Officer').substring(0, 2).toUpperCase())}</div>`;

            // Format last online
            let lastOnlineText = '';
            if (!o.online && o.lastOnline) {
                const now = Date.now();
                const lastOnlineMs = o.lastOnline * 1000; // Convert Unix timestamp to milliseconds
                const diff = now - lastOnlineMs;
                const minutes = Math.floor(diff / 60000);
                const hours = Math.floor(minutes / 60);
                const days = Math.floor(hours / 24);
                
                if (days > 0) lastOnlineText = `${days}d ago`;
                else if (hours > 0) lastOnlineText = `${hours}h ago`;
                else if (minutes > 0) lastOnlineText = `${minutes}m ago`;
                else lastOnlineText = 'Just now';
            }

            const pills = [];
            pills.push(`<span class="officer-pill ${statusClass}">${escapeHtml(status)}</span>`);
            if (o.status && String(o.status).toUpperCase() !== 'ACTIVE') pills.push(`<span class="officer-pill badge-warn">${escapeHtml(o.status)}</span>`);
            if (o.is_fto) pills.push(`<span class="officer-pill badge-good">FTO</span>`);
            if (o.is_supervisor) pills.push(`<span class="officer-pill badge-primary">SUPERVISOR</span>`);
            if (o.probation_until) pills.push(`<span class="officer-pill badge-warn">Probation</span>`);
            if ((o.flagCount || 0) > 0) pills.push(`<span class="officer-pill badge-warn">Flags: ${Number(o.flagCount)||0}</span>`);

            return `
                <div class="officer-item ${active}" data-cid="${escapeHtml(o.citizenid)}">
                    ${avatarHtml}
                    <div class="officer-item-content">
                        <div class="officer-item-top">
                            <div class="officer-item-name">${escapeHtml(o.name || 'Officer')}</div>
                            <div class="officer-item-callsign">${escapeHtml(o.callsign || '')}</div>
                        </div>
                        <div class="officer-item-sub">
                            <span class="officer-item-rank">${escapeHtml(o.rank || 'Unassigned')}</span>${o.unit_type ? ` • ${escapeHtml(o.unit_type)}` : ''}
                            ${lastOnlineText ? `<span class="officer-item-lastonline"> • ${lastOnlineText}</span>` : ''}
                        </div>
                        <div class="officer-item-pills">${pills.join('')}</div>
                    </div>
                </div>
            `;
        }).join('');
    }

    selectOfficer(citizenid, scroll = true) {
        this.selectedCid = String(citizenid);
        this.renderList();
        if (scroll) {
            const el = document.querySelector(`.officer-item[data-cid="${CSS.escape(this.selectedCid)}"]`);
            try { el && el.scrollIntoView({ block: 'nearest' }); } catch (_) {}
        }
        this.loadProfile(this.selectedCid);
    }

    loadProfile(citizenid) {
        const detailEl = document.getElementById('officersDetail');
        if (detailEl) detailEl.innerHTML = '<div class="empty-message">Loading profile...</div>';

        sendCallback('getOfficerProfile', { citizenid }, (res) => {
            if (!res || !res.success) {
                if (detailEl) detailEl.innerHTML = `<div class="empty-message">${escapeHtml((res && res.error) || 'Failed to load profile')}</div>`;
                return;
            }
            this.selected = res.data || null;
            this.renderDetail();
        });
    }

    renderDetail() {
        const detailEl = document.getElementById('officersDetail');
        if (!detailEl) return;

        const data = this.selected;
        if (!data) {
            detailEl.innerHTML = '<div class="empty-message">Select an officer to view profile.</div>';
            return;
        }

        const roster = data.roster || {};
        const prof = data.profile || {};
        const presence = data.presence || {};
        const activity = data.activity || {};
        const discipline = Array.isArray(data.discipline) ? data.discipline : null;
        const history = Array.isArray(data.history) ? data.history : [];

        const canManage = this.canManage();

        const presenceText = presence.online ? (presence.working ? 'Online • Working Police' : 'Online • Not Working Police') : 'Offline';

        const formatAuditAction = (actionRaw) => {
            const a = String(actionRaw || '').toLowerCase();
            const map = {
                'fire_officer': 'Fired Officer',
                'employment_update': 'Updated Employment',
                'profile_update': 'Updated Profile Flags',
                'discipline_add': 'Issued Discipline',
                'discipline_resolve': 'Resolved Discipline',
                'discipline_remove': 'Removed Discipline',
                'bonus_permanent_set': 'Set Permanent Bonus',
                'bonus_permanent_revoke': 'Revoked Permanent Bonus',
                'bonus_oneoff_grant': 'Granted One-off Bonus',
            };
            return map[a] || (actionRaw ? String(actionRaw) : '');
        };

        const formatAuditActor = (nameRaw) => {
            const n = String(nameRaw || '').trim();
            if (!n) return 'Unknown';
            if (/^\d+$/.test(n)) return 'Unknown';
            return n;
        };

        const formatAuditTime = (ts) => {
            if (typeof formatDateTime === 'function') return formatDateTime(ts);
            const raw = String(ts || '').trim();
            if (!raw) return '';
            const d = new Date(raw);
            if (!isNaN(d.getTime())) return d.toLocaleString();
            return raw;
        };

        const formatAuditDetails = (beforeJson, afterJson, action) => {
            const before = beforeJson ? (typeof beforeJson === 'string' ? JSON.parse(beforeJson) : beforeJson) : null;
            const after = afterJson ? (typeof afterJson === 'string' ? JSON.parse(afterJson) : afterJson) : null;

            if (!before && !after) return '';

            const changes = [];

            const formatFieldName = (field) => {
                const map = {
                    'callsign': 'Callsign',
                    'rank': 'Rank',
                    'unit_type': 'Unit',
                    'training_status': 'Training',
                    'status': 'Status',
                    'probation_until': 'Probation Until',
                    'is_fto': 'FTO Status'
                };
                return map[field] || field;
            };

            const formatValue = (val, field) => {
                if (!val || val === '' || val === 'NONE') return null;
                if (field === 'status') {
                    // Format status names: DESK_DUTY → Desk Duty
                    return val.replace(/_/g, ' ').toLowerCase().replace(/\b\w/g, l => l.toUpperCase());
                }
                if (field === 'training_status') {
                    return val === 'NONE' ? null : val;
                }
                return val;
            };

            if (action === 'employment_update') {
                const fields = ['callsign', 'rank', 'unit_type', 'training_status'];
                fields.forEach(field => {
                    const oldVal = formatValue(before && before[field] ? before[field] : '', field);
                    const newVal = formatValue(after && after[field] ? after[field] : '', field);
                    
                    if (oldVal !== newVal) {
                        const fieldLabel = formatFieldName(field);
                        if (!oldVal && newVal) {
                            changes.push(`${fieldLabel} set to "${newVal}"`);
                        } else if (oldVal && !newVal) {
                            changes.push(`${fieldLabel} cleared`);
                        } else if (oldVal && newVal) {
                            changes.push(`${fieldLabel}: "${oldVal}" → "${newVal}"`);
                        }
                    }
                });
            } else if (action === 'profile_update') {
                if (before && after) {
                    const oldStatus = formatValue(before.status || 'ACTIVE', 'status');
                    const newStatus = formatValue(after.status || 'ACTIVE', 'status');
                    if (oldStatus !== newStatus) {
                        changes.push(`Status: ${oldStatus} → ${newStatus}`);
                    }
                    
                    const oldProb = before.probation_until || null;
                    const newProb = after.probation_until || null;
                    if (oldProb !== newProb) {
                        if (!oldProb && newProb) {
                            changes.push(`Probation set until ${newProb}`);
                        } else if (oldProb && !newProb) {
                            changes.push(`Probation cleared`);
                        } else if (oldProb && newProb) {
                            changes.push(`Probation: ${oldProb} → ${newProb}`);
                        }
                    }
                    
                    const oldFto = before.is_fto ? true : false;
                    const newFto = after.is_fto ? true : false;
                    if (oldFto !== newFto) {
                        changes.push(`FTO Status: ${newFto ? 'Granted' : 'Revoked'}`);
                    }
                }
            } else if (action === 'discipline_add') {
                if (after) {
                    const type = after.type ? after.type.replace(/_/g, ' ').toLowerCase().replace(/\b\w/g, l => l.toUpperCase()) : 'Unknown';
                    changes.push(`Type: ${type} • Reason: ${after.reason || 'Not specified'}`);
                }
            } else if (action === 'fire_officer') {
                if (after && after.reason) {
                    changes.push(`Reason: ${after.reason}`);
                }
            } else if (action === 'discipline_resolve' || action === 'discipline_remove') {
                if (after && after.id) {
                    changes.push(`Record ID: ${after.id}`);
                }
            }

            return changes.length ? changes.join(' • ') : '';
        };

        detailEl.innerHTML = `
            <div class="officer-profile">
                <div class="officer-profile-header">
                    <div>
                        <div class="officer-profile-name">${escapeHtml(data.name || 'Officer')}</div>
                        <div class="officer-profile-sub">CID: ${escapeHtml(data.citizenid || '')} • ${escapeHtml(presenceText)}</div>
                    </div>
                </div>

                <div class="officer-section">
                    <div class="officer-section-title">Employment</div>
                    <div class="officer-kv-grid">
                        <div class="officer-kv"><div class="k">Callsign</div><div class="v">${escapeHtml(roster.callsign || '')}</div></div>
                        <div class="officer-kv"><div class="k">Rank</div><div class="v">${escapeHtml(roster.rank || '')}</div></div>
                        <div class="officer-kv"><div class="k">Unit</div><div class="v">${escapeHtml(roster.unit_type || '')}</div></div>
                        <div class="officer-kv"><div class="k">Training</div><div class="v">${escapeHtml(roster.training_status || '')}</div></div>
                        <div class="officer-kv"><div class="k">Status</div><div class="v">${escapeHtml(prof.status || 'ACTIVE')}</div></div>
                        <div class="officer-kv"><div class="k">Probation</div><div class="v">${
                            prof.probation_until ? `<span class="probation-badge" title="Probation until ${escapeHtml(prof.probation_until)}">On Probation</span>` : '<span class="text-muted">None</span>'
                        }</div></div>
                        <div class="officer-kv"><div class="k">FTO</div><div class="v">${prof.is_fto ? 'Yes' : 'No'}</div></div>
                        <div class="officer-kv"><div class="k">Supervisor</div><div class="v">${prof.is_supervisor ? 'Yes' : 'No'}</div></div>
                    </div>

                    ${canManage ? this.renderEmploymentEditor(data) : ''}
                </div>

                <div class="officer-section">
                    <div class="officer-section-title">Activity (Last 30 days)</div>
                    <div class="officer-activity-grid">
                        <div class="officer-activity"><div class="n">${Number(activity.incidents||0)}</div><div class="l">Incidents</div></div>
                        <div class="officer-activity"><div class="n">${Number(activity.reports||0)}</div><div class="l">Reports</div></div>
                        <div class="officer-activity"><div class="n">${Number(activity.warrants||0)}</div><div class="l">Warrants</div></div>
                        <div class="officer-activity"><div class="n">${Number(activity.evidence||0)}</div><div class="l">Evidence</div></div>
                    </div>
                </div>

                <div class="officer-section">
                    <div class="officer-section-title">Discipline</div>
                    ${discipline === null ? `<div class="muted">You can only view your own discipline records.</div>` : this.renderDiscipline(discipline, canManage)}
                </div>

                <div class="officer-section">
                    <div class="officer-section-title">Audit History</div>
                    <div class="officer-history">${history.length ? history.map(h => {
                        const actor = formatAuditActor(h.actor_name);
                        const action = formatAuditAction(h.action);
                        const at = formatAuditTime(h.created_at);
                        const details = formatAuditDetails(h.before_json, h.after_json, h.action);
                        return `
                            <div class="officer-history-row">
                                <div class="officer-history-main">
                                    <div class="officer-history-action">${escapeHtml(action)}</div>
                                    <div class="officer-history-details">${details ? escapeHtml(details) : ''}</div>
                                </div>
                                <div class="officer-history-meta">
                                    <div class="officer-history-actor">${escapeHtml(actor)}</div>
                                    <div class="officer-history-time">${escapeHtml(at)}</div>
                                </div>
                            </div>
                        `;
                    }).join('') : '<div class="muted">No history yet.</div>'}</div>
                </div>
            </div>
        `;

        if (canManage) this.bindDetailActions();
    }

    renderEmploymentEditor(data) {
        const roster = data.roster || {};
        const prof = data.profile || {};

        return `
            <div class="officer-editor">
                <div class="officer-editor-row">
                    <label class="officer-field"><span>Callsign</span><input id="om_callsign" type="text" value="${escapeHtml(roster.callsign || '')}" placeholder="2A-11" readonly style="cursor: not-allowed; user-select: none;" /></label>
                    <label class="officer-field"><span>Rank</span><input id="om_rank" type="text" value="${escapeHtml(roster.rank || '')}" placeholder="Patrol Officer" readonly style="cursor: not-allowed; user-select: none;" /></label>
                </div>
                <div class="officer-editor-row">
                    <label class="officer-field"><span>Unit</span><input id="om_unit" type="text" value="${escapeHtml(roster.unit_type || '')}" placeholder="Patrol Units" readonly style="cursor: not-allowed; user-select: none;" /></label>
                    <label class="officer-field"><span>Training</span><input id="om_training" type="text" value="${escapeHtml(roster.training_status || '')}" placeholder="NONE/TRAINING/TRAINEE" readonly style="cursor: not-allowed; user-select: none;" /></label>
                </div>
                <div class="officer-editor-row">
                    <label class="officer-field"><span>Status</span>
                        <select id="om_status" class="officers-select">
                            ${['ACTIVE','DESK_DUTY','SUSPENDED'].map(s => `<option value="${s}" ${String(prof.status||'ACTIVE').toUpperCase()===s?'selected':''}>${s}</option>`).join('')}
                        </select>
                    </label>
                    <label class="officer-field"><span>Probation Until</span><input id="om_probation" type="datetime-local" value="${escapeHtml(prof.probation_until ? String(prof.probation_until).replace(' ', 'T').substring(0, 16) : '')}" placeholder="" /></label>
                </div>
                <div class="officer-editor-row">
                    <label class="officers-toggle"><input id="om_fto" type="checkbox" ${prof.is_fto ? 'checked' : ''} /> FTO Status</label>
                    <label class="officers-toggle"><input id="om_supervisor" type="checkbox" ${prof.is_supervisor ? 'checked' : ''} /> Supervisor</label>
                </div>
                <div class="officer-editor-actions">
                    <button id="om_save" class="sop-btn primary">Save Employment</button>
                </div>

                <div class="officer-editor-split"></div>

                <div class="officer-editor-row">
                    <label class="officer-field"><span>Fire Reason</span><input id="om_fire_reason" type="text" value="" placeholder="Optional reason" /></label>
                    <div></div>
                </div>
                <div class="officer-editor-actions">
                    <button id="om_fire" class="sop-btn danger">Fire Officer</button>
                </div>
            </div>
        `;
    }

    renderDiscipline(rows, canManage) {
        const list = rows || [];
        const activeText = (r) => (Number(r.active) === 1 ? 'Active' : 'Resolved');

        return `
            ${canManage ? `
                <div class="officer-disc-add">
                    <select id="om_disc_type" class="officers-select">
                        <option value="WARNING">WARNING</option>
                        <option value="STRIKE">STRIKE</option>
                        <option value="SUSPENSION">SUSPENSION</option>
                    </select>
                    <input id="om_disc_reason" class="search-page-input" type="text" placeholder="Reason..." />
                    <button id="om_disc_add" class="sop-btn danger">Issue</button>
                </div>
            ` : ''}

            <div class="officer-disc-list">
                ${list.length ? list.map(r => {
                    const buttons = canManage ? `
                        <div class="officer-disc-actions">
                            ${Number(r.active) === 1 ? `<button class="sop-btn ghost" data-disc-action="resolve" data-disc-id="${r.id}">Resolve</button>` : ''}
                            <button class="sop-btn danger" data-disc-action="remove" data-disc-id="${r.id}">Remove</button>
                        </div>
                    ` : '';
                    return `
                        <div class="officer-disc-row">
                            <div class="officer-disc-top">
                                <div class="t">${escapeHtml(r.type || '')} • ${escapeHtml(activeText(r))}</div>
                                <div class="m">${escapeHtml(r.issued_by || '')} • ${escapeHtml(r.issued_at || '')}</div>
                            </div>
                            <div class="officer-disc-reason">${escapeHtml(r.reason || '')}</div>
                            ${buttons}
                        </div>
                    `;
                }).join('') : '<div class="muted">No discipline records.</div>'}
            </div>
        `;
    }

    bindDetailActions() {
        const saveBtn = document.getElementById('om_save');
        if (saveBtn) saveBtn.onclick = () => this.saveEmployment();

        const fireBtn = document.getElementById('om_fire');
        if (fireBtn) fireBtn.onclick = () => this.openFireModal();

        const addDisc = document.getElementById('om_disc_add');
        if (addDisc) addDisc.onclick = () => this.addDiscipline();

        const discList = document.querySelector('.officer-disc-list');
        if (discList) {
            discList.addEventListener('click', (e) => {
                const btn = e.target.closest('button[data-disc-action]');
                if (!btn) return;
                const action = btn.getAttribute('data-disc-action');
                const id = Number(btn.getAttribute('data-disc-id'));
                if (!id) return;
                this.updateDiscipline(id, action);
            });
        }

        // Bonuses removed
    }

    // fire handled via modal

    saveEmployment() {
        if (!this.selectedCid) return;
        const payload = {
            citizenid: this.selectedCid,
            callsign: (document.getElementById('om_callsign') || {}).value || '',
            rank: (document.getElementById('om_rank') || {}).value || '',
            unit_type: (document.getElementById('om_unit') || {}).value || '',
            training_status: (document.getElementById('om_training') || {}).value || ''
        };

        sendCallback('updateOfficerEmployment', payload, (res) => {
            if (!res || !res.success) {
                if (typeof mdtToast === 'function') mdtToast((res && res.error) ? String(res.error) : 'Failed to update employment', 'error');
                return;
            }

            // Properly format probation datetime
            const probationRaw = (document.getElementById('om_probation') || {}).value || '';
            let probationFormatted = '';
            if (probationRaw) {
                // Input is in format YYYY-MM-DDTHH:mm, need to convert to YYYY-MM-DD HH:mm:ss
                const [date, time] = probationRaw.split('T');
                probationFormatted = date && time ? `${date} ${time}:00` : '';
            }

            const flagsPayload = {
                citizenid: this.selectedCid,
                status: (document.getElementById('om_status') || {}).value || 'ACTIVE',
                probation_until: probationFormatted,
                is_fto: (document.getElementById('om_fto') || {}).checked === true,
                is_supervisor: (document.getElementById('om_supervisor') || {}).checked === true
            };

            sendCallback('updateOfficerProfileFlags', flagsPayload, (res2) => {
                if (!res2 || !res2.success) {
                    if (typeof mdtToast === 'function') mdtToast((res2 && res2.error) ? String(res2.error) : 'Updated employment but failed profile flags', 'error');
                    // Still reload the list even if profile flags fail
                    this.loadList();
                    this.loadProfile(this.selectedCid);
                    return;
                }
                if (typeof mdtToast === 'function') mdtToast('Officer profile updated successfully', 'success');
                this.loadList();
                this.loadProfile(this.selectedCid);
            });
        });
    }

    addDiscipline() {
        if (!this.selectedCid) return;
        const dtype = (document.getElementById('om_disc_type') || {}).value || 'WARNING';
        const reason = (document.getElementById('om_disc_reason') || {}).value || '';
        sendCallback('addOfficerDiscipline', { citizenid: this.selectedCid, type: dtype, reason }, (res) => {
            if (!res || !res.success) {
                if (typeof mdtToast === 'function') mdtToast((res && res.error) ? String(res.error) : 'Failed to add discipline', 'error');
                return;
            }
            this.loadProfile(this.selectedCid);
        });
    }

    updateDiscipline(id, action) {
        sendCallback('updateOfficerDiscipline', { id, action }, (res) => {
            if (!res || !res.success) {
                if (typeof mdtToast === 'function') mdtToast((res && res.error) ? String(res.error) : 'Failed to update discipline', 'error');
                return;
            }
            this.loadProfile(this.selectedCid);
        });
    }

    // Bonuses removed
}

window.OfficersManagementPage = OfficersManagementPage;
})();
