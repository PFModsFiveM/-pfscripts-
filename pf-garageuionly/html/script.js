// Sample Data Structure
const sampleVehicles = [
    {
        id: 1,
        name: 'Grotti Turismo R',
        plate: 'ABC 123',
        model: 'turismor',
        category: 'Super',
        titleStatus: 'clean',
        location: 'Legion Square Parking',
        heading: 90.5,
        mileage: 12345,
        insurance: 'Premium',
        policeHeat: 'low',
        fuel: 75,
        engine: 90,
        body: 85,
        cleanliness: 50,
        favorite: true,
        isJobVehicle: false,
        lastUsed: new Date('2026-02-17T14:30:00'),
        purchaseDate: new Date('2025-06-15'),
        damage: {
            panels: [
                { name: 'Front Bumper', severity: 'minor' },
                { name: 'Hood', severity: 'severe' }
            ],
            lights: ['Headlight (R)'],
            windows: ['Window (Driver)'],
            tires: ['good', 'good', 'worn', 'blown']
        },
        history: [
            {
                type: 'purchase',
                date: new Date('2025-06-15'),
                title: 'Vehicle Purchased',
                description: 'Bought from Luxury Autos for $550,000'
            },
            {
                type: 'repair',
                date: new Date('2025-09-10'),
                title: 'Engine Maintenance',
                description: 'Full tune-up and oil change at LS Customs'
            },
            {
                type: 'crime',
                date: new Date('2025-11-22'),
                title: 'Police Chase',
                description: 'Evaded police pursuit near Del Perro Beach'
            },
            {
                type: 'repair',
                date: new Date('2026-01-05'),
                title: 'Body Repairs',
                description: 'Fixed collision damage - $2,500'
            }
        ]
    },
    {
        id: 2,
        name: 'Vapid Dominator GTX',
        plate: 'XYZ 789',
        model: 'dominator3',
        category: 'Muscle',
        titleStatus: 'salvage',
        location: 'Pillbox Hill Garage',
        heading: 180.0,
        mileage: 45678,
        insurance: 'Basic',
        policeHeat: 'medium',
        fuel: 45,
        engine: 65,
        body: 50,
        cleanliness: 30,
        favorite: false,
        isJobVehicle: false,
        lastUsed: new Date('2026-02-10T08:15:00'),
        purchaseDate: new Date('2024-03-20'),
        damage: {
            panels: [
                { name: 'Rear Bumper', severity: 'severe' },
                { name: 'Trunk', severity: 'minor' }
            ],
            lights: [],
            windows: ['Rear Window'],
            tires: ['good', 'worn', 'good', 'good']
        },
        history: [
            {
                type: 'purchase',
                date: new Date('2024-03-20'),
                title: 'Vehicle Purchased',
                description: 'Bought from salvage auction for $125,000'
            },
            {
                type: 'repair',
                date: new Date('2024-05-10'),
                title: 'Rebuilt Title',
                description: 'Major reconstruction work completed'
            }
        ]
    },
    {
        id: 3,
        name: 'Declasse Granger 3600LX',
        plate: 'LSPD 001',
        model: 'granger2',
        category: 'SUV',
        titleStatus: 'clean',
        location: 'Mission Row PD',
        heading: 270.0,
        mileage: 89012,
        insurance: 'Government',
        policeHeat: 'none',
        fuel: 80,
        engine: 95,
        body: 98,
        cleanliness: 85,
        favorite: false,
        isJobVehicle: true,
        lastUsed: new Date('2026-02-18T06:00:00'),
        purchaseDate: new Date('2023-01-10'),
        damage: {
            panels: [],
            lights: [],
            windows: [],
            tires: ['good', 'good', 'good', 'good']
        },
        history: [
            {
                type: 'purchase',
                date: new Date('2023-01-10'),
                title: 'Fleet Vehicle Assigned',
                description: 'Assigned to LSPD patrol division'
            },
            {
                type: 'repair',
                date: new Date('2025-06-15'),
                title: 'Scheduled Maintenance',
                description: 'Routine service and inspection'
            }
        ]
    },
    {
        id: 4,
        name: 'Annis Elegy RH8',
        plate: 'DEF 456',
        model: 'elegy2',
        category: 'Sports',
        titleStatus: 'rebuilt',
        location: 'Alta Street Garage',
        heading: 45.0,
        mileage: 23456,
        insurance: 'Standard',
        policeHeat: 'high',
        fuel: 25,
        engine: 70,
        body: 60,
        cleanliness: 20,
        favorite: true,
        isJobVehicle: false,
        lastUsed: new Date('2026-02-16T22:45:00'),
        purchaseDate: new Date('2025-01-10'),
        damage: {
            panels: [
                { name: 'Front Fender (L)', severity: 'minor' },
                { name: 'Door (R)', severity: 'minor' }
            ],
            lights: ['Taillight (L)'],
            windows: [],
            tires: ['worn', 'worn', 'good', 'good']
        },
        history: [
            {
                type: 'purchase',
                date: new Date('2025-01-10'),
                title: 'Vehicle Purchased',
                description: 'Rebuilt title - purchased for $180,000'
            },
            {
                type: 'crime',
                date: new Date('2025-12-05'),
                title: 'Street Racing',
                description: 'Caught participating in illegal street race'
            },
            {
                type: 'repair',
                date: new Date('2026-02-01'),
                title: 'Suspension Upgrade',
                description: 'Performance upgrades at Benny\'s - $5,000'
            }
        ]
    }
];

