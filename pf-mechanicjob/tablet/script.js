$(document).ready(function() {
    let receiptOverlayOpen = false;

    function formatMoney(value) {
        const n = Number(value || 0);
        return `€${Number.isFinite(n) ? n.toLocaleString() : '0'}`;
    }

    function renderReceiptPaper(info) {
        const payload = info || {};
        const items = Array.isArray(payload.items) ? payload.items : [];

        const rows = items.length ? items.map((entry) => {
            const qty = Number(entry.qty || 1);
            const unit = Number(entry.unitPrice || 0);
            const lineTotal = Number(entry.lineTotal || (qty * unit));
            return `
                <div class="receipt-item-row">
                    <div class="receipt-item-label">${entry.label || entry.item || 'Item'} <span>x${qty}</span></div>
                    <div class="receipt-item-price">${formatMoney(lineTotal)}</div>
                </div>
                <div class="receipt-item-sub">@ ${formatMoney(unit)} each</div>
            `;
        }).join('') : '<div class="receipt-empty">No line items</div>';

        const paymentType = String(payload.paymentType || '').toUpperCase() || 'N/A';
        const createdAt = payload.createdAtText || 'Unknown';
        const customerName = payload.customerName || 'Customer';

        return `
            <div class="receipt-header">
                <div class="receipt-title">${payload.shopName || 'Mechanic Shop'}</div>
                <div class="receipt-subtitle">OFFICIAL SERVICE RECEIPT</div>
            </div>

            <div class="receipt-meta">
                <div><span>Receipt No.</span><strong>${payload.receiptId || 'N/A'}</strong></div>
                <div><span>Date & Time</span><strong>${createdAt}</strong></div>
                <div><span>Customer</span><strong>${customerName}</strong></div>
                <div><span>Serviced By</span><strong>${payload.chargedBy || 'Unknown'}</strong></div>
                <div><span>Payment Method</span><strong>${paymentType}</strong></div>
            </div>

            <div class="receipt-divider"></div>
            <div class="receipt-items-title">Items</div>
            <div class="receipt-items">${rows}</div>
            <div class="receipt-divider"></div>

            <div class="receipt-totals">
                <div><span>Subtotal</span><strong>${formatMoney(payload.subtotal)}</strong></div>
                <div><span>Sales Tax</span><strong>${formatMoney(payload.tax)}</strong></div>
                <div class="receipt-total"><span>Amount Paid</span><strong>${formatMoney(payload.total)}</strong></div>
            </div>

            <div class="receipt-footer">Thank you for choosing ${payload.shopName || 'our shop'}.</div>
        `;
    }

    function closeReceiptOverlay(notifyClient) {
        if (!receiptOverlayOpen) return;
        receiptOverlayOpen = false;
        $('#pos-receipt-overlay').addClass('hidden').attr('aria-hidden', 'true');

        if (notifyClient) {
            fetch('https://pf-mechanicjob/receipt/close', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify({})
            }).catch(() => {});
        }
    }

    function openReceiptOverlay(info) {
        receiptOverlayOpen = true;
        $('#receipt-paper').html(renderReceiptPaper(info));
        $('#pos-receipt-overlay').removeClass('hidden').attr('aria-hidden', 'false');
    }

    $(document).on('click', '#receipt-close-btn, .pos-receipt-backdrop', function() {
        closeReceiptOverlay(true);
    });

    document.addEventListener('keydown', function(e) {
        if (e.key === 'Escape' && receiptOverlayOpen) {
            e.preventDefault();
            e.stopImmediatePropagation();
            closeReceiptOverlay(true);
        }
    }, true);

    const isEmbedded = !!window.MECH_EMBED || (new URLSearchParams(window.location.search).get('embed') === '1');

    if (isEmbedded) {
        const container = document.getElementById('tablet-container');
        if (container) {
            container.classList.remove('hidden');
        }
    }
    // Update IRL time
    function updateTime() {
        const now = new Date();
        const hours = String(now.getHours()).padStart(2, '0');
        const minutes = String(now.getMinutes()).padStart(2, '0');
        $('#time').text(`${hours}:${minutes}`);
    }
    
    updateTime();
    setInterval(updateTime, 60000);

    // Listen for NUI messages from server
    window.addEventListener('message', function(event) {
        const data = event.data;
        if (data.action === 'showPosReceipt') {
            openReceiptOverlay(data.payload || {});
            return;
        }
        if (data.action === 'hidePosReceipt') {
            closeReceiptOverlay(false);
            return;
        }
        if (data.action === 'pos:clearCart') {
            window.posState.cart = [];
            const $content = $('.app-window[data-app="cash-register"] .window-content');
            if ($content.length) renderCashRegister($content);
        }
    });

    // Global state
    window.openWindows = window.openWindows || {};
    window.playerCitizenId = null; // Will be set when loading employee data
    window.mechTabletState = {
        workOrders: [],
        catalog: [],
        cart: [],
        stats: {},
        employees: []
    };
    
    // Management app state
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

    let draggedWindow = null;
    let dragOffset = { x: 0, y: 0 };
    let windowStartPos = { x: 0, y: 0 };

    // Helper functions
    function getTabletScale() {
        const tablet = document.querySelector('.tablet');
        if (!tablet) return 1;
        const transform = window.getComputedStyle(tablet).transform;
        if (transform === 'none') return 1;
        const matrix = transform.match(/matrix\(([^\)]+)\)/);
        return matrix ? parseFloat(matrix[1].split(',')[0]) : 1;
    }

    function centerWindowNumeric($w) {
        const cw = $('.tablet-screen').width();
        const ch = $('.tablet-screen').height();
        const ww = $w.outerWidth();
        const wh = $w.outerHeight();
        $w.css({ left: (cw - ww) / 2 + 'px', top: (ch - wh) / 2 + 'px', transform: 'none' });
    }

    // Load apps dynamically
    function loadApps(apps) {
        const $grid = $('#app-grid');
        $grid.empty();
        apps.forEach(app => {
            $grid.append(`
                <div class="app-item" data-app="${app.name}">
                    <div class="app-icon">${app.icon}</div>
                    <div class="app-label">${app.label}</div>
                </div>
            `);
        });
    }

    // Default apps
    loadApps([
        { name: 'work', icon: '🔧', label: 'Work Orders' },
        { name: 'cash-register', icon: '💰', label: 'Cash Register' },
        { name: 'management', icon: '📊', label: 'Management' },
        { name: 'settings', icon: '⚙️', label: 'Settings' }
    ]);

    // Window management
    function openAppWindow(appName, appLabel, appIcon) {
        if ($(`.app-window[data-app="${appName}"]`).length) {
            restoreWindow(appName);
            return;
        }

        const $window = $(`
            <div class="app-window" data-app="${appName}">
                <div class="window-titlebar">
                    <div class="window-title">
                        <span class="window-icon">${appIcon}</span>
                        <span>${appLabel}</span>
                    </div>
                    <div class="window-controls">
                        <div class="window-btn minimize" data-action="minimize">_</div>
                        <div class="window-btn close" data-action="close">×</div>
                    </div>
                </div>
                <div class="window-content"></div>
            </div>
        `);

        $('#windows-container').append($window);
        centerWindowNumeric($window);
        window.openWindows[appName] = { minimized: false };

        // Render content based on app
        renderAppContent(appName);
    }

    function minimizeWindow(appName) {
        const $window = $(`.app-window[data-app="${appName}"]`);
        $window.addClass('minimized');
        window.openWindows[appName].minimized = true;

        // Add to dock
        if (!$(`.dock-item.window-task[data-app="${appName}"]`).length) {
            const icon = $window.find('.window-icon').text();
            const label = $window.find('.window-title span:last').text();
            $('.dock').append(`
                <div class="dock-item window-task" data-app="${appName}">
                    <span class="dock-icon">${icon}</span>
                    <span class="dock-label">${label}</span>
                </div>
            `);
        }
    }

    function restoreWindow(appName) {
        const $window = $(`.app-window[data-app="${appName}"]`);
        $window.removeClass('minimized');
        window.openWindows[appName].minimized = false;
        $(`.dock-item.window-task[data-app="${appName}"]`).remove();
    }

    function closeWindow(appName) {
        $(`.app-window[data-app="${appName}"]`).remove();
        $(`.dock-item.window-task[data-app="${appName}"]`).remove();
        delete window.openWindows[appName];
    }

    // Export functions
    window.openAppWindow = openAppWindow;
    window.minimizeWindow = minimizeWindow;
    window.restoreWindow = restoreWindow;
    window.closeWindow = closeWindow;

    // Render app content
    function renderAppContent(appName) {
        const $content = $(`.app-window[data-app="${appName}"] .window-content`);
        
        switch(appName) {
            case 'work':
                renderWorkOrders($content);
                break;
            case 'cash-register':
                renderCashRegister($content);
                break;
            case 'transactions':
                renderTransactionsWindow($content);
                break;
            case 'management':
                renderManagement($content);
                break;
            case 'settings':
                renderSettings($content);
                break;
        }
    }

    // Work Orders rendering
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
        
        // Keep state in sync
        window.mechTabletState.isSearching = isSearching;

        // Calculate XP progress percentage
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

        // Render available orders
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

        // Render accepted orders
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

    // POS state
    window.posState = window.posState || {
        business: null,
        items: {},
        taxRate: 0,
        cart: [],
        activeCategory: 'All',
        search: '',
        paymentType: 'cash',
        posTab: 'sale'
    };

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

    // Cash Register rendering (modern POS)
    function renderCashRegister($content) {
        const categories = posCategories();
        const search = window.posState.search || '';
        const category = window.posState.activeCategory || 'All';

        const filtered = posFilteredItems().filter(item => item.category !== 'Documentation');

        const cart = window.posState.cart || [];
        const subtotal = cart.reduce((sum, line) => sum + (line.price * line.qty), 0);
        const taxAmount = Math.floor(subtotal * (window.posState.taxRate || 0));
        const total = subtotal + taxAmount;

        // Products grid
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
                        <button class="btn-show-transactions" title="View Transaction History">📋 Transactions</button>
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
                        <button class="btn-close-pos">✕</button>
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

    // Transactions window rendering
    function renderTransactionsWindow($content) {
        const search = window.posState.transSearch || '';

        $content.html(`
            <div class="trans-window-container">
                <div class="trans-header">
                    <div class="trans-header-top">
                        <h2 class="trans-title">Transaction History</h2>
                        <button class="btn-back-to-pos">← Back to Register</button>
                    </div>
                    <div class="trans-search-box">
                        <input id="trans-search" type="text" class="trans-search" placeholder="🔍 Search transactions..." value="${search}">
                    </div>
                </div>
                <div id="pos-transactions-list" class="pos-transactions-list">
                    <div class="pos-loading">Loading transactions...</div>
                </div>
                <div class="pos-pagination">
                    <button class="pos-page-btn pos-page-prev">◀ Prev</button>
                    <div class="pos-page-indicator">Page 1 of 1</div>
                    <button class="pos-page-btn pos-page-next">Next ▶</button>
                </div>
            </div>
        `);

        // Load transactions
        loadTransactionHistory();
    }

    // Management rendering - FULL FEATURED APP
    function renderManagement($content) {
        // Use pre-loaded data from window state
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

        // Initial draw: when the window first opens the overview is already visible,
        // so draw the chart after DOM is in place.
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
                    <canvas id="tablet-sales-chart"></canvas>
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

    function initializeManagementHandlers() {
        // Tab switching
        $(document).on('click', '.management-tab', function() {
            const tab = $(this).data('tab');
            $('.management-tab').removeClass('active');
            $(this).addClass('active');
            $('.tab-pane').hide().removeClass('active');
            $(`.tab-pane[data-pane="${tab}"]`).show().addClass('active');

            if (tab === 'overview') {
                // Draw chart if data is available
                setTimeout(() => {
                    const chartData = window.tabletMgmtState?.salesChartData;
                    if (Array.isArray(chartData)) {
                        console.log('[Management-Tab] Drawing chart on overview tab click');
                        drawTabletSalesChart(chartData);
                    }
                }, 100);
            }

            if (tab === 'employees') {
                fetch('https://pf-mechanicjob/management:getEmployees', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({}) });
            }

            if (tab === 'pricing') {
                fetch('https://pf-mechanicjob/management:requestPricing', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({}) });
            }

            if (tab === 'settings') {
                fetch('https://pf-mechanicjob/management:getSettings', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({}) });
            }
        });

        // Hire employee
        $(document).on('click', '#tablet-hire-btn', function() {
            const id = $('#tablet-hire-id').val().trim();
            if (!id) return;
            fetch('https://pf-mechanicjob/hireEmployee', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({ id: id })
            })
            .then(res => res.json())
            .then(resp => {
                if (resp === true || resp.success) {
                    alert('Employee hired successfully!');
                    $('#tablet-hire-id').val('');
                    // Refresh the employees list by triggering the callback
                    setTimeout(() => {
                        fetch('https://pf-mechanicjob/management:getEmployees', {
                            method: 'POST',
                            headers: {'Content-Type': 'application/json'},
                            body: JSON.stringify({})
                        });
                    }, 500);
                } else {
                    alert('Error: ' + (resp.message || 'Unknown error'));
                }
            })
            .catch(err => {
                console.error('Hire error:', err);
                alert('Error hiring employee');
            });
        });

        // View employee stats
        $(document).on('click', '.mgmt-btn-view-stats', function(e) {
            e.preventDefault();
            e.stopPropagation();
            const cid = $(this).data('citizenid');
            console.log('Stats button clicked for:', cid);
            
            if (!cid) {
                console.error('No citizenid found on button');
                alert('Error: No citizen ID found');
                return;
            }
            
            fetch('https://pf-mechanicjob/getEmployeeStats', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({ citizenid: cid })
            })
            .then(res => {
                console.log('Stats response status:', res.status);
                return res.json();
            })
            .then(resp => {
                console.log('Stats response data:', resp);
                // Server returns {currentPlayerCid, employee, transactions, workOrders} directly
                if (resp && resp.employee) {
                    // Store the current player's citizenid globally for security checks
                    window.playerCitizenId = resp.currentPlayerCid;
                    showEmployeeStatsModal(resp.employee, resp.transactions || [], resp.workOrders || []);
                } else {
                    console.error('Invalid response structure:', resp);
                    alert('Failed to load employee stats - invalid response');
                }
            })
            .catch(err => {
                console.error('Stats fetch error:', err);
                alert('Error loading stats: ' + err.message);
            });
        });

        // Edit pricing
        $(document).on('click', '.mgmt-btn-edit-price', function() {
            const item = $(this).data('item');
            const pname = $(this).data('productname');
            const currentPrice = $(this).data('price');
            showPriceEditModal(item, pname, currentPrice);
        });

        // Save settings
        $(document).on('click', '#mgmt-save-settings', function() {
            const bizName = $('#mgmt-biz-name').val();
            const blipName = $('#mgmt-blip-name').val();
            fetch('https://pf-mechanicjob/saveBusinessSettings', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({ 
                    business_name: bizName, 
                    blip_name: blipName,
                    blip_color: 3
                })
            })
            .then(res => res.json())
            .then(resp => {
                alert(resp.success ? 'Settings saved!' : 'Error saving settings');
            });
        });

        // Set locations
        $(document).on('click', '#mgmt-set-stash', function() {
            fetch('https://pf-mechanicjob/startPlacement', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({ type: 'stash_shared', mode: 'coord' })
            })
            .then(res => res.json())
            .then(resp => {
                alert(resp.success ? 'Stash location saved!' : 'Error saving stash');
            });
        });

        $(document).on('click', '#mgmt-set-locker', function() {
            fetch('https://pf-mechanicjob/startPlacement', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({ type: 'locker', mode: 'coord' })
            })
            .then(res => res.json())
            .then(resp => {
                alert(resp.success ? 'Locker location saved!' : 'Error saving locker');
            });
        });

        $(document).on('click', '#mgmt-set-duty', function() {
            fetch('https://pf-mechanicjob/startPlacement', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({ type: 'duty', mode: 'coord' })
            })
            .then(res => res.json())
            .then(resp => {
                alert(resp.success ? 'Duty location saved!' : 'Error saving duty');
            });
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

        console.log('[SalesChart] labels:', labels);
        console.log('[SalesChart] values:', values);

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

    function renderPricingContent(data) {
        const entries = Object.entries(data.prices || {}).map(([key, val]) => ({ key, ...val }));
        entries.sort((a, b) => (a.category || '').localeCompare(b.category || '') || (a.label || '').localeCompare(b.label || ''));

        const lines = entries.map(entry => `
            <div class="pricing-row" data-item="${entry.key}">
                <div class="pricing-info">
                    <div class="pricing-label">${entry.label}</div>
                    <div class="pricing-meta">${entry.category || 'Uncategorized'} ${entry.isCustom ? '<span class="tag">Custom</span>' : ''}</div>
                </div>
                <div class="pricing-edit">
                    <input class="pricing-category" type="text" value="${entry.category || ''}" placeholder="Category">
                    <input class="pricing-label-input" type="text" value="${entry.label}" placeholder="Label">
                    <input class="pricing-price" type="number" min="0" value="${entry.price || 0}" placeholder="Price">
                    <button class="btn-save-price" data-custom="${entry.isCustom ? '1' : '0'}">Save</button>
                    ${entry.isCustom ? '<button class="btn-delete-price" data-custom="1">Delete</button>' : ''}
                </div>
            </div>
        `).join('');

        const categories = Array.from(new Set(entries.map(e => e.category || ''))).filter(Boolean);
        const categoryOptions = categories.map(c => `<option value="${c}">${c}</option>`).join('');

        return `
            <div class="pricing-header">
                <div>
                    <div class="work-title">Pricing</div>
                    <div class="work-subtitle">Business: ${data.business || ''}</div>
                </div>
                <button class="btn-refresh-pricing">Refresh</button>
            </div>
            <div class="pricing-list">${lines || '<div class="work-empty">No entries</div>'}</div>
            <div class="pricing-add">
                <div class="pricing-add-title">Add Custom Charge</div>
                <div class="pricing-add-fields">
                    <input id="price-add-label" type="text" placeholder="Label">
                    <input id="price-add-price" type="number" min="0" placeholder="Price">
                    <input id="price-add-category" list="pricing-categories" type="text" placeholder="Category">
                    <datalist id="pricing-categories">${categoryOptions}</datalist>
                    <button id="btn-price-add">Add</button>
                </div>
            </div>
        `;
    }

    // Settings rendering
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

    // Event handlers
    $(document).on('click', '.app-item', function() {
        const appName = $(this).data('app');
        const appLabel = $(this).find('.app-label').text();
        const appIcon = $(this).find('.app-icon').text();
        openAppWindow(appName, appLabel, appIcon);
        if (appName === 'cash-register') {
            $.post('https://pf-mechanicjob/pos/open', JSON.stringify({}));
        }
    });

    $(document).on('click', '.dock-item:not(.window-task)', function() {
        const appName = $(this).data('app');
        const appLabel = $(this).find('.dock-label').text();
        const appIcon = $(this).find('.dock-icon').text();
        openAppWindow(appName, appLabel, appIcon);
    });

    $(document).on('click', '.dock-item.window-task', function() {
        const appName = $(this).data('app');
        restoreWindow(appName);
    });

    // POS: search
    $(document).on('input', '#pos-search', function() {
        window.posState.search = $(this).val();
        const $content = $('.app-window[data-app="cash-register"] .window-content');
        if ($content.length) renderCashRegister($content);
    });

    // Transaction: search
    $(document).on('input', '#trans-search', function() {
        window.posState.transSearch = $(this).val();
        window.posState.transPage = 1; // reset to first page on new search
        loadTransactionHistory();
    });

    // Transactions: pagination controls
    $(document).on('click', '.pos-page-prev', function() {
        const page = Math.max((window.posState.transPage || 1) - 1, 1);
        window.posState.transPage = page;
        loadTransactionHistory();
    });

    $(document).on('click', '.pos-page-next', function() {
        // totalPages recalculated inside loader, so we optimistically increment
        window.posState.transPage = (window.posState.transPage || 1) + 1;
        loadTransactionHistory();
    });

    // POS: category change
    $(document).on('click', '.pos-category', function() {
        window.posState.activeCategory = $(this).data('cat');
        const $content = $('.app-window[data-app="cash-register"] .window-content');
        if ($content.length) renderCashRegister($content);
    });

    // POS: category card click
    $(document).on('click', '.pos-cat-card', function() {
        const cat = $(this).data('cat');
        if (cat) {
            window.posState.activeCategory = cat;
            const $content = $('.app-window[data-app="cash-register"] .window-content');
            if ($content.length) renderCashRegister($content);
        }
    });

    // POS: add to cart
    $(document).on('click', '.pos-item', function() {
        const key = $(this).data('item');
        const item = window.posState.items[key];
        if (!item) return;
        const existing = window.posState.cart.find(c => c.item === key);
        if (existing) {
            existing.qty += 1;
        } else {
            window.posState.cart.push({
                item: key,
                label: item.label,
                price: item.price,
                category: item.category,
                qty: 1,
            });
        }
        const $content = $('.app-window[data-app="cash-register"] .window-content');
        if ($content.length) renderCashRegister($content);
    });

    // POS: cart qty +/-
    $(document).on('click', '.pos-cart-line .qty-btn', function(e) {
        e.stopPropagation();
        const $line = $(this).closest('.pos-cart-line');
        const key = $line.data('item');
        const action = $(this).data('action');
        const line = window.posState.cart.find(c => c.item === key);
        if (!line) return;
        if (action === 'inc') line.qty += 1; else line.qty = Math.max(1, line.qty - 1);
        const $content = $('.app-window[data-app="cash-register"] .window-content');
        if ($content.length) renderCashRegister($content);
    });

    // POS: remove item from cart
    $(document).on('click', '.btn-remove-item', function(e) {
        e.stopPropagation();
        const item = $(this).data('item');
        window.posState.cart = (window.posState.cart || []).filter(c => c.item !== item);
        const $content = $('.app-window[data-app="cash-register"] .window-content');
        if ($content.length) renderCashRegister($content);
    });

    // POS: payment toggle
    $(document).on('click', '.payment-btn', function() {
        window.posState.paymentType = $(this).data('pay');
        const $content = $('.app-window[data-app="cash-register"] .window-content');
        if ($content.length) renderCashRegister($content);
    });

    // POS: close window
    $(document).on('click', '.btn-close-pos', function() {
        $.post('https://pf-mechanicjob/pos/close', JSON.stringify({}));
    });

    // POS: charge
    $(document).on('click', '.btn-charge-now', function() {
        if ($(this).prop('disabled')) return;
        const cart = window.posState.cart || [];
        const subtotal = cart.reduce((sum, line) => sum + (line.price * line.qty), 0);
        const tax = Math.floor(subtotal * (window.posState.taxRate || 0));
        const total = subtotal + tax;
        $.post('https://pf-mechanicjob/pos/chargeRequest', JSON.stringify({
            cart: cart,
            subtotal: subtotal,
            tax: tax,
            total: total,
            paymentType: window.posState.paymentType || 'cash'
        }), function() {
            // Cart will be cleared by server event
        });
    });

    // POS: charge self
    $(document).on('click', '.btn-charge-self', function() {
        if ($(this).prop('disabled')) return;
        const cart = window.posState.cart || [];
        const subtotal = cart.reduce((sum, line) => sum + (line.price * line.qty), 0);
        const tax = Math.floor(subtotal * (window.posState.taxRate || 0));
        const total = subtotal + tax;
        $.post('https://pf-mechanicjob/pos/chargeRequest', JSON.stringify({
            cart: cart,
            subtotal: subtotal,
            tax: tax,
            total: total,
            paymentType: window.posState.paymentType || 'cash',
            chargeSelf: true
        }), function() {
            // Cart will be cleared by server event
        });
    });

    // POS: tab switching
    $(document).on('click', '.pos-tab-btn', function() {
        const tab = $(this).data('tab');
        window.posState.posTab = tab;
        const $content = $('.app-window[data-app="cash-register"] .window-content');
        if ($content.length) renderCashRegister($content);
    });

    // POS: show transactions window
    $(document).on('click', '.btn-show-transactions', function() {
        if ($(`.app-window[data-app="transactions"]`).length) {
            restoreWindow('transactions');
            return;
        }
        openAppWindow('transactions', 'Transactions', '📋');
    });

    // Transactions: back to register
    $(document).on('click', '.btn-back-to-pos', function() {
        closeWindow('transactions');
    });

    // Load and render transaction history
    function loadTransactionHistory() {
        $.post('https://pf-mechanicjob/pos/history/get', JSON.stringify({ 
            business: window.posState.business,
            limit: 50 
        }), function(transactions) {
            if (!transactions || !Array.isArray(transactions)) {
                transactions = [];
            }

            // Apply search filter
            const search = (window.posState.transSearch || '').toLowerCase();
            let filtered = transactions;
            if (search) {
                filtered = transactions.filter(trans => {
                    const id = (trans.transaction_id || '').toLowerCase();
                    const merchant = (trans.mechanic_name || '').toLowerCase();
                    return id.includes(search) || merchant.includes(search);
                });
            }

            // Pagination
            const pageSize = 9;
            const totalPages = Math.max(1, Math.ceil(filtered.length / pageSize));
            window.posState.transPage = Math.min(Math.max(window.posState.transPage || 1, 1), totalPages);
            const currentPage = window.posState.transPage;
            const startIdx = (currentPage - 1) * pageSize;
            const endIdx = startIdx + pageSize;
            const paged = filtered.slice(startIdx, endIdx);
            
            const transHTML = paged.length ? paged.map(trans => {
                const items = trans.items || [];
                const itemsStr = items.map(it => `${it.qty || 1}x ${it.label || 'Item'}`).join(', ');
                const hasItems = itemsStr && itemsStr.trim().length > 0;
                const dateStr = new Date(trans.created_at).toLocaleString();

                const bodyHTML = hasItems ? `
                        <div class="trans-card-body">
                            <div class="trans-items">${itemsStr}</div>
                            <div class="trans-datetime">${dateStr}</div>
                        </div>
                ` : '';
                
                return `
                    <div class="pos-transaction-card" data-transaction-id="${trans.transaction_id}" style="cursor: pointer;">
                        <div class="trans-card-header">
                            <div class="trans-badge ${trans.status === 'completed' ? 'completed' : 'pending'}">${trans.status || 'Sale'}</div>
                            <div class="trans-id">Order #${(trans.transaction_id || trans.id || '').substring(0, 8)}</div>
                        </div>
                        ${bodyHTML}
                        <div class="trans-card-footer">
                            <div class="trans-merchant">${trans.mechanic_name || 'Mechanic'}</div>
                            <div class="trans-total">€${(trans.total || 0).toLocaleString()}</div>
                        </div>
                    </div>
                `;
            }).join('') : '<div class="pos-loading">No transactions found</div>';

            const $list = $('#pos-transactions-list');
            if ($list.length) {
                $list.html(transHTML);

                // Attach click handler to transaction cards
                $list.off('click', '.pos-transaction-card').on('click', '.pos-transaction-card', function() {
                    const txId = $(this).data('transaction-id');
                    const txData = filtered.find(t => t.transaction_id === txId);
                    if (txData) {
                        showTransactionDetailModal(txData);
                    }
                });

                // Update pagination UI
                const $indicator = $('.pos-page-indicator');
                if ($indicator.length) {
                    $indicator.text(`Page ${currentPage} of ${totalPages}`);
                }
                const $prev = $('.pos-page-prev');
                const $next = $('.pos-page-next');
                if ($prev.length) {
                    $prev.prop('disabled', currentPage <= 1);
                }
                if ($next.length) {
                    $next.prop('disabled', currentPage >= totalPages);
                }
            }
        });
    }

    // Clear POS cart (called after successful charge)
    window.clearPosCart = function() {
        window.posState.cart = [];
        const $content = $('.app-window[data-app="cash-register"] .window-content');
        if ($content.length) renderCashRegister($content);
    };

    $(document).on('click', '.window-btn', function(e) {
        e.stopPropagation();
        const action = $(this).data('action');
        const appName = $(this).closest('.app-window').data('app');
        if (action === 'minimize') minimizeWindow(appName);
        if (action === 'close') closeWindow(appName);
    });

    // Drag functionality
    $(document).on('mousedown', '.window-titlebar', function(e) {
        if ($(e.target).closest('.window-btn').length) return;
        draggedWindow = $(this).closest('.app-window')[0];
        const rect = draggedWindow.getBoundingClientRect();
        const scale = getTabletScale();
        dragOffset.x = (e.clientX - rect.left) / scale;
        dragOffset.y = (e.clientY - rect.top) / scale;
        windowStartPos.x = rect.left / scale;
        windowStartPos.y = rect.top / scale;
    });

    $(document).on('mousemove', function(e) {
        if (!draggedWindow) return;
        const scale = getTabletScale();
        const screenRect = $('.tablet-screen')[0].getBoundingClientRect();
        const newX = (e.clientX - screenRect.left) / scale - dragOffset.x;
        const newY = (e.clientY - screenRect.top) / scale - dragOffset.y;
        $(draggedWindow).css({ left: newX + 'px', top: newY + 'px', transform: 'none' });
    });

    $(document).on('mouseup mouseleave', function() {
        draggedWindow = null;
    });

    function loadPricing() {
        $.post('https://pf-mechanicjob/pos/manage/get', JSON.stringify({ business: window.posState.business }), function(resp) {
            window.mechTabletState.pricing = resp || {};
            const $pane = $('.tab-pane[data-pane="pricing"] .pricing-pane');
            if ($pane.length) {
                $pane.html(renderPricingContent(window.mechTabletState.pricing));
            }
        });
    }

    $(document).on('click', '.btn-refresh-pricing', function() {
        loadPricing();
    });

    $(document).on('click', '.btn-save-price', function() {
        const $row = $(this).closest('.pricing-row');
        const item = $row.data('item');
        const label = $row.find('.pricing-label-input').val();
        const category = $row.find('.pricing-category').val();
        const price = parseInt($row.find('.pricing-price').val() || '0', 10);
        const isCustom = $(this).data('custom') === 1 || $(this).data('custom') === '1';
        $.post('https://pf-mechanicjob/pos/manage/save', JSON.stringify({
            business: window.mechTabletState.pricing.business || window.posState.business,
            item: item,
            label: label,
            category: category,
            price: price,
            isCustom: isCustom
        }), function(resp) {
            if (resp && resp.success) loadPricing();
        });
    });

    $(document).on('click', '.btn-delete-price', function() {
        const $row = $(this).closest('.pricing-row');
        const item = $row.data('item');
        $.post('https://pf-mechanicjob/pos/manage/delete', JSON.stringify({
            business: window.mechTabletState.pricing.business || window.posState.business,
            item: item
        }), function(resp) {
            if (resp && resp.success) loadPricing();
        });
    });

    $(document).on('click', '#btn-price-add', function() {
        const label = $('#price-add-label').val();
        const category = $('#price-add-category').val();
        const price = parseInt($('#price-add-price').val() || '0', 10);
        if (!label || price < 0) return;
        const business = window.mechTabletState.pricing.business || window.posState.business || 'mechanic';
        const itemKey = `custom_${business}_${Date.now()}`;
        $.post('https://pf-mechanicjob/pos/manage/save', JSON.stringify({
            business: business,
            item: itemKey,
            label: label,
            category: category,
            price: price,
            isCustom: true
        }), function(resp) {
            if (resp && resp.success) {
                $('#price-add-label').val('');
                $('#price-add-price').val('');
                $('#price-add-category').val('');
                loadPricing();
            }
        });
    });

    // Catalog item click (add to cart)
    $(document).on('click', '.catalog-item', function() {
        const itemId = $(this).data('item-id');
        const item = window.mechTabletState.catalog[itemId];
        if (!item) return;

        // Add to cart
        const existingItem = window.mechTabletState.cart.find(c => c.name === item.name);
        if (existingItem) {
            existingItem.quantity++;
        } else {
            window.mechTabletState.cart.push({
                name: item.name,
                price: item.price,
                quantity: 1,
                icon: item.icon
            });
        }

        // Re-render cash register
        const $content = $('.app-window[data-app="cash-register"] .window-content');
        if ($content.length) renderCashRegister($content);

        // Notify server
        $.post('https://pf-mechanicjob/tablet/addToCart', JSON.stringify({ item: item }));
    });

    // Checkout button
    $(document).on('click', '.checkout-btn', function() {
        if ($(this).prop('disabled')) return;
        
        const cart = window.mechTabletState.cart;
        const total = cart.reduce((sum, item) => sum + (item.price * item.quantity), 0);

        $.post('https://pf-mechanicjob/tablet/checkout', JSON.stringify({ 
            cart: cart,
            total: total 
        }), function(response) {
            if (response && response.success) {
                window.mechTabletState.cart = [];
                const $content = $('.app-window[data-app="cash-register"] .window-content');
                if ($content.length) renderCashRegister($content);
            }
        });
    });

    // Refresh work orders
    $(document).on('click', '.btn-refresh-icon[data-action="work-refresh"]', function() {
        $.post('https://pf-mechanicjob/workorders/refresh', JSON.stringify({}), function(response) {
            if (response && response.success) {
                // Refresh the entire work order data
                $.post('https://pf-mechanicjob/workorders/getData', JSON.stringify({}), function(data) {
                    if (data) {
                        window.mechTabletState.workOrderData = data;
                        const $content = $('.app-window[data-app="work"] .window-content');
                        if ($content.length) renderWorkOrders($content);
                    }
                });
            }
        });
    });

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

    function syncWorkOrderStateFromServer() {
        $.post('https://pf-mechanicjob/workorders/getData', JSON.stringify({}), function(data) {
            const parsed = normalizeNuiResponse(data);
            if (!parsed) return;

            window.mechTabletState.workOrderData = {
                ...window.mechTabletState.workOrderData,
                ...parsed,
            };

            if (parsed.isSearching !== undefined) {
                window.mechTabletState.isSearching = parsed.isSearching;
            }

            const $content = $('.app-window[data-app="work"] .window-content');
            if ($content.length) renderWorkOrders($content);
        });
    }

    // Accept work order
    $(document).on('click', '[data-action="accept-order"]', function() {
        const $btn = $(this);
        const orderId = $btn.data('order-id');
        
        // Prevent double-clicking
        if ($btn.prop('disabled')) return;
        $btn.prop('disabled', true).css('opacity', '0.5');
        
        console.log('[Tablet] Accepting order:', orderId);
        
        $.post('https://pf-mechanicjob/workorders/accept', JSON.stringify({ orderId: orderId }), function(response) {
            console.log('[Tablet] Accept response SUCCESS:', response.success);
            console.log('[Tablet] Accept response MESSAGE:', response.message);
            console.log('[Tablet] Accept response FULL:', JSON.stringify(response));
            
            if (response && response.success) {
                // Optimistic UI update: move card to accepted locally so the user sees it immediately
                const state = window.mechTabletState.workOrderData || {};
                const availableOrders = state.availableOrders ? [...state.availableOrders] : [];
                const acceptedOrders = state.acceptedOrders ? [...state.acceptedOrders] : [];

                const idx = availableOrders.findIndex(o => String(o.id) === String(orderId));
                if (idx !== -1) {
                    const acceptedOrder = { ...availableOrders[idx], status: 'accepted', acceptedAt: Date.now() / 1000 };
                    availableOrders.splice(idx, 1);
                    acceptedOrders.push(acceptedOrder);
                    window.mechTabletState.workOrderData = {
                        ...state,
                        availableOrders,
                        acceptedOrders,
                    };

                    const $content = $('.app-window[data-app="work"] .window-content');
                    if ($content.length) {
                        renderWorkOrders($content);
                        console.log('[Tablet] Optimistic render applied');
                    }
                }

                // Small delay to ensure server state is updated
                setTimeout(function() {
                    // Refresh work order data
                    $.post('https://pf-mechanicjob/workorders/getData', JSON.stringify({}), function(data) {
                        console.log('[Tablet] getData after accept:', data);
                        console.log('[Tablet] Available orders:', data?.availableOrders?.length);
                        console.log('[Tablet] Accepted orders:', data?.acceptedOrders?.length);
                        console.log('[Tablet] isSearching:', data?.isSearching);
                        
                        if (data) {
                            // Replace the entire state with fresh data
                            window.mechTabletState.workOrderData = data;
                            console.log('[Tablet] State updated:', window.mechTabletState.workOrderData);
                            
                            const $content = $('.app-window[data-app="work"] .window-content');
                            console.log('[Tablet] Content element found:', $content.length);
                            
                            if ($content.length) {
                                renderWorkOrders($content);
                                console.log('[Tablet] Re-rendered - Available:', data.availableOrders.length, 'Accepted:', data.acceptedOrders.length);
                            }
                        }
                    });
                }, 100);
            } else {
                console.error('[Tablet] Accept failed!');
                console.error('[Tablet] Error message:', response?.message || 'No message');
                console.error('[Tablet] Full response:', JSON.stringify(response));
                // Re-enable button on failure
                $btn.prop('disabled', false).css('opacity', '1');
            }
        });
    });

    // Complete work order
    $(document).on('click', '[data-action="complete-order"]', function() {
        const orderId = $(this).data('order-id');
        $.post('https://pf-mechanicjob/workorders/complete', JSON.stringify({ orderId: orderId }), function(response) {
            if (response && response.success) {
                // Refresh work order data
                $.post('https://pf-mechanicjob/workorders/getData', JSON.stringify({}), function(data) {
                    if (data) {
                        window.mechTabletState.workOrderData = data;
                        const $content = $('.app-window[data-app="work"] .window-content');
                        if ($content.length) renderWorkOrders($content);
                    }
                });
            }
        });
    });

    // Cancel work order
    $(document).on('click', '[data-action="cancel-order"]', function() {
        const orderId = $(this).data('order-id');
        $.post('https://pf-mechanicjob/workorders/cancel', JSON.stringify({ orderId: orderId }), function(response) {
            if (response && response.success) {
                // Refresh work order data
                $.post('https://pf-mechanicjob/workorders/getData', JSON.stringify({}), function(data) {
                    if (data) {
                        window.mechTabletState.workOrderData = data;
                        const $content = $('.app-window[data-app="work"] .window-content');
                        if ($content.length) renderWorkOrders($content);
                    }
                });
            }
        });
    });

    // Start searching for work orders
    $(document).on('click', '[data-action="start-search"]', function(e) {
        e.preventDefault();
        e.stopPropagation();
        
        window.mechTabletState.workOrderData = {
            ...window.mechTabletState.workOrderData,
            isSearching: true
        };
        window.mechTabletState.isSearching = true;
        
        const $content = $('.app-window[data-app="work"] .window-content');
        if ($content.length) {
            renderWorkOrders($content);
        }
        
        $.post('https://pf-mechanicjob/workorders/startSearch', JSON.stringify({}), function(result) {
            const parsed = normalizeNuiResponse(result);
            if (parsed && parsed.success) {
                window.mechTabletState.workOrderData = {
                    ...window.mechTabletState.workOrderData,
                    ...parsed,
                    success: undefined,
                    isSearching: true
                };
                window.mechTabletState.isSearching = true;

                const $content = $('.app-window[data-app="work"] .window-content');
                if ($content.length) {
                    renderWorkOrders($content);
                }

                setTimeout(syncWorkOrderStateFromServer, 100);
            } else {
                console.error('[Tablet] Start search failed:', parsed || result);
                window.mechTabletState.isSearching = false;
                if ($content.length) renderWorkOrders($content);
            }
        }).fail(function(err) {
            console.error('[Tablet] POST request failed:', err);
            window.mechTabletState.isSearching = false;
            const $content = $('.app-window[data-app="work"] .window-content');
            if ($content.length) renderWorkOrders($content);
        });
    });

    // Stop searching for work orders
    $(document).on('click', '[data-action="stop-search"]', function(e) {
        e.preventDefault();
        e.stopPropagation();
        
        window.mechTabletState.isSearching = false;
        // Immediately clear available jobs in UI for responsiveness
        if (window.mechTabletState.workOrderData) {
            window.mechTabletState.workOrderData.availableOrders = [];
            window.mechTabletState.workOrderData.isSearching = false;
        }
        const $content = $('.app-window[data-app="work"] .window-content');
        if ($content.length) renderWorkOrders($content);

        $.post('https://pf-mechanicjob/workorders/stopSearch', JSON.stringify({}), function(result) {
            const parsed = normalizeNuiResponse(result);
            if (parsed && parsed.success) {
                window.mechTabletState.workOrderData = {
                    ...window.mechTabletState.workOrderData,
                    ...parsed,
                    success: undefined,
                    availableOrders: [],
                    isSearching: false
                };
                window.mechTabletState.isSearching = false;
                
                const $content = $('.app-window[data-app="work"] .window-content');
                if ($content.length) {
                    renderWorkOrders($content);
                }

                setTimeout(syncWorkOrderStateFromServer, 100);
            }
        }).fail(function(err) {
            console.error('[Tablet] Stop search POST failed:', err);
        });
    });

    // NUI Message handler
    window.addEventListener('message', function(e) {
        const data = e.data || {};
        
        console.log('[Tablet] NUI message received:', data.action || 'unknown');
        
        if (data.action === 'openTablet') {
            $('#tablet-container').removeClass('hidden');
            
            // Update state if provided
            if (data.workOrderData) window.mechTabletState.workOrderData = data.workOrderData;
            if (data.catalog) window.mechTabletState.catalog = data.catalog;
            if (data.stats) window.mechTabletState.stats = data.stats;
            if (data.employees) window.mechTabletState.employees = data.employees;
            if (data.workOrderData && data.workOrderData.isSearching !== undefined) {
                window.mechTabletState.isSearching = data.workOrderData.isSearching;
            }
            
            // Update game time/date
            if (data.gameTime) $('#game-time').text(data.gameTime);
            if (data.gameDate) $('#game-date').text(data.gameDate);
        }
        
        if (data.action === 'closeTablet') {
            if (isEmbedded) return;
            $('#tablet-container').addClass('hidden');
            window.mechTabletState.isSearching = false;
            // Close all windows
            Object.keys(window.openWindows).forEach(appName => closeWindow(appName));
        }

        if (data.action === 'updateWorkOrders') {
            console.log('[Tablet] updateWorkOrders action');
            const previousData = window.mechTabletState.workOrderData || {};
            const incomingData = data.workOrderData || {};
            const mergedData = {
                ...previousData,
                ...incomingData,
                availableOrders: incomingData.availableOrders || previousData.availableOrders || [],
                acceptedOrders: incomingData.acceptedOrders || previousData.acceptedOrders || []
            };

            if (incomingData.isSearching === undefined) {
                mergedData.isSearching = window.mechTabletState.isSearching || previousData.isSearching || false;
            }

            window.mechTabletState.workOrderData = mergedData;
            // Sync search state from server data if available
            if (mergedData.isSearching !== undefined) {
                window.mechTabletState.isSearching = mergedData.isSearching;
            }
            const $content = $('.app-window[data-app="work"] .window-content');
            if ($content.length) renderWorkOrders($content);
        }

        // Management data update
        if (data.action === 'management:update') {
            console.log('[Management] Update received with data:', data.payload);
            window.tabletMgmtState = data.payload || {};
            console.log('[Management] State updated. SalesChartData:', window.tabletMgmtState.salesChartData);
            
            const $content = $('.app-window[data-app="management"] .window-content');
            if ($content.length) {
                renderManagement($content);
                // Draw chart after rendering - use longer delay to ensure DOM is ready
                setTimeout(() => {
                    console.log('[Management] Drawing chart after render...');
                    const chartData = window.tabletMgmtState?.salesChartData;
                    console.log('[Management] Chart data to draw:', chartData);
                    
                    // Draw chart even if data is empty - it will show as all zeros
                    if (Array.isArray(chartData)) {
                        console.log('[Management] Drawing chart with', chartData.length, 'points');
                        drawTabletSalesChart(chartData);
                    } else {
                        console.warn('[Management] salesChartData is not an array:', chartData);
                    }
                }, 250);
            } else {
                console.warn('[Management] Management window not found');
            }
        }

        if (data.action === 'management:overview') {
            window.tabletMgmtState = window.tabletMgmtState || {};
            const payload = data.data || {};
            window.tabletMgmtState.last7Total = payload.last7 || 0;
            window.tabletMgmtState.last30Total = payload.last30 || 0;
            window.tabletMgmtState.todayTotal = payload.today || 0;

            const $pane = $('.tab-pane[data-pane="overview"]');
            if ($pane.length) {
                $pane.html(renderTabletOverview(window.tabletMgmtState));
                setTimeout(() => {
                    if (window.tabletMgmtState.salesChartData && Array.isArray(window.tabletMgmtState.salesChartData)) {
                        drawTabletSalesChart(window.tabletMgmtState.salesChartData);
                    }
                }, 50);
            }
        }

        if (data.action === 'management:graph') {
            window.tabletMgmtState = window.tabletMgmtState || {};
            const points = data.points || [];
            window.tabletMgmtState.salesChartData = points.map(p => ({
                day: p.day || p.date,
                total: Number(p.total ?? p.amount ?? 0)
            }));

            console.log('[Management] Updated salesChartData with', window.tabletMgmtState.salesChartData.length, 'points');
            const $pane = $('.tab-pane[data-pane="overview"]');
            if ($pane.length && $pane.is(':visible')) {
                setTimeout(() => drawTabletSalesChart(window.tabletMgmtState.salesChartData), 50);
            }
        }

        if (data.action === 'management:employees') {
            window.tabletMgmtState = window.tabletMgmtState || {};
            window.tabletMgmtState.employees = data.employees || [];

            const $pane = $('.tab-pane[data-pane="employees"]');
            if ($pane.length) {
                $pane.html(renderTabletEmployees(window.tabletMgmtState));
            }
        }

        if (data.action === 'management:pricing') {
            window.tabletMgmtState = window.tabletMgmtState || {};
            const incoming = data.products || data || [];
            const normalized = incoming.map(p => ({
                id: p.id,
                id2: p.id,
                product_name: p.product_name || p.name,
                base_price: p.base_price || p.price || 0,
                current_price: p.current_price || p.price || 0,
                category: p.category,
                item: p.name || p.product_name
            }));
            window.tabletMgmtState.products = normalized;

            const $pane = $('.tab-pane[data-pane="pricing"]');
            if ($pane.length) {
                $pane.html(renderTabletPricing(window.tabletMgmtState));
            }
        }

        if (data.action === 'management:settings') {
            window.tabletMgmtState = window.tabletMgmtState || {};
            window.tabletMgmtState.businessSettings = data.settings || data || {};

            const $pane = $('.tab-pane[data-pane="settings"]');
            if ($pane.length) {
                $pane.html(renderTabletSettings(window.tabletMgmtState));
            }
        }

        // Explicit completion UI update hook
        if (data.action === 'completeWorkOrder') {
            const state = window.mechTabletState.workOrderData || {};
            const accepted = state.acceptedOrders ? [...state.acceptedOrders] : [];
            const idx = accepted.findIndex(o => String(o.id) === String(data.orderId));
            if (idx !== -1) {
                accepted.splice(idx, 1);
                state.acceptedOrders = accepted;
                window.mechTabletState.workOrderData = state;
                const $content = $('.app-window[data-app="work"] .window-content');
                if ($content.length) renderWorkOrders($content);
                console.log('[Tablet] completeWorkOrder: removed orderId', data.orderId);
            }
        }

        if (data.action === 'refreshWorkOrders') {
            console.log('[Tablet] Refreshing work orders after job acceptance');
            // Check if tablet is open and work orders tab is visible
            const isTabletOpen = !$('#tablet-container').hasClass('hidden');
            console.log('[Tablet] Tablet open:', isTabletOpen);
            
            // Fetch fresh data from server
            console.log('[Tablet] Calling getData...');
            $.post('https://pf-mechanicjob/workorders/getData', JSON.stringify({}), function(freshData) {
                console.log('[Tablet] getData callback executed');
                console.log('[Tablet] Fresh data received:', freshData);
                console.log('[Tablet] Fresh data type:', typeof freshData);
                console.log('[Tablet] Fresh data JSON:', JSON.stringify(freshData));
                console.log('[Tablet] Available:', freshData?.availableOrders?.length, 'Accepted:', freshData?.acceptedOrders?.length);
                
                if (freshData) {
                    window.mechTabletState.workOrderData = freshData;
                    const $content = $('.app-window[data-app="work"] .window-content');
                    console.log('[Tablet] Work content element exists:', $content.length);
                    
                    if ($content.length) {
                        renderWorkOrders($content);
                        console.log('[Tablet] Work orders refreshed successfully');
                    } else {
                        console.log('[Tablet] Work orders updated in state, will render when tab opens');
                    }
                }
            }).fail(function(err) {
                console.error('[Tablet] getData failed:', err);
            });
        }

        if (data.action === 'updateCatalog') {
            window.mechTabletState.catalog = data.catalog || [];
            const $content = $('.app-window[data-app="cash-register"] .window-content');
            if ($content.length) renderCashRegister($content);
        }

        if (data.action === 'updateStats') {
            window.mechTabletState.stats = data.stats || {};
            window.mechTabletState.employees = data.employees || [];
            const $content = $('.app-window[data-app="management"] .window-content');
            if ($content.length) renderManagement($content);
        }

        if (data.action === 'pos:open') {
            window.posState.business = data.data.business;
            window.posState.items = data.data.items || {};
            window.posState.taxRate = data.data.taxRate || 0;
            window.posState.cart = [];
            const $content = $('.app-window[data-app="cash-register"] .window-content');
            if ($content.length) {
                renderCashRegister($content);
            } else {
                openAppWindow('cash-register', 'Cash Register', '💰');
                const c2 = $('.app-window[data-app="cash-register"] .window-content');
                if (c2.length) renderCashRegister(c2);
            }
        }

        if (data.action === 'pos:close') {
            window.posState.cart = [];
            closeWindow('cash-register');
        }
    });

    // Start timer update interval for work order countdowns
    setInterval(function() {
        const $timers = $('.work-order-timer[data-expires-at]');
        const currentTime = Math.floor(Date.now() / 1000);
        
        $timers.each(function() {
            const $timer = $(this);
            const expiresAt = parseInt($timer.data('expires-at'));
            const timeLeft = Math.max(0, expiresAt - currentTime);
            
            const $timerText = $timer.find('.timer-text');
            $timerText.text(timeLeft + 's');
            
            // Color code based on time remaining
            if (timeLeft <= 10) {
                $timer.addClass('timer-critical');
            } else if (timeLeft <= 20) {
                $timer.addClass('timer-warning');
            } else {
                $timer.removeClass('timer-warning timer-critical');
            }
            
            // If expired, hide the card (server will handle removal)
            if (timeLeft === 0) {
                const $card = $timer.closest('.work-order-card');
                $card.fadeOut(300, function() {
                    $(this).remove();
                });
            }
        });
    }, 1000);
});

