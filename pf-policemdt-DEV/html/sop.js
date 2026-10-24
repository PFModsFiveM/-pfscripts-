(function(){
class SOPPage extends BasePage {
    constructor() {
        super('sop','SOP');
        this.sops = [];
        this.categories = [];
        this.selectedId = null;
        this.selected = null;
        this.search = '';
        this.category = '';
        this.formState = null;
        this.searchTimer = null;
    }

    canManage() {
        return (userInfo && (userInfo.rankLevel || 0) >= 4) || (userPermissions && userPermissions.isOwner);
    }

    mount(root) {
        super.mount(root);
        root.innerHTML = `
            <div class="sop-page">
                <div class="sop-topbar">
                    <div class="sop-filter-row">
                        <div class="sop-search-wrap">
                            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"></circle><path d="m21 21-4.35-4.35"></path></svg>
                            <input id="sopSearch" type="text" placeholder="Search SOPs (title, text, category)..." autocomplete="off" />
                        </div>
                        <select id="sopCategoryFilter" class="sop-select">
                            <option value="">All Categories</option>
                        </select>
                    </div>
                    <div class="sop-actions">
                        <button id="sopNewBtn" class="sop-btn primary">New SOP</button>
                    </div>
                </div>
                <div class="sop-layout">
                    <div class="sop-list" id="sopList"><div class="empty-message">Loading SOPs...</div></div>
                    <div class="sop-detail" id="sopDetail"><div class="empty-message">Select an SOP to view details.</div></div>
                </div>
            </div>
        `;
        this.bindEvents();
        this.updateActionVisibility();
        this.loadSOPs();
    }

    bindEvents() {
        const searchInput = document.getElementById('sopSearch');
        if (searchInput) {
            searchInput.addEventListener('input', () => {
                clearTimeout(this.searchTimer);
                this.searchTimer = setTimeout(() => {
                    this.search = searchInput.value;
                    this.loadSOPs();
                }, 250);
            });
        }
        const catSelect = document.getElementById('sopCategoryFilter');
        if (catSelect) {
            catSelect.addEventListener('change', () => {
                this.category = catSelect.value;
                this.loadSOPs();
            });
        }
        const newBtn = document.getElementById('sopNewBtn');
        if (newBtn) {
            newBtn.addEventListener('click', () => {
                if (!this.canManage()) return;
                this.openForm('create');
            });
        }
    }

    updateActionVisibility() {
        const newBtn = document.getElementById('sopNewBtn');
        if (!newBtn) return;
        if (this.canManage()) newBtn.classList.remove('hidden'); else newBtn.classList.add('hidden');
    }

    loadSOPs() {
        const listEl = document.getElementById('sopList');
        if (listEl) listEl.innerHTML = '<div class="empty-message">Loading SOPs...</div>';
        sendCallback('getSOPs', { search: this.search, category: this.category }, (res) => {
            console.log('[SOP DEBUG] getSOPs response:', res);
            if (!res || !res.success) {
                console.error('[SOP ERROR] Failed to load SOPs:', res);
                if (listEl) listEl.innerHTML = `<div class="empty-message">${escapeHtml(res && res.error || 'Failed to load SOPs')}</div>`;
                return;
            }
            this.sops = res.data || [];
            this.categories = Array.from(new Set(this.sops.map(s => s.category))).sort();
            this.refreshCategoryFilter();
            if (this.selectedId && !this.sops.find(s => s.id === this.selectedId)) {
                this.selectedId = null;
                this.selected = null;
            }
            this.renderList();
            if (!this.selectedId && this.sops.length > 0) {
                this.selectSOP(this.sops[0].id, false);
            } else {
                this.renderDetail();
            }
        });
    }

    refreshCategoryFilter() {
        const catSelect = document.getElementById('sopCategoryFilter');
        if (!catSelect) return;
        const current = this.category || '';
        catSelect.innerHTML = '<option value="">All Categories</option>' + this.categories.map(c => `<option value="${escapeHtml(c)}" ${c === current ? 'selected' : ''}>${escapeHtml(c)}</option>`).join('');
    }

    renderList() {
        const listEl = document.getElementById('sopList');
        if (!listEl) return;
        if (!this.sops || this.sops.length === 0) {
            listEl.innerHTML = '<div class="empty-message">No SOPs found.</div>';
            return;
        }
        listEl.innerHTML = this.sops.map(s => {
            const preview = this.buildPreview(s);
            const active = s.id === this.selectedId ? 'active' : '';
            return `
                <div class="sop-item ${active}" data-id="${s.id}">
                    <div class="sop-item-title">${escapeHtml(s.title)}</div>
                    <div class="sop-item-meta">
                        <span class="sop-category-pill">${escapeHtml(s.category)}</span>
                        <span class="sop-item-preview">${escapeHtml(preview)}</span>
                    </div>
                </div>
            `;
        }).join('');
        listEl.querySelectorAll('.sop-item').forEach(el => {
            el.addEventListener('click', () => {
                const id = Number(el.dataset.id);
                this.selectSOP(id, true);
            });
        });
    }

    buildPreview(s) {
        const parts = [s.purpose, s.policy, s.procedure];
        const text = parts.find(p => (p || '').trim() !== '') || '';
        return text.length > 120 ? text.slice(0, 117) + '...' : text;
    }

    selectSOP(id, resetForm) {
        if (!id) return;
        this.selectedId = id;
        if (resetForm) this.formState = null;
        const detailEl = document.getElementById('sopDetail');
        if (detailEl) detailEl.innerHTML = '<div class="empty-message">Loading SOP...</div>';
        sendCallback('getSOP', { id }, (res) => {
            if (!res || !res.success || !res.data) {
                if (detailEl) detailEl.innerHTML = `<div class="empty-message">${escapeHtml(res && res.error || 'Unable to load SOP')}</div>`;
                return;
            }
            this.selected = res.data;
            this.renderList();
            this.renderDetail();
        });
    }

    renderDetail() {
        const detailEl = document.getElementById('sopDetail');
        if (!detailEl) return;
        if (this.formState) {
            detailEl.innerHTML = this.renderFormHtml(this.formState);
            this.bindFormEvents();
            return;
        }
        if (!this.selected) {
            detailEl.innerHTML = '<div class="empty-message">Select an SOP to view details.</div>';
            return;
        }
        const s = this.selected;
        const updatedMeta = s.updated_at ? formatDateTime(s.updated_at) : '—';
        const actions = this.canManage() ? `
            <div class="sop-detail-actions">
                <button class="sop-btn ghost" id="sopEditBtn">Edit SOP</button>
                <button class="sop-btn danger ghost" id="sopDeleteBtn">Delete</button>
            </div>
        ` : '';
        detailEl.innerHTML = `
            <div class="sop-detail-header">
                <div>
                    <div class="sop-detail-title">${escapeHtml(s.title)}</div>
                    <div class="sop-detail-meta">
                        <span class="sop-category-pill">${escapeHtml(s.category)}</span>
                        <span class="muted">Last updated ${escapeHtml(updatedMeta)}</span>
                        ${s.updated_by ? `<span class="muted">by ${escapeHtml(s.updated_by)}</span>` : ''}
                    </div>
                </div>
                ${actions}
            </div>
            ${this.renderSection('Purpose', s.purpose)}
            ${this.renderSection('Policy', s.policy)}
            ${this.renderSection('Procedure', s.procedure, true)}
            ${s.notes ? this.renderSection('Restrictions / Notes', s.notes) : ''}
        `;
        if (this.canManage()) {
            const editBtn = document.getElementById('sopEditBtn');
            if (editBtn) editBtn.addEventListener('click', () => this.openForm('edit', s));
            const delBtn = document.getElementById('sopDeleteBtn');
            if (delBtn) delBtn.addEventListener('click', () => this.deleteSOP());
        }
    }

    renderSection(title, text, listMode) {
        const safe = escapeHtml(text || '');
        const lines = safe.split('\n').filter(l => l.trim() !== '');
        const body = listMode && lines.length > 1
            ? `<ul class="sop-list-block">${lines.map(l => `<li>${l}</li>`).join('')}</ul>`
            : `<p>${safe.replace(/\n/g, '<br>')}</p>`;
        return `
            <div class="sop-section">
                <div class="sop-section-title">${escapeHtml(title)}</div>
                ${body}
            </div>
        `;
    }

    renderFormHtml(state) {
        const s = state.data || {};
        const categories = ['General Conduct','Patrol Operations','Use of Force','Emergency Response','Vehicle Operations','Investigations','Specialized Units','Internal Affairs','Training'];
        const currentCategory = s.category || this.category || '';
        const categoryOptions = [''].concat(Array.from(new Set([...categories, ...this.categories])));
        return `
            <div class="sop-form">
                <div class="sop-detail-header">
                    <div>
                        <div class="sop-detail-title">${state.mode === 'create' ? 'Create SOP' : 'Edit SOP'}</div>
                        <div class="sop-detail-meta">Fill in policy reference details</div>
                    </div>
                </div>
                <div class="sop-form-grid">
                    <label class="sop-field">
                        <span>Title</span>
                        <input id="sopFieldTitle" type="text" value="${escapeHtml(s.title || '')}" placeholder="e.g., Pursuit Policy" />
                    </label>
                    <label class="sop-field">
                        <span>Category</span>
                        <select id="sopFieldCategory" class="sop-select">
                            ${categoryOptions.map(c => `<option value="${escapeHtml(c)}" ${c === currentCategory ? 'selected' : ''}>${c === '' ? 'Select category' : escapeHtml(c)}</option>`).join('')}
                            <option value="__custom">Custom...</option>
                        </select>
                    </label>
                    <label class="sop-field">
                        <span>Custom Category (optional)</span>
                        <input id="sopFieldCategoryCustom" type="text" value="${escapeHtml(currentCategory && !categoryOptions.includes(currentCategory) ? currentCategory : '')}" placeholder="Type a custom category" />
                    </label>
                </div>
                <label class="sop-field">
                    <span>Purpose</span>
                    <div id="sopFieldPurpose" style="margin-top: 6px;" data-initial="${escapeHtml(s.purpose || '')}"></div>
                </label>
                <label class="sop-field">
                    <span>Policy</span>
                    <div id="sopFieldPolicy" style="margin-top: 6px;" data-initial="${escapeHtml(s.policy || '')}"></div>
                </label>
                <label class="sop-field">
                    <span>Procedure</span>
                    <div id="sopFieldProcedure" style="margin-top: 6px;" data-initial="${escapeHtml(s.procedure || '')}"></div>
                </label>
                <label class="sop-field">
                    <span>Notes / Restrictions (optional)</span>
                    <div id="sopFieldNotes" style="margin-top: 6px;" data-initial="${escapeHtml(s.notes || '')}"></div>
                </label>
                <div class="sop-form-actions">
                    <button class="sop-btn ghost" id="sopFormCancel">Cancel</button>
                    <button class="sop-btn primary" id="sopFormSave">${state.mode === 'create' ? 'Create SOP' : 'Save Changes'}</button>
                </div>
            </div>
        `;
    }

    bindFormEvents() {
        const cancelBtn = document.getElementById('sopFormCancel');
        if (cancelBtn) cancelBtn.addEventListener('click', () => { this.formState = null; this.renderDetail(); });
        const saveBtn = document.getElementById('sopFormSave');
        if (saveBtn) saveBtn.addEventListener('click', () => this.saveForm());
    }

    collectFormData() {
        const getVal = (id) => {
            // Try RTE first, then fallback to input element
            if (window.__mdtRTEManager) {
                const val = window.__mdtRTEManager.getPlainText(id);
                if (val) return val;
            }
            const el = document.getElementById(id);
            return el ? (el.value || el.textContent || '') : '';
        };
        const categorySelect = document.getElementById('sopFieldCategory');
        const selectedCat = categorySelect ? categorySelect.value : '';
        const custom = getVal('sopFieldCategoryCustom');
        const finalCategory = (custom && custom.trim() !== '') ? custom : (selectedCat === '__custom' ? '' : selectedCat);
        return {
            id: (this.formState && this.formState.data) ? this.formState.data.id : null,
            title: getVal('sopFieldTitle'),
            category: finalCategory,
            purpose: getVal('sopFieldPurpose'),
            policy: getVal('sopFieldPolicy'),
            procedure: getVal('sopFieldProcedure'),
            notes: getVal('sopFieldNotes')
        };
    }

    saveForm() {
        const payload = this.collectFormData();
        if (!payload.title || !payload.category || !payload.purpose || !payload.policy || !payload.procedure) {
            if (typeof mdtToast === 'function') mdtToast('All required fields except notes must be filled.', 'error');
            return;
        }
        const action = this.formState && this.formState.mode === 'edit' ? 'updateSOP' : 'createSOP';
        sendCallback(action, payload, (res) => {
            if (!res || !res.success) {
                if (typeof mdtToast === 'function') mdtToast((res && res.error) || 'Failed to save SOP', 'error');
                return;
            }
            this.formState = null;
            this.loadSOPs();
        });
    }

    async deleteSOP() {
        if (!this.selected || !this.selected.id) return;
        if (typeof window.mdtConfirm === 'function') {
            const ok = await window.mdtConfirm('Delete this SOP? This cannot be undone.');
            if (!ok) return;
        } else {
            // No browser confirm fallback (per no-popups requirement)
            if (typeof mdtToast === 'function') mdtToast('Confirm dialog unavailable', 'error');
            return;
        }
        sendCallback('deleteSOP', { id: this.selected.id }, (res) => {
            if (!res || !res.success) {
                if (typeof mdtToast === 'function') mdtToast((res && res.error) || 'Failed to delete SOP', 'error');
                return;
            }
            this.selected = null;
            this.selectedId = null;
            this.loadSOPs();
        });
    }

    openForm(mode, data) {
        this.formState = { mode, data: data || {} };
        this.renderDetail();
    }

    unmount() {
        this.sops = [];
        this.categories = [];
        this.selected = null;
        this.selectedId = null;
        this.formState = null;
        super.unmount();
    }
}

window.SOPPage = SOPPage;
})();
