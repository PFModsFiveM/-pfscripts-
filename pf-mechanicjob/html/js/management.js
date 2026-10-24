// Management App Frontend Handler
// Handles UI interactions, tab switching, modals, and NUI callbacks

// ============================================================================
// STATE & GLOBALS
// ============================================================================
let appState = {
    businessName: 'Los Santos Customs',
    employees: [],
    products: [],
    inventory: [],
    businessSettings: {},
    salesData: [],
    currentEmployeeStats: null,
    currentEditingProductId: null,
    confirmationCallback: null
};

let salesChart = null;
let currentActionMenu = null;

// ============================================================================
// INITIALIZATION
// ============================================================================
document.addEventListener('DOMContentLoaded', function() {
    initializeTabs();
    initializeModals();
    initializeEventListeners();
    handleNUIMessages();
});

// ============================================================================
// TAB SWITCHING
// ============================================================================
function initializeTabs() {
    const navTabs = document.querySelectorAll('.nav-tab');
    
    navTabs.forEach(tab => {
        tab.addEventListener('click', function() {
            const tabName = this.getAttribute('data-tab');
            switchTab(tabName);
        });
    });
}

function switchTab(tabName) {
    // Remove active from all tabs and pages
    document.querySelectorAll('.nav-tab').forEach(tab => {
        tab.classList.remove('active');
    });
    document.querySelectorAll('.tab-page').forEach(page => {
        page.classList.remove('active');
    });

    // Add active to clicked tab and matching page
    document.querySelector(`[data-tab="${tabName}"]`).classList.add('active');
    document.querySelector(`[data-page="${tabName}"]`).classList.add('active');
}

// ============================================================================
// NUI MESSAGE HANDLING
// ============================================================================
function handleNUIMessages() {
    window.addEventListener('message', function(event) {
        const message = event.data;
        
        if (message.action === 'openManagement') {
            appState = { ...appState, ...message.payload };
            populateUI();
        }
    });
}

// ============================================================================
// UI POPULATION
// ============================================================================
function populateUI() {
    // Update business name in navbar
    document.getElementById('businessName').textContent = appState.businessName;

    // Populate stat cards
    updateStatCards();

    // Initialize chart
    initializeSalesChart();

    // Populate tables
    populateEmployeesTable();
    populateProductsTable();
    populateInventoryTable();

    // Populate settings
    populateSettings();
}

function updateStatCards() {
    const formatCurrency = (value) => '$' + parseInt(value || 0).toLocaleString();
    
    document.getElementById('last7Sales').textContent = formatCurrency(appState.last7Total || 0);
    document.getElementById('last30Sales').textContent = formatCurrency(appState.last30Total || 0);
    document.getElementById('todaySales').textContent = formatCurrency(appState.todayTotal || 0);
}

function initializeSalesChart() {
    const ctx = document.getElementById('salesChart');
    if (!ctx) return;

    const chartData = appState.salesChartData || [];
    const labels = chartData.map(d => d.date || 'N/A');
    const data = chartData.map(d => d.total || 0);

    if (salesChart) {
        salesChart.destroy();
    }

    salesChart = new Chart(ctx, {
        type: 'line',
        data: {
            labels: labels,
            datasets: [{
                label: 'Daily Sales',
                data: data,
                borderColor: '#4a9eff',
                backgroundColor: 'rgba(74, 158, 255, 0.1)',
                borderWidth: 2,
                fill: true,
                tension: 0.4,
                pointBackgroundColor: '#4a9eff',
                pointBorderColor: '#1a2535',
                pointBorderWidth: 2,
                pointRadius: 5,
                pointHoverRadius: 7
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    display: true,
                    labels: {
                        color: '#8ab4f8',
                        font: { size: 12, weight: '600' }
                    }
                },
                filler: {
                    propagate: true
                }
            },
            scales: {
                y: {
                    beginAtZero: true,
                    grid: {
                        color: 'rgba(42, 63, 95, 0.2)',
                        drawBorder: false
                    },
                    ticks: {
                        color: '#8ab4f8',
                        font: { size: 12 },
                        callback: function(value) {
                            return '$' + value.toLocaleString();
                        }
                    }
                },
                x: {
                    grid: {
                        display: false,
                        drawBorder: false
                    },
                    ticks: {
                        color: '#8ab4f8',
                        font: { size: 12 }
                    }
                }
            }
        }
    });
}