// Modal for employee stats
function showEmployeeStatsModal(employee, transactions, workOrders) {
    // Remove any existing modal
    $('.modal-overlay').remove();
    
    const hiredDate = employee.hiredAt ? new Date(employee.hiredAt).toLocaleDateString() : 'N/A';
    const promotedDate = employee.lastPromotedAt ? new Date(employee.lastPromotedAt).toLocaleDateString() : 'N/A';
    
    const modal = $(`
        <div class="modal-overlay">
            <div class="modal-dialog modal-lg">
                <div class="modal-header">
                    <h3>${employee.name} - Stats</h3>
                    <button class="modal-close">&times;</button>
                </div>
                <div class="modal-body">
                    <div class="stats-timeline">
                        <div class="timeline-item">
                            <div class="timeline-label">Hired</div>
                            <div class="timeline-value">${hiredDate}</div>
                        </div>
                        <div class="timeline-item">
                            <div class="timeline-label">Last Promoted</div>
                            <div class="timeline-value">${promotedDate}</div>
                        </div>
                        <div class="timeline-item">
                            <div class="timeline-label">Role</div>
                            <div class="timeline-value">${employee.role.toUpperCase()}</div>
                        </div>
                    </div>
                    
                    <div class="stats-summary">
                        <div class="stat-box">
                            <div class="stat-label">Today's Sales</div>
                            <div class="stat-value">$${(employee.todaySales || 0).toLocaleString()}</div>
                        </div>
                        <div class="stat-box">
                            <div class="stat-label">Last 7 Days</div>
                            <div class="stat-value">$${(employee.last7Sales || 0).toLocaleString()}</div>
                        </div>
                        <div class="stat-box">
                            <div class="stat-label">Last 30 Days</div>
                            <div class="stat-value">$${(employee.last30Sales || 0).toLocaleString()}</div>
                        </div>
                        <div class="stat-box">
                            <div class="stat-label">All Time Sales</div>
                            <div class="stat-value">$${(employee.totalSales || 0).toLocaleString()}</div>
                        </div>
                        <div class="stat-box">
                            <div class="stat-label">Completed Jobs</div>
                            <div class="stat-value">${employee.completedWorkOrders || 0}</div>
                        </div>
                    </div>
                    
                    <div class="employee-actions">
                        <select class="emp-role-select" data-citizenid="${employee.citizenid}">
                            <option value="">-- Change Role --</option>
                            <option value="employee">Employee</option>
                            <option value="manager">Manager</option>
                            ${employee.role !== 'owner' ? '<option value="owner">Owner</option>' : ''}
                        </select>
                        ${employee.role !== 'owner' ? '<button class="emp-btn-promote" data-citizenid="' + employee.citizenid + '">Promote</button>' : ''}
                        ${employee.role !== 'owner' ? '<button class="emp-btn-demote" data-citizenid="' + employee.citizenid + '">Demote</button>' : ''}
                        <button class="emp-btn-fire" data-citizenid="${employee.citizenid}">Fire</button>
                        ${employee.role === 'owner' ? `<button class="emp-btn-transfer-ownership" data-citizenid="${employee.citizenid}" style="background: rgba(255, 59, 48, 0.1); border-color: rgba(255, 59, 48, 0.6); color: #ff3b30;">Transfer Ownership</button>` : ''}
                    </div>
                    
                    <div class="modal-tabs">
                        <button class="modal-tab active" data-tab="transactions">Transactions</button>
                        <button class="modal-tab" data-tab="workorders">Work Orders</button>
                    </div>
                    
                    <div class="modal-tab-content" id="tab-transactions">
                        <input type="text" class="tx-search-input" placeholder="Search by ID, amount, or items..." style="width: 100%; padding: 10px; margin-bottom: 12px; background: rgba(0,0,0,0.3); border: 1px solid rgba(74,158,255,0.3); color: #4a9eff; border-radius: 4px; box-sizing: border-box;">
                        <div class="transaction-list">
                            ${transactions.length > 0 ? transactions.map(tx => {
                                let itemsText = 'N/A';
                                if (tx.items) {
                                    try {
                                        const parsed = JSON.parse(tx.items);
                                        itemsText = parsed.map(i => i.label || i.name).join(', ');
                                    } catch (e) {
                                        itemsText = 'Invalid data';
                                    }
                                }
                                return `
                                <div class="transaction-item" data-tx-id="${tx.transaction_id}" data-tx-amount="${tx.total}" data-tx-items="${itemsText.toLowerCase()}">
                                    <div class="tx-header">
                                        <span class="tx-id">#${tx.transaction_id}</span>
                                        <span class="tx-date">${new Date(tx.created_at).toLocaleString()}</span>
                                        <span class="tx-total">$${tx.total}</span>
                                    </div>
                                    <div class="tx-details">
                                        <div class="tx-items">${itemsText}</div>
                                        <div class="tx-payment">${tx.payment_type || 'cash'}</div>
                                    </div>
                                </div>
                                `;
                            }).join('') : '<div class="empty-state">No transactions found</div>'}
                        </div>
                    </div>
                    
                    <div class="modal-tab-content" id="tab-workorders" style="display: none;">
                        <div class="workorder-list">
                            ${workOrders.length > 0 ? workOrders.map(wo => `
                                <div class="workorder-item">
                                    <div class="wo-header">
                                        <span class="wo-id">#${wo.id}</span>
                                        <span class="wo-type">${wo.type}</span>
                                        <span class="wo-payout">$${wo.payout || 0}</span>
                                    </div>
                                    <div class="wo-details">
                                        <div class="wo-vehicle">${wo.veh_model || 'Unknown'} - ${wo.plate}</div>
                                        <div class="wo-quality">Quality: ${wo.quality || 'N/A'}%</div>
                                        <div class="wo-date"><strong>Completed:</strong> ${new Date(wo.updated_at || wo.created_at).toLocaleString()}</div>
                                    </div>
                                </div>
                            `).join('') : '<div class="empty-state">No completed work orders found</div>'}
                        </div>
                    </div>
                </div>
            </div>
        </div>
    `);
    
    $('body').append(modal);
    
    // Tab switching
    modal.find('.modal-tab').on('click', function() {
        const tab = $(this).data('tab');
        modal.find('.modal-tab').removeClass('active');
        $(this).addClass('active');
        modal.find('.modal-tab-content').hide();
        modal.find('#tab-' + tab).show();
    });
    
    // Transaction search
    modal.find('.tx-search-input').on('input', function() {
        const query = $(this).val().toLowerCase();
        modal.find('.transaction-item').each(function() {
            const txId = $(this).data('tx-id') ? $(this).data('tx-id').toLowerCase() : '';
            const txAmount = $(this).data('tx-amount') ? $(this).data('tx-amount').toString() : '';
            const txItems = $(this).data('tx-items') ? $(this).data('tx-items').toLowerCase() : '';
            
            const matches = txId.includes(query) || txAmount.includes(query) || txItems.includes(query);
            $(this).toggle(matches);
        });
    });
    
    // Employee action handlers
    modal.find('.emp-role-select').on('change', function() {
        const role = $(this).val();
        const cid = $(this).data('citizenid');
        if (!role) return;
        
        console.log('Setting role to:', role, 'for:', cid);
        
        fetch('https://pf-mechanicjob/setEmployeeRole', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({ citizenid: cid, role: role, grade: 0 })
        })
        .then(res => {
            console.log('Role change response status:', res.status);
            return res.text();
        })
        .then(text => {
            console.log('Role change response text:', text);
            try {
                const resp = JSON.parse(text);
                return resp;
            } catch (e) {
                // Response might be plain true
                return text === 'true';
            }
        })
        .then(resp => {
            console.log('Role change parsed response:', resp);
            if (resp === true || resp.success) {
                alert(`Role updated to ${role}`);
                modal.remove();
                // Refresh employees list
                setTimeout(() => {
                    fetch('https://pf-mechanicjob/management:getEmployees', {
                        method: 'POST',
                        headers: {'Content-Type': 'application/json'},
                        body: JSON.stringify({})
                    });
                }, 300);
            } else {
                alert('Failed to update role');
            }
        })
        .catch(err => {
            console.error('Role change error:', err);
            alert('Error updating role: ' + err.message);
        });
    });
    
    modal.find('.emp-btn-transfer-ownership').on('click', function() {
        const ownerCid = $(this).data('citizenid');
        showTransferOwnershipModal(ownerCid, modal);
    });
    
    modal.find('.emp-btn-promote').on('click', function() {
        const cid = $(this).data('citizenid');
        // Prevent self-promotion
        if (cid === window.playerCitizenId) {
            alert('You cannot promote yourself');
            return;
        }
        
        fetch('https://pf-mechanicjob/promoteEmployee', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({ citizenid: cid })
        })
        .then(res => {
            console.log('Promote response status:', res.status);
            return res.json();
        })
        .then(resp => {
            console.log('Promote response:', resp);
            // Close modal and refresh after brief delay for server to process
            modal.remove();
            setTimeout(() => {
                fetch('https://pf-mechanicjob/management:getEmployees', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({})
                });
            }, 500);
        })
        .catch(err => {
            console.error('Promote error:', err);
        });
    });
    
    modal.find('.emp-btn-demote').on('click', function() {
        const cid = $(this).data('citizenid');
        // Prevent self-demotion
        if (cid === window.playerCitizenId) {
            alert('You cannot demote yourself');
            return;
        }
        
        fetch('https://pf-mechanicjob/demoteEmployee', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({ citizenid: cid })
        })
        .then(res => {
            console.log('Demote response status:', res.status);
            return res.json();
        })
        .then(resp => {
            console.log('Demote response:', resp);
            // Close modal and refresh after brief delay for server to process
            modal.remove();
            setTimeout(() => {
                fetch('https://pf-mechanicjob/management:getEmployees', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({})
                });
            }, 500);
        })
        .catch(err => {
            console.error('Demote error:', err);
        });
    });
    
    modal.find('.emp-btn-fire').on('click', function() {
        if (!confirm('Are you sure you want to fire this employee?')) return;
        
        const cid = $(this).data('citizenid');
        fetch('https://pf-mechanicjob/fireEmployee', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({ citizenid: cid })
        })
        .then(res => res.json())
        .then(resp => {
            if (resp === true || resp.success) {
                alert('Employee has been fired');
                modal.remove();
                // Refresh employees list
                setTimeout(() => {
                    fetch('https://pf-mechanicjob/management:getEmployees', {
                        method: 'POST',
                        headers: {'Content-Type': 'application/json'},
                        body: JSON.stringify({})
                    });
                }, 300);
            } else {
                alert('Failed to fire employee');
            }
        })
        .catch(err => {
            console.error('Fire error:', err);
            alert('Error firing employee');
        });
    });
    
    // Close handlers
    modal.find('.modal-close').on('click', () => modal.remove());
    modal.on('click', function(e) {
        if ($(e.target).hasClass('modal-overlay')) {
            modal.remove();
        }
    });
}

