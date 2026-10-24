// Businesses App - View all active businesses
(function(){
    const RESOURCE_NAME = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'pf-tablet';
    let businessesInterval = null;

    function renderBusinessesUI($container) {
        $container.html(`
            <div class="businesses-container">
                <div class="businesses-header">
                    <div class="businesses-title-section">
                        <div class="businesses-icon">🏪</div>
                        <div>
                            <div class="businesses-title">Active Businesses</div>
                            <div class="businesses-subtitle">View all available businesses</div>
                        </div>
                    </div>
                    <button class="businesses-refresh-btn" id="businesses-refresh">
                        <span>⟳</span> Refresh
                    </button>
                </div>
                <div class="businesses-list" id="businesses-list">
                    <div class="businesses-loading">Loading businesses...</div>
                </div>
            </div>
        `);

        attachBusinessesEvents($container);
        loadAndRenderBusinesses($container);
    }

    function loadAndRenderBusinesses($container) {
        $.post(`https://${RESOURCE_NAME}/app/businesses/list`, JSON.stringify({}), function(resp){
            try{ if(typeof resp==='string') resp=JSON.parse(resp); }catch(e){ resp=[]; }
            renderBusinessesCards($container, resp || []);
        }).fail(() => {
            $container.find('#businesses-list').html(
                '<div class="businesses-error">Failed to load businesses</div>'
            );
        });
    }

    function renderBusinessesCards($container, businesses) {
        if (!businesses || businesses.length === 0) {
            $container.find('#businesses-list').html(
                '<div class="businesses-empty">No active businesses available</div>'
            );
            return;
        }

        const html = businesses.map(biz => {
            const online = Number(biz.online || 0);
            const isActive = online > 0;
            const icon = biz.icon || '🏢';
            const businessName = biz.businessName || biz.label || 'Business';
            const businessType = biz.businessType || 'business';
            const desc = biz.description || (businessType.charAt(0).toUpperCase() + businessType.slice(1) + ' business');
            
            return `
                <div class="business-card-item">
                    <div class="business-card-top">
                        <div class="business-card-icon">${icon}</div>
                        <div class="business-card-status ${isActive ? 'active' : 'inactive'}">
                            <span class="status-dot"></span>
                            <span class="status-text">${online} Online</span>
                        </div>
                    </div>
                    <div class="business-card-info">
                        <div class="business-card-name">${businessName}</div>
                        <div class="business-card-desc">${desc}</div>
                    </div>
                    <div class="business-card-footer">
                        <div class="employees-count">
                            <span class="emp-icon">👥</span>
                            <span>${online} ${online === 1 ? 'employee' : 'employees'} online</span>
                        </div>
                    </div>
                </div>
            `;
        }).join('');

        $container.find('#businesses-list').html(html);
    }

    function attachBusinessesEvents($container) {
        $container.on('click', '#businesses-refresh', function(){
            $(this).find('span:first').css('animation', 'spin 0.6s linear');
            loadAndRenderBusinesses($container);
            setTimeout(() => {
                $(this).find('span:first').css('animation', 'none');
            }, 600);
        });

        // Auto-refresh when window is visible
        const observer = new MutationObserver(() => {
            const $win = $(`.app-window[data-app="businesses"]`);
            if ($win.length && $win.is(':visible')) {
                if (!businessesInterval) {
                    businessesInterval = setInterval(() => {
                        const $w = $(`.app-window[data-app="businesses"]`);
                        if ($w.is(':visible')) {
                            loadAndRenderBusinesses($w.find('.window-content'));
                        }
                    }, 5000);
                }
            } else {
                if (businessesInterval) {
                    clearInterval(businessesInterval);
                    businessesInterval = null;
                }
            }
        });

        const $win = $(`.app-window[data-app="businesses"]`);
        if ($win.length) {
            observer.observe($win[0], { attributes: true, attributeFilter: ['style'] });
        }
    }

    function startBusinessesAutoRefresh() {
        if (businessesInterval) return;
        businessesInterval = setInterval(() => {
            const $w = $(`.app-window[data-app="businesses"]`);
            if ($w.is(':visible')) {
                loadAndRenderBusinesses($w.find('.window-content'));
            }
        }, 5000);
    }

    function stopBusinessesAutoRefresh() {
        if (businessesInterval) {
            clearInterval(businessesInterval);
            businessesInterval = null;
        }
    }

    // Hook into app opening
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function() {
            hookBusinessesApp();
        });
    } else {
        hookBusinessesApp();
    }

    function hookBusinessesApp() {
        if (typeof window.openAppWindow !== 'function') return;
        
        const baseOpen = window.openAppWindow;
        window.openAppWindow = function(...args) {
            baseOpen(...args);
            const appName = String(args[0] || '').toLowerCase();
            if (appName === 'businesses') {
                startBusinessesAutoRefresh();
            }
        };

        if (typeof window.closeWindow !== 'function') return;
        const baseClose = window.closeWindow;
        window.closeWindow = function(appName) {
            if (appName === 'businesses') stopBusinessesAutoRefresh();
            return baseClose(appName);
        };
    }

    // Expose render function
    window.renderBusinessesUI = renderBusinessesUI;
})();
