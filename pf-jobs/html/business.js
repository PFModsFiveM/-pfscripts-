// Auto-refresh for business app (rendering handled by script.js)
(function(){
    let businessInterval = null;

    function startBusinessAutoRefresh(){
        if (businessInterval) return;
        businessInterval = setInterval(()=> {
            const $w = $('.app-window[data-app="business"]');
            if ($w.is(':visible')) {
                // Auto-refresh without showing loading skeleton
                $.post('https://pf-jobs/app/business/getStatus', JSON.stringify({}), function(resp){
                    try{ if(typeof resp==='string') resp=JSON.parse(resp); }catch(e){ resp=[]; }
                    const $c = $w.find('.window-content');
                    if (typeof window.renderBusinessList === 'function') {
                        window.renderBusinessList($c, resp);
                    }
                });
            }
        }, 5000);
    }

    function stopBusinessAutoRefresh(){
        if (businessInterval){ clearInterval(businessInterval); businessInterval = null; }
    }

    function hook(){
        if (typeof window.openAppWindow !== 'function') return;
        const baseOpen = window.openAppWindow;
        window.openAppWindow = function(appName, appLabel, appIcon){
            baseOpen(appName, appLabel, appIcon);
            if (appName === 'business'){
                startBusinessAutoRefresh();
            }
        };
        if (typeof window.closeWindow === 'function') {
            const baseClose = window.closeWindow;
            window.closeWindow = function(appName){
                if (appName === 'business') stopBusinessAutoRefresh();
                return baseClose(appName);
            };
        }
    }

    // Initialize
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', hook);
    } else {
        hook();
    }
    window.addEventListener('pfjs-ready', hook);
})();
