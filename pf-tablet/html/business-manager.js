// PF Tablet Business Manager.
// Registry, compliance, taxes and audit come from the government registry (pf-government),
// visible to staff with the government "businesses" permission. "My supplies" shows the
// player's own business orders. All data comes from the server; nothing here is sample data.

window.renderBusinessManagerUI = function ($container) {
    $container.html(`
        <div class="businesses-window-content">
            <div class="businesses-topbar"><h2>Business Manager</h2></div>
            <div class="businesses-container">
                <div class="businesses-sidebar">
                    <div class="businesses-nav-item active" data-page="overview">Overview</div>
                    <div class="businesses-nav-item" data-page="registry">Registry</div>
                    <div class="businesses-nav-item" data-page="compliance">Compliance</div>
                    <div class="businesses-nav-item" data-page="taxes">Taxes</div>
                    <div class="businesses-nav-item" data-page="audit">Audit</div>
                    <div class="businesses-nav-item" data-page="supplies">My supplies</div>
                </div>
                <div class="businesses-main" id="businesses-content"></div>
            </div>
        </div>
    `);
    window.businessesManager = new BusinessesManager();
};

const bmEsc = (v) => String(v == null ? '' : v).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const bmMoney = (v) => (v == null ? '—' : '$' + (Number(v) || 0).toLocaleString(undefined, { maximumFractionDigits: 2 }));
const bmParse = (r) => { if (typeof r === 'string') { try { return JSON.parse(r); } catch (e) { return null; } } return r; };

function bmPost(name, payload) {
    return new Promise((resolve) => {
        const post = window.PFTablet && window.PFTablet.post;
        if (!post) return resolve(null);
        post(name, payload).done(r => resolve(bmParse(r))).fail(() => resolve(null));
    });
}

const BM_ERRORS = {
    no_permission: 'You need the government businesses permission.',
    registry_unavailable: 'The business registry could not be read.',
    government_offline: 'The government system is offline.',
    unknown_citizen: 'No citizen with that ID.',
    job_business: 'Mechanic shops belong to their job; change the job boss instead.',
    business_not_found: 'That business is no longer registered.',
    too_fast: 'Wait a moment before trying again.',
    orders_offline: 'The supply order system is offline.',
};
const bmErr = (e) => BM_ERRORS[e] || ('Failed: ' + (e || 'unknown error'));

class BusinessesManager {
    constructor() {
        this.page = 'overview';
        this.registry = null;      // server data, or { ok:false, error }
        this.supplies = null;
        this.selectedId = null;
        this.content = document.getElementById('businesses-content');
        if (!this.content) return;
        document.querySelectorAll('.businesses-nav-item').forEach(item => {
            item.addEventListener('click', () => {
                document.querySelectorAll('.businesses-nav-item').forEach(n => n.classList.remove('active'));
                item.classList.add('active');
                this.page = item.dataset.page;
                this.render();
            });
        });
        this.load();
    }

    async load() {
        this.content.innerHTML = '<div class="businesses-page"><div class="page-title">Loading…</div></div>';
        const [registry, supplies] = await Promise.all([bmPost('app/bm/registry', {}), bmPost('app/bm/supplies', {})]);
        this.registry = registry || { ok: false, error: 'registry_unavailable' };
        this.supplies = supplies || { ok: false, error: 'orders_offline' };
        this.render();
    }

    render() {
        const pages = {
            overview: () => this.renderOverview(),
            registry: () => this.renderRegistry(),
            compliance: () => this.renderCompliance(),
            taxes: () => this.renderTaxes(),
            audit: () => this.renderAudit(),
            supplies: () => this.renderSupplies(),
        };
        this.content.innerHTML = (pages[this.page] || pages.overview)();
        this.attach();
    }

