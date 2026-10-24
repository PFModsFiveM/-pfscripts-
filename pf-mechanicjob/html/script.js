$(document).ready(function() {
    // Update time
    function updateTime() {
        const now = new Date();
        const hours = String(now.getHours()).padStart(2, '0');
        const minutes = String(now.getMinutes()).padStart(2, '0');
        $('#time').text(`${hours}:${minutes}`);
    }
    
    updateTime();
    setInterval(updateTime, 60000);

    // Global state container
window.openWindows = window.openWindows || {}

// Stub globals (prevents ReferenceError before real definitions)
window.openAppWindow = window.openAppWindow || function(){}
window.closeWindow = window.closeWindow || function(){}
window.restoreWindow = window.restoreWindow || function(){}
window.minimizeWindow = window.minimizeWindow || function(){}

let draggedWindow = null
let dragOffset = { x: 0, y: 0 }
let windowStartPos = { x: 0, y: 0 }

    // Helpers
    function getTabletScale(){
        const t = getComputedStyle(document.querySelector('.tablet')).transform
        if (!t || t === 'none') return 1
        const m = t.match(/matrix\(([^)]+)\)/)
        if (!m) return 1
        return parseFloat(m[1].split(',')[0]) || 1
    }
    function centerWindowNumeric($w){
        const c = $('.tablet-screen')
        const cw = c.width(), ch = c.height()
        const ww = $w.outerWidth(), wh = $w.outerHeight()
        $w.css({ left: (cw-ww)/2+'px', top: (ch-wh)/2+'px', transform: 'none' })
    }

    // Load apps
    function loadApps(apps){
        const appGrid = $('#app-grid')
        appGrid.empty()
        apps.forEach(a=>{
            if (!a.enabled) return
            appGrid.append(`
                <div class="app-item" data-app="${a.name.toLowerCase().replace(/\s+/g,'-')}">
                    <div class="app-icon">${a.icon}</div>
                    <div class="app-label">${a.name}</div>
                </div>
            `)
        })

        // Inject Garbage app between Gruppe6 and Real Estate if not provided by server
        const order = ['Business','Contracts','Gruppe6','Garbage','Real Estate','Stocking']
        const current = []
        $('#app-grid .app-item').each(function(){ current.push($(this).find('.app-label').text()) })
        if (!current.includes('Garbage')){
            const $items = $('#app-grid .app-item')
            let insertIdx = -1
            $items.each(function(i){
                const label = $(this).find('.app-label').text()
                if (label === 'Real Estate') { insertIdx = i; return false }
            })
            const garbageHtml = `
                <div class="app-item" data-app="garbage">
                    <div class="app-icon">🚚</div>
                    <div class="app-label">Garbage</div>
                </div>`
            if (insertIdx > 0) {
                $items.eq(insertIdx - 1).after(garbageHtml)
            } else {
                $('#app-grid').append(garbageHtml)
            }
        }
    }

// Ensure base functions exist before any overrides
function openAppWindow(appName, appLabel, appIcon) {
    if (openWindows[appName]) { restoreWindow(appName); return; }
    $('#windows-container').append(`
        <div class="app-window" data-app="${appName}" style="width:1100px;height:700px;">
            <div class="window-titlebar">
                <div class="window-title">
                    <span class="window-icon">${appIcon}</span>
                    <span>${appLabel}</span>
                </div>
                <div class="window-controls">
                    <div class="window-btn minimize" data-action="minimize">−</div>
                    <div class="window-btn close" data-action="close">×</div>
                </div>
            </div>
            <div class="window-content"></div>
        </div>
    `);
    const $w = $(`.app-window[data-app="${appName}"]`);
    centerWindowNumeric($w);
    openWindows[appName] = { label: appLabel, icon: appIcon, minimized: false };

    // Notify app script
    window.postMessage({ action:'openApp', app: appName, label: appLabel, icon: appIcon }, '*')

    // Notify app-specific scripts to mount their UI
    try {
        window.postMessage({ action: 'openApp', app: appName, label: appLabel, icon: appIcon }, '*');
    } catch (e) {}

    // Business app bootstrap (kept)
    if (appName === 'business') {
        const $c = $w.find('.window-content');
        renderBusinessLoading($c);
        fetchBusinessStatus();
    }

    // Gruppe6 app bootstrap
    if (appName === 'gruppe6') {
        renderGruppe6Window(appName);
        // Request initial state from client
        try { $.post('https://pf-jobsystem/gruppe6:getInit', JSON.stringify({}), ()=>{}); } catch(e) {}
    }

    // Garbage app bootstrap
    if (appName === 'garbage') {
        renderGarbageWindow(appName)
        try { $.post('https://pf-jobsystem/garbage:getInit', JSON.stringify({}), ()=>{}); } catch(e) {}
    }
}

function minimizeWindow(appName) {
    const w = $(`.app-window[data-app="${appName}"]`);
    if (!w.length || !openWindows[appName] || openWindows[appName].minimized) return;
    w.addClass('minimized');
    openWindows[appName].minimized = true;
    // Standard dock icon style
    $('.dock').append(`
        <div class="dock-item window-task" data-app="${appName}">
            <div class="dock-icon">${openWindows[appName].icon}</div>
            <div class="dock-label">${openWindows[appName].label}</div>
        </div>
    `);
}

function restoreWindow(appName) {
    const w = $(`.app-window[data-app="${appName}"]`);
    if (!w.length) return;
    w.removeClass('minimized');
    openWindows[appName] && (openWindows[appName].minimized = false);
    $(`.dock-item.window-task[data-app="${appName}"]`).remove();
}

function closeWindow(appName) {
    $(`.app-window[data-app="${appName}"]`).remove();
    $(`.dock-item.window-task[data-app="${appName}"]`).remove();
    delete openWindows[appName];
}

// Export to window (if needed elsewhere)
window.openAppWindow = openAppWindow;
window.minimizeWindow = minimizeWindow;
window.restoreWindow  = restoreWindow;
window.closeWindow    = closeWindow;

    // Dispatch readiness for app modules
    window.dispatchEvent(new Event('pfjs-ready'))

    // Event: Tablet open/close
    window.addEventListener('message', e=>{
        const d = e.data || {}
        if (d.action === 'openTablet'){
            $('#tablet-container').removeClass('hidden')
            loadApps(d.apps || [])
        } else if (d.action === 'closeTablet'){
            $('#tablet-container').addClass('hidden')
            Object.keys(openWindows).forEach(k=>closeWindow(k))
        }
    })

    // App icon click
    $(document).on('click','.app-item', function(){
        const appName = $(this).data('app')
        openAppWindow(appName, $(this).find('.app-label').text(), $(this).find('.app-icon').text())
    })
    // Dock minimized click
    $(document).on('click','.dock-item.window-task', function(){
        restoreWindow($(this).data('app'))
    })
    // Window control buttons
    $(document).on('click','.window-btn', function(e){
        e.stopPropagation()
        const action = $(this).data('action')
        const app = $(this).closest('.app-window').data('app')
        if (action === 'close') closeWindow(app)
        else if (action === 'minimize') minimizeWindow(app)
    })

    // Drag start
    $(document).on('mousedown','.window-titlebar', function(e){
        if ($(e.target).closest('.window-btn').length) return
        draggedWindow = $(this).closest('.app-window')
        if (draggedWindow.css('transform') !== 'none') centerWindowNumeric(draggedWindow)
        windowStartPos.x = parseFloat(draggedWindow.css('left')) || 0
        windowStartPos.y = parseFloat(draggedWindow.css('top')) || 0
        const off = $('.tablet-screen').offset()
        const scale = getTabletScale()
        dragOffset.x = (e.clientX - off.left)/scale - windowStartPos.x
        dragOffset.y = (e.clientY - off.top)/scale - windowStartPos.y
        draggedWindow.css('z-index',102)
        e.preventDefault()
    })
    // Drag move
    $(document).on('mousemove', function(e){
        if (!draggedWindow) return
        const cont = $('.tablet-screen')
        const off = cont.offset()
        const scale = getTabletScale()
        const cw = cont.width(), ch = cont.height()
        const ww = draggedWindow.outerWidth(), wh = draggedWindow.outerHeight()
        let nl = (e.clientX - off.left)/scale - dragOffset.x
        let nt = (e.clientY - off.top)/scale - dragOffset.y
        nl = Math.max(0, Math.min(nl, cw - ww))
        nt = Math.max(0, Math.min(nt, ch - wh))
        draggedWindow.css({ left: nl+'px', top: nt+'px' })
    })
    // Drag end
    $(document).on('mouseup mouseleave', function(){
        if (draggedWindow){
            draggedWindow.css('z-index',101)
            draggedWindow = null
        }
    })
});

// Keep resource name helper
function GetParentResourceName(){ return 'pf-jobsystem' }

// Business helpers (simplified - business.js handles auto-refresh)
function renderBusinessLoading($c){
    $c.html(`
        <div class="business-container">
            <div class="business-header">
                <div class="business-header-content">
                    <div class="business-title-section">
                        <div class="business-icon-large">🏢</div>
                        <div>
                            <div class="business-title">Business Management</div>
                            <div class="business-subtitle">Loading...</div>
                        </div>
                    </div>
                    <button class="btn-refresh" data-action="biz-refresh">
                        <span class="refresh-icon">↻</span>
                        <span class="refresh-text">Refresh</span>
                    </button>
                </div>
            </div>
            <div class="business-list">
                <div class="business-card skeleton"></div>
                <div class="business-card skeleton"></div>
                <div class="business-card skeleton"></div>
                <div class="business-card skeleton"></div>
            </div>
        </div>
    `);
}

