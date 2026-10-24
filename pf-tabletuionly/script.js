// GLOBAL FUNCTIONS - MUST BE FIRST
window.unlock = function() {
    console.log('>>> UNLOCK CALLED <<<');
    
    const lockscreen = document.getElementById('lockscreen');
    const homescreen = document.getElementById('homescreen');
    
    if (!lockscreen || !homescreen) {
        console.error('ERROR: Required elements not found!');
        return;
    }
    
    // Hide lockscreen
    lockscreen.style.display = 'none';
    
    // Show homescreen
    homescreen.style.display = 'flex';
    
    console.log('✓ Tablet unlocked successfully');
};

// Global State
let currentApp = null;
let isDragging = false;
let startY = 0;
let currentCalendarMonth = new Date();
let notes = [];
let currentNoteIndex = -1;
let noteEditor = null;
let installedApps = JSON.parse(localStorage.getItem('installedApps') || '[]');

// App Store Functions
function installApp(appId) {
    const listItem = document.querySelector(`.app-list-item[data-app-id="${appId}"]`);
    const btn = listItem.querySelector('.app-list-btn');
    
    // Check if already installed
    if (installedApps.includes(appId)) {
        return;
    }
    
    // Show installing state with spinner
    btn.classList.add('installing');
    btn.innerHTML = '<span class="spinner"></span>';
    
    // Simulate 10 second installation
    setTimeout(() => {
        // Mark as installed
        installedApps.push(appId);
        localStorage.setItem('installedApps', JSON.stringify(installedApps));
        
        // Update button to OPEN
        btn.classList.remove('installing');
        btn.classList.add('installed');
        btn.textContent = 'OPEN';
        btn.onclick = () => {
            closeApp();
            openApp(appId);
        };

        // Show uninstall action
        listItem.classList.add('installed');
        
        // Show app icon on homescreen
        const appIcon = document.querySelector(`.app-icon[data-app="${appId}"]`);
        if (appIcon) {
            appIcon.style.display = 'flex';
        }
    }, 10000);
}

function uninstallApp(appId) {
    const listItem = document.querySelector(`.app-list-item[data-app-id="${appId}"]`);
    if (!listItem) {
        return;
    }

    if (!installedApps.includes(appId)) {
        return;
    }

    installedApps = installedApps.filter(id => id !== appId);
    localStorage.setItem('installedApps', JSON.stringify(installedApps));

    const btn = listItem.querySelector('.app-list-btn');
    btn.classList.remove('installing', 'installed');
    btn.textContent = 'GET';
    btn.onclick = () => installApp(appId);

    listItem.classList.remove('installed');

    const appIcon = document.querySelector(`.app-icon[data-app="${appId}"]`);
    if (appIcon) {
        appIcon.style.display = 'none';
    }

    if (currentApp === appId) {
        closeApp();
    }
}

function checkInstalledApps() {
    // Check all apps in the store and update their button states
    installedApps.forEach(appId => {
        const listItem = document.querySelector(`.app-list-item[data-app-id="${appId}"]`);
        if (listItem) {
            const btn = listItem.querySelector('.app-list-btn');
            btn.classList.add('installed');
            btn.textContent = 'OPEN';
            btn.onclick = () => {
                closeApp();
                openApp(appId);
            };

            listItem.classList.add('installed');
        }
        
        // Show app icon on homescreen
        const appIcon = document.querySelector(`.app-icon[data-app="${appId}"]`);
        if (appIcon) {
            appIcon.style.display = 'flex';
        }
    });
    
    // Hide apps that are not installed
    const jobAppIds = ['taxi-job', 'garbage-job', 'bus-job', 'gruppe6-job'];
    jobAppIds.forEach(appId => {
        if (!installedApps.includes(appId)) {
            const appIcon = document.querySelector(`.app-icon[data-app="${appId}"]`);
            if (appIcon) {
                appIcon.style.display = 'none';
            }
        }
    });
}

// Initialize on load
document.addEventListener('DOMContentLoaded', function() {
    console.log('=== TABLET INITIALIZATION ===');
    console.log('DOM loaded');
    
    initializeTime();
    initializeUnlockGesture();
    initializeAppIcons();
    initializeHomeIndicators();
    loadSettings();
    loadNotes();
    setInterval(updateTime, 1000);
    
    // Initialize bus routes
    renderBusRoutes();

    // Initialize garbage app UI
    initializeGarbageUI();

    // Initialize Gruppe6 app UI
    initializeGruppe6UI();
    
    // Check installed apps and update UI
    checkInstalledApps();
    
    console.log('✓ Tablet initialization complete');
    console.log('✓ Type unlock() to test unlock');
});


// Time Functions
function initializeTime() {
    updateTime();
    updateLockTime();
}

function updateTime() {
    const now = new Date();
    const hours = String(now.getHours()).padStart(2, '0');
    const minutes = String(now.getMinutes()).padStart(2, '0');
    const seconds = String(now.getSeconds()).padStart(2, '0');
    
    // Update status bar time
    const statusTime = document.getElementById('status-time');
    if (statusTime) {
        statusTime.textContent = `${hours}:${minutes}`;
    }
    
    // Update clock app if open
    const clockTime = document.getElementById('clock-time');
    if (clockTime) {
        clockTime.textContent = `${hours}:${minutes}:${seconds}`;
    }
    
    updateLockTime();
}

