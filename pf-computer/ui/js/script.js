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

    // platform apps (pf-devices) keep their own window ids
    if (normalized.startsWith('pfapp-')) return normalized;

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
    const platformIcon = window.PFComputerPlatform && window.PFComputerPlatform.iconFor(appNameOrKey);
    if (platformIcon) {
        const glyph = document.createElement('span');
        glyph.textContent = platformIcon;
        return `<span class="app-icon-badge app-icon-${context} pfapp-icon-badge"><span class="pfapp-emoji">${glyph.innerHTML}</span></span>`;
    }
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
// Mail, Bills, Documents and Calendar are pf-citizen's platform apps: stored on the server, the
// same on the tablet, mail reaching offline players. The computer's own versions lived in this
// browser's cache (the bills were six made-up ones). Their icons, tiles and pins now open the platform
// app; when it is not running, the old window only says so.
// Business Manager, Order Supplies and the Job Board are pf-computer's own platform apps
// (html/apps/*.js, the same modules the tablet runs). Old desktop items, recent apps and saved window
// sessions that name the old windows open the platform app; a player the server does not let use it
// is told so.
const PLATFORM_HANDOFF = {
    mail: 'mail', bills: 'bills', documents: 'documents', calendar: 'calendar',
    'business-manager': 'businessmanager', 'order-supplies': 'ordersupplies', 'job-board': 'jobboard',
};
const PLATFORM_HANDOFF_UNAVAILABLE = {
    'business-manager': 'The Business Manager is for the management of a business.',
    'order-supplies': 'Order Supplies is for business bosses and store owners.',
    'job-board': 'The Job Board is not available right now.',
};

