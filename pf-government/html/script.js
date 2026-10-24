// Lockscreen Management
class LockscreenManager {
    constructor() {
        this.lockscreen = document.getElementById('lockscreen');
        this.passwordInput = document.getElementById('password-input');
        this.loginBtn = document.getElementById('login-btn');
        this.loginError = document.getElementById('login-error');
        this.lockscreenTime = document.getElementById('lockscreen-time');
        this.lockscreenDate = document.getElementById('lockscreen-date');
        this.isLocked = true;
        
        // Default password (can be changed in settings)
        this.password = localStorage.getItem('systemPassword') || '';
        
        this.init();
    }

    init() {
        // Check if lockscreen should be shown
        const authEnabled = localStorage.getItem('authEnabled') !== 'false';
        
        if (!authEnabled || this.password === '') {
            this.unlock();
            return;
        }

        // Show lockscreen
        this.show();

        // Login button click
        this.loginBtn.addEventListener('click', () => this.attemptLogin());

        // Enter key in password field
        this.passwordInput.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') {
                this.attemptLogin();
            }
        });

        // Update lockscreen time
        this.updateLockscreenTime();
        setInterval(() => this.updateLockscreenTime(), 1000);
    }

    show() {
        this.lockscreen.classList.remove('hidden');
        this.isLocked = true;
        this.passwordInput.value = '';
        this.loginError.textContent = '';
        setTimeout(() => this.passwordInput.focus(), 100);
    }

    hide() {
        this.lockscreen.classList.add('hidden');
        this.isLocked = false;
    }

    attemptLogin() {
        const enteredPassword = this.passwordInput.value;

        if (enteredPassword === this.password) {
            this.loginError.textContent = '';
            this.unlock();
        } else {
            this.loginError.textContent = 'Incorrect password';
            this.passwordInput.value = '';
            this.passwordInput.focus();
            
            // Shake animation
            this.passwordInput.style.animation = 'shake 0.5s';
            setTimeout(() => {
                this.passwordInput.style.animation = '';
            }, 500);
        }
    }

    unlock() {
        this.hide();
        // Set session flag
        sessionStorage.setItem('sessionActive', 'true');
    }

    lock() {
        this.show();
        sessionStorage.removeItem('sessionActive');
    }

    updateLockscreenTime() {
        const now = new Date();
        const timeFormat = localStorage.getItem('timeFormat') || '12';
        
        let hours = now.getHours();
        let minutes = now.getMinutes();
        
        if (timeFormat === '12') {
            const ampm = hours >= 12 ? 'PM' : 'AM';
            hours = hours % 12;
            hours = hours || 12;
            this.lockscreenTime.textContent = `${hours}:${minutes.toString().padStart(2, '0')}`;
        } else {
            this.lockscreenTime.textContent = `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}`;
        }

        const options = { weekday: 'long', month: 'long', day: 'numeric' };
        this.lockscreenDate.textContent = now.toLocaleDateString('en-US', options);
    }

    setPassword(newPassword) {
        this.password = newPassword;
        localStorage.setItem('systemPassword', newPassword);
    }
}

const GOV_NUI_RESOURCE = (typeof GetParentResourceName === 'function')
    ? GetParentResourceName()
    : 'pf-government';

const GOV_NUI_FALLBACK_RESOURCES = ['pf-government', 'pf-governmentuionly'];
const GOV_URL = new URL(window.location.href);
const GOV_EMBEDDED_MODE = GOV_URL.searchParams.get('embedded') === '1';
const GOV_EMBEDDED_APP = GOV_URL.searchParams.get('app') || 'city-hall';
const GOV_EMBEDDED_PROGRAM_ID = GOV_URL.searchParams.get('programId') || 'pf-government-city-hall';

function closeGovernmentUi() {
    if (GOV_EMBEDDED_MODE) {
        if (window.parent && window.parent !== window) {
            window.parent.postMessage({
                action: 'pf-computer:closeExternalProgram',
                programId: GOV_EMBEDDED_PROGRAM_ID
            }, '*');
        }

        return Promise.resolve({ ok: true });
    }

    return nuiRequest('closeUI', { programId: GOV_EMBEDDED_PROGRAM_ID });
}

async function nuiRequest(event, data) {
    try {
        const response = await fetch(`https://${GOV_NUI_RESOURCE}/${event}`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json; charset=UTF-8'
            },
            body: JSON.stringify(data || {})
        });
        return await response.json();
    } catch (error) {
        for (const fallbackResource of GOV_NUI_FALLBACK_RESOURCES) {
            if (!fallbackResource || fallbackResource === GOV_NUI_RESOURCE) continue;
            try {
                const fallbackResponse = await fetch(`https://${fallbackResource}/${event}`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json; charset=UTF-8'
                    },
                    body: JSON.stringify(data || {})
                });
                return await fallbackResponse.json();
            } catch (fallbackError) {
                console.warn('NUI fallback failed:', event, fallbackResource, fallbackError);
            }
        }

        console.error('NUI request failed:', event, error);
        return { ok: false, error: 'nui_request_failed' };
    }
}

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        closeGovernmentUi();
    }
});

// Window Management
class WindowManager {
    constructor() {
        this.windows = new Map();
        this.activeWindow = null;
        this.zIndex = 100;
        this.init();
    }

    init() {
        // Initialize all windows first
        const windowElements = document.querySelectorAll('.window');
        console.log('Found windows:', windowElements.length);
        windowElements.forEach(win => {
            this.initWindow(win);
        });

        // Initialize desktop icons after windows are ready
        const iconElements = document.querySelectorAll('.icon');
        console.log('Found desktop icons:', iconElements.length);
        iconElements.forEach(icon => {
            console.log('Setting up icon:', icon.dataset.app);

            // Single click opens app and selects icon
            icon.addEventListener('click', (e) => {
                e.preventDefault();
                e.stopPropagation();
                const appName = icon.dataset.app;

                // Remove selection from other icons
                document.querySelectorAll('.icon').forEach(i => i.classList.remove('selected'));
                icon.classList.add('selected');

                console.log('Opening app from icon:', appName);
                this.openWindow(appName);
            });
        });

        // Robust fallback: event delegation for icons
        document.addEventListener('click', (e) => {
            const icon = e.target.closest('.icon');
            if (!icon) return;

            e.preventDefault();
            e.stopPropagation();
            const appName = icon.dataset.app;

            document.querySelectorAll('.icon').forEach(i => i.classList.remove('selected'));
            icon.classList.add('selected');

            console.log('Opening app from delegated icon:', appName);
            this.openWindow(appName);
        });

        console.log('Windows initialized:', Array.from(this.windows.keys()));

        // Update time
        this.updateDateTime();
        setInterval(() => this.updateDateTime(), 1000);
    }

    initWindow(windowElement) {
        const appName = windowElement.dataset.app;
        
        // Close button
        const closeBtn = windowElement.querySelector('.close');
        closeBtn.addEventListener('click', () => this.closeWindow(appName));

        // Minimize button
        const minimizeBtn = windowElement.querySelector('.minimize');
        minimizeBtn.addEventListener('click', () => this.minimizeWindow(appName));

        // Maximize button
        const maximizeBtn = windowElement.querySelector('.maximize');
        maximizeBtn.addEventListener('click', () => this.toggleMaximize(appName));

        // Make window draggable
        this.makeDraggable(windowElement);

        // Make window resizable
        this.makeResizable(windowElement);

        // Make window active on click
        windowElement.addEventListener('mousedown', () => {
            this.setActiveWindow(appName);
        });

        this.windows.set(appName, {
            element: windowElement,
            isMaximized: false,
            previousPosition: { top: 0, left: 0, width: 0, height: 0 }
        });
    }

    openWindow(appName) {
        console.log('openWindow called for:', appName);
        console.log('Available windows:', Array.from(this.windows.keys()));
        
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
            const defaultWidth = 900;
            const defaultHeight = 620;
            const maxWidth = window.innerWidth - 80;
            const maxHeight = window.innerHeight - 120;

            const appliedWidth = Math.max(520, Math.min(defaultWidth, maxWidth));
            const appliedHeight = Math.max(360, Math.min(defaultHeight, maxHeight));

            windowElement.style.width = `${appliedWidth}px`;
            windowElement.style.height = `${appliedHeight}px`;

            windowElement.style.left = `${(window.innerWidth - appliedWidth) / 2}px`;
            windowElement.style.top = `${(window.innerHeight - 48 - appliedHeight) / 2}px`;
            console.log('Centered window at:', windowElement.style.left, windowElement.style.top);
        }

        this.setActiveWindow(appName);
        if (appName === 'browser' && window.mayorBrowser && typeof window.mayorBrowser.onOpen === 'function') {
            window.mayorBrowser.onOpen();
        }
        this.updateTaskbar();
        console.log('Window opened successfully');
    }

    closeWindow(appName) {
        const windowData = this.windows.get(appName);
        if (!windowData) return;

        windowData.element.style.display = 'none';
        windowData.element.classList.remove('active', 'minimized', 'maximized');
        
        if (this.activeWindow === appName) {
            this.activeWindow = null;
        }

        this.updateTaskbar();
    }

    minimizeWindow(appName) {
        const windowData = this.windows.get(appName);
        if (!windowData) return;

        windowData.element.classList.add('minimized');
        
        if (this.activeWindow === appName) {
            this.activeWindow = null;
        }

        this.updateTaskbar();
    }

    toggleMaximize(appName) {
        const windowData = this.windows.get(appName);
        if (!windowData) return;

        const windowElement = windowData.element;

        if (windowData.isMaximized) {
            // Restore
            windowElement.classList.remove('maximized');
            windowElement.style.top = windowData.previousPosition.top + 'px';
            windowElement.style.left = windowData.previousPosition.left + 'px';
            windowElement.style.width = windowData.previousPosition.width + 'px';
            windowElement.style.height = windowData.previousPosition.height + 'px';
            windowData.isMaximized = false;
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
        }
    }

    setActiveWindow(appName) {
        // Remove active from all windows
        this.windows.forEach((data, name) => {
            data.element.classList.remove('active');
        });

        const windowData = this.windows.get(appName);
        if (!windowData) return;

        windowData.element.classList.add('active');
        windowData.element.style.zIndex = ++this.zIndex;
        this.activeWindow = appName;

        this.updateTaskbar();
    }

    makeDraggable(windowElement) {
        const header = windowElement.querySelector('.window-header');
        let isDragging = false;
        let currentX;
        let currentY;
        let initialX;
        let initialY;

        header.addEventListener('mousedown', (e) => {
            // Don't drag if clicking on window control buttons
            if (e.target.classList.contains('window-btn')) return;
            
            // Don't drag if maximized
            const appName = windowElement.dataset.app;
            const windowData = this.windows.get(appName);
            if (windowData && windowData.isMaximized) return;

            isDragging = true;
            initialX = e.clientX - (parseInt(windowElement.style.left) || windowElement.offsetLeft);
            initialY = e.clientY - (parseInt(windowElement.style.top) || windowElement.offsetTop);
        });

        document.addEventListener('mousemove', (e) => {
            if (!isDragging) return;

            e.preventDefault();
            currentX = e.clientX - initialX;
            currentY = e.clientY - initialY;

            // Keep window in bounds
            const maxX = window.innerWidth - 100;
            const maxY = window.innerHeight - 100;

            currentX = Math.max(0, Math.min(currentX, maxX));
            currentY = Math.max(0, Math.min(currentY, maxY));

            windowElement.style.left = currentX + 'px';
            windowElement.style.top = currentY + 'px';
        });

        document.addEventListener('mouseup', () => {
            isDragging = false;
        });
    }

    makeResizable(windowElement) {
        // Add resize handles
        const resizeRight = document.createElement('div');
        resizeRight.className = 'resize-handle resize-right';
        windowElement.appendChild(resizeRight);

        const resizeBottom = document.createElement('div');
        resizeBottom.className = 'resize-handle resize-bottom';
        windowElement.appendChild(resizeBottom);

        const resizeCorner = document.createElement('div');
        resizeCorner.className = 'resize-handle resize-corner';
        windowElement.appendChild(resizeCorner);

        // Right resize
        this.initResize(windowElement, resizeRight, 'right');
        
        // Bottom resize
        this.initResize(windowElement, resizeBottom, 'bottom');
        
        // Corner resize
        this.initResize(windowElement, resizeCorner, 'corner');
    }

    initResize(windowElement, handle, direction) {
        let isResizing = false;
        let startX, startY, startWidth, startHeight, startLeft, startTop;

        handle.addEventListener('mousedown', (e) => {
            e.stopPropagation();
            isResizing = true;
            startX = e.clientX;
            startY = e.clientY;
            startWidth = parseInt(window.getComputedStyle(windowElement).width, 10);
            startHeight = parseInt(window.getComputedStyle(windowElement).height, 10);
            startLeft = windowElement.offsetLeft;
            startTop = windowElement.offsetTop;
        });

        document.addEventListener('mousemove', (e) => {
            if (!isResizing) return;

            if (direction === 'right' || direction === 'corner') {
                const newWidth = startWidth + (e.clientX - startX);
                if (newWidth > 400) {
                    windowElement.style.width = newWidth + 'px';
                }
            }

            if (direction === 'bottom' || direction === 'corner') {
                const newHeight = startHeight + (e.clientY - startY);
                if (newHeight > 300) {
                    windowElement.style.height = newHeight + 'px';
                }
            }
        });

        document.addEventListener('mouseup', () => {
            isResizing = false;
        });
    }

    updateTaskbar() {
        const taskbarApps = document.querySelector('.taskbar-apps');
        taskbarApps.innerHTML = '';

        this.windows.forEach((data, appName) => {
            // Only show apps that are open (not closed completely)
            if (data.element.style.display === 'none') return;

            const taskbarApp = document.createElement('div');
            taskbarApp.className = 'taskbar-app';
            if (this.activeWindow === appName && !data.element.classList.contains('minimized')) {
                taskbarApp.classList.add('active');
            }

            const icon = data.element.querySelector('.window-icon').textContent;
            const title = data.element.querySelector('.window-title span').textContent;

            taskbarApp.innerHTML = `
                <span>${icon}</span>
                <span>${title}</span>
            `;

            taskbarApp.addEventListener('click', () => {
                if (data.element.classList.contains('minimized')) {
                    // Restore from minimized
                    data.element.classList.remove('minimized');
                    this.setActiveWindow(appName);
                } else if (this.activeWindow === appName) {
                    // Minimize if already active
                    this.minimizeWindow(appName);
                } else {
                    // Bring to front
                    this.setActiveWindow(appName);
                }
            });

            taskbarApps.appendChild(taskbarApp);
        });
    }

    updateDateTime() {
        const now = new Date();
        const timeElement = document.querySelector('.time');
        const dateElement = document.querySelector('.date');

        // Get time format preference
        const timeFormat = localStorage.getItem('timeFormat') || '12-hour';
        
        // Format time
        let hours = now.getHours();
        const minutes = now.getMinutes().toString().padStart(2, '0');
        
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
    }
}

// Theme Management
class ThemeManager {
    constructor() {
        this.currentTheme = localStorage.getItem('theme') || 'light';
        this.currentBackground = localStorage.getItem('background') || 'Default Gradient';
        this.apply();
        this.applyBackground();
    }

    setTheme(theme) {
        this.currentTheme = theme;
        localStorage.setItem('theme', theme);
        this.apply();
    }

    setBackground(background) {
        this.currentBackground = background;
        localStorage.setItem('background', background);
        this.applyBackground();
    }

    apply() {
        document.body.setAttribute('data-theme', this.currentTheme);
        console.log('Applied theme:', this.currentTheme);
    }

    applyBackground() {
        const desktop = document.querySelector('.desktop');
        if (!desktop) return;

        // Check for custom color first
        const customColor = localStorage.getItem('customBackgroundColor');
        if (customColor) {
            desktop.style.background = customColor;
            console.log('Applied custom background color:', customColor);
            return;
        }

        const backgrounds = {
            'Default Gradient': 'linear-gradient(135deg, #0078d4 0%, #0063b1 100%)',
            'Blue': 'linear-gradient(135deg, #2193b0 0%, #6dd5ed 100%)',
            'Purple': 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
            'Custom': 'linear-gradient(135deg, #f093fb 0%, #f5576c 100%)'
        };

        desktop.style.background = backgrounds[this.currentBackground] || backgrounds['Default Gradient'];
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
        this.settings = {
            language: localStorage.getItem('language') || 'English',
            timeFormat: localStorage.getItem('timeFormat') || '12-hour',
            soundEffects: localStorage.getItem('soundEffects') !== 'false',
            animations: localStorage.getItem('animations') !== 'false',
            notifications: localStorage.getItem('notifications') !== 'false',
            notificationSound: localStorage.getItem('notificationSound') !== 'false',
            showPreviews: localStorage.getItem('showPreviews') === 'true',
            saveHistory: localStorage.getItem('saveHistory') !== 'false',
            shareData: localStorage.getItem('shareData') === 'true'
        };
        this.init();
    }

    init() {
        const navItems = document.querySelectorAll('.settings-nav-item');
        const settingsMain = document.querySelector('.settings-main');

        navItems.forEach(item => {
            item.addEventListener('click', () => {
                // Remove active from all
                navItems.forEach(nav => nav.classList.remove('active'));
                // Add active to clicked
                item.classList.add('active');

                // Update main content
                const section = item.textContent;
                this.loadSettingsSection(section, settingsMain);
            });
        });
    }

    saveSetting(key, value) {
        this.settings[key] = value;
        localStorage.setItem(key, value);
        console.log(`Saved ${key}:`, value);
    }

    loadSettingsSection(section, container) {
        const sections = {
            'General': `
                <h2>General Settings</h2>
                <div class="setting-group">
                    <label>Language</label>
                    <select class="setting-select" id="language-select">
                        <option ${this.settings.language === 'English' ? 'selected' : ''}>English</option>
                        <option ${this.settings.language === 'Spanish' ? 'selected' : ''}>Spanish</option>
                        <option ${this.settings.language === 'French' ? 'selected' : ''}>French</option>
                    </select>
                </div>
                <div class="setting-group">
                    <label>Time Format</label>
                    <select class="setting-select" id="timeformat-select">
                        <option ${this.settings.timeFormat === '12-hour' ? 'selected' : ''}>12-hour</option>
                        <option ${this.settings.timeFormat === '24-hour' ? 'selected' : ''}>24-hour</option>
                    </select>
                </div>
                <div class="setting-group">
                    <label>
                        <input type="checkbox" id="sound-effects" ${this.settings.soundEffects ? 'checked' : ''}> Enable Sound Effects
                    </label>
                </div>
                <div class="setting-group">
                    <label>
                        <input type="checkbox" id="animations" ${this.settings.animations ? 'checked' : ''}> Enable Animations
                    </label>
                </div>
                <button class="btn-primary" id="save-general">Save Settings</button>
            `,
            'Appearance': `
                <h2>Appearance</h2>
                <div class="setting-group">
                    <label>Theme</label>
                    <select class="setting-select" id="theme-select">
                        <option value="light" ${this.themeManager.currentTheme === 'light' ? 'selected' : ''}>Light</option>
                        <option value="dark" ${this.themeManager.currentTheme === 'dark' ? 'selected' : ''}>Dark</option>
                    </select>
                </div>
                
                <div class="setting-group">
                    <label>Desktop Wallpaper</label>
                    <select class="setting-select" id="wallpaper-type-select">
                        <option value="gradient" ${!localStorage.getItem('customWallpaper') ? 'selected' : ''}>Gradient</option>
                        <option value="image" ${localStorage.getItem('customWallpaper') ? 'selected' : ''}>Custom Image</option>
                    </select>
                </div>
                
                <div class="setting-group" id="gradient-wallpaper-options">
                    <label>Gradient Preset</label>
                    <select class="setting-select" id="gradient-select">
                        <option value="default">Default Blue</option>
                        <option value="purple">Purple Dream</option>
                        <option value="sunset">Sunset Orange</option>
                        <option value="forest">Forest Green</option>
                    </select>
                </div>
                
                <div class="setting-group" id="custom-wallpaper-options" style="display: ${localStorage.getItem('customWallpaper') ? 'block' : 'none'};">
                    <label>Wallpaper Image URL</label>
                    <input type="text" id="wallpaper-url" class="setting-input" placeholder="https://example.com/image.jpg OR https://i.imgur.com/example.png?w=1920&h=1080" value="${localStorage.getItem('customWallpaper') || ''}">
                    <small style="color: var(--text-muted); font-size: 11px; display: block; margin-top: 6px;">
                        Supports: JPG, PNG, WEBP, GIF. Resize parameters in URL (e.g., ?w=1920&h=1080) are preserved.
                    </small>
                    <button class="btn-secondary" id="preview-wallpaper" style="margin-top: 8px;">Preview</button>
                </div>
                
                <div class="setting-group">
                    <label>Background Type (Deprecated)</label>
                    <select class="setting-select" id="background-type-select">
                        <option value="gradient" ${!localStorage.getItem('customBackgroundColor') ? 'selected' : ''}>Gradient</option>
                        <option value="custom" ${localStorage.getItem('customBackgroundColor') ? 'selected' : ''}>Custom Color</option>
                    </select>
                </div>
                <div class="setting-group" id="gradient-options">
                    <label>Gradient</label>
                    <select class="setting-select" id="background-select">
                        <option ${this.themeManager.currentBackground === 'Default Gradient' ? 'selected' : ''}>Default Gradient</option>
                        <option ${this.themeManager.currentBackground === 'Blue' ? 'selected' : ''}>Blue</option>
                        <option ${this.themeManager.currentBackground === 'Purple' ? 'selected' : ''}>Purple</option>
                        <option ${this.themeManager.currentBackground === 'Custom' ? 'selected' : ''}>Custom</option>
                    </select>
                </div>
                <div class="setting-group" id="custom-color-options" style="display: none;">
                    <label>Custom Background Color</label>
                    <input type="color" id="custom-bg-color" value="${localStorage.getItem('customBackgroundColor') || '#0078d4'}" class="color-picker">
                </div>
                <button class="btn-primary" id="save-appearance">Apply Changes</button>
            `,
            'Security': `
                <h2>Security</h2>
                <div class="setting-group">
                    <label>
                        <input type="checkbox" id="enable-auth" ${localStorage.getItem('authEnabled') !== 'false' ? 'checked' : ''}> Enable Lockscreen
                    </label>
                </div>
                <div class="setting-group">
                    <label>Password</label>
                    <input type="password" id="system-password" class="setting-input" placeholder="Enter password" value="${localStorage.getItem('systemPassword') || ''}">
                    <small>Leave blank for no password protection</small>
                </div>
                <div class="setting-group">
                    <label>Confirm Password</label>
                    <input type="password" id="confirm-password" class="setting-input" placeholder="Confirm password">
                </div>
                <button class="btn-primary" id="save-security">Save Security Settings</button>
            `,
            'Notifications': `
                <h2>Notifications</h2>
                <div class="setting-group">
                    <label>
                        <input type="checkbox" id="enable-notifications" ${this.settings.notifications ? 'checked' : ''}> Enable Notifications
                    </label>
                </div>
                <div class="setting-group">
                    <label>
                        <input type="checkbox" id="notification-sound" ${this.settings.notificationSound ? 'checked' : ''}> Play Sound
                    </label>
                </div>
                <div class="setting-group">
                    <label>
                        <input type="checkbox" id="show-previews" ${this.settings.showPreviews ? 'checked' : ''}> Show Previews
                    </label>
                </div>
                <button class="btn-primary" id="save-notifications">Save Settings</button>
            `,
            'Privacy': `
                <h2>Privacy</h2>
                <div class="setting-group">
                    <label>
                        <input type="checkbox" id="save-history" ${this.settings.saveHistory ? 'checked' : ''}> Save Activity History
                    </label>
                </div>
                <div class="setting-group">
                    <label>
                        <input type="checkbox" id="share-data" ${this.settings.shareData ? 'checked' : ''}> Share Usage Data
                    </label>
                </div>
                <button class="btn-primary" id="save-privacy">Save Settings</button>
            `,
            'About': `
                <h2>About</h2>
                <div class="setting-group">
                    <p><strong>Government UI System</strong></p>
                    <p>Version 1.0.0</p>
                    <p>© 2026 FiveM Server</p>
                </div>
                <div class="setting-group">
                    <p>A modern Windows-like interface for government services.</p>
                </div>
            `
        };

        container.innerHTML = sections[section] || sections['General'];

        // Add event listeners after rendering
        this.attachSettingsHandlers(section);
    }

    attachSettingsHandlers(section) {
        if (section === 'Appearance') {
            const themeSelect = document.getElementById('theme-select');
            const wallpaperTypeSelect = document.getElementById('wallpaper-type-select');
            const gradientWallpaperOptions = document.getElementById('gradient-wallpaper-options');
            const customWallpaperOptions = document.getElementById('custom-wallpaper-options');
            const gradientSelect = document.getElementById('gradient-select');
            const wallpaperUrlInput = document.getElementById('wallpaper-url');
            const previewWallpaperBtn = document.getElementById('preview-wallpaper');
            const backgroundTypeSelect = document.getElementById('background-type-select');
            const backgroundSelect = document.getElementById('background-select');
            const customColorPicker = document.getElementById('custom-bg-color');
            const gradientOptions = document.getElementById('gradient-options');
            const customColorOptions = document.getElementById('custom-color-options');
            const saveBtn = document.getElementById('save-appearance');
            
            if (themeSelect) {
                // Apply theme immediately on change
                themeSelect.addEventListener('change', (e) => {
                    this.themeManager.setTheme(e.target.value);
                });
            }

            // Wallpaper handlers
            if (wallpaperTypeSelect) {
                wallpaperTypeSelect.addEventListener('change', (e) => {
                    if (e.target.value === 'gradient') {
                        gradientWallpaperOptions.style.display = 'block';
                        customWallpaperOptions.style.display = 'none';
                        localStorage.removeItem('customWallpaper');
                        this.applyGradientWallpaper(gradientSelect.value);
                    } else {
                        gradientWallpaperOptions.style.display = 'none';
                        customWallpaperOptions.style.display = 'block';
                    }
                });
            }

            if (gradientSelect) {
                gradientSelect.addEventListener('change', (e) => {
                    this.applyGradientWallpaper(e.target.value);
                });
            }

            if (previewWallpaperBtn) {
                previewWallpaperBtn.addEventListener('click', () => {
                    const url = wallpaperUrlInput.value.trim();
                    if (url) {
                        this.applyCustomWallpaper(url);
                        this.showNotification('Wallpaper preview applied!');
                    } else {
                        this.showNotification('Please enter a valid image URL');
                    }
                });
            }

            if (backgroundTypeSelect) {
                backgroundTypeSelect.addEventListener('change', (e) => {
                    if (e.target.value === 'gradient') {
                        gradientOptions.style.display = 'block';
                        customColorOptions.style.display = 'none';
                        localStorage.removeItem('customBackgroundColor');
                        this.themeManager.applyBackground();
                    } else {
                        gradientOptions.style.display = 'none';
                        customColorOptions.style.display = 'block';
                    }
                });

                // Set initial visibility
                if (backgroundTypeSelect.value === 'custom') {
                    gradientOptions.style.display = 'none';
                    customColorOptions.style.display = 'block';
                }
            }
            
            if (backgroundSelect) {
                // Apply background immediately on change
                backgroundSelect.addEventListener('change', (e) => {
                    this.themeManager.setBackground(e.target.value);
                });
            }

            if (customColorPicker) {
                customColorPicker.addEventListener('input', (e) => {
                    const color = e.target.value;
                    localStorage.setItem('customBackgroundColor', color);
                    document.querySelector('.desktop').style.background = color;
                });
            }
            
            if (saveBtn) {
                saveBtn.addEventListener('click', () => {
                    const wallpaperUrl = wallpaperUrlInput?.value.trim();
                    if (wallpaperTypeSelect.value === 'image' && wallpaperUrl) {
                        localStorage.setItem('customWallpaper', wallpaperUrl);
                        this.applyCustomWallpaper(wallpaperUrl);
                        this.showNotification('Wallpaper saved!');
                    } else if (wallpaperTypeSelect.value === 'gradient') {
                        this.showNotification('Gradient wallpaper applied!');
                    } else {
                        this.showNotification('Appearance settings saved!');
                    }
                });
            }
        } else if (section === 'Security') {
            const saveBtn = document.getElementById('save-security');
            if (saveBtn) {
                saveBtn.addEventListener('click', () => {
                    const enableAuth = document.getElementById('enable-auth')?.checked;
                    const password = document.getElementById('system-password')?.value;
                    const confirmPassword = document.getElementById('confirm-password')?.value;

                    if (password !== confirmPassword) {
                        this.showNotification('Passwords do not match!');
                        return;
                    }

                    localStorage.setItem('authEnabled', enableAuth);
                    
                    if (password) {
                        if (window.lockscreenManager) {
                            window.lockscreenManager.setPassword(password);
                        }
                        this.showNotification('Security settings saved! Password updated.');
                    } else {
                        localStorage.setItem('systemPassword', '');
                        this.showNotification('Security settings saved! Password cleared.');
                    }

                    // Clear password fields
                    document.getElementById('system-password').value = '';
                    document.getElementById('confirm-password').value = '';
                });
            }
        } else if (section === 'General') {
            const saveBtn = document.getElementById('save-general');
            if (saveBtn) {
                saveBtn.addEventListener('click', () => {
                    const language = document.getElementById('language-select')?.value;
                    const timeFormat = document.getElementById('timeformat-select')?.value;
                    const soundEffects = document.getElementById('sound-effects')?.checked;
                    const animations = document.getElementById('animations')?.checked;
                    
                    if (language) this.saveSetting('language', language);
                    if (timeFormat) {
                        this.saveSetting('timeFormat', timeFormat);
                        // Update clock immediately
                        const windowManager = window.windowManagerInstance;
                        if (windowManager) windowManager.updateDateTime();
                    }
                    if (soundEffects !== undefined) this.saveSetting('soundEffects', soundEffects);
                    if (animations !== undefined) {
                        this.saveSetting('animations', animations);
                        document.body.style.setProperty('--animation-enabled', animations ? 'all' : 'none');
                    }
                    
                    this.showNotification('General settings saved!');
                });
            }
        } else if (section === 'Notifications') {
            const saveBtn = document.getElementById('save-notifications');
            if (saveBtn) {
                saveBtn.addEventListener('click', () => {
                    const notifications = document.getElementById('enable-notifications')?.checked;
                    const notificationSound = document.getElementById('notification-sound')?.checked;
                    const showPreviews = document.getElementById('show-previews')?.checked;
                    
                    if (notifications !== undefined) this.saveSetting('notifications', notifications);
                    if (notificationSound !== undefined) this.saveSetting('notificationSound', notificationSound);
                    if (showPreviews !== undefined) this.saveSetting('showPreviews', showPreviews);
                    
                    this.showNotification('Notification settings saved!');
                });
            }
        } else if (section === 'Privacy') {
            const saveBtn = document.getElementById('save-privacy');
            if (saveBtn) {
                saveBtn.addEventListener('click', () => {
                    const saveHistory = document.getElementById('save-history')?.checked;
                    const shareData = document.getElementById('share-data')?.checked;
                    
                    if (saveHistory !== undefined) this.saveSetting('saveHistory', saveHistory);
                    if (shareData !== undefined) this.saveSetting('shareData', shareData);
                    
                    this.showNotification('Privacy settings saved!');
                });
            }
        }
    }