function updateLockTime() {
    const now = new Date();
    const hours = String(now.getHours()).padStart(2, '0');
    const minutes = String(now.getMinutes()).padStart(2, '0');
    
    const lockTime = document.getElementById('lock-time');
    const lockDate = document.getElementById('lock-date');
    const clockDate = document.getElementById('clock-date');
    
    if (lockTime) {
        lockTime.textContent = `${hours}:${minutes}`;
    }
    
    const options = { weekday: 'long', month: 'long', day: 'numeric' };
    const dateString = now.toLocaleDateString('en-US', options);
    
    if (lockDate) {
        lockDate.textContent = dateString;
    }
    
    if (clockDate) {
        const fullOptions = { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' };
        clockDate.textContent = now.toLocaleDateString('en-US', fullOptions);
    }
}

// Unlock Gesture
function initializeUnlockGesture() {
    const lockscreen = document.getElementById('lockscreen');
    
    if (!lockscreen) {
        console.error('Lockscreen not found for gesture initialization');
        return;
    }
    
    let startY = 0;
    let startX = 0;
    let isDragging = false;
    const threshold = 50;
    
    // Track pointer down
    lockscreen.addEventListener('pointerdown', function(e) {
        // Don't interfere with text/button clicks
        if (e.target.querySelector && e.target.querySelector('.unlock-text')) return;
        
        isDragging = true;
        startY = e.clientY;
        startX = e.clientX;
    }, true);
    
    // Track pointer up
    document.addEventListener('pointerup', function(e) {
        if (!isDragging) return;
        
        const endY = e.clientY;
        const endX = e.clientX;
        const deltaY = startY - endY;
        const deltaX = Math.abs(startX - endX);
        
        // Upward swipe detected
        if (deltaY > threshold && deltaX < 50) {
            console.log('Swipe gesture detected, unlocking...');
            unlock();
        }
        
        isDragging = false;
    }, true);
}

// App Navigation
function initializeAppIcons() {
    const appIcons = document.querySelectorAll('.app-icon');
    const dockApps = document.querySelectorAll('.dock-app');
    
    appIcons.forEach(icon => {
        icon.addEventListener('click', function() {
            const appName = this.getAttribute('data-app');
            openApp(appName);
        });
    });
    
    dockApps.forEach(app => {
        app.addEventListener('click', function() {
            const appName = this.getAttribute('data-app');
            openApp(appName);
        });
    });
}

function openApp(appName) {
    const homescreen = document.getElementById('homescreen');
    const app = document.getElementById(`app-${appName}`);
    
    if (app) {
        currentApp = appName;
        homescreen.style.display = 'none';
        app.style.display = 'block';
        
        // Initialize app-specific content
        if (appName === 'calendar') {
            renderCalendar();
        } else if (appName === 'notes') {
            showNotesEditor();
        } else if (appName === 'work-orders') {
            loadWorkOrdersApp();
        } else if (appName === 'cash-register') {
            initializeCashRegister();
        } else if (appName === 'gruppe6-job') {
            // Re-render gruppe6 contracts when opening the app
            if (typeof renderGruppe6Contracts === 'function') {
                renderGruppe6Contracts();
            }
        } else if (appName === 'bus-job') {
            // Re-render bus routes when opening the app
            if (typeof renderBusRoutes === 'function') {
                renderBusRoutes();
            }
        }
    }
}

function closeApp() {
    if (currentApp) {
        const app = document.getElementById(`app-${currentApp}`);
        const homescreen = document.getElementById('homescreen');
        
        if (app) {
            app.style.display = 'none';
        }
        
        homescreen.style.display = 'block';
        currentApp = null;
    }
}

// Home Indicator Click Handler
function initializeHomeIndicators() {
    const indicators = document.querySelectorAll('.home-indicator');
    indicators.forEach(indicator => {
        indicator.style.cursor = 'pointer';
        indicator.addEventListener('click', function() {
            closeApp();
        });
    });
}

// Settings Functions
function loadSettings() {
    // Load theme
    const theme = localStorage.getItem('theme') || 'dark';
    document.documentElement.setAttribute('data-theme', theme);
    
    // Load wallpaper
    const wallpaperType = localStorage.getItem('wallpaperType') || 'gradient';
    const wallpaperUrl = localStorage.getItem('wallpaperUrl');
    const gradient = localStorage.getItem('gradient') || 'default';
    const brightness = localStorage.getItem('brightness') || '100';
    const textSize = localStorage.getItem('textSize') || 'medium';
    
    // Apply settings
    if (wallpaperType === 'image' && wallpaperUrl) {
        applyWallpaperImage(wallpaperUrl);
    } else {
        applyGradientWallpaper(gradient);
    }
    
    const tablet = document.querySelector('.tablet');
    if (tablet) {
        tablet.style.filter = `brightness(${brightness}%)`;
        tablet.classList.add(`text-${textSize}`);
    }
    
    // Update UI elements
    const themeSelect = document.getElementById('theme-select');
    const wallpaperTypeSelect = document.getElementById('wallpaper-type-select');
    const gradientSelect = document.getElementById('gradient-select');
    const wallpaperUrlInput = document.getElementById('wallpaper-url');
    const brightnessSlider = document.getElementById('brightness-slider');
    const brightnessValue = document.getElementById('brightness-value');
    const textSizeSelect = document.getElementById('text-size-select');
    
    if (themeSelect) themeSelect.value = theme;
    if (wallpaperTypeSelect) wallpaperTypeSelect.value = wallpaperType;
    if (gradientSelect) gradientSelect.value = gradient;
    if (wallpaperUrlInput) wallpaperUrlInput.value = wallpaperUrl || '';
    if (brightnessSlider) brightnessSlider.value = brightness;
    if (brightnessValue) brightnessValue.textContent = brightness + '%';
    if (textSizeSelect) textSizeSelect.value = textSize;
    
    // Show/hide wallpaper options based on type
    const gradientOptions = document.getElementById('gradient-options');
    const imageOptions = document.getElementById('image-options');
    if (gradientOptions && imageOptions) {
        if (wallpaperType === 'gradient') {
            gradientOptions.style.display = 'flex';
            imageOptions.style.display = 'none';
        } else {
            gradientOptions.style.display = 'none';
            imageOptions.style.display = 'flex';
        }
    }
}

function showSettingsPage(pageName) {
    const settingsMenu = document.querySelector('.settings-menu');
    const settingsPage = document.getElementById(`settings-${pageName}`);
    
    if (settingsMenu && settingsPage) {
        settingsMenu.style.display = 'none';
        settingsPage.style.display = 'block';
    }
}

function hideSettingsPage() {
    const settingsMenu = document.querySelector('.settings-menu');
    const settingsPages = document.querySelectorAll('.settings-page');
    
    settingsPages.forEach(page => {
        page.style.display = 'none';
    });
    
    if (settingsMenu) {
        settingsMenu.style.display = 'block';
    }
}

function changeTheme() {
    const theme = document.getElementById('theme-select').value;
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('theme', theme);
    console.log('Theme changed to:', theme);
}

function toggleWallpaperOptions() {
    const wallpaperType = document.getElementById('wallpaper-type-select').value;
    const gradientOptions = document.getElementById('gradient-options');
    const imageOptions = document.getElementById('image-options');
    
    if (wallpaperType === 'gradient') {
        gradientOptions.style.display = 'flex';
        imageOptions.style.display = 'none';
        const gradient = document.getElementById('gradient-select').value;
        applyGradientWallpaper(gradient);
    } else {
        gradientOptions.style.display = 'none';
        imageOptions.style.display = 'flex';
    }
    
    localStorage.setItem('wallpaperType', wallpaperType);
}

function applyGradient() {
    const gradient = document.getElementById('gradient-select').value;
    applyGradientWallpaper(gradient);
    localStorage.setItem('gradient', gradient);
}

function applyGradientWallpaper(gradient) {
    const wallpaper = document.querySelector('.wallpaper');
    const gradients = {
        'default': 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
        'blue': 'linear-gradient(135deg, #2193b0 0%, #6dd5ed 100%)',
        'pink': 'linear-gradient(135deg, #f093fb 0%, #f5576c 100%)',
        'green': 'linear-gradient(135deg, #11998e 0%, #38ef7d 100%)',
        'orange': 'linear-gradient(135deg, #fa8c16 0%, #ff6b6b 100%)'
    };
    
    if (wallpaper) {
        wallpaper.style.background = gradients[gradient] || gradients['default'];
    }
}

function applyWallpaperUrl() {
    const url = document.getElementById('wallpaper-url').value.trim();
    if (url) {
        applyWallpaperImage(url);
        localStorage.setItem('wallpaperUrl', url);
        localStorage.setItem('wallpaperType', 'image');
    }
}

function applyWallpaperImage(url) {
    const wallpaper = document.querySelector('.wallpaper');
    if (wallpaper) {
        wallpaper.style.background = `url('${url}') center/cover no-repeat`;
        wallpaper.style.backgroundSize = 'cover';
        wallpaper.style.backgroundPosition = 'center';
    }
}

function changeBrightness() {
    const brightness = document.getElementById('brightness-slider').value;
    const brightnessValue = document.getElementById('brightness-value');
    const tablet = document.querySelector('.tablet');
    
    if (brightnessValue) {
        brightnessValue.textContent = brightness + '%';
    }
    
    if (tablet) {
        tablet.style.filter = `brightness(${brightness}%)`;
    }
    
    localStorage.setItem('brightness', brightness);
}

function changeTextSize() {
    const textSize = document.getElementById('text-size-select').value;
    const tablet = document.querySelector('.tablet');
    
    if (tablet) {
        tablet.classList.remove('text-small', 'text-medium', 'text-large');
        tablet.classList.add(`text-${textSize}`);
    }
    
    localStorage.setItem('textSize', textSize);
}

// Calendar Functions
function renderCalendar() {
    const calendarGrid = document.getElementById('calendar-grid');
    const calendarMonth = document.getElementById('calendar-month');
    
    if (!calendarGrid) return;
    
    const year = currentCalendarMonth.getFullYear();
    const month = currentCalendarMonth.getMonth();
    
    // Update header
    const monthNames = ['January', 'February', 'March', 'April', 'May', 'June',
                        'July', 'August', 'September', 'October', 'November', 'December'];
    if (calendarMonth) {
        calendarMonth.textContent = `${monthNames[month]} ${year}`;
    }
    
    // Clear grid
    calendarGrid.innerHTML = '';
    
    // Add day headers
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    days.forEach(day => {
        const dayHeader = document.createElement('div');
        dayHeader.className = 'calendar-day-header';
        dayHeader.textContent = day;
        calendarGrid.appendChild(dayHeader);
    });
    
    // Get first day of month and number of days
    const firstDay = new Date(year, month, 1).getDay();
    const daysInMonth = new Date(year, month + 1, 0).getDate();
    const daysInPrevMonth = new Date(year, month, 0).getDate();
    
    // Add previous month days
    for (let i = firstDay - 1; i >= 0; i--) {
        const dayElement = document.createElement('div');
        dayElement.className = 'calendar-day other-month';
        dayElement.textContent = daysInPrevMonth - i;
        calendarGrid.appendChild(dayElement);
    }
    
    // Add current month days
    const today = new Date();
    for (let day = 1; day <= daysInMonth; day++) {
        const dayElement = document.createElement('div');
        dayElement.className = 'calendar-day';
        
        if (day === today.getDate() && month === today.getMonth() && year === today.getFullYear()) {
            dayElement.classList.add('today');
        }
        
        dayElement.textContent = day;
        calendarGrid.appendChild(dayElement);
    }
    
    // Add next month days to fill grid
    const totalCells = calendarGrid.children.length - 7; // Subtract day headers
    const remainingCells = 42 - totalCells - 7; // 6 rows * 7 days - current cells - headers
    for (let i = 1; i <= remainingCells; i++) {
        const dayElement = document.createElement('div');
        dayElement.className = 'calendar-day other-month';
        dayElement.textContent = i;
        calendarGrid.appendChild(dayElement);
    }
}

function previousMonth() {
    currentCalendarMonth.setMonth(currentCalendarMonth.getMonth() - 1);
    renderCalendar();
}

function nextMonth() {
    currentCalendarMonth.setMonth(currentCalendarMonth.getMonth() + 1);
    renderCalendar();
}

// Clock Functions
function switchClockTab(tab) {
    const tabs = document.querySelectorAll('.clock-tab');
    tabs.forEach(t => t.classList.remove('active'));
    
    event.target.classList.add('active');
    
    // Switch clock content would go here
    console.log('Switched to clock tab:', tab);
}

// Notes Functions
function loadNotes() {
    const saved = localStorage.getItem('tabletNotes');
    if (saved) {
        notes = JSON.parse(saved);
    }
}

function  saveNotes() {
    localStorage.setItem('tabletNotes', JSON.stringify(notes));
}

function showNotesEditor() {
    const editorView = document.querySelector('.notes-editor-view');
    const listView = document.querySelector('.notes-list-view');
    const headerTitle = document.getElementById('current-note-title');
    
    editorView.style.display = 'block';
    listView.style.display = 'none';
    
    // Initialize RTE if not already done
    if (!noteEditor) {
        noteEditor = createRTE('note-editor-container', {
            minHeight: '300px',
            maxHeight: '500px',
            placeholder: 'Start typing your note...'
        });
    }
    
    // If editing existing note
    if (currentNoteIndex >= 0 && notes[currentNoteIndex]) {
        const note = notes[currentNoteIndex];
        document.getElementById('note-title-input').value = note.title || '';
        noteEditor.setValue(note.content || '');
        headerTitle.textContent = note.title || 'Edit Note';
    } else {
        // New note
        document.getElementById('note-title-input').value = '';
        noteEditor.setValue('');
        headerTitle.textContent = 'New Note';
        currentNoteIndex = -1;
    }
}

function showNotesList() {
    const editorView = document.querySelector('.notes-editor-view');
    const listView = document.querySelector('.notes-list-view');
    
    editorView.style.display = 'none';
    listView.style.display = 'block';
    
    renderNotesList();
}

function renderNotesList() {
    const notesList = document.getElementById('notes-list');
    
    if (!notesList) return;
    
    if (notes.length === 0) {
        notesList.innerHTML = '<div class="empty-state">No notes yet. Tap + to create one.</div>';
    } else {
        notesList.innerHTML = '';
        notes.forEach((note, index) => {
            const noteElement = document.createElement('div');
            noteElement.className = 'note-item';
            const preview = note.content ? note.content.replace(/<[^>]*>/g, '').substring(0, 100) : 'No content';
            noteElement.innerHTML = `
                <div class="note-title">${note.title || 'Untitled'}</div>
                <div class="note-preview">${preview}...</div>
            `;
            noteElement.addEventListener('click', () => editNote(index));
            notesList.appendChild(noteElement);
        });
    }
}

function createNewNote() {
    currentNoteIndex = -1;
    showNotesEditor();
}

function saveNote() {
    const title = document.getElementById('note-title-input').value.trim();
    const content = noteEditor ? noteEditor.getValue() : '';
    
    if (!title && !content) {
        alert('Please enter a title or content for your note.');
        return;
    }
    
    const note = {
        title: title || 'Untitled',
        content: content,
        date: new Date().toISOString()
    };
    
    if (currentNoteIndex >= 0) {
        // Update existing note
        notes[currentNoteIndex] = note;
    } else {
        // Create new note
        notes.push(note);
    }
    
    saveNotes();
    showNotesList();
}

function editNote(index) {
    currentNoteIndex = index;
    showNotesEditor();
}

// Utility Functions
function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

// ========================================
// WORK ORDERS APP FUNCTIONS
// ========================================

let workOrdersData = null;
let workOrdersSearching = false;

// Placeholder work order data for demo
const placeholderWorkOrderData = {
    level: 3,
    levelName: 'Journeyman',
    xp: 650,
    currentLevelXP: 500,
    nextLevelXP: 1000,
    totalJobs: 12,
    payMultiplier: 1.5,
    maxOffers: 3,
    isSearching: false,
    availableOrders: [
        {
            id: 1,
            title: 'Engine Diagnostic',
            difficulty: 'medium',
            difficultyName: 'Medium',
            customer: 'John Smith',
            vehicle: 'Overflod Entity',
            repairType: 'diagnostics',
            taskType: 'diagnostics',
            duration: '30 mins',
            basePay: 350,
            xpReward: 180
        },
        {
            id: 2,
            title: 'Tire Replacement',
            difficulty: 'easy',
            difficultyName: 'Easy',
            customer: 'Maria Garcia',
            vehicle: 'Benefactor Schafter',
            repairType: 'tire',
            taskType: 'tire',
            duration: '15 mins',
            basePay: 150,
            xpReward: 75
        },
        {
            id: 3,
            title: 'Transmission Repair',
            difficulty: 'hard',
            difficultyName: 'Hard',
            customer: 'David Chen',
            vehicle: 'Pegassi Zentorno',
            repairType: 'transmission',
            taskType: 'transmission',
            duration: '45 mins',
            basePay: 700,
            xpReward: 350
        }
    ],
    acceptedOrders: [
        {
            id: 101,
            title: 'Brake System Service',
            difficulty: 'medium',
            difficultyName: 'Medium',
            customer: 'Robert Wilson',
            vehicle: 'Oracle',
            repairType: 'brakes',
            taskType: 'brakes',
            duration: '25 mins',
            basePay: 400,
            xpReward: 200
        }
    ]
};

// Load work orders data when app opens
function loadWorkOrdersApp() {
    // Show placeholder data immediately for better UX
    updateWorkOrdersUI(JSON.parse(JSON.stringify(placeholderWorkOrderData)));
    
    // Then request actual data from server
    const payload = { action: 'workOrdersGetData' };
    if (window.parent && window.parent.postMessage) {
        window.parent.postMessage(payload, '*');
    }
}

// Update work orders UI with data from server
function updateWorkOrdersUI(data) {
    if (!data) return;
    
    workOrdersData = data;
    
    // Update progress section
    document.getElementById('wo-level-name').textContent = data.levelName || 'Apprentice';
    document.getElementById('wo-level').textContent = data.level || 1;
    document.getElementById('wo-jobs-done').textContent = data.totalJobs || 0;
    
    // Update XP bar
    const currentLevelXP = data.currentLevelXP || 0;
    const nextLevelXP = data.nextLevelXP || 100;
    const currentXP = data.xp || 0;
    const xpInCurrentLevel = currentXP - currentLevelXP;
    const xpNeededForLevel = nextLevelXP - currentLevelXP;
    const xpPercentage = (xpInCurrentLevel / xpNeededForLevel) * 100;
    
    document.getElementById('wo-xp-fill').style.width = Math.min(100, Math.max(0, xpPercentage)) + '%';
    document.getElementById('wo-xp-current').textContent = Math.max(0, xpInCurrentLevel);
    document.getElementById('wo-xp-next').textContent = xpNeededForLevel;
    
    // Update search status
    workOrdersSearching = data.isSearching || false;
    updateSearchButtonState();
    
    // Render available orders
    renderAvailableOrders(data.availableOrders || []);
    
    // Render active order
    renderActiveOrder(data.acceptedOrders || []);
}

// Update search button state
function updateSearchButtonState() {
    const btn = document.getElementById('wo-search-btn');
    const status = document.getElementById('wo-search-status');
    
    if (workOrdersSearching) {
        btn.classList.add('searching');
        btn.innerHTML = '<span class="wo-btn-icon">⏹</span><span class="wo-btn-text">Stop Searching</span>';
        status.style.display = 'flex';
    } else {
        btn.classList.remove('searching');
        btn.innerHTML = '<span class="wo-btn-icon">⊙</span><span class="wo-btn-text">Find Jobs</span>';
        status.style.display = 'none';
    }
}

// Toggle work order search
function toggleWorkOrderSearch() {
    if (workOrdersSearching) {
        // Stop searching
        const payload = { action: 'workOrdersStopSearch' };
        if (window.parent && window.parent.postMessage) {
            window.parent.postMessage(payload, '*');
        }
    } else {
        // Start searching
        const payload = { action: 'workOrdersStartSearch' };
        if (window.parent && window.parent.postMessage) {
            window.parent.postMessage(payload, '*');
        }
    }
}

// Render available orders
function renderAvailableOrders(orders) {
    const container = document.getElementById('wo-available-orders');
    const countBadge = document.getElementById('wo-job-count');
    
    if (!container) return;
    
    if (!orders || orders.length === 0) {
        container.innerHTML = `
            <div class="wo-no-jobs">
                <span class="wo-no-jobs-icon">◭</span>
                <p>Search for jobs to begin</p>
            </div>
        `;
        if (countBadge) countBadge.textContent = '0';
        return;
    }
    
    container.innerHTML = '';
    if (countBadge) countBadge.textContent = orders.length;
    
    orders.forEach(order => {
        const card = createOrderCard(order);
        container.appendChild(card);
    });
}

// Create order card element
function createOrderCard(order) {
    const card = document.createElement('div');
    card.className = `wo-job-card difficulty-${getDifficultyClass(order.difficulty)}`;
    
    const difficultyName = order.difficultyName || order.difficulty || 'Unknown';
    const basePay = order.basePay || 0;
    const xpReward = order.xpReward || 0;
    
    card.innerHTML = `
        <div class="wo-job-title">${order.title || 'Unknown Job'}</div>
        <div class="wo-job-badge">${difficultyName}</div>
        <div class="wo-job-meta">
            <div class="wo-meta-item">
                <span class="wo-meta-icon">◎</span>
                <span class="wo-meta-text">${order.customer || 'N/A'}</span>
            </div>
            <div class="wo-meta-item">
                <span class="wo-meta-icon">▪</span>
                <span class="wo-meta-text">${order.vehicle || 'N/A'}</span>
            </div>
            <div class="wo-meta-item">
                <span class="wo-meta-icon">⏲</span>
                <span class="wo-meta-text">${order.duration || 'N/A'}</span>
            </div>
            <div class="wo-meta-item">
                <span class="wo-meta-icon">⚙</span>
                <span class="wo-meta-text">${order.repairType || order.taskType || 'N/A'}</span>
            </div>
        </div>
        <div class="wo-job-footer">
            <div class="wo-job-rewards">
                <div class="wo-reward wo-pay">$ ${basePay}</div>
                <div class="wo-reward wo-xp-reward">★ ${xpReward}</div>
            </div>
            <button class="wo-accept-btn" onclick="acceptWorkOrder(${order.id})">→ Accept</button>
        </div>
    `;
    
    return card;
}

// Accept a work order
function acceptWorkOrder(orderId) {
    const payload = { action: 'workOrdersAccept', orderId: orderId };
    if (window.parent && window.parent.postMessage) {
        window.parent.postMessage(payload, '*');
    }
}

// Render active order
function renderActiveOrder(acceptedOrders) {
    const container = document.getElementById('wo-active-order');
    
    if (!container) return;
    
    if (!acceptedOrders || acceptedOrders.length === 0) {
        container.innerHTML = `
            <div class="wo-no-active">
                <span class="wo-no-active-icon">◐</span>
                <p>No active job</p>
                <small>Accept a job to get started</small>
            </div>
        `;
        return;
    }
    
    const order = acceptedOrders[0]; // Only show first active order
    const basePay = order.basePay || 0;
    const xpReward = order.xpReward || 0;
    const difficultyName = order.difficultyName || order.difficulty || 'Unknown';
    
    container.innerHTML = `
        <div class="wo-active-job">
            <div class="wo-active-header">
                <div class="wo-active-icon">⚙</div>
                <div class="wo-active-info">
                    <div class="wo-active-title">${order.title || 'Unknown Job'}</div>
                    <div class="wo-active-customer">by ${order.customer || 'N/A'}</div>
                </div>
                <div class="wo-active-status">${difficultyName}</div>
            </div>
            
            <div class="wo-active-details">
                <div class="wo-detail">
                    <div class="wo-detail-label">Vehicle</div>
                    <div class="wo-detail-value">${order.vehicle || 'N/A'}</div>
                </div>
                <div class="wo-detail">
                    <div class="wo-detail-label">Work Type</div>
                    <div class="wo-detail-value">${order.repairType || order.taskType || 'N/A'}</div>
                </div>
                <div class="wo-detail">
                    <div class="wo-detail-label">Duration</div>
                    <div class="wo-detail-value">${order.duration || 'N/A'}</div>
                </div>
                <div class="wo-detail">
                    <div class="wo-detail-label">Payment</div>
                    <div class="wo-detail-value">$ ${basePay}</div>
                </div>
            </div>

            <div class="wo-active-buttons">
                <button class="wo-btn-cancel" onclick="cancelWorkOrder(${order.id})">
                    <span class="wo-btn-icon-small">✕</span>
                    Cancel Job
                </button>
            </div>
        </div>
    `;
}

// Complete a work order
function completeWorkOrder(orderId) {
    const payload = { action: 'workOrdersComplete', orderId: orderId };
    if (window.parent && window.parent.postMessage) {
        window.parent.postMessage(payload, '*');
    }
}

// Cancel a work order
function cancelWorkOrder(orderId) {
    if (confirm('Are you sure you want to cancel this job? You will lose 50% of the XP reward.')) {
        const payload = { action: 'workOrdersCancel', orderId: orderId };
        if (window.parent && window.parent.postMessage) {
            window.parent.postMessage(payload, '*');
        }
    }
}

// Get difficulty class name
function getDifficultyClass(difficulty) {
    const difficultyMap = {
        'easy': 'easy',
        'medium': 'medium',
        'hard': 'hard',
        'extreme': 'extreme',
        '1': 'easy',
        '2': 'medium',
        '3': 'hard',
        '4': 'extreme'
    };
    return difficultyMap[String(difficulty).toLowerCase()] || 'medium';
}

// Listen for work orders data from FiveM/parent
window.addEventListener('message', function(event) {
    const data = event.data;
    
    if (data.type === 'jobUpdate') {
        updateMechanicAppVisibility(data.playerData);
    } else if (data.type === 'workOrdersDataUpdate') {
        updateWorkOrdersUI(data.data);
    } else if (data.type === 'gruppe6GroupUpdate') {
        g6ApplyGroupUpdate(data.group);
    } else if (data.type === 'gruppe6InviteReceived') {
        g6ShowInvite(data.invite);
    } else if (data.type === 'workOrdersRefresh') {
        // Refresh the current app if it's open
        if (currentApp === 'work-orders') {
            loadWorkOrdersApp();
        }
    }
});

// Update openApp to load work orders data
const originalOpenApp = window.openApp || function(){};
window.openApp = function(appName) {
    if (typeof originalOpenApp === 'function') {
        originalOpenApp.call(this, appName);
    } else {
        const homescreen = document.getElementById('homescreen');
        const app = document.getElementById(`app-${appName}`);
        
        if (app) {
            currentApp = appName;
            homescreen.style.display = 'none';
            app.style.display = 'block';
            
            // Initialize app-specific content
            if (appName === 'calendar') {
                renderCalendar();
            } else if (appName === 'notes') {
                showNotesEditor();
            } else if (appName === 'work-orders') {
                loadWorkOrdersApp();
            } else if (appName === 'cash-register') {
                initializeCashRegister();
            }
        }
    }
};

// Mechanic Job App Management
let playerJob = null;

// Check if player has mechanic job
function isMechanicJob(job) {
    const mechanicJobs = ['mechanic', 'mechanic2', 'mechanic3', 'bennys', 'beeker'];
    return job && mechanicJobs.includes(job.toLowerCase());
}

// Check if player has specific job type
function hasJobType(job, jobType) {
    if (!job) return false;
    job = job.toLowerCase();
    
    switch(jobType) {
        case 'mechanic':
            return isMechanicJob(job);
        case 'garbage':
            return job === 'garbage';
        case 'taxi':
            return job === 'taxi';
        case 'bus':
            return job === 'bus';
        case 'gruppe6':
            return job === 'gruppe6';
        default:
            return false;
    }
}

// Update app visibility based on job
function updateJobAppVisibility(playerData) {
    const appMappings = {
        'mechanic-app': 'mechanic',
        'garbage-app': 'garbage',
        'taxi-app': 'taxi',
        'bus-app': 'bus',
        'gruppe6-app': 'gruppe6'
    };
    
    console.log('Updating job app visibility:', playerData);
    
    // Update all job-specific apps
    for (const [className, jobType] of Object.entries(appMappings)) {
        const appElements = document.querySelectorAll('.' + className);
        
        if (playerData && playerData.job && hasJobType(playerData.job, jobType)) {
            appElements.forEach(app => {
                app.style.display = '';
                console.log('Showing app:', app.getAttribute('data-app'), 'for job:', playerData.job);
            });
        } else {
            appElements.forEach(app => {
                app.style.display = 'none';
            });
        }
    }
    
    playerJob = (playerData && playerData.job) ? playerData.job : null;
}

// Update mechanic app visibility (kept for backwards compatibility)
function updateMechanicAppVisibility(playerData) {
    updateJobAppVisibility(playerData);
}

// Listen for job changes from FiveM
window.addEventListener('message', function(event) {
    const data = event.data;
    console.log('Message received:', data);
    
    if (data.type === 'jobUpdate') {
        console.log('Job update detected:', data.playerData);
        updateMechanicAppVisibility(data.playerData);
    }
});

// Request initial player data on load
document.addEventListener('DOMContentLoaded', function() {
    console.log('DOM Content Loaded - requesting player data');
    // Send message to get initial player data
    if (window.parent && window.parent.postMessage) {
        window.parent.postMessage({
            type: 'getPlayerData'
        }, '*');
        console.log('Player data request sent');
    }
});

// ============================================================================
// CASH REGISTER SYSTEM
// ============================================================================

let registerItems = {};
let registerCart = {};
let currentFilter = 'all';
let taxRate = 0.08;

function initializeCashRegister() {
    // Initialize with demo items as fallback
    registerItems = {
        test_item: {
            label: '[TEST] Oil Change Service',
            basePrice: 89.99,
            category: 'Diagnostics & Service'
        },
        test_tool: {
            label: '[TEST] Diagnostics Tool',
            basePrice: 1200.00,
            category: 'Diagnostics & Service'
        },
        test_battery: {
            label: '[TEST] Car Battery',
            basePrice: 299.99,
            category: 'Repair Parts'
        }
    };
    populateRegisterItems();
    
    // Request register items from server (will override demo items if successful)
    fetch('https://pf-tabletuionly/getCashRegisterItems', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    })
    .then(r => r.json())
    .then(data => {
        if (data.items && Object.keys(data.items).length > 0) {
            registerItems = data.items;
            registerItems.test_item = {
                label: '[TEST] Oil Change Service',
                basePrice: 89.99,
                category: 'Diagnostics & Service'
            };
            if (data.taxRate) taxRate = data.taxRate;
            populateRegisterItems();
            console.log('✓ Cash Register Items Loaded:', Object.keys(registerItems).length, 'items');
        }
    })
    .catch(e => console.error('Error loading register items:', e));
}