function renderBusinessList($c, list){
    const cards = (list||[]).map(it=>`
        <div class="business-card">
            <div class="business-card-inner">
                <div class="business-card-header">
                    <div class="biz-icon-wrapper">
                        <div class="biz-icon">${it.icon || '🏢'}</div>
                        <div class="biz-icon-glow"></div>
                    </div>
                    <div class="biz-info">
                        <div class="biz-name">${it.label}</div>
                        <div class="biz-description">${it.description || ''}</div>
                    </div>
                </div>
                <div class="business-card-footer">
                    <div class="status-indicator ${it.online>0?'active':'inactive'}">
                        <div class="status-dot"></div>
                        <span class="status-text">${it.online} Employee${it.online !== 1 ? 's' : ''} Online</span>
                    </div>
                </div>
            </div>
        </div>`).join('');
    $c.html(`
        <div class="business-container">
            <div class="business-header">
                <div class="business-header-content">
                    <div class="business-title-section">
                        <div class="business-icon-large">🏢</div>
                        <div>
                            <div class="business-title">Business Management</div>
                            <div class="business-subtitle">${(list||[]).length} Active Business${(list||[]).length !== 1 ? 'es' : ''}</div>
                        </div>
                    </div>
                    <button class="btn-refresh" data-action="biz-refresh">
                        <span class="refresh-icon">↻</span>
                        <span class="refresh-text">Refresh</span>
                    </button>
                </div>
            </div>
            <div class="business-list">${cards || '<div class="business-empty">No businesses found</div>'}</div>
        </div>
    `);
}

function fetchBusinessStatus(){
    const $c = $('.app-window[data-app="business"] .window-content');
    if (!$c.length) return;
    $.post('https://pf-jobsystem/app/business/getStatus', JSON.stringify({}), function(resp){
        try{ if(typeof resp==='string') resp=JSON.parse(resp); }catch(e){ resp=[]; }
        renderBusinessList($c, resp);
    }).fail(()=>{$c.html('<p style="opacity:.6">Failed to load.</p>');});
}

// Refresh button
$(document).on('click','.btn-refresh[data-action="biz-refresh"]',function(e){
    e.stopPropagation();
    const $c=$(this).closest('.app-window').find('.window-content');
    renderBusinessLoading($c);
    fetchBusinessStatus();
});

// Ensure PFState exists and playerName will be filled by NUI on openTablet
window.PFState = window.PFState || {
    airplane: false,
    playerName: 'Player',
    about: { version: '1.0.0', description: 'QBCore Job Tablet System', creator: 'PFMods' }
};

// Helper to set player name robustly
function setPFPlayerName(val){
    const name = (val || '').trim();
    if (name.length) {
        window.PFState.playerName = name;
        // Update Settings sidebar live if open
        const $settings = $('.app-window[data-app="settings"] .settings-profile .name');
        if ($settings.length) $settings.text(name);
        const initials = name.split(' ').map(s => s[0] || '').join('').slice(0,2).toUpperCase();
        const $avatar = $('.app-window[data-app="settings"] .settings-profile .avatar');
        if ($avatar.length) $avatar.text(initials);
    }
}

// When opening Settings, always read from PFState.playerName
function openSettingsWindow(){
    const appName = 'settings'
    const appLabel = 'Settings'
    const appIcon = '⚙️'

    // If already open, restore
    if ($(`.app-window[data-app="${appName}"]`).length) {
        restoreWindow(appName)
    } else {
        // Use the core openAppWindow to build standard window UI (titlebar, controls)
        // Airplane mode must not block settings
        const wasAirplane = !!window.PFState.airplane
        if (wasAirplane) {
            // Temporarily bypass block by calling the original core directly if you wrapped it
            // Otherwise just call openAppWindow; Settings should be allowed by your wrapper.
        }
        openAppWindow(appName, appLabel, appIcon)
    }

    // Render content into the window
    const $content = $(`.app-window[data-app="${appName}"] .window-content`)
    if (!$content.length) return

    const name = (window.PFState && window.PFState.playerName) ? window.PFState.playerName : 'Player';
    const initials = name.split(' ').map(s => s[0] || '').join('').slice(0,2).toUpperCase();

    $('.app-window[data-app="settings"] .window-content').html(`
        <div class="settings-container">
            <div class="settings-sidebar">
                <div class="settings-search"><input type="text" placeholder="Search"></div>
                <div class="settings-profile">
                    <div class="avatar">${initials}</div>
                    <div>
                        <div class="name">${name}</div>
                        <div class="desc">iFruit Account and more</div>
                    </div>
                </div>

                <div class="settings-section-title">NETWORK</div>
                <div class="settings-item" data-pane="airplane">
                    <div class="settings-icon">✈️</div>
                    <div>
                        <div class="label">Airplane Mode</div>
                        <div class="sublabel">Disable notifications and services</div>
                    </div>
                </div>

                <div class="settings-section-title">GENERAL</div>
                <div class="settings-item" data-pane="general">
                    <div class="settings-icon">⚙️</div>
                    <div class="label">General</div>
                </div>

                <div class="settings-section-title">DISPLAY</div>
                <div class="settings-item" data-pane="display">
                    <div class="settings-icon">🖼️</div>
                    <div class="label">Display</div>
                </div>
            </div>

            <div class="settings-main" id="settings-pane"></div>
        </div>
    `)

    renderSettingsPane('airplane') // ensure not empty
}

// Pane renderers (ensure they exist)
function renderSettingsPane(pane) {
	const $pane = $('#settings-pane')
	if (!$pane.length) return

	if (pane === 'airplane') {
		const on = !!(window.PFState && window.PFState.airplane)
		$pane.html(`
			<div class="settings-row">
				<div>
					<div class="label">Airplane Mode</div>
					<div class="sublabel">Turn off notifications, jobs, services</div>
				</div>
				<div class="switch ${on ? 'on' : ''}" id="toggle-airplane">
					<div class="switch-thumb"></div>
				</div>
			</div>
			<div class="settings-row">
				<div class="sublabel">Apps are disabled and show an overlay. Settings remains usable.</div>
			</div>
		`)
		return
	}

	if (pane === 'general') {
		const a = (window.PFState && window.PFState.about) || {}
		$pane.html(`
			<div class="settings-row"><div class="label">About</div></div>
			<div class="settings-row"><div><div class="label">Version</div><div class="sublabel">${a.version || '1.0.0'}</div></div></div>
			<div class="settings-row"><div><div class="label">Description</div><div class="sublabel">${a.description || 'Job Tablet System'}</div></div></div>
			<div class="settings-row"><div><div class="label">Creator</div><div class="sublabel">${a.creator || 'PFMods'}</div></div></div>
		`)
		return
	}

	if (pane === 'display') {
		const current = localStorage.getItem('pfTabletBgUrl') || ''
		$pane.html(`
			<div class="settings-row">
				<div>
					<div class="label">Background URL</div>
					<div class="sublabel">png, jpg, jpeg, webp supported</div>
				</div>
			</div>
			<div class="input-row">
				<input type="text" id="bg-url" placeholder="https://example.com/wallpaper.png" value="${current}">
				<button id="save-bg">Save</button>
                <button id="restore-bg" style="margin-left:8px;">Restore Default</button>
			</div>
		`)
		return
	}
}

// Click bindings (ensure they’re active)
$(document).off('click.settingsNav').on('click.settingsNav', '.settings-item', function() {
	renderSettingsPane($(this).data('pane'))
})

$(document).off('click.settingsGear')
	.on('click.settingsGear', '#settings-btn', function() { openSettingsWindow() })
	.on('click.settingsGear', '.status-right .icon', function() {
		if ($(this).data('app') === 'settings' || /⚙/.test($(this).text())) openSettingsWindow()
	})

// Airplane toggle + overlay logic
$(document).off('click.toggleAir').on('click.toggleAir', '#toggle-airplane', function() {
	const on = !$(this).hasClass('on')
	$(this).toggleClass('on', on)
	window.PFState = window.PFState || {}
	window.PFState.airplane = on

	const screen = document.querySelector('.tablet-screen')
	if (!screen) return
	if (on) screen.classList.add('airplane-on')
	else screen.classList.remove('airplane-on')
})

// Background save + apply
function applySavedBackground() {
    const screen = document.querySelector('.tablet-screen');
    if (!screen) return;
    const url = (localStorage.getItem('pfTabletBgUrl') || '').trim();
    // reset to default
    screen.style.background = 'linear-gradient(135deg, #334a82 0%, #4462a3 100%)';
    screen.style.backgroundImage = '';
    // Support http/https and relative resource paths
    if (url && /\.(png|jpg|jpeg|webp)$/i.test(url)) {
        let resolved = url;
        if (!/^https?:\/\//i.test(url)) {
            try {
                resolved = new URL(url, window.location.href).href;
            } catch (e) {
                resolved = url; // fallback
            }
        }
        screen.style.backgroundImage = `url("${resolved}")`;
        screen.style.backgroundRepeat = 'no-repeat';
        screen.style.backgroundPosition = 'center center';
        screen.style.backgroundSize = 'cover';
    }
}
$(document).off('click.saveBg').on('click.saveBg', '#save-bg', function() {
	const url = ($('#bg-url').val() || '').trim()
	if (!url.length) {
		localStorage.removeItem('pfTabletBgUrl')
		applySavedBackground()
		return
	}
	if (!/\.(png|jpg|jpeg|webp)$/i.test(url)) { alert('Supported: png/jpg/jpeg/webp'); return }
	localStorage.setItem('pfTabletBgUrl', url)
	applySavedBackground()
})

// Restore default wallpaper
$(document).off('click.restoreBg').on('click.restoreBg', '#restore-bg', function(){
    localStorage.removeItem('pfTabletBgUrl');
    $('#bg-url').val('');
    applySavedBackground();
})

// Allow opening settings during airplane mode
const coreOpenAppWindow = window.openAppWindow
window.openAppWindow = function(appName, appLabel, appIcon) {
	if (appName === 'settings') { openSettingsWindow(); return }
	if (window.PFState?.airplane) return
	coreOpenAppWindow(appName, appLabel, appIcon)
}

// Ensure playerName comes from NUI
window.addEventListener('message', function(e) {
    const d = e.data || {}
    if (d.action === 'openTablet') {
        window.PFState = window.PFState || {}
        if (d.playerName) window.PFState.playerName = d.playerName
        if (d.about) window.PFState.about = d.about
        applySavedBackground && applySavedBackground()

        // Ensure Garbage app shows up if server omitted it
        setTimeout(function(){
            const exists = $('#app-grid .app-item[data-app="garbage"]').length > 0
            if (!exists) {
                $('#app-grid .app-item[data-app="gruppe6"]').after(`
                    <div class="app-item" data-app="garbage">
                        <div class="app-icon">🚚</div>
                        <div class="app-label">Garbage</div>
                    </div>
                `)
            }
        }, 0)
    }
    // Allow explicit name updates
    if (d.action === 'setPlayerName') setPFPlayerName(d.value || d.name || '');
});