const defaultTheme = {
    '--primary-color': '#3b82f6',
    '--secondary-color': '#8b5cf6',
    '--success-color': '#10b981',
    '--warning-color': '#f59e0b',
    '--danger-color': '#ef4444',
    '--info-color': '#06b6d4',
    '--bg-primary': '#0f172a',
    '--bg-secondary': '#1e293b',
    '--bg-tertiary': '#334155',
    '--text-primary': '#f1f5f9',
    '--text-secondary': '#cbd5e1',
    '--text-muted': '#94a3b8'
};

// State Management
let state = {
    vehicles: [...sampleVehicles],
    folders: [
        { id: 1, name: 'Daily', icon: 'car', vehicleIds: [1] },
        { id: 2, name: 'Race', icon: 'flag-checkered', vehicleIds: [4] },
        { id: 3, name: 'Illegal', icon: 'skull-crossbones', vehicleIds: [] }
    ],
    currentFilter: 'all',
    currentFolder: null,
    searchQuery: '',
    selectedVehicle: null,
    draggedVehicle: null,
    settings: {
        enableImages: false,
        theme: { ...defaultTheme },
        glassColor: '#1e293b',
        glassOpacity: 0.85,
        borderColor: '#94a3b8',
        borderOpacity: 0.1
    }
};

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    initializeUI();
    renderFolders();
    renderVehicles();
    setupEventListeners();
});

// UI Initialization
function initializeUI() {
    // Setup filter buttons
    document.querySelectorAll('.filter-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            state.currentFilter = btn.dataset.filter;
            renderVehicles();
        });
    });

    // Setup search
    document.getElementById('searchInput').addEventListener('input', (e) => {
        state.searchQuery = e.target.value.toLowerCase();
        renderVehicles();
    });

    // Setup modal tabs
    document.querySelectorAll('.tab-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            const tab = btn.dataset.tab;
            document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
            document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
            btn.classList.add('active');
            document.querySelector(`.tab-content[data-tab="${tab}"]`).classList.add('active');
        });
    });

    // Setup icon picker
    document.querySelectorAll('.icon-option').forEach(btn => {
        btn.addEventListener('click', () => {
            document.querySelectorAll('.icon-option').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
        });
    });

    loadSettings();
    bindSettingsInputs();
}

