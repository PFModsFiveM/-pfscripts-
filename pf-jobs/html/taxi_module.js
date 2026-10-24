(function () {
    const TAXI_RESOURCE = (window.PFTablet && window.PFTablet.resourceName)
        || (typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'pf-tablet');

    const taxiState = {
        initialized: false,
        currentTab: 'dashboard',
        dashboard: null,
        calls: [],
        activeRide: null,
        autoRefreshInterval: null,
    };

    function post(callback, payload, onDone) {
        $.post(`https://${TAXI_RESOURCE}/${callback}`, JSON.stringify(payload || {}), function (resp) {
            if (typeof onDone === 'function') onDone(resp);
        });
    }

    function escapeHtml(value) {
        return String(value ?? '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#039;');
    }

    function formatMoney(num) {
        return `$${Number(num || 0).toLocaleString()}`;
    }

    function getRoot() {
        return $('.app-window[data-app="taxi"] .window-content');
    }

    function renderHeader() {
        const dashboard = taxiState.dashboard || {};
        const accepting = dashboard.accepting === true;
        return `
            <div class="taxi-app-shell">
                <div class="taxi-app-header">
                    <div class="taxi-header-left">
                        <div class="taxi-header-icon">🚕</div>
                        <div>
                            <div class="taxi-header-title">Taxi Dispatch</div>
                            <div class="taxi-header-subtitle">${escapeHtml(dashboard.levelTitle || 'Driver')} • Level ${dashboard.level || 1}</div>
                        </div>
                    </div>
                    <div class="taxi-header-actions">
                        <button class="taxi-accept-toggle ${accepting ? 'on' : 'off'}" data-action="taxi-toggle-accepting">
                            ${accepting ? 'Accepting Rides' : 'Not Accepting'}
                        </button>
                        <button class="taxi-refresh-btn" data-action="taxi-refresh">Refresh</button>
                    </div>
                </div>
                <div class="taxi-tabs-row">
                    <button class="taxi-tab ${taxiState.currentTab === 'dashboard' ? 'active' : ''}" data-tab="dashboard">Dashboard</button>
                    <button class="taxi-tab ${taxiState.currentTab === 'calls' ? 'active' : ''}" data-tab="calls">Ride Calls</button>
                    <button class="taxi-tab ${taxiState.currentTab === 'levels' ? 'active' : ''}" data-tab="levels">Levels</button>
                    <button class="taxi-tab ${taxiState.currentTab === 'rentals' ? 'active' : ''}" data-tab="rentals">Vehicle Rentals</button>
                </div>
                <div class="taxi-app-body" id="taxi-app-body">
                    ${renderTabBody()}
                </div>
            </div>
        `;
    }

    function renderDashboardTab() {
        const dashboard = taxiState.dashboard || {};
        const activeRide = dashboard.activeRide || taxiState.activeRide;
        const unlocks = dashboard.unlocks || {};

        return `
            <div class="taxi-dashboard-grid">
                <div class="taxi-stat-card">
                    <div class="taxi-stat-label">Accepting Rides</div>
                    <div class="taxi-stat-value">${dashboard.accepting ? 'Yes' : 'No'}</div>
                </div>
                <div class="taxi-stat-card">
                    <div class="taxi-stat-label">Rating</div>
                    <div class="taxi-stat-value">${Number(dashboard.rating || 5).toFixed(1)} ⭐</div>
                </div>
                <div class="taxi-stat-card">
                    <div class="taxi-stat-label">Rides This Run</div>
                    <div class="taxi-stat-value">${dashboard.ridesCompletedRun || 0}</div>
                </div>
                <div class="taxi-stat-card taxi-earnings">
                    <div class="taxi-stat-label">Run Earnings</div>
                    <div class="taxi-stat-value">${formatMoney(dashboard.earningsRun || 0)}</div>
                </div>
            </div>

            <div class="taxi-panel-grid">
                <div class="taxi-panel">
                    <div class="taxi-panel-title">Current Ride</div>
                    ${activeRide ? `
                        <div class="taxi-current-ride">
                            <div><strong>Client:</strong> ${escapeHtml(activeRide.clientName || 'Unknown')}</div>
                            <div><strong>Destination:</strong> ${escapeHtml(activeRide.destination && activeRide.destination.label || 'Destination')}</div>
                            <div><strong>Type:</strong> ${activeRide.playerClient ? 'Player Client' : activeRide.premium ? 'Premium' : 'Standard'}</div>
                        </div>
                        <div class="taxi-action-row">
                            <button data-action="taxi-cancel-ride" class="taxi-danger-btn">Cancel Ride</button>
                        </div>
                    ` : '<div class="taxi-empty">No active ride</div>'}
                </div>

                <div class="taxi-panel">
                    <div class="taxi-panel-title">Unlock Progress</div>
                    <ul class="taxi-unlock-list">
                        <li>Private Vehicle Access: <strong>Level ${unlocks.privateVehicleLevel || 4}</strong></li>
                        <li>Premium Clients: <strong>Level ${unlocks.premiumClientLevel || 3}</strong></li>
                        <li>Luxury Vehicles: <strong>Level ${unlocks.luxuryVehicleLevel || 5}</strong></li>
                    </ul>
                    ${dashboard.nextLevel ? `<div class="taxi-next-level">Next: L${dashboard.nextLevel.level} • ${escapeHtml(dashboard.nextLevel.unlocks || '')}</div>` : '<div class="taxi-next-level">Max level reached</div>'}
                </div>
            </div>
        `;
    }

    function renderCallsTab() {
        if (!taxiState.calls || taxiState.calls.length === 0) {
            return `<div class="taxi-empty">No calls available. Turn on accepting rides and refresh.</div>`;
        }

        return `
            <div class="taxi-calls-list">
                ${taxiState.calls.map(call => `
                    <div class="taxi-call-card">
                        <div class="taxi-call-top">
                            <div class="taxi-call-client">${escapeHtml(call.clientName || 'Client')}</div>
                            <div class="taxi-call-badges">
                                ${call.playerClient ? '<span class="taxi-badge player">Player Client</span>' : ''}
                                ${call.premium ? '<span class="taxi-badge premium">Premium</span>' : '<span class="taxi-badge standard">Standard</span>'}
                            </div>
                        </div>
                        <div class="taxi-call-meta">
                            <div><strong>Destination:</strong> ${escapeHtml(call.destination && call.destination.label || 'Unknown')}</div>
                            <div><strong>Distance:</strong> ${Number(call.distanceMiles || 0).toFixed(1)} mi</div>
                            <div><strong>Estimated Pay:</strong> ${call.playerClient ? 'Hidden (Player Ride)' : formatMoney(call.payPreview || 0)}</div>
                        </div>
                        <div class="taxi-call-actions">
                            <button data-action="taxi-accept-call" data-call='${encodeURIComponent(JSON.stringify(call))}' class="taxi-primary-btn">Accept Call</button>
                        </div>
                    </div>
                `).join('')}
            </div>
        `;
    }

    function renderLevelsTab() {
        const levels = (taxiState.dashboard && taxiState.dashboard.levels) || [];
        const current = (taxiState.dashboard && taxiState.dashboard.level) || 1;

        if (!levels.length) {
            return `<div class="taxi-empty">No level data available.</div>`;
        }

        return `
            <div class="taxi-levels-list">
                ${levels.map(level => `
                    <div class="taxi-level-card ${current >= (level.level || 1) ? 'unlocked' : ''}">
                        <div class="taxi-level-top">
                            <div class="taxi-level-name">Level ${level.level} • ${escapeHtml(level.title || 'Taxi Driver')}</div>
                            <div class="taxi-level-xp">XP ${level.xp || 0}</div>
                        </div>
                        <div class="taxi-level-unlocks">${escapeHtml(level.unlocks || '')}</div>
                    </div>
                `).join('')}
            </div>
        `;
    }

    function renderRentalsTab() {
        const dashboard = taxiState.dashboard || {};
        const currentLevel = dashboard.level || 1;
        const rentals = dashboard.rentalVehicles || [];

        if (!rentals.length) {
            return `<div class="taxi-empty">No rental vehicles configured.</div>`;
        }

        return `
            <div class="taxi-rental-grid">
                ${rentals.map(vehicle => {
                    const unlock = vehicle.unlockLevel || 1;
                    const locked = currentLevel < unlock;
                    return `
                        <div class="taxi-rental-card ${locked ? 'locked' : ''}">
                            <div class="taxi-rental-image-wrap">
                                <img src="${escapeHtml(vehicle.image || '')}" alt="${escapeHtml(vehicle.name || vehicle.spawnCode || 'vehicle')}" class="taxi-rental-image" onerror="this.style.display='none'" />
                            </div>
                            <div class="taxi-rental-name">${escapeHtml(vehicle.name || vehicle.spawnCode || 'Vehicle')}</div>
                            <div class="taxi-rental-meta">Unlock: Level ${unlock}</div>
                            <div class="taxi-rental-meta">Max Capacity: ${vehicle.maxCapacity || 2}</div>
                            <div class="taxi-rental-meta">Rental: ${formatMoney(vehicle.rental || 0)}</div>
                            <div class="taxi-rental-meta">Deposit: ${formatMoney(vehicle.deposit || 0)}</div>
                            <div class="taxi-rental-actions">
                                <button data-action="taxi-rent" data-vehicle='${encodeURIComponent(JSON.stringify(vehicle))}' class="taxi-primary-btn" ${locked ? 'disabled' : ''}>${locked ? 'Locked' : 'Rent Vehicle'}</button>
                            </div>
                        </div>
                    `;
                }).join('')}
            </div>
            <div class="taxi-rental-footer">
                <button data-action="taxi-return-rental" class="taxi-secondary-btn">Return Current Rental</button>
            </div>
        `;
    }

    function renderTabBody() {
        if (taxiState.currentTab === 'dashboard') return renderDashboardTab();
        if (taxiState.currentTab === 'calls') return renderCallsTab();
        if (taxiState.currentTab === 'levels') return renderLevelsTab();
        return renderRentalsTab();
    }

    function rerender() {
        const $root = getRoot();
        if (!$root.length) return;
        $root.html(renderHeader());
    }

    function refreshInit() {
        post('taxi:getInit', {}, function (resp) {
            taxiState.dashboard = (resp && resp.state) || (resp || {}).state || taxiState.dashboard;
            taxiState.initialized = true;
            
            // Setup auto-refresh if already accepting rides
            if (taxiState.dashboard && taxiState.dashboard.accepting) {
                if (taxiState.autoRefreshInterval) clearInterval(taxiState.autoRefreshInterval);
                taxiState.autoRefreshInterval = setInterval(refreshCalls, 5000); // Refresh every 5 seconds
            }
            
            rerender();
        });
    }

    function refreshCalls() {
        post('taxi:getCalls', {}, function (resp) {
            const calls = (resp && resp.calls) || [];
            taxiState.calls = Array.isArray(calls) ? calls : [];
            if (taxiState.currentTab === 'calls') rerender();
        });
    }

    function bindHandlers() {
        $(document).off('click.taxi.tab').on('click.taxi.tab', '.taxi-tab', function () {
            taxiState.currentTab = String($(this).data('tab') || 'dashboard');
            rerender();
            if (taxiState.currentTab === 'calls') refreshCalls();
        });

        $(document).off('click.taxi.action').on('click.taxi.action', '[data-action]', function () {
            const action = String($(this).attr('data-action') || '');

            if (action === 'taxi-refresh') {
                refreshInit();
                refreshCalls();
                return;
            }

            if (action === 'taxi-toggle-accepting') {
                const accepting = !((taxiState.dashboard && taxiState.dashboard.accepting) === true);
                post('taxi:toggleAccepting', { accepting }, function () {
                    if (!taxiState.dashboard) taxiState.dashboard = {};
                    taxiState.dashboard.accepting = accepting;
                    rerender();
                    
                    // Always refresh calls
                    refreshCalls();
                    
                    // Start auto-refresh when accepting rides
                    if (accepting) {
                        if (taxiState.autoRefreshInterval) clearInterval(taxiState.autoRefreshInterval);
                        taxiState.autoRefreshInterval = setInterval(refreshCalls, 5000); // Refresh every 5 seconds
                    } else {
                        // Stop auto-refresh when not accepting
                        if (taxiState.autoRefreshInterval) {
                            clearInterval(taxiState.autoRefreshInterval);
                            taxiState.autoRefreshInterval = null;
                        }
                    }
                });
                return;
            }

            if (action === 'taxi-accept-call') {
                let call = null;
                try {
                    call = JSON.parse(decodeURIComponent($(this).attr('data-call') || '%7B%7D'));
                } catch (_) {
                    call = null;
                }
                if (!call || !call.id) return;

                post('taxi:acceptCall', call, function () {
                    taxiState.activeRide = call;
                    taxiState.currentTab = 'dashboard';
                    rerender();
                });
                return;
            }

            if (action === 'taxi-cancel-ride') {
                const rideId = (taxiState.dashboard && taxiState.dashboard.activeRide && taxiState.dashboard.activeRide.id) || null;
                post('taxi:cancelRide', { rideId }, function () {
                    taxiState.activeRide = null;
                    if (taxiState.dashboard) taxiState.dashboard.activeRide = null;
                    rerender();
                });
                return;
            }

            if (action === 'taxi-rent') {
                let vehicle = null;
                try {
                    vehicle = JSON.parse(decodeURIComponent($(this).attr('data-vehicle') || '%7B%7D'));
                } catch (_) {
                    vehicle = null;
                }
                if (!vehicle || !vehicle.spawnCode) return;
                post('taxi:rentVehicle', vehicle, function () { });
                return;
            }

            if (action === 'taxi-return-rental') {
                post('taxi:returnVehicle', {}, function () { });
            }
        });
    }

    window.addEventListener('message', function (event) {
        const data = event.data || {};

        if (data.action === 'taxi:init') {
            taxiState.dashboard = data.state || taxiState.dashboard;
            taxiState.initialized = true;
            rerender();
            return;
        }

        if (data.action === 'taxi:updateStats') {
            taxiState.dashboard = data.stats || taxiState.dashboard;
            rerender();
            return;
        }

        if (data.action === 'taxi:callsData') {
            taxiState.calls = Array.isArray(data.calls) ? data.calls : [];
            if (taxiState.currentTab === 'calls') rerender();
            return;
        }

        if (data.action === 'taxi:rideStarted' || data.action === 'taxi:startCall') {
            taxiState.activeRide = (data.ride || data.data || null);
            if (!taxiState.dashboard) taxiState.dashboard = {};
            taxiState.dashboard.activeRide = taxiState.activeRide;
            taxiState.currentTab = 'dashboard';
            rerender();
            return;
        }

        if (data.action === 'taxi:rideCompleted' || data.action === 'taxi:rideCancelled') {
            taxiState.activeRide = null;
            if (taxiState.dashboard) taxiState.dashboard.activeRide = null;
            refreshInit();
            refreshCalls();
            
            // Restart auto-refresh if still accepting rides
            if (taxiState.dashboard && taxiState.dashboard.accepting) {
                if (taxiState.autoRefreshInterval) clearInterval(taxiState.autoRefreshInterval);
                taxiState.autoRefreshInterval = setInterval(refreshCalls, 5000);
            } else {
                if (taxiState.autoRefreshInterval) {
                    clearInterval(taxiState.autoRefreshInterval);
                    taxiState.autoRefreshInterval = null;
                }
            }
        }
    });

    function renderTaxiWindow(appName) {
        const $content = $(`.app-window[data-app="${appName}"] .window-content`);
        if (!$content.length) return;

        taxiState.currentTab = 'dashboard';
        $content.html('<div class="taxi-app-shell"><div class="taxi-empty">Loading Taxi Dispatch...</div></div>');

        bindHandlers();
        refreshInit();
        refreshCalls();
    }

    window.renderTaxiWindow = renderTaxiWindow;
    window.PFJobsTablet = window.PFJobsTablet || {};
    window.PFJobsTablet.renderTaxiWindow = renderTaxiWindow;
})();