    applyGradientWallpaper(gradient) {
        const desktop = document.querySelector('.desktop');
        const gradients = {
            'default': 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
            'purple': 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
            'sunset': 'linear-gradient(135deg, #fa709a 0%, #fee140 100%)',
            'forest': 'linear-gradient(135deg, #0ba360 0%, #3cba92 100%)'
        };
        
        const gradientValue = gradients[gradient] || gradients['default'];
        desktop.style.background = gradientValue;
        desktop.style.backgroundSize = 'cover';
        localStorage.setItem('wallpaperGradient', gradient);
    }

    applyCustomWallpaper(url) {
        const desktop = document.querySelector('.desktop');
        desktop.style.background = `url('${url}') center/cover no-repeat`;
        desktop.style.backgroundSize = 'cover';
        desktop.style.backgroundPosition = 'center';
        desktop.style.backgroundRepeat = 'no-repeat';
    }

    showNotification(message) {
        // Create a simple notification
        const notification = document.createElement('div');
        notification.className = 'notification';
        notification.textContent = message;
        document.body.appendChild(notification);
        
        setTimeout(() => {
            notification.classList.add('show');
        }, 10);
        
        setTimeout(() => {
            notification.classList.remove('show');
            setTimeout(() => notification.remove(), 300);
        }, 2000);
    }
}

// Start Menu Management
class StartMenu {
    constructor(windowManager) {
        this.windowManager = windowManager;
        this.startMenu = document.getElementById('start-menu');
        this.startButton = document.getElementById('start-button');
        this.searchBox = document.querySelector('.search-input-box');
        this.isOpen = false;
        this.init();
    }