// Event Listeners
function setupEventListeners() {
    // Close on ESC
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            closeGarage();
            closeModal();
            closeFolderModal();
            closeAddToFolderModal();
            closeSettings();
        }
    });

    // Click outside modals to close
    document.querySelectorAll('.modal').forEach(modal => {
        modal.addEventListener('click', (e) => {
            if (e.target === modal) {
                modal.classList.remove('active');
            }
        });
    });

    document.addEventListener('click', (e) => {
        if (!e.target.closest('.vehicle-menu') && !e.target.closest('.menu-btn')) {
            closeAllMenus();
        }
    });
}

// Render Functions
function renderFolders() {
    const container = document.getElementById('foldersList');
    container.innerHTML = '';

    state.folders.forEach(folder => {
        const vehicleCount = folder.vehicleIds.length;
        const folderEl = document.createElement('div');
        folderEl.className = 'folder-item';
        folderEl.draggable = false;
        folderEl.innerHTML = `
            <div class="folder-left">
                <div class="folder-icon">
                    <i class="fas fa-${folder.icon}"></i>
                </div>
                <div class="folder-info">
                    <h4>${folder.name}</h4>
                    <span>${vehicleCount} vehicle${vehicleCount !== 1 ? 's' : ''}</span>
                </div>
            </div>
        `;

        folderEl.addEventListener('click', () => {
            document.querySelectorAll('.folder-item').forEach(f => f.classList.remove('active'));
            folderEl.classList.add('active');
            state.currentFolder = folder.id;
            document.getElementById('sectionTitle').innerHTML = `<i class="fas fa-${folder.icon}"></i> ${folder.name}`;
            renderVehicles();
        });

        // Drop zone for folders
        folderEl.addEventListener('dragover', (e) => {
            e.preventDefault();
            folderEl.classList.add('drag-over');
        });

        folderEl.addEventListener('dragleave', () => {
            folderEl.classList.remove('drag-over');
        });

        folderEl.addEventListener('drop', (e) => {
            e.preventDefault();
            folderEl.classList.remove('drag-over');
            if (state.draggedVehicle) {
                addVehicleToFolder(state.draggedVehicle, folder.id);
                renderFolders();
                renderVehicles();
            }
        });

        container.appendChild(folderEl);
    });
}

function renderVehicles() {
    const container = document.getElementById('vehiclesGrid');
    let filteredVehicles = filterVehicles();

    if (filteredVehicles.length === 0) {
        container.innerHTML = `
            <div class="empty-state">
                <i class="fas fa-inbox"></i>
                <h3>No Vehicles Found</h3>
                <p>Try adjusting your filters or search query.</p>
            </div>
        `;
        document.getElementById('vehicleCount').textContent = '0 vehicles';
        return;
    }

    container.innerHTML = '';
    document.getElementById('vehicleCount').textContent = `${filteredVehicles.length} vehicle${filteredVehicles.length !== 1 ? 's' : ''}`;

    filteredVehicles.forEach(vehicle => {
        const card = createVehicleCard(vehicle);
        container.appendChild(card);
    });
}

