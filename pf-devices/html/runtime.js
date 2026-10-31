/*
 * PF Devices runtime — loaded by every shell (pf-tablet, pf-computer) from
 * https://cfx-nui-pf-devices/html/runtime.js. One app module runs unchanged in every shell.
 *
 * App module contract (served from the owning resource, path given in RegisterApp):
 *
 *   PFApps.register('taxi', {
 *       mount(container, ctx)   // render into container (a DOM element inside the shell's window)
 *       unmount(ctx)            // optional: clean up timers etc.
 *       onEvent(event, payload, ctx) // optional: server pushes (exports['pf-devices']:Push)
 *   });
 *
 * ctx: { app, device, rpc(method, payload) -> Promise<result>, on(event, fn), off(event, fn),
 *        notify(message, type), close(), openApp(id, params), openSite(host), player(),
 *        setWaypoint(x, y), storage, el, h, esc, money, timeAgo }
 *
 * Shell adapter contract (each shell calls PFApps.attachShell once):
 *
 *   PFApps.attachShell({
 *       device: 'tablet' | 'computer',
 *       openWindow(app, mount) -> void   // create the window, then call mount(contentElement)
 *       closeWindow(appId)               // remove the window (runtime already unmounted)
 *       onApps(apps, store)              // render the home screen / desktop
 *       notify(message, type)            // optional in-shell toast
 *       isOpen()                         // optional: the device is on screen
 *   })
 *
 * and forwards NUI messages whose action starts with 'pfapp:' to PFApps.handleMessage(data).
 */