    init() {
        // Toggle start menu on button click
        this.startButton.addEventListener('click', (e) => {
            e.stopPropagation();
            this.toggle();
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

        // Open start menu if searching
        if (normalizedSearch && !this.isOpen) {
            this.open();
        }
    }

    toggle() {
        if (this.isOpen) {
            this.close();
        } else {
            this.open();
        }
    }

    open() {
        this.startMenu.classList.add('active');
        this.startButton.classList.add('active');
        this.isOpen = true;
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

        // Lock option
        document.getElementById('power-lock').addEventListener('click', () => {
            if (window.lockscreenManager) {
                window.lockscreenManager.lock();
                this.close();
            }
        });

        // Log off option
        document.getElementById('power-logoff').addEventListener('click', () => {
            if (window.lockscreenManager) {
                // Close all windows
                document.querySelectorAll('.window').forEach(win => {
                    win.style.display = 'none';
                });
                
                // Lock the session
                window.lockscreenManager.lock();
                this.close();
            }
        });

        // Shutdown option (just reload for now)
        document.getElementById('power-shutdown').addEventListener('click', () => {
            if (confirm('Are you sure you want to shut down?')) {
                location.reload();
            }
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
        this.isOpen = true;
    }

    close() {
        this.powerMenu.classList.remove('visible');
        this.isOpen = false;
    }
}

// City Hall Management System
class CityHallManager {
    constructor() {
        this.currentPage = 'dashboard';
        this.data = {
            cityName: 'City Hall',
            treasuryBalance: 0,
            mayorName: '',
            announcements: [],
            laws: [],
            taxes: [],
            budgets: [],
            licenses: [],
            utilities: {
                power: { active: 0, delinquent: 0, disconnected: 0 },
                water: { active: 0, delinquent: 0, disconnected: 0 },
                accounts: []
            },
            fines: [],
            staff: [],
            auditLog: [],
            civilians: [],
            civiliansTotal: 0,
            civiliansQuery: '',
            civiliansPage: 1,
            civiliansPageSize: 12,
            civilianProfile: null,
            civilianJobs: [],
            civilianProfileTab: 'overview',
            dashboard: {
                treasury: 0,
                businesses: { total_revenue: 0, total_taxes: 0 },
                recentActivity: [],
                announcements: [],
                pendingBills: 0,
                activeLicenses: 0,
                staffCount: 0
            }
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

            this.refreshAllData().then(() => {
                this.loadPage('dashboard');
            });
        }, 100);
    }

    async refreshAllData() {
        const [
            dashboardRes,
            userRes,
            taxesRes,
            budgetsRes,
            lawsRes,
            licensesRes,
            utilitiesRes,
            billsRes,
            staffRes,
            auditRes,
            announcementsRes,
            infraRes
        ] = await Promise.all([
            nuiRequest('dashboard:getData', {}),
            nuiRequest('user:getInfo', {}),
            nuiRequest('tax:getAll', {}),
            nuiRequest('budget:getAll', {}),
            nuiRequest('law:getAll', { status: 'all' }),
            nuiRequest('license:getAll', {}),
            nuiRequest('utility:getAll', {}),
            nuiRequest('bill:getAll', {}),
            nuiRequest('staff:getAll', {}),
            nuiRequest('audit:getLogs', { limit: 50 }),
            nuiRequest('gov:getAnnouncements', {}),
            nuiRequest('infra:getOverview', {})
        ]);

        if (dashboardRes && dashboardRes.ok) {
            this.data.dashboard = dashboardRes.dashboard || this.data.dashboard;
            this.data.treasuryBalance = this.data.dashboard.treasury || 0;
        }

        if (userRes && userRes.ok && userRes.user) {
            this.data.mayorName = userRes.user.name || '';
        }

        // Keep top bar values in sync with server data.
        const treasuryEl = document.querySelector('.treasury-amount');
        if (treasuryEl) {
            const treasuryValue = Number(this.data.treasuryBalance || 0);
            treasuryEl.textContent = `$${treasuryValue.toLocaleString()}`;
        }

        const mayorEl = document.querySelector('.mayor-name');
        if (mayorEl) {
            mayorEl.textContent = this.data.mayorName && this.data.mayorName !== ''
                ? this.data.mayorName
                : 'Unknown';
        }

        if (announcementsRes && announcementsRes.ok) {
            this.data.announcements = announcementsRes.data || [];
        }

        if (taxesRes && taxesRes.ok) {
            this.data.taxes = (taxesRes.taxes || []).map(tax => ({
                id: tax.tax_type,
                name: tax.tax_type.replace(/_/g, ' ').replace(/\b\w/g, m => m.toUpperCase()),
                rate: Number(tax.rate || 0),
                min: Number(tax.min_rate || 0),
                max: Number(tax.max_rate || 0),
                enabled: Number(tax.enabled || 0) === 1,
                description: tax.description || 'No description provided.',
                lastChangedBy: tax.last_changed_by || 'System',
                lastChangedAt: tax.last_changed_at
            }));
        }

        if (budgetsRes && budgetsRes.ok) {
            this.data.budgets = (budgetsRes.budgets || []).map(budget => ({
                department: budget.department || 'department',
                name: String((budget.department || 'Department')).replace(/_/g, ' ').replace(/\b\w/g, m => m.toUpperCase()),
                approvedMonthlyBudget: Number(budget.approved_monthly_budget || budget.weekly_budget || 0),
                linkedSocietyName: budget.linked_society_name || budget.department || 'department',
                societyBalance: Number(budget.society_balance || 0),
                spentThisMonth: Number(budget.spent_this_month || budget.spent_this_week || 0),
                minimumRequiredMonthly: Number(budget.minimum_required_monthly || 0),
                recommendedMonthlyBudget: Number(budget.recommended_monthly_budget || 0),
                projectedMonthEndBalance: Number(budget.projected_month_end_balance || 0),
                budgetStatus: String(budget.budget_status || 'Stable'),
                salaryObligationMonthly: Number(budget.salary_obligation_monthly || 0),
                equipmentPlan: Number(budget.equipment_plan || 0),
                fleetPlan: Number(budget.fleet_plan || 0),
                facilityPlan: Number(budget.facility_plan || 0),
                emergencyBuffer: Number(budget.emergency_buffer || 0),
                projectedObligationsRemaining: Number(budget.projected_obligations_remaining || 0),
                description: budget.description || 'Department budget for operations and public services.',
                enabled: Number(budget.enabled || 1) === 1,
                requests: 0
            }));
        }

        if (lawsRes && lawsRes.ok) {
            this.data.laws = (lawsRes.laws || []).map(law => ({
                id: law.id,
                title: law.title,
                category: law.category,
                text: law.content,
                fine: Number(law.fine_min || 0),
                jail: Number(law.penalty_min || 0),
                status: (law.status || 'active'),
                source: law.source || 'government',
                read_only: law.read_only === true,
                display_enabled: law.display_enabled !== false
            }));
        }

        if (licensesRes && licensesRes.ok) {
            this.data.licenses = licensesRes.licenses || [];
        }

        if (utilitiesRes && utilitiesRes.ok) {
            const accounts = utilitiesRes.utilities || [];
            const power = { active: 0, delinquent: 0, disconnected: 0 };
            const water = { active: 0, delinquent: 0, disconnected: 0 };

            accounts.forEach(row => {
                if (row.power_status === 'active') power.active += 1;
                if (row.power_status === 'delinquent') power.delinquent += 1;
                if (row.power_status === 'disconnected') power.disconnected += 1;
                if (row.water_status === 'active') water.active += 1;
                if (row.water_status === 'delinquent') water.delinquent += 1;
                if (row.water_status === 'disconnected') water.disconnected += 1;
            });

            this.data.utilities = { power, water, accounts };
        }

        if (billsRes && billsRes.ok) {
            this.data.fines = billsRes.bills || [];
        }

        if (infraRes && infraRes.ok) {
            this.data.infrastructure = infraRes.summary || {};
        }

        if (staffRes && staffRes.ok) {
            this.data.staff = (staffRes.staff || []).map(member => {
                let permissions = [];
                if (typeof member.permissions === 'string') {
                    try {
                        permissions = JSON.parse(member.permissions);
                    } catch (err) {
                        permissions = [];
                    }
                } else if (Array.isArray(member.permissions)) {
                    permissions = member.permissions;
                }
                return { ...member, permissions };
            });
        }

        if (auditRes && auditRes.ok) {
            this.data.auditLog = auditRes.logs || [];
        }
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
        this.refreshAllData().then(() => {
            this.loadPage(page);
        });
    }

    loadPage(page) {
        const container = document.getElementById('cityhall-content');
        if (!container) return;

        const pages = {
            'dashboard': this.renderDashboard(),
            'announcements': this.renderAnnouncements(),
            'laws': this.renderLaws(),
            'taxes': this.renderTaxes(),
            'budgets': this.renderBudgets(),
            'licenses': this.renderLicenses(),
            'utilities': this.renderUtilities(),
            'fines': this.renderFines(),
            'staff': this.renderStaff(),
            'audit': this.renderAuditLog(),
            'civilians': this.renderCivilians(),
            'civilian-profile': this.renderCivilianProfile(),
            'cityhall-settings': this.renderCityHallSettings()
        };

        container.innerHTML = pages[page] || pages['dashboard'];
        this.attachPageHandlers(page);
    }

    async refreshAnnouncements() {
        const result = await nuiRequest('gov:getAnnouncements', {});
        this.data.announcements = result && result.ok ? (result.data || []) : [];
    }

    renderAnnouncements() {
        const list = this.data.announcements
            .slice()
            .sort((a, b) => new Date(b.createdAt || b.created_at || 0) - new Date(a.createdAt || a.created_at || 0))
            .map(item => `
                <div class="announcement-card">
                    <div class="announcement-meta">${item.author || item.created_by_name || 'Mayor'} • ${this.formatDate(item.createdAt || item.created_at)}</div>
                    <h3>${item.title}</h3>
                    <p>${item.body || item.content || ''}</p>
                </div>
            `).join('');

        return `
            <div class="cityhall-page announcements-page">
                <div class="announcements-header">
                    <div>
                        <h1 class="page-title">Mayor Announcements</h1>
                        <p class="text-muted">Publish updates that appear on the public government portal.</p>
                    </div>
                    <button class="btn-primary" id="announcement-refresh">Refresh</button>
                </div>

                <div class="announcements-grid">
                    <div class="announcement-form">
                        <h2>Create Announcement</h2>
                        <div class="form-group">
                            <label>Title</label>
                            <input type="text" id="announcement-title" class="form-input" placeholder="Headline">
                        </div>
                        <div class="form-group">
                            <label>Body</label>
                            <textarea id="announcement-body" class="form-textarea" rows="6"></textarea>
                        </div>
                        <div class="form-group">
                            <label>Author</label>
                            <input type="text" id="announcement-author" class="form-input" placeholder="Mayor">
                        </div>
                        <div class="form-actions">
                            <button class="btn-primary" id="announcement-submit">Publish</button>
                        </div>
                    </div>
                    <div class="announcement-list">
                        ${list || '<div class="text-muted">No announcements published yet.</div>'}
                    </div>
                </div>
            </div>
        `;
    }

    formatDate(value) {
        if (!value) return 'Just now';
        const date = new Date(value);
        if (Number.isNaN(date.getTime())) return value;
        return date.toLocaleString();
    }

    renderDashboard() {
        const dashboard = this.data.dashboard || {};
        const businessStats = dashboard.businesses || {};
        const treasury = Number(dashboard.treasury || 0);
        const totalRevenue = Number(businessStats.total_revenue || 0);
        const totalTaxes = Number(businessStats.total_taxes || 0);
        const pendingBills = Number(dashboard.pendingBills || 0);
        const recentActivity = dashboard.recentActivity || [];

        return `
            <div class="cityhall-page dashboard-page">
                <h1 class="page-title">Dashboard Overview</h1>
                
                <div class="dashboard-cards">
                    <div class="dash-card">
                        <div class="dash-card-icon">💰</div>
                        <div class="dash-card-info">
                            <div class="dash-card-label">Treasury Balance</div>
                            <div class="dash-card-value">$${treasury.toLocaleString()}</div>
                        </div>
                    </div>
                    <div class="dash-card">
                        <div class="dash-card-icon">📈</div>
                        <div class="dash-card-info">
                            <div class="dash-card-label">Total Business Revenue</div>
                            <div class="dash-card-value green">$${totalRevenue.toLocaleString()}</div>
                        </div>
                    </div>
                    <div class="dash-card">
                        <div class="dash-card-icon">📊</div>
                        <div class="dash-card-info">
                            <div class="dash-card-label">Total Taxes Collected</div>
                            <div class="dash-card-value green">$${totalTaxes.toLocaleString()}</div>
                        </div>
                    </div>
                    <div class="dash-card">
                        <div class="dash-card-icon">⚠️</div>
                        <div class="dash-card-info">
                            <div class="dash-card-label">Pending Bills</div>
                            <div class="dash-card-value red">${pendingBills.toLocaleString()}</div>
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
                        <h2>Recent Activity</h2>
                        <div class="alert-list">
                            ${recentActivity.length === 0 ? '<div class="text-muted">No recent activity.</div>' : recentActivity.map(item => `
                                <div class="alert-item info">
                                    <span class="alert-icon">ℹ️</span>
                                    <span class="alert-text">${item.action_type || item.action || 'Activity'}</span>
                                    <span class="alert-time">${this.formatDate(item.created_at || item.createdAt)}</span>
                                </div>
                            `).join('')}
                        </div>
                    </div>
                </div>
            </div>
        `;
    }

    renderLaws() {
        const laws = (this.data.laws || []).slice().sort((a, b) => {
            const ac = String(a.category || 'General');
            const bc = String(b.category || 'General');
            if (ac !== bc) return ac.localeCompare(bc);
            return String(a.title || '').localeCompare(String(b.title || ''));
        });

        const statusLabel = (value) => String(value || 'active').replace(/_/g, ' ').replace(/\b\w/g, (m) => m.toUpperCase());
        const categories = ['All', ...Array.from(new Set(laws.map(law => String(law.category || 'General')))).sort((a, b) => a.localeCompare(b))];

        const activeCount = laws.filter(law => String(law.status).toLowerCase() === 'active').length;
        const referenceCount = laws.filter(law => String(law.source || '').toLowerCase() === 'pf-policemdt').length;

        return `
            <div class="cityhall-page laws-page">
                <div class="laws-page-header">
                    <div>
                        <h1 class="page-title">Laws And Policy Management</h1>
                        <p class="laws-page-subtitle">Organize statutes by category and keep your public law registry clean and current.</p>
                    </div>
                    <div class="laws-header-metrics">
                        <div class="laws-metric-chip"><span>Active</span><strong>${activeCount}</strong></div>
                        <div class="laws-metric-chip"><span>Reference</span><strong>${referenceCount}</strong></div>
                    </div>
                </div>
                
                <div class="laws-container">
                    <div class="laws-left">
                        <aside class="laws-category-sidebar">
                            <h3>Categories</h3>
                            <div class="laws-category-list">
                                ${categories.map((category, index) => `
                                    <button class="laws-category-btn ${index === 0 ? 'active' : ''}" data-law-category-filter="${category.toLowerCase()}">${category}</button>
                                `).join('')}
                            </div>
                        </aside>
                        <div class="laws-controls">
                            <input type="text" placeholder="Search laws by title or text..." class="search-input" id="law-search">
                            <button class="btn-primary" id="create-law-btn">Create New Law</button>
                        </div>

                        <div class="laws-list">
                            ${laws.map(law => `
                                <div class="law-item ${law.status}" data-law-id="${law.id}" data-category="${(law.category || '').toLowerCase()}">
                                    <div class="law-item-top">
                                        <div class="law-title">${law.title}</div>
                                        <span class="law-status law-status-pill">${statusLabel(law.status)}</span>
                                    </div>
                                    <div class="law-meta">
                                        <span class="law-category">${law.category}</span>
                                        <span class="law-source">${law.source === 'pf-policemdt' ? 'Reference Registry' : 'City Hall'}</span>
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
                <div class="taxes-header">
                    <div>
                        <h1 class="page-title">Taxes And Fees</h1>
                        <p class="text-muted">Each tax includes a public purpose statement and configured rate boundaries.</p>
                    </div>
                </div>

                <div class="taxes-table">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>Tax Type</th>
                                <th>Purpose</th>
                                <th>Current Rate</th>
                                <th>Allowed Range</th>
                                <th>Last Changed By</th>
                                <th>Last Changed</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${taxes.map(tax => `
                                <tr>
                                    <td>
                                        <strong>${tax.name}</strong>
                                        <div class="tax-enabled-badge ${tax.enabled ? 'active' : 'inactive'}">${tax.enabled ? 'Enabled' : 'Disabled'}</div>
                                    </td>
                                    <td>${tax.description || 'No description provided.'}</td>
                                    <td class="rate-value">${tax.rate}%</td>
                                    <td>${tax.min}% - ${tax.max}%</td>
                                    <td>${tax.lastChangedBy}</td>
                                    <td>${this.formatDate(tax.lastChangedAt) || 'N/A'}</td>
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
        const totalApproved = budgets.reduce((s, b) => s + Number(b.approvedMonthlyBudget || 0), 0);
        const totalSociety = budgets.reduce((s, b) => s + Number(b.societyBalance || 0), 0);
        const totalSpent = budgets.reduce((s, b) => s + Number(b.spentThisMonth || 0), 0);
        const totalMinimum = budgets.reduce((s, b) => s + Number(b.minimumRequiredMonthly || 0), 0);
        return `
            <div class="cityhall-page budgets-page">
                <h1 class="page-title">Department Budgets</h1>
                <p class="text-muted">Monthly budget oversight with linked society accounts, projected obligations, and infrastructure readiness.</p>

                <div class="dashboard-cards">
                    <div class="dash-card">
                        <div class="dash-card-info">
                            <div class="dash-card-label">Approved Monthly Budget</div>
                            <div class="dash-card-value">$${totalApproved.toLocaleString()}</div>
                        </div>
                    </div>
                    <div class="dash-card">
                        <div class="dash-card-info">
                            <div class="dash-card-label">Linked Society Balance</div>
                            <div class="dash-card-value green">$${totalSociety.toLocaleString()}</div>
                        </div>
                    </div>
                    <div class="dash-card">
                        <div class="dash-card-info">
                            <div class="dash-card-label">Spent This Month</div>
                            <div class="dash-card-value">$${totalSpent.toLocaleString()}</div>
                        </div>
                    </div>
                    <div class="dash-card">
                        <div class="dash-card-info">
                            <div class="dash-card-label">Minimum Required</div>
                            <div class="dash-card-value">$${totalMinimum.toLocaleString()}</div>
                        </div>
                    </div>
                </div>
                
                <div class="budgets-list">
                    ${budgets.map(dept => `
                        <div class="budget-card" data-budget-department="${dept.department}">
                            <div class="budget-header">
                                <h3>${dept.name}</h3>
                                <span class="budget-total">$${Number(dept.approvedMonthlyBudget || 0).toLocaleString()}</span>
                            </div>
                            <div class="budget-stats">
                                <div class="budget-stat">
                                    <span class="stat-label">Linked Society Balance</span>
                                    <span class="stat-value">$${Number(dept.societyBalance || 0).toLocaleString()}</span>
                                </div>
                                <div class="budget-stat">
                                    <span class="stat-label">Spent This Month</span>
                                    <span class="stat-value">$${Number(dept.spentThisMonth || 0).toLocaleString()}</span>
                                </div>
                                <div class="budget-stat">
                                    <span class="stat-label">Minimum Required</span>
                                    <span class="stat-value">$${Number(dept.minimumRequiredMonthly || 0).toLocaleString()}</span>
                                </div>
                                <div class="budget-stat">
                                    <span class="stat-label">Recommended</span>
                                    <span class="stat-value">$${Number(dept.recommendedMonthlyBudget || 0).toLocaleString()}</span>
                                </div>
                                <div class="budget-stat">
                                    <span class="stat-label">Projected Month-End</span>
                                    <span class="stat-value ${Number(dept.projectedMonthEndBalance || 0) < 0 ? 'red' : 'green'}">$${Number(dept.projectedMonthEndBalance || 0).toLocaleString()}</span>
                                </div>
                                <div class="budget-stat">
                                    <span class="stat-label">Status</span>
                                    <span class="stat-value">${dept.budgetStatus || 'Stable'}</span>
                                </div>
                            </div>
                            <div class="budget-actions">
                                <button class="btn-secondary btn-sm budget-details-btn" data-budget-details="${dept.department}">View Details</button>
                                <button class="btn-secondary btn-sm budget-adjust-btn" data-budget-adjust="${dept.department}">Set Monthly Budget</button>
                            </div>
                        </div>
                    `).join('')}
                </div>
            </div>
        `;
    }

    renderLicenses() {
        const licenses = this.data.licenses || [];
        const now = new Date();
        const soon = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);
        const activeCount = licenses.filter(l => l.status === 'active').length;
        const expiringSoon = licenses.filter(l => {
            if (l.status !== 'active' || !l.expires_at) return false;
            const exp = new Date(l.expires_at);
            return exp > now && exp <= soon;
        }).length;
        const suspendedCount = licenses.filter(l => l.status === 'suspended').length;
        const pendingCount = licenses.filter(l => l.status === 'pending').length;
        const rows = licenses.map(lic => `
            <tr>
                <td><strong>${lic.id || 'N/A'}</strong></td>
                <td>
                    <div class="holder-info">
                        <div class="holder-name">${lic.owner_name || 'Unknown'}</div>
                        <div class="holder-id">${lic.owner_id || ''}</div>
                    </div>
                </td>
                <td>${lic.license_type || ''}</td>
                <td>${this.formatDate(lic.issued_at)}</td>
                <td>${this.formatDate(lic.expires_at)}</td>
                <td><span class="status-badge ${lic.status === 'active' ? 'active' : 'warning'}">${lic.status || 'unknown'}</span></td>
                <td>
                    <div class="action-buttons">
                        <button class="btn-icon" title="View Details" data-license-id="${lic.id}">👁</button>
                    </div>
                </td>
            </tr>
        `).join('');

        return `
            <div class="cityhall-page licenses-page">
                <div class="licenses-header">
                    <h1 class="page-title">Licenses & Permits</h1>
                    <div class="header-actions">
                        <button class="btn-primary" id="create-license-btn">Create New License</button>
                        <button class="btn-secondary" id="license-export-report">Export Report</button>
                    </div>
                </div>
                
                <div class="licenses-stats-grid">
                    <div class="stat-card">
                        <div class="stat-icon" style="background: var(--success-bg); color: var(--success);">✓</div>
                        <div>
                            <div class="stat-value">${activeCount}</div>
                            <div class="stat-label">Active Licenses</div>
                        </div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-icon" style="background: var(--warning-bg); color: var(--warning);">⌛</div>
                        <div>
                            <div class="stat-value">${expiringSoon}</div>
                            <div class="stat-label">Expiring Soon</div>
                        </div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-icon" style="background: var(--danger-bg); color: var(--danger);">✕</div>
                        <div>
                            <div class="stat-value">${suspendedCount}</div>
                            <div class="stat-label">Suspended</div>
                        </div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-icon" style="background: var(--info-bg); color: var(--info);">📋</div>
                        <div>
                            <div class="stat-value">${pendingCount}</div>
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
                            ${rows || '<tr><td colspan="7" class="text-muted">No licenses found.</td></tr>'}
                        </tbody>
                    </table>
                </div>
            </div>
        `;
    }

    renderUtilities() {
        const utilities = this.data.utilities || { power: { active: 0, delinquent: 0, disconnected: 0 }, water: { active: 0, delinquent: 0, disconnected: 0 }, accounts: [] };
        const infra = this.data.infrastructure || {};
        const departments = infra.departments || {};
        const districts = infra.districts || {};
        const upgradeCatalog = infra.upgradeCatalog || {};
        const utilityBills = (this.data.fines || []).filter(b => String(b.bill_type || '').toLowerCase() === 'utility' && ['unpaid', 'partial', 'delinquent'].includes(String(b.status || '').toLowerCase()));
        const treasuryBalance = Number((this.data.treasury && this.data.treasury.balance) || infra.treasury_balance || 0);
        const accounts = (utilities.accounts || []).map((row) => {
            const debt = utilityBills
                .filter(b => String(b.target_type) === String(row.property_type) && String(b.target_id) === String(row.property_id))
                .reduce((sum, bill) => sum + (Number(bill.amount || 0) - Number(bill.amount_paid || 0)), 0);
            const maxDays = utilityBills
                .filter(b => String(b.target_type) === String(row.property_type) && String(b.target_id) === String(row.property_id))
                .reduce((max, bill) => {
                    const due = new Date(bill.due_date || 0).getTime();
                    if (!due) return max;
                    const days = Math.max(0, Math.floor((Date.now() - due) / 86400000));
                    return Math.max(max, days);
                }, 0);
            const serviceLabel = this.getUtilityServiceLabel(row);
            const serviceType = this.getPrimaryUtilityAction(row);
            return { ...row, debt, daysOverdue: maxDays, serviceLabel, serviceType };
        }).filter(row => row.debt > 0 || row.power_status !== 'active' || row.water_status !== 'active');

        const depRows = ['dot', 'power', 'water'].map((key) => {
            const d = departments[key] || {};
            return `
                <tr>
                    <td>${String(key).toUpperCase()}</td>
                    <td>$${Number(d.monthly_operating_budget || 0).toLocaleString()}</td>
                    <td>$${Number(d.society_balance || 0).toLocaleString()}</td>
                    <td>$${Number(d.monthly_maintenance_demand || 0).toLocaleString()}</td>
                    <td>$${Number(d.monthly_backlog || 0).toLocaleString()}</td>
                    <td>${d.status || 'N/A'}</td>
                </tr>
            `;
        }).join('');

        const districtRows = Object.values(districts).map((d) => `
            <tr>
                <td>${d.district || '-'}</td>
                <td>${Number(d.power_stage || 1)}</td>
                <td>${Number(d.dot_stage || 1)}</td>
                <td>${Number(d.road_condition || 0).toFixed(1)}%</td>
                <td>${d.traffic_light_health != null ? `${Number(d.traffic_light_health || 0).toFixed(1)}%` : (d.has_traffic_signals ? 'Online' : 'Offline')}</td>
                <td>${d.street_light_health != null ? `${Number(d.street_light_health || 0).toFixed(1)}%` : (d.has_street_lights ? 'Online' : 'Offline')}</td>
                <td>${d.blackout ? 'Blackout' : (d.flicker ? 'Flicker' : 'Stable')}</td>
                <td>${Number(d.hazard_stage || 1)}</td>
            </tr>
        `).join('');

        const upgradeRows = Object.keys(upgradeCatalog).map((dept) => {
            const entries = (upgradeCatalog[dept] || []).map((u) => `
                <div class="upgrade-card ${u.installed ? 'installed' : ''}" style="margin-bottom:8px;">
                    <div class="upgrade-card-header budget-header">
                        <h3>${u.name}</h3>
                        <span class="status-badge ${u.installed ? 'active' : 'neutral'}">${u.installed ? 'Installed' : 'Not Installed'}</span>
                    </div>
                    <p class="text-muted">${u.description || ''}</p>
                    <div class="upgrade-meta text-muted" style="margin-bottom:8px;">
                        <div>Cost: $${Number(u.cost || 0).toLocaleString()}</div>
                        <div>Effect: ${u.effectSummary || 'Operational improvement'}</div>
                        <div>${treasuryBalance >= Number(u.cost || 0) ? 'Treasury can afford this upgrade' : 'Treasury cannot currently afford this upgrade'}</div>
                    </div>
                    <div class="budget-actions upgrade-actions">
                        <button class="btn-primary btn-sm upgrade-install-btn" data-infra-department="${dept}" data-upgrade-key="${u.key}" ${u.installed || treasuryBalance < Number(u.cost || 0) ? 'disabled' : ''}>Install</button>
                        <button class="btn-secondary btn-sm upgrade-uninstall-btn" data-infra-department="${dept}" data-upgrade-key="${u.key}" ${!u.installed ? 'disabled' : ''}>Uninstall</button>
                    </div>
                </div>
            `).join('');

            return `<div><h3>${String(dept).toUpperCase()} Upgrades</h3>${entries || '<p class="text-muted">No upgrades configured.</p>'}</div>`;
        }).join('');

        return `
            <div class="cityhall-page utilities-page">
                <h1 class="page-title">Utilities & Infrastructure</h1>
                <p class="text-muted">Administrative infrastructure controls with district impact visibility and upgrade planning.</p>

                <div class="licenses-tabs">
                    <button class="tab-btn active" data-infra-tab="control">Infrastructure Control</button>
                    <button class="tab-btn" data-infra-tab="accounts">Utility Accounts</button>
                    <button class="tab-btn" data-infra-tab="districts">District Status</button>
                    <button class="tab-btn" data-infra-tab="upgrades">Upgrade Planning</button>
                </div>

                <div class="infra-tab-panel" data-infra-panel="control">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>Department</th>
                                <th>Monthly Operating Budget</th>
                                <th>Linked Account Balance</th>
                                <th>Monthly Maintenance Demand</th>
                                <th>Monthly Backlog</th>
                                <th>Status</th>
                            </tr>
                        </thead>
                        <tbody>${depRows}</tbody>
                    </table>
                </div>

                <div class="infra-tab-panel" data-infra-panel="accounts" style="display:none;">
                    <h2>Delinquent Utility Accounts</h2>
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
                            ${accounts.length === 0 ? '<tr><td colspan="7" class="text-muted">No delinquent utility accounts.</td></tr>' : accounts.map(row => `
                                <tr>
                                    <td>${row.property_id}</td>
                                    <td>${row.owner_name || 'Unknown'}</td>
                                    <td>${row.serviceLabel}</td>
                                    <td>$${Number(row.debt || 0).toLocaleString()}</td>
                                    <td>${row.daysOverdue || 0}</td>
                                    <td><span class="status-badge ${row.power_status === 'disconnected' || row.water_status === 'disconnected' ? 'error' : 'warning'}">${row.power_status === 'disconnected' || row.water_status === 'disconnected' ? 'Disconnected' : 'Delinquent'}</span></td>
                                    <td>
                                        <button class="btn-secondary btn-sm utility-notice-btn" data-property-id="${row.property_id}" data-owner-name="${row.owner_name || 'Owner'}">Send Notice</button>
                                        <button class="btn-danger btn-sm utility-disconnect-btn"
                                            data-property-type="${row.property_type}"
                                            data-property-id="${row.property_id}"
                                            data-service-type="${row.serviceType || 'both'}" ${!row.serviceType ? 'disabled' : ''}>Disconnect</button>
                                        <button class="btn-secondary btn-sm restore-btn"
                                            data-property-type="${row.property_type}"
                                            data-property-id="${row.property_id}"
                                            data-service-type="${row.serviceType || 'both'}" ${!row.serviceType ? 'disabled' : ''}>Restore</button>
                                    </td>
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                </div>

                <div class="infra-tab-panel" data-infra-panel="districts" style="display:none;">
                    <h2>District Status</h2>
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>District</th>
                                <th>Power Stage</th>
                                <th>DOT Stage</th>
                                <th>Road Condition</th>
                                <th>Traffic Signals</th>
                                <th>Street Lights</th>
                                <th>Grid State</th>
                                <th>Risk Level</th>
                            </tr>
                        </thead>
                        <tbody>${districtRows || '<tr><td colspan="8" class="text-muted">No district simulation data available.</td></tr>'}</tbody>
                    </table>
                </div>

                <div class="infra-tab-panel" data-infra-panel="upgrades" style="display:none;">
                    <h2>Upgrade Planning</h2>
                    ${upgradeRows || '<p class="text-muted">No infrastructure upgrades configured.</p>'}
                </div>
            </div>
        `;
    }

    getUtilityServiceLabel(row) {
        const powerAffected = row && row.power_status && row.power_status !== 'active';
        const waterAffected = row && row.water_status && row.water_status !== 'active';

        if (powerAffected && waterAffected) return 'Both';
        if (powerAffected) return 'Power';
        if (waterAffected) return 'Water';
        return 'None';
    }

    getPrimaryUtilityAction(row) {
        const powerAffected = row && row.power_status && row.power_status !== 'active';
        const waterAffected = row && row.water_status && row.water_status !== 'active';

        if (powerAffected && waterAffected) return 'both';
        if (powerAffected) return 'power';
        if (waterAffected) return 'water';
        return null;
    }

    renderFines() {
        const fines = this.data.fines || [];
        const totalOutstanding = fines.reduce((sum, bill) => sum + Number(bill.amount || 0) - Number(bill.amount_paid || 0), 0);
        const unpaidCount = fines.filter(bill => bill.status === 'unpaid').length;
        const overdueCount = fines.filter(bill => bill.status === 'delinquent').length;
        return `
            <div class="cityhall-page fines-page">
                <h1 class="page-title">Fines & Collections</h1>
                <p class="text-muted">Issue immediate fines to citizens and collect from available funds even when they are offline.</p>
                
                <div class="fines-summary">
                    <div class="summary-card">
                        <div class="summary-value">$${Math.floor(totalOutstanding).toLocaleString()}</div>
                        <div class="summary-label">Total Outstanding</div>
                    </div>
                    <div class="summary-card">
                        <div class="summary-value">${unpaidCount}</div>
                        <div class="summary-label">Unpaid Fines</div>
                    </div>
                    <div class="summary-card">
                        <div class="summary-value">${overdueCount}</div>
                        <div class="summary-label">Overdue &gt; 30 Days</div>
                    </div>
                </div>

                <div class="fines-issue-panel">
                    <h2>Issue Immediate Fine</h2>
                    <div class="fines-issue-grid">
                        <input type="text" id="fine-citizen-id" class="form-input" placeholder="Target Citizen ID">
                        <input type="number" id="fine-amount" class="form-input" min="1" step="1" placeholder="Amount">
                        <input type="text" id="fine-description" class="form-input" placeholder="Reason / Violation">
                        <button class="btn-primary" id="fine-issue-btn">Issue Fine</button>
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
                            ${fines.length === 0 ? '<tr><td colspan="7" class="text-muted">No fines found.</td></tr>' : fines.map(bill => `
                                <tr>
                                    <td>${bill.id}</td>
                                    <td>${bill.target_id || ''}</td>
                                    <td>${bill.description || bill.bill_type}</td>
                                    <td>$${Number(bill.amount || 0).toLocaleString()}</td>
                                    <td>${this.formatDate(bill.due_date)}</td>
                                    <td><span class="status-badge ${bill.status === 'paid' ? 'active' : 'error'}">${bill.status}</span></td>
                                    <td>
                                        <button class="btn-secondary btn-sm">View</button>
                                    </td>
                                </tr>
                            `).join('')}
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
                    <button class="btn-primary" id="add-staff-btn">Add Staff Member</button>
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
                            ${staff.length === 0 ? '<tr><td colspan="5" class="text-muted">No staff records.</td></tr>' : staff.map(member => `
                                <tr>
                                    <td>${member.name || 'Unknown'}</td>
                                    <td><strong>${member.role || member.position || 'Staff'}</strong></td>
                                    <td>
                                        ${(member.permissions || []).map(p => `<span class="permission-tag">${p}</span>`).join(' ')}
                                    </td>
                                    <td><span class="status-badge active">${member.active == 1 ? 'Active' : 'Inactive'}</span></td>
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
        const logs = this.data.auditLog || [];
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
                            ${logs.length ? logs.map(log => `
                                <tr>
                                    <td>${log.timestamp || ''}</td>
                                    <td>${log.user || ''}</td>
                                    <td>${log.action || ''}</td>
                                    <td><span class="category-tag">${log.category || ''}</span></td>
                                    <td>${log.details || ''}</td>
                                </tr>
                            `).join('') : '<tr><td colspan="5" class="text-muted">No audit log entries.</td></tr>'}
                        </tbody>
                    </table>
                </div>
            </div>
        `;
    }

    renderSettings() {
        return `
            <div class="cityhall-page settings-page">
                <h1 class="page-title">City Hall Settings</h1>

                <div class="setting-group">
                    <label>City Name</label>
                    <input type="text" value="${this.data.cityName || 'Los Santos'}" class="setting-input">
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

    editLaw(lawId) {
        const law = this.data.laws.find(l => l.id == lawId);
        if (!law) return;

        const editor = document.getElementById('law-editor');
        if (!editor) return;

        if (law.read_only || law.source === 'pf-policemdt') {
            editor.innerHTML = `
                <div class="law-editor-form">
                    <h3>${law.title}</h3>
                    <div class="form-group">
                        <label>Category</label>
                        <input type="text" class="form-input" value="${law.category || 'MDT'}" disabled>
                    </div>
                    <div class="form-group">
                        <label>Source</label>
                        <input type="text" class="form-input" value="Government Records (synced to MDT)" disabled>
                    </div>
                    <div class="form-group">
                        <label>Record Text</label>
                        <textarea class="form-textarea" rows="10" disabled>${law.text || law.content || ''}</textarea>
                    </div>
                    <div class="form-actions">
                        <button class="btn-danger" id="law-disable-display">Disable Law</button>
                        <button class="btn-secondary" id="law-mdt-view">View in MDT Format</button>
                    </div>
                </div>
            `;

            document.getElementById('law-disable-display')?.addEventListener('click', async () => {
                if (!confirm('Disable this law from all law displays?')) return;
                const res = await nuiRequest('law:setDisplayEnabled', { lawId: law.id, sourceType: law.source || 'pf-policemdt', enabled: false });
                if (res && res.ok) {
                    await this.refreshAllData();
                    this.loadPage('laws');
                }
            });

            document.getElementById('law-mdt-view')?.addEventListener('click', () => {
                this.openLawMdtPreview(law);
            });
            return;
        }

        editor.innerHTML = `
            <div class="law-editor-form">
                <h3>Edit Law: ${law.title}</h3>

                <div class="form-group">
                    <label>Title</label>
                    <input type="text" id="law-edit-title" value="${law.title}" class="form-input">
                </div>

                <div class="form-group">
                    <label>Category</label>
                    <select id="law-edit-category" class="form-input">
                        <option ${law.category === 'Traffic' ? 'selected' : ''}>Traffic</option>
                        <option ${law.category === 'Weapons' ? 'selected' : ''}>Weapons</option>
                        <option ${law.category === 'Business' ? 'selected' : ''}>Business</option>
                        <option ${law.category === 'Civil' ? 'selected' : ''}>Civil</option>
                    </select>
                </div>

                <div class="form-group">
                    <label>Law Text</label>
                    <textarea id="law-edit-content" class="form-textarea" rows="6">${law.text || law.content || ''}</textarea>
                </div>

                <div class="form-group">
                    <label>Default Fine ($)</label>
                    <input type="number" id="law-edit-fine" value="${law.fine || 0}" class="form-input">
                </div>

                <div class="form-group">
                    <label>Default Jail Time (months)</label>
                    <input type="number" id="law-edit-jail" value="${law.jail || 0}" class="form-input">
                </div>

                <div class="form-actions">
                    <button class="btn-secondary" id="law-save-draft">Save Draft</button>
                    <button class="btn-primary" id="law-publish">Publish Law</button>
                    <button class="btn-danger" id="law-repeal">Repeal Law</button>
                    <button class="btn-danger" id="law-disable-display">Disable Law</button>
                    <button class="btn-secondary" id="law-mdt-view">View in MDT Format</button>
                </div>
            </div>
        `;

        const getFormData = () => ({
            title: document.getElementById('law-edit-title')?.value,
            category: document.getElementById('law-edit-category')?.value,
            content: document.getElementById('law-edit-content')?.value,
            fine: parseInt(document.getElementById('law-edit-fine')?.value) || 0,
            jail: parseInt(document.getElementById('law-edit-jail')?.value) || 0
        });

        document.getElementById('law-save-draft')?.addEventListener('click', async () => {
            const data = getFormData();
            const res = await nuiRequest('law:update', { lawId: law.id, ...data, status: 'draft' });
            if (res && (res.success || res.ok)) {
                await this.refreshAllData();
                this.loadPage('laws');
            }
        });

        document.getElementById('law-publish')?.addEventListener('click', async () => {
            const data = getFormData();
            const res = await nuiRequest('law:publish', { lawId: law.id, ...data });
            if (res && (res.success || res.ok)) {
                await this.refreshAllData();
                this.loadPage('laws');
            }
        });

        document.getElementById('law-repeal')?.addEventListener('click', async () => {
            if (!confirm('Repeal this law?')) return;
            const res = await nuiRequest('law:repeal', { lawId: law.id });
            if (res && (res.success || res.ok)) {
                await this.refreshAllData();
                this.loadPage('laws');
            }
        });

        document.getElementById('law-disable-display')?.addEventListener('click', async () => {
            if (!confirm('Disable this law from all law displays?')) return;
            const res = await nuiRequest('law:setDisplayEnabled', { lawId: law.id, sourceType: law.source || 'government', enabled: false });
            if (res && res.ok) {
                await this.refreshAllData();
                this.loadPage('laws');
            }
        });

        document.getElementById('law-mdt-view')?.addEventListener('click', () => {
            const data = getFormData();
            this.openLawMdtPreview({ ...law, ...data });
        });
    }

    openLawMdtPreview(law) {
        const previewWindow = window.open('', '_blank', 'width=900,height=700');
        if (!previewWindow) {
            alert('Unable to open the MDT preview window. Check your popup blocker settings.');
            return;
        }

        const fine = Number(law.fine || 0).toLocaleString();
        const jail = Number(law.jail || 0).toLocaleString();
        const text = law.content || law.text || 'No law text provided.';

        previewWindow.document.write(`
            <!DOCTYPE html>
            <html lang="en">
            <head>
                <meta charset="UTF-8">
                <title>MDT Law Preview</title>
                <style>
                    body { font-family: Segoe UI, sans-serif; background: #0f172a; color: #e5e7eb; margin: 0; padding: 24px; }
                    .sheet { max-width: 880px; margin: 0 auto; background: #111827; border: 1px solid #334155; border-radius: 12px; padding: 24px; }
                    h1 { margin: 0 0 8px; font-size: 28px; }
                    .meta { color: #94a3b8; margin-bottom: 20px; }
                    .grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; margin-bottom: 20px; }
                    .card { background: #1f2937; border-radius: 8px; padding: 12px; }
                    .label { color: #94a3b8; font-size: 12px; text-transform: uppercase; letter-spacing: 0.08em; }
                    .value { margin-top: 6px; font-size: 16px; }
                    .body { white-space: pre-wrap; line-height: 1.6; background: #0b1220; padding: 16px; border-radius: 8px; border: 1px solid #334155; }
                </style>
            </head>
            <body>
                <div class="sheet">
                    <h1>${law.title || 'Untitled Law'}</h1>
                    <div class="meta">MDT Statute Preview</div>
                    <div class="grid">
                        <div class="card"><div class="label">Category</div><div class="value">${law.category || 'Uncategorized'}</div></div>
                        <div class="card"><div class="label">Default Fine</div><div class="value">$${fine}</div></div>
                        <div class="card"><div class="label">Default Jail</div><div class="value">${jail} months</div></div>
                    </div>
                    <div class="body">${text}</div>
                </div>
            </body>
            </html>
        `);
        previewWindow.document.close();
    }

    createNewLaw() {
        const editor = document.getElementById('law-editor');
        if (!editor) return;

        editor.innerHTML = `
            <div class="law-editor-form">
                <h3>Create New Law</h3>

                <div class="form-group">
                    <label>Title</label>
                    <input type="text" id="law-new-title" class="form-input" placeholder="Law title">
                </div>

                <div class="form-group">
                    <label>Category</label>
                    <select id="law-new-category" class="form-input">
                        <option>Traffic</option>
                        <option>Weapons</option>
                        <option>Business</option>
                        <option>Civil</option>
                    </select>
                </div>

                <div class="form-group">
                    <label>Law Text</label>
                    <textarea id="law-new-content" class="form-textarea" rows="6" placeholder="Describe the law..."></textarea>
                </div>

                <div class="form-group">
                    <label>Default Fine ($)</label>
                    <input type="number" id="law-new-fine" value="0" class="form-input">
                </div>

                <div class="form-group">
                    <label>Default Jail Time (months)</label>
                    <input type="number" id="law-new-jail" value="0" class="form-input">
                </div>

                <div class="form-actions">
                    <button class="btn-primary" id="law-create-submit">Create Law</button>
                    <button class="btn-secondary" id="law-create-cancel">Cancel</button>
                </div>
            </div>
        `;

        document.getElementById('law-create-submit')?.addEventListener('click', async () => {
            const title = document.getElementById('law-new-title')?.value.trim();
            const category = document.getElementById('law-new-category')?.value;
            const content = document.getElementById('law-new-content')?.value.trim();
            const fine = parseInt(document.getElementById('law-new-fine')?.value) || 0;
            const jail = parseInt(document.getElementById('law-new-jail')?.value) || 0;

            if (!title || !content) {
                alert('Title and law text are required.');
                return;
            }

            const res = await nuiRequest('law:create', { title, category, content, fine, jail });
            if (res && (res.success || res.ok)) {
                await this.refreshAllData();
                this.loadPage('laws');
            }
        });

        document.getElementById('law-create-cancel')?.addEventListener('click', () => {
            editor.innerHTML = '<p class="text-muted">Select a law to edit or create a new one.</p>';
        });
    }

    addStaffMember() {
        this.showModal(`
            <h3>Add Staff Member</h3>
            <div class="form-group">
                <label>Citizen ID</label>
                <input type="text" class="form-input" id="staff-citizen-id" placeholder="e.g. ABC123">
            </div>
            <div class="form-group">
                <label>Name</label>
                <input type="text" class="form-input" id="staff-name" placeholder="Full name">
            </div>
            <div class="form-group">
                <label>Role / Position</label>
                <select class="form-input" id="staff-role">
                    <option value="Deputy Mayor">Deputy Mayor</option>
                    <option value="Treasurer">Treasurer</option>
                    <option value="Judge">Judge</option>
                    <option value="Secretary">Secretary</option>
                    <option value="Advisor">Advisor</option>
                </select>
            </div>
        `, async () => {
            const citizenId = document.getElementById('staff-citizen-id')?.value.trim();
            const name = document.getElementById('staff-name')?.value.trim();
            const role = document.getElementById('staff-role')?.value;

            if (!citizenId || !name) {
                alert('Citizen ID and name are required.');
                return;
            }

            const res = await nuiRequest('staff:add', { citizenId, name, role });
            if (res && res.success) {
                await this.refreshAllData();
                this.loadPage('staff');
            }
        });
    }

    attachPageHandlers(page) {
        if (page === 'laws') {
            document.querySelectorAll('.laws-category-btn').forEach(btn => {
                btn.addEventListener('click', () => {
                    document.querySelectorAll('.laws-category-btn').forEach(b => b.classList.remove('active'));
                    btn.classList.add('active');
                    const filter = btn.dataset.lawCategoryFilter || 'all';
                    document.querySelectorAll('.law-item').forEach(item => {
                        const cat = item.dataset.category || '';
                        item.style.display = (filter === 'all' || cat === filter) ? '' : 'none';
                    });
                });
            });

            const lawSearch = document.getElementById('law-search');
            if (lawSearch) {
                lawSearch.addEventListener('input', (e) => {
                    const q = e.target.value.toLowerCase();
                    document.querySelectorAll('.law-item').forEach(item => {
                        item.style.display = item.textContent.toLowerCase().includes(q) ? '' : 'none';
                    });
                });
            }

            document.querySelectorAll('.law-item').forEach(item => {
                item.addEventListener('click', () => this.editLaw(item.dataset.lawId));
            });

            const createBtn = document.getElementById('create-law-btn');
            if (createBtn) createBtn.addEventListener('click', () => this.createNewLaw());
        }

        if (page === 'budgets') {
            document.querySelectorAll('.budget-details-btn').forEach(btn => {
                btn.addEventListener('click', () => this.viewBudgetDetails(btn.dataset.budgetDetails));
            });

            document.querySelectorAll('.budget-adjust-btn').forEach(btn => {
                btn.addEventListener('click', () => this.adjustBudgetPrompt(btn.dataset.budgetAdjust));
            });
        }

        if (page === 'staff') {
            const addBtn = document.getElementById('add-staff-btn');
            if (addBtn) addBtn.addEventListener('click', () => this.addStaffMember());
        }

        if (page === 'licenses') {
            const createBtn = document.getElementById('create-license-btn');
            const exportBtn = document.getElementById('license-export-report');
            if (createBtn) createBtn.addEventListener('click', () => this.createLicense());
            if (exportBtn) exportBtn.addEventListener('click', () => this.exportLicensesReport());
            document.querySelectorAll('[data-license-id]').forEach(btn => {
                btn.addEventListener('click', () => this.showLicenseDetails(btn.dataset.licenseId));
            });
        }

        if (page === 'utilities') {
            document.querySelectorAll('[data-infra-tab]').forEach((btn) => {
                btn.addEventListener('click', () => {
                    const target = btn.dataset.infraTab;
                    document.querySelectorAll('[data-infra-tab]').forEach((b) => b.classList.remove('active'));
                    btn.classList.add('active');
                    document.querySelectorAll('[data-infra-panel]').forEach((panel) => {
                        panel.style.display = panel.dataset.infraPanel === target ? '' : 'none';
                    });
                });
            });

            document.querySelectorAll('.restore-btn').forEach(btn => {
                btn.addEventListener('click', async () => {
                    const propertyType = btn.dataset.propertyType;
                    const propertyId = btn.dataset.propertyId;
                    const serviceType = btn.dataset.serviceType;
                    const res = await nuiRequest('utility:restore', { propertyType, propertyId, serviceType });
                    if (res && res.ok) {
                        await this.refreshAllData();
                        this.loadPage('utilities');
                    }
                });
            });

            document.querySelectorAll('.utility-disconnect-btn').forEach(btn => {
                btn.addEventListener('click', async () => {
                    const propertyType = btn.dataset.propertyType;
                    const propertyId = btn.dataset.propertyId;
                    const serviceType = btn.dataset.serviceType;
                    const reason = 'Delinquent utility account';
                    const res = await nuiRequest('utility:disconnect', { propertyType, propertyId, serviceType, reason });
                    if (res && res.ok) {
                        await this.refreshAllData();
                        this.loadPage('utilities');
                    }
                });
            });

            document.querySelectorAll('.utility-notice-btn').forEach(btn => {
                btn.addEventListener('click', () => {
                    const owner = btn.dataset.ownerName || 'Owner';
                    alert(`Delinquency notice sent to ${owner}.`);
                });
            });

            document.querySelectorAll('.upgrade-install-btn, .infra-upgrade-buy').forEach(btn => {
                btn.addEventListener('click', async () => {
                    const department = btn.dataset.infraDepartment;
                    const upgradeKey = btn.dataset.upgradeKey;
                    const res = await nuiRequest('infra:buyUpgrade', { department, upgradeKey });
                    if (res && res.ok) {
                        await this.refreshAllData();
                        this.loadPage('utilities');
                    }
                });
            });

            document.querySelectorAll('.upgrade-uninstall-btn, .infra-upgrade-remove').forEach(btn => {
                btn.addEventListener('click', async () => {
                    const department = btn.dataset.infraDepartment;
                    const upgradeKey = btn.dataset.upgradeKey;
                    const res = await nuiRequest('infra:uninstallUpgrade', { department, upgradeKey });
                    if (res && res.ok) {
                        await this.refreshAllData();
                        this.loadPage('utilities');
                    }
                });
            });
        }

        if (page === 'announcements') {
            const submitBtn = document.getElementById('announcement-submit');
            const refreshBtn = document.getElementById('announcement-refresh');
            if (submitBtn) submitBtn.addEventListener('click', () => this.publishAnnouncement());
            if (refreshBtn) refreshBtn.addEventListener('click', () => {
                this.refreshAnnouncements().then(() => this.loadPage('announcements'));
            });
        }

        if (page === 'fines') {
            const issueBtn = document.getElementById('fine-issue-btn');
            if (issueBtn) {
                issueBtn.addEventListener('click', () => this.issueImmediateFine());
            }
        }

        if (page === 'cityhall-settings') {
            const saveBtn = document.getElementById('settings-save-btn');
            if (saveBtn) saveBtn.addEventListener('click', () => {
                const cityName = document.getElementById('settings-city-name')?.value.trim();
                const mayorName = document.getElementById('settings-mayor-name')?.value.trim();
                if (cityName) this.data.cityName = cityName;
                if (mayorName) {
                    this.data.mayorName = mayorName;
                    const mayorEl = document.querySelector('.mayor-name');
                    if (mayorEl) mayorEl.textContent = mayorName;
                }
                saveBtn.textContent = 'Saved!';
                setTimeout(() => { saveBtn.textContent = 'Save Changes'; }, 2000);
            });
        }

        if (page === 'civilians') {
            // Wire search input on the initial empty skeleton immediately,
            // then fetch data and re-render with results.
            this._attachCiviliansHandlers();
            this._fetchCivilians().then(() => {
                const container = document.getElementById('cityhall-content');
                if (container) {
                    container.innerHTML = this.renderCivilians();
                    this._attachCiviliansHandlers();
                }
            });
        }

        if (page === 'civilian-profile') {
            this._attachCivilianProfileHandlers();
        }
    }

    _attachCiviliansHandlers() {
        const searchBtn = document.getElementById('civilian-search-btn');
        const searchInput = document.getElementById('civilian-search-input');
        const prevBtn = document.getElementById('civilian-prev-btn');
        const nextBtn = document.getElementById('civilian-next-btn');

        const doSearch = () => {
            this.data.civiliansQuery = searchInput?.value.trim() || '';
            this.data.civiliansPage = 1;
            this._fetchCivilians().then(() => {
                const container = document.getElementById('cityhall-content');
                if (container) {
                    container.innerHTML = this.renderCivilians();
                    this._attachCiviliansHandlers();
                }
            });
        };

        if (searchBtn) searchBtn.addEventListener('click', doSearch);
        if (searchInput) {
            searchInput.addEventListener('keydown', (e) => {
                if (e.key === 'Enter') doSearch();
            });
        }

        if (prevBtn) prevBtn.addEventListener('click', () => {
            if (this.data.civiliansPage > 1) {
                this.data.civiliansPage--;
                this._fetchCivilians().then(() => {
                    const container = document.getElementById('cityhall-content');
                    if (container) {
                        container.innerHTML = this.renderCivilians();
                        this._attachCiviliansHandlers();
                    }
                });
            }
        });

        if (nextBtn) nextBtn.addEventListener('click', () => {
            const maxPage = Math.ceil(this.data.civiliansTotal / this.data.civiliansPageSize);
            if (this.data.civiliansPage < maxPage) {
                this.data.civiliansPage++;
                this._fetchCivilians().then(() => {
                    const container = document.getElementById('cityhall-content');
                    if (container) {
                        container.innerHTML = this.renderCivilians();
                        this._attachCiviliansHandlers();
                    }
                });
            }
        });

        document.querySelectorAll('[data-civilian-view]').forEach(btn => {
            btn.addEventListener('click', (e) => {
                e.stopPropagation();
                this.openCivilianProfile(btn.dataset.civilianView);
            });
        });

        document.querySelectorAll('.civilian-row').forEach(row => {
            row.addEventListener('click', () => this.openCivilianProfile(row.dataset.citizenid));
        });
    }

    _attachCivilianProfileHandlers() {
        const profile = this.data.civilianProfile;
        if (!profile) return;

        document.querySelectorAll('.civilian-profile-tab').forEach(tab => {
            tab.addEventListener('click', () => {
                this.data.civilianProfileTab = tab.dataset.tab || 'overview';
                const container = document.getElementById('cityhall-content');
                if (container) {
                    container.innerHTML = this.renderCivilianProfile();
                    this._attachCivilianProfileHandlers();
                }
            });
        });

        const backBtn = document.getElementById('civilian-profile-back');
        if (backBtn) {
            backBtn.addEventListener('click', () => {
                this.currentPage = 'civilians';
                this.loadPage('civilians');
            });
        }

        const saveIdentityBtn = document.getElementById('civilian-save-identity');
        if (saveIdentityBtn) {
            saveIdentityBtn.addEventListener('click', async () => {
                const payload = {
                    citizenId: profile.citizenId,
                    firstname: document.getElementById('civilian-firstname')?.value.trim() || '',
                    lastname: document.getElementById('civilian-lastname')?.value.trim() || '',
                    dob: document.getElementById('civilian-dob')?.value.trim() || '',
                    phone: document.getElementById('civilian-phone')?.value.trim() || '',
                    nationality: document.getElementById('civilian-nationality')?.value.trim() || '',
                };
                const res = await nuiRequest('civilian:updateIdentity', payload);
                if (!res || !res.ok) {
                    alert('Failed to update civilian identity.');
                    return;
                }
                await this.openCivilianProfile(profile.citizenId, true);
            });
        }

        const saveJobBtn = document.getElementById('civilian-save-job');
        if (saveJobBtn) {
            saveJobBtn.addEventListener('click', async () => {
                const jobName = document.getElementById('civilian-job-select')?.value;
                const res = await nuiRequest('civilian:updateJob', { citizenId: profile.citizenId, jobName });
                if (!res || !res.ok) {
                    alert('Failed to update civilian job.');
                    return;
                }
                await this.openCivilianProfile(profile.citizenId, true);
            });
        }

        document.querySelectorAll('[data-license-key]').forEach(toggle => {
            toggle.addEventListener('change', async () => {
                const res = await nuiRequest('civilian:toggleLicense', {
                    citizenId: profile.citizenId,
                    licenseKey: toggle.dataset.licenseKey,
                    enabled: toggle.checked,
                });
                if (!res || !res.ok) {
                    alert('License update failed.');
                    return;
                }
            });
        });

        document.querySelectorAll('[data-seize-plate]').forEach(btn => {
            btn.addEventListener('click', async () => {
                const plate = btn.dataset.seizePlate;
                const res = await nuiRequest('civilian:seizeVehicle', {
                    citizenId: profile.citizenId,
                    plate,
                });
                if (!res || !res.ok) {
                    alert('Failed to seize vehicle.');
                    return;
                }
                await this.openCivilianProfile(profile.citizenId, true);
            });
        });

        document.querySelectorAll('[data-record-type][data-record-id]').forEach(btn => {
            btn.addEventListener('click', async () => {
                const res = await nuiRequest('civilian:deleteRecord', {
                    recordType: btn.dataset.recordType,
                    recordId: Number(btn.dataset.recordId),
                });
                if (!res || !res.ok) {
                    alert('Failed to delete record.');
                    return;
                }
                await this.openCivilianProfile(profile.citizenId, true);
            });
        });

        const clearConvictions = document.getElementById('civilian-clear-convictions');
        if (clearConvictions) {
            clearConvictions.addEventListener('click', async () => {
                const res = await nuiRequest('civilian:clearConvictions', { citizenId: profile.citizenId });
                if (!res || !res.ok) {
                    alert('Failed to clear convictions.');
                    return;
                }
                await this.openCivilianProfile(profile.citizenId, true);
            });
        }
    }

    async publishAnnouncement() {
        const title = document.getElementById('announcement-title')?.value.trim();
        const body = document.getElementById('announcement-body')?.value.trim();
        const author = document.getElementById('announcement-author')?.value.trim() || 'Mayor';

        if (!title || !body) {
            alert('Title and body are required.');
            return;
        }

        const result = await nuiRequest('gov:createAnnouncement', { title, body, author });
        if (result && result.ok) {
            await this.refreshAnnouncements();
            this.loadPage('announcements');
        } else {
            alert('Failed to publish announcement.');
        }
    }

    exportLicensesReport() {
        const headers = ['License ID', 'Holder', 'Type', 'Issued', 'Expires', 'Status'];
        const rows = (this.data.licenses || []).map(license => [
            license.license_id || '',
            license.holder_name || license.name || '',
            license.license_type || license.type || '',
            license.issue_date || license.issued_at || '',
            license.expiry_date || license.expires_at || '',
            license.status || ''
        ]);

        const csv = [headers, ...rows]
            .map(row => row.map(value => `"${String(value ?? '').replace(/"/g, '""')}"`).join(','))
            .join('\n');

        const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
        const url = URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url;
        link.download = `licenses-report-${new Date().toISOString().slice(0, 10)}.csv`;
        document.body.appendChild(link);
        link.click();
        link.remove();
        URL.revokeObjectURL(url);
    }

    showLicenseDetails(licenseId) {
        const license = (this.data.licenses || []).find(item => String(item.id) === String(licenseId));
        if (!license) return;

        this.showModal(`
            <h3>License Details</h3>
            <div class="detail-list">
                <div class="detail-row"><span>License ID</span><strong>${license.id || 'N/A'}</strong></div>
                <div class="detail-row"><span>Owner</span><strong>${license.owner_name || 'Unknown'}</strong></div>
                <div class="detail-row"><span>Owner ID</span><strong>${license.owner_id || 'N/A'}</strong></div>
                <div class="detail-row"><span>Type</span><strong>${license.license_type || '-'}</strong></div>
                <div class="detail-row"><span>Issued</span><strong>${this.formatDate(license.issued_at)}</strong></div>
                <div class="detail-row"><span>Expires</span><strong>${this.formatDate(license.expires_at)}</strong></div>
                <div class="detail-row"><span>Status</span><strong>${license.status || 'unknown'}</strong></div>
                <div class="detail-row"><span>Notes</span><strong>${license.notes || 'None'}</strong></div>
            </div>
        `, () => {});
    }

    createLicense() {
        this.showModal(`
            <h3>Issue New License</h3>
            <div class="form-group">
                <label>Owner Type</label>
                <select class="form-input" id="license-owner-type">
                    <option value="citizen">Citizen</option>
                    <option value="business">Business</option>
                </select>
            </div>
            <div class="form-group">
                <label>Owner ID</label>
                <input type="text" class="form-input" id="license-owner-id" placeholder="Citizen ID or business ID">
            </div>
            <div class="form-group">
                <label>Owner Name</label>
                <input type="text" class="form-input" id="license-owner-name" placeholder="Full owner name">
            </div>
            <div class="form-group">
                <label>License Type</label>
                <select class="form-input" id="license-type">
                    <option value="drivers_license">Driver's License</option>
                    <option value="weapon_license">Weapon License</option>
                    <option value="business_license">Business License</option>
                    <option value="special_permit">Special Permit</option>
                </select>
            </div>
            <div class="form-group">
                <label>Notes</label>
                <textarea class="form-textarea" id="license-notes" rows="4" placeholder="Optional notes"></textarea>
            </div>
        `, async () => {
            const ownerType = document.getElementById('license-owner-type')?.value;
            const ownerId = document.getElementById('license-owner-id')?.value.trim();
            const ownerName = document.getElementById('license-owner-name')?.value.trim();
            const licenseType = document.getElementById('license-type')?.value;
            const notes = document.getElementById('license-notes')?.value.trim();

            if (!ownerType || !ownerId || !ownerName || !licenseType) {
                alert('Owner type, owner ID, owner name, and license type are required.');
                return;
            }

            const result = await nuiRequest('license:issue', {
                ownerType,
                ownerId,
                ownerName,
                licenseType,
                notes
            });

            if (result && result.ok) {
                await this.refreshAllData();
                this.loadPage('licenses');
            } else {
                alert(result?.message || 'Failed to issue license.');
            }
        });
    }

    renderCivilians() {
        const citizens = this.data.civilians || [];
        const total = this.data.civiliansTotal || 0;
        const page = this.data.civiliansPage || 1;
        const pageSize = this.data.civiliansPageSize || 12;
        const maxPage = Math.max(1, Math.ceil(total / pageSize));
        const start = total === 0 ? 0 : (page - 1) * pageSize + 1;
        const end = Math.min(page * pageSize, total);

        const rows = citizens.map(c => {
            const lics = (c.licenses || []).slice(0, 3).map(l =>
                `<span class="license-tag">${l}</span>`).join('');
            return `
                <tr class="civilian-row" data-citizenid="${c.citizenId || ''}"
                    style="cursor:pointer">
                    <td>${c.name || 'Unknown'}</td>
                    <td>${c.citizenId || '—'}</td>
                    <td>${c.dob || '—'}</td>
                    <td>${c.phone || '—'}</td>
                    <td>${c.nationality || '—'}</td>
                    <td>${c.job || 'Unemployed'}</td>
                    <td>${lics || '<span class="text-muted">None</span>'}</td>
                    <td>
                        <button class="btn-sm" data-civilian-view="${c.citizenId || ''}">View</button>
                    </td>
                </tr>`;
        }).join('');

        return `
            <div class="cityhall-page civilians-page">
                <div class="page-header-row">
                    <div>
                        <h1 class="page-title">Civilian Records</h1>
                        <p class="text-muted">Search and review all registered civilians in the city.</p>
                    </div>
                </div>
                <div class="civilians-search-bar">
                    <input type="text" id="civilian-search-input" class="form-input"
                        placeholder="Search by name, citizen ID, or phone..." value="${this.data.civiliansQuery || ''}">
                    <button class="btn-primary" id="civilian-search-btn">Search</button>
                </div>
                <div class="table-container">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>Name</th>
                                <th>Citizen ID</th>
                                <th>Date of Birth</th>
                                <th>Phone</th>
                                <th>Nationality</th>
                                <th>Job</th>
                                <th>Licenses</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody id="civilian-table-body">
                            ${rows || '<tr><td colspan="8" class="text-muted" style="text-align:center;padding:2rem">No results — use the search bar above to find civilians.</td></tr>'}
                        </tbody>
                    </table>
                </div>
                <div class="pagination-row">
                    <span class="text-muted">Showing ${start}–${end} of ${total} civilians</span>
                    <div class="pagination-btns">
                        <button class="btn-sm" id="civilian-prev-btn" ${page <= 1 ? 'disabled' : ''}>Previous</button>
                        <span style="padding:0 0.5rem">${page} / ${maxPage}</span>
                        <button class="btn-sm" id="civilian-next-btn" ${page >= maxPage ? 'disabled' : ''}>Next</button>
                    </div>
                </div>
            </div>`;
    }

    renderCivilianProfile() {
        const p = this.data.civilianProfile;
        if (!p) {
            return `
                <div class="cityhall-page civilian-profile-page">
                    <div class="page-header-row">
                        <button class="btn-secondary" id="civilian-profile-back">← Back to Civilian Records</button>
                    </div>
                    <div class="text-muted civilian-loading">Loading civilian profile...</div>
                </div>
            `;
        }

        const currentTab = this.data.civilianProfileTab || 'overview';
        const fullname = p.name || [p.firstname || '', p.lastname || ''].join(' ').trim() || 'Unknown';
        const titleSafe = String(fullname || 'Unknown');

        const jobs = (this.data.civilianJobs || []).map(job => {
            const selected = (job.label === p.job || job.name === p.jobName) ? 'selected' : '';
            return `<option value="${job.name}" ${selected}>${job.label}</option>`;
        }).join('');

        const licenseFlags = p.licenseFlags || {};
        const licenseRows = [
            { key: 'driver', label: 'Driver License' },
            { key: 'weapon', label: 'Weapon License' },
            { key: 'business', label: 'Business License' },
        ].map(lic => `
            <label class="detail-row license-toggle-row">
                <span>${lic.label}</span>
                <input type="checkbox" data-license-key="${lic.key}" ${licenseFlags[lic.key] === true ? 'checked' : ''}>
            </label>
        `).join('');

        const propertyRows = (p.properties || []).map(prop => `
            <div class="detail-row"><span>${prop.source || 'property'}</span><strong>${prop.address || prop.name || 'Unknown'}</strong></div>
        `).join('') || '<div class="text-muted">No properties found.</div>';

        const vehicleRows = (p.vehicles || []).map(v => `
            <tr>
                <td>${v.plate || '-'}</td>
                <td>${v.vehicle || 'Unknown'}</td>
                <td>${v.garage || '-'}</td>
                <td><button class="btn-sm btn-danger" data-seize-plate="${v.plate || ''}">Move To Gov Lockup</button></td>
            </tr>
        `).join('') || '<tr><td colspan="4" class="text-muted table-empty-cell">No vehicles found</td></tr>';

        const convictionRows = (p.convictions || []).map(r => `
            <div class="detail-row record-row">
                <span>#${r.id} ${r.title || 'Conviction'} (${r.prisonTime || 0}m)</span>
                <button class="btn-sm btn-danger" data-record-type="conviction" data-record-id="${r.id}">Delete</button>
            </div>
        `).join('') || '<div class="text-muted">No convictions found.</div>';

        const incidentRows = (p.incidents || []).map(r => `
            <div class="detail-row record-row">
                <span>${r.incidentId || r.id}: ${r.title || 'Incident'} (${r.status || 'unknown'})</span>
                <button class="btn-sm btn-danger" data-record-type="incident" data-record-id="${r.id}">Delete</button>
            </div>
        `).join('') || '<div class="text-muted">No incidents found.</div>';

        const photo = p.profilePicture || 'data:image/svg+xml,%3Csvg xmlns=%22http://www.w3.org/2000/svg%22 width=%22200%22 height=%22200%22 viewBox=%220 0 200 200%22%3E%3Crect width=%22200%22 height=%22200%22 fill=%22%23333%22/%3E%3Ccircle cx=%22100%22 cy=%2272%22 r=%2236%22 fill=%22%23666%22/%3E%3Crect x=%2248%22 y=%22122%22 width=%22104%22 height=%2252%22 rx=%2226%22 fill=%22%23555%22/%3E%3C/svg%3E';

        const profileHeader = `
            <div class="civilian-profile-header">
                <button class="btn-secondary" id="civilian-profile-back">← Back to Civilian Records</button>
                <div class="civilian-profile-heading">
                    <h1 class="page-title">${titleSafe} - Record Screen</h1>
                    <p class="text-muted">Official government records viewer for citizen ID ${p.citizenId || '-'}</p>
                </div>
            </div>

            <div class="civilian-profile-tabs">
                <button class="civilian-profile-tab ${currentTab === 'overview' ? 'active' : ''}" data-tab="overview">Overview</button>
                <button class="civilian-profile-tab ${currentTab === 'identity' ? 'active' : ''}" data-tab="identity">Identity</button>
                <button class="civilian-profile-tab ${currentTab === 'licenses' ? 'active' : ''}" data-tab="licenses">Licenses</button>
                <button class="civilian-profile-tab ${currentTab === 'vehicles' ? 'active' : ''}" data-tab="vehicles">Vehicles</button>
                <button class="civilian-profile-tab ${currentTab === 'properties' ? 'active' : ''}" data-tab="properties">Properties</button>
                <button class="civilian-profile-tab ${currentTab === 'criminal' ? 'active' : ''}" data-tab="criminal">Criminal</button>
            </div>
        `;

        const overviewPage = `
            <div class="civilian-record-summary-grid">
                <div class="summary-card"><span class="summary-label">Criminal Record Source</span><strong>Government Records</strong></div>
                <div class="summary-card"><span class="summary-label">Has Criminal Record</span><strong>${p.hasCriminalRecord ? 'True' : 'False'}</strong></div>
                <div class="summary-card"><span class="summary-label">Convictions</span><strong>${(p.convictions || []).length}</strong></div>
                <div class="summary-card"><span class="summary-label">Incidents</span><strong>${(p.incidents || []).length}</strong></div>
                <div class="summary-card"><span class="summary-label">Properties</span><strong>${(p.properties || []).length}</strong></div>
                <div class="summary-card"><span class="summary-label">Vehicles</span><strong>${(p.vehicles || []).length}</strong></div>
                <div class="summary-card"><span class="summary-label">Licenses</span><strong>${Object.values(licenseFlags || {}).filter(Boolean).length}</strong></div>
                <div class="summary-card"><span class="summary-label">Current Job</span><strong>${p.job || 'Unemployed'}</strong></div>
            </div>
            <div class="civilian-overview-panel">
                <img src="${photo}" alt="Profile" class="civilian-profile-photo">
                <div class="detail-list">
                    <div class="detail-row"><span>Name</span><strong>${fullname}</strong></div>
                    <div class="detail-row"><span>Date of Birth</span><strong>${p.dob || '-'}</strong></div>
                    <div class="detail-row"><span>Phone</span><strong>${p.phone || '-'}</strong></div>
                    <div class="detail-row"><span>Nationality</span><strong>${p.nationality || '-'}</strong></div>
                </div>
            </div>
        `;

        const identityPage = `
            <div class="detail-section civilian-section-card">
                <h3>Identity And Employment</h3>
                <div class="civilian-form-grid two-col">
                    <input id="civilian-firstname" class="form-input" placeholder="First name" value="${p.firstname || ''}">
                    <input id="civilian-lastname" class="form-input" placeholder="Last name" value="${p.lastname || ''}">
                    <input id="civilian-dob" class="form-input" placeholder="DOB" value="${p.dob || ''}">
                    <input id="civilian-phone" class="form-input" placeholder="Phone" value="${p.phone || ''}">
                    <input id="civilian-nationality" class="form-input" placeholder="Nationality" value="${p.nationality || ''}">
                    <input class="form-input" disabled value="${p.gender || ''}" placeholder="Gender">
                </div>
                <div class="form-actions">
                    <button class="btn-primary" id="civilian-save-identity">Save Identity Changes</button>
                </div>

                <div class="civilian-form-grid job-row">
                    <select id="civilian-job-select" class="form-input civilian-select">${jobs || '<option value="">No jobs loaded</option>'}</select>
                    <button class="btn-primary" id="civilian-save-job">Change Job</button>
                </div>
            </div>
        `;

        const licensesPage = `
            <div class="detail-section civilian-section-card">
                <h3>License Management</h3>
                <div class="detail-list">${licenseRows}</div>
            </div>
        `;

        const vehiclesPage = `
            <div class="detail-section civilian-section-card">
                <h3>Vehicles (Government Lockup Actions)</h3>
                <div class="table-container">
                    <table class="data-table">
                        <thead><tr><th>Plate</th><th>Vehicle</th><th>Garage</th><th>Action</th></tr></thead>
                        <tbody>${vehicleRows}</tbody>
                    </table>
                </div>
            </div>
        `;

        const propertiesPage = `
            <div class="detail-section civilian-section-card">
                <h3>Properties</h3>
                <div class="detail-list">${propertyRows}</div>
            </div>
        `;

        const criminalPage = `
            <div class="detail-section civilian-section-card">
                <h3>Criminal Records</h3>
                <div class="form-actions">
                    <button class="btn-danger" id="civilian-clear-convictions">Clear All Convictions</button>
                </div>
                <h4>Convictions</h4>
                <div class="detail-list">${convictionRows}</div>
                <h4 class="records-subheading">Incidents</h4>
                <div class="detail-list">${incidentRows}</div>
            </div>
        `;

        const bodyByTab = {
            overview: overviewPage,
            identity: identityPage,
            licenses: licensesPage,
            vehicles: vehiclesPage,
            properties: propertiesPage,
            criminal: criminalPage,
        };

        return `
            <div class="cityhall-page civilian-profile-page">
                ${profileHeader}
                <div class="civilian-profile-content">
                    ${bodyByTab[currentTab] || overviewPage}
                </div>
            </div>
        `;
    }

    async _fetchCivilians() {
        const result = await nuiRequest('civilian:search', {
            query: this.data.civiliansQuery || '',
            page: this.data.civiliansPage || 1,
            pageSize: this.data.civiliansPageSize || 12
        });
        if (result && result.ok) {
            this.data.civilians = result.civilians || [];
            this.data.civiliansTotal = result.total || 0;
        } else {
            this.data.civilians = [];
            this.data.civiliansTotal = 0;
        }
    }

    async _fetchCivilianJobs() {
        const result = await nuiRequest('civilian:getJobs', {});
        if (result && result.ok) {
            this.data.civilianJobs = result.jobs || [];
        } else {
            this.data.civilianJobs = [];
        }
    }

    async openCivilianProfile(citizenId, preserveTab = false) {
        const result = await nuiRequest('civilian:getProfile', { citizenId });
        if (!result || !result.ok) {
            alert('Could not load civilian profile.');
            return;
        }
        this.data.civilianProfile = result.profile || null;
        if (!preserveTab) {
            this.data.civilianProfileTab = 'overview';
        }
        await this._fetchCivilianJobs();
        this.currentPage = 'civilian-profile';
        this.loadPage('civilian-profile');
    }

    editTax(taxId) {
        const tax = this.data.taxes.find(t => t.id === taxId);
        if (!tax) return;

        this.showModal(`
            <h3>Edit ${tax.name}</h3>
            <p class="text-muted">${tax.description || 'No description provided.'}</p>
            <p>You are changing <strong>${tax.name}</strong> from <strong>${tax.rate}%</strong> to:</p>
            <input type="number" id="new-tax-rate" value="${tax.rate}" min="${tax.min}" max="${tax.max}" step="0.1" class="form-input">
            <label class="detail-row tax-toggle-row">
                <span>Enabled</span>
                <input type="checkbox" id="tax-enabled-toggle" ${tax.enabled ? 'checked' : ''}>
            </label>
            <p class="warning-text">This will affect all relevant entities as soon as it is saved.</p>
        `, async () => {
            const newRate = document.getElementById('new-tax-rate').value;
            const enabled = document.getElementById('tax-enabled-toggle')?.checked === true;
            const res = await nuiRequest('tax:update', { taxType: tax.id, rate: parseFloat(newRate) });
            const toggleRes = await nuiRequest('tax:toggle', { taxType: tax.id, enabled });

            if (res && res.ok && toggleRes && toggleRes.ok) {
                tax.rate = parseFloat(newRate);
                tax.enabled = enabled;
                await this.refreshAllData();
                this.loadPage('taxes');
                this.logAction(`Updated ${tax.name} to ${newRate}% (${enabled ? 'Enabled' : 'Disabled'})`);
            }
        });
    }

    adjustBudgetPrompt(department) {
        const dept = (this.data.budgets || []).find(item => item.department === department);
        if (!dept) return;

        this.showModal(`
            <h3>Adjust ${dept.name} Budget</h3>
            <div class="form-group">
                <label>Approved Monthly Budget</label>
                <input type="number" id="budget-adjust-value" class="form-input" min="0" step="100" value="${Number(dept.approvedMonthlyBudget || 0)}">
            </div>
        `, async () => {
            const monthlyBudget = Number(document.getElementById('budget-adjust-value')?.value || 0);
            const res = await nuiRequest('budget:update', { department: dept.department, monthlyBudget });
            if (res && res.ok) {
                await this.refreshAllData();
                this.loadPage('budgets');
            }
        });
    }

    async viewBudgetDetails(department) {
        const dept = (this.data.budgets || []).find(item => item.department === department);
        if (!dept) return;

        const snapshotRes = await nuiRequest('budget:getSnapshot', { department });
        const transactions = (snapshotRes && snapshotRes.ok && Array.isArray(snapshotRes.transactions)) ? snapshotRes.transactions : [];
        const txRows = transactions.slice(0, 8).map((tx) => {
            const type = String(tx.transaction_type || '').replace(/_/g, ' ');
            const category = String(tx.category || '').replace(/_/g, ' ');
            const amount = Number(tx.amount || 0);
            const actor = tx.actor_name || tx.actor_id || 'System';
            const reason = tx.reason || '-';
            const when = tx.created_at ? new Date(tx.created_at).toLocaleString() : '-';
            return `<tr><td>${when}</td><td>${type}</td><td>${category}</td><td>$${amount.toLocaleString()}</td><td>${actor}</td><td>${reason}</td></tr>`;
        }).join('');

        const infraState = this.data.infrastructure && this.data.infrastructure.departments
            ? this.data.infrastructure.departments[department]
            : null;

        const departmentUpgrades = (this.data.infrastructure && this.data.infrastructure.upgradeCatalog && this.data.infrastructure.upgradeCatalog[department]) || [];
        const upgradeOptions = departmentUpgrades.map((u) => `<option value="${u.key}">${u.name} ($${Number(u.cost || 0).toLocaleString()})</option>`).join('');

        const taxOptions = (this.data.taxes || []).map(tax => `<option value="${tax.id}">${tax.name}</option>`).join('');

        this.showModal(`
            <h3>${dept.name} Budget Details</h3>
            <p class="text-muted">${dept.description || 'Department operations, staffing, and service continuity funding.'}</p>
            <div class="detail-list">
                <div class="detail-row"><span>Approved Monthly Budget</span><strong>$${Number(dept.approvedMonthlyBudget || 0).toLocaleString()}</strong></div>
                <div class="detail-row"><span>Linked Society Account</span><strong>${dept.linkedSocietyName || '-'}</strong></div>
                <div class="detail-row"><span>Linked Society Balance</span><strong>$${Number(dept.societyBalance || 0).toLocaleString()}</strong></div>
                <div class="detail-row"><span>Spent This Month</span><strong>$${Number(dept.spentThisMonth || 0).toLocaleString()}</strong></div>
                <div class="detail-row"><span>Minimum Required</span><strong>$${Number(dept.minimumRequiredMonthly || 0).toLocaleString()}</strong></div>
                <div class="detail-row"><span>Recommended</span><strong>$${Number(dept.recommendedMonthlyBudget || 0).toLocaleString()}</strong></div>
                <div class="detail-row"><span>Projected Month-End</span><strong>$${Number(dept.projectedMonthEndBalance || 0).toLocaleString()}</strong></div>
                <div class="detail-row"><span>Status</span><strong>${dept.budgetStatus || 'Stable'}</strong></div>
                <div class="detail-row"><span>Salary Obligations</span><strong>$${Number(dept.salaryObligationMonthly || 0).toLocaleString()}</strong></div>
                <div class="detail-row"><span>Equipment/Fleet/Facility</span><strong>$${Number(dept.equipmentPlan || 0).toLocaleString()} / $${Number(dept.fleetPlan || 0).toLocaleString()} / $${Number(dept.facilityPlan || 0).toLocaleString()}</strong></div>
                <div class="detail-row"><span>Emergency Buffer</span><strong>$${Number(dept.emergencyBuffer || 0).toLocaleString()}</strong></div>
                <div class="detail-row"><span>Projected Remaining Obligations</span><strong>$${Number(dept.projectedObligationsRemaining || 0).toLocaleString()}</strong></div>
                <div class="detail-row"><span>Infrastructure Impact Stage</span><strong>${infraState ? Number(infraState.district_impact_stage || 1) : 1}</strong></div>
            </div>

            <div class="form-group">
                <label>Monthly Transaction History</label>
                <table class="data-table">
                    <thead>
                        <tr>
                            <th>When</th>
                            <th>Type</th>
                            <th>Category</th>
                            <th>Amount</th>
                            <th>Actor</th>
                            <th>Reason</th>
                        </tr>
                    </thead>
                    <tbody>${txRows || '<tr><td colspan="6" class="text-muted">No monthly transactions recorded yet.</td></tr>'}</tbody>
                </table>
            </div>

            <div class="form-group">
                <label>Update Approved Monthly Budget</label>
                <input type="number" id="budget-details-monthly" class="form-input" min="0" step="100" value="${Number(dept.approvedMonthlyBudget || 0)}">
            </div>

            <div class="form-group">
                <label>Treasury Funding Transfer To Linked Society</label>
                <input type="number" id="budget-fund-amount" class="form-input" min="0" step="100" placeholder="Funding amount">
                <input type="text" id="budget-fund-reason" class="form-input" placeholder="Funding reason">
            </div>

            <div class="form-group">
                <label>Log Department Spending</label>
                <select id="budget-spend-category" class="form-input">
                    <option value="salary">Salary</option>
                    <option value="equipment">Equipment</option>
                    <option value="vehicles">Vehicles</option>
                    <option value="maintenance">Maintenance</option>
                    <option value="upgrades">Upgrades</option>
                    <option value="operations">Operations</option>
                    <option value="emergency">Emergency</option>
                </select>
                <input type="number" id="budget-spend-amount" class="form-input" min="0" step="100" placeholder="Spend amount">
                <input type="text" id="budget-spend-reason" class="form-input" placeholder="Spend reason">
            </div>

            <div class="form-group">
                <label>Linked Tax Adjustment (Optional)</label>
                <select id="budget-tax-type" class="form-input"><option value="">No Change</option>${taxOptions}</select>
                <input type="number" id="budget-tax-rate" class="form-input" min="0" max="100" step="0.1" placeholder="New tax rate">
            </div>

            <div class="form-group">
                <label>Infrastructure Upgrades</label>
                <select id="budget-upgrade-key" class="form-input"><option value="">Select upgrade</option>${upgradeOptions}</select>
                <p class="text-muted">Upgrades are department-specific and affect live infrastructure simulation.</p>
                <div class="form-actions">
                    <button class="btn-primary" id="budget-buy-upgrade">Purchase Upgrade</button>
                    <button class="btn-danger" id="budget-uninstall-upgrade">Uninstall Upgrade</button>
                </div>
            </div>
        `, async () => {
            const monthlyBudget = Number(document.getElementById('budget-details-monthly')?.value || 0);
            const budgetRes = await nuiRequest('budget:update', { department: dept.department, monthlyBudget });

            const fundAmount = Number(document.getElementById('budget-fund-amount')?.value || 0);
            if (fundAmount > 0) {
                await nuiRequest('budget:allocate', {
                    department: dept.department,
                    amount: fundAmount,
                    reason: document.getElementById('budget-fund-reason')?.value || 'Treasury funding transfer'
                });
            }

            const spendAmount = Number(document.getElementById('budget-spend-amount')?.value || 0);
            if (spendAmount > 0) {
                await nuiRequest('budget:spend', {
                    department: dept.department,
                    amount: spendAmount,
                    category: document.getElementById('budget-spend-category')?.value || 'operations',
                    reason: document.getElementById('budget-spend-reason')?.value || 'Department expense'
                });
            }

            const taxType = document.getElementById('budget-tax-type')?.value || '';
            const taxRateRaw = document.getElementById('budget-tax-rate')?.value;
            if (taxType && taxRateRaw !== undefined && taxRateRaw !== '') {
                await nuiRequest('tax:update', { taxType, rate: Number(taxRateRaw) });
            }

            if (budgetRes && budgetRes.ok) {
                await this.refreshAllData();
                this.loadPage('budgets');
            }
        });

        setTimeout(() => {
            document.getElementById('budget-buy-upgrade')?.addEventListener('click', async () => {
                const upgradeKey = document.getElementById('budget-upgrade-key')?.value;
                if (!upgradeKey) return;
                const res = await nuiRequest('infra:buyUpgrade', { department: dept.department, upgradeKey });
                if (res && res.ok) {
                    await this.refreshAllData();
                    this.loadPage('budgets');
                    document.querySelector('.modal-overlay')?.remove();
                }
            });

            document.getElementById('budget-uninstall-upgrade')?.addEventListener('click', async () => {
                const upgradeKey = document.getElementById('budget-upgrade-key')?.value;
                if (!upgradeKey) return;
                if (!confirm('Uninstall this department upgrade? No refund will be issued.')) return;
                const res = await nuiRequest('infra:uninstallUpgrade', { department: dept.department, upgradeKey });
                if (res && res.ok) {
                    await this.refreshAllData();
                    this.loadPage('budgets');
                    document.querySelector('.modal-overlay')?.remove();
                }
            });
        }, 0);
    }

    async issueImmediateFine() {
        const targetCitizenId = document.getElementById('fine-citizen-id')?.value.trim();
        const amount = Number(document.getElementById('fine-amount')?.value || 0);
        const description = document.getElementById('fine-description')?.value.trim();

        if (!targetCitizenId || amount <= 0 || !description) {
            alert('Citizen ID, amount, and description are required.');
            return;
        }

        const result = await nuiRequest('fine:issueImmediate', { targetCitizenId, amount, description });
        if (result && result.ok) {
            await this.refreshAllData();
            this.loadPage('fines');
        } else {
            alert('Failed to issue fine.');
        }
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
        const cityHallWindow = document.querySelector('.window[data-app="cityhall"] .window-content') || document.body;
        cityHallWindow.appendChild(modal);

        document.getElementById('modal-confirm').addEventListener('click', () => {
            onConfirm();
            modal.remove();
        });
    }

    logAction(action) {
        const log = {
            timestamp: new Date().toLocaleString(),
            user: this.data.mayorName || 'Mayor',
            action: action,
            category: 'System',
            details: action
        };
        if (!this.data.auditLog) this.data.auditLog = [];
        this.data.auditLog.unshift(log);
    }

    renderCityHallSettings() {
        return `
            <div class="cityhall-page cityhall-settings-page">
                <h1 class="page-title">City Hall Settings</h1>
                <p class="text-muted">Configure government preferences and display options.</p>

                <div class="settings-section">
                    <h2>General</h2>
                    <div class="settings-row">
                        <div class="settings-label">
                            <span>City Name</span>
                            <small>Displayed in the City Hall header and announcements.</small>
                        </div>
                        <input type="text" id="settings-city-name" class="form-input" style="max-width:280px"
                            value="${this.data.cityName || 'City Hall'}" placeholder="City Hall">
                    </div>
                    <div class="settings-row">
                        <div class="settings-label">
                            <span>Mayor Display Name</span>
                            <small>Name shown in the top bar. Defaults to your character name.</small>
                        </div>
                        <input type="text" id="settings-mayor-name" class="form-input" style="max-width:280px"
                            value="${this.data.mayorName || ''}" placeholder="Unknown">
                    </div>
                    <div class="settings-actions">
                        <button class="btn-primary" id="settings-save-btn">Save Changes</button>
                    </div>
                </div>

                <div class="settings-section">
                    <h2>About</h2>
                    <div class="detail-list">
                        <div class="detail-row"><span>Resource</span><strong>pf-government</strong></div>
                        <div class="detail-row"><span>Framework</span><strong>QBCore</strong></div>
                        <div class="detail-row"><span>Version</span><strong>1.0.0</strong></div>
                    </div>
                </div>
            </div>
        `;
    }
}

// ============================================================================
// BUSINESSES MANAGER
// ============================================================================
class BusinessesManager {
    constructor() {
        this.currentPage = 'overview';
        this.currentBusinessId = null;
        this.data = {
            stats: {
                totalBusinesses: 0,
                activeBusinesses: 0,
                totalEmployees: 0,
                totalRevenue: 0,
                totalTaxesPaid: 0,
                alerts: {
                    unpaidTaxes: 0,
                    unlicensed: 0,
                    nonCompliant: 0
                }
            },
            businesses: [],
            jobOptions: []
        };
        this.init();
    }

    async init() {
        await this.refreshData();
        this.attachNavigationHandlers();
        this._updateTopbar();
        this.renderPage(this.currentPage, document.getElementById('businesses-content'));
    }

    async refreshData() {
        try {
            const [allRes, statsRes, jobsRes] = await Promise.all([
                nuiRequest('business:getAll', {}),
                nuiRequest('business:getStats', {}),
                nuiRequest('business:getJobOptions', {})
            ]);
            if (allRes && Array.isArray(allRes.businesses)) {
                this.data.businesses = allRes.businesses;
            }
            if (statsRes && statsRes.stats) {
                this.data.stats = { ...this.data.stats, ...statsRes.stats };
            }
            if (jobsRes && Array.isArray(jobsRes.jobs)) {
                this.data.jobOptions = jobsRes.jobs;
            } else if (jobsRes && Array.isArray(jobsRes.options)) {
                this.data.jobOptions = jobsRes.options;
            }
        } catch (e) {
            console.error('BusinessesManager init error:', e);
        }
    }

    _updateTopbar() {
        const s = this.data.stats;
        const a = s.alerts || {};
        const metricMap = {
            'businesses-total-count': s.totalBusinesses || 0,
            'businesses-total-employees': s.totalEmployees || 0,
            'businesses-total-revenue': `$${Number(s.totalRevenue || 0).toLocaleString()}`,
            'businesses-total-taxes': `$${Number(s.totalTaxesPaid || 0).toLocaleString()}`
        };

        Object.entries(metricMap).forEach(([id, value]) => {
            const element = document.getElementById(id);
            if (element) element.textContent = value;
        });

        const alertMap = {
            'businesses-alert-outstanding': `${a.unpaidTaxes || 0} tax delinquencies`,
            'businesses-alert-license': `${a.unlicensed || 0} unlicensed businesses`,
            'businesses-alert-flagged': `${a.nonCompliant || 0} flagged businesses`
        };

        Object.entries(alertMap).forEach(([id, value]) => {
            const element = document.getElementById(id);
            if (element) element.textContent = value;
        });
    }

    attachNavigationHandlers() {
        document.querySelectorAll('.businesses-nav-item').forEach(item => {
            item.addEventListener('click', () => {
                const container = document.getElementById('businesses-content');
                this.renderPage(item.dataset.page, container);
            });
        });
    }

    renderPage(page, container) {
        if (!container) return;
        this.currentPage = page;
        const activePage = page === 'details' ? 'registry' : page;
        document.querySelectorAll('.businesses-nav-item').forEach(item => {
            item.classList.toggle('active', item.dataset.page === activePage);
        });
        const pages = {
            overview: () => this.renderOverview(),
            registry: () => this.renderRegistry(),
            analytics: () => this.renderAnalytics(),
            employees: () => this.renderEmployees(),
            compliance: () => this.renderCompliance(),
            taxes: () => this.renderTaxes(),
            audit: () => this.renderAuditLog(),
            settings: () => this.renderSettings()
        };

        if (page === 'details' && !this.currentBusinessId) {
            this.currentPage = 'registry';
            container.innerHTML = this.renderRegistry();
        } else {
            container.innerHTML = (pages[page] || pages.overview)();
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
        const s = this.data.stats;
        const a = s.alerts || {};
        const top5 = [...this.data.businesses]
            .sort((a, b) => Number(b.total_revenue || 0) - Number(a.total_revenue || 0))
            .slice(0, 5);
        const watchlist = this.data.businesses.filter(b =>
            b.compliance_status === 'non_compliant' || b.compliance_status === 'flagged' || b.compliance_status === 'warning'
        ).slice(0, 5);

        return `
            <div class="businesses-page">
                <div class="page-title">Business Overview</div>
                <div class="overview-kpi-grid">
                    <div class="kpi-card">
                        <div class="kpi-label">Total Businesses</div>
                        <div class="kpi-value">${s.totalBusinesses || 0}</div>
                    </div>
                    <div class="kpi-card">
                        <div class="kpi-label">Active Businesses</div>
                        <div class="kpi-value">${s.activeBusinesses || 0}</div>
                    </div>
                    <div class="kpi-card">
                        <div class="kpi-label">Total Employees</div>
                        <div class="kpi-value">${s.totalEmployees || 0}</div>
                    </div>
                    <div class="kpi-card">
                        <div class="kpi-label">Total Revenue</div>
                        <div class="kpi-value">$${Number(s.totalRevenue || 0).toLocaleString()}</div>
                    </div>
                    <div class="kpi-card">
                        <div class="kpi-label">Taxes Paid</div>
                        <div class="kpi-value">$${Number(s.totalTaxesPaid || 0).toLocaleString()}</div>
                    </div>
                </div>
                <div class="overview-alerts">
                    <div class="alert-item ${a.unpaidTaxes > 0 ? 'alert-danger' : ''}">
                        <span>Unpaid Tax Bills</span><strong>${a.unpaidTaxes || 0}</strong>
                    </div>
                    <div class="alert-item ${a.unlicensed > 0 ? 'alert-warning' : ''}">
                        <span>Unlicensed</span><strong>${a.unlicensed || 0}</strong>
                    </div>
                    <div class="alert-item ${a.nonCompliant > 0 ? 'alert-danger' : ''}">
                        <span>Non-Compliant</span><strong>${a.nonCompliant || 0}</strong>
                    </div>
                </div>
                ${top5.length ? `
                <div class="overview-section">
                    <h3>Top Businesses by Revenue</h3>
                    <div class="top-list">
                        ${top5.map((b, i) => `
                            <div class="top-list-item">
                                <div class="top-rank">${i + 1}</div>
                                <div class="top-info">
                                    <div class="top-name">${b.business_name}</div>
                                    <div class="top-meta">${b.business_type || '-'} • $${Number(b.total_revenue || 0).toLocaleString()}</div>
                                </div>
                            </div>
                        `).join('')}
                    </div>
                </div>` : ''}
                ${watchlist.length ? `
                <div class="overview-section">
                    <h3>Compliance Watchlist</h3>
                    <div class="watchlist">
                        ${watchlist.map(b => `
                            <div class="watchlist-item">
                                <strong>${b.business_name}</strong>
                                <span>${this.getStatusBadge(b.compliance_status)}</span>
                                <span>${b.owner_name || 'Unassigned'}</span>
                            </div>
                        `).join('')}
                    </div>
                </div>` : ''}
            </div>
        `;
    }

    renderRegistry() {
        const businessTypeOptions = ['Mechanic', 'Restaurant', 'Cafe', 'Dealership', 'Retail'];
        const allTypes = [...new Set([...
            businessTypeOptions,
            ...this.data.businesses.map(b => b.business_type).filter(Boolean)
        ])].sort((a, b) => String(a).localeCompare(String(b)));

        const rows = this.data.businesses.map(business => `
            <tr data-business-id="${business.business_id}">
                <td>${business.business_name}</td>
                <td>${business.owner_name || 'Unassigned'}</td>
                <td>${business.business_type || '-'}</td>
                <td>${this.getStatusBadge(business.compliance_status)}</td>
                <td>${this.getStatusBadge(business.business_status || 'active')}</td>
                <td>${business.employee_count || 0}</td>
                <td>$${Number(business.total_revenue || 0).toLocaleString()}</td>
                <td>${this.getStatusBadge(business.license_status)}</td>
                <td>
                    <div class="action-menu">
                        <button class="kebab-btn" data-menu-toggle="${business.business_id}">⋯</button>
                        <div class="action-dropdown" data-menu="${business.business_id}">
                            <button class="action-item" data-action="view" data-business-id="${business.business_id}">View Details</button>
                            <button class="action-item" data-action="location" data-business-id="${business.business_id}">Edit Location</button>
                            <button class="action-item" data-action="transfer" data-business-id="${business.business_id}">Transfer Ownership</button>
                            <button class="action-item" data-action="remove" data-business-id="${business.business_id}">Remove Owner</button>
                            <button class="action-item" data-action="toggle-status" data-business-id="${business.business_id}">${String(business.business_status || 'active').toLowerCase() === 'closed' ? 'Reopen Business' : 'Close Business'}</button>
                            <button class="action-item action-danger" data-action="delete" data-business-id="${business.business_id}">Delete Business</button>
                        </div>
                    </div>
                </td>
            </tr>
        `).join('') || '<tr><td colspan="9" class="text-muted">No businesses registered.</td></tr>';

        return `
            <div class="businesses-page">
                <div class="page-title">Business Registry</div>
                <div class="filter-bar">
                    <input type="text" class="search-input" id="registry-search" placeholder="Search businesses by name or owner">
                    <select class="setting-select" id="registry-type-filter">
                        <option value="">All Types</option>
                        ${allTypes.map(type => `<option>${type}</option>`).join('')}
                    </select>
                    <select class="setting-select" id="registry-job-filter">
                        <option value="">All Jobs</option>
                        ${(this.data.jobOptions || []).map(option => `<option value="${option.job}">${option.label || option.job}</option>`).join('')}
                    </select>
                    <select class="setting-select" id="registry-status-filter">
                        <option value="">All Status</option>
                        <option value="compliant">Compliant</option>
                        <option value="warning">Warning</option>
                        <option value="non_compliant">Non-Compliant</option>
                    </select>
                    <button class="btn-primary" id="business-registry-create">Create Business</button>
                    <button class="btn-secondary" id="business-registry-export">Export Report</button>
                </div>
                <div class="registry-layout">
                    <div class="table-container">
                        <table class="data-table" id="registry-table">
                            <thead>
                                <tr>
                                    <th>Business</th>
                                    <th>Owner</th>
                                    <th>Type</th>
                                    <th>Compliance</th>
                                    <th>Operational</th>
                                    <th>Employees</th>
                                    <th>Total Revenue</th>
                                    <th>License</th>
                                    <th>Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${rows}
                            </tbody>
                        </table>
                    </div>
                    <div class="business-details-panel" id="business-details-panel">
                        ${this.data.businesses[0] ? this.renderBusinessDetails(this.data.businesses[0]) : '<div class="text-muted">Select a business to view details.</div>'}
                    </div>
                </div>
            </div>
        `;
    }

    renderBusinessDetails(business) {
        if (!business) return '<div class="text-muted">No business selected.</div>';
        return `
            <div class="details-header">
                <h3>${business.business_name}</h3>
                <div class="details-subtitle">${business.business_type || '-'}</div>
            </div>
            <div class="details-tabs">
                <button class="details-tab active" data-tab="overview">Overview</button>
                <button class="details-tab" data-tab="compliance">Compliance</button>
            </div>
            <div class="details-section active" data-tab-content="overview">
                <div class="detail-row"><span>Owner</span><strong>${business.owner_name || 'Unassigned'}</strong></div>
                <div class="detail-row"><span>Owner ID</span><strong>${business.owner_id || 'N/A'}</strong></div>
                <div class="detail-row"><span>Type</span><strong>${business.business_type || '-'}</strong></div>
                <div class="detail-row"><span>Employees</span><strong>${business.employee_count || 0}</strong></div>
                <div class="detail-row"><span>Total Revenue</span><strong>$${Number(business.total_revenue || 0).toLocaleString()}</strong></div>
                <div class="detail-row"><span>Taxes Paid</span><strong>$${Number(business.total_taxes_paid || 0).toLocaleString()}</strong></div>
                <div class="detail-row"><span>Location</span><strong>${this.formatBusinessLocation(business)}</strong></div>
                <div class="detail-row"><span>Registered</span><strong>${business.registered_at ? new Date(business.registered_at).toLocaleDateString() : 'N/A'}</strong></div>
            </div>
            <div class="details-section" data-tab-content="compliance">
                <div class="detail-row"><span>License Status</span><strong>${this.getStatusBadge(business.license_status)}</strong></div>
                <div class="detail-row"><span>Compliance</span><strong>${this.getStatusBadge(business.compliance_status)}</strong></div>
                <div class="detail-row"><span>Notes</span><strong>${business.notes || 'None'}</strong></div>
            </div>
        `;
    }

    renderDetailsPage() {
        const business = this.data.businesses.find(b => b.business_id === this.currentBusinessId);
        if (!business) {
            return `
                <div class="business-details-page">
                    <div class="page-title">Business Details</div>
                    <p class="text-muted">Select a business from the registry.</p>
                </div>
            `;
        }

        return `
            <div class="business-details-page">
                <div class="details-hero">
                    <button class="btn-secondary" id="back-to-registry">Back to Registry</button>
                    <div>
                        <div class="page-title">${business.business_name}</div>
                        <div class="details-subtitle">${business.business_type || '-'} • Owner: ${business.owner_name || 'Unassigned'}</div>
                    </div>
                    <div class="details-actions">
                        <button class="btn-secondary" data-action="location" data-business-id="${business.business_id}">Edit Location</button>
                        ${!business.owner_name || business.owner_name === 'Unassigned'
                            ? `<button class="btn-primary" data-action="assign" data-business-id="${business.business_id}">Assign Owner</button>`
                            : `
                                <button class="btn-secondary" data-action="transfer" data-business-id="${business.business_id}">Transfer Ownership</button>
                                <button class="btn-secondary" data-action="remove" data-business-id="${business.business_id}">Remove Owner</button>
                            `
                        }
                    </div>
                </div>
                <div class="details-grid">
                    <div class="panel-card">
                        <h3>Business Profile</h3>
                        <div class="detail-list">
                            <div class="detail-row"><span>Owner</span><strong>${business.owner_name || 'Unassigned'}</strong></div>
                            <div class="detail-row"><span>Owner ID</span><strong>${business.owner_id || 'N/A'}</strong></div>
                            <div class="detail-row"><span>Type</span><strong>${business.business_type || '-'}</strong></div>
                            <div class="detail-row"><span>Location</span><strong>${this.formatBusinessLocation(business)}</strong></div>
                            <div class="detail-row"><span>Registered</span><strong>${business.registered_at ? new Date(business.registered_at).toLocaleDateString() : 'N/A'}</strong></div>
                        </div>
                    </div>
                    <div class="panel-card">
                        <h3>Financial Summary</h3>
                        <div class="detail-list">
                            <div class="detail-row"><span>Total Revenue</span><strong>$${Number(business.total_revenue || 0).toLocaleString()}</strong></div>
                            <div class="detail-row"><span>Taxes Paid</span><strong>$${Number(business.total_taxes_paid || 0).toLocaleString()}</strong></div>
                            <div class="detail-row"><span>Employee Count</span><strong>${business.employee_count || 0}</strong></div>
                        </div>
                    </div>
                    <div class="panel-card">
                        <h3>Compliance</h3>
                        <div class="detail-list">
                            <div class="detail-row"><span>License</span><strong>${this.getStatusBadge(business.license_status)}</strong></div>
                            <div class="detail-row"><span>Compliance</span><strong>${this.getStatusBadge(business.compliance_status)}</strong></div>
                            <div class="detail-row"><span>Notes</span><strong>${business.notes || 'None'}</strong></div>
                        </div>
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

        const wire = (selector, action) => container.querySelectorAll(selector).forEach(btn => {
            btn.addEventListener('click', () => {
                const businessId = btn.dataset.businessId;
                const business = this.data.businesses.find(b => b.business_id === businessId);
                if (!business) return;
                action(businessId, business);
            });
        });

        wire('[data-action="assign"],[data-action="transfer"]', (businessId, business) => {
            this.showModal(`
                <h3>${business.owner_name && business.owner_name !== 'Unassigned' ? 'Transfer' : 'Assign'} Ownership</h3>
                <p>Business: <strong>${business.business_name}</strong></p>
                <div class="form-group"><label>Citizen ID</label><input type="text" class="form-input" id="new-owner-id" placeholder="e.g. ABC123"></div>
                <div class="form-group"><label>Owner Name</label><input type="text" class="form-input" id="new-owner-name" placeholder="Full name"></div>
            `, async () => {
                const ownerId = document.getElementById('new-owner-id').value.trim();
                const ownerName = document.getElementById('new-owner-name').value.trim();
                if (!ownerId || !ownerName) return;
                const res = await nuiRequest('business:updateOwner', { businessId, ownerId, ownerName });
                if (res && res.ok) {
                    business.owner_id = ownerId;
                    business.owner_name = ownerName;
                    this.renderPage('details', container);
                }
            });
        });

        wire('[data-action="remove"]', (businessId, business) => {
            this.showModal(`
                <h3>Remove Owner</h3>
                <p class="warning-text">Remove current owner from <strong>${business.business_name}</strong>?</p>
            `, async () => {
                const res = await nuiRequest('business:updateOwner', { businessId, ownerId: '', ownerName: 'Unassigned' });
                if (res && res.ok) {
                    business.owner_id = '';
                    business.owner_name = 'Unassigned';
                    this.renderPage('details', container);
                }
            });
        });

        wire('[data-action="location"]', (businessId, business) => {
            this.openBusinessLocationModal(businessId, business, () => {
                this.renderPage('details', container);
            });
        });
    }

    openBusinessLocationModal(businessId, business, onSaved) {
        this.showModal(`
            <h3>Edit Business Location</h3>
            <p>Business: <strong>${business.business_name}</strong></p>
            <div class="form-group"><label>Location X</label><input type="number" step="0.0001" class="form-input" id="edit-business-location-x" value="${business.location_x ?? ''}" placeholder="Optional"></div>
            <div class="form-group"><label>Location Y</label><input type="number" step="0.0001" class="form-input" id="edit-business-location-y" value="${business.location_y ?? ''}" placeholder="Optional"></div>
            <div class="form-group"><label>Location Z</label><input type="number" step="0.0001" class="form-input" id="edit-business-location-z" value="${business.location_z ?? ''}" placeholder="Optional"></div>
            <div class="form-group"><label>Location Address</label><input type="text" class="form-input" id="edit-business-location-address" value="${this.escapeHtml(business.location_address || '')}" placeholder="Optional"></div>
        `, async () => {
            const xRaw = document.getElementById('edit-business-location-x')?.value;
            const yRaw = document.getElementById('edit-business-location-y')?.value;
            const zRaw = document.getElementById('edit-business-location-z')?.value;
            const addressRaw = document.getElementById('edit-business-location-address')?.value || '';

            const locationX = xRaw === '' || xRaw == null ? null : Number(xRaw);
            const locationY = yRaw === '' || yRaw == null ? null : Number(yRaw);
            const locationZ = zRaw === '' || zRaw == null ? null : Number(zRaw);
            const locationAddress = String(addressRaw).trim();

            const res = await nuiRequest('business:updateLocation', {
                businessId,
                locationX,
                locationY,
                locationZ,
                locationAddress
            });

            if (res && res.ok) {
                business.location_x = locationX;
                business.location_y = locationY;
                business.location_z = locationZ;
                business.location_address = locationAddress;
                if (typeof onSaved === 'function') onSaved();
            }
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
        const s = this.data.stats;
        const byType = {};
        this.data.businesses.forEach(b => {
            const t = b.business_type || 'Other';
            if (!byType[t]) byType[t] = { count: 0, revenue: 0 };
            byType[t].count++;
            byType[t].revenue += Number(b.total_revenue || 0);
        });
        const maxRev = Math.max(...Object.values(byType).map(v => v.revenue), 1);
        const typeRows = Object.entries(byType)
            .sort((a, b) => b[1].revenue - a[1].revenue)
            .map(([t, v]) => `
                <div class="chart-row">
                    <span class="chart-label">${t}</span>
                    <div class="chart-bar-container">
                        <div class="chart-bar-fill" style="width: ${Math.round(v.revenue / maxRev * 100)}%; background: var(--primary);"></div>
                    </div>
                    <span class="chart-value">$${Number(v.revenue).toLocaleString()}</span>
                </div>
            `).join('') || '<p class="text-muted">No data.</p>';

        const top5 = [...this.data.businesses]
            .sort((a, b) => Number(b.total_revenue || 0) - Number(a.total_revenue || 0))
            .slice(0, 5);
        const top5Rows = top5.map((b, i) => `
            <div class="top-list-item">
                <div class="top-rank">${i + 1}</div>
                <div class="top-info">
                    <div class="top-name">${b.business_name}</div>
                    <div class="top-meta">${b.business_type || '-'} • $${Number(b.total_revenue || 0).toLocaleString()} revenue</div>
                </div>
            </div>
        `).join('') || '<p class="text-muted">No data.</p>';

        const nonCompliant = this.data.businesses.filter(
            b => b.compliance_status === 'non_compliant' || b.compliance_status === 'flagged'
        ).length;

        return `
            <div class="businesses-page">
                <div class="page-title">Business Analytics</div>
                <div class="analytics-kpi-grid">
                    <div class="analytics-kpi-card">
                        <div class="kpi-icon" style="background: var(--success-bg); color: var(--success);"><span>$</span></div>
                        <div>
                            <div class="kpi-label">Total Revenue</div>
                            <div class="kpi-value">$${Number(s.totalRevenue || 0).toLocaleString()}</div>
                        </div>
                    </div>
                    <div class="analytics-kpi-card">
                        <div class="kpi-icon" style="background: var(--info-bg); color: var(--info);"><span>📊</span></div>
                        <div>
                            <div class="kpi-label">Active Businesses</div>
                            <div class="kpi-value">${s.activeBusinesses || 0}</div>
                        </div>
                    </div>
                    <div class="analytics-kpi-card">
                        <div class="kpi-icon" style="background: var(--warning-bg); color: var(--warning);"><span>👥</span></div>
                        <div>
                            <div class="kpi-label">Total Employment</div>
                            <div class="kpi-value">${s.totalEmployees || 0}</div>
                        </div>
                    </div>
                    <div class="analytics-kpi-card">
                        <div class="kpi-icon" style="background: var(--danger-bg); color: var(--danger);"><span>⚠</span></div>
                        <div>
                            <div class="kpi-label">Compliance Issues</div>
                            <div class="kpi-value">${nonCompliant}</div>
                        </div>
                    </div>
                </div>
                <div class="analytics-charts-grid">
                    <div class="analytics-chart-card">
                        <h3>Revenue by Business Type</h3>
                        <div class="chart-list">${typeRows}</div>
                    </div>
                    <div class="analytics-chart-card">
                        <h3>Top 5 Businesses by Revenue</h3>
                        <div class="top-list">${top5Rows}</div>
                    </div>
                </div>
            </div>
        `;
    }

    renderEmployees() {
        const rows = this.data.businesses.map(b => `
            <tr>
                <td>${b.business_name}</td>
                <td>${b.employee_count || 0}</td>
                <td>${b.business_type || '-'}</td>
                <td>${this.getStatusBadge(b.compliance_status)}</td>
            </tr>
        `).join('') || '<tr><td colspan="4" class="text-muted">No data.</td></tr>';

        return `
            <div class="businesses-page">
                <div class="page-title">Employees Overview</div>
                <div class="dashboard-cards">
                    <div class="dash-card">
                        <div>
                            <div class="dash-card-label">Total Employed</div>
                            <div class="dash-card-value">${this.data.stats.totalEmployees || 0}</div>
                        </div>
                    </div>
                </div>
                <div class="table-container">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>Business</th>
                                <th>Employees</th>
                                <th>Type</th>
                                <th>Compliance</th>
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

    renderCompliance() {
        const compliant = this.data.businesses.filter(b => b.compliance_status === 'compliant').length;
        const warning = this.data.businesses.filter(b => b.compliance_status === 'warning').length;
        const nonCompliant = this.data.businesses.filter(b =>
            b.compliance_status === 'non_compliant' || b.compliance_status === 'flagged'
        ).length;
        const total = this.data.businesses.length || 1;
        const rate = Math.round((compliant / total) * 100);

        const rows = this.data.businesses.filter(b => b.compliance_status !== 'compliant').map(b => `
            <tr>
                <td><strong>${b.business_name}</strong></td>
                <td>${this.getStatusBadge(b.license_status)}</td>
                <td>${this.getStatusBadge(b.compliance_status)}</td>
                <td>${b.owner_name || 'Unassigned'}</td>
                <td>${b.notes || '-'}</td>
            </tr>
        `).join('') || '<tr><td colspan="5" class="text-muted">All businesses compliant.</td></tr>';

        return `
            <div class="businesses-page">
                <div class="compliance-header">
                    <h1 class="page-title">Business Compliance</h1>
                </div>
                <div class="compliance-dashboard">
                    <div class="compliance-kpi">
                        <div class="gauge-value" style="color: var(--success);">${rate}%</div>
                        <div class="gauge-label">Compliance Rate</div>
                    </div>
                    <div class="compliance-stats">
                        <div class="compliance-stat-item">
                            <div class="stat-icon" style="background: var(--success-bg); color: var(--success);">✓</div>
                            <div><div class="stat-value">${compliant}</div><div class="stat-label">Fully Compliant</div></div>
                        </div>
                        <div class="compliance-stat-item">
                            <div class="stat-icon" style="background: var(--warning-bg); color: var(--warning);">⚠</div>
                            <div><div class="stat-value">${warning}</div><div class="stat-label">Minor Issues</div></div>
                        </div>
                        <div class="compliance-stat-item">
                            <div class="stat-icon" style="background: var(--danger-bg); color: var(--danger);">✕</div>
                            <div><div class="stat-value">${nonCompliant}</div><div class="stat-label">Non-Compliant</div></div>
                        </div>
                    </div>
                </div>
                <div class="compliance-table-container">
                    <table class="data-table compliance-table">
                        <thead>
                            <tr>
                                <th>Business</th>
                                <th>License</th>
                                <th>Compliance</th>
                                <th>Owner</th>
                                <th>Notes</th>
                            </tr>
                        </thead>
                        <tbody>${rows}</tbody>
                    </table>
                </div>
            </div>
        `;
    }

    renderTaxes() {
        const rows = this.data.businesses.map(b => `
            <tr>
                <td><strong>${b.business_name}</strong></td>
                <td>${b.business_type || '-'}</td>
                <td>$${Number(b.total_taxes_paid || 0).toLocaleString()}</td>
                <td>${this.getStatusBadge(b.compliance_status)}</td>
            </tr>
        `).join('') || '<tr><td colspan="4" class="text-muted">No data.</td></tr>';

        return `
            <div class="businesses-page">
                <div class="taxes-header">
                    <h1 class="page-title">Business Taxes & Revenue</h1>
                </div>
                <div class="table-container">
                    <table class="data-table taxes-table">
                        <thead>
                            <tr>
                                <th>Business</th>
                                <th>Type</th>
                                <th>Taxes Paid</th>
                                <th>Compliance</th>
                            </tr>
                        </thead>
                        <tbody>${rows}</tbody>
                    </table>
                </div>
            </div>
        `;
    }

    renderAuditLog() {
        return `
            <div class="businesses-page">
                <div class="page-title">Audit Log</div>
                <p class="text-muted">Business audit log entries are recorded in the City Hall section. Use City Hall &gt; Audit Log to view detailed government activity history.</p>
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
                    </div>
                </div>
                <div class="panel-card">
                    <h3>Policy Notes</h3>
                    <p class="text-muted">This module is read-only for business owners. All actions are reserved for government oversight and enforcement.</p>
                </div>
            </div>
        `;
    }

    exportBusinessRegistryReport(businesses) {
        const headers = ['Business ID', 'Business Name', 'Owner', 'Type', 'Compliance', 'Employees', 'Total Revenue', 'License'];
        const rows = businesses.map(business => [
            business.business_id || '',
            business.business_name || '',
            business.owner_name || 'Unassigned',
            business.business_type || '-',
            business.compliance_status || '',
            business.employee_count || 0,
            business.total_revenue || 0,
            business.license_status || ''
        ]);

        const csv = [headers, ...rows]
            .map(row => row.map(value => `"${String(value ?? '').replace(/"/g, '""')}"`).join(','))
            .join('\n');

        const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
        const url = URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url;
        link.download = `business-registry-${new Date().toISOString().slice(0, 10)}.csv`;
        document.body.appendChild(link);
        link.click();
        link.remove();
        URL.revokeObjectURL(url);
    }

    attachRegistryHandlers(container) {
        const tableRows = container.querySelectorAll('#registry-table [data-business-id]');
        const detailsPanel = container.querySelector('#business-details-panel');
        const searchInput = container.querySelector('#registry-search');
        const typeFilter = container.querySelector('#registry-type-filter');
        const jobFilter = container.querySelector('#registry-job-filter');
        const statusFilter = container.querySelector('#registry-status-filter');
        const exportBtn = container.querySelector('#business-registry-export');
        const createBtn = container.querySelector('#business-registry-create');

        if (!detailsPanel) return;

        const setActiveRow = (row) => {
            tableRows.forEach(r => r.classList.remove('active-row'));
            row.classList.add('active-row');
        };

        tableRows.forEach(row => {
            row.addEventListener('click', (e) => {
                if (e.target.closest('.action-menu')) return;
                const businessId = row.dataset.businessId;
                const business = this.data.businesses.find(b => b.business_id === businessId);
                if (!business) return;
                detailsPanel.innerHTML = this.renderBusinessDetails(business);
                this.attachDetailsTabs(detailsPanel);
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
                const business = this.data.businesses.find(b => b.business_id === businessId);
                if (!business) return;

                if (actionType === 'view') {
                    this.openBusinessDetails(businessId, container.closest('#businesses-content'));
                } else if (actionType === 'transfer') {
                    this.showModal(`
                        <h3>Transfer Ownership</h3>
                        <p>Business: <strong>${business.business_name}</strong></p>
                        <div class="form-group"><label>Citizen ID</label><input type="text" class="form-input" id="transfer-owner-id" placeholder="e.g. ABC123"></div>
                        <div class="form-group"><label>Owner Name</label><input type="text" class="form-input" id="transfer-owner-name" placeholder="Full name"></div>
                    `, async () => {
                        const ownerId = document.getElementById('transfer-owner-id').value.trim();
                        const ownerName = document.getElementById('transfer-owner-name').value.trim();
                        if (!ownerId || !ownerName) return;
                        const res = await nuiRequest('business:updateOwner', { businessId, ownerId, ownerName });
                        if (res && res.ok) {
                            business.owner_id = ownerId;
                            business.owner_name = ownerName;
                            this.renderPage('registry', container.closest('#businesses-content'));
                        }
                    });
                } else if (actionType === 'location') {
                    this.openBusinessLocationModal(businessId, business, async () => {
                        await this.refreshData();
                        this._updateTopbar();
                        this.renderPage('registry', container.closest('#businesses-content'));
                    });
                } else if (actionType === 'remove') {
                    this.showModal(`
                        <h3>Remove Owner</h3>
                        <p class="warning-text">Remove current owner from <strong>${business.business_name}</strong>?</p>
                    `, async () => {
                        const res = await nuiRequest('business:updateOwner', { businessId, ownerId: '', ownerName: 'Unassigned' });
                        if (res && res.ok) {
                            business.owner_id = '';
                            business.owner_name = 'Unassigned';
                            this.renderPage('registry', container.closest('#businesses-content'));
                        }
                    });
                } else if (actionType === 'toggle-status') {
                    const targetStatus = String(business.business_status || 'active').toLowerCase() === 'closed' ? 'active' : 'closed';
                    this.showModal(`
                        <h3>${targetStatus === 'closed' ? 'Close' : 'Reopen'} Business</h3>
                        <p>Business: <strong>${business.business_name}</strong></p>
                        <div class="form-group"><label>Reason</label><textarea class="form-input" id="business-status-reason" rows="3" placeholder="Enter reason"></textarea></div>
                    `, async () => {
                        const reason = document.getElementById('business-status-reason')?.value.trim() || '';
                        const res = await nuiRequest('business:setStatus', { businessId, status: targetStatus, reason });
                        if (res && res.ok) {
                            await this.refreshData();
                            this._updateTopbar();
                            this.renderPage('registry', container.closest('#businesses-content'));
                        }
                    });
                } else if (actionType === 'delete') {
                    this.showModal(`
                        <h3>Delete Business</h3>
                        <p class="warning-text">Delete <strong>${business.business_name}</strong>? This cannot be undone.</p>
                    `, async () => {
                        const res = await nuiRequest('business:delete', { businessId });
                        if (res && res.ok) {
                            await this.refreshData();
                            this._updateTopbar();
                            this.renderPage('registry', container.closest('#businesses-content'));
                        }
                    });
                }

                container.querySelectorAll('.action-dropdown').forEach(menu => menu.classList.remove('open'));
                return;
            }

            container.querySelectorAll('.action-dropdown').forEach(menu => menu.classList.remove('open'));
        });

        const filterTable = () => {
            const search = (searchInput ? searchInput.value : '').toLowerCase();
            const type = typeFilter ? typeFilter.value : '';
            const job = jobFilter ? jobFilter.value : '';
            const status = statusFilter ? statusFilter.value : '';
            container.querySelectorAll('#registry-table tbody tr[data-business-id]').forEach(row => {
                const businessId = row.dataset.businessId;
                const business = this.data.businesses.find(b => b.business_id === businessId);
                if (!business) { row.style.display = ''; return; }
                const matchSearch = !search ||
                    business.business_name.toLowerCase().includes(search) ||
                    (business.owner_name || '').toLowerCase().includes(search);
                const matchType = !type || business.business_type === type;
                const matchJob = !job || business.business_id === job;
                const matchStatus = !status || business.compliance_status === status;
                row.style.display = matchSearch && matchType && matchJob && matchStatus ? '' : 'none';
            });
        };

        if (searchInput) searchInput.addEventListener('input', filterTable);
        if (typeFilter) typeFilter.addEventListener('change', filterTable);
        if (jobFilter) jobFilter.addEventListener('change', filterTable);
        if (statusFilter) statusFilter.addEventListener('change', filterTable);
        if (createBtn) {
            createBtn.addEventListener('click', () => {
                this.showModal(`
                    <h3>Create Business Profile</h3>
                    <div class="form-group"><label>Business Job</label>
                        <select class="form-input" id="create-business-job">
                            ${(this.data.jobOptions || []).map(option => `<option value="${option.job}">${option.label || option.job}</option>`).join('')}
                        </select>
                    </div>
                    <div class="form-group"><label>Business Name</label><input type="text" class="form-input" id="create-business-name" placeholder="Display name"></div>
                    <div class="form-group"><label>Business Type</label><input type="text" class="form-input" id="create-business-type" placeholder="Mechanic, Restaurant, etc."></div>
                    <div class="form-group"><label>Owner Name</label><input type="text" class="form-input" id="create-business-owner-name" placeholder="Optional"></div>
                    <div class="form-group"><label>Owner ID</label><input type="text" class="form-input" id="create-business-owner-id" placeholder="Optional"></div>
                    <div class="form-group"><label>Location X</label><input type="number" step="0.0001" class="form-input" id="create-business-location-x" placeholder="Optional"></div>
                    <div class="form-group"><label>Location Y</label><input type="number" step="0.0001" class="form-input" id="create-business-location-y" placeholder="Optional"></div>
                    <div class="form-group"><label>Location Z</label><input type="number" step="0.0001" class="form-input" id="create-business-location-z" placeholder="Optional"></div>
                    <div class="form-group"><label>Location Address</label><input type="text" class="form-input" id="create-business-location-address" placeholder="Optional"></div>
                `, async () => {
                    const businessId = document.getElementById('create-business-job')?.value || '';
                    const businessName = document.getElementById('create-business-name')?.value.trim() || '';
                    const businessType = document.getElementById('create-business-type')?.value.trim() || '';
                    const ownerName = document.getElementById('create-business-owner-name')?.value.trim() || 'Unassigned';
                    const ownerId = document.getElementById('create-business-owner-id')?.value.trim() || '';
                    const locationXRaw = document.getElementById('create-business-location-x')?.value;
                    const locationYRaw = document.getElementById('create-business-location-y')?.value;
                    const locationZRaw = document.getElementById('create-business-location-z')?.value;
                    const locationAddress = document.getElementById('create-business-location-address')?.value.trim() || '';
                    const locationX = locationXRaw === '' || locationXRaw == null ? null : Number(locationXRaw);
                    const locationY = locationYRaw === '' || locationYRaw == null ? null : Number(locationYRaw);
                    const locationZ = locationZRaw === '' || locationZRaw == null ? null : Number(locationZRaw);
                    if (!businessId || !businessName) return;

                    const res = await nuiRequest('business:save', {
                        businessId,
                        businessName,
                        businessType,
                        ownerName,
                        ownerId,
                        locationX,
                        locationY,
                        locationZ,
                        locationAddress
                    });

                    if (res && res.ok) {
                        await this.refreshData();
                        this._updateTopbar();
                        this.renderPage('registry', container.closest('#businesses-content'));
                    }
                });
            });
        }
        if (exportBtn) {
            exportBtn.addEventListener('click', () => {
                const search = (searchInput ? searchInput.value : '').toLowerCase();
                const type = typeFilter ? typeFilter.value : '';
                const job = jobFilter ? jobFilter.value : '';
                const status = statusFilter ? statusFilter.value : '';
                const filteredBusinesses = this.data.businesses.filter(business => {
                    const matchSearch = !search ||
                        business.business_name.toLowerCase().includes(search) ||
                        (business.owner_name || '').toLowerCase().includes(search);
                    const matchType = !type || business.business_type === type;
                    const matchJob = !job || business.business_id === job;
                    const matchStatus = !status || business.compliance_status === status;
                    return matchSearch && matchType && matchJob && matchStatus;
                });
                this.exportBusinessRegistryReport(filteredBusinesses);
            });
        }

        if (tableRows[0]) {
            setActiveRow(tableRows[0]);
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

    formatBusinessLocation(business) {
        if (!business) return 'Not set';
        const address = String(business.location_address || '').trim();
        if (address) return address;

        const x = Number(business.location_x);
        const y = Number(business.location_y);
        if (Number.isFinite(x) && Number.isFinite(y)) {
            return `${x.toFixed(2)}, ${y.toFixed(2)}`;
        }
        return 'Not set';
    }

    getStatusBadge(status) {
        if (!status) return '<span class="status-badge neutral">—</span>';
        const normalized = status.toLowerCase();
        let className = 'neutral';
        if (normalized === 'active' || normalized === 'compliant' || normalized === 'current' || normalized === 'open') {
            className = 'active';
        } else if (normalized === 'suspended' || normalized === 'closed' || normalized === 'inactive') {
            className = 'inactive';
        } else if (normalized === 'warning' || normalized === 'late') {
            className = 'warning';
        } else if (normalized === 'non_compliant' || normalized === 'flagged' || normalized === 'delinquent' || normalized === 'revoked' || normalized === 'expired') {
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
        const stored = localStorage.getItem('gov_documents');
        return stored ? JSON.parse(stored) : [];
    }

    saveDocuments() {
        localStorage.setItem('gov_documents', JSON.stringify(this.documents));
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

    deleteDocument(id) {
        if (!confirm('Are you sure you want to delete this document?')) return;
        
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
        this.draggedElement = null;
        this.init();
    }

    init() {
        this.setupDesktopIcons();
        document.addEventListener('dragover', (e) => e.preventDefault());
        document.addEventListener('drop', (e) => e.preventDefault());
    }

    setupDesktopIcons() {
        const icons = document.querySelectorAll('.icon');
        icons.forEach(icon => {
            // Remove existing listeners by cloning
            const newIcon = icon.cloneNode(true);
            icon.parentNode?.replaceChild(newIcon, icon);
            
            newIcon.setAttribute('draggable', 'true');
            
            newIcon.addEventListener('dragstart', (e) => {
                this.draggedElement = newIcon;
                newIcon.classList.add('dragging');
                e.dataTransfer.effectAllowed = 'move';
                e.dataTransfer.setData('text/plain', newIcon.dataset.app || newIcon.dataset.id);
            });

            newIcon.addEventListener('dragend', () => {
                newIcon.classList.remove('dragging');
                document.querySelectorAll('.drag-over').forEach(el => {
                    el.classList.remove('drag-over');
                });
            });

            // Re-attach double-click handlers
            if (newIcon.dataset.type === 'folder') {
                const folderId = newIcon.dataset.id;
                newIcon.addEventListener('dblclick', () => this.desktopManager.openFolder(folderId));
                this.attachDropListeners(newIcon);
            } else if (newIcon.dataset.type === 'document') {
                const docId = newIcon.dataset.documentId;
                newIcon.addEventListener('dblclick', () => {
                    if (window.documentsManager) {
                        window.documentsManager.openDocument(docId);
                        if (window.windowManagerInstance) {
                            window.windowManagerInstance.openWindow('documents');
                        }
                    }
                });
            } else if (newIcon.dataset.app) {
                const appName = newIcon.dataset.app;
                newIcon.addEventListener('dblclick', () => {
                    if (window.windowManagerInstance) {
                        window.windowManagerInstance.openWindow(appName);
                    }
                });
            }
        });

        const desktop = document.querySelector('.desktop');
        if (desktop) {
            this.attachDropListeners(desktop);
        }
    }

    attachDropListeners(element) {
        element.addEventListener('dragover', (e) => {
            e.preventDefault();
            e.stopPropagation();
            if (this.draggedElement && this.draggedElement !== element) {
                element.classList.add('drag-over');
            }
        });

        element.addEventListener('dragleave', (e) => {
            e.preventDefault();
            e.stopPropagation();
            element.classList.remove('drag-over');
        });

        element.addEventListener('drop', (e) => {
            e.preventDefault();
            e.stopPropagation();
            element.classList.remove('drag-over');

            if (!this.draggedElement) return;

            const itemId = this.draggedElement.dataset.id || this.draggedElement.dataset.app;
            let targetType = 'desktop';
            let targetId = null;

            if (element.classList.contains('desktop')) {
                targetType = 'desktop';
            } else if (element.classList.contains('folder-content')) {
                const folderWindow = element.closest('.window');
                if (folderWindow) {
                    const windowApp = folderWindow.dataset.app;
                    if (windowApp && windowApp.startsWith('folder-')) {
                        targetId = windowApp.replace('folder-', '');
                        targetType = 'folder';
                    }
                }
            } else if (element.dataset.type === 'folder') {
                targetType = 'folder';
                targetId = element.dataset.id;
            }

            this.handleDrop(itemId, targetType, targetId);
        });
    }

    setupDropTarget(element) {
        this.attachDropListeners(element);
    }

    handleDrop(itemId, targetType, targetId) {
        if (this.desktopManager) {
            this.desktopManager.moveItem(itemId, targetType, targetId);
        }
    }

    refreshIcons() {
        this.setupDesktopIcons();
    }
}

// ============================================================================
// MAYOR BROWSER - Government portal with edit controls
// ============================================================================
class MayorBrowserManager {
    constructor() {
        this.currentUrl = '';
        this.history = [];
        this.historyIndex = -1;
        this.homeUrl = 'browser://home';
        this.bookmarks = this.loadBookmarks();
        this.presetSites = this.getPresetSites();
        this.websiteState = this.loadWebsiteState();
        this.websiteStateLoadedFromServer = false;
        this.websiteStateSyncTimer = null;
        this.portalUiState = {
            activePage: 'home',
            editorPage: 'home',
            editMode: false
        };
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
        this.renderBookmarks();
    }

    loadBookmarks() {
        try {
            const stored = localStorage.getItem('gov_browser_bookmarks');
            if (stored) return JSON.parse(stored);
        } catch (e) {
            console.warn('Failed to load gov browser bookmarks', e);
        }
        return [
            { name: 'City Portal', url: 'https://los-santos.gov' },
            { name: 'City Hall Dashboard', url: 'https://cityhall.ls' },
            { name: 'Business Registry', url: 'https://business.ls' }
        ];
    }

    getPresetSites() {
        return [
            {
                name: 'Government Portal',
                url: 'https://los-santos.gov',
                description: 'Official city portal for public records, notices, and municipal services.',
                badge: 'Official',
                accent: 'gov',
                iconText: 'LS'
            },
            {
                name: 'City Hall Dashboard',
                url: 'https://cityhall.ls',
                description: 'Administrative dashboard for city operations, metrics, and service access.',
                badge: 'Internal',
                accent: 'hall',
                iconText: 'CH'
            },
            {
                name: 'Business Registry',
                url: 'https://business.ls',
                description: 'Review registered businesses, oversight records, and compliance details.',
                badge: 'Registry',
                accent: 'business',
                iconText: 'BR'
            },
            {
                name: 'Public Notices',
                url: 'https://los-santos.gov#announcements',
                description: 'Jump directly into active city notices, bulletins, and emergency updates.',
                badge: 'Public',
                accent: 'notice',
                iconText: 'PN'
            }
        ];
    }

    saveBookmarks() {
        localStorage.setItem('gov_browser_bookmarks', JSON.stringify(this.bookmarks));
        this.renderBookmarks();
    }


    escapeHtml(value) {
        const div = document.createElement('div');
        div.textContent = value == null ? '' : String(value);
        return div.innerHTML;
    }

    generateWebsiteBlockId() {
        return `block-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
    }

    getWebsiteBlockTypeLabel(type) {
        const labels = {
            content: 'Content Box',
            callout: 'Callout Banner',
            cards: 'Cards Grid',
            links: 'Quick Links'
        };
        return labels[type] || 'Content Box';
    }

    getDefaultWebsiteState() {
        return {
            globalNotice: 'Official public records, ordinances, revenue notices, and municipal bulletins are available through this verified government portal.',
            siteChrome: {
                utilityPrimary: 'Official website of the City of Los Santos',
                utilitySecondary: 'Secure municipal portal',
                brandKicker: 'City of Los Santos',
                brandTitle: 'Los Santos Government Portal',
                brandSubtitle: 'Public records, ordinances, revenue notices, and official mayoral communications.',
                homeSidebarTitle: 'City Hall',
                homeSidebarLine1: 'Office of the Mayor',
                homeSidebarLine2: 'City Hall, Alta Street',
                homeSidebarLine3: 'Mon - Fri, 08:00 to 17:00',
                footerAboutTitle: 'City of Los Santos',
                footerAboutBody: 'Official municipal portal for public notices, ordinances, taxation, and administrative services.',
                footerResourcesTitle: 'Public Resources',
                footerResourcesItems: [
                    'Public Notices',
                    'Municipal Code',
                    'Tax Schedule',
                    'City Hall Administration'
                ],
                footerContactTitle: 'Contact',
                footerContactAddress: 'Alta Street, Los Santos',
                footerContactHours: 'Mon - Fri, 08:00 to 17:00'
            },
            pages: {
                home: {
                    kicker: 'Municipal Information',
                    title: 'Welcome to the official Los Santos government website',
                    intro: 'Access official ordinances, mayoral notices, public tax information, and administrative services through a single verified city portal.',
                    blocks: [
                        {
                            id: this.generateWebsiteBlockId(),
                            type: 'content',
                            eyebrow: 'City Hall Services',
                            title: 'Government service information',
                            body: 'Residents may review public notices, municipal code, tax schedules, and administrative announcements through the city portal. Records published here should be treated as official unless superseded by later notice.',
                            items: [],
                            buttonLabel: 'Public Notices',
                            buttonPage: 'announcements'
                        },
                        {
                            id: this.generateWebsiteBlockId(),
                            type: 'cards',
                            eyebrow: 'Featured Services',
                            title: 'Common civic resources',
                            body: 'Quick access links for high-traffic public information.',
                            items: [
                                'Public Notices|Emergency updates, bulletins, and active advisories.',
                                'Municipal Code|Published ordinances and city policy reference.',
                                'Taxes & Fees|Active public tax schedules and fee guidance.'
                            ],
                            buttonLabel: '',
                            buttonPage: 'home'
                        }
                    ]
                },
                announcements: {
                    kicker: 'Public Information',
                    title: 'Public Notices and Mayoral Announcements',
                    intro: 'Official bulletins, emergency communications, and municipal updates published by City Hall.',
                    blocks: []
                },
                laws: {
                    kicker: 'Municipal Code',
                    title: 'Code of Ordinances and Policy Register',
                    intro: 'Published laws, MDT reference guidance, and enforceable city policy.',
                    blocks: []
                },
                taxes: {
                    kicker: 'Revenue Administration',
                    title: 'Taxes, Rates, and Municipal Fees',
                    intro: 'Current public tax schedules and authorized rate ranges published by the City of Los Santos.',
                    blocks: []
                }
            }
        };
    }

    normalizeWebsiteBlock(block) {
        const base = {
            id: block && block.id ? String(block.id) : this.generateWebsiteBlockId(),
            type: block && block.type ? String(block.type) : 'content',
            eyebrow: block && block.eyebrow ? String(block.eyebrow) : '',
            title: block && block.title ? String(block.title) : 'New Content Block',
            body: block && block.body ? String(block.body) : '',
            items: Array.isArray(block && block.items) ? block.items.map((item) => String(item)) : [],
            buttonLabel: block && block.buttonLabel ? String(block.buttonLabel) : '',
            buttonPage: block && block.buttonPage ? String(block.buttonPage) : 'home'
        };

        if (!['content', 'callout', 'cards', 'links'].includes(base.type)) {
            base.type = 'content';
        }

        return base;
    }

    normalizeWebsiteState(state) {
        const defaults = this.getDefaultWebsiteState();
        const source = state && typeof state === 'object' ? state : {};
        const chromeSource = source.siteChrome && typeof source.siteChrome === 'object' ? source.siteChrome : {};
        const pages = {};

        Object.keys(defaults.pages).forEach((pageKey) => {
            const pageSource = source.pages && source.pages[pageKey] ? source.pages[pageKey] : {};
            const seenIds = new Set();
            const rawBlocks = (Array.isArray(pageSource.blocks) ? pageSource.blocks : defaults.pages[pageKey].blocks).map((block) => this.normalizeWebsiteBlock(block));
            const blocks = rawBlocks.map((block) => {
                if (seenIds.has(block.id)) {
                    block.id = this.generateWebsiteBlockId();
                }
                seenIds.add(block.id);
                return block;
            });

            pages[pageKey] = {
                kicker: pageSource.kicker != null ? String(pageSource.kicker) : defaults.pages[pageKey].kicker,
                title: pageSource.title != null ? String(pageSource.title) : defaults.pages[pageKey].title,
                intro: pageSource.intro != null ? String(pageSource.intro) : defaults.pages[pageKey].intro,
                blocks
            };
        });

        return {
            globalNotice: source.globalNotice != null ? String(source.globalNotice) : defaults.globalNotice,
            siteChrome: {
                utilityPrimary: chromeSource.utilityPrimary != null ? String(chromeSource.utilityPrimary) : defaults.siteChrome.utilityPrimary,
                utilitySecondary: chromeSource.utilitySecondary != null ? String(chromeSource.utilitySecondary) : defaults.siteChrome.utilitySecondary,
                brandKicker: chromeSource.brandKicker != null ? String(chromeSource.brandKicker) : defaults.siteChrome.brandKicker,
                brandTitle: chromeSource.brandTitle != null ? String(chromeSource.brandTitle) : defaults.siteChrome.brandTitle,
                brandSubtitle: chromeSource.brandSubtitle != null ? String(chromeSource.brandSubtitle) : defaults.siteChrome.brandSubtitle,
                homeSidebarTitle: chromeSource.homeSidebarTitle != null ? String(chromeSource.homeSidebarTitle) : defaults.siteChrome.homeSidebarTitle,
                homeSidebarLine1: chromeSource.homeSidebarLine1 != null ? String(chromeSource.homeSidebarLine1) : defaults.siteChrome.homeSidebarLine1,
                homeSidebarLine2: chromeSource.homeSidebarLine2 != null ? String(chromeSource.homeSidebarLine2) : defaults.siteChrome.homeSidebarLine2,
                homeSidebarLine3: chromeSource.homeSidebarLine3 != null ? String(chromeSource.homeSidebarLine3) : defaults.siteChrome.homeSidebarLine3,
                footerAboutTitle: chromeSource.footerAboutTitle != null ? String(chromeSource.footerAboutTitle) : defaults.siteChrome.footerAboutTitle,
                footerAboutBody: chromeSource.footerAboutBody != null ? String(chromeSource.footerAboutBody) : defaults.siteChrome.footerAboutBody,
                footerResourcesTitle: chromeSource.footerResourcesTitle != null ? String(chromeSource.footerResourcesTitle) : defaults.siteChrome.footerResourcesTitle,
                footerResourcesItems: Array.isArray(chromeSource.footerResourcesItems)
                    ? chromeSource.footerResourcesItems.map((item) => String(item || '').trim()).filter(Boolean)
                    : defaults.siteChrome.footerResourcesItems,
                footerContactTitle: chromeSource.footerContactTitle != null ? String(chromeSource.footerContactTitle) : defaults.siteChrome.footerContactTitle,
                footerContactAddress: chromeSource.footerContactAddress != null ? String(chromeSource.footerContactAddress) : defaults.siteChrome.footerContactAddress,
                footerContactHours: chromeSource.footerContactHours != null ? String(chromeSource.footerContactHours) : defaults.siteChrome.footerContactHours
            },
            pages
        };
    }

    loadWebsiteState() {
        try {
            const stored = localStorage.getItem('gov_browser_website_state_v1');
            if (stored) {
                return this.normalizeWebsiteState(JSON.parse(stored));
            }
        } catch (e) {
            console.warn('Failed to load website editor state', e);
        }
        return this.normalizeWebsiteState(this.getDefaultWebsiteState());
    }

    saveWebsiteState() {
        this.websiteState = this.normalizeWebsiteState(this.websiteState);
        localStorage.setItem('gov_browser_website_state_v1', JSON.stringify(this.websiteState));
        this.pushWebsiteStateToServer();
    }

    resetWebsiteState() {
        this.websiteState = this.normalizeWebsiteState(this.getDefaultWebsiteState());
        this.saveWebsiteState();
    }

    async hydrateWebsiteStateFromServer(force = false) {
        if (this.websiteStateLoadedFromServer && !force) {
            return;
        }

        const response = await nuiRequest('website:getState', {});
        if (response && response.ok && response.state && typeof response.state === 'object') {
            this.websiteState = this.normalizeWebsiteState(response.state);
            localStorage.setItem('gov_browser_website_state_v1', JSON.stringify(this.websiteState));
        }

        this.websiteStateLoadedFromServer = true;
    }

    pushWebsiteStateToServer() {
        if (this.websiteStateSyncTimer) {
            clearTimeout(this.websiteStateSyncTimer);
        }

        this.websiteStateSyncTimer = setTimeout(() => {
            this.websiteStateSyncTimer = null;
            nuiRequest('website:saveState', {
                state: this.websiteState
            });
        }, 200);
    }

    applyInlineWebsiteValue(path, value) {
        if (!path || typeof value !== 'string') {
            return false;
        }

        if (path === 'globalNotice') {
            this.websiteState.globalNotice = value;
            return true;
        }

        if (path.startsWith('siteChrome.')) {
            const key = path.replace('siteChrome.', '');
            if (!key) return false;

            if (key.startsWith('footerResourcesItems.')) {
                const index = Number(key.split('.')[1]);
                if (!Number.isFinite(index) || index < 0) return false;
                if (!Array.isArray(this.websiteState.siteChrome.footerResourcesItems)) {
                    this.websiteState.siteChrome.footerResourcesItems = [];
                }
                this.websiteState.siteChrome.footerResourcesItems[index] = value;
                this.websiteState.siteChrome.footerResourcesItems = this.websiteState.siteChrome.footerResourcesItems
                    .map((item) => String(item || '').trim())
                    .filter(Boolean);
                return true;
            }

            this.websiteState.siteChrome[key] = value;
            return true;
        }

        if (path.startsWith('page.')) {
            const parts = path.split('.');
            if (parts.length !== 3) return false;
            const pageKey = parts[1];
            const fieldKey = parts[2];
            if (!this.websiteState.pages[pageKey]) return false;
            if (!['kicker', 'title', 'intro'].includes(fieldKey)) return false;
            this.websiteState.pages[pageKey][fieldKey] = value;
            return true;
        }

        return false;
    }

    createWebsiteBlock(type) {
        const presets = {
            content: {
                type: 'content',
                eyebrow: 'Information Box',
                title: 'New Content Box',
                body: 'Enter the body copy for this public content section.',
                items: [],
                buttonLabel: '',
                buttonPage: 'home'
            },
            callout: {
                type: 'callout',
                eyebrow: 'Public Notice',
                title: 'Important municipal notice',
                body: 'Use this callout for highlighted public information, advisories, or deadlines.',
                items: [],
                buttonLabel: 'Read notices',
                buttonPage: 'announcements'
            },
            cards: {
                type: 'cards',
                eyebrow: 'Featured Links',
                title: 'Service spotlight grid',
                body: 'Add up to three or four summary cards using one item per line in Title|Description format.',
                items: [
                    'Department Directory|Review active city departments and service areas.',
                    'Permits and Licensing|Find permit rules, approvals, and guidance.',
                    'City Hall Services|Review administrative services and office hours.'
                ],
                buttonLabel: '',
                buttonPage: 'home'
            },
            links: {
                type: 'links',
                eyebrow: 'Quick Links',
                title: 'Popular website destinations',
                body: 'Use one link per line in Label|page format. Valid pages: home, announcements, laws, taxes, editor.',
                items: [
                    'Public Notices|announcements',
                    'Municipal Code|laws',
                    'Taxes and Fees|taxes'
                ],
                buttonLabel: '',
                buttonPage: 'home'
            }
        };

        return this.normalizeWebsiteBlock(presets[type] || presets.content);
    }

    renderWebsiteBlocks(blocks) {
        const esc = (value) => this.escapeHtml(value);
        return (Array.isArray(blocks) ? blocks : []).map((block) => {
            const items = Array.isArray(block.items) ? block.items : [];
            const actionButton = block.buttonLabel
                ? `<button class="gov-site-block-action" data-page-link="${esc(block.buttonPage || 'home')}">${esc(block.buttonLabel)}</button>`
                : '';
            const eyebrow = block.eyebrow ? `<div class="gov-site-section-kicker">${esc(block.eyebrow)}</div>` : '';

            if (block.type === 'callout') {
                return `
                    <section class="gov-custom-block gov-custom-block-callout">
                        ${eyebrow}
                        <h3>${esc(block.title || 'Important notice')}</h3>
                        <p>${esc(block.body || '')}</p>
                        ${actionButton}
                    </section>
                `;
            }

            if (block.type === 'cards') {
                const cards = items.map((entry) => {
                    const [title, desc] = String(entry || '').split('|');
                    return `
                        <article class="gov-custom-card">
                            <h4>${esc(title || 'Card heading')}</h4>
                            <p>${esc(desc || '')}</p>
                        </article>
                    `;
                }).join('');
                return `
                    <section class="gov-custom-block gov-custom-block-panel">
                        ${eyebrow}
                        <div class="gov-site-panel-head gov-site-panel-head-stack">
                            <div>
                                <h3>${esc(block.title || 'Featured content')}</h3>
                                <p>${esc(block.body || '')}</p>
                            </div>
                            ${actionButton}
                        </div>
                        <div class="gov-custom-card-grid">${cards || '<div class="gov-site-empty-state">No cards have been added yet.</div>'}</div>
                    </section>
                `;
            }

            if (block.type === 'links') {
                const links = items.map((entry) => {
                    const [label, page] = String(entry || '').split('|');
                    return `<button class="gov-site-link-chip" data-page-link="${esc(page || 'home')}">${esc(label || 'Open page')}</button>`;
                }).join('');
                return `
                    <section class="gov-custom-block gov-custom-block-panel">
                        ${eyebrow}
                        <div class="gov-site-panel-head gov-site-panel-head-stack">
                            <div>
                                <h3>${esc(block.title || 'Quick links')}</h3>
                                <p>${esc(block.body || '')}</p>
                            </div>
                            ${actionButton}
                        </div>
                        <div class="gov-site-link-chip-row">${links || '<div class="gov-site-empty-state">No quick links have been added yet.</div>'}</div>
                    </section>
                `;
            }

            return `
                <section class="gov-custom-block gov-custom-block-panel">
                    ${eyebrow}
                    <div class="gov-site-panel-head gov-site-panel-head-stack">
                        <div>
                            <h3>${esc(block.title || 'Content block')}</h3>
                            <p>${esc(block.body || '')}</p>
                        </div>
                        ${actionButton}
                    </div>
                </section>
            `;
        }).join('');
    }

    bindWebsiteEditor(container) {
        const shell = container.querySelector('.gov-site-shell');
        const toggleButton = container.querySelector('.gov-site-edit-toggle');
        if (shell) shell.classList.toggle('is-website-editing', !!this.portalUiState.editMode);
        if (toggleButton) {
            toggleButton.textContent = this.portalUiState.editMode ? 'Exit Website Edit' : 'Edit Website';
            toggleButton.classList.toggle('is-active', !!this.portalUiState.editMode);
            toggleButton.addEventListener('click', () => {
                this.portalUiState.editMode = !this.portalUiState.editMode;
                this.renderGovPortal(container, this.currentUrl);
            });
        }

        const pageSelect = container.querySelector('#gov-site-editor-page');
        if (pageSelect) {
            pageSelect.value = this.portalUiState.editorPage || 'home';
            pageSelect.addEventListener('change', () => {
                this.portalUiState.editorPage = pageSelect.value || 'home';
                this.renderGovPortal(container, this.currentUrl);
            });
        }

        const editingPage = this.portalUiState.editorPage || 'home';
        const pageState = this.websiteState.pages[editingPage];
        if (!pageState) return;

        const rerenderEditor = () => {
            this.saveWebsiteState();
            this.renderGovPortal(container, this.currentUrl);
        };

        const bindPageField = (selector, key) => {
            const input = container.querySelector(selector);
            if (!input) return;
            input.value = pageState[key] || '';
            input.addEventListener('input', () => {
                pageState[key] = input.value;
                this.saveWebsiteState();
                if (this.portalUiState.activePage === editingPage) {
                    const target = container.querySelector(`.mayor-browser-page[data-page="${editingPage}"] [data-gov-page-${key === 'intro' ? 'intro' : 'title'}]`);
                    if (target && (key === 'title' || key === 'intro')) target.textContent = input.value || '';
                }
            });
        };

        const bindSiteChromeField = (selector, key, transform) => {
            const input = container.querySelector(selector);
            if (!input) return;
            const currentValue = this.websiteState.siteChrome && this.websiteState.siteChrome[key] != null
                ? this.websiteState.siteChrome[key]
                : '';
            input.value = Array.isArray(currentValue) ? currentValue.join('\n') : String(currentValue || '');
            input.addEventListener('input', () => {
                const raw = input.value;
                this.websiteState.siteChrome[key] = transform ? transform(raw) : raw;
                this.saveWebsiteState();
            });
        };

        const globalNoticeInput = container.querySelector('#gov-site-global-notice');
        if (globalNoticeInput) {
            globalNoticeInput.value = this.websiteState.globalNotice || '';
            globalNoticeInput.addEventListener('input', () => {
                this.websiteState.globalNotice = globalNoticeInput.value;
                this.saveWebsiteState();
                const bannerText = container.querySelector('.gov-site-alert-banner span');
                if (bannerText) bannerText.textContent = this.websiteState.globalNotice || '';
            });
        }

        bindPageField('#gov-site-page-kicker', 'kicker');
        bindPageField('#gov-site-page-title', 'title');
        bindPageField('#gov-site-page-intro', 'intro');
        bindSiteChromeField('#gov-site-brand-kicker', 'brandKicker');
        bindSiteChromeField('#gov-site-brand-title', 'brandTitle');
        bindSiteChromeField('#gov-site-brand-subtitle', 'brandSubtitle');
        bindSiteChromeField('#gov-site-footer-about-title', 'footerAboutTitle');
        bindSiteChromeField('#gov-site-footer-about-body', 'footerAboutBody');
        bindSiteChromeField('#gov-site-footer-resources-items', 'footerResourcesItems', (raw) => String(raw || '').split('\n').map((item) => item.trim()).filter(Boolean));
        bindSiteChromeField('#gov-site-footer-contact-title', 'footerContactTitle');
        bindSiteChromeField('#gov-site-footer-contact-address', 'footerContactAddress');
        bindSiteChromeField('#gov-site-footer-contact-hours', 'footerContactHours');

        container.querySelectorAll('[data-gov-inline-edit]').forEach((element) => {
            element.addEventListener('dblclick', (event) => {
                if (!this.portalUiState.editMode) {
                    return;
                }

                event.preventDefault();
                event.stopPropagation();

                if (element.getAttribute('contenteditable') === 'true') {
                    return;
                }

                const editPath = element.dataset.govInlineEdit;
                const originalValue = String(element.textContent || '').trim();
                element.setAttribute('contenteditable', 'true');
                element.classList.add('is-inline-editing');
                element.focus();

                const selection = window.getSelection();
                if (selection) {
                    const range = document.createRange();
                    range.selectNodeContents(element);
                    selection.removeAllRanges();
                    selection.addRange(range);
                }

                const finishEdit = (commit) => {
                    const rawValue = String(element.textContent || '').trim();
                    const nextValue = rawValue || originalValue;
                    element.removeAttribute('contenteditable');
                    element.classList.remove('is-inline-editing');
                    element.removeEventListener('blur', onBlur);
                    element.removeEventListener('keydown', onKeyDown);

                    if (!commit) {
                        element.textContent = originalValue;
                        return;
                    }

                    if (this.applyInlineWebsiteValue(editPath, nextValue)) {
                        this.saveWebsiteState();
                        this.renderGovPortal(container, this.currentUrl);
                    } else {
                        element.textContent = originalValue;
                    }
                };

                const onBlur = () => finishEdit(true);
                const onKeyDown = (e) => {
                    if (e.key === 'Enter' && !e.shiftKey) {
                        e.preventDefault();
                        finishEdit(true);
                    } else if (e.key === 'Escape') {
                        e.preventDefault();
                        finishEdit(false);
                    }
                };

                element.addEventListener('blur', onBlur);
                element.addEventListener('keydown', onKeyDown);
            });
        });

        container.querySelectorAll('.gov-site-module-preset').forEach((button) => {
            button.addEventListener('click', () => {
                const newBlock = this.createWebsiteBlock(button.dataset.moduleType || 'content');
                pageState.blocks.push(newBlock);
                rerenderEditor();
            });
        });

        container.querySelector('#gov-site-save-layout')?.addEventListener('click', () => {
            this.saveWebsiteState();
            const footerButton = container.querySelector('#gov-site-save-layout');
            if (footerButton) {
                const original = footerButton.textContent;
                footerButton.textContent = 'Saved';
                setTimeout(() => {
                    if (footerButton) footerButton.textContent = original;
                }, 1200);
            }
        });

        container.querySelector('#gov-site-reset-layout')?.addEventListener('click', () => {
            if (!window.confirm('Reset the website layout back to the saved preset?')) return;
            this.resetWebsiteState();
            this.renderGovPortal(container, this.currentUrl);
        });

        let draggedBlockId = null;
        container.querySelectorAll('.gov-site-editor-module').forEach((blockEl) => {
            const blockId = blockEl.dataset.blockId;
            const blockIndex = pageState.blocks.findIndex((entry) => entry.id === blockId);
            if (blockIndex < 0) return;
            const block = pageState.blocks[blockIndex];

            blockEl.addEventListener('dragstart', () => {
                draggedBlockId = blockId;
                blockEl.classList.add('is-dragging');
            });
            blockEl.addEventListener('dragend', () => {
                draggedBlockId = null;
                blockEl.classList.remove('is-dragging');
                container.querySelectorAll('.gov-site-editor-module').forEach((entry) => entry.classList.remove('is-drop-target'));
            });
            blockEl.addEventListener('dragover', (event) => {
                event.preventDefault();
                if (!draggedBlockId || draggedBlockId === blockId) return;
                blockEl.classList.add('is-drop-target');
            });
            blockEl.addEventListener('dragleave', () => blockEl.classList.remove('is-drop-target'));
            blockEl.addEventListener('drop', (event) => {
                event.preventDefault();
                blockEl.classList.remove('is-drop-target');
                if (!draggedBlockId || draggedBlockId === blockId) return;
                const fromIndex = pageState.blocks.findIndex((entry) => entry.id === draggedBlockId);
                const toIndex = pageState.blocks.findIndex((entry) => entry.id === blockId);
                if (fromIndex < 0 || toIndex < 0 || fromIndex === toIndex) return;
                const [moved] = pageState.blocks.splice(fromIndex, 1);
                pageState.blocks.splice(toIndex, 0, moved);
                rerenderEditor();
            });

            const bindBlockField = (selector, key, transform, summarySelector) => {
                const input = blockEl.querySelector(selector);
                if (!input) return;
                input.value = key === 'items' ? (Array.isArray(block.items) ? block.items.join('\n') : '') : (block[key] || '');
                input.addEventListener('input', () => {
                    const raw = input.value;
                    block[key] = transform ? transform(raw) : raw;
                    if (summarySelector) {
                        const summaryEl = blockEl.querySelector(summarySelector);
                        if (summaryEl) summaryEl.textContent = raw || (key === 'title' ? this.getWebsiteBlockTypeLabel(block.type) : '');
                    }
                    if (key === 'body') {
                        const previewEl = blockEl.querySelector('.gov-site-editor-module-summary p');
                        if (previewEl) previewEl.textContent = (raw || 'No summary has been entered for this module yet.').slice(0, 110);
                    }
                    this.saveWebsiteState();
                });
            };

            bindBlockField('.gov-site-block-eyebrow', 'eyebrow');
            bindBlockField('.gov-site-block-title', 'title', null, '.gov-site-editor-module-summary strong');
            bindBlockField('.gov-site-block-body', 'body');
            bindBlockField('.gov-site-block-items', 'items', (raw) => String(raw || '').split('\n').map((line) => line.trim()).filter(Boolean));
            bindBlockField('.gov-site-block-button-label', 'buttonLabel');

            const typeSelect = blockEl.querySelector('.gov-site-block-type');
            if (typeSelect) {
                typeSelect.value = block.type || 'content';
                typeSelect.addEventListener('change', () => {
                    block.type = typeSelect.value || 'content';
                    const typeBadge = blockEl.querySelector('.gov-site-editor-module-type');
                    if (typeBadge) typeBadge.textContent = this.getWebsiteBlockTypeLabel(block.type);
                    const heading = blockEl.querySelector('.gov-site-editor-module-summary strong');
                    if (heading && (!block.title || heading.textContent === this.getWebsiteBlockTypeLabel(block.type))) {
                        heading.textContent = block.title || this.getWebsiteBlockTypeLabel(block.type);
                    }
                    this.saveWebsiteState();
                });
            }

            const pageButtonSelect = blockEl.querySelector('.gov-site-block-button-page');
            if (pageButtonSelect) {
                pageButtonSelect.value = block.buttonPage || 'home';
                pageButtonSelect.addEventListener('change', () => {
                    block.buttonPage = pageButtonSelect.value || 'home';
                    const statTarget = blockEl.querySelector('.gov-site-editor-module-stats span:last-child');
                    if (statTarget) statTarget.textContent = `Target page: ${block.buttonPage || 'home'}`;
                    this.saveWebsiteState();
                });
            }

            blockEl.querySelector('.gov-site-editor-action-duplicate')?.addEventListener('click', () => {
                const duplicate = this.normalizeWebsiteBlock({ ...block, id: this.generateWebsiteBlockId(), title: `${block.title || this.getWebsiteBlockTypeLabel(block.type)} Copy` });
                pageState.blocks.splice(blockIndex + 1, 0, duplicate);
                rerenderEditor();
            });

            blockEl.querySelector('.gov-site-editor-action-delete')?.addEventListener('click', () => {
                pageState.blocks.splice(blockIndex, 1);
                rerenderEditor();
            });
        });
    }

    renderBookmarks() {

        const bar = document.querySelector('#browser-window .browser-bookmarks');
        if (!bar) return;
        bar.innerHTML = this.bookmarks.map((bookmark) => `
            <button class="browser-bookmark" data-url="${bookmark.url}" title="${bookmark.url}">${bookmark.name}</button>
        `).join('');
        bar.querySelectorAll('.browser-bookmark').forEach((btn) => {
            btn.addEventListener('click', () => this.loadUrl(btn.dataset.url));
        });
    }

    onOpen() {
        if (!this.currentUrl) {
            this.loadUrl(this.homeUrl, true);
        }
    }

    isBrowserHomeUrl(url) {
        return String(url || '').trim().toLowerCase() === this.homeUrl;
    }

    normalizeUrl(url) {
        const raw = String(url || '').trim();
        if (!raw) return this.homeUrl;
        if (/^(browser:\/\/home|home|start)$/i.test(raw)) return this.homeUrl;
        if (/\s/.test(raw) && !raw.includes('.')) return `https://search.ls/?q=${encodeURIComponent(raw)}`;
        if (!raw.startsWith('http://') && !raw.startsWith('https://')) return `https://${raw}`;
        return raw;
    }

    getGovPortalPageFromUrl(url) {
        const hash = String(url || '').split('#')[1] || '';
        const page = hash.trim().toLowerCase();
        return ['home', 'announcements', 'laws', 'taxes', 'editor'].includes(page) ? page : 'home';
    }

    pushHistory(url) {
        if (this.historyIndex < this.history.length - 1) {
            this.history = this.history.slice(0, this.historyIndex + 1);
        }
        this.history.push(url);
        this.historyIndex = this.history.length - 1;
    }

    getContent() {
        return document.querySelector('#browser-window .browser-content');
    }

    renderBrowserHome(container) {
        const esc = (value) => this.escapeHtml(value);
        const quickSites = this.presetSites.slice(0, 6);
        container.innerHTML = `
            <div class="browser-homepage browser-homepage-real">
                <section class="browser-homepage-topbar">
                    <div class="browser-homepage-bookmarks-hint">For quick access, place your bookmarks here on the bookmarks bar.</div>
                    <button class="browser-homepage-import-btn" type="button">Import bookmarks now…</button>
                </section>

                <section class="browser-homepage-launcher">
                    <div class="browser-homepage-quick-icons">
                        ${quickSites.map((site) => `
                            <button class="browser-homepage-quick-link" type="button" data-home-url="${esc(site.url)}" title="${esc(site.name)}">
                                <span class="browser-homepage-quick-link-icon browser-homepage-quick-link-icon-${esc(site.accent || 'default')}">${esc(site.iconText || site.name.split(' ').map((part) => part[0]).join('').slice(0, 2))}</span>
                                <span class="browser-homepage-quick-link-label">${esc(site.name)}</span>
                            </button>
                        `).join('')}
                    </div>
                    <div class="browser-homepage-dots"><span></span><span></span></div>
                </section>

                <section class="browser-homepage-search-wrap">
                    <form class="browser-homepage-search-card" id="browser-homepage-assistant-form">
                        <div class="browser-homepage-search-icon">🛡️</div>
                        <input type="text" id="browser-homepage-assistant-input" class="browser-homepage-search-input" placeholder="Ask anything, find anything...">
                        <button type="submit" class="browser-homepage-search-btn">Search</button>
                    </form>
                    <div class="browser-homepage-assistant-chips browser-homepage-search-chips">
                        <button type="button" data-assistant-query="nearest hospital">Nearest hospital</button>
                        <button type="button" data-assistant-query="nearest police station">Police station</button>
                        <button type="button" data-assistant-query="nearest mechanic">Nearest mechanic</button>
                        <button type="button" data-assistant-query="nearest store">Nearest store</button>
                        <button type="button" data-assistant-query="nearest gas station">Gas station</button>
                        <button type="button" data-assistant-query="tax rates">Tax rates</button>
                        <button type="button" data-assistant-query="new laws">New laws</button>
                        <button type="button" data-assistant-query="what jobs are available">Available jobs</button>
                        <button type="button" data-assistant-query="city hall">City Hall</button>
                        <button type="button" data-assistant-query="weather">Weather</button>
                    </div>
                    <div class="browser-homepage-assistant-status" id="browser-homepage-assistant-status">Ask by keyword, question, business type, or destination name.</div>
                    <div class="browser-homepage-assistant-results" id="browser-homepage-assistant-results"></div>
                </section>

                <section class="browser-homepage-panels">
                    <article class="browser-homepage-panel browser-homepage-stats-panel">
                        <div class="browser-homepage-panel-title">Stats</div>
                        <div class="browser-homepage-stats-grid" id="browser-homepage-stats-grid">
                            <div class="browser-homepage-stat-card"><strong>--</strong><span>Health</span></div>
                            <div class="browser-homepage-stat-card"><strong>--</strong><span>Hunger</span></div>
                            <div class="browser-homepage-stat-card"><strong>--</strong><span>Thirst</span></div>
                        </div>
                    </article>
                    <article class="browser-homepage-panel browser-homepage-news-panel">
                        <div class="browser-homepage-panel-title">News</div>
                        <div class="browser-homepage-news-card" id="browser-homepage-news-card">
                            <strong>Loading latest city update...</strong>
                            <p>Please wait while the latest mayor announcement or public law is loaded.</p>
                        </div>
                    </article>
                </section>
            </div>
        `;

        container.querySelectorAll('[data-home-url]').forEach((element) => {
            element.addEventListener('click', () => {
                const targetUrl = element.dataset.homeUrl;
                if (targetUrl) this.loadUrl(targetUrl);
            });
        });

        container.querySelector('.browser-homepage-import-btn')?.addEventListener('click', () => {
            const assistantStatus = container.querySelector('#browser-homepage-assistant-status');
            if (assistantStatus) assistantStatus.textContent = 'Bookmark import is not available yet. Save sites with the star button for now.';
        });

        const assistantInput = container.querySelector('#browser-homepage-assistant-input');
        const assistantStatus = container.querySelector('#browser-homepage-assistant-status');
        const assistantResults = container.querySelector('#browser-homepage-assistant-results');

        const runAssistantQuery = async (query) => {
            const cleanQuery = String(query || '').trim();
            if (!cleanQuery) {
                if (assistantStatus) assistantStatus.textContent = 'Enter a question or keyword to search the city assistant.';
                return;
            }

            if (assistantStatus) assistantStatus.textContent = `Searching for: ${cleanQuery}`;
            if (assistantResults) assistantResults.innerHTML = '<div class="browser-homepage-assistant-loading">Searching...</div>';

            const response = await nuiRequest('assistant:query', { query: cleanQuery });
            if (!response || !response.ok) {
                const code = response && response.error;
                let errMsg;
                if (code === 'nui_request_failed') {
                    errMsg = 'City assistant is not responding. The server resource may need to be restarted.';
                } else if (code === 'assistant_error' && response.message) {
                    errMsg = 'Assistant error: ' + response.message;
                } else if (code === 'no_permission') {
                    errMsg = 'City assistant is currently unavailable.';
                } else {
                    errMsg = 'City assistant could not process your request. Try again shortly.';
                }
                if (assistantStatus) assistantStatus.textContent = errMsg;
                if (assistantResults) assistantResults.innerHTML = '';
                return;
            }

            if (assistantStatus) assistantStatus.textContent = response.summary || 'Search complete.';

            // Auto-apply first waypoint action for answer mode.
            if (response.mode === 'answer' && Array.isArray(response.actions)) {
                const wpAction = response.actions.find((a) => a && a.type === 'waypoint' && a.coords);
                if (wpAction) {
                    await nuiRequest('assistant:setWaypoint', { x: wpAction.coords.x, y: wpAction.coords.y });
                }
            }

            this.renderBrowserAssistantResults(assistantResults, response.results || [], response.actions || []);
        };

        container.querySelector('#browser-homepage-assistant-form')?.addEventListener('submit', (event) => {
            event.preventDefault();
            runAssistantQuery(assistantInput?.value || '');
        });

        container.querySelectorAll('[data-assistant-query]').forEach((chip) => {
            chip.addEventListener('click', () => {
                const query = chip.dataset.assistantQuery || '';
                if (assistantInput) assistantInput.value = query;
                runAssistantQuery(query);
            });
        });

        this.populateBrowserHomepagePanels(container);
    }

    async populateBrowserHomepagePanels(container) {
        if (!container) return;

        const statsGrid = container.querySelector('#browser-homepage-stats-grid');
        const newsCard = container.querySelector('#browser-homepage-news-card');
        const esc = (value) => this.escapeHtml(value);

        try {
            const vitalsResponse = await nuiRequest('browser:getVitals', {});
            const vitals = vitalsResponse && vitalsResponse.ok ? (vitalsResponse.vitals || {}) : {};
            const health = Number(vitals.health || 0);
            const hunger = Number(vitals.hunger || 0);
            const thirst = Number(vitals.thirst || 0);
            if (statsGrid) {
                statsGrid.innerHTML = `
                    <div class="browser-homepage-stat-card"><strong>${esc(Math.max(0, Math.min(100, Math.round(health))))}</strong><span>Health</span></div>
                    <div class="browser-homepage-stat-card"><strong>${esc(Math.max(0, Math.min(100, Math.round(hunger))))}</strong><span>Hunger</span></div>
                    <div class="browser-homepage-stat-card"><strong>${esc(Math.max(0, Math.min(100, Math.round(thirst))))}</strong><span>Thirst</span></div>
                `;
            }
        } catch (e) {
            if (statsGrid) {
                statsGrid.innerHTML = `
                    <div class="browser-homepage-stat-card"><strong>--</strong><span>Health</span></div>
                    <div class="browser-homepage-stat-card"><strong>--</strong><span>Hunger</span></div>
                    <div class="browser-homepage-stat-card"><strong>--</strong><span>Thirst</span></div>
                `;
            }
        }

        try {
            const [announcementsRes, lawsRes] = await Promise.all([
                nuiRequest('gov:getAnnouncements', {}),
                nuiRequest('law:getAll', { status: 'all' })
            ]);

            const announcement = Array.isArray(announcementsRes?.data) && announcementsRes.data.length ? announcementsRes.data[0] : null;
            const laws = Array.isArray(lawsRes?.laws) ? lawsRes.laws : [];
            const publishedLaw = laws.find((law) => String(law.status || '').toLowerCase() === 'published') || laws[0] || null;

            const announcementTime = announcement ? new Date(announcement.createdAt || 0).getTime() || 0 : 0;
            const lawTime = publishedLaw ? new Date(publishedLaw.updated_at || publishedLaw.created_at || 0).getTime() || 0 : 0;

            const latestItem = announcementTime >= lawTime ? {
                type: announcement ? 'Mayor Announcement' : (publishedLaw ? 'City News' : 'none'),
                title: announcement?.title || publishedLaw?.title || 'No updates available',
                body: announcement?.body || publishedLaw?.description || publishedLaw?.summary || 'No mayor announcement or public news is available right now.',
                meta: announcement ? (announcement.author || 'Mayor') : (publishedLaw ? 'Published law' : ''),
                url: announcement ? 'https://los-santos.gov#announcements' : (publishedLaw ? 'https://los-santos.gov#laws' : '')
            } : {
                type: publishedLaw ? 'City News' : (announcement ? 'Mayor Announcement' : 'none'),
                title: publishedLaw?.title || announcement?.title || 'No updates available',
                body: publishedLaw?.description || publishedLaw?.summary || announcement?.body || 'No mayor announcement or public news is available right now.',
                meta: publishedLaw ? 'Published law' : (announcement ? (announcement.author || 'Mayor') : ''),
                url: publishedLaw ? 'https://los-santos.gov#laws' : (announcement ? 'https://los-santos.gov#announcements' : '')
            };

            if (newsCard) {
                newsCard.innerHTML = `
                    <div class="browser-homepage-news-eyebrow">${esc(latestItem.type)}</div>
                    <strong>${esc(latestItem.title)}</strong>
                    <p>${esc(String(latestItem.body || '').slice(0, 220))}</p>
                    ${latestItem.meta ? `<span>${esc(latestItem.meta)}</span>` : ''}
                `;
                if (latestItem.url) {
                    newsCard.setAttribute('data-home-url', latestItem.url);
                    newsCard.classList.add('browser-homepage-news-card-clickable');
                    newsCard.addEventListener('click', () => this.loadUrl(latestItem.url), { once: true });
                }
            }
        } catch (e) {
            if (newsCard) {
                newsCard.innerHTML = '<strong>No updates available</strong><p>The browser could not load the latest mayor announcement or city news.</p>';
            }
        }
    }

    renderBrowserAssistantResults(container, results, actions = []) {
        if (!container) return;

        const esc = (value) => this.escapeHtml(value);
        if (!Array.isArray(results) || results.length === 0) {
            container.innerHTML = '<div class="browser-homepage-assistant-empty">No matches found. Try: nearest hospital, police station, tax rates, new laws, jobs, weather.</div>';
            return;
        }

        const actionCards = (Array.isArray(actions) ? actions : []).map((action) => {
            if (!action || !action.type) return '';
            if (action.type === 'open_url' && action.url) {
                return `<button class="browser-homepage-assistant-action browser-homepage-assistant-action-primary" data-assistant-open-url="${esc(action.url)}">${esc(action.label || 'Open')}</button>`;
            }
            if (action.type === 'waypoint' && action.coords) {
                return `<button class="browser-homepage-assistant-action" data-assistant-waypoint="1" data-waypoint-x="${esc(action.coords.x)}" data-waypoint-y="${esc(action.coords.y)}">${esc(action.label || 'Set Waypoint')}</button>`;
            }
            return '';
        }).filter(Boolean).join('');

        const resultCards = results.map((item) => {
            // Support both item.waypoint and item.coords (new format)
            const wp = item && (item.waypoint || item.coords);
            const hasWaypoint = item && item.hasWaypoint && wp && Number.isFinite(Number(wp.x)) && Number.isFinite(Number(wp.y));

            const waypointButton = hasWaypoint
                ? `<button class="browser-homepage-assistant-action" data-assistant-waypoint="1" data-waypoint-x="${esc(wp.x)}" data-waypoint-y="${esc(wp.y)}">Set Waypoint</button>`
                : '';
            const openButton = item && item.url
                ? `<button class="browser-homepage-assistant-action browser-homepage-assistant-action-primary" data-assistant-open-url="${esc(item.url)}">Open</button>`
                : '';

            // Badges
            const nearestBadge = item.nearest
                ? '<span class="browser-homepage-assistant-badge browser-homepage-assistant-badge-nearest">Nearest</span>'
                : '';
            const distanceBadge = item.distance != null
                ? `<span class="browser-homepage-assistant-badge browser-homepage-assistant-badge-dist">~${esc(item.distance)}m</span>`
                : '';

            const category = esc(item.category || item.type || 'result');

            return `
                <article class="browser-homepage-assistant-card${item.nearest ? ' browser-homepage-assistant-card-nearest' : ''}">
                    <div class="browser-homepage-assistant-card-header">
                        <div class="browser-homepage-assistant-card-meta">${category}</div>
                        <div class="browser-homepage-assistant-card-badges">${nearestBadge}${distanceBadge}</div>
                    </div>
                    <h3>${esc(item.title || 'Result')}</h3>
                    <p>${esc(item.description || '')}</p>
                    <div class="browser-homepage-assistant-actions">
                        ${openButton}
                        ${waypointButton}
                    </div>
                </article>
            `;
        }).join('');

        container.innerHTML = `
            ${actionCards ? `<div class="browser-homepage-assistant-actions-global">${actionCards}</div>` : ''}
            ${resultCards}
        `;

        container.querySelectorAll('[data-assistant-open-url]').forEach((button) => {
            button.addEventListener('click', () => {
                const targetUrl = button.dataset.assistantOpenUrl;
                if (targetUrl) this.loadUrl(targetUrl);
            });
        });

        container.querySelectorAll('[data-assistant-waypoint="1"]').forEach((button) => {
            button.addEventListener('click', async () => {
                const x = Number(button.dataset.waypointX);
                const y = Number(button.dataset.waypointY);
                if (!Number.isFinite(x) || !Number.isFinite(y)) return;

                const res = await nuiRequest('assistant:setWaypoint', { x, y });
                const status = document.querySelector('#browser-homepage-assistant-status');
                if (status) {
                    status.textContent = res && res.ok
                        ? `Waypoint set to ${x.toFixed(1)}, ${y.toFixed(1)}.`
                        : 'Unable to set waypoint for that result.';
                }
            });
        });
    }

    async loadUrl(url, skipHistory = false) {
        const normalizedUrl = this.normalizeUrl(url);
        this.currentUrl = normalizedUrl;
        if (!skipHistory) this.pushHistory(normalizedUrl);

        const urlInput = document.querySelector('#browser-window .browser-url');
        if (urlInput) urlInput.value = normalizedUrl;

        const container = this.getContent();
        if (!container) return;

        if (this.isBrowserHomeUrl(normalizedUrl)) {
            this.renderBrowserHome(container);
            return;
        }

        if (/los-santos\.gov|cityhall\.ls|business\.ls/i.test(normalizedUrl)) {
            await this.renderGovPortal(container, normalizedUrl);
            return;
        }

        container.innerHTML = `
            <div class="mayor-browser-empty">
                <h2>${normalizedUrl}</h2>
                <p>External web content is unavailable in the mayor terminal. Use approved city domains.</p>
            </div>
        `;
    }

    async renderGovPortal(container, url) {
        this.websiteState = this.normalizeWebsiteState(this.websiteState || this.loadWebsiteState());
        await this.hydrateWebsiteStateFromServer();
        this.websiteState = this.normalizeWebsiteState(this.websiteState || this.loadWebsiteState());
        this.portalUiState.activePage = this.getGovPortalPageFromUrl(url || this.currentUrl);

        const [announcementRes, lawsRes, taxesRes, categoriesRes] = await Promise.all([
            nuiRequest('gov:getAnnouncements', {}),
            nuiRequest('law:getAll', { status: 'all' }),
            nuiRequest('tax:getAll', {}),
            nuiRequest('law:getCategories', {})
        ]);

        const announcements = announcementRes && announcementRes.ok ? (announcementRes.data || []) : [];
        const laws = lawsRes && lawsRes.ok ? (lawsRes.laws || []).filter((law) => String(law.status || '').toLowerCase() === 'active' || String(law.status || '').toLowerCase() === 'mdt_reference') : [];
        const taxes = taxesRes && taxesRes.ok ? (taxesRes.taxes || []) : [];
        const categories = categoriesRes && categoriesRes.ok ? (categoriesRes.categories || []) : [];

        const esc = (value) => this.escapeHtml(value);
        const pageState = this.websiteState.pages || {};
        const siteChrome = this.websiteState.siteChrome || this.getDefaultWebsiteState().siteChrome;
        const homePage = pageState.home || this.getDefaultWebsiteState().pages.home;
        const announcementsPage = pageState.announcements || this.getDefaultWebsiteState().pages.announcements;
        const lawsPage = pageState.laws || this.getDefaultWebsiteState().pages.laws;
        const taxesPage = pageState.taxes || this.getDefaultWebsiteState().pages.taxes;
        const latestAnnouncement = announcements[0];
        const latestLaw = laws[0];
        const activeTaxCount = taxes.filter(tax => Number(tax.enabled || 0) > 0).length;
        const categoryOptions = ['all', ...categories.filter(Boolean)];
        const pageNames = {
            home: 'Government Portal',
            announcements: 'Public Notices',
            laws: 'Municipal Code',
            taxes: 'Taxes & Fees',
            editor: 'Administration'
        };

        const renderEditorBlocks = (blocks) => (Array.isArray(blocks) ? blocks : []).map((block, index) => {
            const title = esc(block.title || this.getWebsiteBlockTypeLabel(block.type));
            const typeLabel = esc(this.getWebsiteBlockTypeLabel(block.type));
            const preview = esc(block.body || '').slice(0, 110) || 'No summary has been entered for this module yet.';
            const itemCount = Array.isArray(block.items) ? block.items.length : 0;
            return `
                <article class="gov-site-editor-module" data-block-id="${esc(block.id)}" data-block-type="${esc(block.type)}" draggable="true">
                    <div class="gov-site-editor-module-rail"></div>
                    <div class="gov-site-editor-module-head">
                        <button class="gov-site-editor-module-drag" type="button" title="Drag to reorder" aria-label="Drag to reorder">
                            <span></span><span></span><span></span>
                        </button>
                        <div class="gov-site-editor-module-summary">
                            <div class="gov-site-editor-module-meta">
                                <span class="gov-site-editor-module-index">Module ${index + 1}</span>
                                <span class="gov-site-editor-module-type">${typeLabel}</span>
                            </div>
                            <strong>${title}</strong>
                            <p>${preview}</p>
                        </div>
                        <div class="gov-site-editor-module-tools">
                            <button class="btn btn-secondary gov-site-editor-action-duplicate" type="button">Duplicate</button>
                            <button class="btn btn-danger gov-site-editor-action-delete" type="button">Delete</button>
                        </div>
                    </div>
                    <div class="gov-site-editor-module-stats">
                        <span>${itemCount} item${itemCount === 1 ? '' : 's'}</span>
                        <span>Target page: ${esc(block.buttonPage || 'home')}</span>
                    </div>
                    <div class="gov-site-editor-module-body">
                        <div class="gov-site-editor-block-grid">
                            <label>
                                <span>Module Type</span>
                                <select class="form-input gov-site-block-type">
                                    <option value="content">Content Box</option>
                                    <option value="callout">Callout Banner</option>
                                    <option value="cards">Cards Grid</option>
                                    <option value="links">Quick Links</option>
                                </select>
                            </label>
                            <label>
                                <span>Section Label</span>
                                <input class="form-input gov-site-block-eyebrow" type="text" placeholder="Section kicker">
                            </label>
                            <label class="gov-site-editor-block-wide">
                                <span>Module Heading</span>
                                <input class="form-input gov-site-block-title" type="text" placeholder="Module heading">
                            </label>
                            <label class="gov-site-editor-block-wide">
                                <span>Body Copy</span>
                                <textarea class="form-input gov-site-block-body" rows="4" placeholder="Main body copy"></textarea>
                            </label>
                            <label class="gov-site-editor-block-wide">
                                <span>Structured Items</span>
                                <textarea class="form-input gov-site-block-items" rows="4" placeholder="One item per line. Use Title|Description for cards or Label|page for quick links."></textarea>
                            </label>
                            <label>
                                <span>Button Label</span>
                                <input class="form-input gov-site-block-button-label" type="text" placeholder="Optional action button">
                            </label>
                            <label>
                                <span>Button Destination</span>
                                <select class="form-input gov-site-block-button-page">
                                    <option value="home">Home</option>
                                    <option value="announcements">Public Notices</option>
                                    <option value="laws">Municipal Code</option>
                                    <option value="taxes">Taxes & Fees</option>
                                    <option value="editor">Administration</option>
                                </select>
                            </label>
                        </div>
                    </div>
                </article>
            `;
        }).join('') || '<div class="gov-site-empty-state">No modules have been added to this page yet.</div>';

        container.innerHTML = `
            <div class="mayor-browser-site gov-site-shell ${this.portalUiState.editMode ? 'is-website-editing' : ''}">
                <div class="gov-site-utilitybar">
                    <div class="gov-site-utility-inner">
                        <span data-gov-inline-edit="siteChrome.utilityPrimary">${esc(siteChrome.utilityPrimary || '')}</span>
                        <span class="gov-site-utility-sep">|</span>
                        <span data-gov-inline-edit="siteChrome.utilitySecondary">${esc(siteChrome.utilitySecondary || '')}</span>
                    </div>
                </div>

                <header class="gov-site-header">
                    <div class="gov-site-header-inner">
                        <div class="gov-site-brand-lockup">
                            <div class="gov-site-seal">LS</div>
                            <div class="gov-site-brand-text">
                                <div class="gov-site-kicker" data-gov-inline-edit="siteChrome.brandKicker">${esc(siteChrome.brandKicker || '')}</div>
                                <h1 data-gov-inline-edit="siteChrome.brandTitle">${esc(siteChrome.brandTitle || '')}</h1>
                                <p data-gov-inline-edit="siteChrome.brandSubtitle">${esc(siteChrome.brandSubtitle || '')}</p>
                            </div>
                        </div>
                        <div class="gov-site-header-meta">
                            <div class="gov-site-meta-label">Portal Address</div>
                            <div class="gov-site-meta-value">${esc(url)}</div>
                            <button class="btn btn-secondary gov-site-edit-toggle">Edit Website</button>
                        </div>
                    </div>
                </header>

                <nav class="gov-site-mainnav" aria-label="Primary">
                    <div class="gov-site-mainnav-inner">
                        <button class="mayor-browser-nav-btn active" data-page="home">Home</button>
                        <button class="mayor-browser-nav-btn" data-page="announcements">Public Notices</button>
                        <button class="mayor-browser-nav-btn" data-page="laws">Municipal Code</button>
                        <button class="mayor-browser-nav-btn" data-page="taxes">Taxes & Fees</button>
                        <button class="mayor-browser-nav-btn" data-page="editor">Administration</button>
                    </div>
                </nav>

                <div class="gov-site-breadcrumbs">
                    <span>Home</span>
                    <span class="gov-site-breadcrumb-arrow">/</span>
                    <span class="gov-site-current-page">${esc(pageNames[this.portalUiState.activePage] || 'Government Portal')}</span>
                </div>

                <section class="mayor-browser-page gov-site-page" data-page="home">
                    <div class="gov-site-alert-banner">
                        <strong>Official Notice:</strong>
                        <span data-gov-inline-edit="globalNotice">${esc(this.websiteState.globalNotice || (latestAnnouncement ? latestAnnouncement.title : 'Recent public notice available for review.'))}</span>
                    </div>

                    <div class="gov-site-home-layout">
                        <aside class="gov-site-sidebar">
                            <div class="gov-site-sidebar-block">
                                <div class="gov-site-sidebar-title">Public Services</div>
                                <a class="gov-site-sidebar-link" data-page-link="announcements">Public Notices & Alerts</a>
                                <a class="gov-site-sidebar-link" data-page-link="laws">Municipal Code</a>
                                <a class="gov-site-sidebar-link" data-page-link="taxes">Taxes, Rates, and Fees</a>
                                <a class="gov-site-sidebar-link" data-page-link="editor">Administrative Services</a>
                            </div>
                            <div class="gov-site-sidebar-block">
                                <div class="gov-site-sidebar-title" data-gov-inline-edit="siteChrome.homeSidebarTitle">${esc(siteChrome.homeSidebarTitle || '')}</div>
                                <div class="gov-site-sidebar-text" data-gov-inline-edit="siteChrome.homeSidebarLine1">${esc(siteChrome.homeSidebarLine1 || '')}</div>
                                <div class="gov-site-sidebar-text" data-gov-inline-edit="siteChrome.homeSidebarLine2">${esc(siteChrome.homeSidebarLine2 || '')}</div>
                                <div class="gov-site-sidebar-text" data-gov-inline-edit="siteChrome.homeSidebarLine3">${esc(siteChrome.homeSidebarLine3 || '')}</div>
                            </div>
                        </aside>

                        <div class="gov-site-content">
                            <section class="gov-site-hero-panel">
                                <div>
                                    <div class="gov-site-section-kicker" data-gov-inline-edit="page.home.kicker">${esc(homePage.kicker || '')}</div>
                                    <h2 data-gov-page-title data-gov-inline-edit="page.home.title">${esc(homePage.title || '')}</h2>
                                    <p data-gov-page-intro data-gov-inline-edit="page.home.intro">${esc(homePage.intro || '')}</p>
                                </div>
                                <div class="gov-site-searchbox">
                                    <label for="gov-site-home-search">Search government records</label>
                                    <input id="gov-site-home-search" type="text" class="form-input" placeholder="Search laws, announcements, categories, or taxes">
                                </div>
                            </section>

                            <section class="gov-site-kpi-grid">
                                <article class="gov-site-kpi-card">
                                    <div class="gov-site-kpi-label">Active Public Notices</div>
                                    <div class="gov-site-kpi-value">${announcements.length}</div>
                                </article>
                                <article class="gov-site-kpi-card">
                                    <div class="gov-site-kpi-label">Published Ordinances</div>
                                    <div class="gov-site-kpi-value">${laws.length}</div>
                                </article>
                                <article class="gov-site-kpi-card">
                                    <div class="gov-site-kpi-label">Active Tax Schedules</div>
                                    <div class="gov-site-kpi-value">${activeTaxCount}</div>
                                </article>
                            </section>

                            <section class="gov-site-two-col">
                                <article class="gov-site-panel">
                                    <div class="gov-site-panel-head">
                                        <h3>Latest Public Notice</h3>
                                        <button class="gov-site-text-link" data-page-link="announcements">View all notices</button>
                                    </div>
                                    ${latestAnnouncement ? `
                                        <div class="gov-site-notice-card">
                                            <div class="gov-site-doc-meta">Published ${esc(latestAnnouncement.created_at || '')}</div>
                                            <h4>${esc(latestAnnouncement.title || 'Untitled')}</h4>
                                            <p>${esc(String(latestAnnouncement.content || '').slice(0, 320))}${String(latestAnnouncement.content || '').length > 320 ? '...' : ''}</p>
                                        </div>
                                    ` : '<div class="gov-site-empty-state">No public notices are available.</div>'}
                                </article>

                                <article class="gov-site-panel">
                                    <div class="gov-site-panel-head">
                                        <h3>Latest Ordinance</h3>
                                        <button class="gov-site-text-link" data-page-link="laws">Browse code library</button>
                                    </div>
                                    ${latestLaw ? `
                                        <div class="gov-site-notice-card">
                                            <div class="gov-site-doc-meta">${esc(latestLaw.category || 'General')} • ${esc(latestLaw.status || 'active')}</div>
                                            <h4>${esc(latestLaw.title || 'Untitled')}</h4>
                                            <p>${esc(String(latestLaw.content || '').slice(0, 280))}${String(latestLaw.content || '').length > 280 ? '...' : ''}</p>
                                        </div>
                                    ` : '<div class="gov-site-empty-state">No active ordinances are published.</div>'}
                                </article>
                            </section>
                            <div class="gov-site-custom-area">${this.renderWebsiteBlocks(homePage.blocks)}</div>
                        </div>
                    </div>
                </section>

                <section class="mayor-browser-page gov-site-page" data-page="announcements" style="display:none;">
                    <div class="gov-site-section-header">
                        <div>
                            <div class="gov-site-section-kicker" data-gov-inline-edit="page.announcements.kicker">${esc(announcementsPage.kicker || '')}</div>
                            <h2 data-gov-page-title data-gov-inline-edit="page.announcements.title">${esc(announcementsPage.title || '')}</h2>
                            <p data-gov-page-intro data-gov-inline-edit="page.announcements.intro">${esc(announcementsPage.intro || '')}</p>
                        </div>
                    </div>
                    <div class="gov-site-custom-area gov-site-custom-area-tight">${this.renderWebsiteBlocks(announcementsPage.blocks)}</div>
                    <div class="gov-site-records-grid">
                        ${(announcements || []).map(item => `
                            <article class="gov-site-record-card">
                                <div class="gov-site-doc-meta">Notice • ${esc(item.created_at || '')}</div>
                                <h3>${esc(item.title || 'Untitled')}</h3>
                                <p>${esc(item.content || '')}</p>
                            </article>
                        `).join('') || '<div class="gov-site-empty-state">No announcements available.</div>'}
                    </div>
                </section>

                <section class="mayor-browser-page gov-site-page" data-page="laws" style="display:none;">
                    <div class="gov-site-section-header gov-site-section-header-spread">
                        <div>
                            <div class="gov-site-section-kicker" data-gov-inline-edit="page.laws.kicker">${esc(lawsPage.kicker || '')}</div>
                            <h2 data-gov-page-title data-gov-inline-edit="page.laws.title">${esc(lawsPage.title || '')}</h2>
                            <p data-gov-page-intro data-gov-inline-edit="page.laws.intro">${esc(lawsPage.intro || '')}</p>
                        </div>
                        <div class="gov-site-inline-filters">
                            <input id="gov-law-search" class="form-input gov-site-filter-input" placeholder="Search title or content">
                            <select id="gov-law-category-filter" class="form-input gov-site-filter-select">
                                ${categoryOptions.map(cat => `<option value="${esc(cat)}">${esc(cat === 'all' ? 'All Categories' : cat)}</option>`).join('')}
                            </select>
                        </div>
                    </div>
                    <div class="gov-site-custom-area gov-site-custom-area-tight">${this.renderWebsiteBlocks(lawsPage.blocks)}</div>
                    <div id="gov-laws-list" class="gov-site-records-grid gov-site-records-grid-laws">
                        ${(laws || []).map(item => `
                            <article class="gov-site-record-card gov-law-card" data-law-category="${esc(String(item.category || 'general').toLowerCase())}" data-law-search="${esc(`${item.title || ''} ${item.content || ''}`.toLowerCase())}">
                                <div class="gov-site-doc-meta">${esc(item.category || 'general')} • ${esc(item.status || 'active')}</div>
                                <h3>${esc(item.title || 'Untitled')}</h3>
                                <p>${esc(item.content || '')}</p>
                            </article>
                        `).join('') || '<div class="gov-site-empty-state">No laws available.</div>'}
                    </div>
                </section>

                <section class="mayor-browser-page gov-site-page" data-page="taxes" style="display:none;">
                    <div class="gov-site-section-header">
                        <div>
                            <div class="gov-site-section-kicker" data-gov-inline-edit="page.taxes.kicker">${esc(taxesPage.kicker || '')}</div>
                            <h2 data-gov-page-title data-gov-inline-edit="page.taxes.title">${esc(taxesPage.title || '')}</h2>
                            <p data-gov-page-intro data-gov-inline-edit="page.taxes.intro">${esc(taxesPage.intro || '')}</p>
                        </div>
                    </div>
                    <div class="gov-site-custom-area gov-site-custom-area-tight">${this.renderWebsiteBlocks(taxesPage.blocks)}</div>
                    <div class="gov-site-table-shell">
                        <table class="gov-site-table">
                            <thead>
                                <tr><th>Tax Type</th><th>Current Rate</th><th>Allowed Range</th><th>Status</th></tr>
                            </thead>
                            <tbody>
                                ${(taxes || []).map(tax => `
                                    <tr>
                                        <td><strong>${esc(String(tax.tax_type || '').replace(/_/g, ' '))}</strong></td>
                                        <td>${Number(tax.rate || 0)}%</td>
                                        <td>${Number(tax.min_rate || 0)}% to ${Number(tax.max_rate || 0)}%</td>
                                        <td><span class="gov-site-status-pill ${Number(tax.enabled || 0) > 0 ? 'is-active' : 'is-inactive'}">${Number(tax.enabled || 0) > 0 ? 'Active' : 'Inactive'}</span></td>
                                    </tr>
                                `).join('') || '<tr><td colspan="4" class="text-muted">No tax data.</td></tr>'}
                            </tbody>
                        </table>
                    </div>
                </section>

                <section class="mayor-browser-page gov-site-page" data-page="editor" style="display:none;">
                    <div class="gov-site-section-header">
                        <div>
                            <div class="gov-site-section-kicker">Restricted Access</div>
                            <h2>Mayor and Administrative Publishing Console</h2>
                            <p>Internal government tools for publishing notices, updating ordinances, and managing tax schedules.</p>
                        </div>
                    </div>
                    <div class="mayor-browser-editor-grid gov-admin-grid">
                        <div class="mayor-browser-editor-card gov-admin-card">
                            <h3>Publish Public Notice</h3>
                            <input id="mb-ann-title" class="form-input" placeholder="Notice title">
                            <textarea id="mb-ann-content" class="form-input" rows="5" placeholder="Official announcement body"></textarea>
                            <button id="mb-ann-submit" class="btn btn-primary">Publish Notice</button>
                        </div>

                        <div class="mayor-browser-editor-card gov-admin-card">
                            <h3>Create Ordinance</h3>
                            <input id="mb-law-title" class="form-input" placeholder="Ordinance title">
                            <select id="mb-law-category" class="form-input">
                                ${(categories || []).map(cat => `<option value="${esc(cat)}">${esc(cat)}</option>`).join('')}
                            </select>
                            <textarea id="mb-law-content" class="form-input" rows="5" placeholder="Ordinance content"></textarea>
                            <div class="mayor-browser-inline-fields">
                                <input id="mb-law-fine" class="form-input" type="number" placeholder="Fine amount">
                                <input id="mb-law-jail" class="form-input" type="number" placeholder="Jail months">
                            </div>
                            <label class="mayor-browser-inline-check"><input id="mb-law-publish" type="checkbox" checked> Publish immediately</label>
                            <button id="mb-law-submit" class="btn btn-primary">Save Ordinance</button>
                        </div>

                        <div class="mayor-browser-editor-card gov-admin-card">
                            <h3>Update Tax Schedule</h3>
                            <div class="mayor-browser-tax-edit-list">
                                ${(taxes || []).map(tax => `
                                    <div class="mayor-browser-tax-edit-row" data-tax="${esc(tax.tax_type || '')}">
                                        <div class="mayor-browser-tax-edit-title">${esc(String(tax.tax_type || '').replace(/_/g, ' '))}</div>
                                        <input class="form-input mayor-browser-tax-rate" type="number" min="${Number(tax.min_rate || 0)}" max="${Number(tax.max_rate || 100)}" value="${Number(tax.rate || 0)}">
                                        <label><input class="mayor-browser-tax-enabled" type="checkbox" ${Number(tax.enabled || 0) > 0 ? 'checked' : ''}> Enabled</label>
                                        <button class="btn btn-secondary mayor-browser-tax-save">Save</button>
                                    </div>
                                `).join('')}
                            </div>
                        </div>
                    </div>
                </section>

                <footer class="gov-site-footer">
                    <div class="gov-site-footer-grid">
                        <div>
                            <div class="gov-site-footer-title" data-gov-inline-edit="siteChrome.footerAboutTitle">${esc(siteChrome.footerAboutTitle || '')}</div>
                            <p data-gov-inline-edit="siteChrome.footerAboutBody">${esc(siteChrome.footerAboutBody || '')}</p>
                        </div>
                        <div>
                            <div class="gov-site-footer-title" data-gov-inline-edit="siteChrome.footerResourcesTitle">${esc(siteChrome.footerResourcesTitle || '')}</div>
                            <ul>
                                ${(Array.isArray(siteChrome.footerResourcesItems) ? siteChrome.footerResourcesItems : []).map((item, index) => `<li data-gov-inline-edit="siteChrome.footerResourcesItems.${index}">${esc(item)}</li>`).join('')}
                            </ul>
                        </div>
                        <div>
                            <div class="gov-site-footer-title" data-gov-inline-edit="siteChrome.footerContactTitle">${esc(siteChrome.footerContactTitle || '')}</div>
                            <p data-gov-inline-edit="siteChrome.footerContactAddress">${esc(siteChrome.footerContactAddress || '')}</p>
                            <p data-gov-inline-edit="siteChrome.footerContactHours">${esc(siteChrome.footerContactHours || '')}</p>
                        </div>
                    </div>
                </footer>

                <aside class="gov-site-editor-drawer">
                    <div class="gov-site-editor-header">
                        <div>
                            <div class="gov-site-section-kicker">Website Builder</div>
                            <h3>Website content designer</h3>
                            <p>Build each public page with reusable modules, structured content sections, and drag-and-drop ordering.</p>
                        </div>
                        <div class="gov-site-editor-header-badge">Professional layout mode</div>
                    </div>
                    <div class="gov-site-editor-body">
                        <section class="gov-site-editor-panel gov-site-editor-panel-compact">
                            <div class="gov-site-editor-panel-head">
                                <h4>Page Settings</h4>
                                <p>Select the public page you want to manage.</p>
                            </div>
                            <label>
                                <span>Edit Page</span>
                                <select id="gov-site-editor-page" class="form-input">
                                    <option value="home">Home</option>
                                    <option value="announcements">Public Notices</option>
                                    <option value="laws">Municipal Code</option>
                                    <option value="taxes">Taxes & Fees</option>
                                </select>
                            </label>
                            <label>
                                <span>Official Notice Banner</span>
                                <textarea id="gov-site-global-notice" class="form-input" rows="3" placeholder="Global notice shown on the home page banner"></textarea>
                            </label>
                            <label>
                                <span>Section Label</span>
                                <input id="gov-site-page-kicker" class="form-input" type="text" placeholder="Section label">
                            </label>
                            <label>
                                <span>Page Heading</span>
                                <input id="gov-site-page-title" class="form-input" type="text" placeholder="Page heading">
                            </label>
                            <label>
                                <span>Intro Paragraph</span>
                                <textarea id="gov-site-page-intro" class="form-input" rows="4" placeholder="Page introduction"></textarea>
                            </label>
                            <div class="gov-site-editor-subhead">Website Header & Footer</div>
                            <label>
                                <span>Header Label</span>
                                <input id="gov-site-brand-kicker" class="form-input" type="text" placeholder="City of Los Santos">
                            </label>
                            <label>
                                <span>Header Title</span>
                                <input id="gov-site-brand-title" class="form-input" type="text" placeholder="Los Santos Government Portal">
                            </label>
                            <label>
                                <span>Header Subtitle</span>
                                <textarea id="gov-site-brand-subtitle" class="form-input" rows="3" placeholder="Portal subtitle text"></textarea>
                            </label>
                            <label>
                                <span>Footer About Title</span>
                                <input id="gov-site-footer-about-title" class="form-input" type="text" placeholder="City of Los Santos">
                            </label>
                            <label>
                                <span>Footer About Text</span>
                                <textarea id="gov-site-footer-about-body" class="form-input" rows="3" placeholder="Footer about copy"></textarea>
                            </label>
                            <label>
                                <span>Footer Resources (one item per line)</span>
                                <textarea id="gov-site-footer-resources-items" class="form-input" rows="4" placeholder="Public Notices&#10;Municipal Code"></textarea>
                            </label>
                            <label>
                                <span>Footer Contact Title</span>
                                <input id="gov-site-footer-contact-title" class="form-input" type="text" placeholder="Contact">
                            </label>
                            <label>
                                <span>Footer Contact Address</span>
                                <input id="gov-site-footer-contact-address" class="form-input" type="text" placeholder="Alta Street, Los Santos">
                            </label>
                            <label>
                                <span>Footer Contact Hours</span>
                                <input id="gov-site-footer-contact-hours" class="form-input" type="text" placeholder="Mon - Fri, 08:00 to 17:00">
                            </label>
                        </section>

                        <section class="gov-site-editor-panel gov-site-editor-panel-compact">
                            <div class="gov-site-editor-panel-head">
                                <h4>Module Library</h4>
                                <p>Choose a preset, then drag modules to reorder the page like a professional CMS.</p>
                            </div>
                            <div class="gov-site-module-library">
                                <button class="gov-site-module-preset" type="button" data-module-type="content">
                                    <strong>Content Box</strong>
                                    <span>Standard text section for public information.</span>
                                </button>
                                <button class="gov-site-module-preset" type="button" data-module-type="callout">
                                    <strong>Callout Banner</strong>
                                    <span>Prominent highlighted notice or advisory block.</span>
                                </button>
                                <button class="gov-site-module-preset" type="button" data-module-type="cards">
                                    <strong>Cards Grid</strong>
                                    <span>Multi-card layout for featured services or summaries.</span>
                                </button>
                                <button class="gov-site-module-preset" type="button" data-module-type="links">
                                    <strong>Quick Links</strong>
                                    <span>Shortcut list for key government destinations.</span>
                                </button>
                            </div>
                        </section>

                        <section class="gov-site-editor-panel">
                            <div class="gov-site-editor-panel-head gov-site-editor-panel-head-row">
                                <div>
                                    <h4>Page Modules</h4>
                                    <p>Drag modules into the order you want them to appear on the public website.</p>
                                </div>
                                <div class="gov-site-editor-panel-note">Drag and drop enabled</div>
                            </div>
                            <div class="gov-site-editor-blocks">${renderEditorBlocks(this.websiteState.pages[this.portalUiState.editorPage || 'home']?.blocks || [])}</div>
                        </section>
                    </div>
                    <div class="gov-site-editor-footer">
                        <button id="gov-site-save-layout" class="btn btn-primary">Save Website</button>
                        <button id="gov-site-reset-layout" class="btn btn-secondary">Reset Preset</button>
                    </div>
                </aside>
            </div>
        `;

        const navButtons = container.querySelectorAll('.mayor-browser-nav-btn');
        const pages = container.querySelectorAll('.mayor-browser-page');
        let switchPage = (page) => {
            this.portalUiState.activePage = page;
            const currentBaseUrl = String(this.currentUrl || 'https://los-santos.gov').split('#')[0];
            this.currentUrl = page === 'home' ? currentBaseUrl : `${currentBaseUrl}#${page}`;
            const browserUrlInput = document.querySelector('#browser-window .browser-url');
            if (browserUrlInput) browserUrlInput.value = this.currentUrl;
            navButtons.forEach(btn => btn.classList.toggle('active', btn.dataset.page === page));
            pages.forEach(section => {
                section.style.display = section.dataset.page === page ? '' : 'none';
            });
        };
        container.querySelectorAll('[data-page-link]').forEach(link => {
            link.addEventListener('click', () => switchPage(link.dataset.pageLink));
        });

        const breadcrumbCurrent = container.querySelector('.gov-site-current-page');
        const originalSwitchPage = switchPage;
        switchPage = (page) => {
            originalSwitchPage(page);
            if (breadcrumbCurrent) breadcrumbCurrent.textContent = pageNames[page] || 'Government Portal';
        };
        navButtons.forEach(btn => {
            btn.addEventListener('click', () => switchPage(btn.dataset.page));
        });

        const lawSearch = container.querySelector('#gov-law-search');
        const lawCategoryFilter = container.querySelector('#gov-law-category-filter');
        const filterLawCards = () => {
            const term = (lawSearch?.value || '').trim().toLowerCase();
            const category = (lawCategoryFilter?.value || 'all').toLowerCase();
            container.querySelectorAll('.gov-law-card').forEach(card => {
                const matchesTerm = !term || (card.dataset.lawSearch || '').includes(term);
                const matchesCategory = category === 'all' || (card.dataset.lawCategory || '') === category;
                card.style.display = matchesTerm && matchesCategory ? '' : 'none';
            });
        };
        lawSearch?.addEventListener('input', filterLawCards);
        lawCategoryFilter?.addEventListener('change', filterLawCards);

        container.querySelector('#mb-ann-submit')?.addEventListener('click', async () => {
            const title = container.querySelector('#mb-ann-title')?.value.trim();
            const content = container.querySelector('#mb-ann-content')?.value.trim();
            if (!title || !content) {
                alert('Announcement title and content are required.');
                return;
            }

            const res = await nuiRequest('announcement:create', {
                title,
                content,
                priority: 'normal',
                category: 'general'
            });

            if (!res || !res.ok) {
                alert('Failed to publish announcement.');
                return;
            }
            this.loadUrl(this.currentUrl, true);
        });

        container.querySelector('#mb-law-submit')?.addEventListener('click', async () => {
            const title = container.querySelector('#mb-law-title')?.value.trim();
            const category = container.querySelector('#mb-law-category')?.value || 'General';
            const content = container.querySelector('#mb-law-content')?.value.trim();
            const fine = Number(container.querySelector('#mb-law-fine')?.value || 0);
            const jail = Number(container.querySelector('#mb-law-jail')?.value || 0);
            const publish = !!container.querySelector('#mb-law-publish')?.checked;

            if (!title || !content) {
                alert('Law title and content are required.');
                return;
            }

            const createRes = await nuiRequest('law:create', {
                title,
                category,
                content,
                fine,
                jail
            });

            if (!createRes || !createRes.ok) {
                alert('Failed to create law.');
                return;
            }

            if (publish && createRes.lawId) {
                await nuiRequest('law:publish', { lawId: createRes.lawId });
            }

            this.loadUrl(this.currentUrl, true);
        });

        container.querySelectorAll('.mayor-browser-tax-save').forEach((btn) => {
            btn.addEventListener('click', async () => {
                const row = btn.closest('.mayor-browser-tax-edit-row');
                if (!row) return;
                const taxType = row.dataset.tax;
                const rate = Number(row.querySelector('.mayor-browser-tax-rate')?.value || 0);
                const enabled = !!row.querySelector('.mayor-browser-tax-enabled')?.checked;

                const updateRes = await nuiRequest('tax:update', { taxType, rate });
                if (!updateRes || !updateRes.ok) {
                    alert(`Failed to update ${taxType} rate.`);
                    return;
                }

                const toggleRes = await nuiRequest('tax:toggle', { taxType, enabled });
                if (!toggleRes || !toggleRes.ok) {
                    alert(`Rate updated but failed to toggle ${taxType}.`);
                    return;
                }

                this.loadUrl(this.currentUrl, true);
            });
        });

        this.bindWebsiteEditor(container);
        switchPage(this.portalUiState.activePage || 'home');
    }

    back() {
        if (this.historyIndex > 0) {
            this.historyIndex -= 1;
            this.loadUrl(this.history[this.historyIndex], true);
        }
    }

    forward() {
        if (this.historyIndex < this.history.length - 1) {
            this.historyIndex += 1;
            this.loadUrl(this.history[this.historyIndex], true);
        }
    }

    refresh() {
        if (this.currentUrl) this.loadUrl(this.currentUrl, true);
    }

    home() {
        this.loadUrl(this.homeUrl);
    }

    toggleBookmarkCurrent() {
        if (!this.currentUrl) return;
        if (this.isBrowserHomeUrl(this.currentUrl)) return;
        const existingIndex = this.bookmarks.findIndex((bookmark) => this.normalizeUrl(bookmark.url) === this.currentUrl);
        if (existingIndex >= 0) {
            this.bookmarks.splice(existingIndex, 1);
        } else {
            this.bookmarks.push({
                name: this.currentUrl.replace(/^https?:\/\//i, ''),
                url: this.currentUrl
            });
        }
        this.saveBookmarks();
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
        const stored = localStorage.getItem('gov_desktop_items');
        if (stored) return JSON.parse(stored);

        return [
            { id: 'city-hall', app: 'city-hall', type: 'app', location: 'desktop', position: { x: 0, y: 0 } },
            { id: 'businesses', app: 'businesses', type: 'app', location: 'desktop', position: { x: 0, y: 1 } },
            { id: 'browser', app: 'browser', type: 'app', location: 'desktop', position: { x: 0, y: 2 } },
            { id: 'documents', app: 'documents', type: 'app', location: 'desktop', position: { x: 0, y: 3 } },
            { id: 'settings', app: 'settings', type: 'app', location: 'desktop', position: { x: 0, y: 4 } },
            { id: 'games', app: 'games', type: 'app', location: 'desktop', position: { x: 0, y: 5 } }
        ];
    }

    loadFolders() {
        const stored = localStorage.getItem('gov_folders');
        return stored ? JSON.parse(stored) : [];
    }

    saveItems() {
        localStorage.setItem('gov_desktop_items', JSON.stringify(this.items));
    }

    saveFolders() {
        localStorage.setItem('gov_folders', JSON.stringify(this.folders));
    }

    renderDesktop() {
        const container = document.querySelector('.desktop-icons');
        if (!container) return;

        const desktopItems = this.items.filter(item => item.location === 'desktop');
        
        // Remove icons that are no longer on desktop
        const existingIcons = container.querySelectorAll('.icon');
        existingIcons.forEach(icon => {
            const iconId = icon.dataset.id;
            const iconApp = icon.dataset.app;
            
            // Skip the default app icons (city-hall, businesses, documents, settings)
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

        // Refresh drag handlers after rendering
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
            // Clone existing app icon from desktop
            icon = document.querySelector(`.desktop-icons .icon[data-app="${item.app}"]`)?.cloneNode(true);
            if (icon) {
                icon.dataset.id = item.id;
                icon.addEventListener('dblclick', () => {
                    if (window.windowManagerInstance) {
                        window.windowManagerInstance.openWindow(item.app);
                    }
                });
            }
        }
        
        return icon;
    }

    createFolder(name) {
        const folder = {
            id: 'folder_' + Date.now(),
            name: name || 'New Folder',
            location: 'desktop',
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
                newFolderItem.onclick = () => {
                    const name = prompt('Enter folder name:', 'New Folder');
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
                renameItem.onclick = () => {
                    const folder = this.folders.find(f => f.id === targetId);
                    if (folder) {
                        const newName = prompt('Rename folder:', folder.name);
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
                deleteItem.onclick = () => {
                    if (confirm('Delete this folder and all its contents?')) {
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
        localStorage.removeItem('gov_desktop_items');
        localStorage.removeItem('gov_folders');
        localStorage.removeItem('gov_documents');
        this.items = this.loadItems();
        this.folders = this.loadFolders();
        this.renderDesktop();
        
        if (window.dragDropManager) {
            window.dragDropManager.refreshIcons();
        }
    }
}

// Initialize everything when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    const windowManager = new WindowManager();
    window.windowManagerInstance = windowManager;
    window.cityHall = new CityHallManager();
    window.businessesManager = new BusinessesManager();
    window.mayorBrowser = new MayorBrowserManager();
    let settingsManager = null;

    if (!GOV_EMBEDDED_MODE) {
        const lockscreenManager = new LockscreenManager();
        window.lockscreenManager = lockscreenManager;

        const themeManager = new ThemeManager();
        settingsManager = new SettingsManager(themeManager);
        const startMenu = new StartMenu(windowManager);
        const powerMenu = new PowerMenu();

        // Standalone-only desktop managers
        window.documentsManager = new DocumentsManager();
        window.gamesManager = new GamesManager();
        window.desktopManager = new DesktopManager();
        window.dragDropManager = new DragDropManager(window.desktopManager);
    }

    // Factory Reset Button
    const factoryResetBtn = document.getElementById('factory-reset-btn');
    if (factoryResetBtn) {
        factoryResetBtn.addEventListener('click', () => {
            if (confirm('Are you sure you want to reset everything to default? This will delete all documents, folders, and settings. This action cannot be undone.')) {
                if (confirm('This is your last warning. All your data will be permanently deleted. Continue?')) {
                    // Reset desktop
                    window.desktopManager.resetToDefault();
                    
                    // Clear all localStorage
                    const keysToKeep = ['lockscreen-password']; // Keep password
                    const allKeys = Object.keys(localStorage);
                    allKeys.forEach(key => {
                        if (!keysToKeep.includes(key)) {
                            localStorage.removeItem(key);
                        }
                    });
                    
                    // Reload page
                    alert('Factory reset complete. The page will now reload.');
                    window.location.reload();
                }
            }
        });
    }

    // Apply custom wallpaper on load
    const customWallpaper = localStorage.getItem('customWallpaper');
    if (settingsManager) {
        if (customWallpaper) {
            settingsManager.applyCustomWallpaper(customWallpaper);
        } else {
            const wallpaperGradient = localStorage.getItem('wallpaperGradient');
            if (wallpaperGradient) {
                settingsManager.applyGradientWallpaper(wallpaperGradient);
            }
        }
    }

    if (GOV_EMBEDDED_MODE) {
        document.body.classList.add('show-ui', 'embedded-mode');

        requestAnimationFrame(() => {
            if (window.windowManagerInstance) {
                window.windowManagerInstance.openWindow(GOV_EMBEDDED_APP);
            }
        });
    }

    console.log('Government UI System Loaded - Full Desktop OS with Documents & File Management');
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

// NUI Message Listener
window.addEventListener('message', (event) => {
    const data = event.data;
    
    if (data.action === 'openUI') {
        document.body.classList.add('show-ui');
    } else if (data.action === 'closeUI') {
        document.body.classList.remove('show-ui');
    } else if (data.action === 'openEmbeddedApp' && data.app && window.windowManagerInstance) {
        window.windowManagerInstance.openWindow(data.app);
    } else if (data.action === 'refreshInfrastructureViews') {
        const hall = window.cityHall;
        if (!hall || typeof hall.refreshAllData !== 'function') return;
        hall.refreshAllData().then(() => {
            if (hall.currentPage === 'utilities' || hall.currentPage === 'budgets') {
                hall.loadPage(hall.currentPage);
            }
        }).catch(() => {});
    }
});