function populateRegisterItems(filter = 'all') {
    const container = document.getElementById('registerItems');
    if (!container) return;
    
    const categorized = {};
    let visibleCount = 0;
    
    // Categorize items
    for (const [itemId, itemData] of Object.entries(registerItems)) {
        const category = itemData.category || 'Other';
        if (!categorized[category]) categorized[category] = [];
        categorized[category].push({ id: itemId, ...itemData });
    }
    
    // Render items
    let html = '';
    for (const [category, items] of Object.entries(categorized)) {
        if (filter !== 'all' && category !== filter) continue;
        
        for (const item of items) {
            visibleCount++;
            const qty = registerCart[item.id]?.qty || 0;
            html += `
                <div class="register-item" data-item-id="${item.id}" data-category="${category}">
                    <div class="register-item-name">${item.label}</div>
                    <div class="register-item-price">$${item.basePrice.toFixed(2)}</div>
                    <div class="register-item-category">${category}</div>
                    <div class="register-item-qty">
                        <button class="qty-btn" onclick="adjustItemQuantity('${item.id}', -1)">−</button>
                        <div class="qty-display">${qty > 0 ? qty : '+'}</div>
                        <button class="qty-btn" onclick="adjustItemQuantity('${item.id}', 1)">+</button>
                    </div>
                </div>
            `;
        }
    }
    
    if (visibleCount === 0) {
        html = '<div class="empty-state">No items in this category</div>';
    }
    
    container.innerHTML = html;
}

