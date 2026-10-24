// Bus Tablet Module - JavaScript functionality

let currentStats = null;
let availableRoutes = [];

// ============================================================================
// TAB SWITCHING
// ============================================================================

document.addEventListener('DOMContentLoaded', function() {
    // Tab switching
    document.querySelectorAll('.bus-tab-btn').forEach(btn => {
        btn.addEventListener('click', function() {
            const tabName = this.getAttribute('data-tab');
            switchBusTab(tabName);
        });
    });

    // Load initial data
    requestStatsData();
    requestRoutesData();
});

function switchBusTab(tabName) {
    // Hide all tabs
    document.querySelectorAll('.bus-tab-content').forEach(tab => {
        tab.classList.remove('active');
    });

    // Remove active class from buttons
    document.querySelectorAll('.bus-tab-btn').forEach(btn => {
        btn.classList.remove('active');
    });

    // Show selected tab
    const tabContent = document.getElementById(tabName);
    if (tabContent) {
        tabContent.classList.add('active');
    }

    // Activate button
    document.querySelector(`[data-tab="${tabName}"]`).classList.add('active');

    // Update tab-specific data
    if (tabName === 'routes') {
        requestRoutesData();
    } else if (tabName === 'stats') {
        updateStatisticsTab();
    } else if (tabName === 'levels') {
        updateLevelsTab();
    }
}

// ============================================================================
// DATA REQUESTS
// ============================================================================

function requestStatsData() {
    fetch(`https://${GetParentResourceName()}/bus:server:getStats`, {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({})
    });
}

function requestRoutesData() {
    fetch(`https://${GetParentResourceName()}/bus:server:getRoutes`, {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({})
    });
}

// ============================================================================
// RECEIVE DATA FROM SERVER
// ============================================================================

window.addEventListener('message', function(event) {
    const data = event.data;

    if (data.type === 'busStatsData') {
        currentStats = data.stats;
        updateDashboard();
        updateStatisticsTab();
        updateLevelsTab();
    }

    if (data.type === 'busRoutesData') {
        availableRoutes = data.routes;
        updateRoutesTab();
    }
});

// ============================================================================
// DASHBOARD
// ============================================================================

function updateDashboard() {
    if (!currentStats) return;

    document.getElementById('dash-level').textContent = currentStats.level;
    document.getElementById('dash-earnings').textContent = '$' + formatNumber(currentStats.totalEarnings);
    document.getElementById('dash-routes').textContent = currentStats.routesCompleted;
    document.getElementById('dash-rating').textContent = currentStats.averageRating.toFixed(1);
}

// ============================================================================
// ROUTES TAB
// ============================================================================

function updateRoutesTab() {
    const routesList = document.getElementById('routes-list');
    
    if (!availableRoutes || availableRoutes.length === 0) {
        routesList.innerHTML = '<p style="text-align: center; color: #7f8c8d;">No routes available for your level</p>';
        return;
    }

    let html = '';
    availableRoutes.forEach(route => {
        const difficulty = route.difficulty.charAt(0).toUpperCase() + route.difficulty.slice(1);
        const estimatedTime = Math.round(route.estimatedTime / 1000 / 60);
        const baseFare = calculateRoutePayPreview(route);
        const passengerCount = getRoutePassengerCount(route);

        html += `
            <div class="route-card ${route.difficulty}" onclick="selectRoute(${route.id})">
                <div class="route-info">
                    <h3>${route.name}</h3>
                    <p>Difficulty: ${difficulty} | Time: ${estimatedTime} min | Stops: ${route.stops.length}</p>
                    <p>Passengers: ${passengerCount} | Distance: ${route.baseDistance.toFixed(1)} miles</p>
                </div>
                <div class="route-pay">$${baseFare}</div>
            </div>
        `;
    });

    routesList.innerHTML = html;
}

function calculateRoutePayPreview(route) {
    const multiplier = 1.5; // Base multiplier for preview
    let totalPassengers = 0;

    for (let stop of route.stops) {
        if (stop.isPickup) {
            totalPassengers += stop.passengerCount;
        }
    }

    const baseFare = (totalPassengers * 25) + (route.baseDistance * 5.5);
    return Math.floor(baseFare * multiplier);
}

function getRoutePassengerCount(route) {
    let count = 0;
    for (let stop of route.stops) {
        if (stop.isPickup) {
            count += stop.passengerCount;
        }
    }
    return count;
}

function selectRoute(routeId) {
    fetch(`https://${GetParentResourceName()}/bus:client:selectRoute`, {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({routeId: routeId})
    });
}

// ============================================================================
// STATISTICS TAB
// ============================================================================

function updateStatisticsTab() {
    if (!currentStats) return;

    document.getElementById('stat-passengers').textContent = formatNumber(currentStats.totalPassengers);
    document.getElementById('stat-routes').textContent = currentStats.routesCompleted;
    document.getElementById('stat-earnings').textContent = '$' + formatNumber(currentStats.totalEarnings);
    document.getElementById('stat-ontime').textContent = currentStats.onTimeCount;
    document.getElementById('stat-hours').textContent = Math.round(currentStats.totalTime);
    document.getElementById('stat-rating').textContent = currentStats.averageRating.toFixed(1) + ' ⭐';
}

// ============================================================================
// LEVELS TAB
// ============================================================================

function updateLevelsTab() {
    if (!currentStats) return;

    const levelsList = document.getElementById('levels-list');
    const levels = [
        { level: 1, name: 'Novice Driver', minRoutes: 0, maxRoutes: 10, multiplier: '1.0x' },
        { level: 2, name: 'Experienced', minRoutes: 11, maxRoutes: 30, multiplier: '1.15x' },
        { level: 3, name: 'Licensed Driver', minRoutes: 31, maxRoutes: 75, multiplier: '1.30x' },
        { level: 4, name: 'Professional', minRoutes: 76, maxRoutes: 150, multiplier: '1.45x' },
        { level: 5, name: 'Expert Driver', minRoutes: 151, maxRoutes: 999999, multiplier: '1.60x' }
    ];

    let html = '';
    levels.forEach(level => {
        const isCurrent = level.level === currentStats.level;
        const progress = currentStats.routesCompleted;
        const nextRequirement = level.maxRoutes + 1;
        const currentProgress = Math.min(progress, nextRequirement);

        html += `
            <div class="level-item ${isCurrent ? 'current' : ''}">
                <div class="level-info">
                    <h4>Level ${level.level} - ${level.name}</h4>
                    <p>Pay Multiplier: ${level.multiplier} | Routes: ${level.minRoutes}-${level.maxRoutes}</p>
                    <p>Progress: ${currentProgress}/${nextRequirement}</p>
                </div>
                <div class="level-badge" style="${isCurrent ? 'background: #e67e22;' : 'background: #555;'}">${isCurrent ? '✓ CURRENT' : 'LOCKED'}</div>
            </div>
        `;
    });

    levelsList.innerHTML = html;
}

// ============================================================================
// ACTION BUTTONS
// ============================================================================

function startRoute() {
    // Request routes and show selection
    switchBusTab('routes');
}

function cancelRoute() {
    fetch(`https://${GetParentResourceName()}/bus:client:cancelRoute`, {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({})
    });
}

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

function formatNumber(num) {
    return num.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

function GetParentResourceName() {
    // This will be replaced by the actual resource name in the tablet system
    return 'pf-jobs';
}