function createVehicleCard(vehicle) {
    const card = document.createElement('div');
    card.className = 'vehicle-card';
    card.draggable = true;

    // Drag events
    card.addEventListener('dragstart', (e) => {
        state.draggedVehicle = vehicle.id;
        card.classList.add('dragging');
    });

    card.addEventListener('dragend', () => {
        state.draggedVehicle = null;
        card.classList.remove('dragging');
    });

    // Click to open details
    card.addEventListener('click', (e) => {
        if (!e.target.closest('.action-btn') && !e.target.closest('.spawn-btn') && !e.target.closest('.vehicle-menu')) {
            openVehicleModal(vehicle);
        }
    });

    const isDamaged = vehicle.body < 70 || vehicle.engine < 70;
    const heatClass = vehicle.policeHeat === 'high' ? 'heat-high' : 
                      vehicle.policeHeat === 'medium' ? 'heat-medium' : 'heat-low';
    const showImages = state.settings.enableImages;
    const imageSrc = vehicle.imageUrl || vehicle.image || null;

    card.innerHTML = `
        <div class="vehicle-header">
            <div class="vehicle-title">
                <h3>${vehicle.name}</h3>
                <p>${vehicle.plate} • ${vehicle.category}</p>
            </div>
            <div class="vehicle-actions">
                <button class="action-btn ${vehicle.favorite ? 'favorite' : ''}" onclick="toggleFavorite(event, ${vehicle.id})">
                    <i class="fas fa-star"></i>
                </button>
                <button class="action-btn menu-btn" onclick="toggleVehicleMenu(event, ${vehicle.id})">
                    <i class="fas fa-ellipsis-v"></i>
                </button>
            </div>
        </div>
        ${showImages ? `
        <div class="vehicle-image ${imageSrc ? 'has-image' : ''}">
            ${imageSrc ? `<img src="${imageSrc}" alt="${vehicle.name}">` : `
            <div class="vehicle-image-placeholder">
                <i class="fas fa-camera"></i>
                <span>No image</span>
            </div>`}
        </div>` : ''}
        <div class="vehicle-stats">
            <div class="stat-item">
                <div class="stat-icon fuel">
                    <i class="fas fa-gas-pump"></i>
                </div>
                <div class="stat-info">
                    <div class="stat-label">Fuel</div>
                    <div class="stat-bar">
                        <div class="stat-fill fuel" style="width: ${vehicle.fuel}%"></div>
                    </div>
                </div>
            </div>
            <div class="stat-item">
                <div class="stat-icon engine">
                    <i class="fas fa-cog"></i>
                </div>
                <div class="stat-info">
                    <div class="stat-label">Engine</div>
                    <div class="stat-bar">
                        <div class="stat-fill engine" style="width: ${vehicle.engine}%"></div>
                    </div>
                </div>
            </div>
            <div class="stat-item">
                <div class="stat-icon clean">
                    <i class="fas fa-spray-can"></i>
                </div>
                <div class="stat-info">
                    <div class="stat-label">Clean</div>
                    <div class="stat-bar">
                        <div class="stat-fill clean" style="width: ${vehicle.cleanliness}%"></div>
                    </div>
                </div>
            </div>
            <div class="stat-item">
                <div class="stat-icon damage">
                    <i class="fas fa-shield-alt"></i>
                </div>
                <div class="stat-info">
                    <div class="stat-label">Body</div>
                    <div class="stat-bar">
                        <div class="stat-fill body" style="width: ${vehicle.body}%"></div>
                    </div>
                </div>
            </div>
        </div>
        <div class="vehicle-footer">
            <div class="vehicle-location">
                <i class="fas fa-map-marker-alt"></i>
                <span>${vehicle.location}</span>
            </div>
            <div class="vehicle-footer-actions">
                <button class="spawn-btn" onclick="spawnVehicleById(event, ${vehicle.id})">
                    <i class="fas fa-key"></i> Spawn
                </button>
                <div class="vehicle-badges">
                    <span class="badge ${vehicle.titleStatus}">${capitalizeFirst(vehicle.titleStatus)}</span>
                    ${vehicle.policeHeat !== 'none' ? `<span class="badge ${heatClass}"><i class="fas fa-fire"></i></span>` : ''}
                </div>
            </div>
        </div>
        <div class="vehicle-menu" id="vehicleMenu-${vehicle.id}">
            <button class="menu-item" onclick="openVehicleModalById(${vehicle.id})">
                <i class="fas fa-info-circle"></i> Details
            </button>
            <button class="menu-item" onclick="openAddToFolderModal(${vehicle.id})">
                <i class="fas fa-folder-plus"></i> Add to folder
            </button>
            <button class="menu-item" onclick="spawnVehicleById(event, ${vehicle.id})">
                <i class="fas fa-key"></i> Spawn
            </button>
            ${showImages ? `
            <button class="menu-item" onclick="requestVehicleImage(${vehicle.id})">
                <i class="fas fa-camera"></i> Capture image
            </button>` : ''}
        </div>
    `;

    return card;
}