    // Shown instead of a government page when the registry is not available to this player.
    gate(title) {
        if (this.registry && this.registry.ok) return null;
        return `<div class="businesses-page"><div class="page-title">${bmEsc(title)}</div>
            <div class="panel-card"><p>${bmEsc(bmErr(this.registry && this.registry.error))}</p>
            <p>"My supplies" shows your own business orders.</p></div></div>`;
    }

    badge(status) {
        const s = String(status || '').toLowerCase();
        let cls = 'neutral';
        if (['open', 'active', 'current', 'compliant', 'delivered', 'unpacked'].includes(s)) cls = 'active';
        else if (['closed', 'suspended', 'revoked', 'cancelled', 'failed'].includes(s)) cls = 'inactive';
        else if (['late', 'warning', 'expired', 'in_transit', 'assigned'].includes(s)) cls = 'warning';
        else if (['delinquent', 'non_compliant', 'flagged'].includes(s)) cls = 'error';
        return `<span class="status-badge ${cls}">${bmEsc(status)}</span>`;
    }

    renderOverview() {
        const g = this.gate('Business Oversight'); if (g) return g;
        const { stats, alerts, businesses } = this.registry;
        const top = [...businesses].sort((a, b) => b.revenueWeek - a.revenueWeek).slice(0, 5);
        const watch = businesses.filter(b => b.warnings.length).slice(0, 6);
        return `
            <div class="businesses-page">
                <div class="page-title">Business Oversight</div>
                <div class="overview-kpi-grid">
                    <div class="kpi-card"><div class="kpi-label">Registered</div><div class="kpi-value">${stats.totalBusinesses}</div><div class="kpi-subtext">In the city registry</div></div>
                    <div class="kpi-card"><div class="kpi-label">Open</div><div class="kpi-value">${stats.activeBusinesses}</div><div class="kpi-subtext">Not closed by the city</div></div>
                    <div class="kpi-card"><div class="kpi-label">Employees</div><div class="kpi-value">${stats.totalEmployees}</div><div class="kpi-subtext">As reported by businesses</div></div>
                    <div class="kpi-card"><div class="kpi-label">Revenue (7 days)</div><div class="kpi-value">${bmMoney(stats.revenueWeek)}</div><div class="kpi-subtext">Recorded sales</div></div>
                </div>
                <div class="overview-grid">
                    <div class="panel-card"><h3>Economic Summary</h3><div class="detail-list">
                        <div class="detail-row"><span>Revenue (24 hours)</span><strong>${bmMoney(stats.revenueToday)}</strong></div>
                        <div class="detail-row"><span>Revenue (30 days)</span><strong>${bmMoney(stats.revenueMonth)}</strong></div>
                    </div></div>
                    <div class="panel-card"><h3>Compliance Risk</h3><div class="risk-list">
                        <div class="risk-item danger">${alerts.unpaidTaxes} with unpaid bills</div>
                        <div class="risk-item warning">${alerts.unlicensed} without an active license</div>
                        <div class="risk-item warning">${alerts.incomeSpikes} with revenue more than doubled week on week</div>
                    </div></div>
                    <div class="panel-card"><h3>Top Revenue (7 days)</h3><table class="mini-table">
                        ${top.map(b => `<tr><td>${bmEsc(b.name)}</td><td>${bmMoney(b.revenueWeek)}</td></tr>`).join('') || '<tr><td>No sales recorded</td><td></td></tr>'}
                    </table></div>
                    <div class="panel-card"><h3>Watchlist</h3><div class="risk-list">
                        ${watch.map(b => `<div class="risk-item warning">${bmEsc(b.name)}: ${bmEsc(b.warnings.join(', '))}</div>`).join('') || '<div class="risk-item">Nothing flagged</div>'}
                    </div></div>
                </div>
            </div>`;
    }