// Also apply on initial load
window.addEventListener('load', applySavedBackground);

// Server push refresh
window.addEventListener('message', e=>{
    const d=e.data||{}
    if (d.action==='businessForceRefresh') fetchBusinessStatus()
})

// Gruppe6 UI state (local to NUI)
window.__G6_STATE__ = window.__G6_STATE__ || { searching:false, xp:0, level:1, contracts:[], activeContract:null, groups:{} };

// Define message handler before binding to window
function __g6_msg_handler(e) {
    const d = e.data || {};
    console.log('[Gruppe6] NUI Message:', d.action, d);
    
    if (d.action === 'gruppe6:init') {
        window.__G6_STATE__ = Object.assign(window.__G6_STATE__ || {}, d.state || {});
        console.log('[Gruppe6] State initialized:', window.__G6_STATE__);
        g6RefreshContractDisplay();
        if ($('.g6-tab-inline.active').data('g6-tab') === 'work') g6RenderWorkPane();
    } else if (d.action === 'gruppe6:contracts') {
        window.__G6_STATE__.contracts = d.contracts || [];
        console.log('[Gruppe6] Contracts updated:', window.__G6_STATE__.contracts);
        g6RefreshContractDisplay();
    } else if (d.action === 'gruppe6:activeContract') {
        window.__G6_STATE__.activeContract = d.contract || null;
        console.log('[Gruppe6] Active contract:', window.__G6_STATE__.activeContract);
        g6RefreshContractDisplay();
    } else if (d.action === 'gruppe6:updateXP') {
        window.__G6_STATE__.xp = Number(d.xp || 0);
        window.__G6_STATE__.level = Number(d.level || 1);
        console.log('[Gruppe6] XP updated:', window.__G6_STATE__.xp, 'Level:', window.__G6_STATE__.level);
        g6RefreshContractDisplay();
    } else if (d.action === 'gruppe6:groups') {
        window.__G6_STATE__.groups = d.groups || {};
        if ($('.g6-tab-inline.active').data('g6-tab') === 'work') g6RenderWorkPane();
    } else if (d.action === 'gruppe6:groupUpdate') {
        window.__G6_STATE__.currentGroup = d.group || null;
        console.log('[Gruppe6] Group updated:', window.__G6_STATE__.currentGroup);
        // Always render if on group tab
        if ($('.g6-tab-inline.active').data('g6-tab') === 'group') {
            g6RenderGroupPane();
        }
        // If group was just created (no members yet) and we're not on group tab, auto-switch
        if (d.group && d.group.members && d.group.members.length === 0) {
            $('.g6-tab-inline').removeClass('active');
            $('.g6-tab-inline[data-g6-tab="group"]').addClass('active');
            g6RenderGroupPane();
        }
    } else if (d.action === 'gruppe6:addInvite') {
        if (!window.__G6_STATE__.pendingInvites) window.__G6_STATE__.pendingInvites = [];
        // Check if invite already exists
        const existing = window.__G6_STATE__.pendingInvites.find(inv => inv.leaderId === d.invite.leaderId);
        if (!existing) {
            window.__G6_STATE__.pendingInvites.push(d.invite);
        }
        console.log('[Gruppe6] Invite added:', d.invite);
        if ($('.g6-tab-inline.active').data('g6-tab') === 'group') {
            g6RenderGroupPane();
        }
    } else if (d.action === 'gruppe6:upgradesPurchased') {
        window.__G6_STATE__.upgrades = d.upgrades || {};
        console.log('[Gruppe6] Upgrades updated:', window.__G6_STATE__.upgrades);
        if ($('.g6-tab-inline.active').data('g6-tab') === 'upgrades') g6RenderUpgradesPane();
    }
}

// Bind handler once globally (remove previous if any)
window.removeEventListener('message', __g6_msg_handler, true);
window.addEventListener('message', __g6_msg_handler, true);

// Define missing refresh function (called by renderGruppe6Window and message handler)
function g6RefreshContractDisplay() {
    const contracts = window.__G6_STATE__.contracts || [];
    const activeContract = window.__G6_STATE__.activeContract;
    const searching = window.__G6_STATE__.searching;

    // Left side shows status
    if (activeContract) {
        $('#g6-contract-card').show();
        $('#g6-waiting-card').hide();
        $('#g6-tier-badge').text('Tier ' + (activeContract.tier || '1'));
        $('#g6-vehicle-name').text(activeContract.vehicle || 'Speedo');
        $('#g6-contract-type').text(activeContract.contractType || 'Bank Delivery');
        $('#g6-bags').text(activeContract.bags || '12');
        $('#g6-payout').text('$' + (activeContract.payout || 0).toLocaleString());
        $('#g6-maxgroup').text(activeContract.maxGroup || '2');
        $('#g6-start-contract').text('End Contract Early').data('action', 'end');
    } else {
        $('#g6-contract-card').hide();
        $('#g6-waiting-card').show();
        $('#g6-waiting-subtitle').text(searching ? 'Searching for contracts...' : contracts.length > 0 ? 'Accept a contract from the list' : 'Go to Work tab to start searching');
    }

    // Right side shows available contracts when on contracts tab
    if ($('.g6-tab-inline.active').data('g6-tab') === 'contracts') {
        g6RenderContractsList(contracts);
    }

    // XP/Level bar
    const xp = Number(window.__G6_STATE__.xp || 0);
    const level = Number(window.__G6_STATE__.level || 1);
    $('#g6-level').text(level);

    const thresholds = [0, 1000, 5000, 10000, 15000, 30000];
    const cur = thresholds[level - 1] || 0;
    const next = thresholds[level] || thresholds[thresholds.length - 1];
    const inLevel = Math.max(0, xp - cur);
    const need = Math.max(1, next - cur);
    const pct = Math.min(100, (inLevel / need) * 100);
    $('#g6-xpbar-top').css('width', pct + '%');
    $('#g6-xp-text').text(`${inLevel} / ${need} XP`);
}

function g6RenderContractsList(contracts) {
    const activeContract = window.__G6_STATE__.activeContract;
    
    if (!contracts || contracts.length === 0) {
        $('#g6-right-pane').html(`
            <div class="g6-empty-state">
                <div style="font-size:48px;margin-bottom:16px;opacity:.3;">📋</div>
                <div style="color:#94a3b8;font-size:16px;">No contracts available</div>
                <div style="color:#64748b;font-size:14px;margin-top:8px;">Go to Work tab to start searching</div>
            </div>
        `);
        return;
    }

    const cards = contracts.slice(0,3).map((c, idx) => `
        <div class="g6-contract-card-available" data-contract-id="${idx}">
            <div class="g6-tier-badge">Tier ${c.tier || 1}</div>
            <div class="g6-vehicle-name">${c.vehicle || 'Speedo'}</div>
            <div class="g6-rank-badge">
                <span class="g6-wing left">🪽</span>
                <div class="g6-rank-circle"><span class="g6-rank-star">⭐</span></div>
                <span class="g6-wing right">🪽</span>
            </div>
            <div class="g6-info-rows">
                <div class="g6-info-row">
                    <span class="g6-info-label"><span class="g6-info-icon">📦</span> Type</span>
                    <span class="g6-info-value">${c.contractType || 'Bank Delivery'}</span>
                </div>
                <div class="g6-info-row">
                    <span class="g6-info-label"><span class="g6-info-icon">💼</span> Bags</span>
                    <span class="g6-info-value">${c.bags || 12}</span>
                </div>
                <div class="g6-info-row">
                    <span class="g6-info-label"><span class="g6-info-icon">💰</span> Payout</span>
                    <span class="g6-info-value">$${(c.payout || 0).toLocaleString()}</span>
                </div>
                <div class="g6-info-row">
                    <span class="g6-info-label"><span class="g6-info-icon">👥</span> Max Group</span>
                    <span class="g6-info-value">${c.maxGroup || 2}</span>
                </div>
            </div>
            <button class="g6-accept-contract-btn" data-contract-id="${idx}" ${activeContract ? 'disabled' : ''}>
                ${activeContract ? 'Contract Active' : 'Accept Contract'}
            </button>
        </div>
    `).join('');
    
    $('#g6-right-pane').html(`
        <div class="g6-contracts-list">
            <div class="g6-contracts-header">
                <div style="color:#e5e7eb;font-weight:700;font-size:18px;">Available Contracts</div>
                <div style="color:#94a3b8;font-size:13px;">${contracts.length} contract${contracts.length!==1?'s':''} available</div>
            </div>
            <div class="g6-contracts-row">
                ${cards}
            </div>
        </div>
    `);
}

