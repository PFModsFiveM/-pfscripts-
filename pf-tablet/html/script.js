(() => {
    const RESOURCE_NAME = window.RESOURCE_NAME || (typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'pf-tablet');

    // Expose a tiny API for external app modules
    window.PFTablet = window.PFTablet || {};
    window.PFTablet.resourceName = RESOURCE_NAME;
    window.PFTablet.post = function (callbackName, payload) {
        return $.post(`https://${RESOURCE_NAME}/${callbackName}`, JSON.stringify(payload || {}));
    };

    const PFState = (window.PFState = window.PFState || {
        playerName: 'Player',
        apps: [],
    });

    const PFExternalFrames = (window.PFExternalFrames = window.PFExternalFrames || {});
    const PFExternalQueue = (window.PFExternalQueue = window.PFExternalQueue || {});

    function registerExternalFrame(resource, app, frameEl) {
        if (!resource || !app || !frameEl) return;
        const resKey = String(resource).toLowerCase();
        const appKey = String(app).toLowerCase();
        const key = `${resKey}:${appKey}`;
        PFExternalFrames[key] = frameEl;
        const queued = PFExternalQueue[key];
        if (queued && queued.length && frameEl.contentWindow) {
            queued.forEach(payload => frameEl.contentWindow.postMessage(payload, '*'));
            PFExternalQueue[key] = [];
        }
    }

    const __loadedExternal = (window.__PF_LOADED_EXTERNAL__ = window.__PF_LOADED_EXTERNAL__ || {});

    function loadExternalScriptOnce(url, key) {
        const k = key || url;
        if (!url || __loadedExternal[k]) return;
        __loadedExternal[k] = true;
        const s = document.createElement('script');
        s.src = url;
        s.async = false;
        s.onerror = function () {
            // keep flag true to avoid retry loops
        };
        document.head.appendChild(s);
    }

    function loadExternalStyleOnce(url, key) {
        const k = key || url;
        if (!url || __loadedExternal[k]) return;
        __loadedExternal[k] = true;
        const l = document.createElement('link');
        l.rel = 'stylesheet';
        l.href = url;
        l.onerror = function () {
            // keep flag true to avoid retry loops
        };
        document.head.appendChild(l);
    }

    window.openWindows = window.openWindows || {};

    function pad2(n) {
        return String(n).padStart(2, '0');
    }

    function escapeHtml(s) {
        return String(s ?? '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#039;');
    }

    function setGameTime(hour, minute) {
        const hh = pad2(Number(hour) || 0);
        const mm = pad2(Number(minute) || 0);
        const gameTimeText = `${hh}:${mm}`;

        const $statusTime = $('#time');
        const $cornerTime = $('#game-time');
        if ($statusTime.length) $statusTime.text(gameTimeText);
        if ($cornerTime.length) $cornerTime.text(gameTimeText);
    }

    function setRealtimeDate() {
        const now = new Date();
        const value = `${pad2(now.getDate())}/${pad2(now.getMonth() + 1)}/${now.getFullYear()}`;
        const $date = $('#game-date');
        if ($date.length) $date.text(value);
    }

    function getThemeDefaultBackground(theme) {
        if (theme === 'light') {
            return 'linear-gradient(135deg, #cfe8ff 0%, #e9f4ff 55%, #d6efff 100%)';
        }
        return 'linear-gradient(135deg, #1e3a8a 0%, #3b82f6 50%, #06b6d4 100%)';
    }

    function applyWallpaperUrl(url) {
        const el = document.querySelector('.tablet-screen');
        if (!el) return;
        el.style.backgroundImage = `url('${url}')`;
        el.style.backgroundSize = 'cover';
        el.style.backgroundPosition = 'center';
    }

    function applySavedBackground() {
        const el = document.querySelector('.tablet-screen');
        if (!el) return;

        const bg = String(localStorage.getItem('pf-tablet-background') || '').trim();
        const theme = String(localStorage.getItem('pf-tablet-theme') || 'dark').toLowerCase();

        if (!bg) {
            el.style.backgroundImage = '';
            el.style.background = getThemeDefaultBackground(theme);
            return;
        }

        applyWallpaperUrl(bg);
    }

    function applyTabletTheme(theme) {
        const value = theme === 'light' ? 'light' : 'dark';
        localStorage.setItem('pf-tablet-theme', value);
        document.body.setAttribute('data-tablet-theme', value);
        applySavedBackground();
    }

    function applySavedTheme() {
        const value = String(localStorage.getItem('pf-tablet-theme') || 'dark').toLowerCase();
        document.body.setAttribute('data-tablet-theme', value === 'light' ? 'light' : 'dark');
    }

    function getAppName(app) {
        // platform apps (pf-devices) carry their own id
        if (app && app.platform && app.appId) return String(app.appId).toLowerCase();
        return String(app && app.name ? app.name : '').toLowerCase();
    }

    function getAppLabel(app) {
        if (app && app.platform) return app.name || app.appId;
        const name = getAppName(app);
        if (name === 'settings') return 'Settings';
        return app && app.name ? app.name : 'App';
    }

    function ensureSystemApps(apps) {
        const list = Array.isArray(apps) ? apps.map(a => ({ ...a })) : [];
        const hasSettings = list.some(a => getAppName(a) === 'settings');
        if (!hasSettings) {
            list.push({ name: 'Settings', icon: '⚙️', enabled: true, system: true });
        }
        return list;
    }

    function showTablet() {
        // Show lockscreen first
        showLockscreen();
        $('#tablet-container').removeClass('hidden');
        applySavedBackground();
    }

    function hideTablet() {
        $('#tablet-container').addClass('hidden');
        $('#lockscreen').removeClass('unlocking').addClass('hidden');
    }

    function showLockscreen() {
        const lockscreen = $('#lockscreen');
        lockscreen.removeClass('hidden unlocking');
        updateLockscreenTime();
        renderNotifications();
        
        // Update time every second while lockscreen is visible
        if (window.lockscreenInterval) {
            clearInterval(window.lockscreenInterval);
        }
        window.lockscreenInterval = setInterval(() => {
            if (!lockscreen.hasClass('hidden')) {
                updateLockscreenTime();
            } else {
                clearInterval(window.lockscreenInterval);
            }
        }, 1000);
    }

    function updateLockscreenTime() {
        // Use in-game time from the status bar
        const ingameTime = $('#time').text() || '00:00';
        $('#lockscreen-time').text(ingameTime);
        
        // Use real-life date
        const now = new Date();
        const days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
        const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
        const dayName = days[now.getDay()];
        const monthName = months[now.getMonth()];
        const day = now.getDate();
        const year = now.getFullYear();
        
        // Get ordinal suffix (1st, 2nd, 3rd, 4th, etc.)
        const getOrdinal = (n) => {
            const s = ['th', 'st', 'nd', 'rd'];
            const v = n % 100;
            return n + (s[(v - 20) % 10] || s[v] || s[0]);
        };
        
        $('#lockscreen-date').text(`${dayName}, ${monthName} ${getOrdinal(day)}`);
    }

    function renderNotifications() {
        const $container = $('#lockscreen-notifications');
        // Notifications disabled for now - will be implemented later
        $container.empty();
    }

    function unlockTablet() {
        const lockscreen = $('#lockscreen');
        lockscreen.addClass('unlocking');
        
        // Hide lockscreen after animation completes
        setTimeout(() => {
            lockscreen.addClass('hidden');
            if (window.lockscreenInterval) {
                clearInterval(window.lockscreenInterval);
            }
        }, 500); // Match animation duration
    }

    function closeAllWindows() {
        Object.keys(window.openWindows || {}).forEach(k => {
            closeWindow(k);
        });
        window.openWindows = {};
        $('#windows-container').empty();
        // Re-render dock to drop any minimized entries
        renderDock(PFState.apps || []);
    }

    // The tablet's own apps (from client/main.lua) plus the platform apps from pf-devices.
    function mergedApps(ownApps) {
        const own = Array.isArray(ownApps) ? ownApps : (PFState.ownApps || []);
        const platform = (window.PFTabletPlatform && window.PFTabletPlatform.apps()) || [];
        const ids = new Set(platform.map(a => a.appId));
        return own.filter(a => !ids.has(getAppName(a))).concat(platform);
    }
    window.PFTabletRenderApps = function () { renderApps(mergedApps()); };

    function renderApps(apps) {
        const normalizedApps = ensureSystemApps(apps);
        PFState.apps = normalizedApps;

        const $grid = $('#app-grid');
        $grid.empty();

        normalizedApps.forEach(app => {
            const name = getAppName(app);
            const label = getAppLabel(app);
            const icon = app.icon || (name === 'settings' ? '⚙️' : '📦');
            if (!name || app.enabled === false) return;

            const appMeta = {
                ...app,
                name: label,
                appId: name,
            };

            const $item = $(
                `<div class="app-item" data-app="${escapeHtml(name)}">
                    <div class="app-icon">${escapeHtml(icon)}</div>
                    <div class="app-label">${escapeHtml(label)}</div>
                </div>`
            );
            $item.on('click', () => {
                if (appMeta.platform && window.PFApps) window.PFApps.open(name);
                else openAppWindow(name, label, icon, appMeta);
            });
            $grid.append($item);
        });

        renderDock(normalizedApps);
    }

    function renderDock(apps) {
        const $dock = $('.dock');
        const html = [];
        const added = {};
        const appList = ensureSystemApps(apps);

        const pinnedOrder = ['settings'];
        pinnedOrder.forEach(appId => {
            const app = appList.find(a => getAppName(a) === appId);
            if (!app || app.enabled === false) return;

            const label = getAppLabel(app);
            const icon = app.icon || (appId === 'settings' ? '⚙️' : '📊');
            const state = window.openWindows[appId];

            html.push(
                `<div class="dock-item" data-app="${escapeHtml(appId)}" data-pinned="true" ${state && state.minimized ? 'data-minimized="true"' : ''}>
                    <span class="dock-icon">${escapeHtml(icon)}</span>
                    <span class="dock-label">${escapeHtml(label)}</span>
                </div>`
            );
            added[appId] = true;
        });

        Object.keys(window.openWindows || {}).forEach(appName => {
            if (added[appName]) return;
            const w = window.openWindows[appName];
            if (!w) return;

            const appIcon = w.icon || '📦';
            const appLabel = w.label || appName;

            html.push(
                `<div class="dock-item" data-app="${escapeHtml(appName)}" ${w.minimized ? 'data-minimized="true"' : ''}>
                    <span class="dock-icon">${escapeHtml(appIcon)}</span>
                    <span class="dock-label">${escapeHtml(appLabel)}</span>
                </div>`
            );
        });

        $dock.html(html.join(''));
    }

    function bringToFront($win) {
        let maxZ = 101;
        $('.app-window').each(function () {
            const z = parseInt($(this).css('z-index') || '101', 10);
            if (z > maxZ) maxZ = z;
        });
        $win.css('z-index', maxZ + 1);
    }

    function postNui(resourceName, callbackName, payload) {
        const res = resourceName || RESOURCE_NAME;
        return $.post(`https://${res}/${callbackName}`, JSON.stringify(payload || {}));
    }

    function renderExternalApp($container, app) {
        const resource = app && app.external ? app.external.resource : null;
        const appId = app && app.external ? app.external.app : null;
        const title = (app && app.name) ? app.name : (appId || 'External App');

        if (resource === 'pf-mechanicjob' && appId === 'mechanic') {
            $container.html(
                `<iframe class="external-iframe" data-external="pf-mechanicjob"` +
                ` style="width:100%;height:100%;border:0;"` +
                ` src="https://cfx-nui-pf-mechanicjob/tablet/embedded.html?embed=1"></iframe>`
            );
            const frame = $container.find('iframe')[0];
            if (frame) registerExternalFrame('pf-mechanicjob', 'mechanic', frame);
            return;
        }

        // If the external module is loaded, let it mount the real UI.
        if (resource === 'pf-jobs' && window.PFJobsTablet) {
            if (appId === 'gruppe6' && typeof window.PFJobsTablet.renderGruppe6Window === 'function') {
                // Module renders directly into the window-content
                $container.empty();
                window.PFJobsTablet.renderGruppe6Window('gruppe6');
                return;
            }
            if (appId === 'garbage' && typeof window.PFJobsTablet.renderGarbageWindow === 'function') {
                $container.empty();
                window.PFJobsTablet.renderGarbageWindow('garbage');
                return;
            }
            if (appId === 'taxi' && typeof window.PFJobsTablet.renderTaxiWindow === 'function') {
                $container.empty();
                window.PFJobsTablet.renderTaxiWindow('taxi');
                return;
            }
            if (appId === 'bus' && typeof window.PFJobsTablet.renderBusWindow === 'function') {
                $container.empty();
                window.PFJobsTablet.renderBusWindow('bus');
                return;
            }
        }

        // If the external module is loaded, let it mount the mechanic UI.
        if (resource === 'pf-mechanicjob' && window.MechanicTablet) {
            if (appId === 'work-orders' && typeof window.MechanicTablet.renderWorkOrders === 'function') {
                $container.empty();
                window.MechanicTablet.renderWorkOrders($container);
                return;
            }
            if (appId === 'cash-register' && typeof window.MechanicTablet.renderCashRegister === 'function') {
                $container.empty();
                window.MechanicTablet.renderCashRegister($container);
                return;
            }
            if (appId === 'management' && typeof window.MechanicTablet.renderManagement === 'function') {
                $container.empty();
                window.MechanicTablet.renderManagement($container);
                return;
            }
        }

        if (resource === 'pf-jobs' && appId === 'gruppe6') {
            $container.html(`
                <div style="display:flex; flex-direction:column; gap:12px;">
                    <div style="opacity:.85; font-weight:600;">${escapeHtml(title)}</div>
                    <div style="opacity:.7;">Controls for the pf-jobs Gruppe6 job.</div>
                    <div style="display:flex; gap:10px; flex-wrap:wrap;">
                        <button class="btn-refresh" data-ext="g6-init">Init</button>
                        <button class="btn-refresh" data-ext="g6-start">Start Search</button>
                        <button class="btn-refresh" data-ext="g6-stop">Stop Search</button>
                    </div>
                </div>
            `);

            $container.off('click.pfext').on('click.pfext', '[data-ext]', function (e) {
                e.preventDefault();
                const action = String($(this).attr('data-ext') || '');
                if (action === 'g6-init') postNui('pf-jobs', 'gruppe6:getInit', {}).fail(() => {});
                if (action === 'g6-start') postNui('pf-jobs', 'gruppe6:startSearch', {}).fail(() => {});
                if (action === 'g6-stop') postNui('pf-jobs', 'gruppe6:stopSearch', {}).fail(() => {});
            });
            return;
        }

        if (resource === 'pf-jobs' && appId === 'garbage') {
            $container.html(`
                <div style="display:flex; flex-direction:column; gap:12px;">
                    <div style="opacity:.85; font-weight:600;">${escapeHtml(title)}</div>
                    <div style="opacity:.7;">Controls for the pf-jobs Garbage job.</div>
                    <div style="display:flex; gap:10px; flex-wrap:wrap;">
                        <button class="btn-refresh" data-ext="garb-init">Init</button>
                        <button class="btn-refresh" data-ext="garb-start">Start Job</button>
                    </div>
                </div>
            `);

            $container.off('click.pfext').on('click.pfext', '[data-ext]', function (e) {
                e.preventDefault();
                const action = String($(this).attr('data-ext') || '');
                if (action === 'garb-init') postNui('pf-jobs', 'garbage:getInit', {}).fail(() => {});
                if (action === 'garb-start') postNui('pf-jobs', 'garbage:startJob', {}).fail(() => {});
            });
            return;
        }

        // Police MDT embedded app - use tablet module
        if (resource === 'pf-policemdt' && appId === 'policemdt') {
            console.log('[pf-tablet] Rendering pf-policemdt app...');
            console.log('[pf-tablet] window.PFMDTTablet exists:', !!window.PFMDTTablet);
            console.log('[pf-tablet] typeof renderPoliceMDT:', typeof (window.PFMDTTablet && window.PFMDTTablet.renderPoliceMDT));
            
            // Call the tablet module function to render the MDT UI
            if (window.PFMDTTablet && typeof window.PFMDTTablet.renderPoliceMDT === 'function') {
                console.log('[pf-tablet] Calling renderPoliceMDT...');
                // Module renders directly into its window container
                $container.empty();
                window.PFMDTTablet.renderPoliceMDT('policemdt');
                console.log('[pf-tablet] renderPoliceMDT completed');
            } else {
                console.log('[pf-tablet] Module not ready, showing loading message');
                $container.html('<div style="opacity:.7">Police MDT module loading... Try again in a moment.</div>');
            }
            return;
        }

        $container.html('<div style="opacity:.7">This app is not available.</div>');
    }

    function openAppWindow(appName, appLabel, appIcon, appMeta) {
        const name = String(appName || '').toLowerCase();
        if (!name) return;

        const $existing = $(`.app-window[data-app="${name}"]`);
        if ($existing.length) {
            restoreWindow(name);
            bringToFront($existing);
            return;
        }

        const $win = $(
            `<div class="app-window" data-app="${escapeHtml(name)}">
                <div class="window-content"></div>
            </div>`
        );

        const $content = $win.find('.window-content');

        $win.on('mousedown', () => bringToFront($win));
        $('#windows-container').append($win);
        bringToFront($win);

        window.openWindows[name] = { 
            minimized: false, 
            label: appLabel || name, 
            icon: appIcon,
            appMeta: appMeta // Store metadata for restoration
        };
        
        renderDock(PFState.apps || []);
        updateUIVisibility();

        if (appMeta && appMeta.platform) {
            // pf-devices mounts the shared module into this window (platform apps come first, so an
            // app id like 'taxi' never falls into a legacy branch)
            const mount = window.PFTabletPlatform && window.PFTabletPlatform.takeMount(name);
            if (mount) mount($content[0]);
            else if (window.PFApps) setTimeout(() => window.PFApps.open(name), 0);
        } else if (name === 'settings') {
            renderSettingsWindow($content);
        } else if (appMeta && appMeta.external) {
            // Validate that the client sees the external resource as available
            postNui(RESOURCE_NAME, 'external/open', { resource: appMeta.external.resource, app: appMeta.external.app })
                .always(() => {
                    renderExternalApp($content, appMeta);
                });
        } else {
            $content.html('<div style="opacity:.7">This app is not available.</div>');
        }
    }

    function closeWindow(appName) {
        const name = String(appName || '').toLowerCase();
        if (window.PFApps && window.PFApps.isOpen(name)) window.PFApps.windowClosed(name);
        $(`.app-window[data-app="${name}"]`).remove();
        delete window.openWindows[name];
        renderDock(PFState.apps || []);
        updateUIVisibility();
    }

    function minimizeWindow(appName) {
        const name = String(appName || '').toLowerCase();
        const $w = $(`.app-window[data-app="${name}"]`);
        if (!$w.length) return;
        $w.addClass('minimized');
        if (window.openWindows[name]) window.openWindows[name].minimized = true;
        renderDock(PFState.apps || []);
        updateUIVisibility();
    }

    function restoreWindow(appName) {
        const name = String(appName || '').toLowerCase();
        const $w = $(`.app-window[data-app="${name}"]`);
        if (!$w.length) {
            // Window doesn't exist, try to recreate it if we have metadata
            const winData = window.openWindows[name];
            if (winData && winData.appMeta) {
                openAppWindow(name, winData.label, winData.icon, winData.appMeta);
            }
            return;
        }
        $w.removeClass('minimized');
        if (window.openWindows[name]) window.openWindows[name].minimized = false;
        bringToFront($w);
        renderDock(PFState.apps || []);
        updateUIVisibility();
    }

    function updateUIVisibility() {
        // Check if there are any visible (non-minimized) windows
        const hasVisibleWindows = $('.app-window:not(.minimized)').length > 0;
        
        if (hasVisibleWindows) {
            $('.app-grid').addClass('hidden');
            $('.dock').addClass('hidden');
        } else {
            $('.app-grid').removeClass('hidden');
            $('.dock').removeClass('hidden');
        }
    }

    function renderSettingsWindow($container) {
        const currentTheme = String(localStorage.getItem('pf-tablet-theme') || 'dark').toLowerCase();
        const savedWallpaper = String(localStorage.getItem('pf-tablet-background') || '');

        $container.html(`
            <div class="settings-container">
                <div class="settings-sidebar">
                    <div class="settings-profile">
                        <div class="avatar">⚙️</div>
                        <div>
                            <div class="name">Settings</div>
                            <div class="desc">Theme and wallpaper customization</div>
                        </div>
                    </div>
                    <div class="settings-section-title">APPEARANCE</div>
                    <div class="settings-item" data-pane="appearance">
                        <div class="settings-icon">🎨</div>
                        <div>
                            <div class="label">Display</div>
                        </div>
                    </div>
                </div>
                <div class="settings-main" id="settings-pane">
                    <div class="settings-row">
                        <div>
                            <div class="label">Theme Mode</div>
                            <div class="sublabel">Switch between light and dark mode</div>
                        </div>
                        <select id="tablet-theme-select" class="setting-select">
                            <option value="dark" ${currentTheme === 'dark' ? 'selected' : ''}>Dark</option>
                            <option value="light" ${currentTheme === 'light' ? 'selected' : ''}>Light</option>
                        </select>
                    </div>
                    <div class="settings-row" style="display:block;">
                        <div class="label" style="margin-bottom:6px;">Wallpaper URL</div>
                        <div class="sublabel" style="margin-bottom:10px;">Paste image URL (jpg/png/webp) to set tablet wallpaper</div>
                        <div class="input-row">
                            <input id="tablet-wallpaper-url" type="text" placeholder="https://example.com/wallpaper.jpg" value="${escapeHtml(savedWallpaper)}" />
                            <button id="tablet-wallpaper-preview" type="button">Preview</button>
                            <button id="tablet-wallpaper-apply" type="button">Apply</button>
                            <button id="tablet-wallpaper-clear" type="button">Clear</button>
                        </div>
                    </div>
                </div>
            </div>
        `);
    }

    // The window functions the platform shell (pfapps_shell.js) uses
    window.openAppWindow = openAppWindow;
    window.closeWindow = closeWindow;
    window.minimizeWindow = minimizeWindow;
    window.restoreWindow = restoreWindow;

    $(document).on('change', '#tablet-theme-select', function () {
        const selected = String($(this).val() || 'dark').toLowerCase();
        applyTabletTheme(selected);
    });

    $(document).on('click', '#tablet-wallpaper-preview', function () {
        const url = String($('#tablet-wallpaper-url').val() || '').trim();
        if (!url) {
            applySavedBackground();
            return;
        }
        applyWallpaperUrl(url);
    });

    $(document).on('click', '#tablet-wallpaper-apply', function () {
        const url = String($('#tablet-wallpaper-url').val() || '').trim();
        if (!url) {
            localStorage.removeItem('pf-tablet-background');
            applySavedBackground();
            return;
        }
        localStorage.setItem('pf-tablet-background', url);
        applySavedBackground();
    });

    $(document).on('click', '#tablet-wallpaper-clear', function () {
        localStorage.removeItem('pf-tablet-background');
        $('#tablet-wallpaper-url').val('');
        applySavedBackground();
    });

    function openSettingsApp() {
        const settingsApp = ensureSystemApps(PFState.apps || []).find(a => getAppName(a) === 'settings');
        if (!settingsApp) return;
        const appMeta = { ...settingsApp, appId: 'settings', name: 'Settings' };

        if ($('.app-window[data-app="settings"]').length) {
            restoreWindow('settings');
        } else {
            openAppWindow('settings', 'Settings', settingsApp.icon || '⚙️', appMeta);
        }
    }

    $(document).on('click', '.status-right .icon:nth-child(2)', function(e) {
        e.stopPropagation();
        openSettingsApp();
    });

    window.addEventListener('message', (event) => {
        const d = event.data || {};

        if (d.action === 'openTablet') {
            showTablet();
            if (Array.isArray(d.apps)) {
                PFState.ownApps = d.apps;
                renderApps(mergedApps(d.apps));
            }
            if (typeof d.playerName === 'string' && d.playerName.trim().length) {
                PFState.playerName = d.playerName.trim();
            }
            return;
        }

        if (d.action === 'updateApps') {
            if (Array.isArray(d.apps)) {
                PFState.ownApps = d.apps;
                renderApps(mergedApps(d.apps));
            }
            return;
        }

        if (d.action === 'openApp') {
            const appName = String(d.app || '').toLowerCase();
            if (!appName) return;
            const app = (PFState.apps || []).find(a => {
                const name = getAppName(a);
                const id = String(a.appId || a.app || '').toLowerCase();
                const extId = String(a.external && a.external.app ? a.external.app : '').toLowerCase();
                return name === appName || id === appName || extId === appName;
            });
            if (app) {
                const id = getAppName(app);
                openAppWindow(id, getAppLabel(app), app.icon || '📦', { ...app, appId: id, name: getAppLabel(app) });
            }
            return;
        }

        if (d.action === 'externalAppMessage') {
            const res = String(d.resource || '').toLowerCase();
            const app = String(d.app || '').toLowerCase();
            const payload = d.payload || {};
            const key = `${res}:${app}`;
            const frame = window.PFExternalFrames && window.PFExternalFrames[key];
            if (frame && frame.contentWindow) {
                frame.contentWindow.postMessage(payload, '*');
            } else if (window.PFExternalQueue) {
                window.PFExternalQueue[key] = window.PFExternalQueue[key] || [];
                window.PFExternalQueue[key].push(payload);
            }
            return;
        }

        // Dynamically load external UI modules (e.g. pf-jobs) when the client tells us to.
        if (d.action === 'loadExternalModules') {
            const scripts = Array.isArray(d.scripts) ? d.scripts : [];
            scripts.forEach(s => {
                if (!s || !s.url) return;
                loadExternalScriptOnce(String(s.url), String(s.key || s.url));
            });

            const styles = Array.isArray(d.styles) ? d.styles : [];
            styles.forEach(st => {
                if (!st) return;
                if (typeof st === 'string') {
                    loadExternalStyleOnce(String(st), `css:${st}`);
                    return;
                }
                if (!st.url) return;
                loadExternalStyleOnce(String(st.url), String(st.key || `css:${st.url}`));
            });
            return;
        }

        if (d.action === 'closeTablet') {
            hideTablet();
            return;
        }

        if (d.action === 'setPlayerName') {
            if (typeof d.value === 'string' && d.value.trim().length) {
                PFState.playerName = d.value.trim();
            }
            return;
        }

        if (d.action === 'updateGameTime') {
            setGameTime(d.hour, d.minute, d.day, d.month, d.year);
            return;
        }

    });

    // Event delegation for dock items
    $(document).on('click', '.dock-item', function(e) {
        e.stopPropagation();
        const appName = String($(this).attr('data-app') || '').toLowerCase();
        if (!appName) return;

        const appMeta = ensureSystemApps(PFState.apps || []).find(a => getAppName(a) === appName);

        if (window.openWindows[appName]) {
            const w = window.openWindows[appName];
            if (w.minimized) {
                restoreWindow(appName);
            } else {
                const $win = $(`.app-window[data-app="${appName}"]`);
                if ($win.length) {
                    bringToFront($win);
                }
            }
            return;
        }

        if (appMeta) {
            if (appMeta.platform && window.PFApps) { window.PFApps.open(appName); return; }
            const label = getAppLabel(appMeta);
            openAppWindow(appName, label, appMeta.icon || '📦', { ...appMeta, appId: appName, name: label });
        }
    });

    // App Switcher functionality
    function showAppSwitcher() {
        const $switcher = $('#app-switcher');
        const $apps = $('#switcher-apps');
        $apps.empty();

        Object.keys(window.openWindows || {}).forEach(appName => {
            const w = window.openWindows[appName];
            if (!w) return;

            // Get the window's current content for preview
            const $win = $(`.app-window[data-app="${appName}"]`);
            let contentPreview = '';
            
            if ($win.length) {
                const $content = $win.find('.window-content');
                if ($content.length) {
                    // Clone the content for preview
                    contentPreview = $content.html();
                }
            }

            const previewContent = contentPreview ? 
                `<div class="switcher-content-preview">${contentPreview}</div>` : 
                `<div class="switcher-app-icon">${escapeHtml(w.icon || '📦')}</div>
                 <div class="switcher-app-name">${escapeHtml(w.label || appName)}</div>`;

            const $card = $(`
                <div class="switcher-app-card" data-app="${escapeHtml(appName)}">
                    <div class="switcher-close-btn" data-close="${escapeHtml(appName)}">×</div>
                    <div class="switcher-app-preview">
                        ${previewContent}
                    </div>
                </div>
            `);

            $apps.append($card);
        });

        $switcher.removeClass('hidden');
    }

    function hideAppSwitcher() {
        $('#app-switcher').addClass('hidden');
    }

    $(document).on('click', '#switcher-button', function(e) {
        e.stopPropagation();
        // Close all windows and return to home screen
        const openApps = Object.keys(window.openWindows || {});
        openApps.forEach(appName => {
            closeWindow(appName);
        });
    });

    $(document).on('click', '.switcher-app-card', function(e) {
        if ($(e.target).hasClass('switcher-close-btn') || $(e.target).closest('.switcher-close-btn').length) {
            return; // Let the close button handler deal with it
        }
        const appName = $(this).attr('data-app');
        if (appName) {
            restoreWindow(appName);
            hideAppSwitcher();
        }
    });

    $(document).on('click', '.switcher-close-btn', function(e) {
        e.stopPropagation();
        const appName = $(this).attr('data-close');
        if (appName) {
            closeWindow(appName);
            // Refresh switcher
            if (Object.keys(window.openWindows || {}).length === 0) {
                hideAppSwitcher();
            } else {
                showAppSwitcher();
            }
        }
    });

    // Close switcher when clicking outside
    $(document).on('click', '#app-switcher', function(e) {
        if (e.target.id === 'app-switcher') {
            hideAppSwitcher();
        }
    });

    // Apply theme/background and start realtime date updates
    window.addEventListener('load', function () {
        applySavedTheme();
        applySavedBackground();
        setRealtimeDate();
    });

    setRealtimeDate();
    setInterval(setRealtimeDate, 1000);

    // Lockscreen unlock handlers
    $(document).on('click', '#unlock-button, .lockscreen-unlock', function(e) {
        e.stopPropagation();
        unlockTablet();
    });


    // Touch/swipe support for lockscreen
    let touchStartY = 0;
    let touchEndY = 0;
    
    $(document).on('touchstart', '#lockscreen', function(e) {
        touchStartY = e.touches[0].clientY;
    });
    
    $(document).on('touchmove', '#lockscreen', function(e) {
        touchEndY = e.touches[0].clientY;
        const deltaY = touchStartY - touchEndY;
        
        // Provide visual feedback during swipe
        if (deltaY > 0 && deltaY < 200) {
            $(this).css('transform', `translateY(-${deltaY * 0.5}px)`);
            $(this).css('opacity', 1 - (deltaY / 400));
        }
    });
    
    $(document).on('touchend', '#lockscreen', function(e) {
        const deltaY = touchStartY - touchEndY;
        
        if (deltaY > 100) { // Swipe up threshold
            unlockTablet();
        } else {
            // Reset position if swipe wasn't enough
            $(this).css('transform', 'translateY(0)');
            $(this).css('opacity', '1');
        }
    });

    // Notify that the window functions exist
    window.dispatchEvent(new Event('pfjs-ready'));

    // Close tablet button handler
    $(document).on('click', '#close-tablet-btn', function(e) {
        e.stopPropagation();
        $.post(`https://${RESOURCE_NAME}/closeTablet`, JSON.stringify({}), function() {
            // Tablet closed
        });
    });

    // Hover effect for close button
    $(document).on('mouseenter', '#close-tablet-btn', function() {
        $(this).css('opacity', '1');
    }).on('mouseleave', '#close-tablet-btn', function() {
        $(this).css('opacity', '0.8');
    });
})();


