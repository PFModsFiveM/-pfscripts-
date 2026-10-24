// Mechanic Job Apps Module for pf-tablet
// Integrates Work Orders, Cash Register, and Management apps directly into pf-tablet
(function() {
    // Register mechanic apps globally
    window.MechanicTablet = window.MechanicTablet || {};

    // Initialize mechanic state
    window.mechTabletState = {
        workOrderData: {},
        catalog: [],
        cart: [],
        stats: {},
        employees: [],
        isSearching: false
    };

    window.tabletMgmtState = {
        businessName: 'Los Santos Customs',
        last7Total: 0,
        last30Total: 0,
        todayTotal: 0,
        onDutyEmployees: 0,
        totalEmployees: 0,
        popularWork: { label: 'No data', count: 0 },
        activeTab: 'overview',
        salesChartData: [],
        employees: [],
        selectedEmployee: null,
        selectedTransaction: null,
        products: [],
        pricingEntries: [],
        pricingEditor: null,
        pricingNotice: null,
        pricingSearch: '',
        pricingCategoryFilter: 'All',
        mandatorySearch: '',
        mandatoryCharges: [],
        inventory: [],
        businessSettings: {},
        permissionLevel: 'employee'
    };

    window.posState = {
        business: null,
        items: {},
        mandatoryCharges: [],
        taxRate: 0,
        cart: [],
        activeCategory: 'All',
        search: '',
        paymentType: 'cash',
        posTab: 'sale',
        loadRequested: false
    };

    window.mechTabletRefs = window.mechTabletRefs || {
        cashContainer: null,
        managementContainer: null,
    };

    let lastWorkOrderSyncAt = 0;

    // POS Helper Functions
    function posCategories() {
        const cats = new Set(['All']);
        Object.values(window.posState.items || {}).forEach(it => {
            cats.add(it.category || 'Other');
        });
        return Array.from(cats).sort((a, b) => {
            if (a === 'All') return -1;
            if (b === 'All') return 1;
            return a.localeCompare(b);
        });
    }

    function posFilteredItems() {
        const list = [];
        const search = (window.posState.search || '').toLowerCase();
        const category = window.posState.activeCategory || 'All';
        Object.entries(window.posState.items || {}).forEach(([key, item]) => {
            const matchesCat = category === 'All' || item.category === category;
            const matchesSearch = !search || (item.label && item.label.toLowerCase().includes(search)) || key.toLowerCase().includes(search);
            if (matchesCat && matchesSearch) {
                list.push({ key, ...item });
            }
        });
        list.sort((a, b) => {
            const catCmp = (a.category || '').localeCompare(b.category || '');
            if (catCmp !== 0) return catCmp;
            return (a.label || '').localeCompare(b.label || '');
        });
        return list;
    }

    function getMandatoryChargeMap() {
        const map = {};
        for (const entry of (window.posState.mandatoryCharges || [])) {
            if (entry && entry.item) {
                map[entry.item] = entry;
            }
        }
        return map;
    }

    function syncMandatoryChargesInCart() {
        const mandatory = window.posState.mandatoryCharges || [];
        if (!Array.isArray(mandatory) || mandatory.length === 0) return;

        const cart = window.posState.cart || [];
        const byItem = {};
        cart.forEach(line => {
            if (line && line.item) byItem[line.item] = line;
        });

        for (const charge of mandatory) {
            if (!charge || !charge.item) continue;
            if (byItem[charge.item]) {
                byItem[charge.item].isMandatory = true;
                if (!Number.isFinite(byItem[charge.item].price)) {
                    byItem[charge.item].price = Number(charge.price || 0);
                }
            } else {
                cart.push({
                    item: charge.item,
                    label: charge.label || charge.item,
                    price: Number(charge.price || 0),
                    category: charge.category || 'General',
                    qty: 1,
                    isMandatory: true,
                });
            }
        }

        window.posState.cart = cart;
    }

    function applyPosCatalogFilters($content) {
        const search = (window.posState.search || '').trim().toLowerCase();
        const category = window.posState.activeCategory || 'All';
        let visible = 0;

        $content.find('.pos-item').each(function() {
            const $el = $(this);
            const label = String($el.data('label') || '').toLowerCase();
            const itemKey = String($el.data('item') || '').toLowerCase();
            const itemCategory = String($el.data('category') || 'General');
            const matchesSearch = !search || label.includes(search) || itemKey.includes(search);
            const matchesCategory = category === 'All' || itemCategory === category;
            const show = matchesSearch && matchesCategory;
            $el.toggle(show);
            if (show) visible += 1;
        });

        $content.find('.pos-empty-filter').remove();
        const $grid = $content.find('.pos-grid');
        if (visible === 0) {
            $grid.append('<div class="pos-empty pos-empty-filter">No products match your search/filter</div>');
        }
    }

    function getMandatorySelectableEntries() {
        const entries = window.tabletMgmtState.pricingEntries || [];
        const mandatoryCharges = Array.isArray(window.tabletMgmtState.mandatoryCharges) ? window.tabletMgmtState.mandatoryCharges : [];
        const mandatorySearch = String(window.tabletMgmtState.mandatorySearch || '').trim().toLowerCase();
        const mandatorySet = new Set(mandatoryCharges.map(m => m.item));

        return entries.filter((entry) => {
            if (mandatorySet.has(entry.item)) return false;
            const hay = `${entry.label || ''} ${entry.item || ''} ${entry.category || ''}`.toLowerCase();
            return !mandatorySearch || hay.includes(mandatorySearch);
        });
    }

    function renderMandatorySelectOptions(entries) {
        if (!entries.length) {
            return '<option value="">No items available</option>';
        }
        return entries.map(entry => `<option value="${entry.item}">${entry.label} • ${entry.category || 'General'} • €${Number(entry.price || 0).toLocaleString()}</option>`).join('');
    }

    function refreshMandatorySelect($scope) {
        const $container = $scope && $scope.length ? $scope : getOpenManagementContainers().first();
        if (!$container || !$container.length) return;
        const entries = getMandatorySelectableEntries();
        const $select = $container.find('#mgmt-mandatory-select');
        if (!$select.length) return;
        const prev = String($select.val() || '');
        $select.html(renderMandatorySelectOptions(entries));
        if (prev && entries.some(e => String(e.item) === prev)) {
            $select.val(prev);
        }
    }

    function drawManagementChartWithRetry($container, retriesLeft) {
        const chartData = window.tabletMgmtState?.salesChartData;
        const canvas = $container && $container.find ? $container.find('#tablet-sales-chart').get(0) : null;
        console.log('[Chart Retry] Attempt:', (8 - retriesLeft), 'Canvas:', canvas ? 'found' : 'missing', 'Data points:', chartData ? chartData.length : 0);
        
        if (!canvas || !Array.isArray(chartData)) {
            if ((retriesLeft || 0) > 0) {
                console.log('[Chart Retry] Canvas or data missing, retrying...');
                setTimeout(() => drawManagementChartWithRetry($container, (retriesLeft || 0) - 1), 150);
            }
            return;
        }

        const rect = canvas.getBoundingClientRect();
        console.log('[Chart Retry] Canvas size:', rect.width, 'x', rect.height);
        if ((rect.width < 20 || rect.height < 20) && (retriesLeft || 0) > 0) {
            console.log('[Chart Retry] Canvas too small, retrying...');
            setTimeout(() => drawManagementChartWithRetry($container, (retriesLeft || 0) - 1), 150);
            return;
        }

        console.log('[Chart Retry] Drawing chart now');
        drawTabletSalesChart(chartData, canvas);
    }

    function formatCountdown(secondsLeft) {
        const safe = Math.max(0, Number(secondsLeft) || 0);
        const mins = Math.floor(safe / 60);
        const secs = safe % 60;
        return `${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
    }

    // Work Orders Rendering
    function renderWorkOrders($content) {
        const now = Date.now();
        if (now - lastWorkOrderSyncAt > 4000) {
            lastWorkOrderSyncAt = now;
            setTimeout(function() { refreshWorkOrdersFromServer($content); }, 0);
        }

        const data = window.mechTabletState.workOrderData || {};
        const availableOrders = data.availableOrders || [];
        const acceptedOrders = data.acceptedOrders || [];
        const level = data.level || 1;
        const levelName = data.levelName || 'Apprentice';
        const xp = data.xp || 0;
        const nextLevelXP = data.nextLevelXP;
        const payMultiplier = data.payMultiplier || 1.0;
        const totalJobs = data.totalJobs || 0;
        const isSearching = data.isSearching !== undefined ? data.isSearching : (window.mechTabletState.isSearching || false);

        window.mechTabletState.isSearching = isSearching;

        let xpProgress = 0;
        let xpText = `${xp} XP`;
        let xpNeeded = 0;
        if (nextLevelXP) {
            const currentLevelXP = level > 1 ? (data.currentLevelXP || 0) : 0;
            const xpIntoLevel = xp - currentLevelXP;
            const xpNeededForLevel = nextLevelXP - currentLevelXP;
            xpProgress = Math.min((xpIntoLevel / xpNeededForLevel) * 100, 100);
            xpNeeded = nextLevelXP - xp;
            xpText = `${xp} / ${nextLevelXP} XP`;
        } else {
            xpProgress = 100;
            xpText = `${xp} XP (Max Level)`;
        }

        const availableHTML = availableOrders.length ? availableOrders.map(order => {
            const payout = Math.floor(order.basePay * payMultiplier);
            const hasExpiration = order.expiresAt !== null && order.expiresAt !== undefined;
            const currentTime = Math.floor(Date.now() / 1000);
            const timeLeft = hasExpiration ? Math.max(0, order.expiresAt - currentTime) : 0;
            const timerClass = timeLeft <= 10 ? 'timer-critical' : (timeLeft <= 25 ? 'timer-warning' : '');
            
            return `
                <tr class="job-row" data-order-id="${order.id}" data-difficulty="${order.difficulty}" ${hasExpiration ? `data-expires-at="${order.expiresAt}"` : ''}>
                    <td class="job-cell job-status">
                        <span class="status-badge" style="background: ${order.color};">${order.difficultyName}</span>
                    </td>
                    <td class="job-cell job-info">
                        <div class="job-title">${order.title}</div>
                        <div class="job-meta">
                            <span class="job-chip">🚗 ${order.vehicle}</span>
                            <span class="job-chip">👤 ${order.customer}</span>
                        </div>
                    </td>
                    <td class="job-cell job-reward">
                        <div class="reward-amount">$${payout.toLocaleString()}</div>
                        <div class="reward-xp">+${order.xpReward} XP</div>
                    </td>
                    ${hasExpiration ? `
                    <td class="job-cell job-timer">
                        <div class="timer-display work-order-timer ${timerClass}" data-expires-at="${order.expiresAt}">
                            <span class="timer-text">${formatCountdown(timeLeft)}</span>
                        </div>
                    </td>
                    ` : '<td class="job-cell job-timer">—</td>'}
                    <td class="job-cell job-action">
                        <button class="job-btn job-btn-accept" data-action="accept-order" data-order-id="${order.id}">Accept</button>
                    </td>
                </tr>
            `;
        }).join('') : '<tr><td colspan="5" class="no-jobs">No work orders available</td></tr>';

        const acceptedHTML = acceptedOrders.length ? acceptedOrders.map(order => {
            const payout = Math.floor(order.basePay * payMultiplier);
            return `
                <tr class="job-row active-job" data-order-id="${order.id}" data-difficulty="${order.difficulty}">
                    <td class="job-cell job-status">
                        <span class="status-badge active" style="background: ${order.color};">${order.difficultyName}</span>
                    </td>
                    <td class="job-cell job-info">
                        <div class="job-title">${order.title}</div>
                        <div class="job-meta">${order.vehicle} • ${order.customer} • ~${order.duration}s</div>
                    </td>
                    <td class="job-cell job-reward">
                        <div class="reward-amount">$${payout.toLocaleString()}</div>
                        <div class="reward-xp">+${order.xpReward} XP</div>
                    </td>
                    <td class="job-cell job-timer">
                        <span class="in-progress-tag">IN PROGRESS</span>
                    </td>
                    <td class="job-cell job-action">
                        <button class="job-btn job-btn-cancel" data-action="cancel-order" data-order-id="${order.id}">Cancel</button>
                    </td>
                </tr>
            `;
        }).join('') : '';

        $content.html(`
            <div class="work-container">
                <div class="work-header">
                    <div class="header-left">
                        <div class="header-title">Work Orders</div>
                        <div class="header-stats">
                            <span class="stat">Level ${level} ${levelName}</span>
                            <span class="stat-sep">•</span>
                            <span class="stat">${totalJobs} Jobs</span>
                            <span class="stat-sep">•</span>
                            <span class="stat"><span class="stat-value">${xpText}</span></span>
                        </div>
                        <div class="xp-progression">
                            <div class="xp-bar">
                                <div class="xp-fill" style="width: ${xpProgress}%"></div>
                            </div>
                            <div class="xp-label">${xpProgress.toFixed(0)}% to Level ${level + 1}</div>
                        </div>
                    </div>
                    <div class="header-right">
                        <button class="header-btn" data-action="work-refresh" title="Refresh">↻ Refresh</button>
                        ${isSearching ? `
                            <button class="header-btn btn-active" data-action="stop-search">⏸ Stop Search</button>
                        ` : `
                            <button class="header-btn" data-action="start-search">▶ Start Search</button>
                        `}
                    </div>
                </div>
                
                ${acceptedOrders.length > 0 ? `
                    <div class="jobs-section">
                        <div class="section-title">Active Jobs (${acceptedOrders.length}/3)</div>
                        <table class="jobs-table">
                            <thead>
                                <tr>
                                    <th>Priority</th>
                                    <th>Job Details</th>
                                    <th>Reward</th>
                                    <th>Status</th>
                                    <th>Action</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${acceptedHTML}
                            </tbody>
                        </table>
                    </div>
                ` : ''}
                
                <div class="jobs-section">
                    <div class="section-title">Available Jobs (${availableOrders.length})</div>
                    ${!isSearching && availableOrders.length === 0 ? `
                        <div class="empty-state">
                            <div class="empty-icon">🔍</div>
                            <div class="empty-text">No active search</div>
                            <div class="empty-subtext">Start searching to find available jobs</div>
                        </div>
                    ` : isSearching && availableOrders.length === 0 ? `
                        <div class="empty-state">
                            <div class="loading-spinner"></div>
                            <div class="empty-text">Searching for jobs...</div>
                        </div>
                    ` : `
                        <table class="jobs-table">
                            <thead>
                                <tr>
                                    <th>Priority</th>
                                    <th>Job Details</th>
                                    <th>Reward</th>
                                    <th>Timer</th>
                                    <th>Action</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${availableHTML}
                            </tbody>
                        </table>
                    `}
                </div>
            </div>
        `);
    }

    // Cash Register Rendering (POS)
    function renderCashRegister($content) {
        window.mechTabletRefs.cashContainer = $content;

        if ((!window.posState.items || Object.keys(window.posState.items).length === 0) && !window.posState.loadRequested) {
            window.posState.loadRequested = true;
            $.post('https://pf-mechanicjob/pos/open', JSON.stringify({}), function(resp) {
                const parsed = normalizeNuiResponse(resp);
                if (parsed && typeof parsed === 'object') {
                    window.posState.business = parsed.business || window.posState.business || 'mechanic';
                    window.posState.items = parsed.items || {};
                    window.posState.mandatoryCharges = Array.isArray(parsed.mandatoryCharges) ? parsed.mandatoryCharges : [];
                    window.posState.taxRate = Number(parsed.taxRate || 0);
                    window.posState.loadRequested = false;

                    window.tabletMgmtState.pricingEntries = mapPricingEntries(parsed.items || {});
                    if (parsed.canEdit !== undefined) {
                        window.tabletMgmtState.canEditPricing = parsed.canEdit === true;
                    }

                    renderCashRegister($content);
                    rerenderOpenManagementWindows();
                    return;
                }

                window.posState.loadRequested = false;
            }).fail(function() {
                window.posState.loadRequested = false;
            });
        }

        const categories = posCategories();
        const search = window.posState.search || '';
        const category = window.posState.activeCategory || 'All';
        const filtered = posFilteredItems();
        const cart = window.posState.cart || [];
        const cartKeys = new Set(cart.map(line => line.item));
        const mandatoryExtras = (window.posState.mandatoryCharges || []).filter(charge => charge && charge.item && !cartKeys.has(charge.item));
        const cartSubtotal = cart.reduce((sum, line) => sum + (line.price * line.qty), 0);
        const mandatorySubtotal = mandatoryExtras.reduce((sum, line) => sum + Number(line.price || 0), 0);
        const subtotal = cartSubtotal + mandatorySubtotal;
        const taxAmount = Math.floor(subtotal * (window.posState.taxRate || 0));
        const total = subtotal + taxAmount;

        const itemsHTML = filtered.length ? filtered.map(item => {
            const inCart = (cart || []).some(line => line.item === item.key);
            const categoryLabel = item.category || 'General';
            return `
                <div class="pos-item ${inCart ? 'added' : ''}" data-item="${item.key}" data-label="${String(item.label || '').replace(/"/g, '&quot;')}" data-category="${String(item.category || 'General').replace(/"/g, '&quot;')}">
                    <div class="pos-item-top">
                        <div class="pos-item-price">€${(item.price || 0).toLocaleString()}</div>
                        ${inCart ? '<span class="pos-item-added">Added</span>' : ''}
                    </div>
                    <div class="pos-item-name">${item.label}</div>
                    <div class="pos-item-meta">
                        <span class="pos-item-category">${categoryLabel}</span>
                    </div>
                </div>
            `;
        }).join('') : '<div class="pos-empty">📦 No items in catalog</div>';

        const cartHTML = cart.length ? cart.map(line => `
            <div class="pos-cart-line" data-item="${line.item}">
                <div class="pos-line-header">
                    <div class="pos-line-label">${line.label} ${line.isMandatory ? '<span class="pos-tag-mandatory">Mandatory</span>' : ''}</div>
                    <div class="pos-line-actions">
                        <div class="pos-line-price">€${(line.price * line.qty).toLocaleString()}</div>
                        ${line.isMandatory ? '' : `<button class="btn-remove-item" data-item="${line.item}" title="Remove">✕</button>`}
                    </div>
                </div>
                <div class="pos-line-controls">
                    ${line.isMandatory
                        ? `<div class="line-unit">Automatically added to every invoice</div>`
                        : `<div class="qty-box">
                            <button class="qty-btn" data-action="dec">−</button>
                            <span class="qty-display">${line.qty}x</span>
                            <button class="qty-btn" data-action="inc">+</button>
                        </div>`}
                    <div class="line-unit">@ €${(line.price).toLocaleString()}</div>
                </div>
            </div>
        `).join('') : '<div class="pos-empty-cart">🛒 Cart is empty</div>';

        const mandatorySummary = mandatoryExtras.length ? `
            <div class="pos-mandatory-summary">
                <div class="pos-mandatory-title">Mandatory Charges (auto-applied)</div>
                ${mandatoryExtras.map(line => `
                    <div class="pos-mandatory-row">
                        <span>${line.label || line.item}</span>
                        <strong>€${Number(line.price || 0).toLocaleString()}</strong>
                    </div>
                `).join('')}
            </div>
        ` : '';

        const payCash = window.posState.paymentType === 'cash';
        const receiptData = window.posState.receiptData || null;

        $content.html(`
            <div class="pos-container">
                <div class="pos-main">
                    <div class="pos-ios-header">
                        <div class="pos-ios-title">Cash Register</div>
                        <div class="pos-ios-subtitle">${window.posState.business || 'Mechanic Shop'}</div>
                    </div>
                    <div class="pos-toolbar">
                        <input id="pos-search" type="text" class="pos-search" placeholder="Search products" value="${search}">
                    </div>
                    <div class="pos-filter-tabs">${categories.map(cat => `
                        <button class="pos-category ${category === cat ? 'active' : ''}" data-cat="${cat}">${cat}</button>
                    `).join('')}</div>
                    <div class="pos-grid">${itemsHTML}</div>
                </div>
                <div class="pos-sidebar">
                    <div class="pos-header">
                        <div class="pos-title-block">
                            <h2 class="pos-title">Invoice</h2>
                            <p class="pos-business">${window.posState.business || 'Mechanic Shop'}</p>
                        </div>
                    </div>
                    <div class="pos-cart-items">${cartHTML}</div>
                    ${mandatorySummary}
                    <div class="pos-totals">
                        <div class="total-row">
                            <span class="total-label">Subtotal</span>
                            <span class="total-value">€${subtotal.toLocaleString()}</span>
                        </div>
                        <div class="total-row">
                            <span class="total-label">Tax (${Math.round((window.posState.taxRate || 0)*100)}%)</span>
                            <span class="total-value">€${taxAmount.toLocaleString()}</span>
                        </div>
                        <div class="total-row total-final">
                            <span class="total-label">Total Due</span>
                            <span class="total-value-final">€${total.toLocaleString()}</span>
                        </div>
                    </div>
                    <div class="pos-payment-section">
                        <div class="payment-label">Payment Method</div>
                        <div class="payment-buttons">
                            <button class="payment-btn ${payCash ? 'active' : ''}" data-pay="cash">💵 Cash</button>
                            <button class="payment-btn ${!payCash ? 'active' : ''}" data-pay="card">💳 Card</button>
                        </div>
                    </div>
                    <div class="pos-charge-buttons">
                        <button class="btn-charge-now" ${cart.length ? '' : 'disabled'}>Charge Customer</button>
                        <button class="btn-charge-self" ${cart.length ? '' : 'disabled'}>Charge Self</button>
                    </div>
                </div>

                ${receiptData ? `
                    <div class="pos-receipt-modal">
                        <div class="pos-receipt-backdrop"></div>
                        <div class="pos-receipt-sheet">
                            <div class="pos-receipt-header">
                                <div class="pos-receipt-title">${receiptData.shopName || 'Mechanic Shop'}</div>
                                <div class="pos-receipt-subtitle">Service Receipt</div>
                            </div>

                            <div class="pos-receipt-meta">
                                <div><span>Receipt #</span><strong>${receiptData.receiptId || 'N/A'}</strong></div>
                                <div><span>Date/Time</span><strong>${receiptData.createdAtText || 'Unknown'}</strong></div>
                                <div><span>Charged By</span><strong>${receiptData.chargedBy || 'Unknown'}</strong></div>
                                <div><span>Payment</span><strong>${String(receiptData.paymentType || '').toUpperCase() || 'N/A'}</strong></div>
                            </div>

                            <div class="pos-receipt-divider"></div>
                            <div class="pos-receipt-items">
                                ${(Array.isArray(receiptData.items) && receiptData.items.length) ? receiptData.items.map((entry) => `
                                    <div class="pos-receipt-item-row">
                                        <div class="pos-receipt-item-label">${entry.label || entry.item || 'Item'} <span>x${Number(entry.qty || 1)}</span></div>
                                        <div class="pos-receipt-item-price">€${Number(entry.lineTotal || 0).toLocaleString()}</div>
                                    </div>
                                    <div class="pos-receipt-item-sub">@ €${Number(entry.unitPrice || 0).toLocaleString()} each</div>
                                `).join('') : '<div class="pos-receipt-empty">No line items</div>'}
                            </div>

                            <div class="pos-receipt-divider"></div>
                            <div class="pos-receipt-totals">
                                <div><span>Subtotal</span><strong>€${Number(receiptData.subtotal || 0).toLocaleString()}</strong></div>
                                <div><span>Tax</span><strong>€${Number(receiptData.tax || 0).toLocaleString()}</strong></div>
                                <div class="pos-receipt-total"><span>Total</span><strong>€${Number(receiptData.total || 0).toLocaleString()}</strong></div>
                            </div>

                            <button class="pos-receipt-close" type="button">Close</button>
                        </div>
                    </div>
                ` : ''}
            </div>
        `);

        applyPosCatalogFilters($content);
    }

    // Management Rendering
    function renderManagement($content) {
        window.mechTabletRefs.managementContainer = $content;

        const data = window.tabletMgmtState;
        const activeTab = (data.activeTab || 'overview');
        const tabActive = (tab) => activeTab === tab ? 'active' : '';
        const paneActive = (tab) => activeTab === tab ? 'active' : '';
        const paneDisplay = (tab) => activeTab === tab ? '' : 'style="display: none;"';
        
        if (!data) {
            $content.html('<div class="work-empty">No management data available</div>');
            return;
        }

        const html = `
            <div class="management-container">
                <div class="management-header">
                    <div class="work-header-content">
                        <div class="work-title-section">
                            <div class="work-icon-large">📊</div>
                            <div>
                                <div class="work-title">Management</div>
                                <div class="work-subtitle">${data.businessName || 'Business Overview'}</div>
                            </div>
                        </div>
                    </div>
                </div>
                <div class="management-tabs">
                    <div class="management-tab ${tabActive('overview')}" data-tab="overview">Overview</div>
                    <div class="management-tab ${tabActive('employees')}" data-tab="employees">Employees</div>
                    <div class="management-tab ${tabActive('inventory')}" data-tab="inventory">Inventory</div>
                    <div class="management-tab ${tabActive('pricing')}" data-tab="pricing">Pricing</div>
                    <div class="management-tab ${tabActive('mandatory')}" data-tab="mandatory">Mandatory Charges</div>
                    <div class="management-tab ${tabActive('settings')}" data-tab="settings">Settings</div>
                </div>
                <div class="management-content">
                    <div class="tab-pane ${paneActive('overview')}" data-pane="overview" ${paneDisplay('overview')}>
                        ${renderTabletOverview(data)}
                    </div>
                    <div class="tab-pane ${paneActive('employees')}" data-pane="employees" ${paneDisplay('employees')}>
                        ${renderTabletEmployees(data)}
                    </div>
                    <div class="tab-pane ${paneActive('inventory')}" data-pane="inventory" ${paneDisplay('inventory')}>
                        ${renderTabletInventory(data)}
                    </div>
                    <div class="tab-pane ${paneActive('pricing')}" data-pane="pricing" ${paneDisplay('pricing')}>
                        ${renderTabletPricing(data)}
                    </div>
                    <div class="tab-pane ${paneActive('mandatory')}" data-pane="mandatory" ${paneDisplay('mandatory')}>
                        ${renderTabletMandatoryCharges(data)}
                    </div>
                    <div class="tab-pane ${paneActive('settings')}" data-pane="settings" ${paneDisplay('settings')}>
                        ${renderTabletSettings(data)}
                    </div>
                </div>
            </div>
        `;

        $content.html(html);
        initializeManagementHandlers();

        const now = Date.now();
        const lastFetchAt = Number(window.tabletMgmtState._lastFetchAt || 0);
        const needsFetch = !window.tabletMgmtState.business || (now - lastFetchAt > 3000);
        
        if (needsFetch) {
            window.tabletMgmtState._lastFetchAt = now;

            $.post('https://pf-mechanicjob/management:getOverview', JSON.stringify({}), function(result) {
                const parsed = normalizeNuiResponse(result);
                console.log('[Management] Overview data received:', parsed);
                if (parsed && typeof parsed === 'object') {
                    window.tabletMgmtState = { ...window.tabletMgmtState, ...parsed };
                    console.log('[Management] Updated state:', window.tabletMgmtState);
                    rerenderOpenManagementWindows();
                }
            });
            $.post('https://pf-mechanicjob/management:getGraph', JSON.stringify({}), function(points) {
                const parsed = normalizeNuiResponse(points);
                console.log('[Management] Graph data received:', parsed);
                if (Array.isArray(parsed)) {
                    window.tabletMgmtState.salesChartData = parsed;
                    rerenderOpenManagementWindows();
                    setTimeout(() => drawManagementChartWithRetry($content, 8), 150);
                }
            });
            loadPricingData();
        }

        setTimeout(() => {
            if (activeTab === 'overview') {
                drawManagementChartWithRetry($content, 8);
            }
        }, 200);
    }

    function renderTabletOverview(data) {
        console.log('[Overview Render] Data:', data);
        const formatCurrency = (val) => '$' + (parseInt(val || 0).toLocaleString());
        const last7 = formatCurrency(data.last7Total || 0);
        const last30 = formatCurrency(data.last30Total || 0);
        const today = formatCurrency(data.todayTotal || 0);
        const onDuty = Number(data.onDutyEmployees || 0);
        const totalEmployees = Number(data.totalEmployees || 0);
        const popularLabel = (data.popularWork && data.popularWork.label) || 'No data';
        const popularCount = Number((data.popularWork && data.popularWork.count) || 0);
        console.log('[Overview Render] Formatted values - Last7:', last7, 'Last30:', last30, 'Today:', today, 'OnDuty:', onDuty, '/', totalEmployees, 'Popular:', popularLabel, '(', popularCount, ')');

        return `
            <div class="mgmt-stat-cards">
                <div class="mgmt-stat-card">
                    <div class="mgmt-stat-label">Last 7 Days</div>
                    <div class="mgmt-stat-value">${last7}</div>
                </div>
                <div class="mgmt-stat-card">
                    <div class="mgmt-stat-label">Last 30 Days</div>
                    <div class="mgmt-stat-value">${last30}</div>
                </div>
                <div class="mgmt-stat-card">
                    <div class="mgmt-stat-label">Today's Sales</div>
                    <div class="mgmt-stat-value">${today}</div>
                </div>
                <div class="mgmt-stat-card">
                    <div class="mgmt-stat-label">On Duty</div>
                    <div class="mgmt-stat-value">${onDuty} / ${totalEmployees}</div>
                </div>
                <div class="mgmt-stat-card">
                    <div class="mgmt-stat-label">Most Popular Work</div>
                    <div class="mgmt-stat-value">${popularLabel}</div>
                    <div class="mgmt-stat-sub">${popularCount} sold (30d)</div>
                </div>
            </div>
            <div class="mgmt-chart-panel">
                <div class="mgmt-panel-title">Sales (Last 30 Days)</div>
                <div class="mgmt-chart-wrap">
                    <canvas id="tablet-sales-chart"></canvas>
                </div>
            </div>
        `;
    }

    function renderTabletEmployees(data) {
        const employees = data.employees || [];
        const selected = data.selectedEmployee || null;
        const selectedTx = data.selectedTransaction || null;

        const formatDateTime = (value) => {
            if (!value) return 'Never';
            const dt = new Date(value);
            if (Number.isNaN(dt.getTime())) return String(value);
            return dt.toLocaleString();
        };

        const rows = employees.length ? employees.map(emp => `
            <div class="mgmt-employee-row">
                <div class="mgmt-emp-info">
                    <img src="${emp.avatar || ''}" alt="${emp.name || 'Employee'}" class="mgmt-emp-avatar" onerror="this.style.display='none'" />
                    <div class="mgmt-emp-name">${emp.name}</div>
                    <div class="mgmt-emp-id">${(emp.citizenid || '').substring(0, 12)}${(emp.citizenid || '').length > 12 ? '...' : ''}</div>
                </div>
                <div class="mgmt-emp-role">RANK ${Number(emp.rank || emp.grade || 0)} • ${(emp.role || 'employee').toUpperCase()}</div>
                <div class="mgmt-emp-sales">$${(emp.totalSales || 0).toLocaleString()}</div>
                <div class="mgmt-emp-actions">
                    <button class="mgmt-btn-view-stats" data-citizenid="${emp.citizenid}">View</button>
                </div>
            </div>
        `).join('') : '<div class="work-empty"><div class="empty-icon">👥</div><div class="empty-text">No Employees</div><div class="empty-subtext">Hire employees to get started</div></div>';

        const profilePanel = selected ? `
            <div class="mgmt-profile-panel">
                <div class="mgmt-profile-header">
                    <img src="${selected.avatar || ''}" alt="${selected.name || 'Employee'}" class="mgmt-profile-avatar" onerror="this.style.display='none'" />
                    <div>
                        <div class="mgmt-profile-name">${selected.name}</div>
                        <div class="mgmt-profile-meta">Rank ${Number(selected.rank || selected.grade || 0)} • ${(selected.role || 'employee').toUpperCase()}</div>
                        <div class="mgmt-profile-meta">Last Online: ${formatDateTime(selected.lastOnline)}</div>
                    </div>
                </div>
                <div class="mgmt-profile-stats">
                    <div class="mgmt-profile-stat"><span>Work Orders</span><strong>${Number(selected.completedWorkOrders || 0)}</strong></div>
                    <div class="mgmt-profile-stat"><span>Customer Charges</span><strong>${Number(selected.customerCharges || 0)}</strong></div>
                    <div class="mgmt-profile-stat"><span>Total Sales</span><strong>$${Number(selected.totalSales || 0).toLocaleString()}</strong></div>
                </div>
                <div class="mgmt-profile-actions">
                    <button class="mgmt-btn-promote" data-citizenid="${selected.citizenid}" ${Number(selected.rank || selected.grade || 0) >= 4 ? 'disabled' : ''}>Promote</button>
                    <button class="mgmt-btn-demote" data-citizenid="${selected.citizenid}" ${Number(selected.rank || selected.grade || 0) <= 0 ? 'disabled' : ''}>Demote</button>
                    <button class="mgmt-btn-fire" data-citizenid="${selected.citizenid}">Fire</button>
                </div>
                <div class="mgmt-profile-history-title">Charge History</div>
                <div class="mgmt-profile-history">
                    ${Array.isArray(selected.transactions) && selected.transactions.length ? selected.transactions.slice(0, 60).map(tx => `
                        <div class="mgmt-history-row">
                            <div class="mgmt-history-main">
                                <div class="mgmt-history-customer">${tx.customer || 'Unknown Customer'}</div>
                                <div class="mgmt-history-meta">${formatDateTime(tx.when)} • ${tx.where || 'Unknown location'}</div>
                            </div>
                            <div class="mgmt-history-amount">$${Number(tx.total || 0).toLocaleString()}</div>
                            <button class="mgmt-btn-view-transaction" data-txid="${tx.id}">Details</button>
                        </div>
                    `).join('') : '<div class="mgmt-history-empty">No transactions recorded for this employee.</div>'}
                </div>
            </div>
        ` : '';

        const transactionPanel = (selected && selectedTx) ? `
            <div class="mgmt-tx-panel">
                <div class="mgmt-profile-history-title">Transaction Detail</div>
                <div class="mgmt-tx-grid">
                    <div><span>ID</span><strong>${selectedTx.id || 'N/A'}</strong></div>
                    <div><span>Customer</span><strong>${selectedTx.customer || 'Unknown'}</strong></div>
                    <div><span>Vehicle</span><strong>${(selectedTx.vehicle && selectedTx.vehicle.model) || 'N/A'} / ${(selectedTx.vehicle && selectedTx.vehicle.plate) || 'N/A'}</strong></div>
                    <div><span>When / Where</span><strong>${formatDateTime(selectedTx.when)} • ${selectedTx.where || 'Unknown'}</strong></div>
                    <div><span>Subtotal</span><strong>$${Number(selectedTx.subtotal || 0).toLocaleString()}</strong></div>
                    <div><span>Tax</span><strong>$${Number(selectedTx.tax || 0).toLocaleString()}</strong></div>
                    <div><span>Total</span><strong>$${Number(selectedTx.total || 0).toLocaleString()}</strong></div>
                    <div><span>Payment</span><strong>${selectedTx.paymentType || 'cash'}</strong></div>
                </div>
                <div class="mgmt-tx-items-title">Items</div>
                <div class="mgmt-tx-items">
                    ${Array.isArray(selectedTx.items) && selectedTx.items.length ? selectedTx.items.map(item => `
                        <div class="mgmt-tx-item-row">
                            <div>${item.label || item.item || 'Item'} x${Number(item.qty || 1)}</div>
                            <div>$${Number(item.lineTotal || (Number(item.unitPrice || item.price || 0) * Number(item.qty || 1))).toLocaleString()}</div>
                        </div>
                    `).join('') : '<div class="mgmt-history-empty">No item details captured.</div>'}
                </div>
            </div>
        ` : '';

        return `
            <div class="mgmt-hire-panel">
                <input type="text" id="tablet-hire-id" placeholder="Enter citizenid to hire (offline supported)" class="mgmt-input">
                <button id="tablet-hire-btn" class="mgmt-btn-primary">Hire by CitizenID</button>
            </div>
            <div class="mgmt-employees-list">
                ${rows}
            </div>
            ${profilePanel}
            ${transactionPanel}
        `;
    }

    function renderTabletInventory(data) {
        const inventory = data.inventory || [];
        
        if (!inventory.length) {
            return `
                <div class="work-empty">
                    <div class="empty-icon">📦</div>
                    <div class="empty-text">No Inventory</div>
                    <div class="empty-subtext">Stock items will appear here</div>
                </div>
            `;
        }

        const rows = inventory.map(item => {
            const qtyClass = (item.quantity || 0) === 0 ? 'mgmt-qty-empty' : 'mgmt-qty-ok';
            return `
                <div class="mgmt-inv-row">
                    <div class="mgmt-inv-name">${item.product_name}</div>
                    <div class="mgmt-inv-id">#${item.product_id}</div>
                    <div class="mgmt-inv-qty ${qtyClass}">${item.quantity || 0}</div>
                </div>
            `;
        }).join('');

        return `<div class="mgmt-inventory-list">${rows}</div>`;
    }

    function renderTabletPricing(data) {
        const entries = data.pricingEntries || [];
        const canEdit = data.canEditPricing === true;
        const editor = data.pricingEditor || null;
        const notice = data.pricingNotice || null;
        const searchText = String(data.pricingSearch || '').trim().toLowerCase();
        const activeCategoryFilter = data.pricingCategoryFilter || 'All';
        const mandatoryCharges = Array.isArray(data.mandatoryCharges) ? data.mandatoryCharges : [];
        const categories = Array.from(new Set((entries || []).map(e => String(e.category || 'General').trim()).filter(Boolean)));
        if (!categories.length) categories.push('General');
        ['General', 'Parts', 'Labor', 'Fluids', 'Wheels', 'Body', 'Diagnostics'].forEach(cat => {
            if (!categories.includes(cat)) categories.push(cat);
        });
        categories.sort((a, b) => a.localeCompare(b));

        const filteredEntries = (entries || []).filter((entry) => {
            const byCategory = activeCategoryFilter === 'All' || (entry.category || 'General') === activeCategoryFilter;
            const hay = `${entry.label || ''} ${entry.item || ''} ${entry.category || ''}`.toLowerCase();
            const bySearch = !searchText || hay.includes(searchText);
            return byCategory && bySearch;
        });

        const noticeHtml = notice ? `<div class="mgmt-pricing-notice ${notice.type === 'error' ? 'error' : 'success'}">${notice.text}</div>` : '';

        if (!entries.length) {
            return `
                <div class="work-empty">
                    <div class="empty-icon">💳</div>
                    <div class="empty-text">No Register Items</div>
                    <div class="empty-subtext">Default pricing will load from register config</div>
                    ${canEdit ? '<button class="mgmt-btn-add-item">Add Item</button>' : ''}
                </div>
                ${noticeHtml}
                ${renderPricingEditor(editor, canEdit, categories)}
            `;
        }

        const rows = filteredEntries.map(entry => `
            <div class="mgmt-pricing-row">
                <div class="mgmt-pricing-name">${entry.label}</div>
                <div class="mgmt-pricing-info">
                    <div class="mgmt-price-item">
                        <div class="mgmt-price-label">Category</div>
                        <div class="mgmt-price-value">${entry.category || 'General'}</div>
                    </div>
                    <div class="mgmt-price-item">
                        <div class="mgmt-price-label">Current</div>
                        <div class="mgmt-price-value">€${(entry.price || 0).toLocaleString()}</div>
                    </div>
                </div>
                <div class="mgmt-pricing-actions">
                    <button class="mgmt-btn-price-edit" data-item="${entry.item}" data-productname="${entry.label}" data-price="${entry.price || 0}" data-category="${entry.category || ''}" data-custom="${entry.isCustom ? '1' : '0'}" ${canEdit ? '' : 'disabled'}>${canEdit ? 'Edit' : 'Boss Only'}</button>
                    <button class="mgmt-btn-remove-item" data-item="${entry.item}" data-productname="${entry.label}" ${canEdit ? '' : 'disabled'}>${canEdit ? 'Remove' : 'Boss Only'}</button>
                </div>
            </div>
        `).join('');

        const categoryTabs = ['All', ...categories].map(cat => `
            <button class="mgmt-pricing-cat ${activeCategoryFilter === cat ? 'active' : ''}" data-cat="${cat}">${cat}</button>
        `).join('');

        return `
            <div class="mgmt-pricing-toolbar">
                <button class="mgmt-btn-pricing-refresh">Refresh</button>
                <button class="mgmt-btn-pricing-reset" ${canEdit ? '' : 'disabled'}>${canEdit ? 'Reset to Defaults' : 'Boss Only'}</button>
                <button class="mgmt-btn-add-item" ${canEdit ? '' : 'disabled'}>${canEdit ? 'Add Item' : 'Boss Only'}</button>
            </div>
            <div class="mgmt-pricing-filters">
                <input id="mgmt-pricing-search" class="mgmt-input" type="text" placeholder="Search items" value="${data.pricingSearch || ''}">
                <div class="mgmt-pricing-cats">${categoryTabs}</div>
            </div>
            <div class="mgmt-pricing-list">${rows || '<div class="work-empty">No items found for this filter.</div>'}</div>

            ${noticeHtml}
            ${renderPricingEditor(editor, canEdit, categories)}
        `;
    }

    function renderTabletMandatoryCharges(data) {
        const canEdit = data.canEditPricing === true;
        const mandatoryCharges = Array.isArray(data.mandatoryCharges) ? data.mandatoryCharges : [];
        const available = getMandatorySelectableEntries();

        return `
            <div class="mgmt-mandatory-panel">
                <div class="mgmt-panel-title">Mandatory Charges</div>
                <div class="mgmt-mandatory-add">
                    <input id="mgmt-mandatory-search" class="mgmt-input" type="text" placeholder="Search charge to add" value="${data.mandatorySearch || ''}">
                    <select id="mgmt-mandatory-select" class="mgmt-form-input">
                        ${renderMandatorySelectOptions(available)}
                    </select>
                    <button id="mgmt-mandatory-add-btn" class="mgmt-btn-primary" ${canEdit ? '' : 'disabled'}>${canEdit ? 'Add Mandatory' : 'Boss Only'}</button>
                </div>
                <div class="mgmt-mandatory-list">
                    ${(mandatoryCharges.length ? mandatoryCharges : []).map(charge => `
                        <div class="mgmt-mandatory-row">
                            <div>
                                <div class="mgmt-pricing-name">${charge.label || charge.item}</div>
                                <div class="mgmt-history-meta">${charge.category || 'General'} • €${Number(charge.price || 0).toLocaleString()}</div>
                            </div>
                            <button class="mgmt-btn-mandatory-remove mgmt-mandatory-remove" data-item="${charge.item}" ${canEdit ? '' : 'disabled'}>${canEdit ? 'Remove' : 'Boss Only'}</button>
                        </div>
                    `).join('') || '<div class="mgmt-history-empty">No mandatory charges configured.</div>'}
                </div>
            </div>
        `;
    }

    function renderPricingEditor(editor, canEdit, categories) {
        if (!canEdit || !editor) return '';

        const modeLabel = editor.mode === 'add' ? 'Add Register Item' : 'Edit Register Item';
        const optionsHtml = (categories || ['General']).map(cat => {
            const selected = String(editor.category || 'General') === cat ? 'selected' : '';
            return `<option value="${cat}" ${selected}>${cat}</option>`;
        }).join('');

        return `
            <div class="mgmt-pricing-modal">
                <div class="mgmt-pricing-modal-backdrop"></div>
                <div class="mgmt-pricing-modal-card">
                    <div class="mgmt-pricing-modal-head">
                        <div class="mgmt-pricing-editor-title">${modeLabel}</div>
                        <button class="mgmt-btn-editor-close" type="button">✕</button>
                    </div>
                    <div class="mgmt-pricing-editor-grid">
                        <div class="mgmt-form-group">
                            <label class="mgmt-form-label">Label</label>
                            <input type="text" id="mgmt-editor-label" class="mgmt-form-input" value="${editor.label || ''}">
                        </div>
                        <div class="mgmt-form-group">
                            <label class="mgmt-form-label">Category</label>
                            <select id="mgmt-editor-category" class="mgmt-form-input">${optionsHtml}</select>
                        </div>
                        <div class="mgmt-form-group">
                            <label class="mgmt-form-label">Price</label>
                            <input type="number" id="mgmt-editor-price" min="0" class="mgmt-form-input" value="${Number(editor.price || 0)}">
                        </div>
                    </div>
                    <div class="mgmt-pricing-editor-actions">
                        <button class="mgmt-btn-editor-cancel">Cancel</button>
                        <button class="mgmt-btn-editor-save">Save</button>
                    </div>
                </div>
            </div>
        `;
    }

    function setPricingNotice(text, type) {
        window.tabletMgmtState.pricingNotice = { text: String(text || ''), type: type === 'error' ? 'error' : 'success' };
        rerenderOpenManagementWindows();
        clearTimeout(window.tabletMgmtState._pricingNoticeTimer);
        window.tabletMgmtState._pricingNoticeTimer = setTimeout(function() {
            window.tabletMgmtState.pricingNotice = null;
            rerenderOpenManagementWindows();
        }, 2200);
    }

    function slugifyItemKey(label) {
        const base = String(label || '')
            .toLowerCase()
            .replace(/[^a-z0-9]+/g, '_')
            .replace(/^_+|_+$/g, '')
            .replace(/_+/g, '_');

        if (base && base.length >= 2) return base;
        return `item_${Date.now()}`;
    }

    function renderTabletSettings(data) {
        const settings = data.businessSettings || {};
        return `
            <div class="mgmt-settings-panel">
                <div>
                    <h3 style="color: #cbd5e1; font-size: 14px; margin-bottom: 14px; text-transform: uppercase; letter-spacing: 0.5px;">Business Details</h3>
                    <div class="mgmt-form-group">
                        <label class="mgmt-form-label">Business Name</label>
                        <input type="text" id="mgmt-biz-name" value="${settings.business_name || 'Los Santos Customs'}" class="mgmt-form-input">
                    </div>
                    <div class="mgmt-form-group">
                        <label class="mgmt-form-label">Blip Name</label>
                        <input type="text" id="mgmt-blip-name" value="${settings.blip_name || 'Customs Shop'}" class="mgmt-form-input">
                    </div>
                    <div class="mgmt-form-group">
                        <label class="mgmt-form-label">Blip Color</label>
                        <input type="number" id="mgmt-blip-color" min="0" max="85" value="${Number(settings.blip_color || 3)}" class="mgmt-form-input">
                    </div>
                    <button id="mgmt-save-settings" class="mgmt-save-button">Save Settings</button>
                </div>
                <div>
                    <h3 style="color: #cbd5e1; font-size: 14px; margin-bottom: 14px; text-transform: uppercase; letter-spacing: 0.5px;">Location Placement</h3>
                    <p style="color: #94a3b8; font-size: 11px; margin-bottom: 12px;">Set the positions for your business locations:</p>
                    <div class="mgmt-location-buttons">
                        <button id="mgmt-set-stash" class="mgmt-btn-location">📦 Stash</button>
                        <button id="mgmt-set-locker" class="mgmt-btn-location">🔐 Locker</button>
                        <button id="mgmt-set-duty" class="mgmt-btn-location">📋 Duty</button>
                    </div>
                </div>
            </div>
        `;
    }

    function renderSettings($content) {
        $content.html(`
            <div class="management-container">
                <div class="management-header">
                    <div class="work-header-content">
                        <div class="work-title-section">
                            <div class="work-icon-large">⚙️</div>
                            <div>
                                <div class="work-title">Settings</div>
                                <div class="work-subtitle">System Configuration</div>
                            </div>
                        </div>
                    </div>
                </div>
                <div class="work-empty">Settings coming soon</div>
            </div>
        `);
    }

    function initializeManagementHandlers() {
        $(document).off('click.mechmgmt', '.management-tab').on('click.mechmgmt', '.management-tab', function() {
            const tab = $(this).data('tab');
            const $management = $(this).closest('.management-container');
            $management.find('.management-tab').removeClass('active');
            $(this).addClass('active');
            $management.find('.tab-pane').hide().removeClass('active');
            $management.find(`.tab-pane[data-pane="${tab}"]`).show().addClass('active');
            window.tabletMgmtState.activeTab = tab;

            if (tab === 'overview') {
                setTimeout(() => {
                    drawManagementChartWithRetry($management, 4);
                }, 100);
            }

            if (tab === 'employees') {
                $.post('https://pf-mechanicjob/management:getEmployees', JSON.stringify({}), function(list) {
                    const parsed = normalizeNuiResponse(list);
                    if (Array.isArray(parsed)) {
                        window.tabletMgmtState.employees = parsed;
                        rerenderOpenManagementWindows();
                    }
                });
            }

            if (tab === 'pricing' || tab === 'mandatory') {
                loadPricingData();
            }

            if (tab === 'settings') {
                $.post('https://pf-mechanicjob/management:getSettings', JSON.stringify({}), function(settings) {
                    const parsed = normalizeNuiResponse(settings);
                    if (parsed && typeof parsed === 'object') {
                        window.tabletMgmtState.businessSettings = parsed;
                        rerenderOpenManagementWindows();
                    }
                });
            }
        });

        $(document).off('click.mechmgmt', '#tablet-hire-btn').on('click.mechmgmt', '#tablet-hire-btn', function() {
            const citizenid = $('#tablet-hire-id').val().trim();
            if (!citizenid) return;
            $.post('https://pf-mechanicjob/hireEmployee', JSON.stringify({ citizenid: citizenid }))
            .done(function(resp) {
                if (resp === true || resp.success) {
                    alert('Employee hired successfully!');
                    $('#tablet-hire-id').val('');
                    setTimeout(() => {
                        $.post('https://pf-mechanicjob/management:getEmployees', JSON.stringify({}), function(list) {
                            const parsed = normalizeNuiResponse(list);
                            if (Array.isArray(parsed)) {
                                window.tabletMgmtState.employees = parsed;
                                rerenderOpenManagementWindows();
                            }
                        });
                    }, 500);
                    return;
                }
                alert('Unable to hire employee. Verify citizenid and permissions.');
            });
        });

        $(document).off('click.mechmgmt', '.mgmt-btn-view-stats').on('click.mechmgmt', '.mgmt-btn-view-stats', function() {
            const citizenid = $(this).data('citizenid');
            if (!citizenid) return;
            $.post('https://pf-mechanicjob/management:getEmployeeStats', JSON.stringify({ citizenid }), function(resp) {
                const parsed = normalizeNuiResponse(resp);
                if (!parsed || typeof parsed !== 'object' || !parsed.employee) return;

                window.tabletMgmtState.selectedEmployee = {
                    ...parsed.employee,
                    transactions: Array.isArray(parsed.transactions) ? parsed.transactions : []
                };
                window.tabletMgmtState.selectedTransaction = null;
                rerenderOpenManagementWindows();
            });
        });

        $(document).off('click.mechmgmt', '.mgmt-btn-view-transaction').on('click.mechmgmt', '.mgmt-btn-view-transaction', function() {
            const txid = $(this).data('txid');
            const selected = window.tabletMgmtState.selectedEmployee;
            if (!selected || !Array.isArray(selected.transactions)) return;
            const tx = selected.transactions.find(t => String(t.id) === String(txid));
            if (!tx) return;
            window.tabletMgmtState.selectedTransaction = tx;
            rerenderOpenManagementWindows();
        });

        $(document).off('click.mechmgmt', '.mgmt-btn-promote').on('click.mechmgmt', '.mgmt-btn-promote', function() {
            const citizenid = $(this).data('citizenid');
            if (!citizenid) return;
            $.post('https://pf-mechanicjob/promoteEmployee', JSON.stringify({ citizenid }), function(resp) {
                const parsed = normalizeNuiResponse(resp);
                if (!(parsed && parsed.success)) {
                    alert('Unable to promote employee. Rank cap is 4.');
                    return;
                }
                window.tabletMgmtState.selectedEmployee = null;
                window.tabletMgmtState.selectedTransaction = null;
                $.post('https://pf-mechanicjob/management:getEmployees', JSON.stringify({}), function(list) {
                    const employees = normalizeNuiResponse(list);
                    if (Array.isArray(employees)) {
                        window.tabletMgmtState.employees = employees;
                        rerenderOpenManagementWindows();
                    }
                });
            });
        });

        $(document).off('click.mechmgmt', '.mgmt-btn-demote').on('click.mechmgmt', '.mgmt-btn-demote', function() {
            const citizenid = $(this).data('citizenid');
            if (!citizenid) return;
            $.post('https://pf-mechanicjob/demoteEmployee', JSON.stringify({ citizenid }), function(resp) {
                const parsed = normalizeNuiResponse(resp);
                if (!(parsed && parsed.success)) {
                    alert('Unable to demote employee.');
                    return;
                }
                window.tabletMgmtState.selectedEmployee = null;
                window.tabletMgmtState.selectedTransaction = null;
                $.post('https://pf-mechanicjob/management:getEmployees', JSON.stringify({}), function(list) {
                    const employees = normalizeNuiResponse(list);
                    if (Array.isArray(employees)) {
                        window.tabletMgmtState.employees = employees;
                        rerenderOpenManagementWindows();
                    }
                });
            });
        });

        $(document).off('click.mechmgmt', '.mgmt-btn-fire').on('click.mechmgmt', '.mgmt-btn-fire', function() {
            const citizenid = $(this).data('citizenid');
            if (!citizenid) return;
            if (!window.confirm('Fire this employee?')) return;
            $.post('https://pf-mechanicjob/fireEmployee', JSON.stringify({ citizenid }), function(resp) {
                const parsed = normalizeNuiResponse(resp);
                if (!(parsed && parsed.success)) {
                    alert('Unable to fire employee.');
                    return;
                }
                window.tabletMgmtState.selectedEmployee = null;
                window.tabletMgmtState.selectedTransaction = null;
                $.post('https://pf-mechanicjob/management:getEmployees', JSON.stringify({}), function(list) {
                    const employees = normalizeNuiResponse(list);
                    if (Array.isArray(employees)) {
                        window.tabletMgmtState.employees = employees;
                        rerenderOpenManagementWindows();
                    }
                });
            });
        });

        $(document).off('click.mechmgmt', '.mgmt-btn-price-edit').on('click.mechmgmt', '.mgmt-btn-price-edit', function() {
            const item = $(this).data('item');
            const pname = $(this).data('productname');
            const currentPrice = $(this).data('price');
            const category = $(this).data('category') || 'General';
            const isCustom = $(this).data('custom') === 1 || $(this).data('custom') === '1';
            window.tabletMgmtState.pricingEditor = {
                mode: 'edit',
                item: String(item || ''),
                label: String(pname || item || ''),
                category: String(category || 'General'),
                price: Number(currentPrice || 0),
                isCustom: !!isCustom,
            };
            rerenderOpenManagementWindows();
        });

        $(document).off('click.mechmgmt', '.mgmt-btn-pricing-refresh').on('click.mechmgmt', '.mgmt-btn-pricing-refresh', function() {
            loadPricingData();
        });

        $(document).off('click.mechmgmt', '.mgmt-btn-pricing-reset').on('click.mechmgmt', '.mgmt-btn-pricing-reset', function() {
            $.post('https://pf-mechanicjob/pos/manage/reset', JSON.stringify({
                business: getActiveBusinessKey(),
            }), function(resp) {
                const parsed = normalizeNuiResponse(resp);
                if (parsed && parsed.success) {
                    loadPricingData();
                    setPricingNotice('Pricing reset to defaults', 'success');
                    return;
                }
                setPricingNotice(`Failed to reset pricing${parsed && parsed.error ? ` (${parsed.error})` : ''}`, 'error');
            });
        });

        $(document).off('click.mechmgmt', '.mgmt-btn-add-item').on('click.mechmgmt', '.mgmt-btn-add-item', function() {
            window.tabletMgmtState.pricingEditor = {
                mode: 'add',
                item: '',
                label: '',
                category: 'General',
                price: 0,
                isCustom: true,
            };
            rerenderOpenManagementWindows();
        });

        $(document).off('click.mechmgmt', '.mgmt-btn-editor-cancel').on('click.mechmgmt', '.mgmt-btn-editor-cancel', function() {
            window.tabletMgmtState.pricingEditor = null;
            rerenderOpenManagementWindows();
        });

        $(document).off('click.mechmgmt', '.mgmt-pricing-modal-backdrop, .mgmt-btn-editor-close').on('click.mechmgmt', '.mgmt-pricing-modal-backdrop, .mgmt-btn-editor-close', function() {
            window.tabletMgmtState.pricingEditor = null;
            rerenderOpenManagementWindows();
        });

        $(document).off('click.mechmgmt', '.mgmt-btn-editor-save').on('click.mechmgmt', '.mgmt-btn-editor-save', function() {
            const editor = window.tabletMgmtState.pricingEditor || {};
            const labelInput = String($('#mgmt-editor-label').val() || '').trim();
            const category = String($('#mgmt-editor-category').val() || '').trim() || 'General';
            const price = Number($('#mgmt-editor-price').val() || 0);
            const label = labelInput;
            const item = editor.mode === 'add'
                ? slugifyItemKey(label)
                : String(editor.item || '').trim();

            const finalLabel = String(label || '').trim();

            if (!item) {
                setPricingNotice('Could not create item key from label', 'error');
                return;
            }
            if (!finalLabel) {
                setPricingNotice('Label is required', 'error');
                return;
            }
            if (!Number.isFinite(price) || price < 0) {
                setPricingNotice('Price must be 0 or greater', 'error');
                return;
            }

            if (editor.mode === 'add' && window.posState.items && window.posState.items[item]) {
                setPricingNotice('An item with that label already exists', 'error');
                return;
            }

            $.post('https://pf-mechanicjob/pos/manage/save', JSON.stringify({
                business: getActiveBusinessKey(),
                item,
                label: finalLabel,
                category,
                price: Math.floor(price),
                isCustom: editor.mode === 'add' ? true : !!editor.isCustom,
            }), function(resp) {
                const parsed = normalizeNuiResponse(resp);
                if (parsed && parsed.success) {
                    window.tabletMgmtState.pricingEditor = null;
                    loadPricingData();
                    setPricingNotice(editor.mode === 'add' ? 'Item added' : 'Price updated', 'success');
                    return;
                }
                setPricingNotice('Failed to save price', 'error');
            });
        });

        $(document).off('click.mechmgmt', '.mgmt-btn-remove-item').on('click.mechmgmt', '.mgmt-btn-remove-item', function() {
            if ($(this).hasClass('mgmt-mandatory-remove')) return;
            const item = $(this).data('item');
            const productName = $(this).data('productname') || item;
            if (!item) return;

        const businessKey = getActiveBusinessKey();
        console.log('[POS Remove] Item:', item, 'Business:', businessKey);

        $.post('https://pf-mechanicjob/pos/manage/deleteEntry', JSON.stringify({
            business: businessKey,
            item,
        }), function(resp) {
            console.log('[POS Remove] Response:', resp);
                setPricingNotice(`Failed to remove item${parsed && parsed.error ? ` (${parsed.error})` : ''}`, 'error');
            });
        });

        $(document).off('click.mechmgmt', '#mgmt-save-settings').on('click.mechmgmt', '#mgmt-save-settings', function() {
            const bizName = $('#mgmt-biz-name').val();
            const blipName = $('#mgmt-blip-name').val();
            const blipColor = Number($('#mgmt-blip-color').val() || 3);
            $.post('https://pf-mechanicjob/saveBusinessSettings', JSON.stringify({ 
                business_name: bizName, 
                blip_name: blipName,
                blip_color: Number.isFinite(blipColor) ? blipColor : 3
            }));
        });
    }

    function getOpenManagementContainers() {
        const refs = [];
        const ref = window.mechTabletRefs && window.mechTabletRefs.managementContainer;
        if (ref && ref.length && document.body.contains(ref[0])) {
            refs.push(ref[0]);
        }

        const discovered = $('.window-content').filter(function () {
            return $(this).find('.management-container').length > 0;
        }).toArray();

        return $(Array.from(new Set([...refs, ...discovered])));
    }

    function rerenderOpenManagementWindows() {
        const $containers = getOpenManagementContainers();
        $containers.each(function () {
            renderManagement($(this));
        });
    }

    function getCashRegisterContainer() {
        const ref = window.mechTabletRefs && window.mechTabletRefs.cashContainer;
        if (ref && ref.length && document.body.contains(ref[0])) {
            return ref;
        }

        const $byMarker = $('.window-content').filter(function () {
            return $(this).find('.pos-container').length > 0;
        }).first();

        if ($byMarker.length) {
            window.mechTabletRefs.cashContainer = $byMarker;
            return $byMarker;
        }

        return $('.app-window[data-app="cash-register"] .window-content').first();
    }

    function getCashRegisterContainerFromEvent(el) {
        const $direct = $(el).closest('.window-content');
        if ($direct.length) {
            window.mechTabletRefs.cashContainer = $direct;
            return $direct;
        }
        return getCashRegisterContainer();
    }

    function getActiveBusinessKey() {
        return window.tabletMgmtState.business || window.posState.business || 'mechanic';
    }

    function mapPricingEntries(priceMap) {
        return Object.entries(priceMap || {}).map(([item, entry]) => ({
            item,
            label: entry.label || item,
            category: entry.category || 'General',
            price: Number(entry.price || 0),
            isCustom: !!entry.isCustom,
        })).sort((a, b) => {
            const catCmp = (a.category || '').localeCompare(b.category || '');
            if (catCmp !== 0) return catCmp;
            return (a.label || '').localeCompare(b.label || '');
        });
    }

    function loadPricingData() {
        const requestedBusiness = window.posState.business || window.tabletMgmtState.business || null;
        const payload = requestedBusiness ? { business: requestedBusiness } : {};

        $.post('https://pf-mechanicjob/pos/manage/get', JSON.stringify(payload), function(resp) {
            const parsed = normalizeNuiResponse(resp);
            if (!parsed || typeof parsed !== 'object') return;

            window.posState.business = parsed.business || requestedBusiness || window.posState.business || 'mechanic';
            window.tabletMgmtState.business = window.posState.business;
            window.posState.taxRate = Number(parsed.taxRate || 0);
            window.posState.items = parsed.prices || {};
            window.posState.mandatoryCharges = Array.isArray(parsed.mandatoryCharges) ? parsed.mandatoryCharges : [];
            window.tabletMgmtState.pricingEntries = mapPricingEntries(parsed.prices || {});
            window.tabletMgmtState.mandatoryCharges = Array.isArray(parsed.mandatoryCharges) ? parsed.mandatoryCharges : [];
            window.tabletMgmtState.canEditPricing = parsed.canEdit === true;

            const $cash = getCashRegisterContainer();
            if ($cash.length) {
                renderCashRegister($cash);
            }

            rerenderOpenManagementWindows();
        });
    }

    $(document).off('input.mechpos', '#pos-search').on('input.mechpos', '#pos-search', function() {
        window.posState.search = $(this).val();
        const $content = getCashRegisterContainerFromEvent(this);
        if ($content.length) applyPosCatalogFilters($content);
    });

    $(document).off('click.mechpos', '.pos-category').on('click.mechpos', '.pos-category', function() {
        window.posState.activeCategory = $(this).data('cat');
        const $content = getCashRegisterContainerFromEvent(this);
        if ($content.length) renderCashRegister($content);
    });

    $(document).off('click.mechpos', '.pos-item').on('click.mechpos', '.pos-item', function() {
        const key = $(this).data('item');
        const item = window.posState.items[key];
        if (!item) return;
        const existing = (window.posState.cart || []).find(c => c.item === key);
        if (existing) {
            existing.qty += 1;
        } else {
            window.posState.cart.push({
                item: key,
                label: item.label,
                price: Number(item.price || 0),
                category: item.category,
                qty: 1,
            });
        }
        const $content = getCashRegisterContainerFromEvent(this);
        if ($content.length) renderCashRegister($content);
    });

    $(document).off('click.mechpos', '.pos-cart-line .qty-btn').on('click.mechpos', '.pos-cart-line .qty-btn', function(e) {
        e.stopPropagation();
        const $line = $(this).closest('.pos-cart-line');
        const key = $line.data('item');
        const action = $(this).data('action');
        const line = (window.posState.cart || []).find(c => c.item === key);
        if (!line) return;
        if (line.isMandatory && action === 'dec') return;
        if (action === 'inc') line.qty += 1;
        if (action === 'dec') line.qty = Math.max(1, line.qty - 1);
        const $content = getCashRegisterContainerFromEvent(this);
        if ($content.length) renderCashRegister($content);
    });

    $(document).off('click.mechpos', '.btn-remove-item').on('click.mechpos', '.btn-remove-item', function(e) {
        e.stopPropagation();
        const item = $(this).data('item');
        const line = (window.posState.cart || []).find(c => c.item === item);
        if (line && line.isMandatory) return;
        window.posState.cart = (window.posState.cart || []).filter(c => c.item !== item);
        const $content = getCashRegisterContainerFromEvent(this);
        if ($content.length) renderCashRegister($content);
    });

    $(document).off('input.mechmgmt', '#mgmt-pricing-search').on('input.mechmgmt', '#mgmt-pricing-search', function() {
        window.tabletMgmtState.pricingSearch = $(this).val() || '';
        rerenderOpenManagementWindows();
    });

    $(document).off('click.mechmgmt', '.mgmt-pricing-cat').on('click.mechmgmt', '.mgmt-pricing-cat', function() {
        window.tabletMgmtState.pricingCategoryFilter = $(this).data('cat') || 'All';
        rerenderOpenManagementWindows();
    });

    $(document).off('input.mechmgmt', '#mgmt-mandatory-search').on('input.mechmgmt', '#mgmt-mandatory-search', function() {
        window.tabletMgmtState.mandatorySearch = $(this).val() || '';
        const $container = $(this).closest('.management-container');
        refreshMandatorySelect($container);
    });

    $(document).off('click.mechmgmt', '#mgmt-mandatory-add-btn').on('click.mechmgmt', '#mgmt-mandatory-add-btn', function() {
        const item = String($('#mgmt-mandatory-select').val() || '').trim();
        if (!item) {
            setPricingNotice('Select an item to add as mandatory', 'error');
            return;
        }

        $.post('https://pf-mechanicjob/pos/manage/mandatoryAdd', JSON.stringify({
            business: getActiveBusinessKey(),
            item,
        }), function(resp) {
            const parsed = normalizeNuiResponse(resp);
            if (parsed && parsed.success) {
                loadPricingData();
                setPricingNotice('Mandatory charge added', 'success');
                return;
            }
            setPricingNotice(`Failed to add mandatory charge${parsed && parsed.error ? ` (${parsed.error})` : ''}`, 'error');
        });
    });

    $(document).off('click.mechmgmt', '.mgmt-mandatory-remove').on('click.mechmgmt', '.mgmt-mandatory-remove', function() {
        const item = $(this).data('item');
        if (!item) return;

        const businessKey = getActiveBusinessKey();
        console.log('[Mandatory Remove] Item:', item, 'Business:', businessKey);

        $.post('https://pf-mechanicjob/pos/manage/mandatoryRemove', JSON.stringify({
            business: businessKey,
            item,
        }), function(resp) {
            console.log('[Mandatory Remove] Response:', resp);
            const parsed = normalizeNuiResponse(resp);
            if (parsed && parsed.success) {
                loadPricingData();
                setPricingNotice('Mandatory charge removed', 'success');
                return;
            }
            setPricingNotice(`Failed to remove mandatory charge${parsed && parsed.error ? ` (${parsed.error})` : ''}`, 'error');
        });
    });

    $(document).off('click.mechpos', '.payment-btn').on('click.mechpos', '.payment-btn', function() {
        window.posState.paymentType = $(this).data('pay');
        const $content = getCashRegisterContainerFromEvent(this);
        if ($content.length) renderCashRegister($content);
    });

    $(document).off('click.mechpos', '.btn-charge-now').on('click.mechpos', '.btn-charge-now', function() {
        if ($(this).prop('disabled')) return;
        const cart = window.posState.cart || [];
        const subtotal = cart.reduce((sum, line) => sum + (line.price * line.qty), 0);
        const tax = Math.floor(subtotal * (window.posState.taxRate || 0));
        const total = subtotal + tax;

        $.post('https://pf-mechanicjob/pos/chargeRequest', JSON.stringify({
            cart,
            subtotal,
            tax,
            total,
            paymentType: window.posState.paymentType || 'cash'
        }));
    });

    $(document).off('click.mechpos', '.btn-charge-self').on('click.mechpos', '.btn-charge-self', function() {
        if ($(this).prop('disabled')) return;
        const cart = window.posState.cart || [];
        const subtotal = cart.reduce((sum, line) => sum + (line.price * line.qty), 0);
        const tax = Math.floor(subtotal * (window.posState.taxRate || 0));
        const total = subtotal + tax;

        $.post('https://pf-mechanicjob/pos/chargeRequest', JSON.stringify({
            cart,
            subtotal,
            tax,
            total,
            paymentType: window.posState.paymentType || 'cash',
            chargeSelf: true,
        }));
    });

    $(document).off('click.mechpos', '.pos-receipt-close, .pos-receipt-backdrop').on('click.mechpos', '.pos-receipt-close, .pos-receipt-backdrop', function() {
        window.posState.receiptData = null;
        $.post('https://pf-mechanicjob/receipt/close', JSON.stringify({}));
        const $content = getCashRegisterContainerFromEvent(this);
        if ($content.length) renderCashRegister($content);
    });

    function drawFallbackSalesChart(canvas, labels, values) {
        const ctx = canvas.getContext('2d');
        if (!ctx) return;

        const parent = canvas.parentElement;
        const w = (parent && parent.clientWidth) || canvas.clientWidth || 640;
        const h = (parent && parent.clientHeight) || canvas.clientHeight || 260;
        canvas.width = w;
        canvas.height = h;

        ctx.clearRect(0, 0, w, h);

        const leftPad = 56;
        const rightPad = 14;
        const topPad = 14;
        const bottomPad = 34;
        const plotW = Math.max(1, w - leftPad - rightPad);
        const plotH = Math.max(1, h - topPad - bottomPad);

        ctx.strokeStyle = 'rgba(148, 163, 184, 0.25)';
        ctx.lineWidth = 1;
        for (let i = 0; i <= 4; i++) {
            const y = Math.floor(topPad + ((plotH / 4) * i));
            ctx.beginPath();
            ctx.moveTo(leftPad, y);
            ctx.lineTo(leftPad + plotW, y);
            ctx.stroke();
        }

        const points = values.length ? values : [0];
        const max = Math.max(...points, 1);
        const min = 0;
        const span = Math.max(max - min, 1);
        const step = points.length > 1 ? (plotW / (points.length - 1)) : 0;

        ctx.fillStyle = 'rgba(148, 163, 184, 0.95)';
        ctx.font = '11px sans-serif';
        ctx.textAlign = 'right';
        ctx.textBaseline = 'middle';
        for (let i = 0; i <= 4; i++) {
            const value = Math.round(max - ((max / 4) * i));
            const y = Math.floor(topPad + ((plotH / 4) * i));
            ctx.fillText(`$${Number(value).toLocaleString()}`, leftPad - 8, y);
        }

        const xLabels = labels.length ? labels : points.map((_, idx) => `${idx + 1}`);
        const tickIndexes = [0, Math.floor((xLabels.length - 1) / 3), Math.floor(((xLabels.length - 1) * 2) / 3), xLabels.length - 1]
            .filter((val, idx, arr) => val >= 0 && arr.indexOf(val) === idx);

        ctx.textAlign = 'center';
        ctx.textBaseline = 'top';
        tickIndexes.forEach((idx) => {
            const x = leftPad + (idx * step);
            const label = String(xLabels[idx] || '');
            ctx.fillText(label, x, topPad + plotH + 8);
        });

        ctx.strokeStyle = 'rgba(96, 165, 250, 0.95)';
        ctx.lineWidth = 3;
        ctx.beginPath();
        points.forEach((value, index) => {
            const x = leftPad + (index * step);
            const y = topPad + plotH - (((value - min) / span) * plotH);
            if (index === 0) ctx.moveTo(x, y);
            else ctx.lineTo(x, y);
        });
        ctx.stroke();
    }

    function drawTabletSalesChart(chartData, targetCanvas) {
        const canvas = targetCanvas || document.getElementById('tablet-sales-chart');
        if (!canvas) return;

        const labels = [];
        const values = [];

        const dayLabel = (raw) => {
            if (!raw) return '';
            const date = new Date(raw);
            if (Number.isNaN(date.getTime())) return String(raw).slice(5, 10);
            return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
        };

        for (const row of (chartData || [])) {
            const label = row.day ?? row.date ?? '';
            const raw = row.total ?? row.amount ?? 0;
            labels.push(dayLabel(label));
            const n = Number(raw);
            values.push(Number.isFinite(n) ? n : 0);
        }

        if (typeof Chart !== 'function') {
            drawFallbackSalesChart(canvas, labels, values);
            return;
        }

        const ctx = canvas.getContext('2d');
        if (!ctx) return;

        if (window.tabletSalesChart) {
            window.tabletSalesChart.destroy();
            window.tabletSalesChart = null;
        }

        window.tabletSalesChart = new Chart(ctx, {
            type: 'line',
            data: {
                labels,
                datasets: [{
                    label: 'Sales',
                    data: values,
                    borderColor: 'rgba(96, 165, 250, 0.95)',
                    backgroundColor: 'rgba(96, 165, 250, 0.20)',
                    pointBackgroundColor: 'rgba(147, 197, 253, 1)',
                    pointBorderColor: 'rgba(191, 219, 254, 1)',
                    borderWidth: 3,
                    tension: 0.35,
                    fill: true,
                    pointRadius: 2.5,
                    pointHoverRadius: 4
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                interaction: { mode: 'index', intersect: false },
                plugins: {
                    legend: { display: false },
                    tooltip: {
                        backgroundColor: 'rgba(15, 23, 42, 0.95)',
                        titleColor: '#e2e8f0',
                        bodyColor: '#cbd5e1',
                        borderColor: 'rgba(148, 163, 184, 0.35)',
                        borderWidth: 1,
                        callbacks: {
                            label: (context) => `Amount: $${Number(context.parsed.y || 0).toLocaleString()}`
                        }
                    }
                },
                scales: {
                    y: {
                        beginAtZero: true,
                        title: {
                            display: true,
                            text: 'Amount ($)',
                            color: 'rgba(203, 213, 225, 0.95)',
                            font: { weight: '700', size: 11 }
                        },
                        ticks: {
                            color: 'rgba(148, 163, 184, 0.95)',
                            callback: (v) => '$' + Number(v).toLocaleString(),
                            maxTicksLimit: 7
                        },
                        grid: {
                            color: 'rgba(148, 163, 184, 0.18)',
                            borderDash: [4, 4]
                        }
                    },
                    x: {
                        title: {
                            display: true,
                            text: 'Day',
                            color: 'rgba(203, 213, 225, 0.95)',
                            font: { weight: '700', size: 11 }
                        },
                        ticks: {
                            color: 'rgba(148, 163, 184, 0.95)',
                            autoSkip: true,
                            maxTicksLimit: 12,
                            maxRotation: 0,
                        },
                        grid: {
                            color: 'rgba(148, 163, 184, 0.08)'
                        }
                    }
                }
            }
        });

        if (window.tabletSalesChart && typeof window.tabletSalesChart.resize === 'function') {
            setTimeout(function() {
                try { window.tabletSalesChart.resize(); } catch (_) {}
            }, 30);
        }
    }

    function normalizeNuiResponse(response) {
        if (typeof response === 'string') {
            try {
                return JSON.parse(response);
            } catch (error) {
                return null;
            }
        }
        return response;
    }

    function getWorkContainerFromTrigger(el) {
        const $direct = $(el).closest('.window-content');
        if ($direct.length) return $direct;

        const $fallback = $('.app-window .window-content').filter(function () {
            return $(this).find('.work-container').length > 0;
        }).first();

        return $fallback;
    }

    function getOpenWorkOrderContainers() {
        return $('.app-window .window-content').filter(function () {
            return $(this).find('.work-container').length > 0;
        });
    }

    function rerenderOpenWorkOrderWindows(preferredContainer) {
        if (preferredContainer && preferredContainer.length) {
            renderWorkOrders(preferredContainer);
        }

        const $containers = getOpenWorkOrderContainers();
        $containers.each(function () {
            const $current = $(this);
            if (preferredContainer && preferredContainer.length && $current[0] === preferredContainer[0]) {
                return;
            }
            renderWorkOrders($current);
        });
    }

    function applyWorkOrderData(data) {
        if (!data) return;

        const merged = {
            ...(window.mechTabletState.workOrderData || {}),
            ...data,
        };

        if (data.availableOrders !== undefined) {
            merged.availableOrders = data.availableOrders || [];
        }
        if (data.acceptedOrders !== undefined) {
            merged.acceptedOrders = data.acceptedOrders || [];
        }

        window.mechTabletState.workOrderData = merged;
        if (merged.isSearching !== undefined) {
            window.mechTabletState.isSearching = merged.isSearching;
        }
    }

    function refreshWorkOrdersFromServer(preferredContainer) {
        $.post('https://pf-mechanicjob/workorders/getData', JSON.stringify({}), function(result) {
            const parsed = normalizeNuiResponse(result);
            if (!parsed) return;
            applyWorkOrderData(parsed);
            rerenderOpenWorkOrderWindows(preferredContainer);
        });
    }

    // Work Orders Click Handlers
    $(document).on('click', '[data-action="accept-order"]', function(e) {
        e.preventDefault();
        const orderId = $(this).data('order-id');
        $.post('https://pf-mechanicjob/workorders/accept', JSON.stringify({ orderId: orderId }));
    });

    $(document).on('click', '[data-action="cancel-order"]', function(e) {
        e.preventDefault();
        const orderId = $(this).data('order-id');
        $.post('https://pf-mechanicjob/workorders/cancel', JSON.stringify({ orderId: orderId }));
    });

    $(document).on('click', '[data-action="work-refresh"]', function(e) {
        e.preventDefault();
        const $content = getWorkContainerFromTrigger(this);
        $.post('https://pf-mechanicjob/workorders/refresh', JSON.stringify({}), function() {
            refreshWorkOrdersFromServer($content);
        });
    });

    $(document).on('click', '[data-action="start-search"]', function(e) {
        e.preventDefault();
        const $content = getWorkContainerFromTrigger(this);

        applyWorkOrderData({ isSearching: true });
        rerenderOpenWorkOrderWindows($content);

        $.post('https://pf-mechanicjob/workorders/startSearch', JSON.stringify({}), function(result) {
            const parsed = normalizeNuiResponse(result);
            if (parsed && parsed.success) {
                applyWorkOrderData({ ...parsed, isSearching: true });
                rerenderOpenWorkOrderWindows($content);
                setTimeout(function() { refreshWorkOrdersFromServer($content); }, 150);
            } else {
                applyWorkOrderData({ isSearching: false });
                rerenderOpenWorkOrderWindows($content);
            }
        }).fail(function() {
            applyWorkOrderData({ isSearching: false });
            rerenderOpenWorkOrderWindows($content);
        });
    });

    $(document).on('click', '[data-action="stop-search"]', function(e) {
        e.preventDefault();
        const $content = getWorkContainerFromTrigger(this);

        applyWorkOrderData({ isSearching: false, availableOrders: [] });
        rerenderOpenWorkOrderWindows($content);

        $.post('https://pf-mechanicjob/workorders/stopSearch', JSON.stringify({}), function(result) {
            const parsed = normalizeNuiResponse(result);
            if (parsed && parsed.success) {
                applyWorkOrderData({ ...parsed, isSearching: false, availableOrders: [] });
                rerenderOpenWorkOrderWindows($content);
                setTimeout(function() { refreshWorkOrdersFromServer($content); }, 150);
            }
        });
    });

    window.addEventListener('message', function(event) {
        const data = event.data || {};

        if (data.action === 'updateWorkOrders') {
            applyWorkOrderData(data.workOrderData || {});
            rerenderOpenWorkOrderWindows();
            return;
        }

        if (data.action === 'pos:open') {
            const payload = data.data || {};
            window.posState.business = payload.business || window.posState.business || 'mechanic';
            window.posState.items = payload.items || {};
            window.posState.mandatoryCharges = Array.isArray(payload.mandatoryCharges) ? payload.mandatoryCharges : [];
            window.posState.taxRate = Number(payload.taxRate || 0);
            window.posState.loadRequested = false;

            window.tabletMgmtState.pricingEntries = mapPricingEntries(payload.items || {});
            if (payload.canEdit !== undefined) {
                window.tabletMgmtState.canEditPricing = payload.canEdit === true;
            }

            const $cash = getCashRegisterContainer();
            if ($cash.length) renderCashRegister($cash);
            rerenderOpenManagementWindows();
            return;
        }

        if (data.action === 'pos:clearCart') {
            window.posState.cart = [];
            const $cash = getCashRegisterContainer();
            if ($cash.length) renderCashRegister($cash);
            return;
        }

        if (data.action === 'pos:showReceipt') {
            const payload = data.data || data.payload || {};
            window.posState.receiptData = payload;

            const $cash = getCashRegisterContainer();
            if ($cash.length) {
                renderCashRegister($cash);
            }
            return;
        }

        if (data.action === 'pos:hideReceipt') {
            window.posState.receiptData = null;
            const $cash = getCashRegisterContainer();
            if ($cash.length) {
                renderCashRegister($cash);
            }
            return;
        }

        if (data.action === 'management:overview' && data.data) {
            window.tabletMgmtState = {
                ...window.tabletMgmtState,
                ...data.data,
            };
            rerenderOpenManagementWindows();
            return;
        }

        if (data.action === 'management:employees') {
            window.tabletMgmtState.employees = Array.isArray(data.employees) ? data.employees : [];
            rerenderOpenManagementWindows();
            return;
        }

        if (data.action === 'management:settings') {
            window.tabletMgmtState.businessSettings = data.settings || {};
            rerenderOpenManagementWindows();
            return;
        }

        if (data.action === 'management:pricing') {
            if (Array.isArray(data.products)) {
                window.tabletMgmtState.products = data.products;
            }
            if (data.prices && typeof data.prices === 'object') {
                window.tabletMgmtState.pricingEntries = mapPricingEntries(data.prices);
            }
            if (Array.isArray(data.mandatoryCharges)) {
                window.tabletMgmtState.mandatoryCharges = data.mandatoryCharges;
                window.posState.mandatoryCharges = data.mandatoryCharges;
            }
            if (data.canEdit !== undefined) {
                window.tabletMgmtState.canEditPricing = data.canEdit === true;
            }
            rerenderOpenManagementWindows();
            return;
        }

        if (data.action === 'management:graph') {
            window.tabletMgmtState.salesChartData = Array.isArray(data.points) ? data.points : [];
            rerenderOpenManagementWindows();
            setTimeout(() => {
                const $containers = getOpenManagementContainers();
                $containers.each(function() {
                    const $c = $(this);
                    drawManagementChartWithRetry($c, 4);
                });
            }, 30);
            return;
        }

        if (data.action === 'refreshWorkOrders') {
            refreshWorkOrdersFromServer();
        }
    });

    setInterval(function() {
        const data = window.mechTabletState.workOrderData || {};
        const available = Array.isArray(data.availableOrders) ? data.availableOrders : [];
        if (!available.length) return;

        const now = Math.floor(Date.now() / 1000);
        let changed = false;

        const filtered = available.filter(function(order) {
            if (order.expiresAt === undefined || order.expiresAt === null) return true;
            return Number(order.expiresAt) > now;
        });

        if (filtered.length !== available.length) {
            changed = true;
            window.mechTabletState.workOrderData = {
                ...data,
                availableOrders: filtered,
            };
        }

        $('.work-order-timer[data-expires-at]').each(function() {
            const $timer = $(this);
            const expiresAt = Number($timer.data('expires-at'));
            if (!expiresAt) return;

            const secondsLeft = Math.max(0, expiresAt - now);
            $timer.find('.timer-text').text(formatCountdown(secondsLeft));
            $timer.removeClass('timer-warning timer-critical');

            if (secondsLeft <= 10) {
                $timer.addClass('timer-critical');
            } else if (secondsLeft <= 25) {
                $timer.addClass('timer-warning');
            }
        });

        if (changed) {
            rerenderOpenWorkOrderWindows();
        }
    }, 1000);

    // Export public functions
    window.MechanicTablet.renderWorkOrders = renderWorkOrders;
    window.MechanicTablet.renderCashRegister = renderCashRegister;
    window.MechanicTablet.renderManagement = renderManagement;
    window.MechanicTablet.renderSettings = renderSettings;
})();