function filterVehicles() {
    let filtered = [...state.vehicles];

    // Apply folder filter
    if (state.currentFolder) {
        const folder = state.folders.find(f => f.id === state.currentFolder);
        filtered = filtered.filter(v => folder.vehicleIds.includes(v.id));
    }

    // Apply category filters
    switch (state.currentFilter) {
        case 'favorite':
            filtered = filtered.filter(v => v.favorite);
            break;
        case 'job':
            filtered = filtered.filter(v => v.isJobVehicle);
            break;
        case 'recent':
            filtered = filtered.sort((a, b) => b.lastUsed - a.lastUsed).slice(0, 5);
            break;
        case 'damaged':
            filtered = filtered.filter(v => v.body < 70 || v.engine < 70);
            break;
    }

    // Apply search
    if (state.searchQuery) {
        filtered = filtered.filter(v => 
            v.name.toLowerCase().includes(state.searchQuery) ||
            v.plate.toLowerCase().includes(state.searchQuery) ||
            v.category.toLowerCase().includes(state.searchQuery) ||
            v.location.toLowerCase().includes(state.searchQuery)
        );
    }

    // Sort favorites first, then by last used
    filtered.sort((a, b) => {
        if (a.favorite && !b.favorite) return -1;
        if (!a.favorite && b.favorite) return 1;
        return b.lastUsed - a.lastUsed;
    });

    return filtered;
}

// Modal Functions
function openVehicleModal(vehicle) {
    if (typeof vehicle === 'string') {
        vehicle = JSON.parse(vehicle.replace(/&quot;/g, '"'));
    }
    
    state.selectedVehicle = vehicle;
    closeAllMenus();
    const modal = document.getElementById('vehicleModal');
    
    // Update modal content
    document.getElementById('modalVehicleName').textContent = vehicle.name;
    document.getElementById('detailPlate').textContent = vehicle.plate;
    document.getElementById('detailTitle').innerHTML = `<span class="title-badge ${vehicle.titleStatus}">${capitalizeFirst(vehicle.titleStatus)} Title</span>`;
    document.getElementById('detailLocation').textContent = vehicle.location;
    document.getElementById('detailMileage').textContent = `${vehicle.mileage.toLocaleString()} km`;
    document.getElementById('detailInsurance').textContent = vehicle.insurance + ' Tier';
    
    const heatText = vehicle.policeHeat === 'high' ? 'High' : 
                     vehicle.policeHeat === 'medium' ? 'Medium' : 
                     vehicle.policeHeat === 'low' ? 'Low' : 'None';
    const heatColor = vehicle.policeHeat === 'high' ? 'var(--danger-color)' : 
                      vehicle.policeHeat === 'medium' ? 'var(--warning-color)' : 
                      'var(--success-color)';
    
    document.getElementById('detailHeat').innerHTML = `
        <div class="heat-indicator">
            <i class="fas fa-fire" style="color: ${heatColor}"></i>
            <span>${heatText}</span>
        </div>
    `;

    // Update condition bars
    updateConditionBar('conditionFuel', vehicle.fuel);
    updateConditionBar('conditionEngine', vehicle.engine);
    updateConditionBar('conditionBody', vehicle.body);
    updateConditionBar('conditionClean', vehicle.cleanliness);

    // Render timeline
    renderTimeline(vehicle.history);

    modal.classList.add('active');
}

function updateConditionBar(id, value) {
    const bar = document.getElementById(id);
    bar.style.width = value + '%';
    bar.nextElementSibling.textContent = value + '%';
}

function renderTimeline(history) {
    const timeline = document.getElementById('vehicleTimeline');
    timeline.innerHTML = '';

    history.sort((a, b) => b.date - a.date).forEach(event => {
        const eventEl = document.createElement('div');
        eventEl.className = `timeline-event ${event.type}`;
        eventEl.innerHTML = `
            <div class="timeline-date">${formatDate(event.date)}</div>
            <div class="timeline-title">${event.title}</div>
            <div class="timeline-desc">${event.description}</div>
        `;
        timeline.appendChild(eventEl);
    });
}