function populateEmployeesTable() {
    const tbody = document.getElementById('employeesTableBody');
    tbody.innerHTML = '';

    if (!appState.employees || appState.employees.length === 0) {
        tbody.innerHTML = '<tr><td colspan="7" style="text-align: center; color: #666;">No employees found</td></tr>';
        return;
    }

    appState.employees.forEach(emp => {
        const row = document.createElement('tr');
        row.innerHTML = `
            <td>${emp.name || 'Unknown'}</td>
            <td>${emp.citizenid || 'N/A'}</td>
            <td><span style="color: ${getRoleColor(emp.role)}">${emp.role || 'employee'}</span></td>
            <td>$${(emp.totalSales || 0).toLocaleString()}</td>
            <td>$${(emp.last7Sales || 0).toLocaleString()}</td>
            <td>$${(emp.last30Sales || 0).toLocaleString()}</td>
            <td>
                <div class="actions-dropdown">
                    <button class="action-btn" data-employeeid="${emp.citizenid}">⋮</button>
                    <div class="action-menu" style="display: none;">
                        <button class="action-menu-item" onclick="viewEmployeeStats('${emp.citizenid}')">View Stats</button>
                        <button class="action-menu-item" onclick="promoteEmployee('${emp.citizenid}')">Promote</button>
                        <button class="action-menu-item danger" onclick="confirmFireEmployee('${emp.citizenid}', '${emp.name}')">Fire</button>
                    </div>
                </div>
            </td>
        `;
        tbody.appendChild(row);
    });

    // Attach action menu listeners
    attachActionMenuListeners();
}

function populateProductsTable() {
    const tbody = document.getElementById('pricingTableBody');
    tbody.innerHTML = '';

    if (!appState.products || appState.products.length === 0) {
        tbody.innerHTML = '<tr><td colspan="5" style="text-align: center; color: #666;">No products found</td></tr>';
        return;
    }

    appState.products.forEach(prod => {
        const row = document.createElement('tr');
        const updatedAt = prod.updated_at ? new Date(prod.updated_at).toLocaleDateString() : 'Never';
        const basePrice = `<span class="pricing-base-price">$${(prod.base_price || 0).toLocaleString()}</span>`;
        const currentPrice = `<span class="pricing-price-display">$${(prod.current_price || 0).toLocaleString()}</span>`;
        row.innerHTML = `
            <td><strong>${prod.product_name || 'Unknown'}</strong></td>
            <td>${basePrice}</td>
            <td>${currentPrice}</td>
            <td>${updatedAt}</td>
            <td><button class="btn btn-small btn-primary" onclick="openPriceEditModal(${prod.id}, '${prod.product_name}', ${prod.current_price})">Edit</button></td>
        `;
        tbody.appendChild(row);
    });
}

function populateInventoryTable() {
    const tbody = document.getElementById('inventoryTableBody');
    tbody.innerHTML = '';

    if (!appState.inventory || appState.inventory.length === 0) {
        tbody.innerHTML = '<tr><td colspan="3" style="text-align: center; color: #666;">No inventory items found</td></tr>';
        return;
    }

    appState.inventory.forEach(inv => {
        const row = document.createElement('tr');
        const qtyClass = (inv.quantity || 0) === 0 ? 'inventory-empty-qty' : 'inventory-qty';
        row.innerHTML = `
            <td><strong>${inv.product_name || 'Unknown'}</strong></td>
            <td>${inv.product_id || 'N/A'}</td>
            <td><span class="${qtyClass}">${inv.quantity || 0}</span></td>
        `;
        tbody.appendChild(row);
    });
}

function populateSettings() {
    if (!appState.businessSettings) return;

    document.getElementById('settingsBusinessName').value = appState.businessSettings.business_name || '';
    document.getElementById('settingsBlipName').value = appState.businessSettings.blip_name || '';
    document.getElementById('settingsBlipColor').value = appState.businessSettings.blip_color || 3;
}