    renderRegistry() {
        const g = this.gate('Business Registry'); if (g) return g;
        const list = this.registry.businesses;
        if (!this.selectedId && list[0]) this.selectedId = list[0].id;
        const rows = list.map(b => `
            <tr data-select="${bmEsc(b.id)}" class="${b.id === this.selectedId ? 'active-row' : ''}">
                <td>${bmEsc(b.name)}</td><td>${bmEsc(b.owner)}</td><td>${bmEsc(b.type)}</td>
                <td>${this.badge(b.status)}</td><td>${b.employees}</td><td>${bmMoney(b.revenueWeek)}</td>
                <td>${this.badge(b.licenseStatus)}</td><td>${this.badge(b.taxStatus)}</td>
            </tr>`).join('');
        return `
            <div class="businesses-page">
                <div class="page-title">Business Registry</div>
                <p style="opacity:.7">Businesses register themselves when they are bought or opened (stores, restaurants, mechanic shops).</p>
                <div class="registry-layout">
                    <div class="table-container"><table class="data-table">
                        <thead><tr><th>Business</th><th>Owner</th><th>Type</th><th>Status</th><th>Employees</th><th>Revenue (7d)</th><th>License</th><th>Bills</th></tr></thead>
                        <tbody>${rows || '<tr><td colspan="8">No registered businesses</td></tr>'}</tbody>
                    </table></div>
                    <div class="business-details-panel">${this.renderDetails(list.find(b => b.id === this.selectedId))}</div>
                </div>
            </div>`;
    }

    renderDetails(b) {
        if (!b) return '<div class="panel-card">Select a business</div>';
        const ownerActions = b.transferable
            ? `<button class="btn-primary" data-transfer="${bmEsc(b.id)}">${b.ownerId ? 'Transfer Ownership' : 'Assign Owner'}</button>
               ${b.ownerId ? `<button class="btn-secondary" data-remove="${bmEsc(b.id)}">Remove Owner</button>` : ''}`
            : '<p style="opacity:.7">Owned by its job; the job boss runs it.</p>';
        return `
            <div class="panel-card">
                <h3>${bmEsc(b.name)}</h3>
                <div class="detail-list">
                    <div class="detail-row"><span>Business ID</span><strong>${bmEsc(b.id)}</strong></div>
                    <div class="detail-row"><span>Owner</span><strong>${bmEsc(b.owner)}${b.ownerId ? ` (${bmEsc(b.ownerId)})` : ''}</strong></div>
                    <div class="detail-row"><span>Location</span><strong>${bmEsc(b.location)}</strong></div>
                    <div class="detail-row"><span>Account balance</span><strong>${bmMoney(b.balance)}</strong></div>
                    <div class="detail-row"><span>Revenue (30 days)</span><strong>${bmMoney(b.revenueMonth)} from ${b.sales30d} sales</strong></div>
                    <div class="detail-row"><span>Lifetime revenue</span><strong>${bmMoney(b.salesTotal)}</strong></div>
                    <div class="detail-row"><span>Taxes paid</span><strong>${bmMoney(b.taxesPaid)}</strong></div>
                    <div class="detail-row"><span>Unpaid bills</span><strong>${bmMoney(b.taxDebt)}</strong></div>
                    <div class="detail-row"><span>Compliance</span><strong>${bmEsc(b.compliance)}</strong></div>
                    <div class="detail-row"><span>Active licenses</span><strong>${bmEsc(b.permits.join(', ') || 'None')}</strong></div>
                </div>
                <div style="display:flex; gap:8px; margin:12px 0;">${ownerActions}</div>
                <h4>Recent government activity</h4>
                <table class="mini-table">${b.activityLog.map(a => `<tr><td>${bmEsc(a.date)}</td><td>${bmEsc(a.action)}</td><td>${bmEsc(a.actor)}</td></tr>`).join('') || '<tr><td>None recorded</td></tr>'}</table>
            </div>`;
    }