function closeModal() {
    document.getElementById('vehicleModal').classList.remove('active');
    // Reset to first tab
    document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
    document.querySelector('.tab-btn[data-tab="overview"]').classList.add('active');
    document.querySelector('.tab-content[data-tab="overview"]').classList.add('active');
}

function openVehicleModalById(vehicleId) {
    const vehicle = getVehicleById(vehicleId);
    if (vehicle) {
        closeAllMenus();
        openVehicleModal(vehicle);
    }
}

function toggleVehicleMenu(event, vehicleId) {
    event.stopPropagation();
    const menu = document.getElementById(`vehicleMenu-${vehicleId}`);
    if (!menu) return;

    const isOpen = menu.classList.contains('active');
    closeAllMenus();
    if (!isOpen) {
        menu.classList.add('active');
    }
}

function closeAllMenus() {
    document.querySelectorAll('.vehicle-menu').forEach(menu => menu.classList.remove('active'));
}

function spawnVehicleById(event, vehicleId) {
    if (event) {
        event.stopPropagation();
    }
    const vehicle = getVehicleById(vehicleId);
    if (!vehicle) return;
    spawnVehicle(vehicle);
}

// Folder Functions
function createFolder() {
    document.getElementById('folderModal').classList.add('active');
    document.getElementById('folderName').value = '';
}

function closeFolderModal() {
    document.getElementById('folderModal').classList.remove('active');
}

function saveFolder() {
    const name = document.getElementById('folderName').value.trim();
    if (!name) return;

    const selectedIcon = document.querySelector('.icon-option.active');
    const icon = selectedIcon ? selectedIcon.dataset.icon : 'folder';

    const newFolder = {
        id: state.folders.length + 1,
        name: name,
        icon: icon,
        vehicleIds: []
    };

    state.folders.push(newFolder);
    renderFolders();
    closeFolderModal();
}

function addVehicleToFolder(vehicleId, folderId) {
    const folder = state.folders.find(f => f.id === folderId);
    if (folder && !folder.vehicleIds.includes(vehicleId)) {
        folder.vehicleIds.push(vehicleId);
    }
}

function removeVehicleFromAllFolders(vehicleId) {
    state.folders.forEach(folder => {
        folder.vehicleIds = folder.vehicleIds.filter(id => id !== vehicleId);
    });
}

function openAddToFolderModal(vehicleId) {
    const vehicle = getVehicleById(vehicleId);
    if (!vehicle) return;
    state.selectedVehicle = vehicle;
    renderAddToFolderOptions(vehicleId);
    document.getElementById('addToFolderModal').classList.add('active');
    closeAllMenus();
}

function closeAddToFolderModal() {
    document.getElementById('addToFolderModal').classList.remove('active');
}

function renderAddToFolderOptions(vehicleId) {
    const select = document.getElementById('addToFolderSelect');
    const currentFolderId = getVehicleFolderId(vehicleId);
    select.innerHTML = '';

    const noneOption = document.createElement('option');
    noneOption.value = '';
    noneOption.textContent = 'No Folder';
    select.appendChild(noneOption);

    state.folders.forEach(folder => {
        const option = document.createElement('option');
        option.value = folder.id;
        option.textContent = folder.name;
        if (folder.id === currentFolderId) {
            option.selected = true;
        }
        select.appendChild(option);
    });
}

function saveAddToFolder() {
    const select = document.getElementById('addToFolderSelect');
    const folderId = select.value ? Number(select.value) : null;
    if (!state.selectedVehicle) return;

    removeVehicleFromAllFolders(state.selectedVehicle.id);
    if (folderId) {
        addVehicleToFolder(state.selectedVehicle.id, folderId);
    }

    renderFolders();
    renderVehicles();
    closeAddToFolderModal();
}

// Action Functions
function toggleFavorite(event, vehicleId) {
    event.stopPropagation();
    const vehicle = state.vehicles.find(v => v.id === vehicleId);
    if (vehicle) {
        vehicle.favorite = !vehicle.favorite;
        renderVehicles();
    }
}