(function () {
    if (window.PFApps && window.PFApps.__runtime) return;

    const RUNTIME_RESOURCE = 'pf-devices';
    const PFApps = (window.PFApps = window.PFApps || {});
    PFApps.__runtime = true;

    const modules = {};      // appId -> module
    const siteModules = {};  // host -> module
    const waiting = {};      // appId -> [resolve]
    const loadedUrls = {};   // url -> Promise
    const instances = {};    // appId -> { app, container, ctx, module, listeners }
    const siteInstances = {};// host -> instance (sites mounted inside the browser app)
    let apps = [];
    let store = [];
    let categories = [];
    let shell = null;
    let refreshing = null;
    const globalListeners = {};

    // ── helpers ────────────────────────────────────────────────────
    function esc(s) {
        return String(s == null ? '' : s)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;').replace(/'/g, '&#039;');
    }

    function money(n) {
        const v = Number(n) || 0;
        return '$' + v.toLocaleString('en-US', { maximumFractionDigits: 2 });
    }

    function timeAgo(ts) {
        const t = typeof ts === 'number' ? ts * (ts < 1e12 ? 1000 : 1) : Date.parse(ts);
        if (!t || Number.isNaN(t)) return '';
        const diff = Math.max(0, Date.now() - t) / 1000;
        if (diff < 60) return 'just now';
        if (diff < 3600) return Math.floor(diff / 60) + ' min ago';
        if (diff < 86400) return Math.floor(diff / 3600) + ' h ago';
        return Math.floor(diff / 86400) + ' d ago';
    }

    // h('div.cls#id', { attr: v, onclick: fn }, children...) — small DOM builder.
    function h(tag, attrs, ...children) {
        const m = String(tag).match(/^([a-z0-9-]+)?((?:[.#][\w-]+)*)$/i);
        const el = document.createElement((m && m[1]) || 'div');
        if (m && m[2]) {
            m[2].split(/(?=[.#])/).forEach((part) => {
                if (part[0] === '.') el.classList.add(part.slice(1));
                else if (part[0] === '#') el.id = part.slice(1);
            });
        }
        if (attrs && typeof attrs === 'object' && !(attrs instanceof Node) && !Array.isArray(attrs)) {
            Object.entries(attrs).forEach(([k, v]) => {
                if (v == null || v === false) return;
                if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2).toLowerCase(), v);
                else if (k === 'class' || k === 'className') el.className = v;
                else if (k === 'style' && typeof v === 'object') Object.assign(el.style, v);
                else if (k === 'dataset') Object.assign(el.dataset, v);
                else if (k === 'html') el.innerHTML = v;
                else el.setAttribute(k, v === true ? '' : String(v));
            });
        } else if (attrs != null) {
            children.unshift(attrs);
        }
        const append = (c) => {
            if (c == null || c === false) return;
            if (Array.isArray(c)) { c.forEach(append); return; }
            el.appendChild(c instanceof Node ? c : document.createTextNode(String(c)));
        };
        children.forEach(append);
        return el;
    }

    async function post(name, data) {
        try {
            const res = await fetch(`https://${RUNTIME_RESOURCE}/${name}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify(data || {}),
            });
            return await res.json();
        } catch (err) {
            console.error('[pf-devices] request failed', name, err);
            return { ok: false, error: 'request_failed' };
        }
    }

    function loadScript(url) {
        if (!url) return Promise.resolve();
        if (!loadedUrls[url]) {
            loadedUrls[url] = new Promise((resolve) => {
                const s = document.createElement('script');
                s.src = url;
                s.async = false;
                s.onload = () => resolve(true);
                s.onerror = () => { console.error('[pf-devices] failed to load', url); resolve(false); };
                document.head.appendChild(s);
            });
        }
        return loadedUrls[url];
    }

    function loadStyle(url) {
        if (!url || loadedUrls[url]) return;
        loadedUrls[url] = Promise.resolve(true);
        const l = document.createElement('link');
        l.rel = 'stylesheet';
        l.href = url;
        document.head.appendChild(l);
    }

    function ensureRuntimeStyles() {
        loadStyle(`https://cfx-nui-${RUNTIME_RESOURCE}/html/runtime.css`);
    }

    // Some app modules use jQuery; a shell without it gets the vendored copy before modules load.
    let jqueryReady = null;
    function ensureJQuery() {
        if (window.jQuery) return Promise.resolve(true);
        if (!jqueryReady) jqueryReady = loadScript(`https://cfx-nui-${RUNTIME_RESOURCE}/html/vendor/jquery-3.6.0.min.js`);
        return jqueryReady;
    }

    function waitForModule(appId, timeoutMs) {
        if (modules[appId]) return Promise.resolve(modules[appId]);
        return new Promise((resolve) => {
            waiting[appId] = waiting[appId] || [];
            waiting[appId].push(resolve);
            setTimeout(() => resolve(modules[appId] || null), timeoutMs || 4000);
        });
    }

    function scopedStorage(prefix) {
        const key = (k) => `pfapp:${prefix}:${k}`;
        return {
            get(k, fallback) {
                try { const v = localStorage.getItem(key(k)); return v == null ? fallback : JSON.parse(v); } catch (_) { return fallback; }
            },
            set(k, v) { try { localStorage.setItem(key(k), JSON.stringify(v)); } catch (_) { /* ignore */ } },
            remove(k) { try { localStorage.removeItem(key(k)); } catch (_) { /* ignore */ } },
        };
    }

    function makeCtx(app, container, kind) {
        const listeners = {};
        const ctx = {
            app,
            device: shell ? shell.device : 'unknown',
            el: container,
            h, esc, money, timeAgo,
            storage: scopedStorage((kind === 'site' ? 'site:' : '') + app.id),
            rpc(method, payload) { return post('rpc', { app: app.id, method, payload: payload || {} }); },
            on(event, fn) { (listeners[event] = listeners[event] || []).push(fn); return () => ctx.off(event, fn); },
            off(event, fn) { listeners[event] = (listeners[event] || []).filter((f) => f !== fn); },
            emit(event, payload) { (listeners[event] || []).forEach((fn) => { try { fn(payload, ctx); } catch (e) { console.error('[pf-devices] listener failed', app.id, event, e); } }); },
            notify(message, type) { return PFApps.notify(message, type); },
            close() { if (kind === 'site') PFApps.closeSite(app.host); else PFApps.close(app.id); },
            openApp(id, params) { return PFApps.open(id, params); },
            openSite(host) { return PFApps.openSite(host); },
            player() { return post('player', {}); },
            setWaypoint(x, y) { return post('setWaypoint', { x, y }); },
            apps() { return apps.slice(); },
        };
        return { ctx, listeners };
    }

    // ── public API ─────────────────────────────────────────────────
    PFApps.register = function (appId, module) {
        if (!appId || !module || typeof module.mount !== 'function') {
            console.error('[pf-devices] bad module registration', appId);
            return;
        }
        modules[appId] = module;
        (waiting[appId] || []).forEach((resolve) => resolve(module));
        delete waiting[appId];
    };

    PFApps.registerSite = function (host, module) {
        if (!host || !module || typeof module.mount !== 'function') return;
        siteModules[String(host).toLowerCase()] = module;
        const key = 'site:' + String(host).toLowerCase();
        (waiting[key] || []).forEach((resolve) => resolve(module));
        delete waiting[key];
    };

    PFApps.attachShell = function (adapter) {
        shell = adapter;
        ensureRuntimeStyles();
    };

    PFApps.getApps = () => apps.slice();
    PFApps.getStore = () => store.slice();
    PFApps.getCategories = () => categories.slice();
    PFApps.getApp = (id) => apps.find((a) => a.id === id) || null;
    PFApps.isOpen = (id) => !!instances[id];

    PFApps.notify = function (message, type) {
        if (shell && typeof shell.notify === 'function') {
            try { shell.notify(message, type); return; } catch (_) { /* fall through */ }
        }
        post('notify', { message: String(message), type: type || 'primary' });
    };

    // Fetch the app list for this device and preload the modules.
    PFApps.refresh = async function () {
        if (!shell) return [];
        if (refreshing) return refreshing;
        refreshing = (async () => {
            const res = await post('apps', { device: shell.device });
            apps = Array.isArray(res && res.apps) ? res.apps : [];
            store = Array.isArray(res && res.store) ? res.store : [];
            categories = Array.isArray(res && res.categories) ? res.categories : [];
            await ensureJQuery();
            apps.forEach((a) => {
                (a.styles || []).forEach(loadStyle);
                if (a.kind === 'module' && a.entry) loadScript(a.entry);
            });
            // Apps the player lost access to close by themselves.
            Object.keys(instances).forEach((id) => { if (!apps.some((a) => a.id === id)) PFApps.close(id); });
            if (typeof shell.onApps === 'function') shell.onApps(apps.slice(), store.slice());
            return apps;
        })();
        try { return await refreshing; } finally { refreshing = null; }
    };

    async function mountInto(app, container, params) {
        container.classList.add('pfapp-root');
        container.dataset.pfapp = app.id;
        if (app.kind === 'iframe') {
            container.innerHTML = '';
            const frame = h('iframe.pfapp-frame', { src: app.url, title: app.name, allow: 'clipboard-read; clipboard-write' });
            container.appendChild(frame);
            const { ctx, listeners } = makeCtx(app, container, 'app');
            instances[app.id] = { app, container, ctx, listeners, module: null, frame };
            return;
        }
        container.innerHTML = '<div class="pfapp-loading">Loading ' + esc(app.name) + '…</div>';
        await ensureJQuery();
        await loadScript(app.entry);
        const module = await waitForModule(app.id);
        if (!instances[app.id] || instances[app.id].container !== container) return; // closed meanwhile
        if (!module) {
            container.innerHTML = '<div class="pfapp-error">This app did not load. Its resource may be stopped.</div>';
            return;
        }
        const inst = instances[app.id];
        inst.module = module;
        container.innerHTML = '';
        try {
            await module.mount(container, inst.ctx, params || {});
        } catch (e) {
            console.error('[pf-devices] mount failed', app.id, e);
            container.innerHTML = '<div class="pfapp-error">This app crashed while opening.</div>';
        }
    }

    PFApps.open = async function (appId, params) {
        if (!shell) return false;
        const app = PFApps.getApp(appId);
        if (!app) {
            PFApps.notify('That app is not available on this device', 'error');
            return false;
        }
        if (instances[appId]) {
            if (typeof shell.focusWindow === 'function') shell.focusWindow(appId);
            if (params && instances[appId].ctx) instances[appId].ctx.emit('params', params);
            return true;
        }
        const placeholder = { app, container: null, ctx: null, listeners: {}, module: null };
        instances[appId] = placeholder;
        shell.openWindow(app, (container) => {
            if (instances[appId] !== placeholder) return;
            const { ctx, listeners } = makeCtx(app, container, 'app');
            placeholder.container = container;
            placeholder.ctx = ctx;
            placeholder.listeners = listeners;
            mountInto(app, container, params);
        });
        return true;
    };

    PFApps.close = function (appId) {
        const inst = instances[appId];
        if (!inst) return;
        delete instances[appId];
        if (inst.module && typeof inst.module.unmount === 'function') {
            try { inst.module.unmount(inst.ctx); } catch (e) { console.error('[pf-devices] unmount failed', appId, e); }
        }
        if (inst.container) inst.container.innerHTML = '';
        if (shell && typeof shell.closeWindow === 'function') shell.closeWindow(appId);
    };

    // Called by the shell when the user closed the window themselves.
    PFApps.windowClosed = function (appId) {
        const inst = instances[appId];
        if (!inst) return;
        delete instances[appId];
        if (inst.module && typeof inst.module.unmount === 'function') {
            try { inst.module.unmount(inst.ctx); } catch (_) { /* ignore */ }
        }
    };

    PFApps.closeAll = function () {
        Object.keys(instances).forEach((id) => PFApps.close(id));
    };

    // ── sites (rendered inside the Browser app) ────────────────────
    PFApps.sites = async function () {
        const res = await post('sites', {});
        return Array.isArray(res && res.sites) ? res.sites : [];
    };

    PFApps.mountSite = async function (site, container) {
        const host = String(site.host).toLowerCase();
        PFApps.unmountSite(host);
        container.classList.add('pfsite-root');
        container.innerHTML = '<div class="pfapp-loading">Connecting to ' + esc(host) + '…</div>';
        (site.styles || []).forEach(loadStyle);
        await ensureJQuery();
        await loadScript(site.entry);
        const module = siteModules[host] || (await waitForModule('site:' + host));
        if (!module) {
            container.innerHTML = '<div class="pfapp-error">This site is not responding.</div>';
            return false;
        }
        const app = { id: site.appId, name: site.name, icon: site.icon, host };
        const { ctx, listeners } = makeCtx(app, container, 'site');
        siteInstances[host] = { app, container, ctx, listeners, module };
        container.innerHTML = '';
        try { await module.mount(container, ctx, {}); } catch (e) {
            console.error('[pf-devices] site mount failed', host, e);
            container.innerHTML = '<div class="pfapp-error">This site crashed while loading.</div>';
        }
        return true;
    };

    PFApps.unmountSite = function (host) {
        const inst = siteInstances[String(host).toLowerCase()];
        if (!inst) return;
        delete siteInstances[String(host).toLowerCase()];
        if (inst.module && typeof inst.module.unmount === 'function') {
            try { inst.module.unmount(inst.ctx); } catch (_) { /* ignore */ }
        }
    };

    // A shell with its own browser (the computer) renders sites in it; the tablet uses the Browser app.
    PFApps.openSite = async function (host) {
        if (shell && typeof shell.openSite === 'function') return shell.openSite(String(host || '').toLowerCase());
        return PFApps.open('browser', { host });
    };

    PFApps.closeSite = function (host) {
        PFApps.unmountSite(host);
        emitGlobal('site:closed', { host });
    };

    // ── events from the client (via the shell) ─────────────────────
    function emitGlobal(event, payload) {
        (globalListeners[event] || []).forEach((fn) => { try { fn(payload); } catch (_) { /* ignore */ } });
    }
    PFApps.on = function (event, fn) { (globalListeners[event] = globalListeners[event] || []).push(fn); };

    PFApps.handleMessage = function (data) {
        if (!data || typeof data.action !== 'string' || !data.action.startsWith('pfapp:')) return false;
        switch (data.action) {
            case 'pfapp:event': {
                const inst = instances[data.app];
                if (inst && inst.ctx) {
                    inst.ctx.emit(data.event, data.payload);
                    if (inst.module && typeof inst.module.onEvent === 'function') {
                        try { inst.module.onEvent(data.event, data.payload, inst.ctx); } catch (e) { console.error('[pf-devices] onEvent failed', data.app, e); }
                    }
                    if (inst.frame && inst.frame.contentWindow) {
                        inst.frame.contentWindow.postMessage({ action: 'pfapp:event', app: data.app, event: data.event, payload: data.payload }, '*');
                    }
                }
                Object.values(siteInstances).forEach((s) => { if (s.app.id === data.app) s.ctx.emit(data.event, data.payload); });
                emitGlobal('event', data);
                return true;
            }
            case 'pfapp:appsChanged':
                PFApps.refresh();
                return true;
            case 'pfapp:open':
                PFApps.open(data.app, data.params);
                return true;
            case 'pfapp:close':
                PFApps.close(data.app);
                return true;
            case 'pfapp:openSite':
                PFApps.openSite(data.host);
                return true;
            default:
                return false;
        }
    };

    window.addEventListener('message', (ev) => {
        const d = ev && ev.data;
        if (d && typeof d.action === 'string' && d.action.startsWith('pfapp:')) PFApps.handleMessage(d);
    });

    PFApps.util = { esc, money, timeAgo, h };
})();