// Render Gruppe6 app UI into its window
function renderGruppe6Window(appName) {
    const $content = $(`.app-window[data-app="${appName}"] .window-content`);
    if (!$content.length) return;

    $content.html(`
        <div class="g6-container">
            <div class="g6-top-bar">
                <div class="g6-welcome-inline">
                    <div class="g6-logo-small">🛡️</div>
                    <div class="g6-welcome-text-inline">
                        <div class="g6-welcome-title">Welcome</div>
                        <div class="g6-welcome-subtitle">Gruppe6</div>
                    </div>
                </div>

                <div class="g6-tabs-inline">
                    <div class="g6-tab-inline active" data-g6-tab="contracts"><span class="g6-tab-icon">📋</span><span>Contract Offers</span></div>
                    <div class="g6-tab-inline" data-g6-tab="work"><span class="g6-tab-icon">🛠️</span><span>Work</span></div>
                    <div class="g6-tab-inline" data-g6-tab="group"><span class="g6-tab-icon">👥</span><span>Group</span></div>
                    <div class="g6-tab-inline" data-g6-tab="upgrades"><span class="g6-tab-icon">⬆️</span><span>Upgrades</span></div>
                </div>

                <div class="g6-progression-inline">
                    <div class="g6-prog-header"><span class="g6-prog-icon">⚡</span><span class="g6-prog-title">Level <span id="g6-level">1</span></span></div>
                    <div class="g6-prog-bar-container"><div class="g6-prog-bar" id="g6-xpbar-top" style="width: 0%;"></div></div>
                    <div style="margin-top:4px;font-size:12px;color:#94a3b8;"><span id="g6-xp-text">0 / 1000 XP</span></div>
                </div>
            </div>

            <div class="g6-main-content">
                <div class="g6-left-col">
                    <div class="g6-contract-card" id="g6-contract-card" style="display:none;">
                        <div class="g6-tier-badge" id="g6-tier-badge">Tier 1</div>
                        <div class="g6-vehicle-name" id="g6-vehicle-name">Speedo</div>
                        <div class="g6-rank-badge"><span class="g6-wing left">🪽</span><div class="g6-rank-circle"><span class="g6-rank-star">⭐</span></div><span class="g6-wing right">🪽</span></div>
                        <div class="g6-info-rows">
                            <div class="g6-info-row"><span class="g6-info-label"><span class="g6-info-icon">📦</span> Type</span><span class="g6-info-value" id="g6-contract-type">Bank Delivery</span></div>
                            <div class="g6-info-row"><span class="g6-info-label"><span class="g6-info-icon">💼</span> Bags</span><span class="g6-info-value" id="g6-bags">12</span></div>
                            <div class="g6-info-row"><span class="g6-info-label"><span class="g6-info-icon">💰</span> Payout</span><span class="g6-info-value" id="g6-payout">$1,872</span></div>
                            <div class="g6-info-row"><span class="g6-info-label"><span class="g6-info-icon">👥</span> Max Group</span><span class="g6-info-value" id="g6-maxgroup">2</span></div>
                        </div>
                        <button class="g6-start-contract-btn" id="g6-start-contract">Start Contract</button>
                    </div>

                    <div class="g6-waiting-card" id="g6-waiting-card">
                        <div class="g6-waiting-icon">⏳</div>
                        <div class="g6-waiting-text">
                            <div class="g6-waiting-title">No Contract Available</div>
                            <div class="g6-waiting-subtitle" id="g6-waiting-subtitle">Start searching to find contracts</div>
                        </div>
                    </div>
                </div>

                <div class="g6-right-col" id="g6-right-pane"></div>
            </div>
        </div>
    `);

    g6BindHandlers();
    g6RefreshContractDisplay();
}

function g6RenderUpgradesPane() {
    const state = window.__G6_STATE__;
    const level = state.level || 1;
    const upgrades = state.upgrades || {};
    
    const upgradesConfig = [
        { id: 'tier_2', label: 'Vehicle Upgrade', description: 'Unlock Tier 2 contracts with better vehicles', cost: 10000, requiredLevel: 2, icon: '🚚' },
        { id: 'tier_3', label: 'Advanced Vehicle Upgrade', description: 'Unlock Tier 3 contracts with armored vehicles', cost: 25000, requiredLevel: 3, requiresTier2: true, icon: '🛡️' },
        { id: 'bag_capacity', label: 'Bag Capacity Upgrade', description: 'Increase maximum bags per location by 25%', cost: 15000, requiredLevel: 2, icon: '💰' }
    ];
    
    const upgradeCards = upgradesConfig.map(upgrade => {
        const owned = !!upgrades[upgrade.id];
        const canBuy = level >= upgrade.requiredLevel && (!upgrade.requiresTier2 || upgrades.tier_2);
        const statusText = owned ? 'Owned' : canBuy ? `$${upgrade.cost.toLocaleString()}` : `Requires Level ${upgrade.requiredLevel}${upgrade.requiresTier2 ? ' & Tier 2' : ''}`;
        const statusColor = owned ? '#10b981' : canBuy ? '#2563eb' : '#6b7280';
        
        return `
            <div class="g6-upgrade-card" style="background:rgba(255,255,255,0.05);border:1px solid rgba(255,255,255,0.1);border-radius:12px;padding:16px;margin-bottom:12px;">
                <div style="display:flex;justify-content:space-between;align-items:center;">
                    <div style="display:flex;align-items:center;gap:12px;">
                        <div style="font-size:32px;">${upgrade.icon}</div>
                        <div>
                            <div style="color:#e5e7eb;font-weight:700;font-size:16px;">${upgrade.label}</div>
                            <div style="color:#9ca3af;font-size:13px;margin-top:4px;">${upgrade.description}</div>
                        </div>
                    </div>
                    <button class="g6-buy-upgrade-btn" data-upgrade-id="${upgrade.id}" ${owned || !canBuy ? 'disabled' : ''} 
                        style="background:${statusColor};color:#fff;border:0;padding:10px 16px;border-radius:8px;cursor:${owned || !canBuy ? 'not-allowed' : 'pointer'};opacity:${owned || !canBuy ? '0.6' : '1'};">
                        ${statusText}
                    </button>
                </div>
            </div>
        `;
    }).join('');
    
    $('#g6-right-pane').html(`
        <div class="g6-card" style="background:rgba(255,255,255,0.05);border:1px solid rgba(255,255,255,0.1);border-radius:12px;padding:18px;">
            <div style="color:#e5e7eb;font-weight:700;font-size:18px;margin-bottom:16px;">Upgrades</div>
            ${upgradeCards}
        </div>
    `);
}

function g6RenderWorkPane() {
    const searching = !!window.__G6_STATE__.searching;
    $('#g6-right-pane').html(`
        <div class="g6-card" style="background:rgba(255,255,255,0.05);border:1px solid rgba(74, 217, 222,0.15);border-radius:16px;padding:24px;">
            <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:20px;">
                <div style="color:#f1f5f9;font-weight:700;font-size:20px;">Work Status</div>
                <div>
                    <button id="g6-start-search" class="g6-search-btn" style="${searching ? 'display:none;' : ''}">Start Searching</button>
                    <button id="g6-stop-search" class="g6-stop-search-btn" style="${searching ? '' : 'display:none;'}">Stop Searching</button>
                </div>
            </div>
            <div style="color:#94a3b8;font-size:15px;text-align:center;padding:40px 20px;">
                ${searching ? '🔍 Searching for contracts...' : '💼 Click "Start Searching" to find contracts'}
            </div>
        </div>
    `);
}