function toggleFilters() {
    const container = document.getElementById('filtersContainer');
    container.style.display = container.style.display === 'none' ? 'flex' : 'none';
}

function openSettings() {
    refreshSettingsUI();
    document.getElementById('settingsModal').classList.add('active');
}

function closeSettings() {
    document.getElementById('settingsModal').classList.remove('active');
}

function bindSettingsInputs() {
    document.querySelectorAll('[data-var]').forEach(input => {
        input.addEventListener('input', (e) => {
            const cssVar = e.target.dataset.var;
            const value = e.target.value;
            state.settings.theme[cssVar] = value;
            applyTheme();
        });
    });

    const glassColor = document.getElementById('colorGlass');
    const glassOpacity = document.getElementById('glassOpacity');
    const borderColor = document.getElementById('colorBorder');
    const borderOpacity = document.getElementById('borderOpacity');

    glassColor.addEventListener('input', (e) => {
        state.settings.glassColor = e.target.value;
        applyTheme();
    });

    glassOpacity.addEventListener('input', (e) => {
        state.settings.glassOpacity = Number(e.target.value);
        applyTheme();
    });

    borderColor.addEventListener('input', (e) => {
        state.settings.borderColor = e.target.value;
        applyTheme();
    });

    borderOpacity.addEventListener('input', (e) => {
        state.settings.borderOpacity = Number(e.target.value);
        applyTheme();
    });

    const enableImagesToggle = document.getElementById('enableImagesToggle');
    enableImagesToggle.addEventListener('change', (e) => {
        state.settings.enableImages = e.target.checked;
        saveSettings(false);
        renderVehicles();
    });
}

function refreshSettingsUI() {
    document.querySelectorAll('[data-var]').forEach(input => {
        const cssVar = input.dataset.var;
        const value = state.settings.theme[cssVar] || defaultTheme[cssVar];
        input.value = normalizeHex(value);
    });

    document.getElementById('colorGlass').value = normalizeHex(state.settings.glassColor);
    document.getElementById('glassOpacity').value = state.settings.glassOpacity;
    document.getElementById('colorBorder').value = normalizeHex(state.settings.borderColor);
    document.getElementById('borderOpacity').value = state.settings.borderOpacity;
    document.getElementById('enableImagesToggle').checked = state.settings.enableImages;
}

function saveSettings(showToast = true) {
    localStorage.setItem('pfGarageSettings', JSON.stringify(state.settings));
    applyTheme();
    if (showToast) {
        closeSettings();
    }
}

function resetSettings() {
    state.settings = {
        enableImages: false,
        theme: { ...defaultTheme },
        glassColor: '#1e293b',
        glassOpacity: 0.85,
        borderColor: '#94a3b8',
        borderOpacity: 0.1
    };
    applyTheme();
    refreshSettingsUI();
    renderVehicles();
}

function loadSettings() {
    const saved = localStorage.getItem('pfGarageSettings');
    if (saved) {
        try {
            const parsed = JSON.parse(saved);
            state.settings = {
                ...state.settings,
                ...parsed,
                theme: { ...defaultTheme, ...(parsed.theme || {}) }
            };
        } catch (err) {
            state.settings = { ...state.settings, theme: { ...defaultTheme } };
        }
    }
    applyTheme();
}

function applyTheme() {
    Object.entries(state.settings.theme).forEach(([key, value]) => {
        document.documentElement.style.setProperty(key, value);
    });

    document.documentElement.style.setProperty('--bg-glass', hexToRgba(state.settings.glassColor, state.settings.glassOpacity));
    document.documentElement.style.setProperty('--border-color', hexToRgba(state.settings.borderColor, state.settings.borderOpacity));
}

function spawnVehicle(vehicleOverride) {
    const vehicle = vehicleOverride || state.selectedVehicle;
    if (!vehicle) return;
    
    // Send to FiveM client
    console.log('Spawning vehicle:', vehicle);
    
    // For FiveM integration:
    // fetch(`https://${GetParentResourceName()}/spawnVehicle`, {
    //     method: 'POST',
    //     headers: { 'Content-Type': 'application/json' },
    //     body: JSON.stringify({ vehicleId: vehicle.id })
    // });
    
    closeModal();
    closeGarage();
}