// ============================================================================
// EMPLOYEE ACTIONS
// ============================================================================
function attachActionMenuListeners() {
    document.querySelectorAll('.action-btn').forEach(btn => {
        btn.addEventListener('click', function(e) {
            e.stopPropagation();
            const menu = this.nextElementSibling;
            
            // Close other menus
            document.querySelectorAll('.action-menu').forEach(m => {
                if (m !== menu) m.style.display = 'none';
            });
            
            menu.style.display = menu.style.display === 'none' ? 'block' : 'none';
        });
    });
}

function viewEmployeeStats(citizenid) {
    // Close action menu
    document.querySelectorAll('.action-menu').forEach(m => m.style.display = 'none');

    // Fetch employee stats
    fetch('https://pf-mechanicjob/getEmployeeStats', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ citizenid: citizenid })
    }).then(res => res.json()).then(data => {
        if (data.success) {
            populateEmployeeStatsModal(data);
            openModal('employeeStatsModal');
        }
    }).catch(err => console.error('Error fetching employee stats:', err));
}

function populateEmployeeStatsModal(data) {
    const emp = data.employee;
    document.getElementById('employeeStatsName').textContent = emp.name || 'Employee Stats';
    document.getElementById('employeeStatsTotalSales').textContent = '$' + (emp.totalSales || 0).toLocaleString();
    document.getElementById('employeeStatsLast7').textContent = '$' + (emp.last7Sales || 0).toLocaleString();
    document.getElementById('employeeStatsLast30').textContent = '$' + (emp.last30Sales || 0).toLocaleString();
    document.getElementById('employeeStatsRole').textContent = emp.role || 'employee';

    // Populate transactions
    const tbody = document.getElementById('employeeTransactionsBody');
    tbody.innerHTML = '';

    if (data.transactions && data.transactions.length > 0) {
        data.transactions.forEach(trans => {
            const row = document.createElement('tr');
            const date = new Date(trans.created_at).toLocaleDateString();
            row.innerHTML = `
                <td>${date}</td>
                <td>${trans.product_name || 'Unknown'}</td>
                <td>${trans.quantity || 0}</td>
                <td>$${(trans.total_price || 0).toLocaleString()}</td>
            `;
            tbody.appendChild(row);
        });
    } else {
        tbody.innerHTML = '<tr><td colspan="4" style="text-align: center; color: #666;">No transactions found</td></tr>';
    }
}

function promoteEmployee(citizenid) {
    document.querySelectorAll('.action-menu').forEach(m => m.style.display = 'none');

    fetch('https://pf-mechanicjob/promoteEmployee', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ citizenid: citizenid })
    }).then(res => res.json()).then(data => {
        if (data.success) {
            showStatus('Employee promoted!', 'success');
        } else {
            showStatus('Error promoting employee: ' + (data.message || 'Unknown error'), 'error');
        }
    }).catch(err => {
        console.error('Error promoting employee:', err);
        showStatus('Error promoting employee', 'error');
    });
}

function confirmFireEmployee(citizenid, name) {
    document.querySelectorAll('.action-menu').forEach(m => m.style.display = 'none');

    openConfirmationModal('Fire Employee', `Are you sure you want to fire ${name}?`, () => {
        fireEmployee(citizenid);
    });
}

function fireEmployee(citizenid) {
    fetch('https://pf-mechanicjob/fireEmployee', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ citizenid: citizenid })
    }).then(res => res.json()).then(data => {
        if (data.success) {
            showStatus('Employee fired!', 'success');
            // Refresh employees list
            setTimeout(() => {
                fetch('https://pf-mechanicjob/refreshData', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' }
                });
            }, 500);
        } else {
            showStatus('Error firing employee: ' + (data.message || 'Unknown error'), 'error');
        }
    }).catch(err => {
        console.error('Error firing employee:', err);
        showStatus('Error firing employee', 'error');
    });
}