function filterCategory(category) {
    currentFilter = category;
    
    // Update active button
    document.querySelectorAll('.category-btn').forEach(btn => {
        btn.classList.toggle('active', btn.dataset.category === category);
    });
    
    populateRegisterItems(category);
}

function adjustItemQuantity(itemId, amount) {
    if (!registerItems[itemId]) return;
    
    if (!registerCart[itemId]) {
        registerCart[itemId] = {
            id: itemId,
            label: registerItems[itemId].label,
            price: registerItems[itemId].basePrice,
            qty: 0
        };
    }
    
    registerCart[itemId].qty += amount;
    
    // Remove from cart if qty is 0
    if (registerCart[itemId].qty <= 0) {
        delete registerCart[itemId];
    }
    
    populateRegisterItems(currentFilter);
    updateCartDisplay();
}

function removeFromCart(itemId) {
    delete registerCart[itemId];
    populateRegisterItems(currentFilter);
    updateCartDisplay();
}

function updateCartDisplay() {
    const cartContainer = document.getElementById('cartItems');
    const itemCount = document.getElementById('cartItemCount');
    
    if (!cartContainer) return;
    
    let totalItems = 0;
    let html = '';
    
    if (Object.keys(registerCart).length === 0) {
        html = '<div class="empty-cart">No items added</div>';
        itemCount.textContent = '0 items';
    } else {
        for (const [itemId, item] of Object.entries(registerCart)) {
            totalItems += item.qty;
            const lineTotal = (item.price * item.qty).toFixed(2);
            html += `
                <div class="cart-item">
                    <div class="cart-item-info">
                        <div class="cart-item-name">${item.label}</div>
                        <div class="cart-item-detail">$${item.price.toFixed(2)} each</div>
                    </div>
                    <div class="cart-item-actions">
                        <input type="number" class="cart-qty-input" value="${item.qty}" 
                            onchange="updateCartItemQty('${itemId}', this.value)">
                        <div class="cart-item-price">$${lineTotal}</div>
                        <button class="cart-item-remove" onclick="removeFromCart('${itemId}')">×</button>
                    </div>
                </div>
            `;
        }
        itemCount.textContent = totalItems + ' item' + (totalItems !== 1 ? 's' : '');
    }
    
    cartContainer.innerHTML = html;
    updateTotal();
}