function closeGarage() {
    const container = document.getElementById('garageContainer');
    container.style.animation = 'slideOutLeft 0.3s cubic-bezier(0.4, 0, 1, 1) forwards';
    
    setTimeout(() => {
        container.style.display = 'none';
        
        // For FiveM integration:
        // fetch(`https://${GetParentResourceName()}/closeUI`, {
        //     method: 'POST',
        //     headers: { 'Content-Type': 'application/json' },
        //     body: JSON.stringify({})
        // });
    }, 300);
}

// Utility Functions
function getVehicleById(vehicleId) {
    return state.vehicles.find(v => v.id === vehicleId);
}

function getVehicleFolderId(vehicleId) {
    for (const folder of state.folders) {
        if (folder.vehicleIds.includes(vehicleId)) {
            return folder.id;
        }
    }
    return null;
}

function requestVehicleImage(vehicleId) {
    const vehicle = getVehicleById(vehicleId);
    if (!vehicle || !state.settings.enableImages) return;

    closeAllMenus();

    if (typeof GetParentResourceName === 'function') {
        fetch(`https://${GetParentResourceName()}/captureVehicleImage`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ vehicleId: vehicle.id, plate: vehicle.plate, model: vehicle.model })
        });
    } else {
        console.log('Capture image requested for:', vehicle);
    }
}

function setVehicleImageByPlate(plate, imageUrl) {
    const vehicle = state.vehicles.find(v => v.plate === plate);
    if (!vehicle) return;
    vehicle.imageUrl = imageUrl;
    renderVehicles();
}

function normalizeHex(value) {
    if (!value) return '#000000';
    if (value.startsWith('#')) return value;
    if (value.startsWith('rgb')) {
        const numbers = value.replace(/[rgba()\s]/g, '').split(',').slice(0, 3).map(n => parseInt(n, 10));
        return `#${numbers.map(n => n.toString(16).padStart(2, '0')).join('')}`;
    }
    return '#000000';
}

function hexToRgba(hex, alpha) {
    const clean = hex.replace('#', '');
    const r = parseInt(clean.substring(0, 2), 16) || 0;
    const g = parseInt(clean.substring(2, 4), 16) || 0;
    const b = parseInt(clean.substring(4, 6), 16) || 0;
    return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

function capitalizeFirst(str) {
    return str.charAt(0).toUpperCase() + str.slice(1);
}

function formatDate(date) {
    const options = { year: 'numeric', month: 'long', day: 'numeric' };
    return new Date(date).toLocaleDateString('en-US', options);
}

// Add slideOutLeft animation to CSS
const style = document.createElement('style');
style.textContent = `
    @keyframes slideOutLeft {
        from {
            opacity: 1;
            transform: translateY(-50%) translateX(0);
        }
        to {
            opacity: 0;
            transform: translateY(-50%) translateX(-50px);
        }
    }
`;
document.head.appendChild(style);

// FiveM Integration Listeners (for when connected to FiveM)
/*
window.addEventListener('message', (event) => {
    const data = event.data;
    
    switch(data.action) {
        case 'openGarage':
            document.getElementById('garageContainer').style.display = 'flex';
            if (data.vehicles) {
                state.vehicles = data.vehicles;
                renderVehicles();
            }
            break;
            
        case 'closeGarage':
            closeGarage();
            break;
            
        case 'updateVehicle':
            const vehicle = state.vehicles.find(v => v.id === data.vehicle.id);
            if (vehicle) {
                Object.assign(vehicle, data.vehicle);
                renderVehicles();
            }
            break;
        
        case 'updateVehicleImage':
            if (data.plate && data.imageUrl) {
                setVehicleImageByPlate(data.plate, data.imageUrl);
            }
            break;
    }
});
*/