function g6RenderGroupPane() {
    console.log('[g6RenderGroupPane] Called');
    const state = window.__G6_STATE__ || {};
    const group = state.currentGroup;
    const pendingInvites = state.pendingInvites || [];
    console.log('[g6RenderGroupPane] Current group:', group);
    console.log('[g6RenderGroupPane] Pending invites:', pendingInvites);
    console.log('[g6RenderGroupPane] Player ID:', state.playerId);
    
    if (!group) {
        // No group - show create option and pending invites
        let invitesHTML = '';
        if (pendingInvites.length > 0) {
            invitesHTML = `
                <div style="margin-top:24px;">
                    <div style="color:#f1f5f9;font-weight:700;font-size:18px;margin-bottom:16px;">📬 Pending Invites</div>
                    ${pendingInvites.map(invite => `
                        <div style="background:rgba(255,255,255,0.06);border:1px solid rgba(74,217,222,0.3);border-radius:12px;padding:16px;margin-bottom:12px;">
                            <div style="color:#f1f5f9;font-weight:700;margin-bottom:8px;">${invite.leaderName} (ID: ${invite.leaderId})</div>
                            <div style="display:flex;gap:10px;">
                                <button class="g6-accept-invite" data-leader-id="${invite.leaderId}" style="flex:1;background:linear-gradient(135deg,#10b981,#059669);color:#fff;border:0;padding:10px;border-radius:8px;cursor:pointer;font-weight:700;">Accept</button>
                                <button class="g6-decline-invite" data-leader-id="${invite.leaderId}" style="flex:1;background:linear-gradient(135deg,#ef4444,#dc2626);color:#fff;border:0;padding:10px;border-radius:8px;cursor:pointer;font-weight:700;">Decline</button>
                            </div>
                        </div>
                    `).join('')}
                </div>
            `;
        }
        
        $('#g6-right-pane').html(`
            <div class="g6-card" style="background:linear-gradient(135deg, rgba(74, 217, 222,0.08), rgba(74, 217, 222,0.04));border:2px solid rgba(74, 217, 222,0.3);border-radius:20px;padding:32px;text-align:center;">
                <div style="font-size:64px;margin-bottom:20px;">👥</div>
                <div style="color:#f1f5f9;font-weight:700;font-size:22px;margin-bottom:12px;">No Active Party</div>
                <div style="color:#94a3b8;font-size:15px;margin-bottom:28px;">Create a party to invite members and share contract rewards</div>
                <button id="g6-create-group" style="background:linear-gradient(135deg, #4ad9de, #22d3ee);color:#0a0e1a;border:0;padding:16px 32px;border-radius:14px;font-size:16px;font-weight:800;cursor:pointer;text-transform:uppercase;letter-spacing:1px;box-shadow:0 8px 24px rgba(74,217,222,0.4);transition:all 0.3s;">
                    Create Party
                </button>
                ${invitesHTML}
            </div>
        `);
        return;
    }
    
    // Has group - show management UI
    // Check both exact match and type-converted match for leader detection
    const isLeader = (group.leader === state.playerId) || (String(group.leader) === String(state.playerId)) || (Number(group.leader) === Number(state.playerId));
    const members = group.members || [];
    const splits = group.payoutSplits || {};
    
    console.log('[g6RenderGroupPane] Is leader:', isLeader, 'Leader ID:', group.leader, '(type:', typeof group.leader, ') My ID:', state.playerId, '(type:', typeof state.playerId, ')');
    console.log('[g6RenderGroupPane] Members:', members);
    console.log('[g6RenderGroupPane] Splits:', splits);
    
    let membersHTML = '';
    
    // Always show leader first
    const leaderSplit = splits[group.leader] || 100;
    
    if (isLeader) {
        // Leader view - editable split
        membersHTML += `
            <div style="background:rgba(74,217,222,0.15);border:2px solid rgba(74,217,222,0.4);border-radius:12px;padding:16px;margin-bottom:12px;display:flex;justify-content:space-between;align-items:center;">
                <div style="display:flex;align-items:center;gap:14px;">
                    <div style="width:44px;height:44px;background:linear-gradient(135deg,#fbbf24,#f59e0b);border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:20px;">👑</div>
                    <div>
                        <div style="color:#f1f5f9;font-weight:700;font-size:15px;">You <span style="color:#fbbf24;font-size:13px;">(Party Leader)</span></div>
                        <div style="color:#94a3b8;font-size:13px;">ID: ${state.playerId}</div>
                    </div>
                </div>
                <div style="display:flex;align-items:center;gap:12px;">
                    <input type="number" class="g6-split-input" data-member-id="${state.playerId}" value="${leaderSplit}" min="0" max="100" 
                        style="width:70px;padding:8px;border-radius:8px;border:1px solid rgba(251,191,36,0.4);background:rgba(251,191,36,0.15);color:#fbbf24;text-align:center;font-weight:700;">
                    <span style="color:#fbbf24;font-weight:700;">%</span>
                </div>
            </div>
        `;
    } else {
        // Member view - show leader (read-only)
        const leaderName = group.leaderName || 'Party Leader';
        membersHTML += `
            <div style="background:rgba(74,217,222,0.08);border:1px solid rgba(251,191,36,0.3);border-radius:12px;padding:16px;margin-bottom:12px;display:flex;justify-content:space-between;align-items:center;">
                <div style="display:flex;align-items:center;gap:14px;">
                    <div style="width:44px;height:44px;background:linear-gradient(135deg,#fbbf24,#f59e0b);border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:20px;">👑</div>
                    <div>
                        <div style="color:#f1f5f9;font-weight:700;font-size:15px;">${leaderName} <span style="color:#fbbf24;font-size:13px;">(Leader)</span></div>
                        <div style="color:#94a3b8;font-size:13px;">ID: ${group.leader}</div>
                    </div>
                </div>
                <div style="color:#fbbf24;font-weight:700;font-size:18px;">${leaderSplit}%</div>
            </div>
        `;
    }
    
    // Then show other members
    members.forEach(member => {
        const split = splits[member.id] || 25;
        const isYou = (member.id == state.playerId);
        const bgColor = isYou ? 'rgba(74,217,222,0.12)' : 'rgba(255,255,255,0.06)';
        const borderColor = isYou ? 'rgba(74,217,222,0.4)' : 'rgba(74,217,222,0.2)';
        
        membersHTML += `
            <div style="background:${bgColor};border:1px solid ${borderColor};border-radius:12px;padding:16px;margin-bottom:12px;display:flex;justify-content:space-between;align-items:center;">
                <div style="display:flex;align-items:center;gap:14px;">
                    <div style="width:44px;height:44px;background:linear-gradient(135deg,#4ad9de,#22d3ee);border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:20px;">👤</div>
                    <div>
                        <div style="color:#f1f5f9;font-weight:700;font-size:15px;">${member.name}${isYou ? ' <span style="color:#4ad9de;font-size:13px;">(You)</span>' : ''}</div>
                        <div style="color:#94a3b8;font-size:13px;">ID: ${member.id}</div>
                    </div>
                </div>
                <div style="display:flex;align-items:center;gap:12px;">
                    ${isLeader ? `
                        <input type="number" class="g6-split-input" data-member-id="${member.id}" value="${split}" min="0" max="100" 
                            style="width:70px;padding:8px;border-radius:8px;border:1px solid rgba(74,217,222,0.3);background:rgba(255,255,255,0.08);color:#f1f5f9;text-align:center;font-weight:700;">
                        <span style="color:#4ad9de;font-weight:700;">%</span>
                        <button class="g6-kick-member" data-member-id="${member.id}" 
                            style="background:linear-gradient(135deg,#ef4444,#dc2626);color:#fff;border:0;padding:8px 14px;border-radius:8px;cursor:pointer;font-weight:700;">Kick</button>
                    ` : `
                        <span style="color:#4ad9de;font-weight:700;font-size:18px;">${split}%</span>
                    `}
                </div>
            </div>
        `;
    });
    
    // Pending invites HTML (show even if in a group)
    let invitesHTML = '';
    if (pendingInvites.length > 0) {
        invitesHTML = `
            <div style="background:rgba(251,191,36,0.1);border:2px solid rgba(251,191,36,0.4);border-radius:12px;padding:18px;margin-bottom:20px;">
                <div style="color:#fbbf24;font-weight:700;font-size:16px;margin-bottom:12px;">📬 Pending Party Invites</div>
                <div style="color:#fef3c7;font-size:13px;margin-bottom:14px;">You have ${pendingInvites.length} pending invitation${pendingInvites.length > 1 ? 's' : ''}. Accepting will leave your current party.</div>
                ${pendingInvites.map(invite => `
                    <div style="background:rgba(255,255,255,0.08);border:1px solid rgba(251,191,36,0.3);border-radius:10px;padding:14px;margin-bottom:10px;">
                        <div style="color:#f1f5f9;font-weight:700;margin-bottom:8px;">Invitation from ${invite.leaderName} (ID: ${invite.leaderId})</div>
                        <div style="display:flex;gap:10px;">
                            <button class="g6-accept-invite" data-leader-id="${invite.leaderId}" style="flex:1;background:linear-gradient(135deg,#10b981,#059669);color:#fff;border:0;padding:10px;border-radius:8px;cursor:pointer;font-weight:700;transition:all 0.3s;">✓ Accept</button>
                            <button class="g6-decline-invite" data-leader-id="${invite.leaderId}" style="flex:1;background:linear-gradient(135deg,#ef4444,#dc2626);color:#fff;border:0;padding:10px;border-radius:8px;cursor:pointer;font-weight:700;transition:all 0.3s;">✗ Decline</button>
                        </div>
                    </div>
                `).join('')}
            </div>
        `;
    }
    
    $('#g6-right-pane').html(`
        <div class="g6-card" style="background:rgba(255,255,255,0.05);border:2px solid rgba(74,217,222,0.25);border-radius:20px;padding:28px;">
            ${invitesHTML}
            
            <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:24px;">
                <div>
                    <div style="color:#f1f5f9;font-weight:700;font-size:20px;margin-bottom:4px;">${isLeader ? '👑 Your Party' : '👥 Party Members'}</div>
                    <div style="color:#94a3b8;font-size:13px;">${members.length}/${4} members</div>
                </div>
                ${isLeader ? `
                    <button id="g6-disband-group" style="background:linear-gradient(135deg,#ef4444,#dc2626);color:#fff;border:0;padding:10px 18px;border-radius:10px;cursor:pointer;font-weight:700;">
                        Disband Party
                    </button>
                ` : `
                    <button id="g6-leave-group" style="background:linear-gradient(135deg,#6b7280,#4b5563);color:#fff;border:0;padding:10px 18px;border-radius:10px;cursor:pointer;font-weight:700;">
                        Leave Party
                    </button>
                `}
            </div>
            
            <div style="color:#f1f5f9;font-weight:700;font-size:16px;margin-bottom:14px;">Party Members</div>
            ${membersHTML || '<div style="color:#94a3b8;text-align:center;padding:20px;">No members yet</div>'}
            
            ${isLeader ? `
                <div style="background:rgba(74,217,222,0.1);border:1px solid rgba(74,217,222,0.3);border-radius:12px;padding:16px;margin-top:20px;">
                    <div style="color:#f1f5f9;font-weight:700;font-size:15px;margin-bottom:12px;">✉️ Invite Player by Server ID</div>
                    <div style="color:#94a3b8;font-size:13px;margin-bottom:12px;">Enter the player's in-game server ID to send them a party invite</div>
                    <div style="display:flex;gap:10px;">
                        <input type="number" id="g6-invite-id" placeholder="Enter player server ID (e.g., 1, 2, 3...)" 
                            style="flex:1;padding:12px;border-radius:10px;border:1px solid rgba(74,217,222,0.4);background:rgba(255,255,255,0.08);color:#f1f5f9;font-size:14px;">
                        <button id="g6-invite-btn" style="background:linear-gradient(135deg,#4ad9de,#22d3ee);color:#0a0e1a;border:0;padding:12px 24px;border-radius:10px;cursor:pointer;font-weight:800;transition:all 0.3s;">
                            Send Invite
                        </button>
                    </div>
                </div>
            ` : ''}
        </div>
    `);
    
    console.log('[g6RenderGroupPane] HTML rendered, checking for invite button:', $('#g6-invite-btn').length);
    
    // Rebind handlers after rendering
    g6BindHandlers();
    
    console.log('[g6RenderGroupPane] Handlers bound');
}

function g6RenderGroupsList(groups) {
    const container = $('#g6-members'); 
    if (!container.length) return;
    
    const items = Object.keys(groups).map(id => {
        const g = groups[id]; 
        const members = g.members || {};
        const rows = Object.keys(members).map(cid => {
            const m = members[cid]; 
            const cut = Number(m.cut || 0);
            return `
                <div style="display:flex;align-items:center;gap:10px;margin-bottom:8px;">
                    <div style="flex:1;color:#e5e7eb;">${m.name} <span style="color:#64748b;">(${cid})</span></div>
                    <input type="number" min="0" max="100" value="${cut}" data-group="${id}" data-cid="${cid}" class="g6-cut" style="width:80px;padding:6px 8px;border-radius:8px;border:1px solid rgba(255,255,255,0.18);background:rgba(255,255,255,0.08);color:#fff;">
                    <span style="color:#9ca3b8;">%</span>
                    <button class="g6-leave" data-group="${id}" data-cid="${cid}" style="background:#ef4444;color:#fff;border:0;padding:6px 10px;border-radius:8px;cursor:pointer;">Remove</button>
                </div>
            `;
        }).join('');
        
        const total = Object.keys(members).reduce((s,cid)=> s + (Number(members[cid].cut||0)), 0);
        return `
            <div style="padding:12px;border-radius:10px;background:rgba(255,255,255,0.04);border:1px solid rgba(255,255,255,0.1);margin-bottom:12px;">
                <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;">
                    <div style="color:#e5e7eb;">Group #${id} ${g.open ? '(Open)' : ''}</div>
                    <div style="color:${total>100?'#ef4444':'#22d3ee'};font-weight:600;">Total: ${total}%</div>
                </div>
                ${rows || '<div style="color:#94a3b8;">No members</div>'}
            </div>
        `;
    }).join('');
    
    container.html(items || '<div style="color:#94a3b8;">No groups yet.</div>');
}