function updateCartItemQty(itemId, newQty) {
    const qty = parseInt(newQty) || 0;
    if (qty <= 0) {
        removeFromCart(itemId);
    } else {
        registerCart[itemId].qty = qty;
        updateCartDisplay();
    }
}

function updateTotal() {
    let subtotal = 0;
    
    for (const [itemId, item] of Object.entries(registerCart)) {
        subtotal += item.price * item.qty;
    }
    
    const taxAmount = subtotal * taxRate;
    const total = subtotal + taxAmount;
    
    const subtotalEl = document.getElementById('subtotal');
    const taxAmountEl = document.getElementById('taxAmount');
    const totalEl = document.getElementById('totalAmount');
    const processBtn = document.querySelector('.btn-process');
    
    if (subtotalEl) subtotalEl.textContent = '$' + subtotal.toFixed(2);
    if (taxAmountEl) taxAmountEl.textContent = '$' + taxAmount.toFixed(2);
    if (totalEl) totalEl.textContent = '$' + total.toFixed(2);
    if (processBtn) {
        processBtn.disabled = Object.keys(registerCart).length === 0;
    }
}

function clearCart() {
    registerCart = {};
    populateRegisterItems(currentFilter);
    updateCartDisplay();
}

function processTransaction() {
    if (Object.keys(registerCart).length === 0) {
        showTransactionStatus('No items in cart', 'error');
        return;
    }
    
    // Build transaction data
    let subtotal = 0;
    const items = [];
    
    for (const [itemId, item] of Object.entries(registerCart)) {
        subtotal += item.price * item.qty;
        items.push({
            item: itemId,
            label: item.label,
            price: item.price,
            quantity: item.qty
        });
    }
    
    const taxAmount = subtotal * taxRate;
    const total = subtotal + taxAmount;
    
    // Send to server
    fetch('https://pf-tabletuionly/processCashRegister', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            items: items,
            subtotal: subtotal,
            tax: taxAmount,
            total: total,
            taxRate: taxRate
        })
    })
    .then(r => r.json())
    .then(data => {
        if (data.success) {
            showTransactionStatus('Transaction completed: $' + total.toFixed(2), 'success');
            clearCart();
            document.querySelector('.btn-process').disabled = true;
        } else {
            showTransactionStatus(data.message || 'Transaction failed', 'error');
        }
    })
    .catch(e => {
        console.error('Transaction error:', e);
        showTransactionStatus('Transaction error', 'error');
    });
}

function showTransactionStatus(message, type) {
    const statusEl = document.getElementById('transactionStatus');
    if (!statusEl) return;
    
    statusEl.textContent = message;
    statusEl.className = 'transaction-status ' + type;
    statusEl.style.display = 'block';
    
    if (type === 'success') {
        setTimeout(() => {
            statusEl.style.display = 'none';
        }, 3000);
    }
}

// Also initialize when the app is shown via data-app attribute
document.addEventListener('click', function(e) {
    const app = e.target.closest('[data-app="cash-register"]');
    if (app) {
        setTimeout(initializeCashRegister, 100);
    }
}, true);

// Demo function - Call showDemoCashRegister() in console to test the styling
window.showDemoCashRegister = function() {
    // Set light theme for demo
    document.documentElement.setAttribute('data-theme', 'light');
    localStorage.setItem('theme', 'light');
    
    const homescreen = document.getElementById('homescreen');
    const app = document.getElementById('app-cash-register');
    
    if (app) {
        currentApp = 'cash-register';
        homescreen.style.display = 'none';
        app.style.display = 'block';
        
        // Load demo data
        registerItems = {
            mechanic_tools: { label: 'Mechanic Tools', basePrice: 500, category: 'Diagnostics & Service' },
            diagnosticstool: { label: 'Diagnostics Tool', basePrice: 1200, category: 'Diagnostics & Service' },
            carbattery: { label: 'Car Battery', basePrice: 700, category: 'Repair Parts' },
            sparkplugs: { label: 'Spark Plugs', basePrice: 120, category: 'Repair Parts' },
            engine_oil: { label: 'Engine Oil', basePrice: 100, category: 'Fluids' },
            coolant: { label: 'Coolant', basePrice: 70, category: 'Fluids' },
            bumper: { label: 'Bumper', basePrice: 400, category: 'Cosmetics' },
            exhaust: { label: 'Exhaust', basePrice: 350, category: 'Cosmetics' },
            engine1: { label: 'Engine Level 1', basePrice: 800, category: 'Performance' },
            turbo: { label: 'Turbo', basePrice: 2000, category: 'Performance' }
        };
        
        populateRegisterItems();
        updateCartDisplay();
        console.log('%cDEMO CASH REGISTER LOADED ✓\n- Light theme applied\n- Demo items loaded\n- Ready to add items to cart', 'color: #22c55e; font-weight: bold; font-size: 12px;');
    }
};

// Test unlock function
window.testUnlock = function() {
    console.log('=== Testing Unlock ===');
    unlock();
};

// ============================================================================
// GARBAGE JOB APP FUNCTIONS
// ============================================================================
let garbajeJobData = {
    level: 1,
    xp: 0,
    xpThresholds: [0, 1000, 3000, 7000, 12000, 20000],
    bagCollected: 0,
    carrying: false,
    payPerBag: 20
};

function initializeGarbageUI() {
    const startBtn = document.getElementById('garbage-start-job');
    if (startBtn) {
        startBtn.addEventListener('click', startGarbageJob);
    }

    const tabs = document.querySelectorAll('.g6-tab-inline');
    if (tabs.length) {
        tabs.forEach(tab => {
            tab.addEventListener('click', () => {
                const target = tab.getAttribute('data-garbage-tab');
                if (target) {
                    switchGarbageTab(target);
                }
            });
        });
        switchGarbageTab('work');
    }

    updateGarbageXP(garbajeJobData.xp, garbajeJobData.level);
    updateGarbageStatus(garbajeJobData.bagCollected, garbajeJobData.carrying, garbajeJobData.payPerBag);
}

function startGarbageJob() {
    console.log('Starting garbage job...');
    TriggerEvent('pf-tabletuionly:startGarbageJob', {});
}

function switchGarbageTab(tab) {
    const tabs = document.querySelectorAll('.g6-tab-inline');
    tabs.forEach(el => el.classList.remove('active'));
    document.querySelector(`.g6-tab-inline[data-garbage-tab="${tab}"]`)?.classList.add('active');

    const rightPane = document.getElementById('garbage-right-pane');
    if (!rightPane) {
        return;
    }

    if (tab === 'work') {
        rightPane.innerHTML = '<div class="g6-card" style="background:rgba(255,255,255,0.05);border:1px solid rgba(74,217,222,0.15);border-radius:16px;padding:24px;text-align:center;">Collect trash bags from dumpsters and deposit at the Trashmaster. One bag at a time.</div>';
    } else if (tab === 'group') {
        rightPane.innerHTML = '<div class="g6-card" style="background:rgba(255,255,255,0.05);border:1px solid rgba(74,217,222,0.15);border-radius:16px;padding:24px;text-align:center;">Party management coming soon.</div>';
    } else if (tab === 'upgrades') {
        rightPane.innerHTML = '<div class="g6-card" style="background:rgba(255,255,255,0.05);border:1px solid rgba(74,217,222,0.15);border-radius:16px;padding:24px;text-align:center;">Upgrades coming soon.</div>';
    }
}