async function openPlatformHandoff(appName, windowManager) {
    const id = PLATFORM_HANDOFF[appName];
    const api = window.PFApps;
    if (api && typeof api.getApp === 'function') {
        if (!api.getApp(id) && typeof api.refresh === 'function') {
            try { await api.refresh(); } catch (e) { /* the app list could not be read */ }
        }
        if (api.getApp(id)) {
            api.open(id);
            return;
        }
    }
    if (windowManager.windows.has(appName)) {
        windowManager.openWindow(appName, { platformChecked: true });
        return;
    }
    uiNotify(PLATFORM_HANDOFF_UNAVAILABLE[appName] || 'That app is not available right now.', 'warning');
}

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
        if (PLATFORM_HANDOFF[appName] && !options.platformChecked) {
            openPlatformHandoff(appName, this);
            return;
        }
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
            // the lock screen is the server's (SecurityManager); a PIN or password never comes back
            ...this.securityFields(),
            computerName: scopedSettingGet('computerName', localStorage.getItem('computerName') || 'computer'),
            computerID: scopedSettingGet('computerID', localStorage.getItem('computerID'))
        };
    }

    reloadForScope() {
        this.settings = this.loadSettingsFromStorage();
        this.applyAllSettings();
        this.loadSettingsSection(this.currentSection || 'Home');
    }

    securityFields(state) {
        const sec = state || (window.securityManager && window.securityManager.state)
            || SecurityManager.prototype.cachedState.call(null) || {};
        return {
            securityLockscreenEnabled: sec.enabled === true,
            securityUnlockMethod: String(sec.method || 'pin'),
            securityHasPin: sec.hasPin === true,
            securityHasPassword: sec.hasPassword === true,
            securityHasLockdownPassword: sec.hasLockdownPassword === true,
            securityLockWallpaper: String(sec.lockWallpaper || ''),
            securityLockdownOnHackFail: sec.lockdownOnHackFail === true,
            securityLockdownThreshold: Number(sec.lockdownThreshold || 3),
        };
    }

    // the server's lock screen state changed (saved, locked, unlocked): keep the shown values current
    applySecurityState(state) {
        Object.assign(this.settings, this.securityFields(state));
    }

    // Lock screen settings go to the server. The handlers save several fields one after another;
    // they are sent together once the handler is done. Empty secrets mean "keep the current one".
    queueSecuritySetting(key, value) {
        const field = {
            securityLockscreenEnabled: 'enabled', securityUnlockMethod: 'method', securityPassword: 'password', securityPin: 'pin',
            securityLockWallpaper: 'lockWallpaper', securityLockdownOnHackFail: 'lockdownOnHackFail',
            securityLockdownPassword: 'lockdownPassword', securityLockdownThreshold: 'lockdownThreshold',
        }[key];
        if (!field) return;
        if (['password', 'pin', 'lockdownPassword'].includes(field)) {
            value = String(value || '').trim();
            if (!value) return;
        }
        if (field === 'enabled' || field === 'lockdownOnHackFail') value = value === true || value === 'true';
        if (field === 'lockdownThreshold') value = Math.max(1, Math.min(10, Math.floor(Number(value) || 3)));
        this.pendingSecurity = Object.assign(this.pendingSecurity || {}, { [field]: value });
        if (this.pendingSecurityFlush) return;
        this.pendingSecurityFlush = Promise.resolve().then(async () => {
            const patch = this.pendingSecurity;
            this.pendingSecurity = null;
            this.pendingSecurityFlush = null;
            if (window.securityManager && patch) await window.securityManager.saveSettings(patch);
        });
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
        if (String(key).startsWith('security')) {
            if (!['securityPin', 'securityPassword', 'securityLockdownPassword'].includes(key)) this.settings[key] = value;
            this.queueSecuritySetting(key, value);
            return;
        }
        this.settings[key] = value;
        const serialized = typeof value === 'boolean' ? String(value) : value;
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
                ${id === 'fingerprint' ? '<small style="color:rgba(255,255,255,0.65)">Press and hold the fingerprint sensor for 3 seconds on the lock screen.</small>' : `<input class="settings-input" type="password" id="security-${id}" value="" autocomplete="off" placeholder="${id === 'pin' ? (this.settings.securityHasPin ? 'PIN set: type a new one to change it' : 'Choose a PIN (4 to 8 digits)') : (this.settings.securityHasPassword ? 'Password set: type a new one to change it' : 'Choose a password (4 or more characters)')}"><small style="color:rgba(255,255,255,0.45);margin-top:4px;display:block">Leave blank to keep the current ${id === 'pin' ? 'PIN' : 'password'}.</small>`}
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
                                <input class="settings-input" type="password" id="security-lockdown-password" value="" autocomplete="off" placeholder="${this.settings.securityHasLockdownPassword ? 'Set: type a new one to change it' : 'Lockdown exit password'}">
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

            // a new PIN or password only when one was typed (the server keeps the current one otherwise)
            this.saveSetting('securityPin', String(document.getElementById('security-pin')?.value || '').trim());
            this.saveSetting('securityPassword', String(document.getElementById('security-password')?.value || '').trim());
            this.saveSetting('securityLockdownOnHackFail', !!document.getElementById('security-lockdown-on-hack-fail')?.checked);
            this.saveSetting('securityLockdownPassword', String(document.getElementById('security-lockdown-password')?.value || '').trim());
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
                    computerName: 'computer'
                };
                Object.entries(defaults).forEach(([key, value]) => this.saveSetting(key, value));
                if (window.securityManager) window.securityManager.resetSettings();
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