// Transfer Ownership Modal
function showTransferOwnershipModal(currentOwnerCid, parentModal) {
    $('.modal-overlay').remove();
    
    // Fetch employees and nearby players
    fetch('https://pf-mechanicjob/getNearbyPlayersAndEmployees', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({})
    })
    .then(res => res.json())
    .then(data => {
        const employees = data.employees || [];
        const nearbyPlayers = data.nearbyPlayers || [];
        
        // Combine and filter out current owner
        const candidates = [
            ...employees.map(e => ({...e, type: 'employee'})),
            ...nearbyPlayers.map(p => ({...p, type: 'nearby'}))
        ].filter(c => c.citizenid !== currentOwnerCid);
        
        const modal = $(`
            <div class="modal-overlay">
                <div class="modal-dialog modal-lg">
                    <div class="modal-header">
                        <h3>Transfer Ownership</h3>
                        <button class="modal-close">&times;</button>
                    </div>
                    <div class="modal-body">
                        <input type="text" class="transfer-search" placeholder="Search by name or citizen ID..." style="width: 100%; padding: 10px; margin-bottom: 15px; background: rgba(0,0,0,0.3); border: 1px solid rgba(74,158,255,0.3); color: #4a9eff; border-radius: 4px;">
                        <div class="transfer-candidates">
                            ${candidates.length > 0 ? candidates.map(c => `
                                <div class="transfer-candidate-row">
                                    <div class="candidate-info">
                                        <div class="candidate-name">${c.name || c.player_name || 'Unknown'}</div>
                                        <div class="candidate-id">${(c.citizenid || '').substring(0, 12)}...</div>
                                        <div class="candidate-type">${c.type === 'employee' ? '👤 Employee' : '📍 Nearby'}</div>
                                    </div>
                                    <button class="btn-transfer" data-citizenid="${c.citizenid}" style="background: rgba(255, 59, 48, 0.1); border: 1px solid rgba(255, 59, 48, 0.6); color: #ff3b30; padding: 8px 16px; border-radius: 4px; cursor: pointer; font-weight: 600;">Transfer</button>
                                </div>
                            `).join('') : '<div class="empty-state">No candidates available</div>'}
                        </div>
                    </div>
                </div>
            </div>
        `);
        
        $('body').append(modal);
        
        // Search functionality
        modal.find('.transfer-search').on('input', function() {
            const query = $(this).val().toLowerCase();
            modal.find('.transfer-candidate-row').each(function() {
                const name = $(this).find('.candidate-name').text().toLowerCase();
                const id = $(this).find('.candidate-id').text().toLowerCase();
                const matches = name.includes(query) || id.includes(query);
                $(this).toggle(matches);
            });
        });
        
        // Transfer button
        modal.find('.btn-transfer').on('click', function() {
            const newOwnerCid = $(this).data('citizenid');
            if (!confirm('Are you sure? This will make you unemployed.')) return;
            
            fetch('https://pf-mechanicjob/transferOwnership', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({ newOwnerCid: newOwnerCid })
            })
            .then(res => res.text())
            .then(text => {
                try {
                    return JSON.parse(text);
                } catch (e) {
                    return text === 'true';
                }
            })
            .then(resp => {
                if (resp === true || resp.success) {
                    alert('Ownership transferred successfully');
                    modal.remove();
                    if (parentModal) parentModal.remove();
                    setTimeout(() => {
                        fetch('https://pf-mechanicjob/management:getEmployees', {
                            method: 'POST',
                            headers: {'Content-Type': 'application/json'},
                            body: JSON.stringify({})
                        });
                    }, 300);
                } else {
                    alert('Failed to transfer ownership');
                }
            })
            .catch(err => {
                console.error('Transfer error:', err);
                alert('Error transferring ownership: ' + err.message);
            });
        });
        
        // Close handlers
        modal.find('.modal-close').on('click', () => modal.remove());
        modal.on('click', function(e) {
            if ($(e.target).hasClass('modal-overlay')) {
                modal.remove();
            }
        });
    })
    .catch(err => {
        console.error('Fetch candidates error:', err);
        alert('Error loading candidates');
    });
}

