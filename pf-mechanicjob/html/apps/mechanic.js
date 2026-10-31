// Mechanic apps for pf-devices: the existing mechanic UI (html/tablet_module.js, MechanicTablet)
// mounted inside whichever device shell is open. Its buttons post to this resource's NUI callbacks,
// which run the server-checked flows; updates arrive through PFMechShell (client/devices_shell.lua).
(function () {
    const BASE = 'https://cfx-nui-pf-mechanicjob/html/';
    let loading = null;

    function load() {
        if (window.MechanicTablet && typeof window.MechanicTablet.renderWorkOrders === 'function') return Promise.resolve(true);
        if (!loading) {
            loading = new Promise((resolve) => {
                const s = document.createElement('script');
                s.src = BASE + 'tablet_module.js?v=2';
                s.onload = () => resolve(true);
                s.onerror = () => resolve(false);
                document.head.appendChild(s);
            });
        }
        return loading;
    }

    function app(renderName) {
        return {
            async mount(container) {
                container.classList.add('mech-platform-app');
                await load();
                const fn = window.MechanicTablet && window.MechanicTablet[renderName];
                if (typeof fn !== 'function') {
                    container.innerHTML = '<div class="pfapp-error">The mechanic app did not load. Is pf-mechanicjob running?</div>';
                    return;
                }
                fn(window.jQuery(container));
            },
        };
    }

    PFApps.register('mechanic-workorders', app('renderWorkOrders'));
    PFApps.register('mechanic-register', app('renderCashRegister'));
    PFApps.register('mechanic-management', app('renderManagement'));
})();