function g6BindHandlers() {
    $(document).off('click.g6tabs').on('click.g6tabs', '.g6-tab-inline', function(){
        console.log('[g6BindHandlers] Tab clicked');
        $('.g6-tab-inline').removeClass('active');
        $(this).addClass('active');
        const tab = $(this).data('g6-tab');
        console.log('[g6BindHandlers] Switching to tab:', tab);
        if (tab === 'work') g6RenderWorkPane();
        if (tab === 'group') g6RenderGroupPane();
        if (tab === 'contracts') g6RenderContractsList(window.__G6_STATE__.contracts || []);
        if (tab === 'upgrades') g6RenderUpgradesPane();
        g6RefreshContractDisplay();
    });

    $(document).off('click.g6start').on('click.g6start', '#g6-start-search', function(){
        $.post('https://pf-jobsystem/gruppe6:startSearch', JSON.stringify({}), ()=> {
            window.__G6_STATE__.searching = true;
            $('#g6-start-search').hide(); $('#g6-stop-search').show();
            g6RefreshContractDisplay();
        });
    });
    
    $(document).off('click.g6stop').on('click.g6stop', '#g6-stop-search', function(){
        $.post('https://pf-jobsystem/gruppe6:stopSearch', JSON.stringify({}), ()=> {
            window.__G6_STATE__.searching = false;
            $('#g6-start-search').show(); $('#g6-stop-search').hide();
            g6RefreshContractDisplay();
        });
    });

    $(document).off('click.g6create').on('click.g6create', '#g6-create-group', function(){
        console.log('[g6BindHandlers] Create group button clicked');
        $.post('https://pf-jobsystem/gruppe6:createGroup', JSON.stringify({}), function(resp){
            console.log('[g6BindHandlers] Create group response:', resp);
            // Server will send groupUpdate message which auto-switches tab and renders
        });
    });
    
    $(document).off('click.g6disband').on('click.g6disband', '#g6-disband-group', function(){
        $.post('https://pf-jobsystem/gruppe6:disbandGroup', JSON.stringify({}), function(){
            setTimeout(() => g6RenderGroupPane(), 500);
        });
    });
    
    $(document).off('click.g6leave').on('click.g6leave', '#g6-leave-group', function(){
        $.post('https://pf-jobsystem/gruppe6:leaveGroup', JSON.stringify({}), function(){
            setTimeout(() => g6RenderGroupPane(), 500);
        });
    });
    
    $(document).off('click.g6kick').on('click.g6kick', '.g6-kick-member', function(){
        const targetId = $(this).data('member-id');
        $.post('https://pf-jobsystem/gruppe6:kickMember', JSON.stringify({ targetId }), function(){
            setTimeout(() => g6RenderGroupPane(), 500);
        });
    });
    
    $(document).off('change.g6splitchange').on('change.g6splitchange', '.g6-split-input', function(){
        const targetId = $(this).data('member-id');
        const percentage = parseInt($(this).val(), 10);
        $.post('https://pf-jobsystem/gruppe6:updateSplit', JSON.stringify({ targetId, percentage }), function(){
            setTimeout(() => g6RenderGroupPane(), 500);
        });
    });
    
    $(document).off('click.g6buyupgrade').on('click.g6buyupgrade', '.g6-buy-upgrade-btn', function(){
        if ($(this).is(':disabled')) return;
        const upgradeId = $(this).data('upgrade-id');
        $.post('https://pf-jobsystem/gruppe6:purchaseUpgrade', JSON.stringify({ upgradeId }), ()=> {
            // Will refresh via event
        });
    });
    
    $(document).off('click.g6invite').on('click.g6invite', '#g6-invite-btn', function(){
        const targetId = parseInt($('#g6-invite-id').val(), 10);
        if (!targetId || isNaN(targetId)) return;
        $.post('https://pf-jobsystem/gruppe6:invitePlayer', JSON.stringify({ targetId }), function(){
            $('#g6-invite-id').val('');
            setTimeout(() => g6RenderGroupPane(), 500);
        });
    });
    
    $(document).off('click.g6acceptinv').on('click.g6acceptinv', '.g6-accept-invite', function(){
        const leaderId = $(this).data('leader-id');
        $.post('https://pf-jobsystem/gruppe6:acceptInvite', JSON.stringify({ leaderId }), function(){
            // Remove invite from pending list
            if (window.__G6_STATE__.pendingInvites) {
                window.__G6_STATE__.pendingInvites = window.__G6_STATE__.pendingInvites.filter(inv => inv.leaderId !== leaderId);
            }
            setTimeout(() => g6RenderGroupPane(), 500);
        });
    });
    
    $(document).off('click.g6declineinv').on('click.g6declineinv', '.g6-decline-invite', function(){
        const leaderId = $(this).data('leader-id');
        $.post('https://pf-jobsystem/gruppe6:declineInvite', JSON.stringify({ leaderId }), function(){
            // Remove invite from pending list
            if (window.__G6_STATE__.pendingInvites) {
                window.__G6_STATE__.pendingInvites = window.__G6_STATE__.pendingInvites.filter(inv => inv.leaderId !== leaderId);
            }
            setTimeout(() => g6RenderGroupPane(), 500);
        });
    });

    $(document).off('change.g6split').on('change.g6split', '.g6-cut', function(){
        const gid = $(this).data('group'); 
        const cid = $(this).data('cid'); 
        const val = Math.max(0, Math.min(100, parseInt($(this).val(),10)||0));
        const rows = $('.g6-cut[data-group="'+gid+'"]');
        let sumOther = 0;
        rows.each(function(){
            if ($(this).data('cid') !== cid) sumOther += Math.max(0, Math.min(100, parseInt($(this).val(),10)||0));
        });
        if (sumOther + val > 100) { alert('Total exceeds 100%'); $(this).val(Math.max(0, 100 - sumOther)); return; }
        $.post('https://pf-jobsystem/gruppe6:setSplit', JSON.stringify({ id: gid, cid, cut: val }), function(ok){
            g6RenderWorkPane();
        });
    });

    $(document).off('click.g6leave').on('click.g6leave', '.g6-leave', function(){
        const gid = $(this).data('group'); 
        const cid = $(this).data('cid');
        $.post('https://pf-jobsystem/gruppe6:leave', JSON.stringify({ id: gid, cid }), function(ok){
            g6RenderWorkPane();
        });
    });

    // ACCEPT CONTRACT HANDLER (FIXED: Only send via NUI callback, not direct POST)
    let acceptInProgress = false;
    
    $(document).off('click.g6accept').on('click.g6accept', '.g6-accept-contract-btn', function(e){
        e.preventDefault();
        e.stopPropagation();
        
        // FIXED: Check if accept is in progress
        if (acceptInProgress) {
            console.log('[Gruppe6 NUI] ❌ Accept already in progress, ignoring');
            return;
        }
        
        // Check if button is disabled
        if ($(this).is(':disabled') || $(this).prop('disabled')) {
            console.log('[Gruppe6 NUI] Button is disabled, ignoring');
            return;
        }
        
        const contractId = parseInt($(this).data('contract-id'));
        console.log('[Gruppe6 NUI] ✅ Accept button clicked, contractId:', contractId);
        
        if (isNaN(contractId) || contractId < 0) {
            console.error('[Gruppe6 NUI] ❌ Invalid contractId:', contractId);
            return;
        }
        
        // FIXED: Set flag and disable ALL accept buttons immediately
        acceptInProgress = true;
        $('.g6-accept-contract-btn').prop('disabled', true).text('Processing...');
        
        console.log('[Gruppe6 NUI] 📤 Triggering client callback (NOT direct POST)');
        
        // FIXED: Use NUI callback instead of direct POST (lets client handle it)
        // This prevents double-sending because client has the lock
        fetch(`https://${GetParentResourceName()}/gruppe6:acceptContract`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify({ contractId: contractId })
        }).then(resp => resp.json()).then(data => {
            console.log('[Gruppe6 NUI] ✅ Client callback response:', data);
        }).catch(err => {
            console.error('[Gruppe6 NUI] ❌ Accept failed:', err);
            // Re-enable buttons on failure
            $('.g6-accept-contract-btn').prop('disabled', false).text('Accept Contract');
            acceptInProgress = false;
        });
        
        // Clear flag after 5 seconds
        setTimeout(function() {
            acceptInProgress = false;
            console.log('[Gruppe6 NUI] 🔓 Accept flag cleared');
        }, 5000);
    });

    $(document).off('click.g6startc').on('click.g6startc', '#g6-start-contract', function(){
        const action = $(this).data('action');
        if (action === 'end') {
            $.post('https://pf-jobsystem/gruppe6:endContract', JSON.stringify({}), ()=>{});
        } else {
            $.post('https://pf-jobsystem/gruppe6:acceptContract', JSON.stringify({}), ()=>{});
        }
    });
}

// Keep searching on minimize/close: do not change server search state
const __origClose = window.closeWindow;
window.closeWindow = function(appName) {
    if (appName === 'business') stopBusinessAutoRefresh && stopBusinessAutoRefresh();
    __origClose(appName);
};

const __origMinimize = window.minimizeWindow;
window.minimizeWindow = function(appName) {
    __origMinimize(appName);
};

// ===== JOB SCOREBOARD (76b-ui EXACT ANIMATION) =====
(function() {
    var mainElement = document.getElementById("scoreboard-main");
    var titleElement = document.getElementById("scoreboard-title");
    var subtitleElement = document.getElementById("scoreboard-subtitle");
    var progressElement = document.getElementById("scoreboard-progress");

    // Start hidden off-screen
    mainElement.style.display = "none";

    window.addEventListener("message", function(event) {
        var data = event.data || {};

        if (data.action === "scoreboard_open" || data.action === "scoreboard_update") {
            // Update content
            if (data.title) titleElement.innerHTML = data.title;
            if (data.subtitle !== undefined) subtitleElement.innerHTML = data.subtitle;
            if (data.progress !== undefined) progressElement.innerHTML = data.progress;

            // Show if opening
            if (data.action === "scoreboard_open") {
                mainElement.style.display = "block";
                $('#scoreboard-main').animate({ 'margin-left': '2%' }, 500);
            }
        } else if (data.action === "scoreboard_close") {
            // Animate out (exact 76b-ui behavior)
            $('#scoreboard-main').animate({ 'margin-left': '-30%' }, 500);
            setTimeout(function() {
                mainElement.style.display = "none";
            }, 500);
        }
    });
})();