// Modal for price editing
function showPriceEditModal(item, productName, currentPrice) {
    // Remove any existing modal
    $('.modal-overlay').remove();
    
    const modal = $(`
        <div class="modal-overlay">
            <div class="modal-dialog modal-sm">
                <div class="modal-header">
                    <h3>Edit Price</h3>
                    <button class="modal-close">&times;</button>
                </div>
                <div class="modal-body">
                    <div class="form-group">
                        <label>${productName}</label>
                        <div class="price-input-group">
                            <span class="price-prefix">$</span>
                            <input type="number" id="price-input" class="form-input" value="${currentPrice}" min="0" step="1">
                        </div>
                    </div>
                </div>
                <div class="modal-footer">
                    <button class="btn btn-secondary modal-cancel">Cancel</button>
                    <button class="btn btn-primary modal-save">Save</button>
                </div>
            </div>
        </div>
    `);
    
    $('body').append(modal);
    
    // Focus input
    modal.find('#price-input').focus().select();
    
    // Save handler
    modal.find('.modal-save').on('click', function() {
        const newPrice = parseInt(modal.find('#price-input').val());
        if (isNaN(newPrice) || newPrice < 0) {
            alert('Please enter a valid price');
            return;
        }
        
        fetch('https://pf-mechanicjob/updateProductPrice', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({ productItem: item, newPrice: newPrice })
        })
        .then(res => res.json())
        .then(resp => {
            if (resp.success) {
                modal.remove();
                // Refresh management data
                QBCore.Functions.TriggerCallback('pf_mechanic:getManagementData', function(mgmtData) {
                    if (mgmtData) {
                        window.tabletMgmtState = mgmtData;
                        renderManagement($('.app-window[data-app="management"] .window-content'));
                    }
                });
            } else {
                alert('Error updating price: ' + (resp.message || 'Unknown error'));
            }
        });
    });
    
    // Close handlers
    modal.find('.modal-close, .modal-cancel').on('click', () => modal.remove());
    modal.on('click', function(e) {
        if ($(e.target).hasClass('modal-overlay')) {
            modal.remove();
        }
    });
    
    // Enter key to save
    modal.find('#price-input').on('keypress', function(e) {
        if (e.which === 13) {
            modal.find('.modal-save').click();
        }
    });
}

