// pf-tablet as a pf-devices shell: platform apps (pf-jobs, pf-news, pf-government, pf-services...)
// appear on the home screen next to the tablet's own apps and open in tablet windows. The modules
// are the same ones the computer runs.
(function () {
    const pendingMounts = {};
    let platformApps = [];

    function windowFor(id) {
        return $(`.app-window[data-app="${id}"]`);
    }

    window.PFTabletPlatform = {
        // home-screen entries for the platform apps (merged with the tablet's own list by script.js)
        apps() { return platformApps.slice(); },
        // script.js calls this when it created a window for a platform app
        takeMount(id) {
            const m = pendingMounts[id];
            delete pendingMounts[id];
            return m || null;
        },
        isPlatform(id) { return platformApps.some((a) => a.appId === id); },
    };

    function attach() {
        if (!window.PFApps || window.PFApps.__tabletAttached) return !!window.PFApps;
        window.PFApps.__tabletAttached = true;
        window.PFApps.attachShell({
            device: 'tablet',
            openWindow(app, mount) {
                const $win = windowFor(app.id);
                if ($win.length) {
                    window.restoreWindow(app.id);
                    mount($win.find('.window-content')[0]);
                    return;
                }
                pendingMounts[app.id] = mount;
                window.openAppWindow(app.id, app.name, app.icon, { platform: true, appId: app.id, name: app.name, icon: app.icon });
            },
            closeWindow(id) {
                if (windowFor(id).length) window.closeWindow(id);
            },
            focusWindow(id) {
                if (windowFor(id).length) window.restoreWindow(id);
            },
            onApps(apps) {
                platformApps = apps.map((a) => ({
                    name: a.name, icon: a.icon, enabled: true, platform: true, appId: a.id,
                    category: a.category, description: a.description,
                }));
                if (typeof window.PFTabletRenderApps === 'function') window.PFTabletRenderApps();
            },
            notify(message, type) {
                $.post(`https://${window.RESOURCE_NAME || 'pf-tablet'}/notify`, JSON.stringify({ message: String(message), type: type || 'primary' }));
            },
        });
        return true;
    }

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
        const d = event.data || {};
        if (d.action === 'openTablet') {
            if (!(await ensureRuntime())) return;
            if (attach()) window.PFApps.refresh();
        }
    });

    if (window.PFApps) attach();
})();
