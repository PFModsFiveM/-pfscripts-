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
        salesChartData: [],
        employees: [],
        products: [],
        inventory: [],
        businessSettings: {},
        permissionLevel: 'employee'
    };

    window.posState = {
        business: null,
        items: {},
        taxRate: 0,
        cart: [],
        activeCategory: 'All',
        search: '',
        paymentType: 'cash',
        posTab: 'sale'
    };

    // POS Helper Functions
    function posCategories() {
        const cats = new Set(['All']);
        Object.values(window.posState.items || {}).forEach(it => {
            if (it.category !== 'Documentation') {
                cats.add(it.category || 'Other');
            }
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

    // Work Orders Rendering
    function renderWorkOrders($content) {
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
            
            return `
                <div class="work-order-card available" data-order-id="${order.id}" data-difficulty="${order.difficulty}" ${hasExpiration ? `data-expires-at="${order.expiresAt}"` : ''}>
                    <div class="work-order-badge" style="background: ${order.color};">
                        ${order.difficultyName}
                    </div>
                    <div class="work-order-content">
                        <div class="work-order-main">
                            <div class="work-order-title-section">
                                <div class="work-order-title">${order.title}</div>
                                <div class="work-order-vehicle">🚗 ${order.vehicle}</div>
                            </div>
                            <div class="work-order-payout-section">
                                <div class="payout-label">Payout</div>
                                <div class="work-order-payout">$${payout.toLocaleString()}</div>
                            </div>
                        </div>
                        <div class="work-order-meta">
                            <div class="work-meta-item">
                                <span class="meta-icon">👤</span>
                                <span class="meta-text">${order.customer}</span>
                            </div>
                            ${hasExpiration ? `
                            <div class="work-meta-item work-order-timer" data-expires-at="${order.expiresAt}">
                                <span class="meta-icon timer-icon">⏰</span>
                                <span class="meta-text timer-text">${timeLeft}s</span>
                            </div>
                            ` : ''}
                            <div class="work-meta-item xp-reward">
                                <span class="meta-icon">⭐</span>
                                <span class="meta-text">+${order.xpReward} XP</span>
                            </div>
                        </div>
                    </div>
                    <button class="work-order-btn accept-btn" data-action="accept-order" data-order-id="${order.id}">
                        <span class="btn-icon">✓</span>
                        <span>ACCEPT JOB</span>
                    </button>
                </div>
            `;
        }).join('') : '<div class="work-empty"><div class="empty-icon">📋</div><div class="empty-text">No work orders available</div><div class="empty-subtext">New jobs will appear automatically</div></div>';

        const acceptedHTML = acceptedOrders.length ? acceptedOrders.map(order => {
            const payout = Math.floor(order.basePay * payMultiplier);
            return `
                <div class="work-order-card accepted" data-order-id="${order.id}" data-difficulty="${order.difficulty}">
                    <div class="work-order-badge" style="background: ${order.color};">
                        ${order.difficultyName}
                    </div>
                    <div class="work-order-status-badge">⚡ IN PROGRESS</div>
                    <div class="work-order-content">
                        <div class="work-order-main">
                            <div class="work-order-title-section">
                                <div class="work-order-title">${order.title}</div>
                                <div class="work-order-vehicle">🚗 ${order.vehicle}</div>
                            </div>
                            <div class="work-order-payout-section">
                                <div class="payout-label">Payout</div>
                                <div class="work-order-payout">$${payout.toLocaleString()}</div>
                            </div>
                        </div>
                        <div class="work-order-meta">
                            <div class="work-meta-item">
                                <span class="meta-icon">👤</span>
                                <span class="meta-text">${order.customer}</span>
                            </div>
                            <div class="work-meta-item">
                                <span class="meta-icon">⏱️</span>
                                <span class="meta-text">~${order.duration}s</span>
                            </div>
                            <div class="work-meta-item xp-reward">
                                <span class="meta-icon">⭐</span>
                                <span class="meta-text">+${order.xpReward} XP</span>
                            </div>
                        </div>
                    </div>
                    <div class="work-order-actions">
                        <button class="work-order-btn cancel-btn" data-action="cancel-order" data-order-id="${order.id}">
                            <span class="btn-icon">✕</span>
                            <span>CANCEL</span>
                        </button>
                    </div>
                </div>
            `;
        }).join('') : '';

        $content.html(`
            <div class="work-container">
                <div class="work-header-card">
                    <div class="work-header-top">
                        <div class="work-level-badge">
                            <div class="level-badge-content">
                                <div class="level-number">Level ${level}</div>
                                <div class="level-name">${levelName.toUpperCase()}</div>
                            </div>
                        </div>
                        <div class="work-stats-row">
                            <div class="stat-item">
                                <div class="stat-icon">📋</div>
                                <div class="stat-info">
                                    <div class="stat-label">TOTAL JOBS</div>
                                    <div class="stat-value">${totalJobs}</div>
                                </div>
                            </div>
                        </div>
                        <div class="xp-section-top">
                            <div class="xp-header">
                                <span class="xp-label">EXPERIENCE</span>
                                <span class="xp-text">${xpText}</span>
                            </div>
                            <div class="xp-bar-wrapper">
                                <div class="xp-bar">
                                    <div class="xp-fill" style="width: ${xpProgress}%;"></div>
                                </div>
                            </div>
                            ${nextLevelXP ? `<div class="xp-subtitle">${xpNeeded} XP to next level</div>` : '<div class="xp-subtitle">Max Level Reached</div>'}
                        </div>
                        <button class="btn-refresh-icon" data-action="work-refresh" title="Refresh Orders">
                            <span class="refresh-icon">↻</span>
                        </button>
                    </div>
                </div>
                
                ${acceptedOrders.length > 0 ? `
                    <div class="work-section">
                        <div class="section-header">
                            <span class="section-icon">📋</span>
                            <span class="section-title">ACTIVE JOBS (${acceptedOrders.length}/3)</span>
                        </div>
                        <div class="work-orders-grid">${acceptedHTML}</div>
                    </div>
                ` : ''}
                
                <div class="work-section">
                    <div class="section-header">
                        <span class="section-icon">🔧</span>
                        <span class="section-title">AVAILABLE WORK ORDERS (${availableOrders.length})</span>
                        ${isSearching ? `
                            <button class="btn-toggle-search active" data-action="stop-search" title="Stop searching for jobs">
                                <span class="search-toggle-icon">⏸</span>
                                <span>STOP SEARCHING</span>
                            </button>
                        ` : `
                            <button class="btn-toggle-search" data-action="start-search" title="Start searching for jobs">
                                <span class="search-toggle-icon">▶</span>
                                <span>START SEARCHING</span>
                            </button>
                        `}
                    </div>
                    ${!isSearching && availableOrders.length === 0 ? `
                        <div class="search-prompt">
                            <div class="search-prompt-content">
                                <div class="search-icon">🔍</div>
                                <div class="search-text">Job search inactive</div>
                                <div class="search-subtext">Click "Start Searching" above to find available work orders</div>
                            </div>
                        </div>
                    ` : isSearching && availableOrders.length === 0 ? `
                        <div class="searching-state">
                            <div class="searching-content">
                                <div class="spinner"></div>
                                <div class="searching-text">Searching for work orders...</div>
                                <div class="searching-subtext">New jobs will appear here</div>
                            </div>
                        </div>
                    ` : `
                        <div class="work-orders-grid">${availableHTML}</div>
                    `}
                </div>
            </div>
        `);
    }

    // Cash Register Rendering (POS)
    function renderCashRegister($content) {
        const categories = posCategories();
        const search = window.posState.search || '';
        const category = window.posState.activeCategory || 'All';
        const filtered = posFilteredItems().filter(item => item.category !== 'Documentation');
        const cart = window.posState.cart || [];
        const subtotal = cart.reduce((sum, line) => sum + (line.price * line.qty), 0);
        const taxAmount = Math.floor(subtotal * (window.posState.taxRate || 0));
        const total = subtotal + taxAmount;

        const itemsHTML = filtered.length ? filtered.map(item => {
            const inCart = (cart || []).some(line => line.item === item.key);
            const categoryLabel = item.category || 'General';
            return `
                <div class="pos-item ${inCart ? 'added' : ''}" data-item="${item.key}">
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
                    <div class="pos-line-label">${line.label}</div>
                    <div class="pos-line-actions">
                        <div class="pos-line-price">€${(line.price * line.qty).toLocaleString()}</div>
                        <button class="btn-remove-item" data-item="${line.item}" title="Remove">✕</button>
                    </div>
                </div>
                <div class="pos-line-controls">
                    <div class="qty-box">
                        <button class="qty-btn" data-action="dec">−</button>
                        <span class="qty-display">${line.qty}x</span>
                        <button class="qty-btn" data-action="inc">+</button>
                    </div>
                    <div class="line-unit">@ €${(line.price).toLocaleString()}</div>
                </div>
            </div>
        `).join('') : '<div class="pos-empty-cart">🛒 Cart is empty</div>';

        const payCash = window.posState.paymentType === 'cash';

        $content.html(`
            <div class="pos-container">
                <div class="pos-main">
                    <div class="pos-toolbar">
                        <input id="pos-search" type="text" class="pos-search" placeholder="🔍 Search products..." value="${search}">
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
                        <button class="btn-charge-now" ${cart.length ? '' : 'disabled'}>⚡ Charge Customer</button>
                        <button class="btn-charge-self" ${cart.length ? '' : 'disabled'}>👤 Charge Self</button>
                    </div>
                </div>
            </div>
        `);
    }

    // Management Rendering
    function renderManagement($content) {
        const data = window.tabletMgmtState;
        
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
                    <div class="management-tab active" data-tab="overview">Overview</div>
                    <div class="management-tab" data-tab="employees">Employees</div>
                    <div class="management-tab" data-tab="inventory">Inventory</div>
                    <div class="management-tab" data-tab="pricing">Pricing</div>
                    <div class="management-tab" data-tab="settings">Settings</div>
                </div>
                <div class="management-content">
                    <div class="tab-pane active" data-pane="overview">
                        ${renderTabletOverview(data)}
                    </div>
                    <div class="tab-pane" data-pane="employees" style="display: none;">
                        ${renderTabletEmployees(data)}
                    </div>
                    <div class="tab-pane" data-pane="inventory" style="display: none;">
                        ${renderTabletInventory(data)}
                    </div>
                    <div class="tab-pane" data-pane="pricing" style="display: none;">
                        ${renderTabletPricing(data)}
                    </div>
                    <div class="tab-pane" data-pane="settings" style="display: none;">
                        ${renderTabletSettings(data)}
                    </div>
                </div>
            </div>
        `;

        $content.html(html);
        initializeManagementHandlers();

        setTimeout(() => {
            const chartData = window.tabletMgmtState?.salesChartData;
            if (Array.isArray(chartData)) {
                drawTabletSalesChart(chartData);
            }
        }, 50);
    }

    function renderTabletOverview(data) {
        const formatCurrency = (val) => '$' + (parseInt(val || 0).toLocaleString());
        const last7 = formatCurrency(data.last7Total || 0);
        const last30 = formatCurrency(data.last30Total || 0);
        const today = formatCurrency(data.todayTotal || 0);

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
            </div>
            <div class="mgmt-chart-panel">
                <div class="mgmt-panel-title">Sales (Last 30 Days)</div>
                <div style="position: relative; height: 250px; width: 100%;">
                    <canvasid="tablet-sales-chart"></canvas>
                </div>
            </div>
        `;
    }

    function renderTabletEmployees(data) {
        const employees = data.employees || [];

        const rows = employees.length ? employees.map(emp => `
            <div class="mgmt-employee-row">
                <div class="mgmt-emp-info">
                    <div class="mgmt-emp-name">${emp.name}</div>
                    <div class="mgmt-emp-id">${emp.citizenid.substring(0, 10)}...</div>
                </div>
                <div class="mgmt-emp-role">${(emp.role || 'employee').toUpperCase()}</div>
                <div class="mgmt-emp-sales">$${(emp.totalSales || 0).toLocaleString()}</div>
                <div class="mgmt-emp-actions">
                    <button class="mgmt-btn-view-stats" data-citizenid="${emp.citizenid}">View</button>
                </div>
            </div>
        `).join('') : '<div class="work-empty"><div class="empty-icon">👥</div><div class="empty-text">No Employees</div><div class="empty-subtext">Hire employees to get started</div></div>';

        return `
            <div class="mgmt-hire-panel">
                <input type="text" id="tablet-hire-id" placeholder="Enter Player ID to hire" class="mgmt-input">
                <button id="tablet-hire-btn" class="mgmt-btn-primary">Hire</button>
            </div>
            <div class="mgmt-employees-list">
                ${rows}
            </div>
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
        const products = data.products || [];
        
        if (!products.length) {
            return `
                <div class="work-empty">
                    <div class="empty-icon">📦</div>
                    <div class="empty-text">No Products Found</div>
                    <div class="empty-subtext">Products will appear here when available</div>
                </div>
            `;
        }

        const rows = products.map(prod => `
            <div class="mgmt-pricing-row">
                <div class="mgmt-pricing-name">${prod.product_name}</div>
                <div class="mgmt-pricing-info">
                    <div class="mgmt-price-item">
                        <div class="mgmt-price-label">Base</div>
                        <div class="mgmt-price-value">$${(prod.base_price || 0).toLocaleString()}</div>
                    </div>
                    <div class="mgmt-price-item">
                        <div class="mgmt-price-label">Current</div>
                        <div class="mgmt-price-value">$${(prod.current_price || 0).toLocaleString()}</div>
                    </div>
                </div>
                <button class="mgmt-btn-edit-price" data-item="${prod.id2 || prod.item || prod.id}" data-productname="${prod.product_name}" data-price="${prod.current_price || 0}">Edit</button>
            </div>
        `).join('');

        return `<div class="mgmt-pricing-list">${rows}</div>`;
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
        $(document).on('click', '.management-tab', function() {
            const tab = $(this).data('tab');
            $('.management-tab').removeClass('active');
            $(this).addClass('active');
            $('.tab-pane').hide().removeClass('active');
            $(`.tab-pane[data-pane="${tab}"]`).show().addClass('active');

            if (tab === 'overview') {
                setTimeout(() => {
                    const chartData = window.tabletMgmtState?.salesChartData;
                    if (Array.isArray(chartData)) {
                        drawTabletSalesChart(chartData);
                    }
                }, 100);
            }

            if (tab === 'employees') {
                $.post('https://pf-mechanicjob/management:getEmployees', JSON.stringify({}));
            }

            if (tab === 'pricing') {
                $.post('https://pf-mechanicjob/management:requestPricing', JSON.stringify({}));
            }

            if (tab === 'settings') {
                $.post('https://pf-mechanicjob/management:getSettings', JSON.stringify({}));
            }
        });

        $(document).on('click', '#tablet-hire-btn', function() {
            const id = $('#tablet-hire-id').val().trim();
            if (!id) return;
            $.post('https://pf-mechanicjob/hireEmployee', JSON.stringify({ id: id }))
            .done(function(resp) {
                if (resp === true || resp.success) {
                    alert('Employee hired successfully!');
                    $('#tablet-hire-id').val('');
                    setTimeout(() => {
                        $.post('https://pf-mechanicjob/management:getEmployees', JSON.stringify({}));
                    }, 500);
                }
            });
        });

        $(document).on('click', '.mgmt-btn-edit-price', function() {
            const item = $(this).data('item');
            const pname = $(this).data('productname');
            const currentPrice = $(this).data('price');
            showPriceEditModal(item, pname, currentPrice);
        });

        $(document).on('click', '#mgmt-save-settings', function() {
            const bizName = $('#mgmt-biz-name').val();
            const blipName = $('#mgmt-blip-name').val();
            $.post('https://pf-mechanicjob/saveBusinessSettings', JSON.stringify({ 
                business_name: bizName, 
                blip_name: blipName,
                blip_color: 3
            }));
        });
    }

    function drawTabletSalesChart(chartData) {
        const canvas = document.getElementById('tablet-sales-chart');
        if (!canvas) return;

        const labels = [];
        const values = [];

        for (const row of (chartData || [])) {
            const label = row.day ?? row.date ?? '';
            const raw = row.total ?? row.amount ?? 0;
            labels.push(String(label));
            const n = Number(raw);
            values.push(Number.isFinite(n) ? n : 0);
        }

        const ctx = canvas.getContext('2d');

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
                    borderColor: '#22d3ee',
                    backgroundColor: 'rgba(34, 211, 238, 0.15)',
                    pointBackgroundColor: '#22d3ee',
                    pointBorderColor: '#22d3ee',
                    borderWidth: 2,
                    tension: 0.35,
                    fill: true,
                    pointRadius: 2
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { display: false } },
                scales: {
                    y: {
                        beginAtZero: true,
                        ticks: {
                            callback: (v) => '$' + Number(v).toLocaleString()
                        }
                    },
                    x: {
                        ticks: { autoSkip: true, maxTicksLimit: 10, maxRotation: 0 },
                        grid: { display: false }
                    }
                }
            }
        });
    }

    // Export public functions
    window.MechanicTablet.renderWorkOrders = renderWorkOrders;
    window.MechanicTablet.renderCashRegister = renderCashRegister;
    window.MechanicTablet.renderManagement = renderManagement;
    window.MechanicTablet.renderSettings = renderSettings;
})();
