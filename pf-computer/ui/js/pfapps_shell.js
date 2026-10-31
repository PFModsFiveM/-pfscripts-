// pf-computer as a pf-devices shell: platform apps (pf-jobs, pf-news, pf-government, pf-services...)
// get desktop icons, start-menu tiles and normal computer windows; their modules are the same ones
// the tablet runs. Websites published through pf-devices render inside the computer's own browser.
(function () {
    const PREFIX = 'pfapp-';
    const icons = {};          // window id -> emoji
    let currentApps = [];
    let siteCache = { at: 0, list: [] };

    function wm() { return window.windowManagerInstance; }
    function winId(id) { return PREFIX + id; }

    function textOf(s) {
        const d = document.createElement('div');
        d.textContent = s == null ? '' : String(s);
        return d.innerHTML;
    }

    window.PFComputerPlatform = {
        iconFor(appName) {
            const key = String(appName || '').toLowerCase();
            return icons[key] || null;
        },
        async listSites() {
            if (!window.PFApps) return [];
            if (Date.now() - siteCache.at < 10000) return siteCache.list;
            siteCache = { at: Date.now(), list: await window.PFApps.sites() };
            return siteCache.list;
        },
        async findSite(host) {
            const h = String(host || '').toLowerCase();
            if (!h) return null;
            const list = await this.listSites();
            return list.find((s) => s.host === h) || null;
        },
    };

    function ensureWindow(app) {
        const key = winId(app.id);
        icons[key] = app.icon || '📦';
        let el = document.querySelector(`.window[data-app="${key}"]`);
        if (el) return el;
        const container = document.querySelector('.windows-container');
        if (!container || !wm()) return null;
        el = document.createElement('div');
        el.className = 'window pfapp-window';
        el.id = `${key}-window`;
        el.dataset.app = key;
        el.style.display = 'none';
        el.innerHTML = `
            <div class="window-header">
                <div class="window-title">
                    <div class="window-icon"></div>
                    <span>${textOf(app.name)}</span>
                </div>
                <div class="window-controls">
                    <button class="window-btn minimize">−</button>
                    <button class="window-btn maximize">□</button>
                    <button class="window-btn close">×</button>
                </div>
            </div>
            <div class="window-content pfapp-content" style="padding:0;overflow:auto;"></div>`;
        el.querySelector('.window-icon').innerHTML = renderAppIcon(key, 'window', app.name);
        container.appendChild(el);
        wm().initWindow(el);
        // the window manager only hides a closed window; the app must also be unmounted
        el.querySelector('.close').addEventListener('click', () => {
            if (window.PFApps) window.PFApps.windowClosed(app.id);
            const content = el.querySelector('.pfapp-content');
            if (content) content.innerHTML = '';
        });
        if (app.window && app.window.width) el.style.width = `${Math.max(480, app.window.width)}px`;
        if (app.window && app.window.height) el.style.height = `${Math.max(360, app.window.height)}px`;
        return el;
    }

    function removeStale(apps) {
        const keep = new Set(apps.map((a) => winId(a.id)));
        document.querySelectorAll('.desktop-icons .icon.pfapp-icon').forEach((el) => {
            if (!keep.has(el.dataset.app)) el.remove();
        });
        document.querySelectorAll('.start-menu-apps .start-app-tile.pfapp-tile').forEach((el) => {
            if (!keep.has(el.dataset.app)) el.remove();
        });
        document.querySelectorAll('.window.pfapp-window').forEach((el) => {
            if (!keep.has(el.dataset.app)) {
                if (wm()) {
                    wm().closeWindow(el.dataset.app, { suppressSessionSave: true });
                    wm().windows.delete(el.dataset.app);
                }
                el.remove();
            }
        });
    }

    function renderIcons(apps) {
        currentApps = apps;
        removeStale(apps);
        const desktop = document.querySelector('.desktop-icons');
        const startApps = document.querySelector('.start-menu-apps');
        apps.forEach((app) => {
            const key = winId(app.id);
            icons[key] = app.icon || '📦';
            if (desktop && !desktop.querySelector(`.icon.pfapp-icon[data-app="${key}"]`)) {
                const icon = document.createElement('div');
                icon.className = 'icon pfapp-icon external-program';
                icon.dataset.app = key;
                icon.title = app.description || app.name;
                icon.innerHTML = `<div class="icon-image">${renderAppIcon(key, 'desktop', app.name)}</div><div class="icon-label">${textOf(app.name)}</div>`;
                icon.addEventListener('dblclick', (e) => {
                    e.preventDefault();
                    e.stopPropagation();
                    window.PFApps.open(app.id);
                });
                desktop.appendChild(icon);
            }
            if (startApps && !startApps.querySelector(`.start-app-tile.pfapp-tile[data-app="${key}"]`)) {
                const tile = document.createElement('div');
                tile.className = 'start-app-tile pfapp-tile external-program';
                tile.dataset.app = key;
                tile.innerHTML = `<div class="start-app-icon">${renderAppIcon(key, 'desktop', app.name)}</div><div class="start-app-name">${textOf(app.name)}</div>`;
                tile.addEventListener('click', () => window.PFApps.open(app.id));
                startApps.appendChild(tile);
            }
        });
        if (window.desktopManager && typeof window.desktopManager.applyDesktopPositions === 'function') window.desktopManager.applyDesktopPositions();
        if (window.dragDropManager && typeof window.dragDropManager.refreshIcons === 'function') window.dragDropManager.refreshIcons();
    }

    function attach() {
        if (!window.PFApps || window.PFApps.__computerAttached) return !!window.PFApps;
        window.PFApps.__computerAttached = true;
        window.PFApps.attachShell({
            device: 'computer',
            openWindow(app, mount) {
                const el = ensureWindow(app);
                if (!el) return;
                wm().openWindow(winId(app.id));
                mount(el.querySelector('.pfapp-content'));
            },
            closeWindow(id) {
                if (wm()) wm().closeWindow(winId(id));
                const el = document.querySelector(`.window[data-app="${winId(id)}"] .pfapp-content`);
                if (el) el.innerHTML = '';
            },
            focusWindow(id) {
                if (wm()) wm().openWindow(winId(id));
            },
            onApps(apps) { renderIcons(apps); },
            notify(message, type) {
                if (typeof uiNotify === 'function') uiNotify(message, type === 'error' ? 'error' : (type === 'success' ? 'success' : 'info'));
            },
            openSite(host) {
                if (!wm()) return false;
                wm().openWindow('browser');
                if (window.browserManager) window.browserManager.loadUrl(host);
                return true;
            },
        });
        return true;
    }

    // The runtime is loaded from pf-devices; if it was not there when the page loaded, try again.
    function ensureRuntime() {
        if (window.PFApps) return Promise.resolve(true);
        return new Promise((resolve) => {
            const s = document.createElement('script');
            s.src = 'https://cfx-nui-pf-devices/html/runtime.js';
            s.onload = () => resolve(true);
            s.onerror = () => resolve(false);
            document.head.appendChild(s);
        });
    }

    window.addEventListener('message', async (event) => {
        const data = event.data || {};
        if (data.action === 'openComputer') {
            if (!(await ensureRuntime())) return;
            // the window manager is created on DOMContentLoaded; wait for it
            let tries = 0;
            while (!wm() && tries < 50) { await new Promise((r) => setTimeout(r, 50)); tries++; }
            if (attach()) {
                siteCache = { at: 0, list: [] };
                window.PFApps.refresh();
            }
        } else if (data.action === 'closeComputer') {
            // apps stay mounted while the computer is closed, like the computer's own windows
        }
    });

    if (window.PFApps) attach();
})();