function updateGarbageXP(xp, level) {
    garbajeJobData.xp = xp;
    garbajeJobData.level = level;
    
    const nextThreshold = garbajeJobData.xpThresholds[level] || garbajeJobData.xpThresholds[garbajeJobData.xpThresholds.length - 1];
    const currentThreshold = garbajeJobData.xpThresholds[level - 1] || 0;
    const progress = ((xp - currentThreshold) / (nextThreshold - currentThreshold)) * 100;

    const levelEl = document.getElementById('garbage-level');
    if (levelEl) {
        levelEl.textContent = level;
    }

    const xpBar = document.getElementById('garbage-xpbar');
    if (xpBar) {
        xpBar.style.width = Math.min(progress, 100) + '%';
    }

    const xpText = document.getElementById('garbage-xp-text');
    if (xpText) {
        xpText.textContent = `${Math.max(0, xp - currentThreshold)} / ${Math.max(1, nextThreshold - currentThreshold)} XP`;
    }
}

function updateGarbageStatus(collected, carrying, payPerBag) {
    garbajeJobData.bagCollected = collected;
    garbajeJobData.carrying = carrying;
    garbajeJobData.payPerBag = payPerBag;

    const carryingEl = document.getElementById('garbage-carrying');
    if (carryingEl) {
        carryingEl.textContent = carrying ? 'Yes' : 'No';
    }
}

// ============================================================================
// TAXI JOB APP FUNCTIONS
// ============================================================================
let taxiJobData = {
    level: 1,
    miles: 0,
    mileThresholds: [0, 50, 200, 500, 1000],
    earnings: 0,
    rating: 5.0,
    streak: 0,
    meterActive: false,
    meterAmount: 0
};

function startTaxiJob() {
    console.log('Starting taxi duty...');
    TriggerEvent('pf-tabletuionly:startTaxiDuty', {});
}

function switchTaxiTab(tab) {
    document.querySelectorAll('[id^="taxi-"][id$="-content"]').forEach(el => {
        el.style.display = 'none';
    });
    const tabEl = document.getElementById('taxi-' + tab);
    if (tabEl) tabEl.style.display = 'block';
    
    document.querySelectorAll('[data-tab^="taxi-"]').forEach(el => el.classList.remove('active'));
    document.querySelector(`[data-tab="taxi-${tab}"]`)?.classList.add('active');
}

function updateTaxiMeter(amount, active) {
    taxiJobData.meterAmount = amount;
    taxiJobData.meterActive = active;
    
    document.getElementById('taxi-meter-amount').textContent = amount.toFixed(2);
    document.getElementById('taxi-meter-status').textContent = active ? 'Active' : 'Idle';
    document.getElementById('taxi-meter-status').style.color = active ? '#10b981' : '#94a3b8';
}

function updateTaxiStats(miles, earnings, rating, streak) {
    taxiJobData.miles = miles;
    taxiJobData.earnings = earnings;
    taxiJobData.rating = rating;
    taxiJobData.streak = streak;
    
    // Update level based on miles
    for (let i = taxiJobData.mileThresholds.length - 1; i >= 0; i--) {
        if (miles >= taxiJobData.mileThresholds[i]) {
            taxiJobData.level = i + 1;
            break;
        }
    }
    
    const nextThreshold = taxiJobData.mileThresholds[taxiJobData.level] || taxiJobData.mileThresholds[taxiJobData.mileThresholds.length - 1];
    const currentMiles = miles - (taxiJobData.mileThresholds[taxiJobData.level - 1] || 0);
    const nextMiles = nextThreshold - (taxiJobData.mileThresholds[taxiJobData.level - 1] || 0);
    const progress = (currentMiles / nextMiles) * 100;
    
    document.getElementById('taxi-level').textContent = taxiJobData.level;
    document.getElementById('taxi-xp-current').textContent = miles;
    document.getElementById('taxi-xp-next').textContent = nextThreshold;
    document.getElementById('taxi-xp-fill').style.width = Math.min(progress, 100) + '%';
    document.getElementById('taxi-earnings').textContent = '$' + earnings.toFixed(2);
    document.getElementById('taxi-distance').textContent = miles.toFixed(1) + ' miles';
    document.getElementById('taxi-rating').textContent = rating.toFixed(1);
    document.getElementById('taxi-streak').textContent = streak + ' rides';
    
    const ranks = ['Novice Driver', 'Experienced Driver', 'Licensed Operator', 'Professional Driver', 'Elite Taxi Service'];
    document.getElementById('taxi-rank').textContent = ranks[taxiJobData.level - 1] || ranks[0];
}

// ============================================================================
// BUS JOB APP FUNCTIONS
// ============================================================================
let busJobData = {
    level: 1,
    routes: 0,
    routeThresholds: [0, 10, 30, 75, 150],
    passengers: 0,
    distance: 0,
    earnings: 0,
    selectedRoute: null,
    availableRoutes: [
        { id: 1, name: 'Downtown Loop', difficulty: 'Easy', pay: 150, requiredLevel: 1 },
        { id: 2, name: 'Beach Express', difficulty: 'Medium', pay: 250, requiredLevel: 1 },
        { id: 3, name: 'North County', difficulty: 'Hard', pay: 350, requiredLevel: 2 },
        { id: 4, name: 'Airport Run', difficulty: 'Expert', pay: 500, requiredLevel: 3 },
        { id: 5, name: 'Cross County Express', difficulty: 'Master', pay: 750, requiredLevel: 4 }
    ]
};

function startBusJob() {
    if (!busJobData.selectedRoute) {
        alert('Please select a route first');
        return;
    }
    console.log('Starting bus route:', busJobData.selectedRoute);
    TriggerEvent('pf-tabletuionly:startBusRoute', { route: busJobData.selectedRoute });
}

function switchBusTab(tab) {
    document.querySelectorAll('[id^="bus-"][id$="-tab"]').forEach(el => {
        el.style.display = 'none';
    });
    const tabEl = document.getElementById('bus-' + tab + '-tab');
    if (tabEl) tabEl.style.display = 'block';
    
    document.querySelectorAll('.bus-tab-btn').forEach(el => el.classList.remove('active'));
    document.querySelector(`[data-tab="${tab}"]`)?.classList.add('active');
}

function selectBusRoute(routeId) {
    const route = busJobData.availableRoutes.find(r => r.id === routeId);
    if (!route) return;
    
    // Check if route is locked
    if (busJobData.level < route.requiredLevel) {
        alert(`Route locked! Requires Level ${route.requiredLevel}`);
        return;
    }
    
    busJobData.selectedRoute = routeId;
    document.getElementById('bus-selected-route-name').textContent = route.name;
    document.getElementById('bus-route-pay').textContent = '$' + route.pay;
    document.getElementById('bus-route-stops').textContent = '8-12';
    
    // Update route selection visual
    document.querySelectorAll('.bus-route-card').forEach(el => el.classList.remove('selected'));
    const routeEl = document.querySelector(`.bus-route-card[data-route-id="${routeId}"]`);
    if (routeEl) routeEl.classList.add('selected');
    
    console.log('Selected route:', route.name);
}

function updateBusProgress(routes, passengers, distance, earnings) {
    busJobData.routes = routes;
    busJobData.passengers = passengers;
    busJobData.distance = distance;
    busJobData.earnings = earnings;
    
    // Update level based on routes
    for (let i = busJobData.routeThresholds.length - 1; i >= 0; i--) {
        if (routes >= busJobData.routeThresholds[i]) {
            busJobData.level = i + 1;
            break;
        }
    }
    
    const nextThreshold = busJobData.routeThresholds[busJobData.level] || busJobData.routeThresholds[busJobData.routeThresholds.length - 1];
    const currentRoutes = routes - (busJobData.routeThresholds[busJobData.level - 1] || 0);
    const nextRoutes = nextThreshold - (busJobData.routeThresholds[busJobData.level - 1] || 0);
    const progress = (currentRoutes / nextRoutes) * 100;
    
    document.getElementById('bus-level').textContent = busJobData.level;
    document.getElementById('bus-xp-current').textContent = routes;
    document.getElementById('bus-xp-next').textContent = nextThreshold;
    document.getElementById('bus-xp-fill').style.width = Math.min(progress, 100) + '%';
    document.getElementById('bus-routes-completed').textContent = routes;
    document.getElementById('bus-passengers-total').textContent = passengers;
    document.getElementById('bus-earnings').textContent = '$' + earnings;
    
    // Re-render routes to update locked states
    renderBusRoutes();
}

// Render Bus Routes with Level Requirements
function renderBusRoutes() {
    const container = document.getElementById('bus-routes-list');
    if (!container) return;
    
    container.innerHTML = '';
    
    busJobData.availableRoutes.forEach(route => {
        const isLocked = busJobData.level < route.requiredLevel;
        const routeEl = document.createElement('div');
        routeEl.className = 'bus-route-card' + (isLocked ? ' locked' : '');
        routeEl.setAttribute('data-route-id', route.id);
        
        if (!isLocked) {
            routeEl.onclick = () => selectBusRoute(route.id);
        }
        
        routeEl.innerHTML = `
            <div class="route-card-header">
                <span class="route-name">${route.name}</span>
                ${isLocked ? `<span class="route-level-req">Lv${route.requiredLevel}</span>` : ''}
            </div>
            <div class="route-card-details">
                <div class="route-detail">
                    <span class="route-icon"><span class="icon-chart"></span></span>
                    <span class="route-difficulty ${route.difficulty.toLowerCase()}">${route.difficulty}</span>
                </div>
                <div class="route-detail">
                    <span class="route-icon"><span class="icon-dollar"></span></span>
                    <span class="route-pay">$${route.pay}</span>
                </div>
            </div>
            ${isLocked ? '<div class="route-locked-badge"><span class="icon-lock"></span> LOCKED</div>' : ''}
        `;
        
        container.appendChild(routeEl);
    });
}

