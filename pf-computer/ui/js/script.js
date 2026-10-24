const PC_NUI_RESOURCE = (typeof GetParentResourceName === 'function')
    ? GetParentResourceName()
    : 'pf-computer';

async function nuiRequest(event, data) {
    try {
        const response = await fetch(`https://${PC_NUI_RESOURCE}/${event}`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json; charset=UTF-8'
            },
            body: JSON.stringify(data || {})
        });
        return await response.json();
    } catch (error) {
        console.error('NUI request failed:', event, error);
        return { ok: false, error: 'nui_request_failed' };
    }
}

const DEFAULT_WALLPAPER_URL = 'assets/wallpaper.jpg';

let CURRENT_COMPUTER_STATE_SCOPE = 'default';
let CURRENT_COMPUTER_BASE_SCOPE = 'default';
let CURRENT_ACCOUNT_SCOPE = 'anon';

function rebuildStorageScope() {
    CURRENT_COMPUTER_STATE_SCOPE = `${CURRENT_COMPUTER_BASE_SCOPE}:acct:${CURRENT_ACCOUNT_SCOPE}`;
}

function setComputerStateScope(scope) {
    const nextScope = String(scope || '').trim();
    CURRENT_COMPUTER_BASE_SCOPE = nextScope || 'default';
    rebuildStorageScope();
}

function setAccountScope(accountId) {
    const nextAccount = String(accountId || '').trim().toLowerCase();
    CURRENT_ACCOUNT_SCOPE = nextAccount || 'anon';
    rebuildStorageScope();
}

function scopedStorageKey(key) {
    return `pf_computer:${CURRENT_COMPUTER_STATE_SCOPE}:${key}`;
}

function scopedStorageGet(key, fallback = null) {
    const scopedValue = localStorage.getItem(scopedStorageKey(key));
    if (scopedValue !== null) return scopedValue;
    const legacyValue = localStorage.getItem(key);
    return legacyValue !== null ? legacyValue : fallback;
}

function scopedStorageSet(key, value) {
    localStorage.setItem(scopedStorageKey(key), value);
}

function scopedStorageRemove(key) {
    localStorage.removeItem(scopedStorageKey(key));
}

function scopedSettingGet(key, fallback = null) {
    return scopedStorageGet(`setting:${key}`, fallback);
}

function scopedSettingSet(key, value) {
    scopedStorageSet(`setting:${key}`, value);
}

function clearStorageByPattern(pattern) {
    const keys = [];
    for (let i = 0; i < localStorage.length; i += 1) {
        const key = localStorage.key(i);
        if (key && pattern.test(key)) {
            keys.push(key);
        }
    }
    keys.forEach((key) => localStorage.removeItem(key));
}

function clearCurrentScopeStorage() {
    const prefix = `pf_computer:${CURRENT_COMPUTER_STATE_SCOPE}:`;
    const keys = [];
    for (let i = 0; i < localStorage.length; i += 1) {
        const key = localStorage.key(i);
        if (key && key.startsWith(prefix)) {
            keys.push(key);
        }
    }
    keys.forEach((key) => localStorage.removeItem(key));
}

function clearAllMailAccountStorage() {
    clearStorageByPattern(/(^|:)mail_accounts$|(^|:)mail_current_account$|(^|:)mail_recent_accounts$|(^|:)mail_emails_/i);
    localStorage.removeItem('mail_accounts');
    localStorage.removeItem('mail_current_account');
    localStorage.removeItem('mail_recent_accounts');
}

const WEATHER_PRESETS = {
    sunny: { label: 'Sunny', icon: 'icons8-summer-100.png', tempC: 28 },
    clear: { label: 'Clear', icon: 'icons8-summer-100.png', tempC: 24 },
    partly_cloudy: { label: 'Partly Cloudy', icon: 'icons8-partly-cloudy-day-100.png', tempC: 21 },
    cloudy: { label: 'Cloudy', icon: 'icons8-clouds-100.png', tempC: 18 },
    light_rain: { label: 'Light Rain', icon: 'icons8-light-rain-100.png', tempC: 16 },
    heavy_rain: { label: 'Heavy Rain', icon: 'icons8-heavy-rain-100.png', tempC: 12 },
    storm: { label: 'Storm', icon: 'icons8-storm-100.png', tempC: 10 },
    snow: { label: 'Snow', icon: 'icons8-snow-100.png', tempC: -2 }
};

function normalizeClockParts(hourValue, minuteValue) {
    const h = Number(hourValue);
    const m = Number(minuteValue);
    if (!Number.isInteger(h) || !Number.isInteger(m)) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return { hours: h, minutes: m };
}

function normalizeWeatherKey(rawValue) {
    const value = String(rawValue || '').trim().toLowerCase().replace(/[\s-]+/g, '_');
    if (!value) return 'partly_cloudy';

    if (value.includes('snow')) return 'snow';
    if (value.includes('storm') || value.includes('thunder')) return 'storm';
    if (value.includes('heavy_rain') || value.includes('pour') || value.includes('rainy')) return 'heavy_rain';
    if (value.includes('rain') || value.includes('drizzle')) return 'light_rain';
    if (value.includes('partly') || value.includes('few_cloud')) return 'partly_cloudy';
    if (value.includes('cloud')) return 'cloudy';
    if (value.includes('sun') || value.includes('clear')) return value.includes('sun') ? 'sunny' : 'clear';

    return WEATHER_PRESETS[value] ? value : 'partly_cloudy';
}


function computeInitials(fullName) {
    const parts = String(fullName || '')
        .trim()
        .split(/\s+/)
        .filter(Boolean)
        .slice(0, 2);

    if (!parts.length) return 'PC';
    return parts.map((part) => part.charAt(0).toUpperCase()).join('');
}

function setText(selector, value) {
    if (!value) return;
    document.querySelectorAll(selector).forEach((element) => {
        element.textContent = value;
    });
}

async function hydratePlayerProfile() {
    try {
        const response = await nuiRequest('pc:getPlayerData', {});
        const player = response && response.ok ? response.data || {} : {};
        setAccountScope(player.citizenid || player.identifier || player.name || 'anon');
        const playerName = String(player.name || 'Player').trim() || 'Player';
        const initials = computeInitials(playerName);
        const subtitle = player.jobLabel ? `${player.jobLabel}${player.gradeLabel ? ` • ${player.gradeLabel}` : ''}` : 'Terminal Administrator';
        const firstName = playerName.split(/\s+/)[0] || playerName;

        setText('[data-player-name]', playerName);
        setText('[data-player-subtitle]', subtitle);
        setText('[data-player-avatar]', initials);
        setText('[data-device-name]', firstName);

        document.documentElement.style.setProperty('--taskbar-height', `${document.querySelector('.taskbar')?.offsetHeight || 48}px`);
        return player;
    } catch (error) {
        console.error('Failed to hydrate player profile:', error);
        return null;
    }
}

function updateWindowScaleClasses(windowElement) {
    if (!windowElement) return;
    const width = windowElement.offsetWidth || 0;
    const height = windowElement.offsetHeight || 0;
    windowElement.classList.toggle('size-compact', width < 900 || height < 620);
    windowElement.classList.toggle('size-small', width < 760 || height < 520);
    windowElement.classList.toggle('size-tiny', width < 620 || height < 430);
}

function syncChromeMetrics() {
    const taskbarHeight = document.querySelector('.taskbar')?.offsetHeight || 48;
    document.documentElement.style.setProperty('--taskbar-height', `${taskbarHeight}px`);
    document.querySelectorAll('.window').forEach(updateWindowScaleClasses);
}

function uiNotify(message, type = 'info') {
    const notificationsEnabled = scopedSettingGet('notifications', localStorage.getItem('notifications') !== 'false' ? 'true' : 'false') !== 'false';
    const focusAssist = scopedSettingGet('focusAssist', localStorage.getItem('focusAssist') || 'priority');
    if (!notificationsEnabled) return;
    if (focusAssist === 'alarms' && type !== 'error') return;

    const notification = document.createElement('div');
    notification.className = `notification ${type}`;
    notification.textContent = message;
    if (scopedSettingGet('showPreviews', localStorage.getItem('showPreviews') === 'false' ? 'false' : 'true') === 'false') {
        notification.textContent = type === 'error' ? 'Error' : 'Notification';
    }
    document.body.appendChild(notification);
    setTimeout(() => notification.remove(), 2200);
}

function uiConfirm(message, options = {}) {
    const title = options.title || 'Confirm';
    const confirmLabel = options.confirmLabel || 'Confirm';
    const cancelLabel = options.cancelLabel || 'Cancel';

    return new Promise((resolve) => {
        const overlay = document.createElement('div');
        overlay.className = 'modal-overlay';
        overlay.innerHTML = `
            <div class="modal-content" style="max-width:460px;">
                <div class="modal-header"><h2>${title}</h2></div>
                <div class="modal-body"><p>${String(message || '').replace(/</g, '&lt;').replace(/>/g, '&gt;')}</p></div>
                <div class="modal-footer">
                    <button class="btn-secondary" id="ui-confirm-cancel">${cancelLabel}</button>
                    <button class="btn-primary" id="ui-confirm-ok">${confirmLabel}</button>
                </div>
            </div>
        `;

        const finish = (value) => {
            overlay.remove();
            resolve(!!value);
        };

        overlay.querySelector('#ui-confirm-cancel')?.addEventListener('click', () => finish(false));
        overlay.querySelector('#ui-confirm-ok')?.addEventListener('click', () => finish(true));
        overlay.addEventListener('click', (event) => {
            if (event.target === overlay) finish(false);
        });
        document.body.appendChild(overlay);
    });
}

function uiPrompt(message, defaultValue = '', options = {}) {
    const title = options.title || 'Input Required';
    const submitLabel = options.submitLabel || 'Submit';
    const cancelLabel = options.cancelLabel || 'Cancel';
    const placeholder = options.placeholder || '';

    return new Promise((resolve) => {
        const overlay = document.createElement('div');
        overlay.className = 'modal-overlay';
        overlay.innerHTML = `
            <div class="modal-content" style="max-width:520px;">
                <div class="modal-header"><h2>${title}</h2></div>
                <div class="modal-body">
                    <p>${String(message || '').replace(/</g, '&lt;').replace(/>/g, '&gt;')}</p>
                    <input id="ui-prompt-input" class="form-input" type="text" value="${String(defaultValue || '').replace(/"/g, '&quot;')}" placeholder="${String(placeholder || '').replace(/"/g, '&quot;')}">
                </div>
                <div class="modal-footer">
                    <button class="btn-secondary" id="ui-prompt-cancel">${cancelLabel}</button>
                    <button class="btn-primary" id="ui-prompt-submit">${submitLabel}</button>
                </div>
            </div>
        `;

        const finish = (value) => {
            overlay.remove();
            resolve(value);
        };

        const input = overlay.querySelector('#ui-prompt-input');
        overlay.querySelector('#ui-prompt-cancel')?.addEventListener('click', () => finish(null));
        overlay.querySelector('#ui-prompt-submit')?.addEventListener('click', () => finish(input ? input.value : null));
        input?.addEventListener('keydown', (event) => {
            if (event.key === 'Enter') finish(input.value);
            if (event.key === 'Escape') finish(null);
        });
        overlay.addEventListener('click', (event) => {
            if (event.target === overlay) finish(null);
        });

        document.body.appendChild(overlay);
        input?.focus();
        input?.select();
    });
}

// Hard-disable native browser dialogs in NUI to avoid blocking JS windows.
window.alert = (message) => {
    uiNotify(String(message || 'Notification'), 'info');
};
window.confirm = (message) => {
    uiNotify(String(message || 'Confirmation required'), 'warning');
    return false;
};
window.prompt = (_message, _defaultValue) => null;

const APP_ICON_FILES = {
    start: 'icons8-windows-11-100.png',
    cityhall: 'icons8-organization-100.png',
    browser: 'icons8-microsoft-edge-100.png',
    mail: 'icons8-gmail-100.png',
    calendar: 'icons8-calendar-100.png',
    maps: 'icons8-google-maps-100.png',
    bills: 'icons8-scales-100.png',
    business: 'icons8-company-100.png',
    supplies: 'icons8-shopping-cart-100-2.png',
    trucking: 'icons8-deliver-food-100.png',
    job: 'icons8-job-100.png',
    darkweb: 'icons8-console-100.png',
    terminal: 'icons8-console-100.png',
    calculator: 'icons8-calculator-100.png',
    documents: 'icons8-file-explorer-100.png',
    settings: 'icons8-settings-100.png',
    store: 'icons8-app-store-100.png',
    games: 'icons8-app-store-100.png',
    minesweeper: 'icons8-app-store-100.png',
    tetris: 'icons8-app-store-100.png',
    snake: 'icons8-app-store-100.png',
    pong: 'icons8-app-store-100.png',
    flappy: 'icons8-app-store-100.png',
    search: 'icons8-search-100.png',
    taskview: 'icons8-dashboard-layout-100.png',
    chat: 'icons8-ai-100.png',
    music: 'icons8-image-100.png',
    default: 'icons8-windows-11-100.png'
};

const MONO_ICON_FILES = new Set([
    'icons8-search-100.png',
    'icons8-chevron-100.png',
    'icons8-wi-fi-100.png',
    'icons8-filter-100.png',
    'icons8-logout-100.png',
    'icons8-shutdown-100.png',
    'icons8-copy-100.png',
    'icons8-edit-100.png',
    'icons8-share-100.png',
    'icons8-trash-can-100.png',
    'icons8-shopping-cart-100.png',
    'icons8-settings-100-2.png'
]);

const APP_ICON_KEYS = {
    cityhall: 'cityhall',
    'city-hall': 'cityhall',
    browser: 'browser',
    mail: 'mail',
    calendar: 'calendar',
    maps: 'maps',
    bills: 'bills',
    'business-manager': 'business',
    'order-supplies': 'supplies',
    trucking: 'trucking',
    'pf-trucking': 'trucking',
    'job-board': 'job',
    terminal: 'terminal',
    'dark-web': 'terminal',
    calculator: 'calculator',
    documents: 'documents',
    settings: 'settings',
    store: 'store',
    games: 'games',
    minesweeper: 'minesweeper',
    tetris: 'tetris',
    snake: 'snake',
    pong: 'pong',
    flappy: 'flappy'
};

const APP_DISPLAY_NAMES = {
    cityhall: 'City Hall',
    'city-hall': 'City Hall',
    browser: 'Browser',
    mail: 'Mail',
    calendar: 'Calendar',
    maps: 'Maps',
    bills: 'Bills',
    'business-manager': 'Business Manager',
    'order-supplies': 'Order Supplies',
    trucking: 'Trucking',
    'pf-trucking': 'Trucking',
    'job-board': 'Job Board',
    terminal: 'Terminal',
    'dark-web': 'Terminal',
    calculator: 'Calculator',
    documents: 'Documents',
    settings: 'Settings',
    store: 'Store',
    games: 'Games',
    minesweeper: 'Minesweeper',
    tetris: 'Tetris',
    snake: 'Snake',
    pong: 'Pong',
    flappy: 'Flappy Bird'
};

function normalizeAppName(appNameOrKey) {
    return String(appNameOrKey || '')
        .trim()
        .toLowerCase()
        .replace(/[_\s]+/g, '-')
        .replace(/-+/g, '-');
}

function resolveAppName(appNameOrKey) {
    const normalized = normalizeAppName(appNameOrKey);
    if (!normalized) return '';

    if (APP_ICON_FILES[normalized] || APP_ICON_KEYS[normalized]) {
        return normalized;
    }

    if (normalized.includes('truck') || normalized.includes('deliver') || normalized.includes('delivery')) {
        return 'trucking';
    }

    if (normalized.includes('dark') && normalized.includes('web')) {
        return 'terminal';
    }

    if (normalized.includes('business') && normalized.includes('manager')) {
        return 'business-manager';
    }

    if (normalized.includes('job') && normalized.includes('board')) {
        return 'job-board';
    }

    if (normalized.includes('order') && normalized.includes('supplies')) {
        return 'order-supplies';
    }

    return normalized;
}

function normalizeDesktopItem(item) {
    if (!item || typeof item !== 'object') return item;

    const normalizedItem = { ...item };
    const resolvedApp = resolveAppName(normalizedItem.app || normalizedItem.id);

    if (resolvedApp) {
        normalizedItem.app = resolvedApp;
        if (!normalizedItem.type) {
            normalizedItem.type = 'app';
        }
    }

    return normalizedItem;
}

function getIconKey(appNameOrKey) {
    const resolvedApp = resolveAppName(appNameOrKey);
    if (!resolvedApp) return 'default';
    if (APP_ICON_FILES[resolvedApp]) return resolvedApp;
    return APP_ICON_KEYS[resolvedApp] || 'default';
}

function getAppDisplayName(appNameOrKey) {
    const resolvedApp = resolveAppName(appNameOrKey);
    if (!resolvedApp) return 'App';
    if (APP_DISPLAY_NAMES[resolvedApp]) return APP_DISPLAY_NAMES[resolvedApp];

    return String(resolvedApp)
        .split('-')
        .filter(Boolean)
        .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
        .join(' ');
}

function renderAppIcon(appNameOrKey, context = 'taskbar', altText = 'app') {
    const iconKey = getIconKey(appNameOrKey);
    const fileName = APP_ICON_FILES[iconKey] || APP_ICON_FILES.default;
    const safeAlt = String(altText || 'app').replace(/"/g, '&quot;');
    const sizeClass = fileName.includes('-144') ? 'app-icon-image-hires' : 'app-icon-image-standard';
    const monoClass = MONO_ICON_FILES.has(fileName) ? ' app-icon-image-mono' : '';

    return `
        <span class="app-icon-badge app-icon-${context} icon-theme-${iconKey}">
            <img class="app-icon-image ${sizeClass}${monoClass}" src="assets/icons/${fileName}" alt="${safeAlt}" draggable="false">
        </span>
    `.trim();
}

// WindowManager - Manages all app windows
class WindowManager {
    constructor() {
        this.windows = new Map();
        this.activeWindow = null;
        this.zIndex = 100;
        this.isRestoringWindowSession = false;
        this.init();
    }

    init() {
        // Initialize all windows first
        const windowElements = document.querySelectorAll('.window');
        console.log('Found windows:', windowElements.length);
        windowElements.forEach(win => {
            this.initWindow(win);
        });

        // Unify icons everywhere before interaction starts.
        this.applyGlobalAppIcons();

        // Initialize desktop icons after windows are ready
        const iconElements = document.querySelectorAll('.icon');
        console.log('Found desktop icons:', iconElements.length);
        iconElements.forEach(icon => {
            console.log('Setting up icon:', icon.dataset.app);

            icon.addEventListener('click', (e) => {
                e.preventDefault();
                e.stopPropagation();
                document.querySelectorAll('.icon').forEach(i => i.classList.remove('selected'));
                icon.classList.add('selected');
            });

            icon.addEventListener('dblclick', (e) => {
                e.preventDefault();
                e.stopPropagation();
                const appName = resolveAppName(icon.dataset.app);
                console.log('Opening app from icon:', appName);
                this.openWindow(appName);
            });
        });

        // Delegated selection for dynamically inserted icons
        document.addEventListener('click', (e) => {
            const icon = e.target.closest('.icon');
            if (!icon) return;

            e.preventDefault();
            e.stopPropagation();
            document.querySelectorAll('.icon').forEach(i => i.classList.remove('selected'));
            icon.classList.add('selected');
        });

        console.log('Windows initialized:', Array.from(this.windows.keys()));

        // Update time
        this.updateDateTime();
        setInterval(() => this.updateDateTime(), 1000);
    }

    applyGlobalAppIcons() {
        const startIconShell = document.querySelector('#start-button .taskbar-icon');
        if (startIconShell) {
            startIconShell.innerHTML = renderAppIcon('start', 'taskbar', 'Start');
        }

        document.querySelectorAll('.icon[data-app]').forEach((iconEl) => {
            const appName = iconEl.dataset.app;
            const label = iconEl.querySelector('.icon-label')?.textContent || appName;
            const iconShell = iconEl.querySelector('.icon-image');
            if (!iconShell) return;
            iconShell.innerHTML = renderAppIcon(appName, 'desktop', label);
        });

        document.querySelectorAll('.window[data-app]').forEach((windowEl) => {
            const appName = windowEl.dataset.app;
            const label = windowEl.querySelector('.window-title span')?.textContent || appName;
            const iconShell = windowEl.querySelector('.window-icon');
            if (!iconShell) return;
            iconShell.innerHTML = renderAppIcon(appName, 'window', label);
        });

        document.querySelectorAll('.taskbar-pin-launch').forEach((button) => {
            const appName = button.dataset.app;
            const label = button.getAttribute('title') || appName;
            const iconShell = button.querySelector('.taskbar-icon');
            if (!iconShell) return;
            iconShell.innerHTML = renderAppIcon(appName, 'taskbar', label);
        });

        const staticTaskbarIcons = [
            ['#taskbar-search-button .taskbar-icon', 'search', 'Search'],
            ['.taskbar-pin-static[title="Task View"] .taskbar-icon', 'taskview', 'Task View'],
            ['.taskbar-pin-static[title="Chat"] .taskbar-icon', 'chat', 'Chat'],
            ['.taskbar-pin-static[title="Music"] .taskbar-icon', 'music', 'Music']
        ];

        staticTaskbarIcons.forEach(([selector, iconKey, label]) => {
            const iconShell = document.querySelector(selector);
            if (!iconShell) return;
            iconShell.innerHTML = renderAppIcon(iconKey, 'taskbar', label);
        });
    }

    initWindow(windowElement) {
        const appName = windowElement.dataset.app;
        
        // Close button
        const closeBtn = windowElement.querySelector('.close');
        if (closeBtn) closeBtn.addEventListener('click', () => this.closeWindow(appName));

        // Minimize button
        const minimizeBtn = windowElement.querySelector('.minimize');
        if (minimizeBtn) minimizeBtn.addEventListener('click', () => this.minimizeWindow(appName));

        // Maximize button
        const maximizeBtn = windowElement.querySelector('.maximize');
        if (maximizeBtn) maximizeBtn.addEventListener('click', () => this.toggleMaximize(appName));

        // Make window draggable
        this.makeDraggable(windowElement);

        // Make window resizable
        this.makeResizable(windowElement);

        // Make window active on click
        windowElement.addEventListener('mousedown', () => {
            this.setActiveWindow(appName);
        });

        if (typeof ResizeObserver !== 'undefined') {
            let scaleUpdateRaf = null;
            const resizeObserver = new ResizeObserver(() => {
                if (scaleUpdateRaf) {
                    cancelAnimationFrame(scaleUpdateRaf);
                }
                scaleUpdateRaf = requestAnimationFrame(() => {
                    updateWindowScaleClasses(windowElement);
                    scaleUpdateRaf = null;
                });
            });
            resizeObserver.observe(windowElement);
        }
        updateWindowScaleClasses(windowElement);

        this.windows.set(appName, {
            element: windowElement,
            isMaximized: false,
            isTogglingMaximize: false,
            previousPosition: { top: 0, left: 0, width: 0, height: 0 }
        });
    }

    openWindow(appName, options = {}) {
        appName = resolveAppName(appName);
        console.log('openWindow called for:', appName);
        console.log('Available windows:', Array.from(this.windows.keys()));
        
        let requestedGame = null;

        const windowData = this.windows.get(appName);
        if (!windowData) {
            console.error('Window data not found for:', appName);
            return;
        }

        console.log('Window data found:', windowData);
        const windowElement = windowData.element;
        
        // If already open, just bring to front
        if (windowElement.style.display !== 'none' && !windowElement.classList.contains('minimized')) {
            console.log('Window already open, bringing to front');
            this.setActiveWindow(appName);
            return;
        }

        console.log('Opening window...');
        windowElement.style.display = 'flex';
        windowElement.classList.remove('minimized');

        // Center window if first time opening
        if (!windowData.previousPosition.width) {
            const taskbarHeight = document.querySelector('.taskbar')?.offsetHeight || 48;
            const availableWidth = window.innerWidth - 48;
            const availableHeight = window.innerHeight - taskbarHeight - 32;
            const defaultWidth = Math.round(Math.min(Math.max(window.innerWidth * 0.78, 760), 1280));
            const defaultHeight = Math.round(Math.min(Math.max((window.innerHeight - taskbarHeight) * 0.8, 520), 860));
            const maxWidth = Math.max(520, availableWidth);
            const maxHeight = Math.max(360, availableHeight);

            const appliedWidth = Math.max(520, Math.min(defaultWidth, maxWidth));
            const appliedHeight = Math.max(360, Math.min(defaultHeight, maxHeight));

            windowElement.style.width = `${appliedWidth}px`;
            windowElement.style.height = `${appliedHeight}px`;

            windowElement.style.left = `${Math.max(12, (window.innerWidth - appliedWidth) / 2)}px`;
            windowElement.style.top = `${Math.max(12, (window.innerHeight - taskbarHeight - appliedHeight) / 2)}px`;
            updateWindowScaleClasses(windowElement);
            console.log('Centered window at:', windowElement.style.left, windowElement.style.top);
        }

        this.setActiveWindow(appName);
        if (appName === 'browser' && window.browserManager && typeof window.browserManager.onOpen === 'function') {
            window.browserManager.onOpen();
        }
        this.recordRecentOpen(appName);
        this.updateTaskbar();
        if (!options.suppressSessionSave) {
            this.persistWindowSession();
        }
        console.log('Window opened successfully');
    }

    recordRecentOpen(appName) {
        if (!appName) return;
        let recent = [];
        try {
            recent = JSON.parse(scopedStorageGet('recentApps', '[]') || '[]');
        } catch {
            recent = [];
        }
        recent = [appName, ...recent.filter((name) => name !== appName)].slice(0, 12);
        scopedStorageSet('recentApps', JSON.stringify(recent));
    }

    closeWindow(appName, options = {}) {
        const windowData = this.windows.get(appName);
        if (!windowData) return;

        windowData.element.style.display = 'none';
        windowData.element.classList.remove('active', 'minimized', 'maximized');
        
        if (this.activeWindow === appName) {
            this.activeWindow = null;
        }

        this.updateTaskbar();
        if (!options.suppressSessionSave) {
            this.persistWindowSession();
        }
    }

    minimizeWindow(appName, options = {}) {
        const windowData = this.windows.get(appName);
        if (!windowData) return;

        windowData.element.classList.add('minimized');
        
        if (this.activeWindow === appName) {
            this.activeWindow = null;
        }

        this.updateTaskbar();
        if (!options.suppressSessionSave) {
            this.persistWindowSession();
        }
    }

    toggleMaximize(appName) {
        const windowData = this.windows.get(appName);
        if (!windowData) return;

        const windowElement = windowData.element;
        if (windowData.isTogglingMaximize) return;

        windowData.isTogglingMaximize = true;
        windowElement.classList.add('window-maximize-transition-off');

        if (windowData.isMaximized) {
            // Restore
            windowElement.classList.remove('maximized');
            windowElement.style.top = windowData.previousPosition.top + 'px';
            windowElement.style.left = windowData.previousPosition.left + 'px';
            windowElement.style.width = windowData.previousPosition.width + 'px';
            windowElement.style.height = windowData.previousPosition.height + 'px';
            windowData.isMaximized = false;
            updateWindowScaleClasses(windowElement);
        } else {
            // Maximize
            const rect = windowElement.getBoundingClientRect();
            windowData.previousPosition = {
                top: parseInt(windowElement.style.top) || rect.top,
                left: parseInt(windowElement.style.left) || rect.left,
                width: rect.width,
                height: rect.height
            };
            windowElement.classList.add('maximized');
            windowData.isMaximized = true;
            updateWindowScaleClasses(windowElement);
        }

        requestAnimationFrame(() => {
            windowElement.classList.remove('window-maximize-transition-off');
            windowData.isTogglingMaximize = false;
        });
    }

    setActiveWindow(appName, options = {}) {
        // Remove active from all windows
        this.windows.forEach((data, name) => {
            data.element.classList.remove('active');
        });

        // Set the active window
        const windowData = this.windows.get(appName);
        if (windowData) {
            windowData.element.classList.add('active');
            windowData.element.style.zIndex = ++this.zIndex;
            this.activeWindow = appName;
        }

        if (!options.suppressSessionSave) {
            this.persistWindowSession();
        }
    }

    getWindowSessionSnapshot() {
        const openWindows = [];

        this.windows.forEach((windowData, appName) => {
            if (windowData.element.style.display === 'none') return;
            openWindows.push({
                app: appName,
                minimized: windowData.element.classList.contains('minimized')
            });
        });

        return {
            activeWindow: this.activeWindow,
            openWindows
        };
    }

    persistWindowSession() {
        if (this.isRestoringWindowSession) return;
        try {
            scopedStorageSet('gov_open_windows', JSON.stringify(this.getWindowSessionSnapshot()));
        } catch (error) {
            console.warn('Failed to persist open windows:', error);
        }
    }

    clearWindowSessionVisualState() {
        this.windows.forEach((windowData) => {
            windowData.element.style.display = 'none';
            windowData.element.classList.remove('active', 'minimized');
        });
        this.activeWindow = null;
        this.updateTaskbar();
    }

    restoreWindowSession() {
        this.isRestoringWindowSession = true;
        this.clearWindowSessionVisualState();

        let payload = null;
        try {
            const raw = scopedStorageGet('gov_open_windows');
            payload = raw ? JSON.parse(raw) : null;
        } catch (error) {
            console.warn('Failed to parse open windows session:', error);
        }

        const openWindows = Array.isArray(payload?.openWindows) ? payload.openWindows : [];
        openWindows.forEach((entry) => {
            const appName = resolveAppName(entry?.app);
            if (!appName || !this.windows.has(appName)) return;
            this.openWindow(appName, { suppressSessionSave: true });
            if (entry?.minimized) {
                this.minimizeWindow(appName, { suppressSessionSave: true });
            }
        });

        const targetActive = resolveAppName(payload?.activeWindow || '');
        if (targetActive && this.windows.has(targetActive)) {
            const windowData = this.windows.get(targetActive);
            if (windowData && windowData.element.style.display !== 'none' && !windowData.element.classList.contains('minimized')) {
                this.setActiveWindow(targetActive, { suppressSessionSave: true });
            }
        }

        this.isRestoringWindowSession = false;
        this.updateTaskbar();
    }

    makeDraggable(windowElement) {
        const header = windowElement.querySelector('.window-header');
        if (!header) return;

        let isDragging = false;
        let currentX;
        let currentY;
        let initialX;
        let initialY;

        header.addEventListener('mousedown', (e) => {
            if (e.target.closest('.window-btn')) return;
            if (windowElement.classList.contains('maximized')) return;

            isDragging = true;
            initialX = e.clientX - parseInt(windowElement.style.left || 0);
            initialY = e.clientY - parseInt(windowElement.style.top || 0);

            document.addEventListener('mousemove', drag);
            document.addEventListener('mouseup', stopDrag);
        });

        const drag = (e) => {
            if (!isDragging) return;

            e.preventDefault();
            currentX = e.clientX - initialX;
            currentY = e.clientY - initialY;

            windowElement.style.left = currentX + 'px';
            windowElement.style.top = Math.max(0, currentY) + 'px';
        };

        const stopDrag = () => {
            isDragging = false;
            document.removeEventListener('mousemove', drag);
            document.removeEventListener('mouseup', stopDrag);
        };
    }

    makeResizable(windowElement) {
        const resizeHandles = ['n', 'e', 's', 'w', 'ne', 'se', 'sw', 'nw'];
        
        resizeHandles.forEach(direction => {
            const handle = document.createElement('div');
            handle.className = `resize-handle resize-${direction}`;
            windowElement.appendChild(handle);

            let isResizing = false;
            let originalWidth;
            let originalHeight;
            let originalX;
            let originalY;
            let originalMouseX;
            let originalMouseY;

            handle.addEventListener('mousedown', (e) => {
                if (windowElement.classList.contains('maximized')) return;
                
                e.preventDefault();
                e.stopPropagation();
                isResizing = true;

                originalWidth = windowElement.offsetWidth;
                originalHeight = windowElement.offsetHeight;
                originalX = windowElement.offsetLeft;
                originalY = windowElement.offsetTop;
                originalMouseX = e.clientX;
                originalMouseY = e.clientY;

                document.addEventListener('mousemove', resize);
                document.addEventListener('mouseup', stopResize);
            });

            const resize = (e) => {
                if (!isResizing) return;

                const deltaX = e.clientX - originalMouseX;
                const deltaY = e.clientY - originalMouseY;

                let newWidth = originalWidth;
                let newHeight = originalHeight;
                let newX = originalX;
                let newY = originalY;

                if (direction.includes('e')) {
                    newWidth = originalWidth + deltaX;
                }
                if (direction.includes('w')) {
                    newWidth = originalWidth - deltaX;
                    newX = originalX + deltaX;
                }
                if (direction.includes('s')) {
                    newHeight = originalHeight + deltaY;
                }
                if (direction.includes('n')) {
                    newHeight = originalHeight - deltaY;
                    newY = originalY + deltaY;
                }

                newWidth = Math.max(400, newWidth);
                newHeight = Math.max(300, newHeight);

                windowElement.style.width = newWidth + 'px';
                windowElement.style.height = newHeight + 'px';
                windowElement.style.left = newX + 'px';
                windowElement.style.top = newY + 'px';
            };

            const stopResize = () => {
                isResizing = false;
                document.removeEventListener('mousemove', resize);
                document.removeEventListener('mouseup', stopResize);
            };
        });
    }

    updateTaskbar() {
        const taskbarApps = document.querySelector('.taskbar-apps');
        if (!taskbarApps) return;

        const pinnedApps = new Set(['documents', 'browser', 'mail', 'settings']);

        document.querySelectorAll('.taskbar-pin-launch').forEach((button) => {
            const appName = button.dataset.app;
            const windowData = this.windows.get(appName);
            const isOpen = !!windowData && windowData.element.style.display !== 'none';
            const isMinimized = isOpen && !!windowData && windowData.element.classList.contains('minimized');
            const isActive = isOpen && this.activeWindow === appName && !isMinimized;

            button.classList.toggle('open', isOpen);
            button.classList.toggle('active', isActive);
            button.classList.toggle('minimized', isMinimized);
        });

        taskbarApps.innerHTML = '';

        this.windows.forEach((windowData, appName) => {
            if (windowData.element.style.display === 'none') return;
            if (pinnedApps.has(appName)) return;

            const taskbarApp = document.createElement('button');
            taskbarApp.type = 'button';
            taskbarApp.className = 'taskbar-app';

            const isMinimized = windowData.element.classList.contains('minimized');
            const isActive = this.activeWindow === appName && !isMinimized;
            taskbarApp.classList.add('open');
            if (isMinimized) {
                taskbarApp.classList.add('minimized');
            }
            if (isActive) {
                taskbarApp.classList.add('active');
            }

            const title = windowData.element.querySelector('.window-title span');
            const label = title ? title.textContent : appName;
            const iconMarkup = renderAppIcon(appName, 'taskbar', label);
            taskbarApp.innerHTML = `<span class="taskbar-icon">${iconMarkup}</span>`;
            taskbarApp.title = label;
            taskbarApp.setAttribute('aria-label', label);

            taskbarApp.addEventListener('click', () => {
                this.handleTaskbarSelection(appName);
            });

            taskbarApps.appendChild(taskbarApp);
        });
    }

    handleTaskbarSelection(appName) {
        const windowData = this.windows.get(appName);
        if (!windowData) return;

        if (windowData.element.style.display === 'none') {
            this.openWindow(appName);
            return;
        }

        if (windowData.element.classList.contains('minimized')) {
            windowData.element.classList.remove('minimized');
            this.setActiveWindow(appName);
        } else if (this.activeWindow === appName) {
            this.minimizeWindow(appName);
        } else {
            this.setActiveWindow(appName);
        }

        this.persistWindowSession();
    }

    updateDateTime() {
        const now = new Date();
        const timeElement = document.querySelector('.time');
        const dateElement = document.querySelector('.date');

        if (!timeElement || !dateElement) return;

        // Get time format preference
        const timeFormat = scopedSettingGet('timeFormat', localStorage.getItem('timeFormat') || '12-hour');
        const clockSource = String(scopedSettingGet('clockSource', localStorage.getItem('clockSource') || 'real')).toLowerCase();
        const gameClock = normalizeClockParts(scopedStorageGet('ingameHour', localStorage.getItem('ingameHour')), scopedStorageGet('ingameMinute', localStorage.getItem('ingameMinute')));
        
        // Format time
        let hours = now.getHours();
        let minutesValue = now.getMinutes();

        if (clockSource === 'ingame' && gameClock) {
            hours = gameClock.hours;
            minutesValue = gameClock.minutes;
        }

        const minutes = String(minutesValue).padStart(2, '0');
        
        if (timeFormat === '12-hour') {
            const ampm = hours >= 12 ? 'PM' : 'AM';
            hours = hours % 12 || 12;
            timeElement.textContent = `${hours}:${minutes} ${ampm}`;
        } else {
            timeElement.textContent = `${hours.toString().padStart(2, '0')}:${minutes}`;
        }

        // Format date
        const month = now.getMonth() + 1;
        const day = now.getDate();
        const year = now.getFullYear();

        dateElement.textContent = `${month}/${day}/${year}`;
        this.updateWeatherWidget();
    }

    updateWeatherWidget() {
        const weatherIcon = document.querySelector('[data-weather-icon]');
        const weatherTemp = document.querySelector('[data-weather-temp]');
        const weatherText = document.querySelector('[data-weather-text]');
        if (!weatherIcon || !weatherTemp || !weatherText) return;

        const weatherKey = normalizeWeatherKey(scopedStorageGet('currentWeather', localStorage.getItem('currentWeather') || 'partly_cloudy'));
        const weatherData = WEATHER_PRESETS[weatherKey] || WEATHER_PRESETS.partly_cloudy;

        const preferredUnit = String(scopedSettingGet('temperatureUnit', localStorage.getItem('temperatureUnit') || 'celsius')).toLowerCase();
        const useFahrenheit = preferredUnit === 'fahrenheit';
        const temp = useFahrenheit ? Math.round((weatherData.tempC * 9) / 5 + 32) : weatherData.tempC;
        const unitSymbol = useFahrenheit ? 'F' : 'C';

        weatherIcon.src = `assets/icons/${weatherData.icon}`;
        weatherIcon.alt = weatherData.label;
        weatherText.textContent = weatherData.label;
        weatherTemp.textContent = `${temp}${String.fromCharCode(176)}${unitSymbol}`;
        scopedStorageSet('weatherTemp', `${temp}${String.fromCharCode(176)}${unitSymbol}`);
    }
}



// Theme Management
class ThemeManager {
    constructor() {
        this.currentTheme = scopedSettingGet('theme', localStorage.getItem('theme') || 'light');
        this.currentBackground = scopedSettingGet('background', localStorage.getItem('background') || 'Forest');
        this.apply();
        this.applyBackground();
    }

    setTheme(theme) {
        this.currentTheme = theme;
        scopedSettingSet('theme', theme);
        this.apply();
    }

    setBackground(background) {
        this.currentBackground = background;
        scopedSettingSet('background', background);
        this.applyBackground();
    }

    apply() {
        document.body.setAttribute('data-theme', this.currentTheme);
        console.log('Applied theme:', this.currentTheme);
    }

    applyBackground() {
        const desktop = document.querySelector('.desktop');
        if (!desktop) return;

        const customWallpaper = scopedStorageGet('customWallpaper', localStorage.getItem('customWallpaper'));
        if (customWallpaper) {
            desktop.style.background = `url('${customWallpaper}') center/cover no-repeat`;
            desktop.style.backgroundSize = 'cover';
            desktop.style.backgroundPosition = 'center';
            desktop.style.backgroundRepeat = 'no-repeat';
            console.log('Applied custom wallpaper:', customWallpaper);
            return;
        }

        // Check for custom color first
        const customColor = scopedStorageGet('customBackgroundColor', localStorage.getItem('customBackgroundColor'));
        if (customColor) {
            desktop.style.background = customColor;
            console.log('Applied custom background color:', customColor);
            return;
        }

        const backgrounds = {
            'Forest': `url('${DEFAULT_WALLPAPER_URL}') center/cover no-repeat`,
            'Wallpaper Light': "url('assets/wallpaper_light.png') center/cover no-repeat",
            'Wallpaper Dark': "url('assets/wallpaper_dark.png') center/cover no-repeat",
            'Default Gradient': `url('${DEFAULT_WALLPAPER_URL}') center/cover no-repeat`,
            'Blue': 'linear-gradient(135deg, #2193b0 0%, #6dd5ed 100%)',
            'Purple': 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
            'Custom': 'linear-gradient(135deg, #f093fb 0%, #f5576c 100%)'
        };

        desktop.style.background = backgrounds[this.currentBackground] || backgrounds['Default Gradient'];
        desktop.style.backgroundSize = 'cover';
        desktop.style.backgroundPosition = 'center';
        desktop.style.backgroundRepeat = 'no-repeat';
        console.log('Applied background:', this.currentBackground);
    }

    toggle() {
        this.setTheme(this.currentTheme === 'light' ? 'dark' : 'light');
    }
}

// Settings Navigation
class SettingsManager {
    constructor(themeManager) {
        this.themeManager = themeManager;
        
        // Generate random computer ID if it doesn't exist
        const existingComputerId = scopedSettingGet('computerID') || localStorage.getItem('computerID');
        if (!existingComputerId) {
            const randomId = this.generateComputerID();
            scopedSettingSet('computerID', randomId);
        }
        
        this.settings = this.loadSettingsFromStorage();
        this.searchHandlersBound = false;
        this.init();
        this.applyAllSettings();
    }

    loadSettingsFromStorage() {
        return {
            language: scopedSettingGet('language', localStorage.getItem('language') || 'English'),
            timeFormat: scopedSettingGet('timeFormat', localStorage.getItem('timeFormat') || '12-hour'),
            clockSource: scopedSettingGet('clockSource', localStorage.getItem('clockSource') || 'real'),
            temperatureUnit: scopedSettingGet('temperatureUnit', localStorage.getItem('temperatureUnit') || 'celsius'),
            soundEffects: scopedSettingGet('soundEffects', localStorage.getItem('soundEffects') !== 'false' ? 'true' : 'false') !== 'false',
            animations: scopedSettingGet('animations', localStorage.getItem('animations') !== 'false' ? 'true' : 'false') !== 'false',
            notifications: scopedSettingGet('notifications', localStorage.getItem('notifications') !== 'false' ? 'true' : 'false') !== 'false',
            notificationSound: scopedSettingGet('notificationSound', localStorage.getItem('notificationSound') !== 'false' ? 'true' : 'false') !== 'false',
            showPreviews: scopedSettingGet('showPreviews', localStorage.getItem('showPreviews') !== 'false' ? 'true' : 'false') !== 'false',
            saveHistory: scopedSettingGet('saveHistory', localStorage.getItem('saveHistory') !== 'false' ? 'true' : 'false') !== 'false',
            shareData: scopedSettingGet('shareData', localStorage.getItem('shareData') === 'true' ? 'true' : 'false') === 'true',
            transparency: scopedSettingGet('transparency', localStorage.getItem('transparency') !== 'false' ? 'true' : 'false') !== 'false',
            accentColor: scopedSettingGet('accentColor', localStorage.getItem('accentColor') || '#4cc2ff'),
            taskbarSize: scopedSettingGet('taskbarSize', localStorage.getItem('taskbarSize') || 'comfortable'),
            desktopIconScale: scopedSettingGet('desktopIconScale', localStorage.getItem('desktopIconScale') || 'medium'),
            wallpaperPreset: scopedSettingGet('wallpaperPreset', localStorage.getItem('wallpaperPreset') || 'forest'),
            themeMode: scopedSettingGet('themeMode', localStorage.getItem('themeMode') || localStorage.getItem('theme') || 'dark'),
            focusAssist: scopedSettingGet('focusAssist', localStorage.getItem('focusAssist') || 'priority'),
            securityLockscreenEnabled: scopedStorageGet('security_lockscreen_enabled') === 'true',
            securityUnlockMethod: String(scopedStorageGet('security_unlock_method') || 'pin'),
            securityPassword: scopedStorageGet('security_password') || '',
            securityPin: scopedStorageGet('security_pin') || '',
            securityLockWallpaper: scopedStorageGet('security_lock_wallpaper') || '',
            securityLockdownOnHackFail: scopedStorageGet('security_lockdown_on_hack_fail') === 'true',
            securityLockdownPassword: scopedStorageGet('security_lockdown_password') || '',
            computerName: scopedSettingGet('computerName', localStorage.getItem('computerName') || 'computer'),
            computerID: scopedSettingGet('computerID', localStorage.getItem('computerID'))
        };
    }

    reloadForScope() {
        this.settings = this.loadSettingsFromStorage();
        this.applyAllSettings();
        this.loadSettingsSection(this.currentSection || 'Home');
    }

    generateComputerID() {
        const prefix = 'MS-';
        const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
        let id = '';
        for (let i = 0; i < 6; i++) {
            id += chars.charAt(Math.floor(Math.random() * chars.length));
        }
        return prefix + id;
    }

    init() {
        const navItems = document.querySelectorAll('.settings-nav-item');
        navItems.forEach(item => {
            item.addEventListener('click', () => {
                navItems.forEach(nav => nav.classList.remove('active'));
                item.classList.add('active');
                const section = item.textContent.trim();
                this.loadSettingsSection(section);
            });
        });

        this.bindGlobalSearch();
    }

    bindGlobalSearch() {
        if (this.searchHandlersBound) return;
        this.searchHandlersBound = true;
        document.querySelectorAll('.settings-global-search-input, .settings-sidebar-search-input').forEach((input) => {
            input.addEventListener('input', (event) => this.filterCurrentSettingsPage(event.target.value));
        });
    }

    getMainContainer() {
        return document.querySelector('.settings-main');
    }

    saveSetting(key, value) {
        this.settings[key] = value;
        const serialized = typeof value === 'boolean' ? String(value) : value;
        if (String(key).startsWith('security')) {
            const scopedKeyMap = {
                securityLockscreenEnabled: 'security_lockscreen_enabled',
                securityUnlockMethod: 'security_unlock_method',
                securityPassword: 'security_password',
                securityPin: 'security_pin',
                securityLockWallpaper: 'security_lock_wallpaper',
                securityLockdownOnHackFail: 'security_lockdown_on_hack_fail',
                securityLockdownPassword: 'security_lockdown_password'
            };
            const scopedKey = scopedKeyMap[key] || key;
            scopedStorageSet(scopedKey, serialized);
            return;
        }
        scopedSettingSet(key, serialized);
    }

    getWallpaperPresets() {
        return [
            { key: 'forest', label: 'Forest', src: 'assets/wallpaper.jpg' },
            { key: 'wallpaper_light', label: 'Wallpaper Light', src: 'assets/wallpaper_light.png' },
            { key: 'wallpaper_dark', label: 'Wallpaper Dark', src: 'assets/wallpaper_dark.png' }
        ];
    }

    renderShell(content) {
        return `
            <div class="settings-global-search" role="search">
                <i class="fa-solid fa-magnifying-glass"></i>
                <input type="text" class="settings-global-search-input" placeholder="Find a setting">
            </div>
            ${content}
        `;
    }

    renderHomeSection() {
        const wallpaper = scopedStorageGet('customWallpaper', localStorage.getItem('customWallpaper') || 'assets/wallpaper.jpg');
        return this.renderShell(`
            <section class="settings-page-block" data-settings-search="home dashboard summary computer name identity">

                <section class="settings-computer-hero-card">
                    <div class="settings-computer-hero-thumb" style="background-image:url('${wallpaper}')"></div>
                    <div class="settings-computer-hero-info">
                        <div class="settings-computer-hero-name" id="computer-name-display">${this.settings.computerName}</div>
                        <div class="settings-computer-hero-id">${this.settings.computerID || 'MS-??????'}</div>
                        <button class="settings-computer-rename-btn" id="open-rename-computer">Rename</button>
                    </div>
                </section>

                <div class="settings-computer-rename-form" id="rename-computer-form" style="display:none">
                    <input type="text" class="settings-input" id="computer-name-input" value="${this.settings.computerName}" placeholder="Computer name" maxlength="32">
                    <button class="btn-primary" type="button" id="save-computer-name">Save</button>
                    <button class="btn-secondary" type="button" id="cancel-rename-computer">Cancel</button>
                </div>

                <div class="settings-home-grid">
                    <section class="settings-card settings-card-wide" data-settings-search="system personalization notifications privacy about">
                        <div class="settings-card-header"><div><h3>Quick access</h3><p>Jump straight to the pages that matter.</p></div></div>
                        <div class="settings-quick-links settings-link-grid">
                            <button class="settings-link-row" type="button" data-settings-nav="System"><span><strong>System</strong><small>Clock, language, sound and responsiveness</small></span><i class="fa-solid fa-chevron-right"></i></button>
                            <button class="settings-link-row" type="button" data-settings-nav="Personalization"><span><strong>Personalization</strong><small>Theme, wallpaper, accent and taskbar look</small></span><i class="fa-solid fa-chevron-right"></i></button>
                            <button class="settings-link-row" type="button" data-settings-nav="Notifications"><span><strong>Notifications</strong><small>Alerts, sound and focus assist</small></span><i class="fa-solid fa-chevron-right"></i></button>
                            <button class="settings-link-row" type="button" data-settings-nav="Privacy & Security"><span><strong>Privacy & Security</strong><small>Sign-in options and data handling</small></span><i class="fa-solid fa-chevron-right"></i></button>
                        </div>
                    </section>

                    <section class="settings-card" data-settings-search="summary theme taskbar notifications accent">
                        <div class="settings-card-header"><div><h3>Current experience</h3><p>Live status of the shell.</p></div></div>
                        <div class="settings-stat-list">
                            <div class="settings-stat-item"><span>Theme</span><strong>${this.settings.themeMode}</strong></div>
                            <div class="settings-stat-item"><span>Taskbar size</span><strong>${this.settings.taskbarSize}</strong></div>
                            <div class="settings-stat-item"><span>Notifications</span><strong>${this.settings.notifications ? this.settings.focusAssist : 'off'}</strong></div>
                            <div class="settings-stat-item"><span>Lock screen</span><strong>${this.settings.securityLockscreenEnabled ? 'On' : 'Off'}</strong></div>
                        </div>
                    </section>
                </div>
            </section>
        `);
    }

    renderSystemSection() {
        return this.renderShell(`
            <section class="settings-page-block" data-settings-search="system language clock time sound animation desktop icons taskbar">
                <div class="settings-page-heading"><h2>System</h2><p>Core behavior for the computer shell.</p></div>
                <div class="settings-panel-grid">
                    <section class="settings-card">
                        <div class="settings-card-header"><div><h3>Regional format</h3><p>Controls language labels and the taskbar clock.</p></div></div>
                        <div class="setting-group">
                            <label>Language</label>
                            <select class="settings-select" id="language-select">
                                <option value="English" ${this.settings.language === 'English' ? 'selected' : ''}>English</option>
                                <option value="Polish" ${this.settings.language === 'Polish' ? 'selected' : ''}>Polish</option>
                                <option value="Spanish" ${this.settings.language === 'Spanish' ? 'selected' : ''}>Spanish</option>
                            </select>
                        </div>
                        <div class="setting-group">
                            <label>Time format</label>
                            <select class="settings-select" id="timeformat-select">
                                <option value="12-hour" ${this.settings.timeFormat === '12-hour' ? 'selected' : ''}>12-hour</option>
                                <option value="24-hour" ${this.settings.timeFormat === '24-hour' ? 'selected' : ''}>24-hour</option>
                            </select>
                        </div>
                        <div class="setting-group">
                            <label>Clock source</label>
                            <select class="settings-select" id="clock-source-select">
                                <option value="real" ${this.settings.clockSource === 'real' ? 'selected' : ''}>Real time</option>
                                <option value="ingame" ${this.settings.clockSource === 'ingame' ? 'selected' : ''}>In-game time</option>
                            </select>
                        </div>
                        <div class="setting-group">
                            <label>Weather temperature unit</label>
                            <select class="settings-select" id="temperature-unit-select">
                                <option value="celsius" ${this.settings.temperatureUnit === 'celsius' ? 'selected' : ''}>Celsius (C)</option>
                                <option value="fahrenheit" ${this.settings.temperatureUnit === 'fahrenheit' ? 'selected' : ''}>Fahrenheit (F)</option>
                            </select>
                        </div>
                    </section>

                    <section class="settings-card">
                        <div class="settings-card-header"><div><h3>Experience</h3><p>Immediate visual and interaction behavior.</p></div></div>
                        <label class="settings-toggle-row"><span><strong>Sound effects</strong><small>Allow UI clicks and confirmation sounds.</small></span><input type="checkbox" id="sound-effects" ${this.settings.soundEffects ? 'checked' : ''}></label>
                        <label class="settings-toggle-row"><span><strong>Animations</strong><small>Turns fades and motion on or off.</small></span><input type="checkbox" id="animations" ${this.settings.animations ? 'checked' : ''}></label>
                        <div class="setting-group">
                            <label>Desktop icon size</label>
                            <select class="settings-select" id="desktop-icon-scale">
                                <option value="small" ${this.settings.desktopIconScale === 'small' ? 'selected' : ''}>Small</option>
                                <option value="medium" ${this.settings.desktopIconScale === 'medium' ? 'selected' : ''}>Medium</option>
                                <option value="large" ${this.settings.desktopIconScale === 'large' ? 'selected' : ''}>Large</option>
                            </select>
                        </div>
                        <button class="btn-secondary" type="button" id="reset-desktop-layout">Reset desktop app locations</button>
                        <button class="btn-primary" type="button" id="save-system">Apply system settings</button>
                    </section>
                </div>
            </section>
        `);
    }

    renderPersonalizationSection() {
        const wallpapers = this.getWallpaperPresets();
        return this.renderShell(`
            <section class="settings-page-block" data-settings-search="personalization theme wallpaper accent transparency taskbar appearance bevel icons">
                <div class="settings-page-heading"><h2>Personalization</h2><p>Make the shell look like a proper Windows 11 style desktop.</p></div>
                <div class="settings-panel-grid">
                    <section class="settings-card settings-card-wide">
                        <div class="settings-card-header"><div><h3>Theme and wallpaper</h3><p>Applies instantly to the desktop and windows.</p></div></div>
                        <div class="setting-group">
                            <label>Theme mode</label>
                            <select class="settings-select" id="theme-select">
                                <option value="dark" ${this.settings.themeMode === 'dark' ? 'selected' : ''}>Dark</option>
                                <option value="light" ${this.settings.themeMode === 'light' ? 'selected' : ''}>Light</option>
                            </select>
                        </div>
                        <div class="setting-group">
                            <label>Wallpaper</label>
                            <div class="appearance-preset-grid">
                                ${wallpapers.map((preset) => `
                                    <button type="button" class="appearance-preset-card ${this.settings.wallpaperPreset === preset.key ? 'active' : ''}" data-wallpaper-preset="${preset.key}">
                                        <img src="${preset.src}" alt="${preset.label}">
                                        <span>${preset.label}</span>
                                    </button>
                                `).join('')}
                            </div>
                        </div>
                    </section>

                    <section class="settings-card">
                        <div class="settings-card-header"><div><h3>Shell finish</h3><p>Controls the actual taskbar and shell framing.</p></div></div>
                        <div class="setting-group">
                            <label>Accent color</label>
                            <input class="settings-input settings-color-input" type="color" id="accent-color" value="${this.settings.accentColor}">
                        </div>
                        <label class="settings-toggle-row"><span><strong>Transparency effects</strong><small>Blurred materials on the taskbar and start menu.</small></span><input type="checkbox" id="transparency-toggle" ${this.settings.transparency ? 'checked' : ''}></label>
                        <div class="setting-group">
                            <label>Taskbar size</label>
                            <select class="settings-select" id="taskbar-size-select">
                                <option value="compact" ${this.settings.taskbarSize === 'compact' ? 'selected' : ''}>Compact</option>
                                <option value="comfortable" ${this.settings.taskbarSize === 'comfortable' ? 'selected' : ''}>Comfortable</option>
                                <option value="large" ${this.settings.taskbarSize === 'large' ? 'selected' : ''}>Large</option>
                            </select>
                        </div>
                        <button class="btn-primary" type="button" id="save-personalization">Apply personalization</button>
                    </section>
                </div>
            </section>
        `);
    }

    renderNotificationsSection() {
        return this.renderShell(`
            <section class="settings-page-block" data-settings-search="notifications alerts previews focus assist sound">
                <div class="settings-page-heading"><h2>Notifications</h2><p>Control which alerts appear and how noisy they are.</p></div>
                <section class="settings-card settings-card-wide">
                    <label class="settings-toggle-row"><span><strong>Enable notifications</strong><small>Allows popups from the shell and apps.</small></span><input type="checkbox" id="enable-notifications" ${this.settings.notifications ? 'checked' : ''}></label>
                    <label class="settings-toggle-row"><span><strong>Notification sounds</strong><small>Play a sound when a notification appears.</small></span><input type="checkbox" id="notification-sound" ${this.settings.notificationSound ? 'checked' : ''}></label>
                    <label class="settings-toggle-row"><span><strong>Show previews</strong><small>Show the full message body instead of a compact label.</small></span><input type="checkbox" id="show-previews" ${this.settings.showPreviews ? 'checked' : ''}></label>
                    <div class="setting-group">
                        <label>Focus assist</label>
                        <select class="settings-select" id="focus-assist-select">
                            <option value="priority" ${this.settings.focusAssist === 'priority' ? 'selected' : ''}>Priority only</option>
                            <option value="alarms" ${this.settings.focusAssist === 'alarms' ? 'selected' : ''}>Alarms only</option>
                            <option value="all" ${this.settings.focusAssist === 'all' ? 'selected' : ''}>All notifications</option>
                        </select>
                    </div>
                    <button class="btn-primary" type="button" id="save-notifications">Apply notification settings</button>
                </section>
            </section>
        `);
    }

    renderPrivacySection() {
        const locked = this.settings.securityLockscreenEnabled;
        const method = this.settings.securityUnlockMethod || 'pin';
        const lockdownOn = this.settings.securityLockdownOnHackFail;

        const methodRow = (id, icon, label, desc, isActive) => `
            <div class="settings-signin-method-row${isActive ? ' settings-signin-method-active' : ''}" id="method-${id}-card">
                <div class="settings-signin-method-icon"><i class="fa-solid ${icon}"></i></div>
                <div class="settings-signin-method-info"><strong>${label}</strong><small>${isActive ? `${label} sign-in is active` : desc}</small></div>
                <i class="fa-solid fa-chevron-${isActive ? 'up' : 'down'}"></i>
            </div>
            <div class="settings-signin-method-body" id="${id}-method-body" style="display:${isActive ? 'block' : 'none'}">
                ${id === 'fingerprint' ? '<small style="color:rgba(255,255,255,0.65)">Press and hold the fingerprint sensor for 3 seconds on the lock screen.</small>' : `<input class="settings-input" type="password" id="security-${id}" value="${id === 'pin' ? (this.settings.securityPin || '') : (this.settings.securityPassword || '')}" placeholder="${id === 'pin' ? 'Enter PIN (default: 1111)' : 'Enter password'}"><small style="color:rgba(255,255,255,0.45);margin-top:4px;display:block">Leave blank to keep current ${id === 'pin' ? 'PIN' : 'password'}.</small>`}
            </div>
        `;

        return this.renderShell(`
            <section class="settings-page-block" data-settings-search="privacy security lock sign-in pin password fingerprint lockdown history">
                <div class="settings-page-heading"><h2>Privacy &amp; Security</h2><p>Manage sign-in options, data controls, and system reset.</p></div>

                <div class="settings-section-label">Security</div>

                <div class="settings-accordion-wrap">
                    <div class="settings-accordion-header" id="signin-accordion-toggle">
                        <div class="settings-accordion-icon"><i class="fa-solid fa-lock"></i></div>
                        <div class="settings-accordion-text">
                            <strong>Sign-in options</strong>
                            <small>Lock screen, PIN, password, fingerprint</small>
                        </div>
                        <i class="fa-solid fa-chevron-down" id="signin-accordion-chevron"></i>
                    </div>
                    <div class="settings-accordion-body" id="signin-accordion-body" style="display:none">
                        <label class="settings-toggle-row settings-toggle-inset">
                            <span><strong>Enable lock screen</strong><small>Locks this computer when you log off.</small></span>
                            <input type="checkbox" id="security-lockscreen-enabled" ${locked ? 'checked' : ''}>
                        </label>

                        <div id="lockscreen-method-panel" style="display:${locked ? 'block' : 'none'}">
                            <div class="settings-subsection-title" style="margin-top:14px">Unlock method</div>
                            ${methodRow('pin', 'fa-hashtag', 'PIN', 'Sign in with a numeric PIN', method === 'pin')}
                            ${methodRow('password', 'fa-key', 'Password', 'Sign in with a text password', method === 'password')}
                            ${methodRow('fingerprint', 'fa-fingerprint', 'Fingerprint', 'Press and hold to unlock', method === 'fingerprint')}

                            <div class="settings-subsection-title" style="margin-top:16px">Lockdown mode</div>
                            <label class="settings-toggle-row settings-toggle-inset">
                                <span><strong>Enable lockdown</strong><small>Requires an admin password after hack failures.</small></span>
                                <input type="checkbox" id="security-lockdown-on-hack-fail" ${lockdownOn ? 'checked' : ''}>
                            </label>
                            <div id="lockdown-password-panel" style="display:${lockdownOn ? 'block' : 'none'}; padding:8px 0">
                                <input class="settings-input" type="password" id="security-lockdown-password" value="${this.settings.securityLockdownPassword || ''}" placeholder="Lockdown exit password">
                                <small style="color:rgba(255,255,255,0.45);margin-top:4px;display:block">This password can exit an active lockdown on the lock screen.</small>
                            </div>

                            <div class="setting-group" style="margin-top:12px">
                                <label>Lockscreen wallpaper URL (optional)</label>
                                <input class="settings-input" type="text" id="security-lock-wallpaper" value="${this.settings.securityLockWallpaper || ''}" placeholder="https://...">
                            </div>
                        </div>

                        <button class="btn-primary" type="button" id="save-security" style="margin-top:14px">Save sign-in settings</button>
                    </div>
                </div>

                <div class="settings-section-label" style="margin-top:20px">Windows permissions</div>
                <section class="settings-card settings-card-wide">
                    <label class="settings-toggle-row"><span><strong>Save activity history</strong><small>Keeps recent usage data for recommendations.</small></span><input type="checkbox" id="save-history" ${this.settings.saveHistory ? 'checked' : ''}></label>
                    <label class="settings-toggle-row"><span><strong>Share usage data</strong><small>Allows aggregated diagnostics for the terminal.</small></span><input type="checkbox" id="share-data" ${this.settings.shareData ? 'checked' : ''}></label>
                    <button class="btn-primary" type="button" id="save-privacy" style="margin-top:10px">Apply privacy settings</button>
                </section>

                <div class="settings-section-label" style="margin-top:20px">Reset</div>
                <section class="settings-card settings-danger-card">
                    <div class="settings-danger-actions">
                        <button class="btn-secondary" type="button" id="clear-history">Clear recent history</button>
                        <button class="btn-danger" type="button" id="factory-reset">Factory reset</button>
                    </div>
                </section>
            </section>
        `);
    }

    renderAboutSection() {
        const playerName = document.querySelector('[data-player-name]')?.textContent || 'Player';
        const subtitle = document.querySelector('[data-player-subtitle]')?.textContent || 'User';
        return this.renderShell(`
            <section class="settings-page-block" data-settings-search="about version player shell terminal">
                <div class="settings-page-heading"><h2>About</h2><p>Information about this terminal session.</p></div>
                <div class="settings-panel-grid">
                    <section class="settings-card">
                        <div class="settings-stat-list">
                            <div class="settings-stat-item"><span>Current user</span><strong>${playerName}</strong></div>
                            <div class="settings-stat-item"><span>Role</span><strong>${subtitle}</strong></div>
                            <div class="settings-stat-item"><span>Shell version</span><strong>Windows 11 inspired</strong></div>
                            <div class="settings-stat-item"><span>Theme mode</span><strong>${this.settings.themeMode}</strong></div>
                        </div>
                    </section>
                    <section class="settings-card">
                        <div class="settings-card-header"><div><h3>What works</h3><p>The categories now map to real shell behavior.</p></div></div>
                        <ul class="settings-bullet-list">
                            <li>Clock follows 12 or 24 hour format.</li>
                            <li>Taskbar size changes live.</li>
                            <li>Wallpaper, theme, transparency and accent update live.</li>
                            <li>Notifications obey shell rules.</li>
                        </ul>
                    </section>
                </div>
            </section>
        `);
    }

    loadSettingsSection(section = 'Home') {
        const container = this.getMainContainer();
        if (!container) return;

        const map = {
            'Home': () => this.renderHomeSection(),
            'System': () => this.renderSystemSection(),
            'Personalization': () => this.renderPersonalizationSection(),
            'Notifications': () => this.renderNotificationsSection(),
            'Privacy & Security': () => this.renderPrivacySection(),
            'About': () => this.renderAboutSection()
        };

        const renderer = map[section] || map['Home'];
        container.innerHTML = renderer();
        this.bindGlobalSearch();
        this.attachSettingsHandlers(section);
        hydratePlayerProfile();
    }

    filterCurrentSettingsPage(query) {
        const q = String(query || '').trim().toLowerCase();
        document.querySelectorAll('.settings-page-block [data-settings-search], .settings-page-block .settings-card, .settings-page-block .settings-link-row, .settings-page-block .settings-toggle-row, .settings-page-block .setting-group').forEach((element) => {
            const haystack = ((element.getAttribute('data-settings-search') || '') + ' ' + element.textContent).toLowerCase();
            element.classList.toggle('settings-filter-hidden', !!q && !haystack.includes(q));
        });
    }

    applyAllSettings() {
        this.themeManager.setTheme(this.settings.themeMode || 'dark');
        this.applyWallpaperPreset(this.settings.wallpaperPreset || 'forest', true);
        this.applyLiveSettings();
    }

    applyLiveSettings() {
        document.documentElement.style.setProperty('--accent-color', this.settings.accentColor);
        document.body.classList.toggle('animations-disabled', !this.settings.animations);
        document.body.classList.toggle('transparency-disabled', !this.settings.transparency);
        document.body.classList.toggle('notifications-disabled', !this.settings.notifications);
        document.body.dataset.taskbarSize = this.settings.taskbarSize;
        document.body.dataset.desktopIcons = this.settings.desktopIconScale;
        syncChromeMetrics();
        const windowManager = window.windowManagerInstance;
        if (windowManager) windowManager.updateDateTime();
    }

    applyWallpaperPreset(presetKey, silent = false) {
        const preset = this.getWallpaperPresets().find((entry) => entry.key === presetKey);
        if (!preset) return;
        this.saveSetting('wallpaperPreset', preset.key);
        scopedStorageSet('customWallpaper', preset.src);
        scopedStorageRemove('wallpaperGradient');
        scopedStorageRemove('customBackgroundColor');
        this.applyCustomWallpaper(preset.src);
        if (!silent) this.showNotification('Wallpaper updated.');
    }

    applyCustomWallpaper(url) {
        const desktop = document.querySelector('.desktop');
        if (!desktop) return;
        desktop.style.background = `url('${url}') center/cover no-repeat`;
        desktop.style.backgroundSize = 'cover';
        desktop.style.backgroundPosition = 'center';
        desktop.style.backgroundRepeat = 'no-repeat';
    }

    navigateTo(section) {
        const item = Array.from(document.querySelectorAll('.settings-nav-item')).find((node) => node.textContent.trim() === section);
        if (item) item.click();
    }

    attachSettingsHandlers(section) {
        document.querySelectorAll('[data-settings-nav]').forEach((button) => {
            button.addEventListener('click', () => this.navigateTo(button.dataset.settingsNav));
        });

        document.querySelectorAll('[data-wallpaper-preset]').forEach((button) => {
            button.addEventListener('click', () => {
                this.applyWallpaperPreset(button.dataset.wallpaperPreset);
                this.loadSettingsSection('Personalization');
            });
        });

        const bindSave = (id, callback, message) => {
            const button = document.getElementById(id);
            if (!button) return;
            button.addEventListener('click', () => {
                callback();
                this.applyLiveSettings();
                this.showNotification(message);
            });
        };

        bindSave('save-system', () => {
            this.saveSetting('language', document.getElementById('language-select')?.value || 'English');
            this.saveSetting('timeFormat', document.getElementById('timeformat-select')?.value || '12-hour');
            this.saveSetting('clockSource', document.getElementById('clock-source-select')?.value || 'real');
            this.saveSetting('temperatureUnit', document.getElementById('temperature-unit-select')?.value || 'celsius');
            this.saveSetting('soundEffects', !!document.getElementById('sound-effects')?.checked);
            this.saveSetting('animations', !!document.getElementById('animations')?.checked);
            this.saveSetting('desktopIconScale', document.getElementById('desktop-icon-scale')?.value || 'medium');
        }, 'System settings applied.');

        bindSave('save-personalization', () => {
            const themeMode = document.getElementById('theme-select')?.value || 'dark';
            this.saveSetting('themeMode', themeMode);
            this.themeManager.setTheme(themeMode);
            this.saveSetting('accentColor', document.getElementById('accent-color')?.value || '#4cc2ff');
            this.saveSetting('transparency', !!document.getElementById('transparency-toggle')?.checked);
            this.saveSetting('taskbarSize', document.getElementById('taskbar-size-select')?.value || 'comfortable');
        }, 'Personalization applied.');

        bindSave('save-notifications', () => {
            this.saveSetting('notifications', !!document.getElementById('enable-notifications')?.checked);
            this.saveSetting('notificationSound', !!document.getElementById('notification-sound')?.checked);
            this.saveSetting('showPreviews', !!document.getElementById('show-previews')?.checked);
            this.saveSetting('focusAssist', document.getElementById('focus-assist-select')?.value || 'priority');
        }, 'Notification settings applied.');

        bindSave('save-privacy', () => {
            this.saveSetting('saveHistory', !!document.getElementById('save-history')?.checked);
            this.saveSetting('shareData', !!document.getElementById('share-data')?.checked);
        }, 'Privacy settings applied.');

        // --- Sign-in options accordion ---
        const signinToggle = document.getElementById('signin-accordion-toggle');
        if (signinToggle) {
            signinToggle.addEventListener('click', () => {
                const body = document.getElementById('signin-accordion-body');
                const chevron = document.getElementById('signin-accordion-chevron');
                if (!body) return;
                const isOpen = body.style.display !== 'none';
                body.style.display = isOpen ? 'none' : 'block';
                if (chevron) chevron.className = `fa-solid fa-chevron-${isOpen ? 'down' : 'up'}`;
            });
        }

        // Lockscreen enable toggle
        const lockscreenEnabledCb = document.getElementById('security-lockscreen-enabled');
        if (lockscreenEnabledCb) {
            lockscreenEnabledCb.addEventListener('change', () => {
                const enabled = lockscreenEnabledCb.checked;
                const methodPanel = document.getElementById('lockscreen-method-panel');
                if (methodPanel) methodPanel.style.display = enabled ? 'block' : 'none';
            });
        }

        // Sign-in method row click → switches active method
        ['pin', 'password', 'fingerprint'].forEach((m) => {
            const card = document.getElementById(`method-${m}-card`);
            if (!card) return;
            card.addEventListener('click', () => {
                ['pin', 'password', 'fingerprint'].forEach((mo) => {
                    const c = document.getElementById(`method-${mo}-card`);
                    if (c) {
                        c.classList.remove('settings-signin-method-active');
                        const chev = c.querySelector('i.fa-solid:last-child');
                        if (chev) chev.className = 'fa-solid fa-chevron-down';
                    }
                    const b = document.getElementById(`${mo}-method-body`);
                    if (b) b.style.display = 'none';
                });
                card.classList.add('settings-signin-method-active');
                const chevron = card.querySelector('i.fa-solid:last-child');
                if (chevron) chevron.className = 'fa-solid fa-chevron-up';
                const body = document.getElementById(`${m}-method-body`);
                if (body) body.style.display = 'block';
            });
        });

        // Lockdown toggle → show/hide lockdown password field
        const lockdownCb = document.getElementById('security-lockdown-on-hack-fail');
        if (lockdownCb) {
            lockdownCb.addEventListener('change', () => {
                const pwPanel = document.getElementById('lockdown-password-panel');
                if (pwPanel) pwPanel.style.display = lockdownCb.checked ? 'block' : 'none';
            });
        }

        // Save sign-in settings
        bindSave('save-security', () => {
            const lockEnabled = !!document.getElementById('security-lockscreen-enabled')?.checked;
            this.saveSetting('securityLockscreenEnabled', lockEnabled);

            let activeMethod = this.settings.securityUnlockMethod || 'pin';
            ['pin', 'password', 'fingerprint'].forEach((m) => {
                if (document.getElementById(`method-${m}-card`)?.classList.contains('settings-signin-method-active')) {
                    activeMethod = m;
                }
            });
            this.saveSetting('securityUnlockMethod', activeMethod);

            const pinVal = String(document.getElementById('security-pin')?.value || '').trim();
            const pwVal = String(document.getElementById('security-password')?.value || '').trim();
            this.saveSetting('securityPin', pinVal || (activeMethod === 'pin' && lockEnabled && !this.settings.securityPin ? '1111' : this.settings.securityPin));
            this.saveSetting('securityPassword', pwVal || this.settings.securityPassword);
            this.saveSetting('securityLockdownOnHackFail', !!document.getElementById('security-lockdown-on-hack-fail')?.checked);
            this.saveSetting('securityLockdownPassword', String(document.getElementById('security-lockdown-password')?.value || '').trim() || this.settings.securityLockdownPassword);
            this.saveSetting('securityLockWallpaper', String(document.getElementById('security-lock-wallpaper')?.value || '').trim());
            if (window.securityManager && typeof window.securityManager.refreshFromStorage === 'function') {
                window.securityManager.refreshFromStorage();
            }
        }, 'Sign-in settings saved.');

        // Computer name rename flow (Home section)
        const openRenameBtn = document.getElementById('open-rename-computer');
        const renameForm = document.getElementById('rename-computer-form');
        const cancelRenameBtn = document.getElementById('cancel-rename-computer');
        if (openRenameBtn && renameForm) {
            openRenameBtn.addEventListener('click', () => {
                renameForm.style.display = 'flex';
                openRenameBtn.style.display = 'none';
                document.getElementById('computer-name-input')?.focus();
            });
        }
        if (cancelRenameBtn && renameForm) {
            cancelRenameBtn.addEventListener('click', () => {
                renameForm.style.display = 'none';
                if (openRenameBtn) openRenameBtn.style.display = '';
            });
        }

        // Computer name save
        const saveComputerNameButton = document.getElementById('save-computer-name');
        if (saveComputerNameButton) {
            saveComputerNameButton.addEventListener('click', () => {
                const newName = String(document.getElementById('computer-name-input')?.value || '').trim();
                if (!newName) {
                    this.showNotification('Computer name cannot be empty.');
                    return;
                }
                this.saveSetting('computerName', newName);
                this.showNotification(`Computer renamed to "${newName}".`);
                this.loadSettingsSection('Home');
            });
        }

        const clearHistoryButton = document.getElementById('clear-history');
        if (clearHistoryButton) {
            clearHistoryButton.addEventListener('click', () => {
                ['recentFiles', 'recentApps', 'computerRecentItems'].forEach((key) => {
                    scopedStorageRemove(key);
                    localStorage.removeItem(key);
                });
                this.showNotification('Recent history cleared.');
            });
        }

        const factoryResetButton = document.getElementById('factory-reset');
        if (factoryResetButton) {
            factoryResetButton.addEventListener('click', () => {
                const defaults = {
                    language: 'English',
                    timeFormat: '12-hour',
                    clockSource: 'real',
                    temperatureUnit: 'celsius',
                    soundEffects: true,
                    animations: true,
                    notifications: true,
                    notificationSound: true,
                    showPreviews: true,
                    saveHistory: true,
                    shareData: false,
                    transparency: true,
                    accentColor: '#4cc2ff',
                    taskbarSize: 'comfortable',
                    desktopIconScale: 'medium',
                    wallpaperPreset: 'forest',
                    themeMode: 'dark',
                    focusAssist: 'priority',
                    securityLockscreenEnabled: false,
                    securityUnlockMethod: 'password',
                    securityPassword: '',
                    securityPin: '',
                    securityLockWallpaper: '',
                    securityLockdownOnHackFail: false,
                    securityLockdownPassword: '',
                    computerName: 'computer'
                };
                Object.entries(defaults).forEach(([key, value]) => this.saveSetting(key, value));
                scopedStorageSet('security_is_locked', 'false');
                scopedStorageRemove('security_lockdown_until');
                clearAllMailAccountStorage();
                this.applyAllSettings();
                this.loadSettingsSection('Home');
                if (window.securityManager && typeof window.securityManager.refreshFromStorage === 'function') {
                    window.securityManager.refreshFromStorage();
                }
                this.showNotification('Shell reset to default settings.');
            });
        }

        const resetDesktopLayoutButton = document.getElementById('reset-desktop-layout');
        if (resetDesktopLayoutButton) {
            resetDesktopLayoutButton.addEventListener('click', () => {
                if (window.desktopManager && typeof window.desktopManager.resetDesktopLayout === 'function') {
                    window.desktopManager.resetDesktopLayout();
                }
                this.showNotification('Desktop app locations were reset.');
            });
        }
    }

    showNotification(message) {
        uiNotify(message);
    }
}

// Start Menu Management
class StartMenu {
    constructor(windowManager) {
        this.windowManager = windowManager;
        this.startMenu = document.getElementById('start-menu');
        this.startButton = document.getElementById('start-button');
        this.searchTrigger = document.getElementById('taskbar-search-button');
        this.searchBox = document.querySelector('.search-input-box');
        this.recommendations = document.querySelectorAll('.start-recommendation');
        this.isOpen = false;
        this.applyGoogleIcons();
        this.init();
    }

    applyGoogleIcons() {
        document.querySelectorAll('.start-app-tile').forEach((tile) => {
            const appName = tile.dataset.app;
            const iconShell = tile.querySelector('.start-app-icon');
            const appLabel = tile.querySelector('.start-app-name')?.textContent || appName;

            if (!iconShell) return;

            iconShell.innerHTML = renderAppIcon(appName, 'start', appLabel);
        });

        this.recommendations.forEach((item) => {
            const appName = item.dataset.app;
            const iconShell = item.querySelector('.start-recommendation-icon');
            const appLabel = item.querySelector('.start-recommendation-title')?.textContent || appName;

            if (!iconShell) return;

            iconShell.innerHTML = renderAppIcon(appName, 'recommendation', appLabel);
        });
    }

    init() {
        // Toggle start menu on button click
        this.startButton.addEventListener('click', (e) => {
            e.stopPropagation();
            this.toggle();
        });

        if (this.searchTrigger) {
            this.searchTrigger.addEventListener('click', (e) => {
                e.stopPropagation();
                this.open({ focusSearch: true, originEl: this.searchTrigger });
            });
        }

        document.querySelectorAll('.taskbar-pin-launch').forEach((button) => {
            button.addEventListener('click', (e) => {
                e.stopPropagation();
                const appName = button.dataset.app;
                if (!appName) return;

                this.windowManager.handleTaskbarSelection(appName);

                this.close();
            });
        });

        document.querySelectorAll('.taskbar-pin-static').forEach((button) => {
            button.addEventListener('click', (e) => {
                e.stopPropagation();
                uiNotify(button.dataset.message || 'This app is not available on this terminal.');
            });
        });

        // Handle app tile clicks
        const appTiles = document.querySelectorAll('.start-app-tile');
        appTiles.forEach(tile => {
            tile.addEventListener('click', () => {
                const appName = tile.dataset.app;
                this.windowManager.openWindow(appName);
                this.close();
            });
        });

        this.recommendations.forEach((item) => {
            item.addEventListener('click', () => {
                const appName = item.dataset.app;
                if (!appName) return;

                this.windowManager.handleTaskbarSelection(appName);
                this.close();
            });
        });

        // Search functionality for taskbar search box
        if (this.searchBox) {
            this.searchBox.addEventListener('input', (e) => {
                this.filterApps(e.target.value);
            });

            this.searchBox.addEventListener('focus', () => {
                // Open start menu when search is focused
                if (!this.isOpen) {
                    this.open();
                }
            });

            this.searchBox.addEventListener('keypress', (e) => {
                if (e.key === 'Enter') {
                    // Open first visible app
                    const firstVisible = document.querySelector('.start-app-tile:not([style*="display: none"])');
                    if (firstVisible) {
                        const appName = firstVisible.dataset.app;
                        this.windowManager.openWindow(appName);
                        this.close();
                        this.searchBox.value = '';
                        this.filterApps('');
                    }
                }
            });
        }

        // Close start menu when clicking outside
        document.addEventListener('click', (e) => {
            if (this.isOpen && 
                !this.startMenu.contains(e.target) && 
                !this.startButton.contains(e.target) &&
                !this.searchTrigger?.contains(e.target) &&
                !this.searchBox?.contains(e.target)) {
                this.close();
            }
        });

        // Prevent clicks inside start menu from closing it
        this.startMenu.addEventListener('click', (e) => {
            e.stopPropagation();
        });
    }

    filterApps(searchTerm) {
        const normalizedSearch = searchTerm.toLowerCase().trim();
        const appTiles = document.querySelectorAll('.start-app-tile');
        const recommendedSection = this.startMenu?.querySelector('.start-menu-recommended');
        const recommendedLabel = this.startMenu?.querySelector('.start-menu-section-row-secondary');

        appTiles.forEach(tile => {
            const appName = tile.querySelector('.start-app-name').textContent.toLowerCase();
            const appData = tile.dataset.app?.toLowerCase() || '';

            if (normalizedSearch === '' || 
                appName.includes(normalizedSearch) || 
                appData.includes(normalizedSearch)) {
                tile.style.display = '';
            } else {
                tile.style.display = 'none';
            }
        });

        if (recommendedSection) {
            recommendedSection.style.display = normalizedSearch ? 'none' : '';
        }

        if (recommendedLabel) {
            recommendedLabel.style.display = normalizedSearch ? 'none' : '';
        }

        // Open start menu if searching
        if (normalizedSearch && !this.isOpen) {
            this.open();
        }
    }

    toggle() {
        if (this.isOpen) {
            this.close();
        } else {
            this.open({ originEl: this.startButton });
        }
    }

    open(options = {}) {
        this.refreshRecommendations();
        this.updateAnimationOrigin(options.originEl || this.startButton);
        this.startMenu.classList.add('active');
        this.startButton.classList.add('active');
        this.isOpen = true;

        if (options.focusSearch && this.searchBox) {
            requestAnimationFrame(() => this.searchBox.focus());
        }
    }

    close() {
        this.startMenu.classList.remove('active');
        this.startButton.classList.remove('active');
        this.isOpen = false;
        // Clear search when closing
        if (this.searchBox) {
            this.searchBox.value = '';
            this.filterApps('');
        }
    }

    updateAnimationOrigin(originEl) {
        if (!this.startMenu || !originEl) return;

        const triggerRect = originEl.getBoundingClientRect();
        const viewportCenterX = window.innerWidth / 2;
        const menuWidth = this.startMenu.offsetWidth;
        const menuLeft = viewportCenterX - (menuWidth / 2);
        const triggerCenterX = triggerRect.left + triggerRect.width / 2;
        const offsetX = triggerCenterX - viewportCenterX;
        const localOriginX = Math.max(26, Math.min(menuWidth - 26, triggerCenterX - menuLeft));

        this.startMenu.style.setProperty('--start-launch-shift-x', `${offsetX * 0.82}px`);
        this.startMenu.style.setProperty('--start-launch-shift-y', '3.3vh');
        this.startMenu.style.setProperty('--start-pop-origin', `${localOriginX}px`);
    }

    refreshRecommendations() {
        let recentApps = [];
        try {
            recentApps = JSON.parse(scopedStorageGet('recentApps', '[]') || '[]');
        } catch {
            recentApps = [];
        }

        if (!Array.isArray(recentApps) || recentApps.length === 0) return;

        this.recommendations.forEach((button, index) => {
            const appName = recentApps[index];
            if (!appName) return;
            const title = button.querySelector('.start-recommendation-title');
            const meta = button.querySelector('.start-recommendation-meta');
            const icon = button.querySelector('.start-recommendation-icon');

            button.dataset.app = appName;
            if (title) title.textContent = getAppDisplayName(appName);
            if (meta) meta.textContent = 'Recently opened';
            if (icon) icon.innerHTML = renderAppIcon(appName, 'recommendation', getAppDisplayName(appName));
        });
    }
}

// Power Menu
class PowerMenu {
    constructor() {
        this.powerMenu = document.getElementById('power-menu');
        this.powerButton = document.querySelector('.power-button');
        this.isOpen = false;
        this.init();
    }

    init() {
        // Toggle power menu on button click
        this.powerButton.addEventListener('click', (e) => {
            e.stopPropagation();
            this.toggle();
        });

        // Log off option
        document.getElementById('power-logoff').addEventListener('click', () => {
            if (window.securityManager) {
                try {
                    scopedStorageSet('security_is_locked', 'true');
                    if (typeof window.securityManager.markLockedFromLogoff === 'function') {
                        window.securityManager.markLockedFromLogoff();
                    }
                    window.securityManager.lockView = 'idle';
                    window.securityManager.showOverlay();
                } catch (error) {
                    console.warn('Failed to show lock screen on logoff:', error);
                }
            }
            this.close();
        });

        // Shutdown option
        document.getElementById('power-shutdown').addEventListener('click', () => {
            if (window.securityManager && typeof window.securityManager.clearActiveLockscreen === 'function') {
                window.securityManager.clearActiveLockscreen();
            }
            this.close();
            nuiRequest('pc:close', {});
        });

        // Close power menu when clicking outside
        document.addEventListener('click', (e) => {
            if (this.isOpen && 
                !this.powerMenu.contains(e.target) && 
                !this.powerButton.contains(e.target)) {
                this.close();
            }
        });

        // Prevent clicks inside power menu from closing it
        this.powerMenu.addEventListener('click', (e) => {
            e.stopPropagation();
        });
    }

    toggle() {
        if (this.isOpen) {
            this.close();
        } else {
            this.open();
        }
    }

    open() {
        this.powerMenu.classList.add('visible');

        const triggerRect = this.powerButton?.getBoundingClientRect();
        const menuRect = this.powerMenu.getBoundingClientRect();
        if (triggerRect) {
            const left = Math.min(window.innerWidth - menuRect.width - 12, triggerRect.right + 10);
            const top = Math.max(12, triggerRect.bottom - menuRect.height);
            this.powerMenu.style.left = `${left}px`;
            this.powerMenu.style.top = `${top}px`;
            this.powerMenu.style.bottom = 'auto';
        }

        this.isOpen = true;
    }

    close() {
        this.powerMenu.classList.remove('visible');
        this.isOpen = false;
    }
}

class SecurityManager {
    constructor() {
        this.overlay = null;
        this.hackOverlay = null;
        this.clockInterval = null;
        this.lockView = 'idle';
        this.hackFailCount = Number(scopedStorageGet('security_hack_failures') || 0);
        this.serverConfig = { security: {}, hacking: {} };
        this.adminRecoveryAllowed = false;
        this.detectedHackTool = null;
        this.refreshFromStorage();
    }

    async bootstrap() {
        try {
            const result = await nuiRequest('pc:security:getConfig', {});
            if (result?.ok) {
                this.serverConfig = result.data || this.serverConfig;
                this.adminRecoveryAllowed = !!result?.data?.adminRecoveryAllowed;
            }
        } catch (error) {
            console.warn('Failed to load security config:', error);
        }
    }

    refreshFromStorage() {
        this.settings = {
            enabled: scopedStorageGet('security_lockscreen_enabled') === 'true',
            unlockMethod: String(scopedStorageGet('security_unlock_method') || 'pin'),
            password: String(scopedStorageGet('security_password') || ''),
            pin: String(scopedStorageGet('security_pin') || ''),
            lockWallpaper: String(scopedStorageGet('security_lock_wallpaper') || ''),
            lockdownOnHackFail: scopedStorageGet('security_lockdown_on_hack_fail') === 'true',
            lockdownPassword: String(scopedStorageGet('security_lockdown_password') || ''),
            lockdownThreshold: Number(scopedStorageGet('securityLockdownThreshold') || localStorage.getItem('securityLockdownThreshold') || scopedStorageGet('security_lockdown_threshold') || 3)
        };
        if (this.overlay) {
            this.renderOverlay();
        }
    }

    isLocked() {
        return scopedStorageGet('security_is_locked') === 'true' && this.settings.enabled;
    }

    isLockdownActive() {
        const until = Number(scopedStorageGet('security_lockdown_until') || 0);
        return until > Date.now();
    }

    getLockdownRemainingSeconds() {
        const until = Number(scopedStorageGet('security_lockdown_until') || 0);
        return Math.max(0, Math.ceil((until - Date.now()) / 1000));
    }

    isUnlockAttemptTimeoutActive() {
        const until = Number(scopedStorageGet('security_unlock_timeout_until') || 0);
        return until > Date.now();
    }

    getUnlockAttemptTimeoutRemainingSeconds() {
        const until = Number(scopedStorageGet('security_unlock_timeout_until') || 0);
        return Math.max(0, Math.ceil((until - Date.now()) / 1000));
    }

    recordFailedUnlockAttempt() {
        // Timeout levels in seconds: [10, 30, 60, 600, 1800] for attempts 1-5
        const timeoutDurations = [10000, 30000, 60000, 600000, 1800000];
        let failCount = Number(scopedStorageGet('security_unlock_attempt_fails') || 0);
        failCount = Math.min(failCount + 1, 5);
        
        scopedStorageSet('security_unlock_attempt_fails', String(failCount));
        const timeout = timeoutDurations[failCount - 1];
        scopedStorageSet('security_unlock_timeout_until', String(Date.now() + timeout));
    }

    resetFailedUnlockAttempts() {
        scopedStorageRemove('security_unlock_attempt_fails');
        scopedStorageRemove('security_unlock_timeout_until');
    }

    markLockedFromLogoff() {
        this.refreshFromStorage();
        if (!this.settings.enabled) return;
        scopedStorageSet('security_is_locked', 'true');
    }

    clearActiveLockscreen() {
        this.stopClock();
        this.hideOverlay();
        this.hideHackOverlay();
    }

    async handleComputerOpened() {
        await this.bootstrap();
        this.refreshFromStorage();
        await this.detectBestHackTool();

        if (!this.isLocked()) {
            this.hideOverlay();
            return;
        }

        this.lockView = 'idle';
        this.showOverlay();
    }

    async detectBestHackTool() {
        this.detectedHackTool = null;
        try {
            const detected = await nuiRequest('pc:security:detectHackTool', {});
            if (detected?.ok && detected?.data) {
                this.detectedHackTool = detected.data;
            }
        } catch (error) {
            console.warn('Failed to detect hack tool:', error);
        }
    }

    showOverlay() {
        if (!this.overlay) {
            this.overlay = document.createElement('div');
            this.overlay.className = 'pc-lockscreen-overlay';
            document.body.appendChild(this.overlay);
        }
        this.overlay.style.display = 'flex';
        this.renderOverlay();
        this.bindOverlayActions();
        this.startClock();
    }

    hideOverlay() {
        if (!this.overlay) return;
        this.overlay.style.display = 'none';
        this.stopClock();
    }

    hideHackOverlay() {
        if (!this.hackOverlay) return;
        this.hackOverlay.remove();
        this.hackOverlay = null;
    }

    startClock() {
        this.stopClock();
        this.updateLockClock();
        this.clockInterval = setInterval(() => this.updateLockClock(), 1000);
    }

    stopClock() {
        if (!this.clockInterval) return;
        clearInterval(this.clockInterval);
        this.clockInterval = null;
    }

    updateLockClock() {
        if (!this.overlay) return;
        const timeNode = this.overlay.querySelector('[data-lock-clock-time]');
        const dateNode = this.overlay.querySelector('[data-lock-clock-date]');
        if (!timeNode || !dateNode) return;

        const now = new Date();
        timeNode.textContent = now.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
        dateNode.textContent = now.toLocaleDateString([], { weekday: 'long', month: 'long', day: 'numeric' });
    }

    renderOverlay() {
        if (!this.overlay) return;

        const wallpaper = this.settings.lockWallpaper || scopedStorageGet('customWallpaper', localStorage.getItem('customWallpaper') || DEFAULT_WALLPAPER_URL);
        const lockdown = this.isLockdownActive();
        const lockdownRemaining = this.getLockdownRemainingSeconds();
        const method = this.settings.unlockMethod;

        const failCount = Number(scopedStorageGet('security_unlock_attempt_fails') || 0);
        const attemptsLeft = Math.max(0, 5 - failCount);
        const timeoutActive = this.isUnlockAttemptTimeoutActive();
        const timeoutRemaining = this.getUnlockAttemptTimeoutRemainingSeconds();

        let methodTitle = 'Password';
        let methodSubtitle = 'Sign in to continue';
        if (method === 'pin') { methodTitle = 'PIN'; }
        if (method === 'fingerprint') { methodTitle = 'Fingerprint'; methodSubtitle = 'Press and hold for 3 seconds'; }

        const showBreachAction = !!this.detectedHackTool && !lockdown;
        const lockdownWarning = lockdown
            ? `<div class="pc-lockscreen-warning">Lockdown active &mdash; ${lockdownRemaining}s remaining</div>`
            : '';

        const lockdownExitForm = (lockdown && this.settings.lockdownPassword)
            ? `<div class="pc-lockdown-exit-form">
                <div class="pc-lock-auth-subtitle" style="margin-bottom:8px">Enter admin password to exit lockdown</div>
                <div class="pc-lock-auth-input-row">
                    <input id="pc-lockdown-exit-input" type="password" class="settings-input" placeholder="Admin password" autocomplete="off">
                    <button id="pc-lockdown-exit-submit" class="btn-primary">Exit</button>
                </div>
               </div>`
            : '';

        const attemptsText = (!lockdown && failCount > 0)
            ? `<div class="pc-lock-attempts-badge">${
                timeoutActive
                    ? `Too many attempts &mdash; try again in ${timeoutRemaining}s`
                    : `${attemptsLeft} attempt${attemptsLeft !== 1 ? 's' : ''} remaining`
              }</div>`
            : '';

        const inputDisabled = (lockdown || timeoutActive) ? 'disabled' : '';
        const isAuthView = this.lockView === 'auth' || this.lockView === 'fingerprint';

        const fpContent = `
            <div class="pc-fp-hold-wrap" id="pc-fp-hold-target" ${(lockdown || timeoutActive) ? 'data-disabled="1"' : ''}>
                <img src="assets/icons/icons8-fingerprint-100-3.png" class="pc-fp-base" alt="Fingerprint">
                <div class="pc-fp-fill-mask" id="pc-fp-fill-mask"></div>
            </div>
            <div class="pc-fp-progress-text" id="pc-fp-progress-text">${timeoutActive ? `Try again in ${timeoutRemaining}s` : 'Hold to verify'}</div>
        `;

        const pwContent = `
            <div class="pc-lock-auth-input-row">
                <input id="pc-lock-auth-input" type="password" class="settings-input" placeholder="${method === 'pin' ? 'Enter PIN' : 'Enter password'}" ${inputDisabled} autocomplete="off">
                <button id="pc-lock-auth-submit" class="btn-primary" ${inputDisabled}>Unlock</button>
            </div>
        `;

        this.overlay.style.backgroundImage = `linear-gradient(rgba(7, 10, 18, 0.55), rgba(7, 10, 18, 0.75)), url('${wallpaper}')`;
        this.overlay.innerHTML = `
            <div class="pc-lockscreen-stage${isAuthView ? ' pc-lockscreen-stage--auth' : ''}" id="pc-lockscreen-stage">
                <div class="pc-lock-time-container">
                    <div class="pc-lock-time" data-lock-clock-time>--:--</div>
                    <div class="pc-lock-date" data-lock-clock-date></div>
                </div>

                <div class="pc-lock-idle-region" id="pc-lock-idle-region" style="display:${isAuthView ? 'none' : 'flex'}">
                    <div class="pc-lock-idle-hint" id="pc-lock-idle-unlock">
                        <div class="pc-lock-click-hint">Click to unlock</div>
                    </div>
                    ${attemptsText}
                    ${lockdownExitForm}
                </div>

                <div class="pc-lock-auth-region" id="pc-lock-auth-region" style="display:${isAuthView ? 'flex' : 'none'}">
                    <div class="pc-lock-auth-title">${methodTitle}</div>
                    <div class="pc-lock-auth-subtitle">${methodSubtitle}</div>
                    ${lockdownWarning}
                    ${method === 'fingerprint' ? fpContent : pwContent}
                    ${attemptsText}
                    <div class="pc-lock-actions-row">
                        <button class="btn-secondary" id="pc-lock-back">&#8592; Back</button>
                        ${showBreachAction ? '<button class="btn-secondary" id="pc-lock-breach">Use breach device</button>' : ''}
                    </div>
                </div>

                <div id="pc-lock-feedback" class="pc-lockscreen-feedback"></div>
            </div>
        `;

        this.updateLockClock();
    }

    bindOverlayActions() {
        const feedback = (message, isError = false) => {
            const node = this.overlay?.querySelector('#pc-lock-feedback');
            if (!node) return;
            node.textContent = message;
            node.classList.toggle('error', isError);
            clearTimeout(this._feedbackTimer);
            if (message) this._feedbackTimer = setTimeout(() => { if (node) node.textContent = ''; }, 4000);
        };

        const showAuthView = () => {
            const stage = this.overlay.querySelector('#pc-lockscreen-stage');
            const idleRegion = this.overlay.querySelector('#pc-lock-idle-region');
            const authRegion = this.overlay.querySelector('#pc-lock-auth-region');
            if (stage) stage.classList.add('pc-lockscreen-stage--auth');
            if (idleRegion) idleRegion.style.display = 'none';
            if (authRegion) authRegion.style.display = 'flex';
            setTimeout(() => this.overlay?.querySelector('#pc-lock-auth-input')?.focus(), 60);
        };

        const showIdleView = () => {
            const stage = this.overlay.querySelector('#pc-lockscreen-stage');
            const idleRegion = this.overlay.querySelector('#pc-lock-idle-region');
            const authRegion = this.overlay.querySelector('#pc-lock-auth-region');
            if (stage) stage.classList.remove('pc-lockscreen-stage--auth');
            if (idleRegion) idleRegion.style.display = 'flex';
            if (authRegion) authRegion.style.display = 'none';
            this.lockView = 'idle';
        };

        const idleUnlock = this.overlay.querySelector('#pc-lock-idle-unlock');
        if (idleUnlock) {
            idleUnlock.addEventListener('click', () => {
                if (this.isLockdownActive()) {
                    feedback(`Lockdown active — ${this.getLockdownRemainingSeconds()}s remaining`, true);
                    return;
                }
                if (this.isUnlockAttemptTimeoutActive()) {
                    const remaining = this.getUnlockAttemptTimeoutRemainingSeconds();
                    feedback(`Too many failed attempts. Try again in ${remaining}s.`, true);
                    return;
                }
                const method = this.settings.unlockMethod;
                if ((method === 'password' && !this.settings.password) || (method === 'pin' && !this.settings.pin)) {
                    this.onUnlockSuccess('Unlocked.');
                    return;
                }
                this.lockView = method === 'fingerprint' ? 'fingerprint' : 'auth';
                showAuthView();
            });
        }

        const backButton = this.overlay.querySelector('#pc-lock-back');
        if (backButton) {
            backButton.addEventListener('click', () => showIdleView());
        }

        // Lockdown exit via admin password
        const lockdownExitBtn = this.overlay.querySelector('#pc-lockdown-exit-submit');
        if (lockdownExitBtn) {
            const submitLockdownExit = () => {
                const val = String(this.overlay.querySelector('#pc-lockdown-exit-input')?.value || '');
                if (val && val === this.settings.lockdownPassword) {
                    scopedStorageRemove('security_lockdown_until');
                    this.resetFailedUnlockAttempts();
                    this.renderOverlay();
                    this.bindOverlayActions();
                    feedback('Lockdown cleared.', false);
                } else {
                    feedback('Incorrect admin password.', true);
                }
            };
            lockdownExitBtn.addEventListener('click', submitLockdownExit);
            const lockdownExitInput = this.overlay.querySelector('#pc-lockdown-exit-input');
            if (lockdownExitInput) {
                lockdownExitInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') submitLockdownExit(); });
            }
        }

        const authSubmit = this.overlay.querySelector('#pc-lock-auth-submit');
        if (authSubmit) {
            const submitAuth = () => {
                if (this.isUnlockAttemptTimeoutActive()) {
                    const remaining = this.getUnlockAttemptTimeoutRemainingSeconds();
                    feedback(`Too many failed attempts. Try again in ${remaining}s.`, true);
                    return;
                }
                const value = String(this.overlay.querySelector('#pc-lock-auth-input')?.value || '');
                const method = this.settings.unlockMethod;
                if (method === 'pin') {
                    const expected = this.settings.pin || '1111';
                    if (!value || value !== expected) {
                        this.recordFailedUnlockAttempt();
                        const fails = Number(scopedStorageGet('security_unlock_attempt_fails') || 0);
                        const left = Math.max(0, 5 - fails);
                        const rem = this.getUnlockAttemptTimeoutRemainingSeconds();
                        if (this.overlay.querySelector('#pc-lock-auth-input')) this.overlay.querySelector('#pc-lock-auth-input').value = '';
                        feedback(left > 0 ? `Incorrect PIN — ${left} attempt${left !== 1 ? 's' : ''} remaining` : `Too many attempts. Try again in ${rem}s.`, true);
                        return;
                    }
                    this.onUnlockSuccess('Unlocked with PIN.');
                    return;
                }
                if (!value || value !== this.settings.password) {
                    this.recordFailedUnlockAttempt();
                    const fails = Number(scopedStorageGet('security_unlock_attempt_fails') || 0);
                    const left = Math.max(0, 5 - fails);
                    const rem = this.getUnlockAttemptTimeoutRemainingSeconds();
                    if (this.overlay.querySelector('#pc-lock-auth-input')) this.overlay.querySelector('#pc-lock-auth-input').value = '';
                    feedback(left > 0 ? `Incorrect password — ${left} attempt${left !== 1 ? 's' : ''} remaining` : `Too many attempts. Try again in ${rem}s.`, true);
                    return;
                }
                this.onUnlockSuccess('Unlocked with password.');
            };

            authSubmit.addEventListener('click', submitAuth);
            const authInput = this.overlay.querySelector('#pc-lock-auth-input');
            if (authInput) {
                authInput.addEventListener('keydown', (event) => {
                    if (event.key === 'Enter') {
                        submitAuth();
                    }
                });
                authInput.focus();
            }
        }

        const fpTarget = this.overlay.querySelector('#pc-fp-hold-target');
        if (fpTarget) {
            const progressLabel = this.overlay.querySelector('#pc-fp-progress-text');
            const fillMask = this.overlay.querySelector('#pc-fp-fill-mask');
            const holdDuration = 3000;
            let holdStart = 0;
            let holdTimer = null;

            const resetHold = (text) => {
                if (holdTimer) {
                    clearInterval(holdTimer);
                    holdTimer = null;
                }
                holdStart = 0;
                if (fillMask) {
                    fillMask.style.background = 'transparent';
                }
                if (progressLabel && text) progressLabel.textContent = text;
            };

            const beginHold = () => {
                if (fpTarget.dataset.disabled === '1') return;
                
                // Check if timeout is active
                if (this.isUnlockAttemptTimeoutActive()) {
                    const remaining = this.getUnlockAttemptTimeoutRemainingSeconds();
                    resetHold(`Try again in ${remaining}s`);
                    return;
                }
                
                resetHold('Hold to verify');
                holdStart = Date.now();
                holdTimer = setInterval(() => {
                    const elapsed = Date.now() - holdStart;
                    const pct = Math.max(0, Math.min(1, elapsed / holdDuration));
                    // Use gradient fill that grows upward from bottom
                    if (fillMask) {
                        fillMask.style.background = `linear-gradient(to top, rgba(52, 168, 131, 0.6) 0%, rgba(52, 168, 131, 0.6) ${pct * 100}%, transparent ${pct * 100}%)`;
                    }
                    if (progressLabel) progressLabel.textContent = `Verifying... ${Math.floor(pct * 100)}%`;
                    if (pct >= 1) {
                        resetHold('Fingerprint verified.');
                        this.onUnlockSuccess('Unlocked with fingerprint.');
                    }
                }, 30);
            };

            const endHold = () => {
                if (!holdStart) return;
                if (Date.now() - holdStart < holdDuration) {
                    resetHold('Hold canceled');
                }
            };

            fpTarget.addEventListener('mousedown', (event) => {
                if (event.button !== 0) return;
                beginHold();
            });
            fpTarget.addEventListener('mouseup', endHold);
            fpTarget.addEventListener('mouseleave', endHold);
        }

        const breachButton = this.overlay.querySelector('#pc-lock-breach');
        if (breachButton) {
            breachButton.addEventListener('click', async () => {
                await this.tryHackUnlock(feedback);
            });
        }
    }

    getDifficultyForTier(tierCfg) {
        const difficultyName = String(tierCfg?.difficulty || 'easy');
        return this.serverConfig?.hacking?.Difficulty?.[difficultyName] || {
            codeLength: 4,
            memoryDigits: 4,
            mathMax: 20,
            typingLength: 6,
            timeLimitMs: 12000
        };
    }

    async tryHackUnlock(feedback) {
        if (this.isLockdownActive()) {
            feedback(`Lockdown active: ${this.getLockdownRemainingSeconds()}s`, true);
            return;
        }

        const detected = this.detectedHackTool;
        const cfg = detected?.config || (detected?.tier ? this.serverConfig?.hacking?.Tools?.[detected.tier] : null);
        if (!cfg || !detected?.tier) {
            feedback('No breach device found in inventory.', true);
            return;
        }

        const toolCheck = await nuiRequest('pc:security:checkHackTool', { tier: detected.tier });
        if (!toolCheck?.ok) {
            feedback(`Missing tool: ${toolCheck?.data?.label || cfg.label || detected.tier}`, true);
            return;
        }

        const success = await this.runHackSequence(cfg, detected.tier);
        if (success) {
            this.onUnlockSuccess(`Breach successful (${detected.tier}).`);
            return;
        }

        this.hackFailCount += 1;
        scopedStorageSet('security_hack_failures', String(this.hackFailCount));
        feedback(`Hack failed (${this.hackFailCount}).`, true);

        if (!this.settings.lockdownOnHackFail) return;
        const maxFails = Number(this.settings.lockdownThreshold || this.serverConfig?.security?.Default?.maxHackFailuresBeforeLockdown || 3);
        if (this.hackFailCount >= maxFails) {
            const minutes = Number(this.serverConfig?.security?.Default?.lockdownMinutes || 10);
            scopedStorageSet('security_lockdown_until', String(Date.now() + (minutes * 60 * 1000)));
            feedback(`Lockdown activated for ${minutes} minute(s).`, true);
            this.renderOverlay();
            this.bindOverlayActions();
        }
    }

    async runHackSequence(tierCfg, tierName) {
        const difficulty = this.getDifficultyForTier(tierCfg);
        const minigames = Array.isArray(tierCfg.minigames) ? tierCfg.minigames : ['hack_keypad_bruteforce'];
        const stages = Math.max(1, Number(tierCfg.stages || minigames.length || 1));

        for (let i = 0; i < stages; i += 1) {
            const game = minigames[i % minigames.length];
            const ok = await this.runSingleMinigame(game, difficulty, i + 1, stages, tierName);
            if (!ok) return false;
        }
        return true;
    }

    async runSingleMinigame(game, difficulty, stage, totalStages, tierName) {
        const stageTitle = `${String(game).replaceAll('_', ' ')} | ${tierName.toUpperCase()} STAGE ${stage}/${totalStages}`;
        if (game === 'hack_fingerprint_clone') {
            return this.runFingerprintHack(stageTitle, difficulty);
        }
        if (game === 'hack_keypad_bruteforce') {
            return this.runKeypadHack(stageTitle, difficulty);
        }
        if (game === 'hack_voltage_nodes') {
            return this.runVoltageHack(stageTitle, difficulty);
        }
        if (game === 'hack_dot_matrix') {
            return this.runDotMatrixHack(stageTitle, difficulty);
        }

        uiNotify(`Unsupported hack type: ${game}`, 'error');
        return false;
    }

    ensureHackOverlay() {
        if (this.hackOverlay) {
            this.hackOverlay.remove();
        }
        this.hackOverlay = document.createElement('div');
        this.hackOverlay.className = 'pc-hack-overlay';
        document.body.appendChild(this.hackOverlay);
        return this.hackOverlay;
    }

    createTimedHackShell(title, difficulty) {
        const shell = this.ensureHackOverlay();
        shell.innerHTML = `
            <div class="pc-hack-card">
                <div class="pc-hack-title">${title}</div>
                <div class="pc-hack-timer-bar"><span id="pc-hack-timer-fill"></span></div>
                <div class="pc-hack-body" id="pc-hack-body"></div>
                <div class="pc-hack-footer" id="pc-hack-footer"></div>
            </div>
        `;

        const limitMs = Number(difficulty?.timeLimitMs || 12000);
        const timerFill = shell.querySelector('#pc-hack-timer-fill');
        const start = Date.now();
        let timedOut = false;
        const timer = setInterval(() => {
            const elapsed = Date.now() - start;
            const pct = Math.max(0, Math.min(1, elapsed / limitMs));
            if (timerFill) timerFill.style.width = `${Math.max(0, 100 - Math.floor(pct * 100))}%`;
            if (pct >= 1) {
                timedOut = true;
                clearInterval(timer);
            }
        }, 50);

        return {
            shell,
            body: shell.querySelector('#pc-hack-body'),
            footer: shell.querySelector('#pc-hack-footer'),
            isTimedOut: () => timedOut,
            cleanup: () => clearInterval(timer)
        };
    }

    runFingerprintHack(title, difficulty) {
        return new Promise((resolve) => {
            const ui = this.createTimedHackShell(title, difficulty);
            const segmentCount = 4;
            const choicesPerSegment = 4;
            const targets = Array.from({ length: segmentCount }, () => Math.floor(Math.random() * choicesPerSegment));
            const selected = Array.from({ length: segmentCount }, () => -1);

            ui.body.innerHTML = `
                <div class="pc-hack-subtitle">Match each fingerprint segment to reconstruct the print.</div>
                <div class="pc-hack-fingerprint-grid" id="pc-hack-fingerprint-grid"></div>
            `;
            const grid = ui.body.querySelector('#pc-hack-fingerprint-grid');
            targets.forEach((target, segmentIndex) => {
                const row = document.createElement('div');
                row.className = 'pc-hack-fp-row';
                row.innerHTML = `<span>S${segmentIndex + 1}</span>`;
                for (let i = 0; i < choicesPerSegment; i += 1) {
                    const button = document.createElement('button');
                    button.className = 'pc-hack-chip';
                    button.textContent = String(i + 1);
                    button.addEventListener('click', () => {
                        selected[segmentIndex] = i;
                        row.querySelectorAll('button').forEach((btn) => btn.classList.remove('active'));
                        button.classList.add('active');
                    });
                    row.appendChild(button);
                }
                grid.appendChild(row);
            });

            const done = (ok) => {
                ui.cleanup();
                this.hideHackOverlay();
                resolve(ok);
            };

            const submit = document.createElement('button');
            submit.className = 'btn-primary';
            submit.textContent = 'Validate Clone';
            submit.addEventListener('click', () => {
                if (ui.isTimedOut()) return done(false);
                const ok = selected.every((value, idx) => value === targets[idx]);
                done(ok);
            });
            ui.footer.appendChild(submit);

            const timeoutPoll = setInterval(() => {
                if (ui.isTimedOut()) {
                    clearInterval(timeoutPoll);
                    done(false);
                }
            }, 120);
        });
    }

    runKeypadHack(title, difficulty) {
        return new Promise((resolve) => {
            const ui = this.createTimedHackShell(title, difficulty);
            const target = Array.from({ length: 4 }, () => Math.floor(Math.random() * 10));
            const current = Array.from({ length: 4 }, () => 0);
            const locked = Array.from({ length: 4 }, () => false);
            const reels = [];

            ui.body.innerHTML = `
                <div class="pc-hack-subtitle">Stop each rolling digit on the target code.</div>
                <div class="pc-hack-code">TARGET: ${target.join('')}</div>
                <div class="pc-hack-keypad" id="pc-hack-keypad"></div>
            `;
            const keypad = ui.body.querySelector('#pc-hack-keypad');

            for (let i = 0; i < 4; i += 1) {
                const reel = document.createElement('button');
                reel.className = 'pc-hack-reel';
                reel.textContent = '0';
                reel.addEventListener('click', () => {
                    locked[i] = true;
                    reel.classList.add('locked');
                    if (locked.every(Boolean)) {
                        const ok = current.every((digit, idx) => digit === target[idx]);
                        done(ok);
                    }
                });
                reels.push(reel);
                keypad.appendChild(reel);
            }

            const rollInterval = setInterval(() => {
                reels.forEach((reel, idx) => {
                    if (locked[idx]) return;
                    current[idx] = Math.floor(Math.random() * 10);
                    reel.textContent = String(current[idx]);
                });
            }, 85);

            const done = (ok) => {
                clearInterval(rollInterval);
                ui.cleanup();
                this.hideHackOverlay();
                resolve(ok);
            };

            const timeoutPoll = setInterval(() => {
                if (ui.isTimedOut()) {
                    clearInterval(timeoutPoll);
                    done(false);
                }
            }, 120);
        });
    }

    runVoltageHack(title, difficulty) {
        return new Promise((resolve) => {
            const ui = this.createTimedHackShell(title, difficulty);
            const target = 120 + Math.floor(Math.random() * 30);
            const values = [30, 45, 50];

            ui.body.innerHTML = `
                <div class="pc-hack-subtitle">Balance voltage output to match target load.</div>
                <div class="pc-hack-code">TARGET LOAD: <span id="pc-load-target">${target}</span>v</div>
                <div class="pc-hack-voltage" id="pc-hack-voltage"></div>
                <div class="pc-hack-code">CURRENT: <span id="pc-load-current">${values.reduce((a, b) => a + b, 0)}</span>v</div>
            `;
            const voltage = ui.body.querySelector('#pc-hack-voltage');
            const currentNode = ui.body.querySelector('#pc-load-current');

            const updateCurrent = () => {
                const total = values.reduce((a, b) => a + b, 0);
                if (currentNode) currentNode.textContent = String(total);
                return total;
            };

            for (let i = 0; i < 3; i += 1) {
                const input = document.createElement('input');
                input.type = 'range';
                input.min = '0';
                input.max = '90';
                input.value = String(values[i]);
                input.className = 'pc-hack-slider';
                input.addEventListener('input', () => {
                    values[i] = Number(input.value);
                    updateCurrent();
                });
                voltage.appendChild(input);
            }

            const done = (ok) => {
                ui.cleanup();
                this.hideHackOverlay();
                resolve(ok);
            };

            const submit = document.createElement('button');
            submit.className = 'btn-primary';
            submit.textContent = 'Apply Load';
            submit.addEventListener('click', () => {
                if (ui.isTimedOut()) return done(false);
                const total = updateCurrent();
                done(Math.abs(total - target) <= 3);
            });
            ui.footer.appendChild(submit);

            const timeoutPoll = setInterval(() => {
                if (ui.isTimedOut()) {
                    clearInterval(timeoutPoll);
                    done(false);
                }
            }, 120);
        });
    }

    runDotMatrixHack(title, difficulty) {
        return new Promise((resolve) => {
            const ui = this.createTimedHackShell(title, difficulty);
            const size = 4;
            const target = Array.from({ length: size * size }, () => Math.random() > 0.55);
            const state = Array.from({ length: size * size }, () => false);

            ui.body.innerHTML = `
                <div class="pc-hack-subtitle">Replicate the highlighted matrix.</div>
                <div class="pc-hack-code">Watch pattern...</div>
                <div class="pc-hack-matrix" id="pc-hack-target"></div>
                <div class="pc-hack-code">Your input</div>
                <div class="pc-hack-matrix" id="pc-hack-input"></div>
            `;

            const targetGrid = ui.body.querySelector('#pc-hack-target');
            const inputGrid = ui.body.querySelector('#pc-hack-input');

            const makeCell = (active) => {
                const cell = document.createElement('button');
                cell.className = `pc-hack-dot${active ? ' active' : ''}`;
                return cell;
            };

            target.forEach((active) => targetGrid.appendChild(makeCell(active)));
            setTimeout(() => {
                targetGrid.querySelectorAll('.pc-hack-dot').forEach((cell) => cell.classList.remove('active'));
            }, 1400);

            state.forEach((active, idx) => {
                const cell = makeCell(active);
                cell.addEventListener('click', () => {
                    state[idx] = !state[idx];
                    cell.classList.toggle('active', state[idx]);
                });
                inputGrid.appendChild(cell);
            });

            const done = (ok) => {
                ui.cleanup();
                this.hideHackOverlay();
                resolve(ok);
            };

            const submit = document.createElement('button');
            submit.className = 'btn-primary';
            submit.textContent = 'Confirm Pattern';
            submit.addEventListener('click', () => {
                if (ui.isTimedOut()) return done(false);
                done(state.every((value, idx) => value === target[idx]));
            });
            ui.footer.appendChild(submit);

            const timeoutPoll = setInterval(() => {
                if (ui.isTimedOut()) {
                    clearInterval(timeoutPoll);
                    done(false);
                }
            }, 120);
        });
    }

    randomAlphaNumeric(length) {
        const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        let out = '';
        for (let i = 0; i < length; i += 1) {
            out += chars[Math.floor(Math.random() * chars.length)];
        }
        return out;
    }

    randomDigits(length) {
        let out = '';
        for (let i = 0; i < length; i += 1) {
            out += String(Math.floor(Math.random() * 10));
        }
        return out;
    }

    onUnlockSuccess(message) {
        this.hackFailCount = 0;
        scopedStorageSet('security_hack_failures', '0');
        scopedStorageRemove('security_lockdown_until');
        this.resetFailedUnlockAttempts();
        scopedStorageSet('security_is_locked', 'false');
        this.lockView = 'idle';
        this.hideOverlay();
        this.hideHackOverlay();
        uiNotify(message, 'success');
    }
}

// City Hall Management System
class CityHallManager {
    constructor() {
        this.currentPage = 'dashboard';
        this.data = {
            cityName: 'State of San Andreas',
            treasuryBalance: 2450000,
            mayorName: 'John Smith',
            laws: this.loadLaws(),
            taxes: this.loadTaxes(),
            budgets: this.loadBudgets(),
            licenses: this.loadLicenses(),
            utilities: this.loadUtilities(),
            fines: this.loadFines(),
            staff: this.loadStaff(),
            auditLog: this.loadAuditLog()
        };
        this.init();
    }

    init() {
        // Wait for City Hall window to be opened
        setTimeout(() => {
            const navItems = document.querySelectorAll('.cityhall-nav-item');
            navItems.forEach(item => {
                item.addEventListener('click', () => {
                    this.navigateTo(item.dataset.page);
                });
            });

            // Load initial page
            this.loadPage('dashboard');
        }, 100);
    }

    navigateTo(page) {
        // Update active nav item
        document.querySelectorAll('.cityhall-nav-item').forEach(item => {
            item.classList.remove('active');
            if (item.dataset.page === page) {
                item.classList.add('active');
            }
        });

        this.currentPage = page;
        this.loadPage(page);
    }

    loadPage(page) {
        const container = document.getElementById('cityhall-content');
        if (!container) return;

        const pages = {
            'dashboard': this.renderDashboard(),
            'laws': this.renderLaws(),
            'taxes': this.renderTaxes(),
            'budgets': this.renderBudgets(),
            'licenses': this.renderLicenses(),
            'utilities': this.renderUtilities(),
            'fines': this.renderFines(),
            'staff': this.renderStaff(),
            'audit': this.renderAuditLog(),
            'cityhall-settings': this.renderCityHallSettings()
        };

        container.innerHTML = pages[page] || pages['dashboard'];
        this.attachPageHandlers(page);
    }

    renderDashboard() {
        return `
            <div class="cityhall-page dashboard-page">
                <h1 class="page-title">Dashboard Overview</h1>
                
                <div class="dashboard-cards">
                    <div class="dash-card">
                        <div class="dash-card-icon">💰</div>
                        <div class="dash-card-info">
                            <div class="dash-card-label">Treasury Balance</div>
                            <div class="dash-card-value">$${this.data.treasuryBalance.toLocaleString()}</div>
                        </div>
                    </div>
                    <div class="dash-card">
                        <div class="dash-card-icon">📈</div>
                        <div class="dash-card-info">
                            <div class="dash-card-label">Revenue Today</div>
                            <div class="dash-card-value green">+$48,200</div>
                        </div>
                    </div>
                    <div class="dash-card">
                        <div class="dash-card-icon">📊</div>
                        <div class="dash-card-info">
                            <div class="dash-card-label">Revenue This Week</div>
                            <div class="dash-card-value green">+$342,800</div>
                        </div>
                    </div>
                    <div class="dash-card">
                        <div class="dash-card-icon">⚠️</div>
                        <div class="dash-card-info">
                            <div class="dash-card-label">Unpaid Debt Total</div>
                            <div class="dash-card-value red">$12,500</div>
                        </div>
                    </div>
                </div>

                <div class="dashboard-content">
                    <div class="dashboard-section">
                        <h2>Revenue Sources</h2>
                        <div class="chart-placeholder">
                            <div class="chart-bar" style="height: 70%;">
                                <span>Tax Revenue</span>
                                <span>70%</span>
                            </div>
                            <div class="chart-bar" style="height: 15%;">
                                <span>Business Fees</span>
                                <span>15%</span>
                            </div>
                            <div class="chart-bar" style="height: 10%;">
                                <span>Fines</span>
                                <span>10%</span>
                            </div>
                            <div class="chart-bar" style="height: 5%;">
                                <span>Licenses</span>
                                <span>5%</span>
                            </div>
                        </div>
                    </div>

                    <div class="dashboard-section">
                        <h2>Alerts & Notifications</h2>
                        <div class="alert-list">
                            <div class="alert-item warning">
                                <span class="alert-icon">⚠️</span>
                                <span class="alert-text">5 businesses delinquent on license</span>
                                <span class="alert-time">2h ago</span>
                            </div>
                            <div class="alert-item error">
                                <span class="alert-icon">❌</span>
                                <span class="alert-text">Power delinquency in 3 properties</span>
                                <span class="alert-time">4h ago</span>
                            </div>
                            <div class="alert-item info">
                                <span class="alert-icon">ℹ️</span>
                                <span class="alert-text">New law passed, pending publish</span>
                                <span class="alert-time">1d ago</span>
                            </div>
                            <div class="alert-item info">
                                <span class="alert-icon">📋</span>
                                <span class="alert-text">Budget request from PD</span>
                                <span class="alert-time">2d ago</span>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        `;
    }

    renderLaws() {
        const laws = this.data.laws;
        return `
            <div class="cityhall-page laws-page">
                <h1 class="page-title">Laws & Policy Management</h1>
                
                <div class="laws-container">
                    <div class="laws-left">
                        <div class="laws-controls">
                            <input type="text" placeholder="Search laws..." class="search-input" id="law-search">
                            <button class="btn-primary" id="create-law-btn">Create New Law</button>
                        </div>
                        
                        <div class="laws-filters">
                            <button class="filter-btn active" data-filter="all">All</button>
                            <button class="filter-btn" data-filter="traffic">Traffic</button>
                            <button class="filter-btn" data-filter="weapons">Weapons</button>
                            <button class="filter-btn" data-filter="business">Business</button>
                            <button class="filter-btn" data-filter="civil">Civil</button>
                        </div>

                        <div class="laws-list">
                            ${laws.map(law => `
                                <div class="law-item ${law.status}" data-law-id="${law.id}">
                                    <div class="law-title">${law.title}</div>
                                    <div class="law-meta">
                                        <span class="law-category">${law.category}</span>
                                        <span class="law-status">${law.status}</span>
                                    </div>
                                </div>
                            `).join('')}
                        </div>
                    </div>

                    <div class="laws-right">
                        <div id="law-editor" class="law-editor">
                            <div class="editor-placeholder">
                                <p>Select a law to edit or create a new one</p>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        `;
    }

    renderTaxes() {
        const taxes = this.data.taxes;
        return `
            <div class="cityhall-page taxes-page">
                <h1 class="page-title">Taxes & Fees</h1>
                
                <div class="taxes-table">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>Tax Type</th>
                                <th>Current Rate</th>
                                <th>Min - Max</th>
                                <th>Last Changed By</th>
                                <th>Last Changed</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${taxes.map(tax => `
                                <tr>
                                    <td>${tax.name}</td>
                                    <td class="rate-value">${tax.rate}%</td>
                                    <td>${tax.min}% - ${tax.max}%</td>
                                    <td>${tax.lastChangedBy}</td>
                                    <td>${tax.lastChanged}</td>
                                    <td>
                                        <button class="btn-secondary btn-sm" onclick="cityHall.editTax('${tax.id}')">Edit</button>
                                    </td>
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                </div>
            </div>
        `;
    }

    renderBudgets() {
        const budgets = this.data.budgets;
        return `
            <div class="cityhall-page budgets-page">
                <h1 class="page-title">Department Budgets</h1>
                
                <div class="budgets-list">
                    ${budgets.map(dept => `
                        <div class="budget-card">
                            <div class="budget-header">
                                <h3>${dept.name}</h3>
                                <span class="budget-total">$${dept.allocated.toLocaleString()}</span>
                            </div>
                            <div class="budget-stats">
                                <div class="budget-stat">
                                    <span class="stat-label">Spent This Month</span>
                                    <span class="stat-value">$${dept.spent.toLocaleString()}</span>
                                </div>
                                <div class="budget-stat">
                                    <span class="stat-label">Remaining</span>
                                    <span class="stat-value green">$${(dept.allocated - dept.spent).toLocaleString()}</span>
                                </div>
                                ${dept.requests > 0 ? `
                                    <div class="budget-stat">
                                        <span class="stat-label">Pending Requests</span>
                                        <span class="stat-value orange">${dept.requests}</span>
                                    </div>
                                ` : ''}
                            </div>
                            <div class="budget-actions">
                                <button class="btn-secondary btn-sm">View Details</button>
                                <button class="btn-secondary btn-sm">Adjust Budget</button>
                                ${dept.requests > 0 ? `<button class="btn-primary btn-sm">Review Requests</button>` : ''}
                            </div>
                        </div>
                    `).join('')}
                </div>
            </div>
        `;
    }

    renderLicenses() {
        return `
            <div class="cityhall-page licenses-page">
                <div class="licenses-header">
                    <h1 class="page-title">Licenses & Permits</h1>
                    <div class="header-actions">
                        <button class="btn-primary" data-modal="create-license">Create New License</button>
                        <button class="btn-secondary">Export Report</button>
                    </div>
                </div>
                
                <div class="licenses-stats-grid">
                    <div class="stat-card">
                        <div class="stat-icon" style="background: var(--success-bg); color: var(--success);">✓</div>
                        <div>
                            <div class="stat-value">342</div>
                            <div class="stat-label">Active Licenses</div>
                        </div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-icon" style="background: var(--warning-bg); color: var(--warning);">⌛</div>
                        <div>
                            <div class="stat-value">18</div>
                            <div class="stat-label">Expiring Soon</div>
                        </div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-icon" style="background: var(--danger-bg); color: var(--danger);">✕</div>
                        <div>
                            <div class="stat-value">7</div>
                            <div class="stat-label">Suspended</div>
                        </div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-icon" style="background: var(--info-bg); color: var(--info);">📋</div>
                        <div>
                            <div class="stat-value">42</div>
                            <div class="stat-label">Pending Review</div>
                        </div>
                    </div>
                </div>

                <div class="licenses-tabs">
                    <button class="tab-btn active" data-tab="citizen">Citizen Licenses</button>
                    <button class="tab-btn" data-tab="business">Business Licenses</button>
                    <button class="tab-btn" data-tab="permits">Special Permits</button>
                    <button class="tab-btn" data-tab="vehicles">Vehicle Registration</button>
                </div>

                <div class="licenses-controls">
                    <input type="text" placeholder="Search by name, ID, license number..." class="search-input">
                    <select class="filter-select">
                        <option>All Status</option>
                        <option>Active</option>
                        <option>Expiring Soon</option>
                        <option>Suspended</option>
                        <option>Revoked</option>
                    </select>
                    <select class="filter-select">
                        <option>All Types</option>
                        <option>Driver's License</option>
                        <option>Weapon License</option>
                        <option>Business License</option>
                        <option>Special Permit</option>
                    </select>
                </div>

                <div class="licenses-table-container">
                    <table class="data-table licenses-data-table">
                        <thead>
                            <tr>
                                <th>License ID</th>
                                <th>Holder</th>
                                <th>Type</th>
                                <th>Issued</th>
                                <th>Expires</th>
                                <th>Status</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${this.renderLicenseRows()}
                        </tbody>
                    </table>
                </div>
            </div>
        `;
    }

    renderLicenseRows() {
        // Combine demo citizen licenses with business licenses
        const demoLicenses = [
            {
                id: 'DL-10245',
                holder: 'John Doe',
                holderType: 'Citizen',
                holderInfo: 'CID: 4782',
                type: 'Driver\'s License',
                issueDate: '01/15/2025',
                expiryDate: '01/15/2027',
                status: 'active'
            },
            {
                id: 'WL-3872',
                holder: 'Sarah Connor',
                holderType: 'Citizen',
                holderInfo: 'CID: 2901',
                type: 'Weapon License',
                issueDate: '03/10/2024',
                expiryDate: '03/10/2026',
                status: 'active'
            },
            {
                id: 'DL-9233',
                holder: 'Mark Smith',
                holderType: 'Citizen',
                holderInfo: 'CID: 6642',
                type: 'Driver\'s License',
                issueDate: '08/22/2023',
                expiryDate: '08/22/2025',
                status: 'suspended'
            }
        ];

        // Add business licenses from config
        const allLicenses = [...demoLicenses, ...this.data.licenses];

        return allLicenses.map(license => {
            let statusBadge = '';
            let statusClass = '';
            
            if (license.status === 'active') {
                statusBadge = 'Active';
                statusClass = 'active';
            } else if (license.status === 'warning') {
                statusBadge = `Expires in ${license.daysUntilExpiry} days`;
                statusClass = 'warning';
            } else if (license.status === 'expired') {
                statusBadge = 'Expired';
                statusClass = 'error';
            } else if (license.status === 'suspended') {
                statusBadge = 'Suspended';
                statusClass = 'error';
            }

            const holderInfo = license.holderType === 'Business' 
                ? `Type: ${license.businessType || 'General'}` 
                : license.holderInfo;

            return `
                <tr>
                    <td><strong>${license.id}</strong></td>
                    <td>
                        <div class="holder-info">
                            <div class="holder-name">${license.holder}</div>
                            <div class="holder-id">${holderInfo}</div>
                        </div>
                    </td>
                    <td>${license.type}</td>
                    <td>${license.issueDate}</td>
                    <td>${license.expiryDate}</td>
                    <td><span class="status-badge ${statusClass}">${statusBadge}</span></td>
                    <td>
                        <div class="action-buttons">
                            <button class="btn-icon" title="View Details">👁</button>
                            <button class="btn-icon" title="Renew">🔄</button>
                            <button class="btn-icon" title="${license.status === 'suspended' ? 'Reinstate' : 'Suspend'}">
                                ${license.status === 'suspended' ? '↩' : '⏸'}
                            </button>
                        </div>
                    </td>
                </tr>
            `;
        }).join('');
    }

    renderUtilities() {
        const utilities = this.data.utilities;
        return `
            <div class="cityhall-page utilities-page">
                <h1 class="page-title">Utilities & Services Management</h1>
                
                <div class="utilities-overview">
                    <div class="utility-card">
                        <h3>Power Grid Status</h3>
                        <div class="utility-status">
                            <span class="status-indicator active"></span>
                            <span>OPERATIONAL</span>
                        </div>
                        <div class="utility-stats">
                            <div>Active Connections: <strong>${utilities.power.active}</strong></div>
                            <div>Delinquent: <strong class="warning">${utilities.power.delinquent}</strong></div>
                            <div>Disconnected: <strong class="error">${utilities.power.disconnected}</strong></div>
                        </div>
                    </div>

                    <div class="utility-card">
                        <h3>Water Services</h3>
                        <div class="utility-status">
                            <span class="status-indicator active"></span>
                            <span>OPERATIONAL</span>
                        </div>
                        <div class="utility-stats">
                            <div>Active Connections: <strong>${utilities.water.active}</strong></div>
                            <div>Delinquent: <strong class="warning">${utilities.water.delinquent}</strong></div>
                            <div>Disconnected: <strong class="error">${utilities.water.disconnected}</strong></div>
                        </div>
                    </div>
                </div>

                <div class="utilities-controls">
                    <h2>Delinquent Accounts</h2>
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>Property ID</th>
                                <th>Owner</th>
                                <th>Service</th>
                                <th>Amount Owed</th>
                                <th>Days Overdue</th>
                                <th>Status</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr>
                                <td>PROP-1024</td>
                                <td>John Smith</td>
                                <td>Power</td>
                                <td>$425</td>
                                <td>45</td>
                                <td><span class="status-badge warning">Delinquent</span></td>
                                <td>
                                    <button class="btn-secondary btn-sm">Send Notice</button>
                                    <button class="btn-danger btn-sm">Disconnect</button>
                                </td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        `;
    }

    renderFines() {
        return `
            <div class="cityhall-page fines-page">
                <h1 class="page-title">Fines & Collections</h1>
                
                <div class="fines-summary">
                    <div class="summary-card">
                        <div class="summary-value">$12,500</div>
                        <div class="summary-label">Total Outstanding</div>
                    </div>
                    <div class="summary-card">
                        <div class="summary-value">23</div>
                        <div class="summary-label">Unpaid Fines</div>
                    </div>
                    <div class="summary-card">
                        <div class="summary-value">8</div>
                        <div class="summary-label">Overdue &gt; 30 Days</div>
                    </div>
                </div>

                <div class="fines-controls">
                    <input type="text" placeholder="Search by name or citation ID..." class="search-input">
                    <select class="filter-select">
                        <option>All Fines</option>
                        <option>Unpaid</option>
                        <option>Overdue</option>
                        <option>Paid</option>
                    </select>
                </div>

                <div class="fines-table">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>Citation ID</th>
                                <th>Name</th>
                                <th>Violation</th>
                                <th>Amount</th>
                                <th>Due Date</th>
                                <th>Status</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr>
                                <td>FINE-2491</td>
                                <td>Jane Doe</td>
                                <td>Reckless Driving</td>
                                <td>$500</td>
                                <td>02/01/2026</td>
                                <td><span class="status-badge error">Overdue</span></td>
                                <td>
                                    <button class="btn-secondary btn-sm">View</button>
                                    <button class="btn-secondary btn-sm">Add Late Fee</button>
                                    <button class="btn-danger btn-sm">Escalate</button>
                                </td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        `;
    }

    renderStaff() {
        const staff = this.data.staff;
        return `
            <div class="cityhall-page staff-page">
                <h1 class="page-title">Government Staff & Permissions</h1>
                
                <div class="staff-controls">
                    <button class="btn-primary">Add Staff Member</button>
                </div>

                <div class="staff-table">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>Name</th>
                                <th>Position</th>
                                <th>Permissions</th>
                                <th>Status</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${staff.map(member => `
                                <tr>
                                    <td>${member.name}</td>
                                    <td><strong>${member.position}</strong></td>
                                    <td>
                                        ${member.permissions.map(p => `<span class="permission-tag">${p}</span>`).join(' ')}
                                    </td>
                                    <td><span class="status-badge active">${member.status}</span></td>
                                    <td>
                                        <button class="btn-secondary btn-sm">Edit</button>
                                        <button class="btn-secondary btn-sm">Permissions</button>
                                    </td>
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                </div>
            </div>
        `;
    }

    renderAuditLog() {
        const logs = this.data.auditLog;
        return `
            <div class="cityhall-page audit-page">
                <h1 class="page-title">Audit Log</h1>
                
                <div class="audit-filters">
                    <select class="filter-select">
                        <option>All Categories</option>
                        <option>Laws</option>
                        <option>Taxes</option>
                        <option>Budgets</option>
                        <option>Utilities</option>
                        <option>Licenses</option>
                    </select>
                    <select class="filter-select">
                        <option>All Users</option>
                        <option>Mayor</option>
                        <option>Deputy Mayor</option>
                        <option>Treasurer</option>
                    </select>
                    <input type="date" class="filter-input">
                </div>

                <div class="audit-table">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>Timestamp</th>
                                <th>User</th>
                                <th>Action</th>
                                <th>Category</th>
                                <th>Details</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${logs.map(log => `
                                <tr>
                                    <td>${log.timestamp}</td>
                                    <td>${log.user}</td>
                                    <td>${log.action}</td>
                                    <td><span class="category-tag">${log.category}</span></td>
                                    <td>${log.details}</td>
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                </div>
            </div>
        `;
    }

    renderCityHallSettings() {
        return `
            <div class="cityhall-page settings-page">
                <h1 class="page-title">City Hall Settings</h1>
                
                <div class="setting-group">
                    <label>City Name</label>
                    <input type="text" value="${this.data.cityName}" class="setting-input">
                </div>

                <div class="setting-group">
                    <label>Mayor Term Length (months)</label>
                    <input type="number" value="6" class="setting-input">
                </div>

                <div class="setting-group">
                    <label>
                        <input type="checkbox" checked> Enable MDT Integration
                    </label>
                </div>

                <div class="setting-group">
                    <label>
                        <input type="checkbox" checked> Enable Audit Logging
                    </label>
                </div>

                <button class="btn-primary">Save Settings</button>
            </div>
        `;
    }

    attachPageHandlers(page) {
        // Attach event handlers specific to each page
        if (page === 'laws') {
            const lawItems = document.querySelectorAll('.law-item');
            lawItems.forEach(item => {
                item.addEventListener('click', () => {
                    this.editLaw(item.dataset.lawId);
                });
            });
        }
    }

    editLaw(lawId) {
        const law = this.data.laws.find(l => l.id == lawId);
        if (!law) return;

        const editor = document.getElementById('law-editor');
        editor.innerHTML = `
            <div class="law-editor-form">
                <h3>Edit Law</h3>
                
                <div class="form-group">
                    <label>Title</label>
                    <input type="text" value="${law.title}" class="form-input">
                </div>

                <div class="form-group">
                    <label>Category</label>
                    <select class="form-input">
                        <option ${law.category === 'Traffic' ? 'selected' : ''}>Traffic</option>
                        <option ${law.category === 'Weapons' ? 'selected' : ''}>Weapons</option>
                        <option ${law.category === 'Business' ? 'selected' : ''}>Business</option>
                        <option ${law.category === 'Civil' ? 'selected' : ''}>Civil</option>
                    </select>
                </div>

                <div class="form-group">
                    <label>Law Text</label>
                    <textarea class="form-textarea" rows="6">${law.text}</textarea>
                </div>

                <div class="form-group">
                    <label>Default Fine ($)</label>
                    <input type="number" value="${law.fine}" class="form-input">
                </div>

                <div class="form-group">
                    <label>Default Jail Time (months)</label>
                    <input type="number" value="${law.jail}" class="form-input">
                </div>

                <div class="form-group">
                    <label>Status</label>
                    <select class="form-input">
                        <option ${law.status === 'draft' ? 'selected' : ''}>Draft</option>
                        <option ${law.status === 'active' ? 'selected' : ''}>Active</option>
                        <option ${law.status === 'repealed' ? 'selected' : ''}>Repealed</option>
                    </select>
                </div>

                <div class="form-actions">
                    <button class="btn-secondary">Save Draft</button>
                    <button class="btn-primary">Publish Law</button>
                    <button class="btn-danger">Repeal Law</button>
                    <button class="btn-secondary">View in MDT Format</button>
                </div>
            </div>
        `;
    }

    editTax(taxId) {
        const tax = this.data.taxes.find(t => t.id === taxId);
        if (!tax) return;

        // Show confirmation modal
        this.showModal(`
            <h3>Change ${tax.name}</h3>
            <p>You are changing <strong>${tax.name}</strong> from <strong>${tax.rate}%</strong> to:</p>
            <input type="number" id="new-tax-rate" value="${tax.rate}" min="${tax.min}" max="${tax.max}" step="0.1" class="form-input">
            <p class="warning-text">⚠️ This will affect all ${tax.name.includes('Income') ? 'citizens' : 'relevant entities'}.</p>
        `, () => {
            const newRate = document.getElementById('new-tax-rate').value;
            tax.rate = parseFloat(newRate);
            this.loadPage('taxes');
            this.logAction(`Changed ${tax.name} from ${tax.rate}% to ${newRate}%`);
        });
    }

    showModal(content, onConfirm) {
        const modal = document.createElement('div');
        modal.className = 'modal-overlay';
        modal.innerHTML = `
            <div class="modal-content">
                ${content}
                <div class="modal-actions">
                    <button class="btn-secondary" onclick="this.closest('.modal-overlay').remove()">Cancel</button>
                    <button class="btn-primary" id="modal-confirm">Confirm</button>
                </div>
            </div>
        `;
        document.body.appendChild(modal);

        document.getElementById('modal-confirm').addEventListener('click', () => {
            onConfirm();
            modal.remove();
        });
    }

    logAction(action) {
        const log = {
            timestamp: new Date().toLocaleString(),
            user: this.data.mayorName,
            action: action,
            category: 'System',
            details: action
        };
        this.data.auditLog.unshift(log);
        console.log('Logged action:', action);
    }

    // Data loaders with sample data
    loadLaws() {
        return [
            { id: 1, title: 'Reckless Driving', category: 'Traffic', text: 'Operating a vehicle in a manner that endangers public safety', fine: 500, jail: 0, status: 'active' },
            { id: 2, title: 'Illegal Street Racing', category: 'Traffic', text: 'Participating in unauthorized street racing', fine: 1000, jail: 3, status: 'active' },
            { id: 3, title: 'Unlicensed Firearm Possession', category: 'Weapons', text: 'Possession of a firearm without proper licensing', fine: 2000, jail: 6, status: 'active' },
            { id: 4, title: 'Operating Without Business License', category: 'Business', text: 'Operating a business without valid city license', fine: 5000, jail: 0, status: 'draft' }
        ];
    }

    loadTaxes() {
        return [
            { id: 'income', name: 'Income Tax', rate: 4.5, min: 0, max: 10, lastChangedBy: 'Mayor Smith', lastChanged: '01/15/2026' },
            { id: 'business', name: 'Business Tax', rate: 6.0, min: 2, max: 15, lastChangedBy: 'Mayor Smith', lastChanged: '12/10/2025' },
            { id: 'property', name: 'Property Tax', rate: 1.2, min: 0.5, max: 3, lastChangedBy: 'Deputy Mayor', lastChanged: '11/20/2025' },
            { id: 'registration', name: 'Vehicle Registration', rate: 2.5, min: 1, max: 5, lastChangedBy: 'Treasurer', lastChanged: '10/05/2025' }
        ];
    }

    loadBudgets() {
        return [
            { name: 'Police Department', allocated: 500000, spent: 320000, requests: 2 },
            { name: 'EMS', allocated: 350000, spent: 280000, requests: 0 },
            { name: 'DOT', allocated: 200000, spent: 145000, requests: 1 },
            { name: 'Utilities', allocated: 180000, spent: 170000, requests: 0 },
            { name: 'Government Payroll', allocated: 300000, spent: 300000, requests: 0 }
        ];
    }

    loadLicenses() {
        // Load business licenses from config
        const licenses = [];
        const businessJobs = typeof Config !== 'undefined' && Config.BusinessManager 
            ? Config.BusinessManager.AllowedJobs 
            : {};
        
        // Demo business licenses based on configured jobs
        let id = 1;
        for (const [job, config] of Object.entries(businessJobs)) {
            const issueDate = new Date(2024, Math.floor(Math.random() * 12), Math.floor(Math.random() * 28));
            const expiryDate = new Date(issueDate);
            expiryDate.setFullYear(expiryDate.getFullYear() + 1);
            
            const daysUntilExpiry = Math.floor((expiryDate - new Date()) / (1000 * 60 * 60 * 24));
            let status = 'active';
            if (daysUntilExpiry < 0) status = 'expired';
            else if (daysUntilExpiry < 30) status = 'warning';
            
            licenses.push({
                id: `BL-${1000 + id++}`,
                holder: config.businessName,
                holderType: 'Business',
                type: 'Business License',
                businessType: config.businessType,
                issueDate: issueDate.toLocaleDateString(),
                expiryDate: expiryDate.toLocaleDateString(),
                status: status,
                daysUntilExpiry: daysUntilExpiry
            });
        }
        
        return licenses;
    }

    loadUtilities() {
        return {
            power: { active: 245, delinquent: 8, disconnected: 3 },
            water: { active: 238, delinquent: 5, disconnected: 2 }
        };
    }

    loadFines() {
        return [];
    }

    loadStaff() {
        return [
            { name: 'John Smith', position: 'Mayor', permissions: ['All'], status: 'Active' },
            { name: 'Sarah Johnson', position: 'Deputy Mayor', permissions: ['Laws', 'Budgets', 'Staff'], status: 'Active' },
            { name: 'Mike Davis', position: 'Treasurer', permissions: ['Taxes', 'Budgets', 'Fines'], status: 'Active' },
            { name: 'Emily Brown', position: 'Clerk', permissions: ['Licenses', 'Permits'], status: 'Active' },
            { name: 'Tom Wilson', position: 'Utility Manager', permissions: ['Utilities'], status: 'Active' }
        ];
    }

    loadAuditLog() {
        return [
            { timestamp: '02/17/2026 10:30 AM', user: 'Mayor Smith', action: 'Changed income tax', category: 'Taxes', details: 'Changed income tax from 4% to 4.5%' },
            { timestamp: '02/16/2026 3:45 PM', user: 'Deputy Mayor', action: 'Published new law', category: 'Laws', details: 'Published: Illegal Street Racing' },
            { timestamp: '02/15/2026 2:15 PM', user: 'Treasurer', action: 'Restored power', category: 'Utilities', details: 'Restored power to property PROP-1024' },
            { timestamp: '02/14/2026 11:00 AM', user: 'Clerk', action: 'Revoked license', category: 'Licenses', details: 'Revoked business license BL-8392' }
        ];
    }
}

// Businesses Management System
class BusinessesManager {
    constructor() {
        this.currentPage = 'overview';
        this.currentBusinessId = null;
        this.citizens = [
            { name: 'Mia Harris', citizenId: 'CID-8421' },
            { name: 'Dylan Reese', citizenId: 'CID-1134' },
            { name: 'Laura Park', citizenId: 'CID-7749' },
            { name: 'Marcus Cole', citizenId: 'CID-4920' },
            { name: 'Jordan Blake', citizenId: 'CID-2267' },
            { name: 'Taylor Quinn', citizenId: 'CID-3358' }
        ];
        this.data = {
            stats: {
                totalBusinesses: 128,
                activeBusinesses: 112,
                totalEmployees: 684,
                revenueToday: 185400,
                revenueWeek: 1287400,
                revenueMonth: 5526000,
                mostProfitable: 'Harmony Customs',
                lowestPerforming: 'Bean Machine'
            },
            alerts: {
                unpaidTaxes: 7,
                unlicensed: 3,
                incomeSpikes: 4
            },
            businesses: [
                {
                    id: 'BUS-1001',
                    name: 'Harmony Customs',
                    owner: 'Mia Harris',
                    ownerId: 'CID-8421',
                    type: 'Mechanic',
                    status: 'Open',
                    employees: 18,
                    revenueWeek: 248000,
                    licenseStatus: 'Active',
                    taxStatus: 'Current',
                    balance: 540000,
                    blip: 'Harmony Customs',
                    blipColor: 'Blue',
                    location: 'Strawberry Ave',
                    salesTotal: 985000,
                    invoices: 420,
                    avgSale: 2347,
                    peakHours: '18:00-22:00',
                    payroll: 72000,
                    wageAvg: 3200,
                    permits: ['Repair', 'Towing'],
                    taxDebt: 0,
                    warnings: [],
                    employeesList: [
                        { name: 'Alex Vega', role: 'Lead Mechanic', wage: 4200, activity: 'Active' },
                        { name: 'Sam Patel', role: 'Service Advisor', wage: 3200, activity: 'Active' },
                        { name: 'Jamie Fox', role: 'Mechanic', wage: 2800, activity: 'Active' }
                    ],
                    transactions: [
                        { date: '02/17/2026', type: 'Service', amount: 4200, note: 'Performance upgrades' },
                        { date: '02/16/2026', type: 'Repair', amount: 1650, note: 'Engine rebuild' },
                        { date: '02/15/2026', type: 'Service', amount: 850, note: 'Brake replacement' }
                    ],
                    activityLog: [
                        { date: '02/17/2026 09:20', action: 'Inspection passed', actor: 'City Inspector' },
                        { date: '02/16/2026 17:40', action: 'Tax payment recorded', actor: 'Treasury' },
                        { date: '02/15/2026 14:05', action: 'License renewed', actor: 'Mayor Office' }
                    ]
                },
                {
                    id: 'BUS-1002',
                    name: 'Burger Shot',
                    owner: 'Dylan Reese',
                    ownerId: 'CID-1134',
                    type: 'Restaurant',
                    status: 'Open',
                    employees: 42,
                    revenueWeek: 165500,
                    licenseStatus: 'Active',
                    taxStatus: 'Late',
                    balance: 320000,
                    blip: 'Burger Shot',
                    blipColor: 'Red',
                    location: 'Vespucci Blvd',
                    salesTotal: 612000,
                    invoices: 1250,
                    avgSale: 490,
                    peakHours: '12:00-14:00',
                    payroll: 96000,
                    wageAvg: 1900,
                    permits: ['Food', 'Alcohol'],
                    taxDebt: 18400,
                    warnings: ['Tax delinquency notice'],
                    employeesList: [
                        { name: 'Riley Stone', role: 'Manager', wage: 2600, activity: 'Active' },
                        { name: 'Chris Lane', role: 'Cook', wage: 1700, activity: 'Active' },
                        { name: 'Morgan Lee', role: 'Cashier', wage: 1500, activity: 'Inactive' }
                    ],
                    transactions: [
                        { date: '02/17/2026', type: 'Sales', amount: 6200, note: 'Lunch rush' },
                        { date: '02/16/2026', type: 'Sales', amount: 5400, note: 'Dinner service' },
                        { date: '02/15/2026', type: 'Sales', amount: 4900, note: 'Weekend traffic' }
                    ],
                    activityLog: [
                        { date: '02/17/2026 11:15', action: 'Late fee applied', actor: 'Treasury' },
                        { date: '02/16/2026 10:05', action: 'Compliance warning issued', actor: 'Mayor Office' },
                        { date: '02/15/2026 18:45', action: 'Tax reminder sent', actor: 'Treasury' }
                    ]
                },
                {
                    id: 'BUS-1003',
                    name: 'Bean Machine',
                    owner: 'Laura Park',
                    ownerId: 'CID-7749',
                    type: 'Cafe',
                    status: 'Closed',
                    employees: 6,
                    revenueWeek: 8400,
                    licenseStatus: 'Suspended',
                    taxStatus: 'Delinquent',
                    balance: 14000,
                    blip: 'Bean Machine',
                    blipColor: 'Green',
                    location: 'Downtown',
                    salesTotal: 85000,
                    invoices: 160,
                    avgSale: 530,
                    peakHours: '08:00-10:00',
                    payroll: 9800,
                    wageAvg: 1200,
                    permits: ['Food'],
                    taxDebt: 9200,
                    warnings: ['Operating without license'],
                    employeesList: [
                        { name: 'Dakota Reed', role: 'Barista', wage: 1100, activity: 'Inactive' },
                        { name: 'Casey Wynn', role: 'Barista', wage: 1100, activity: 'Inactive' }
                    ],
                    transactions: [
                        { date: '02/10/2026', type: 'Sales', amount: 600, note: 'Limited service' },
                        { date: '02/08/2026', type: 'Sales', amount: 450, note: 'Morning rush' }
                    ],
                    activityLog: [
                        { date: '02/14/2026 08:10', action: 'License suspended', actor: 'Mayor Office' },
                        { date: '02/12/2026 13:30', action: 'Inspection failed', actor: 'City Inspector' }
                    ]
                },
                {
                    id: 'BUS-1004',
                    name: 'Premium Deluxe Motorsport',
                    owner: 'Marcus Cole',
                    ownerId: 'CID-4920',
                    type: 'Dealership',
                    status: 'Open',
                    employees: 25,
                    revenueWeek: 312000,
                    licenseStatus: 'Active',
                    taxStatus: 'Current',
                    balance: 980000,
                    blip: 'PDM',
                    blipColor: 'Yellow',
                    location: 'Power St',
                    salesTotal: 1850000,
                    invoices: 140,
                    avgSale: 13214,
                    peakHours: '16:00-19:00',
                    payroll: 105000,
                    wageAvg: 4200,
                    permits: ['Sales', 'Test Drive'],
                    taxDebt: 0,
                    warnings: [],
                    employeesList: [
                        { name: 'Avery Shaw', role: 'Sales Lead', wage: 5200, activity: 'Active' },
                        { name: 'Quinn Hayes', role: 'Sales', wage: 3600, activity: 'Active' },
                        { name: 'Drew Scott', role: 'Finance', wage: 4100, activity: 'Active' }
                    ],
                    transactions: [
                        { date: '02/17/2026', type: 'Vehicle Sale', amount: 78000, note: 'Sports vehicle' },
                        { date: '02/16/2026', type: 'Vehicle Sale', amount: 65000, note: 'Sedan package' },
                        { date: '02/15/2026', type: 'Vehicle Sale', amount: 54000, note: 'SUV lease' }
                    ],
                    activityLog: [
                        { date: '02/17/2026 15:30', action: 'Audit completed', actor: 'Mayor Office' },
                        { date: '02/16/2026 12:00', action: 'Tax payment recorded', actor: 'Treasury' }
                    ]
                }
            ],
            auditLog: [
                { timestamp: '02/17/2026 10:15 AM', action: 'Mayor applied late fee', business: 'Burger Shot', type: 'Tax Enforcement' },
                { timestamp: '02/16/2026 04:50 PM', action: 'Mayor suspended license', business: 'Bean Machine', type: 'Compliance' },
                { timestamp: '02/16/2026 01:25 PM', action: 'Mayor renewed license', business: 'Harmony Customs', type: 'Licensing' },
                { timestamp: '02/15/2026 09:10 AM', action: 'Mayor changed business tax', business: 'All Businesses', type: 'Policy' }
            ]
        };
        this.init();
    }

    init() {
        const navItems = document.querySelectorAll('.businesses-nav-item');
        const content = document.getElementById('businesses-content');

        if (!content) return;

        navItems.forEach(item => {
            item.addEventListener('click', () => {
                navItems.forEach(nav => nav.classList.remove('active'));
                item.classList.add('active');
                const page = item.dataset.page;
                this.currentPage = page;
                this.renderPage(page, content);
            });
        });

        this.renderPage(this.currentPage, content);
    }

    renderPage(page, container) {
        const pages = {
            overview: this.renderOverview(),
            registry: this.renderRegistry(),
            details: this.renderDetailsPage(),
            analytics: this.renderAnalytics(),
            employees: this.renderEmployees(),
            compliance: this.renderCompliance(),
            taxes: this.renderTaxes(),
            audit: this.renderAuditLog(),
            settings: this.renderSettings()
        };

        if (page === 'details' && !this.currentBusinessId) {
            this.currentPage = 'registry';
            container.innerHTML = this.renderRegistry();
        } else {
            container.innerHTML = pages[page] || this.renderOverview();
        }

        if (page === 'registry') {
            this.attachRegistryHandlers(container);
        } else if (page === 'details') {
            this.attachDetailsPageHandlers(container);
        }
    }

    openBusinessDetails(businessId, container) {
        this.currentBusinessId = businessId;
        this.currentPage = 'details';
        this.renderPage('details', container);
    }

    renderOverview() {
        return `
            <div class="businesses-page">
                <div class="page-title">Business Oversight</div>
                <div class="overview-kpi-grid">
                    <div class="kpi-card">
                        <div class="kpi-label">Total Businesses</div>
                        <div class="kpi-value">${this.data.stats.totalBusinesses}</div>
                        <div class="kpi-subtext">Registered in city directory</div>
                    </div>
                    <div class="kpi-card">
                        <div class="kpi-label">Active Businesses</div>
                        <div class="kpi-value">${this.data.stats.activeBusinesses}</div>
                        <div class="kpi-subtext">Open and operating today</div>
                    </div>
                    <div class="kpi-card">
                        <div class="kpi-label">Total Employees</div>
                        <div class="kpi-value">${this.data.stats.totalEmployees}</div>
                        <div class="kpi-subtext">Across all businesses</div>
                    </div>
                    <div class="kpi-card">
                        <div class="kpi-label">Revenue This Week</div>
                        <div class="kpi-value">$${this.data.stats.revenueWeek.toLocaleString()}</div>
                        <div class="kpi-subtext">Combined gross revenue</div>
                    </div>
                </div>

                <div class="overview-grid">
                    <div class="panel-card">
                        <h3>Economic Summary</h3>
                        <div class="detail-list">
                            <div class="detail-row"><span>Revenue Today</span><strong>$${this.data.stats.revenueToday.toLocaleString()}</strong></div>
                            <div class="detail-row"><span>Revenue This Month</span><strong>$${this.data.stats.revenueMonth.toLocaleString()}</strong></div>
                            <div class="detail-row"><span>Most Profitable</span><strong>${this.data.stats.mostProfitable}</strong></div>
                            <div class="detail-row"><span>Lowest Performing</span><strong>${this.data.stats.lowestPerforming}</strong></div>
                        </div>
                    </div>
                    <div class="panel-card">
                        <h3>Compliance Risk</h3>
                        <div class="risk-list">
                            <div class="risk-item danger">${this.data.alerts.unpaidTaxes} businesses behind on tax</div>
                            <div class="risk-item warning">${this.data.alerts.unlicensed} operating without license</div>
                            <div class="risk-item warning">${this.data.alerts.incomeSpikes} suspicious income spikes</div>
                        </div>
                    </div>
                    <div class="panel-card">
                        <h3>Top Revenue Businesses</h3>
                        <table class="mini-table">
                            <tr><td>Harmony Customs</td><td>$248,000</td></tr>
                            <tr><td>PDM</td><td>$312,000</td></tr>
                            <tr><td>Burger Shot</td><td>$165,500</td></tr>
                            <tr><td>Bean Machine</td><td>$8,400</td></tr>
                        </table>
                    </div>
                    <div class="panel-card">
                        <h3>Compliance Watchlist</h3>
                        <div class="detail-list">
                            <div class="detail-row"><span>Unpaid Taxes</span><strong>7</strong></div>
                            <div class="detail-row"><span>License Suspensions</span><strong>3</strong></div>
                            <div class="detail-row"><span>Escalation Cases</span><strong>2</strong></div>
                            <div class="detail-row"><span>Inspection Queue</span><strong>5</strong></div>
                        </div>
                    </div>
                </div>

                <div class="table-container">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>Business</th>
                                <th>Issue</th>
                                <th>Owner</th>
                                <th>Status</th>
                                <th>Last Action</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr>
                                <td>Bean Machine</td>
                                <td>Operating without license</td>
                                <td>Laura Park</td>
                                <td>${this.getStatusBadge('Suspended')}</td>
                                <td>Compliance notice sent</td>
                            </tr>
                            <tr>
                                <td>Burger Shot</td>
                                <td>Tax delinquency</td>
                                <td>Dylan Reese</td>
                                <td>${this.getStatusBadge('Late')}</td>
                                <td>Late fee applied</td>
                            </tr>
                            <tr>
                                <td>Harmony Customs</td>
                                <td>Income spike review</td>
                                <td>Mia Harris</td>
                                <td>${this.getStatusBadge('Active')}</td>
                                <td>Audit scheduled</td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        `;
    }

    renderRegistry() {
        const citizenOptions = this.citizens.map(citizen => 
            `<option value="${citizen.name} (${citizen.citizenId})">${citizen.name} (${citizen.citizenId})</option>`
        ).join('');
        const rows = this.data.businesses.map(business => `
            <tr data-business-id="${business.id}">
                <td>${business.name}</td>
                <td>${business.owner}</td>
                <td>${business.type}</td>
                <td>${this.getStatusBadge(business.status)}</td>
                <td>${business.employees}</td>
                <td>$${business.revenueWeek.toLocaleString()}</td>
                <td>${this.getStatusBadge(business.licenseStatus)}</td>
                <td>${this.getStatusBadge(business.taxStatus)}</td>
                <td>
                    <div class="action-menu">
                        <button class="kebab-btn" data-menu-toggle="${business.id}">⋯</button>
                        <div class="action-dropdown" data-menu="${business.id}">
                            <button class="action-item" data-action="view" data-business-id="${business.id}">View Details</button>
                            <button class="action-item" data-action="transfer" data-business-id="${business.id}">Transfer Ownership</button>
                            <button class="action-item" data-action="remove" data-business-id="${business.id}">Remove Owner</button>
                        </div>
                    </div>
                </td>
            </tr>
        `).join('');

        return `
            <div class="businesses-page">
                <div class="page-title">Business Registry</div>
                <div class="create-business-card">
                    <h3>Create Business</h3>
                    <div class="create-business-grid">
                        <div class="form-group">
                            <label>Business Name</label>
                            <input type="text" class="form-input" id="create-business-name" placeholder="Business name">
                        </div>
                        <div class="form-group">
                            <label>Owner</label>
                            <select class="form-input" id="create-business-owner">
                                <option value="">Select citizen</option>
                                ${citizenOptions}
                            </select>
                        </div>
                        <div class="form-group">
                            <label>Type</label>
                            <select class="form-input" id="create-business-type">
                                <option>Mechanic</option>
                                <option>Restaurant</option>
                                <option>Cafe</option>
                                <option>Dealership</option>
                                <option>Retail</option>
                            </select>
                        </div>
                        <div class="form-group">
                            <label>Location</label>
                            <input type="text" class="form-input" id="create-business-location" placeholder="District or address">
                        </div>
                    </div>
                    <button class="btn-primary" id="create-business-btn">Create Business</button>
                </div>
                <div class="filter-bar">
                    <input type="text" class="search-input" placeholder="Search businesses by name or owner">
                    <select class="setting-select">
                        <option>All Types</option>
                        <option>Mechanic</option>
                        <option>Restaurant</option>
                        <option>Cafe</option>
                        <option>Dealership</option>
                    </select>
                    <select class="setting-select">
                        <option>All Status</option>
                        <option>Open</option>
                        <option>Closed</option>
                    </select>
                    <button class="btn-secondary">Export Report</button>
                    <button class="btn-primary">Open Compliance Review</button>
                </div>
                <div class="registry-layout">
                    <div class="table-container">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>Business</th>
                                    <th>Owner</th>
                                    <th>Type</th>
                                    <th>Status</th>
                                    <th>Employees</th>
                                    <th>Revenue (Week)</th>
                                    <th>License</th>
                                    <th>Tax Status</th>
                                    <th>Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${rows}
                            </tbody>
                        </table>
                    </div>
                    <div class="business-details-panel" id="business-details-panel">
                        ${this.renderBusinessDetails(this.data.businesses[0])}
                    </div>
                </div>
            </div>
        `;
    }

    renderBusinessDetails(business) {
        return `
            <div class="details-header">
                <h3>${business.name}</h3>
                <div class="details-subtitle">${business.type} - ${business.status}</div>
            </div>
            <div class="details-tabs">
                <button class="details-tab active" data-tab="overview">Overview</button>
                <button class="details-tab" data-tab="performance">Performance</button>
                <button class="details-tab" data-tab="employees">Employees</button>
                <button class="details-tab" data-tab="compliance">Compliance</button>
            </div>
            <div class="details-section active" data-tab-content="overview">
                <div class="detail-row"><span>Owner</span><strong>${business.owner}</strong></div>
                <div class="detail-row"><span>Location</span><strong>${business.location}</strong></div>
                <div class="detail-row"><span>Blip</span><strong>${business.blip} (${business.blipColor})</strong></div>
                <div class="detail-row"><span>Balance</span><strong>$${business.balance.toLocaleString()}</strong></div>
            </div>
            <div class="details-section" data-tab-content="performance">
                <div class="detail-row"><span>Sales Total</span><strong>$${business.salesTotal.toLocaleString()}</strong></div>
                <div class="detail-row"><span>Invoices</span><strong>${business.invoices}</strong></div>
                <div class="detail-row"><span>Average Sale</span><strong>$${business.avgSale.toLocaleString()}</strong></div>
                <div class="detail-row"><span>Peak Hours</span><strong>${business.peakHours}</strong></div>
            </div>
            <div class="details-section" data-tab-content="employees">
                <div class="detail-row"><span>Employee Count</span><strong>${business.employees}</strong></div>
                <div class="detail-row"><span>Average Wage</span><strong>$${business.wageAvg.toLocaleString()}</strong></div>
                <div class="detail-row"><span>Total Payroll</span><strong>$${business.payroll.toLocaleString()}</strong></div>
            </div>
            <div class="details-section" data-tab-content="compliance">
                <div class="detail-row"><span>License</span><strong>${business.licenseStatus}</strong></div>
                <div class="detail-row"><span>Tax Status</span><strong>${business.taxStatus}</strong></div>
                <div class="detail-row"><span>Permits</span><strong>${business.permits.join(', ')}</strong></div>
                <div class="detail-row"><span>Warnings</span><strong>${business.warnings.length ? business.warnings.join(', ') : 'None'}</strong></div>
            </div>
        `;
    }

    renderDetailsPage() {
        const business = this.data.businesses.find(item => item.id === this.currentBusinessId);
        if (!business) {
            return `
                <div class="business-details-page">
                    <div class="page-title">Business Details</div>
                    <p class="text-muted">Select a business from the registry.</p>
                </div>
            `;
        }

        const transactions = business.transactions.map(tx => `
            <tr>
                <td>${tx.date}</td>
                <td>${tx.type}</td>
                <td>$${tx.amount.toLocaleString()}</td>
                <td>${tx.note}</td>
            </tr>
        `).join('');

        const employees = business.employeesList.map(emp => `
            <tr>
                <td>${emp.name}</td>
                <td>${emp.role}</td>
                <td>$${emp.wage.toLocaleString()}</td>
                <td>${emp.activity}</td>
            </tr>
        `).join('');

        const activity = business.activityLog.map(entry => `
            <tr>
                <td>${entry.date}</td>
                <td>${entry.action}</td>
                <td>${entry.actor}</td>
            </tr>
        `).join('');

        return `
            <div class="business-details-page">
                <div class="details-hero">
                    <button class="btn-secondary" id="back-to-registry">Back to Registry</button>
                    <div>
                        <div class="page-title">${business.name}</div>
                        <div class="details-subtitle">${business.type} • ${business.status} • Owner: ${business.owner}</div>
                    </div>
                    <div class="details-actions">
                        ${business.owner === 'Unassigned' 
                            ? `<button class="btn-primary" data-action="assign" data-business-id="${business.id}">Assign Owner</button>`
                            : `
                                <button class="btn-secondary" data-action="transfer" data-business-id="${business.id}">Transfer Ownership</button>
                                <button class="btn-secondary" data-action="remove" data-business-id="${business.id}">Remove Owner</button>
                            `
                        }
                    </div>
                </div>

                <div class="details-grid">
                    <div class="panel-card">
                        <h3>Business Profile</h3>
                        <div class="detail-list">
                            <div class="detail-row"><span>Owner</span><strong>${business.owner}</strong></div>
                            <div class="detail-row"><span>Citizen ID</span><strong>${business.ownerId || 'N/A'}</strong></div>
                            <div class="detail-row"><span>Location</span><strong>${business.location}</strong></div>
                            <div class="detail-row"><span>Balance</span><strong>$${business.balance.toLocaleString()}</strong></div>
                            <div class="detail-row"><span>Blip</span><strong>${business.blip} (${business.blipColor})</strong></div>
                        </div>
                    </div>
                    <div class="panel-card">
                        <h3>Performance</h3>
                        <div class="detail-list">
                            <div class="detail-row"><span>Sales Total</span><strong>$${business.salesTotal.toLocaleString()}</strong></div>
                            <div class="detail-row"><span>Invoices</span><strong>${business.invoices}</strong></div>
                            <div class="detail-row"><span>Avg Sale</span><strong>$${business.avgSale.toLocaleString()}</strong></div>
                            <div class="detail-row"><span>Peak Hours</span><strong>${business.peakHours}</strong></div>
                        </div>
                    </div>
                    <div class="panel-card">
                        <h3>Compliance</h3>
                        <div class="detail-list">
                            <div class="detail-row"><span>License</span><strong>${business.licenseStatus}</strong></div>
                            <div class="detail-row"><span>Tax Status</span><strong>${business.taxStatus}</strong></div>
                            <div class="detail-row"><span>Permits</span><strong>${business.permits.join(', ') || 'None'}</strong></div>
                            <div class="detail-row"><span>Warnings</span><strong>${business.warnings.length ? business.warnings.join(', ') : 'None'}</strong></div>
                        </div>
                    </div>
                </div>

                <div class="details-section-block">
                    <h3>Transactions</h3>
                    <div class="table-container">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>Date</th>
                                    <th>Type</th>
                                    <th>Amount</th>
                                    <th>Note</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${transactions || `<tr><td colspan="4">No transactions recorded</td></tr>`}
                            </tbody>
                        </table>
                    </div>
                </div>

                <div class="details-section-block">
                    <h3>Employees</h3>
                    <div class="table-container">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>Name</th>
                                    <th>Role</th>
                                    <th>Wage</th>
                                    <th>Activity</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${employees || `<tr><td colspan="4">No employees listed</td></tr>`}
                            </tbody>
                        </table>
                    </div>
                </div>

                <div class="details-section-block">
                    <h3>Activity Log</h3>
                    <div class="table-container">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>Date</th>
                                    <th>Activity</th>
                                    <th>Actor</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${activity || `<tr><td colspan="3">No activity recorded</td></tr>`}
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
        `;
    }

    attachDetailsPageHandlers(container) {
        const backBtn = container.querySelector('#back-to-registry');
        if (backBtn) {
            backBtn.addEventListener('click', () => {
                this.currentPage = 'registry';
                this.renderPage('registry', container);
            });
        }

        container.querySelectorAll('[data-action="assign"]').forEach(btn => {
            btn.addEventListener('click', () => {
                const businessId = btn.dataset.businessId;
                const business = this.data.businesses.find(item => item.id === businessId);
                if (!business) return;

                this.showModal(`
                    <h3>Assign Owner</h3>
                    <p>Assign an owner to <strong>${business.name}</strong>:</p>
                    <select class="form-input" id="assign-owner">
                        ${this.citizens.map(citizen => `<option value="${citizen.name} (${citizen.citizenId})">${citizen.name} (${citizen.citizenId})</option>`).join('')}
                    </select>
                `, () => {
                    const newOwner = document.getElementById('assign-owner').value;
                    if (newOwner) {
                        business.owner = newOwner;
                        business.ownerId = newOwner.match(/\(([^)]+)\)/)?.[1] || '';
                        this.renderPage('details', container);
                    }
                });
            });
        });

        container.querySelectorAll('[data-action="transfer"]').forEach(btn => {
            btn.addEventListener('click', () => {
                const businessId = btn.dataset.businessId;
                const business = this.data.businesses.find(item => item.id === businessId);
                if (!business) return;

                this.showModal(`
                    <h3>Transfer Ownership</h3>
                    <p>Transfer <strong>${business.name}</strong> to:</p>
                    <select class="form-input" id="transfer-owner">
                        ${this.citizens.map(citizen => `<option value="${citizen.name} (${citizen.citizenId})">${citizen.name} (${citizen.citizenId})</option>`).join('')}
                    </select>
                `, () => {
                    const newOwner = document.getElementById('transfer-owner').value;
                    if (newOwner) {
                        business.owner = newOwner;
                        business.ownerId = newOwner.match(/\(([^)]+)\)/)?.[1] || business.ownerId;
                        this.renderPage('details', container);
                    }
                });
            });
        });

        container.querySelectorAll('[data-action="remove"]').forEach(btn => {
            btn.addEventListener('click', () => {
                const businessId = btn.dataset.businessId;
                const business = this.data.businesses.find(item => item.id === businessId);
                if (!business) return;

                this.showModal(`
                    <h3>Remove Owner</h3>
                    <p class="warning-text">Remove current owner from <strong>${business.name}</strong>?</p>
                `, () => {
                    business.owner = 'Unassigned';
                    business.ownerId = '';
                    this.renderPage('details', container);
                });
            });
        });
    }

    showModal(content, onConfirm) {
        const modal = document.createElement('div');
        modal.className = 'modal-overlay';
        modal.innerHTML = `
            <div class="modal-content">
                ${content}
                <div class="modal-actions">
                    <button class="btn-secondary" onclick="this.closest('.modal-overlay').remove()">Cancel</button>
                    <button class="btn-primary" id="modal-confirm">Confirm</button>
                </div>
            </div>
        `;
        document.body.appendChild(modal);

        document.getElementById('modal-confirm').addEventListener('click', () => {
            onConfirm();
            modal.remove();
        });
    }

    renderAnalytics() {
        return `
            <div class="businesses-page">
                <div class="page-title">Business Analytics</div>
                <div class="filter-bar">
                    <select class="analytics-filter">
                        <option>Last 7 Days</option>
                        <option>Last 30 Days</option>
                        <option>Last 90 Days</option>
                        <option>Year to Date</option>
                        <option>All Time</option>
                    </select>
                    <select class="analytics-filter">
                        <option>All Types</option>
                        <option>Mechanic</option>
                        <option>Restaurant</option>
                        <option>Dealership</option>
                        <option>Retail</option>
                    </select>
                    <select class="analytics-filter">
                        <option>All Districts</option>
                        <option>Downtown</option>
                        <option>Vespucci</option>
                        <option>Strawberry</option>
                        <option>Sandy Shores</option>
                    </select>
                    <button class="btn-primary">Export</button>
                </div>
                
                <div class="analytics-kpi-grid">
                    <div class="analytics-kpi-card">
                        <div class="kpi-icon" style="background: var(--success-bg); color: var(--success);">
                            <span>$</span>
                        </div>
                        <div>
                            <div class="kpi-label">Total Revenue</div>
                            <div class="kpi-value">$1.2M</div>
                            <div class="kpi-change positive">+12.5% vs last period</div>
                        </div>
                    </div>
                    <div class="analytics-kpi-card">
                        <div class="kpi-icon" style="background: var(--info-bg); color: var(--info);">
                            <span>📊</span>
                        </div>
                        <div>
                            <div class="kpi-label">Active Businesses</div>
                            <div class="kpi-value">47</div>
                            <div class="kpi-change positive">+3 new this month</div>
                        </div>
                    </div>
                    <div class="analytics-kpi-card">
                        <div class="kpi-icon" style="background: var(--warning-bg); color: var(--warning);">
                            <span>👥</span>
                        </div>
                        <div>
                            <div class="kpi-label">Employment</div>
                            <div class="kpi-value">284</div>
                            <div class="kpi-change">$282k total payroll</div>
                        </div>
                    </div>
                    <div class="analytics-kpi-card">
                        <div class="kpi-icon" style="background: var(--danger-bg); color: var(--danger);">
                            <span>⚠</span>
                        </div>
                        <div>
                            <div class="kpi-label">Compliance Issues</div>
                            <div class="kpi-value">5</div>
                            <div class="kpi-change negative">+2 since last week</div>
                        </div>
                    </div>
                </div>

                <div class="analytics-charts-grid">
                    <div class="analytics-chart-card full-width">
                        <div class="chart-header">
                            <h3>Revenue Trend (30 Days)</h3>
                            <div class="chart-legend">
                                <span class="legend-item"><span class="legend-dot" style="background: var(--primary);"></span> Revenue</span>
                                <span class="legend-item"><span class="legend-dot" style="background: var(--accent);"></span> Expenses</span>
                            </div>
                        </div>
                        <div class="line-chart">
                            <div class="line-chart-bars">
                                <div class="line-chart-bar" style="height: 40%"><span class="bar-tooltip">$42k</span></div>
                                <div class="line-chart-bar" style="height: 55%"><span class="bar-tooltip">$58k</span></div>
                                <div class="line-chart-bar" style="height: 50%"><span class="bar-tooltip">$52k</span></div>
                                <div class="line-chart-bar" style="height: 65%"><span class="bar-tooltip">$68k</span></div>
                                <div class="line-chart-bar" style="height: 70%"><span class="bar-tooltip">$74k</span></div>
                                <div class="line-chart-bar" style="height: 60%"><span class="bar-tooltip">$63k</span></div>
                                <div class="line-chart-bar" style="height: 75%"><span class="bar-tooltip">$78k</span></div>
                                <div class="line-chart-bar" style="height: 80%"><span class="bar-tooltip">$84k</span></div>
                                <div class="line-chart-bar" style="height: 85%"><span class="bar-tooltip">$89k</span></div>
                                <div class="line-chart-bar" style="height: 78%"><span class="bar-tooltip">$82k</span></div>
                            </div>
                            <div class="chart-x-labels">
                                <span>Week 1</span><span>Week 2</span><span>Week 3</span><span>Week 4</span>
                            </div>
                        </div>
                    </div>

                    <div class="analytics-chart-card">
                        <h3>Revenue by Business Type</h3>
                        <div class="chart-list">
                            <div class="chart-row">
                                <span class="chart-label">Mechanic</span>
                                <div class="chart-bar-container">
                                    <div class="chart-bar-fill" style="width: 80%; background: var(--primary);"></div>
                                </div>
                                <span class="chart-value">$420k</span>
                            </div>
                            <div class="chart-row">
                                <span class="chart-label">Dealership</span>
                                <div class="chart-bar-container">
                                    <div class="chart-bar-fill" style="width: 65%; background: var(--accent);"></div>
                                </div>
                                <span class="chart-value">$350k</span>
                            </div>
                            <div class="chart-row">
                                <span class="chart-label">Restaurant</span>
                                <div class="chart-bar-container">
                                    <div class="chart-bar-fill" style="width: 45%; background: var(--info);"></div>
                                </div>
                                <span class="chart-value">$220k</span>
                            </div>
                            <div class="chart-row">
                                <span class="chart-label">Retail</span>
                                <div class="chart-bar-container">
                                    <div class="chart-bar-fill" style="width: 30%; background: var(--warning);"></div>
                                </div>
                                <span class="chart-value">$140k</span>
                            </div>
                            <div class="chart-row">
                                <span class="chart-label">Other</span>
                                <div class="chart-bar-container">
                                    <div class="chart-bar-fill" style="width: 20%; background: var(--text-muted);"></div>
                                </div>
                                <span class="chart-value">$70k</span>
                            </div>
                        </div>
                    </div>

                    <div class="analytics-chart-card">
                        <h3>Top 5 Businesses</h3>
                        <div class="top-list">
                            <div class="top-list-item">
                                <div class="top-rank">1</div>
                                <div class="top-info">
                                    <div class="top-name">Harmony Customs</div>
                                    <div class="top-meta">Mechanic • $120k revenue</div>
                                </div>
                            </div>
                            <div class="top-list-item">
                                <div class="top-rank">2</div>
                                <div class="top-info">
                                    <div class="top-name">PDM</div>
                                    <div class="top-meta">Dealership • $105k revenue</div>
                                </div>
                            </div>
                            <div class="top-list-item">
                                <div class="top-rank">3</div>
                                <div class="top-info">
                                    <div class="top-name">Burger Shot</div>
                                    <div class="top-meta">Restaurant • $96k revenue</div>
                                </div>
                            </div>
                            <div class="top-list-item">
                                <div class="top-rank">4</div>
                                <div class="top-info">
                                    <div class="top-name">LS Customs</div>
                                    <div class="top-meta">Mechanic • $88k revenue</div>
                                </div>
                            </div>
                            <div class="top-list-item">
                                <div class="top-rank">5</div>
                                <div class="top-info">
                                    <div class="top-name">Ammunation</div>
                                    <div class="top-meta">Retail • $72k revenue</div>
                                </div>
                            </div>
                        </div>
                    </div>

                    <div class="analytics-chart-card">
                        <h3>District Performance</h3>
                        <div class="donut-chart-container">
                            <div class="donut-stats">
                                <div class="donut-stat">
                                    <span class="donut-dot" style="background: var(--primary);"></span>
                                    <span>Downtown</span>
                                    <strong>42%</strong>
                                </div>
                                <div class="donut-stat">
                                    <span class="donut-dot" style="background: var(--accent);"></span>
                                    <span>Vespucci</span>
                                    <strong>28%</strong>
                                </div>
                                <div class="donut-stat">
                                    <span class="donut-dot" style="background: var(--info);"></span>
                                    <span>Strawberry</span>
                                    <strong>18%</strong>
                                </div>
                                <div class="donut-stat">
                                    <span class="donut-dot" style="background: var(--warning);"></span>
                                    <span>Sandy Shores</span>
                                    <strong>12%</strong>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        `;
    }

    renderEmployees() {
        return `
            <div class="businesses-page">
                <div class="page-title">Employees Overview</div>
                <div class="dashboard-cards">
                    <div class="dash-card">
                        <div>
                            <div class="dash-card-label">Total Employed</div>
                            <div class="dash-card-value">${this.data.stats.totalEmployees}</div>
                        </div>
                    </div>
                    <div class="dash-card">
                        <div>
                            <div class="dash-card-label">Businesses with Most Staff</div>
                            <div class="dash-card-value">Burger Shot</div>
                        </div>
                    </div>
                    <div class="dash-card">
                        <div>
                            <div class="dash-card-label">High Wage Alerts</div>
                            <div class="dash-card-value">3</div>
                        </div>
                    </div>
                    <div class="dash-card">
                        <div>
                            <div class="dash-card-label">Zero Staff Flags</div>
                            <div class="dash-card-value">2</div>
                        </div>
                    </div>
                </div>
                <div class="table-container">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>Business</th>
                                <th>Employees</th>
                                <th>Average Wage</th>
                                <th>Total Payroll</th>
                                <th>Notes</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr>
                                <td>Harmony Customs</td>
                                <td>18</td>
                                <td>$3,200</td>
                                <td>$72,000</td>
                                <td>Normal</td>
                            </tr>
                            <tr>
                                <td>Burger Shot</td>
                                <td>42</td>
                                <td>$1,900</td>
                                <td>$96,000</td>
                                <td>Most staff</td>
                            </tr>
                            <tr>
                                <td>Bean Machine</td>
                                <td>6</td>
                                <td>$1,200</td>
                                <td>$9,800</td>
                                <td>Under review</td>
                            </tr>
                            <tr>
                                <td>PDM</td>
                                <td>25</td>
                                <td>$4,200</td>
                                <td>$105,000</td>
                                <td>High wages</td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        `;
    }

    renderCompliance() {
        return `
            <div class="businesses-page">
                <div class="compliance-header">
                    <h1 class="page-title">Business Compliance</h1>
                    <div class="header-actions">
                        <button class="btn-primary">Issue Compliance Notice</button>
                        <button class="btn-secondary">Generate Report</button>
                    </div>
                </div>

                <div class="compliance-dashboard">
                    <div class="compliance-kpi">
                        <div class="compliance-gauge">
                            <div class="gauge-value" style="color: var(--success);">91%</div>
                            <div class="gauge-label">Compliance Rate</div>
                        </div>
                    </div>
                    <div class="compliance-stats">
                        <div class="compliance-stat-item">
                            <div class="stat-icon" style="background: var(--success-bg); color: var(--success);">✓</div>
                            <div>
                                <div class="stat-value">108</div>
                                <div class="stat-label">Fully Compliant</div>
                            </div>
                        </div>
                        <div class="compliance-stat-item">
                            <div class="stat-icon" style="background: var(--warning-bg); color: var(--warning);">⚠</div>
                            <div>
                                <div class="stat-value">9</div>
                                <div class="stat-label">Minor Issues</div>
                            </div>
                        </div>
                        <div class="compliance-stat-item">
                            <div class="stat-icon" style="background: var(--danger-bg); color: var(--danger);">✕</div>
                            <div>
                                <div class="stat-value">5</div>
                                <div class="stat-label">Non-Compliant</div>
                            </div>
                        </div>
                    </div>
                </div>

                <div class="compliance-filters">
                    <select class="filter-select">
                        <option>All Businesses</option>
                        <option>Fully Compliant</option>
                        <option>Minor Issues</option>
                        <option>Non-Compliant</option>
                    </select>
                    <select class="filter-select">
                        <option>All Types</option>
                        <option>Mechanic</option>
                        <option>Restaurant</option>
                        <option>Dealership</option>
                        <option>Retail</option>
                    </select>
                    <input type="text" placeholder="Search businesses..." class="search-input">
                </div>

                <div class="compliance-table-container">
                    <table class="data-table compliance-table">
                        <thead>
                            <tr>
                                <th>Business</th>
                                <th>License</th>
                                <th>Permits</th>
                                <th>Tax Status</th>
                                <th>Health/Safety</th>
                                <th>Compliance Score</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr class="compliance-row compliant">
                                <td>
                                    <div class="business-cell">
                                        <strong>Harmony Customs</strong>
                                        <span>Mechanic • Downtown</span>
                                    </div>
                                </td>
                                <td><span class="status-badge active">Active</span></td>
                                <td><span class="permits-chip">Repair, Towing</span></td>
                                <td><span class="status-badge active">Current</span></td>
                                <td><span class="status-badge active">Pass</span></td>
                                <td>
                                    <div class="compliance-score">
                                        <div class="score-bar" style="width: 100%; background: var(--success);"></div>
                                        <span class="score-text">100%</span>
                                    </div>
                                </td>
                                <td>
                                    <button class="btn-icon" title="View Details">👁</button>
                                    <button class="btn-icon" title="Audit">📋</button>
                                </td>
                            </tr>
                            <tr class="compliance-row warning">
                                <td>
                                    <div class="business-cell">
                                        <strong>Burger Shot</strong>
                                        <span>Restaurant • Strawberry</span>
                                    </div>
                                </td>
                                <td><span class="status-badge active">Active</span></td>
                                <td><span class="permits-chip">Food, Alcohol</span></td>
                                <td><span class="status-badge warning">Late</span></td>
                                <td><span class="status-badge active">Pass</span></td>
                                <td>
                                    <div class="compliance-score">
                                        <div class="score-bar" style="width: 75%; background: var(--warning);"></div>
                                        <span class="score-text">75%</span>
                                    </div>
                                </td>
                                <td>
                                    <button class="btn-icon" title="View Details">👁</button>
                                    <button class="btn-icon" title="Send Notice">📧</button>
                                </td>
                            </tr>
                            <tr class="compliance-row danger">
                                <td>
                                    <div class="business-cell">
                                        <strong>Bean Machine</strong>
                                        <span>Cafe • Vespucci</span>
                                    </div>
                                </td>
                                <td><span class="status-badge error">Suspended</span></td>
                                <td><span class="permits-chip">Food</span></td>
                                <td><span class="status-badge error">Delinquent</span></td>
                                <td><span class="status-badge error">Fail</span></td>
                                <td>
                                    <div class="compliance-score">
                                        <div class="score-bar" style="width: 30%; background: var(--danger);"></div>
                                        <span class="score-text">30%</span>
                                    </div>
                                </td>
                                <td>
                                    <button class="btn-icon" title="View Details">👁</button>
                                    <button class="btn-icon" title="Enforcement Action">⚠</button>
                                </td>
                            </tr>
                            <tr class="compliance-row compliant">
                                <td>
                                    <div class="business-cell">
                                        <strong>PDM</strong>
                                        <span>Dealership • Downtown</span>
                                    </div>
                                </td>
                                <td><span class="status-badge active">Active</span></td>
                                <td><span class="permits-chip">Sales, Finance</span></td>
                                <td><span class="status-badge active">Current</span></td>
                                <td><span class="status-badge active">Pass</span></td>
                                <td>
                                    <div class="compliance-score">
                                        <div class="score-bar" style="width: 95%; background: var(--success);"></div>
                                        <span class="score-text">95%</span>
                                    </div>
                                </td>
                                <td>
                                    <button class="btn-icon" title="View Details">👁</button>
                                    <button class="btn-icon" title="Audit">📋</button>
                                </td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        `;
    }

    renderTaxes() {
        return `
            <div class="businesses-page">
                <div class="taxes-header">
                    <h1 class="page-title">Business Taxes & Revenue</h1>
                    <div class="header-actions">
                        <button class="btn-primary">Generate Tax Report</button>
                        <button class="btn-secondary">Send Payment Reminders</button>
                    </div>
                </div>

                <div class="taxes-dashboard-grid">
                    <div class="taxes-summary-card">
                        <div class="summary-header">
                            <h3>Revenue Summary</h3>
                            <select class="period-select">
                                <option>This Month</option>
                                <option>This Quarter</option>
                                <option>This Year</option>
                                <option>Year to Date</option>
                            </select>
                        </div>
                        <div class="summary-metric-grid">
                            <div class="summary-metric">
                                <div class="metric-icon" style="background: var(--success-bg); color: var(--success);">$</div>
                                <div>
                                    <div class="metric-label">Total Collected</div>
                                    <div class="metric-value">$1,245,000</div>
                                    <div class="metric-trend positive">+8.2% vs last month</div>
                                </div>
                            </div>
                            <div class="summary-metric">
                                <div class="metric-icon" style="background: var(--warning-bg); color: var(--warning);">💰</div>
                                <div>
                                    <div class="metric-label">Outstanding</div>
                                    <div class="metric-value">$62,000</div>
                                    <div class="metric-trend">17 businesses</div>
                                </div>
                            </div>
                            <div class="summary-metric">
                                <div class="metric-icon" style="background: var(--info-bg); color: var(--info);">📈</div>
                                <div>
                                    <div class="metric-label">Average Tax Rate</div>
                                    <div class="metric-value">7.2%</div>
                                    <div class="metric-trend">Across all businesses</div>
                                </div>
                            </div>
                            <div class="summary-metric">
                                <div class="metric-icon" style="background: var(--danger-bg); color: var(--danger);">⚠</div>
                                <div>
                                    <div class="metric-label">Delinquent</div>
                                    <div class="metric-value">$24,600</div>
                                    <div class="metric-trend negative">5 businesses overdue >30 days</div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>

                <div class="taxes-viz-grid">
                    <div class="taxes-chart-card">
                        <h3>Revenue Collection Trend</h3>
                        <div class="revenue-chart">
                            <div class="revenue-bars">
                                <div class="revenue-bar" style="height: 65%"><span class="bar-label">$72k</span></div>
                                <div class="revenue-bar" style="height: 72%"><span class="bar-label">$84k</span></div>
                                <div class="revenue-bar" style="height: 68%"><span class="bar-label">$78k</span></div>
                                <div class="revenue-bar" style="height: 80%"><span class="bar-label">$92k</span></div>
                                <div class="revenue-bar" style="height: 85%"><span class="bar-label">$98k</span></div>
                                <div class="revenue-bar" style="height: 90%"><span class="bar-label">$105k</span></div>
                            </div>
                            <div class="revenue-x-labels">
                                <span>Jan</span><span>Feb</span><span>Mar</span><span>Apr</span><span>May</span><span>Jun</span>
                            </div>
                        </div>
                    </div>

                    <div class="taxes-chart-card">
                        <h3>Top Tax Contributors</h3>
                        <div class="contributors-list">
                            <div class="contributor-item">
                                <span class="contributor-rank">1</span>
                                <div class="contributor-info">
                                    <div class="contributor-name">PDM</div>
                                    <div class="contributor-meta">Dealership • 8.5% rate</div>
                                </div>
                                <div class="contributor-amount">$42,500</div>
                            </div>
                            <div class="contributor-item">
                                <span class="contributor-rank">2</span>
                                <div class="contributor-info">
                                    <div class="contributor-name">Harmony Customs</div>
                                    <div class="contributor-meta">Mechanic • 7% rate</div>
                                </div>
                                <div class="contributor-amount">$38,200</div>
                            </div>
                            <div class="contributor-item">
                                <span class="contributor-rank">3</span>
                                <div class="contributor-info">
                                    <div class="contributor-name">Burger Shot</div>
                                    <div class="contributor-meta">Restaurant • 7% rate</div>
                                </div>
                                <div class="contributor-amount">$28,100</div>
                            </div>
                            <div class="contributor-item">
                                <span class="contributor-rank">4</span>
                                <div class="contributor-info">
                                    <div class="contributor-name">Ammunation</div>
                                    <div class="contributor-meta">Retail • 9% rate</div>
                                </div>
                                <div class="contributor-amount">$24,800</div>
                            </div>
                            <div class="contributor-item">
                                <span class="contributor-rank">5</span>
                                <div class="contributor-info">
                                    <div class="contributor-name">LS Customs</div>
                                    <div class="contributor-meta">Mechanic • 7% rate</div>
                                </div>
                                <div class="contributor-amount">$22,600</div>
                            </div>
                        </div>
                    </div>
                </div>

                <div class="taxes-filters">
                    <input type="text" placeholder="Search businesses..." class="search-input">
                    <select class="filter-select">
                        <option>All Payment Status</option>
                        <option>Current</option>
                        <option>Late (1-30 days)</option>
                        <option>Delinquent (>30 days)</option>
                    </select>
                    <select class="filter-select">
                        <option>All Types</option>
                        <option>Mechanic</option>
                        <option>Restaurant</option>
                        <option>Dealership</option>
                        <option>Retail</option>
                    </select>
                </div>

                <div class="taxes-table-container">
                    <table class="data-table taxes-table">
                        <thead>
                            <tr>
                                <th>Business</th>
                                <th>Tax Rate</th>
                                <th>Monthly Revenue</th>
                                <th>Tax Due</th>
                                <th>Paid This Month</th>
                                <th>Outstanding</th>
                                <th>Status</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr class="tax-row current">
                                <td>
                                    <div class="business-cell">
                                        <strong>Harmony Customs</strong>
                                        <span>Mechanic • Downtown</span>
                                    </div>
                                </td>
                                <td><strong>7%</strong></td>
                                <td>$545,000</td>
                                <td>$38,150</td>
                                <td class="paid-amount">$38,150</td>
                                <td class="outstanding-zero">$0</td>
                                <td><span class="status-badge active">Current</span></td>
                                <td>
                                    <button class="btn-icon" title="View History">📊</button>
                                    <button class="btn-icon" title="Generate Invoice">📄</button>
                                </td>
                            </tr>
                            <tr class="tax-row late">
                                <td>
                                    <div class="business-cell">
                                        <strong>Burger Shot</strong>
                                        <span>Restaurant • Strawberry</span>
                                    </div>
                                </td>
                                <td><strong>7%</strong></td>
                                <td>$401,000</td>
                                <td>$28,070</td>
                                <td class="paid-amount">$18,000</td>
                                <td class="outstanding-late">$10,070</td>
                                <td><span class="status-badge warning">Late (12 days)</span></td>
                                <td>
                                    <button class="btn-icon" title="Send Reminder">📧</button>
                                    <button class="btn-icon" title="Apply Late Fee">💰</button>
                                </td>
                            </tr>
                            <tr class="tax-row delinquent">
                                <td>
                                    <div class="business-cell">
                                        <strong>Bean Machine</strong>
                                        <span>Cafe • Vespucci</span>
                                    </div>
                                </td>
                                <td><strong>7%</strong></td>
                                <td>$132,000</td>
                                <td>$9,240</td>
                                <td class="paid-amount">$0</td>
                                <td class="outstanding-delinquent">$9,240</td>
                                <td><span class="status-badge error">Delinquent (42 days)</span></td>
                                <td>
                                    <button class="btn-icon" title="Enforcement Action">⚠</button>
                                    <button class="btn-icon" title="Revoke License">🚫</button>
                                </td>
                            </tr>
                            <tr class="tax-row current">
                                <td>
                                    <div class="business-cell">
                                        <strong>PDM</strong>
                                        <span>Dealership • Downtown</span>
                                    </div>
                                </td>
                                <td><strong>8.5%</strong></td>
                                <td>$500,000</td>
                                <td>$42,500</td>
                                <td class="paid-amount">$42,500</td>
                                <td class="outstanding-zero">$0</td>
                                <td><span class="status-badge active">Current</span></td>
                                <td>
                                    <button class="btn-icon" title="View History">📊</button>
                                    <button class="btn-icon" title="Generate Invoice">📄</button>
                                </td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        `;
    }

    renderAuditLog() {
        const rows = this.data.auditLog.map(entry => `
            <tr>
                <td>${entry.timestamp}</td>
                <td>${entry.action}</td>
                <td>${entry.business}</td>
                <td>${entry.type}</td>
            </tr>
        `).join('');

        return `
            <div class="businesses-page">
                <div class="page-title">Audit Log</div>
                <div class="filter-bar">
                    <input type="text" class="search-input" placeholder="Filter by business or action">
                    <select class="setting-select">
                        <option>All Actions</option>
                        <option>Compliance</option>
                        <option>Tax Enforcement</option>
                        <option>Licensing</option>
                        <option>Policy</option>
                    </select>
                    <select class="setting-select">
                        <option>Last 7 Days</option>
                        <option>Last 30 Days</option>
                        <option>Last 90 Days</option>
                    </select>
                </div>
                <div class="table-container">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>Timestamp</th>
                                <th>Action</th>
                                <th>Business</th>
                                <th>Type</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${rows}
                        </tbody>
                    </table>
                </div>
            </div>
        `;
    }

    renderSettings() {
        return `
            <div class="businesses-page">
                <div class="page-title">Business Oversight Settings</div>
                <div class="panel-card">
                    <h3>Mayor Access</h3>
                    <div class="detail-list">
                        <div class="detail-row"><span>Access Level</span><strong>Mayor Only</strong></div>
                        <div class="detail-row"><span>Audit Logging</span><strong>Enabled</strong></div>
                        <div class="detail-row"><span>Auto Compliance Alerts</span><strong>Enabled</strong></div>
                        <div class="detail-row"><span>Tax Escalation Rules</span><strong>Enabled</strong></div>
                    </div>
                </div>
                <div class="panel-card">
                    <h3>Policy Notes</h3>
                    <p class="text-muted">This module is read-only for business owners. All actions are reserved for government oversight and enforcement.</p>
                </div>
            </div>
        `;
    }

    attachRegistryHandlers(container) {
        const rows = container.querySelectorAll('[data-business-id]');
        const detailsPanel = container.querySelector('#business-details-panel');
        const createBtn = container.querySelector('#create-business-btn');
        const createName = container.querySelector('#create-business-name');
        const createOwner = container.querySelector('#create-business-owner');
        const createType = container.querySelector('#create-business-type');
        const createLocation = container.querySelector('#create-business-location');

        if (!detailsPanel) return;

        const setActiveRow = (row) => {
            rows.forEach(r => r.classList.remove('active-row'));
            row.classList.add('active-row');
        };

        rows.forEach(row => {
            row.addEventListener('click', () => {
                const businessId = row.dataset.businessId;
                const business = this.data.businesses.find(item => item.id === businessId);
                if (!business) return;
                this.openBusinessDetails(businessId, container.closest('#businesses-content'));
                setActiveRow(row);
            });
        });

        container.addEventListener('click', (e) => {
            const toggle = e.target.closest('[data-menu-toggle]');
            if (toggle) {
                e.stopPropagation();
                const menuId = toggle.dataset.menuToggle;
                container.querySelectorAll('.action-dropdown').forEach(menu => {
                    menu.classList.toggle('open', menu.dataset.menu === menuId);
                });
                return;
            }

            const action = e.target.closest('.action-item');
            if (action) {
                e.stopPropagation();
                const actionType = action.dataset.action;
                const businessId = action.dataset.businessId;
                const business = this.data.businesses.find(item => item.id === businessId);
                if (!business) return;

                if (actionType === 'view') {
                    this.openBusinessDetails(businessId, container.closest('#businesses-content'));
                } else if (actionType === 'transfer') {
                    this.showModal(`
                        <h3>Transfer Ownership</h3>
                        <p>Transfer <strong>${business.name}</strong> to:</p>
                        <select class="form-input" id="transfer-owner">
                            ${this.citizens.map(citizen => `<option value="${citizen.name} (${citizen.citizenId})">${citizen.name} (${citizen.citizenId})</option>`).join('')}
                        </select>
                    `, () => {
                        const newOwner = document.getElementById('transfer-owner').value;
                        if (newOwner) {
                            business.owner = newOwner;
                            this.renderPage('registry', container.closest('#businesses-content'));
                        }
                    });
                } else if (actionType === 'remove') {
                    this.showModal(`
                        <h3>Remove Owner</h3>
                        <p class="warning-text">Remove current owner from <strong>${business.name}</strong>?</p>
                    `, () => {
                        business.owner = 'Unassigned';
                        this.renderPage('registry', container.closest('#businesses-content'));
                    });
                }

                container.querySelectorAll('.action-dropdown').forEach(menu => menu.classList.remove('open'));
                return;
            }

            container.querySelectorAll('.action-dropdown').forEach(menu => menu.classList.remove('open'));
        });

        if (createBtn) {
            createBtn.addEventListener('click', () => {
                const name = createName?.value.trim();
                const owner = createOwner?.value;
                const type = createType?.value;
                const location = createLocation?.value.trim();

                if (!name || !owner) {
                    this.showNotification('Business name and owner are required.', 'error');
                    return;
                }

                const newBusiness = {
                    id: `BUS-${Math.floor(1000 + Math.random() * 9000)}`,
                    name,
                    owner,
                    ownerId: owner.match(/\(([^)]+)\)/)?.[1] || 'Unassigned',
                    type,
                    status: 'Open',
                    employees: 0,
                    revenueWeek: 0,
                    licenseStatus: 'Pending',
                    taxStatus: 'Current',
                    balance: 0,
                    blip: name,
                    blipColor: 'Blue',
                    location: location || 'Unassigned',
                    salesTotal: 0,
                    invoices: 0,
                    avgSale: 0,
                    peakHours: 'N/A',
                    payroll: 0,
                    wageAvg: 0,
                    permits: [],
                    taxDebt: 0,
                    warnings: [],
                    employeesList: [],
                    transactions: [],
                    activityLog: []
                };

                this.data.businesses.unshift(newBusiness);
                this.renderPage('registry', container.closest('#businesses-content'));
            });
        }

        if (rows[0]) {
            setActiveRow(rows[0]);
            this.attachDetailsTabs(detailsPanel);
        }
    }

    attachDetailsTabs(panel) {
        const tabs = panel.querySelectorAll('.details-tab');
        const sections = panel.querySelectorAll('.details-section');

        tabs.forEach(tab => {
            tab.addEventListener('click', () => {
                tabs.forEach(t => t.classList.remove('active'));
                sections.forEach(s => s.classList.remove('active'));
                tab.classList.add('active');
                const target = panel.querySelector(`[data-tab-content="${tab.dataset.tab}"]`);
                if (target) target.classList.add('active');
            });
        });
    }

    getStatusBadge(status) {
        const normalized = status.toLowerCase();
        let className = 'neutral';

        if (normalized === 'open' || normalized === 'active' || normalized === 'current') {
            className = 'active';
        } else if (normalized === 'closed' || normalized === 'suspended') {
            className = 'inactive';
        } else if (normalized === 'late') {
            className = 'warning';
        } else if (normalized === 'delinquent') {
            className = 'error';
        }

        return `<span class="status-badge ${className}">${status}</span>`;
    }
}

// ============================================================================
// DOCUMENTS MANAGER
// ============================================================================
class DocumentsManager {
    constructor() {
        this.documents = this.loadDocuments();
        this.currentDocument = null;
        this.rte = null;
        this.init();
    }

    init() {
        const newBtn = document.getElementById('new-document-btn');
        const saveBtn = document.getElementById('save-document-btn');
        const backBtn = document.getElementById('back-to-list-btn');
        const saveToDesktopBtn = document.getElementById('save-to-desktop-btn');
        const searchInput = document.getElementById('documents-search-input');

        if (newBtn) newBtn.addEventListener('click', () => this.newDocument());
        if (saveBtn) saveBtn.addEventListener('click', () => this.saveDocument());
        if (backBtn) backBtn.addEventListener('click', () => this.showList());
        if (saveToDesktopBtn) saveToDesktopBtn.addEventListener('click', () => this.saveToDesktop());
        if (searchInput) {
            searchInput.addEventListener('input', (e) => this.filterDocuments(e.target.value));
        }

        this.renderDocumentsList();
    }

    loadDocuments() {
        const stored = scopedStorageGet('gov_documents');
        return stored ? JSON.parse(stored) : [];
    }

    saveDocuments() {
        scopedStorageSet('gov_documents', JSON.stringify(this.documents));
    }

    newDocument() {
        this.currentDocument = {
            id: Date.now(),
            title: '',
            content: '',
            created: new Date().toISOString(),
            modified: new Date().toISOString()
        };
        this.showEditor();
    }

    openDocument(id) {
        this.currentDocument = this.documents.find(d => d.id === id);
        if (this.currentDocument) {
            this.showEditor();
        }
    }

    saveDocument() {
        if (!this.currentDocument) return;

        const titleInput = document.getElementById('document-title-input');
        const title = titleInput.value.trim() || 'Untitled Document';
        
        this.currentDocument.title = title;
        this.currentDocument.content = this.rte ? this.rte.getValue() : '';
        this.currentDocument.modified = new Date().toISOString();

        const existingIndex = this.documents.findIndex(d => d.id === this.currentDocument.id);
        if (existingIndex >= 0) {
            this.documents[existingIndex] = this.currentDocument;
        } else {
            this.documents.unshift(this.currentDocument);
        }

        this.saveDocuments();
        this.showNotification('Document saved successfully');
    }

    saveToDesktop() {
        if (!this.currentDocument) {
            this.showNotification('Please save the document first', 'error');
            return;
        }

        // First save the document
        this.saveDocument();

        // Get the document object
        const doc = this.documents.find(d => d.id === this.currentDocument);
        if (!doc) {
            this.showNotification('Document not found', 'error');
            return;
        }

        // Then add to desktop
        if (window.desktopManager) {
            window.desktopManager.addDocumentToDesktop(doc.id, doc.title);
            this.showNotification('Document added to desktop');
        }
    }

    async deleteDocument(id) {
        const confirmed = await uiConfirm('Are you sure you want to delete this document?', {
            title: 'Delete Document',
            confirmLabel: 'Delete'
        });
        if (!confirmed) return;

        this.documents = this.documents.filter(d => d.id !== id);
        this.saveDocuments();
        this.renderDocumentsList();
        this.showNotification('Document deleted');
    }

    showEditor() {
        const list = document.getElementById('documents-list');
        const editor = document.getElementById('document-editor');
        const titleInput = document.getElementById('document-title-input');
        const rteContainer = document.getElementById('rte-container');

        if (list) list.style.display = 'none';
        if (editor) editor.style.display = 'flex';
        
        if (titleInput && this.currentDocument) {
            titleInput.value = this.currentDocument.title || '';
        }

        if (rteContainer) {
            rteContainer.innerHTML = '';
            const editorDiv = document.createElement('div');
            editorDiv.id = 'document-rte-editor';
            rteContainer.appendChild(editorDiv);

            this.rte = createRTE('document-rte-editor', {
                placeholder: 'Start writing your document...',
                initialContent: this.currentDocument?.content || '',
                minHeight: '400px',
                maxHeight: '70vh'
            });
        }
    }

    showList() {
        const list = document.getElementById('documents-list');
        const editor = document.getElementById('document-editor');
        const searchInput = document.getElementById('documents-search-input');

        if (list) list.style.display = 'grid';
        if (editor) editor.style.display = 'none';
        if (searchInput) searchInput.value = '';

        this.renderDocumentsList();
    }

    filterDocuments(query) {
        const normalizedQuery = query.toLowerCase().trim();
        this.renderDocumentsList(normalizedQuery);
    }

    renderDocumentsList(filter = '') {
        const container = document.getElementById('documents-list');
        if (!container) return;

        const filteredDocs = filter 
            ? this.documents.filter(d => d.title.toLowerCase().includes(filter))
            : this.documents;

        if (filteredDocs.length === 0) {
            container.innerHTML = `
                <div class="empty-documents" style="grid-column: 1/-1;">
                    <svg viewBox="0 0 24 24" fill="currentColor">
                        <path d="M14 2H6c-1.1 0-1.99.9-1.99 2L4 20c0 1.1.89 2 1.99 2H18c1.1 0 2-.9 2-2V8l-6-6zm2 16H8v-2h8v2zm0-4H8v-2h8v2zm-3-5V3.5L18.5 9H13z"/>
                    </svg>
                    <h3>${filter ? 'No documents found' : 'No documents yet'}</h3>
                    <p>${filter ? 'Try a different search term' : 'Click "New Document" to get started'}</p>
                </div>
            `;
            return;
        }

        container.innerHTML = filteredDocs.map(doc => {
            const modifiedDate = new Date(doc.modified).toLocaleDateString();
            return `
                <div class="document-card" data-id="${doc.id}">
                    <div class="document-card-actions">
                        <button class="document-card-delete-btn" data-id="${doc.id}" onclick="event.stopPropagation();">
                            <svg viewBox="0 0 24 24" fill="currentColor" width="14" height="14">
                                <path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/>
                            </svg>
                        </button>
                    </div>
                    <div class="document-card-icon">
                        <svg viewBox="0 0 24 24" fill="currentColor">
                            <path d="M14 2H6c-1.1 0-1.99.9-1.99 2L4 20c0 1.1.89 2 1.99 2H18c1.1 0 2-.9 2-2V8l-6-6zm2 16H8v-2h8v2zm0-4H8v-2h8v2zm-3-5V3.5L18.5 9H13z"/>
                        </svg>
                    </div>
                    <div class="document-card-title">${doc.title || 'Untitled Document'}</div>
                    <div class="document-card-meta">Modified ${modifiedDate}</div>
                </div>
            `;
        }).join('');

        container.querySelectorAll('.document-card').forEach(card => {
            card.addEventListener('click', () => {
                const id = parseInt(card.dataset.id);
                this.openDocument(id);
            });
        });

        container.querySelectorAll('.document-card-delete-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                e.stopPropagation();
                const id = parseInt(btn.dataset.id);
                this.deleteDocument(id);
            });
        });
    }

    showNotification(message, type = 'success') {
        const notification = document.createElement('div');
        notification.className = 'notification';
        notification.textContent = message;
        const bgColor = type === 'error' ? '#ef4444' : '#10b981';
        notification.style.cssText = `
            position: fixed;
            bottom: 24px;
            right: 24px;
            background: ${bgColor};
            color: white;
            padding: 12px 20px;
            border-radius: 8px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.15);
            z-index: 10001;
            font-size: 14px;
            font-weight: 500;
            animation: slideIn 0.3s ease;
        `;
        document.body.appendChild(notification);
        setTimeout(() => {
            notification.style.animation = 'slideOut 0.3s ease';
            setTimeout(() => notification.remove(), 300);
        }, 2000);
    }
}

// ============================================================================
// DRAG AND DROP MANAGER
// ============================================================================
class DragDropManager {
    constructor(desktopManager) {
        this.desktopManager = desktopManager;
        this.selectedIcons = new Set();
        this.pendingDrag = null;
        this.activeDrag = null;
        this.selectionBox = null;
        this.selectionStart = null;
        this.boundMouseMove = (e) => this.onMouseMove(e);
        this.boundMouseUp = (e) => this.onMouseUp(e);
        this.init();
    }

    init() {
        this.setupDesktopSurface();
        this.setupDesktopIcons();
        document.addEventListener('mousemove', this.boundMouseMove);
        document.addEventListener('mouseup', this.boundMouseUp);
        window.addEventListener('blur', () => this.cancelTransientDesktopInteractions());
        document.addEventListener('visibilitychange', () => {
            if (document.hidden) {
                this.cancelTransientDesktopInteractions();
            }
        });
    }

    setupDesktopSurface() {
        const desktop = document.getElementById('desktop');
        const iconsContainer = document.querySelector('.desktop-icons');
        if (!desktop || !iconsContainer) return;

        desktop.addEventListener('mousedown', (e) => {
            if (e.button !== 0) return;
            const icon = e.target.closest('.icon');
            const inIconsArea = !!e.target.closest('.desktop-icons');

            if (icon || !inIconsArea) return;

            this.finishSelection();
            this.clearSelection();
            this.beginSelection(e.clientX, e.clientY);
        });
    }

    setupDesktopIcons() {
        const icons = document.querySelectorAll('.desktop-icons .icon');
        icons.forEach(icon => {
            if (icon.dataset.dndBound === 'true') return;
            icon.dataset.dndBound = 'true';

            icon.addEventListener('mousedown', (e) => this.onIconMouseDown(e, icon));
            if (!icon.classList.contains('external-program')) {
                icon.addEventListener('dblclick', () => this.openIcon(icon));
            }
        });
    }

    openIcon(icon) {
        if (!icon) return;
        if (icon.dataset.type === 'folder') {
            this.desktopManager.openFolder(icon.dataset.id);
            return;
        }
        if (icon.dataset.type === 'document') {
            const docId = icon.dataset.documentId;
            if (window.documentsManager) {
                window.documentsManager.openDocument(docId);
            }
            if (window.windowManagerInstance) {
                window.windowManagerInstance.openWindow('documents');
            }
            return;
        }
        if (window.windowManagerInstance && icon.dataset.app) {
            window.windowManagerInstance.openWindow(resolveAppName(icon.dataset.app));
        }
    }

    onIconMouseDown(e, icon) {
        if (e.button !== 0) return;
        e.preventDefault();
        e.stopPropagation();

        if (!e.ctrlKey) {
            this.clearSelection();
        }
        this.selectIcon(icon, true);

        this.pendingDrag = {
            icon,
            startX: e.clientX,
            startY: e.clientY
        };
    }

    onMouseMove(e) {
        if (this.selectionStart) {
            this.updateSelectionBox(e.clientX, e.clientY);
            return;
        }

        if (!this.pendingDrag && !this.activeDrag) return;

        if (this.pendingDrag && !this.activeDrag) {
            const dx = e.clientX - this.pendingDrag.startX;
            const dy = e.clientY - this.pendingDrag.startY;
            if (Math.hypot(dx, dy) < 5) return;
            this.startDrag(this.pendingDrag.icon, this.pendingDrag.startX, this.pendingDrag.startY);
        }

        if (this.activeDrag?.ghost) {
            this.activeDrag.ghost.style.left = `${e.clientX - this.activeDrag.pointerOffsetX}px`;
            this.activeDrag.ghost.style.top = `${e.clientY - this.activeDrag.pointerOffsetY}px`;
            const anchorX = e.clientX - (this.activeDrag.pointerOffsetX || 0);
            const anchorY = e.clientY - (this.activeDrag.pointerOffsetY || 0);
            const targetCell = this.getCellFromPoint(anchorX, anchorY, this.activeDrag.metrics);
            if (targetCell && this.activeDrag.preview) {
                const occupied = this.getOccupiedCells(this.activeDrag.entries.map((entry) => entry.key));
                const snapped = this.findNearestAvailableCell(targetCell, occupied);
                const left = this.activeDrag.metrics.rect.left + snapped.x * this.activeDrag.metrics.cellW + (this.activeDrag.metrics.iconOffsetX || 0);
                const top = this.activeDrag.metrics.rect.top + snapped.y * this.activeDrag.metrics.cellH + (this.activeDrag.metrics.iconOffsetY || 0);
                this.activeDrag.preview.style.left = `${left}px`;
                this.activeDrag.preview.style.top = `${top}px`;
            }
        }
    }

    onMouseUp(e) {
        if (this.selectionStart) {
            this.finishSelection();
        }

        if (this.activeDrag) {
            this.finishDrag(e.clientX, e.clientY);
        }

        this.pendingDrag = null;
    }

    cancelTransientDesktopInteractions() {
        this.pendingDrag = null;
        if (this.activeDrag) {
            this.activeDrag.entries.forEach((entry) => entry.icon.classList.remove('dragging-manual'));
            if (this.activeDrag.ghost) {
                this.activeDrag.ghost.remove();
            }
            if (this.activeDrag.preview) {
                this.activeDrag.preview.remove();
            }
            this.activeDrag = null;
        }
        this.finishSelection();
    }

    getIconCurrentCell(icon, metrics = this.getGridMetrics()) {
        if (!icon || !metrics) return { x: 0, y: 0 };

        const explicitCol = parseInt(icon.style.gridColumn, 10);
        const explicitRow = parseInt(icon.style.gridRow, 10);
        if (Number.isFinite(explicitCol) && Number.isFinite(explicitRow)) {
            return { x: Math.max(0, explicitCol - 1), y: Math.max(0, explicitRow - 1) };
        }

        const rect = icon.getBoundingClientRect();
        const x = Math.round((rect.left - metrics.rect.left - (metrics.iconOffsetX || 0)) / Math.max(1, metrics.cellW));
        const y = Math.round((rect.top - metrics.rect.top - (metrics.iconOffsetY || 0)) / Math.max(1, metrics.cellH));
        return { x: Math.max(0, x), y: Math.max(0, y) };
    }

    startDrag(icon, x, y) {
        this.desktopManager.ensureDesktopPositions();

        const selected = Array.from(this.selectedIcons);
        const primary = selected.includes(icon) ? icon : selected[0] || icon;
        const metrics = this.getGridMetrics();
        const startCell = this.getCellFromPoint(x, y, metrics);

        const primaryEntity = this.desktopManager.getDesktopEntityByIcon(primary)
            || this.desktopManager.ensureDesktopEntityForIcon(primary);
        const primaryPos = primaryEntity?.position || this.getIconCurrentCell(primary, metrics) || startCell || { x: 0, y: 0 };
        const primaryRect = primary.getBoundingClientRect();
        const pointerOffsetX = Math.max(0, Math.min(primaryRect.width, x - primaryRect.left));
        const pointerOffsetY = Math.max(0, Math.min(primaryRect.height, y - primaryRect.top));

        const entries = selected.map((entryIcon) => {
            const entity = this.desktopManager.getDesktopEntityByIcon(entryIcon)
                || this.desktopManager.ensureDesktopEntityForIcon(entryIcon);
            const pos = entity?.position || this.getIconCurrentCell(entryIcon, metrics);
            return {
                icon: entryIcon,
                key: entity?.key || resolveAppName(entryIcon.dataset.app || entryIcon.dataset.id),
                dx: (pos.x || 0) - (primaryPos.x || 0),
                dy: (pos.y || 0) - (primaryPos.y || 0)
            };
        });

        const ghost = icon.cloneNode(true);
        ghost.classList.add('drag-ghost');
        ghost.style.position = 'fixed';
        ghost.style.left = `${x - pointerOffsetX}px`;
        ghost.style.top = `${y - pointerOffsetY}px`;
        ghost.style.pointerEvents = 'none';
        ghost.style.zIndex = '9999';
        document.body.appendChild(ghost);

        const preview = document.createElement('div');
        preview.className = 'desktop-snap-preview';
        preview.style.position = 'fixed';
        preview.style.pointerEvents = 'none';
        preview.style.zIndex = '9998';
        preview.style.width = `${Math.round(metrics.iconW || primaryRect.width)}px`;
        preview.style.height = `${Math.round(metrics.iconH || primaryRect.height)}px`;
        document.body.appendChild(preview);

        selected.forEach((entry) => entry.classList.add('dragging-manual'));

        this.activeDrag = { primaryCell: primaryPos, entries, ghost, preview, metrics, pointerOffsetX, pointerOffsetY };
    }

    finishDrag(clientX, clientY) {
        const drag = this.activeDrag;
        this.activeDrag = null;
        if (!drag) return;

        drag.entries.forEach((entry) => entry.icon.classList.remove('dragging-manual'));
        if (drag.ghost) drag.ghost.remove();
        if (drag.preview) drag.preview.remove();

        const anchorX = clientX - (drag.pointerOffsetX || 0);
        const anchorY = clientY - (drag.pointerOffsetY || 0);
        const targetCell = this.getCellFromPoint(anchorX, anchorY, drag.metrics);
        if (!targetCell) return;

        const occupied = this.getOccupiedCells(drag.entries.map((entry) => entry.key));
        const anchorCell = this.findNearestAvailableCell(targetCell, occupied);
        const reserved = new Set([`${anchorCell.x}:${anchorCell.y}`]);

        drag.entries.forEach((entry, index) => {
            if (!entry.key) return;
            let desired = index === 0 ? anchorCell : this.desktopManager.clampDesktopPosition(anchorCell.x + entry.dx, anchorCell.y + entry.dy);
            while (occupied.has(`${desired.x}:${desired.y}`) || reserved.has(`${desired.x}:${desired.y}`)) {
                desired = this.findNearestAvailableCell(desired, new Map([...occupied, ...Array.from(reserved).map((key)=>[key,true])]));
                break;
            }
            reserved.add(`${desired.x}:${desired.y}`);
            this.desktopManager.setDesktopPosition(entry.key, desired.x, desired.y, true);
        });

        this.desktopManager.saveItems();
        this.desktopManager.applyDesktopPositions();
    }

    beginSelection(startX, startY) {
        const desktop = document.getElementById('desktop');
        if (!desktop) return;

        this.selectionStart = { x: startX, y: startY };
        this.selectionBox = document.createElement('div');
        this.selectionBox.className = 'desktop-selection-box';
        this.selectionBox.style.left = `${startX}px`;
        this.selectionBox.style.top = `${startY}px`;
        this.selectionBox.style.width = '0px';
        this.selectionBox.style.height = '0px';
        desktop.appendChild(this.selectionBox);
    }

    updateSelectionBox(x, y) {
        if (!this.selectionStart || !this.selectionBox) return;

        const left = Math.min(this.selectionStart.x, x);
        const top = Math.min(this.selectionStart.y, y);
        const width = Math.abs(x - this.selectionStart.x);
        const height = Math.abs(y - this.selectionStart.y);

        this.selectionBox.style.left = `${left}px`;
        this.selectionBox.style.top = `${top}px`;
        this.selectionBox.style.width = `${width}px`;
        this.selectionBox.style.height = `${height}px`;

        const boxRect = { left, top, right: left + width, bottom: top + height };
        document.querySelectorAll('.desktop-icons .icon').forEach((icon) => {
            const rect = icon.getBoundingClientRect();
            const inside = rect.left >= boxRect.left && rect.right <= boxRect.right && rect.top >= boxRect.top && rect.bottom <= boxRect.bottom;
            this.selectIcon(icon, inside);
        });
    }

    finishSelection() {
        this.selectionStart = null;
        if (this.selectionBox) {
            this.selectionBox.remove();
            this.selectionBox = null;
        }
    }

    selectIcon(icon, selected) {
        if (!icon) return;
        icon.classList.toggle('selected', !!selected);
        if (selected) {
            this.selectedIcons.add(icon);
        } else {
            this.selectedIcons.delete(icon);
        }
    }

    clearSelection() {
        this.selectedIcons.forEach((icon) => icon.classList.remove('selected'));
        this.selectedIcons.clear();
    }

    getGridMetrics() {
        const container = document.querySelector('.desktop-icons');
        if (!container) return null;
        const icon = container.querySelector('.icon');
        const rect = container.getBoundingClientRect();
        const grid = this.desktopManager.getDesktopGridSize();
        const cellW = rect.width / Math.max(1, grid.columns);
        const cellH = rect.height / Math.max(1, grid.rows);
        const iconRect = icon?.getBoundingClientRect();
        return {
            rect,
            cellW,
            cellH,
            columns: grid.columns,
            rows: grid.rows,
            iconW: iconRect?.width || Math.min(88, cellW * 0.72),
            iconH: iconRect?.height || Math.min(104, cellH * 0.72),
            iconOffsetX: Math.max(0, ((cellW - (iconRect?.width || Math.min(88, cellW * 0.72))) / 2)),
            iconOffsetY: Math.max(0, ((cellH - (iconRect?.height || Math.min(104, cellH * 0.72))) / 2))
        };
    }

    getCellFromPoint(clientX, clientY, metrics = this.getGridMetrics()) {
        if (!metrics) return null;
        const { rect, cellW, cellH } = metrics;
        const relX = clientX - rect.left;
        const relY = clientY - rect.top;
        const rawX = Math.round((relX - cellW / 2) / Math.max(1, cellW));
        const rawY = Math.round((relY - cellH / 2) / Math.max(1, cellH));
        return this.desktopManager.clampDesktopPosition(rawX, rawY);
    }

    getOccupiedCells(excludeKeys = []) {
        const excluded = new Set(excludeKeys.map((key) => resolveAppName(key) || key));
        const occupied = new Map();
        (this.desktopManager.items || []).forEach((item) => {
            if (!item || item.location !== 'desktop' || !item.position) return;
            const key = resolveAppName(item.app || item.id) || item.id;
            if (excluded.has(key)) return;
            occupied.set(`${item.position.x}:${item.position.y}`, key);
        });
        (this.desktopManager.folders || []).forEach((folder) => {
            if (!folder || folder.location !== 'desktop' || !folder.position) return;
            const key = folder.id;
            if (excluded.has(key)) return;
            occupied.set(`${folder.position.x}:${folder.position.y}`, key);
        });
        return occupied;
    }

    findNearestAvailableCell(targetCell, occupied) {
        const grid = this.desktopManager.getDesktopGridSize();
        const target = this.desktopManager.clampDesktopPosition(targetCell?.x || 0, targetCell?.y || 0);
        const isFree = (x, y) => !occupied.has(`${x}:${y}`);
        if (isFree(target.x, target.y)) return target;
        for (let radius = 1; radius < Math.max(grid.columns, grid.rows); radius += 1) {
            for (let y = Math.max(0, target.y - radius); y <= Math.min(grid.rows - 1, target.y + radius); y += 1) {
                for (let x = Math.max(0, target.x - radius); x <= Math.min(grid.columns - 1, target.x + radius); x += 1) {
                    if (Math.max(Math.abs(x - target.x), Math.abs(y - target.y)) !== radius) continue;
                    if (isFree(x, y)) return { x, y };
                }
            }
        }
        return target;
    }

    setupDropTarget(_element) {
        // Folder drop targets are currently not interactive in selection mode.
    }

    refreshIcons() {
        this.finishSelection();
        this.setupDesktopIcons();
        this.desktopManager?.applyDesktopPositions();
    }
}

// ============================================================================
// BROWSER APP MANAGER
// ============================================================================
class BrowserManager {
    constructor() {
        this.currentUrl = '';
        this.history = [];
        this.historyIndex = -1;
        this.homeUrl = 'https://start.ls';
        this.bookmarks = this.loadBookmarks();
        this.init();
    }

    init() {
        const urlInput = document.querySelector('#browser-window .browser-url');
        
        if (urlInput) {
            urlInput.addEventListener('keypress', (e) => {
                if (e.key === 'Enter') {
                    this.loadUrl(urlInput.value);
                }
            });
        }

        this.renderBookmarksBar();
    }


    async getConfig() {
        if (this.config) {
            return this.config;
        }

        const response = await nuiRequest('pc:browser:getConfig', {});
        this.config = response && response.ok ? (response.data || {}) : {};
        return this.config;
    }

    loadBookmarks() {
        const stored = localStorage.getItem('browser_bookmarks');
        if (stored) {
            try {
                const parsed = JSON.parse(stored);
                if (Array.isArray(parsed) && parsed.length) {
                    return parsed;
                }
            } catch (e) {}
        }

        return [
            { name: 'Start', url: 'start.ls' },
            { name: 'Government Portal', url: 'los-santos.gov' },
            { name: 'Domains', url: 'domains.ls' },
            { name: 'Services', url: 'services.ls' }
        ];
    }

    saveBookmarks() {
        localStorage.setItem('browser_bookmarks', JSON.stringify(this.bookmarks));
        this.renderBookmarksBar();
    }

    async onOpen() {
        await this.getConfig();
        if ((!this.bookmarks || !this.bookmarks.length) && this.config && Array.isArray(this.config.defaultBookmarks)) {
            this.bookmarks = this.config.defaultBookmarks.slice();
            this.saveBookmarks();
        }
        if (!this.currentUrl) {
            this.loadUrl((this.config && this.config.homeUrl) || this.homeUrl, true);
        }
    }

    normalizeUrl(url) {
        const raw = String(url || '').trim();
        if (!raw) return (this.config && this.config.homeUrl) || this.homeUrl;

        if (/\s/.test(raw) && !raw.includes('.')) {
            return `https://search.ls/?q=${encodeURIComponent(raw)}`;
        }

        let normalized = raw.replace(/^https?:\/\//i, '').replace(/^www\./i, '');
        if (!normalized.includes('.')) {
            normalized = `${normalized}.ls`;
        }

        return `https://${normalized}`;
    }

    pushHistory(url) {
        if (this.historyIndex < this.history.length - 1) {
            this.history = this.history.slice(0, this.historyIndex + 1);
        }
        this.history.push(url);
        this.historyIndex = this.history.length - 1;
    }

    getUrlInput() {
        return document.querySelector('#browser-window .browser-url');
    }

    getContent() {
        return document.querySelector('#browser-window .browser-content');
    }

    getShortDomain(url) {
        return String(url || '').replace(/^https?:\/\//i, '').replace(/\/.*$/, '');
    }

    async loadUrl(url, skipHistory = false) {
        await this.getConfig();
        const normalizedUrl = this.normalizeUrl(url);

        this.currentUrl = normalizedUrl;
        if (!skipHistory) {
            this.pushHistory(normalizedUrl);
        }

        const urlInput = this.getUrlInput();
        if (urlInput) urlInput.value = this.getShortDomain(normalizedUrl);

        const content = this.getContent();
        if (!content) return;

        if (this.isStartUrl(normalizedUrl)) {
            this.renderStartPage(content);
            return;
        }

        if (this.isDomainsUrl(normalizedUrl)) {
            this.renderDomainsPage(content);
            return;
        }

        if (this.isServicesUrl(normalizedUrl)) {
            this.renderServicesPage(content);
            return;
        }

        if (this.isGovUrl(normalizedUrl)) {
            this.renderGovPortal(content, normalizedUrl);
            return;
        }

        if (this.isSearchUrl(normalizedUrl)) {
            this.renderSearchPage(content, normalizedUrl);
            return;
        }

        await this.renderCustomSite(content, normalizedUrl);
    }

    renderBookmarksBar() {
        const bar = document.querySelector('#browser-window .browser-bookmarks');
        if (!bar) return;

        bar.innerHTML = this.bookmarks.map(bookmark => `
            <button class="browser-bookmark" data-url="${bookmark.url}" title="${bookmark.url}">${bookmark.name}</button>
        `).join('');

        bar.querySelectorAll('.browser-bookmark').forEach(btn => {
            btn.addEventListener('click', () => this.loadUrl(btn.dataset.url));
        });
    }

    isStartUrl(url) {
        return /start\.ls/i.test(url);
    }

    isSearchUrl(url) {
        return /search\.ls/i.test(url);
    }

    isDomainsUrl(url) {
        return /domains\.ls/i.test(url);
    }

    isServicesUrl(url) {
        return /services\.ls/i.test(url);
    }

    escapeHtml(value) {
        const div = document.createElement('div');
        div.textContent = value == null ? '' : String(value);
        return div.innerHTML;
    }

    normalizeThemeColor(value, fallback) {
        const raw = String(value == null ? '' : value).trim();
        if (!raw) return fallback;

        // Accept short/long hex colors and common rgb/rgba/hsl/hsla/color() syntaxes.
        if (/^#([0-9a-f]{3}|[0-9a-f]{6})$/i.test(raw)) return raw;
        if (/^(rgb|rgba|hsl|hsla|color)\(/i.test(raw)) return raw;
        return fallback;
    }

    normalizeImageSource(value) {
        const raw = String(value == null ? '' : value).trim();
        if (!raw) return '';

        if (/^(https?:\/\/|data:image\/|blob:|nui:\/\/)/i.test(raw)) {
            return raw;
        }

        if (/^\/\//.test(raw)) {
            return `https:${raw}`;
        }

        // Allow direct cfx-nui resource links without forcing file extensions.
        if (/^cfx-nui-/i.test(raw)) {
            return `https://${raw}`;
        }

        // Support shorthand resource paths such as pf-policemdt/html/assets/logo.
        if (/^[a-z0-9_-]+\/.+/i.test(raw)) {
            return `https://cfx-nui-${raw}`;
        }

        if (/^www\./i.test(raw) || raw.includes('.')) {
            return `https://${raw}`;
        }

        return raw;
    }

    async renderStartPage(container) {
        const config = await this.getConfig();
        const shortcuts = Array.isArray(config.shortcuts) ? config.shortcuts : [];
        const featured = Array.isArray(config.featuredSites) ? config.featuredSites : [];
        const recent = this.history.slice(-5).reverse();
        const esc = (value) => this.escapeHtml(value);

        container.innerHTML = `
            <div class="browser-homepage">
                <div class="browser-home-shell">
                    <div class="browser-home-shortcuts">
                        ${shortcuts.map(site => `
                            <button class="browser-shortcut" data-url="${esc(site.url)}">
                                <span class="browser-shortcut-icon">${esc((site.name || '?').slice(0, 2).toUpperCase())}</span>
                                <span class="browser-shortcut-label">${esc(site.name || site.url)}</span>
                            </button>
                        `).join('')}
                    </div>

                    <div class="browser-home-search-card">
                        <div class="browser-home-search-row">
                            <input id="browser-start-input" type="text" placeholder="Search or type a domain" value="">
                            <button id="browser-start-go" class="btn btn-primary">Go</button>
                        </div>
                        <div class="browser-home-guide-row">
                            <input id="browser-guide-input" type="text" placeholder="Ask anything, find anything...">
                            <button id="browser-guide-go" class="btn btn-secondary">Guide</button>
                        </div>
                        <div id="browser-guide-result" class="browser-guide-result"></div>
                    </div>

                    <div class="browser-home-panels">
                        <section class="browser-home-panel">
                            <div class="browser-home-panel-title">Featured</div>
                            <div class="browser-home-list">
                                ${featured.map(site => `
                                    <button class="browser-link-item browser-link-item--full" data-url="${esc(site.url)}">
                                        <strong>${esc(site.name || site.url)}</strong>
                                        <span>${esc(site.description || '')}</span>
                                    </button>
                                `).join('')}
                            </div>
                        </section>
                        <section class="browser-home-panel">
                            <div class="browser-home-panel-title">Recent</div>
                            <div class="browser-home-list">
                                ${recent.length ? recent.map(url => `
                                    <button class="browser-link-item browser-link-item--full" data-url="${esc(url)}">
                                        <strong>${esc(this.getShortDomain(url))}</strong>
                                        <span>${esc(url)}</span>
                                    </button>
                                `).join('') : '<div class="gov-empty">No recent pages yet.</div>'}
                            </div>
                        </section>
                    </div>
                </div>
            </div>
        `;

        container.querySelectorAll('[data-url]').forEach(btn => {
            btn.addEventListener('click', () => this.loadUrl(btn.dataset.url));
        });

        const goToValue = () => this.loadUrl(container.querySelector('#browser-start-input')?.value || '');
        container.querySelector('#browser-start-go')?.addEventListener('click', goToValue);
        container.querySelector('#browser-start-input')?.addEventListener('keydown', (e) => {
            if (e.key === 'Enter') goToValue();
        });

        const handleGuide = async () => {
            const query = container.querySelector('#browser-guide-input')?.value || '';
            const resultEl = container.querySelector('#browser-guide-result');
            if (!query.trim()) {
                resultEl.innerHTML = '';
                return;
            }
            resultEl.innerHTML = '<div class="browser-guide-card"><strong>Guide</strong><span>Searching...</span></div>';
            const response = await nuiRequest('pc:browser:ask', { query });
            const data = response && response.ok ? (response.data || {}) : {};
            const waypointButton = data.waypoint ? `<button class="btn btn-secondary btn-small" id="browser-guide-waypoint">Set Waypoint</button>` : '';
            const openButton = data.url ? `<button class="btn btn-primary btn-small" id="browser-guide-open">Open</button>` : '';
            resultEl.innerHTML = `
                <div class="browser-guide-card">
                    <strong>${esc(data.title || 'Guide')}</strong>
                    <span>${esc(data.body || 'No matching guide entry was found.')}</span>
                    <div class="browser-guide-actions">${openButton}${waypointButton}</div>
                </div>
            `;
            resultEl.querySelector('#browser-guide-open')?.addEventListener('click', () => this.loadUrl(data.url));
            resultEl.querySelector('#browser-guide-waypoint')?.addEventListener('click', async () => {
                await nuiRequest('pc:setWaypoint', data.waypoint || {});
                this.showNotification('Waypoint set');
            });
        };

        container.querySelector('#browser-guide-go')?.addEventListener('click', handleGuide);
        container.querySelector('#browser-guide-input')?.addEventListener('keydown', (e) => {
            if (e.key === 'Enter') handleGuide();
        });
    }

    async renderDomainsPage(container) {
        const [configResult, domainsResult] = await Promise.all([
            nuiRequest('pc:browser:getConfig', {}),
            nuiRequest('pc:browser:getDomains', {})
        ]);
        const config = configResult && configResult.ok ? (configResult.data || {}) : {};
        const domains = domainsResult && domainsResult.ok ? (domainsResult.data || []) : [];
        const owned = domains.filter(domain => domain.isOwner);
        const available = domains.filter(domain => !domain.isOwner);
        const domainPrice = config.domainPrice || 2500;
        const esc = (value) => this.escapeHtml(value);

        container.innerHTML = `
            <div class="browser-page-shell domains-page">
                <div class="dom-utility-bar">
                    <span>Domain Commerce Registry</span>
                    <span class="dom-sep">|</span>
                    <span class="dom-price-highlight">$${domainPrice.toLocaleString()} per domain</span>
                </div>

                <header class="dom-page-header">
                    <div class="dom-header-content">
                        <div class="dom-header-kicker">Domain Registry</div>
                        <h1 class="dom-page-title">Web Domain Services</h1>
                        <p class="dom-header-subtitle">Purchase, manage, and publish your custom websites. Build your online presence with player-owned domains.</p>
                    </div>
                    <div class="dom-header-badge">
                        <div class="dom-badge-price">\$${domainPrice.toLocaleString()}</div>
                        <div class="dom-badge-label">per domain</div>
                    </div>
                </header>

                <nav class="dom-page-nav">
                    <button class="dom-nav-btn active">Purchase</button>
                    <button class="dom-nav-btn">My Domains</button>
                    <button class="dom-nav-btn">Registry</button>
                </nav>

                <div class="dom-main-grid">
                    <section class="dom-panel">
                        <div class="dom-panel-header">
                            <h2>Register New Domain</h2>
                            <p>Find and purchase an available domain to start building your website.</p>
                        </div>
                        <form class="dom-form-grid" onsubmit="return false;">
                            <div class="dom-form-group">
                                <label for="browser-domain-input" class="form-label">Domain Name</label>
                                <input id="browser-domain-input" class="form-input dom-input-large" type="text" placeholder="example.com" autocomplete="off">
                                <span class="dom-form-hint">.com, .net, .org, and custom TLDs available</span>
                            </div>
                            <div class="dom-form-group">
                                <label for="browser-domain-template" class="form-label">Website Template</label>
                                <select id="browser-domain-template" class="form-input">
                                    ${Object.keys(config.templates || {}).map(key => `<option value="${esc(key)}">${esc((config.templates[key] && config.templates[key].name) || key)}</option>`).join('')}
                                </select>
                                <span class="dom-form-hint">Choose a template for your new website</span>
                            </div>
                            <button id="browser-domain-buy" class="btn btn-primary btn-large dom-btn-full">Purchase Domain Now (\$${domainPrice.toLocaleString()})</button>
                        </form>
                    </section>

                    <section class="dom-panel">
                        <div class="dom-panel-header">
                            <h2>Your Domains</h2>
                            <div class="dom-counter">${owned.length} owned</div>
                        </div>
                        <div class="dom-cards-list">
                            ${owned.length ? owned.map(domain => `
                                <div class="dom-card dom-card-owned" data-domain="${esc(domain.domain)}">
                                    <div class="dom-card-header">
                                        <strong class="dom-domain-name">${esc(domain.domain)}</strong>
                                        <span class="dom-card-tag">Owned</span>
                                    </div>
                                    <div class="dom-card-meta">
                                        <div class="dom-meta-row">
                                            <span class="dom-meta-label">Template</span>
                                            <span class="dom-meta-value">${esc(domain.templateId || 'services')}</span>
                                        </div>
                                        <div class="dom-meta-row">
                                            <span class="dom-meta-label">Registered</span>
                                            <span class="dom-meta-value">${domain.purchasedAt ? new Date(domain.purchasedAt).toLocaleDateString() : 'Unknown'}</span>
                                        </div>
                                    </div>
                                    <div class="dom-card-actions">
                                        <button class="btn btn-secondary btn-small" data-open-domain="${esc(domain.domain)}">Open Site</button>
                                        <button class="btn btn-secondary btn-small" data-transfer-domain="${esc(domain.domain)}">Transfer</button>
                                    </div>
                                </div>
                            `).join('') : '<div class="dom-empty-state"><p>No domains owned. Purchase one above to get started.</p></div>'}
                        </div>
                    </section>
                </div>

                <section class="dom-panel dom-panel-full">
                    <div class="dom-panel-header">
                        <h2>Domain Registry</h2>
                        <p>View all registered domains in the system</p>
                    </div>
                    <div class="dom-registry-list">
                        ${domains.length ? domains.map(domain => `
                            <div class="dom-registry-entry ${domain.isOwner ? 'dom-registry-owned' : ''}">
                                <div class="dom-registry-main">
                                    <strong class="dom-registry-domain">${esc(domain.domain)}</strong>
                                    <span class="dom-registry-owner">Owner: ${esc(domain.ownerName || domain.ownerIdentifier || 'Unknown')}</span>
                                </div>
                                <div class="dom-registry-status">${domain.isOwner ? '<span class="dom-status-owned">You own this</span>' : '<span class="dom-status-taken">Registered</span>'}</div>
                            </div>
                        `).join('') : '<div class="dom-empty-state"><p>No domains have been registered yet.</p></div>'}
                    </div>
                </section>
            </div>
        `;

        // Domain purchase button
        container.querySelector('#browser-domain-buy')?.addEventListener('click', async () => {
            const domain = container.querySelector('#browser-domain-input')?.value || '';
            const templateId = container.querySelector('#browser-domain-template')?.value || 'services';
            if (!domain.trim()) {
                this.showNotification('Please enter a domain name');
                return;
            }
            const response = await nuiRequest('pc:browser:buyDomain', { domain, templateId });
            if (!response || !response.ok) {
                this.showNotification(response && response.error ? response.error.replace(/_/g, ' ') : 'Purchase failed');
                return;
            }
            this.showNotification('Domain purchased successfully!');
            this.loadUrl(response.data.domain);
        });

        // Open domain buttons
        container.querySelectorAll('[data-open-domain]').forEach(btn => {
            btn.addEventListener('click', () => this.loadUrl(btn.dataset.openDomain));
        });

        // Transfer domain buttons
        container.querySelectorAll('[data-transfer-domain]').forEach(btn => {
            btn.addEventListener('click', async () => {
                const targetIdentifier = (await uiPrompt('Enter the citizen identifier to transfer this domain to:', '', {
                    title: 'Transfer Domain',
                    submitLabel: 'Next'
                }))?.trim();
                if (!targetIdentifier) return;
                const targetName = (await uiPrompt('Enter the display name for the new owner:', targetIdentifier, {
                    title: 'Transfer Domain',
                    submitLabel: 'Transfer'
                })) || targetIdentifier;
                const response = await nuiRequest('pc:browser:transferDomain', {
                    domain: btn.dataset.transferDomain,
                    targetIdentifier,
                    targetName
                });
                if (!response || !response.ok) {
                    this.showNotification(response && response.error ? response.error.replace(/_/g, ' ') : 'Transfer failed');
                    return;
                }
                this.showNotification('Domain transferred successfully');
                this.renderDomainsPage(container);
            });
        });

        // Tab navigation
        container.querySelectorAll('.dom-nav-btn').forEach((btn, idx) => {
            btn.addEventListener('click', () => {
                container.querySelectorAll('.dom-nav-btn').forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                
                const panels = container.querySelectorAll('.dom-panel');
                panels.forEach(p => p.style.display = 'none');
                
                if (idx === 0) {
                    panels[0].style.display = 'block';
                    panels[1].style.display = 'block';
                } else if (idx === 1) {
                    panels[1].style.display = 'block';
                } else {
                    panels[2].style.display = 'block';
                }
            });
        });
    }

    async renderServicesPage(container) {
        const response = await nuiRequest('pc:browser:getConfig', {});
        const config = response && response.ok ? (response.data || {}) : {};
        const intents = (config.assistant && config.assistant.Intents) || [];
        const locations = (config.assistant && config.assistant.Locations) || [];
        const esc = (value) => this.escapeHtml(value);

        container.innerHTML = `
            <div class="browser-page-shell">
                <div class="browser-page-header">
                    <div>
                        <div class="browser-page-kicker">Public Services</div>
                        <h1>Guides and city services</h1>
                        <p>Quick help for deliveries, permits, laws, taxes, and common city locations.</p>
                    </div>
                </div>
                <div class="browser-grid-two">
                    <section class="browser-panel-card">
                        <h3>Guides</h3>
                        <div class="browser-service-list">
                            ${intents.map(intent => `
                                <button class="browser-link-item browser-link-item--full" data-guide-url="${esc(intent.url || '')}">
                                    <strong>${esc(intent.title || intent.id)}</strong>
                                    <span>${esc(intent.body || '')}</span>
                                </button>
                            `).join('')}
                        </div>
                    </section>
                    <section class="browser-panel-card">
                        <h3>Locations</h3>
                        <div class="browser-service-list">
                            ${locations.map(location => `
                                <div class="browser-location-card">
                                    <strong>${esc(location.name)}</strong>
                                    <span>${esc(location.description || '')}</span>
                                    <small>${esc(location.street || '')}</small>
                                    <button class="btn btn-secondary btn-small" data-waypoint='${JSON.stringify(location.coords || {})}'>Set Waypoint</button>
                                </div>
                            `).join('')}
                        </div>
                    </section>
                </div>
            </div>
        `;

        container.querySelectorAll('[data-guide-url]').forEach(btn => {
            btn.addEventListener('click', () => btn.dataset.guideUrl && this.loadUrl(btn.dataset.guideUrl));
        });
        container.querySelectorAll('[data-waypoint]').forEach(btn => {
            btn.addEventListener('click', async () => {
                const coords = JSON.parse(btn.dataset.waypoint || '{}');
                await nuiRequest('pc:setWaypoint', coords);
                this.showNotification('Waypoint set');
            });
        });
    }

    renderSearchPage(container, url) {
        const queryMatch = /[?&]q=([^&]+)/i.exec(url);
        const query = queryMatch ? decodeURIComponent(queryMatch[1]) : '';
        container.innerHTML = `
            <div class="browser-page-shell">
                <div class="browser-page-header">
                    <div>
                        <div class="browser-page-kicker">Search</div>
                        <h1>Search results for "${this.escapeHtml(query)}"</h1>
                        <p>Use the guide box on the start page for smart city help, or enter a full domain in the address bar.</p>
                    </div>
                </div>
            </div>
        `;
    }

    buildModuleLibrary() {
        return {
            hero: { title: 'Hero', defaults: { title: 'Page Heading', body: 'Introduce the page here.', buttonLabel: 'Action', buttonUrl: '' } },
            text: { title: 'Text Section', defaults: { title: 'Section Title', body: 'Write your content here.' } },
            callout: { title: 'Callout', defaults: { title: 'Important Notice', body: 'Highlight a message for visitors.' } },
            cards: { title: 'Cards Grid', defaults: { title: 'Highlights', items: [{ title: 'Card One', body: 'Describe the first item.' }, { title: 'Card Two', body: 'Describe the second item.' }] } },
            links: { title: 'Quick Links', defaults: { title: 'Quick Links', items: [{ label: 'Home', url: 'home' }, { label: 'Contact', url: 'contact' }] } },
            image: { title: 'Image', defaults: { title: 'Image', imageUrl: '', body: 'Use a hosted image URL for your logo or content.' } }
        };
    }

    normalizeWebsiteState(domain, state) {
        const raw = state && typeof state === 'object' ? state : {};
        const pages = raw.pages && typeof raw.pages === 'object' ? raw.pages : {};
        if (!pages.home) {
            pages.home = { title: 'Home', modules: [] };
        }
        Object.keys(pages).forEach((key) => {
            const page = pages[key] || {};
            page.title = page.title || key;
            page.modules = Array.isArray(page.modules) ? page.modules.map((module, index) => ({
                id: module.id || `${key}_${index}_${Date.now()}`,
                type: module.type || 'text',
                title: module.title || '',
                body: module.body || '',
                buttonLabel: module.buttonLabel || '',
                buttonUrl: module.buttonUrl || '',
                imageUrl: this.normalizeImageSource(module.imageUrl || ''),
                items: Array.isArray(module.items) ? module.items : []
            })) : [];
            pages[key] = page;
        });

        const rawTheme = raw.theme && typeof raw.theme === 'object' ? raw.theme : {};
        const defaultTheme = { accent: '#143d6b', background: '#f5f7fb', surface: '#ffffff', text: '#10233a' };

        return {
            domain,
            owner: raw.owner || {},
            theme: {
                accent: this.normalizeThemeColor(rawTheme.accent, defaultTheme.accent),
                background: this.normalizeThemeColor(rawTheme.background, defaultTheme.background),
                surface: this.normalizeThemeColor(rawTheme.surface, defaultTheme.surface),
                text: this.normalizeThemeColor(rawTheme.text, defaultTheme.text)
            },
            branding: {
                siteName: (raw.branding && raw.branding.siteName) || domain,
                tagline: (raw.branding && raw.branding.tagline) || 'Player-owned website',
                logoUrl: this.normalizeImageSource(raw.branding && raw.branding.logoUrl)
            },
            pages,
            updatedAt: raw.updatedAt || null
        };
    }

    getSitePresentationClass(site) {
        const domain = String(site && site.domain || '').toLowerCase();
        const name = String(site && site.state && site.state.branding && site.state.branding.siteName || '').toLowerCase();
        const tag = `${domain} ${name}`;
        if (tag.includes('video') || tag.includes('tube') || tag.includes('stream')) return 'site-template-media';
        if (tag.includes('gov') || tag.includes('city') || tag.includes('state')) return 'site-template-government';
        if (tag.includes('shop') || tag.includes('store') || tag.includes('pizza') || tag.includes('burger')) return 'site-template-store';
        return 'site-template-business';
    }

    renderSiteModule(module) {
        const esc = (value) => this.escapeHtml(value);
        if (module.type === 'hero') {
            return `
                <section class="site-module site-module-hero">
                    <div class="site-module-hero-copy">
                        <div class="site-module-kicker">Featured</div>
                        <h2>${esc(module.title)}</h2>
                        <p>${esc(module.body)}</p>
                        ${module.buttonLabel ? `<button class="btn btn-primary" data-module-link="${esc(module.buttonUrl || '')}">${esc(module.buttonLabel)}</button>` : ''}
                    </div>
                </section>
            `;
        }
        if (module.type === 'callout') {
            return `<section class="site-module site-module-callout"><div class="site-module-kicker">Notice</div><strong>${esc(module.title)}</strong><p>${esc(module.body)}</p></section>`;
        }
        if (module.type === 'cards') {
            return `
                <section class="site-module site-module-panel">
                    <div class="site-module-heading-wrap"><div class="site-module-kicker">Highlights</div><div class="site-module-heading">${esc(module.title)}</div></div>
                    <div class="site-cards-grid">
                        ${(module.items || []).map(item => `<article class="site-card"><div class="site-card-media"></div><h4>${esc(item.title)}</h4><p>${esc(item.body)}</p><span class="site-card-link">Learn more</span></article>`).join('')}
                    </div>
                </section>
            `;
        }
        if (module.type === 'links') {
            return `
                <section class="site-module site-module-panel">
                    <div class="site-module-heading-wrap"><div class="site-module-kicker">Explore</div><div class="site-module-heading">${esc(module.title)}</div></div>
                    <div class="site-links-grid">
                        ${(module.items || []).map(item => `<button class="site-link-pill" data-module-link="${esc(item.url || '')}"><span>${esc(item.label || item.url || 'Link')}</span><i class="fas fa-arrow-right"></i></button>`).join('')}
                    </div>
                </section>
            `;
        }
        if (module.type === 'image') {
            const imageSrc = this.normalizeImageSource(module.imageUrl);
            return `
                <section class="site-module site-module-image site-module-panel">
                    <div class="site-image-frame">${imageSrc ? `<img src="${esc(imageSrc)}" alt="${esc(module.title || 'Image')}" onerror="this.style.display='none'; this.insertAdjacentHTML('afterend', '<div class="site-image-placeholder">Image failed to load</div>');">` : '<div class="site-image-placeholder">No image URL set</div>'}</div>
                    <div><div class="site-module-kicker">Featured image</div><div class="site-module-heading">${esc(module.title)}</div><p>${esc(module.body)}</p></div>
                </section>
            `;
        }
        return `<section class="site-module site-module-panel"><div class="site-module-kicker">Section</div><div class="site-module-heading">${esc(module.title)}</div><p>${esc(module.body)}</p></section>`;
    }


    async renderCustomSite(container, url) {
        const domain = this.getShortDomain(url);
        const response = await nuiRequest('pc:browser:getWebsite', { domain });
        if (!response || !response.ok) {
            this.renderGenericPage(container, url);
            return;
        }

        const payload = response.data || {};
        if (payload.kind === 'government') {
            this.renderGovPortal(container, url);
            return;
        }

        const state = this.normalizeWebsiteState(domain, payload.state || {});
        this.currentSite = { domain, editable: !!payload.editable, state, currentPage: 'home', editing: false };
        this.renderCurrentCustomSite(container);
    }

    renderCurrentCustomSite(container) {
        const site = this.currentSite;
        if (!site) return;
        const state = site.state;
        const currentPage = site.currentPage in state.pages ? site.currentPage : 'home';
        const current = state.pages[currentPage];
        const esc = (value) => this.escapeHtml(value);

        const presentationClass = this.getSitePresentationClass(site);
        container.innerHTML = `
            <div class="player-site ${presentationClass}" style="--site-accent:${esc(state.theme.accent)};--site-bg:${esc(state.theme.background)};--site-surface:${esc(state.theme.surface)};--site-text:${esc(state.theme.text)};">
                <div class="player-site-topbar">
                    <span>Verified site</span>
                    <span>${esc(site.domain)}</span>
                    <span>${esc(state.updatedAt ? new Date(state.updatedAt).toLocaleDateString() : 'Published')}</span>
                </div>
                <header class="player-site-header">
                    <div class="player-site-branding">
                        ${state.branding.logoUrl ? `<img class="player-site-logo" src="${esc(state.branding.logoUrl)}" alt="${esc(state.branding.siteName)}" onerror="this.style.display='none';">` : '<div class="player-site-logo player-site-logo-fallback"><i class="fas fa-globe"></i></div>'}
                        <div>
                            <div class="player-site-domain">${esc(site.domain)}</div>
                            <h1>${esc(state.branding.siteName || site.domain)}</h1>
                            <p>${esc(state.branding.tagline || '')}</p>
                        </div>
                    </div>
                    <div class="player-site-header-actions">
                        ${site.editable ? `<button class="btn btn-secondary" id="site-toggle-editor">${site.editing ? 'Close Editor' : 'Edit Site'}</button>` : ''}
                        <button class="btn btn-secondary" id="site-bookmark-btn">Bookmark</button>
                    </div>
                </header>
                <nav class="player-site-nav">
                    <div class="player-site-nav-links">
                    ${Object.keys(state.pages).map(key => `<button class="player-site-nav-btn ${key === currentPage ? 'active' : ''}" data-site-page="${esc(key)}">${esc(state.pages[key].title || key)}</button>`).join('')}
                    </div>
                    <button class="player-site-nav-cta">Contact</button>
                </nav>
                <main class="player-site-main">
                    <div class="player-site-content">
                        ${(current.modules || []).map(module => this.renderSiteModule(module)).join('') || '<div class="gov-empty">No modules on this page yet.</div>'}
                    </div>
                    ${site.editing && site.editable ? this.renderSiteEditor(state, currentPage) : ''}
                </main>
            </div>
        `;

        // Apply theme to the site
        this.applyCustomSiteTheme(container, site);

        container.querySelectorAll('[data-site-page]').forEach(btn => {
            btn.addEventListener('click', () => {
                this.currentSite.currentPage = btn.dataset.sitePage;
                this.renderCurrentCustomSite(container);
            });
        });

        container.querySelector('#site-toggle-editor')?.addEventListener('click', () => {
            this.currentSite.editing = !this.currentSite.editing;
            this.renderCurrentCustomSite(container);
        });
        container.querySelector('#site-bookmark-btn')?.addEventListener('click', () => this.toggleBookmarkCurrent());

        container.querySelectorAll('[data-module-link]').forEach(btn => {
            btn.addEventListener('click', () => {
                const target = btn.dataset.moduleLink || '';
                if (!target) return;
                if (state.pages[target]) {
                    this.currentSite.currentPage = target;
                    this.renderCurrentCustomSite(container);
                    return;
                }
                this.loadUrl(target);
            });
        });

        if (site.editing && site.editable) {
            this.bindSiteEditorEvents(container);
        }
    }

    applyCustomSiteTheme(container, site) {
        const themeMode = site.state.themeMode || 'auto';
        const playerSite = container.querySelector('.player-site');
        
        if (!playerSite) return;
        
        // Determine if dark mode should be applied
        let isDarkMode = false;
        
        if (themeMode === 'dark') {
            isDarkMode = true;
        } else if (themeMode === 'auto') {
            // Check system preference
            isDarkMode = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
        }
        
        // Apply theme class
        if (isDarkMode) {
            playerSite.classList.add('dark-mode');
            playerSite.setAttribute('data-site-theme', 'dark');
        } else {
            playerSite.classList.remove('dark-mode');
            playerSite.setAttribute('data-site-theme', 'light');
        }
    }

    renderSiteEditor(state, currentPage) {
        const library = this.buildModuleLibrary();
        const page = state.pages[currentPage];
        const esc = (value) => this.escapeHtml(value);
        return `
            <aside class="site-editor-panel">
                <div class="site-editor-section site-editor-theme-toggle">
                    <div class="site-editor-heading">Website Theme</div>
                    <div class="site-theme-mode-selector">
                        <label class="site-theme-label">
                            <input type="radio" name="site-theme-mode" value="light" class="site-theme-radio"> Light Mode
                        </label>
                        <label class="site-theme-label">
                            <input type="radio" name="site-theme-mode" value="dark" class="site-theme-radio"> Dark Mode
                        </label>
                        <label class="site-theme-label">
                            <input type="radio" name="site-theme-mode" value="auto" class="site-theme-radio" checked> Auto (System)
                        </label>
                    </div>
                </div>
                <div class="site-editor-section">
                    <div class="site-editor-heading">Branding</div>
                    <input id="site-name-input" class="form-input" type="text" value="${esc(state.branding.siteName || '')}" placeholder="Site name">
                    <input id="site-tagline-input" class="form-input" type="text" value="${esc(state.branding.tagline || '')}" placeholder="Tagline">
                    <input id="site-logo-input" class="form-input" type="text" value="${esc(state.branding.logoUrl || '')}" placeholder="Logo URL (https://..., cfx-nui-resource/path, or resource/path)">
                    <div class="site-theme-grid">
                        <input id="site-accent-input" class="form-input" type="text" value="${esc(state.theme.accent || '')}" placeholder="Accent color (#143d6b)">
                        <input id="site-surface-input" class="form-input" type="text" value="${esc(state.theme.surface || '')}" placeholder="Surface color (#ffffff)">
                        <input id="site-background-input" class="form-input" type="text" value="${esc(state.theme.background || '')}" placeholder="Background color (#f5f7fb)">
                        <input id="site-text-input" class="form-input" type="text" value="${esc(state.theme.text || '')}" placeholder="Text color (#10233a)">
                    </div>
                </div>
                <div class="site-editor-section">
                    <div class="site-editor-heading">Pages</div>
                    <div class="site-editor-page-list">
                        ${Object.keys(state.pages).map(key => `<button class="site-editor-page-btn ${key === currentPage ? 'active' : ''}" data-editor-page="${esc(key)}">${esc(state.pages[key].title || key)}</button>`).join('')}
                    </div>
                    <div class="site-editor-inline">
                        <input id="site-new-page-input" class="form-input" type="text" placeholder="new-page">
                        <button id="site-add-page" class="btn btn-secondary btn-small">Add Page</button>
                    </div>
                </div>
                <div class="site-editor-section">
                    <div class="site-editor-heading">Current Page</div>
                    <input id="site-page-title-input" class="form-input" type="text" value="${esc(page.title || currentPage)}" placeholder="Page title">
                    <div class="site-editor-module-list">
                        ${(page.modules || []).map((module, index) => `
                            <div class="site-editor-module" data-module-index="${index}">
                                <div class="site-editor-module-head">
                                    <strong>${esc(module.type)}</strong>
                                    <button class="btn btn-secondary btn-small" data-remove-module="${index}">Delete</button>
                                </div>
                                <input class="form-input" data-field="title" value="${esc(module.title || '')}" placeholder="Module title">
                                <textarea class="form-input" data-field="body" placeholder="Module body">${esc(module.body || '')}</textarea>
                                ${module.type === 'hero' ? `<div class="site-editor-inline"><input class="form-input" data-field="buttonLabel" value="${esc(module.buttonLabel || '')}" placeholder="Button label"><input class="form-input" data-field="buttonUrl" value="${esc(module.buttonUrl || '')}" placeholder="Button URL or page slug"></div>` : ''}
                                ${module.type === 'image' ? `<input class="form-input" data-field="imageUrl" value="${esc(module.imageUrl || '')}" placeholder="Image URL">` : ''}
                                ${(module.type === 'cards' || module.type === 'links') ? `<textarea class="form-input" data-field="itemsJson" placeholder='[{"title":"Card","body":"Text"}]'>${esc(JSON.stringify(module.items || []))}</textarea>` : ''}
                            </div>
                        `).join('') || '<div class="gov-empty">No modules to edit.</div>'}
                    </div>
                    <div class="site-editor-add-grid">
                        ${Object.keys(library).map(key => `<button class="btn btn-secondary btn-small" data-add-module="${esc(key)}">+ ${esc(library[key].title)}</button>`).join('')}
                    </div>
                    <button id="site-save-btn" class="btn btn-primary">Save Website</button>
                </div>
            </aside>
        `;
    }

    bindSiteEditorEvents(container) {
        const site = this.currentSite;
        if (!site) return;

        // Theme mode switching
        container.querySelectorAll('.site-theme-radio').forEach(radio => {
            radio.addEventListener('change', (e) => {
                site.state.themeMode = e.target.value;
                this.applyCustomSiteTheme(container, site);
            });
            // Set the current theme mode as checked
            if (radio.value === (site.state.themeMode || 'auto')) {
                radio.checked = true;
            }
        });

        container.querySelectorAll('[data-editor-page]').forEach(btn => {
            btn.addEventListener('click', () => {
                site.currentPage = btn.dataset.editorPage;
                this.renderCurrentCustomSite(container);
            });
        });

        container.querySelector('#site-add-page')?.addEventListener('click', () => {
            const slug = String(container.querySelector('#site-new-page-input')?.value || '').trim().toLowerCase().replace(/[^a-z0-9\-]/g, '-');
            if (!slug || site.state.pages[slug]) return;
            site.state.pages[slug] = { title: slug, modules: [] };
            site.currentPage = slug;
            this.renderCurrentCustomSite(container);
        });

        container.querySelectorAll('[data-add-module]').forEach(btn => {
            btn.addEventListener('click', () => {
                const type = btn.dataset.addModule;
                const library = this.buildModuleLibrary();
                const template = library[type];
                if (!template) return;
                const page = site.state.pages[site.currentPage];
                page.modules.push(Object.assign({ id: `${type}_${Date.now()}`, type }, JSON.parse(JSON.stringify(template.defaults))));
                this.renderCurrentCustomSite(container);
            });
        });

        container.querySelectorAll('[data-remove-module]').forEach(btn => {
            btn.addEventListener('click', () => {
                const index = Number(btn.dataset.removeModule);
                const page = site.state.pages[site.currentPage];
                page.modules.splice(index, 1);
                this.renderCurrentCustomSite(container);
            });
        });

        container.querySelector('#site-save-btn')?.addEventListener('click', async () => {
            site.state.branding.siteName = container.querySelector('#site-name-input')?.value || site.state.branding.siteName;
            site.state.branding.tagline = container.querySelector('#site-tagline-input')?.value || '';
            site.state.branding.logoUrl = this.normalizeImageSource(container.querySelector('#site-logo-input')?.value || '');
            site.state.theme.accent = this.normalizeThemeColor(container.querySelector('#site-accent-input')?.value, site.state.theme.accent);
            site.state.theme.surface = this.normalizeThemeColor(container.querySelector('#site-surface-input')?.value, site.state.theme.surface);
            site.state.theme.background = this.normalizeThemeColor(container.querySelector('#site-background-input')?.value, site.state.theme.background);
            site.state.theme.text = this.normalizeThemeColor(container.querySelector('#site-text-input')?.value, site.state.theme.text);
            const page = site.state.pages[site.currentPage];
            page.title = container.querySelector('#site-page-title-input')?.value || page.title;

            container.querySelectorAll('.site-editor-module').forEach(moduleEl => {
                const index = Number(moduleEl.dataset.moduleIndex);
                const module = page.modules[index];
                if (!module) return;
                module.title = moduleEl.querySelector('[data-field="title"]')?.value || '';
                module.body = moduleEl.querySelector('[data-field="body"]')?.value || '';
                if (moduleEl.querySelector('[data-field="buttonLabel"]')) module.buttonLabel = moduleEl.querySelector('[data-field="buttonLabel"]')?.value || '';
                if (moduleEl.querySelector('[data-field="buttonUrl"]')) module.buttonUrl = moduleEl.querySelector('[data-field="buttonUrl"]')?.value || '';
                if (moduleEl.querySelector('[data-field="imageUrl"]')) module.imageUrl = this.normalizeImageSource(moduleEl.querySelector('[data-field="imageUrl"]')?.value || '');
                if (moduleEl.querySelector('[data-field="itemsJson"]')) {
                    try {
                        const parsed = JSON.parse(moduleEl.querySelector('[data-field="itemsJson"]')?.value || '[]');
                        module.items = Array.isArray(parsed) ? parsed : [];
                    } catch (e) {
                        module.items = [];
                    }
                }
            });

            const response = await nuiRequest('pc:browser:saveWebsite', {
                domain: site.domain,
                state: site.state
            });
            if (!response || !response.ok) {
                this.showNotification(response && response.error ? response.error.replace(/_/g, ' ') : 'Failed to save website');
                return;
            }
            this.showNotification('Website saved');
            site.editing = false;
            this.renderCurrentCustomSite(container);
        });
    }

    renderGenericPage(container, url) {
        container.innerHTML = `
            <div class="browser-page-shell">
                <div class="browser-page-header">
                    <div>
                        <div class="browser-page-kicker">Website unavailable</div>
                        <h1>${this.escapeHtml(this.getShortDomain(url))}</h1>
                        <p>This domain has not been registered yet. Use domains.ls to purchase it and publish a player-owned website.</p>
                    </div>
                    <button class="btn btn-primary" id="browser-open-domains">Open Domains</button>
                </div>
            </div>
        `;
        container.querySelector('#browser-open-domains')?.addEventListener('click', () => this.loadUrl('domains.ls'));
    }

    isGovUrl(url) {
        return /los-santos\.gov|gov\.ls|cityhall\.ls/i.test(url);
    }

    async renderGovPortal(container, url) {
        const [announcementResult, lawsResult, taxesResult, websiteStateResult] = await Promise.all([
            nuiRequest('pc:getAnnouncements', {}),
            nuiRequest('pc:getGovLaws', {}),
            nuiRequest('pc:getGovTaxes', {}),
            nuiRequest('pc:getGovWebsiteState', {})
        ]);

        const announcements = announcementResult && announcementResult.ok ? (announcementResult.data || []) : [];
        const laws = lawsResult && lawsResult.ok ? (lawsResult.data || []) : [];
        const taxes = taxesResult && taxesResult.ok ? (taxesResult.data || []) : [];
        const websiteState = websiteStateResult && websiteStateResult.ok && websiteStateResult.data && typeof websiteStateResult.data === 'object'
            ? websiteStateResult.data
            : {};
        const siteChrome = websiteState.siteChrome || {};
        const pageState = websiteState.pages || {};
        const homePage = pageState.home || {};
        const esc = (value) => {
            const div = document.createElement('div');
            div.textContent = value == null ? '' : String(value);
            return div.innerHTML;
        };

        const sortedAnnouncements = [...announcements].sort((a, b) => {
            const at = new Date(a.createdAt || a.created_at || 0).getTime();
            const bt = new Date(b.createdAt || b.created_at || 0).getTime();
            return bt - at;
        });

        const sortedLaws = [...laws].filter((law) => String(law.status || 'active').toLowerCase() === 'active').sort((a, b) => {
            const at = new Date(a.effective_date || a.updated_at || a.created_at || 0).getTime();
            const bt = new Date(b.effective_date || b.updated_at || b.created_at || 0).getTime();
            return bt - at;
        });

        const lawCategories = Array.from(new Set(sortedLaws.map((law) => String(law.category || 'General')))).sort((a, b) => a.localeCompare(b));

        const announcementCards = sortedAnnouncements.map(item => {
            const date = item.createdAt || item.created_at ? new Date(item.createdAt || item.created_at).toLocaleString() : 'Just now';
            return `
                <article class="gov-news-card">
                    <div class="gov-news-meta">
                        <span>${esc(item.author || item.created_by_name || 'Mayor')} • ${esc(date)}</span>
                    </div>
                    <h3>${esc(item.title || 'Announcement')}</h3>
                    <p>${esc(item.body || item.content || '')}</p>
                </article>
            `;
        }).join('');

        const lawCards = sortedLaws.map(law => {
            const source = law.source === 'pf-policemdt' ? 'MDT Records' : 'Government Records';
            const penalty = Number(law.penalty_min || 0) > 0 || Number(law.penalty_max || 0) > 0
                ? `${Number(law.penalty_min || 0)}-${Number(law.penalty_max || 0)} months`
                : 'No jail range';
            const fine = Number(law.fine_min || 0) > 0 || Number(law.fine_max || 0) > 0
                ? `$${Number(law.fine_min || 0).toLocaleString()}-$${Number(law.fine_max || 0).toLocaleString()}`
                : 'No fine range';
            return `
                <article class="gov-law-card" data-law-category="${esc(String(law.category || 'General').toLowerCase())}">
                    <div class="gov-law-top">
                        <span class="gov-law-category">${esc(law.category || 'General')}</span>
                        <span class="gov-law-status active">Active</span>
                    </div>
                    <h3>${esc(law.title || 'Untitled Law')}</h3>
                    <p>${esc((law.content || '').slice(0, 220))}${(law.content || '').length > 220 ? '...' : ''}</p>
                    <div class="gov-law-meta">Source: ${esc(source)} | Penalty: ${esc(penalty)} | Fine: ${esc(fine)}</div>
                </article>
            `;
        }).join('');

        const taxRows = [...taxes].sort((a, b) => String(a.tax_type || '').localeCompare(String(b.tax_type || ''))).map(tax => `
            <tr>
                <td>${esc(String(tax.tax_type || '').replace(/_/g, ' '))}</td>
                <td>${esc(String(tax.description || 'No description provided.'))}</td>
                <td>${Number(tax.rate || 0)}%</td>
                <td>${Number(tax.min_rate || 0)}% - ${Number(tax.max_rate || 0)}%</td>
            </tr>
        `).join('');

        container.innerHTML = `
            <div class="gov-site">
                <header class="gov-topline">
                    <div class="gov-brand">${esc(siteChrome.brandKicker || 'City of Los Santos')}</div>
                    <nav class="gov-primary-nav">
                        <button class="gov-main-nav active" data-page="home">Home</button>
                        <button class="gov-main-nav" data-page="announcements">Announcements</button>
                        <button class="gov-main-nav" data-page="laws">Laws</button>
                        <button class="gov-main-nav" data-page="taxes">Taxes</button>
                        <button class="gov-main-nav" data-page="policies">Departments</button>
                    </nav>
                </header>

                <div class="gov-hero gov-page active" data-page="home">
                    <div class="gov-hero-text">
                        <h1>${esc(homePage.title || siteChrome.brandTitle || 'Los Santos Municipal Portal')}</h1>
                        <p>${esc(homePage.intro || siteChrome.brandSubtitle || 'Official city website for public notices, active law references, tax schedules, and department policy guidance.')}</p>
                    </div>
                    <div class="gov-hero-badge">${esc(url)}</div>
                </div>

                <section class="gov-directory gov-page active" data-page="home">
                    <div class="gov-directory-item">
                        <strong>${esc(siteChrome.homeSidebarLine1 || 'Office Of The Mayor')}</strong>
                        <span>Civic planning, budgeting, and public administration.</span>
                    </div>
                    <div class="gov-directory-item">
                        <strong>Public Records</strong>
                        <span>Laws, notices, and archives are available online.</span>
                    </div>
                    <div class="gov-directory-item">
                        <strong>Citizen Support</strong>
                        <span>Use announcements and policy pages for current updates.</span>
                    </div>
                </section>

                <section class="gov-panel gov-page active" data-page="announcements" style="display:none;">
                        <div class="gov-news-grid">
                            ${announcementCards || '<div class="gov-empty">No announcements yet.</div>'}
                        </div>
                </section>

                <section class="gov-panel gov-page" data-page="laws" style="display:none;">
                        <div class="gov-laws-layout">
                            <aside class="gov-laws-sidebar">
                                <h3>Law Categories</h3>
                                <button class="gov-law-filter active" data-law-filter="all">All Categories</button>
                                ${lawCategories.map(cat => `<button class="gov-law-filter" data-law-filter="${esc(String(cat).toLowerCase())}">${esc(cat)}</button>`).join('')}
                            </aside>
                            <div class="gov-laws-grid">
                                ${lawCards || '<div class="gov-empty">No active laws available.</div>'}
                            </div>
                        </div>
                </section>

                <section class="gov-panel gov-page" data-page="taxes" style="display:none;">
                    <div class="gov-news-header"><h2>Current Tax Schedule</h2><span>${taxes.length} configured rates</span></div>
                    <div class="table-container">
                        <table class="data-table">
                            <thead><tr><th>Tax Type</th><th>Purpose</th><th>Current Rate</th><th>Allowed Range</th></tr></thead>
                            <tbody>${taxRows || '<tr><td colspan="4" class="text-muted">No tax records available.</td></tr>'}</tbody>
                        </table>
                    </div>
                </section>

                <section class="gov-panel gov-page" data-page="policies" style="display:none;">
                    <div class="gov-news-header"><h2>Department Policy Hub</h2></div>
                    <div class="gov-news-grid">
                        <article class="gov-news-card"><h3>Public Safety Departments</h3><p>Police, EMS, and fire operations are funded through approved budgets and compliance standards.</p></article>
                        <article class="gov-news-card"><h3>Utilities And Infrastructure</h3><p>Power, water, and road services are managed by city departments with staged service response planning.</p></article>
                        <article class="gov-news-card"><h3>Treasury And Tax Administration</h3><p>Taxes and treasury controls fund public operations and critical city services.</p></article>
                    </div>
                </section>

                <footer class="gov-site-footer">
                    <div class="gov-site-footer-grid">
                        <div>
                            <div class="gov-site-footer-title">${esc(siteChrome.footerAboutTitle || 'City of Los Santos')}</div>
                            <p>${esc(siteChrome.footerAboutBody || 'Official municipal portal for public notices, ordinances, taxation, and administrative services.')}</p>
                        </div>
                        <div>
                            <div class="gov-site-footer-title">${esc(siteChrome.footerResourcesTitle || 'Public Resources')}</div>
                            <ul>
                                ${(Array.isArray(siteChrome.footerResourcesItems) ? siteChrome.footerResourcesItems : ['Public Notices', 'Municipal Code', 'Tax Schedule']).map((item) => `<li>${esc(item)}</li>`).join('')}
                            </ul>
                        </div>
                        <div>
                            <div class="gov-site-footer-title">${esc(siteChrome.footerContactTitle || 'Contact')}</div>
                            <p>${esc(siteChrome.footerContactAddress || 'Alta Street, Los Santos')}</p>
                            <p>${esc(siteChrome.footerContactHours || 'Mon - Fri, 08:00 to 17:00')}</p>
                        </div>
                    </div>
                </footer>
            </div>
        `;

        const navButtons = container.querySelectorAll('.gov-main-nav');
        const pages = container.querySelectorAll('.gov-page');
        const showPage = (page) => {
            navButtons.forEach(btn => btn.classList.toggle('active', btn.dataset.page === page));
            pages.forEach(section => {
                const active = section.dataset.page === page || (page === 'home' && section.dataset.page === 'home');
                section.style.display = active ? '' : 'none';
            });
        };

        container.querySelectorAll('.gov-law-filter').forEach(btn => {
            btn.addEventListener('click', () => {
                container.querySelectorAll('.gov-law-filter').forEach(item => item.classList.remove('active'));
                btn.classList.add('active');
                const filter = btn.dataset.lawFilter || 'all';
                container.querySelectorAll('.gov-law-card').forEach(card => {
                    const category = card.dataset.lawCategory || '';
                    card.style.display = filter === 'all' || filter === category ? '' : 'none';
                });
            });
        });

        navButtons.forEach(btn => btn.addEventListener('click', () => showPage(btn.dataset.page)));
        showPage('home');
    }

    back() {
        if (this.historyIndex > 0) {
            this.historyIndex -= 1;
            const previousUrl = this.history[this.historyIndex];
            this.loadUrl(previousUrl, true);
        }
    }

    forward() {
        if (this.historyIndex < this.history.length - 1) {
            this.historyIndex += 1;
            const nextUrl = this.history[this.historyIndex];
            this.loadUrl(nextUrl, true);
        }
    }

    refresh() {
        if (this.currentUrl) {
            this.loadUrl(this.currentUrl, true);
        }
    }

    home() {
        this.loadUrl(this.homeUrl);
    }

    toggleBookmarkCurrent() {
        if (!this.currentUrl) return;
        const idx = this.bookmarks.findIndex(bookmark => this.normalizeUrl(bookmark.url) === this.currentUrl);
        if (idx >= 0) {
            this.bookmarks.splice(idx, 1);
            this.showNotification('Bookmark removed');
        } else {
            const title = this.currentUrl.replace(/^https?:\/\//i, '');
            this.bookmarks.push({ name: title, url: this.currentUrl });
            this.showNotification('Bookmarked');
        }
        this.saveBookmarks();
    }

    showNotification(message) {
        const notification = document.createElement('div');
        notification.className = 'notification';
        notification.textContent = message;
        document.body.appendChild(notification);
        setTimeout(() => notification.remove(), 2000);
    }
}

// ============================================================================
// MAIL APP MANAGER
// ============================================================================
class MailManager {
    constructor() {
        // Auth state
        this.accounts = this.loadAccounts();
        this.currentAccount = this.loadCurrentAccount();
        this.recentAccounts = this.loadRecentAccounts();

        // Mail state
        this.emails = [];
        this.currentFolder = 'inbox';
        this.currentEmailId = null;

        this.init();
    }

    // ── Auth storage ──────────────────────────────────────────────────────────

    loadAccounts() {
        try { return JSON.parse(scopedStorageGet('mail_accounts', '[]') || '[]'); } catch { return []; }
    }

    saveAccounts() {
        scopedStorageSet('mail_accounts', JSON.stringify(this.accounts));
    }

    loadCurrentAccount() {
        return scopedStorageGet('mail_current_account') || null;
    }

    saveCurrentAccount() {
        if (this.currentAccount) {
            scopedStorageSet('mail_current_account', this.currentAccount);
        } else {
            scopedStorageRemove('mail_current_account');
        }
    }

    loadRecentAccounts() {
        try { return JSON.parse(scopedStorageGet('mail_recent_accounts', '[]') || '[]'); } catch { return []; }
    }

    saveRecentAccounts() {
        scopedStorageSet('mail_recent_accounts', JSON.stringify(this.recentAccounts));
    }

    pushRecentAccount(email) {
        this.recentAccounts = [email, ...this.recentAccounts.filter(e => e !== email)].slice(0, 3);
        this.saveRecentAccounts();
    }

    // ── Email storage (per-account) ───────────────────────────────────────────

    emailKey(account) {
        return `mail_emails_${account || this.currentAccount || 'global'}`;
    }

    loadEmails(account) {
        try {
            const stored = scopedStorageGet(this.emailKey(account));
            if (stored) return JSON.parse(stored);
        } catch {}
        const addr = account || this.currentAccount || 'your account';
        return [
            {
                id: 1,
                from: 'Mail System',
                subject: 'Welcome to Mail',
                preview: `Your account ${addr} is ready to use.`,
                body: `Welcome! Your account ${addr} has been successfully created. You can now send and receive emails.`,
                time: 'Just now',
                unread: true,
                folder: 'inbox'
            }
        ];
    }

    saveEmails() {
        if (!this.currentAccount) return;
        scopedStorageSet(this.emailKey(), JSON.stringify(this.emails));
    }

    reloadForScope() {
        this.accounts = this.loadAccounts();
        this.currentAccount = this.loadCurrentAccount();
        this.recentAccounts = this.loadRecentAccounts();
        this.currentEmailId = null;

        if (this.currentAccount) {
            this.emails = this.loadEmails(this.currentAccount);
            this.showMailView();
        } else {
            this.emails = [];
            this.showAuthScreen('login');
        }
    }

    // ── Init ──────────────────────────────────────────────────────────────────

    init() {
        this.setupAuthTabs();
        this.setupAuthForms();
        this.setupAccountMenu();
        if (this.currentAccount) {
            this.emails = this.loadEmails(this.currentAccount);
            this.showMailView();
        } else {
            this.showAuthScreen();
        }
    }

    // ── View toggling ─────────────────────────────────────────────────────────

    showAuthScreen(tab = 'login') {
        const authScreen = document.getElementById('mail-auth-screen');
        const mainView = document.getElementById('mail-main-view');
        if (authScreen) authScreen.classList.remove('hidden');
        if (mainView) mainView.classList.add('hidden');
        this.switchAuthTab(tab);
        this.clearAuthMessages();
    }

    showMailView() {
        const authScreen = document.getElementById('mail-auth-screen');
        const mainView = document.getElementById('mail-main-view');
        if (authScreen) authScreen.classList.add('hidden');
        if (mainView) mainView.classList.remove('hidden');
        const accountEl = document.getElementById('mail-account');
        if (accountEl) accountEl.textContent = this.currentAccount || 'Not logged in';
        this.setupFolders();
        this.currentFolder = 'inbox';
        this.renderMailList();
        this.renderMailView(null);
    }

    // ── Auth tabs ─────────────────────────────────────────────────────────────

    setupAuthTabs() {
        const tabs = document.querySelectorAll('#mail-auth-screen .mail-auth-tab');
        tabs.forEach(tab => {
            tab.addEventListener('click', () => {
                this.switchAuthTab(tab.dataset.tab);
                this.clearAuthMessages();
            });
        });
    }

    switchAuthTab(tab) {
        const tabs = document.querySelectorAll('#mail-auth-screen .mail-auth-tab');
        const loginForm = document.getElementById('mail-login-form');
        const registerForm = document.getElementById('mail-register-form');
        tabs.forEach(t => t.classList.toggle('active', t.dataset.tab === tab));
        if (loginForm) {
            loginForm.classList.toggle('active', tab === 'login');
            loginForm.classList.toggle('hidden', tab !== 'login');
        }
        if (registerForm) {
            registerForm.classList.toggle('active', tab === 'register');
            registerForm.classList.toggle('hidden', tab !== 'register');
        }
    }

    clearAuthMessages() {
        document.querySelectorAll('.mail-auth-message')
            .forEach(m => { m.textContent = ''; m.className = 'mail-auth-message'; });
    }

    setMessage(elId, text, type = 'error') {
        const el = document.getElementById(elId);
        if (el) { el.textContent = text; el.className = `mail-auth-message ${type}`; }
    }

    // ── Auth forms ────────────────────────────────────────────────────────────

    setupAuthForms() {
        const loginBtn = document.getElementById('mail-login-btn');
        const registerBtn = document.getElementById('mail-register-btn');
        if (loginBtn) loginBtn.addEventListener('click', () => this.login());
        if (registerBtn) registerBtn.addEventListener('click', () => this.register());
        const loginPw = document.getElementById('mail-login-password');
        if (loginPw) loginPw.addEventListener('keydown', e => { if (e.key === 'Enter') this.login(); });
        const regConfirm = document.getElementById('mail-register-confirm');
        if (regConfirm) regConfirm.addEventListener('keydown', e => { if (e.key === 'Enter') this.register(); });
    }

    login() {
        const emailEl = document.getElementById('mail-login-email');
        const passwordEl = document.getElementById('mail-login-password');
        const email = (emailEl ? emailEl.value.trim().toLowerCase() : '');
        const password = passwordEl ? passwordEl.value : '';

        if (!email || !password) {
            this.setMessage('mail-login-message', 'Please enter your email and password.');
            return;
        }
        const account = this.accounts.find(a => a.email.toLowerCase() === email);
        if (!account) {
            this.setMessage('mail-login-message', 'No account found with that email address.');
            return;
        }
        if (account.password !== password) {
            this.setMessage('mail-login-message', 'Incorrect password.');
            return;
        }
        this.currentAccount = account.email;
        this.saveCurrentAccount();
        this.pushRecentAccount(account.email);
        this.emails = this.loadEmails(account.email);
        if (emailEl) emailEl.value = '';
        if (passwordEl) passwordEl.value = '';
        this.showMailView();
    }

    register() {
        const usernameEl = document.getElementById('mail-register-username');
        const domainEl = document.getElementById('mail-register-domain');
        const passwordEl = document.getElementById('mail-register-password');
        const confirmEl = document.getElementById('mail-register-confirm');
        const username = (usernameEl ? usernameEl.value.trim() : '');
        const domain = domainEl ? domainEl.value : '';
        const password = passwordEl ? passwordEl.value : '';
        const confirm = confirmEl ? confirmEl.value : '';

        if (!username) {
            this.setMessage('mail-register-message', 'Please enter a username.');
            return;
        }
        if (!/^[a-zA-Z0-9._-]+$/.test(username)) {
            this.setMessage('mail-register-message', 'Username may only contain letters, numbers, dots, underscores and hyphens.');
            return;
        }
        if (!domain) {
            this.setMessage('mail-register-message', 'Please select a domain.');
            return;
        }
        if (!password) {
            this.setMessage('mail-register-message', 'Please enter a password.');
            return;
        }
        if (password.length < 6) {
            this.setMessage('mail-register-message', 'Password must be at least 6 characters long.');
            return;
        }
        if (password !== confirm) {
            this.setMessage('mail-register-message', 'Passwords do not match.');
            return;
        }
        const email = `${username}@${domain}`;
        if (this.accounts.find(a => a.email.toLowerCase() === email.toLowerCase())) {
            // Suggest up to 3 alternatives
            const suggestions = [];
            const candidates = [
                `${username}1`, `${username}2`, `${username}_ls`, `${username}99`, `${username}x`
            ];
            for (const alt of candidates) {
                if (suggestions.length >= 3) break;
                const altEmail = `${alt}@${domain}`;
                if (!this.accounts.find(a => a.email.toLowerCase() === altEmail.toLowerCase())) {
                    suggestions.push(altEmail);
                }
            }
            const hint = suggestions.length
                ? ` Try: ${suggestions.join(', ')}`
                : '';
            this.setMessage('mail-register-message', `That email address is already registered.${hint}`);
            return;
        }
        this.accounts.push({ email, password });
        this.saveAccounts();
        this.currentAccount = email;
        this.saveCurrentAccount();
        this.pushRecentAccount(email);
        this.emails = this.loadEmails(email);
        this.saveEmails();
        if (usernameEl) usernameEl.value = '';
        if (domainEl) domainEl.value = '';
        if (passwordEl) passwordEl.value = '';
        if (confirmEl) confirmEl.value = '';
        this.showMailView();
    }

    logout() {
        this.currentAccount = null;
        this.saveCurrentAccount();
        this.emails = [];
        this.currentEmailId = null;
        this.closeAccountMenu();
        this.showAuthScreen('login');
    }

    // ── Account menu (3-dot) ──────────────────────────────────────────────────

    setupAccountMenu() {
        const menuBtn = document.querySelector('#mail-window .mail-account-menu-btn');
        const menu = document.getElementById('mail-account-menu');
        const swapBtn = document.getElementById('mail-swap-account');
        const logoutBtn = document.getElementById('mail-logout');
        if (menuBtn && menu) {
            menuBtn.addEventListener('click', e => {
                e.stopPropagation();
                menu.classList.toggle('hidden');
            });
        }
        document.addEventListener('click', e => {
            if (menu && !menu.classList.contains('hidden')) {
                if (!menu.contains(e.target) && e.target !== menuBtn) {
                    menu.classList.add('hidden');
                }
            }
        });
        if (swapBtn) swapBtn.addEventListener('click', () => { this.closeAccountMenu(); this.switchAccount(); });
        if (logoutBtn) logoutBtn.addEventListener('click', () => this.logout());
    }

    closeAccountMenu() {
        const menu = document.getElementById('mail-account-menu');
        if (menu) menu.classList.add('hidden');
    }

    switchAccount() {
        const existing = document.getElementById('mail-switch-overlay');
        if (existing) existing.remove();
        const mainView = document.getElementById('mail-main-view');
        if (!mainView) { this.showAuthScreen('login'); return; }

        const recents = this.recentAccounts.filter(e => e !== this.currentAccount).slice(0, 3);
        const overlay = document.createElement('div');
        overlay.id = 'mail-switch-overlay';
        overlay.className = 'mail-switch-overlay';

        const recentItems = recents.map(email => `
            <div class="mail-switch-account-item" data-email="${this.escHtml(email)}">
                <span class="mail-switch-account-email">${this.escHtml(email)}</span>
                <span class="mail-switch-account-hint">Click to select</span>
            </div>
        `).join('');

        overlay.innerHTML = `
            <div class="mail-switch-card">
                <div class="mail-switch-title">Switch Account</div>
                ${recents.length ? `
                    <div class="mail-switch-recent-label">Recent accounts</div>
                    ${recentItems}
                    <div class="mail-switch-divider"></div>
                ` : ''}
                <div class="mail-switch-password-section" id="mail-switch-password-section" style="display:none;">
                    <div class="mail-switch-selected-email" id="mail-switch-selected-email"></div>
                    <input type="password" class="mail-auth-input" id="mail-switch-password" placeholder="Enter password" />
                    <button class="btn btn-primary" id="mail-switch-confirm-btn">Sign In</button>
                    <div class="mail-auth-message" id="mail-switch-message"></div>
                </div>
                <div class="mail-switch-actions">
                    <button class="btn btn-secondary" id="mail-switch-use-other">Use another account</button>
                    <button class="btn btn-secondary" id="mail-switch-cancel">Cancel</button>
                </div>
            </div>
        `;
        mainView.appendChild(overlay);

        let selectedEmail = null;
        overlay.querySelectorAll('.mail-switch-account-item').forEach(item => {
            item.addEventListener('click', () => {
                selectedEmail = item.dataset.email;
                overlay.querySelectorAll('.mail-switch-account-item').forEach(i => i.classList.remove('selected'));
                item.classList.add('selected');
                const pwSection = document.getElementById('mail-switch-password-section');
                const selLabel = document.getElementById('mail-switch-selected-email');
                if (pwSection) pwSection.style.display = 'flex';
                if (selLabel) selLabel.textContent = selectedEmail;
                const pwInput = document.getElementById('mail-switch-password');
                if (pwInput) { pwInput.value = ''; pwInput.focus(); }
                const msgEl = document.getElementById('mail-switch-message');
                if (msgEl) msgEl.textContent = '';
            });
        });

        const confirmBtn = document.getElementById('mail-switch-confirm-btn');
        if (confirmBtn) confirmBtn.addEventListener('click', () => this.confirmSwitch(selectedEmail));
        const switchPw = document.getElementById('mail-switch-password');
        if (switchPw) switchPw.addEventListener('keydown', e => { if (e.key === 'Enter') this.confirmSwitch(selectedEmail); });
        const useOtherBtn = document.getElementById('mail-switch-use-other');
        if (useOtherBtn) {
            useOtherBtn.addEventListener('click', () => {
                overlay.remove();
                this.logout();
            });
        }
        const cancelBtn = document.getElementById('mail-switch-cancel');
        if (cancelBtn) cancelBtn.addEventListener('click', () => overlay.remove());
    }

    confirmSwitch(email) {
        if (!email) {
            const msgEl = document.getElementById('mail-switch-message');
            if (msgEl) { msgEl.textContent = 'Please select an account first.'; msgEl.className = 'mail-auth-message error'; }
            return;
        }
        const pwInput = document.getElementById('mail-switch-password');
        const password = pwInput ? pwInput.value : '';
        const account = this.accounts.find(a => a.email.toLowerCase() === email.toLowerCase());
        if (!account || account.password !== password) {
            const msgEl = document.getElementById('mail-switch-message');
            if (msgEl) { msgEl.textContent = 'Incorrect password.'; msgEl.className = 'mail-auth-message error'; }
            return;
        }
        const overlay = document.getElementById('mail-switch-overlay');
        if (overlay) overlay.remove();
        this.currentAccount = account.email;
        this.saveCurrentAccount();
        this.pushRecentAccount(account.email);
        this.emails = this.loadEmails(account.email);
        this.currentEmailId = null;
        this.showMailView();
    }

    escHtml(str) {
        return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    // ── Folders ───────────────────────────────────────────────────────────────

    setupFolders() {
        const folders = document.querySelectorAll('#mail-window .mail-folder');
        folders.forEach(folder => {
            folder.addEventListener('click', () => {
                folders.forEach(f => f.classList.remove('active'));
                folder.classList.add('active');
                this.currentFolder = folder.dataset.folder;
                this.renderMailList();
            });
        });
    }

    // ── Mail rendering ────────────────────────────────────────────────────────

    renderMailList() {
        const mailList = document.querySelector('#mail-window .mail-list');
        if (!mailList) return;
        const folderEmails = this.emails.filter(email => email.folder === this.currentFolder);
        mailList.innerHTML = folderEmails.map(email => `
            <div class="mail-item ${email.unread ? 'unread' : ''}" data-id="${email.id}">
                <div class="mail-header">
                    <span class="mail-from">${this.escHtml(email.from)}</span>
                    <span class="mail-time">${this.escHtml(email.time)}</span>
                </div>
                <div class="mail-subject">${this.escHtml(email.subject)}</div>
                <div class="mail-preview">${this.escHtml(email.preview)}</div>
            </div>
        `).join('');
        mailList.querySelectorAll('.mail-item').forEach(item => {
            item.addEventListener('click', () => this.openEmail(parseInt(item.dataset.id)));
        });
        this.updateUnreadCount();
    }

    openEmail(emailId) {
        const email = this.emails.find(e => e.id === emailId);
        if (!email) return;
        this.currentEmailId = emailId;
        email.unread = false;
        this.saveEmails();
        this.renderMailView(email);
        this.renderMailList();
    }

    renderMailView(email) {
        const view = document.querySelector('#mail-window .mail-view');
        if (!view) return;
        if (!email) {
            view.innerHTML = '<div class="mail-empty">Select an email to view.</div>';
            return;
        }
        view.innerHTML = `
            <div class="mail-view-header">
                <div class="mail-view-subject">${this.escHtml(email.subject || '(no subject)')}</div>
                <div class="mail-view-meta">
                    <span class="mail-view-from">From: ${this.escHtml(email.from || 'Unknown')}</span>
                    <span class="mail-view-time">${this.escHtml(email.time || '')}</span>
                </div>
            </div>
            <div class="mail-view-body">${this.escHtml(email.body || '')}</div>
        `;
    }

    updateUnreadCount() {
        const unreadCount = this.emails.filter(e => e.unread && e.folder === 'inbox').length;
        const badge = document.querySelector('#mail-window .mail-folder[data-folder="inbox"] .mail-count');
        if (badge) {
            badge.textContent = unreadCount;
            badge.style.display = unreadCount > 0 ? 'block' : 'none';
        }
    }
}

// ============================================================================
// CALENDAR APP MANAGER
// ============================================================================
class CalendarManager {
    constructor() {
        this.currentDate = new Date();
        this.events = [];
        this.owner = 'global';
        this.init();
    }

    async init() {
        await this.loadEvents();
        this.renderCalendar();
        this.setupNavigation();
        this.setupActions();
    }

    async loadEvents() {
        const result = await nuiRequest('pc:getEvents', { owner: this.owner });
        this.events = result && result.ok ? (result.data || []) : [];
    }

    setupNavigation() {
        const navButtons = document.querySelectorAll('#calendar-window .calendar-nav .btn-secondary');
        const prevBtn = navButtons[0];
        const nextBtn = navButtons[1];
        
        if (prevBtn) {
            prevBtn.addEventListener('click', () => {
                this.currentDate.setMonth(this.currentDate.getMonth() - 1);
                this.renderCalendar();
            });
        }
        
        if (nextBtn) {
            nextBtn.addEventListener('click', () => {
                this.currentDate.setMonth(this.currentDate.getMonth() + 1);
                this.renderCalendar();
            });
        }
    }

    setupActions() {
        const addBtn = document.querySelector('#calendar-window .calendar-add-btn');
        const todayBtn = document.querySelector('#calendar-window .calendar-today-btn');

        if (addBtn) {
            addBtn.addEventListener('click', () => this.openReminderModal(this.formatDate(new Date())));
        }

        if (todayBtn) {
            todayBtn.addEventListener('click', () => {
                this.currentDate = new Date();
                this.renderCalendar();
            });
        }

        const cancelBtn = document.getElementById('calendar-cancel');
        const saveBtn = document.getElementById('calendar-save');

        if (cancelBtn) {
            cancelBtn.addEventListener('click', () => this.closeReminderModal());
        }

        if (saveBtn) {
            saveBtn.addEventListener('click', () => this.saveReminder());
        }
    }

    renderCalendar() {
        const monthDisplay = document.querySelector('#calendar-window .calendar-month');
        const grid = document.querySelector('#calendar-window .calendar-grid');
        
        if (!grid) return;
        
        // Month/year display
        const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
        if (monthDisplay) {
            monthDisplay.textContent = `${months[this.currentDate.getMonth()]} ${this.currentDate.getFullYear()}`;
        }
        
        // Clear grid
        grid.innerHTML = '';
        
        // Day headers
        const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
        days.forEach(day => {
            const header = document.createElement('div');
            header.className = 'calendar-day-header';
            header.textContent = day;
            grid.appendChild(header);
        });
        
        // Get first day of month and number of days
        const firstDay = new Date(this.currentDate.getFullYear(), this.currentDate.getMonth(), 1);
        const lastDay = new Date(this.currentDate.getFullYear(), this.currentDate.getMonth() + 1, 0);
        const startingDayOfWeek = firstDay.getDay();
        const daysInMonth = lastDay.getDate();
        
        // Previous month's trailing days
        const prevMonthLastDay = new Date(this.currentDate.getFullYear(), this.currentDate.getMonth(), 0).getDate();
        for (let i = startingDayOfWeek - 1; i >= 0; i--) {
            const day = document.createElement('div');
            day.className = 'calendar-day other-month';
            day.innerHTML = `<div class="calendar-date">${prevMonthLastDay - i}</div>`;
            grid.appendChild(day);
        }
        
        // Current month's days
        const today = new Date();
        for (let day = 1; day <= daysInMonth; day++) {
            const dayEl = document.createElement('div');
            const dateStr = `${this.currentDate.getFullYear()}-${String(this.currentDate.getMonth() + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
            
            dayEl.className = 'calendar-day';
            if (day === today.getDate() && this.currentDate.getMonth() === today.getMonth()) {
                dayEl.classList.add('today');
            }
            
            dayEl.innerHTML = `<div class="calendar-date">${day}</div>`;
            dayEl.addEventListener('click', () => this.openReminderModal(dateStr));
            
            // Add events for this day
            const dayEvents = this.events.filter(e => e.date === dateStr);
            if (dayEvents.length > 0) {
                const eventsContainer = document.createElement('div');
                eventsContainer.className = 'calendar-events';
                dayEvents.forEach(event => {
                    const eventEl = document.createElement('div');
                    eventEl.className = 'calendar-event';
                    eventEl.textContent = event.title;
                    eventEl.title = `${event.time} - ${event.description}`;
                    eventsContainer.appendChild(eventEl);
                });
                dayEl.appendChild(eventsContainer);
            }
            
            grid.appendChild(dayEl);
        }
        
        // Next month's leading days
        const remainingDays = 42 - (startingDayOfWeek + daysInMonth); // 6 rows * 7 days
        for (let day = 1; day <= remainingDays; day++) {
            const dayEl = document.createElement('div');
            dayEl.className = 'calendar-day other-month';
            dayEl.innerHTML = `<div class="calendar-date">${day}</div>`;
            grid.appendChild(dayEl);
        }
    }

    openReminderModal(dateStr) {
        const modal = document.getElementById('calendar-modal');
        if (!modal) return;

        const dateInput = document.getElementById('calendar-date');
        const titleInput = document.getElementById('calendar-title');
        const timeInput = document.getElementById('calendar-time');
        const descInput = document.getElementById('calendar-description');

        if (dateInput) dateInput.value = dateStr;
        if (titleInput) titleInput.value = '';
        if (timeInput) timeInput.value = '';
        if (descInput) descInput.value = '';

        modal.classList.remove('hidden');
    }

    closeReminderModal() {
        const modal = document.getElementById('calendar-modal');
        if (modal) modal.classList.add('hidden');
    }

    async saveReminder() {
        const title = document.getElementById('calendar-title')?.value.trim();
        const date = document.getElementById('calendar-date')?.value;
        const time = document.getElementById('calendar-time')?.value;
        const description = document.getElementById('calendar-description')?.value.trim();

        if (!title || !date) {
            this.showNotification('Title and date are required');
            return;
        }

        const result = await nuiRequest('pc:addEvent', {
            owner: this.owner,
            title,
            date,
            time: time || 'All Day',
            description: description || ''
        });

        if (result.ok) {
            await this.loadEvents();
            this.renderCalendar();
            this.closeReminderModal();
            this.showNotification('Reminder saved');
        } else {
            this.showNotification('Failed to save reminder');
        }
    }

    formatDate(date) {
        return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
    }

    showNotification(message) {
        const notification = document.createElement('div');
        notification.className = 'notification';
        notification.textContent = message;
        document.body.appendChild(notification);
        setTimeout(() => notification.remove(), 2000);
    }
}

// ============================================================================
// MAPS APP MANAGER
// ============================================================================
class MapsManager {
    constructor() {
        this.currentLocation = 'Los Santos';
        this.map = null;
        this.mapConfig = {
            mode: 'tiles',
            width: 512,
            height: 768,
            minZoom: 0,
            maxZoom: 4
        };
        this.init();
    }

    init() {
        const searchInput = document.querySelector('#maps-window .maps-search input');
        if (searchInput) {
            searchInput.addEventListener('keypress', (e) => {
                if (e.key === 'Enter') {
                    this.search(searchInput.value);
                }
            });
        }

        // Don't initialize map during page load - wait until window is opened
        // The map will be initialized when the window opens via WindowManager
        // this.initMap();
    }

    search(query) {
        if (!query) return;
        
        const locations = [
            'City Hall', 'Police Station', 'Hospital', 'Bank',
            'Post Office', 'DMV', 'Legion Square', 'Vinewood Hills',
            'Del Perro Beach', 'Los Santos International Airport'
        ];
        
        const found = locations.find(loc => loc.toLowerCase().includes(query.toLowerCase()));
        
        if (found) {
            this.currentLocation = found;
            this.showNotification(`Found: ${found}`);
        } else {
            this.showNotification('Location not found');
        }
    }

    initMap() {
        console.log('MapsManager: initMap() called');
        const mapContainer = document.getElementById('maps-leaflet');
        if (!mapContainer) {
            console.warn('MapsManager: Map container not found');
            return;
        }
        
        if (typeof L === 'undefined') {
            console.warn('MapsManager: Leaflet not loaded yet, retrying in 500ms...');
            setTimeout(() => this.initMap(), 500);
            return;
        }

        const { width, height, minZoom, maxZoom, mode } = this.mapConfig;
        const bounds = [[0, 0], [height, width]];

        if (this.map) {
            console.log('MapsManager: Map already exists, invalidating size');
            this.map.invalidateSize();
            return;
        }

        console.log('MapsManager: Creating new Leaflet map');
        this.map = L.map('maps-leaflet', {
            crs: L.CRS.Simple,
            minZoom,
            maxZoom,
            zoom: 1,
            zoomControl: false,
            doubleClickZoom: false,
            scrollWheelZoom: true,
            zoomSnap: 0.5,
            zoomDelta: 0.5,
            attributionControl: false,
            dragging: true,
            inertia: true
        });

        this.map.setView([height / 2, width / 2], 1);
        this.addBaseLayers(mode, bounds);
        this.map.fitBounds(bounds, { animate: false });
    }

    addBaseLayers(mode, bounds) {
        if (!this.map) return;

        if (mode === 'map' || mode === 'map2') {
            const file = mode === 'map2' ? 'map2/full_map.png' : 'map/full_map.png';
            const url = `https://cfx-nui-pf-emsmdt/html/${file}`;
            L.imageOverlay(url, bounds, { className: 'map-image' }).addTo(this.map);
            return;
        }

        const baseUrl = 'https://cfx-nui-pf-emsmdt/html/tiles';
        const tileW = this.mapConfig.width / 2;
        const tileH = this.mapConfig.height / 3;
        const rows = [
            { folder: 2, y0: 0 * tileH, y1: 1 * tileH },
            { folder: 1, y0: 1 * tileH, y1: 2 * tileH },
            { folder: 0, y0: 2 * tileH, y1: 3 * tileH }
        ];

        rows.forEach((row) => {
            for (let col = 0; col < 2; col++) {
                const x0 = col * tileW;
                const x1 = (col + 1) * tileW;
                const url = `${baseUrl}/${row.folder}/0/${col}.png`;
                L.imageOverlay(url, [[row.y0, x0], [row.y1, x1]], { className: 'map-tile' }).addTo(this.map);
            }
        });
    }

    showNotification(message) {
        const notification = document.createElement('div');
        notification.className = 'notification';
        notification.textContent = message;
        document.body.appendChild(notification);
        setTimeout(() => notification.remove(), 2000);
    }
}

// ============================================================================
// BILLS/INVOICES APP MANAGER
// ============================================================================
class BillsManager {
    constructor() {
        this.bills = this.loadBills();
        this.currentFilter = 'all';
        this.init();
    }

    init() {
        this.setupFilters();
        this.renderBills();
    }

    loadBills() {
        const stored = localStorage.getItem('bills_data');
        if (stored) return JSON.parse(stored);
        
        return [
            {
                id: 1,
                name: 'Electricity Bill',
                amount: 245.50,
                dueDate: '2026-02-25',
                status: 'pending',
                company: 'Los Santos Power & Light'
            },
            {
                id: 2,
                name: 'Water Bill',
                amount: 89.00,
                dueDate: '2026-02-28',
                status: 'pending',
                company: 'LS Water Department'
            },
            {
                id: 3,
                name: 'Business License Fee',
                amount: 500.00,
                dueDate: '2026-03-01',
                status: 'pending',
                company: 'City Government'
            },
            {
                id: 4,
                name: 'Property Tax',
                amount: 1250.00,
                dueDate: '2026-01-15',
                status: 'overdue',
                company: 'Tax Assessor'
            },
            {
                id: 5,
                name: 'Internet Service',
                amount: 79.99,
                dueDate: '2026-02-10',
                status: 'paid',
                company: 'LS Telecom'
            },
            {
                id: 6,
                name: 'Insurance Premium',
                amount: 350.00,
                dueDate: '2026-02-05',
                status: 'paid',
                company: 'Guardian Insurance'
            }
        ];
    }

    saveBills() {
        localStorage.setItem('bills_data', JSON.stringify(this.bills));
    }

    setupFilters() {
        const filterBtns = document.querySelectorAll('#bills-window .bills-filters .filter-btn');
        filterBtns.forEach(btn => {
            btn.addEventListener('click', () => {
                filterBtns.forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                this.currentFilter = btn.dataset.filter || 'all';
                this.renderBills();
            });
        });
    }

    renderBills() {
        const billsList = document.querySelector('#bills-window .bills-list');
        if (!billsList) return;
        
        let filteredBills = this.bills;
        if (this.currentFilter !== 'all') {
            filteredBills = this.bills.filter(bill => bill.status === this.currentFilter);
        }
        
        billsList.innerHTML = filteredBills.map(bill => `
            <div class="bill-item ${bill.status}">
                <div class="bill-info">
                    <h4>${bill.name}</h4>
                    <p>${bill.company} • Due: ${this.formatDate(bill.dueDate)}</p>
                </div>
                <div style="display: flex; align-items: center; gap: 20px;">
                    <div class="bill-amount">$${bill.amount.toFixed(2)}</div>
                    <div class="bill-status ${bill.status}">${bill.status}</div>
                    ${bill.status !== 'paid' ? `<button class="btn btn-primary" onclick="window.billsManager.payBill(${bill.id})">Pay</button>` : ''}
                </div>
            </div>
        `).join('');
    }

    async payBill(billId) {
        const bill = this.bills.find(b => b.id === billId);
        if (!bill) return;

        const confirmed = await uiConfirm(`Pay $${bill.amount.toFixed(2)} for ${bill.name}?`, {
            title: 'Pay Bill',
            confirmLabel: 'Pay'
        });
        if (!confirmed) return;

        bill.status = 'paid';
        this.saveBills();
        this.renderBills();
        this.showNotification(`Paid $${bill.amount.toFixed(2)} for ${bill.name}`);
    }

    formatDate(dateStr) {
        const date = new Date(dateStr);
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return `${months[date.getMonth()]} ${date.getDate()}, ${date.getFullYear()}`;
    }

    showNotification(message) {
        const notification = document.createElement('div');
        notification.className = 'notification';
        notification.textContent = message;
        document.body.appendChild(notification);
        setTimeout(() => notification.remove(), 2000);
    }
}

// ============================================================================
// JOB BOARD APP MANAGER
// ============================================================================
class JobBoardManager {
    constructor() {
        this.jobs = [];
        this.currentFilter = 'all';
        this.searchQuery = '';
        this.activeJobId = null;
        this.init();
    }

    async init() {
        this.setupFilters();
        this.setupToolbar();
        this.setupModals();
        await this.refresh();
    }

    async refresh() {
        const result = await nuiRequest('pc:getJobs', {});
        this.jobs = result && result.ok ? (result.data || []) : [];
        this.renderJobs();
    }

    setupFilters() {
        const filterBtns = document.querySelectorAll('#job-board-window .job-filters .filter-btn');
        filterBtns.forEach(btn => {
            btn.addEventListener('click', () => {
                filterBtns.forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                this.currentFilter = btn.dataset.filter || 'all';
                this.renderJobs();
            });
        });
    }

    setupToolbar() {
        const searchInput = document.querySelector('#job-board-window .job-search-input');
        if (searchInput) {
            searchInput.addEventListener('input', (e) => {
                this.searchQuery = e.target.value.toLowerCase();
                this.renderJobs();
            });
        }

        const createBtn = document.querySelector('#job-board-window .job-create-btn');
        if (createBtn) {
            createBtn.addEventListener('click', () => this.openCreateModal());
        }

        const myJobsBtn = document.getElementById('job-my-jobs-btn');
        if (myJobsBtn) {
            myJobsBtn.addEventListener('click', () => this.openMyJobsModal());
        }
    }

    setupModals() {
        const createCancel = document.getElementById('job-create-cancel');
        const createSave = document.getElementById('job-create-save');
        const applyCancel = document.getElementById('job-apply-cancel');
        const applySubmit = document.getElementById('job-apply-submit');

        if (createCancel) createCancel.addEventListener('click', () => this.closeCreateModal());
        if (createSave) createSave.addEventListener('click', () => this.submitCreate());
        if (applyCancel) applyCancel.addEventListener('click', () => this.closeApplyModal());
        if (applySubmit) applySubmit.addEventListener('click', () => this.submitApplication());

        const myJobsClose = document.getElementById('job-my-jobs-close');
        if (myJobsClose) myJobsClose.addEventListener('click', () => this.closeMyJobsModal());
        const applicantsBack = document.getElementById('job-applicants-back');
        if (applicantsBack) applicantsBack.addEventListener('click', () => this.showMyJobsList());
    }

    renderJobs() {
        const jobListings = document.querySelector('#job-board-window .job-listings');
        if (!jobListings) return;

        let filteredJobs = this.jobs;
        if (this.currentFilter !== 'all') {
            filteredJobs = filteredJobs.filter(job => job.category === this.currentFilter);
        }

        if (this.searchQuery) {
            filteredJobs = filteredJobs.filter(job => {
                const haystack = `${job.title} ${job.company} ${job.description}`.toLowerCase();
                return haystack.includes(this.searchQuery);
            });
        }

        // every field is player-written: escape it (it used to be inserted as HTML, so a job post could
        // run script in other players' computers)
        const esc = (v) => this.escHtml(v == null ? '' : String(v));
        jobListings.innerHTML = filteredJobs.map(job => `
            <div class="job-item">
                <div class="job-title">${esc(job.title)}</div>
                <div class="job-company">${esc(job.company)}</div>
                <div class="job-details">
                    <span>📍 ${esc(job.location)}</span>
                    <span>💰 ${esc(job.salary)}</span>
                    <span>⏰ ${esc(job.type)}</span>
                </div>
                <div class="job-description">${esc(job.description)}</div>
                <div class="job-tags">
                    ${(job.tags || []).map(tag => `<span class="job-tag">${esc(tag)}</span>`).join('')}
                </div>
                <button class="btn btn-primary job-apply-btn" data-id="${esc(job.id)}" style="margin-top: 15px;">Apply Now</button>
            </div>
        `).join('');

        jobListings.querySelectorAll('.job-apply-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                const jobId = parseInt(btn.dataset.id);
                this.applyToJob(jobId);
            });
        });
    }

    applyToJob(jobId) {
        const job = this.jobs.find(j => j.id === jobId);
        if (!job) return;

        this.activeJobId = jobId;
        const modal = document.getElementById('job-apply-modal');
        if (modal) modal.classList.remove('hidden');
    }

    openCreateModal() {
        const modal = document.getElementById('job-create-modal');
        if (modal) modal.classList.remove('hidden');
    }

    closeCreateModal() {
        const modal = document.getElementById('job-create-modal');
        if (modal) modal.classList.add('hidden');
    }

    closeApplyModal() {
        const modal = document.getElementById('job-apply-modal');
        if (modal) modal.classList.add('hidden');
        this.activeJobId = null;
    }

    async submitCreate() {
        const payload = {
            title: document.getElementById('job-title')?.value.trim(),
            company: document.getElementById('job-company')?.value.trim(),
            location: document.getElementById('job-location')?.value.trim(),
            salary: document.getElementById('job-salary')?.value.trim(),
            type: document.getElementById('job-type')?.value.trim(),
            category: document.getElementById('job-category')?.value.trim().toLowerCase() || 'general',
            description: document.getElementById('job-description')?.value.trim(),
            tags: (document.getElementById('job-tags')?.value || '').split(',').map(t => t.trim()).filter(Boolean)
        };

        if (!payload.title || !payload.company) {
            this.showNotification('Title and company are required');
            return;
        }

        const result = await nuiRequest('pc:createJob', payload);
        if (result.ok) {
            this.closeCreateModal();
            await this.refresh();
            this.showNotification('Job posted');
        } else {
            this.showNotification('Failed to post job');
        }
    }

    async submitApplication() {
        if (!this.activeJobId) return;

        const payload = {
            jobId: this.activeJobId,
            name: document.getElementById('job-apply-name')?.value.trim(),
            phone: document.getElementById('job-apply-phone')?.value.trim(),
            email: document.getElementById('job-apply-email')?.value.trim(),
            experience: document.getElementById('job-apply-experience')?.value.trim(),
            message: document.getElementById('job-apply-message')?.value.trim()
        };

        if (!payload.name) {
            this.showNotification('Name is required');
            return;
        }

        const result = await nuiRequest('pc:applyJob', payload);
        if (result.ok) {
            this.closeApplyModal();
            this.showNotification('Application submitted');
        } else {
            this.showNotification('Failed to submit application');
        }
    }

    async openMyJobsModal() {
        const modal = document.getElementById('job-my-jobs-modal');
        if (modal) modal.classList.remove('hidden');
        this.showMyJobsList();
        await this.loadMyJobs();
    }

    closeMyJobsModal() {
        const modal = document.getElementById('job-my-jobs-modal');
        if (modal) modal.classList.add('hidden');
    }

    showMyJobsList() {
        const list = document.getElementById('job-my-jobs-list');
        const panel = document.getElementById('job-applicants-panel');
        if (list) list.classList.remove('hidden');
        if (panel) panel.classList.add('hidden');
    }

    async loadMyJobs() {
        const list = document.getElementById('job-my-jobs-list');
        if (!list) return;
        list.innerHTML = '<div class="job-my-jobs-empty">Loading…</div>';
        const result = await nuiRequest('pc:getMyJobs', {});
        const jobs = result && result.ok ? (result.data || []) : [];
        if (jobs.length === 0) {
            list.innerHTML = '<div class="job-my-jobs-empty">You haven\'t posted any jobs yet.</div>';
            return;
        }
        list.innerHTML = jobs.map(job => `
            <div class="job-my-jobs-item" data-job-id="${job.id}" data-job-title="${this.escAttr(job.title)}">
                <div class="job-my-jobs-item-info">
                    <div class="job-my-jobs-item-title">${this.escHtml(job.title)}</div>
                    <div class="job-my-jobs-item-company">${this.escHtml(job.company)} · ${this.escHtml(job.location)}</div>
                </div>
                <div class="job-my-jobs-item-badge">${job.applicantCount || 0} applied</div>
            </div>
        `).join('');
        list.querySelectorAll('.job-my-jobs-item').forEach(item => {
            item.addEventListener('click', () => {
                const jobId = parseInt(item.dataset.jobId);
                const title = item.dataset.jobTitle;
                this.viewApplicants(jobId, title);
            });
        });
    }

    async viewApplicants(jobId, jobTitle) {
        const list = document.getElementById('job-my-jobs-list');
        const panel = document.getElementById('job-applicants-panel');
        const titleEl = document.getElementById('job-applicants-title');
        const applicantsList = document.getElementById('job-applicants-list');
        if (!panel || !applicantsList) return;
        if (list) list.classList.add('hidden');
        panel.classList.remove('hidden');
        if (titleEl) titleEl.textContent = jobTitle || 'Applicants';
        applicantsList.innerHTML = '<div class="job-applicants-empty">Loading…</div>';
        const result = await nuiRequest('pc:getJobApplicants', { jobId });
        const applicants = result && result.ok ? (result.data || []) : [];
        if (applicants.length === 0) {
            applicantsList.innerHTML = '<div class="job-applicants-empty">No applications yet.</div>';
            return;
        }
        applicantsList.innerHTML = applicants.map(app => `
            <div class="job-applicants-item">
                <div class="job-applicants-item-name">${this.escHtml(app.name)}</div>
                <div class="job-applicants-item-row">
                    ${app.phone ? `<span><span class="job-applicants-item-label">Phone:</span> ${this.escHtml(app.phone)}</span>` : ''}
                    ${app.email ? `<span><span class="job-applicants-item-label">Email:</span> ${this.escHtml(app.email)}</span>` : ''}
                </div>
                ${app.experience ? `<div class="job-applicants-item-row"><span class="job-applicants-item-label">Experience:</span> ${this.escHtml(app.experience)}</div>` : ''}
                ${app.message ? `<div class="job-applicants-item-message">${this.escHtml(app.message)}</div>` : ''}
            </div>
        `).join('');
    }

    escHtml(str) {
        return String(str || '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    escAttr(str) {
        return String(str || '').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
    }

    showNotification(message) {
        const notification = document.createElement('div');
        notification.className = 'notification';
        notification.textContent = message;
        document.body.appendChild(notification);
        setTimeout(() => notification.remove(), 2000);
    }
}

// ============================================================================
// TERMINAL APP MANAGER
// ============================================================================
class TerminalManager {
    constructor() {
        this.commandHistory = [];
        this.historyIndex = -1;
        this.currentRoom = 'market';
        this.chatAuthor = scopedStorageGet('darkweb_alias') || `Anonymous_${Math.floor(Math.random() * 10000)}`;
        this.darknetMode = scopedStorageGet('terminal_darknet_mode') === 'true';
        this.currentDirectory = '/home/user';
        this.fileSystem = { '/home/user': { 'documents.txt': 'Work files', 'notes.md': 'Personal notes' }, '/etc': { 'config.conf': 'System config' } };
        this.init();
    }

    init() {
        this.renderTerminal();
        this.setupInput();
        this.setupModal();
        this.applyTerminalChrome();
        this.showWelcomeMessage();
    }

    applyTerminalChrome() {
        const content = document.querySelector('#terminal-window .terminal-content');
        const title = document.querySelector('#terminal-window .window-title span');
        const prompt = document.querySelector('#terminal-window .terminal-input-line .terminal-prompt');

        if (content) {
            content.classList.toggle('darknet-mode', this.darknetMode);
        }

        if (title) {
            title.textContent = this.darknetMode ? 'Dark Terminal' : 'Terminal Shell';
        }

        if (prompt) {
            prompt.textContent = this.darknetMode ? 'darknet@root:~$' : 'user@localhost:~$';
        }
    }

    renderTerminal() {
        const terminal = document.querySelector('#terminal-window .terminal');
        if (!terminal) return;
        
        if (!terminal.querySelector('.terminal-output')) {
            const prompt = this.darknetMode ? 'darknet@root:~$' : 'user@localhost:~$';
            terminal.innerHTML = `
                <div class="terminal-output"></div>
                <div class="terminal-input-line">
                    <span class="terminal-prompt">${prompt}</span>
                    <input type="text" class="terminal-input" autofocus>
                </div>
            `;
        }
    }

    setupInput() {
        const input = document.querySelector('#terminal-window .terminal-input');
        if (!input) return;
        
        input.addEventListener('keydown', (e) => {
            if (e.key === 'Enter') {
                const command = input.value.trim();
                if (command) {
                    this.executeCommand(command);
                    this.commandHistory.push(command);
                    this.historyIndex = this.commandHistory.length;
                    input.value = '';
                }
            } else if (e.key === 'ArrowUp') {
                e.preventDefault();
                if (this.historyIndex > 0) {
                    this.historyIndex--;
                    input.value = this.commandHistory[this.historyIndex];
                }
            } else if (e.key === 'ArrowDown') {
                e.preventDefault();
                if (this.historyIndex < this.commandHistory.length - 1) {
                    this.historyIndex++;
                    input.value = this.commandHistory[this.historyIndex];
                } else {
                    this.historyIndex = this.commandHistory.length;
                    input.value = '';
                }
            }
        });
        
        // Keep input focused when clicking in terminal
        const terminal = document.querySelector('#terminal-window .terminal');
        if (terminal) {
            terminal.addEventListener('click', () => input.focus());
        }
    }

    showWelcomeMessage() {
        if (this.darknetMode) {
            this.addOutput(`
╔══════════════════════════════════════════════════════╗
║          DARK WEB TERMINAL v2.5.1                    ║
║          WARNING: Unauthorized access detected       ║
║          Connection encrypted via TOR                ║
╚══════════════════════════════════════════════════════╝

Type 'help' for available commands.
            `.trim(), 'terminal-success');
        } else {
            this.addOutput(`
╔══════════════════════════════════════════════════════╗
║              TERMINAL SHELL v1.2.3                   ║
║              Los Santos Operating System             ║
╚══════════════════════════════════════════════════════╝

Type 'help' for available commands. Type 'darkweb on' to enter darknet mode.
            `.trim(), 'terminal-success');
        }
    }

    async executeCommand(command) {
        const prompt = this.darknetMode ? 'darknet@root:~$' : 'user@localhost:~$';
        this.addOutput(`${prompt} ${command}`, 'terminal-prompt');
        
        const [cmd, ...args] = command.toLowerCase().split(' ');
        
        if (this.darknetMode) {
            await this.executeDarknetCommand(cmd, args);
        } else {
            await this.executeRegularCommand(cmd, args);
        }
    }

    async executeRegularCommand(cmd, args) {
        switch (cmd) {
            case 'help':
                this.showRegularHelp();
                break;
            case 'ls':
            case 'dir':
                this.listFiles();
                break;
            case 'pwd':
                this.addOutput(this.currentDirectory);
                break;
            case 'cd':
                this.changeDirectory(args[0]);
                break;
            case 'cat':
                this.catFile(args[0]);
                break;
            case 'echo':
                this.addOutput(args.join(' '));
                break;
            case 'whoami':
                this.addOutput('user');
                break;
            case 'date':
                this.addOutput(new Date().toString());
                break;
            case 'mkdir':
                this.makeDirectory(args[0]);
                break;
            case 'rm':
                this.removeFile(args[0]);
                break;
            case 'clear':
                this.clearTerminal();
                break;
            case 'darkweb':
                if (args[0] === 'on') {
                    this.darknetMode = true;
                    scopedStorageSet('terminal_darknet_mode', 'true');
                    this.applyTerminalChrome();
                    this.clearTerminal();
                    this.showWelcomeMessage();
                    this.renderTerminal();
                    this.addOutput('Entering dark web mode...', 'terminal-success');
                } else {
                    this.addOutput('Usage: darkweb on', 'terminal-error');
                }
                break;
            case 'exit':
                this.addOutput('Type exit again to close the terminal window.', 'terminal-warning');
                break;
            default:
                this.addOutput(`Command not found: ${cmd}. Type 'help' for available commands.`, 'terminal-error');
        }
    }

    async executeDarknetCommand(cmd, args) {
        switch (cmd) {
            case 'help':
                this.showDarknetHelp();
                break;
            case 'ls':
            case 'dir':
                this.listDirectory();
                break;
            case 'connect':
                this.connect(args[0]);
                break;
            case 'market':
                await this.showMarket();
                break;
            case 'sell':
                this.openSellModal();
                break;
            case 'buy':
                this.buyItem(args.join(' '));
                break;
            case 'rooms':
                await this.listChatRooms();
                break;
            case 'join':
                await this.joinRoom(args.join(' '));
                break;
            case 'mkroom':
                await this.joinRoom(args.join(' '));
                break;
            case 'say':
                await this.postChatMessage(args.join(' '));
                break;
            case 'chatlog':
                await this.printChatLog();
                break;
            case 'scan':
                this.scanNetwork();
                break;
            case 'hack':
                this.hack(args[0]);
                break;
            case 'profile':
                this.showProfile();
                break;
            case 'darkweb':
                if (args[0] === 'off') {
                    this.darknetMode = false;
                    scopedStorageSet('terminal_darknet_mode', 'false');
                    this.applyTerminalChrome();
                    this.clearTerminal();
                    this.showWelcomeMessage();
                    this.renderTerminal();
                    this.addOutput('Exiting dark web mode...', 'terminal-success');
                } else {
                    this.addOutput('Usage: darkweb off', 'terminal-error');
                }
                break;
            case 'clear':
                this.clearTerminal();
                break;
            case 'exit':
                this.addOutput('Connection terminated.', 'terminal-error');
                break;
            default:
                this.addOutput(`Command not found: ${cmd}. Type 'help' for available commands.`, 'terminal-error');
        }
    }

    showRegularHelp() {
        this.addOutput(`
Available Commands:
  ls/dir       - List files in current directory
  pwd          - Print working directory
  cd <dir>     - Change directory
  cat <file>   - View file contents
  echo <text>  - Print text
  whoami       - Display current user
  date         - Show current date/time
  mkdir <dir>  - Create directory
  rm <file>    - Remove file
  darkweb on   - Enter darknet mode
  clear        - Clear screen
  help         - Show this help message
  exit         - Close terminal
        `.trim());
    }

    showDarknetHelp() {
        this.addOutput(`
Available Commands:
  help         - Show this help message
  ls/dir       - List directory contents
  connect      - Connect to a server
  market       - View dark web marketplace
  sell         - Create a listing
  buy <item>   - Purchase an item
  rooms        - List chat rooms
  join <room>  - Join or create a room
  mkroom <r>   - Create a room
  say <msg>    - Post a message
  chatlog      - Show room messages
  scan         - Scan the network
  hack <ip>    - Attempt to hack a system
  profile      - View your profile
  darkweb off  - Exit darknet mode
  clear        - Clear terminal
  exit         - Close connection
        `.trim());
    }

    listFiles() {
        const dir = this.fileSystem[this.currentDirectory] || {};
        const items = Object.entries(dir).map(([name, desc]) => `-rw-r--r-- 1 user group 0 Feb 18 ${name}`);
        if (items.length === 0) {
            this.addOutput('(empty directory)');
        } else {
            this.addOutput(items.join('\n'));
        }
    }

    changeDirectory(dir) {
        if (!dir) {
            this.addOutput('Usage: cd <directory>', 'terminal-error');
            return;
        }
        if (dir === '..') {
            const parts = this.currentDirectory.split('/');
            if (parts.length > 2) {
                parts.pop();
                this.currentDirectory = parts.join('/');
                this.addOutput(`Changed to: ${this.currentDirectory}`, 'terminal-success');
            }
        } else if (this.fileSystem['/' + dir] || this.fileSystem[this.currentDirectory + '/' + dir]) {
            this.currentDirectory = '/' + dir;
            this.addOutput(`Changed to: ${this.currentDirectory}`, 'terminal-success');
        } else {
            this.addOutput(`Directory not found: ${dir}`, 'terminal-error');
        }
    }

    catFile(filename) {
        if (!filename) {
            this.addOutput('Usage: cat <filename>', 'terminal-error');
            return;
        }
        const dir = this.fileSystem[this.currentDirectory] || {};
        if (dir[filename]) {
            this.addOutput(dir[filename]);
        } else {
            this.addOutput(`File not found: ${filename}`, 'terminal-error');
        }
    }

    makeDirectory(dirname) {
        if (!dirname) {
            this.addOutput('Usage: mkdir <dirname>', 'terminal-error');
            return;
        }
        this.addOutput(`Created directory: ${dirname}`, 'terminal-success');
    }

    removeFile(filename) {
        if (!filename) {
            this.addOutput('Usage: rm <filename>', 'terminal-error');
            return;
        }
        const dir = this.fileSystem[this.currentDirectory] || {};
        if (dir[filename]) {
            delete dir[filename];
            this.addOutput(`Removed: ${filename}`, 'terminal-success');
        } else {
            this.addOutput(`File not found: ${filename}`, 'terminal-error');
        }
    }

    showHelp() {
        if (this.darknetMode) {
            this.showDarknetHelp();
        } else {
            this.showRegularHelp();
        }
    }

    listDirectory() {
        this.addOutput(`
drwxr-xr-x  2 root root 4096 Feb 18 15:42 ./
drwxr-xr-x 12 root root 4096 Feb 15 09:21 ../
-rw-r--r--  1 root root 2048 Feb 18 14:30 encrypted.dat
-rw-r--r--  1 root root  512 Feb 17 22:15 contacts.txt
-rwxr-xr-x  1 root root 8192 Feb 16 18:45 crack.exe
-rw-r--r--  1 root root 1024 Feb 18 15:42 wallet.dat
        `.trim());
    }

    connect(server) {
        if (!server) {
            this.addOutput('Usage: connect <server>', 'terminal-error');
            return;
        }
        
        this.addOutput('Establishing encrypted connection...');
        setTimeout(() => {
            this.addOutput(`Connected to ${server}`, 'terminal-success');
            this.addOutput('Warning: All activity is monitored and logged');
        }, 500);
    }

    async showMarket() {
        const result = await nuiRequest('pc:getMarket', {});
        const items = result && result.ok ? (result.data || []) : [];

        if (items.length === 0) {
            this.addOutput('No listings available. Use `sell` to create one.', 'terminal-error');
            return;
        }

        const lines = items.map((item, index) => {
            const contact = item.contact || 'darkchat:market';
            return `${index + 1}. ${item.title} - ${item.price} | ${contact}`;
        });

        this.addOutput(`
═════════════════════════════════════════════════════
              DARK WEB MARKETPLACE
═════════════════════════════════════════════════════

${lines.join('\n')}

Use 'buy <item name>' to purchase
        `.trim());
    }

    setupModal() {
        const cancelBtn = document.getElementById('darkweb-cancel');
        const createBtn = document.getElementById('darkweb-create');
        if (cancelBtn) cancelBtn.addEventListener('click', () => this.closeSellModal());
        if (createBtn) createBtn.addEventListener('click', () => this.submitListing());
    }

    openSellModal() {
        const modal = document.getElementById('darkweb-sell-modal');
        if (modal) modal.classList.remove('hidden');
    }

    closeSellModal() {
        const modal = document.getElementById('darkweb-sell-modal');
        if (modal) modal.classList.add('hidden');
    }

    async submitListing() {
        const payload = {
            title: document.getElementById('darkweb-title')?.value.trim(),
            price: document.getElementById('darkweb-price')?.value.trim(),
            condition: document.getElementById('darkweb-condition')?.value.trim(),
            contact: document.getElementById('darkweb-contact')?.value.trim(),
            description: document.getElementById('darkweb-description')?.value.trim()
        };

        if (!payload.title || !payload.price) {
            this.addOutput('Listing requires a title and price.', 'terminal-error');
            return;
        }

        const result = await nuiRequest('pc:createListing', payload);
        if (result.ok) {
            this.closeSellModal();
            this.addOutput('Listing created.', 'terminal-success');
        } else {
            this.addOutput('Failed to create listing.', 'terminal-error');
        }
    }

    async listChatRooms() {
        const result = await nuiRequest('pc:getChatRooms', {});
        const rooms = result && result.ok ? (result.data || []) : [];
        if (rooms.length === 0) {
            this.addOutput('No rooms available. Use `mkroom <name>` to create one.');
            return;
        }

        const lines = rooms.map(room => `${room.name} (${room.count})`);
        this.addOutput(`Chat rooms: ${lines.join(', ')}`);
    }

    async joinRoom(name) {
        const room = name && name.trim() ? name.trim() : 'market';
        const result = await nuiRequest('pc:joinChatRoom', { room });
        if (!result.ok) {
            this.addOutput('Failed to join room.', 'terminal-error');
            return;
        }

        this.currentRoom = room;
        this.addOutput(`Joined room: ${room}`, 'terminal-success');
        const messages = result.data?.messages || [];
        messages.slice(-6).forEach((msg) => {
            this.addOutput(`[${msg.author}] ${msg.message}`);
        });
    }

    async postChatMessage(message) {
        if (!message || message.trim() === '') {
            this.addOutput('Usage: say <message>', 'terminal-error');
            return;
        }

        const result = await nuiRequest('pc:postChatMessage', {
            room: this.currentRoom,
            author: this.chatAuthor,
            message: message.trim()
        });

        if (result.ok) {
            this.addOutput(`[${this.chatAuthor}] ${message.trim()}`);
        } else {
            this.addOutput('Failed to send message.', 'terminal-error');
        }
    }

    async printChatLog() {
        const result = await nuiRequest('pc:joinChatRoom', { room: this.currentRoom });
        if (!result.ok) {
            this.addOutput('Failed to load messages.', 'terminal-error');
            return;
        }

        const messages = result.data?.messages || [];
        if (messages.length === 0) {
            this.addOutput('Room is empty.');
            return;
        }

        messages.slice(-10).forEach((msg) => {
            this.addOutput(`[${msg.author}] ${msg.message}`);
        });
    }

    buyItem(item) {
        if (!item) {
            this.addOutput('Usage: buy <item name>', 'terminal-error');
            return;
        }
        
        this.addOutput(`Processing transaction for: ${item}...`);
        setTimeout(() => {
            this.addOutput('Transaction failed: Insufficient funds', 'terminal-error');
            this.addOutput('Your wallet balance: 0.00 BTC');
        }, 1000);
    }

    scanNetwork() {
        this.addOutput('Scanning network...');
        const ips = [
            '192.168.1.1    [ROUTER]        - Open',
            '10.0.0.5       [DATABASE]      - Firewalled',
            '172.16.0.100   [WEB SERVER]    - Vulnerable',
            '192.168.1.50   [WORKSTATION]   - Protected',
            '10.0.0.25      [FILE SERVER]   - Open'
        ];
        
        ips.forEach((ip, index) => {
            setTimeout(() => {
                this.addOutput(ip);
            }, (index + 1) * 300);
        });
    }

    hack(target) {
        if (!target) {
            this.addOutput('Usage: hack <ip address>', 'terminal-error');
            return;
        }
        
        this.addOutput(`Initiating hack on ${target}...`);
        this.addOutput('Running exploit...', 'terminal-success');
        
        setTimeout(() => {
            if (Math.random() > 0.5) {
                this.addOutput('Access granted!', 'terminal-success');
                this.addOutput('Downloading files...');
                this.addOutput('[████████████████████] 100%', 'terminal-success');
            } else {
                this.addOutput('Access denied. Firewall detected.', 'terminal-error');
                this.addOutput('Aborting to avoid detection...');
            }
        }, 1500);
    }

    showProfile() {
        this.addOutput(`
═════════════════════════════════════════════════════
User Profile:
═════════════════════════════════════════════════════
Username:     Anonymous_${Math.floor(Math.random() * 10000)}
Reputation:   ★★★☆☆ (3/5)
Total Deals:  28
Wallet:       0.00 BTC
Member Since: Jan 2025
Last Seen:    Online
        `.trim());
    }

    clearTerminal() {
        const output = document.querySelector('#terminal-window .terminal-output');
        if (output) output.innerHTML = '';
    }

    addOutput(text, className = '') {
        const output = document.querySelector('#terminal-window .terminal-output');
        if (!output) return;
        
        const line = document.createElement('div');
        line.className = `terminal-line ${className}`;
        line.textContent = text;
        output.appendChild(line);
        
        // Auto-scroll to bottom
        const terminal = document.querySelector('#terminal-window .terminal');
        if (terminal) {
            terminal.scrollTop = terminal.scrollHeight;
        }
    }
}

// ============================================================================
// CALCULATOR APP MANAGER
// ============================================================================
class CalculatorManager {
    constructor() {
        this.display = '';
        this.operator = '';
        this.previousValue = '';
        this.shouldResetDisplay = false;
        this.init();
    }

    init() {
        this.renderCalculator();
        this.setupButtons();
    }

    renderCalculator() {
        const container = document.querySelector('#calculator-window .window-content');
        if (!container || container.querySelector('.calculator-container')) return;
        
        container.innerHTML = `
            <div class="calculator-container">
                <div class="calculator-display">0</div>
                <div class="calculator-buttons">
                    <button class="calc-btn clear">C</button>
                    <button class="calc-btn">±</button>
                    <button class="calc-btn">%</button>
                    <button class="calc-btn operator">÷</button>
                    
                    <button class="calc-btn">7</button>
                    <button class="calc-btn">8</button>
                    <button class="calc-btn">9</button>
                    <button class="calc-btn operator">×</button>
                    
                    <button class="calc-btn">4</button>
                    <button class="calc-btn">5</button>
                    <button class="calc-btn">6</button>
                    <button class="calc-btn operator">−</button>
                    
                    <button class="calc-btn">1</button>
                    <button class="calc-btn">2</button>
                    <button class="calc-btn">3</button>
                    <button class="calc-btn operator">+</button>
                    
                    <button class="calc-btn">0</button>
                    <button class="calc-btn">.</button>
                    <button class="calc-btn equals">=</button>
                </div>
            </div>
        `;
    }

    setupButtons() {
        const buttons = document.querySelectorAll('#calculator-window .calc-btn');
        buttons.forEach(btn => {
            btn.addEventListener('click', () => {
                const value = btn.textContent;
                
                if (btn.classList.contains('clear')) {
                    this.clear();
                } else if (btn.classList.contains('equals')) {
                    this.calculate();
                } else if (btn.classList.contains('operator')) {
                    this.setOperator(value);
                } else if (value === '±') {
                    this.toggleSign();
                } else if (value === '%') {
                    this.percentage();
                } else {
                    this.appendNumber(value);
                }
            });
        });
    }

    updateDisplay() {
        const displayEl = document.querySelector('#calculator-window .calculator-display');
        if (displayEl) {
            displayEl.textContent = this.display || '0';
        }
    }

    appendNumber(num) {
        if (this.shouldResetDisplay) {
            this.display = '';
            this.shouldResetDisplay = false;
        }
        
        if (num === '.' && this.display.includes('.')) return;
        
        this.display += num;
        this.updateDisplay();
    }

    setOperator(op) {
        if (this.operator && this.display) {
            this.calculate();
        }
        
        this.operator = op;
        this.previousValue = this.display;
        this.shouldResetDisplay = true;
    }

    calculate() {
        if (!this.operator || !this.previousValue) return;
        
        const prev = parseFloat(this.previousValue);
        const current = parseFloat(this.display);
        
        let result = 0;
        
        switch (this.operator) {
            case '+':
                result = prev + current;
                break;
            case '−':
                result = prev - current;
                break;
            case '×':
                result = prev * current;
                break;
            case '÷':
                result = current !== 0 ? prev / current : 'Error';
                break;
        }
        
        this.display = result.toString();
        this.operator = '';
        this.previousValue = '';
        this.shouldResetDisplay = true;
        this.updateDisplay();
    }

    clear() {
        this.display = '';
        this.operator = '';
        this.previousValue = '';
        this.shouldResetDisplay = false;
        this.updateDisplay();
    }

    toggleSign() {
        if (this.display) {
            this.display = (parseFloat(this.display) * -1).toString();
            this.updateDisplay();
        }
    }

    percentage() {
        if (this.display) {
            this.display = (parseFloat(this.display) / 100).toString();
            this.updateDisplay();
        }
    }
}

// ============================================================================
// BUSINESS MANAGER - Comprehensive business management system
// ============================================================================
class BusinessManager {
    constructor() {
        this.businessConfig = null;
        this.businessData = null;
        this.currentSection = 'dashboard';
        this.menuItems = [];
        this.mealItems = [];
        this.transactions = [];
        this.employees = [];
        this.analyticsData = null;
        this.analyticsPeriod = 'week';
        this.analyticsChartType = 'bar';
        this.liveUpdateTimer = null;
        this.liveUpdateIntervalMs = 10000;
        this.isRefreshing = false;
        this.dataLoaded = false; // Track if data has been loaded
        this.isFiveM = typeof GetParentResourceName !== 'undefined';
        this.businessId = null;
        this.init();
    }

    async init() {
        console.log('BusinessManager: Initializing...');
        
        // Wait for window to be opened before loading data
        const window = document.getElementById('business-manager-window');
        if (!window) {
            console.error('Business Manager window not found');
            return;
        }

        // Load business data when window opens (only once)
        const observer = new MutationObserver((mutations) => {
            mutations.forEach((mutation) => {
                if (mutation.attributeName !== 'style') return;
                const display = window.style.display;
                if (display !== 'none') {
                    if (!this.dataLoaded) {
                        this.dataLoaded = true;
                        this.loadBusinessData();
                    }
                    this.startLiveUpdates();
                } else {
                    this.stopLiveUpdates();
                }
            });
        });

        observer.observe(window, { attributes: true });
    }

    async loadBusinessData() {
        console.log('BusinessManager: Loading business data...');
        
        if (!this.isFiveM) {
            // Browser mode - use demo data
            console.log('BusinessManager: Running in browser mode with demo data');
            this.loadDemoData();
            return;
        }
        
        // FiveM mode - fetch from server
        const playerResult = await nuiRequest('pc:getPlayerData', {});
        if (!playerResult.ok) {
            this.renderError('Failed to load player data.');
            return;
        }

        const playerJob = playerResult.data?.job;
        const playerGrade = playerResult.data?.grade ?? 0;
        if (!playerJob) {
            this.renderError('Player job not available.');
            return;
        }

        try {
            // Get business config
            const configResult = await this.fetchServer('pc:business:getConfig', {
                job: playerJob,
                grade: playerGrade
            });

            if (!configResult.ok) {
                this.renderAccessDenied(configResult.error);
                return;
            }

            this.businessConfig = configResult.data;
            this.businessId = this.businessConfig.job || playerJob;

            // Get business data
            const dataResult = await this.fetchServer('pc:business:getData', {
                businessId: this.businessId
            });

            if (dataResult.ok) {
                this.businessData = dataResult.data;
            }

            // Load menu items
            const menuResult = await this.fetchServer('pc:business:menu:list', {
                businessId: this.businessId
            });

            if (menuResult.ok) {
                this.menuItems = menuResult.data;
            }

            // Load meal items
            const mealsResult = await this.fetchServer('pc:business:meals:list', {
                businessId: this.businessId
            });

            if (mealsResult.ok) {
                this.mealItems = mealsResult.data;
            } else {
                this.mealItems = [];
            }

            // Load transactions
            const txResult = await this.fetchServer('pc:business:transactions:list', {
                businessId: this.businessId,
                limit: 100
            });

            if (txResult.ok) {
                this.transactions = txResult.data;
            }

            // Load real employees
            const empResult = await this.fetchServer('pc:business:employees:list', {
                businessId: this.businessId
            });

            if (empResult.ok) {
                this.employees = empResult.data;
            } else {
                this.employees = []; // Empty if failed to load
            }

            // Load analytics data
            await this.fetchAnalytics(this.analyticsPeriod);

            // Build employee performance metrics
            this.buildEmployeePerformance();

            // Render the interface
            this.renderInterface();

        } catch (error) {
            console.error('BusinessManager: Error loading data', error);
            this.renderError(error.message);
        }
    }

    startLiveUpdates() {
        if (!this.isFiveM || this.liveUpdateTimer) return;
        this.liveUpdateTimer = setInterval(() => {
            this.refreshLiveData();
        }, this.liveUpdateIntervalMs);
        this.refreshLiveData();
    }

    stopLiveUpdates() {
        if (this.liveUpdateTimer) {
            clearInterval(this.liveUpdateTimer);
            this.liveUpdateTimer = null;
        }
    }

    async refreshLiveData() {
        if (!this.isFiveM || !this.businessId || this.isRefreshing) return;
        const windowEl = document.getElementById('business-manager-window');
        if (!windowEl || windowEl.style.display === 'none') return;

        this.isRefreshing = true;
        try {
            const dataResult = await this.fetchServer('pc:business:getData', {
                businessId: this.businessId
            });
            if (dataResult.ok) {
                this.businessData = dataResult.data;
            }

            const txResult = await this.fetchServer('pc:business:transactions:list', {
                businessId: this.businessId,
                limit: 100
            });
            if (txResult.ok) {
                this.transactions = txResult.data;
            }

            const empResult = await this.fetchServer('pc:business:employees:list', {
                businessId: this.businessId
            });
            if (empResult.ok) {
                this.employees = empResult.data;
            }

            if (this.currentSection === 'menu') {
                const menuResult = await this.fetchServer('pc:business:menu:list', {
                    businessId: this.businessId
                });
                if (menuResult.ok) {
                    this.menuItems = menuResult.data;
                }
            }

            await this.fetchAnalytics(this.analyticsPeriod);
            this.buildEmployeePerformance();

            if (['dashboard', 'analytics', 'transactions', 'employees', 'menu'].includes(this.currentSection)) {
                this.navigateTo(this.currentSection);
            }
        } catch (error) {
            console.error('BusinessManager: Live refresh failed', error);
        } finally {
            this.isRefreshing = false;
        }
    }

    async fetchAnalytics(period) {
        if (!this.isFiveM || !this.businessId) return;
        const result = await this.fetchServer('pc:business:analytics', {
            businessId: this.businessId,
            period: period || 'week'
        });
        if (result && result.ok) {
            this.analyticsData = result.data;
        }
    }

    buildEmployeePerformance() {
        const perfMap = {};
        const transactions = this.transactions || [];

        transactions.forEach(tx => {
            const id = tx.mechanic_id || tx.mechanicId || tx.employeeId || null;
            const name = tx.mechanic_name || tx.employee || tx.processedBy || 'Unknown';
            const key = id || name;
            if (!perfMap[key]) {
                perfMap[key] = { salesCount: 0, salesTotal: 0 };
            }
            perfMap[key].salesCount += 1;
            perfMap[key].salesTotal += Number(tx.total || tx.amount || 0);
        });

        let maxSales = 0;
        this.employees = (this.employees || []).map(emp => {
            const key = emp.citizenid || emp.id || emp.identifier || emp.name;
            const perf = perfMap[key] || perfMap[emp.name] || { salesCount: 0, salesTotal: 0 };
            maxSales = Math.max(maxSales, perf.salesTotal);
            return {
                ...emp,
                salesCount: perf.salesCount,
                salesTotal: perf.salesTotal,
                performance: emp.performance || 0,
                isActive: emp.isActive ?? emp.duty ?? emp.online ?? false
            };
        });

        if (maxSales > 0) {
            this.employees = this.employees.map(emp => ({
                ...emp,
                performance: Math.round((Number(emp.salesTotal || 0) / maxSales) * 100)
            }));
        }
    }

    getAnalyticsSeries(period) {
        const data = this.analyticsData || {};
        if (data.series && data.series[period]) {
            return data.series[period];
        }
        if (period === 'day' && Array.isArray(data.salesByHour) && data.salesByHour.length) {
            return {
                labels: Array.from({ length: data.salesByHour.length }, (_, i) => `${i}:00`),
                values: data.salesByHour
            };
        }
        if ((period === 'week' || period === 'month') && Array.isArray(data.salesByDay) && data.salesByDay.length) {
            return {
                labels: data.salesByDay.map(row => String(row.day ?? row.label ?? '')),
                values: data.salesByDay.map(row => Number(row.revenue ?? row.sales ?? 0))
            };
        }
        return { labels: [], values: [] };
    }

    loadDemoData() {
        // Demo business config for browser testing
        this.businessConfig = {
            job: 'burgershot',
            businessName: 'Burger Shot',
            businessType: 'restaurant',
            businessTypeConfig: {
                name: 'Restaurant',
                icon: '🍔',
                features: [
                    'analytics',
                    'menu_management',
                    'employee_management',
                    'inventory',
                    'transactions',
                    'promotions',
                    'customer_reviews'
                ],
                menuCategories: ['Burgers', 'Sides', 'Drinks', 'Desserts', 'Specials', 'Combos'],
                ingredients: [
                    { name: 'Beef Patty', category: 'protein', cost: 2.50 },
                    { name: 'Chicken Breast', category: 'protein', cost: 2.00 },
                    { name: 'Lettuce', category: 'vegetable', cost: 0.25 },
                    { name: 'Tomato', category: 'vegetable', cost: 0.30 },
                    { name: 'Onion', category: 'vegetable', cost: 0.20 },
                    { name: 'Cheddar Cheese', category: 'cheese', cost: 0.50 },
                    { name: 'Ketchup', category: 'sauce', cost: 0.10 },
                    { name: 'Mayo', category: 'sauce', cost: 0.10 },
                    { name: 'Regular Bun', category: 'bun', cost: 0.50 }
                ]
            }
        };

        this.businessData = {
            id: 'burgershot',
            totalRevenue: 45280.50,
            totalTransactions: 1247,
            employeeCount: 4,
            stats: {
                today: { sales: 87, transactions: 87, revenue: 1245.30 },
                week: { sales: 523, transactions: 523, revenue: 8450.75 },
                month: { sales: 2104, transactions: 2104, revenue: 35280.50 }
            }
        };

        this.menuItems = this.generateDemoMenuItems();
        this.transactions = this.generateDemoTransactions();
        this.employees = this.generateDemoEmployees();
        this.analyticsData = this.generateDemoAnalytics();
        this.buildEmployeePerformance();

        // Render the interface
        this.renderInterface();
    }

    renderAccessDenied(error) {
        const container = document.querySelector('#business-manager-window .window-content');
        if (!container) return;

        let message = 'You do not have access to Business Manager.';
        if (error === 'job_not_allowed') {
            message = 'Your job does not have a business to manage.';
        } else if (error === 'insufficient_grade') {
            message = 'You do not have sufficient rank to access Business Manager.';
        }

        container.innerHTML = `
            <div style="padding: 40px; text-align: center;">
                <h2 style="color: var(--danger); margin-bottom: 20px;">🚫 Access Denied</h2>
                <p style="color: var(--text-muted); font-size: 16px;">${message}</p>
            </div>
        `;
    }

    renderError(message) {
        const container = document.querySelector('#business-manager-window .window-content');
        if (!container) return;

        container.innerHTML = `
            <div style="padding: 40px; text-align: center;">
                <h2 style="color: var(--danger); margin-bottom: 20px;">⚠️ Error</h2>
                <p style="color: var(--text-muted); font-size: 16px;">${message}</p>
            </div>
        `;
    }

    handleJobChange(jobData) {
        console.log('BusinessManager: Job change detected, refreshing data...', jobData);
        // Reset the dataLoaded flag to force reload on next window open
        this.dataLoaded = false;
        
        // If the window is currently open, reload immediately
        const window = document.getElementById('business-manager-window');
        if (window && window.style.display !== 'none') {
            console.log('BusinessManager: Window is open, reloading business data immediately');
            this.loadBusinessData();
        } else {
            console.log('BusinessManager: Window is closed, will reload on next open');
        }
    }

    renderInterface() {
        const container = document.querySelector('#business-manager-window .window-content');
        if (!container) return;

        const typeConfig = this.businessConfig.businessTypeConfig || {
            name: this.businessConfig.businessType || 'Business',
            icon: '🏢',
            features: [],
        };
        const icon = typeConfig.icon || '🏢';
        const logoHtml = this.businessConfig.logoUrl 
            ? `<img src="${this.businessConfig.logoUrl}" alt="Business Logo" style="width: 100%; height: 100%; object-fit: contain;">`
            : icon;

        container.innerHTML = `
            <div class="business-manager-container">
                <div class="business-sidebar">
                    <div class="business-header" id="business-header-dropdown">
                        <div class="business-logo">${logoHtml}</div>
                        <div class="business-info">
                            <div class="business-name" style="cursor: pointer; display: flex; align-items: center; gap: 8px;">
                                ${this.businessConfig.businessName}
                                <i class="fas fa-chevron-down" style="font-size: 12px;"></i>
                            </div>
                            <div class="business-type">${typeConfig.name}</div>
                        </div>
                    </div>
                    <div id="business-switcher-menu" style="display: none; position: absolute; top: 80px; left: 10px; background: #1e1e1e; border: 2px solid #0066ff; border-radius: 8px; min-width: 250px; max-height: 250px; overflow-y: auto; z-index: 10000; box-shadow: 0 4px 20px rgba(0,0,0,0.5);">
                        <div style="padding: 8px; color: #888; font-size: 12px; border-bottom: 1px solid #333;">Current Job</div>
                        <div style="padding: 12px; background: #0066ff; color: white; cursor: pointer; display: flex; align-items: center; justify-content: space-between;">
                            <span>${this.businessConfig.businessName}</span>
                            <i class="fas fa-check"></i>
                        </div>
                        <div style="padding: 8px; color: #888; font-size: 12px; border-top: 1px solid #333; border-bottom: 1px solid #333;">Quick Actions</div>
                        <div style="padding: 12px; cursor: pointer; color: #aaa; display: flex; align-items: center; gap: 8px; hover: color: white;" onmouseover="this.style.background='#2a2a2a'" onmouseout="this.style.background='transparent'" onclick="TriggerEvent('openJobMenu');">
                            <i class="fas fa-briefcase"></i> Open Job Menu (F10)
                        </div>
                    </div>
                    <div class="business-nav">
                        <div class="business-nav-item active" data-section="dashboard">
                            <i class="fas fa-chart-line"></i> Dashboard
                        </div>
                        <div class="business-nav-item" data-section="analytics">
                            <i class="fas fa-chart-bar"></i> Analytics
                        </div>
                        <div class="business-nav-item" data-section="menu">
                            <i class="fas fa-utensils"></i> ${(typeConfig.features || []).includes('menu_management') ? 'Menu' : 'Services'}
                        </div>
                        <div class="business-nav-item" data-section="transactions">
                            <i class="fas fa-credit-card"></i> Transactions
                        </div>
                        <div class="business-nav-item" data-section="employees">
                            <i class="fas fa-users"></i> Employees
                        </div>
                        <div class="business-nav-item" data-section="wages">
                            <i class="fas fa-money-bill"></i> Wages
                        </div>
                        <div class="business-nav-item" data-section="company-account">
                            <i class="fas fa-piggy-bank"></i> Company Account
                        </div>
                        <div class="business-nav-item" data-section="inventory">
                            <i class="fas fa-boxes"></i> Inventory
                        </div>
                        <div class="business-nav-item" data-section="settings">
                            <i class="fas fa-cog"></i> Settings
                        </div>
                    </div>
                </div>
                <div class="business-content" id="business-content">
                    ${this.renderDashboard()}
                </div>
            </div>
        `;

        this.attachEventListeners();
    }

    attachEventListeners() {
        // Business header dropdown toggle
        const headerDropdown = document.getElementById('business-header-dropdown');
        const switcherMenu = document.getElementById('business-switcher-menu');
        if (headerDropdown && switcherMenu) {
            headerDropdown.addEventListener('click', (e) => {
                e.stopPropagation();
                switcherMenu.style.display = switcherMenu.style.display === 'none' ? 'block' : 'none';
            });
            
            // Close dropdown when clicking outside
            document.addEventListener('click', (e) => {
                if (!headerDropdown.contains(e.target) && !switcherMenu.contains(e.target)) {
                    switcherMenu.style.display = 'none';
                }
            });
        }
        
        // Navigation
        const navItems = document.querySelectorAll('.business-nav-item');
        console.log('BusinessManager: Attaching event listeners to', navItems.length, 'nav items');
        navItems.forEach(item => {
            item.addEventListener('click', (e) => {
                e.preventDefault();
                e.stopPropagation();
                const section = item.dataset.section;
                console.log('BusinessManager: Nav item clicked:', section);
                this.navigateTo(section);
            });
        });
    }

    navigateTo(section) {
        // Update active nav
        document.querySelectorAll('.business-nav-item').forEach(item => {
            item.classList.remove('active');
            if (item.dataset.section === section) {
                item.classList.add('active');
            }
        });

        this.currentSection = section;
        console.log('BusinessManager: Navigating to section:', section);

        // Render section
        const content = document.getElementById('business-content');
        if (!content) {
            console.error('BusinessManager: Content container not found');
            return;
        }

        try {
        try {
            const sections = {
                'dashboard': this.renderDashboard(),
                'analytics': this.renderAnalytics(),
                'menu': this.renderMenu(),
                'transactions': this.renderTransactions(),
                'employees': this.renderEmployees(),
                'wages': this.renderWages(),
                'company-account': this.renderCompanyAccount(),
                'inventory': this.renderInventory(),
                'settings': this.renderSettings()
            };

            const html = sections[section] || sections['dashboard'];
            if (!html) {
                console.warn('BusinessManager: No HTML returned for section:', section);
                return;
            }

            content.innerHTML = html;
            console.log('BusinessManager: Successfully rendered section:', section);
            this.attachSectionHandlers(section);
        } catch (error) {
            console.error('BusinessManager: Error rendering section', section, error);
            console.error('Stack:', error.stack);
            content.innerHTML = `<div class="error-message" style="color: red; padding: 20px;">Error loading ${section}: ${error.message}</div>`;
        }
        } catch (error) {
            console.error('BusinessManager: Error rendering section', section, error);
            content.innerHTML = `<div class="error-message">Error loading section: ${error.message}</div>`;
        }
    }

    renderDashboard() {
        const stats = this.businessData?.stats || {
            today: { revenue: 0, transactions: 0, sales: 0 },
            week: { revenue: 0, transactions: 0, sales: 0 },
            month: { revenue: 0, transactions: 0, sales: 0 }
        };

        // Calculate percentage changes (simplified - would need historical data for accurate trending)
        const todayRevenue = Math.max(0, parseFloat(stats.today?.revenue || 0));
        const weekRevenue = Math.max(0, parseFloat(stats.week?.revenue || 0));
        const monthRevenue = Math.max(0, parseFloat(stats.month?.revenue || 0));
        const todayTransactions = Math.max(0, parseInt(stats.today?.transactions || 0));
        const activeEmployees = this.employees.filter(e => e.isActive).length;

        return `
            <div class="business-section">
                <h1 class="section-title">Dashboard Overview</h1>
                
                <div class="stats-grid">
                    <div class="stat-card">
                        <div class="stat-icon">💰</div>
                        <div class="stat-info">
                            <div class="stat-label">Today's Revenue</div>
                            <div class="stat-value">$${todayRevenue.toFixed(2)}</div>
                            <div class="stat-change positive">+${(todayRevenue > 0 ? 12.5 : 0).toFixed(1)}%</div>
                        </div>
                    </div>
                    
                    <div class="stat-card">
                        <div class="stat-icon">📦</div>
                        <div class="stat-info">
                            <div class="stat-label">Today's Orders</div>  
                            <div class="stat-value">${todayTransactions}</div>
                            <div class="stat-change positive">+${(todayTransactions > 0 ? 8.3 : 0).toFixed(1)}%</div>
                        </div>
                    </div>
                    
                    <div class="stat-card">
                        <div class="stat-icon">👥</div>
                        <div class="stat-info">
                            <div class="stat-label">Active Employees</div>
                            <div class="stat-value">${activeEmployees}</div>
                            <div class="stat-change neutral">${this.employees.length} total</div>
                        </div>
                    </div>
                    
                    <div class="stat-card">
                        <div class="stat-icon">⭐</div>
                        <div class="stat-info">
                            <div class="stat-label">Week Revenue</div>
                            <div class="stat-value">$${weekRevenue.toFixed(2)}</div>
                            <div class="stat-change positive">+${(weekRevenue > todayRevenue ? 15.2 : 0).toFixed(1)}%</div>
                        </div>
                    </div>
                </div>

                <div class="dashboard-grid">
                    <div class="dashboard-card">
                        <h3>Recent Transactions</h3>
                        <div class="transaction-list">
                            ${this.renderRecentTransactionsList()}
                        </div>
                    </div>
                    
                    <div class="dashboard-card">
                        <h3>Top Selling Items</h3>
                        <div class="top-items-list">
                            ${this.renderTopItemsList()}
                        </div>
                    </div>
                </div>
            </div>
        `;
    }

    renderRecentTransactionsList() {
        if (!this.transactions || this.transactions.length === 0) {
            return '<p class="empty-state">No recent transactions</p>';
        }

        // Get last 5 real transactions
        const recentTransactions = this.transactions.slice(-5).reverse();

        return recentTransactions.map(tx => `
            <div class="transaction-item">
                <div class="tx-info">
                    <div class="tx-type ${tx.type || 'sale'}">${tx.type === 'refund' ? '↩️' : '💳'} ${(tx.type || 'sale').toUpperCase()}</div>
                    <div class="tx-employee">${tx.employee || tx.processedBy || 'System'}</div>
                </div>
                <div class="tx-amount ${(tx.amount || 0) < 0 ? 'negative' : 'positive'}">
                    $${Math.abs(tx.amount || 0).toFixed(2)}
                </div>
            </div>
        `).join('');
    }

    renderTopItemsList() {
        // Group transactions by item type to find top sellers
        if (!this.transactions || this.transactions.length === 0) {
            return '<p class="empty-state">No item data available</p>';
        }

        const itemSales = {};
        this.transactions.forEach(tx => {
            if (tx.items) {
                tx.items.forEach(item => {
                    if (!itemSales[item.name]) {
                        itemSales[item.name] = { sales: 0, revenue: 0 };
                    }
                    itemSales[item.name].sales += item.quantity || 1;
                    itemSales[item.name].revenue += item.price * (item.quantity || 1);
                });
            }
        });

        const topItems = Object.entries(itemSales)
            .map(([name, data]) => ({ name, ...data }))
            .sort((a, b) => b.sales - a.sales)
            .slice(0, 5);

        if (topItems.length === 0) {
            return '<p class="empty-state">No item data available</p>';
        }

        return topItems.map((item, index) => `
            <div class="top-item">
                <div class="item-rank">#${index + 1}</div>
                <div class="item-info">
                    <div class="item-name">${item.name}</div>
                    <div class="item-stats">${item.sales} sold • $${item.revenue.toFixed(2)}</div>
                </div>
            </div>
        `).join('');
    }

    renderAnalytics() {
        const period = this.analyticsPeriod || 'week';
        const chartType = this.analyticsChartType || 'bar';
        return `
            <div class="business-section">
                <h1 class="section-title">Analytics & Reports</h1>
                
                <div class="analytics-controls">
                    <div class="period-selector">
                        <button class="period-btn ${period === 'day' ? 'active' : ''}" data-period="day">Day</button>
                        <button class="period-btn ${period === 'week' ? 'active' : ''}" data-period="week">Week</button>
                        <button class="period-btn ${period === 'month' ? 'active' : ''}" data-period="month">Month</button>
                    </div>
                    <div class="chart-type-selector">
                        <button class="chart-type-btn ${chartType === 'bar' ? 'active' : ''}" data-type="bar"><i class="fas fa-chart-bar"></i> Bar</button>
                        <button class="chart-type-btn ${chartType === 'line' ? 'active' : ''}" data-type="line"><i class="fas fa-chart-line"></i> Line</button>
                    </div>
                    <button class="btn-secondary">
                        <i class="fas fa-file-export"></i> Export Report
                    </button>
                </div>

                <div class="analytics-grid">
                    <div class="analytics-card full-width">
                        <h3>Sales Overview</h3>
                        <div class="chart-container" id="sales-chart">
                            ${this.renderSalesChart(period, chartType)}
                        </div>
                    </div>
                    
                    <div class="analytics-card">
                        <h3>Revenue by Category</h3>
                        <div class="chart-container" id="category-chart">
                            ${this.renderCategoryChart()}
                        </div>
                    </div>
                    
                    <div class="analytics-card">
                        <h3>Employee Performance</h3>
                        <div class="performance-list">
                            ${this.renderEmployeePerformance()}
                        </div>
                    </div>
                </div>
            </div>
        `;
    }

    renderSalesChart(period, chartType = 'bar') {
        const series = this.getAnalyticsSeries(period);
        const data = (series.values || []).map(value => {
            const num = Number(value);
            return Number.isFinite(num) ? num : 0;
        });
        const labels = series.labels || [];

        if (!data.length) {
            return '<div class="empty-state">No sales data yet.</div>';
        }

        const max = Math.max(...data, 0);
        const min = Math.min(...data, 0);

        if (chartType === 'line') {
            return this.renderLineChart(data, labels, max, min);
        }

        return `
            <div class="bar-chart">
                <div class="bar-chart-inner">
                    ${data.map((value, i) => {
                        const range = max - min;
                        const height = range > 0 ? ((value - min) / range) * 100 : (value > 0 ? 100 : 0);
                        return `
                            <div class="chart-bar-wrapper">
                                <div class="chart-bar">
                                    <div class="chart-value">$${value.toLocaleString()}</div>
                                    <div class="chart-bar-fill" style="height: ${height}%"></div>
                                </div>
                                <div class="chart-label">${labels[i] || ''}</div>
                            </div>
                        `;
                    }).join('')}
                </div>
            </div>
        `;
    }

    renderLineChart(data, labels, max, min) {
        const safeData = data && data.length > 1 ? data : [data[0] || 0, data[0] || 0];
        const safeLabels = labels && labels.length > 1 ? labels : [labels[0] || '', labels[0] || ''];
        const range = max - min || 1;
        const padding = { top: 40, right: 20, bottom: 10, left: 10 };
        const chartWidth = 1000;
        const chartHeight = 300;
        
        // Calculate Y-axis labels (5 steps)
        const ySteps = 5;
        const yLabels = [];
        for (let i = 0; i <= ySteps; i++) {
            yLabels.push(Math.round(min + (range / ySteps) * i));
        }
        
        // Create points
        const points = safeData.map((value, i) => {
            const x = padding.left + (i / (safeData.length - 1)) * (chartWidth - padding.left - padding.right);
            const y = chartHeight - padding.bottom - ((value - min) / range) * (chartHeight - padding.top - padding.bottom);
            return { x, y, value };
        });
        
        // Create smooth curve using Catmull-Rom spline
        let pathData = `M ${points[0].x} ${points[0].y}`;
        
        for (let i = 0; i < points.length - 1; i++) {
            const p0 = points[Math.max(0, i - 1)];
            const p1 = points[i];
            const p2 = points[i + 1];
            const p3 = points[Math.min(points.length - 1, i + 2)];
            
            // Calculate control points for smooth curve
            const cp1x = p1.x + (p2.x - p0.x) / 6;
            const cp1y = p1.y + (p2.y - p0.y) / 6;
            const cp2x = p2.x - (p3.x - p1.x) / 6;
            const cp2y = p2.y - (p3.y - p1.y) / 6;
            
            pathData += ` C ${cp1x} ${cp1y}, ${cp2x} ${cp2y}, ${p2.x} ${p2.y}`;
        }

        return `
            <div class="line-chart-container">
                <div class="line-chart-y-axis">
                    ${yLabels.reverse().map(label => `<div class="y-label">$${label.toLocaleString()}</div>`).join('')}
                </div>
                <div class="line-chart-wrapper">
                    <svg class="sales-line-chart" viewBox="0 0 ${chartWidth} ${chartHeight}" preserveAspectRatio="none">
                        <defs>
                            <linearGradient id="line-gradient" x1="0%" y1="0%" x2="0%" y2="100%">
                                <stop offset="0%" style="stop-color:var(--primary);stop-opacity:0.3" />
                                <stop offset="100%" style="stop-color:var(--primary);stop-opacity:0" />
                            </linearGradient>
                        </defs>
                        
                        <!-- Grid lines -->
                        ${yLabels.map((label, i) => {
                            const y = padding.top + (i / ySteps) * (chartHeight - padding.top - padding.bottom);
                            return `<line x1="${padding.left}" y1="${y}" x2="${chartWidth - padding.right}" y2="${y}" stroke="var(--border)" stroke-width="1" opacity="0.3"/>`;
                        }).join('')}
                        
                        <!-- Area under the line -->
                        <path
                            d="${pathData} L ${points[points.length - 1].x} ${chartHeight - padding.bottom} L ${points[0].x} ${chartHeight - padding.bottom} Z"
                            fill="url(#line-gradient)"
                        />
                        
                        <!-- Main line -->
                        <path
                            d="${pathData}"
                            fill="none"
                            stroke="var(--primary)"
                            stroke-width="3"
                            stroke-linecap="round"
                            stroke-linejoin="round"
                        />
                        
                        <!-- Data points -->
                        ${points.map(point => 
                            `<circle cx="${point.x}" cy="${point.y}" r="4" fill="var(--primary)" stroke="var(--surface)" stroke-width="2"/>`
                        ).join('')}
                    </svg>
                    <div class="line-chart-x-axis">
                        ${safeLabels.map((label, i) => {
                            const showLabel = safeLabels.length <= 10 || i % Math.ceil(safeLabels.length / 10) === 0 || i === safeLabels.length - 1;
                            return `<div class="x-label" style="flex: 1; text-align: center;">${showLabel ? label : ''}</div>`;
                        }).join('')}
                    </div>
                </div>
            </div>
        `;
    }

    renderCategoryChart() {
        const categoryData = (this.analyticsData && this.analyticsData.categoryRevenue) || [];
        if (!categoryData.length) {
            return '<div class="empty-state">No category data yet.</div>';
        }

        const total = categoryData.reduce((sum, entry) => sum + Number(entry.revenue || 0), 0) || 1;
        return categoryData.map(entry => {
            const percentage = ((Number(entry.revenue || 0) / total) * 100).toFixed(1);
            return `
                <div class="category-bar">
                    <div class="category-label">${entry.category || 'General'}</div>
                    <div class="category-progress">
                        <div class="category-fill" style="width: ${percentage}%"></div>
                    </div>
                    <div class="category-value">${percentage}%</div>
                </div>
            `;
        }).join('');
    }

    renderEmployeePerformance() {
        return this.employees.slice(0, 5).map(emp => `
            <div class="performance-item">
                <div class="performance-info">
                    <div class="perf-name">${emp.name}</div>
                    <div class="perf-stats">${emp.salesCount || 0} sales • $${(emp.salesTotal || 0).toFixed(2)}</div>
                </div>
                <div class="perf-score ${emp.performance >= 80 ? 'high' : emp.performance >= 60 ? 'medium' : 'low'}">
                    ${emp.performance || 0}%
                </div>
            </div>
        `).join('');
    }

    renderMenu() {
        const typeConfig = this.businessConfig.businessTypeConfig || {
            name: this.businessConfig.businessType || 'Business',
            icon: '🏢',
            features: [],
            menuCategories: ['General'],
        };
        const isRestaurant = this.businessConfig.businessType === 'restaurant';
        const isMechanic = this.businessConfig.businessType === 'mechanic';

        return `
            <div class="business-section">
                <div class="section-header">
                    <h1 class="section-title">${isRestaurant ? 'Menu Management' : isMechanic ? 'Cash Register Management' : 'Service Management'}</h1>
                    <div class="button-group">
                        <button class="btn-primary" id="add-menu-item-btn">
                            <i class="fas fa-plus"></i> Add ${isRestaurant ? 'Menu Item' : isMechanic ? 'Service' : 'Item'}
                        </button>
                        ${isRestaurant ? `<button class="btn-primary" id="add-meal-item-btn" style="background-color: #059669;">
                            <i class="fas fa-list"></i> Add Meal Item
                        </button>` : ''}
                        ${isMechanic ? `<button class="btn-secondary" id="manage-categories-btn" style="margin-left: 8px;">
                            <i class="fas fa-folder"></i> Manage Categories
                        </button>` : ''}
                    </div>
                </div>
                
                <div class="menu-tabs">
                    <button class="tab-btn active" data-tab="items">${isMechanic ? 'Services' : 'Items'}</button>
                    ${isRestaurant ? `<button class="tab-btn" data-tab="meals">Meals</button>` : ''}
                </div>

                <div id="items-tab" class="tab-content active">
                    <div class="menu-filters">
                        <select class="filter-select" id="category-filter">
                            <option value="">All Categories</option>
                            ${(typeConfig.menuCategories || []).map(cat => `
                                <option value="${cat}">${cat}</option>
                            `).join('')}
                        </select>
                        <input type="search" class="search-input" id="menu-search" placeholder="Search items...">
                    </div>

                    <div class="menu-grid" id="menu-grid">
                        ${this.renderMenuItems()}
                    </div>
                </div>

                ${isRestaurant ? `<div id="meals-tab" class="tab-content">
                    <div class="menu-grid" id="meals-grid">
                        ${this.renderMealItems()}
                    </div>
                </div>` : ''}
            </div>
        `;
    }

    renderMenuItems() {
        if (!this.menuItems || this.menuItems.length === 0) {
            if (this.isFiveM) {
                return '<p class="empty-state">No items configured yet.</p>';
            }

            const demoItems = this.generateDemoMenuItems();
            return demoItems.map(item => this.renderMenuItem(item)).join('');
        }

        return this.menuItems.map(item => this.renderMenuItem(item)).join('');
    }

    renderMenuItem(item) {
        // Normalize item data with safe defaults
        const itemPrice = Math.max(0, parseFloat(item.price) || 0);
        const itemCost = Math.max(0, parseFloat(item.cost) || 0);
        const itemName = item.name || item.label || 'Item';
        const itemCategory = item.category || 'General';
        const itemDescription = item.description || '';
        const itemAvailable = item.available !== false;
        const itemIngredients = Array.isArray(item.ingredients) ? item.ingredients : [];
        
        const profit = (itemPrice - itemCost).toFixed(2);
        const margin = itemPrice > 0 ? ((profit / itemPrice) * 100).toFixed(1) : '0';

        return `
            <div class="menu-card" data-id="${item.id}">
                <div class="menu-card-header">
                    <div class="menu-category">${itemCategory}</div>
                    <div class="menu-actions">
                        <button class="icon-btn" onclick="(async () => await window.businessManager.editMenuItem(${item.id}))()"><i class="fas fa-edit"></i></button>
                        <button class="icon-btn" onclick="window.businessManager.deleteMenuItem(${item.id})"><i class="fas fa-trash"></i></button>
                    </div>
                </div>
                <div class="menu-card-body">
                    <h3 class="menu-item-name">${itemName}</h3>
                    <p class="menu-item-desc">${itemDescription || 'No description'}</p>
                    <div class="menu-item-ingredients">
                        ${itemIngredients.slice(0, 3).map(ing => `<span class="ingredient-tag">${ing.name}</span>`).join('')}
                        ${itemIngredients.length > 3 ? `<span class="ingredient-tag">+${itemIngredients.length - 3} more</span>` : ''}
                    </div>
                </div>
                <div class="menu-card-footer">
                    <div class="menu-pricing">
                        <div class="price-row">
                            <span class="price-label">Price:</span>
                            <span class="price-value">$${itemPrice.toFixed(2)}</span>
                        </div>
                        <div class="price-row">
                            <span class="price-label">Cost:</span>
                            <span class="price-value">$${itemCost.toFixed(2)}</span>
                        </div>
                        <div class="price-row profit">
                            <span class="price-label">Profit:</span>
                            <span class="price-value">$${profit} (${margin}%)</span>
                        </div>
                    </div>
                    <div class="menu-status">
                        <label class="toggle-switch">
                            <input type="checkbox" ${itemAvailable ? 'checked' : ''} onchange="window.businessManager.toggleItemAvailability(${item.id})">
                            <span class="toggle-slider"></span>
                        </label>
                        <span>${itemAvailable ? 'Available' : 'Unavailable'}</span>
                    </div>
                </div>
            </div>
        `;
    }

    renderMealItems() {
        if (!this.mealItems || this.mealItems.length === 0) {
            return '<p class="empty-state">No meals configured yet. Create meals by combining menu items.</p>';
        }

        return this.mealItems.map(meal => `
            <div class="menu-card" data-id="${meal.id}">
                <div class="menu-card-header">
                    <div class="menu-category">Meal</div>
                    <div class="menu-actions">
                        <button class="icon-btn" onclick="window.businessManager.editMealItem(${meal.id})"><i class="fas fa-edit"></i></button>
                        <button class="icon-btn" onclick="window.businessManager.deleteMealItem(${meal.id})"><i class="fas fa-trash"></i></button>
                    </div>
                </div>
                <div class="menu-card-body">
                    <h3 class="menu-item-name">${meal.name}</h3>
                    <p class="menu-item-desc">${meal.description || 'Meal combo'}</p>
                    <div class="menu-item-ingredients">
                        ${(meal.items || []).slice(0, 3).map(mealItem => {
                            const item = this.menuItems.find(i => i.id === mealItem.itemId);
                            return `<span class="ingredient-tag">${item ? item.name : 'Item'} x${mealItem.quantity || 1}</span>`;
                        }).join('')}
                        ${(meal.items || []).length > 3 ? `<span class="ingredient-tag">+${meal.items.length - 3} more</span>` : ''}
                    </div>
                </div>
                <div class="menu-card-footer">
                    <div class="menu-pricing">
                        <div class="price-row profit">
                            <span class="price-label">Meal Price:</span>
                            <span class="price-value">$${meal.price.toFixed(2)}</span>
                        </div>
                        <div class="price-row">
                            <span class="price-label">Items:</span>
                            <span class="price-value">${meal.items ? meal.items.length : 0}</span>
                        </div>
                    </div>
                    <div class="menu-status">
                        <label class="toggle-switch">
                            <input type="checkbox" ${meal.available ? 'checked' : ''} onchange="window.businessManager.toggleMealAvailability(${meal.id})">
                            <span class="toggle-slider"></span>
                        </label>
                        <span>${meal.available ? 'Available' : 'Unavailable'}</span>
                    </div>
                </div>
            </div>
        `).join('');
    }

    renderTransactions() {
        return `
            <div class="business-section">
                <div class="section-header">
                    <h1 class="section-title">Transaction History</h1>
                    <button class="btn-secondary">
                        <span>📥</span> Export CSV
                    </button>
                </div>
                
                <div class="transaction-filters">
                    <input type="date" class="filter-input" id="tx-date-from" placeholder="From">
                    <input type="date" class="filter-input" id="tx-date-to" placeholder="To">
                    <select class="filter-select" id="tx-type-filter">
                        <option value="">All Types</option>
                        <option value="sale">Sales</option>
                        <option value="refund">Refunds</option>
                        <option value="expense">Expenses</option>
                    </select>
                    <input type="search" class="search-input" id="tx-search" placeholder="Search transactions...">
                </div>

                <div class="transaction-table-container">
                    <table class="transaction-table">
                        <thead>
                            <tr>
                                <th>ID</th>
                                <th>Date & Time</th>
                                <th>Type</th>
                                <th>Items</th>
                                <th>Employee</th>
                                <th>Payment</th>
                                <th>Amount</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${this.renderTransactionRows()}
                        </tbody>
                    </table>
                </div>
            </div>
        `;
    }

    renderTransactionRows() {
        const rows = this.isFiveM ? (this.transactions || []) : this.generateDemoTransactions();
        if (!rows.length) {
            return '<tr><td colspan="8" class="empty-state">No transactions available</td></tr>';
        }

        return rows.map(tx => {
            const idValue = tx.id || tx.transaction_id || 'N/A';
            const idDisplay = idValue;
            const viewId = Number.isFinite(Number(idValue)) ? Number(idValue) : 0;
            const date = tx.date || tx.created_at || tx.timestamp || 'N/A';
            const type = tx.type || 'sale';
            const itemsCount = tx.itemsCount || (tx.items ? tx.items.length : 0);
            const employee = tx.employee || tx.processedBy || tx.mechanic_name || 'System';
            const paymentMethod = tx.paymentMethod || tx.payment_method || 'N/A';
            const amount = Number(tx.amount ?? tx.total ?? 0);

            return `
                <tr class="tx-row">
                    <td>#${idDisplay}</td>
                    <td>${date}</td>
                    <td><span class="tx-badge ${type}">${type}</span></td>
                    <td>${itemsCount} items</td>
                    <td>${employee}</td>
                    <td>${paymentMethod}</td>
                    <td class="${amount < 0 ? 'negative' : 'positive'}">$${Math.abs(amount).toFixed(2)}</td>
                    <td>
                        <button class="icon-btn" onclick="window.businessManager.viewTransaction(${viewId})">👁️</button>
                    </td>
                </tr>
            `;
        }).join('');
    }

    renderEmployees() {
        return `
            <div class="business-section">
                <h1 class="section-title">Employee Management</h1>
                
                <div class="employees-grid">
                    ${this.employees.map(emp => this.renderEmployeeCard(emp)).join('')}
                </div>
            </div>
        `;
    }

    renderEmployeeCard(emp) {
        // Add safety defaults for employee properties
        const empName = emp.name || 'Unknown';
        const empRank = emp.rank || 'Employee';
        const empPerformance = Math.max(0, parseInt(emp.performance) || 0);
        const empSalary = Math.max(0, parseFloat(emp.salary) || 0);
        const empSalesTotal = Math.max(0, parseFloat(emp.salesTotal) || 0);
        const empSalesToday = Math.max(0, parseInt(emp.salesToday) || 0);
        const empActive = Boolean(emp.isActive);
        const empBoss = Boolean(emp.isBoss);
        const empId = emp.id || emp.identifier || 'unknown';

        return `
            <div class="employee-card">
                <div class="emp-header">
                    <div class="emp-avatar">${empBoss ? '👔' : empName.charAt(0)}</div>
                    <div class="emp-info">
                        <h3 class="emp-name">${empName}${empBoss ? ' <span style="color: gold; font-size: 0.8em;">★ BOSS</span>' : ''}</h3>
                        <div class="emp-rank">${empRank}</div>
                    </div>
                    <div class="emp-status ${empActive ? 'active' : 'inactive'}">
                        ${empActive ? '🟢 Active' : '⚪ Offline'}
                    </div>
                </div>
                <div class="emp-body">
                    <div class="emp-stat">
                        <span class="stat-label">Sales Today:</span>
                        <span class="stat-value">${empSalesToday}</span>
                    </div>
                    <div class="emp-stat">
                        <span class="stat-label">Total Revenue:</span>
                        <span class="stat-value">$${empSalesTotal.toFixed(2)}</span>
                    </div>
                    <div class="emp-stat">
                        <span class="stat-label">Performance:</span>
                        <span class="stat-value ${empPerformance >= 80 ? 'high' : empPerformance >= 60 ? 'medium' : 'low'}">
                            ${empPerformance}%
                        </span>
                    </div>
                    <div class="emp-stat">
                        <span class="stat-label">Salary:</span>
                        <span class="stat-value">$${empSalary.toFixed(2)}/hr</span>
                    </div>
                </div>
                <div class="emp-actions">
                    ${!empBoss ? `
                    <button class="btn-small" onclick="window.businessManager.promoteEmployee('${empId}')">⬆️ Promote</button>
                    <button class="btn-small" onclick="window.businessManager.demoteEmployee('${empId}')">⬇️ Demote</button>
                    <button class="btn-small" onclick="window.businessManager.giveBonus('${empId}')">💰 Bonus</button>
                    <button class="btn-small danger" onclick="window.businessManager.fireEmployee('${empId}')">🚫 Fire</button>
                    ` : '<div style="color: gold; text-align: center; padding: 10px;">Owner/Manager</div>'}
                </div>
            </div>
        `;
    }

    renderInventory() {
        const typeConfig = this.businessConfig.businessTypeConfig || {};
        const ingredients = (typeConfig.ingredients || typeConfig.parts || []);

        return `
            <div class="business-section">
                <div class="section-header">
                    <h1 class="section-title">Inventory Management</h1>
                    <button class="btn-primary" id="open-order-supplies">
                        <i class="fas fa-shopping-cart"></i> Order Stock
                    </button>
                </div>
                
                <div class="inventory-grid">
                    ${ingredients.map(item => this.renderInventoryItem(item)).join('')}
                </div>
            </div>
        `;
    }

    renderInventoryItem(item) {
        // In browser mode, use random stock. In FiveM, this will fetch from stash
        let stock = item.stock || Math.floor(Math.random() * 100);
        
        const stockLevel = stock > 50 ? 'high' : stock > 20 ? 'medium' : 'low';
        const itemId = item.id || item.name.replace(/\s+/g, '_');

        return `
            <div class="inventory-card">
                <div class="inv-header">
                    <h3 class="inv-name">${item.name}</h3>
                    <div class="inv-category">${item.category}</div>
                </div>
                <div class="inv-body">
                    <div class="inv-stat-large">
                        <span class="stat-label">Product</span>
                        <span class="stat-value-large">${item.name}</span>
                    </div>
                    <div class="inv-stat-large" style="margin-top: 10px;">
                        <span class="stat-label">In Stock</span>
                        <span class="stat-value-large stock-${stockLevel}">${stock} units</span>
                    </div>
                </div>
            </div>
        `;
    }

    renderWages() {
        return `
            <div class="business-section">
                <div class="section-header">
                    <h1 class="section-title">Wage Management</h1>
                    <p class="section-subtitle">Set salary for each employee grade (Capped by Wage Limits)</p>
                </div>
                
                <div class="wages-container" id="wages-container">
                    <div class="wages-loading">
                        <p>Loading wage configuration...</p>
                    </div>
                </div>
                
                <div class="wages-actions">
                    <button class="btn-primary" id="save-wages-btn">
                        <i class="fas fa-save"></i> Save Wages
                    </button>
                    <button class="btn-secondary" id="reset-wages-btn">
                        <i class="fas fa-redo"></i> Reset Changes
                    </button>
                </div>
            </div>
        `;
    }

    renderCompanyAccount() {
        const balance = this.companyAccountBalance || 0;
        const transactions = this.companyAccountTransactions || [];
        const page = this.companyAccountPage || 1;
        const perPage = 10;
        const totalPages = Math.ceil(transactions.length / perPage);
        const start = (page - 1) * perPage;
        const paginatedTx = transactions.slice(start, start + perPage);

        return `
            <div class="business-section">
                <div class="section-header">
                    <h1 class="section-title">Company Account</h1>
                    <p class="section-subtitle">Manage company funds and view transaction history</p>
                </div>
                
                <div class="account-balance-card">
                    <div class="balance-label">Current Balance</div>
                    <div class="balance-amount">$${balance.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2})}</div>
                </div>

                <div class="account-actions">
                    <button class="btn-primary" id="deposit-btn">
                        <i class="fas fa-plus"></i> Deposit
                    </button>
                    <button class="btn-warning" id="withdraw-btn">
                        <i class="fas fa-minus"></i> Withdraw
                    </button>
                </div>

                <div class="transactions-section">
                    <h2>Transaction History</h2>
                    ${transactions.length === 0 ? `
                        <div class="empty-state">No transactions yet</div>
                    ` : `
                        <table class="transactions-table">
                            <thead>
                                <tr>
                                    <th>Date</th>
                                    <th>Type</th>
                                    <th>Amount</th>
                                    <th>Description</th>
                                    <th>Balance</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${paginatedTx.map(tx => `
                                    <tr class="tx-${tx.type}">
                                        <td>${new Date(tx.date).toLocaleString()}</td>
                                        <td><span class="tx-type-badge ${tx.type}">${tx.type === 'deposit' ? '➕ Deposit' : '➖ Withdrawal'}</span></td>
                                        <td class="amount ${tx.type}">$${tx.amount.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2})}</td>
                                        <td>${tx.description}</td>
                                        <td>$${tx.balanceAfter.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2})}</td>
                                    </tr>
                                `).join('')}
                            </tbody>
                        </table>

                        ${totalPages > 1 ? `
                            <div class="pagination">
                                <button class="page-btn" id="prev-page" ${page <= 1 ? 'disabled' : ''}>
                                    <i class="fas fa-chevron-left"></i> Previous
                                </button>
                                <span class="page-info">Page ${page} of ${totalPages}</span>
                                <button class="page-btn" id="next-page" ${page >= totalPages ? 'disabled' : ''}>
                                    Next <i class="fas fa-chevron-right"></i>
                                </button>
                            </div>
                        ` : ''}
                    `}
                </div>
            </div>

            <!-- Deposit Modal -->
            <div class="modal" id="deposit-modal" style="display: none;">
                <div class="modal-content">
                    <div class="modal-header">
                        <h2>Deposit Funds</h2>
                        <button class="modal-close">&times;</button>
                    </div>
                    <div class="modal-body">
                        <div class="form-group">
                            <label>Amount</label>
                            <input type="number" id="deposit-amount" placeholder="Enter amount" min="0" step="0.01">
                        </div>
                        <div class="form-group">
                            <label>Description (Optional)</label>
                            <input type="text" id="deposit-desc" placeholder="e.g., Weekly Sales">
                        </div>
                    </div>
                    <div class="modal-footer">
                        <button class="btn-secondary modal-close-btn">Cancel</button>
                        <button class="btn-primary" id="confirm-deposit">Confirm Deposit</button>
                    </div>
                </div>
            </div>

            <!-- Withdraw Modal -->
            <div class="modal" id="withdraw-modal" style="display: none;">
                <div class="modal-content">
                    <div class="modal-header">
                        <h2>Withdraw Funds</h2>
                        <button class="modal-close">&times;</button>
                    </div>
                    <div class="modal-body">
                        <div class="form-group">
                            <label>Amount</label>
                            <input type="number" id="withdraw-amount" placeholder="Enter amount" min="0" step="0.01">
                        </div>
                        <div class="form-group">
                            <label>Description (Optional)</label>
                            <input type="text" id="withdraw-desc" placeholder="e.g., Operating Expenses">
                        </div>
                    </div>
                    <div class="modal-footer">
                        <button class="btn-secondary modal-close-btn">Cancel</button>
                        <button class="btn-warning" id="confirm-withdraw">Confirm Withdrawal</button>
                    </div>
                </div>
            </div>
        `;
    }

    renderSettings() {
        const blipColor = Number(this.businessConfig.blipColor ?? 5);
        const blipColors = [
            { value: 1, label: 'White' },
            { value: 2, label: 'Red' },
            { value: 3, label: 'Green' },
            { value: 5, label: 'Yellow' },
            { value: 18, label: 'Blue' },
            { value: 27, label: 'Purple' },
            { value: 40, label: 'Orange' },
            { value: 46, label: 'Light Blue' },
            { value: 47, label: 'Pink' }
        ];
        const blipLocationButton = this.isFiveM
            ? '<button class="btn-secondary" id="set-business-blip">Set Blip to My Location</button>'
            : '';

        return `
            <div class="business-section">
                <h1 class="section-title">Business Settings</h1>
                
                <div class="settings-grid">
                    <div class="setting-card">
                        <h3>Business Information</h3>
                        <div class="setting-group">
                            <label>Business Name</label>
                            <input type="text" id="business-name" class="setting-input" value="${this.businessConfig.businessName}">
                        </div>
                        <div class="setting-group">
                            <label>Business Logo URL</label>
                            <input type="text" id="business-logo" class="setting-input" placeholder="https://example.com/logo.png" value="${this.businessConfig.logoUrl || ''}">
                            <small style="color: #888; font-size: 12px;">Enter a direct image URL (PNG, JPG, GIF). Leave empty to use default icon.</small>
                        </div>
                        <div class="setting-group">
                            <label>Map Blip Color</label>
                            <select id="business-color" class="setting-input">
                                ${blipColors.map(item => `
                                    <option value="${item.value}" ${item.value === blipColor ? 'selected' : ''}>${item.label}</option>
                                `).join('')}
                            </select>
                        </div>
                        <button class="btn-primary" id="save-business-info">Save Business Info</button>
                        ${blipLocationButton}
                    </div>
                    
                    <div class="setting-card">
                        <h3>Business Storage</h3>
                        <p style="color: #888; font-size: 13px; margin-bottom: 12px;">Place storage stashes for your employees to access inventory.</p>
                        <button class="btn-primary" id="place-stash">📦 Place Storage Stash</button>
                    </div>
                    
                    <div class="setting-card">
                        <h3>Business Hours</h3>
                        <div class="setting-group">
                            <label>Opening Time</label>
                            <input type="time" class="setting-input" value="08:00">
                        </div>
                        <div class="setting-group">
                            <label>Closing Time</label>
                            <input type="time" class="setting-input" value="22:00">
                        </div>
                        <button class="btn-primary">Save Hours</button>
                    </div>
                    
                    <div class="setting-card">
                        <h3>Tax Settings</h3>
                        <div class="setting-group">
                            <label>Sales Tax (%)</label>
                            <input type="number" class="setting-input" value="8.5" step="0.1">
                        </div>
                        <button class="btn-primary">Update Tax Rate</button>
                    </div>
                    
                    <div class="setting-card">
                        <h3>Discounts & Promotions</h3>
                        <div class="setting-group">
                            <label>Happy Hour Discount (%)</label>
                            <input type="number" class="setting-input" value="15">
                        </div>
                        <div class="setting-group">
                            <label>Happy Hour Time</label>
                            <input type="time" class="setting-input" value="17:00">
                        </div>
                        <button class="btn-primary">Save Promotion</button>
                    </div>
                </div>
            </div>
        `;
    }

    attachSectionHandlers(section) {
        if (section === 'analytics') {
            let currentPeriod = this.analyticsPeriod || 'week';
            let currentChartType = this.analyticsChartType || 'bar';

            const refreshCharts = async () => {
                await this.fetchAnalytics(currentPeriod);
                this.analyticsPeriod = currentPeriod;
                this.analyticsChartType = currentChartType;

                const chartContainer = document.getElementById('sales-chart');
                if (chartContainer) {
                    chartContainer.innerHTML = this.renderSalesChart(currentPeriod, currentChartType);
                }

                const categoryContainer = document.getElementById('category-chart');
                if (categoryContainer) {
                    categoryContainer.innerHTML = this.renderCategoryChart();
                }

                const performanceContainer = document.querySelector('.performance-list');
                if (performanceContainer) {
                    performanceContainer.innerHTML = this.renderEmployeePerformance();
                }
            };
            
            // Period selector buttons
            const periodBtns = document.querySelectorAll('.period-btn');
            periodBtns.forEach(btn => {
                btn.addEventListener('click', async () => {
                    periodBtns.forEach(b => b.classList.remove('active'));
                    btn.classList.add('active');
                    currentPeriod = btn.dataset.period;
                    await refreshCharts();
                });
            });
            
            // Chart type toggle buttons
            const chartTypeBtns = document.querySelectorAll('.chart-type-btn');
            chartTypeBtns.forEach(btn => {
                btn.addEventListener('click', async () => {
                    chartTypeBtns.forEach(b => b.classList.remove('active'));
                    btn.classList.add('active');
                    currentChartType = btn.dataset.type;
                    await refreshCharts();
                });
            });

            refreshCharts();
        }
        
        if (section === 'menu') {
            // Tab switching
            const tabBtns = document.querySelectorAll('.tab-btn');
            tabBtns.forEach(btn => {
                btn.addEventListener('click', () => {
                    tabBtns.forEach(b => b.classList.remove('active'));
                    btn.classList.add('active');
                    
                    const tabName = btn.dataset.tab;
                    document.querySelectorAll('.tab-content').forEach(tab => {
                        tab.classList.remove('active');
                    });
                    
                    const targetTab = document.getElementById(tabName + '-tab');
                    if (targetTab) {
                        targetTab.classList.add('active');
                    }
                });
            });
            
            // Add menu item button
            const addBtn = document.getElementById('add-menu-item-btn');
            if (addBtn) {
                addBtn.addEventListener('click', async () => await this.showAddMenuItemModal());
            }
            
            // Add meal item button
            const addMealBtn = document.getElementById('add-meal-item-btn');
            if (addMealBtn) {
                addMealBtn.addEventListener('click', () => this.showAddMealItemModal());
            }

            // Category management for mechanic jobs
            const manageCategoriesBtn = document.getElementById('manage-categories-btn');
            if (manageCategoriesBtn) {
                manageCategoriesBtn.addEventListener('click', () => this.showCategoryManagementModal());
            }
            
            // Category filter
            const categoryFilter = document.getElementById('category-filter');
            if (categoryFilter) {
                categoryFilter.addEventListener('change', (e) => {
                    const category = e.target.value;
                    this.filterMenuItems(category);
                });
            }
            
            // Menu search
            const searchInput = document.getElementById('menu-search');
            if (searchInput) {
                searchInput.addEventListener('input', (e) => {
                    this.searchMenuItems(e.target.value);
                });
            }
        }
        
        if (section === 'inventory') {
            const orderBtn = document.getElementById('open-order-supplies');
            if (orderBtn) {
                orderBtn.addEventListener('click', () => {
                    // Open Order Supplies window
                    const orderWindow = document.getElementById('order-supplies-window');
                    if (orderWindow) {
                        orderWindow.style.display = 'flex';
                    }
                });
            }
        }
        
        if (section === 'settings') {
            const saveInfoBtn = document.getElementById('save-business-info');
            if (saveInfoBtn) {
                saveInfoBtn.addEventListener('click', async () => {
                    const name = document.getElementById('business-name').value;
                    const logo = document.getElementById('business-logo').value;
                    const color = document.getElementById('business-color').value;
                    
                    if (!name) {
                        uiNotify('Please enter a business name.', 'error');
                        return;
                    }
                    
                    const saveResult = await this.fetchServer('pc:business:update:settings', {
                        name: name,
                        logoUrl: logo,
                        blipColor: parseInt(color, 10)
                    });

                    if (!saveResult.ok) {
                        uiNotify('Failed to save business settings.', 'error');
                        return;
                    }

                    this.businessConfig.businessName = name;
                    this.businessConfig.logoUrl = logo;
                    this.businessConfig.blipColor = parseInt(color, 10);

                    uiNotify('Business information updated!', 'success');
                    this.renderInterface();
                });
            }

            const setBlipBtn = document.getElementById('set-business-blip');
            if (setBlipBtn) {
                setBlipBtn.addEventListener('click', async () => {
                    const coordsResult = await nuiRequest('pc:getPlayerCoords', {});
                    if (!coordsResult.ok) {
                        uiNotify('Unable to get your position.', 'error');
                        return;
                    }

                    const name = document.getElementById('business-name').value || this.businessConfig.businessName;
                    const color = document.getElementById('business-color').value;
                    const saveResult = await this.fetchServer('pc:business:blips:save', {
                        businessId: this.businessId,
                        name: name,
                        color: parseInt(color, 10),
                        coords: coordsResult.data
                    });

                    if (!saveResult.ok) {
                        uiNotify('Failed to update blip location.', 'error');
                        return;
                    }

                    this.businessConfig.blipCoords = coordsResult.data;
                    uiNotify('Business blip updated to your location.', 'success');
                });
            }

            const placeStashBtn = document.getElementById('place-stash');
            if (placeStashBtn) {
                placeStashBtn.addEventListener('click', async () => {
                    const coordsResult = await nuiRequest('pc:getPlayerCoords', {});
                    if (!coordsResult.ok) {
                        uiNotify('Unable to get your position.', 'error');
                        return;
                    }

                    const saveResult = await this.fetchServer('pc:business:stash:place', {
                        businessId: this.businessId,
                        coords: coordsResult.data
                    });

                    if (!saveResult.ok) {
                        uiNotify('Failed to place storage stash.', 'error');
                        return;
                    }

                    uiNotify('Storage stash placed at your location!', 'success');
                });
            }
        }

        if (section === 'wages') {
            this.loadAndRenderWages();
        }

        if (section === 'company-account') {
            // Load company account data
            this.loadCompanyAccountData();
            
            // Deposit button
            const depositBtn = document.getElementById('deposit-btn');
            if (depositBtn) {
                depositBtn.addEventListener('click', () => {
                    const modal = document.getElementById('deposit-modal');
                    if (modal) modal.style.display = 'flex';
                });
            }
            
            // Withdraw button
            const withdrawBtn = document.getElementById('withdraw-btn');
            if (withdrawBtn) {
                withdrawBtn.addEventListener('click', () => {
                    const modal = document.getElementById('withdraw-modal');
                    if (modal) modal.style.display = 'flex';
                });
            }

            // Close modals
            document.querySelectorAll('.modal-close, .modal-close-btn').forEach(btn => {
                btn.addEventListener('click', (e) => {
                    e.target.closest('.modal').style.display = 'none';
                });
            });

            // Click outside modal to close
            document.querySelectorAll('.modal').forEach(modal => {
                modal.addEventListener('click', (e) => {
                    if (e.target === modal) modal.style.display = 'none';
                });
            });

            // Confirm deposit
            const confirmDepositBtn = document.getElementById('confirm-deposit');
            if (confirmDepositBtn) {
                confirmDepositBtn.addEventListener('click', async () => {
                    const amount = parseFloat(document.getElementById('deposit-amount').value);
                    const description = document.getElementById('deposit-desc').value || 'Deposit';
                    
                    if (!amount || amount <= 0) {
                        uiNotify('Please enter a valid amount.', 'error');
                        return;
                    }

                    const result = await this.fetchServer('pc:business:account:deposit', {
                        businessId: this.businessId,
                        amount: amount,
                        description: description
                    });

                    if (result.ok) {
                        uiNotify(`Deposited $${amount.toFixed(2)} to company account.`, 'success');
                        document.getElementById('deposit-modal').style.display = 'none';
                        document.getElementById('deposit-amount').value = '';
                        document.getElementById('deposit-desc').value = '';
                        await this.loadCompanyAccountData();
                        this.navigateTo('company-account');
                    } else {
                        uiNotify(this.companyAccountError(result.error) || 'Failed to deposit funds.', 'error');
                    }
                });
            }

            // Confirm withdraw
            const confirmWithdrawBtn = document.getElementById('confirm-withdraw');
            if (confirmWithdrawBtn) {
                confirmWithdrawBtn.addEventListener('click', async () => {
                    const amount = parseFloat(document.getElementById('withdraw-amount').value);
                    const description = document.getElementById('withdraw-desc').value || 'Withdrawal';
                    
                    if (!amount || amount <= 0) {
                        uiNotify('Please enter a valid amount.', 'error');
                        return;
                    }

                    if (amount > this.companyAccountBalance) {
                        uiNotify('Insufficient funds in company account.', 'error');
                        return;
                    }

                    const result = await this.fetchServer('pc:business:account:withdraw', {
                        businessId: this.businessId,
                        amount: amount,
                        description: description
                    });

                    if (result.ok) {
                        uiNotify(`Withdrew $${amount.toFixed(2)} from company account.`, 'success');
                        document.getElementById('withdraw-modal').style.display = 'none';
                        document.getElementById('withdraw-amount').value = '';
                        document.getElementById('withdraw-desc').value = '';
                        await this.loadCompanyAccountData();
                        this.navigateTo('company-account');
                    } else {
                        uiNotify(this.companyAccountError(result.error) || 'Failed to withdraw funds.', 'error');
                    }
                });
            }

            // Errors from the company account (the job's bank account).
            this.companyAccountError = (code) => ({
                insufficient_funds: 'Not enough money for that.',
                not_boss: 'Only the boss can withdraw from the company account.',
                bank_unavailable: 'The bank is unavailable right now. Try again shortly.',
                invalid_amount: 'Please enter a valid amount.',
                payment_failed: 'The bank refused the transfer.',
            })[code] || code;

            // Pagination
            const prevPageBtn = document.getElementById('prev-page');
            const nextPageBtn = document.getElementById('next-page');
            
            if (prevPageBtn) {
                prevPageBtn.addEventListener('click', async () => {
                    this.companyAccountPage = (this.companyAccountPage || 1) - 1;
                    this.navigateTo('company-account');
                });
            }

            if (nextPageBtn) {
                nextPageBtn.addEventListener('click', async () => {
                    const totalPages = Math.ceil((this.companyAccountTransactions || []).length / 10);
                    if ((this.companyAccountPage || 1) < totalPages) {
                        this.companyAccountPage = (this.companyAccountPage || 1) + 1;
                        this.navigateTo('company-account');
                    }
                });
            }
        }
    }

    async loadCompanyAccountData() {
        const result = await this.fetchServer('pc:business:account:list', {
            businessId: this.businessId
        });

        if (result && result.ok) {
            this.companyAccountBalance = result.data.balance || 0;
            this.companyAccountTransactions = result.data.transactions || [];
        } else {
            console.warn('Failed to load company account data:', result?.error);
            this.companyAccountBalance = 0;
            this.companyAccountTransactions = [];
        }
    }

    // Helper methods for wage management
    async loadAndRenderWages() {
        const container = document.getElementById('wages-container');
        if (!container) return;

        try {
            // Fetch current wages and caps
            const wagesResult = await this.fetchServer('pc:business:wages:get', {});
            if (!wagesResult.ok) {
                container.innerHTML = `<p class="error-message">${wagesResult.error || 'Failed to load wages'}</p>`;
                return;
            }

            const wages = wagesResult.data;
            
            // Get grades - either from businessConfig or use default structure
            let grades = this.businessConfig.businessGrades || [];
            
            // Fallback: if no grades configured, create default grades 0-4
            if (grades.length === 0) {
                grades = [
                    { level: 0, name: 'Trainee' },
                    { level: 1, name: 'Employee' },
                    { level: 2, name: 'Supervisor' },
                    { level: 3, name: 'Manager' },
                    { level: 4, name: 'Boss' }
                ];
            }

            // Build wage table HTML
            let wagesHtml = `
                <div class="wages-table-container">
                    <table class="wages-table">
                        <thead>
                            <tr>
                                <th>Grade Level</th>
                                <th>Grade Name</th>
                                <th>Current Wage</th>
                                <th>Wage Cap</th>
                                <th>New Wage</th>
                                <th>Status</th>
                            </tr>
                        </thead>
                        <tbody>
            `;

            // Populate grades
            grades.forEach((grade, index) => {
                const gradeLevel = grade.level !== undefined ? grade.level : index;
                const currentWage = wages.wages?.[gradeLevel] || 0;
                const cap = wages.caps?.[gradeLevel] || 0;
                const gradeName = grade.name || `Grade ${gradeLevel}`;

                wagesHtml += `
                    <tr class="wage-row" data-grade="${gradeLevel}">
                        <td class="grade-level">${gradeLevel}</td>
                        <td class="grade-name">${gradeName}</td>
                        <td class="current-wage">$${currentWage.toFixed(2)}</td>
                        <td class="wage-cap">$${cap.toFixed(2)}</td>
                        <td class="new-wage">
                            <input type="number" class="wage-input" value="${currentWage}" min="0" step="0.01" data-cap="${cap}" />
                        </td>
                        <td class="wage-status" data-status="unchanged">
                            <span class="status-badge">No changes</span>
                        </td>
                    </tr>
                `;
            });

            wagesHtml += `
                        </tbody>
                    </table>
                </div>
            `;

            container.innerHTML = wagesHtml;

            // Attach event listeners to wage inputs
            const wageInputs = container.querySelectorAll('.wage-input');
            wageInputs.forEach(input => {
                input.addEventListener('change', (e) => this.validateWageInput(e, container));
                input.addEventListener('input', (e) => this.updateWageStatus(e, container));
            });

            // Attach buttons
            const saveBtn = document.getElementById('save-wages-btn');
            const resetBtn = document.getElementById('reset-wages-btn');

            if (saveBtn) {
                saveBtn.addEventListener('click', () => this.saveWages(wages));
            }

            if (resetBtn) {
                resetBtn.addEventListener('click', () => this.loadAndRenderWages());
            }

        } catch (error) {
            console.error('Error loading wages:', error);
            container.innerHTML = `<p class="error-message">Error loading wage configuration</p>`;
        }
    }

    updateWageStatus(event, container) {
        const input = event.target;
        const row = input.closest('.wage-row');
        const statusCell = row.querySelector('.wage-status');
        const gradeLevel = row.dataset.grade;
        const currentWageCell = row.querySelector('.current-wage');
        const currentWage = parseFloat(currentWageCell.textContent.replace('$', ''));
        const newWage = parseFloat(input.value) || 0;

        if (newWage !== currentWage) {
            statusCell.textContent = '✏️ Modified';
            statusCell.parentElement.dataset.status = 'modified';
        } else {
            statusCell.textContent = 'No changes';
            statusCell.parentElement.dataset.status = 'unchanged';
        }
    }

    validateWageInput(event, container) {
        const input = event.target;
        const cap = parseFloat(input.dataset.cap);
        let value = parseFloat(input.value) || 0;

        if (value > cap) {
            value = cap;
            input.value = cap;
            uiNotify(`Wage exceeds cap of $${cap.toFixed(2)}. Adjusted to cap.`, 'warning');
        }

        if (value < 0) {
            value = 0;
            input.value = 0;
            uiNotify('Wage cannot be negative. Set to 0.', 'warning');
        }

        this.updateWageStatus(event, container);
    }

    async saveWages(previousWages) {
        const container = document.getElementById('wages-container');
        const wageInputs = container.querySelectorAll('.wage-input');
        const newWages = {};

        // Collect new wage values
        wageInputs.forEach(input => {
            const gradeLevel = input.parentElement.parentElement.dataset.grade;
            newWages[gradeLevel] = parseFloat(input.value) || 0;
        });

        // Check if any wages changed
        let wagesChanged = false;
        for (const gradeLevel in newWages) {
            if (newWages[gradeLevel] !== (previousWages.wages?.[gradeLevel] || 0)) {
                wagesChanged = true;
                break;
            }
        }

        if (!wagesChanged) {
            uiNotify('No changes to save.', 'info');
            return;
        }

        // Save to server
        const saveResult = await this.fetchServer('pc:business:wages:set', {
            wages: newWages
        });

        if (!saveResult.ok) {
            uiNotify(`Failed to save wages: ${saveResult.error}`, 'error');
            return;
        }

        uiNotify('Wages saved successfully!', 'success');
        // Reload wages to refresh UI
        await this.loadAndRenderWages();
    }

    // Helper methods
    generateDemoMenuItems() {
        return [
            {
                id: 1,
                name: 'Classic Burger',
                description: 'Beef patty, lettuce, tomato, onion, pickles',
                category: 'Burgers',
                price: 12.99,
                cost: 5.50,
                ingredients: [
                    { name: 'Beef Patty' },
                    { name: 'Lettuce' },
                    { name: 'Tomato' },
                    { name: 'Onion' }
                ],
                available: true
            },
            {
                id: 2,
                name: 'Chicken Sandwich',
                description: 'Grilled chicken breast, mayo, lettuce',
                category: 'Burgers',
                price: 11.99,
                cost: 4.75,
                ingredients: [{ name: 'Chicken Breast' }, { name: 'Mayo' }],
                available: true
            },
            {
                id: 3,
                name: 'French Fries',
                description: 'Crispy golden fries',
                category: 'Sides',
                price: 3.99,
                cost: 1.25,
                ingredients: [],
                available: true
            }
        ];
    }

    generateDemoEmployees() {
        return [
            {
                id: 1,
                name: 'John Doe',
                rank: 'Senior Cook',
                salary: 25.00,
                isActive: true,
                salesToday: 32,
                salesTotal: 3245.50,
                performance: 95
            },
            {
                id: 2,
                name: 'Jane Smith',
                rank: 'Cook',
                salary: 20.00,
                isActive: true,
                salesToday: 28,
                salesTotal: 2890.25,
                performance: 88
            },
            {
                id: 3,
                name: 'Bob Johnson',
                rank: 'Cashier',
                salary: 15.00,
                isActive: false,
                salesToday: 0,
                salesTotal: 1245.00,
                performance: 72
            },
            {
                id: 4,
                name: 'Alice Williams',
                rank: 'Server',
                salary: 12.00,
                isActive: true,
                salesToday: 18,
                salesTotal: 1580.75,
                performance: 82
            }
        ];
    }

    generateDemoTransactions() {
        const transactions = [];
        for (let i = 1; i <= 20; i++) {
            transactions.push({
                id: 1000 + i,
                date: new Date(Date.now() - Math.random() * 7 * 24 * 60 * 60 * 1000).toLocaleString(),
                type: Math.random() > 0.9 ? 'refund' : 'sale',
                itemsCount: Math.floor(Math.random() * 5) + 1,
                employee: ['John Doe', 'Jane Smith', 'Bob Johnson', 'Alice Williams'][Math.floor(Math.random() * 4)],
                paymentMethod: ['Cash', 'Card', 'Digital'][Math.floor(Math.random() * 3)],
                amount: (Math.random() * 100 + 10) * (Math.random() > 0.9 ? -1 : 1)
            });
        }
        return transactions;
    }

    generateDemoAnalytics() {
        const dayValues = [120, 180, 240, 210, 190, 250, 280, 310, 290, 330, 350, 380, 400, 420, 390, 410, 440, 460, 480, 500, 520, 550, 530, 560];
        const weekValues = [2500, 2800, 3200, 2900, 3100, 3400, 3600];
        const monthValues = [15000, 16500, 14200, 17800, 16900, 18200, 19500, 17300, 18800, 20100, 19400, 21000, 22300, 20800, 21500, 23100, 22700, 24000, 23400, 24800, 25200, 26100, 25800, 27000, 26500, 28200, 27800, 29000, 28500, 30000];
        const categories = this.businessConfig?.businessTypeConfig?.menuCategories || ['General'];

        return {
            series: {
                day: {
                    labels: Array.from({ length: 24 }, (_, i) => `${i}:00`),
                    values: dayValues
                },
                week: {
                    labels: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
                    values: weekValues
                },
                month: {
                    labels: Array.from({ length: 30 }, (_, i) => {
                        const date = new Date();
                        date.setDate(date.getDate() - (29 - i));
                        return `${date.getMonth() + 1}/${date.getDate()}`;
                    }),
                    values: monthValues
                }
            },
            categoryRevenue: categories.map((category, index) => ({
                category,
                revenue: (index + 1) * 900
            }))
        };
    }

    // Ingredient quantity control methods
    incrementIngredient(itemId) {
        const input = document.getElementById(`qty-${itemId}`);
        if (input) {
            input.value = (parseInt(input.value) || 0) + 1;
        }
    }

    decrementIngredient(itemId) {
        const input = document.getElementById(`qty-${itemId}`);
        if (input) {
            const current = parseInt(input.value) || 0;
            input.value = Math.max(0, current - 1);
        }
    }

    showNotification(message, type = 'success') {
        const notificationDiv = document.createElement('div');
        notificationDiv.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            padding: 15px 20px;
            background: ${type === 'error' ? '#dc3545' : '#28a745'};
            color: white;
            border-radius: 5px;
            z-index: 10000;
            box-shadow: 0 2px 10px rgba(0,0,0,0.2);
            animation: slideIn 0.3s ease-in;
        `;
        notificationDiv.textContent = message;
        document.body.appendChild(notificationDiv);
        
        setTimeout(() => {
            notificationDiv.style.opacity = '0';
            notificationDiv.style.transition = 'opacity 0.3s ease-out';
            setTimeout(() => notificationDiv.remove(), 300);
        }, 3000);
    }

    async saveIngredientQuantity(itemId) {
        const input = document.getElementById(`qty-${itemId}`);
        const quantity = parseInt(input.value) || 0;

        const result = await this.fetchServer('pc:business:inventory:updateQuantity', {
            businessId: this.businessId,
            ingredientId: itemId,
            quantity: quantity
        });

        if (result && result.ok) {
            this.showNotification(`✓ ${itemId} quantity updated to ${quantity}`);
        } else {
            this.showNotification(`✗ Failed to update quantity`, 'error');
        }
    }

    // Menu item editing
    async editMenuItem(id) {
        console.log('editMenuItem called with id:', id, 'type:', typeof id);
        
        // Find the menu item - handle both string and number ids
        const menuItem = this.menuItems?.find(m => parseInt(m.id) === parseInt(id));
        
        if (!menuItem) {
            console.error('Menu item not found. Available items:', this.menuItems?.map(m => ({ id: m.id, name: m.name })));
            this.showNotification('Menu item not found', 'error');
            return;
        }

        console.log('Found menu item:', menuItem);

        // Fetch categories from server
        const categoriesResult = await this.fetchServer('pc:business:menu:categories:list', {
            businessId: this.businessId
        });
        const categories = categoriesResult.ok && categoriesResult.data ? categoriesResult.data : ['General'];

        console.log('Fetched categories:', categories);

        const typeConfig = this.businessConfig.businessTypeConfig || {};
        const isRestaurant = this.businessConfig.businessType === 'restaurant';
        
        // Create edit modal
        const modalHTML = `
            <div class="modal-overlay" id="edit-menu-modal-${id}">
                <div class="modal-content modal-large">
                    <div class="modal-header">
                        <h2>Edit Menu Item</h2>
                        <button class="modal-close" onclick="document.getElementById('edit-menu-modal-${id}').remove()">×</button>
                    </div>
                    <div class="modal-body">
                        <div class="form-grid">
                            <div class="form-group">
                                <label>Name</label>
                                <input type="text" id="edit-item-name" value="${menuItem.name || ''}" placeholder="Item name">
                            </div>
                            <div class="form-group">
                                <label>Category</label>
                                <select id="edit-item-category">
                                    ${categories.map(cat => `<option value="${cat}" ${cat === menuItem.category ? 'selected' : ''}>${cat}</option>`).join('')}
                                </select>
                            </div>
                            <div class="form-group">
                                <label>Price ($)</label>
                                <input type="number" id="edit-item-price" value="${menuItem.price || 0}" step="0.01" min="0">
                            </div>
                            <div class="form-group full-width">
                                <label>Description</label>
                                <textarea id="edit-item-description" placeholder="Describe this item..." rows="3">${menuItem.description || ''}</textarea>
                            </div>
                            <div class="form-group full-width">
                                <label class="checkbox-label">
                                    <input type="checkbox" id="edit-item-available" ${menuItem.available !== false ? 'checked' : ''}>
                                    <span>Available for sale</span>
                                </label>
                            </div>
                        </div>
                    </div>
                    <div class="modal-footer">
                        <button class="btn-secondary" onclick="document.getElementById('edit-menu-modal-${id}').remove()">Cancel</button>
                        <button class="btn-primary" id="save-edit-menu-item">Save Changes</button>
                    </div>
                </div>
            </div>
        `;
        
        console.log('Modal HTML length:', modalHTML.length);
        console.log('Inserting modal into DOM...');
        document.body.insertAdjacentHTML('beforeend', modalHTML);
        console.log('Modal inserted. Looking for button with id: save-edit-menu-item');
        
        const saveBtn = document.getElementById('save-edit-menu-item');
        console.log('Save button found:', saveBtn);
        
        if (!saveBtn) {
            console.error('Save button not found! Modal div id: edit-menu-modal-' + id);
            return;
        }
        
        // Save button handler - use arrow function to preserve `this` context
        const handleSave = async () => {
            console.log('Save button clicked');
            const updatedItem = {
                name: document.getElementById('edit-item-name').value,
                category: document.getElementById('edit-item-category').value,
                price: parseFloat(document.getElementById('edit-item-price').value),
                description: document.getElementById('edit-item-description').value,
                available: document.getElementById('edit-item-available').checked
            };

            console.log('Updated item:', updatedItem);

            const result = await this.fetchServer('pc:business:menu:editItem', {
                businessId: this.businessId,
                itemId: id,
                item: updatedItem
            });

            console.log('Server result:', result);

            if (result && result.ok) {
                this.showNotification(`✓ Menu item updated`);
                const modal = document.getElementById(`edit-menu-modal-${id}`);
                if (modal) modal.remove();
                // Reload data from server and refresh display
                await this.loadBusinessData();
                this.navigateTo('menu');
            } else {
                const errorMsg = result?.message ? `${result.error}: ${result.message}` : (result?.error || 'Unknown error');
                console.error('Update failed:', errorMsg);
                this.showNotification(`Failed to update menu item: ${errorMsg}`, 'error');
            }
        };
        
        saveBtn.addEventListener('click', handleSave);
        console.log('Event listener attached to save button');
        console.log('Modal should be visible now. Modal ID:', `edit-menu-modal-${id}`);
        const modalDiv = document.getElementById(`edit-menu-modal-${id}`);
        console.log('Modal div element:', modalDiv);
    }

    async deleteMenuItem(id) {
        const confirmed = await uiConfirm('Are you sure you want to delete this menu item?', {
            title: 'Delete Menu Item',
            confirmLabel: 'Delete'
        });
        if (!confirmed) return;
        this.performDeleteMenuItem(id);
    }

    async performDeleteMenuItem(id) {
        const result = await this.fetchServer('pc:business:menu:delete', {
            businessId: this.businessId,
            itemId: id
        });

        if (result && result.ok) {
            this.showNotification(`✓ Menu item deleted`);
            // Reload data from server and refresh display
            await this.loadBusinessData();
            this.navigateTo('menu');
        } else {
            this.showNotification('Failed to delete menu item', 'error');
        }
    }

    toggleItemAvailability(id) {
        console.log('Toggle availability:', id);
    }

    async showAddMenuItemModal() {
        const typeConfig = this.businessConfig.businessTypeConfig || {};
        const isRestaurant = this.businessConfig.businessType === 'restaurant';
        const ingredients = typeConfig.ingredients || [];
        
        // Fetch categories from server
        const categoriesResult = await this.fetchServer('pc:business:menu:categories:list', {
            businessId: this.businessId
        });
        const categories = categoriesResult.ok && categoriesResult.data ? categoriesResult.data : ['General'];
        
        // Create modal overlay
        const modalHTML = `
            <div class="modal-overlay" id="add-menu-modal">
                <div class="modal-content modal-large">
                    <div class="modal-header">
                        <h2>Add ${isRestaurant ? 'Menu Item' : 'Service'}</h2>
                        <button class="modal-close" onclick="document.getElementById('add-menu-modal').remove()">×</button>
                    </div>
                    <div class="modal-body">
                        <div class="form-grid">
                            <div class="form-group">
                                <label>Name</label>
                                <input type="text" id="item-name" placeholder="Item name">
                            </div>
                            <div class="form-group">
                                <label>Category</label>
                                <select id="item-category">
                                    ${categories.map(cat => `<option value="${cat}">${cat}</option>`).join('')}
                                </select>
                            </div>
                            <div class="form-group">
                                <label>Price ($)</label>
                                <input type="number" id="item-price" placeholder="0.00" step="0.01" min="0">
                            </div>
                            <div class="form-group full-width">
                                <label>Description</label>
                                <textarea id="item-description" placeholder="Describe this item..." rows="3"></textarea>
                            </div>
                            <div class="form-group full-width">
                                <label>${isRestaurant ? 'Ingredients' : 'Parts Required'}</label>
                                <div class="ingredients-selector" style="max-height: 200px; overflow-y: auto; border: 1px solid #ddd; padding: 8px; border-radius: 4px;">
                                    ${ingredients.map(ing => `
                                        <div class="ingredient-option" style="display: flex; align-items: center; margin-bottom: 8px; padding: 5px;">
                                            <input type="checkbox" value="${ing.name}" data-cost="${ing.cost}" class="ingredient-check" style="margin-right: 8px;">
                                            <span style="flex: 1;">${ing.name}</span>
                                            <span style="color: #666; margin: 0 8px;">$${ing.cost.toFixed(2)}</span>
                                            <input type="number" class="ingredient-qty" min="1" max="99" value="1" data-ingredient="${ing.name}" style="width: 50px; padding: 4px; border: 1px solid #ccc; border-radius: 3px;">
                                        </div>
                                    `).join('')}
                                </div>
                            </div>
                            <div class="form-group">
                                <label>Total Cost</label>
                                <input type="text" id="item-cost" readonly value="$0.00">
                            </div>
                            <div class="form-group">
                                <label>Profit Margin</label>
                                <input type="text" id="item-margin" readonly value="0%">
                            </div>
                            <div class="form-group full-width">
                                <label class="checkbox-label">
                                    <input type="checkbox" id="auto-add-inventory" checked>
                                    <span>Automatically add quantity to inventory when creating this item</span>
                                </label>
                            </div>
                            <div class="form-group" id="inventory-qty-group">
                                <label>Initial Inventory Quantity</label>
                                <input type="number" id="inventory-quantity" value="10" min="0" step="1">
                            </div>
                        </div>
                    </div>
                    <div class="modal-footer">
                        <button class="btn-secondary" onclick="document.getElementById('add-menu-modal').remove()">Cancel</button>
                        <button class="btn-primary" id="save-menu-item">Save Item</button>
                    </div>
                </div>
            </div>
        `;
        
        document.body.insertAdjacentHTML('beforeend', modalHTML);
        
        // Calculate cost as ingredients are selected
        const checkboxes = document.querySelectorAll('.ingredient-check');
        const costInput = document.getElementById('item-cost');
        const marginInput = document.getElementById('item-margin');
        const priceInput = document.getElementById('item-price');
        const qtyInputs = document.querySelectorAll('.ingredient-qty');
        
        const updateCost = () => {
            let totalCost = 0;
            checkboxes.forEach((cb, idx) => {
                if (cb.checked) {
                    const qty = parseInt(qtyInputs[idx].value) || 1;
                    const ingredientCost = (parseFloat(cb.dataset.cost) || 0) * qty;
                    totalCost += ingredientCost;
                }
            });
            costInput.value = `$${totalCost.toFixed(2)}`;
            
            const price = parseFloat(priceInput.value) || 0;
            if (price > 0 && totalCost > 0) {
                const margin = ((price - totalCost) / price * 100).toFixed(1);
                marginInput.value = `${margin}%`;
            } else {
                marginInput.value = '0%';
            }
        };
        
        checkboxes.forEach(cb => cb.addEventListener('change', updateCost));
        qtyInputs.forEach(input => input.addEventListener('input', updateCost));
        priceInput.addEventListener('input', updateCost);
        
        // Auto-add inventory checkbox toggle
        const autoAddCheckbox = document.getElementById('auto-add-inventory');
        const inventoryQtyGroup = document.getElementById('inventory-qty-group');
        
        autoAddCheckbox.addEventListener('change', () => {
            inventoryQtyGroup.style.display = autoAddCheckbox.checked ? 'flex' : 'none';
        });
        
        // Save button handler
        document.getElementById('save-menu-item').addEventListener('click', async () => {
            const name = document.getElementById('item-name').value;
            const category = document.getElementById('item-category').value;
            const price = parseFloat(document.getElementById('item-price').value) || 0;
            const description = document.getElementById('item-description').value;
            const autoAddInventory = document.getElementById('auto-add-inventory').checked;
            const inventoryQty = autoAddInventory ? parseInt(document.getElementById('inventory-quantity').value) || 0 : 0;
            
            if (!name || price <= 0) {
                this.showNotification('Please enter a name and valid price', 'error');
                return;
            }
            
            const selectedIngredients = [];
            let cost = 0;
            checkboxes.forEach((cb, idx) => {
                if (cb.checked) {
                    const qty = parseInt(qtyInputs[idx].value) || 1;
                    selectedIngredients.push({ name: cb.value, quantity: qty });
                    cost += (parseFloat(cb.dataset.cost) || 0) * qty;
                }
            });
            
            const newItem = {
                name,
                category,
                price,
                cost,
                description,
                ingredients: selectedIngredients,
                available: true
            };
            
            // Save to server
            const result = await this.fetchServer('pc:business:menu:add', {
                businessId: this.businessId,
                item: newItem
            });

            if (result && result.ok) {
                this.showNotification(`✓ Menu item "${name}" created`);
                
                if (autoAddInventory && inventoryQty > 0) {
                    // Optional: add to inventory
                    await this.fetchServer('pc:business:inventory:add', { 
                        item: name, 
                        quantity: inventoryQty 
                    });
                }
                
                document.getElementById('add-menu-modal').remove();
                // Reload data from server and refresh display
                await this.loadBusinessData();
                this.navigateTo('menu');
            } else {
                this.showNotification(`Failed to create menu item: ${result?.error || 'Unknown error'}`, 'error');
            }
        });
    }

    showCategoryManagementModal() {
        const categories = (this.businessConfig.businessTypeConfig?.menuCategories || ['General']);
        const categoryList = categories.map((cat, idx) => `
            <div class="category-item" style="display: flex; justify-content: space-between; align-items: center; padding: 12px; border: 1px solid #ddd; border-radius: 4px; margin-bottom: 8px;">
                <span>${cat}</span>
                <div style="display: flex; gap: 8px;">
                    <button class="btn-small" onclick="window.businessManager.showRenameCategoryModal('${cat}')">
                        <i class="fas fa-edit"></i> Rename
                    </button>
                    ${cat !== 'General' ? `<button class="btn-small danger" onclick="window.businessManager.deleteCategory('${cat}')">
                        <i class="fas fa-trash"></i> Delete
                    </button>` : ''}
                </div>
            </div>
        `).join('');

        const modalHTML = `
            <div class="modal-overlay" id="category-management-modal">
                <div class="modal-content modal-large" style="max-width: 500px;">
                    <div class="modal-header">
                        <h2>Manage Categories</h2>
                        <button class="modal-close" onclick="document.getElementById('category-management-modal').remove()">×</button>
                    </div>
                    <div class="modal-body">
                        <div class="form-group full-width" style="margin-bottom: 20px;">
                            <label>Add New Category</label>
                            <div style="display: flex; gap: 8px;">
                                <input type="text" id="new-category-input" placeholder="Enter category name" style="flex: 1;">
                                <button class="btn-primary" id="add-category-btn">Add</button>
                            </div>
                        </div>
                        <div class="divider" style="margin: 20px 0; border-top: 1px solid #ddd;"></div>
                        <div style="margin-top: 20px;">
                            <h3>Existing Categories</h3>
                            <div id="categories-list" style="margin-top: 12px;">
                                ${categoryList}
                            </div>
                        </div>
                    </div>
                    <div class="modal-footer">
                        <button class="btn-secondary" onclick="document.getElementById('category-management-modal').remove()">Close</button>
                    </div>
                </div>
            </div>
        `;
        
        document.body.insertAdjacentHTML('beforeend', modalHTML);
        
        // Add event listener for add category button
        document.getElementById('add-category-btn').addEventListener('click', async () => {
            const categoryName = document.getElementById('new-category-input').value.trim();
            if (!categoryName) {
                this.showNotification('Please enter a category name', 'error');
                return;
            }
            
            const result = await this.fetchServer('pc:business:menu:categories:add', {
                businessId: this.businessId,
                category: categoryName
            });
            
            if (result && result.ok) {
                this.showNotification(`✓ Category "${categoryName}" added`);
                // Refresh the modal
                document.getElementById('category-management-modal').remove();
                
                // Refresh menu to update category list
                await this.loadBusinessData();
                this.navigateTo('menu');
            } else {
                this.showNotification('Failed to add category', 'error');
            }
        });
    }

    showRenameCategoryModal(oldCategoryName) {
        const modalHTML = `
            <div class="modal-overlay" id="rename-category-modal">
                <div class="modal-content" style="max-width: 400px;">
                    <div class="modal-header">
                        <h2>Rename Category</h2>
                        <button class="modal-close" onclick="document.getElementById('rename-category-modal').remove()">×</button>
                    </div>
                    <div class="modal-body">
                        <div class="form-group">
                            <label>Current Name</label>
                            <input type="text" value="${oldCategoryName}" readonly style="background-color: #f5f5f5;">
                        </div>
                        <div class="form-group">
                            <label>New Name</label>
                            <input type="text" id="rename-input" placeholder="Enter new category name">
                        </div>
                    </div>
                    <div class="modal-footer">
                        <button class="btn-secondary" onclick="document.getElementById('rename-category-modal').remove()">Cancel</button>
                        <button class="btn-primary" id="confirm-rename-btn">Rename</button>
                    </div>
                </div>
            </div>
        `;
        
        document.body.insertAdjacentHTML('beforeend', modalHTML);
        
        document.getElementById('confirm-rename-btn').addEventListener('click', async () => {
            const newCategoryName = document.getElementById('rename-input').value.trim();
            if (!newCategoryName) {
                this.showNotification('Please enter a new category name', 'error');
                return;
            }
            
            const result = await this.fetchServer('pc:business:menu:categories:rename', {
                businessId: this.businessId,
                oldCategory: oldCategoryName,
                newCategory: newCategoryName
            });
            
            if (result && result.ok) {
                this.showNotification(`✓ Category renamed to "${newCategoryName}"`);
                // Close both modals and refresh
                document.getElementById('rename-category-modal').remove();
                document.getElementById('category-management-modal').remove();
                
                // Refresh menu
                await this.loadBusinessData();
                this.navigateTo('menu');
            } else {
                this.showNotification('Failed to rename category', 'error');
            }
        });
    }

    async deleteCategory(categoryName) {
        const confirmed = await uiConfirm(`Delete category "${categoryName}" and all its items?`, {
            title: 'Delete Category',
            confirmLabel: 'Delete'
        });
        if (!confirmed) {
            return;
        }
        
        const result = await this.fetchServer('pc:business:menu:categories:delete', {
            businessId: this.businessId,
            category: categoryName
        });
        
        if (result && result.ok) {
            this.showNotification(`✓ Category "${categoryName}" deleted`);
            // Refresh the UI
            document.getElementById('category-management-modal').remove();
            await this.loadBusinessData();
            this.navigateTo('menu');
        } else {
            this.showNotification('Failed to delete category', 'error');
        }
    }

    viewTransaction(id) {
        console.log('View transaction:', id);
        uiNotify('Transaction details coming soon.', 'info');
    }

    promoteEmployee(id) {
        console.log('Promote employee:', id);
        uiNotify('Employee promoted (demo).', 'success');
    }

    demoteEmployee(id) {
        console.log('Demote employee:', id);
        uiNotify('Employee demoted (demo).', 'info');
    }

    giveBonus(id) {
        console.log('Give bonus:', id);
        uiNotify('Bonus feature coming soon.', 'info');
    }

    fireEmployee(id) {
        console.log('Fire employee:', id);
        uiNotify('Employee fired (demo).', 'success');
    }

    // Meal Item Management
    showAddMealItemModal() {
        const mealItems = this.menuItems.filter(item => ['Burgers', 'Sides', 'Drinks', 'Desserts', 'Specials'].includes(item.category));
        
        const modalHTML = `
            <div class="modal-overlay" id="add-meal-modal">
                <div class="modal-content modal-large">
                    <div class="modal-header">
                        <h2>Add Meal Item</h2>
                        <button class="modal-close" onclick="document.getElementById('add-meal-modal').remove()">×</button>
                    </div>
                    <div class="modal-body">
                        <div class="form-grid">
                            <div class="form-group">
                                <label>Meal Name</label>
                                <input type="text" id="meal-name" placeholder="e.g., Combo #1, Value Meal">
                            </div>
                            <div class="form-group">
                                <label>Meal Price ($)</label>
                                <input type="number" id="meal-price" placeholder="0.00" step="0.01" min="0">
                            </div>
                            <div class="form-group full-width">
                                <label>Description</label>
                                <textarea id="meal-description" placeholder="Describe this meal combo..." rows="2"></textarea>
                            </div>
                            <div class="form-group full-width">
                                <label>Select Menu Items for This Meal</label>
                                <div class="meal-items-selector">
                                    <div style="max-height: 300px; overflow-y: auto;">
                                        ${mealItems.map(item => `
                                            <div class="meal-item-selector" data-item-id="${item.id}">
                                                <input type="checkbox" class="item-checkbox" value="${item.id}" data-name="${item.name}" data-price="${item.price}">
                                                <span class="item-name">${item.name}</span>
                                                <input type="number" class="item-qty" value="1" min="1" max="10" style="width: 60px; margin-left: auto;">
                                                <span class="item-price">$${item.price.toFixed(2)}</span>
                                            </div>
                                        `).join('')}
                                    </div>
                                </div>
                            </div>
                            <div class="form-group full-width">
                                <label>Meal Composition & Pricing</label>
                                <div id="meal-pricing-info" style="background: #f9f9f9; padding: 12px; border-radius: 4px; border-left: 4px solid #3498db; margin-bottom: 10px;">
                                    <div style="margin-bottom: 8px;">
                                        <strong>Items:</strong> <span id="meal-item-count">0 selected</span>
                                    </div>
                                    <div style="margin-bottom: 8px;">
                                        <strong>Default Total:</strong> <span id="meal-default-price" style="color: #2980b9; font-weight: bold;">$0.00</span>
                                    </div>
                                    <div id="meal-savings-container" style="display: none;">
                                        <strong>Meal Savings:</strong> <span id="meal-savings-amount" style="color: #27ae60; font-weight: bold;">-$0.00</span> (vs individual items)
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                    <div class="modal-footer">
                        <button class="btn-secondary" onclick="document.getElementById('add-meal-modal').remove()">Cancel</button>
                        <button class="btn-primary" id="save-meal-item">Create Meal</button>
                    </div>
                </div>
            </div>
        `;
        
        document.body.insertAdjacentHTML('beforeend', modalHTML);
        
        // Update summary when items are selected
        const checkboxes = document.querySelectorAll('.item-checkbox');
        const qtyInputs = document.querySelectorAll('.item-qty');
        const mealPriceInput = document.getElementById('meal-price');
        const itemCountSpan = document.getElementById('meal-item-count');
        const defaultPriceSpan = document.getElementById('meal-default-price');
        const savingsContainer = document.getElementById('meal-savings-container');
        const savingsAmount = document.getElementById('meal-savings-amount');
        
        const updateSummary = () => {
            let selectedCount = 0;
            let totalDefaultPrice = 0;
            
            checkboxes.forEach((cb, idx) => {
                if (cb.checked) {
                    selectedCount++;
                    const qty = parseInt(qtyInputs[idx].value) || 1;
                    const itemPrice = parseFloat(cb.dataset.price) || 0;
                    totalDefaultPrice += itemPrice * qty;
                }
            });
            
            itemCountSpan.textContent = selectedCount + ' selected';
            defaultPriceSpan.textContent = '$' + totalDefaultPrice.toFixed(2);
            
            // Calculate savings
            const mealPrice = parseFloat(mealPriceInput.value) || 0;
            if (mealPrice > 0 && totalDefaultPrice > 0) {
                const savings = totalDefaultPrice - mealPrice;
                if (savings !== 0) {
                    savingsContainer.style.display = 'block';
                    savingsAmount.textContent = (savings > 0 ? '-' : '+') + '$' + Math.abs(savings).toFixed(2);
                    savingsAmount.style.color = savings > 0 ? '#27ae60' : '#e74c3c';
                } else {
                    savingsContainer.style.display = 'none';
                }
            } else {
                savingsContainer.style.display = 'none';
            }
        };
        
        checkboxes.forEach(cb => cb.addEventListener('change', updateSummary));
        qtyInputs.forEach(input => input.addEventListener('input', updateSummary));
        mealPriceInput.addEventListener('input', updateSummary);
        
        // Save button handler
        document.getElementById('save-meal-item').addEventListener('click', async () => {
            const name = document.getElementById('meal-name').value.trim();
            const priceStr = document.getElementById('meal-price').value.trim();
            const price = parseFloat(priceStr) || 0;
            const description = document.getElementById('meal-description').value.trim();
            
            if (!name) {
                uiNotify('Please enter a meal name', 'error');
                return;
            }
            
            if (!priceStr || price <= 0) {
                uiNotify('Please enter a valid meal price (must be greater than $0.00)', 'error');
                return;
            }
            
            const selectedItems = [];
            checkboxes.forEach(cb => {
                if (cb.checked) {
                    const qtyInput = cb.closest('.meal-item-selector').querySelector('.item-qty');
                    const qty = parseInt(qtyInput.value) || 1;
                    selectedItems.push({
                        itemId: parseInt(cb.value),
                        quantity: qty
                    });
                }
            });
            
            if (selectedItems.length === 0) {
                uiNotify('Please select at least one menu item for this meal', 'error');
                return;
            }
            
            const mealPayload = {
                name,
                description,
                items: selectedItems,
                price,
                available: true
            };
            
            // Save to server
            const result = await this.fetchServer('pc:business:meals:add', {
                businessId: this.businessId,
                ...mealPayload
            });
            
            if (result.ok) {
                this.mealItems.push({ id: result.data?.id || Date.now(), ...mealPayload });
                document.getElementById('add-meal-modal').remove();
                await this.loadBusinessData();
                this.navigateTo('menu');
                uiNotify('Meal created successfully!', 'success');
            } else {
                uiNotify(`Failed to create meal: ${result.error || 'Unknown error'}`, 'error');
            }
        });
    }

    editMealItem(mealId) {
        const meal = this.mealItems.find(m => m.id === mealId);
        if (!meal) return;
        
        const mealItems = this.menuItems.filter(item => ['Burgers', 'Sides', 'Drinks', 'Desserts', 'Specials'].includes(item.category));
        
        const modalHTML = `
            <div class="modal-overlay" id="edit-meal-modal">
                <div class="modal-content modal-large">
                    <div class="modal-header">
                        <h2>Edit Meal Item</h2>
                        <button class="modal-close" onclick="document.getElementById('edit-meal-modal').remove()">×</button>
                    </div>
                    <div class="modal-body">
                        <div class="form-grid">
                            <div class="form-group">
                                <label>Meal Name</label>
                                <input type="text" id="edit-meal-name" placeholder="Meal name" value="${meal.name}">
                            </div>
                            <div class="form-group">
                                <label>Meal Price ($)</label>
                                <input type="number" id="edit-meal-price" placeholder="0.00" step="0.01" min="0" value="${meal.price}">
                            </div>
                            <div class="form-group full-width">
                                <label>Description</label>
                                <textarea id="edit-meal-description" placeholder="Describe this meal combo..." rows="2">${meal.description || ''}</textarea>
                            </div>
                            <div class="form-group full-width">
                                <label>Select Menu Items for This Meal</label>
                                <div class="meal-items-selector">
                                    <div style="max-height: 300px; overflow-y: auto;">
                                        ${mealItems.map(item => {
                                            const mealItem = meal.items.find(mi => mi.itemId === item.id);
                                            return `
                                                <div class="meal-item-selector" data-item-id="${item.id}">
                                                    <input type="checkbox" class="item-checkbox" value="${item.id}" data-name="${item.name}" data-price="${item.price}" ${mealItem ? 'checked' : ''}>
                                                    <span class="item-name">${item.name}</span>
                                                    <input type="number" class="item-qty" value="${mealItem ? mealItem.quantity : 1}" min="1" max="10" style="width: 60px; margin-left: auto;">
                                                    <span class="item-price">$${item.price.toFixed(2)}</span>
                                                </div>
                                            `;
                                        }).join('')}
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                    <div class="modal-footer">
                        <button class="btn-secondary" onclick="document.getElementById('edit-meal-modal').remove()">Cancel</button>
                        <button class="btn-danger" id="delete-meal-btn">Delete Meal</button>
                        <button class="btn-primary" id="update-meal-item">Update Meal</button>
                    </div>
                </div>
            </div>
        `;
        
        document.body.insertAdjacentHTML('beforeend', modalHTML);
        
        // Update button handler
        document.getElementById('update-meal-item').addEventListener('click', async () => {
            const name = document.getElementById('edit-meal-name').value.trim();
            const price = parseFloat(document.getElementById('edit-meal-price').value) || 0;
            const description = document.getElementById('edit-meal-description').value.trim();
            
            if (!name || price <= 0) {
                uiNotify('Please enter a meal name and valid price', 'error');
                return;
            }
            
            const checkboxes = document.querySelectorAll('#edit-meal-modal .item-checkbox');
            const selectedItems = [];
            checkboxes.forEach(cb => {
                if (cb.checked) {
                    const qtyInput = cb.closest('.meal-item-selector').querySelector('.item-qty');
                    const qty = parseInt(qtyInput.value) || 1;
                    selectedItems.push({
                        itemId: parseInt(cb.value),
                        quantity: qty
                    });
                }
            });
            
            if (selectedItems.length === 0) {
                uiNotify('Please select at least one menu item for this meal', 'error');
                return;
            }
            
            const updatePayload = {
                name,
                description,
                items: selectedItems,
                price
            };
            
            const result = await this.fetchServer('pc:business:meals:update', {
                businessId: this.businessId,
                mealId,
                ...updatePayload
            });
            
            if (result.ok) {
                const mealIndex = this.mealItems.findIndex(m => m.id === mealId);
                if (mealIndex >= 0) {
                    this.mealItems[mealIndex] = { id: mealId, ...updatePayload, available: meal.available };
                }
                document.getElementById('edit-meal-modal').remove();
                this.navigateTo('menu');
                uiNotify('Meal updated successfully!', 'success');
            } else {
                uiNotify(`Failed to update meal: ${result.error || 'Unknown error'}`, 'error');
            }
        });
        
        // Delete button handler
        document.getElementById('delete-meal-btn').addEventListener('click', async () => {
            const confirmed = await uiConfirm(`Delete "${meal.name}"? This cannot be undone.`, {
                title: 'Delete Meal',
                confirmLabel: 'Delete'
            });
            if (!confirmed) return;
            
            const result = await this.fetchServer('pc:business:meals:delete', {
                businessId: this.businessId,
                mealId
            });
            
            if (result.ok) {
                this.mealItems = this.mealItems.filter(m => m.id !== mealId);
                document.getElementById('edit-meal-modal').remove();
                this.navigateTo('menu');
                uiNotify('Meal deleted successfully!', 'success');
            } else {
                uiNotify(`Failed to delete meal: ${result.error || 'Unknown error'}`, 'error');
            }
        });
    }

    async deleteMealItem(mealId) {
        const meal = this.mealItems.find(m => m.id === mealId);
        if (!meal) return;

        const confirmed = await uiConfirm(`Delete "${meal.name}" meal? This cannot be undone.`, {
            title: 'Delete Meal',
            confirmLabel: 'Continue'
        });
        if (!confirmed) return;
        this.editMealItem(mealId); // Open edit modal which has delete button
    }

    async toggleMealAvailability(mealId) {
        const meal = this.mealItems.find(m => m.id === mealId);
        if (!meal) return;
        
        meal.available = !meal.available;
        
        const result = await this.fetchServer('pc:business:meals:update', {
            businessId: this.businessId,
            mealId,
            available: meal.available
        });
        
        if (!result.ok) {
            meal.available = !meal.available; // Revert on failure
            uiNotify('Failed to update meal availability', 'error');
        }
    }

    filterMenuItems(category) {
        const menuGrid = document.getElementById('menu-grid');
        if (!menuGrid) return;
        
        if (!category) {
            // Show all
            menuGrid.innerHTML = this.renderMenuItems();
        } else {
            // Filter by category
            const filtered = this.menuItems.filter(item => item.category === category);
            menuGrid.innerHTML = filtered.map(item => this.renderMenuItem(item)).join('');
        }
    }

    searchMenuItems(query) {
        const menuGrid = document.getElementById('menu-grid');
        if (!menuGrid) return;
        
        if (!query.trim()) {
            // Show all
            menuGrid.innerHTML = this.renderMenuItems();
        } else {
            // Search by name/description
            const results = this.menuItems.filter(item => 
                item.name.toLowerCase().includes(query.toLowerCase()) ||
                (item.description || '').toLowerCase().includes(query.toLowerCase())
            );
            menuGrid.innerHTML = results.length > 0 
                ? results.map(item => this.renderMenuItem(item)).join('')
                : '<p class="empty-state">No items found matching your search.</p>';
        }
    }

    // Server communication
    fetchServer(eventName, data) {
        return new Promise((resolve) => {
            // Check if running in FiveM
            if (typeof GetParentResourceName === 'undefined') {
                console.warn('fetchServer called outside FiveM environment:', eventName);
                resolve({ ok: false, error: 'Not running in FiveM' });
                return;
            }
            
            fetch(`https://${GetParentResourceName()}/${eventName}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(data || {})
            })
                .then(resp => resp.json())
                .then(resolve)
                .catch(err => {
                    console.error('Fetch error:', err);
                    resolve({ ok: false, error: err.message });
                });
        });
    }
}

// ============================================================================
// ORDER SUPPLIES MANAGER - Manages ingredient/supply ordering
// ============================================================================
class OrderSuppliesManager {
    constructor() {
        this.businessConfig = null;
        this.cart = [];
        this.orders = [];
        this.dataLoaded = false;
        this.supplyItems = [];
        this.catalogCategories = [];
        this.imageBase = 'https://cfx-nui-qb-inventory/html/images/';
        this.filters = { category: 'all', sort: 'desc', search: '' };
        this.fulfillment = 'pickup';
        this.isFiveM = typeof GetParentResourceName !== 'undefined';
        this.liveUpdateTimer = null;
        this.liveUpdateIntervalMs = 3000; // Update every 3 seconds
        // Which business the app is ordering for: a job business ('job') or a player-owned store
        // ('store', paid from the store's bank account through pf-stores). Sent with every request.
        this.context = { mode: null, storeId: null };
        this.storeBalance = null;
        this.deliveryAvailable = false;
        this.canSwitch = false;
        this.init();
    }

    async init() {
        const window = document.getElementById('order-supplies-window');
        if (!window) {
            console.error('Order Supplies window not found');
            return;
        }

        const observer = new MutationObserver((mutations) => {
            mutations.forEach((mutation) => {
                if (mutation.attributeName === 'style') {
                    const display = window.style.display;
                    if (display !== 'none') {
                        if (!this.dataLoaded) {
                            this.dataLoaded = true;
                            this.loadData();
                        }
                        this.startLiveUpdates();
                    } else {
                        this.stopLiveUpdates();
                    }
                }
            });
        });

        observer.observe(window, { attributes: true });
    }

    async loadData() {
        if (!this.isFiveM) {
            this.loadDemoData();
            return;
        }

        const catalogResult = await nuiRequest('pc:supplies:getCatalog', this.requestContext());
        if (!catalogResult.ok) {
            this.renderAccessDenied(catalogResult.error);
            return;
        }

        this.businessConfig = {
            businessId: catalogResult.data?.businessId,
            businessName: catalogResult.data?.businessName,
            businessType: catalogResult.data?.businessType
        };
        this.context = {
            mode: catalogResult.data?.mode || 'job',
            storeId: catalogResult.data?.storeId || null
        };
        this.storeBalance = catalogResult.data?.balance ?? null;
        this.deliveryAvailable = catalogResult.data?.deliveryAvailable === true;
        this.canSwitch = catalogResult.data?.canSwitch === true;
        if (!this.isStore() || !this.deliveryAvailable) this.fulfillment = 'pickup';
        this.cart = [];

        const catalog = catalogResult.data?.catalog || {};
        this.imageBase = catalog.imageBase || this.imageBase;
        this.supplyItems = this.buildSupplyItems(catalog);
        this.catalogCategories = catalog.categories || [];

        await this.refreshOrders();
        this.renderInterface();
    }

    loadDemoData() {
        this.businessConfig = {
            job: 'burgershot',
            businessName: 'Burger Shot',
            businessType: 'restaurant',
            suppliesCatalog: {
                imageBase: 'https://cfx-nui-qb-inventory/html/images/',
                categories: [
                    { id: 'Proteins', label: 'Proteins' },
                    { id: 'Vegetables', label: 'Vegetables' },
                    { id: 'Packaging', label: 'Packaging' }
                ],
                items: [
                    { item: 'beef_patty', label: 'Beef Patty', category: 'Proteins', caseSize: 24, caseContents: '24x Beef Patty', pricePerCase: 60 },
                    { item: 'lettuce', label: 'Lettuce', category: 'Vegetables', caseSize: 40, caseContents: '40x Lettuce', pricePerCase: 25 },
                    { item: 'burger_box', label: 'Burger Boxes', category: 'Packaging', caseSize: 100, caseContents: '100x Burger Boxes', pricePerCase: 30 }
                ]
            }
        };

        const catalog = this.businessConfig.suppliesCatalog;
        this.imageBase = catalog.imageBase || this.imageBase;
        this.supplyItems = this.buildSupplyItems(catalog);
        this.catalogCategories = catalog.categories || [];

        this.orders = [
            { id: 1, createdAt: '2026-02-15T12:45:00Z', total: 245.50, status: 'picked_up', totalCases: 15, fulfillment: 'pickup', items: [] },
            { id: 2, createdAt: '2026-02-10T15:10:00Z', total: 380.75, status: 'ready', totalCases: 22, fulfillment: 'pickup', items: [] },
            { id: 3, createdAt: '2026-02-05T09:30:00Z', total: 195.00, status: 'packing', totalCases: 12, fulfillment: 'pickup', items: [] }
        ];

        this.renderInterface();
    }

    isStore() {
        return this.context && this.context.mode === 'store';
    }

    // The business this request is for (see constructor).
    requestContext(extra) {
        const ctx = {};
        if (this.context && this.context.mode) ctx.mode = this.context.mode;
        if (this.context && this.context.storeId) ctx.storeId = this.context.storeId;
        return Object.assign(ctx, extra || {});
    }

    // Switches between the player's job business and their store (only offered when they have both).
    async switchBusiness() {
        this.context = { mode: this.isStore() ? 'job' : 'store', storeId: null };
        this.dataLoaded = true;
        await this.loadData();
    }

    formatMoney(n) {
        return `$${Number(n || 0).toFixed(2)}`;
    }

    handleJobChange(jobData) {
        console.log('OrderSuppliesManager: Job change detected, refreshing data...', jobData);
        // Reset the dataLoaded flag to force reload on next window open
        this.dataLoaded = false;
        
        // If the window is currently open, reload immediately
        const window = document.getElementById('order-supplies-window');
        if (window && window.style.display !== 'none') {
            console.log('OrderSuppliesManager: Window is open, reloading data immediately');
            this.loadData();
        } else {
            console.log('OrderSuppliesManager: Window is closed, will reload on next open');
        }
    }

    renderInterface() {
        const container = document.querySelector('.order-supplies-content');
        if (!container) return;

        const heading = this.businessConfig.businessType === 'mechanic' ? 'Order Parts' : 'Order Supplies';
        const subheading = this.isStore()
            ? `Restock your store. Orders are paid from the store account (balance ${this.formatMoney(this.storeBalance)}); fund it with Deposit in the store's Manage panel.`
            : this.businessConfig.businessType === 'mechanic'
                ? 'Stock up on parts and materials for your shop'
                : 'Stock up on ingredients and supplies for your restaurant';
        const switchLabel = this.isStore() ? 'Switch to job business' : 'Switch to my store';

        container.innerHTML = `
            <div class="order-supplies-container">
                <div class="order-header">
                    <div class="order-header-left">
                        <h1>${this.businessConfig.businessName} - ${heading}</h1>
                        <p>${subheading}</p>
                    </div>
                    ${this.canSwitch ? `
                        <button class="btn-view-cart" onclick="window.orderSuppliesManager.switchBusiness()">
                            <i class="fas fa-exchange-alt"></i> ${switchLabel}
                        </button>
                    ` : ''}
                    <button class="btn-view-cart" onclick="window.orderSuppliesManager.viewCart()">
                        <i class="fas fa-shopping-cart"></i> Cart (${this.cart.length})
                    </button>
                </div>

                <div class="order-tabs">
                    <button class="order-tab active" data-tab="shop"><i class="fas fa-store"></i> Shop</button>
                    <button class="order-tab" data-tab="cart"><i class="fas fa-shopping-cart"></i> Cart</button>
                    <button class="order-tab" data-tab="orders"><i class="fas fa-clipboard-list"></i> Orders</button>
                    <button class="order-tab" data-tab="history"><i class="fas fa-history"></i> History</button>
                    <button class="order-tab" data-tab="settings"><i class="fas fa-cog"></i> Settings</button>
                </div>

                <div class="order-content" id="order-main-content">
                    ${this.renderShop()}
                </div>
            </div>
        `;

        this.attachEventListeners();
    }

    renderShop() {
        const filteredItems = this.getFilteredItems();
        const grouped = this.groupByCategory(filteredItems);
        const categoryFilters = [
            { id: 'all', label: 'All' },
            ...(this.catalogCategories || [])
        ];

        return `
            <div class="supplies-filters">
                <div class="category-filters">
                    ${categoryFilters.map(cat => `
                        <button class="filter-chip ${this.filters.category === cat.id ? 'active' : ''}" data-category="${cat.id}">
                            ${cat.label}
                        </button>
                    `).join('')}
                </div>
                <button class="sort-chip" id="supplies-sort-toggle">
                    <i class="fas fa-sort-amount-${this.filters.sort === 'asc' ? 'up' : 'down'}"></i>
                    Price: ${this.filters.sort === 'asc' ? 'Low to High' : 'High to Low'}
                </button>
            </div>

            <div class="supplies-search">
                <i class="fas fa-search"></i>
                <input type="text" placeholder="Search supplies..." id="supplies-search" value="${this.filters.search}">
            </div>

            ${Object.keys(grouped).map(category => `
                <div class="supply-category">
                    <h2 class="category-title"><i class="fas fa-box"></i> ${category}</h2>
                    <div class="supply-grid">
                        ${grouped[category].map(item => `
                            <div class="supply-card">
                                <div class="supply-header">
                                    <div class="supply-image">
                                        <img src="${this.getItemImage(item)}" alt="${item.label}" onerror="this.src='${this.imageBase}placeholder.png'">
                                    </div>
                                    <div class="supply-meta">
                                        <h3>${item.label}</h3>
                                        <span class="supply-price">$${item.pricePerCase.toFixed(2)}/case</span>
                                        <div class="supply-case">${item.caseContents}</div>
                                    </div>
                                </div>
                                <div class="supply-quantity">
                                    <label>Quantity:</label>
                                    <div class="quantity-controls">
                                        <button onclick="window.orderSuppliesManager.adjustQuantity('${item.item}', -1)">−</button>
                                        <input type="number" id="qty-${item.item}" value="1" min="1" max="100">
                                        <button onclick="window.orderSuppliesManager.adjustQuantity('${item.item}', 1)">+</button>
                                    </div>
                                </div>
                                <button class="btn-add-to-cart" onclick="window.orderSuppliesManager.addToCart('${item.item}')">
                                    <i class="fas fa-cart-plus"></i> Add to Cart
                                </button>
                            </div>
                        `).join('')}
                    </div>
                </div>
            `).join('')}
        `;
    }

    renderCart() {
        if (this.cart.length === 0) {
            return `
                <div class="empty-cart">
                    <i class="fas fa-shopping-cart"></i>
                    <h2>Your cart is empty</h2>
                    <p>Add some items from the shop to get started</p>
                </div>
            `;
        }

        const total = this.cart.reduce((sum, item) => sum + (item.pricePerCase * item.quantity), 0);

        return `
            <div class="cart-items">
                ${this.cart.map((item, index) => `
                    <div class="cart-item">
                        <div class="cart-item-image">
                            <img src="${this.getItemImage(item)}" alt="${item.label}" onerror="this.src='${this.imageBase}placeholder.png'">
                        </div>
                        <div class="cart-item-info">
                            <h3>${item.label}</h3>
                            <p>$${item.pricePerCase.toFixed(2)} per case</p>
                            <span>${item.caseContents}</span>
                        </div>
                        <div class="cart-item-quantity">
                            <button onclick="window.orderSuppliesManager.updateCartQty(${index}, -1)">−</button>
                            <span>${item.quantity}</span>
                            <button onclick="window.orderSuppliesManager.updateCartQty(${index}, 1)">+</button>
                        </div>
                        <div class="cart-item-total">$${(item.pricePerCase * item.quantity).toFixed(2)}</div>
                        <button class="cart-item-remove" onclick="window.orderSuppliesManager.removeFromCart(${index})">
                            <i class="fas fa-trash"></i>
                        </button>
                    </div>
                `).join('')}
            </div>
            <div class="fulfillment-section">
                <h3>Fulfillment Method</h3>
                <div class="fulfillment-options">
                    <button class="fulfillment-option ${this.fulfillment === 'pickup' ? 'active' : ''}" onclick="window.orderSuppliesManager.setFulfillment('pickup')">
                        <i class="fas fa-warehouse"></i> Self Pickup
                    </button>
                    ${this.isStore() && this.deliveryAvailable ? `
                        <button class="fulfillment-option ${this.fulfillment === 'delivery' ? 'active' : ''}" onclick="window.orderSuppliesManager.setFulfillment('delivery')">
                            <i class="fas fa-truck"></i> Trucking Delivery
                        </button>
                    ` : `
                        <button class="fulfillment-option disabled" disabled>
                            <i class="fas fa-truck"></i> Delivery (Coming Soon)
                        </button>
                    `}
                </div>
                ${this.isStore() ? `
                    <p class="help-text-small">
                        ${this.fulfillment === 'delivery'
                            ? 'Posted to trucking dispatch. The payment is held until a trucker delivers it; the trucker is paid from it. You can cancel while no trucker has taken the job.'
                            : 'Collected from the supplier straight into your store stock.'}
                        Store account: ${this.formatMoney(this.storeBalance)}
                    </p>
                ` : ''}
            </div>
            <div class="cart-footer">
                <div class="cart-total">
                    <span>Total:</span>
                    <span class="total-amount">$${total.toFixed(2)}</span>
                </div>
                <button class="btn-primary btn-large" onclick="window.orderSuppliesManager.checkout()">
                    <i class="fas fa-check"></i> Place Order
                </button>
            </div>
        `;
    }

    isFinishedOrder(order) {
        return ['picked_up', 'cancelled', 'failed'].includes(order.status);
    }

    renderOrders() {
        const activeOrders = (this.orders || []).filter(order => !this.isFinishedOrder(order));

        if (activeOrders.length === 0) {
            return `
                <div class="empty-cart">
                    <i class="fas fa-clipboard-list"></i>
                    <h2>No active orders</h2>
                    <p>Place an order to see it here.</p>
                </div>
            `;
        }

        return `
            <div class="orders-section">
                <h2>Active Orders</h2>
                <div class="orders-grid">
                    ${activeOrders.map(order => `
                        <div class="order-card">
                            <div class="order-header-row">
                                <div>
                                    <div class="order-id">Order #${order.id}</div>
                                    <div class="order-date">${new Date(order.createdAt).toLocaleString()}</div>
                                </div>
                                <div class="order-total">$${order.total.toFixed(2)}</div>
                            </div>
                            ${this.renderOrderTimeline(order)}
                            <div class="order-meta">
                                <span>${order.totalCases} cases</span>
                                <span>${order.items.length} items</span>
                                <span class="order-status-pill status-${order.status}">${order.status.replace('_', ' ')}</span>
                            </div>
                            ${order.status === 'ready' && order.fulfillment === 'pickup' ? `
                                <button class="btn-primary btn-large" onclick="window.orderSuppliesManager.pickupOrder(${order.id})">
                                    <i class="fas fa-truck-loading"></i> Pick Up
                                </button>
                            ` : ''}
                            ${order.cancellable ? `
                                <button class="btn-primary btn-large" onclick="window.orderSuppliesManager.cancelOrder(${order.id})">
                                    <i class="fas fa-times"></i> Cancel &amp; Refund
                                </button>
                            ` : ''}
                        </div>
                    `).join('')}
                </div>
            </div>
        `;
    }

    renderSettings() {
        return `
            <div class="supplies-settings">
                <h2><i class="fas fa-cog"></i> Delivery Settings</h2>
                <p>Configure where supplies will be delivered when ordered for pickup.</p>
                
                <div class="settings-section">
                    <h3>Delivery Location</h3>
                    <p class="help-text">Set the location where pickup trucks will deliver supplies. By default, supplies are delivered to your business location.</p>
                    
                    <button class="btn-primary" onclick="window.orderSuppliesManager.setDeliveryLocation()">
                        <i class="fas fa-map-marker-alt"></i> Set Delivery Location
                    </button>
                    
                    <p class="help-text-small">Click this button, then position the phantom truck where you want deliveries, and press E to confirm.</p>
                </div>
                
                <div class="settings-section">
                    <h3>About Pickup Missions</h3>
                    <ul class="info-list">
                        <li><i class="fas fa-truck"></i> When ready, your order will be available for pickup</li>
                        <li><i class="fas fa-box"></i> Use the forklift to load pallets into the truck</li>
                        <li><i class="fas fa-warehouse"></i> Deliver to your set location to complete the order</li>
                    </ul>
                </div>
            </div>
        `;
    }

    renderHistory() {
        const history = (this.orders || []).filter(order => this.isFinishedOrder(order));
        const finishedLabel = { picked_up: this.isStore() ? 'Delivered' : 'Picked Up', cancelled: 'Cancelled', failed: 'Failed' };

        if (history.length === 0) {
            return `
                <div class="empty-cart">
                    <i class="fas fa-history"></i>
                    <h2>No order history</h2>
                    <p>Picked up orders will appear here.</p>
                </div>
            `;
        }

        return `
            <div class="orders-history">
                <h2>Order History</h2>
                <div class="orders-table">
                    ${history.map(order => `
                        <div class="order-row">
                            <div class="order-id">#${order.id}</div>
                            <div class="order-date">${new Date(order.createdAt).toLocaleDateString()}</div>
                            <div class="order-items">${order.items.length} items</div>
                            <div class="order-total">$${order.total.toFixed(2)}</div>
                            <div class="order-status status-delivered">${finishedLabel[order.status] || order.status}</div>
                        </div>
                    `).join('')}
                </div>
            </div>
        `;
    }

    renderOrderTimeline(order) {
        if (this.isStore()) {
            const detail = {
                awaiting_supplier: 'Paid · offered to suppliers',
                awaiting_delivery: 'Paid · waiting for a trucker',
                assigned: 'A trucker accepted the delivery',
                in_transit: 'On the road',
                delivered: 'Delivered · unpack the pallet at the store',
                ready: 'Paid · ready to collect',
            };
            const text = detail[order.orderStatus] || detail[order.status] || String(order.status).replace(/_/g, ' ');
            return `<div class="order-timeline"><div class="timeline-step active"><div class="step-dot"></div><div class="step-label">${text}</div></div></div>`;
        }
        const stages = [
            { key: 'ordered', label: 'Ordered' },
            { key: 'sorting', label: 'Sorting' },
            { key: 'packing', label: 'Packing' },
            { key: 'ready', label: 'Ready' }
        ];

        const currentIndex = stages.findIndex(stage => stage.key === order.status);

        return `
            <div class="order-timeline">
                ${stages.map((stage, index) => {
                    const state = index < currentIndex ? 'done' : index === currentIndex ? 'active' : '';
                    return `
                        <div class="timeline-step ${state}">
                            <div class="step-dot"></div>
                            <div class="step-label">${stage.label}</div>
                        </div>
                    `;
                }).join('')}
            </div>
        `;
    }

    attachEventListeners() {
        const tabs = document.querySelectorAll('.order-tab');
        tabs.forEach(tab => {
            tab.addEventListener('click', () => {
                tabs.forEach(t => t.classList.remove('active'));
                tab.classList.add('active');
                const tabName = tab.dataset.tab;
                this.switchTab(tabName);
            });
        });

        this.attachShopListeners();
    }

    attachShopListeners() {
        const searchInput = document.getElementById('supplies-search');
        if (searchInput) {
            searchInput.addEventListener('input', (e) => {
                this.filters.search = e.target.value || '';
                this.switchTab('shop');
            });
        }

        const filterButtons = document.querySelectorAll('.filter-chip');
        filterButtons.forEach(button => {
            button.addEventListener('click', () => {
                this.filters.category = button.dataset.category || 'all';
                this.switchTab('shop');
            });
        });

        const sortBtn = document.getElementById('supplies-sort-toggle');
        if (sortBtn) {
            sortBtn.addEventListener('click', () => {
                this.filters.sort = this.filters.sort === 'asc' ? 'desc' : 'asc';
                this.switchTab('shop');
            });
        }
    }

    switchTab(tab) {
        const content = document.getElementById('order-main-content');
        if (!content) return;

        if (tab === 'shop') {
            content.innerHTML = this.renderShop();
            this.attachShopListeners();
        } else if (tab === 'cart') {
            content.innerHTML = this.renderCart();
        } else if (tab === 'orders') {
            content.innerHTML = this.renderOrders();
        } else if (tab === 'history') {
            content.innerHTML = this.renderHistory();
        } else if (tab === 'settings') {
            content.innerHTML = this.renderSettings();
        }
    }

    adjustQuantity(itemName, delta) {
        const input = document.getElementById(`qty-${itemName}`);
        if (input) {
            const newVal = Math.max(1, Math.min(100, parseInt(input.value) + delta));
            input.value = newVal;
        }
    }

    addToCart(itemId) {
        const input = document.getElementById(`qty-${itemId}`);
        const quantity = input ? parseInt(input.value) : 1;

        const item = this.supplyItems.find(entry => entry.item === itemId);
        if (!item) {
            uiNotify('Item not found.', 'error');
            return;
        }

        const existingItem = this.cart.find(entry => entry.item === itemId);
        if (existingItem) {
            existingItem.quantity += quantity;
        } else {
            this.cart.push({ ...item, quantity });
        }

        this.updateCartButton();
        uiNotify(`Added ${quantity} case(s) of ${item.label} to cart.`, 'success');
    }

    viewCart() {
        const tabs = document.querySelectorAll('.order-tab');
        tabs.forEach(t => t.classList.remove('active'));
        if (tabs[1]) {
            tabs[1].classList.add('active');
        }
        this.switchTab('cart');
    }

    updateCartQty(index, delta) {
        if (this.cart[index]) {
            this.cart[index].quantity = Math.max(1, this.cart[index].quantity + delta);
            this.switchTab('cart');
        }
    }

    removeFromCart(index) {
        this.cart.splice(index, 1);
        this.switchTab('cart');
        this.updateCartButton();
    }

    setFulfillment(method) {
        this.fulfillment = method;
        this.switchTab('cart');
    }

    async checkout() {
        if (this.cart.length === 0) {
            uiNotify('Your cart is empty.', 'error');
            return;
        }

        const payload = this.requestContext({
            fulfillment: this.fulfillment,
            items: this.cart.map(item => ({ item: item.item, quantity: item.quantity }))
        });

        const result = await nuiRequest('pc:supplies:orders:create', payload);
        if (!result.ok) {
            const messages = {
                insufficient_funds: 'Insufficient company funds.',
                insufficient_store_funds: 'Not enough money in the store account. Deposit funds in the store\'s Manage panel.',
                bank_unavailable: 'Payments are unavailable right now. Try again shortly.',
                payment_failed: 'Payment failed. Nothing was charged.',
                delivery_unavailable: 'Delivery is not available yet.',
                trucking_disabled: 'Trucking delivery is disabled for this store.',
                delivery_locations_not_configured: 'Trucking delivery is not set up for this store.',
                contract_create_failed: 'Trucking dispatch is unavailable; the store was refunded.',
            };
            uiNotify(messages[result.error] || 'Failed to place order.', 'error');
            return;
        }

        if (result.balance != null) this.storeBalance = result.balance;
        uiNotify(result.message || 'Order placed successfully.', 'success');
        this.cart = [];
        this.updateCartButton();
        await this.refreshOrders();
        this.switchTab('orders');
    }

    startLiveUpdates() {
        if (!this.isFiveM || this.liveUpdateTimer) return;
        this.liveUpdateTimer = setInterval(() => {
            this.refreshOrdersQuietly();
        }, this.liveUpdateIntervalMs);
    }

    stopLiveUpdates() {
        if (this.liveUpdateTimer) {
            clearInterval(this.liveUpdateTimer);
            this.liveUpdateTimer = null;
        }
    }

    async refreshOrdersQuietly() {
        // Refresh orders without re-rendering entire interface
        const ordersResult = await nuiRequest('pc:supplies:orders:list', this.requestContext());
        if (ordersResult.ok) {
            const oldOrders = this.orders;
            const oldBalance = this.storeBalance;
            this.orders = ordersResult.data || [];
            if (ordersResult.balance != null) this.storeBalance = ordersResult.balance;

            // Only re-render if orders changed
            if (JSON.stringify(oldOrders) !== JSON.stringify(this.orders) || oldBalance !== this.storeBalance) {
                this.renderInterface();
            }
        }
    }

    async refreshOrders() {
        const ordersResult = await nuiRequest('pc:supplies:orders:list', this.requestContext());
        if (ordersResult.ok) {
            this.orders = ordersResult.data || [];
            if (ordersResult.balance != null) this.storeBalance = ordersResult.balance;
        }
    }

    async pickupOrder(orderId) {
        const result = await nuiRequest('pc:supplies:orders:pickup', this.requestContext({ orderId }));
        if (!result.ok) {
            uiNotify('Pickup failed.', 'error');
            return;
        }
        uiNotify(this.isStore() ? 'Supplies added to your store stock.' : 'Pickup mission started.', 'success');
        await this.refreshOrders();
        this.switchTab('history');
    }

    async cancelOrder(orderId) {
        const result = await nuiRequest('pc:supplies:orders:cancel', this.requestContext({ orderId }));
        if (!result.ok) {
            const msg = result.error === 'already_claimed'
                ? 'A trucker has already taken this delivery.'
                : 'This order can no longer be cancelled.';
            uiNotify(msg, 'error');
            return;
        }
        if (result.balance != null) this.storeBalance = result.balance;
        uiNotify(`Order cancelled. ${this.formatMoney(result.data && result.data.refunded)} returned to the store account.`, 'success');
        await this.refreshOrders();
        this.renderInterface();
    }

    async setDeliveryLocation() {
        if (!this.isFiveM) {
            uiNotify('This feature is only available in-game.', 'info');
            return;
        }
        
        uiNotify('Position the phantom truck where you want deliveries, then press E to confirm', 'info');
        
        // Close the computer UI
        nuiRequest('pc:close', {});
        
        // Trigger client-side delivery location setting
        const result = await nuiRequest('pc:supplies:setDeliveryLocation', {});
        
        if (result && result.ok) {
            uiNotify('Delivery location updated!', 'success');
        } else {
            uiNotify('Failed to set delivery location.', 'error');
        }
    }

    buildSupplyItems(catalog) {
        const items = (catalog && catalog.items) || [];
        return items.map(item => ({
            item: item.item,
            label: item.label,
            category: item.category,
            caseSize: item.caseSize || 10,
            caseContents: item.caseContents || `${item.caseSize || 10}x ${item.label}`,
            pricePerCase: item.pricePerCase || 0,
            image: item.image
        }));
    }

    getFilteredItems() {
        let items = [...(this.supplyItems || [])];
        if (this.filters.category !== 'all') {
            items = items.filter(item => item.category === this.filters.category);
        }
        if (this.filters.search) {
            const q = this.filters.search.toLowerCase();
            items = items.filter(item =>
                (item.label || '').toLowerCase().includes(q) ||
                (item.category || '').toLowerCase().includes(q)
            );
        }
        items.sort((a, b) => {
            if (this.filters.sort === 'asc') {
                return (a.pricePerCase || 0) - (b.pricePerCase || 0);
            }
            return (b.pricePerCase || 0) - (a.pricePerCase || 0);
        });
        return items;
    }

    groupByCategory(items) {
        const grouped = {};
        items.forEach(item => {
            if (!grouped[item.category]) grouped[item.category] = [];
            grouped[item.category].push(item);
        });
        return grouped;
    }

    getItemImage(item) {
        if (item.image) return item.image;
        return `${this.imageBase}${item.item}.png`;
    }

    updateCartButton() {
        const cartBtn = document.querySelector('.btn-view-cart');
        if (cartBtn) {
            cartBtn.innerHTML = `<i class="fas fa-shopping-cart"></i> Cart (${this.cart.length})`;
        }
    }

    renderAccessDenied(error) {
        const container = document.querySelector('.order-supplies-content');
        if (!container) return;

        let message = 'You do not have access to Order Supplies.';
        if (error === 'job_not_allowed') {
            message = 'Your job does not have a business to manage.';
        } else if (error === 'insufficient_grade') {
            message = 'You do not have sufficient rank to access Order Supplies.';
        }

        container.innerHTML = `
            <div style="padding: 40px; text-align: center;">
                <h2 style="color: var(--danger); margin-bottom: 20px;">🚫 Access Denied</h2>
                <p style="color: var(--text-muted); font-size: 16px;">${message}</p>
            </div>
        `;
    }

    renderError(message) {
        const container = document.querySelector('.order-supplies-content');
        if (!container) return;

        container.innerHTML = `
            <div style="padding: 40px; text-align: center;">
                <h2 style="color: var(--danger); margin-bottom: 20px;">⚠️ Error</h2>
                <p style="color: var(--text-muted); font-size: 16px;">${message}</p>
            </div>
        `;
    }
}

// ============================================================================
// DESKTOP MANAGER - Manages icons, folders, and layout
// ============================================================================
class DesktopManager {
    constructor() {
        this.items = this.loadItems();
        this.folders = this.loadFolders();
        this.init();
    }

    init() {
        this.renderDesktop();
        this.setupContextMenu();
    }

    loadItems() {
        const stored = scopedStorageGet('gov_desktop_items');
        if (stored) {
            try {
                const parsedItems = JSON.parse(stored);
                return Array.isArray(parsedItems) ? parsedItems.map(normalizeDesktopItem) : [];
            } catch (error) {
                console.warn('Failed to parse saved desktop items:', error);
            }
        }

        return [
            { id: 'browser', app: 'browser', type: 'app', location: 'desktop', position: { x: 0, y: 0 } },
            { id: 'mail', app: 'mail', type: 'app', location: 'desktop', position: { x: 0, y: 1 } },
            { id: 'calendar', app: 'calendar', type: 'app', location: 'desktop', position: { x: 0, y: 2 } },
            { id: 'maps', app: 'maps', type: 'app', location: 'desktop', position: { x: 0, y: 3 } },
            { id: 'bills', app: 'bills', type: 'app', location: 'desktop', position: { x: 0, y: 4 } },
            { id: 'terminal', app: 'terminal', type: 'app', location: 'desktop', position: { x: 1, y: 2 } },
            { id: 'calculator', app: 'calculator', type: 'app', location: 'desktop', position: { x: 1, y: 3 } },
            { id: 'documents', app: 'documents', type: 'app', location: 'desktop', position: { x: 1, y: 4 } },
            { id: 'settings', app: 'settings', type: 'app', location: 'desktop', position: { x: 2, y: 0 } },
            { id: 'store', app: 'store', type: 'app', location: 'desktop', position: { x: 2, y: 1 } }
        ].map(normalizeDesktopItem);
    }

    loadFolders() {
        const stored = scopedStorageGet('gov_folders');
        if (!stored) return [];

        try {
            const parsedFolders = JSON.parse(stored);
            if (!Array.isArray(parsedFolders)) return [];
            return parsedFolders.map((folder) => ({
                ...folder,
                position: {
                    x: Math.max(0, Math.floor(Number(folder?.position?.x) || 0)),
                    y: Math.max(0, Math.floor(Number(folder?.position?.y) || 0))
                }
            }));
        } catch (error) {
            console.warn('Failed to parse saved folders:', error);
            return [];
        }
    }

    saveItems() {
        scopedStorageSet('gov_desktop_items', JSON.stringify(this.items));
    }

    saveFolders() {
        scopedStorageSet('gov_folders', JSON.stringify(this.folders));
    }

    reloadForScope() {
        this.items = this.loadItems();
        this.folders = this.loadFolders();
        this.renderDesktop();
    }

    getDesktopItemByIcon(iconEl) {
        const iconId = iconEl?.dataset?.id;
        if (iconId) {
            return this.items.find((item) => item.id === iconId) || null;
        }

        const app = resolveAppName(iconEl?.dataset?.app);
        if (!app) return null;
        return this.items.find((item) => item.type === 'app' && resolveAppName(item.app || item.id) === app) || null;
    }

    getDesktopEntityByIcon(iconEl) {
        if (!iconEl) return null;

        if (iconEl.dataset.type === 'folder') {
            const folder = this.folders.find((entry) => entry.id === iconEl.dataset.id);
            if (!folder) return null;
            return {
                key: folder.id,
                location: folder.location,
                position: folder.position,
                kind: 'folder'
            };
        }

        const item = this.getDesktopItemByIcon(iconEl);
        if (!item) return null;

        return {
            key: item.id,
            location: item.location,
            position: item.position,
            kind: item.type || 'app'
        };
    }

    ensureDesktopEntityForIcon(iconEl) {
        if (!iconEl) return null;
        if (iconEl.dataset.type === 'folder') {
            const folder = this.folders.find((entry) => entry.id === iconEl.dataset.id);
            if (!folder) return null;
            return {
                key: folder.id,
                location: folder.location,
                position: folder.position,
                kind: 'folder'
            };
        }

        const appKey = iconEl.dataset.app || iconEl.dataset.id;
        const item = this.getDesktopItemByIcon(iconEl) || this.ensureAppItem(appKey);
        if (!item) return null;

        return {
            key: item.id,
            location: item.location,
            position: item.position,
            kind: item.type || 'app'
        };
    }

    getDesktopGridSize() {
        const container = document.querySelector('.desktop-icons');
        const styles = container ? getComputedStyle(container) : null;

        const columns = Math.max(1, (styles?.gridTemplateColumns || '').split(' ').filter(Boolean).length || 20);
        const rows = Math.max(1, (styles?.gridTemplateRows || '').split(' ').filter(Boolean).length || 10);

        return { columns, rows };
    }

    clampDesktopPosition(x, y) {
        const grid = this.getDesktopGridSize();
        const clampedX = Math.max(0, Math.min(grid.columns - 1, Math.floor(Number(x) || 0)));
        const clampedY = Math.max(0, Math.min(grid.rows - 1, Math.floor(Number(y) || 0)));
        return { x: clampedX, y: clampedY };
    }

    ensureDesktopPositions() {
        const container = document.querySelector('.desktop-icons');
        if (!container) return;

        const iconNodes = Array.from(container.querySelectorAll('.icon'));
        const grid = this.getDesktopGridSize();
        const used = new Set();
        let itemsChanged = false;
        let foldersChanged = false;

        const keyFor = (x, y) => `${x}:${y}`;
        const readGridValue = (value) => {
            const parsed = parseInt(value, 10);
            return Number.isFinite(parsed) ? Math.max(0, parsed - 1) : null;
        };

        const findNextOpenCell = () => {
            for (let y = 0; y < grid.rows; y += 1) {
                for (let x = 0; x < grid.columns; x += 1) {
                    if (!used.has(keyFor(x, y))) {
                        return { x, y };
                    }
                }
            }
            return { x: 0, y: 0 };
        };

        iconNodes.forEach((iconEl) => {
            const entity = this.getDesktopEntityByIcon(iconEl) || this.ensureDesktopEntityForIcon(iconEl);
            if (!entity || entity.location !== 'desktop') return;

            let pos = entity.position ? this.clampDesktopPosition(entity.position.x, entity.position.y) : null;
            if (!pos || used.has(keyFor(pos.x, pos.y))) {
                const inferredX = readGridValue(iconEl.style.gridColumn);
                const inferredY = readGridValue(iconEl.style.gridRow);
                if (inferredX !== null && inferredY !== null) {
                    const inferred = this.clampDesktopPosition(inferredX, inferredY);
                    if (!used.has(keyFor(inferred.x, inferred.y))) {
                        pos = inferred;
                    }
                }
            }

            if (!pos || used.has(keyFor(pos.x, pos.y))) {
                pos = findNextOpenCell();
            }

            used.add(keyFor(pos.x, pos.y));

            if (entity.kind === 'folder') {
                const folder = this.folders.find((entry) => entry.id === entity.key);
                if (folder && (!folder.position || folder.position.x !== pos.x || folder.position.y !== pos.y || folder.location !== 'desktop')) {
                    folder.location = 'desktop';
                    folder.position = pos;
                    foldersChanged = true;
                }
            } else {
                const item = this.items.find((entry) => entry.id === entity.key);
                if (item && (!item.position || item.position.x !== pos.x || item.position.y !== pos.y || item.location !== 'desktop')) {
                    item.location = 'desktop';
                    item.position = pos;
                    itemsChanged = true;
                }
            }
        });

        if (itemsChanged) this.saveItems();
        if (foldersChanged) this.saveFolders();
        if (itemsChanged || foldersChanged) {
            this.applyDesktopPositions();
        }
    }

    ensureAppItem(appName) {
        const resolved = resolveAppName(appName);
        if (!resolved) return null;

        let item = this.items.find((entry) => entry.type === 'app' && resolveAppName(entry.app || entry.id) === resolved);
        if (item) return item;

        item = {
            id: resolved,
            app: resolved,
            type: 'app',
            location: 'desktop',
            position: { x: 0, y: 0 }
        };
        this.items.push(item);
        this.saveItems();
        return item;
    }

    setDesktopPosition(itemKey, x, y, suppressApply = false) {
        const key = resolveAppName(itemKey) || itemKey;
        const clamped = this.clampDesktopPosition(x, y);
        let item = this.items.find((entry) => entry.id === key || resolveAppName(entry.app || entry.id) === key);

        if (!item && key) {
            const folder = this.folders.find((entry) => entry.id === key);
            if (folder) {
                folder.location = 'desktop';
                folder.position = { x: clamped.x, y: clamped.y };
                this.saveFolders();
                this.applyDesktopPositions();
                return;
            }
        }

        if (!item && key) {
            item = this.ensureAppItem(key);
        }

        if (!item) return;

        item.location = 'desktop';
        item.position = { x: clamped.x, y: clamped.y };

        if (!suppressApply) {
            this.saveItems();
            this.applyDesktopPositions();
        }
    }

    applyDesktopPositions() {
        const container = document.querySelector('.desktop-icons');
        if (!container) return;

        const icons = container.querySelectorAll('.icon');
        icons.forEach((iconEl) => {
            const entity = this.getDesktopEntityByIcon(iconEl);
            if (!entity || entity.location !== 'desktop' || !entity.position) {
                iconEl.style.gridColumn = '';
                iconEl.style.gridRow = '';
                return;
            }

            const pos = this.clampDesktopPosition(entity.position.x, entity.position.y);

            iconEl.style.gridColumn = `${Math.max(1, pos.x + 1)}`;
            iconEl.style.gridRow = `${Math.max(1, pos.y + 1)}`;
        });
    }

    renderDesktop() {
        const container = document.querySelector('.desktop-icons');
        if (!container) return;

        const dedupeSeen = new Set();
        container.querySelectorAll('.icon').forEach((icon) => {
            const key = icon.dataset.id || `app:${resolveAppName(icon.dataset.app || '')}`;
            if (!key || key === 'app:') return;
            if (dedupeSeen.has(key)) {
                icon.remove();
                return;
            }
            dedupeSeen.add(key);
        });

        const desktopItems = this.items.filter(item => item.location === 'desktop');
        
        // Remove icons that are no longer on desktop
        const existingIcons = container.querySelectorAll('.icon');
        existingIcons.forEach(icon => {
            const iconId = icon.dataset.id;
            const iconApp = icon.dataset.app;
            
            // Skip the default app icons (browser, mail, calendar, etc.)
            if (iconApp && !iconId) return;
            
            // Check if this icon should still be on desktop
            const item = this.items.find(i => {
                if (iconId) return (i.id === iconId || i.app === iconId) && i.location === 'desktop';
                return false;
            });
            
            const folder = this.folders.find(f => f.id === iconId && f.location === 'desktop');
            
            if (!item && !folder) {
                icon.remove();
            }
        });

        // Add folder icons
        this.folders.forEach(folder => {
            if (folder.location !== 'desktop') return;
            
            let folderIcon = container.querySelector(`.icon[data-id="${folder.id}"]`);
            if (!folderIcon) {
                folderIcon = this.createFolderIcon(folder);
                container.appendChild(folderIcon);
            }
        });

        // Add document icons
        desktopItems.forEach(item => {
            if (item.type === 'document') {
                let docIcon = container.querySelector(`.icon[data-id="${item.id}"]`);
                if (!docIcon) {
                    docIcon = this.createDocumentIcon(item);
                    container.appendChild(docIcon);
                }
            }
        });

        // Add or refresh saved app icons that do not exist in the static desktop markup.
        desktopItems.forEach(item => {
            if (item.type !== 'app') return;

            const savedIcon = container.querySelector(`.icon[data-id="${item.id}"]`);
            const staticIcon = container.querySelector(`.icon[data-app="${item.app}"]:not([data-id])`);

            if (savedIcon) {
                const appName = item.app || item.id;
                const label = getAppDisplayName(appName);
                savedIcon.dataset.app = resolveAppName(appName) || appName;

                const iconImage = savedIcon.querySelector('.icon-image');
                if (iconImage) {
                    iconImage.innerHTML = renderAppIcon(appName, 'desktop', label);
                }

                const iconLabel = savedIcon.querySelector('.icon-label');
                if (iconLabel) {
                    iconLabel.textContent = label;
                }
                return;
            }

            if (staticIcon) return;

            const appIcon = this.createItemIcon(item);
            if (appIcon) {
                container.appendChild(appIcon);
            }
        });

        // Normalize all desktop entities before wiring interactions.
        this.ensureDesktopPositions();

        // Refresh drag handlers after rendering
        this.applyDesktopPositions();
        if (window.dragDropManager) {
            setTimeout(() => window.dragDropManager.refreshIcons(), 100);
        }
    }

    createFolderIcon(folder) {
        const icon = document.createElement('div');
        icon.className = 'icon';
        icon.dataset.id = folder.id;
        icon.dataset.type = 'folder';
        icon.innerHTML = `
            <div class="icon-image">
                <svg viewBox="0 0 48 48" fill="none">
                    <defs>
                        <linearGradient id="folderGrad${folder.id}" x1="0%" y1="0%" x2="100%" y2="100%">
                            <stop offset="0%" style="stop-color:#fbbf24;stop-opacity:1" />
                            <stop offset="100%" style="stop-color:#f59e0b;stop-opacity:1" />
                        </linearGradient>
                    </defs>
                    <path fill="url(#folderGrad${folder.id})" d="M40 12H22l-4-4H8c-2.2 0-4 1.8-4 4v24c0 2.2 1.8 4 4 4h32c2.2 0 4-1.8 4-4V16c0-2.2-1.8-4-4-4z"/>
                    <path fill="#fff" opacity="0.3" d="M40 16H8v20h32V16z"/>
                </svg>
            </div>
            <div class="icon-label">${folder.name}</div>
        `;

        icon.addEventListener('dblclick', () => this.openFolder(folder.id));
        
        return icon;
    }

    openFolder(folderId) {
        const folder = this.folders.find(f => f.id === folderId);
        if (!folder) return;

        const container = document.querySelector('.windows-container');
        if (!container) return;

        const template = document.getElementById('folder-window-template');
        const folderWindow = template.cloneNode(true);
        folderWindow.id = `folder-window-${folderId}`;
        folderWindow.dataset.app = `folder-${folderId}`;
        folderWindow.style.display = 'block';

        const titleSpan = folderWindow.querySelector('.folder-title');
        if (titleSpan) titleSpan.textContent = folder.name;

        const folderContent = folderWindow.querySelector('.folder-content');
        const folderItems = this.items.filter(item => item.location === folderId);

        folderItems.forEach(item => {
            const icon = this.createItemIcon(item);
            if (icon) folderContent.appendChild(icon);
        });

        // Setup folder content as drop target
        if (window.dragDropManager) {
            window.dragDropManager.setupDropTarget(folderContent);
        }

        container.appendChild(folderWindow);

        if (window.windowManagerInstance) {
            window.windowManagerInstance.initWindow(folderWindow);
            window.windowManagerInstance.openWindow(`folder-${folderId}`);
        }
        
        // Make icons in folder draggable
        if (window.dragDropManager) {
            window.dragDropManager.refreshIcons();
        }
    }

    createItemIcon(item) {
        let icon = null;
        
        if (item.type === 'document') {
            // Create document icon
            icon = this.createDocumentIcon(item);
        } else {
            const appName = item.app || item.id;
            // Clone existing app icon from desktop when available, otherwise build it directly.
            icon = document.querySelector(`.desktop-icons .icon[data-app="${resolveAppName(appName)}"]`)?.cloneNode(true);
            if (!icon) {
                icon = document.createElement('div');
                icon.className = 'icon';
                icon.dataset.app = resolveAppName(appName) || appName;
                icon.innerHTML = `
                    <div class="icon-image">${renderAppIcon(appName, 'desktop', getAppDisplayName(appName))}</div>
                    <div class="icon-label">${getAppDisplayName(appName)}</div>
                `;
            }

            icon.dataset.id = item.id;
            icon.addEventListener('dblclick', () => {
                if (window.windowManagerInstance) {
                    window.windowManagerInstance.openWindow(appName);
                }
            });
        }
        
        return icon;
    }

    createFolder(name) {
        const folder = {
            id: 'folder_' + Date.now(),
            name: name || 'New Folder',
            location: 'desktop',
            position: { x: 0, y: 0 },
            created: new Date().toISOString()
        };
        this.folders.push(folder);
        this.saveFolders();
        this.renderDesktop();
        
        if (window.dragDropManager) {
            window.dragDropManager.refreshIcons();
        }
    }

    moveItem(itemId, targetType, targetId) {
        const item = this.items.find(i => (i.app || i.id) === itemId);
        if (!item) return;

        item.location = targetType === 'desktop' ? 'desktop' : targetId;
        this.saveItems();
        this.renderDesktop();

        if (window.dragDropManager) {
            window.dragDropManager.refreshIcons();
        }
    }

    addDocumentToDesktop(documentId, documentTitle) {
        // Check if document already exists on desktop
        const existing = this.items.find(i => i.type === 'document' && i.documentId === documentId);
        if (existing) {
            return; // Already on desktop
        }

        const item = {
            id: 'doc_' + documentId,
            documentId: documentId,
            title: documentTitle,
            type: 'document',
            location: 'desktop',
            position: { x: 0, y: this.items.length },
            created: new Date().toISOString()
        };

        this.items.push(item);
        this.saveItems();
        this.renderDesktop();
        
        // Refresh drag handlers
        if (window.dragDropManager) {
            window.dragDropManager.refreshIcons();
        }
    }

    createDocumentIcon(item) {
        const icon = document.createElement('div');
        icon.className = 'icon';
        icon.dataset.id = item.id;
        icon.dataset.type = 'document';
        icon.dataset.documentId = item.documentId;
        icon.style.cursor = 'pointer';
        
        icon.innerHTML = `
            <div class="icon-image">
                <svg viewBox="0 0 48 48" fill="none">
                    <defs>
                        <linearGradient id="docGrad${item.id}" x1="0%" y1="0%" x2="100%" y2="100%">
                            <stop offset="0%" style="stop-color:#3b82f6;stop-opacity:1" />
                            <stop offset="100%" style="stop-color:#1d4ed8;stop-opacity:1" />
                        </linearGradient>
                    </defs>
                    <path fill="url(#docGrad${item.id})" d="M30 4H10c-2.2 0-4 1.8-4 4v32c0 2.2 1.8 4 4 4h28c2.2 0 4-1.8 4-4V16L30 4z"/>
                    <path fill="#fff" opacity="0.3" d="M30 4v12h12L30 4z"/>
                    <path fill="#fff" opacity="0.6" d="M12 22h24v2H12v-2zm0 6h24v2H12v-2zm0 6h16v2H12v-2z"/>
                </svg>
            </div>
            <div class="icon-label">${item.title}</div>
        `;

        icon.addEventListener('dblclick', () => {
            if (window.documentsManager) {
                window.documentsManager.openDocument(item.documentId);
                if (window.windowManagerInstance) {
                    window.windowManagerInstance.openWindow('documents');
                }
            }
        });

        return icon;
    }

    setupContextMenu() {
        const desktop = document.querySelector('.desktop');
        if (!desktop) return;

        desktop.addEventListener('contextmenu', (e) => {
            const icon = e.target.closest('.icon');
            if (icon) {
                e.preventDefault();
                e.stopPropagation();
                const targetType = icon.dataset.type || 'app';
                const targetId = icon.dataset.id || icon.dataset.app;
                this.showContextMenu(e.clientX, e.clientY, targetType, targetId, icon);
                return;
            }
            
            e.preventDefault();
            this.showContextMenu(e.clientX, e.clientY, 'desktop', null, null);
        });

        document.addEventListener('click', () => this.hideContextMenu());
    }

    showContextMenu(x, y, targetType, targetId = null, targetElement = null) {
        const menu = document.getElementById('context-menu');
        if (!menu) return;

        // Hide all menu items first
        menu.querySelectorAll('.context-menu-item').forEach(item => item.style.display = 'none');

        // Show items based on target type
        if (targetType === 'desktop') {
            // Desktop context menu
            const newFolderItem = menu.querySelector('[data-action="new-folder"]');
            const refreshItem = menu.querySelector('[data-action="refresh"]');
            if (newFolderItem) {
                newFolderItem.style.display = 'flex';
                newFolderItem.onclick = async () => {
                    const name = (await uiPrompt('Enter folder name:', 'New Folder', {
                        title: 'New Folder',
                        submitLabel: 'Create'
                    }))?.trim();
                    if (name) this.createFolder(name);
                    this.hideContextMenu();
                };
            }
            if (refreshItem) {
                refreshItem.style.display = 'flex';
                refreshItem.onclick = () => {
                    this.renderDesktop();
                    this.hideContextMenu();
                };
            }
        } else if (targetType === 'app' || targetType === 'document') {
            // App/Document context menu
            const openItem = menu.querySelector('[data-action="open"]');
            if (openItem) {
                openItem.style.display = 'flex';
                openItem.onclick = () => {
                    if (targetType === 'document' && window.documentsManager) {
                        window.documentsManager.openDocument(targetElement.dataset.documentId);
                        if (window.windowManagerInstance) {
                            window.windowManagerInstance.openWindow('documents');
                        }
                    } else if (targetType === 'app' && window.windowManagerInstance) {
                        window.windowManagerInstance.openWindow(targetId);
                    }
                    this.hideContextMenu();
                };
            }
        } else if (targetType === 'folder') {
            // Folder context menu
            const openItem = menu.querySelector('[data-action="open"]');
            const renameItem = menu.querySelector('[data-action="rename"]');
            const deleteItem = menu.querySelector('[data-action="delete"]');
            
            if (openItem) {
                openItem.style.display = 'flex';
                openItem.onclick = () => {
                    this.openFolder(targetId);
                    this.hideContextMenu();
                };
            }
            if (renameItem) {
                renameItem.style.display = 'flex';
                renameItem.onclick = async () => {
                    const folder = this.folders.find(f => f.id === targetId);
                    if (folder) {
                        const newName = (await uiPrompt('Rename folder:', folder.name, {
                            title: 'Rename Folder',
                            submitLabel: 'Save'
                        }))?.trim();
                        if (newName && newName.trim()) {
                            folder.name = newName.trim();
                            this.saveFolders();
                            this.renderDesktop();
                        }
                    }
                    this.hideContextMenu();
                };
            }
            if (deleteItem) {
                deleteItem.style.display = 'flex';
                deleteItem.onclick = async () => {
                    const confirmed = await uiConfirm('Delete this folder and all its contents?', {
                        title: 'Delete Folder',
                        confirmLabel: 'Delete'
                    });
                    if (confirmed) {
                        this.folders = this.folders.filter(f => f.id !== targetId);
                        this.items = this.items.filter(i => i.location !== targetId);
                        this.saveFolders();
                        this.saveItems();
                        this.renderDesktop();
                    }
                    this.hideContextMenu();
                };
            }
        }

        menu.style.display = 'block';
        menu.style.left = x + 'px';
        menu.style.top = y + 'px';
    }

    hideContextMenu() {
        const menu = document.getElementById('context-menu');
        if (menu) menu.style.display = 'none';
    }

    resetToDefault() {
        scopedStorageRemove('gov_desktop_items');
        scopedStorageRemove('gov_folders');
        scopedStorageRemove('gov_documents');
        this.items = this.loadItems();
        this.folders = this.loadFolders();
        this.renderDesktop();
        if (window.dragDropManager) {
            window.dragDropManager.refreshIcons();
        }
    }

    resetDesktopLayout() {
        scopedStorageRemove('gov_desktop_items');
        scopedStorageRemove('gov_folders');
        this.items = this.loadItems();
        this.folders = this.loadFolders();
        this.renderDesktop();
        if (window.dragDropManager) {
            window.dragDropManager.clearSelection();
            window.dragDropManager.refreshIcons();
        }
    }
}

function renderExternalProgramIcon(icon, programId = '') {
    const normalizedProgramId = resolveAppName(programId);
    if (normalizedProgramId && getIconKey(normalizedProgramId) !== 'default') {
        return renderAppIcon(normalizedProgramId, 'desktop', getAppDisplayName(normalizedProgramId));
    }

    if (!icon) {
        return '<span class="external-program-glyph">&#128187;</span>';
    }

    if (/<[a-z][\s\S]*>/i.test(icon)) {
        return icon;
    }

    if (typeof icon === 'string' && icon.includes('fa')) {
        return `<i class="${icon}"></i>`;
    }

    return icon;
}

async function launchExternalProgram(program, windowManager, playerJob = null) {
    if (!program?.id) return false;

    if (program.url) {
        createExternalProgramWindow(program, windowManager);
        windowManager.openWindow(program.id);
        return true;
    }

    const launchResult = await nuiRequest(`program:${program.id}:open`, {
        programId: program.id,
        resource: program.resource,
        playerJob
    });

    if (!launchResult?.ok) {
        uiNotify(`Failed to launch ${program.label}`, 'error');
        return false;
    }

    if (launchResult.url) {
        const runtimeProgram = { ...program, url: launchResult.url };
        createExternalProgramWindow(runtimeProgram, windowManager);
        windowManager.openWindow(program.id);
        return true;
    }

    return true;
}

function createExternalProgramWindow(program, windowManager) {
    const windowsContainer = document.querySelector('.windows-container');
    if (!windowsContainer || !windowManager || !program?.id || !program?.url) {
        return;
    }

    const existingWindow = document.querySelector(`.window[data-app="${program.id}"]`);
    if (existingWindow) {
        return;
    }

    const windowElement = document.createElement('div');
    windowElement.className = 'window external-program-window';
    windowElement.id = `${program.id}-window`;
    windowElement.dataset.app = program.id;
    windowElement.style.display = 'none';
    windowElement.innerHTML = `
        <div class="window-header">
            <div class="window-title">
                <div class="window-icon">${renderExternalProgramIcon(program.icon, program.id)}</div>
                <span>${program.label}</span>
            </div>
            <div class="window-controls">
                <button class="window-btn minimize">−</button>
                <button class="window-btn maximize">□</button>
                <button class="window-btn close">×</button>
            </div>
        </div>
        <div class="window-content" style="padding: 0; overflow: hidden; background: #fff;">
            <iframe
                class="external-program-frame"
                src="${program.url}"
                title="${program.label}"
                loading="lazy"
                allow="clipboard-read; clipboard-write"
                style="width: 100%; height: 100%; border: 0; background: #fff;"
            ></iframe>
        </div>
    `;

    windowsContainer.appendChild(windowElement);
    windowManager.initWindow(windowElement);

    if (program.window && typeof program.window === 'object') {
        if (program.window.width) {
            windowElement.style.width = `${program.window.width}px`;
        }
        if (program.window.height) {
            windowElement.style.height = `${program.window.height}px`;
        }
    }
}

function createExternalProgramStartTile(program, windowManager) {
    const appsContainer = document.querySelector('.start-menu-apps');
    if (!appsContainer || !program?.id) {
        return;
    }

    if (appsContainer.querySelector(`.start-app-tile[data-app="${program.id}"]`)) {
        return;
    }

    const tile = document.createElement('div');
    tile.className = 'start-app-tile external-program';
    tile.dataset.app = program.id;
    tile.innerHTML = `
        <div class="start-app-icon">${renderExternalProgramIcon(program.icon, program.id)}</div>
        <div class="start-app-name">${program.label}</div>
    `;

    tile.addEventListener('click', async () => {
        await launchExternalProgram(program, windowManager);
    });

    appsContainer.appendChild(tile);
}

function clearExternalPrograms(windowManager) {
    document.querySelectorAll('.desktop-icons .icon.external-program').forEach((el) => el.remove());
    document.querySelectorAll('.start-menu-apps .start-app-tile.external-program').forEach((el) => el.remove());

    document.querySelectorAll('.window.external-program-window').forEach((win) => {
        const appName = win.dataset.app;
        if (windowManager && windowManager.windows && appName) {
            windowManager.windows.delete(appName);
            if (windowManager.activeWindow === appName) {
                windowManager.activeWindow = null;
            }
        }
        win.remove();
    });

    if (windowManager && typeof windowManager.updateTaskbar === 'function') {
        windowManager.updateTaskbar();
    }
}

// Load and display external programs from other resources
async function loadExternalPrograms(windowManager, profile = 'default') {
    console.log('Loading external programs from other resources...');
    
    try {

    if (typeof window.StoreManager !== 'function') {
    window.StoreManager = class StoreManager {
        constructor(settingsManager) {
            this.settingsManager = settingsManager;
            this.container = document.getElementById('store-content');
            this.catalog = this.buildCatalog();
            this.currentTab = 'home';
            this.currentDetailId = null;
            this.searchQuery = '';
            this.installed = this.loadInstalled();
            this.player = null;
            this.init();
        }

        buildCatalog() {
            return [
                {
                    id: 'business-manager-suite',
                    label: 'Business Manager',
                    category: 'apps',
                    appId: 'business-manager',
                    publisher: 'PF Industries',
                    price: 'Free',
                    badge: 'Business',
                    companyOnly: true,
                    requiredJobs: ['government', 'mayor'],
                    short: 'Manage city and company operations',
                    description: 'Access business analytics, workforce controls, and compliance operations.',
                    hero: 'linear-gradient(120deg,#122849,#2f5f98)',
                    screenshots: ['assets/wallpaper_dark.png', 'assets/wallpaper_light.png', 'assets/wallpaper.jpg']
                },
                {
                    id: 'order-supplies-pro',
                    label: 'Order Supplies',
                    category: 'apps',
                    appId: 'order-supplies',
                    publisher: 'San Andreas Logistics',
                    price: 'Free',
                    badge: 'Operations',
                    companyOnly: true,
                    short: 'Business inventory ordering',
                    description: 'Order and track supplies for approved businesses and departments.',
                    hero: 'linear-gradient(120deg,#3e2a10,#b36b00)',
                    screenshots: ['assets/wallpaper.jpg', 'assets/wallpaper_dark.png', 'assets/wallpaper_light.png']
                },
                {
                    id: 'job-board-center',
                    label: 'Job Board',
                    category: 'apps',
                    appId: 'job-board',
                    publisher: 'Los Santos Workforce',
                    price: 'Free',
                    badge: 'Productivity',
                    short: 'Post and review job opportunities',
                    description: 'Publish positions, review applicants, and manage employment listings.',
                    hero: 'linear-gradient(120deg,#0d3240,#0ea5b7)',
                    screenshots: ['assets/wallpaper_light.png', 'assets/wallpaper.jpg', 'assets/wallpaper_dark.png']
                },
                { id: 'minesweeper-classic', label: 'Minesweeper', category: 'games', appId: 'minesweeper', publisher: 'PF Play', price: 'Free', badge: 'Classic', short: 'Flag every mine and clear the field', description: 'Classic Minesweeper with multiple difficulties, timer, and best-time leaderboard.', hero: 'linear-gradient(120deg,#1f3d63,#5a88d7)', screenshots: ['assets/wallpaper_dark.png','assets/wallpaper_light.png','assets/wallpaper.jpg'] },
                { id: 'tetris-classic', label: 'Tetris', category: 'games', appId: 'tetris', publisher: 'PF Play', price: 'Free', badge: 'Arcade', short: 'Stack pieces and clear lines', description: 'Modernized falling-block classic with queue, hold, score, and leaderboard.', hero: 'linear-gradient(120deg,#35145e,#8b5cf6)', screenshots: ['assets/wallpaper_dark.png','assets/wallpaper_light.png','assets/wallpaper.jpg'] },
                { id: 'snake-classic', label: 'Snake', category: 'games', appId: 'snake', publisher: 'PF Play', price: 'Free', badge: 'Arcade', short: 'Grow longer and survive', description: 'Responsive Snake with speed scaling, wall option, and score leaderboard.', hero: 'linear-gradient(120deg,#163d2a,#22c55e)', screenshots: ['assets/wallpaper_dark.png','assets/wallpaper_light.png','assets/wallpaper.jpg'] },
                { id: 'pong-classic', label: 'Pong', category: 'games', appId: 'pong', publisher: 'PF Play', price: 'Free', badge: 'Arcade', short: 'Classic paddle duel', description: 'Single-player Pong with AI difficulty, score tracking, and leaderboard.', hero: 'linear-gradient(120deg,#14233e,#38bdf8)', screenshots: ['assets/wallpaper_dark.png','assets/wallpaper_light.png','assets/wallpaper.jpg'] },
                { id: 'flappy-bird-classic', label: 'Flappy Bird', category: 'games', appId: 'flappy', publisher: 'PF Play', price: 'Free', badge: 'Arcade', short: 'Tap through the pipes', description: 'Pipe-dodging challenge with best score leaderboard and polished UI.', hero: 'linear-gradient(120deg,#275a15,#84cc16)', screenshots: ['assets/wallpaper_dark.png','assets/wallpaper_light.png','assets/wallpaper.jpg'] },
                {
                    id: 'civic-assistant-ai',
                    label: 'Civic Assistant AI',
                    category: 'ai',
                    publisher: 'San Andreas Digital',
                    price: 'Free',
                    badge: 'AI',
                    short: 'Summaries, drafting, and workflow copilots',
                    description: 'Smart assistant for internal reports, legal drafting, and admin workflows.',
                    hero: 'linear-gradient(120deg,#1d245f,#4f5ce0)',
                    screenshots: ['assets/wallpaper_dark.png', 'assets/wallpaper.jpg', 'assets/wallpaper_light.png']
                },
                {
                    id: 'vision-caption-ai',
                    label: 'Vision Caption AI',
                    category: 'ai',
                    publisher: 'NView Systems',
                    price: '$2.99',
                    badge: 'AI',
                    short: 'Analyze and caption gallery images',
                    description: 'Build captions and searchable tags from imported camera and phone photos.',
                    hero: 'linear-gradient(120deg,#11314e,#2384cf)',
                    screenshots: ['assets/wallpaper_light.png', 'assets/wallpaper_dark.png', 'assets/wallpaper.jpg']
                }
            ];
        }

        init() {
            if (!this.container) return;
            this.bindGlobalHandlers();
            this.syncInstalledAppVisibility();
            this.render();
        }

        async reloadForScope() {
            this.installed = this.loadInstalled();
            this.player = null;
            this.syncInstalledAppVisibility();
            this.render();
        }

        loadInstalled() {
            try {
                return new Set(JSON.parse(scopedStorageGet('store_installed_items', '[]') || '[]'));
            } catch {
                return new Set();
            }
        }

        saveInstalled() {
            scopedStorageSet('store_installed_items', JSON.stringify(Array.from(this.installed)));
        }

        async ensurePlayer() {
            if (this.player) return this.player;
            const response = await nuiRequest('pc:getPlayerData', {});
            this.player = response?.ok ? (response.data || {}) : {};
            return this.player;
        }

        isCompanyComputer() {
            const fromSettings = !!this.settingsManager?.settings?.businessAccount;
            return fromSettings || CURRENT_COMPUTER_BASE_SCOPE.includes('profile:mayor');
        }

        async getRestriction(item) {
            const player = await this.ensurePlayer();
            if (item.companyOnly && !this.isCompanyComputer()) {
                return 'Requires a company/government computer profile.';
            }
            if (Array.isArray(item.requiredJobs) && item.requiredJobs.length) {
                const job = String(player?.job || '').toLowerCase();
                const allowed = item.requiredJobs.map((entry) => String(entry).toLowerCase());
                if (!allowed.includes(job)) {
                    return `Restricted to jobs: ${item.requiredJobs.join(', ')}`;
                }
            }
            return '';
        }

        bindGlobalHandlers() {
            this.container.addEventListener('click', async (event) => {
                const tabBtn = event.target.closest('[data-store-rail]');
                if (tabBtn) {
                    this.currentTab = tabBtn.dataset.storeRail;
                    this.currentDetailId = null;
                    this.render();
                    return;
                }

                const openBtn = event.target.closest('[data-store-open]');
                if (openBtn) {
                    this.currentDetailId = openBtn.dataset.storeOpen;
                    this.render();
                    return;
                }

                const backBtn = event.target.closest('#store-back-home');
                if (backBtn) {
                    this.currentDetailId = null;
                    this.render();
                    return;
                }

                const installBtn = event.target.closest('[data-store-install]');
                if (installBtn) {
                    const item = this.catalog.find((entry) => entry.id === installBtn.dataset.storeInstall);
                    if (!item) return;
                    const restriction = await this.getRestriction(item);
                    if (restriction) {
                        uiNotify(restriction, 'warning');
                        return;
                    }
                    this.installed.add(item.id);
                    this.saveInstalled();
                    this.syncInstalledAppVisibility();
                    uiNotify(`${item.label} installed.`, 'success');
                    this.render();
                    return;
                }

                const launchBtn = event.target.closest('[data-store-launch]');
                if (launchBtn) {
                    const appId = launchBtn.dataset.storeLaunch;
                    if (appId && window.windowManagerInstance) {
                        window.windowManagerInstance.openWindow(appId);
                    }
                    return;
                }

                const clearBtn = event.target.closest('#store-clear-search');
                if (clearBtn) {
                    this.searchQuery = '';
                    this.render();
                }
            });

            this.container.addEventListener('input', (event) => {
                if (event.target && event.target.id === 'store-search-input') {
                    this.searchQuery = String(event.target.value || '');
                    this.currentDetailId = null;
                    this.render();
                }
            });
        }

        syncInstalledAppVisibility() {
            let desktopItemsChanged = false;

            this.catalog
                .filter((item) => item.appId)
                .forEach((item) => {
                    const installed = this.installed.has(item.id);
                    const appId = resolveAppName(item.appId);

                    if (window.desktopManager) {
                        const existingIndex = window.desktopManager.items.findIndex((entry) => resolveAppName(entry.app || entry.id) === appId);
                        if (installed && existingIndex < 0) {
                            window.desktopManager.ensureAppItem(appId);
                            desktopItemsChanged = true;
                        }
                        if (!installed && existingIndex >= 0) {
                            window.desktopManager.items.splice(existingIndex, 1);
                            desktopItemsChanged = true;
                        }
                    }

                    document.querySelectorAll(`.icon.icon-downloadable[data-app="${item.appId}"]`).forEach((icon) => {
                        icon.style.display = installed ? 'flex' : 'none';
                    });
                    document.querySelectorAll(`.start-app-tile[data-app="${item.appId}"]`).forEach((tile) => {
                        tile.style.display = installed ? '' : 'none';
                    });
                });

            if (desktopItemsChanged && window.desktopManager) {
                window.desktopManager.saveItems();
                window.desktopManager.renderDesktop();
            }

            if (window.dragDropManager && typeof window.dragDropManager.refreshIcons === 'function') {
                window.dragDropManager.refreshIcons();
            }
        }

        esc(text) {
            return String(text || '')
                .replace(/&/g, '&amp;')
                .replace(/</g, '&lt;')
                .replace(/>/g, '&gt;')
                .replace(/"/g, '&quot;')
                .replace(/'/g, '&#39;');
        }

        getVisibleItems(tab) {
            let items = [];
            if (tab === 'apps') items = this.catalog.filter((item) => item.category === 'apps');
            else if (tab === 'gaming') items = this.catalog.filter((item) => item.category === 'games');
            else if (tab === 'ai') items = this.catalog.filter((item) => item.category === 'ai');
            else if (tab === 'library') items = this.catalog.filter((item) => this.installed.has(item.id));
            else items = [...this.catalog];

            const query = this.searchQuery.trim().toLowerCase();
            if (!query) return items;

            return items.filter((item) => {
                const haystack = [item.label, item.short, item.description, item.publisher, item.category]
                    .map((entry) => String(entry || '').toLowerCase())
                    .join(' ');
                return haystack.includes(query);
            });
        }

        cardMarkup(item, options = {}) {
            const installed = this.installed.has(item.id);
            const compact = !!options.compact;
            const restriction = item.companyOnly || (Array.isArray(item.requiredJobs) && item.requiredJobs.length);
            return `
                <article class="store-app-card ${compact ? 'store-app-card-compact' : ''}" data-store-open="${this.esc(item.id)}">
                    <div class="store-app-thumb" style="background:${item.hero}"></div>
                    <div class="store-app-meta">
                        <div class="store-app-meta-top">
                            <strong>${this.esc(item.label)}</strong>
                            <span class="store-price-pill">${this.esc(item.price || 'Free')}</span>
                        </div>
                        <small>${this.esc(item.short)}</small>
                        <div class="store-meta-row">
                            <span>${this.esc(item.publisher || 'Publisher')}</span>
                            ${item.badge ? `<span class="store-badge-pill">${this.esc(item.badge)}</span>` : ''}
                            ${installed ? '<span class="store-install-state">Installed</span>' : ''}
                            ${restriction ? '<span class="store-restricted-state">Restricted</span>' : ''}
                        </div>
                    </div>
                </article>
            `;
        }

        renderList(items, options = {}) {
            return items.length
                ? `<div class="store-card-grid ${options.compact ? 'store-card-grid-compact' : ''}">${items.map((item) => this.cardMarkup(item, options)).join('')}</div>`
                : '<div class="settings-empty-copy">No programs available in this category.</div>';
        }

        renderHorizontalSection(title, items) {
            return `
                <section class="store-section">
                    <div class="store-section-head">
                        <h3>${this.esc(title)}</h3>
                    </div>
                    <div class="store-h-scroll">
                        ${items.map((item) => this.cardMarkup(item, { compact: true })).join('')}
                    </div>
                </section>
            `;
        }

        renderFeaturedHome(items) {
            const featured = items.slice(0, 4);
            const lead = featured[0];
            const side = featured.slice(1, 4);

            if (!lead) return '<div class="settings-empty-copy">No featured items currently available.</div>';

            return `
                <section class="store-featured-grid">
                    <article class="store-featured-hero" data-store-open="${this.esc(lead.id)}" style="background:${lead.hero}">
                        <div class="store-featured-overlay"></div>
                        <div class="store-featured-content">
                            ${lead.badge ? `<span class="store-featured-tag">${this.esc(lead.badge)}</span>` : ''}
                            <h2>${this.esc(lead.label)}</h2>
                            <p>${this.esc(lead.short)}</p>
                            <button class="btn-secondary" type="button" data-store-open="${this.esc(lead.id)}">See details</button>
                        </div>
                    </article>
                    <aside class="store-featured-side">
                        ${side.map((entry) => `
                            <article class="store-featured-small" data-store-open="${this.esc(entry.id)}" style="background:${entry.hero}">
                                <div class="store-featured-overlay"></div>
                                <div class="store-featured-small-content">
                                    <strong>${this.esc(entry.label)}</strong>
                                    <small>${this.esc(entry.short)}</small>
                                </div>
                            </article>
                        `).join('')}
                    </aside>
                </section>
            `;
        }

        renderDetail(item) {
            const installed = this.installed.has(item.id);
            const canLaunch = installed && item.appId;
            const discover = this.catalog.filter((entry) => entry.id !== item.id).slice(0, 6);
            return `
                <div class="store-app-page">
                    <div class="store-app-hero" style="background:${item.hero}">
                        <button class="btn-secondary" id="store-back-home" type="button">Back</button>
                        <div class="store-app-title-wrap">
                            <h2>${this.esc(item.label)}</h2>
                            <p>${this.esc(item.description)}</p>
                            <div class="store-app-meta-line">
                                <span>${this.esc(item.publisher || 'Publisher')}</span>
                                <span>${item.category === 'games' ? 'Gaming' : item.category === 'ai' ? 'AI Hub' : 'Apps'}</span>
                                <span>${this.esc(item.price || 'Free')}</span>
                            </div>
                            <div class="store-app-actions">
                                ${installed
                                    ? '<button class="btn-primary" type="button" disabled>Installed</button>'
                                    : `<button class="btn-primary" type="button" data-store-install="${item.id}">Get</button>`}
                                ${canLaunch ? `<button class="btn-secondary" type="button" data-store-launch="${item.appId}">Launch</button>` : ''}
                            </div>
                        </div>
                    </div>
                    <div class="store-app-layout">
                        <section>
                            <div class="settings-section-label">Screenshots</div>
                            <div class="store-shots-grid">${item.screenshots.map((shot) => `<div class="store-shot-card"><img src="${shot}" alt="${this.esc(item.label)} screenshot"></div>`).join('')}</div>
                            <div class="settings-section-label" style="margin-top:14px">Description</div>
                            <section class="settings-card settings-card-wide"><p>${this.esc(item.description)}</p></section>
                        </section>
                        <aside>
                            <div class="settings-section-label">Discover more</div>
                            <section class="settings-card settings-card-wide store-discover-list">
                                ${discover.map((entry) => `<button class="store-discover-item" type="button" data-store-open="${this.esc(entry.id)}"><span>${this.esc(entry.label)}</span><small>${entry.category === 'games' ? 'Gaming' : entry.category === 'ai' ? 'AI Hub' : 'Apps'}</small></button>`).join('')}
                            </section>
                        </aside>
                    </div>
                </div>
            `;
        }

        renderContent() {
            const apps = this.getVisibleItems('apps');
            const games = this.getVisibleItems('gaming');
            const ai = this.getVisibleItems('ai');
            const library = this.getVisibleItems('library');

            if (this.currentTab === 'apps') {
                return `<section class="store-section"><div class="store-section-head"><h3>Apps</h3></div>${this.renderList(apps)}</section>`;
            }
            if (this.currentTab === 'gaming') {
                return `<section class="store-section"><div class="store-section-head"><h3>Gaming</h3></div>${this.renderList(games)}</section>`;
            }
            if (this.currentTab === 'ai') {
                return `<section class="store-section"><div class="store-section-head"><h3>AI Hub</h3></div>${this.renderList(ai)}</section>`;
            }
            if (this.currentTab === 'library') {
                return `<section class="store-section"><div class="store-section-head"><h3>Library</h3></div>${this.renderList(library)}</section>`;
            }

            const homePool = this.getVisibleItems('home');
            return `
                ${this.renderFeaturedHome(homePool)}
                ${this.renderHorizontalSection('Trending games', games.slice(0, 8))}
                ${this.renderHorizontalSection('Trending apps', apps.slice(0, 8))}
                ${this.renderHorizontalSection('Recently added', ai.slice(0, 4).concat(games.slice(0,4)))}
            `;
        }

        renderChrome(body) {
            const navMain = [
                { key: 'home', icon: 'fa-house', label: 'Home' },
                { key: 'apps', icon: 'fa-table-cells-large', label: 'Apps' },
                { key: 'gaming', icon: 'fa-gamepad', label: 'Gaming' },
                { key: 'ai', icon: 'fa-sparkles', label: 'AI Hub' }
            ];
            const navBottom = [
                { key: 'home', icon: 'fa-bolt', label: "What's New" },
                { key: 'library', icon: 'fa-download', label: 'Downloads' },
                { key: 'library', icon: 'fa-books', label: 'Library' }
            ];

            return `
                <div class="store-shell">
                    <aside class="store-rail" aria-label="Store navigation">
                        <div class="store-rail-main">
                        ${navMain.map((entry) => `
                            <button class="store-rail-btn ${this.currentTab === entry.key ? 'active' : ''}" type="button" data-store-rail="${entry.key}" title="${entry.label}" aria-label="${entry.label}">
                                <i class="fa-solid ${entry.icon}"></i>
                            </button>
                        `).join('')}
                        </div>
                        <div class="store-rail-bottom">
                        ${navBottom.map((entry) => `
                            <button class="store-rail-btn ${this.currentTab === entry.key ? 'active' : ''}" type="button" data-store-rail="${entry.key}" title="${entry.label}" aria-label="${entry.label}">
                                <i class="fa-solid ${entry.icon}"></i>
                            </button>
                        `).join('')}
                        </div>
                    </aside>
                    <div class="store-main-shell">
                        <header class="store-topbar">
                            <div class="store-search-wrap">
                                <i class="fa-solid fa-magnifying-glass"></i>
                                <input id="store-search-input" type="text" value="${this.esc(this.searchQuery)}" placeholder="Search apps, games, and more">
                                ${this.searchQuery ? '<button id="store-clear-search" class="store-search-clear" type="button" aria-label="Clear search"><i class="fa-solid fa-xmark"></i></button>' : ''}
                            </div>
                            <button class="store-profile-avatar" type="button" title="Profile" aria-label="Profile">DB</button>
                        </header>
                        <main class="store-main-content">
                            ${body}
                        </main>
                    </div>
                </div>
            `;
        }

        render() {
            if (!this.container) return;

            if (this.currentDetailId) {
                const item = this.catalog.find((entry) => entry.id === this.currentDetailId);
                if (item) {
                    this.container.innerHTML = this.renderChrome(this.renderDetail(item));
                    return;
                }
            }

            this.container.innerHTML = this.renderChrome(this.renderContent());
        }
    };
    }

        const response = await nuiRequest('pc:getExternalPrograms', { profile });
        
        if (!response.ok || !response.data || response.data.length === 0) {
            console.log('No external programs found');
            return;
        }
        
        const programs = response.data;
        scopedStorageSet('downloaded_apps', JSON.stringify(programs.map((program) => program.id)));
        console.log(`Found ${programs.length} external program(s) for profile ${profile}:`, programs);
        
        // Get player's current job
        const playerDataResponse = await nuiRequest('pc:getPlayerData', {});
        const playerJob = playerDataResponse.ok && playerDataResponse.data ? playerDataResponse.data.job : null;
        
        // Add programs to desktop
        const desktop = document.querySelector('.desktop-icons');
        if (!desktop) {
            console.error('Desktop icons container not found');
            return;
        }
        
        programs.forEach(program => {
            // Check job restrictions
            if (program.jobRestricted && program.allowedJobs) {
                if (!playerJob || !program.allowedJobs.includes(playerJob)) {
                    console.log(`Skipping ${program.label} - job restricted (requires: ${program.allowedJobs.join(', ')})`);
                    return;
                }
            }
            
            // Create desktop icon
            const icon = document.createElement('div');
            icon.className = 'icon external-program';
            icon.dataset.app = program.id;
            icon.dataset.resource = program.resource;
            
            icon.innerHTML = `
                <div class="icon-image">${renderExternalProgramIcon(program.icon, program.id)}</div>
                <div class="icon-label">${program.label}</div>
            `;

            if (program.url) {
                createExternalProgramWindow(program, windowManager);
            }

            createExternalProgramStartTile(program, windowManager);
            
            // Add click handler for external programs
            icon.addEventListener('dblclick', async (e) => {
                e.preventDefault();
                e.stopPropagation();
                
                console.log(`Launching external program: ${program.label} (${program.id})`);
                await launchExternalProgram(program, windowManager, playerJob);
            });
            
            desktop.appendChild(icon);
            console.log(`Added external program to desktop: ${program.label}`);
        });

        if (window.desktopManager) {
            window.desktopManager.applyDesktopPositions();
        }
        if (window.dragDropManager) {
            window.dragDropManager.refreshIcons();
        }
        
    } catch (error) {
        console.error('Error loading external programs:', error);
    }
}



/* Windows 11 settings override */
(function(){
  const WP = SettingsManager.prototype;

  WP.ensureWindowsDefaults = function() {
    const defaults = {
            brightness: Number(scopedSettingGet('brightness', localStorage.getItem('brightness') || 100)),
            firewallEnabled: scopedSettingGet('firewallEnabled', localStorage.getItem('firewallEnabled') !== 'false' ? 'true' : 'false') !== 'false',
            firewallLevel: scopedSettingGet('firewallLevel', localStorage.getItem('firewallLevel') || 'standard'),
            businessAccount: scopedSettingGet('businessAccount', localStorage.getItem('businessAccount') === 'true' ? 'true' : 'false') === 'true',
            ownerName: scopedSettingGet('ownerName', localStorage.getItem('ownerName') || ''),
            accountUsers: scopedSettingGet('accountUsers', localStorage.getItem('accountUsers') || '[]'),
            fontFamily: scopedSettingGet('fontFamily', localStorage.getItem('fontFamily') || 'Segoe UI'),
            lockscreenWidgets: scopedSettingGet('lockscreenWidgets', localStorage.getItem('lockscreenWidgets') !== 'false' ? 'true' : 'false') !== 'false',
            vpnEnabled: scopedSettingGet('vpnEnabled', localStorage.getItem('vpnEnabled') === 'true' ? 'true' : 'false') === 'true',
            vpnDevice: scopedSettingGet('vpnDevice', localStorage.getItem('vpnDevice') || 'No VPN device detected'),
      themeMode: this.settings.themeMode || 'dark',
            themePreset: scopedSettingGet('themePreset', localStorage.getItem('themePreset') || 'default'),
            taskbarAlignment: scopedSettingGet('taskbarAlignment', localStorage.getItem('taskbarAlignment') || 'center'),
            lockscreenType: scopedSettingGet('lockscreenType', localStorage.getItem('lockscreenType') || 'pin'),
            securityLockdownThreshold: Number(scopedStorageGet('securityLockdownThreshold', localStorage.getItem('securityLockdownThreshold') || 3)),
            languageCode: scopedSettingGet('languageCode', localStorage.getItem('languageCode') || 'en-US')
    };
    Object.entries(defaults).forEach(([k,v]) => {
      if (this.settings[k] === undefined || this.settings[k] === null || this.settings[k] === '') this.settings[k] = v;
    });
  };

  WP.init = function() {
    this.ensureWindowsDefaults();
    const navItems = document.querySelectorAll('.settings-nav-item');
    navItems.forEach(item => {
      item.addEventListener('click', () => {
        navItems.forEach(nav => nav.classList.remove('active'));
        item.classList.add('active');
        const section = item.textContent.trim();
        this.loadSettingsSection(section);
      });
    });
    this.bindGlobalSearch();
  };

  WP.renderShell = function(content, path = []) {
    const crumbs = path.map((part, idx) => {
      const isLast = idx === path.length - 1;
      return `<button type="button" class="settings-crumb ${isLast ? 'is-current' : ''}" data-settings-crumb="${part.replace(/"/g,'&quot;')}">${part}</button>`;
    }).join('<span class="settings-crumb-sep">›</span>');
    return `
      <div class="settings-global-search" role="search">
        <i class="fa-solid fa-magnifying-glass"></i>
        <input type="text" class="settings-global-search-input" placeholder="Find a setting">
      </div>
      ${path.length ? `<div class="settings-breadcrumbs">${crumbs}</div>` : ''}
      ${content}`;
  };

  WP.getPlayerIdentity = function() {
    const playerName = document.querySelector('[data-player-name]')?.textContent?.trim() || this.settings.ownerName || 'Player';
    const subtitle = document.querySelector('[data-player-subtitle]')?.textContent?.trim() || 'Administrator';
    return { playerName, subtitle };
  };

  WP.renderSectionRow = function(label, desc, nav) {
    return `<button class="settings-link-row windows-link-row" type="button" data-settings-nav="${nav}"><span><strong>${label}</strong><small>${desc}</small></span><i class="fa-solid fa-chevron-right"></i></button>`;
  };

  WP.renderHomeSection = function() {
    const { playerName, subtitle } = this.getPlayerIdentity();
        const wallpaper = scopedStorageGet('customWallpaper', localStorage.getItem('customWallpaper') || 'assets/wallpaper_dark.png');
        const weatherLabel = scopedStorageGet('currentWeather', localStorage.getItem('currentWeather') || '--');
        const weatherTemp = scopedStorageGet('weatherTemp', localStorage.getItem('weatherTemp') || '--°');
    return this.renderShell(`
      <section class="settings-page-block windows-home-shell" data-settings-search="home display personalization lockscreen time language privacy firewall weather accounts">
        <div class="settings-page-heading windows-main-title"><h2>Home</h2></div>
        <div class="settings-home-topline">
          <section class="settings-home-identity-card">
            <div class="settings-computer-hero-thumb windows-thumb" style="background-image:url('${wallpaper}')"></div>
            <div class="settings-computer-hero-info">
              <div class="settings-computer-hero-name">${this.settings.computerName}</div>
              <div class="settings-computer-hero-id">${this.settings.computerID || 'MS-??????'}</div>
              <button class="settings-computer-rename-btn" id="open-rename-computer">Rename</button>
            </div>
          </section>
          <div class="windows-chip-row">
            <div class="windows-status-chip"><i class="fa-solid fa-network-wired"></i><div><strong>Ethernet</strong><span>Connected</span></div></div>
            <div class="windows-status-chip weather-chip"><i class="fa-solid fa-cloud-sun"></i><div><strong>Weather</strong><span>${weatherLabel}</span></div></div>
          </div>
        </div>
        <div class="settings-computer-rename-form" id="rename-computer-form" style="display:none">
          <input type="text" class="settings-input" id="computer-name-input" value="${this.settings.computerName}" placeholder="Computer name" maxlength="32">
          <button class="btn-primary" type="button" id="save-computer-name">Save</button>
          <button class="btn-secondary" type="button" id="cancel-rename-computer">Cancel</button>
        </div>
        <div class="settings-home-grid windows-home-grid">
          <section class="settings-card settings-card-wide">
            <div class="settings-card-header"><div><h3>Recommended settings</h3><p>Recent and commonly used settings</p></div></div>
            <div class="settings-quick-links settings-link-grid">
              ${this.renderSectionRow('Display', 'Brightness, animations, icon size', 'System > Display')}
              ${this.renderSectionRow('Date & time', 'Real or in-game time, formats', 'Time & language > Date & time')}
              ${this.renderSectionRow('Lock screen', 'Image, widgets, sign-in behavior', 'Personalization > Lock screen')}
            </div>
          </section>
          <section class="settings-card">
            <div class="settings-card-header"><div><h3>Personalize your device</h3><p>Neatly organized and responsive like Windows 11.</p></div></div>
            <div class="windows-theme-strip">
              ${this.getWallpaperPresets().map((preset)=>`<button type="button" class="appearance-preset-card ${this.settings.wallpaperPreset===preset.key?'active':''}" data-wallpaper-preset="${preset.key}"><img src="${preset.src}" alt="${preset.label}"></button>`).join('')}
            </div>
            <div class="setting-group compact"><label>Color mode</label><select class="settings-select" id="theme-select"><option value="dark" ${this.settings.themeMode==='dark'?'selected':''}>Dark</option><option value="light" ${this.settings.themeMode==='light'?'selected':''}>Light</option></select></div>
          </section>
          <section class="settings-card settings-card-wide">
            <div class="settings-card-header"><div><h3>Weather</h3><p>Widget visible on the desktop shell</p></div></div>
            <div class="settings-stat-list">
                            <div class="settings-stat-item"><span>Current</span><strong>${weatherLabel || 'Weather'}</strong></div>
                            <div class="settings-stat-item"><span>Temperature</span><strong>${weatherTemp}</strong></div>
              <div class="settings-stat-item"><span>Clock mode</span><strong>${this.settings.clockSource === 'ingame' ? 'In-game' : 'Real'}</strong></div>
            </div>
          </section>
        </div>
      </section>`, ['Home']);
  };

  WP.renderSystemSection = function() {
    return this.renderShell(`
      <section class="settings-page-block" data-settings-search="system display sound brightness desktop icons">
        <div class="settings-page-heading windows-main-title"><h2>System</h2></div>
        <div class="settings-quick-links windows-stack-list">
          ${this.renderSectionRow('Display', 'Monitors, brightness, night light, display profile', 'System > Display')}
          ${this.renderSectionRow('Sound', 'Volume levels, output, input, sound devices', 'System > Sound')}
        </div>
      </section>`, ['System']);
  };

  WP.renderSystemDisplaySection = function() {
    return this.renderShell(`
      <section class="settings-page-block" data-settings-search="display brightness animations icon size">
        <div class="settings-page-heading windows-main-title"><h2>Display</h2></div>
        <section class="settings-card settings-card-wide">
          <div class="setting-group"><label>Brightness</label><input class="settings-range" type="range" min="20" max="100" value="${this.settings.brightness}" id="brightness-range"><div class="settings-range-meta"><span>Dark</span><strong id="brightness-value">${this.settings.brightness}%</strong><span>Bright</span></div></div>
          <label class="settings-toggle-row"><span><strong>Animations</strong><small>Show animations in Windows</small></span><input type="checkbox" id="animations" ${this.settings.animations?'checked':''}></label>
          <div class="setting-group"><label>Desktop icon size</label><select class="settings-select" id="desktop-icon-scale"><option value="small" ${this.settings.desktopIconScale==='small'?'selected':''}>Small</option><option value="medium" ${this.settings.desktopIconScale==='medium'?'selected':''}>Medium</option><option value="large" ${this.settings.desktopIconScale==='large'?'selected':''}>Large</option></select></div>
          <button class="btn-primary" id="save-system-display" type="button">Apply</button>
        </section>
      </section>`, ['System','Display']);
  };

  WP.renderSystemSoundSection = function() {
    return this.renderShell(`
      <section class="settings-page-block" data-settings-search="sound volume notifications audio">
        <div class="settings-page-heading windows-main-title"><h2>Sound</h2></div>
        <section class="settings-card settings-card-wide">
          <label class="settings-toggle-row"><span><strong>Sound effects</strong><small>Play notification and interface sounds</small></span><input type="checkbox" id="sound-effects" ${this.settings.soundEffects?'checked':''}></label>
          <label class="settings-toggle-row"><span><strong>Notification sounds</strong><small>Play a sound when a notification arrives</small></span><input type="checkbox" id="notification-sound" ${this.settings.notificationSound?'checked':''}></label>
          <button class="btn-primary" id="save-system-sound" type="button">Apply</button>
        </section>
      </section>`, ['System','Sound']);
  };

  WP.renderBluetoothSection = function() {
    return this.renderShell(`
      <section class="settings-page-block"><div class="settings-page-heading windows-main-title"><h2>Bluetooth & devices</h2></div><div class="settings-quick-links windows-stack-list">${this.renderSectionRow('Devices', 'Nearby phones and connected accessories', 'Bluetooth & devices > Devices')}</div></section>`, ['Bluetooth & devices']);
  };

    WP.renderBluetoothDevicesSection = function() {
        let gallery = [];
        try {
            gallery = JSON.parse(scopedStorageGet('devices_phone_gallery_cache', '[]') || '[]');
        } catch (_error) {
            gallery = [];
        }

        const galleryCards = gallery.length
            ? gallery.map((img, idx) => `
                    <div class="store-shot-card">
                        <img src="${String(img.url || '').replace(/"/g, '&quot;')}" alt="Phone image ${idx + 1}" loading="lazy">
                        <button class="btn-secondary download-phone-image" type="button" data-image-url="${String(img.url || '').replace(/"/g, '&quot;')}" data-image-name="${String(img.name || `phone-image-${idx + 1}`).replace(/"/g, '&quot;')}">Download</button>
                    </div>
                `).join('')
            : '<div class="settings-empty-copy">No phone images synced yet.</div>';

    return this.renderShell(`
      <section class="settings-page-block">
        <div class="settings-page-heading windows-main-title"><h2>Devices</h2></div>
                <section class="settings-card settings-card-wide">
                    <div class="settings-card-toolbar">
                        <strong>Connected phone</strong>
                        <div class="settings-inline">
                            <button class="btn-primary" type="button" id="search-nearby-phones">Sync from phone</button>
                            <button class="btn-secondary" type="button" id="download-all-phone-images" ${gallery.length ? '' : 'disabled'}>Download all</button>
                        </div>
                    </div>
                    <div class="settings-empty-copy">Uses qb-phone media when available.</div>
                </section>
                <div class="settings-section-label">Synced images</div>
                <section class="settings-card settings-card-wide">
                    <div class="store-shots-grid">${galleryCards}</div>
                </section>
      </section>`, ['Bluetooth & devices','Devices']);
  };

  WP.renderNetworkSection = function() {
    return this.renderShell(`
      <section class="settings-page-block"><div class="settings-page-heading windows-main-title"><h2>Network & internet</h2></div><div class="settings-quick-links windows-stack-list">${this.renderSectionRow('Ethernet','Local network connection','Network & internet > Ethernet')}${this.renderSectionRow('VPN','Reroute traffic through detected VPN devices','Network & internet > VPN')}</div></section>`, ['Network & internet']);
  };

  WP.renderNetworkEthernetSection = function() {
    return this.renderShell(`<section class="settings-page-block"><div class="settings-page-heading windows-main-title"><h2>Ethernet</h2></div><section class="settings-card settings-card-wide"><div class="settings-stat-list"><div class="settings-stat-item"><span>Status</span><strong>Connected</strong></div><div class="settings-stat-item"><span>Address</span><strong>192.168.0.24</strong></div><div class="settings-stat-item"><span>Traceable</span><strong>${this.settings.vpnEnabled ? 'Masked by VPN' : 'Yes'}</strong></div></div></section></section>`, ['Network & internet','Ethernet']);
  };

  WP.renderNetworkVpnSection = function() {
    return this.renderShell(`<section class="settings-page-block"><div class="settings-page-heading windows-main-title"><h2>VPN</h2></div><section class="settings-card settings-card-wide"><label class="settings-toggle-row"><span><strong>Use detected VPN device</strong><small>Route traffic and reduce traceability</small></span><input type="checkbox" id="vpn-enabled" ${this.settings.vpnEnabled?'checked':''}></label><div class="setting-group"><label>Detected device</label><input class="settings-input" id="vpn-device" value="${this.settings.vpnDevice}" placeholder="No VPN device detected"></div><button class="btn-primary" id="save-network-vpn" type="button">Apply</button></section></section>`, ['Network & internet','VPN']);
  };

  WP.renderPersonalizationSection = function() {
    return this.renderShell(`<section class="settings-page-block"><div class="settings-page-heading windows-main-title"><h2>Personalization</h2></div><div class="settings-quick-links windows-stack-list">${this.renderSectionRow('Background','Background image, color, slideshow','Personalization > Background')}${this.renderSectionRow('Colors','Accent color, transparency effects, color theme','Personalization > Colors')}${this.renderSectionRow('Themes','Install, create, manage','Personalization > Themes')}${this.renderSectionRow('Lock screen','Lock screen images, apps, animations','Personalization > Lock screen')}${this.renderSectionRow('Fonts','Installed fonts and text appearance','Personalization > Fonts')}</div></section>`, ['Personalization']);
  };

  WP.renderPersonalizationBackgroundSection = function() {
    return this.renderShell(`<section class="settings-page-block"><div class="settings-page-heading windows-main-title"><h2>Background</h2></div><section class="settings-card settings-card-wide"><div class="windows-theme-strip">${this.getWallpaperPresets().map((preset)=>`<button type="button" class="appearance-preset-card ${this.settings.wallpaperPreset===preset.key?'active':''}" data-wallpaper-preset="${preset.key}"><img src="${preset.src}" alt="${preset.label}"></button>`).join('')}</div><button class="btn-primary" id="save-personalization-background" type="button">Apply selected wallpaper</button></section></section>`, ['Personalization','Background']);
  };

  WP.renderPersonalizationColorsSection = function() {
    return this.renderShell(`<section class="settings-page-block"><div class="settings-page-heading windows-main-title"><h2>Colors</h2></div><section class="settings-card settings-card-wide"><div class="setting-group"><label>Accent color</label><input class="settings-input settings-color-input" type="color" id="accent-color" value="${this.settings.accentColor}"></div><label class="settings-toggle-row"><span><strong>Transparency effects</strong><small>Show transparent surfaces throughout Windows</small></span><input type="checkbox" id="transparency-toggle" ${this.settings.transparency?'checked':''}></label><button class="btn-primary" id="save-personalization-colors" type="button">Apply</button></section></section>`, ['Personalization','Colors']);
  };

  WP.renderPersonalizationThemesSection = function() {
    return this.renderShell(`<section class="settings-page-block"><div class="settings-page-heading windows-main-title"><h2>Themes</h2></div><section class="settings-card settings-card-wide"><div class="setting-group"><label>Color mode</label><select class="settings-select" id="theme-select"><option value="dark" ${this.settings.themeMode==='dark'?'selected':''}>Dark</option><option value="light" ${this.settings.themeMode==='light'?'selected':''}>Light</option></select></div><button class="btn-primary" id="save-personalization-theme" type="button">Apply</button></section></section>`, ['Personalization','Themes']);
  };

  WP.renderPersonalizationLockScreenSection = function() {
    const method = this.settings.securityUnlockMethod || 'pin';
    const enabled = !!this.settings.securityLockscreenEnabled;
    return this.renderShell(`<section class="settings-page-block"><div class="settings-page-heading windows-main-title"><h2>Lock screen</h2></div><section class="settings-card settings-card-wide"><label class="settings-toggle-row"><span><strong>Enable lock screen</strong><small>Show Windows style lock screen when the computer is locked</small></span><input type="checkbox" id="security-lockscreen-enabled" ${enabled?'checked':''}></label><div class="setting-group"><label>Lock screen image</label><input class="settings-input" id="security-lock-wallpaper" value="${this.settings.securityLockWallpaper || ''}" placeholder="Image URL or leave blank for wallpaper"></div><label class="settings-toggle-row"><span><strong>Show widgets</strong><small>Weather and quick widgets on the lock screen</small></span><input type="checkbox" id="lockscreen-widgets" ${this.settings.lockscreenWidgets?'checked':''}></label><div class="setting-group"><label>Sign-in option</label><select class="settings-select" id="lockscreen-type"><option value="pin" ${method==='pin'?'selected':''}>PIN</option><option value="password" ${method==='password'?'selected':''}>Password</option><option value="fingerprint" ${method==='fingerprint'?'selected':''}>Fingerprint</option></select></div><button class="btn-primary" id="save-lockscreen" type="button">Apply</button></section></section>`, ['Personalization','Lock screen']);
  };

  WP.renderPersonalizationFontsSection = function() {
    return this.renderShell(`<section class="settings-page-block"><div class="settings-page-heading windows-main-title"><h2>Fonts</h2></div><section class="settings-card settings-card-wide"><div class="setting-group"><label>Interface font</label><select class="settings-select" id="font-family"><option ${this.settings.fontFamily==='Segoe UI'?'selected':''}>Segoe UI</option><option ${this.settings.fontFamily==='Arial'?'selected':''}>Arial</option><option ${this.settings.fontFamily==='Tahoma'?'selected':''}>Tahoma</option></select></div><button class="btn-primary" id="save-fonts" type="button">Apply</button></section></section>`, ['Personalization','Fonts']);
  };

  WP.renderAccountsSection = function() {
    const { playerName, subtitle } = this.getPlayerIdentity();
    let users=[]; try { users = JSON.parse(this.settings.accountUsers || '[]'); } catch(e) {}
    return this.renderShell(`<section class="settings-page-block"><div class="settings-page-heading windows-main-title"><h2>Accounts</h2></div><section class="settings-card settings-card-wide"><div class="setting-group"><label>Computer owner</label><input class="settings-input" id="owner-name" value="${this.settings.ownerName || playerName}"></div><label class="settings-toggle-row"><span><strong>Business account</strong><small>Turns this computer into a government or company managed account</small></span><input type="checkbox" id="business-account" ${this.settings.businessAccount?'checked':''}></label><div class="setting-group"><label>Add local account</label><div class="settings-inline"><input class="settings-input" id="new-local-user" placeholder="Account name"><button class="btn-secondary" id="add-local-user" type="button">Add</button></div></div><div class="settings-section-label">Other users</div><div id="account-users-list">${users.length ? users.map((u,idx)=>`<div class="windows-device-row"><div class="windows-device-icon"><i class="fa-solid fa-user"></i></div><div><strong>${u}</strong><small>Local account</small></div><button class="btn-secondary remove-local-user" data-index="${idx}" type="button">Remove</button></div>`).join('') : '<div class="settings-empty-copy">No additional local accounts.</div>'}</div><button class="btn-primary" id="save-accounts" type="button">Apply</button></section></section>`, ['Accounts']);
  };

  WP.renderTimeLanguageSection = function() {
    return this.renderShell(`<section class="settings-page-block"><div class="settings-page-heading windows-main-title"><h2>Time & language</h2></div><div class="settings-quick-links windows-stack-list">${this.renderSectionRow('Date & time','Time zones, automatic clock settings, calendar display','Time & language > Date & time')}${this.renderSectionRow('Language','Windows display language and regional formats','Time & language > Language')}</div></section>`, ['Time & language']);
  };

  WP.renderTimeDateSection = function() {
    return this.renderShell(`<section class="settings-page-block"><div class="settings-page-heading windows-main-title"><h2>Date & time</h2></div><section class="settings-card settings-card-wide"><label class="settings-toggle-row"><span><strong>Use in-game time</strong><small>Use live synced game time instead of real-world time</small></span><input type="checkbox" id="clock-source-ingame" ${this.settings.clockSource==='ingame'?'checked':''}></label><div class="setting-group"><label>Time format</label><select class="settings-select" id="timeformat-select"><option value="12-hour" ${this.settings.timeFormat==='12-hour'?'selected':''}>12-hour</option><option value="24-hour" ${this.settings.timeFormat==='24-hour'?'selected':''}>24-hour</option></select></div><button class="btn-primary" id="save-time-date" type="button">Apply</button></section></section>`, ['Time & language','Date & time']);
  };

  WP.renderLanguageSection = function() {
    return this.renderShell(`<section class="settings-page-block"><div class="settings-page-heading windows-main-title"><h2>Language</h2></div><section class="settings-card settings-card-wide"><div class="setting-group"><label>Windows display language</label><select class="settings-select" id="language-select"><option value="English" ${this.settings.language==='English'?'selected':''}>English</option><option value="Polish" ${this.settings.language==='Polish'?'selected':''}>Polish</option><option value="Spanish" ${this.settings.language==='Spanish'?'selected':''}>Spanish</option></select></div><button class="btn-primary" id="save-language" type="button">Apply</button></section></section>`, ['Time & language','Language']);
  };

  WP.renderAccessibilitySection = function() {
    return this.renderShell(`<section class="settings-page-block"><div class="settings-page-heading windows-main-title"><h2>Accessibility</h2></div><div class="settings-quick-links windows-stack-list">${this.renderSectionRow('Text size','Adjust the size of text throughout Windows and your apps','Accessibility > Text size')}</div></section>`, ['Accessibility']);
  };

  WP.renderAccessibilityTextSection = function() {
    return this.renderShell(`<section class="settings-page-block"><div class="settings-page-heading windows-main-title"><h2>Text size</h2></div><section class="settings-card settings-card-wide"><div class="setting-group"><label>Text size</label><input class="settings-range" type="range" min="85" max="140" value="100" id="text-size-range"><div class="settings-range-meta"><span>A</span><strong id="text-size-value">100%</strong><span style="font-size:1.4rem">A</span></div></div><button class="btn-primary" id="save-text-size" type="button">Apply</button></section></section>`, ['Accessibility','Text size']);
  };

  WP.renderPrivacySection = function() {
    return this.renderShell(`<section class="settings-page-block"><div class="settings-page-heading windows-main-title"><h2>Privacy & Security</h2></div><div class="settings-quick-links windows-stack-list">${this.renderSectionRow('Firewall','Protect this computer from terminal and dark terminal attacks','Privacy & Security > Firewall')}${this.renderSectionRow('Lock screen','Configure sign-in options and lockdown mode','Privacy & Security > Lock screen')}</div></section>`, ['Privacy & Security']);
  };

  WP.renderPrivacyFirewallSection = function() {
    return this.renderShell(`<section class="settings-page-block"><div class="settings-page-heading windows-main-title"><h2>Firewall</h2></div><section class="settings-card settings-card-wide"><label class="settings-toggle-row"><span><strong>Microsoft Defender Firewall</strong><small>Protect your device from unauthorized terminal access</small></span><input type="checkbox" id="firewall-enabled" ${this.settings.firewallEnabled?'checked':''}></label><div class="setting-group"><label>Protection level</label><select class="settings-select" id="firewall-level"><option value="basic" ${this.settings.firewallLevel==='basic'?'selected':''}>Basic</option><option value="standard" ${this.settings.firewallLevel==='standard'?'selected':''}>Standard</option><option value="hardened" ${this.settings.firewallLevel==='hardened'?'selected':''}>Hardened</option></select></div><button class="btn-primary" id="save-firewall" type="button">Apply</button></section></section>`, ['Privacy & Security','Firewall']);
  };

  WP.renderPrivacyLockScreenSection = function() {
    const enabled = !!this.settings.securityLockscreenEnabled;
    const method = this.settings.securityUnlockMethod || 'pin';
    return this.renderShell(`<section class="settings-page-block"><div class="settings-page-heading windows-main-title"><h2>Lock screen</h2></div><section class="settings-card settings-card-wide"><label class="settings-toggle-row"><span><strong>Enable lock screen</strong><small>Require sign-in when this PC is locked</small></span><input type="checkbox" id="security-lockscreen-enabled" ${enabled?'checked':''}></label><div class="setting-group"><label>Sign-in option</label><select class="settings-select" id="security-unlock-method"><option value="password" ${method==='password'?'selected':''}>Password</option><option value="pin" ${method==='pin'?'selected':''}>PIN</option><option value="fingerprint" ${method==='fingerprint'?'selected':''}>Fingerprint</option></select></div><div class="setting-group"><label>Password</label><input class="settings-input" type="password" id="security-password" value="${this.settings.securityPassword || ''}" placeholder="Password"></div><div class="setting-group"><label>PIN</label><input class="settings-input" id="security-pin" value="${this.settings.securityPin || ''}" placeholder="PIN"></div><label class="settings-toggle-row"><span><strong>Lockdown mode</strong><small>Enter lockdown after repeated failed sign-in attempts</small></span><input type="checkbox" id="security-lockdown-on-hack-fail" ${this.settings.securityLockdownOnHackFail?'checked':''}></label><div class="setting-group"><label>Failed tries until lockdown</label><input class="settings-input" type="number" min="1" max="10" id="security-lockdown-threshold" value="${this.settings.securityLockdownThreshold || 3}"></div><div class="setting-group"><label>Lockdown password</label><input class="settings-input" type="password" id="security-lockdown-password" value="${this.settings.securityLockdownPassword || ''}" placeholder="Required to exit lockdown"></div><button class="btn-primary" id="save-privacy-lockscreen" type="button">Apply</button></section></section>`, ['Privacy & Security','Lock screen']);
  };

  WP.parseSettingsPath = function(section) {
    return String(section || 'Home').split('>').map(s => s.trim()).filter(Boolean);
  };

  WP.loadSettingsSection = function(section = 'Home') {
    this.ensureWindowsDefaults();
    const container = this.getMainContainer();
    if (!container) return;
    const key = String(section || 'Home');
    this.currentSection = key;
    const routes = {
      'Home': ()=>this.renderHomeSection(),
      'System': ()=>this.renderSystemSection(),
      'System > Display': ()=>this.renderSystemDisplaySection(),
      'System > Sound': ()=>this.renderSystemSoundSection(),
      'Bluetooth & devices': ()=>this.renderBluetoothSection(),
      'Bluetooth & devices > Devices': ()=>this.renderBluetoothDevicesSection(),
      'Network & internet': ()=>this.renderNetworkSection(),
      'Network & internet > Ethernet': ()=>this.renderNetworkEthernetSection(),
      'Network & internet > VPN': ()=>this.renderNetworkVpnSection(),
      'Personalization': ()=>this.renderPersonalizationSection(),
      'Personalization > Background': ()=>this.renderPersonalizationBackgroundSection(),
      'Personalization > Colors': ()=>this.renderPersonalizationColorsSection(),
      'Personalization > Themes': ()=>this.renderPersonalizationThemesSection(),
      'Personalization > Lock screen': ()=>this.renderPersonalizationLockScreenSection(),
      'Personalization > Fonts': ()=>this.renderPersonalizationFontsSection(),
      'Accounts': ()=>this.renderAccountsSection(),
      'Time & language': ()=>this.renderTimeLanguageSection(),
      'Time & language > Date & time': ()=>this.renderTimeDateSection(),
      'Time & language > Language': ()=>this.renderLanguageSection(),
      'Accessibility': ()=>this.renderAccessibilitySection(),
      'Accessibility > Text size': ()=>this.renderAccessibilityTextSection(),
      'Privacy & Security': ()=>this.renderPrivacySection(),
      'Privacy & Security > Firewall': ()=>this.renderPrivacyFirewallSection(),
      'Privacy & Security > Lock screen': ()=>this.renderPrivacyLockScreenSection()
    };
    container.innerHTML = (routes[key] || routes['Home'])();
    document.querySelectorAll('.settings-nav-item').forEach(nav => nav.classList.toggle('active', nav.textContent.trim() === this.parseSettingsPath(key)[0]));
    this.bindGlobalSearch();
    this.attachSettingsHandlers(key);
    hydratePlayerProfile();
  };

  WP.attachSettingsHandlers = function(section) {
    const navTo = (value) => this.loadSettingsSection(value);
    document.querySelectorAll('[data-settings-nav]').forEach(el => el.addEventListener('click', ()=> navTo(el.dataset.settingsNav)));
    document.querySelectorAll('[data-settings-crumb]').forEach(el => {
      el.addEventListener('click', ()=> {
        const clicked = el.dataset.settingsCrumb;
        const parts = this.parseSettingsPath(this.currentSection || 'Home');
        const idx = parts.indexOf(clicked);
        if (idx >= 0) navTo(parts.slice(0, idx+1).join(' > '));
      });
    });
    document.querySelectorAll('[data-wallpaper-preset]').forEach((button)=>button.addEventListener('click',()=>{this.applyWallpaperPreset(button.dataset.wallpaperPreset); this.loadSettingsSection(this.currentSection || 'Personalization > Background'); }));
    const byId = (id)=>document.getElementById(id);
    const bind = (id, fn, msg='Saved.') => { const b=byId(id); if (b) b.addEventListener('click', ()=>{ fn(); this.applyLiveSettings(); this.showNotification(msg); }); };
    const brightness = byId('brightness-range'); if (brightness) brightness.addEventListener('input', ()=> { const v=byId('brightness-value'); if(v) v.textContent = `${brightness.value}%`; document.documentElement.style.setProperty('--desktop-brightness', `${brightness.value}%`);});
    const textSize = byId('text-size-range'); if (textSize) textSize.addEventListener('input', ()=> { const v=byId('text-size-value'); if(v) v.textContent = `${textSize.value}%`; document.documentElement.style.fontSize = `${textSize.value}%`;});
    bind('save-system-display', ()=>{ this.saveSetting('brightness', Number(byId('brightness-range')?.value || 100)); this.saveSetting('animations', !!byId('animations')?.checked); this.saveSetting('desktopIconScale', byId('desktop-icon-scale')?.value || 'medium'); }, 'Display settings applied.');
    bind('save-system-sound', ()=>{ this.saveSetting('soundEffects', !!byId('sound-effects')?.checked); this.saveSetting('notificationSound', !!byId('notification-sound')?.checked); }, 'Sound settings applied.');
    bind('save-network-vpn', ()=>{ this.saveSetting('vpnEnabled', !!byId('vpn-enabled')?.checked); this.saveSetting('vpnDevice', byId('vpn-device')?.value || 'No VPN device detected'); }, 'VPN settings applied.');
    bind('save-personalization-background', ()=>{}, 'Wallpaper applied.');
    bind('save-personalization-colors', ()=>{ this.saveSetting('accentColor', byId('accent-color')?.value || '#4cc2ff'); this.saveSetting('transparency', !!byId('transparency-toggle')?.checked); }, 'Colors applied.');
    bind('save-personalization-theme', ()=>{ const theme = byId('theme-select')?.value || 'dark'; this.saveSetting('themeMode', theme); this.themeManager.setTheme(theme); }, 'Theme applied.');
    bind('save-lockscreen', ()=>{ this.saveSetting('securityLockscreenEnabled', !!byId('security-lockscreen-enabled')?.checked); this.saveSetting('securityLockWallpaper', byId('security-lock-wallpaper')?.value || ''); this.saveSetting('lockscreenWidgets', !!byId('lockscreen-widgets')?.checked); this.saveSetting('securityUnlockMethod', byId('lockscreen-type')?.value || 'pin'); if(window.securityManager?.refreshFromStorage) window.securityManager.refreshFromStorage(); }, 'Lock screen updated.');
    bind('save-fonts', ()=>{ this.saveSetting('fontFamily', byId('font-family')?.value || 'Segoe UI'); document.body.style.fontFamily = this.settings.fontFamily; }, 'Font updated.');
    bind('save-accounts', ()=>{ this.saveSetting('ownerName', byId('owner-name')?.value || ''); this.saveSetting('businessAccount', !!byId('business-account')?.checked); }, 'Account settings applied.');
    const addUser = byId('add-local-user'); if (addUser) addUser.addEventListener('click', ()=>{ let users=[]; try { users=JSON.parse(this.settings.accountUsers||'[]'); }catch(e){} const name = String(byId('new-local-user')?.value || '').trim(); if(!name) return; users.push(name); this.saveSetting('accountUsers', JSON.stringify(users)); this.loadSettingsSection('Accounts'); });
    document.querySelectorAll('.remove-local-user').forEach(btn=>btn.addEventListener('click', ()=>{ let users=[]; try { users=JSON.parse(this.settings.accountUsers||'[]'); }catch(e){} users.splice(Number(btn.dataset.index),1); this.saveSetting('accountUsers', JSON.stringify(users)); this.loadSettingsSection('Accounts'); }));
    bind('save-time-date', ()=>{ this.saveSetting('clockSource', byId('clock-source-ingame')?.checked ? 'ingame' : 'real'); this.saveSetting('timeFormat', byId('timeformat-select')?.value || '12-hour'); }, 'Date & time applied.');
    bind('save-language', ()=>{ this.saveSetting('language', byId('language-select')?.value || 'English'); }, 'Language applied.');
    bind('save-text-size', ()=>{ document.documentElement.style.fontSize = `${byId('text-size-range')?.value || 100}%`; }, 'Text size applied.');
    bind('save-firewall', ()=>{ this.saveSetting('firewallEnabled', !!byId('firewall-enabled')?.checked); this.saveSetting('firewallLevel', byId('firewall-level')?.value || 'standard'); }, 'Firewall applied.');
    bind('save-privacy-lockscreen', ()=>{ this.saveSetting('securityLockscreenEnabled', !!byId('security-lockscreen-enabled')?.checked); this.saveSetting('securityUnlockMethod', byId('security-unlock-method')?.value || 'password'); this.saveSetting('securityPassword', byId('security-password')?.value || ''); this.saveSetting('securityPin', byId('security-pin')?.value || ''); this.saveSetting('securityLockdownOnHackFail', !!byId('security-lockdown-on-hack-fail')?.checked); this.saveSetting('securityLockdownThreshold', Number(byId('security-lockdown-threshold')?.value || 3)); this.saveSetting('securityLockdownPassword', byId('security-lockdown-password')?.value || ''); if(window.securityManager?.refreshFromStorage) window.securityManager.refreshFromStorage(); }, 'Lock screen settings applied.');

        const triggerImageDownload = (url, fileName) => {
            const safeUrl = String(url || '').trim();
            if (!safeUrl) return;
            const link = document.createElement('a');
            link.href = safeUrl;
            link.target = '_blank';
            link.rel = 'noopener noreferrer';
            link.download = fileName || '';
            document.body.appendChild(link);
            link.click();
            link.remove();
        };

        const syncPhoneBtn = byId('search-nearby-phones');
        if (syncPhoneBtn) {
            syncPhoneBtn.addEventListener('click', async () => {
                syncPhoneBtn.disabled = true;
                try {
                    const response = await nuiRequest('pc:devices:getPhoneImages', {});
                    const images = Array.isArray(response?.data?.images) ? response.data.images : [];
                    scopedStorageSet('devices_phone_gallery_cache', JSON.stringify(images));
                    this.showNotification(images.length ? `Synced ${images.length} image(s) from phone.` : 'No phone images found.');
                    this.loadSettingsSection('Bluetooth & devices > Devices');
                } catch (error) {
                    console.error('Phone sync failed:', error);
                    this.showNotification('Failed to sync phone images.');
                } finally {
                    syncPhoneBtn.disabled = false;
                }
            });
        }

        const downloadAllBtn = byId('download-all-phone-images');
        if (downloadAllBtn) {
            downloadAllBtn.addEventListener('click', () => {
                let images = [];
                try {
                    images = JSON.parse(scopedStorageGet('devices_phone_gallery_cache', '[]') || '[]');
                } catch (_error) {
                    images = [];
                }
                images.forEach((img, idx) => triggerImageDownload(img.url, img.name || `phone-image-${idx + 1}.jpg`));
                this.showNotification(images.length ? `Downloading ${images.length} image(s).` : 'No phone images to download.');
            });
        }

        document.querySelectorAll('.download-phone-image').forEach((button) => {
            button.addEventListener('click', () => {
                triggerImageDownload(button.dataset.imageUrl, button.dataset.imageName || 'phone-image.jpg');
            });
        });

    const openRenameBtn = byId('open-rename-computer'); const renameForm = byId('rename-computer-form'); const cancelRenameBtn = byId('cancel-rename-computer');
    if (openRenameBtn && renameForm) openRenameBtn.addEventListener('click', ()=>{ renameForm.style.display='flex'; openRenameBtn.style.display='none'; byId('computer-name-input')?.focus(); });
    if (cancelRenameBtn && renameForm) cancelRenameBtn.addEventListener('click', ()=>{ renameForm.style.display='none'; if (openRenameBtn) openRenameBtn.style.display=''; });
    const saveComputerNameButton = byId('save-computer-name'); if (saveComputerNameButton) saveComputerNameButton.addEventListener('click', ()=>{ const v = String(byId('computer-name-input')?.value || '').trim(); if (!v) return; this.saveSetting('computerName', v); this.loadSettingsSection('Home'); });
  };

  WP.filterCurrentSettingsPage = function(query) {
    const q = String(query || '').trim().toLowerCase();
    document.querySelectorAll('.settings-page-block [data-settings-search], .settings-page-block .settings-card, .settings-page-block .settings-link-row, .settings-page-block .settings-toggle-row, .settings-page-block .setting-group, .settings-page-block .windows-device-row').forEach((element) => {
      const haystack = ((element.getAttribute('data-settings-search') || '') + ' ' + element.textContent).toLowerCase();
      element.classList.toggle('settings-filter-hidden', !!q && !haystack.includes(q));
    });
  };
})();

// Initialize everything when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    const themeManager = new ThemeManager();
    const windowManager = new WindowManager();
    window.windowManagerInstance = windowManager;
    // window.cityHall = new CityHallManager(); // REMOVED - old app
    // window.businessesManager = new BusinessesManager(); // REMOVED - old app
    const settingsManager = new SettingsManager(themeManager);
    window.settingsManager = settingsManager;
    const startMenu = new StartMenu(windowManager);
    const powerMenu = new PowerMenu();
    window.securityManager = new SecurityManager();
    
    // Initialize new app managers
    console.log('Creating app managers...');
    window.browserManager = new BrowserManager();
    console.log('- BrowserManager created');
    window.mailManager = new MailManager();
    console.log('- MailManager created');
    window.calendarManager = new CalendarManager();
    console.log('- CalendarManager created');
    window.mapsManager = new MapsManager();
    console.log('- MapsManager created');
    window.billsManager = new BillsManager();
    console.log('- BillsManager created');
    window.jobBoardManager = new JobBoardManager();
    console.log('- JobBoardManager created');
    window.terminalManager = new TerminalManager();
    console.log('- TerminalManager created');
    window.calculatorManager = new CalculatorManager();
    console.log('- CalculatorManager created');
    window.businessManager = new BusinessManager();
    console.log('- BusinessManager created');
    window.orderSuppliesManager = new OrderSuppliesManager();
    console.log('- OrderSuppliesManager created');
    
    // Initialize system managers
    console.log('Creating system managers...');
    window.documentsManager = new DocumentsManager();
    console.log('- DocumentsManager created');
    window.gamesManager = new GamesManager();
    console.log('- GamesManager created');
    // Load external programs first so StoreManager class is initialized from that module block.
    loadExternalPrograms(windowManager, 'default');

    if (typeof window.StoreManager === 'function') {
        window.storeManager = new window.StoreManager(settingsManager);
        console.log('- StoreManager created');
    } else {
        console.error('StoreManager class was not initialized.');
    }
    window.desktopManager = new DesktopManager();
    console.log('- DesktopManager created');
    window.dragDropManager = new DragDropManager(window.desktopManager);
    console.log('- DragDropManager created');
    
    // External programs are loaded above before StoreManager creation.

    // Factory Reset Button
    const factoryResetBtn = document.getElementById('factory-reset-btn');
    if (factoryResetBtn) {
        factoryResetBtn.addEventListener('click', () => {
            window.desktopManager.resetToDefault();
            scopedStorageSet('security_is_locked', 'false');
            scopedStorageRemove('security_lockdown_until');
            clearAllMailAccountStorage();
            clearCurrentScopeStorage();
            window.location.reload();
        });
    }

    // Apply custom wallpaper on load
    const customWallpaper = scopedStorageGet('customWallpaper', localStorage.getItem('customWallpaper'));
    if (customWallpaper) {
        settingsManager.applyCustomWallpaper(customWallpaper);
    } else {
        const wallpaperGradient = scopedStorageGet('wallpaperGradient', localStorage.getItem('wallpaperGradient'));
        if (wallpaperGradient) {
            settingsManager.applyGradientWallpaper(wallpaperGradient);
        }
    }

    console.log('=== Government UI System Loaded Successfully ===');
    console.log('All managers initialized. System ready.');
});

// Listen for messages from Lua (for opening/closing computer)
window.addEventListener('message', async function(event) {
    const data = event.data;

    if (data.action === 'environmentSync' || data.weather || data.weatherType || data.currentWeather) {
        const nextWeather = normalizeWeatherKey(data.weather || data.weatherType || data.currentWeather);
        scopedStorageSet('currentWeather', nextWeather);

        const normalizedClock = normalizeClockParts(data.gameHour, data.gameMinute);
        if (normalizedClock) {
            scopedStorageSet('ingameHour', String(normalizedClock.hours));
            scopedStorageSet('ingameMinute', String(normalizedClock.minutes));
        }

        if (window.windowManagerInstance && typeof window.windowManagerInstance.updateWeatherWidget === 'function') {
            window.windowManagerInstance.updateWeatherWidget();
            window.windowManagerInstance.updateDateTime();
        }
    }

    if (data.action === 'pf-computer:closeExternalProgram' && data.programId) {
        if (window.windowManagerInstance) {
            window.windowManagerInstance.closeWindow(data.programId);
        }
        return;
    }

    if (data.action === 'pf-computer:openExternalProgram' && data.programId) {
        if (window.windowManagerInstance) {
            window.windowManagerInstance.openWindow(data.programId);
        }
        return;
    }
    
    if (data.action === 'openComputer') {
        const profile = data.computerProfile || 'default';
        const stateScope = data.computerStateKey || profile;
        setComputerStateScope(stateScope);
        await hydratePlayerProfile();

        if (window.desktopManager && typeof window.desktopManager.reloadForScope === 'function') {
            window.desktopManager.reloadForScope();
        }
        if (window.documentsManager && typeof window.documentsManager.loadDocuments === 'function') {
            window.documentsManager.documents = window.documentsManager.loadDocuments();
            if (typeof window.documentsManager.renderDocumentList === 'function') {
                window.documentsManager.renderDocumentList();
            }
        }
        if (window.terminalManager) {
            window.terminalManager.darknetMode = scopedStorageGet('terminal_darknet_mode') === 'true';
            if (typeof window.terminalManager.applyTerminalChrome === 'function') {
                window.terminalManager.applyTerminalChrome();
            }
        }
        if (window.mailManager && typeof window.mailManager.reloadForScope === 'function') {
            window.mailManager.reloadForScope();
        }
        if (window.settingsManager && typeof window.settingsManager.reloadForScope === 'function') {
            window.settingsManager.reloadForScope();
        }
        if (window.storeManager && typeof window.storeManager.reloadForScope === 'function') {
            window.storeManager.reloadForScope();
        }

        clearExternalPrograms(window.windowManagerInstance);
        loadExternalPrograms(window.windowManagerInstance, profile);

        if (window.windowManagerInstance && typeof window.windowManagerInstance.restoreWindowSession === 'function') {
            window.windowManagerInstance.restoreWindowSession();
        }

        // Show the computer interface
        document.body.style.display = 'block';
        syncChromeMetrics();
        if (window.securityManager && typeof window.securityManager.handleComputerOpened === 'function') {
            window.securityManager.handleComputerOpened();
        }
        console.log('Computer opened from Lua');
    } else if (data.action === 'closeComputer') {
        // Hide the computer interface
        document.body.style.display = 'none';
        if (window.securityManager && typeof window.securityManager.clearActiveLockscreen === 'function') {
            window.securityManager.clearActiveLockscreen();
        }
        console.log('Computer closed from Lua');
    } else if (data.action === 'openExternalProgram' && data.programId) {
        if (window.windowManagerInstance) {
            window.windowManagerInstance.openWindow(data.programId);
        }
    } else if (data.action === 'closeExternalProgram' && data.programId) {
        if (window.windowManagerInstance) {
            window.windowManagerInstance.closeWindow(data.programId);
        }
    } else if (data.action === 'jobChanged') {
        // Handle job change - refresh business manager and order supplies if they're open
        console.log('Job changed detected, refreshing job-dependent apps');
        if (window.businessManager) {
            window.businessManager.handleJobChange(data);
        }
        if (window.orderSuppliesManager) {
            window.orderSuppliesManager.handleJobChange(data);
        }
    }
});

// ESC key to close computer
document.addEventListener('keydown', function(event) {
    if (event.key === 'Escape') {
        fetch('https://pf-computer/pc:close', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({})
        });
    }
});

// Add notification animations
const style = document.createElement('style');
style.textContent = `
    @keyframes slideIn {
        from { transform: translateX(400px); opacity: 0; }
        to { transform: translateX(0); opacity: 1; }
    }
    @keyframes slideOut {
        from { transform: translateX(0); opacity: 1; }
        to { transform: translateX(400px); opacity: 0; }
    }
`;
document.head.appendChild(style);


window.addEventListener('resize', syncChromeMetrics);
document.addEventListener('DOMContentLoaded', () => {
    syncChromeMetrics();
    hydratePlayerProfile();
});