// ============================================================================
// HIRE EMPLOYEE
// ============================================================================
document.addEventListener('DOMContentLoaded', function() {
    const hireBtn = document.getElementById('hireBtn');
    if (hireBtn) {
        hireBtn.addEventListener('click', function() {
            const playerId = document.getElementById('hirePlayerId').value.trim();
            if (!playerId) {
                showStatus('Please enter a player ID', 'error');
                return;
            }

            fetch('https://pf-mechanicjob/hireEmployee', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ id: playerId })
            }).then(res => res.json()).then(data => {
                if (data.success) {
                    showStatus('Employee hired!', 'success');
                    document.getElementById('hirePlayerId').value = '';
                    // Refresh employees list
                    setTimeout(() => {
                        fetch('https://pf-mechanicjob/refreshData', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' }
                        });
                    }, 500);
                } else {
                    showStatus('Error hiring employee: ' + (data.message || 'Unknown error'), 'error');
                }
            }).catch(err => {
                console.error('Error hiring employee:', err);
                showStatus('Error hiring employee', 'error');
            });
        });
    }
});

// ============================================================================
// PRODUCT PRICE EDITING
// ============================================================================
function openPriceEditModal(productId, productName, currentPrice) {
    appState.currentEditingProductId = productId;
    document.getElementById('priceEditProductName').value = productName;
    document.getElementById('priceEditProductPrice').value = currentPrice;
    openModal('priceEditModal');
}

document.addEventListener('DOMContentLoaded', function() {
    const savePriceBtn = document.getElementById('savePriceBtn');
    if (savePriceBtn) {
        savePriceBtn.addEventListener('click', function() {
            const newPrice = parseInt(document.getElementById('priceEditProductPrice').value);
            if (isNaN(newPrice) || newPrice < 0) {
                showStatus('Please enter a valid price', 'error');
                return;
            }

            fetch('https://pf-mechanicjob/updateProductPrice', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ 
                    productId: appState.currentEditingProductId, 
                    newPrice: newPrice 
                })
            }).then(res => res.json()).then(data => {
                if (data.success) {
                    showStatus('Price updated!', 'success');
                    closeModal('priceEditModal');
                    // Refresh products
                    setTimeout(() => {
                        fetch('https://pf-mechanicjob/refreshData', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' }
                        });
                    }, 500);
                } else {
                    showStatus('Error updating price: ' + (data.message || 'Unknown error'), 'error');
                }
            }).catch(err => {
                console.error('Error updating price:', err);
                showStatus('Error updating price', 'error');
            });
        });
    }

    const cancelPriceBtn = document.getElementById('cancelPriceBtn');
    if (cancelPriceBtn) {
        cancelPriceBtn.addEventListener('click', function() {
            closeModal('priceEditModal');
        });
    }
});

// ============================================================================
// SETTINGS
// ============================================================================
document.addEventListener('DOMContentLoaded', function() {
    const saveSettingsBtn = document.getElementById('saveSettingsBtn');
    if (saveSettingsBtn) {
        saveSettingsBtn.addEventListener('click', function() {
            const businessName = document.getElementById('settingsBusinessName').value.trim();
            const blipName = document.getElementById('settingsBlipName').value.trim();
            const blipColor = parseInt(document.getElementById('settingsBlipColor').value);

            if (!businessName || !blipName || isNaN(blipColor)) {
                showStatus('Please fill all fields correctly', 'error');
                return;
            }

            fetch('https://pf-mechanicjob/saveBusinessSettings', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    business_name: businessName,
                    blip_name: blipName,
                    blip_color: blipColor
                })
            }).then(res => res.json()).then(data => {
                if (data.success) {
                    showStatus('Settings saved!', 'success');
                } else {
                    showStatus('Error saving settings: ' + (data.message || 'Unknown error'), 'error');
                }
            }).catch(err => {
                console.error('Error saving settings:', err);
                showStatus('Error saving settings', 'error');
            });
        });
    }
});