// ============================================================================
// GRUPPE6 JOB APP FUNCTIONS
// ============================================================================
let gruppe6JobData = {
    level: 1,
    xp: 0,
    xpThresholds: [0, 100, 500, 1000, 1500],
    status: 'awaiting',
    activeContract: null,
    group: null,
    pendingInvite: null,
    upgrades: [],
    contracts: [],
    searching: false
};

function initializeGruppe6UI() {
    const tabs = document.querySelectorAll('.g6-gruppe6 .g6-tab-inline');
    tabs.forEach(tab => {
        tab.addEventListener('click', () => {
            const target = tab.getAttribute('data-g6-tab');
            if (target) {
                switchGruppe6Tab(target);
            }
        });
    });

    const startSearchBtn = document.getElementById('g6-start-search');
    if (startSearchBtn) {
        startSearchBtn.addEventListener('click', startGruppe6Contract);
    }

    const startContractBtn = document.getElementById('g6-start-contract');
    if (startContractBtn) {
        startContractBtn.addEventListener('click', startGruppe6Contract);
    }

    switchGruppe6Tab('contracts');
    updateGruppe6Status(gruppe6JobData.level, gruppe6JobData.xp, gruppe6JobData.status, gruppe6JobData.activeContract);
}

function startGruppe6Contract() {
    console.log('Seeking Gruppe6 contract...');
    gruppe6JobData.searching = true;
    updateGruppe6Status(gruppe6JobData.level, gruppe6JobData.xp, 'awaiting', gruppe6JobData.activeContract);
    TriggerEvent('pf-tabletuionly:startGruppe6Search', {});
}

function switchGruppe6Tab(tab) {
    const tabs = document.querySelectorAll('.g6-gruppe6 .g6-tab-inline');
    tabs.forEach(el => el.classList.remove('active'));
    document.querySelector(`.g6-gruppe6 .g6-tab-inline[data-g6-tab="${tab}"]`)?.classList.add('active');

    const rightPane = document.getElementById('g6-right-pane');
    if (!rightPane) {
        return;
    }

    if (tab === 'contracts') {
        renderGruppe6Contracts();
    } else if (tab === 'group') {
        g6RenderGroupPanel();
    } else if (tab === 'upgrades') {
        rightPane.innerHTML = '<div class="g6-card" style="background:rgba(255,255,255,0.05);border:1px solid rgba(74,217,222,0.15);border-radius:16px;padding:24px;text-align:center;">Upgrades coming soon.</div>';
    }
}

function g6RenderGroupPanel() {
    const rightPane = document.getElementById('g6-right-pane');
    if (!rightPane) {
        return;
    }

    const group = gruppe6JobData.group;
    const invite = gruppe6JobData.pendingInvite;
    const groupId = group?.id || 'G6';
    const groupMax = group?.maxSize || 4;
    const memberCount = group?.members?.length || 0;
    const isLeader = Boolean(group?.isLeader);

    const membersHtml = group && memberCount
        ? group.members.map(member => {
            const memberId = String(member.id ?? '');
            const memberName = member.name || `Player ${memberId}`;
            const memberRole = member.role || (member.isLeader ? 'Leader' : 'Member');
            const isMemberLeader = Boolean(member.isLeader);
            const statusText = member.status ? ` · ${member.status}` : '';
            const removeBtn = (isLeader && !isMemberLeader)
                ? `<button class="g6-group-btn danger" onclick="g6RemoveMember('${memberId}')">Remove</button>`
                : '';

            return `
                <div class="g6-member-row">
                    <div class="g6-member-avatar">🛡️</div>
                    <div class="g6-member-meta">
                        <div class="g6-member-name">${memberName}${isMemberLeader ? ' ⭐' : ''}</div>
                        <div class="g6-member-role">${memberRole}${statusText}</div>
                    </div>
                    <div class="g6-member-actions">${removeBtn}</div>
                </div>
            `;
        }).join('')
        : '<div class="g6-member-empty">No members yet</div>';

    const inviteControls = group
        ? `
            <div class="g6-group-input-row">
                <input class="g6-group-input" id="g6-invite-id" type="number" min="1" placeholder="Player ID" />
                <button class="g6-group-btn" onclick="g6InviteMember()">Invite</button>
            </div>
        `
        : `
            <div class="g6-group-input-row">
                <button class="g6-group-btn" onclick="g6CreateGroup()">Create Group</button>
            </div>
        `;

    const footerActions = group
        ? (isLeader
            ? '<button class="g6-group-btn danger" onclick="g6DisbandGroup()">Disband Group</button>'
            : '<button class="g6-group-btn secondary" onclick="g6LeaveGroup()">Leave Group</button>')
        : '';

    const inviteHtml = invite
        ? `
            <div class="g6-card g6-group-card">
                <div class="g6-group-title">Incoming Invite</div>
                <div class="g6-group-subtitle">${invite.fromName || 'Gruppe6'} · Group ${invite.groupId || 'G6'}</div>
                <div class="g6-group-actions">
                    <div class="g6-group-input-row">
                        <button class="g6-group-btn" onclick="g6AcceptInvite()">Accept</button>
                        <button class="g6-group-btn secondary" onclick="g6DeclineInvite()">Decline</button>
                    </div>
                </div>
            </div>
        `
        : '';

    rightPane.innerHTML = `
        <div class="g6-group-grid">
            <div class="g6-card g6-group-card">
                <div class="g6-group-header">
                    <div>
                        <div class="g6-group-title">Security Team</div>
                        <div class="g6-group-subtitle">
                            ${group ? `Group ${groupId} · ${memberCount}/${groupMax} members` : 'You are not in a group'}
                        </div>
                    </div>
                    <div class="g6-group-badge">${group ? (isLeader ? 'Leader' : 'Member') : 'Solo'}</div>
                </div>
                <div class="g6-group-actions">
                    ${inviteControls}
                </div>
                <div class="g6-group-status" id="g6-group-status" style="display:none;"></div>
            </div>
            ${inviteHtml}
            <div class="g6-card g6-group-card">
                <div class="g6-group-title">Members</div>
                <div class="g6-member-list">${membersHtml}</div>
                <div class="g6-group-footer">${footerActions}</div>
            </div>
        </div>
    `;
}

function g6CreateGroup() {
    if (gruppe6JobData.group) {
        g6SetGroupStatus('You are already in a group.', 'error');
        return;
    }

    gruppe6JobData.group = {
        id: `G6-${String(Date.now()).slice(-4)}`,
        isLeader: true,
        maxSize: 4,
        members: [{ id: 'self', name: 'You', role: 'Leader', isLeader: true }]
    };

    g6RenderGroupPanel();
    TriggerEvent('pf-tabletuionly:gruppe6CreateGroup', {});
}

function g6InviteMember() {
    const input = document.getElementById('g6-invite-id');
    const rawValue = input ? input.value.trim() : '';
    const playerId = Number.parseInt(rawValue, 10);

    if (!gruppe6JobData.group) {
        g6SetGroupStatus('Create a group before inviting.', 'error');
        return;
    }

    if (!Number.isFinite(playerId) || playerId <= 0) {
        g6SetGroupStatus('Enter a valid player ID.', 'error');
        return;
    }

    const existing = gruppe6JobData.group.members.find(member => Number(member.id) === playerId);
    if (existing) {
        g6SetGroupStatus('Player is already in the group.', 'error');
        return;
    }

    if (gruppe6JobData.group.members.length >= gruppe6JobData.group.maxSize) {
        g6SetGroupStatus('Group is full.', 'error');
        return;
    }

    gruppe6JobData.group.members.push({
        id: playerId,
        name: `Player ${playerId}`,
        role: 'Invited',
        status: 'Pending'
    });

    if (input) input.value = '';
    g6RenderGroupPanel();
    g6SetGroupStatus(`Invite sent to player ${playerId}.`, 'success');
    TriggerEvent('pf-tabletuionly:gruppe6InvitePlayer', { playerId });
}

function g6RemoveMember(memberId) {
    if (!gruppe6JobData.group || !gruppe6JobData.group.isLeader) {
        g6SetGroupStatus('Only the leader can remove members.', 'error');
        return;
    }

    gruppe6JobData.group.members = gruppe6JobData.group.members.filter(member => String(member.id) !== String(memberId));
    g6RenderGroupPanel();
    TriggerEvent('pf-tabletuionly:gruppe6RemoveMember', { playerId: memberId });
}

function g6DisbandGroup() {
    if (!gruppe6JobData.group || !gruppe6JobData.group.isLeader) {
        g6SetGroupStatus('Only the leader can disband the group.', 'error');
        return;
    }

    gruppe6JobData.group = null;
    g6RenderGroupPanel();
    TriggerEvent('pf-tabletuionly:gruppe6DisbandGroup', {});
}

function g6LeaveGroup() {
    if (!gruppe6JobData.group) {
        return;
    }

    gruppe6JobData.group = null;
    g6RenderGroupPanel();
    TriggerEvent('pf-tabletuionly:gruppe6LeaveGroup', {});
}

