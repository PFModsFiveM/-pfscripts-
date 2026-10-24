(function () {
    const TAXI_RESOURCE = (window.PFTablet && window.PFTablet.resourceName)
        || (typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'pf-tablet');

    const taxiState = {
        initialized: false,
        currentTab: 'dashboard',
        dashboard: null,
        calls: [],
        activeRide: null,
        levelCardIndex: 0,
        autoRefreshInterval: null,
        photos: [],
        meter: {
            visible: false,
            onJob: false,
            inTaxi: false,
            currentFare: 0,
            distance: 0,
            rate: 60,
            collisions: 0,
            passengerName: 'Customer',
            passengerType: 'standard',
        },
    };

    function post(callback, payload, onDone) {
        $.post(`https://${TAXI_RESOURCE}/${callback}`, JSON.stringify(payload || {}))
            .done(function (resp) {
                if (typeof onDone === 'function') onDone(resp);
            })
            .fail(function () {
                console.error(`[Taxi] Failed to call ${callback}`);
                if (typeof onDone === 'function') onDone({ ok: false });
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

    function getCurrentLevel() {
        return Number((taxiState.dashboard && taxiState.dashboard.level) || 1);
    }

    function getLevels() {
        return (taxiState.dashboard && taxiState.dashboard.levels) || [];
    }

    function getNextLevelInfo(level) {
        return getLevels().find(item => Number(item.level || 1) > Number(level || 1)) || null;
    }

    function getVisibleCalls() {
        const level = getCurrentLevel();
        return (taxiState.calls || []).filter(call => Number(call.requiredLevel || 1) <= level);
    }

    function getMeterState() {
        const meter = taxiState.meter || {};
        return {
            visible: meter.visible === true,
            onJob: meter.onJob === true,
            inTaxi: meter.inTaxi === true,
            currentFare: Number(meter.currentFare || 0),
            distance: Number(meter.distance || 0),
            rate: Number(meter.rate || 60),
            collisions: Number(meter.collisions || 0),
            passengerName: meter.passengerName || 'Customer',
            passengerType: meter.passengerType || 'standard',
        };
    }

    function renderHeader() {
        const dashboard = taxiState.dashboard || {};
        const accepting = dashboard.accepting === true;
        const level = getCurrentLevel();
        const levelTitle = dashboard.levelTitle || 'Driver';
        const visibleCalls = getVisibleCalls();

        return `
            <div class="taxi-app-shell">
                <div class="taxi-app-header">
                    <div class="taxi-header-left">
                        <div class="taxi-header-icon">🚕</div>
                        <div class="taxi-header-copy">
                            <div class="taxi-header-title">Taxi Dispatch Center</div>
                            <div class="taxi-header-subtitle">${escapeHtml(levelTitle)} • Level ${level}</div>
                        </div>
                    </div>
                    <div class="taxi-header-actions">
                        <button class="taxi-accept-toggle ${accepting ? 'on' : 'off'}" data-action="taxi-toggle-accepting">
                            ${accepting ? 'Stop Accepting' : 'Start Accepting'}
                        </button>
                        <button class="taxi-refresh-btn" data-action="taxi-refresh">Refresh</button>
                    </div>
                </div>

                <div class="taxi-tabs-row">
                    <button class="taxi-tab ${taxiState.currentTab === 'dashboard' ? 'active' : ''}" data-tab="dashboard">Dashboard</button>
                    <button class="taxi-tab ${taxiState.currentTab === 'calls' ? 'active' : ''}" data-tab="calls">All Calls (${visibleCalls.length})</button>
                    <button class="taxi-tab ${taxiState.currentTab === 'levels' ? 'active' : ''}" data-tab="levels">Levels</button>
                    <button class="taxi-tab ${taxiState.currentTab === 'rentals' ? 'active' : ''}" data-tab="rentals">Rentals</button>
                    <button class="taxi-tab ${taxiState.currentTab === 'photos' ? 'active' : ''}" data-tab="photos">Photos</button>
                </div>

                <div class="taxi-content-wrapper">
                    <div class="taxi-app-body" id="taxi-app-body">
                        ${renderTabBody()}
                    </div>
                    <aside class="taxi-calls-sidebar">
                        ${renderCallsSidebar()}
                    </aside>
                </div>
            </div>
        `;
    }

    function renderCallsSidebar() {
        const calls = getVisibleCalls().slice(0, 4);
        const total = getVisibleCalls().length;

        if (!calls.length) {
            return `
                <div class="taxi-sidebar-header">
                    <div class="taxi-sidebar-title">Active Calls</div>
                    <div class="taxi-sidebar-count">0</div>
                </div>
                <div class="taxi-sidebar-content">
                    <div class="taxi-empty-sidebar">No eligible calls right now.</div>
                </div>
            `;
        }

        return `
            <div class="taxi-sidebar-header">
                <div class="taxi-sidebar-title">Active Calls</div>
                <div class="taxi-sidebar-count">${total}</div>
            </div>
            <div class="taxi-sidebar-content">
                ${calls.map(call => `
                    <div class="taxi-sidebar-call ${call.vip ? 'vip' : ''}">
                        <div class="taxi-sidebar-call-client">${escapeHtml(call.clientName || 'Client')} ${call.vip ? '👑' : ''}</div>
                        <div class="taxi-sidebar-call-dest">${escapeHtml((call.destination && call.destination.label) || 'Unknown')}</div>
                        <div class="taxi-sidebar-call-pay">${call.playerClient ? 'Player Ride' : formatMoney(call.payPreview || 0)}</div>
                        <button data-action="taxi-accept-call" data-call='${encodeURIComponent(JSON.stringify(call))}' class="taxi-sidebar-accept-btn">Accept Call</button>
                    </div>
                `).join('')}
                ${total > 4 ? `<div class="taxi-sidebar-more">+${total - 4} more in All Calls</div>` : ''}
            </div>
        `;
    }

    function renderDashboardTab() {
        const dashboard = taxiState.dashboard || {};

        if (!dashboard.level && !taxiState.initialized) {
            return `<div class="taxi-empty">Loading dashboard data...</div>`;
        }

        return `
            <div class="taxi-dashboard-grid">
                <div class="taxi-stat-card">
                    <div class="taxi-stat-label">Ratings</div>
                    <div class="taxi-stat-value">${Number(dashboard.rating || 5).toFixed(1)} ⭐</div>
                </div>
                <div class="taxi-stat-card taxi-earnings">
                    <div class="taxi-stat-label">Earnings</div>
                    <div class="taxi-stat-value">${formatMoney(dashboard.earningsRun || 0)}</div>
                </div>
                <div class="taxi-stat-card">
                    <div class="taxi-stat-label">Current XP</div>
                    <div class="taxi-stat-value">${Math.floor(dashboard.xp || 0)}</div>
                </div>
                <div class="taxi-stat-card">
                    <div class="taxi-stat-label">Driver Rating</div>
                    <div class="taxi-stat-value">${Number(dashboard.rating || 5).toFixed(1)} ⭐</div>
                </div>
            </div>

            <div class="taxi-panel-grid">
                <section class="taxi-panel">
                    <div class="taxi-section-title">Statistics</div>
                    <div class="taxi-stats-grid">
                        <div class="taxi-mini-stat">
                            <div class="taxi-mini-stat-value">${dashboard.totalRides || 0}</div>
                            <div class="taxi-mini-stat-label">Total Rides</div>
                        </div>
                        <div class="taxi-mini-stat">
                            <div class="taxi-mini-stat-value">${formatMoney(dashboard.totalEarnings || 0)}</div>
                            <div class="taxi-mini-stat-label">Total Earned</div>
                        </div>
                        <div class="taxi-mini-stat">
                            <div class="taxi-mini-stat-value">${Number(dashboard.totalMiles || 0).toFixed(1)}</div>
                            <div class="taxi-mini-stat-label">Miles Driven</div>
                        </div>
                    </div>
                </section>

                <section class="taxi-panel">
                    <div class="taxi-section-title">Taxi Meter</div>
                    ${renderMeterPanel()}
                </section>
            </div>
        `;
    }

    function renderMeterPanel() {
        const meter = getMeterState();

        if (!(meter.visible && meter.onJob && meter.inTaxi)) {
            return `
                <div class="taxi-empty">
                    Meter is inactive.<br>
                    <small>It appears only while driving a taxi during an active job.</small>
                </div>
            `;
        }

        const collisionPenaltyPct = Math.min(100, meter.collisions * 5);
        return `
            <div class="taxi-meter-card ${meter.passengerType}">
                <div class="taxi-meter-row">
                    <div class="taxi-meter-label">Passenger</div>
                    <div class="taxi-meter-value">${escapeHtml(meter.passengerName)}</div>
                </div>
                <div class="taxi-meter-row">
                    <div class="taxi-meter-label">Cab Fare</div>
                    <div class="taxi-meter-fare">${formatMoney(meter.currentFare)}</div>
                </div>
                <div class="taxi-meter-grid">
                    <div class="taxi-meter-chip">Distance: ${meter.distance.toFixed(2)} mi</div>
                    <div class="taxi-meter-chip">Rate: ${formatMoney(meter.rate)}/mi</div>
                    <div class="taxi-meter-chip warn">Collisions: ${meter.collisions}</div>
                    <div class="taxi-meter-chip warn">Penalty: -${collisionPenaltyPct}%</div>
                </div>
            </div>
        `;
    }

    function renderCallsTab() {
        const dashboard = taxiState.dashboard || {};
        const accepting = dashboard.accepting === true;
        const calls = getVisibleCalls();

        if (!accepting) {
            return `<div class="taxi-empty">Enable accepting rides to receive calls.</div>`;
        }

        if (!calls.length) {
            return `<div class="taxi-empty">No eligible calls available for your current level.</div>`;
        }

        return `
            <div class="taxi-calls-list">
                ${calls.map(call => `
                    <div class="taxi-call-card ${call.vip ? 'vip' : ''}">
                        <div class="taxi-call-top">
                            <div class="taxi-call-client">${escapeHtml(call.clientName || 'Client')} ${call.vip ? '👑' : ''}</div>
                            <div class="taxi-call-badges">
                                ${call.vip ? '<span class="taxi-badge vip">VIP</span>' : ''}
                                ${call.playerClient ? '<span class="taxi-badge player">Player</span>' : ''}
                                ${call.premium && !call.vip ? '<span class="taxi-badge premium">Premium</span>' : '<span class="taxi-badge standard">Standard</span>'}
                            </div>
                        </div>
                        <div class="taxi-call-meta">
                            <div><strong>Destination:</strong> ${escapeHtml(call.destination && call.destination.label || 'Unknown')}</div>
                            <div><strong>Distance:</strong> ${Number(call.distanceMiles || 0).toFixed(1)} mi</div>
                            <div><strong>Required Level:</strong> ${Number(call.requiredLevel || 1)}</div>
                            <div><strong>Estimated Pay:</strong> ${call.playerClient ? 'Hidden' : formatMoney(call.payPreview || 0)}</div>
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
        const dashboard = taxiState.dashboard || {};
        const levels = getLevels();
        const currentLevel = getCurrentLevel();
        const currentXP = Number(dashboard.xp || 0);

        if (!levels.length) {
            return `<div class="taxi-empty">No level data available.</div>`;
        }

        taxiState.levelCardIndex = Math.max(0, Math.min(taxiState.levelCardIndex, levels.length - 1));
        const selected = levels[taxiState.levelCardIndex] || levels[0];
        const selectedLevel = Number(selected.level || 1);
        const selectedXP = Number(selected.xp || 0);
        const nextLevel = levels.find(level => Number(level.level || 1) > selectedLevel) || null;

        let progressPct = 0;
        if (selectedLevel < currentLevel) {
            progressPct = 100;
        } else if (selectedLevel === currentLevel) {
            if (!nextLevel) {
                progressPct = 100;
            } else {
                const nextXP = Number(nextLevel.xp || selectedXP);
                const span = Math.max(1, nextXP - selectedXP);
                progressPct = Math.max(0, Math.min(100, ((currentXP - selectedXP) / span) * 100));
            }
        }

        return `
            <div class="taxi-level-browser">
                <button class="taxi-carousel-arrow" data-action="taxi-level-prev" ${taxiState.levelCardIndex === 0 ? 'disabled' : ''}>‹</button>

                <div class="taxi-level-feature-card ${selectedLevel <= currentLevel ? 'unlocked' : 'locked'} ${selectedLevel === currentLevel ? 'current' : ''}">
                    <div class="taxi-level-feature-head">
                        <div class="taxi-level-feature-title">Level ${selectedLevel} • ${escapeHtml(selected.title || 'Taxi Driver')}</div>
                        <div class="taxi-level-feature-status">${selectedLevel <= currentLevel ? 'Unlocked' : 'Locked'}</div>
                    </div>
                    <div class="taxi-level-feature-sub">Required XP: ${selectedXP}</div>
                    <div class="taxi-level-feature-unlocks">${escapeHtml(selected.unlocks || 'No unlocks listed')}</div>

                    <div class="taxi-level-progress-wrap">
                        <div class="taxi-level-progress-head">
                            <span>Progress to next level</span>
                            <span>${nextLevel ? `${Math.round(progressPct)}%` : 'MAX'}</span>
                        </div>
                        <div class="taxi-level-progress-bar">
                            <div class="taxi-level-progress-fill" style="width:${nextLevel ? progressPct : 100}%;"></div>
                        </div>
                        <div class="taxi-level-progress-meta">
                            ${nextLevel
                                ? `Current XP ${currentXP} • Next Level ${Number(nextLevel.level || selectedLevel + 1)} at ${Number(nextLevel.xp || 0)} XP`
                                : 'Maximum level reached'}
                        </div>
                    </div>
                </div>

                <button class="taxi-carousel-arrow" data-action="taxi-level-next" ${taxiState.levelCardIndex >= levels.length - 1 ? 'disabled' : ''}>›</button>
            </div>
            <div class="taxi-carousel-indicator">Level ${taxiState.levelCardIndex + 1} of ${levels.length}</div>
        `;
    }

    function renderRentalsTab() {
        const dashboard = taxiState.dashboard || {};
        const currentLevel = getCurrentLevel();
        const rentals = dashboard.rentalVehicles || [];

        if (!rentals.length) {
            return `<div class="taxi-empty">No rental vehicles configured.</div>`;
        }

        return `
            <div class="taxi-rental-grid">
                ${rentals.map(vehicle => {
                    const unlock = Number(vehicle.unlockLevel || 1);
                    const locked = currentLevel < unlock;

                    return `
                        <div class="taxi-rental-card ${locked ? 'locked' : ''}">
                            <div class="taxi-rental-image-wrap">
                                <img src="${escapeHtml(vehicle.image || '')}" alt="${escapeHtml(vehicle.name || vehicle.spawnCode || 'vehicle')}" class="taxi-rental-image" onerror="this.style.display='none'" />
                            </div>
                            <div class="taxi-rental-name">${escapeHtml(vehicle.name || vehicle.spawnCode || 'Vehicle')}</div>
                            <div class="taxi-rental-meta">Unlock: Level ${unlock}</div>
                            <div class="taxi-rental-meta">Capacity: ${vehicle.maxCapacity || 2}</div>
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

    function renderPhotosTab() {
        const photos = taxiState.photos || [];

        if (!photos.length) {
            return `
                <div class="taxi-photos-container">
                    <div class="taxi-empty">
                        📸 No photos captured yet<br>
                        <small>Use /vehiclephoto to start capturing vehicle photos</small>
                    </div>
                </div>
            `;
        }

        return `
            <div class="taxi-photos-container">
                <div class="taxi-photos-grid">
                    ${photos.map(photo => `
                        <div class="taxi-photo-card">
                            <div class="taxi-photo-placeholder">📸</div>
                            <div class="taxi-photo-info">
                                <div class="taxi-photo-filename">${escapeHtml(photo.filename || 'photo')}</div>
                                <div class="taxi-photo-model">${escapeHtml(photo.model || 'Unknown Model')}</div>
                                <div class="taxi-photo-plate">Plate: ${escapeHtml(photo.plate || 'N/A')}</div>
                                <div class="taxi-photo-time">${escapeHtml(photo.timestamp || photo.created_at || 'N/A')}</div>
                            </div>
                        </div>
                    `).join('')}
                </div>
                <div class="taxi-photos-footer">
                    <button data-action="taxi-refresh-photos" class="taxi-secondary-btn">Refresh Photos</button>
                </div>
            </div>
        `;
    }

    function renderTabBody() {
        if (taxiState.currentTab === 'dashboard') return renderDashboardTab();
        if (taxiState.currentTab === 'calls') return renderCallsTab();
        if (taxiState.currentTab === 'levels') return renderLevelsTab();
        if (taxiState.currentTab === 'rentals') return renderRentalsTab();
        if (taxiState.currentTab === 'photos') return renderPhotosTab();
        return renderDashboardTab();
    }

    function rerender() {
        const $root = getRoot();
        if (!$root.length) return;
        $root.html(renderHeader());
    }

    function refreshInit() {
        post('taxi:getInit', {}, function (resp) {
            if (resp && resp.ok === false) {
                const $root = getRoot();
                if ($root.length) {
                    $root.html('<div class="taxi-app-shell"><div class="taxi-empty">Taxi service is unavailable. Make sure pf-jobs is running and configured.</div></div>');
                }
                return;
            }

            taxiState.dashboard = (resp && resp.state) || (resp || {}).state || {};
            taxiState.initialized = true;

            if (taxiState.dashboard && taxiState.dashboard.level) {
                const levels = getLevels();
                const currentIndex = levels.findIndex(level => Number(level.level || 1) === Number(taxiState.dashboard.level));
                if (currentIndex >= 0) {
                    taxiState.levelCardIndex = currentIndex;
                }
            }

            if (taxiState.dashboard && taxiState.dashboard.accepting) {
                if (taxiState.autoRefreshInterval) clearInterval(taxiState.autoRefreshInterval);
                taxiState.autoRefreshInterval = setInterval(refreshCalls, 5000);
            } else if (taxiState.autoRefreshInterval) {
                clearInterval(taxiState.autoRefreshInterval);
                taxiState.autoRefreshInterval = null;
            }

            rerender();
        });
    }

    function refreshCalls() {
        post('taxi:getCalls', {}, function (resp) {
            const calls = (resp && resp.calls) || [];
            taxiState.calls = Array.isArray(calls) ? calls : [];
            rerender();
        });
    }

    function refreshPhotos() {
        post('taxi:getPhotos', {}, function (resp) {
            const photos = (resp && resp.photos) || [];
            taxiState.photos = Array.isArray(photos) ? photos : [];
            if (taxiState.currentTab === 'photos') rerender();
        });
    }

    function bindHandlers() {
        $(document).off('click.taxi.tab').on('click.taxi.tab', '.taxi-tab', function () {
            taxiState.currentTab = String($(this).data('tab') || 'dashboard');
            rerender();
            if (taxiState.currentTab === 'calls') refreshCalls();
            if (taxiState.currentTab === 'photos') refreshPhotos();
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

                    if (accepting) {
                        if (taxiState.autoRefreshInterval) clearInterval(taxiState.autoRefreshInterval);
                        taxiState.autoRefreshInterval = setInterval(refreshCalls, 5000);
                        setTimeout(refreshCalls, 250);
                    } else {
                        if (taxiState.autoRefreshInterval) {
                            clearInterval(taxiState.autoRefreshInterval);
                            taxiState.autoRefreshInterval = null;
                        }
                        taxiState.calls = [];
                    }

                    rerender();
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

            if (action === 'taxi-level-prev') {
                if (taxiState.levelCardIndex > 0) {
                    taxiState.levelCardIndex -= 1;
                    rerender();
                }
                return;
            }

            if (action === 'taxi-level-next') {
                const levels = getLevels();
                if (taxiState.levelCardIndex < levels.length - 1) {
                    taxiState.levelCardIndex += 1;
                    rerender();
                }
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
                return;
            }

            if (action === 'taxi-refresh-photos') {
                refreshPhotos();
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
            rerender();
            return;
        }

        if (data.action === 'taxi:meterUpdate') {
            taxiState.meter = Object.assign({}, taxiState.meter || {}, data.meter || {});
            if (taxiState.currentTab === 'dashboard') rerender();
            return;
        }

        if (data.action === 'taxi:meterHide') {
            taxiState.meter = Object.assign({}, taxiState.meter || {}, data.meter || {}, { visible: false, inTaxi: false });
            if (taxiState.currentTab === 'dashboard') rerender();
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
            taxiState.meter = Object.assign({}, taxiState.meter || {}, { visible: false, inTaxi: false, onJob: false });
            if (taxiState.dashboard) taxiState.dashboard.activeRide = null;
            refreshInit();
            refreshCalls();
            return;
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