    renderCompliance() {
        const g = this.gate('Compliance'); if (g) return g;
        const flagged = this.registry.businesses.filter(b => b.warnings.length || b.licenseStatus.toLowerCase() !== 'active');
        return `
            <div class="businesses-page">
                <div class="page-title">Compliance</div>
                <p style="opacity:.7">Inspections, closures and licenses are managed in the government app on PF Computer.</p>
                <div class="table-container"><table class="data-table">
                    <thead><tr><th>Business</th><th>Status</th><th>License</th><th>Compliance</th><th>Issues</th></tr></thead>
                    <tbody>${flagged.map(b => `<tr><td>${bmEsc(b.name)}</td><td>${this.badge(b.status)}</td><td>${this.badge(b.licenseStatus)}</td><td>${this.badge(b.compliance)}</td><td>${bmEsc(b.warnings.join(', ') || 'No active license')}</td></tr>`).join('') || '<tr><td colspan="5">No compliance issues</td></tr>'}</tbody>
                </table></div>
            </div>`;
    }

    renderTaxes() {
        const g = this.gate('Taxes and Bills'); if (g) return g;
        const rows = [];
        this.registry.businesses.forEach(b => (b.bills || []).forEach(bill => rows.push({ b, bill })));
        const total = rows.reduce((s, r) => s + (Number(r.bill.owed) || 0), 0);
        return `
            <div class="businesses-page">
                <div class="page-title">Taxes and Bills</div>
                <div class="overview-kpi-grid">
                    <div class="kpi-card"><div class="kpi-label">Outstanding</div><div class="kpi-value">${bmMoney(total)}</div><div class="kpi-subtext">${rows.length} open bills</div></div>
                </div>
                <div class="table-container"><table class="data-table">
                    <thead><tr><th>Bill</th><th>Business</th><th>Type</th><th>Owed</th><th>Status</th><th>Due</th><th>Description</th></tr></thead>
                    <tbody>${rows.map(({ b, bill }) => `<tr><td>#${bmEsc(bill.id)}</td><td>${bmEsc(b.name)}</td><td>${bmEsc(bill.type)}</td><td>${bmMoney(bill.owed)}</td><td>${this.badge(bill.status)}</td><td>${bmEsc(bill.dueDate || '')}</td><td>${bmEsc(bill.description || '')}</td></tr>`).join('') || '<tr><td colspan="7">No unpaid business bills</td></tr>'}</tbody>
                </table></div>
            </div>`;
    }

    renderAudit() {
        const g = this.gate('Audit Log'); if (g) return g;
        return `
            <div class="businesses-page">
                <div class="page-title">Audit Log</div>
                <div class="table-container"><table class="data-table">
                    <thead><tr><th>Time</th><th>Action</th><th>By</th><th>Target</th></tr></thead>
                    <tbody>${this.registry.auditLog.map(a => `<tr><td>${bmEsc(a.timestamp)}</td><td>${bmEsc(a.action)}</td><td>${bmEsc(a.actor)}</td><td>${bmEsc(a.target)}</td></tr>`).join('') || '<tr><td colspan="4">No entries</td></tr>'}</tbody>
                </table></div>
            </div>`;
    }

    renderSupplies() {
        const s = this.supplies;
        if (!s || !s.ok) {
            return `<div class="businesses-page"><div class="page-title">My supplies</div><div class="panel-card">${bmEsc(bmErr(s && s.error))}</div></div>`;
        }
        const blocks = (s.buyers || []).map(b => `
            <div class="panel-card" style="margin-bottom:12px;">
                <h3>${bmEsc(b.label)} <span style="opacity:.6; font-size:12px;">${bmEsc(b.kind)}</span></h3>
                <table class="data-table">
                    <thead><tr><th>Order</th><th>Status</th><th>Method</th><th>Items</th><th>Total</th><th>Placed</th></tr></thead>
                    <tbody>${(b.orders || []).map(o => `<tr><td>#${bmEsc(o.id)}</td><td>${this.badge(o.status)}</td><td>${bmEsc(o.method)}</td>
                        <td>${bmEsc((o.items || []).map(i => `${i.quantity || i.amount || ''}× ${i.label || i.name || i.item || ''}`).join(', '))}</td>
                        <td>${bmMoney(o.total)}</td><td>${bmEsc(o.createdAt || '')}</td></tr>`).join('') || '<tr><td colspan="6">No orders yet</td></tr>'}</tbody>
                </table>
            </div>`).join('');
        return `
            <div class="businesses-page">
                <div class="page-title">My supplies</div>
                <p style="opacity:.7">Orders are placed and unpacked from the Business Manager on PF Computer. Truckers take deliveries in the trucking app.</p>
                ${blocks || '<div class="panel-card">You do not manage a business that can order supplies.</div>'}
                <button class="btn-secondary" data-reload="1">Refresh</button>
            </div>`;
    }

    attach() {
        const c = this.content;
        c.querySelectorAll('[data-select]').forEach(row => row.addEventListener('click', () => {
            this.selectedId = row.dataset.select;
            this.render();
        }));
        c.querySelectorAll('[data-transfer]').forEach(btn => btn.addEventListener('click', () => this.openTransfer(btn.dataset.transfer)));
        c.querySelectorAll('[data-remove]').forEach(btn => btn.addEventListener('click', () => {
            const b = this.registry.businesses.find(x => x.id === btn.dataset.remove);
            if (!b) return;
            this.showModal(`<h3>Remove Owner</h3><p class="warning-text">Remove ${bmEsc(b.owner)} as owner of <strong>${bmEsc(b.name)}</strong>?</p>`,
                () => this.transfer(b.id, null));
        }));
        c.querySelectorAll('[data-reload]').forEach(btn => btn.addEventListener('click', () => this.load()));
    }

    openTransfer(businessId) {
        const b = this.registry.businesses.find(x => x.id === businessId);
        if (!b) return;
        const options = (this.registry.citizens || []).map(ci => `<option value="${bmEsc(ci.citizenId)}">${bmEsc(ci.name)} (${bmEsc(ci.citizenId)})</option>`).join('');
        this.showModal(`
            <h3>${b.ownerId ? 'Transfer Ownership' : 'Assign Owner'}</h3>
            <p>New owner of <strong>${bmEsc(b.name)}</strong>:</p>
            <select class="form-input" id="bm-owner-select"><option value="">Online citizens…</option>${options}</select>
            <input class="form-input" id="bm-owner-id" placeholder="Or type a citizen ID" style="margin-top:8px;">
        `, () => {
            const typed = (document.getElementById('bm-owner-id').value || '').trim();
            const picked = document.getElementById('bm-owner-select').value;
            const ownerId = typed || picked;
            if (!ownerId) return this.toast('Choose a citizen.');
            this.transfer(b.id, ownerId);
        });
    }

    async transfer(businessId, ownerId) {
        const res = await bmPost('app/bm/transfer', { businessId, ownerId });
        if (res && res.ok) { this.toast('Ownership updated.'); this.load(); }
        else this.toast(bmErr(res && res.error));
    }

    toast(msg) {
        const el = document.createElement('div');
        el.className = 'modal-overlay';
        el.innerHTML = `<div class="modal-content"><p>${bmEsc(msg)}</p><div class="modal-actions"><button class="btn-primary">OK</button></div></div>`;
        el.querySelector('button').addEventListener('click', () => el.remove());
        document.body.appendChild(el);
    }

    showModal(content, onConfirm) {
        const modal = document.createElement('div');
        modal.className = 'modal-overlay';
        modal.innerHTML = `<div class="modal-content">${content}
            <div class="modal-actions"><button class="btn-secondary" data-cancel>Cancel</button><button class="btn-primary" data-confirm>Confirm</button></div></div>`;
        document.body.appendChild(modal);
        modal.querySelector('[data-cancel]').addEventListener('click', () => modal.remove());
        modal.querySelector('[data-confirm]').addEventListener('click', () => { onConfirm(); modal.remove(); });
    }
}