function g6ShowInvite(invite) {
    gruppe6JobData.pendingInvite = invite || null;
    if (g6IsGroupTabActive()) {
        g6RenderGroupPanel();
    }
}

function g6AcceptInvite() {
    if (!gruppe6JobData.pendingInvite) {
        return;
    }

    const invite = gruppe6JobData.pendingInvite;
    gruppe6JobData.pendingInvite = null;
    g6RenderGroupPanel();
    TriggerEvent('pf-tabletuionly:gruppe6AcceptInvite', {
        groupId: invite.groupId,
        leaderId: invite.leaderId
    });
}

function g6DeclineInvite() {
    if (!gruppe6JobData.pendingInvite) {
        return;
    }

    const invite = gruppe6JobData.pendingInvite;
    gruppe6JobData.pendingInvite = null;
    g6RenderGroupPanel();
    TriggerEvent('pf-tabletuionly:gruppe6DeclineInvite', {
        groupId: invite.groupId,
        leaderId: invite.leaderId
    });
}

function g6SetGroupStatus(message, type) {
    const statusEl = document.getElementById('g6-group-status');
    if (!statusEl) {
        return;
    }

    statusEl.textContent = message;
    statusEl.className = `g6-group-status ${type}`;
    statusEl.style.display = 'block';
}

function g6ApplyGroupUpdate(group) {
    if (!group) {
        gruppe6JobData.group = null;
    } else {
        gruppe6JobData.group = {
            id: group.id || 'G6',
            isLeader: Boolean(group.isLeader),
            maxSize: group.maxSize || 4,
            members: Array.isArray(group.members) ? group.members : []
        };
    }

    if (g6IsGroupTabActive()) {
        g6RenderGroupPanel();
    }
}

function g6IsGroupTabActive() {
    const activeTab = document.querySelector('.g6-gruppe6 .g6-tab-inline.active');
    return activeTab?.getAttribute('data-g6-tab') === 'group';
}

function createParty() {
    console.log('Creating Gruppe6 party...');
    TriggerEvent('pf-tabletuionly:createGruppe6Party', {});
}

function startSearching() {
    console.log('Searching for Gruppe6 contracts...');
    TriggerEvent('pf-tabletuionly:startContractSearch', {});
}

function purchaseUpgrade(upgradeType) {
    console.log('Purchasing upgrade:', upgradeType);
    TriggerEvent('pf-tabletuionly:purchaseGruppe6Upgrade', { upgrade: upgradeType });
}

function updateGruppe6Status(level, xp, status, activeContract) {
    gruppe6JobData.level = level;
    gruppe6JobData.xp = xp;
    gruppe6JobData.status = status;
    gruppe6JobData.activeContract = activeContract;
    
    const nextThreshold = gruppe6JobData.xpThresholds[level] || gruppe6JobData.xpThresholds[gruppe6JobData.xpThresholds.length - 1];
    const currentThreshold = gruppe6JobData.xpThresholds[level - 1] || 0;
    const progress = ((xp - currentThreshold) / (nextThreshold - currentThreshold)) * 100;
    
    const levelEl = document.getElementById('g6-level');
    if (levelEl) {
        levelEl.textContent = level;
    }

    const xpBar = document.getElementById('g6-xpbar-top');
    if (xpBar) {
        xpBar.style.width = Math.min(progress, 100) + '%';
    }

    const xpText = document.getElementById('g6-xp-text');
    if (xpText) {
        xpText.textContent = `${Math.max(0, xp - currentThreshold)} / ${Math.max(1, nextThreshold - currentThreshold)} XP`;
    }

    const waitingCard = document.getElementById('g6-waiting-card');
    const contractCard = document.getElementById('g6-contract-card');
    if (status === 'active' && activeContract) {
        if (waitingCard) waitingCard.style.display = 'none';
        if (contractCard) contractCard.style.display = 'block';
        const tierBadge = document.getElementById('g6-tier-badge');
        const vehicleName = document.getElementById('g6-vehicle-name');
        const typeEl = document.getElementById('g6-contract-type');
        const bagsEl = document.getElementById('g6-bags');
        const payoutEl = document.getElementById('g6-payout');
        const maxGroupEl = document.getElementById('g6-maxgroup');
        if (tierBadge) tierBadge.textContent = `Tier ${activeContract.tier || 1}`;
        if (vehicleName) vehicleName.textContent = activeContract.vehicle || 'Speedo';
        if (typeEl) typeEl.textContent = activeContract.contractType || 'Bank Delivery';
        if (bagsEl) bagsEl.textContent = activeContract.bags || 12;
        if (payoutEl) payoutEl.textContent = `$${(activeContract.payout || 0).toLocaleString()}`;
        if (maxGroupEl) maxGroupEl.textContent = activeContract.maxGroup || 2;
        const actionBtn = document.getElementById('g6-start-contract');
        if (actionBtn) {
            actionBtn.textContent = 'End Contract Early';
            actionBtn.setAttribute('data-action', 'end');
        }
    } else {
        if (contractCard) contractCard.style.display = 'none';
        if (waitingCard) waitingCard.style.display = 'block';
        const waitingSubtitle = document.getElementById('g6-waiting-subtitle');
        if (waitingSubtitle) {
            waitingSubtitle.textContent = gruppe6JobData.searching ? 'Searching for contracts...' : 'Start searching to receive contract offers';
        }
        const actionBtn = document.getElementById('g6-start-contract');
        if (actionBtn) {
            actionBtn.textContent = 'Start Contract';
            actionBtn.setAttribute('data-action', 'start');
        }
    }
}

function renderGruppe6Contracts() {
    const rightPane = document.getElementById('g6-right-pane');
    if (!rightPane) {
        return;
    }

    const contracts = gruppe6JobData.contracts || [];
    if (!contracts.length) {
        rightPane.innerHTML = '<div class="g6-card" style="background:rgba(255,255,255,0.05);border:1px solid rgba(74,217,222,0.15);border-radius:16px;padding:24px;text-align:center;"><div style="font-size:48px;margin-bottom:16px;opacity:.3;">📋</div><div style="color:#94a3b8;font-size:16px;">No contracts available</div><div style="color:#64748b;font-size:14px;margin-top:8px;">Go to Work tab to start searching</div></div>';
        return;
    }

    const cards = contracts.slice(0, 3).map((contract, index) => {
        return `<div class="g6-contract-card-available" data-contract-id="${index}">
            <div class="g6-tier-badge">Tier ${contract.tier || 1}</div>
            <div class="g6-vehicle-name">${contract.vehicle || 'Speedo'}</div>
            <div class="g6-rank-badge"><span class="g6-wing left">🪽</span><div class="g6-rank-circle"><span class="g6-rank-star">⭐</span></div><span class="g6-wing right">🪽</span></div>
            <div class="g6-info-rows">
                <div class="g6-info-row"><span class="g6-info-label"><span class="g6-info-icon">📦</span> Type</span><span class="g6-info-value">${contract.contractType || 'Bank Delivery'}</span></div>
                <div class="g6-info-row"><span class="g6-info-label"><span class="g6-info-icon">💼</span> Bags</span><span class="g6-info-value">${contract.bags || 12}</span></div>
                <div class="g6-info-row"><span class="g6-info-label"><span class="g6-info-icon">💰</span> Payout</span><span class="g6-info-value">$${(contract.payout || 0).toLocaleString()}</span></div>
                <div class="g6-info-row"><span class="g6-info-label"><span class="g6-info-icon">👥</span> Max Group</span><span class="g6-info-value">${contract.maxGroup || 2}</span></div>
            </div>
            <button class="g6-accept-contract-btn" data-contract-id="${index}">Accept Contract</button>
        </div>`;
    }).join('');

    rightPane.innerHTML = `<div class="g6-contracts-list">
        <div class="g6-contracts-header">
            <div style="color:#e5e7eb;font-weight:700;font-size:18px;">Available Contracts</div>
            <div style="color:#94a3b8;font-size:13px;">${contracts.length} contract${contracts.length !== 1 ? 's' : ''} available</div>
        </div>
        <div class="g6-contracts-row">${cards}</div>
    </div>`;

    rightPane.querySelectorAll('.g6-accept-contract-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            const idx = Number(btn.getAttribute('data-contract-id'));
            const selected = gruppe6JobData.contracts[idx];
            if (!selected) {
                return;
            }
            gruppe6JobData.activeContract = selected;
            updateGruppe6Status(gruppe6JobData.level, gruppe6JobData.xp, 'active', selected);
            TriggerEvent('pf-tabletuionly:acceptGruppe6Contract', { contractIndex: idx });
        });
    });
}

// Demo function - Call showDemoWorkOrder() in console to test the styling
window.showDemoWorkOrder = function() {
    // First set the light theme
    document.documentElement.setAttribute('data-theme', 'light');
    localStorage.setItem('theme', 'light');
    
    const homescreen = document.getElementById('homescreen');
    const app = document.getElementById('app-work-orders');
    
    if (app) {
        currentApp = 'work-orders';
        homescreen.style.display = 'none';
        app.style.display = 'block';
        
        // Load placeholder demo data with temporary work order showing
        const demoData = JSON.parse(JSON.stringify(placeholderWorkOrderData));
        updateWorkOrdersUI(demoData);
        console.log('%cDEMO WORK ORDER LOADED ✓\n- Light gray (#f8f9fa) styling applied\n- Unicode icons enabled\n- Temporary job displayed in Active Job section', 'color: #22c55e; font-weight: bold; font-size: 12px;');
    }
};