// The lock screen of this character on this computer is kept on the server (server/profiles.lua):
// the PIN, password and lockdown password are checked there and never sent to this page, and failed
// tries, timeouts, breach failures and lockdowns are counted there. The browser cache keeps only the
// public part of the state, so the settings show something before the server answers.
class SecurityManager {
    constructor() {
        this.overlay = null;
        this.hackOverlay = null;
        this.clockInterval = null;
        this.lockView = 'idle';
        this.serverConfig = { security: {}, hacking: {} };
        this.adminRecoveryAllowed = false;
        this.detectedHackTool = null;
        this.deadlines = { timeout: 0, lockdown: 0 };
        this.state = this.cachedState();
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

    scope() {
        return CURRENT_COMPUTER_BASE_SCOPE || 'default';
    }

    cachedState() {
        try {
            const cached = JSON.parse(scopedStorageGet('security_state_cache', 'null') || 'null');
            if (cached && typeof cached === 'object') return cached;
        } catch (error) { /* no cache yet */ }
        return { enabled: false, method: 'pin', locked: false, fails: 0, attemptsLeft: 5, timeoutRemaining: 0, lockdownRemaining: 0 };
    }

    // The server's answer (public fields only) becomes the state; the cache is a convenience.
    applyState(security) {
        if (!security || typeof security !== 'object') return;
        this.state = security;
        this.deadlines = {
            timeout: Date.now() + Math.max(0, Number(security.timeoutRemaining) || 0) * 1000,
            lockdown: Date.now() + Math.max(0, Number(security.lockdownRemaining) || 0) * 1000,
        };
        try { scopedStorageSet('security_state_cache', JSON.stringify(security)); } catch (error) { /* full storage */ }
        // the lock screen's input is blocked during a timeout or lockdown: draw it again when that ends
        clearTimeout(this.unblockTimer);
        const wait = Math.max(Number(security.timeoutRemaining) || 0, Number(security.lockdownRemaining) || 0);
        if (wait > 0) this.unblockTimer = setTimeout(() => this.refreshFromStorage(), wait * 1000 + 250);
        this.refreshFromStorage();
        if (window.settingsManager && typeof window.settingsManager.applySecurityState === 'function') {
            window.settingsManager.applySecurityState(security);
        }
    }

    async syncFromServer() {
        const res = await nuiRequest('pc:lock:state', { scope: this.scope() });
        if (res && res.ok && res.security) this.applyState(res.security);
        return res;
    }

    // Kept under its old name: the settings call it after a change.
    refreshFromStorage() {
        const st = this.state || {};
        this.settings = {
            enabled: st.enabled === true,
            unlockMethod: String(st.method || 'pin'),
            hasPin: st.hasPin === true,
            hasPassword: st.hasPassword === true,
            hasLockdownPassword: st.hasLockdownPassword === true,
            lockWallpaper: String(st.lockWallpaper || ''),
            lockdownOnHackFail: st.lockdownOnHackFail === true,
            lockdownThreshold: Number(st.lockdownThreshold || 3),
        };
        if (this.overlay && this.overlay.style.display !== 'none') {
            this.renderOverlay();
            this.bindOverlayActions();
        }
    }

    // Saves lock screen settings on the server; fields left out stay as they are.
    async saveSettings(patch) {
        const res = await nuiRequest('pc:lock:settings', Object.assign({ scope: this.scope() }, patch || {}));
        if (res && res.ok) {
            this.applyState(res.security);
            return res;
        }
        const why = {
            locked: 'Unlock the computer first.', pin_required: 'Set a PIN (4 to 8 digits) to use the PIN lock.',
            password_required: 'Set a password to use the password lock.', bad_pin: 'A PIN is 4 to 8 digits.',
            bad_password: 'A password is 4 to 64 characters.', bad_wallpaper: 'The lock screen image must be an https:// address.',
            bad_threshold: 'Failed tries until lockdown: 1 to 10.', bad_method: 'That sign-in option is turned off on this server.',
            storage_starting: 'The computer is still starting. Try again in a moment.',
        }[res && res.error];
        uiNotify(why || 'The lock screen settings were not saved.', 'error');
        return res;
    }

    async resetSettings() {
        const res = await nuiRequest('pc:lock:reset', { scope: this.scope() });
        if (res && res.ok) this.applyState(res.security);
        return res;
    }

    isLocked() {
        return this.state.locked === true && this.settings.enabled;
    }

    isLockdownActive() {
        return this.deadlines.lockdown > Date.now();
    }

    getLockdownRemainingSeconds() {
        return Math.max(0, Math.ceil((this.deadlines.lockdown - Date.now()) / 1000));
    }

    isUnlockAttemptTimeoutActive() {
        return this.deadlines.timeout > Date.now();
    }

    getUnlockAttemptTimeoutRemainingSeconds() {
        return Math.max(0, Math.ceil((this.deadlines.timeout - Date.now()) / 1000));
    }

    async markLockedFromLogoff() {
        const res = await nuiRequest('pc:lock:lock', { scope: this.scope() });
        if (res && res.ok) this.applyState(res.security);
    }

    clearActiveLockscreen() {
        this.stopClock();
        this.hideOverlay();
        this.hideHackOverlay();
    }

    async handleComputerOpened() {
        await this.bootstrap();
        await this.syncFromServer();
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

    // A refused unlock: the server says how many tries are left and for how long input is blocked.
    unlockRefusedText(res, what) {
        const st = (res && res.security) || this.state;
        if (res && res.error === 'lockdown') return `Lockdown active — ${this.getLockdownRemainingSeconds()}s remaining`;
        if (res && res.error === 'timeout') return `Too many attempts. Try again in ${this.getUnlockAttemptTimeoutRemainingSeconds()}s.`;
        if (res && res.error === 'wrong_secret') {
            const left = Number(st.attemptsLeft || 0);
            return left > 0 ? `Incorrect ${what} — ${left} attempt${left !== 1 ? 's' : ''} remaining`
                : `Too many attempts. Try again in ${this.getUnlockAttemptTimeoutRemainingSeconds()}s.`;
        }
        return 'The computer could not be unlocked right now.';
    }

    async requestUnlock(secret) {
        const res = await nuiRequest('pc:lock:unlock', { scope: this.scope(), secret });
        if (res && res.security) this.applyState(res.security);
        return res || { ok: false };
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

        const failCount = Number(this.state.fails || 0);
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

        const lockdownExitForm = (lockdown && this.settings.hasLockdownPassword)
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
                const needsSecret = (method === 'password' && this.settings.hasPassword) || (method === 'pin' && this.settings.hasPin);
                if (method !== 'fingerprint' && !needsSecret) {
                    this.requestUnlock('').then((res) => {
                        if (res.ok) this.onUnlockSuccess('Unlocked.');
                        else feedback(this.unlockRefusedText(res, 'PIN'), true);
                    });
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
            const submitLockdownExit = async () => {
                const val = String(this.overlay.querySelector('#pc-lockdown-exit-input')?.value || '');
                if (!val) return;
                const res = await nuiRequest('pc:lock:exitLockdown', { scope: this.scope(), password: val });
                if (res && res.security) this.applyState(res.security);
                if (res && res.ok) feedback('Lockdown cleared.', false);
                else feedback(res && res.error === 'wrong_secret' ? 'Incorrect admin password.' : this.unlockRefusedText(res, 'password'), true);
            };
            lockdownExitBtn.addEventListener('click', submitLockdownExit);
            const lockdownExitInput = this.overlay.querySelector('#pc-lockdown-exit-input');
            if (lockdownExitInput) {
                lockdownExitInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') submitLockdownExit(); });
            }
        }

        const authSubmit = this.overlay.querySelector('#pc-lock-auth-submit');
        if (authSubmit) {
            // the server checks the PIN or password and counts the failed tries
            const submitAuth = async () => {
                if (this.isUnlockAttemptTimeoutActive()) {
                    const remaining = this.getUnlockAttemptTimeoutRemainingSeconds();
                    feedback(`Too many failed attempts. Try again in ${remaining}s.`, true);
                    return;
                }
                const value = String(this.overlay.querySelector('#pc-lock-auth-input')?.value || '');
                if (!value) return;
                const what = this.settings.unlockMethod === 'pin' ? 'PIN' : 'password';
                const res = await this.requestUnlock(value);
                if (res.ok) {
                    this.onUnlockSuccess(`Unlocked with ${what}.`);
                    return;
                }
                const input = this.overlay && this.overlay.querySelector('#pc-lock-auth-input');
                if (input) input.value = '';
                feedback(this.unlockRefusedText(res, what), true);
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
                        this.requestUnlock('').then((res) => {
                            if (res.ok) this.onUnlockSuccess('Unlocked with fingerprint.');
                            else resetHold(this.unlockRefusedText(res, 'fingerprint'));
                        });
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
        // the server checks the device is still in the inventory and counts failures towards a lockdown
        const res = await nuiRequest('pc:lock:breach', { scope: this.scope(), tier: detected.tier, success: success === true });
        if (res && res.security) this.applyState(res.security);
        if (res && res.ok) {
            this.onUnlockSuccess(`Breach successful (${detected.tier}).`);
            return;
        }
        if (res && res.error === 'lockdown') {
            feedback(`Lockdown active — ${this.getLockdownRemainingSeconds()}s remaining.`, true);
        } else if (res && res.error === 'missing_tool') {
            feedback('No breach device found in inventory.', true);
        } else {
            feedback(`Hack failed (${Number((res && res.security && res.security.hackFailures) || 0)}).`, true);
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

    // the server has already unlocked; this only puts the lock screen away
    onUnlockSuccess(message) {
        this.lockView = 'idle';
        this.hideOverlay();
        this.hideHackOverlay();
        uiNotify(message, 'success');
    }
}

// (The in-shell City Hall and Businesses copies, all made-up data, were removed: City Hall is
// pf-government's own screen, launched from the computer apps cityhall-admin / cityhall-businesses.)

// (Documents: pf-citizen's platform app; see PLATFORM_HANDOFF)

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

        // Sites published through pf-devices (news.ls and others) render with the same module as
        // on the tablet's browser.
        if (this.platformSiteHost && window.PFApps) {
            window.PFApps.unmountSite(this.platformSiteHost);
            this.platformSiteHost = null;
        }
        if (window.PFComputerPlatform) {
            const site = await window.PFComputerPlatform.findSite(this.getShortDomain(normalizedUrl));
            if (site) {
                content.innerHTML = '';
                const mount = document.createElement('div');
                mount.className = 'pf-site-mount';
                mount.style.height = '100%';
                content.appendChild(mount);
                this.platformSiteHost = site.host;
                await window.PFApps.mountSite(site, mount);
                return;
            }
        }

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
        const featured = Array.isArray(config.featuredSites) ? config.featuredSites.slice() : [];
        // city websites published through pf-devices come first
        if (window.PFComputerPlatform) {
            const sites = await window.PFComputerPlatform.listSites();
            sites.slice().reverse().forEach((site) => {
                if (!featured.some((f) => this.getShortDomain(this.normalizeUrl(f.url)) === site.host)) {
                    featured.unshift({ name: site.name, url: site.host, description: site.description || '' });
                }
            });
        }
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
                                    <span class="dom-registry-owner">Owner: ${esc(domain.ownerName || 'Unknown')}</span>
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
                // the server checks the citizen exists and uses their real name
                const targetIdentifier = (await uiPrompt('Citizen ID (or server ID) of the new owner:', '', {
                    title: 'Transfer Domain',
                    submitLabel: 'Transfer'
                }))?.trim();
                if (!targetIdentifier) return;
                const response = await nuiRequest('pc:browser:transferDomain', {
                    domain: btn.dataset.transferDomain,
                    targetIdentifier
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

// (Mail and Calendar: pf-citizen's platform apps; see PLATFORM_HANDOFF)

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

// (Bills: pf-citizen's platform app; see PLATFORM_HANDOFF)

// (Job Board: pf-computer's own platform app, html/apps/jobboard.js; see PLATFORM_HANDOFF)

// ============================================================================
// TERMINAL APP MANAGER
// ============================================================================
class TerminalManager {
    constructor() {
        this.commandHistory = [];
        this.historyIndex = -1;
        this.currentRoom = 'market';
        this.chatAuthor = 'anon';   // the server's handle replaces it on the first message
        this.darknetMode = scopedStorageGet('terminal_darknet_mode') === 'true';
        this.currentDirectory = '/home/user';
        this.fileSystem = { '/home/user': { 'documents.txt': 'Work files', 'notes.md': 'Personal notes' }, '/etc': { 'config.conf': 'System config' } };
        this.init();
    }

    init() {
        this.renderTerminal();
        this.setupInput();
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
                await this.listChatRooms();
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
            case 'whoami':
                await this.showHandle();
                break;
            case 'rm':
                await this.removeChatMessage(args[0]);
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
  ls/dir       - List chat rooms
  rooms        - List chat rooms
  join <room>  - Join or create a room
  mkroom <r>   - Create a room
  say <msg>    - Post a message
  chatlog      - Show room messages
  whoami       - Your handle (the network gives it to you)
  rm <id>      - Remove a message (staff)
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
        if (result.data?.handle) this.chatAuthor = result.data.handle;
        messages.slice(-6).forEach((msg) => {
            this.addOutput(`#${msg.id} [${msg.author}] ${msg.message}`);
        });
    }

    async postChatMessage(message) {
        if (!message || message.trim() === '') {
            this.addOutput('Usage: say <message>', 'terminal-error');
            return;
        }

        const result = await nuiRequest('pc:postChatMessage', {
            room: this.currentRoom,
            message: message.trim()
        });

        if (result.ok) {
            this.chatAuthor = result.data?.author || this.chatAuthor;
            this.addOutput(`#${result.data?.id} [${this.chatAuthor}] ${result.data?.message || message.trim()}`);
        } else {
            this.addOutput(result.error === 'slow_down' ? 'Slow down.' : 'Failed to send message.', 'terminal-error');
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
            this.addOutput(`#${msg.id} [${msg.author}] ${msg.message}`);
        });
    }

    // The handle is chosen by the server (the same for a character every time), so nobody can post as
    // someone else. The old market, buy, scan, hack and profile commands printed made-up results.
    async showHandle() {
        const result = await nuiRequest('pc:joinChatRoom', { room: this.currentRoom });
        if (result && result.ok && result.data && result.data.handle) {
            this.chatAuthor = result.data.handle;
            this.addOutput(`You are ${result.data.handle}${result.data.moderator ? ' (staff)' : ''}`);
        } else {
            this.addOutput('The network is not answering.', 'terminal-error');
        }
    }

    async removeChatMessage(id) {
        const result = await nuiRequest('pc:deleteChatMessage', { room: this.currentRoom, messageId: Number(id) });
        this.addOutput(result && result.ok ? 'Message removed.' : 'Could not remove that message.', result && result.ok ? 'terminal-success' : 'terminal-error');
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

// (Business Manager and Order Supplies: pf-computer's own platform apps, html/apps/businessmanager.js and
// html/apps/ordersupplies.js, the same modules the tablet runs; see PLATFORM_HANDOFF)

// ============================================================================
// DESKTOP MANAGER - Manages icons, folders, and layout
// ============================================================================
// The desktop layout of each character on each computer is kept on the server (server/profiles.lua);
// the browser cache holds a copy so the desktop draws at once, and a cache from before the server
// kept layouts is sent up the first time.
// The old Business Manager, Order Supplies and Job Board windows are platform apps now: the server
// decides who sees them and they bring their own icons, so their old desktop items are dropped.
const RETIRED_DESKTOP_APPS = new Set(['business-manager', 'order-supplies', 'job-board']);

class DesktopManager {
    constructor() {
        this.items = this.loadItems();
        this.folders = this.loadFolders();
        this.serverSaveTimer = null;
        this.serverSynced = false;   // nothing is sent before the server's layout for this computer is in
        this.init();
    }

    // The layout as the server has it for this computer; a browser cache it has never seen is sent up.
    async syncFromServer() {
        const scope = CURRENT_COMPUTER_BASE_SCOPE || 'default';
        this.serverSynced = false;
        const res = await nuiRequest('pc:profile:get', { scope });
        if (!res || !res.ok || scope !== (CURRENT_COMPUTER_BASE_SCOPE || 'default')) return;
        this.serverSynced = true;
        if (res.security && window.securityManager) window.securityManager.applyState(res.security);
        const layout = res.layout;
        if (layout && Array.isArray(layout.items)) {
            scopedStorageSet('gov_desktop_items', JSON.stringify(layout.items));
            scopedStorageSet('gov_folders', JSON.stringify(Array.isArray(layout.folders) ? layout.folders : []));
            this.items = this.loadItems();
            this.folders = this.loadFolders();
            this.renderDesktop();
        } else if (scopedStorageGet('gov_desktop_items')) {
            this.queueServerSave(0);
        }
    }

    queueServerSave(delay = 800) {
        if (!this.serverSynced) return;
        clearTimeout(this.serverSaveTimer);
        this.serverSaveTimer = setTimeout(() => {
            nuiRequest('pc:profile:saveLayout', { scope: CURRENT_COMPUTER_BASE_SCOPE || 'default', items: this.items, folders: this.folders });
        }, delay);
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
                return Array.isArray(parsedItems)
                    ? parsedItems.map(normalizeDesktopItem).filter((item) => !(item && item.type === 'app' && RETIRED_DESKTOP_APPS.has(resolveAppName(item.app || item.id))))
                    : [];
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
        this.queueServerSave();
    }

    saveFolders() {
        scopedStorageSet('gov_folders', JSON.stringify(this.folders));
        this.queueServerSave();
    }

    reloadForScope() {
        this.items = this.loadItems();
        this.folders = this.loadFolders();
        this.renderDesktop();
        this.syncFromServer();
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
            <div class="icon-label"></div>
        `;
        icon.querySelector('.icon-label').textContent = folder.name || 'New Folder';

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
            <div class="icon-label"></div>
        `;
        icon.querySelector('.icon-label').textContent = item.title || 'Document';

        icon.addEventListener('dblclick', () => {
            if (window.windowManagerInstance) {
                {
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
        clearTimeout(this.serverSaveTimer);
        nuiRequest('pc:profile:resetLayout', { scope: CURRENT_COMPUTER_BASE_SCOPE || 'default' });
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
        clearTimeout(this.serverSaveTimer);
        nuiRequest('pc:profile:resetLayout', { scope: CURRENT_COMPUTER_BASE_SCOPE || 'default' });
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

    // NUI callbacks belong to a resource: the launch request goes to the program's own resource
    // (it used to be posted to pf-computer, so e.g. pf-trucking's program:pf-trucking:open never ran)
    const owner = /^[A-Za-z0-9_-]+$/.test(String(program.resource || '')) ? program.resource : PC_NUI_RESOURCE;
    let launchResult;
    try {
        const response = await fetch(`https://${owner}/program:${encodeURIComponent(program.id)}:open`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify({ programId: program.id, resource: program.resource, playerJob })
        });
        launchResult = await response.json();
    } catch (error) {
        launchResult = { ok: false, error: 'program_unavailable' };
    }

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
                // (Business Manager, Order Supplies and the Job Board are platform apps: the server decides who
                // sees them, and they appear on the desktop by themselves)
                { id: 'minesweeper-classic', label: 'Minesweeper', category: 'games', appId: 'minesweeper', publisher: 'PF Play', price: 'Free', badge: 'Classic', short: 'Flag every mine and clear the field', description: 'Classic Minesweeper with multiple difficulties, timer, and best-time leaderboard.', hero: 'linear-gradient(120deg,#1f3d63,#5a88d7)', screenshots: ['assets/wallpaper_dark.png','assets/wallpaper_light.png','assets/wallpaper.jpg'] },
                { id: 'tetris-classic', label: 'Tetris', category: 'games', appId: 'tetris', publisher: 'PF Play', price: 'Free', badge: 'Arcade', short: 'Stack pieces and clear lines', description: 'Modernized falling-block classic with queue, hold, score, and leaderboard.', hero: 'linear-gradient(120deg,#35145e,#8b5cf6)', screenshots: ['assets/wallpaper_dark.png','assets/wallpaper_light.png','assets/wallpaper.jpg'] },
                { id: 'snake-classic', label: 'Snake', category: 'games', appId: 'snake', publisher: 'PF Play', price: 'Free', badge: 'Arcade', short: 'Grow longer and survive', description: 'Responsive Snake with speed scaling, wall option, and score leaderboard.', hero: 'linear-gradient(120deg,#163d2a,#22c55e)', screenshots: ['assets/wallpaper_dark.png','assets/wallpaper_light.png','assets/wallpaper.jpg'] },
                { id: 'pong-classic', label: 'Pong', category: 'games', appId: 'pong', publisher: 'PF Play', price: 'Free', badge: 'Arcade', short: 'Classic paddle duel', description: 'Single-player Pong with AI difficulty, score tracking, and leaderboard.', hero: 'linear-gradient(120deg,#14233e,#38bdf8)', screenshots: ['assets/wallpaper_dark.png','assets/wallpaper_light.png','assets/wallpaper.jpg'] },
                { id: 'flappy-bird-classic', label: 'Flappy Bird', category: 'games', appId: 'flappy', publisher: 'PF Play', price: 'Free', badge: 'Arcade', short: 'Tap through the pipes', description: 'Pipe-dodging challenge with best score leaderboard and polished UI.', hero: 'linear-gradient(120deg,#275a15,#84cc16)', screenshots: ['assets/wallpaper_dark.png','assets/wallpaper_light.png','assets/wallpaper.jpg'] }
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
    return this.renderShell(`<section class="settings-page-block"><div class="settings-page-heading windows-main-title"><h2>Lock screen</h2></div><section class="settings-card settings-card-wide"><label class="settings-toggle-row"><span><strong>Enable lock screen</strong><small>Require sign-in when this PC is locked</small></span><input type="checkbox" id="security-lockscreen-enabled" ${enabled?'checked':''}></label><div class="setting-group"><label>Sign-in option</label><select class="settings-select" id="security-unlock-method"><option value="password" ${method==='password'?'selected':''}>Password</option><option value="pin" ${method==='pin'?'selected':''}>PIN</option><option value="fingerprint" ${method==='fingerprint'?'selected':''}>Fingerprint</option></select></div><div class="setting-group"><label>Password</label><input class="settings-input" type="password" id="security-password" value="" autocomplete="off" placeholder="${this.settings.securityHasPassword ? 'Set: type a new one to change it' : 'Password'}"></div><div class="setting-group"><label>PIN</label><input class="settings-input" type="password" id="security-pin" value="" autocomplete="off" placeholder="${this.settings.securityHasPin ? 'Set: type a new one to change it' : 'PIN (4 to 8 digits)'}"></div><label class="settings-toggle-row"><span><strong>Lockdown mode</strong><small>Enter lockdown after repeated failed sign-in attempts</small></span><input type="checkbox" id="security-lockdown-on-hack-fail" ${this.settings.securityLockdownOnHackFail?'checked':''}></label><div class="setting-group"><label>Failed tries until lockdown</label><input class="settings-input" type="number" min="1" max="10" id="security-lockdown-threshold" value="${this.settings.securityLockdownThreshold || 3}"></div><div class="setting-group"><label>Lockdown password</label><input class="settings-input" type="password" id="security-lockdown-password" value="" autocomplete="off" placeholder="${this.settings.securityHasLockdownPassword ? 'Set: type a new one to change it' : 'Required to exit lockdown'}"></div><button class="btn-primary" id="save-privacy-lockscreen" type="button">Apply</button></section></section>`, ['Privacy & Security','Lock screen']);
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
    const settingsManager = new SettingsManager(themeManager);
    window.settingsManager = settingsManager;
    const startMenu = new StartMenu(windowManager);
    const powerMenu = new PowerMenu();
    window.securityManager = new SecurityManager();
    
    // Initialize new app managers
    console.log('Creating app managers...');
    window.browserManager = new BrowserManager();
    console.log('- BrowserManager created');
    window.mapsManager = new MapsManager();
    console.log('- MapsManager created');
    window.terminalManager = new TerminalManager();
    console.log('- TerminalManager created');
    window.calculatorManager = new CalculatorManager();
    console.log('- CalculatorManager created');
    
    // Initialize system managers
    console.log('Creating system managers...');
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
            if (window.securityManager) window.securityManager.resetSettings();
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
            // a program the server allowed on this computer (e.g. City Hall from the computer apps) may
            // not be in this computer profile's list: make its window from the program the client sent
            const p = data.program;
            if (p && p.id === data.programId && typeof p.url === 'string' && /^https:\/\/cfx-nui-[A-Za-z0-9_-]+\//.test(p.url)
                && !window.windowManagerInstance.windows.has(p.id)) {
                createExternalProgramWindow(p, window.windowManagerInstance);
            }
            window.windowManagerInstance.openWindow(data.programId);
        }
    } else if (data.action === 'closeExternalProgram' && data.programId) {
        if (window.windowManagerInstance) {
            window.windowManagerInstance.closeWindow(data.programId);
        }
    }
    // (job changes: pf-devices refreshes the platform apps' list and the apps reload themselves)
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