// ============================================================================
// LOCATION PLACEMENT
// ============================================================================
function setupPlacementButtons() {
    // Stash
    document.getElementById('stashPropBtn')?.addEventListener('click', function() {
        startPlacement('stash_shared', 'prop');
    });
    document.getElementById('stashCoordBtn')?.addEventListener('click', function() {
        startPlacement('stash_shared', 'coord');
    });

    // Locker
    document.getElementById('lockerPropBtn')?.addEventListener('click', function() {
        startPlacement('locker', 'prop');
    });
    document.getElementById('lockerCoordBtn')?.addEventListener('click', function() {
        startPlacement('locker', 'coord');
    });

    // Duty
    document.getElementById('dutyBtn')?.addEventListener('click', function() {
        startPlacement('duty', 'coord');
    });
}

function startPlacement(type, mode) {
    fetch('https://pf-mechanicjob/startPlacement', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ type: type, mode: mode })
    }).then(res => res.json()).then(data => {
        if (data.success) {
            showPlacementStatus(type, 'Location saved successfully!', 'success');
        } else {
            showPlacementStatus(type, 'Error: ' + (data.message || 'Unknown error'), 'error');
        }
    }).catch(err => {
        console.error('Error starting placement:', err);
        showPlacementStatus(type, 'Error starting placement', 'error');
    });
}

function showPlacementStatus(type, message, status) {
    let statusEl;
    if (type === 'stash_shared') {
        statusEl = document.getElementById('stashStatus');
    } else if (type === 'locker') {
        statusEl = document.getElementById('lockerStatus');
    } else if (type === 'duty') {
        statusEl = document.getElementById('dutyStatus');
    }

    if (statusEl) {
        statusEl.textContent = message;
        statusEl.classList.remove('success', 'error');
        statusEl.classList.add(status);
    }
}

// ============================================================================
// MODAL HANDLING
// ============================================================================
function initializeModals() {
    setupPlacementButtons();

    // Close buttons
    document.getElementById('closeEmployeeStatsBtn')?.addEventListener('click', function() {
        closeModal('employeeStatsModal');
    });

    document.getElementById('closePriceEditBtn')?.addEventListener('click', function() {
        closeModal('priceEditModal');
    });

    document.getElementById('confirmationCancelBtn')?.addEventListener('click', function() {
        closeModal('confirmationModal');
    });

    document.getElementById('confirmationConfirmBtn')?.addEventListener('click', function() {
        if (appState.confirmationCallback) {
            appState.confirmationCallback();
        }
        closeModal('confirmationModal');
    });
}

function openModal(modalId) {
    const modal = document.getElementById(modalId);
    if (modal) {
        modal.classList.add('active');
    }
}

function closeModal(modalId) {
    const modal = document.getElementById(modalId);
    if (modal) {
        modal.classList.remove('active');
    }
}

function openConfirmationModal(title, message, callback) {
    document.getElementById('confirmationTitle').textContent = title;
    document.getElementById('confirmationMessage').textContent = message;
    appState.confirmationCallback = callback;
    openModal('confirmationModal');
}

function showStatus(message, type) {
    // Create temporary status message
    const statusEl = document.createElement('div');
    statusEl.className = `status-message ${type}`;
    statusEl.textContent = message;
    statusEl.style.position = 'fixed';
    statusEl.style.top = '100px';
    statusEl.style.right = '20px';
    statusEl.style.zIndex = '3000';
    statusEl.style.minWidth = '300px';
    
    document.body.appendChild(statusEl);
    
    setTimeout(() => {
        statusEl.remove();
    }, 3000);
}

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================
function getRoleColor(role) {
    const colors = {
        'owner': '#4bc05c',
        'manager': '#ffc107',
        'employee': '#8ab4f8'
    };
    return colors[role] || '#8ab4f8';
}

// ============================================================================
// APP CLOSE & ESC KEY
// ============================================================================
document.addEventListener('DOMContentLoaded', function() {
    document.getElementById('closeBtn')?.addEventListener('click', closeApp);

    document.addEventListener('keydown', function(e) {
        if (e.key === 'Escape') {
            closeApp();
        }
    });
});

function closeApp() {
    fetch('https://pf-mechanicjob/close', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' }
    });
}