function showTransactionDetailModal(transaction) {
    // Parse items array
    let itemsList = [];
    if (transaction.items && Array.isArray(transaction.items)) {
        itemsList = transaction.items;
    } else if (typeof transaction.items === 'string') {
        try {
            itemsList = JSON.parse(transaction.items);
        } catch(e) {
            itemsList = [];
        }
    }

    // Get customer name from server
    let customerName = 'Unknown';
    if (transaction.customer_id) {
        $.post('https://pf-mechanicjob/pos/getCustomerName', JSON.stringify({ customerId: transaction.customer_id }), function(resp) {
            if (resp && resp.name) {
                customerName = resp.name;
                // Update the modal with the customer name
                $('.tx-party-value').filter(function(i) {
                    return i === 1; // Second party value (customer)
                }).text(customerName);
            }
        });
    }

    // Create items HTML rows
    const itemsHTML = itemsList.map(item => {
        const qty = item.qty || 1;
        const label = item.label || item.name || 'Item';
        const price = parseFloat(item.price || 0);
        const lineTotal = (qty * price).toFixed(2);
        
        return `
            <div class="tx-item-row">
                <div class="tx-item-qty">${qty}x</div>
                <div class="tx-item-label">${label}</div>
                <div class="tx-item-price">€${price.toFixed(2)}</div>
                <div class="tx-item-total">€${lineTotal}</div>
            </div>
        `;
    }).join('');

    // Format date
    const dateStr = new Date(transaction.created_at).toLocaleString();
    
    // Create modal HTML
    const modalHTML = `
        <div class="tx-modal-overlay">
            <div class="tx-modal-dialog">
                <div class="tx-modal-header">
                    <h2>Transaction Details</h2>
                    <button class="tx-modal-close" style="background: none; border: none; font-size: 24px; cursor: pointer; color: #999;">×</button>
                </div>
                
                <div class="tx-modal-content">
                    <!-- Header Info -->
                    <div class="tx-header-info">
                        <div class="tx-info-pair">
                            <span class="tx-label">Order ID:</span>
                            <span class="tx-value">${transaction.transaction_id}</span>
                        </div>
                        <div class="tx-info-pair">
                            <span class="tx-label">Status:</span>
                            <span class="tx-value tx-status-${transaction.status || 'completed'}">${transaction.status || 'Completed'}</span>
                        </div>
                        <div class="tx-info-pair">
                            <span class="tx-label">Date:</span>
                            <span class="tx-value">${dateStr}</span>
                        </div>
                    </div>

                    <!-- Mechanic & Customer Info -->
                    <div class="tx-parties-info">
                        <div class="tx-party-block">
                            <div class="tx-party-label">Mechanic</div>
                            <div class="tx-party-value">${transaction.mechanic_name || 'Unknown'}</div>
                        </div>
                        <div class="tx-party-block">
                            <div class="tx-party-label">Customer ID</div>
                            <div class="tx-party-value">${transaction.customer_id || 'N/A'}</div>
                        </div>
                        <div class="tx-party-block">
                            <div class="tx-party-label">Payment Method</div>
                            <div class="tx-party-value">${transaction.payment_type || 'Unknown'}</div>
                        </div>
                    </div>

                    <!-- Items List -->
                    <div class="tx-items-section">
                        <h3>Items Purchased</h3>
                        <div class="tx-items-list">
                            <div class="tx-item-header">
                                <div class="tx-item-qty">Qty</div>
                                <div class="tx-item-label">Item</div>
                                <div class="tx-item-price">Price</div>
                                <div class="tx-item-total">Total</div>
                            </div>
                            ${itemsHTML || '<div class="tx-empty-items">No items recorded</div>'}
                        </div>
                    </div>

                    <!-- Totals -->
                    <div class="tx-totals-section">
                        <div class="tx-total-row">
                            <span>Subtotal:</span>
                            <span>€${(transaction.subtotal || 0).toFixed(2)}</span>
                        </div>
                        <div class="tx-total-row">
                            <span>Tax:</span>
                            <span>€${(transaction.tax || 0).toFixed(2)}</span>
                        </div>
                        <div class="tx-total-row tx-final-total">
                            <span>Total:</span>
                            <span>€${(transaction.total || 0).toFixed(2)}</span>
                        </div>
                    </div>
                </div>

                <div class="tx-modal-footer">
                    <button class="tx-modal-btn-close">Close</button>
                </div>
            </div>
        </div>
    `;

    // Create modal element
    const $modal = $(modalHTML);

    // Add to tablet screen (for proper z-index stacking)
    const $tabletScreen = $('.tablet-screen');
    if ($tabletScreen.length) {
        $tabletScreen.append($modal);
    } else {
        $('body').append($modal);
    }

    // Close handlers
    $modal.on('click', '.tx-modal-close, .tx-modal-btn-close', function(e) {
        e.stopPropagation();
        $modal.fadeOut(200, function() { $(this).remove(); });
    });

    $modal.on('click', '.tx-modal-overlay', function(e) {
        if ($(e.target).hasClass('tx-modal-overlay')) {
            $modal.fadeOut(200, function() { $(this).remove(); });
        }
    });

    // ESC key to close
    $(document).on('keydown.transactionmodal', function(e) {
        if (e.key === 'Escape') {
            $modal.fadeOut(200, function() { $(this).remove(); });
            $(document).off('keydown.transactionmodal');
        }
    });

    // Fade in animation
    $modal.css('opacity', '0').css('display', 'flex').animate({ opacity: 1 }, 200);
}

function GetParentResourceName() {
    return 'pf-mechanicjob';
}