// ===== JOB SCOREBOARD (76b-ui style) =====
window.addEventListener('message', function(e) {
    const d = e.data || {};
    
    if (d.action === 'scoreboard_open' || d.action === 'scoreboard_update') {
        const scoreboard = document.getElementById('scoreboard-main');
        const title = document.getElementById('scoreboard-title');
        const subtitle = document.getElementById('scoreboard-subtitle');
        const progress = document.getElementById('scoreboard-progress');
        
        if (d.title) title.innerHTML = d.title;
        if (d.subtitle !== undefined) subtitle.innerHTML = d.subtitle;
        if (d.progress !== undefined) progress.innerHTML = d.progress;
        
        if (d.action === 'scoreboard_open') {
            scoreboard.style.display = 'block';
        }
    } else if (d.action === 'scoreboard_close') {
        const scoreboard = document.getElementById('scoreboard-main');
        scoreboard.style.display = 'none';
    }
});

// ===== Garbage UI state and renderer =====
window.__GARBAGE_STATE__ = window.__GARBAGE_STATE__ || { xp:0, level:1, carrying:false, truckNetId:null, group:null }

function renderGarbageWindow(appName){
    const $content = $(`.app-window[data-app="${appName}"] .window-content`)
    if (!$content.length) return
    $content.html(`
        <div class="g6-container">
            <div class="g6-top-bar">
                <div class="g6-welcome-inline">
                    <div class="g6-logo-small">🚚</div>
                    <div class="g6-welcome-text-inline">
                        <div class="g6-welcome-title">Welcome</div>
                        <div class="g6-welcome-subtitle">Garbage</div>
                    </div>
                </div>
                <div class="g6-tabs-inline">
                    <div class="g6-tab-inline active" data-garbage-tab="work"><span class="g6-tab-icon">🛠️</span><span>Work</span></div>
                    <div class="g6-tab-inline" data-garbage-tab="group"><span class="g6-tab-icon">👥</span><span>Group</span></div>
                    <div class="g6-tab-inline" data-garbage-tab="upgrades"><span class="g6-tab-icon">⬆️</span><span>Upgrades</span></div>
                </div>
                <div class="g6-progression-inline">
                    <div class="g6-prog-header"><span class="g6-prog-icon">⚡</span><span class="g6-prog-title">Level <span id="garbage-level">1</span></span></div>
                    <div class="g6-prog-bar-container"><div class="g6-prog-bar" id="garbage-xpbar" style="width:0%;"></div></div>
                    <div style="margin-top:4px;font-size:12px;color:#94a3b8;"><span id="garbage-xp-text">0 / 1000 XP</span></div>
                </div>
            </div>
            <div class="g6-main-content">
                <div class="g6-left-col">
                    <div class="g6-contract-card" id="garbage-work-card">
                        <div class="g6-tier-badge">Job</div>
                        <div class="g6-vehicle-name">Trashmaster</div>
                        <div class="g6-info-rows">
                            <div class="g6-info-row"><span class="g6-info-label"><span class="g6-info-icon">🚚</span> Vehicle</span><span class="g6-info-value">Trashmaster</span></div>
                            <div class="g6-info-row"><span class="g6-info-label"><span class="g6-info-icon">📦</span> Carrying</span><span class="g6-info-value" id="garbage-carrying">No</span></div>
                        </div>
                        <button class="g6-start-contract-btn" id="garbage-start-job">Start Job</button>
                    </div>
                </div>
                <div class="g6-right-col" id="garbage-right-pane"></div>
            </div>
        </div>
    `)

    bindGarbageHandlers()
    refreshGarbageDisplay()
}

function refreshGarbageDisplay(){
    const xp=Number(window.__GARBAGE_STATE__.xp||0), level=Number(window.__GARBAGE_STATE__.level||1)
    $('#garbage-level').text(level)
    const thresholds=[0,1000,3000,7000,12000,20000]
    const cur=thresholds[level-1]||0, next=thresholds[level]||thresholds[thresholds.length-1]
    const inLevel=Math.max(0,xp-cur), need=Math.max(1,next-cur)
    const pct=Math.min(100,(inLevel/need)*100)
    $('#garbage-xpbar').css('width', pct+'%')
    $('#garbage-xp-text').text(`${inLevel} / ${need} XP`)
    $('#garbage-carrying').text(window.__GARBAGE_STATE__.carrying ? 'Yes' : 'No')
}

function garbageRenderGroupPane() {
    console.log('[garbageRenderGroupPane] Called');
    const state = window.__GARBAGE_STATE__ || {};
    const group = state.currentGroup;
    const pendingInvites = state.pendingInvites || [];
    console.log('[garbageRenderGroupPane] Current group:', group);
    console.log('[garbageRenderGroupPane] Pending invites:', pendingInvites);
    console.log('[garbageRenderGroupPane] Player ID:', state.playerId);
    
    if (!group) {
        // No group - show create option and pending invites
        let invitesHTML = '';
        if (pendingInvites.length > 0) {
            invitesHTML = `
                <div style="margin-top:24px;">
                    <div style="color:#f1f5f9;font-weight:700;font-size:18px;margin-bottom:16px;">📬 Pending Invites</div>
                    ${pendingInvites.map(invite => `
                        <div style="background:rgba(255,255,255,0.06);border:1px solid rgba(74,217,222,0.3);border-radius:12px;padding:16px;margin-bottom:12px;">
                            <div style="color:#f1f5f9;font-weight:700;margin-bottom:8px;">${invite.leaderName} (ID: ${invite.leaderId})</div>
                            <div style="display:flex;gap:10px;">
                                <button class="garbage-accept-invite" data-leader-id="${invite.leaderId}" style="flex:1;background:linear-gradient(135deg,#10b981,#059669);color:#fff;border:0;padding:10px;border-radius:8px;cursor:pointer;font-weight:700;">Accept</button>
                                <button class="garbage-decline-invite" data-leader-id="${invite.leaderId}" style="flex:1;background:linear-gradient(135deg,#ef4444,#dc2626);color:#fff;border:0;padding:10px;border-radius:8px;cursor:pointer;font-weight:700;">Decline</button>
                            </div>
                        </div>
                    `).join('')}
                </div>
            `;
        }
        
        $('#garbage-right-pane').html(`
            <div class="g6-card" style="background:rgba(255,255,255,0.05);border:1px solid rgba(74,217,222,0.15);border-radius:16px;padding:24px;">
                <div style="color:#f1f5f9;font-weight:700;font-size:20px;margin-bottom:20px;text-align:center;">👥 Party Management</div>
                <div style="text-align:center;padding:20px 0;">
                    <div style="font-size:48px;margin-bottom:16px;">🚚</div>
                    <div style="color:#94a3b8;font-size:15px;margin-bottom:24px;">Create a party to work together and split payouts</div>
                    <button id="garbage-create-group" class="g6-start-contract-btn" style="width:auto;padding:12px 32px;">Create Party</button>
                </div>
                ${invitesHTML}
            </div>
        `);
        return;
    }
    
    // Has group - show members and controls
    const isLeader = group.leader === state.playerId;
    const members = group.members || [];
    const splits = group.payoutSplits || {};
    
    let membersHTML = '';
    // Show leader first
    const leaderSplit = splits[group.leader] || 100;
    membersHTML += `
        <div style="background:rgba(74,217,222,0.15);border:1px solid rgba(74,217,222,0.3);border-radius:12px;padding:16px;margin-bottom:12px;">
            <div style="display:flex;justify-content:space-between;align-items:center;">
                <div>
                    <div style="color:#f1f5f9;font-weight:700;font-size:16px;">👑 Leader (ID: ${group.leader})</div>
                    <div style="color:#94a3b8;font-size:13px;margin-top:4px;">Party Leader</div>
                </div>
                <div style="display:flex;align-items:center;gap:12px;">
                    <div style="color:#10b981;font-weight:700;font-size:18px;">${leaderSplit}%</div>
                    ${isLeader ? `<input type="number" class="garbage-split-input" data-target-id="${group.leader}" value="${leaderSplit}" min="0" max="100" style="width:70px;padding:8px;border:1px solid rgba(255,255,255,0.2);background:rgba(0,0,0,0.3);color:#fff;border-radius:6px;text-align:center;">` : ''}
                </div>
            </div>
        </div>
    `;
    
    // Show members (handle both array of IDs and array of {id, name} objects)
    members.forEach(member => {
        const memberId = (typeof member === 'object' && member.id) ? member.id : member;
        const memberName = (typeof member === 'object' && member.name) ? member.name : `Player ${memberId}`;
        const memberSplit = splits[memberId] || 0;
        membersHTML += `
            <div style="background:rgba(255,255,255,0.06);border:1px solid rgba(255,255,255,0.1);border-radius:12px;padding:16px;margin-bottom:12px;">
                <div style="display:flex;justify-content:space-between;align-items:center;">
                    <div>
                        <div style="color:#f1f5f9;font-weight:700;font-size:16px;">👤 ${memberName}</div>
                        <div style="color:#94a3b8;font-size:13px;margin-top:4px;">ID: ${memberId} • Party Member</div>
                    </div>
                    <div style="display:flex;align-items:center;gap:12px;">
                        <div style="color:#10b981;font-weight:700;font-size:18px;">${memberSplit}%</div>
                        ${isLeader ? `<input type="number" class="garbage-split-input" data-target-id="${memberId}" value="${memberSplit}" min="0" max="100" style="width:70px;padding:8px;border:1px solid rgba(255,255,255,0.2);background:rgba(0,0,0,0.3);color:#fff;border-radius:6px;text-align:center;">` : ''}
                        ${isLeader ? `<button class="garbage-kick-member" data-target-id="${memberId}" style="background:#ef4444;color:#fff;border:0;padding:8px 12px;border-radius:6px;cursor:pointer;font-weight:700;">Kick</button>` : ''}
                    </div>
                </div>
            </div>
        `;
    });
    
    let inviteHTML = '';
    if (isLeader) {
        inviteHTML = `
            <div style="margin-top:24px;background:rgba(255,255,255,0.05);border:1px solid rgba(74,217,222,0.2);border-radius:12px;padding:20px;">
                <div style="color:#f1f5f9;font-weight:700;font-size:16px;margin-bottom:16px;">✉️ Invite Player</div>
                <div style="display:flex;gap:10px;">
                    <input type="number" id="garbage-invite-id" placeholder="Enter Player ID" style="flex:1;padding:12px;border:1px solid rgba(255,255,255,0.2);background:rgba(0,0,0,0.3);color:#fff;border-radius:8px;">
                    <button id="garbage-send-invite" style="background:linear-gradient(135deg,#2563eb,#1d4ed8);color:#fff;border:0;padding:12px 24px;border-radius:8px;cursor:pointer;font-weight:700;">Send Invite</button>
                </div>
            </div>
        `;
    }
    
    $('#garbage-right-pane').html(`
        <div class="g6-card" style="background:rgba(255,255,255,0.05);border:1px solid rgba(74,217,222,0.15);border-radius:16px;padding:24px;">
            <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:20px;">
                <div style="color:#f1f5f9;font-weight:700;font-size:20px;">👥 Party (${1 + members.length} members)</div>
                <div style="display:flex;gap:10px;">
                    ${isLeader ? `<button id="garbage-disband-group" style="background:#dc2626;color:#fff;border:0;padding:10px 16px;border-radius:8px;cursor:pointer;font-weight:700;">Disband</button>` : ''}
                    <button id="garbage-leave-group" style="background:#ef4444;color:#fff;border:0;padding:10px 16px;border-radius:8px;cursor:pointer;font-weight:700;">Leave Party</button>
                </div>
            </div>
            ${membersHTML}
            ${inviteHTML}
        </div>
    `);
}

function bindGarbageHandlers(){
    $(document).off('click.garbstart').on('click.garbstart','#garbage-start-job',function(){
        $.post('https://pf-jobsystem/garbage:startJob', JSON.stringify({}), ()=>{})
    })

    $(document).off('click.garbtabs').on('click.garbtabs','.g6-tab-inline',function(){
        const tab=$(this).data('garbage-tab')
        if (!tab) return
        $('.g6-tab-inline').removeClass('active'); $(this).addClass('active')
        console.log('[Garbage] Tab clicked:', tab);
        if (tab==='work') {
            $('#garbage-right-pane').html(`<div class="g6-card" style="background:rgba(255,255,255,0.05);border:1px solid rgba(74,217,222,0.15);border-radius:16px;padding:24px;text-align:center;">Collect trash bags from dumpsters and deposit at the Trashmaster. One bag at a time.</div>`)
        } else if (tab==='group') {
            console.log('[Garbage] Fetching fresh group state from server...');
            // Query current group state from server before rendering
            $.post('https://pf-jobsystem/garbage/group/getState', JSON.stringify({}), function(groupData) {
                console.log('[Garbage] Fresh group state received:', groupData);
                window.__GARBAGE_STATE__.currentGroup = groupData;
                garbageRenderGroupPane();
            });
        } else if (tab==='upgrades') {
            $('#garbage-right-pane').html(`<div class="g6-card" style="background:rgba(255,255,255,0.05);border:1px solid rgba(74,217,222,0.15);border-radius:16px;padding:24px;text-align:center;">Upgrades coming soon.</div>`)
        }
    })
    
    // Group management handlers
    $(document).off('click.garbgroup');
    $(document).on('click.garbgroup', '#garbage-create-group', function() {
        console.log('[Garbage NUI] Create party button clicked');
        $.post('https://pf-jobsystem/garbage/group/create', JSON.stringify({}), function(resp) {
            console.log('[Garbage NUI] Create party response:', resp);
            // Immediately switch to Group tab and fetch fresh state
            $('.g6-tab-inline').removeClass('active');
            $('.g6-tab-inline[data-garbage-tab="group"]').addClass('active');
            console.log('[Garbage NUI] Switched to Group tab after create');
            $.post('https://pf-jobsystem/garbage/group/getState', JSON.stringify({}), function(groupData) {
                console.log('[Garbage NUI] Group state after create:', groupData);
                window.__GARBAGE_STATE__.currentGroup = groupData || null;
                if (typeof garbageRenderGroupPane === 'function') garbageRenderGroupPane();
            });
        });
    });
    $(document).on('click.garbgroup', '#garbage-send-invite', function() {
        const targetId = $('#garbage-invite-id').val();
        if (!targetId) return alert('Please enter a player ID');
        $.post('https://pf-jobsystem/garbage/group/invite', JSON.stringify({ target: parseInt(targetId) }));
        $('#garbage-invite-id').val('');
    });
    $(document).on('click.garbgroup', '#garbage-leave-group', function() {
        if (confirm('Are you sure you want to leave the party?')) {
            $.post('https://pf-jobsystem/garbage/group/leave', JSON.stringify({}));
        }
    });
    $(document).on('click.garbgroup', '#garbage-disband-group', function() {
        if (confirm('Disband the entire party? All members will be removed.')) {
            $.post('https://pf-jobsystem/garbage/group/disband', JSON.stringify({}));
        }
    });
    $(document).on('click.garbgroup', '.garbage-kick-member', function() {
        const targetId = $(this).data('target-id');
        if (confirm('Kick this player from the party?')) {
            $.post('https://pf-jobsystem/garbage/group/kick', JSON.stringify({ target: targetId }));
        }
    });
    $(document).on('change.garbgroup', '.garbage-split-input', function() {
        const targetId = $(this).data('target-id');
        const percentage = parseInt($(this).val()) || 0;
        if (percentage < 0 || percentage > 100) {
            alert('Percentage must be between 0 and 100');
            return;
        }
        $.post('https://pf-jobsystem/garbage/group/split', JSON.stringify({ target: targetId, percent: percentage }));
    });
    $(document).on('click.garbgroup', '.garbage-accept-invite', function() {
        const leaderId = $(this).data('leader-id');
        $.post('https://pf-jobsystem/garbage/group/accept', JSON.stringify({ leaderId }));
        window.__GARBAGE_STATE__.pendingInvites = window.__GARBAGE_STATE__.pendingInvites.filter(inv => inv.leaderId !== leaderId);
        garbageRenderGroupPane();
    });
    $(document).on('click.garbgroup', '.garbage-decline-invite', function() {
        const leaderId = $(this).data('leader-id');
        $.post('https://pf-jobsystem/garbage/group/decline', JSON.stringify({ leaderId }));
        window.__GARBAGE_STATE__.pendingInvites = window.__GARBAGE_STATE__.pendingInvites.filter(inv => inv.leaderId !== leaderId);
        garbageRenderGroupPane();
    });
}

// Garbage UI state (local to NUI)
window.__GARBAGE_STATE__ = window.__GARBAGE_STATE__ || { xp:0, level:1, carrying:false, currentGroup:null, pendingInvites:[], playerId:null };

// Listen for garbage state updates
window.addEventListener('message',function(e){
    const d=e.data||{}
    if (d.action==='garbage:init') { 
        window.__GARBAGE_STATE__=Object.assign(window.__GARBAGE_STATE__||{}, d.state||{}); 
        // Ensure playerId is present for leader checks
        if (d.state && d.state.playerId) {
            window.__GARBAGE_STATE__.playerId = d.state.playerId;
        }
        console.log('[Garbage] Init - playerId:', window.__GARBAGE_STATE__.playerId);
        console.log('[Garbage] Init - currentGroup:', window.__GARBAGE_STATE__.currentGroup);
        refreshGarbageDisplay() 
    }
    if (d.action==='garbage:updateXP') { 
        window.__GARBAGE_STATE__.xp=Number(d.xp||0); 
        window.__GARBAGE_STATE__.level=Number(d.level||1); 
        refreshGarbageDisplay() 
    }
    if (d.action==='garbage:carrying') { 
        window.__GARBAGE_STATE__.carrying=!!d.carrying; 
        refreshGarbageDisplay() 
    }
    if (d.action==='garbage_group_update') {
        console.log('[Garbage NUI] Received garbage_group_update message:', d.group);
        window.__GARBAGE_STATE__.currentGroup = d.group || null;
        console.log('[Garbage NUI] Updated currentGroup state:', window.__GARBAGE_STATE__.currentGroup);
        // Check which tab is active
        const activeTab = $('.g6-tab-inline.active[data-garbage-tab]').data('garbage-tab');
        console.log('[Garbage NUI] Current active tab:', activeTab);
        // Always render if on group tab
        if (activeTab === 'group' && typeof garbageRenderGroupPane === 'function') {
            console.log('[Garbage NUI] Rendering group pane NOW');
            garbageRenderGroupPane();
        } else {
            // Auto-switch to Group tab if group was just created (no members yet)
            if (d.group && Array.isArray(d.group.members) && d.group.members.length === 0) {
                $('.g6-tab-inline').removeClass('active');
                $('.g6-tab-inline[data-garbage-tab="group"]').addClass('active');
                console.log('[Garbage NUI] Auto-switched to Group tab after creation');
                if (typeof garbageRenderGroupPane === 'function') garbageRenderGroupPane();
            } else {
                console.log('[Garbage NUI] Not on group tab, skipping render');
            }
        }
    }
    if (d.action==='garbage_group_invite') {
        const invite = d.invite || {};
        const leaderName = invite.leaderName || 'Player';
        const leaderId = invite.leaderId;
        if (!window.__GARBAGE_STATE__.pendingInvites) window.__GARBAGE_STATE__.pendingInvites = [];
        // Avoid duplicates
        const existing = window.__GARBAGE_STATE__.pendingInvites.find(inv => inv.leaderId === leaderId);
        if (!existing) {
            window.__GARBAGE_STATE__.pendingInvites.push({ leaderName, leaderId });
        }
        console.log('[Garbage] Invite received from:', leaderName, leaderId);
        if (typeof garbageRenderGroupPane === 'function') {
            garbageRenderGroupPane();
        }
    }
})
