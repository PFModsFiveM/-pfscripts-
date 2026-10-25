// ============================================================================
// POLICE MDT - Clean Build
// ============================================================================

// Global State
let router = null;
let mapConfig = null;
let userPermissions = { allowed: false, isSupervisor: false };
let prioritiesConfig = {};
let statusesConfig = {};
let userInfo = { name: "Officer", rank: "Police", callsign: "", rankLevel: 0 };
let currentVehicleInfo = { plate: null, name: null };
let mdtConfig = {};
let localeStrings = {};
let currentLocale = 'en';

let __mdtPreloadedMapSrc = null;
let __mdtPreloadPromise = null;
let __mdtDeferredOpenPayload = null;
let __mdtDeferredOpenTimer = null;
let __mdtDeferredOpenAttempts = 0;

// Keep the latest dispatch payloads even when Dispatch page isn't active.
// This allows instant navigation to Dispatch without waiting for a new push.
let __mdtLastDispatchCalls = null;
let __mdtLastDispatchUnits = null;

let __mdtDispatchWarmed = false;
let __citationPrevTabletHidden = true;
let __citationPrevAppHidden = true;
let __dispatchOverlayVisible = true;
let __dispatchOverlayCurrentCalls = [];
let __dispatchOverlayCurrentIndex = 0;

function isPanicDispatchCall(call) {
    if (!call || typeof call !== 'object') return false;
    if (call.panic === true || call.isPanic === true) return true;
    const blob = [call.callType, call.type, call.code, call.title, call.description, call.details]
        .map((v) => String(v || '').toLowerCase())
        .join(' ');
    return blob.includes('panic') || blob.includes('10-99') || blob.includes('officer down');
}

function __mdtGetKeepAliveHost() {
    let host = document.getElementById('mdtKeepAliveHost');
    if (host) return host;
    host = document.createElement('div');
    host.id = 'mdtKeepAliveHost';
    host.style.position = 'absolute';
    host.style.left = '-99999px';
    host.style.top = '-99999px';
    host.style.width = '1px';
    host.style.height = '1px';
    host.style.overflow = 'hidden';
    host.setAttribute('aria-hidden', 'true');
    document.body.appendChild(host);
    return host;
}

function __mdtWarmDispatchInBackground() {
    try {
        if (__mdtDispatchWarmed) return;
        if (!router || !router.pages) return;
        const dispatchPage = router.pages.get('dispatch');
        if (!dispatchPage || typeof dispatchPage.mount !== 'function' || typeof dispatchPage.unmount !== 'function') return;
        if (!mapConfig) return;

        __mdtDispatchWarmed = true;

        const host = __mdtGetKeepAliveHost();
        const scratch = document.createElement('div');
        scratch.style.position = 'absolute';
        scratch.style.left = '-99999px';
        scratch.style.top = '-99999px';
        scratch.style.width = '1100px';
        scratch.style.height = '700px';
        scratch.style.overflow = 'hidden';
        host.appendChild(scratch);

        // Mount once to build DOM + initialize Leaflet, then immediately unmount
        // (our DispatchPage.unmount keeps it alive in the keepalive host).
        dispatchPage.mount(scratch);

        // Give Leaflet a moment to initialize and decode base layers.
        setTimeout(() => {
            try { dispatchPage.unmount(); } catch (_) {}
            try { scratch.remove(); } catch (_) {}
        }, 250);
    } catch (_) {
        // If anything goes wrong, allow a future attempt.
        __mdtDispatchWarmed = false;
    }
}

function getMapImageSources() {
    const full = getMapImagePath();
    const preview = (mapConfig?.image?.previewPath || mapConfig?.image?.preview || mapConfig?.image?.previewFile)
        ? String(mapConfig.image.previewPath || mapConfig.image.preview || mapConfig.image.previewFile)
        : null;

    // If preview is just a filename, assume same folder as the selected set/mode.
    if (preview && !preview.includes('/') && !preview.includes('\\')) {
        const simple = String(mapConfig?.mode || '').toLowerCase();
        if (simple === 'map' || simple === 'map2') return { full, preview: `${simple}/${preview}` };
        const set = mapConfig?.image?.set;
        if (set) return { full, preview: `${String(set).replace(/\\/g, '/').replace(/\/+$/, '')}/${preview}` };
    }
    return { full, preview: preview || full };
}

function preloadMapImageIfNeeded() {
    try {
        if (!mapConfig) return;
        if (getMapRenderMode() !== 'image') return;
        const { full, preview } = getMapImageSources();
        if (!full) return;

        if (__mdtPreloadedMapSrc === full && __mdtPreloadPromise) return;
        __mdtPreloadedMapSrc = full;

        const loadOne = (src) => {
            if (!src) return Promise.resolve();
            const img = new Image();
            try { img.decoding = 'async'; } catch (_) {}
            try { img.loading = 'eager'; } catch (_) {}
            img.src = src;
            return (typeof img.decode === 'function')
                ? img.decode().catch(() => {})
                : new Promise((resolve) => { img.onload = () => resolve(); img.onerror = () => resolve(); });
        };

        __mdtPreloadPromise = Promise.all([loadOne(preview), loadOne(full)]).then(() => {}).catch(() => {});
    } catch (_) {}
}

function getMapRenderMode() {
    // Preferred simple setting: Config.Map.mode = 'tiles' | 'map' | 'map2'
    const simple = String(mapConfig?.mode || '').toLowerCase();
    if (simple === 'map' || simple === 'map2') return 'image';
    if (simple === 'tiles') return 'tiles';

    // Backward compat
    const mode = String(mapConfig?.renderMode || 'tiles').toLowerCase();
    return (mode === 'image' || mode === 'full' || mode === 'single') ? 'image' : 'tiles';
}

function getMapImagePath() {
    // Preferred simple setting: mapConfig.mode controls the folder
    const simple = String(mapConfig?.mode || '').toLowerCase();
    if (simple === 'map' || simple === 'map2') {
        const file = String(mapConfig?.image?.file || 'full_map.png').replace(/\\/g, '/').replace(/^\/+/, '');
        return `${simple}/${file}`;
    }

    const imageCfg = mapConfig?.image || null;
    const set = imageCfg?.set || imageCfg?.folder || imageCfg?.dir || null;
    const file = imageCfg?.file || imageCfg?.filename || imageCfg?.name || 'full_map.png';

    // Preferred: set + file (lets servers easily toggle map vs map2)
    if (set) {
        const s = String(set).replace(/\\/g, '/').replace(/^\/+/, '').replace(/\/+$/, '');
        const f = String(file).replace(/\\/g, '/').replace(/^\/+/, '');
        return `${s}/${f}`;
    }

    // Backward compat: explicit path
    const p = imageCfg?.path || mapConfig?.imagePath || mapConfig?.fullMapPath;
    return p ? String(p) : null;
}

function getMapBaseSize() {
    const W = Number(mapConfig?.width || 512);
    const H = Number(mapConfig?.height || 768);
    return { W, H };
}

function getMapRenderSize() {
    const base = getMapBaseSize();
    if (getMapRenderMode() !== 'image') return base;

    const iw = Number(mapConfig?.image?.width || mapConfig?.image?.w || 0);
    const ih = Number(mapConfig?.image?.height || mapConfig?.image?.h || 0);
    if (iw > 0 && ih > 0) return { W: iw, H: ih };

    // Fallback: render in base size (may squash if image aspect differs)
    return base;
}

function getMapScaleFactors() {
    const base = getMapBaseSize();
    const render = getMapRenderSize();
    const sx = base.W > 0 ? (render.W / base.W) : 1;
    const sy = base.H > 0 ? (render.H / base.H) : 1;
    return { sx, sy, baseW: base.W, baseH: base.H, renderW: render.W, renderH: render.H };
}

function getActiveCalibration() {
    const isImage = getMapRenderMode() === 'image';
    if (!mapConfig) return { affine: null, worldBounds: null, flipY: false, offsetX: 0, offsetY: 0, useScale: false };

    if (isImage) {
        const img = mapConfig.image || {};
        const imgHomography = img.homography && img.homography.enabled ? img.homography : null;
        const imgAffine = img.affine && img.affine.enabled ? img.affine : null;
        const imgWorldBounds = img.worldBounds || null;
        const imgFlipY = (typeof img.flipY === 'boolean') ? img.flipY : mapConfig.flipY;
        const offsetX = Number(img.offsetX || 0);
        const offsetY = Number(img.offsetY || 0);
        // If no dedicated image affine, fall back to tile affine but scaled into render space.
        const useScale = !imgHomography && !imgAffine;
        return { homography: imgHomography, affine: imgAffine || mapConfig.affine || null, worldBounds: imgWorldBounds || mapConfig.worldBounds || null, flipY: imgFlipY, offsetX, offsetY, useScale };
    }

    return { homography: null, affine: mapConfig.affine || null, worldBounds: mapConfig.worldBounds || null, flipY: !!mapConfig.flipY, offsetX: 0, offsetY: 0, useScale: false };
}

function addMapBaseLayers(leafletMap) {
    if (!leafletMap || !mapConfig) return;

    const base = getMapBaseSize();
    const render = getMapRenderSize();
    const bounds = [[0, 0], [render.H, render.W]];

    const mode = getMapRenderMode();
    if (mode === 'image') {
        const { full, preview } = getMapImageSources();
        if (full) {
            const initial = preview || full;
            const overlay = L.imageOverlay(initial, bounds, { className: 'map-tile map-image' }).addTo(leafletMap);
            leafletMap.__mdtImageOverlay = overlay;
            leafletMap.__mdtImageFull = full;
            leafletMap.__mdtImagePreview = preview || full;
            leafletMap.__mdtImageZooming = false;
            leafletMap.__mdtImageSwapTimer = null;

            // Swap to preview while zooming (much faster), back to full on zoom end.
            // Also works fine if preview==full.
            const swapTo = (src) => {
                try {
                    const o = leafletMap.__mdtImageOverlay;
                    if (!o || typeof o.setUrl !== 'function' || !src) return;
                    // Avoid re-setting the same src; can trigger costly re-decode in CEF.
                    const img = o._image;
                    const current = img ? (img.getAttribute('src') || img.src) : null;
                    if (current && String(current) === String(src)) return;
                    o.setUrl(src);
                } catch (_) {}
            };
            try {
                const previewSrc = leafletMap.__mdtImagePreview;
                const fullSrc = leafletMap.__mdtImageFull;

                // Only attach swap logic if preview differs from full.
                if (previewSrc && fullSrc && String(previewSrc) !== String(fullSrc)) {
                    const clearSwapTimer = () => {
                        try {
                            if (leafletMap.__mdtImageSwapTimer) clearTimeout(leafletMap.__mdtImageSwapTimer);
                        } catch (_) {}
                        leafletMap.__mdtImageSwapTimer = null;
                    };

                    leafletMap.on('zoomstart', () => {
                        leafletMap.__mdtImageZooming = true;
                        clearSwapTimer();
                        swapTo(previewSrc);
                    });
                    leafletMap.on('zoomend', () => {
                        leafletMap.__mdtImageZooming = false;
                        clearSwapTimer();
                        // Wait a bit after zooming stops before switching to full-res.
                        // This prevents full-res decode from fighting with user input.
                        const delay = Number(mapConfig?.image?.fullSwapDelayMs ?? 250);
                        leafletMap.__mdtImageSwapTimer = setTimeout(() => swapTo(fullSrc), Number.isFinite(delay) ? delay : 250);
                    });
                }
            } catch (_) {}

            return;
        }
        console.warn('[MAP] renderMode=image but no Config.Map.image.path was provided; falling back to tiles');
    }

    // Tiles: stitched 3 rows x 2 columns
    const W = base.W;
    const H = base.H;
    const tileW = W / 2;
    const tileH = H / 3;
    const rows = [
        { folder: 2, y0: 0 * tileH, y1: 1 * tileH },
        { folder: 1, y0: 1 * tileH, y1: 2 * tileH },
        { folder: 0, y0: 2 * tileH, y1: 3 * tileH },
    ];

    rows.forEach((r) => {
        for (let col = 0; col < 2; col++) {
            const x0 = col * tileW;
            const x1 = (col + 1) * tileW;
            const url = `tiles/${r.folder}/0/${col}.png`;
            L.imageOverlay(url, [[r.y0, x0], [r.y1, x1]], { className: 'map-tile' }).addTo(leafletMap);
        }
    });
}

function setTextContent(selector, key, fallback) {
    try {
        const el = document.querySelector(selector);
        if (el) el.textContent = t(key, fallback || key);
    } catch (_) {}
}

function applyLocaleDataAttributes(root = document) {
    try {
        root.querySelectorAll('[data-i18n]').forEach((el) => {
            const key = el.getAttribute('data-i18n');
            if (!key) return;
            const fallback = el.textContent || key;
            el.textContent = t(key, fallback);
        });

        root.querySelectorAll('[data-i18n-placeholder]').forEach((el) => {
            const key = el.getAttribute('data-i18n-placeholder');
            if (!key) return;
            const fallback = el.getAttribute('placeholder') || key;
            el.setAttribute('placeholder', t(key, fallback));
        });

        root.querySelectorAll('[data-i18n-title]').forEach((el) => {
            const key = el.getAttribute('data-i18n-title');
            if (!key) return;
            const fallback = el.getAttribute('title') || key;
            el.setAttribute('title', t(key, fallback));
        });

        root.querySelectorAll('[data-i18n-aria-label]').forEach((el) => {
            const key = el.getAttribute('data-i18n-aria-label');
            if (!key) return;
            const fallback = el.getAttribute('aria-label') || key;
            el.setAttribute('aria-label', t(key, fallback));
        });
    } catch (_) {}
}

function applyLocaleTexts() {
    // Tablet title
    setTextContent('#tabletTitleLabel', 'tablet_title', 'Police MDT');

    // Topbar search placeholder
    try {
        const searchInput = document.querySelector('.search-box input');
        if (searchInput) searchInput.setAttribute('placeholder', t('search_placeholder', 'Search...'));
    } catch (_) {}

    // Nav section headers (order-based)
    const sections = document.querySelectorAll('.nav-section-title');
    if (sections && sections.length > 0) {
        if (sections[0]) sections[0].textContent = t('nav_main', 'Main');
        if (sections[1]) sections[1].textContent = t('nav_records', 'Records');
        if (sections[2]) sections[2].textContent = t('nav_admin', 'Admin');
    }

    // Nav items by page
    const navMap = {
        dashboard: 'nav_dashboard',
        dispatch: 'nav_dispatch',
        cctv: 'nav_cctv',
        citizens: 'nav_citizens',
        vehicles: 'nav_vehicles',
        warrant: 'nav_warrant',
        weapons: 'nav_weapons',
        reports: 'nav_reports',
        incidents: 'nav_incidents',
        evidence: 'nav_evidence',
        templates: 'nav_templates',
        officers: 'nav_officers',
        roster: 'nav_roster',
        sop: 'nav_sop'
    };
    document.querySelectorAll('.nav-item').forEach((item) => {
        const page = item.getAttribute('data-page');
        const key = navMap[page];
        if (!key) return;
        const label = item.querySelector('span');
        if (label) label.textContent = t(key, label.textContent || key);
    });

    // CCTV overlay
    setTextContent('#cctvViewerLabel', 'cctv_live', 'CCTV LIVE');
    setTextContent('#cctvViewerOverlay .cctv-viewer-overlay__hint', 'cctv_exit_hint', 'BACKSPACE to exit');

    // Topbar buttons
    try {
        const refreshBtn = document.getElementById('refreshBtn');
        if (refreshBtn) refreshBtn.setAttribute('title', t('topbar_refresh', 'Refresh'));
        const closeBtn = document.getElementById('closeBtn');
        if (closeBtn) closeBtn.setAttribute('title', t('topbar_close', 'Close'));
    } catch (_) {}

    // Profile modal
    setTextContent('#profileModal h3', 'profile_edit_title', 'Edit Profile');
    try {
        const profileModalClose = document.getElementById('profileModalClose');
        if (profileModalClose) profileModalClose.setAttribute('title', t('common_close', 'Close'));
        const saveBtn = document.getElementById('profileSaveBtn');
        if (saveBtn) saveBtn.textContent = t('common_save', 'Save');
        const nameInput = document.getElementById('profileNameInput');
        if (nameInput) nameInput.setAttribute('placeholder', t('profile_name_placeholder', 'Officer Name'));
        const callsignInput = document.getElementById('profileCallsignInput');
        if (callsignInput) callsignInput.setAttribute('placeholder', t('profile_callsign_placeholder', 'e.g. 3A-12'));
    } catch (_) {}

    // Generic i18n attributes (static HTML + any pages that set them)
    applyLocaleDataAttributes(document);
}

// Lightweight caches so returning to Dashboard can re-render immediately
let dashboardCache = null;           // { bulletins, warrants, ... }
let dashboardChatCache = [];         // [{ name, message }]

function canCreateBulletins() {
    const lvl = Number(userInfo?.rankLevel ?? 0);
    return Number.isFinite(lvl) && lvl >= 4;
}

function renderDashboardCacheIfPresent() {
    try {
        if (!dashboardCache) return;
        const page = router?.pages?.get('dashboard');
        page?.onMessage?.({ action: 'setDashboard', data: dashboardCache });
    } catch (_) {}

    try {
        if (!Array.isArray(dashboardChatCache) || dashboardChatCache.length === 0) return;
        const container = document.getElementById('chatMessages');
        if (!container) return;
        container.innerHTML = '';
        for (const m of dashboardChatCache) {
            const name = m?.name ?? 'Officer';
            const msg = m?.message ?? '';
            const el = document.createElement('div');
            el.className = 'chat-message';
            el.innerHTML = `<div class="chat-author">${escapeHtml(String(name))}</div><div class="chat-text">${escapeHtml(String(msg))}</div>`;
            container.appendChild(el);
        }
        container.scrollTop = container.scrollHeight;
    } catch (_) {}
}

// ============================================================================
// Locale System
// ============================================================================

/**
 * Load locale file for the specified language
 * @param {string} lang - Language code (en, es, fr, etc.)
 */
// NOTE: Locales are delivered from Lua via `config.localeData` on the open payload.
// Fetching locales over HTTP is intentionally disabled.
async function loadLocale(_lang = 'en') {
    console.warn('[LOCALE] loadLocale() is disabled; expecting localeData from Lua');
    return null;
}

function applyLocaleData(payload) {
    if (!payload || typeof payload !== 'object') {
        console.warn('[LOCALE] applyLocaleData: payload missing or invalid', payload);
        return;
    }
    console.log('[LOCALE] Received localeData with', Object.keys(payload).length, 'keys');
    localeStrings = payload;
    currentLocale = mdtConfig?.locale || currentLocale;
    console.log('[LOCALE] Applied locale:', currentLocale);
    applyLocaleTexts();
}

function updateLocale(lang) {
    if (!lang) return;
    currentLocale = lang;
    localStorage.setItem('mdt_language', lang);
    applyLocaleTexts();
    console.log('[LOCALE] Language changed to:', lang);
}

/**
 * Get translated string by key
 * @param {string} key - Locale key
 * @param {string} fallback - Fallback text if key not found
 * @returns {string} Translated string or fallback
 */
function t(key, fallback = key) {
    if (!localeStrings || Object.keys(localeStrings).length === 0) {
        return fallback;
    }
    return localeStrings[key] || fallback;
}

// ============================================================================
// Helpers
// ============================================================================

function getResourceName() {
    // In FiveM/NUI, the native GetParentResourceName() exists on window.
    // Do NOT override it (overriding breaks fetch URLs and causes "Failed to fetch").
    try {
        if (typeof window.GetParentResourceName === 'function') {
            const n = window.GetParentResourceName();
            if (n) return n;
        }
    } catch (_) {}

    // Fallback: parse from NUI hostname (cfx-nui-<resource>)
    const hostname = window.location.hostname || '';
    if (hostname.startsWith('cfx-nui-')) {
        return hostname.substring('cfx-nui-'.length);
    }

    // Final fallback (for dev/testing)
    return 'pf-policemdt';
}

async function sendCallback(action, data, callback, options) {
    const resName = getResourceName();
    const url = `https://${resName}/${action}`;
    console.log('[MDT SEND CALLBACK]', action, data, 'url:', url);
    try {
        const controller = new AbortController();
        const timeoutMs = (options && typeof options.timeoutMs === 'number') ? options.timeoutMs : 20000;
        let t = null;
        if (timeoutMs > 0) {
            t = setTimeout(() => {
                try { controller.abort(); } catch (_) {}
            }, timeoutMs);
        }

        const response = await fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
            signal: controller.signal
        });
        if (t) clearTimeout(t);
        if (!response.ok) {
            console.error('[MDT CALLBACK ERROR]', action, 'status:', response.status, response.statusText);
        }
        if (callback && typeof callback === 'function') {
            const result = await response.json();
            callback(result);
        }
    } catch (err) {
        console.error('[MDT CALLBACK ERROR]', action, err && err.name, err && err.message ? err.message : err);
        if (callback && typeof callback === 'function') {
            const msg = (err && err.name === 'AbortError') ? 'timeout' : (err && err.message) ? err.message : String(err);
            callback({ success: false, error: msg });
        }
    }
}

function mdtToastSafe(message, type) {
    try {
        if (typeof window.mdtToast === 'function') {
            window.mdtToast(message, type);
            return;
        }
        if (typeof mdtToast === 'function') {
            mdtToast(message, type);
            return;
        }
    } catch (_) {}
    console.log('[MDT TOAST]', type || 'info', message);
}

async function mdtConfirmSafe(message) {
    try {
        if (typeof window.mdtConfirm === 'function') {
            return await window.mdtConfirm(message);
        }
    } catch (_) {}
    mdtToastSafe(message, 'info');
    return false;
}

function escapeHtml(str) {
    return String(str ?? "")
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#039;");
}

function formatLabel(value) {
    if (value === null || value === undefined) return '—';
    if (typeof value === 'object') {
        return value.name || value.label || value.title || value.fullName || value.plate || value.callsign || value.id || JSON.stringify(value);
    }
    return String(value);
}

function formatDateTime(input) {
    if (!input) return "Unknown";
    try {
        let d;
        let numValue = null;
        
        // Convert string numbers to actual numbers
        if (typeof input === 'string' && /^\d+$/.test(input)) {
            numValue = parseInt(input, 10);
        } else if (typeof input === 'number') {
            numValue = input;
        }
        
        // Handle numeric timestamps
        if (numValue !== null) {
            // If it's milliseconds (very large number), use as-is
            // If it's seconds (smaller), multiply by 1000
            d = new Date(numValue < 10000000000 ? numValue * 1000 : numValue);
        }
        // String formats
        else if (typeof input === 'string') {
            // MySQL datetime format (YYYY-MM-DD HH:MM:SS)
            if (input.includes(' ')) {
                d = new Date(input.replace(' ', 'T'));
            }
            // ISO format
            else if (input.includes('T') || input.includes('-')) {
                d = new Date(input);
            }
            // Fallback
            else {
                d = new Date(input);
            }
        }
        // Other types
        else {
            d = new Date(input);
        }
        
        // Validate the date
        if (isNaN(d.getTime())) {
            console.warn('[formatDateTime] Invalid date:', input);
            return String(input);
        }
        
        // Format as MM/DD/YYYY with leading zeros
        const month = String(d.getMonth() + 1).padStart(2, '0');
        const day = String(d.getDate()).padStart(2, '0');
        const year = d.getFullYear();
        return `${month}/${day}/${year}`;
    } catch (e) {
        console.error('[formatDateTime] Exception:', e, 'input:', input);
        return String(input);
    }
}

function getStatusPillClass(status) {
    const s = String(status || "").toLowerCase();
    if (s === 'clear') return 'pillClear';
    return 'pillClear';
}

function computeStrikeSummary(strikes) {
    const active = (strikes || []).filter(s => String(s.status || 'active').toLowerCase() === 'active');
    const points = active.reduce((sum, s) => sum + (Number(s.points) || 4), 0);
    const activeCount = active.length;
    let risk = 'Low';
    if (points >= 8) risk = 'High'; else if (points >= 4) risk = 'Medium';
    return { points, activeCount, risk };
}

function formatOfficerLabel() {
    const name = userInfo?.name || 'Officer';
    const callsign = userInfo?.callsign || '';
    return callsign ? `${name} • ${callsign}` : name;
}

function canEditReports() {
    return userInfo.rankLevel >= 2 && userInfo.rankLevel <= 4;
}

function renderStrikeCard(s) {
    const status = String(s.status || 'active').toLowerCase();
    const isActive = status === 'active';
    const pillClass = isActive ? 'pillActive' : 'pillDismissed';
    const pillText = isActive ? 'ACTIVE' : 'DISMISSED';
    return `
      <div class="strikeCard ${isActive ? 'active' : ''}">
        <div class="strikeLeft">
          <div class="strikeTopRow">
            <span class="pill ${pillClass}">${pillText}</span>
            <span class="muted">${Number(s.points) || 4} points</span>
          </div>
          <div class="strikeTitle">${escapeHtml(s.title || s.reason || 'Strike')}</div>
          <div class="strikeMeta">
            <div>📅 ${formatDateTime(s.createdAt)}</div>
            ${s.createdByName ? `<div>👤 ${escapeHtml(s.createdByName)}</div>` : ''}
            ${s.expiresAt ? `<div>⏳ Expires: ${formatDateTime(s.expiresAt)}</div>` : ''}
          </div>
        </div>
      </div>
    `;
}

function worldToLatLng(x, y) {
    if (!mapConfig) return [0, 0];
    const { width = 512, height = 768 } = mapConfig;
    const calib = getActiveCalibration();
    const scale = getMapScaleFactors();
    const sx = calib.useScale ? scale.sx : 1;
    const sy = calib.useScale ? scale.sy : 1;

    if (calib.homography && calib.homography.enabled) {
        const {
            h11 = 1, h12 = 0, h13 = 0,
            h21 = 0, h22 = 1, h23 = 0,
            h31 = 0, h32 = 0, h33 = 1
        } = calib.homography;

        const den = (h31 * x) + (h32 * y) + h33;
        if (Math.abs(den) > 1e-9) {
            const px = ((h11 * x) + (h12 * y) + h13) / den + calib.offsetX;
            const py = ((h21 * x) + (h22 * y) + h23) / den + calib.offsetY;
            return [py, px];
        }
    }

    if (calib.affine && calib.affine.enabled) {
        const { a = 1, b = 0, c = 0, d = 0, e = 1, f = 0 } = calib.affine;
        const px = (a * x + b * y + c) * sx + calib.offsetX;
        const py = (d * x + e * y + f) * sy + calib.offsetY;
        return [py, px];
    }
    const wb = calib.worldBounds || { minX: -4400, maxX: 3600, minY: -5400, maxY: 8200 };
    const nx = (x - wb.minX) / (wb.maxX - wb.minX);
    const ny = (y - wb.minY) / (wb.maxY - wb.minY);
    let px = nx * width;
    let py = ny * height;
    if (calib.flipY) py = height - py;
    return [py * sy + calib.offsetY, px * sx + calib.offsetX];
}

class BasePage {
    constructor(id = 'base', title = 'MDT') {
        this.id = id;
        this.title = title;
        this.root = null;
    }
    mount(root) { 
        this.root = root;
    }
    unmount() { 
        if (this.root) {
            this.root.innerHTML = '';
            this.root = null;
        }
    }
    onMessage(_data) {}
    static updatePageTitle() {
        const el = document.getElementById('pageTitle');
        if (!el || !router) return;
        const title = router.titles.get(router.current) || 'MDT';
        el.textContent = title;
    }
}

class Router {
    constructor(root) {
        this.root = root;
        this.pages = new Map();
        this.titles = new Map();
        this.current = null;
        // Mini-map state for Dashboard
        this.mini = null;
        this.miniMarker = null;
        this.miniUnitsLayer = null;
        this.miniUnitMarkers = null;
        this.searchAllowed = new Set(['warrant','criminalcode','weapons','reports','incidents','citizens','vehicles','evidence']);
    }

    register(name, page, title) {
        this.pages.set(name, page);
        if (title) this.titles.set(name, title);
    }

    set(name) {
        if (!this.pages.has(name)) return;
        if (!this.root) {
            this.root = document.getElementById('pageContent');
            if (!this.root) {
                console.warn(`[APP] Cannot route to '${name}' because pageContent is not ready yet.`);
                return;
            }
        }
        if (this.current && this.pages.get(this.current)) { 
            try { this.pages.get(this.current).unmount(); } catch (_) {}
        }
        this.current = name;
        const page = this.pages.get(name);
        try {
            page.mount(this.root);
        } catch (err) {
            console.error(`[APP] Failed to mount page '${name}':`, err);
            try {
                const fallbackRoot = this.root;
                if (fallbackRoot) {
                    const title = this.titles.get(name) || name;
                    fallbackRoot.innerHTML = `
                        <section class="page-card" style="margin:12px;">
                            <h3>${escapeHtml(String(title))}</h3>
                            <div class="muted">This page failed to load. Check F8/NUI console for details.</div>
                        </section>
                    `;
                }
            } catch (_) {}
        }
        document.querySelectorAll('.nav-item').forEach(el => el.classList.toggle('active', el.dataset.page === name));
        BasePage.updatePageTitle();
        // Toggle search visibility by page
        if (this.searchAllowed.has(name)) document.body.classList.add('show-search');
        else document.body.classList.remove('show-search');
    }

    message(data) {
        try { this.pages.get(this.current)?.onMessage?.(data); } catch (_) {}
        // Only update the Dashboard mini-map while Dashboard is the active view.
        // Updating Leaflet layers while on Dispatch is a noticeable perf hit.
        if (this.current === 'dashboard') {
            if (data.action === 'setUnits' && Array.isArray(data.units)) {
                this.updateMiniUnits(data.units);
            }
            if (data.action === 'playerPos' && data.coords) {
                const ll = worldToLatLng(data.coords.x, data.coords.y);
                if (this.miniMarker) this.miniMarker.setLatLng(ll);
            }
        }
    }

    getPageTitle() { return this.titles.get(this.current) || 'MDT'; }

    destroyMiniMap() {
        if (this.mini) try { this.mini.remove(); } catch (_) {}
        this.mini = null; this.miniMarker = null; this.miniUnitsLayer = null; this.miniUnitMarkers = null;
    }

    initMiniMap() {
        if (!mapConfig) return;
        if (this.mini) return;
        const container = document.getElementById('dashboardMiniMap');
        if (!container) {
            // Guard against init when dashboard isn't mounted yet
            return;
        }
        const { W, H } = getMapRenderSize();
        const isImage = getMapRenderMode() === 'image';
        // "Live location" mini-map default: slightly less zoomed-in for image mode.
        const miniZoom = isImage ? 2.75 : 3;
        this.mini = L.map('dashboardMiniMap', {
            crs: L.CRS.Simple,
            minZoom: 0,
            maxZoom: 4,
            zoom: miniZoom,
            zoomSnap: 0.25,
            zoomDelta: 0.25,
            zoomControl: false,
            doubleClickZoom: false,
            scrollWheelZoom: false,
            dragging: false,
            attributionControl: false,
        });
        this.mini.setView([H / 2, W / 2], miniZoom);

        addMapBaseLayers(this.mini);

        // Debug helper: click to print pixel coords (useful for calibrating image mode)
        if (mapConfig?.debugCalibration) {
            try {
                this.mini.on('click', (e) => {
                    const mode = getMapRenderMode();
                    const x = Number(e.latlng?.lng ?? 0);
                    const y = Number(e.latlng?.lat ?? 0);
                    console.log(`[MDT MAP CLICK][mini] mode=${mode} x=${x.toFixed(2)} y=${y.toFixed(2)}`);
                });
            } catch (_) {}
        }

        this.miniUnitsLayer = L.layerGroup().addTo(this.mini);
        this.miniUnitMarkers = new Map();
        this.miniMarker = L.circleMarker([H / 2, W / 2], { radius: 7, color: '#ff8e53', fillColor: '#ff8e53', fillOpacity: 1, weight: 1 }).addTo(this.mini);
    }

    updateMiniUnits(units) {
        if (!this.mini) this.initMiniMap();
        if (!this.mini || !this.miniUnitsLayer) return;
        const incoming = new Set();
        units.forEach(u => {
            if (!u || !u.coords || u.coords.x === undefined) return;
            const id = u.source || u.citizenid || u.callsign || u.name || Math.random().toString(36).slice(2);
            incoming.add(id);
            const ll = worldToLatLng(u.coords.x, u.coords.y);
            const color = u.attachedCallId ? '#ffb347' : '#4dd0e1';
            const isVeh = !!u.inVehicle;
            if (this.miniUnitMarkers.has(id)) {
                const m = this.miniUnitMarkers.get(id);
                if (m.setLatLng) m.setLatLng(ll);
                if (m.setStyle) m.setStyle({ color, fillColor: color });
            } else {
                let marker;
                if (isVeh) {
                    const carIcon = L.divIcon({ className: 'unit-car-icon', iconSize: [18, 13], html: `<div style="width:18px;height:13px;border-radius:3px;background:${color};border:1px solid rgba(0,0,0,0.35);"></div>` });
                    marker = L.marker(ll, { icon: carIcon, title: u.name || 'Unit' });
                } else {
                    marker = L.circleMarker(ll, { radius: 6, color, fillColor: color, fillOpacity: 0.9, weight: 1 });
                }
                marker.bindTooltip(u.name || 'Unit', { direction: 'top', offset: [0, -2], opacity: 0.85 });
                marker.addTo(this.miniUnitsLayer);
                this.miniUnitMarkers.set(id, marker);
            }
        });
        for (const [id, marker] of this.miniUnitMarkers.entries()) {
            if (!incoming.has(id)) { this.miniUnitsLayer.removeLayer(marker); this.miniUnitMarkers.delete(id); }
        }
    }

    openCitizenProfile(citizenId) {
        try { sendCallback('openCitizen', { citizenId }); } catch (_) {}
        const modal = document.getElementById('citizenProfileModal');
        if (modal) modal.classList.remove('hidden');
    }

    openVehicleProfile(plateOrVehicle) {
        const plate = (typeof plateOrVehicle === 'string') ? plateOrVehicle : (plateOrVehicle && (plateOrVehicle.plate || plateOrVehicle))
        try { sendCallback('openVehicle', { plate }); } catch (_) {}
    }
}

// ============================================================================
// Dashboard Page
// ============================================================================
class DashboardPage extends BasePage {
    constructor() {
        super('dashboard', 'Dashboard');
        this._keepAliveRoot = null;
        this._listenersBound = false;
        this._emojiDocHandler = null;
    }
    applyStatusToControls(statusValue) {
        const dutySelect = document.getElementById('dutySelect');
        const statusSelect = document.getElementById('statusSelect');
        if (!dutySelect || !statusSelect || !statusValue) return;

        const dutyValues = new Set(['on_duty', 'off_duty']);
        const statusValues = new Set(['available', 'unavailable', 'busy', 'on_mission']);

        // New format: { duty, status }
        if (typeof statusValue === 'object') {
            const d = String(statusValue.duty || '').toLowerCase();
            const s = String(statusValue.status || '').toLowerCase();
            if (dutyValues.has(d)) dutySelect.value = d;
            if (statusValues.has(s)) statusSelect.value = s;
            return;
        }

        if (dutyValues.has(statusValue)) {
            dutySelect.value = statusValue;
            return;
        }

        if (statusValues.has(statusValue)) {
            dutySelect.value = 'on_duty';
            statusSelect.value = statusValue;
        }
    }

    unmount() {
        // Remove document-level listeners to prevent stacking duplicates.
        try {
            if (this._emojiDocHandler) document.removeEventListener('click', this._emojiDocHandler);
        } catch (_) {}

        // Keep-alive: stash dashboard DOM instead of destroying it (faster switching).
        try {
            const keepAliveRoot = document.getElementById('dashboardKeepAliveRoot');
            if (keepAliveRoot) {
                this._keepAliveRoot = keepAliveRoot;
                __mdtGetKeepAliveHost().appendChild(keepAliveRoot);
            }
        } catch (_) {}

        // Don't destroy the mini-map here; it stays bound to its container.
        this.root = null;
    }

    mount(root) {
        super.mount(root);

        // Reuse stashed DOM (instant switch)
        if (this._keepAliveRoot) {
            root.appendChild(this._keepAliveRoot);
            this._keepAliveRoot = null;

            // Leaflet: refresh sizing after being offscreen.
            setTimeout(() => { try { router?.mini?.invalidateSize?.(true); } catch (_) {} }, 0);
            BasePage.updatePageTitle();
            renderDashboardCacheIfPresent();
            return;
        }

        root.innerHTML = `
            <div id="dashboardKeepAliveRoot" class="dashboard-layout">
                <div class="dashboard-left-column">
                    <!-- Top Left: Personal Information -->
                    <section class="dashboard-panel personal-info-panel">
                        <h3>${t('dashboard_personal_information', 'Personal Information')}</h3>
                        <div class="personal-info-content">
                            <div class="personal-profile-pic" id="personalProfilePic">
                                <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                    <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"></path>
                                    <circle cx="12" cy="7" r="4"></circle>
                                </svg>
                            </div>
                            <div class="personal-info-text">
                                <div class="personal-name" id="personalName">—</div>
                                <div class="personal-job" id="personalJob">—</div>
                                <div class="personal-grade" id="personalGrade">—</div>
                                <div class="personal-callsign" id="personalCallsign">—</div>
                            </div>
                        </div>
                            <div class="personal-controls">
                                <div class="control-group">
                                    <label>${t('dashboard_duty_status', 'Duty Status')}</label>
                                    <select id="dutySelect" class="status-dropdown">
                                        <option value="on_duty">${t('duty_on_duty', 'On Duty')}</option>
                                        <option value="off_duty">${t('duty_off_duty', 'Off Duty')}</option>
                                    </select>
                                </div>
                                <div class="control-group">
                                    <label>${t('dashboard_status', 'Status')}</label>
                                    <select id="statusSelect" class="status-dropdown">
                                        <option value="available">${t('status_available', 'Available')}</option>
                                        <option value="unavailable">${t('status_unavailable', 'Unavailable')}</option>
                                        <option value="busy">${t('status_busy', 'Busy')}</option>
                                        <option value="on_mission">${t('status_on_mission', 'On Mission')}</option>
                                    </select>
                                </div>
                            </div>
                    </section>

                    <!-- Bottom Left: Chat -->
                    <section class="dashboard-panel chat-panel">
                        <h3>${t('dashboard_chat', 'Chat')}</h3>
                        <div class="chat-messages" id="chatMessages"></div>
                        <div class="chat-input-area">
                            <div class="chat-input-wrapper">
                                <input type="text" id="chatInput" class="chat-input" placeholder="${t('chat_type_message', 'Type a message...')}" maxlength="200">
                                <button id="chatEmojiBtn" class="chat-emoji-btn" title="${t('chat_emojis', 'Emojis')}" type="button">
                                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                        <circle cx="12" cy="12" r="10"></circle>
                                        <path d="M8 14s1.5 2 4 2 4-2 4-2"></path>
                                        <line x1="9" y1="9" x2="9.01" y2="9"></line>
                                        <line x1="15" y1="9" x2="15.01" y2="9"></line>
                                    </svg>
                                </button>
                                <button id="chatSendBtn" class="chat-send-btn" title="${t('chat_send', 'Send')}" type="button">
                                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                        <line x1="22" y1="2" x2="11" y2="13"></line>
                                        <polygon points="22 2 15 22 11 13 2 9 22 2"></polygon>
                                    </svg>
                                </button>
                            </div>
                            <div id="chatEmojiPicker" class="chat-emoji-picker hidden" aria-hidden="true">
                                <button class="emoji-item" type="button">😀</button>
                                <button class="emoji-item" type="button">😂</button>
                                <button class="emoji-item" type="button">😍</button>
                                <button class="emoji-item" type="button">😎</button>
                                <button class="emoji-item" type="button">👍</button>
                                <button class="emoji-item" type="button">👎</button>
                                <button class="emoji-item" type="button">✅</button>
                                <button class="emoji-item" type="button">❌</button>
                                <button class="emoji-item" type="button">🚓</button>
                                <button class="emoji-item" type="button">🚨</button>
                                <button class="emoji-item" type="button">📍</button>
                                <button class="emoji-item" type="button">❤️</button>
                                <button class="emoji-item" type="button">🔥</button>
                            </div>
                        </div>
                    </section>
                </div>

                <!-- Top Center: Bulletin Board -->
                <section class="dashboard-panel bulletin-panel">
                    <div style="display:flex; align-items:center; justify-content:space-between; gap:10px;">
                        <h3 style="margin:0;">${t('dashboard_bulletin_board', 'Bulletin Board')}</h3>
                        <button id="createBulletinBtn" class="btn primary" type="button" style="display:none;">${t('bulletin_create', 'Create Bulletin')}</button>
                    </div>
                    <div id="createBulletinForm" class="hidden" style="margin-top:10px; display:flex; flex-direction:column; gap:8px;">
                        <input id="bulletinTitleInput" class="chat-input" type="text" maxlength="255" placeholder="${t('bulletin_title', 'Title')}" />
                        <div id="bulletinBodyInput" style="margin-top: 6px;"></div>
                        <div style="display:flex; gap:8px; justify-content:flex-end;">
                            <button id="bulletinCancelBtn" class="btn" type="button">${t('common_cancel', 'Cancel')}</button>
                            <button id="bulletinSubmitBtn" class="btn primary" type="button">${t('common_save', 'Save')}</button>
                        </div>
                    </div>
                    <div class="bulletin-list" id="dashBulletins">
                        <div class="empty-message">${t('bulletin_empty', 'No bulletins')}</div>
                    </div>
                </section>

                <!-- Top Right: Active Warrants -->
                <section class="dashboard-panel warrants-panel">
                    <h3>${t('dashboard_active_warrants', 'Active Warrants')}</h3>
                    <div class="warrants-list" id="dashWarrantsList">
                        <div class="empty-message">${t('warrants_empty', 'No warrants')}</div>
                    </div>
                </section>

                <!-- Bottom Center: Active Units -->
                <section class="dashboard-panel units-panel">
                    <h3>${t('dashboard_active_units', 'Active Units')}</h3>
                    <div class="units-grid" id="dashUnitsGrid">
                        <div class="empty-message">${t('units_empty', 'No units')}</div>
                    </div>
                </section>

                <!-- Bottom Right: Map -->
                <section class="dashboard-panel map-panel">
                    <h3>${t('dashboard_live_location', 'Live Location')}</h3>
                    <div class="dashboard-map-wrap">
                        <div id="dashboardMiniMap" class="dashboard-map"></div>
                        <div class="map-dark-overlay" aria-hidden="true"></div>
                        <div class="map-street-overlay" id="dashboardStreetName">${t('dashboard_street_name', 'Street name')}: —</div>
                    </div>
                </section>
            </div>
        `;
        if (typeof router?.initMiniMap === 'function') {
            // Leaflet init can be expensive; defer so dashboard content paints instantly.
            (window.requestAnimationFrame || window.setTimeout)(() => {
                try { router.initMiniMap(); } catch (_) {}
            }, 0);
        }
        
        // Load personal info
        sendCallback('getPersonalInfo', {}, (result) => {
            if (result && result.success) {
                if (result.name) document.getElementById('personalName').textContent = result.name;
                if (result.job) document.getElementById('personalJob').textContent = result.job;
                if (result.grade) document.getElementById('personalGrade').textContent = result.grade;
                if (result.callsign) document.getElementById('personalCallsign').textContent = result.callsign;
                if (result.duty || result.status) this.applyStatusToControls({ duty: result.duty, status: result.status });
            }
        });
        
        // Setup chat handlers
        document.getElementById('chatSendBtn')?.addEventListener('click', () => this.sendChatMessage());
        document.getElementById('chatInput')?.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') this.sendChatMessage();
        });

        // Emoji picker
        const emojiBtn = document.getElementById('chatEmojiBtn');
        const emojiPicker = document.getElementById('chatEmojiPicker');
        if (emojiBtn && emojiPicker) {
            emojiBtn.addEventListener('click', (e) => {
                e.preventDefault();
                e.stopPropagation();
                emojiPicker.classList.toggle('hidden');
                emojiPicker.setAttribute('aria-hidden', emojiPicker.classList.contains('hidden') ? 'true' : 'false');
            });

            emojiPicker.addEventListener('click', (e) => {
                const btn = e.target && e.target.closest ? e.target.closest('button.emoji-item') : null;
                if (!btn) return;
                const input = document.getElementById('chatInput');
                if (!input) return;
                input.value = (input.value || '') + (btn.textContent || '');
                input.focus();
            });

            this._emojiDocHandler = (evt) => {
                const p = document.getElementById('chatEmojiPicker');
                const b = document.getElementById('chatEmojiBtn');
                if (!p || !b) return;
                if (p.classList.contains('hidden')) return;
                const t = evt.target;
                if (p.contains(t) || b.contains(t)) return;
                p.classList.add('hidden');
                p.setAttribute('aria-hidden', 'true');
            };
            document.addEventListener('click', this._emojiDocHandler);
        }
        
        // Setup personal info handlers
        document.getElementById('dutySelect')?.addEventListener('change', () => this.updateStatus('duty'));
        document.getElementById('statusSelect')?.addEventListener('change', () => this.updateStatus('status'));
        
        BasePage.updatePageTitle();

        // Bulletin create UI (grade 4+ only)
        const createBtn = document.getElementById('createBulletinBtn');
        const form = document.getElementById('createBulletinForm');
        const titleInput = document.getElementById('bulletinTitleInput');
        const bodyInput = document.getElementById('bulletinBodyInput');
        const cancelBtn = document.getElementById('bulletinCancelBtn');
        const submitBtn = document.getElementById('bulletinSubmitBtn');

        if (createBtn && canCreateBulletins()) {
            createBtn.style.display = '';
        }

        createBtn?.addEventListener('click', () => {
            if (!form) return;
            form.classList.toggle('hidden');
            if (!form.classList.contains('hidden')) {
                titleInput?.focus();
                // Initialize RTE when form is shown
                if (!window.__rteBulletinBody) {
                    window.__rteBulletinBody = createRTE('bulletinBodyInput', {
                        placeholder: 'Description...',
                        minHeight: '100px',
                        maxHeight: '30vh'
                    });
                } else {
                    window.__rteBulletinBody.clear();
                }
            }
        });

        cancelBtn?.addEventListener('click', () => {
            if (!form) return;
            form.classList.add('hidden');
            if (titleInput) titleInput.value = '';
            window.__mdtRTEManager?.clear('bulletinBodyInput');
        });

        submitBtn?.addEventListener('click', () => {
            if (!canCreateBulletins()) return;
            const title = (titleInput?.value || '').trim();
            const body = window.__rteBulletinBody ? 
                window.__rteBulletinBody.getPlainText().trim() : 
                (window.__mdtRTEManager?.getPlainText('bulletinBodyInput') || '');
            if (!title || !body.trim()) return;
            sendCallback('createBulletin', { title, body }, (res) => {
                if (res && res.success) {
                    if (titleInput) titleInput.value = '';
                    if (window.__rteBulletinBody) window.__rteBulletinBody.clear();
                    form?.classList.add('hidden');
                }
            });
        });

        // If we already received dashboard/chat data earlier, re-render it now.
        renderDashboardCacheIfPresent();
    }

    sendChatMessage() {
        const input = document.getElementById('chatInput');
        const msg = input?.value?.trim();
        if (!msg) return;
        
        sendCallback('sendChatMessage', { message: msg }, (cb) => {
            if (cb && cb.success) {
                input.value = '';
                this.addChatMessage(t('chat_you', 'You'), msg, true);
            } else {
                console.warn('[MDT] Failed to send chat:', cb?.error);
            }
        });
    }

    addChatMessage(name, msg, isSelf) {
        const container = document.getElementById('chatMessages');
        if (!container) return;
        
        const el = document.createElement('div');
        el.className = 'chat-message' + (isSelf ? ' self' : '');
        el.innerHTML = `
            <div class="chat-author">${name}</div>
            <div class="chat-text">${msg}</div>
        `;
        
        container.appendChild(el);
        container.scrollTop = container.scrollHeight;
    }

    updateStatus(changed) {
        const duty = document.getElementById('dutySelect')?.value || 'on_duty';
        const status = document.getElementById('statusSelect')?.value || 'available';

        sendCallback('updatePlayerStatus', { duty, status, changed }, (cb) => {
            if (!cb || !cb.success) {
                console.warn('[MDT] Failed to update status');
            }
        });
    }

    onMessage(data) {
        if (data.action === 'setUnits' && Array.isArray(data.units)) {
            const grid = document.getElementById('dashUnitsGrid');
            if (grid) {
                if (data.units.length === 0) {
                    grid.innerHTML = `<div class="empty-message">${t('units_empty', 'No units')}</div>`;
                } else {
                    const statusLabel = (s) => {
                        const key = String(s || '').toLowerCase();
                        const map = {
                            available: t('status_available', 'Available'),
                            unavailable: t('status_unavailable', 'Unavailable'),
                            busy: t('status_busy', 'Busy'),
                            on_mission: t('status_on_mission', 'On Mission'),
                            onmission: t('status_on_mission', 'On Mission'),
                            off_duty: t('duty_off_duty', 'Off Duty'),
                            on_duty: t('duty_on_duty', 'On Duty')
                        };
                        if (map[key]) return map[key];
                        return key ? key.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase()) : t('common_unknown', 'Unknown');
                    };

                    grid.innerHTML = data.units.map(u => {
                        const name = escapeHtml(u.name || '—');
                        const phoneRaw = u.phone || u.phoneNumber || u.phonenumber || '';
                        const phone = escapeHtml(phoneRaw || '—');
                        const dutyKey = String(u.duty || '').toLowerCase() === 'off_duty' ? 'off_duty' : 'on_duty';
                        const dutyText = dutyKey === 'off_duty' ? t('duty_off_duty', 'Off Duty') : t('duty_on_duty', 'On Duty');

                        const statusKey = String(u.status || '').toLowerCase() || 'available';
                        const statusText = statusLabel(statusKey);

                        const rankRaw = u.rank || u.rosterRank || u.roster_rank || '';
                        const rank = escapeHtml(rankRaw || t('common_officer', 'Officer'));

                        return `<div class="unit-box unit-card">
                            <div class="unit-avatar" aria-hidden="true">
                                <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                                    <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"></path>
                                    <circle cx="12" cy="7" r="4"></circle>
                                </svg>
                            </div>

                            <div class="unit-meta">
                                <div class="unit-title">${name}</div>
                                <div class="unit-subtitle">${t('unit_phone_number', 'Phone number')}: <strong>${phone}</strong></div>
                                <div class="unit-badges">
                                    <span class="unit-pill unit-pill-duty" data-duty="${dutyKey}">
                                        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>
                                        ${dutyText}
                                    </span>
                                    <span class="unit-pill unit-pill-status" data-status="${escapeHtml(statusKey)}">
                                        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2a10 10 0 1 0 10 10"></path><path d="M12 6v6l4 2"></path></svg>
                                        ${t('unit_status', 'Status')}: ${escapeHtml(statusText)}
                                    </span>
                                    <span class="unit-pill unit-pill-rank">
                                        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="12 2 15 8.5 22 9.3 17 14 18.5 21 12 17.8 5.5 21 7 14 2 9.3 9 8.5 12 2"></polygon></svg>
                                        ${rank}
                                    </span>
                                </div>
                            </div>
                        </div>`;
                    }).join('');
                }
            }
            if (router && typeof router.updateMiniUnits === 'function') router.updateMiniUnits(data.units);
        }
        if (data.action === 'playerPos' && data.coords) {
            const ll = worldToLatLng(data.coords.x, data.coords.y);
            if (router?.miniMarker) router.miniMarker.setLatLng(ll);
            if (router?.mini) router.mini.setView(ll, router.mini.getZoom(), { animate: false });
            const streetEl = document.getElementById('dashboardStreetName');
            if (streetEl) {
                const label = data.location || data.street || data.streetName || '';
                const prefix = t('dashboard_street_name', 'Street name');
                streetEl.textContent = label ? `${prefix}: ${label}` : `${prefix}: —`;
            }
        }
        if (data.action === 'setCalls' && Array.isArray(data.calls)) {
            const actEl = document.getElementById('dashActiveCalls');
            if (actEl) actEl.textContent = data.calls.filter(c=>c.status!=='completed').length;
        }
        if (data.action === 'setDashboard' && data.data) {
            dashboardCache = data.data;
            const bWrap = document.getElementById('dashBulletins');
            if (bWrap) {
                const b = data.data.bulletins || [];
                bWrap.innerHTML = b.length ? b.map(x=>`<div class="bulletin-card"><div class="bulletin-title">${escapeHtml(x.title||'Bulletin')}</div><div class="bulletin-date">${x.createdAt? new Date(x.createdAt*1000).toLocaleString():''}</div><div class="bulletin-body">${escapeHtml(x.body||'')}</div></div>`).join('') : '<div class="empty-message">No bulletins</div>';
            }
            const wWrap = document.getElementById('dashWarrantsList');
            if (wWrap) {
                const w = data.data.warrants || [];
                wWrap.innerHTML = w.length ? w.map(x=>{
                    let dateValue = x.createdAt || x.timestamp;
                    if (typeof dateValue === 'string' && !dateValue.match(/^\d+$/)) {
                        dateValue = new Date(dateValue).getTime() / 1000;
                    } else if (typeof dateValue === 'string') {
                        dateValue = parseInt(dateValue);
                    }
                    const warrantId = x.id || x.warrantId || 'unknown';
                    return `<div class="call-card warrant-card" data-warrant-id="${escapeHtml(String(warrantId))}" style="cursor:pointer;" role="button" tabindex="0">
                        <div class="call-title">${escapeHtml(x.name||'Unknown')}</div>
                        <div class="call-status" style="color:#00e676">${escapeHtml(x.status||'active')}</div>
                        <div class="call-id">📅 ${dateValue ? formatDateTime(dateValue) : 'Unknown'}</div>
                    </div>`;
                }).join('') : '<div class="empty-message">No warrants</div>';

                // Add click handlers to warrant cards
                wWrap.querySelectorAll('.warrant-card').forEach(card => {
                    const handleClick = () => {
                        const warrantId = card.getAttribute('data-warrant-id');
                        if (warrantId && router) {
                            // router route name is singular ('warrant')
                            router.set('warrant');
                            setTimeout(() => {
                                sendCallback('getWarrantDetails', { warrantId }, (details) => {
                                    if (details) {
                                        const wPage = router.pages.get('warrant');
                                        if (wPage && typeof wPage.onMessage === 'function') {
                                            wPage.onMessage({ action: 'selectWarrant', warrant: details });
                                        }
                                    }
                                });
                            }, 100);
                        }
                    };
                    card.addEventListener('click', handleClick);
                    card.addEventListener('keydown', (e) => {
                        if (e.key === 'Enter' || e.key === ' ') {
                            handleClick();
                        }
                    });
                });
            }
        }
        if (data.action === 'chatMessage') {
            try {
                dashboardChatCache.push({ name: data.name || 'Officer', message: data.message || '' });
                if (dashboardChatCache.length > 200) dashboardChatCache = dashboardChatCache.slice(-200);
            } catch (_) {}
            this.addChatMessage(data.name || 'Officer', data.message || '', false);
        }
        if (data.action === 'setPersonalInfo') {
            if (data.name) document.getElementById('personalName').textContent = data.name;
            if (data.job) document.getElementById('personalJob').textContent = data.job;
            if (data.grade) document.getElementById('personalGrade').textContent = data.grade;
            if (data.callsign) document.getElementById('personalCallsign').textContent = data.callsign;
            if (data.duty || data.status) this.applyStatusToControls({ duty: data.duty, status: data.status });
        }
    }
}

// ============================================================================
// Dispatch Page
// ============================================================================
class DispatchPage extends BasePage {
    constructor() {
        super('dispatch', 'Dispatch');
        this.currentCalls = [];
        this.allCalls = [];
        this.selectedCallId = null;
        this.map = null;
        this.markersLayer = null;
        this.markers = new Map();
        this.previousCallIds = new Set();
        this.markerUpdateTimeout = null;
        this.lastCallSignature = '';
        this.unitMarkersLayer = null;
        this.unitMarkers = new Map();

        this.autoClearSeconds = 0;
        this.autoClearTick = null;

        // Keep-alive: stash the whole dispatch DOM + Leaflet map between navigations
        // so switching to/from dispatch is instant.
        this._keepAliveRoot = null;
        this._globalKeyHandler = null;

        this._didInitialFit = false;
    }

    getAutoClearStorageKey() {
        const keyPart = (userInfo?.callsign || userInfo?.name || 'default').toString().trim() || 'default';
        return `pf_mdt_dispatch_autoclear_${keyPart}`;
    }

    clampAutoClearSeconds(value) {
        const v = Number(value);
        if (!Number.isFinite(v) || v <= 0) return 0;
        return Math.max(0, Math.min(300, Math.floor(v)));
    }

    loadAutoClearSetting() {
        try {
            const raw = localStorage.getItem(this.getAutoClearStorageKey());
            return this.clampAutoClearSeconds(parseInt(raw || '0', 10));
        } catch (_) {
            return 0;
        }
    }

    saveAutoClearSetting(seconds) {
        try {
            localStorage.setItem(this.getAutoClearStorageKey(), String(this.clampAutoClearSeconds(seconds)));
        } catch (_) {}
    }

    setAutoClearSeconds(seconds, refresh) {
        this.autoClearSeconds = this.clampAutoClearSeconds(seconds);
        this.saveAutoClearSetting(this.autoClearSeconds);
        if (refresh) this.refreshVisibleCalls(true);
    }

    getVisibleCalls() {
        const sec = this.clampAutoClearSeconds(this.autoClearSeconds);
        if (!sec) return this.allCalls || [];
        const now = Math.floor(Date.now() / 1000);
        return (this.allCalls || []).filter(c => {
            const created = Number(c?.createdAt || c?.timestamp || 0);
            if (!Number.isFinite(created) || created <= 0) return true;
            return (now - created) < sec;
        });
    }

    refreshVisibleCalls(alsoUpdateMarkers) {
        this.currentCalls = this.getVisibleCalls();
        if (this.selectedCallId && !this.currentCalls.some(c => c.id === this.selectedCallId)) {
            this.selectedCallId = null;
            this.closeModal();
        }
        this.updateCallCount();
        this.renderCallsList();
        if (alsoUpdateMarkers) this.updateMarkers();
    }

    formatTimeAgo(createdAtSeconds) {
        const ts = Number(createdAtSeconds);
        if (!Number.isFinite(ts) || ts <= 0) return 'unknown';
        const diffMs = Date.now() - (ts * 1000);
        const diffSec = Math.max(0, Math.floor(diffMs / 1000));
        const min = Math.floor(diffSec / 60);
        const hr = Math.floor(min / 60);
        const day = Math.floor(hr / 24);
        if (day > 0) return `about ${day} day${day === 1 ? '' : 's'} ago`;
        if (hr > 0) return `about ${hr} hour${hr === 1 ? '' : 's'} ago`;
        if (min > 0) return `about ${min} minute${min === 1 ? '' : 's'} ago`;
        return 'just now';
    }

    mount(root) {
        super.mount(root);

        // If we have a stashed DOM tree, reuse it instead of rebuilding + reinitializing Leaflet.
        if (this._keepAliveRoot) {
            root.appendChild(this._keepAliveRoot);
            this._keepAliveRoot = null;
            this.attachEventListeners();
            this.setAutoClearSeconds(this.loadAutoClearSetting(), false);
            const sel = document.getElementById('dispatchAutoClearSelect');
            if (sel) sel.value = String(this.autoClearSeconds || 0);
            if (!this.autoClearTick) {
                this.autoClearTick = setInterval(() => {
                    if (!this.autoClearSeconds) return;
                    this.refreshVisibleCalls(true);
                }, 1000);
            }

            // Apply cached payloads immediately.
            if (Array.isArray(__mdtLastDispatchCalls)) this.handleSetCalls(__mdtLastDispatchCalls);
            if (Array.isArray(__mdtLastDispatchUnits)) this.updateUnitMarkers(__mdtLastDispatchUnits);

            // Leaflet needs this when a map is shown after being offscreen.
            setTimeout(() => {
                try { this.map?.invalidateSize?.(true); } catch (_) {}
                // On first show after opening MDT, ensure Dispatch starts zoomed out.
                if (!this._didInitialFit) {
                    try {
                        const { W, H } = getMapRenderSize();
                        this.map?.fitBounds?.([[0, 0], [H, W]], { animate: false });
                    } catch (_) {}
                    this._didInitialFit = true;
                }
                // Start animation after map is ready
                this.startAnimation();
            }, 0);
            return;
        }

        root.innerHTML = `
            <div id="dispatchKeepAliveRoot" class="dispatch-layout">
                <div class="dispatch-left">
                    <div class="panel-header">
                        <h3>${t('dispatch_active_calls', 'Active Calls')}</h3>
                        <div class="dispatch-header-right">
                            <span class="call-count"><span id="dispatchCallCount">0</span> ${t('dispatch_active', 'Active')}</span>
                            <div class="dispatch-autoclear">
                                <span class="dispatch-autoclear-label">${t('dispatch_autoclear', 'Auto-clear')}</span>
                                <select id="dispatchAutoClearSelect" class="dispatch-autoclear-select" aria-label="${t('dispatch_autoclear_aria', 'Auto clear calls')}">
                                    <option value="0">${t('dispatch_autoclear_off', 'Off')}</option>
                                    <option value="60">${t('dispatch_autoclear_1m', '1 min')}</option>
                                    <option value="120">${t('dispatch_autoclear_2m', '2 min')}</option>
                                    <option value="180">${t('dispatch_autoclear_3m', '3 min')}</option>
                                    <option value="240">${t('dispatch_autoclear_4m', '4 min')}</option>
                                    <option value="300">${t('dispatch_autoclear_5m', '5 min')}</option>
                                </select>
                            </div>
                        </div>
                    </div>
                    <div id="dispatchCallsList" class="calls-list"></div>
                </div>
                <div class="dispatch-right">
                    <div id="map"></div>
                    <div class="zoom-controls">
                        <button id="dispatchZoomIn" class="zoom-btn" title="${t('dispatch_zoom_in', 'Zoom In')}"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="12" y1="5" x2="12" y2="19"></line><line x1="5" y1="12" x2="19" y2="12"></line></svg></button>
                        <button id="dispatchZoomOut" class="zoom-btn" title="${t('dispatch_zoom_out', 'Zoom Out')}"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="5" y1="12" x2="19" y2="12"></line></svg></button>
                    </div>
                    <div id="callDetailModal" class="modal hidden">
                        <div class="modal-card">
                            <div class="modal-header"><h3 id="modalCallTitle">${t('dispatch_call_title', 'Call Title')}</h3><button id="modalCloseBtn" class="modal-btn" title="${t('common_close', 'Close')}"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="18" y1="6" x2="6" y2="18"></line><line x1="6" y1="6" x2="18" y2="18"></line></svg></button></div>
                            <div class="modal-body">
                                <div class="detail-row"><span class="detail-label">${t('dispatch_id', 'ID')}</span><span id="modalCallId" class="detail-value"></span></div>
                                <div class="detail-row"><span class="detail-label">${t('dispatch_status', 'Status')}</span><span id="modalCallStatus" class="detail-value"></span></div>
                                <div class="detail-row"><span class="detail-label">${t('dispatch_priority', 'Priority')}</span><span id="modalCallPriority" class="detail-value"></span></div>
                                <div class="detail-row"><span class="detail-label">${t('dispatch_location', 'Location')}</span><span id="modalCallLocation" class="detail-value"></span></div>
                                <div class="detail-row"><span class="detail-label">${t('dispatch_coords', 'Coords')}</span><span id="modalCallCoords" class="detail-value"></span></div>
                                <div class="detail-row"><span class="detail-label">${t('dispatch_created', 'Created')}</span><span id="modalCallTime" class="detail-value"></span></div>
                                <div class="detail-row"><span class="detail-label">${t('dispatch_units', 'Units')}</span><span id="modalCallUnits" class="detail-value"></span></div>
                            </div>
                            <div class="modal-footer">
                                <button id="modalAcceptBtn" class="modal-btn primary" title="${t('button_accept', 'Accept')}">${t('button_accept', 'Accept')}</button>
                                <button id="modalCompleteBtn" class="modal-btn success" title="${t('button_complete', 'Complete')}">${t('button_complete', 'Complete')}</button>
                                <button id="modalWaypointBtn" class="modal-btn info" title="${t('button_waypoint', 'Waypoint')}">${t('button_waypoint', 'Waypoint')}</button>
                                <button id="modalDeleteBtn" class="modal-btn danger" title="${t('button_delete', 'Delete')}">${t('button_delete', 'Delete')}</button>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        `;

        // Ensure first paint happens fast; initialize Leaflet right after.
        (window.requestAnimationFrame || window.setTimeout)(() => this.initializeMap(), 0);
        this.attachEventListeners();

        this.allCalls = this.currentCalls || [];
        this.setAutoClearSeconds(this.loadAutoClearSetting(), false);
        const sel = document.getElementById('dispatchAutoClearSelect');
        if (sel) {
            sel.value = String(this.autoClearSeconds || 0);
            sel.addEventListener('change', () => {
                const v = this.clampAutoClearSeconds(parseInt(sel.value || '0', 10));
                this.setAutoClearSeconds(v, true);
            });
        }

        if (!this.autoClearTick) {
            this.autoClearTick = setInterval(() => {
                if (!this.autoClearSeconds) return;
                this.refreshVisibleCalls(true);
            }, 1000);
        }

        // If calls arrived before this page was shown, render immediately.
        if (Array.isArray(__mdtLastDispatchCalls)) this.handleSetCalls(__mdtLastDispatchCalls);
        if (Array.isArray(__mdtLastDispatchUnits)) this.updateUnitMarkers(__mdtLastDispatchUnits);
    }

    unmount() {
        // Pause timers while hidden.
        if (this.autoClearTick) {
            clearInterval(this.autoClearTick);
            this.autoClearTick = null;
        }

        // Close modal so it won't eat clicks while stashed.
        try { this.closeModal(); } catch (_) {}

        // Keep-alive: move DOM to hidden host instead of destroying it.
        try {
            const keepAliveRoot = document.getElementById('dispatchKeepAliveRoot');
            if (keepAliveRoot) {
                this._keepAliveRoot = keepAliveRoot;
                __mdtGetKeepAliveHost().appendChild(keepAliveRoot);
            }
        } catch (_) {}

        // Do NOT remove the Leaflet map; it stays bound to its container.
        // Just detach page root.
        this.root = null;
    }

    attachEventListeners() {
        const zoomIn = document.getElementById('dispatchZoomIn');
        const zoomOut = document.getElementById('dispatchZoomOut');
        if (zoomIn) zoomIn.onclick = () => { if (this.map) this.map.zoomIn(); };
        if (zoomOut) zoomOut.onclick = () => { if (this.map) this.map.zoomOut(); };

        const closeBtn = document.getElementById('modalCloseBtn');
        if (closeBtn) closeBtn.onclick = () => this.closeModal();

        const acceptBtn = document.getElementById('modalAcceptBtn');
        if (acceptBtn) acceptBtn.onclick = () => { 
            if (this.selectedCallId) {
                const call = this.currentCalls.find(c => c.id === this.selectedCallId);
                sendCallback('acceptCall', { id: this.selectedCallId, coords: call?.coords }); 
            }
            this.closeModal(); 
        };

        const completeBtn = document.getElementById('modalCompleteBtn');
        if (completeBtn) completeBtn.onclick = () => { if (this.selectedCallId) sendCallback('completeCall', { id: this.selectedCallId }); this.closeModal(); };

        const waypointBtn = document.getElementById('modalWaypointBtn');
        if (waypointBtn) waypointBtn.onclick = () => {
            const call = this.currentCalls.find(c => c.id === this.selectedCallId);
            if (call && call.coords) sendCallback('setWaypoint', { coords: call.coords });
            this.closeModal();
        };

        const deleteBtn = document.getElementById('modalDeleteBtn');
        if (deleteBtn) deleteBtn.onclick = () => { if (userPermissions?.isSupervisor && this.selectedCallId) sendCallback('deleteCall', { id: this.selectedCallId }); this.closeModal(); };

        const overlay = document.getElementById('callDetailModal');
        if (overlay) overlay.onclick = (e) => { if (e.target === overlay) this.closeModal(); };

        // Ensure we don't stack duplicate document listeners.
        if (this._globalKeyHandler) {
            try { document.removeEventListener('keydown', this._globalKeyHandler, true); } catch (_) {}
        }
        this._globalKeyHandler = (e) => { if (e.key === 'Escape') this.closeModal(); };
        document.addEventListener('keydown', this._globalKeyHandler, true);
    }

    initializeMap() {
        if (this.map) return;
        if (!mapConfig) { console.error('mapConfig not loaded'); return; }
        const { W, H } = getMapRenderSize();
        const bounds = [[0,0],[H,W]];
        const isImage = getMapRenderMode() === 'image';
        // NOTE: In CRS.Simple, fitBounds may require negative zoom to fully fit large images.
        // If minZoom is clamped to 0, the map will appear "too zoomed in" on open.
        const minZoom = isImage ? -6 : (mapConfig.minZoom || 0);

        this.map = L.map('map', {
            crs: L.CRS.Simple,
            minZoom,
            maxZoom: mapConfig.maxZoom || 4,
            zoom: 1,
            zoomControl: false,
            doubleClickZoom: false,
            scrollWheelZoom: true,
            // Make wheel zoom feel immediate.
            wheelPxPerZoomLevel: isImage ? 15 : 30,
            // In CEF, fully un-debounced wheel zoom can flood events and feel laggy.
            wheelDebounceTime: isImage ? 20 : 0,
            // IMPORTANT: update during zoom so image-mode doesn't feel like it "zooms later".
            // We already swap to a preview image during zoomstart for performance.
            updateWhenZooming: true,
            updateWhenIdle: false,
            // In image mode, larger zoom steps feel much faster in CEF.
            zoomSnap: isImage ? 1 : 0.5,
            zoomDelta: isImage ? 1 : 0.5,
            zoomAnimation: false,
            fadeAnimation: false,
            markerZoomAnimation: false,
            attributionControl: false,
            // Render vector layers on canvas when possible (cheaper than SVG in CEF).
            preferCanvas: true,
            dragging: true,
            inertia: !isImage,
        });
        this.map.setView([H/2, W/2], 1);

        addMapBaseLayers(this.map);

        this.markersLayer = L.layerGroup().addTo(this.map);
        this.unitMarkersLayer = L.layerGroup().addTo(this.map);

        // During zoom, hide marker panes to reduce paint/reflow cost.
        // This makes zooming feel much smoother when there are many calls/units.
        if (isImage) {
            try {
                const hidePanes = () => {
                    try { this.map.closePopup(); } catch (_) {}
                    const markerPane = this.map.getPane('markerPane');
                    const shadowPane = this.map.getPane('shadowPane');
                    const popupPane = this.map.getPane('popupPane');
                    if (markerPane) markerPane.style.display = 'none';
                    if (shadowPane) shadowPane.style.display = 'none';
                    if (popupPane) popupPane.style.display = 'none';
                };
                const showPanes = () => {
                    const markerPane = this.map.getPane('markerPane');
                    const shadowPane = this.map.getPane('shadowPane');
                    const popupPane = this.map.getPane('popupPane');
                    if (markerPane) markerPane.style.display = '';
                    if (shadowPane) shadowPane.style.display = '';
                    if (popupPane) popupPane.style.display = '';
                };
                this.map.on('zoomstart', hidePanes);
                this.map.on('zoomend', () => setTimeout(showPanes, 0));
            } catch (_) {}
        }
        this.map.fitBounds(bounds, { animate: false });

        // Image mode: fitBounds can over-zoom out (very negative zoom) depending on container size.
        // Start slightly closer than the raw fit, and restrict how far the user can zoom out.
        if (isImage) {
            try {
                const fitZoom = this.map.getZoom();
                const maxZoom = (typeof this.map.getMaxZoom === 'function') ? this.map.getMaxZoom() : (this.map.options.maxZoom ?? 4);

                // Default to "fit + 1" so dispatch doesn't open feeling too far out.
                const targetZoom = Math.min(fitZoom + 1, Number.isFinite(maxZoom) ? maxZoom : (fitZoom + 1));
                this.map.setZoom(targetZoom, { animate: false });

                // Allow some zoom-out beyond the initial view, but not excessive.
                // (Larger negative numbers = more zoomed out.)
                const desiredMinZoom = Math.max(fitZoom - 2, -6);
                if (typeof this.map.setMinZoom === 'function') this.map.setMinZoom(desiredMinZoom);
            } catch (_) {}
        }

        // Mark initial fit done so we don't force-reset zoom on later navigations.
        this._didInitialFit = true;

        // Debug helper: click to print pixel coords (useful for calibrating image mode)
        if (mapConfig?.debugCalibration) {
            try {
                this.map.on('click', (e) => {
                    const mode = getMapRenderMode();
                    const x = Number(e.latlng?.lng ?? 0);
                    const y = Number(e.latlng?.lat ?? 0);
                    console.log(`[MDT MAP CLICK][dispatch] mode=${mode} x=${x.toFixed(2)} y=${y.toFixed(2)}`);
                });
            } catch (_) {}
        }
    }

    onMessage(data) {
        if (data.action === 'setCalls') this.handleSetCalls(data.calls);
        if (data.action === 'setUnits' && Array.isArray(data.units)) this.updateUnitMarkers(data.units);
    }

    handleSetCalls(calls) {
        const incoming = calls || [];
        // Fast signature to skip redundant re-renders (JSON.stringify can be expensive in CEF).
        // Keep it deterministic by sorting IDs.
        let signature = '';
        try {
            const parts = new Array(incoming.length);
            for (let i = 0; i < incoming.length; i++) {
                const c = incoming[i] || {};
                const coords = c.coords ? `${c.coords.x ?? ''},${c.coords.y ?? ''},${c.coords.z ?? ''}` : '';
                const units = (c.assignedUnits && c.assignedUnits.length) ? c.assignedUnits.length : (c.assignedUnitNames && c.assignedUnitNames.length) ? c.assignedUnitNames.length : 0;
                parts[i] = `${c.id ?? ''}|${c.status ?? ''}|${c.priority ?? ''}|${units}|${coords}`;
            }
            parts.sort();
            signature = parts.join('~');
        } catch (_) {
            signature = String(incoming.length);
        }
        if (signature === this.lastCallSignature) return;
        this.lastCallSignature = signature;
        this.allCalls = incoming;
        this.currentCalls = this.getVisibleCalls();
        if (this.selectedCallId && !this.currentCalls.some(c => c.id === this.selectedCallId)) {
            this.selectedCallId = null;
            this.closeModal();
        }
        const newCalls = [];
        const incomingIds = new Set();
        this.allCalls.forEach(c => { incomingIds.add(c.id); if (!this.previousCallIds.has(c.id)) newCalls.push(c); });
        this.previousCallIds = incomingIds;
        this.renderCallsList();
        this.updateMarkers();
        this.updateCallCount();
        setTimeout(() => { newCalls.forEach(c => { if (c.coords) this.pingCall(c); }); }, 100);
    }

    renderCallsList() {
        const list = document.getElementById('dispatchCallsList');
        if (!list) return;
        if (this.currentCalls.length === 0) { list.innerHTML = '<div class="empty-message">No active calls</div>'; return; }
        const statusOrder = { pending:0, accepted:1, completed:2 };
        const sorted = [...this.currentCalls].sort((a,b)=>{ const sd=statusOrder[a.status]-statusOrder[b.status]; if (sd!==0) return sd; return b.priority-a.priority; });
        list.innerHTML = sorted.map(call => {
            const selectedClass = (this.selectedCallId && call.id === this.selectedCallId) ? ' selected' : '';
            const title = escapeHtml(call.title || 'Call');
            const location = escapeHtml(call.locationLabel || 'Unknown');
            const timeAgo = this.formatTimeAgo(call.createdAt);
            const priority = Number(call.priority) || 2;
            const idLabel = escapeHtml(String(call.id || ''));
            
            // Build units display string
            let unitsDisplay = 'No units assigned';
            if (call.assignedUnitNames && call.assignedUnitNames.length > 0) {
                unitsDisplay = call.assignedUnitNames.map(name => escapeHtml(name)).join(', ');
            } else if (call.assignedUnits && call.assignedUnits.length > 0) {
                unitsDisplay = call.assignedUnits.map(unit => {
                    const name = escapeHtml(unit.name || unit.callsign || 'Unit');
                    const callsign = unit.callsign ? ` (${escapeHtml(unit.callsign)})` : '';
                    return name + callsign;
                }).join(', ');
            }

            return `
                <div class="dispatch-call-card${selectedClass}" onclick="router.pages.get('dispatch').selectCall('${call.id}')">
                    <div class="dispatch-call-top">
                        <div class="dispatch-call-badges">
                            <span class="dispatch-badge dispatch-badge-priority priority-${priority}">P${priority}</span>
                            <span class="dispatch-badge dispatch-badge-id">${idLabel}</span>
                        </div>
                        <div class="dispatch-call-title">${title}</div>
                    </div>
                    <div class="dispatch-call-details">
                        <div class="dispatch-call-row">
                            <span class="dispatch-call-ico" aria-hidden="true">
                                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"></circle><polyline points="12 6 12 12 16 14"></polyline></svg>
                            </span>
                            <span>Dispatch time: <span class="dispatch-call-muted">${timeAgo}</span></span>
                        </div>
                        <div class="dispatch-call-row">
                            <span class="dispatch-call-ico" aria-hidden="true">
                                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 10c0 6-9 13-9 13S3 16 3 10a9 9 0 0 1 18 0Z"></path><circle cx="12" cy="10" r="3"></circle></svg>
                            </span>
                            <span>Location: <span class="dispatch-call-muted">${location}</span></span>
                        </div>
                        <div class="dispatch-call-row">
                            <span class="dispatch-call-ico" aria-hidden="true">
                                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 17v-5"></path><path d="M12 7v.01"></path><circle cx="12" cy="12" r="10"></circle></svg>
                            </span>
                            <span>Units: <span class="dispatch-call-muted">${unitsDisplay}</span></span>
                        </div>
                        <div class="dispatch-call-row dispatch-call-hint">
                            <span class="dispatch-call-ico" aria-hidden="true">
                                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"></circle><line x1="12" y1="16" x2="12" y2="12"></line><line x1="12" y1="8" x2="12.01" y2="8"></line></svg>
                            </span>
                            <span>Click on the alert to see more details</span>
                        </div>
                    </div>
                </div>
            `;
        }).join('');
    }

    updateCallCount() { const el = document.getElementById('dispatchCallCount'); if (el) el.textContent = this.currentCalls.length; }

    updateMarkers() {
        if (this.markerUpdateTimeout) clearTimeout(this.markerUpdateTimeout);
        this.markerUpdateTimeout = setTimeout(() => {
            const currentIds = new Set(this.currentCalls.map(c=>c.id));
            for (const [id, marker] of this.markers.entries()) { if (!currentIds.has(id)) { this.markersLayer.removeLayer(marker); this.markers.delete(id); } }
            this.currentCalls.forEach(call => this.upsertMarker(call));
        }, 80);
    }

    getCallMarkerLabel(call) {
        const t = (call?.callType || call?.type || '').toString().toLowerCase();
        if (t.includes('shot')) return 'SF';
        if (t.includes('vehicle') || t.includes('theft') || t.includes('gta')) return 'VT';
        if (t.includes('homicide') || t.includes('murder')) return 'HM';
        // Fallback: show the numeric priority if present
        const p = Number(call?.priority);
        if (Number.isFinite(p) && p >= 1 && p <= 3) return `P${p}`;
        return '!';
    }

    makeCallPinIcon(color, label) {
        return L.divIcon({
            className: 'dispatch-call-pin-icon',
            iconSize: [28, 34],
            iconAnchor: [14, 34],
            popupAnchor: [0, -30],
            html: `<div class="dispatch-call-pin" style="--pin:${color}"><div class="dispatch-call-pin-label">${escapeHtml(label || '')}</div></div>`
        });
    }

    upsertMarker(call) {
        if (!call.coords || call.coords.x === undefined) return;
        const latLng = this.worldToLatLng(call.coords.x, call.coords.y);
        // Use CSS variable for accent colors if available, fallback to defaults
        const accentPrimary = getComputedStyle(document.documentElement).getPropertyValue('--accent-primary').trim() || '#2196F3';
        const colorByStatus = { pending:'#F44336', accepted: accentPrimary, completed:'#757575' };
        const color = colorByStatus[call.status] || '#ff8e53';
        if (this.markers.has(call.id)) {
            const marker = this.markers.get(call.id);
            marker.setLatLng(latLng);
            if (marker.setIcon) {
                const label = this.getCallMarkerLabel(call);
                marker.setIcon(this.makeCallPinIcon(color, label));
            }
        } else {
            const label = this.getCallMarkerLabel(call);
            const marker = L.marker(latLng, { icon: this.makeCallPinIcon(color, label) }).bindPopup(`<div>${escapeHtml(call.title)}</div>`);
            marker.addTo(this.markersLayer);
            this.markers.set(call.id, marker);
        }
    }

    pingCall(call) {
        if (!this.markersLayer || !call.coords) return;
        const latLng = this.worldToLatLng(call.coords.x, call.coords.y);
        const pulse = L.circle(latLng, { radius: 40, color:'#ff5252', weight:2, fillColor:'#ff5252', fillOpacity:0.35, interactive:false }).addTo(this.markersLayer);
        setTimeout(() => { try { this.markersLayer.removeLayer(pulse); } catch (_) {} }, 2500);
    }

    selectCall(callId) {
        this.selectedCallId = callId;
        const call = this.currentCalls.find(c => c.id === callId);
        if (!call) return;
        if (call.coords && call.coords.x !== undefined) {
            const latLng = this.worldToLatLng(call.coords.x, call.coords.y);
            const isImage = getMapRenderMode() === 'image';
            this.map.setView(latLng, this.map.getZoom(), { animate: !isImage });
        }
        this.renderCallsList();
        this.openCallModal(call);
    }

    openCallModal(call) {
        document.getElementById('modalCallTitle').textContent = call.title || 'Call';
        document.getElementById('modalCallId').textContent = call.id || '';
        document.getElementById('modalCallStatus').textContent = (statusesConfig[call.status]?.label || call.status || '');
        document.getElementById('modalCallPriority').textContent = (prioritiesConfig[call.priority]?.label || ('P'+call.priority));
        document.getElementById('modalCallLocation').textContent = call.locationLabel || 'Unknown Area';
        if (call.coords) document.getElementById('modalCallCoords').textContent = `X: ${call.coords.x?.toFixed?.(2) ?? call.coords.x}, Y: ${call.coords.y?.toFixed?.(2) ?? call.coords.y}`;
        document.getElementById('modalCallTime').textContent = call.createdAt ? new Date(call.createdAt * 1000).toLocaleString() : '';
        const unitsLabel = (call.assignedUnitNames && call.assignedUnitNames.length)
            ? call.assignedUnitNames.join(', ')
            : ((call.assignedUnits && call.assignedUnits.length) ? `${call.assignedUnits.length} units` : 'No units assigned');
        document.getElementById('modalCallUnits').textContent = unitsLabel;
        const delBtn = document.getElementById('modalDeleteBtn');
        if (userPermissions && userPermissions.isSupervisor) delBtn.classList.remove('hidden'); else delBtn.classList.add('hidden');
        document.getElementById('callDetailModal').classList.remove('hidden');
    }

    closeModal() { document.getElementById('callDetailModal').classList.add('hidden'); }

    handleMapClick(_e) {}

    worldToLatLng(x, y) { return worldToLatLng(x, y); }

    updateUnitMarkers(units) {
        if (!this.map || !this.unitMarkersLayer) return;
        const incoming = new Set();
        units.forEach(u => {
            if (!u || !u.coords || u.coords.x === undefined) return;
            const id = u.source || u.citizenid || u.callsign || u.name || Math.random().toString(36).slice(2);
            incoming.add(id);
            const ll = this.worldToLatLng(u.coords.x, u.coords.y);
            const isVeh = !!u.inVehicle;
            const color = u.attachedCallId ? '#ffb347' : '#4dd0e1';
            if (this.unitMarkers.has(id)) {
                const marker = this.unitMarkers.get(id);
                if (marker.setLatLng) marker.setLatLng(ll);
                if (marker.setStyle) marker.setStyle({ color, fillColor: color });
            } else {
                let marker;
                if (isVeh) {
                    const carIcon = L.divIcon({ className:'unit-car-icon', iconSize:[24,18], html:`<div style="width:22px;height:16px;border-radius:4px;background:${color};border:1px solid rgba(0,0,0,0.35);"></div>` });
                    marker = L.marker(ll, { icon: carIcon, title: u.name || 'Unit' });
                } else {
                    marker = L.circleMarker(ll, { radius:8, color, fillColor: color, fillOpacity:0.9, weight:1 });
                }
                marker.bindTooltip(u.name || 'Unit', { direction:'top', offset:[0,-8], opacity:0.85 });
                marker.addTo(this.unitMarkersLayer);
                this.unitMarkers.set(id, marker);
            }
        });
        for (const [id, marker] of this.unitMarkers.entries()) {
            if (!incoming.has(id)) { this.unitMarkersLayer.removeLayer(marker); this.unitMarkers.delete(id); }
        }
    }

    startAnimation() {
        // Placeholder for animation startup logic
        // Can be implemented to add UI animations or periodic updates as needed
    }
}

// ============================================================================
// Charges Page
// ============================================================================
class ChargesPage extends BasePage {
    constructor() {
        super('charges', 'Charges');
        this.allCharges = [];
        this.filteredCharges = [];
        this.currentPage = 1;
        this.pageSize = 9;
    }

    mount(root) {
        super.mount(root);
        const canCreate = userInfo.rankLevel >= 4;
        
        root.innerHTML = `
            <div class="charges-page">
                <div class="page-header">
                    <div class="search-bar-container">
                        <input type="text" id="chargesSearchInput" class="search-input" placeholder="Search charges by code, name, category, or description...">
                    </div>
                    ${canCreate ? `<button id="createChargeBtn" class="btn-primary">+ Create Charge</button>` : ''}
                </div>
                
                <div class="charges-table-container">
                    <table class="charges-table">
                        <thead>
                            <tr>
                                <th>Code</th>
                                <th>Name</th>
                                <th>Description</th>
                                <th>Category</th>
                                <th>Fine</th>
                                <th>Bail</th>
                                <th>Prison Time</th>
                                ${canCreate ? '<th>Actions</th>' : ''}
                            </tr>
                        </thead>
                        <tbody id="chargesTableBody">
                            <tr><td colspan="${canCreate ? '8' : '7'}" style="text-align: center; padding: 40px;">Loading charges...</td></tr>
                        </tbody>
                    </table>
                </div>

                <div class="pagination-footer" style="margin-top: 14px;">
                    <span id="chargesPaginationText">Showing 0 to 0 of 0 Charges</span>
                    <div class="pagination-buttons">
                        <button id="chargesPrevBtn" class="pagination-btn">Previous</button>
                        <button id="chargesNextBtn" class="pagination-btn">Next</button>
                    </div>
                </div>
            </div>
        `;

        // Load charges
        this.loadCharges();

        // Setup event listeners
        const searchInput = document.getElementById('chargesSearchInput');
        if (searchInput) {
            searchInput.addEventListener('input', () => this.filterCharges(searchInput.value));
        }

        document.getElementById('chargesPrevBtn')?.addEventListener('click', () => {
            if (this.currentPage > 1) {
                this.currentPage--;
                this.renderCharges();
            }
        });
        document.getElementById('chargesNextBtn')?.addEventListener('click', () => {
            const maxPage = Math.max(1, Math.ceil(this.filteredCharges.length / this.pageSize));
            if (this.currentPage < maxPage) {
                this.currentPage++;
                this.renderCharges();
            }
        });

        if (canCreate) {
            const createBtn = document.getElementById('createChargeBtn');
            if (createBtn) {
                createBtn.addEventListener('click', () => this.openChargeModal());
            }
            
            // Set up the charge save button listener - remove old one first to prevent duplicates
            const saveBtn = document.getElementById('chargeCreateBtn');
            if (saveBtn) {
                console.log('[MDT DEBUG] Removing old listeners and setting up new click handler for chargeCreateBtn');
                // Clone to remove all event listeners
                const newSaveBtn = saveBtn.cloneNode(true);
                saveBtn.parentNode.replaceChild(newSaveBtn, saveBtn);
                
                // Add fresh listener
                newSaveBtn.addEventListener('click', (e) => {
                    console.log('[MDT DEBUG] chargeCreateBtn clicked!');
                    e.preventDefault();
                    e.stopPropagation();
                    this.saveCharge();
                });
            } else {
                console.error('[MDT DEBUG] chargeCreateBtn not found in DOM!');
            }
        }

        BasePage.updatePageTitle();
    }

    loadCharges() {
        sendCallback('getCharges', {}, (result) => {
            if (result && result.charges) {
                this.allCharges = result.charges;
                this.filteredCharges = [...this.allCharges];
                this.renderCharges();
            } else {
                this.showError('Failed to load charges');
            }
        });
    }

    filterCharges(searchTerm) {
        const term = searchTerm.toLowerCase().trim();
        if (!term) {
            this.filteredCharges = [...this.allCharges];
        } else {
            this.filteredCharges = this.allCharges.filter(charge => {
                return (
                    charge.code?.toLowerCase().includes(term) ||
                    charge.name?.toLowerCase().includes(term) ||
                    charge.category?.toLowerCase().includes(term) ||
                    (charge.description || '')?.toLowerCase?.().includes?.(term)
                );
            });
        }
        this.currentPage = 1;
        this.renderCharges();
    }

    renderCharges() {
        const tbody = document.getElementById('chargesTableBody');
        if (!tbody) return;

        const canEdit = userInfo.rankLevel >= 4;

        const total = this.filteredCharges.length;
        const maxPage = Math.max(1, Math.ceil(total / this.pageSize));
        if (this.currentPage > maxPage) this.currentPage = maxPage;
        const startIdx = (this.currentPage - 1) * this.pageSize;
        const endIdx = Math.min(startIdx + this.pageSize, total);

        const paginationText = document.getElementById('chargesPaginationText');
        if (paginationText) {
            paginationText.textContent = total
                ? `Showing ${startIdx + 1} to ${endIdx} of ${total} Charges`
                : 'Showing 0 to 0 of 0 Charges';
        }
        const prevBtn = document.getElementById('chargesPrevBtn');
        const nextBtn = document.getElementById('chargesNextBtn');
        if (prevBtn) prevBtn.disabled = this.currentPage <= 1;
        if (nextBtn) nextBtn.disabled = this.currentPage >= maxPage;

        if (total === 0) {
            tbody.innerHTML = `<tr><td colspan="${canEdit ? '8' : '7'}" style="text-align: center; padding: 40px; color: rgba(255,255,255,0.5);">No charges found</td></tr>`;
            return;
        }

        const pageRows = this.filteredCharges.slice(startIdx, endIdx);
        tbody.innerHTML = pageRows.map(charge => `
            <tr data-charge-id="${charge.id}">
                <td><strong>${escapeHtml(charge.code || 'N/A')}</strong></td>
                <td>${escapeHtml(charge.name || 'Unnamed')}</td>
                <td>${escapeHtml(charge.description || '')}</td>
                <td><span class="badge">${escapeHtml(charge.category || 'General')}</span></td>
                <td>$${(charge.fineAmount || charge.fine_amount || 0).toLocaleString()}</td>
                <td>$${(charge.bailAmount || charge.bail_amount || 0).toLocaleString()}</td>
                <td>${charge.prisonTime || charge.jail_time || 0} months</td>
                ${canEdit ? `
                    <td>
                        <button class="btn-icon edit-charge" data-charge-id="${charge.id}" title="Edit">
                            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"></path>
                                <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"></path>
                            </svg>
                        </button>
                        <button class="btn-icon delete-charge" data-charge-id="${charge.id}" title="Delete">
                            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                <polyline points="3 6 5 6 21 6"></polyline>
                                <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
                            </svg>
                        </button>
                    </td>
                ` : ''}
            </tr>
        `).join('');

        // Attach event listeners for edit/delete
        if (canEdit) {
            tbody.querySelectorAll('.edit-charge').forEach(btn => {
                btn.addEventListener('click', (e) => {
                    const chargeId = e.currentTarget.dataset.chargeId;
                    const charge = this.allCharges.find(c => c.id == chargeId);
                    if (charge) this.openChargeModal(charge);
                });
            });

            tbody.querySelectorAll('.delete-charge').forEach(btn => {
                btn.addEventListener('click', (e) => {
                    const chargeId = e.currentTarget.dataset.chargeId;
                    const charge = this.allCharges.find(c => c.id == chargeId);
                    if (!charge) return;
                    (async () => {
                        const ok = await mdtConfirmSafe(`Delete charge "${charge.code} - ${charge.name}"?`);
                        if (ok) this.deleteCharge(chargeId);
                    })();
                });
            });
        }
    }

    openChargeModal(charge = null) {
        const modal = document.getElementById('newChargeModal');
        if (!modal) return;

        // Set modal title
        const modalTitle = modal.querySelector('.modal-header h3');
        if (modalTitle) {
            modalTitle.textContent = charge ? 'Edit Charge' : 'Create New Charge';
        }

        // Get all form elements
        const idInput = document.getElementById('chargeIdInput');
        const codeInput = document.getElementById('chargeCodeInput');
        const nameInput = document.getElementById('chargeNameInput');
        const catInput = document.getElementById('chargeCategoryInput');
        const fineInput = document.getElementById('chargeFineInput');
        const bailInput = document.getElementById('chargeBailInput');
        const prisonInput = document.getElementById('chargePrisonInput');
        
        // Populate form fields
        if (idInput) idInput.value = charge ? charge.id : '';
        if (codeInput) codeInput.value = charge ? charge.code : '';
        if (nameInput) nameInput.value = charge ? charge.name : '';
        if (catInput) catInput.value = charge ? charge.category : '';
        
        // Initialize/reset RTE for description
        const descContent = charge ? (charge.description || '') : '';
        if (!window.__rteChargeDescription) {
            window.__rteChargeDescription = createRTE('chargeDescriptionInput', {
                placeholder: 'Charge description...',
                initialContent: descContent,
                minHeight: '80px',
                maxHeight: '30vh'
            });
        } else {
            window.__rteChargeDescription.setValue(descContent);
        }
        
        // Set numeric values - use actual numeric properties
        if (fineInput) {
            const fineVal = charge ? (charge.fineAmount || charge.fine_amount || 0) : 0;
            fineInput.value = String(parseInt(fineVal) || 0);
        }
        if (bailInput) {
            const bailVal = charge ? (charge.bailAmount || charge.bail_amount || 0) : 0;
            bailInput.value = String(parseInt(bailVal) || 0);
        }
        if (prisonInput) {
            const prisonVal = charge ? (charge.prisonTime || charge.jail_time || 0) : 0;
            prisonInput.value = String(parseInt(prisonVal) || 0);
        }
        
        console.log('[MDT DEBUG] openChargeModal - Modal opened for', charge ? 'edit' : 'create');
        console.log('[MDT DEBUG] openChargeModal - Numeric inputs set to:', {
            fine: fineInput?.value,
            bail: bailInput?.value,
            prison: prisonInput?.value
        });

        // Update button text
        const createBtn = document.getElementById('chargeCreateBtn');
        if (createBtn) {
            createBtn.textContent = charge ? 'Update Charge' : 'Create Charge';
        }

        modal.classList.remove('hidden');
    }

    saveCharge() {
        // Get all input elements
        const idEl = document.getElementById('chargeIdInput');
        const codeEl = document.getElementById('chargeCodeInput');
        const nameEl = document.getElementById('chargeNameInput');
        const catEl = document.getElementById('chargeCategoryInput');
        const fineEl = document.getElementById('chargeFineInput');
        const bailEl = document.getElementById('chargeBailInput');
        const prisonEl = document.getElementById('chargePrisonInput');
        
        // Get text values
        const id = idEl ? idEl.value.trim() : '';
        const code = codeEl ? codeEl.value.trim() : '';
        const name = nameEl ? nameEl.value.trim() : '';
        // Get description from RTE if available
        let description = '';
        if (window.__rteChargeDescription) {
            description = window.__rteChargeDescription.getPlainText().trim();
        } else {
            const descEl = document.getElementById('chargeDescriptionInput');
            description = descEl ? descEl.value.trim() : '';
        }
        const category = catEl ? catEl.value.trim() : '';
        
        // For number inputs, get the actual numeric value directly without trim
        const fineValue = fineEl ? fineEl.value : '0';
        const bailValue = bailEl ? bailEl.value : '0';
        const prisonValue = prisonEl ? prisonEl.value : '0';
        
        console.log('[MDT DEBUG] === SAVING CHARGE ===');
        console.log('[MDT DEBUG] Elements found:', { idEl: !!idEl, codeEl: !!codeEl, nameEl: !!nameEl, fineEl: !!fineEl, bailEl: !!bailEl, prisonEl: !!prisonEl });
        console.log('[MDT DEBUG] Raw element values - Fine El:', fineEl?.value, 'Bail El:', bailEl?.value, 'Prison El:', prisonEl?.value);
        console.log('[MDT DEBUG] Raw input values (no trim) - Fine:', fineValue, 'Bail:', bailValue, 'Prison:', prisonValue);
        
        // Parse as integers
        const fine = parseInt(fineValue, 10) || 0;
        const bail = parseInt(bailValue, 10) || 0;
        const prison = parseInt(prisonValue, 10) || 0;
        
        console.log('[MDT DEBUG] Parsed integers - Fine:', fine, 'Bail:', bail, 'Prison:', prison);
        console.log('[MDT DEBUG] Type check:', typeof fine, typeof bail, typeof prison);

        if (!code || !name) {
            mdtToastSafe('Code and Name are required', 'error');
            return;
        }

        const chargeData = {
            id: id || undefined,
            code,
            name,
            description,
            category,
            fine_amount: fine,
            bail_amount: bail,
            jail_time: prison
        };

        console.log('[MDT DEBUG] FINAL DATA OBJECT:', JSON.stringify(chargeData));

        const action = id ? 'updateCharge' : 'createCharge';
        console.log('[MDT DEBUG] Action:', action);
        
        sendCallback(action, chargeData, (result) => {
            console.log('[MDT DEBUG] Server callback result:', JSON.stringify(result));
            console.log('[MDT DEBUG] Result type:', typeof result);
            console.log('[MDT DEBUG] Result.success:', result?.success);
            
            if (result && result.success) {
                console.log('[MDT DEBUG] Update successful - closing modal and reloading charges');
                const modal = document.getElementById('newChargeModal');
                if (modal) modal.classList.add('hidden');
                this.loadCharges();
            } else {
                console.error('[MDT DEBUG] Update failed:', result?.error || 'Unknown error');
                if (result?.requested) {
                    console.error('[MDT DEBUG] Requested numeric values:', result.requested);
                }
                if (result?.charge) {
                    console.error('[MDT DEBUG] DB returned charge row:', result.charge);
                }
                if (result?.diagnostics) {
                    console.error('[MDT DEBUG] DB diagnostics:', result.diagnostics);
                    const conn = result.diagnostics.connection || {};
                    const tbl = result.diagnostics.table || {};
                    const triggerCount = Array.isArray(result.diagnostics.triggers) ? result.diagnostics.triggers.length : 0;
                    const triggerNames = Array.isArray(result.diagnostics.triggers)
                        ? result.diagnostics.triggers.map(t => t.TRIGGER_NAME).filter(Boolean).join(', ')
                        : '';
                    const colInfo = Array.isArray(result.diagnostics.columns) ? result.diagnostics.columns.map(c => `${c.COLUMN_NAME}:${c.COLUMN_TYPE}`).join(', ') : '';
                    const connStr = conn.db ? `${conn.db}@${conn.host || '?'}:${conn.port || '?'}` : '(unknown)';
                    const tableStr = (tbl.TABLE_TYPE || tbl.ENGINE) ? `${tbl.TABLE_TYPE || '?'} / ${tbl.ENGINE || '?'}` : '(unknown)';
                    const triggersLine = `Triggers: ${triggerCount}` + (triggerNames ? ` (${triggerNames})` : '');
                    const msg = String(result?.error || 'Failed to save charge') +
                        "\r\n\r\n" +
                        "Diagnostics:" +
                        "\r\n" +
                        `DB: ${connStr}` +
                        "\r\n" +
                        `Table: ${tableStr}` +
                        "\r\n" +
                        `Columns: ${colInfo || '(none)'}` +
                        "\r\n" +
                        triggersLine +
                        "\r\n" +
                        "(Open console for full details)";
                    console.warn('[MDT DEBUG] Charges save diagnostics:', msg);
                    mdtToastSafe('Failed to save charge (see console for details)', 'error');
                } else {
                    mdtToastSafe(result?.error || 'Failed to save charge', 'error');
                }
            }
        });
    }

    deleteCharge(chargeId) {
        sendCallback('deleteCharge', { id: chargeId }, (result) => {
            if (result && result.success) {
                this.loadCharges();
            } else {
                mdtToastSafe(result?.error || 'Failed to delete charge', 'error');
            }
        });
    }

    showError(message) {
        const tbody = document.getElementById('chargesTableBody');
        if (tbody) {
            tbody.innerHTML = `<tr><td colspan="7" style="text-align: center; padding: 40px; color: #ff6b6b;">${escapeHtml(message)}</td></tr>`;
        }
    }

    unmount() {
        this.allCharges = [];
        this.filteredCharges = [];
        super.unmount();
    }
}

// ============================================================================
// NUI Message Handling
// ============================================================================

let _dispatchDingCtx = null;
let _dispatchDingUnlockBound = false;

function _bindDispatchDingUnlock() {
    if (_dispatchDingUnlockBound) return;
    _dispatchDingUnlockBound = true;
    const unlock = () => {
        try {
            if (_dispatchDingCtx && _dispatchDingCtx.state === 'suspended') {
                _dispatchDingCtx.resume();
            }
        } catch (_) {}
    };
    // Any user gesture should unlock audio in CEF.
    document.addEventListener('pointerdown', unlock, { passive: true });
    document.addEventListener('keydown', unlock, { passive: true });
}

function _ensureDispatchDingCtx() {
    if (_dispatchDingCtx) return _dispatchDingCtx;
    const Ctx = window.AudioContext || window.webkitAudioContext;
    if (!Ctx) return null;
    try {
        _dispatchDingCtx = new Ctx();
        _bindDispatchDingUnlock();
    } catch (_) {
        _dispatchDingCtx = null;
    }
    return _dispatchDingCtx;
}

function playDispatchDing(opts) {
    const ctx = _ensureDispatchDingCtx();
    if (!ctx) return;

    // Try to resume if browser suspended it.
    try { if (ctx.state === 'suspended') ctx.resume(); } catch (_) {}

    const o = (opts && typeof opts === 'object') ? opts : { volume: opts };
    const v = Math.max(0, Math.min(Number(o.volume) || 1.0, 10.0));
    const waveform = String(o.waveform || 'sine');
    const tone1 = Math.max(40, Math.min(Number(o.tone1Hz) || 880, 4000));
    const tone2 = Number.isFinite(Number(o.tone2Hz)) ? Math.max(40, Math.min(Number(o.tone2Hz), 4000)) : null;
    const tone2AtMs = Math.max(0, Math.min(Number(o.tone2AtMs) || 0, 2000));
    const durationMs = Math.max(60, Math.min(Number(o.durationMs) || 200, 2000));

    const now = ctx.currentTime;

    const osc = ctx.createOscillator();
    osc.type = (['sine','triangle','square','sawtooth'].includes(waveform) ? waveform : 'sine');
    osc.frequency.setValueAtTime(tone1, now);
    if (tone2 && tone2AtMs > 0) {
        osc.frequency.setValueAtTime(tone2, now + (tone2AtMs / 1000));
    }

    const gain = ctx.createGain();
    gain.gain.setValueAtTime(0.0, now);

    // Base gain tuned for NUI; multiplied by requested volume.
    const peak = 0.08 * v;
    gain.gain.linearRampToValueAtTime(peak, now + 0.01);
    gain.gain.exponentialRampToValueAtTime(0.0001, now + (durationMs / 1000));

    osc.connect(gain);
    gain.connect(ctx.destination);

    osc.start(now);
    osc.stop(now + (durationMs / 1000) + 0.02);
}

function playDispatchPanicDing(opts) {
    const o = (opts && typeof opts === 'object') ? opts : {};
    const baseVolume = Math.max(0.25, Number(o.volume) || 1.0);
    const wave = o.waveform || 'square';
    const pattern = [0, 170, 340];
    pattern.forEach((delayMs, index) => {
        setTimeout(() => {
            playDispatchDing({
                volume: baseVolume,
                waveform: wave,
                tone1Hz: index === 1 ? 980 : 880,
                durationMs: 130
            });
        }, delayMs);
    });
}

window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data || typeof data !== 'object') return;
    switch (data.action) {
        case 'custodyTimer': {
            const el = document.getElementById('custodyOverlay');
            const timeEl = document.getElementById('custodyOverlayTime');
            const barEl = document.getElementById('custodyOverlayProgress');
            if (!el || !timeEl || !barEl) break;

            const show = data.show === true;
            el.classList.toggle('hidden', !show);
            el.setAttribute('aria-hidden', show ? 'false' : 'true');

            if (!show) break;

            const secondsLeft = Math.max(0, Number(data.secondsLeft) || 0);
            const mins = Math.floor(secondsLeft / 60);
            const secs = Math.floor(secondsLeft % 60);
            timeEl.textContent = `${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;

            const progress = Math.max(0, Math.min(1, Number(data.progress) || 0));
            barEl.style.width = `${Math.round(progress * 1000) / 10}%`;
            break;
        }
        case 'open': 
        case 'openTablet': handleOpen(data); break;
        case 'close':
        case 'closeTablet': handleClose(); break;
        case 'show': setMDTVisible(true); break;
        case 'hide': setMDTVisible(false); break;
        case 'setMDTVisible': setMDTVisible(data.visible !== false); break;
        case 'showCitationPaper': showCitationPaper(data.citation || data.payload || {}); break;
        case 'hideCitationPaper': hideCitationPaper(); break;
        case 'updateDispatchOverlay':
            try { updateDispatchOverlay(data.calls || [], data.currentIndex || 0); } catch (_) {}
            break;
        case 'setDispatchOverlayVisibility':
            try {
                __dispatchOverlayVisible = data.visible !== false;
                updateDispatchOverlay(__dispatchOverlayCurrentCalls || [], __dispatchOverlayCurrentIndex || 0);
            } catch (_) {}
            break;
        case 'cctvViewer': setCCTVViewerOverlay(data.show === true, data.label); break;
        case 'cctvCaptureMask': setCCTVCaptureMask(data.show === true); break;
        case 'cctvPreview':
            // Send to the CCTV page instance even if it's not the current route.
            try { router?.pages?.get('cctv')?.onMessage?.(data); } catch (_) {}
            break;
        case 'playDispatchDing':
            try { playDispatchDing(data); } catch (_) {}
            break;
        case 'playDispatchPanicDing':
            try { playDispatchPanicDing(data); } catch (_) {}
            break;
        case 'setCalls':
            try { __mdtLastDispatchCalls = Array.isArray(data.calls) ? data.calls : (data.calls || null); } catch (_) {}
            if (router) router.message(data);
            break;
        case 'setUnits':
            try { __mdtLastDispatchUnits = Array.isArray(data.units) ? data.units : (data.units || null); } catch (_) {}
            if (router) router.message(data);
            break;
        case 'playerPos': if (router) router.message(data); break;
        case 'setUserInfo': updateUserInfo(data.user); break;
        case 'setPersonalInfo': {
            // Live updates (duty/status/callsign/etc)
            try {
                const merged = Object.assign({}, userInfo, data);
                delete merged.action;
                updateUserInfo(merged);
            } catch (_) {}
            if (router) router.message(data);
            break;
        }
        case 'setUserPerms': userPermissions = data.permissions; break;
        // Extended pages routing
        case 'setCitizens': if (router) router.message(data); break;
        case 'setVehicles': if (router) router.message(data); break;
        case 'setWarrants': if (router) router.message(data); break;
        case 'setIncidents': if (router) router.message(data); break;
        case 'setReports': if (router) router.message(data); break;
        case 'setFTOReports': if (router) router.message(data); break;
        case 'setEvidence': if (router) router.message(data); break;
        case 'setDashboard':
            try { dashboardCache = data.data || null; } catch (_) {}
            if (router) router.message(data);
            break;
        case 'bulletinCreated': {
            const b = data.bulletin;
            if (!b) break;
            try {
                dashboardCache = dashboardCache || { bulletins: [], warrants: [] };
                dashboardCache.bulletins = Array.isArray(dashboardCache.bulletins) ? dashboardCache.bulletins : [];
                dashboardCache.bulletins.unshift({ title: b.title, body: b.body, createdAt: b.createdAt });
                dashboardCache.bulletins = dashboardCache.bulletins.slice(0, 10);
            } catch (_) {}
            try { router?.pages?.get('dashboard')?.onMessage?.({ action: 'setDashboard', data: dashboardCache }); } catch (_) {}
            break;
        }
    }
});

// ESC should close the MDT while NUI has focus.
// This calls the existing Lua NUI callback "close" which already shuts the MDT.
document.addEventListener('keydown', (e) => {
    const target = e.target;
    const tagName = target && target.tagName ? String(target.tagName).toLowerCase() : '';
    const isTypingTarget = !!(
        target &&
        (
            target.isContentEditable ||
            tagName === 'input' ||
            tagName === 'textarea' ||
            tagName === 'select'
        )
    );

    if (e.key === 'Escape') {
        try {
            const citationOverlay = document.getElementById('citationPaperOverlay');
            if (citationOverlay && !citationOverlay.classList.contains('hidden')) {
                sendCallback('closeCitationPaper', {}, () => {});
                return;
            }
            sendCallback('close', {}, () => {});
        } catch (_) {}
        return;
    }

    if (isTypingTarget) return;

    const overlay = document.getElementById('dispatchOverlay');
    const overlayActive = __dispatchOverlayVisible && overlay && !overlay.classList.contains('hidden');
    if (!overlayActive) return;

    if (e.key === 'ArrowLeft') {
        e.preventDefault();
        dispatchOverlayPrev();
        return;
    }
    if (e.key === 'ArrowRight') {
        e.preventDefault();
        dispatchOverlayNext();
    }
}, true);

function setMDTVisible(visible) {
    const app = document.getElementById('app');
    if (!app) return;
    if (visible) app.classList.remove('hidden');
    else app.classList.add('hidden');
}

function formatCitationDate(rawValue) {
    if (rawValue === undefined || rawValue === null) return 'Unknown Date';
    const raw = String(rawValue).trim();
    if (raw === '') return 'Unknown Date';

    let d;
    if (/^-?\d+(?:\.\d+)?$/.test(raw)) {
        let ts = Number(raw);
        if (Number.isFinite(ts)) {
            ts = Math.trunc(ts);
            if (ts < 1000000000000) ts *= 1000;
            d = new Date(ts);
        }
    }
    if (!d || isNaN(d.getTime())) {
        const isoLike = raw.includes(' ') && !raw.includes('T') ? raw.replace(' ', 'T') : raw;
        d = new Date(isoLike);
    }
    if (!d || isNaN(d.getTime())) return raw;

    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    const year = d.getFullYear();
    return `${month}.${day}.${year}`;
}

function showCitationPaper(citation) {
    const overlay = document.getElementById('citationPaperOverlay');
    if (!overlay) return;

    const tabletFrame = document.getElementById('tabletFrame');
    const app = document.getElementById('app');
    __citationPrevTabletHidden = tabletFrame ? tabletFrame.classList.contains('hidden') : true;
    __citationPrevAppHidden = app ? app.classList.contains('hidden') : true;

    // Keep citation paper isolated from the MDT shell (mechanic receipt-style behavior).
    if (tabletFrame) tabletFrame.classList.add('hidden');
    if (app) app.classList.add('hidden');

    const data = (citation && typeof citation === 'object') ? citation : {};
    const fineAmount = Number(data.fineAmount || data.fine || 0);
    const paidCandidates = [
        data.finePaid,
        data.paid,
        data.fineSuccess,
        data.paymentStatus,
        data.status,
        data.payment_state,
        data.isPaid,
        data.paidStatus
    ];
    const isPaid = paidCandidates.some((value) => {
        if (value === true) return true;
        if (value === false || value === null || value === undefined) return false;

        if (typeof value === 'number') {
            return Number.isFinite(value) && value > 0;
        }

        const asText = String(value).trim().toLowerCase();
        if (asText === '') return false;

        if (/^-?\d+(?:\.\d+)?$/.test(asText)) {
            const asNum = Number(asText);
            return Number.isFinite(asNum) && asNum > 0;
        }

        return (
            asText === 'true' ||
            asText === 'paid' ||
            asText === 'complete' ||
            asText === 'completed' ||
            asText === 'success' ||
            asText === 'succeeded' ||
            asText === 'yes' ||
            asText === 'y'
        );
    });

    // Runtime fallback styling: keeps modal behavior even if stylesheet parsing fails.
    overlay.style.position = 'fixed';
    overlay.style.inset = '0';
    overlay.style.zIndex = '24000';
    overlay.style.display = 'flex';
    overlay.style.alignItems = 'center';
    overlay.style.justifyContent = 'center';
    overlay.style.background = 'rgba(5,8,14,0.42)';
    overlay.style.padding = '24px';

    const sheet = overlay.querySelector('.citation-paper-sheet');
    if (sheet) {
        sheet.style.width = 'min(500px, 94vw)';
        sheet.style.minHeight = '640px';
        sheet.style.maxHeight = '92vh';
        sheet.style.overflowY = 'auto';
        sheet.style.borderRadius = '8px';
        sheet.style.border = '1px solid #c6b794';
        sheet.style.background = 'linear-gradient(180deg, rgba(249,244,230,0.98) 0%, rgba(238,226,196,0.98) 100%), repeating-linear-gradient(0deg, rgba(114,92,54,0.07) 0px, rgba(114,92,54,0.07) 1px, transparent 1px, transparent 18px)';
        sheet.style.color = '#17120b';
        sheet.style.boxShadow = '0 18px 42px rgba(0,0,0,0.42)';
        sheet.style.padding = '20px 18px 22px';
        sheet.style.fontFamily = '"Courier New", "Consolas", monospace';
    }

    const uidEl = document.getElementById('citationPaperUid');
    const statusEl = document.getElementById('citationPaperStatus');
    const citizenEl = document.getElementById('citationPaperCitizen');
    const citizenIdEl = document.getElementById('citationPaperCitizenId');
    const officerEl = document.getElementById('citationPaperOfficer');
    const issuedAtEl = document.getElementById('citationPaperIssuedAt');
    const titleEl = document.getElementById('citationPaperTitle');
    const fineEl = document.getElementById('citationPaperFine');
    const notesEl = document.getElementById('citationPaperNotes');

    if (uidEl) uidEl.textContent = String(data.citationUid || data.uid || 'N/A');
    if (statusEl) statusEl.textContent = isPaid ? 'PAID' : 'UNPAID';
    if (citizenEl) citizenEl.textContent = String(data.citizenName || data.name || 'Unknown Citizen');
    if (citizenIdEl) citizenIdEl.textContent = String(data.citizenId || 'N/A');
    if (officerEl) officerEl.textContent = String(data.officerName || 'Unknown Officer');
    if (issuedAtEl) issuedAtEl.textContent = formatCitationDate(data.issuedAt || data.createdAt || data.date || data.timestamp);
    if (titleEl) titleEl.textContent = String(data.title || 'Citation');
    if (fineEl) fineEl.textContent = `$${(Number.isFinite(fineAmount) ? fineAmount : 0).toLocaleString()}`;
    if (notesEl) {
        const notes = String(data.description || data.notes || '').trim();
        notesEl.textContent = notes !== '' ? notes : 'No additional notes.';
    }

    // Reset animation state so each open replays the notebook-style motion.
    overlay.classList.remove('citation-book-open');
    if (sheet) {
        sheet.classList.remove('citation-paper-sheet-open');
        void sheet.offsetWidth;
    }

    overlay.classList.remove('hidden');
    overlay.style.display = 'flex';
    overlay.setAttribute('aria-hidden', 'false');

    overlay.classList.add('citation-book-open');
    if (sheet) sheet.classList.add('citation-paper-sheet-open');
}

function hideCitationPaper() {
    const overlay = document.getElementById('citationPaperOverlay');
    if (!overlay) return;

    const tabletFrame = document.getElementById('tabletFrame');
    const app = document.getElementById('app');
    const sheet = overlay.querySelector('.citation-paper-sheet');

    overlay.classList.remove('citation-book-open');
    if (sheet) sheet.classList.remove('citation-paper-sheet-open');

    overlay.classList.add('hidden');
    overlay.style.display = 'none';
    overlay.setAttribute('aria-hidden', 'true');

    // Restore MDT shell only if it was visible before citation opened.
    if (tabletFrame && !__citationPrevTabletHidden) tabletFrame.classList.remove('hidden');
    if (app && !__citationPrevAppHidden) app.classList.remove('hidden');

    __citationPrevTabletHidden = true;
    __citationPrevAppHidden = true;
}

function updateDispatchOverlay(calls, currentIndex) {
    const overlay = document.getElementById('dispatchOverlay');
    if (!overlay) return;

    __dispatchOverlayCurrentCalls = Array.isArray(calls) ? calls : [];

    const countEl = overlay.querySelector('.dispatch-overlay-count');
    const typeEl = overlay.querySelector('.dispatch-overlay-type');
    const timeEl = overlay.querySelector('.dispatch-overlay-time');
    const descEl = overlay.querySelector('.dispatch-overlay-desc');
    const locEl = overlay.querySelector('.dispatch-overlay-location');
    const hintEl = overlay.querySelector('.dispatch-overlay-hint');

    if (!__dispatchOverlayVisible) {
        overlay.classList.remove('dispatch-overlay-panic');
        overlay.classList.add('hidden');
        return;
    }

    if (!calls || calls.length === 0) {
        overlay.classList.remove('dispatch-overlay-panic');
        overlay.classList.remove('hidden');
        __dispatchOverlayCurrentIndex = 0;

        if (countEl) countEl.textContent = '';
        if (typeEl) typeEl.textContent = 'No active calls';
        if (timeEl) timeEl.textContent = '';
        if (locEl) locEl.textContent = 'Awaiting incoming dispatch calls';
        if (descEl) descEl.textContent = 'No units are currently requesting response.';
        if (hintEl) hintEl.textContent = 'No active calls';

        const prevBtn = overlay.querySelector('.dispatch-overlay-prev');
        const nextBtn = overlay.querySelector('.dispatch-overlay-next');
        if (prevBtn) prevBtn.style.display = 'none';
        if (nextBtn) nextBtn.style.display = 'none';
        return;
    }

    overlay.classList.remove('hidden');
    const idx = Math.max(0, Math.min(currentIndex, calls.length - 1));
    __dispatchOverlayCurrentIndex = idx;
    const call = calls[idx] || {};
    overlay.classList.toggle('dispatch-overlay-panic', isPanicDispatchCall(call));

    const callType = String(call.callType || call.type || call.code || call.title || 'Dispatch');
    const location = String(call.location || call.locationLabel || call.address || call.street || call.zone || '');
    const description = String(call.description || call.details || call.message || call.note || '');

    const rawTime = call.time || call.callTime || call.createdAt || call.created_at || call.timestamp;
    let displayTime = '';
    if (typeof rawTime === 'number' || /^\d+$/.test(String(rawTime || ''))) {
        const t = Number(rawTime);
        if (Number.isFinite(t) && t > 0) {
            const d = new Date((t < 1000000000000 ? t * 1000 : t));
            displayTime = d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
        }
    } else {
        const parsed = new Date(rawTime || '');
        if (!Number.isNaN(parsed.getTime())) {
            displayTime = parsed.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
        } else {
            displayTime = String(rawTime || '');
        }
    }

    const fallbackDesc = description || String(call.title || callType || `Call ${idx + 1}`);

    if (countEl) countEl.textContent = calls.length > 1 ? `${idx + 1} / ${calls.length}` : '';
    if (typeEl) typeEl.textContent = callType;
    if (timeEl) timeEl.textContent = displayTime;
    if (descEl) descEl.textContent = fallbackDesc;
    if (locEl) locEl.textContent = location;
    if (hintEl) hintEl.textContent = '[G] Respond';

    const prevBtn = overlay.querySelector('.dispatch-overlay-prev');
    const nextBtn = overlay.querySelector('.dispatch-overlay-next');
    if (prevBtn) prevBtn.style.display = calls.length > 1 ? '' : 'none';
    if (nextBtn) nextBtn.style.display = calls.length > 1 ? '' : 'none';
}

function dispatchOverlayRespond() {
    sendCallback('respondToCall', {}, () => {});
}

function dispatchOverlayPrev() {
    if (Array.isArray(__dispatchOverlayCurrentCalls) && __dispatchOverlayCurrentCalls.length > 1) {
        const len = __dispatchOverlayCurrentCalls.length;
        const nextIdx = ((__dispatchOverlayCurrentIndex - 1) + len) % len;
        updateDispatchOverlay(__dispatchOverlayCurrentCalls, nextIdx);
    }
    sendCallback('dispatchOverlayPrev', {}, () => {});
}

function dispatchOverlayNext() {
    if (Array.isArray(__dispatchOverlayCurrentCalls) && __dispatchOverlayCurrentCalls.length > 1) {
        const len = __dispatchOverlayCurrentCalls.length;
        const nextIdx = (__dispatchOverlayCurrentIndex + 1) % len;
        updateDispatchOverlay(__dispatchOverlayCurrentCalls, nextIdx);
    }
    sendCallback('dispatchOverlayNext', {}, () => {});
}

function setCCTVViewerOverlay(show, label) {
    const overlay = document.getElementById('cctvViewerOverlay');
    const tabletFrame = document.getElementById('tabletFrame');
    if (!overlay) return;

    // Hide the rest of the MDT UI while the CCTV viewer is active
    if (show) {
        document.body.classList.add('cctv-view-active');
        setMDTVisible(false);
        if (tabletFrame) tabletFrame.classList.add('hidden');
    } else {
        document.body.classList.remove('cctv-view-active');
        setMDTVisible(true);
        if (tabletFrame) tabletFrame.classList.remove('hidden');
    }

    if (show) overlay.classList.remove('hidden');
    else overlay.classList.add('hidden');

    overlay.setAttribute('aria-hidden', show ? 'false' : 'true');

    const labelEl = document.getElementById('cctvViewerLabel');
    if (labelEl) {
        if (label === undefined || label === null || String(label).trim() === '') labelEl.textContent = '—';
        else labelEl.textContent = String(label);
    }
}

function setCCTVCaptureMask(show) {
    const el = document.getElementById('cctvCaptureMask');
    if (!el) return;
    if (show) el.classList.remove('hidden');
    else el.classList.add('hidden');
    el.setAttribute('aria-hidden', show ? 'false' : 'true');
}

function deferPageUpgrade(routeName, globalClassName, title) {
    // In FiveM NUI, messages can arrive while the HTML is still loading.
    // If that happens, optional page scripts (like cctv.js) may not have run yet.
    // This helper upgrades the placeholder page once the class becomes available.
    const maxWaitMs = 4000;
    const pollEveryMs = 50;
    const startedAt = Date.now();
    const timer = setInterval(() => {
        try {
            if (!router) {
                clearInterval(timer);
                return;
            }
            const Cls = window[globalClassName];
            if (typeof Cls === 'function') {
                console.log(`[APP] Upgrading page '${routeName}' -> ${globalClassName}`);
                router.register(routeName, new Cls(), title);
                if (router.current === routeName) {
                    router.set(routeName);
                }
                clearInterval(timer);
                return;
            }
            if (Date.now() - startedAt > maxWaitMs) {
                console.warn(`[APP] Timed out waiting for ${globalClassName}; keeping fallback page for '${routeName}'.`);
                clearInterval(timer);
            }
        } catch (e) {
            console.error('[APP] deferPageUpgrade error:', e);
            clearInterval(timer);
        }
    }, pollEveryMs);
}

async function handleOpen(data) {
    const contentRoot = document.getElementById('pageContent');
    if (!contentRoot) {
        __mdtDeferredOpenPayload = data || {};
        if (!__mdtDeferredOpenTimer) {
            __mdtDeferredOpenAttempts = 0;
            __mdtDeferredOpenTimer = setInterval(() => {
                const root = document.getElementById('pageContent');
                __mdtDeferredOpenAttempts += 1;
                if (!root) {
                    if (__mdtDeferredOpenAttempts >= 120) {
                        clearInterval(__mdtDeferredOpenTimer);
                        __mdtDeferredOpenTimer = null;
                        console.error('[APP] pageContent never became available; aborting deferred open.');
                    }
                    return;
                }

                clearInterval(__mdtDeferredOpenTimer);
                __mdtDeferredOpenTimer = null;
                const pending = __mdtDeferredOpenPayload || {};
                __mdtDeferredOpenPayload = null;
                handleOpen(pending);
            }, 25);
        }
        return;
    }

    const tabletFrame = document.getElementById('tabletFrame');
    const appDiv = document.getElementById('app');

    // Ensure NUI console logging matches Lua Config.Debug.
    try {
        const dbg = data && data.config && data.config.debug === true;
        if (typeof window.__mdtSetDebug === 'function') window.__mdtSetDebug(dbg);
    } catch (_) {}
    
    // Show both tablet frame and app
    if (tabletFrame) tabletFrame.classList.remove('hidden');
    if (appDiv) appDiv.classList.remove('hidden');
    
    // Set tablet title from config
    const titleLabel = document.getElementById('tabletTitleLabel');
    if (titleLabel && data.config && data.config.tabletTitle) {
        titleLabel.textContent = data.config.tabletTitle;
    }
    
    if (data.config) {
        mdtConfig = data.config || {};
        window.mdtConfig = mdtConfig;
        mapConfig = data.config.map;
        prioritiesConfig = data.config.priorities;
        statusesConfig = data.config.statuses;
        console.log('[APP] mdtConfig.localeData:', mdtConfig.localeData ? 'present (' + Object.keys(mdtConfig.localeData).length + ' keys)' : 'MISSING');
        if (mdtConfig.localeData) {
            applyLocaleData(mdtConfig.localeData);
            // Restore saved language preference
            const savedLanguage = localStorage.getItem('mdt_language');
            if (savedLanguage) {
                updateLocale(savedLanguage);
            }
        } else {
            console.error('[LOCALE] localeData not provided in config; using fallback strings');
        }
    }

    // Image mode can be heavy (7k x 9k PNG). Defer preload until after first paint
    // so Dashboard opens instantly, but still warms cache for quick Dispatch switching.
    const deferPreload = () => {
        try { preloadMapImageIfNeeded(); } catch (_) {}
    };
    try {
        if (typeof window.requestIdleCallback === 'function') window.requestIdleCallback(deferPreload, { timeout: 250 });
        else setTimeout(deferPreload, 50);
    } catch (_) {
        setTimeout(deferPreload, 50);
    }
    if (data.permissions) userPermissions = data.permissions;
    if (data.user) updateUserInfo(data.user);
    if (!router) {
        router = new Router(contentRoot);
        const safePage = (route, ctor, fallbackTitle) => {
            try {
                return ctor();
            } catch (e) {
                console.error(`[APP] Failed to init page '${route}', using fallback:`, e);
                return new BasePage(route, fallbackTitle);
            }
        };

        router.register('dashboard', safePage('dashboard', () => new DashboardPage(), 'Dashboard'), t('page_dashboard', 'Dashboard'));
        router.register('dispatch', safePage('dispatch', () => new DispatchPage(), 'Dispatch'), t('page_dispatch', 'Dispatch'));
        console.log('[APP] CCTVPage class available:', typeof window.CCTVPage !== 'undefined');
        const CCTVCls = window.CCTVPage || null;
        if (CCTVCls) {
            console.log('[APP] Registering CCTVPage');
            router.register('cctv', safePage('cctv', () => new CCTVCls(), 'CCTV'), t('page_cctv', 'CCTV'));
        } else {
            console.log('[APP] CCTVPage not found, using BasePage');
            router.register('cctv', new BasePage('cctv','CCTV'), t('page_cctv', 'CCTV'));
            deferPageUpgrade('cctv', 'CCTVPage', 'CCTV');
        }
        // Prefer extended pages if available, else placeholders
        const CitizensCls = window.CitizenSearchPage || null;
        const VehiclesCls = window.VehicleSearchPage || null;
        const WarrantCls = window.WarrantSearchPage || null;
        const IncidentsCls = window.IncidentsPage || null;
        const ReportsCls = window.ReportsPage || null;
        const FTOCls = window.FTOReportsPage || null;
        const EvidenceCls = window.EvidencePage || null;
        const CriminalCodeCls = window.CriminalCodePage || null;
        const SOPCls = window.SOPPage || null;
        const TemplatesCls = window.TemplatesPage || null;
        router.register('citizens', CitizensCls ? safePage('citizens', () => new CitizensCls(), 'Citizens') : new BasePage('citizens','Citizens'), t('page_citizens', 'Citizens'));
        router.register('vehicles', VehiclesCls ? safePage('vehicles', () => new VehiclesCls(), 'Vehicles') : new BasePage('vehicles','Vehicles'), t('page_vehicles', 'Vehicles'));
        router.register('reports', ReportsCls ? safePage('reports', () => new ReportsCls(), 'Reports') : new BasePage('reports','Reports'), t('page_reports', 'Reports'));
        const RosterCls = window.RosterPage || null;
        router.register('roster', RosterCls ? safePage('roster', () => new RosterCls(), 'Roster') : new BasePage('roster','Roster'), t('page_roster', 'Roster'));
        router.register('warrant', WarrantCls ? safePage('warrant', () => new WarrantCls(), 'Warrant') : new BasePage('warrant','Warrant'), t('page_warrant', 'Warrant'));
        router.register('criminalcode', CriminalCodeCls ? safePage('criminalcode', () => new CriminalCodeCls(), 'Criminal Code') : new BasePage('criminalcode','Criminal Code'), t('nav_criminalcode', 'Criminal Code'));
        const WeaponsCls = window.WeaponsRegistryPage;
        router.register('weapons', WeaponsCls ? safePage('weapons', () => new WeaponsCls(), 'Weapons') : new BasePage('weapons','Weapons'), t('page_weapons', 'Weapons'));
        router.register('incidents', IncidentsCls ? safePage('incidents', () => new IncidentsCls(), 'Incidents') : new BasePage('incidents','Incidents'), t('page_incidents', 'Incidents'));
        router.register('fto', FTOCls ? safePage('fto', () => new FTOCls(), 'FTO Reports') : new BasePage('fto','FTO Reports'), t('page_fto', 'FTO Reports'));
        router.register('charges', safePage('charges', () => new ChargesPage(), 'Charges'), 'Charges');
        router.register('evidence', EvidenceCls ? safePage('evidence', () => new EvidenceCls(), 'Evidence') : new BasePage('evidence','Evidence'), 'Evidence');
        router.register('templates', TemplatesCls ? safePage('templates', () => new TemplatesCls(), 'Templates') : new BasePage('templates','Templates'), 'Templates');
        router.register('sop', SOPCls ? safePage('sop', () => new SOPCls(), 'SOP') : new BasePage('sop','SOP'), 'SOP');
        const OfficersCls = window.OfficersManagementPage || null;
        router.register('officers', OfficersCls ? safePage('officers', () => new OfficersCls(), 'Officers Management') : new BasePage('officers','Officers Management'), 'Officers Management');

        try {
            setupNavigationHandlers();
        } catch (e) {
            console.error('[APP] setupNavigationHandlers failed:', e);
        }

        try {
            router.set('dashboard');
        } catch (e) {
            console.error('[APP] Failed to route dashboard:', e);
        }

        // Start warming Dispatch immediately after initial dashboard paint.
        // This makes the first switch to Dispatch instant.
        (window.requestAnimationFrame || window.setTimeout)(() => {
            try { __mdtWarmDispatchInBackground(); } catch (_) {}
        }, 0);
    } else if (!router.root) {
        router.root = contentRoot;
    }
    if (Array.isArray(data.calls)) {
        try { __mdtLastDispatchCalls = data.calls; } catch (_) {}
        if (router) router.message({ action:'setCalls', calls: data.calls });
    }
    BasePage.updatePageTitle();
}

function handleClose() { 
    const tabletFrame = document.getElementById('tabletFrame');
    const appDiv = document.getElementById('app');
    
    // Hide both tablet frame and app
    if (tabletFrame) tabletFrame.classList.add('hidden');
    if (appDiv) appDiv.classList.add('hidden');
}

function updateUserInfo(info) {
    userInfo = Object.assign({}, userInfo, (info || {}));
    window.playerGrade = userInfo?.rankLevel || 0;
    document.getElementById('userName').textContent = userInfo?.name || 'Officer';
    document.getElementById('userRank').textContent = userInfo?.grade || userInfo?.job || 'Police';

    // Sidebar profile reflect
    const name = userInfo?.name || 'Officer';
    const initials = name.split(' ').map(p=>p[0]).slice(0,2).join('').toUpperCase();
    const profileNameEl = document.getElementById('profileName');
    const profileInitials = document.getElementById('profileInitials');
    const avatar = document.getElementById('profileAvatar');
    if (profileNameEl) profileNameEl.textContent = name;
    if (profileInitials) profileInitials.textContent = initials;
    if (avatar && userInfo?.avatarUrl) {
        avatar.style.background = `center/cover no-repeat url('${userInfo.avatarUrl}')`;
        const span = avatar.querySelector('span'); if (span) span.style.display = 'none';
    }

    const normalize = (v) => {
        const s = String(v || '').trim().toLowerCase();
        if (s === 'onduty') return 'on_duty';
        if (s === 'offduty') return 'off_duty';
        if (s === 'onmission') return 'on_mission';
        return s;
    };

    // Sidebar duty (green/gray)
    const dutyEl = document.getElementById('profileDuty');
    if (dutyEl) {
        const duty = normalize(userInfo?.duty) || 'on_duty';
        const offDuty = duty === 'off_duty';
        dutyEl.textContent = offDuty ? t('duty_off_duty', 'Off Duty') : t('duty_on_duty', 'On Duty');
        dutyEl.setAttribute('data-duty', offDuty ? 'off_duty' : 'on_duty');
    }

    // Sidebar status (purple)
    const statusBtn = document.getElementById('profileStatus');
    if (statusBtn) {
        const status = normalize(userInfo?.status) || 'available';
        const labelMap = {
            available: t('status_available', 'Available'),
            unavailable: t('status_unavailable', 'Unavailable'),
            busy: t('status_busy', 'Busy'),
            on_mission: t('status_on_mission', 'On Mission')
        };
        statusBtn.textContent = labelMap[status] || t('status_available', 'Available');
        statusBtn.classList.remove('status-available', 'status-unavailable', 'status-busy', 'status-on_mission');
        statusBtn.classList.add(`status-${status}`);
        statusBtn.setAttribute('data-status', status);
    }
}

function setupNavigationHandlers() {
    document.querySelectorAll('.nav-item').forEach(item => {
        item.addEventListener('click', (e) => { e.preventDefault(); const page = item.dataset.page; if (page && router) router.set(page); });
    });
    const refreshBtn = document.getElementById('refreshBtn');
    if (refreshBtn) refreshBtn.addEventListener('click', () => sendCallback('refresh', {}));
    const closeBtnTopbar = document.getElementById('closeBtn');
    if (closeBtnTopbar) closeBtnTopbar.addEventListener('click', () => sendCallback('close', {}));

    // Sidebar profile editor
    const openBtn = document.getElementById('openProfileEditor');
    const modal = document.getElementById('profileModal');
    const closeBtn = document.getElementById('profileModalClose');
    const avatar = document.getElementById('profileAvatar');
    const saveBtn = document.getElementById('profileSaveBtn');
    const photoInput = document.getElementById('profilePhotoInput');
    const preview = document.getElementById('profileAvatarPreview');
    const nameInput = document.getElementById('profileNameInput');
    const callsignInput = document.getElementById('profileCallsignInput');
    const statusInput = document.getElementById('profileStatusInput');

    function openProfile() {
        if (!modal) return;
        nameInput.value = userInfo?.name || '';
        callsignInput.value = userInfo?.callsign || '';
        statusInput.value = (userInfo?.status || 'available');
        if (userInfo?.avatarUrl) {
            preview.style.background = `center/cover no-repeat url('${userInfo.avatarUrl}')`;
            const s = preview.querySelector('span'); if (s) s.style.display='none';
        }
        modal.classList.remove('hidden');
    }

    function closeProfile() { if (modal) modal.classList.add('hidden'); }

    if (openBtn) openBtn.onclick = openProfile;
    if (avatar) avatar.onclick = openProfile;
    if (closeBtn) closeBtn.onclick = closeProfile;
    if (modal) modal.addEventListener('click', (e)=>{ if (e.target === modal) closeProfile(); });

    if (photoInput) photoInput.addEventListener('change', (e) => {
        const file = e.target.files[0];
        if (!file) return;
        const reader = new FileReader();
        reader.onload = () => {
            const url = reader.result;
            preview.style.background = `center/cover no-repeat url('${url}')`;
            const s = preview.querySelector('span'); if (s) s.style.display='none';
            userInfo = { ...(userInfo||{}), avatarUrl: url };
            updateUserInfo(userInfo);
        };
        reader.readAsDataURL(file);
    });

    if (saveBtn) saveBtn.onclick = () => {
        const status = statusInput.value;
        userInfo = { ...(userInfo||{}), name: nameInput.value || userInfo?.name, callsign: callsignInput.value || userInfo?.callsign, status };
        updateUserInfo(userInfo);
        // Persist to server
        sendCallback('saveProfile', { name: userInfo.name, callsign: userInfo.callsign, status, avatarUrl: userInfo.avatarUrl });
        closeProfile();
    };

    // ========================================================================
    // SETTINGS - COLOR MANAGEMENT
    // ========================================================================

    const COLOR_PRESETS = {
        default: {
            // Topbar
            topbarBg: 'linear-gradient(90deg, #1a1f3a 0%, #2d3561 100%)',
            topbarText: '#e0e6f2',
            
            // Sidebar
            sidebarBg: 'linear-gradient(180deg, #1a1f3a 0%, #0f1428 100%)',
            sidebarBorder: 'rgba(255,255,255,0.15)',
            sidebarItemBg: 'rgba(255,255,255,0.05)',
            sidebarItemText: '#e0e6f2',
            sidebarItemActive: '#ff8e53',
            sidebarItemActiveBg: 'rgba(255,142,83,0.1)',
            sidebarItemActiveHover: '#ffa076',
            
            // Tablet Frame
            tabletFrameBg: 'linear-gradient(135deg, #060916 0%, #060916 100%)',
            tabletFrameBorder: 'rgba(255, 255, 255, 0.15)',
            tabletTitlebarBg: 'linear-gradient(180deg, rgba(30, 35, 60, 0.9) 0%, rgba(20, 25, 45, 0.9) 100%)',
            
            // Main Content
            contentBg: 'transparent',
            panelBg: 'rgba(15, 20, 40, 0.78)',
            pageContentBg: 'linear-gradient(135deg, #0a0e27 0%, #1a1f3a 100%)',
            
            // Cards & Modals
            cardBg: 'rgba(30,35,60,0.9)',
            cardBorder: 'rgba(255,255,255,0.1)',
            cardText: '#e0e6f2',
            
            // Section Headers
            sectionHeaderBg: '#0f172a',
            sectionHeaderText: '#e0e6f2',
            
            // Buttons
            btnPrimaryBg: 'linear-gradient(135deg, #2196f3, #1976d2)',
            btnPrimaryText: '#fff',
            btnPrimaryHover: 'linear-gradient(135deg, #42a5f5, #1e88e5)',
            btnSecondaryBg: 'rgba(255,255,255,0.06)',
            btnSecondaryBorder: 'rgba(255,255,255,0.15)',
            btnSecondaryText: '#e0e6f2',
            btnSecondaryHover: 'rgba(255,255,255,0.1)',
            btnDangerBg: 'linear-gradient(135deg, #f44336, #d32f2f)',
            btnDangerHover: 'linear-gradient(135deg, #ef5350, #e53935)',
            btnSuccessBg: 'linear-gradient(135deg, #4CAF50, #2E7D32)',
            btnSuccessHover: 'linear-gradient(135deg, #66BB6A, #388E3C)',
            
            // Form Elements
            inputBg: 'rgba(255,255,255,0.06)',
            inputBorder: 'rgba(255,255,255,0.12)',
            inputText: '#e0e6f2',
            inputPlaceholder: 'rgba(255,255,255,0.55)',
            inputFocus: 'rgba(59,130,246,0.45)',
            inputFocusGlow: 'rgba(59,130,246,0.15)',
            
            // Tabs
            tabBg: 'rgba(255,255,255,0.06)',
            tabBorder: 'rgba(255,255,255,0.12)',
            tabText: '#e0e6f2',
            tabActiveBg: 'rgba(255,255,255,0.12)',
            tabActiveBorder: '#ff8e53',
            tabHoverBg: 'rgba(255,255,255,0.1)',
            
            // Badges & Chips
            badgeBg: 'rgba(255,255,255,0.06)',
            badgeBorder: 'rgba(255,255,255,0.15)',
            badgeText: '#e0e6f2',
            badgeSuccessBorder: '#4CAF50',
            badgeSuccessText: '#4CAF50',
            badgeWarnBorder: '#ffb347',
            badgeWarnText: '#ffb347',
            badgeInfoBorder: '#4dd0e1',
            badgeInfoText: '#4dd0e1',
            
            // Text & Emphasis
            textPrimary: '#e0e6f2',
            textSecondary: 'rgba(255,255,255,0.6)',
            textTertiary: 'rgba(255,255,255,0.4)',
            textMuted: 'rgba(255,255,255,0.55)',
            
            // Borders & Dividers
            borderLight: 'rgba(255,255,255,0.08)',
            borderMedium: 'rgba(255,255,255,0.12)',
            borderDark: 'rgba(255,255,255,0.15)',
            
            // Status Colors
            statusSuccess: '#4CAF50',
            statusWarning: '#ffb347',
            statusError: '#F44336',
            statusInfo: '#4dd0e1',
            
            // Accent Highlights
            accentPrimary: '#2196f3',
            accentHover: '#42a5f5',
            accentActive: '#1976d2',
            
            // Scrollbar
            scrollbarTrack: 'rgba(255,255,255,0.03)',
            scrollbarThumb: 'linear-gradient(180deg, rgba(90,160,255,0.8), rgba(60,120,220,0.8))',
            scrollbarThumbHover: 'linear-gradient(180deg, rgba(120,180,255,1), rgba(80,140,255,1))',
            
            // Navigation Icons
            iconDashboard: '#5AA2FF',
            iconDispatch: '#00D4FF',
            iconCctv: '#5AA2FF',
            iconCitizens: '#B388FF',
            iconVehicles: '#FF7EB3',
            iconWarrant: '#FFC75F',
            iconCourt: '#FF9671',
            iconCriminalcode: '#F9F871',
            iconWeapons: '#FF6B6B',
            iconReports: '#77DD77',
            iconIncidents: '#00E5A3',
            iconFto: '#A0CED9',
            iconRoster: '#FFD166',
            iconSop: '#BBD0FF',
            iconOfficers: '#F4A261',
            
            // Profile Avatar & Dispatch
            profileAvatarGradient1: '#2b335e',
            profileAvatarGradient2: '#151b34',
            dispatchBadgeId: 'rgba(100, 120, 180, 0.6)',
            dispatchBadgePriority1: 'rgba(244, 67, 54, 0.9)',
            dispatchBadgePriority2: 'rgba(255, 179, 71, 0.9)',
            dispatchBadgePriority3: 'rgba(33, 150, 243, 0.9)',
            dispatchOverlayBg: 'linear-gradient(160deg, rgba(10, 16, 28, 0.72), rgba(8, 13, 24, 0.82))',
            dispatchOverlayBorder: 'rgba(96, 165, 250, 0.55)',
            dispatchOverlayShadow: '0 16px 38px rgba(0,0,0,0.55)',
            dispatchOverlayHeaderBg: 'rgba(59, 130, 246, 0.24)',
            dispatchOverlayHeaderBorder: 'rgba(59, 130, 246, 0.3)',
            dispatchOverlayTitleText: 'rgba(191, 219, 254, 1)',
            dispatchOverlayMetaText: 'rgba(148, 163, 184, 0.92)',
            dispatchOverlayTypeText: 'rgba(255, 255, 255, 0.98)',
            dispatchOverlayLocationText: 'rgba(147, 197, 253, 0.96)',
            dispatchOverlayDescriptionText: 'rgba(226, 232, 240, 0.95)',
            dispatchOverlayFooterBorder: 'rgba(255,255,255,0.12)',
            dispatchOverlayButtonBg: 'rgba(59, 130, 246, 0.2)',
            dispatchOverlayButtonBorder: 'rgba(59, 130, 246, 0.45)',
            dispatchOverlayButtonText: 'rgba(191, 219, 254, 0.98)',
            dispatchOverlayButtonHoverBg: 'rgba(59, 130, 246, 0.35)',
            
            // Modal Gradients
            modalGradient1: 'rgba(25,30,45,0.95)',
            modalGradient2: 'rgba(20,25,40,0.95)',
            
            // Card Avatar Gradient
            cardAvatarGradient1: '#2b335e',
            cardAvatarGradient2: '#151b34',
            
            // Warrant Status Cleared
            warrantStatusClearedColor: '#77aaff',
            warrantStatusClearedBorder: 'rgba(33,150,243,0.45)',
            warrantStatusClearedBg: 'rgba(33,150,243,0.15)',
            
            // Incident Details Button
            incidentDetailsButtonBg: 'linear-gradient(135deg, rgba(33,150,243,0.3), rgba(33,150,243,0.15))',
            incidentDetailsButtonBorder: 'rgba(33,150,243,0.5)',
            incidentDetailsButtonColor: '#77aaff',
            incidentDetailsButtonHoverBg: 'linear-gradient(135deg, rgba(33,150,243,0.5), rgba(33,150,243,0.3))',
            incidentDetailsButtonHoverBorder: 'rgba(33,150,243,0.8)',
            incidentDetailsButtonHoverShadow: 'rgba(33,150,243,0.2)',
            
            // Incident Editable Focus
            incidentEditableFocusBorder: 'rgba(33,150,243,0.5)',
            incidentEditableFocusBox: 'rgba(33,150,243,0.1)',
            
            // Callsign & Status Colors
            callsignColor: 'rgba(90, 160, 255, 0.9)',
            statusDropdownFocusBorder: 'rgba(90, 160, 255, 0.6)',
            statusDropdownFocusBg: 'rgba(90, 160, 255, 0.1)',
            updateBtnBg: 'rgba(90, 160, 255, 0.3)',
            updateBtnBorder: 'rgba(90, 160, 255, 0.5)',
            updateBtnHoverBg: 'rgba(90, 160, 255, 0.5)',
            updateBtnHoverBorder: 'rgba(90, 160, 255, 0.8)',
            
            // Chat Colors
            chatSelfAuthorColor: 'rgba(90, 160, 255, 0.7)',
            chatSelfBg: 'rgba(90, 160, 255, 0.2)',
            chatSelfBorder: 'rgba(90, 160, 255, 0.5)',
            chatInputFocusBorder: 'rgba(90, 160, 255, 0.6)',
            chatInputFocusBg: 'rgba(90, 160, 255, 0.1)',
            chatSendBtnBg: 'rgba(90, 160, 255, 0.3)',
            chatSendBtnBorder: 'rgba(90, 160, 255, 0.5)'
        },
        dark: {
            topbarBg: 'linear-gradient(90deg, #000000 0%, #1a1a1a 100%)',
            topbarText: '#ffffff',
            sidebarBg: 'linear-gradient(180deg, #0a0a0a 0%, #000000 100%)',
            sidebarBorder: 'rgba(255,255,255,0.15)',
            sidebarItemBg: 'rgba(255,255,255,0.05)',
            sidebarItemText: '#f0f0f0',
            sidebarItemActive: '#ffffff',
            sidebarItemActiveBg: 'rgba(255,255,255,0.12)',
            sidebarItemActiveHover: '#ffffff',
            tabletFrameBg: 'linear-gradient(135deg, #000000 0%, #000000 100%)',
            tabletFrameBorder: 'rgba(255, 255, 255, 0.2)',
            tabletTitlebarBg: 'linear-gradient(180deg, #1a1a1a 0%, #0f0f0f 100%)',
            contentBg: 'transparent',
            panelBg: 'rgba(10, 10, 10, 0.9)',
            pageContentBg: 'linear-gradient(135deg, #000000 0%, #0a0a0a 100%)',
            cardBg: '#1a1a1a',
            cardBorder: 'rgba(255,255,255,0.15)',
            cardText: '#ffffff',
            sectionHeaderBg: '#0f0f0f',
            sectionHeaderText: '#ffffff',
            btnPrimaryBg: 'linear-gradient(135deg, #333333, #1a1a1a)',
            btnPrimaryText: '#ffffff',
            btnPrimaryHover: 'linear-gradient(135deg, #404040, #262626)',
            btnSecondaryBg: 'rgba(255,255,255,0.08)',
            btnSecondaryBorder: 'rgba(255,255,255,0.15)',
            btnSecondaryText: '#f0f0f0',
            btnSecondaryHover: 'rgba(255,255,255,0.12)',
            btnDangerBg: 'linear-gradient(135deg, #c41e3a, #8B0000)',
            btnDangerHover: 'linear-gradient(135deg, #dc2626, #b91c1c)',
            btnSuccessBg: 'linear-gradient(135deg, #2d5a2d, #1a3a1a)',
            btnSuccessHover: 'linear-gradient(135deg, #3d7a3d, #2a4a2a)',
            inputBg: 'rgba(255,255,255,0.06)',
            inputBorder: 'rgba(255,255,255,0.12)',
            inputText: '#ffffff',
            inputPlaceholder: 'rgba(255,255,255,0.5)',
            inputFocus: 'rgba(255,255,255,0.2)',
            inputFocusGlow: 'rgba(255,255,255,0.1)',
            tabBg: 'rgba(255,255,255,0.06)',
            tabBorder: 'rgba(255,255,255,0.12)',
            tabText: '#f0f0f0',
            tabActiveBg: 'rgba(255,255,255,0.12)',
            tabActiveBorder: '#ffffff',
            tabHoverBg: 'rgba(255,255,255,0.1)',
            badgeBg: 'rgba(255,255,255,0.08)',
            badgeBorder: 'rgba(255,255,255,0.15)',
            badgeText: '#ffffff',
            badgeSuccessBorder: '#4CAF50',
            badgeSuccessText: '#4CAF50',
            badgeWarnBorder: '#FFC107',
            badgeWarnText: '#FFC107',
            badgeInfoBorder: '#2196F3',
            badgeInfoText: '#2196F3',
            textPrimary: '#ffffff',
            textSecondary: 'rgba(255,255,255,0.7)',
            textTertiary: 'rgba(255,255,255,0.5)',
            textMuted: 'rgba(255,255,255,0.55)',
            borderLight: 'rgba(255,255,255,0.08)',
            borderMedium: 'rgba(255,255,255,0.12)',
            borderDark: 'rgba(255,255,255,0.15)',
            statusSuccess: '#4CAF50',
            statusWarning: '#FFC107',
            statusError: '#F44336',
            statusInfo: '#2196F3',
            
            // Accent Highlights
            accentPrimary: '#404040',
            accentHover: '#505050',
            accentActive: '#2a2a2a',
            
            scrollbarTrack: 'rgba(255,255,255,0.05)',
            scrollbarThumb: 'linear-gradient(180deg, rgba(100,100,100,0.8), rgba(80,80,80,0.8))',
            scrollbarThumbHover: 'linear-gradient(180deg, rgba(150,150,150,1), rgba(120,120,120,1))',
            iconDashboard: '#5AA2FF',
            iconDispatch: '#00D4FF',
            iconCctv: '#5AA2FF',
            iconCitizens: '#B388FF',
            iconVehicles: '#FF7EB3',
            iconWarrant: '#FFC75F',
            iconCourt: '#FF9671',
            iconCriminalcode: '#F9F871',
            iconWeapons: '#FF6B6B',
            iconReports: '#77DD77',
            iconIncidents: '#00E5A3',
            iconFto: '#A0CED9',
            iconRoster: '#FFD166',
            iconSop: '#BBD0FF',
            iconOfficers: '#F4A261',
            
            // Profile Avatar & Dispatch
            profileAvatarGradient1: '#1a1a1a',
            profileAvatarGradient2: '#0f0f0f',
            dispatchBadgeId: 'rgba(80, 80, 80, 0.7)',
            dispatchBadgePriority1: 'rgba(244, 67, 54, 0.9)',
            dispatchBadgePriority2: 'rgba(255, 179, 71, 0.9)',
            dispatchBadgePriority3: 'rgba(100, 100, 100, 0.7)',
            dispatchOverlayBg: 'linear-gradient(160deg, rgba(6, 6, 6, 0.84), rgba(18, 18, 18, 0.92))',
            dispatchOverlayBorder: 'rgba(240, 240, 240, 0.35)',
            dispatchOverlayShadow: '0 16px 38px rgba(0,0,0,0.62)',
            dispatchOverlayHeaderBg: 'rgba(255, 255, 255, 0.08)',
            dispatchOverlayHeaderBorder: 'rgba(255, 255, 255, 0.2)',
            dispatchOverlayTitleText: 'rgba(250, 250, 250, 0.98)',
            dispatchOverlayMetaText: 'rgba(212, 212, 212, 0.86)',
            dispatchOverlayTypeText: 'rgba(255, 255, 255, 0.98)',
            dispatchOverlayLocationText: 'rgba(229, 229, 229, 0.95)',
            dispatchOverlayDescriptionText: 'rgba(235, 235, 235, 0.9)',
            dispatchOverlayFooterBorder: 'rgba(255,255,255,0.12)',
            dispatchOverlayButtonBg: 'rgba(255, 255, 255, 0.1)',
            dispatchOverlayButtonBorder: 'rgba(255, 255, 255, 0.3)',
            dispatchOverlayButtonText: 'rgba(250, 250, 250, 0.98)',
            dispatchOverlayButtonHoverBg: 'rgba(255, 255, 255, 0.2)',
            
            // Modal Gradients
            modalGradient1: 'rgba(20,20,20,0.95)',
            modalGradient2: 'rgba(15,15,15,0.95)',
            
            // Card Avatar Gradient
            cardAvatarGradient1: '#1a1a1a',
            cardAvatarGradient2: '#0f0f0f',
            
            // Warrant Status Cleared
            warrantStatusClearedColor: '#5a9eff',
            warrantStatusClearedBorder: 'rgba(100,150,200,0.4)',
            warrantStatusClearedBg: 'rgba(100,150,200,0.1)',
            
            // Incident Details Button
            incidentDetailsButtonBg: 'linear-gradient(135deg, rgba(100,150,200,0.25), rgba(100,150,200,0.1))',
            incidentDetailsButtonBorder: 'rgba(100,150,200,0.4)',
            incidentDetailsButtonColor: '#5a9eff',
            incidentDetailsButtonHoverBg: 'linear-gradient(135deg, rgba(100,150,200,0.4), rgba(100,150,200,0.2))',
            incidentDetailsButtonHoverBorder: 'rgba(100,150,200,0.6)',
            incidentDetailsButtonHoverShadow: 'rgba(100,150,200,0.2)',
            
            // Incident Editable Focus
            incidentEditableFocusBorder: 'rgba(100,150,200,0.4)',
            incidentEditableFocusBox: 'rgba(100,150,200,0.05)',
            
            // Callsign & Status Colors
            callsignColor: 'rgba(100, 150, 200, 0.8)',
            statusDropdownFocusBorder: 'rgba(100, 150, 200, 0.5)',
            statusDropdownFocusBg: 'rgba(100, 150, 200, 0.08)',
            updateBtnBg: 'rgba(100, 150, 200, 0.2)',
            updateBtnBorder: 'rgba(100, 150, 200, 0.4)',
            updateBtnHoverBg: 'rgba(100, 150, 200, 0.35)',
            updateBtnHoverBorder: 'rgba(100, 150, 200, 0.6)',
            
            // Chat Colors
            chatSelfAuthorColor: 'rgba(100, 150, 200, 0.6)',
            chatSelfBg: 'rgba(100, 150, 200, 0.15)',
            chatSelfBorder: 'rgba(100, 150, 200, 0.4)',
            chatInputFocusBorder: 'rgba(100, 150, 200, 0.5)',
            chatInputFocusBg: 'rgba(100, 150, 200, 0.08)',
            chatSendBtnBg: 'rgba(100, 150, 200, 0.2)',
            chatSendBtnBorder: 'rgba(100, 150, 200, 0.4)'
        },
        green: {
            topbarBg: 'linear-gradient(90deg, #0d3d2d 0%, #105d4a 100%)',
            topbarText: '#e0e6f2',
            sidebarBg: 'linear-gradient(180deg, #064e3b 0%, #022c20 100%)',
            sidebarBorder: 'rgba(255,255,255,0.12)',
            sidebarItemBg: 'rgba(255,255,255,0.04)',
            sidebarItemText: '#d1fae5',
            sidebarItemActive: '#10b981',
            sidebarItemActiveBg: 'rgba(16,185,129,0.12)',
            sidebarItemActiveHover: '#6ee7b7',
            tabletFrameBg: 'linear-gradient(135deg, #021f1d 0%, #021f1d 100%)',
            tabletFrameBorder: 'rgba(16, 185, 129, 0.3)',
            tabletTitlebarBg: 'linear-gradient(180deg, rgba(5, 150, 105, 0.8) 0%, rgba(4, 120, 87, 0.8) 100%)',
            contentBg: 'transparent',
            panelBg: 'rgba(6, 78, 59, 0.78)',
            pageContentBg: 'linear-gradient(135deg, #064e3b 0%, #0d3d2d 100%)',
            cardBg: 'rgba(6,78,59,0.9)',
            cardBorder: 'rgba(16,185,129,0.12)',
            cardText: '#d1fae5',
            sectionHeaderBg: '#0d3d2d',
            sectionHeaderText: '#d1fae5',
            btnPrimaryBg: 'linear-gradient(135deg, #059669, #047857)',
            btnPrimaryText: '#ecfdf5',
            btnPrimaryHover: 'linear-gradient(135deg, #10b981, #059669)',
            btnSecondaryBg: 'rgba(16,185,129,0.08)',
            btnSecondaryBorder: 'rgba(16,185,129,0.2)',
            btnSecondaryText: '#d1fae5',
            btnSecondaryHover: 'rgba(16,185,129,0.12)',
            btnDangerBg: 'linear-gradient(135deg, #dc2626, #b91c1c)',
            btnDangerHover: 'linear-gradient(135deg, #ef4444, #dc2626)',
            btnSuccessBg: 'linear-gradient(135deg, #10b981, #059669)',
            btnSuccessHover: 'linear-gradient(135deg, #6ee7b7, #34d399)',
            inputBg: 'rgba(16,185,129,0.06)',
            inputBorder: 'rgba(16,185,129,0.15)',
            inputText: '#d1fae5',
            inputPlaceholder: 'rgba(16,185,129,0.5)',
            inputFocus: 'rgba(16,185,129,0.3)',
            inputFocusGlow: 'rgba(16,185,129,0.1)',
            tabBg: 'rgba(16,185,129,0.06)',
            tabBorder: 'rgba(16,185,129,0.15)',
            tabText: '#d1fae5',
            tabActiveBg: 'rgba(16,185,129,0.12)',
            tabActiveBorder: '#10b981',
            tabHoverBg: 'rgba(16,185,129,0.1)',
            badgeBg: 'rgba(16,185,129,0.08)',
            badgeBorder: 'rgba(16,185,129,0.2)',
            badgeText: '#d1fae5',
            badgeSuccessBorder: '#10b981',
            badgeSuccessText: '#10b981',
            badgeWarnBorder: '#f59e0b',
            badgeWarnText: '#f59e0b',
            badgeInfoBorder: '#06b6d4',
            badgeInfoText: '#06b6d4',
            textPrimary: '#d1fae5',
            textSecondary: 'rgba(209,250,229,0.7)',
            textTertiary: 'rgba(209,250,229,0.5)',
            textMuted: 'rgba(209,250,229,0.55)',
            borderLight: 'rgba(16,185,129,0.08)',
            borderMedium: 'rgba(16,185,129,0.12)',
            borderDark: 'rgba(16,185,129,0.15)',
            statusSuccess: '#10b981',
            statusWarning: '#f59e0b',
            statusError: '#dc2626',
            statusInfo: '#06b6d4',
            
            // Accent Highlights
            accentPrimary: '#059669',
            accentHover: '#10b981',
            accentActive: '#047857',
            
            scrollbarTrack: 'rgba(16,185,129,0.03)',
            scrollbarThumb: 'linear-gradient(180deg, rgba(16,185,129,0.7), rgba(5,150,105,0.7))',
            scrollbarThumbHover: 'linear-gradient(180deg, rgba(52,211,153,0.9), rgba(16,185,129,0.9))',
            iconDashboard: '#5AA2FF',
            iconDispatch: '#00D4FF',
            iconCctv: '#5AA2FF',
            iconCitizens: '#B388FF',
            iconVehicles: '#FF7EB3',
            iconWarrant: '#FFC75F',
            iconCourt: '#FF9671',
            iconCriminalcode: '#F9F871',
            iconWeapons: '#FF6B6B',
            iconReports: '#77DD77',
            iconIncidents: '#00E5A3',
            iconFto: '#A0CED9',
            iconRoster: '#FFD166',
            iconSop: '#BBD0FF',
            iconOfficers: '#F4A261',
            
            // Profile Avatar & Dispatch
            profileAvatarGradient1: '#064e3b',
            profileAvatarGradient2: '#022c20',
            dispatchBadgeId: 'rgba(16, 185, 129, 0.6)',
            dispatchBadgePriority1: 'rgba(220, 38, 38, 0.9)',
            dispatchBadgePriority2: 'rgba(245, 158, 11, 0.9)',
            dispatchBadgePriority3: 'rgba(16, 185, 129, 0.8)',
            dispatchOverlayBg: 'linear-gradient(160deg, rgba(2, 44, 34, 0.84), rgba(4, 72, 56, 0.9))',
            dispatchOverlayBorder: 'rgba(16, 185, 129, 0.45)',
            dispatchOverlayShadow: '0 16px 38px rgba(1, 24, 20, 0.58)',
            dispatchOverlayHeaderBg: 'rgba(16, 185, 129, 0.2)',
            dispatchOverlayHeaderBorder: 'rgba(16, 185, 129, 0.34)',
            dispatchOverlayTitleText: 'rgba(167, 243, 208, 0.98)',
            dispatchOverlayMetaText: 'rgba(110, 231, 183, 0.9)',
            dispatchOverlayTypeText: 'rgba(236, 253, 245, 0.98)',
            dispatchOverlayLocationText: 'rgba(167, 243, 208, 0.95)',
            dispatchOverlayDescriptionText: 'rgba(220, 252, 231, 0.92)',
            dispatchOverlayFooterBorder: 'rgba(16,185,129,0.24)',
            dispatchOverlayButtonBg: 'rgba(16, 185, 129, 0.2)',
            dispatchOverlayButtonBorder: 'rgba(16, 185, 129, 0.45)',
            dispatchOverlayButtonText: 'rgba(209, 250, 229, 0.98)',
            dispatchOverlayButtonHoverBg: 'rgba(16, 185, 129, 0.34)',
            
            // Modal Gradients
            modalGradient1: 'rgba(5, 150, 105, 0.9)',
            modalGradient2: 'rgba(4, 120, 87, 0.9)',
            
            // Card Avatar Gradient
            cardAvatarGradient1: '#064e3b',
            cardAvatarGradient2: '#022c20',
            
            // Warrant Status Cleared
            warrantStatusClearedColor: '#10b981',
            warrantStatusClearedBorder: 'rgba(16, 185, 129, 0.5)',
            warrantStatusClearedBg: 'rgba(16, 185, 129, 0.15)',
            
            // Incident Details Button
            incidentDetailsButtonBg: 'linear-gradient(135deg, rgba(16, 185, 129, 0.3), rgba(16, 185, 129, 0.15))',
            incidentDetailsButtonBorder: 'rgba(16, 185, 129, 0.5)',
            incidentDetailsButtonColor: '#10b981',
            incidentDetailsButtonHoverBg: 'linear-gradient(135deg, rgba(16, 185, 129, 0.5), rgba(16, 185, 129, 0.3))',
            incidentDetailsButtonHoverBorder: 'rgba(16, 185, 129, 0.8)',
            incidentDetailsButtonHoverShadow: 'rgba(16, 185, 129, 0.2)',
            
            // Incident Editable Focus
            incidentEditableFocusBorder: 'rgba(16, 185, 129, 0.5)',
            incidentEditableFocusBox: 'rgba(16, 185, 129, 0.1)',
            
            // Callsign & Status Colors
            callsignColor: 'rgba(16, 185, 129, 0.85)',
            statusDropdownFocusBorder: 'rgba(16, 185, 129, 0.55)',
            statusDropdownFocusBg: 'rgba(16, 185, 129, 0.1)',
            updateBtnBg: 'rgba(16, 185, 129, 0.3)',
            updateBtnBorder: 'rgba(16, 185, 129, 0.5)',
            updateBtnHoverBg: 'rgba(16, 185, 129, 0.5)',
            updateBtnHoverBorder: 'rgba(16, 185, 129, 0.8)',
            
            // Chat Colors
            chatSelfAuthorColor: 'rgba(16, 185, 129, 0.7)',
            chatSelfBg: 'rgba(16, 185, 129, 0.2)',
            chatSelfBorder: 'rgba(16, 185, 129, 0.5)',
            chatInputFocusBorder: 'rgba(16, 185, 129, 0.55)',
            chatInputFocusBg: 'rgba(16, 185, 129, 0.1)',
            chatSendBtnBg: 'rgba(16, 185, 129, 0.3)',
            chatSendBtnBorder: 'rgba(16, 185, 129, 0.5)'
        },
        purple: {
            topbarBg: 'linear-gradient(90deg, #581c87 0%, #6b21a8 100%)',
            topbarText: '#f3e8ff',
            sidebarBg: 'linear-gradient(180deg, #3f0f5c 0%, #2d0a42 100%)',
            sidebarBorder: 'rgba(243,232,255,0.12)',
            sidebarItemBg: 'rgba(243,232,255,0.04)',
            sidebarItemText: '#f3e8ff',
            sidebarItemActive: '#d946ef',
            sidebarItemActiveBg: 'rgba(217,70,239,0.12)',
            sidebarItemActiveHover: '#f5b3ff',
            tabletFrameBg: 'linear-gradient(135deg, #3f0f5c 0%, #3f0f5c 100%)',
            tabletFrameBorder: 'rgba(217, 70, 239, 0.3)',
            tabletTitlebarBg: 'linear-gradient(180deg, rgba(168, 85, 247, 0.8) 0%, rgba(147, 51, 234, 0.8) 100%)',
            contentBg: 'transparent',
            panelBg: 'rgba(63, 15, 92, 0.78)',
            pageContentBg: 'linear-gradient(135deg, #3f0f5c 0%, #581c87 100%)',
            cardBg: 'rgba(63,15,92,0.9)',
            cardBorder: 'rgba(217,70,239,0.12)',
            cardText: '#f3e8ff',
            sectionHeaderBg: '#581c87',
            sectionHeaderText: '#f3e8ff',
            btnPrimaryBg: 'linear-gradient(135deg, #a855f7, #9333ea)',
            btnPrimaryText: '#faf5ff',
            btnPrimaryHover: 'linear-gradient(135deg, #d946ef, #c084fc)',
            btnSecondaryBg: 'rgba(217,70,239,0.08)',
            btnSecondaryBorder: 'rgba(217,70,239,0.2)',
            btnSecondaryText: '#f3e8ff',
            btnSecondaryHover: 'rgba(217,70,239,0.12)',
            btnDangerBg: 'linear-gradient(135deg, #dc2626, #b91c1c)',
            btnDangerHover: 'linear-gradient(135deg, #ef4444, #dc2626)',
            btnSuccessBg: 'linear-gradient(135deg, #7c3aed, #6d28d9)',
            btnSuccessHover: 'linear-gradient(135deg, #a855f7, #9333ea)',
            inputBg: 'rgba(217,70,239,0.06)',
            inputBorder: 'rgba(217,70,239,0.15)',
            inputText: '#f3e8ff',
            inputPlaceholder: 'rgba(217,70,239,0.5)',
            inputFocus: 'rgba(217,70,239,0.3)',
            inputFocusGlow: 'rgba(217,70,239,0.1)',
            tabBg: 'rgba(217,70,239,0.06)',
            tabBorder: 'rgba(217,70,239,0.15)',
            tabText: '#f3e8ff',
            tabActiveBg: 'rgba(217,70,239,0.12)',
            tabActiveBorder: '#d946ef',
            tabHoverBg: 'rgba(217,70,239,0.1)',
            badgeBg: 'rgba(217,70,239,0.08)',
            badgeBorder: 'rgba(217,70,239,0.2)',
            badgeText: '#f3e8ff',
            badgeSuccessBorder: '#a855f7',
            badgeSuccessText: '#a855f7',
            badgeWarnBorder: '#f59e0b',
            badgeWarnText: '#f59e0b',
            badgeInfoBorder: '#06b6d4',
            badgeInfoText: '#06b6d4',
            textPrimary: '#f3e8ff',
            textSecondary: 'rgba(243,232,255,0.7)',
            textTertiary: 'rgba(243,232,255,0.5)',
            textMuted: 'rgba(243,232,255,0.55)',
            borderLight: 'rgba(217,70,239,0.08)',
            borderMedium: 'rgba(217,70,239,0.12)',
            borderDark: 'rgba(217,70,239,0.15)',
            statusSuccess: '#a855f7',
            statusWarning: '#f59e0b',
            statusError: '#dc2626',
            statusInfo: '#06b6d4',
            
            // Accent Highlights
            accentPrimary: '#a855f7',
            accentHover: '#d946ef',
            accentActive: '#9333ea',
            
            scrollbarTrack: 'rgba(217,70,239,0.03)',
            scrollbarThumb: 'linear-gradient(180deg, rgba(217,70,239,0.7), rgba(168,85,247,0.7))',
            scrollbarThumbHover: 'linear-gradient(180deg, rgba(245,179,255,0.9), rgba(217,70,239,0.9))',
            iconDashboard: '#5AA2FF',
            iconDispatch: '#00D4FF',
            iconCctv: '#5AA2FF',
            iconCitizens: '#B388FF',
            iconVehicles: '#FF7EB3',
            iconWarrant: '#FFC75F',
            iconCourt: '#FF9671',
            iconCriminalcode: '#F9F871',
            iconWeapons: '#FF6B6B',
            iconReports: '#77DD77',
            iconIncidents: '#00E5A3',
            iconFto: '#A0CED9',
            iconRoster: '#FFD166',
            iconSop: '#BBD0FF',
            iconOfficers: '#F4A261',
            
            // Profile Avatar & Dispatch
            profileAvatarGradient1: '#3f0f5c',
            profileAvatarGradient2: '#2d0a42',
            dispatchBadgeId: 'rgba(168, 85, 247, 0.6)',
            dispatchBadgePriority1: 'rgba(244, 67, 54, 0.9)',
            dispatchBadgePriority2: 'rgba(255, 179, 71, 0.9)',
            dispatchBadgePriority3: 'rgba(168, 85, 247, 0.8)',
            dispatchOverlayBg: 'linear-gradient(160deg, rgba(45, 10, 66, 0.84), rgba(70, 18, 104, 0.9))',
            dispatchOverlayBorder: 'rgba(217, 70, 239, 0.42)',
            dispatchOverlayShadow: '0 16px 38px rgba(30, 8, 44, 0.58)',
            dispatchOverlayHeaderBg: 'rgba(168, 85, 247, 0.22)',
            dispatchOverlayHeaderBorder: 'rgba(217, 70, 239, 0.36)',
            dispatchOverlayTitleText: 'rgba(243, 232, 255, 0.98)',
            dispatchOverlayMetaText: 'rgba(221, 214, 254, 0.9)',
            dispatchOverlayTypeText: 'rgba(250, 245, 255, 0.98)',
            dispatchOverlayLocationText: 'rgba(233, 213, 255, 0.95)',
            dispatchOverlayDescriptionText: 'rgba(243, 232, 255, 0.92)',
            dispatchOverlayFooterBorder: 'rgba(217,70,239,0.24)',
            dispatchOverlayButtonBg: 'rgba(168, 85, 247, 0.2)',
            dispatchOverlayButtonBorder: 'rgba(217, 70, 239, 0.45)',
            dispatchOverlayButtonText: 'rgba(243, 232, 255, 0.98)',
            dispatchOverlayButtonHoverBg: 'rgba(168, 85, 247, 0.34)',
            
            // Modal Gradients
            modalGradient1: 'rgba(126, 34, 206, 0.85)',
            modalGradient2: 'rgba(88, 28, 135, 0.85)',
            
            // Card Avatar Gradient
            cardAvatarGradient1: '#3f0f5c',
            cardAvatarGradient2: '#2d0a42',
            
            // Warrant Status Cleared
            warrantStatusClearedColor: '#a78bfa',
            warrantStatusClearedBorder: 'rgba(168, 85, 247, 0.5)',
            warrantStatusClearedBg: 'rgba(168, 85, 247, 0.15)',
            
            // Incident Details Button
            incidentDetailsButtonBg: 'linear-gradient(135deg, rgba(168, 85, 247, 0.3), rgba(168, 85, 247, 0.15))',
            incidentDetailsButtonBorder: 'rgba(168, 85, 247, 0.5)',
            incidentDetailsButtonColor: '#a78bfa',
            incidentDetailsButtonHoverBg: 'linear-gradient(135deg, rgba(168, 85, 247, 0.5), rgba(168, 85, 247, 0.3))',
            incidentDetailsButtonHoverBorder: 'rgba(168, 85, 247, 0.8)',
            incidentDetailsButtonHoverShadow: 'rgba(168, 85, 247, 0.2)',
            
            // Incident Editable Focus
            incidentEditableFocusBorder: 'rgba(168, 85, 247, 0.5)',
            incidentEditableFocusBox: 'rgba(168, 85, 247, 0.1)',
            
            // Callsign & Status Colors
            callsignColor: 'rgba(168, 85, 247, 0.85)',
            statusDropdownFocusBorder: 'rgba(168, 85, 247, 0.55)',
            statusDropdownFocusBg: 'rgba(168, 85, 247, 0.1)',
            updateBtnBg: 'rgba(168, 85, 247, 0.3)',
            updateBtnBorder: 'rgba(168, 85, 247, 0.5)',
            updateBtnHoverBg: 'rgba(168, 85, 247, 0.5)',
            updateBtnHoverBorder: 'rgba(168, 85, 247, 0.8)',
            
            // Chat Colors
            chatSelfAuthorColor: 'rgba(168, 85, 247, 0.7)',
            chatSelfBg: 'rgba(168, 85, 247, 0.2)',
            chatSelfBorder: 'rgba(168, 85, 247, 0.5)',
            chatInputFocusBorder: 'rgba(168, 85, 247, 0.55)',
            chatInputFocusBg: 'rgba(168, 85, 247, 0.1)',
            chatSendBtnBg: 'rgba(168, 85, 247, 0.3)',
            chatSendBtnBorder: 'rgba(168, 85, 247, 0.5)'
        },
        orange: {
            topbarBg: 'linear-gradient(90deg, #7c2d12 0%, #9a3412 100%)',
            topbarText: '#fed7aa',
            sidebarBg: 'linear-gradient(180deg, #5a2e0c 0%, #3e1f08 100%)',
            sidebarBorder: 'rgba(254,215,170,0.12)',
            sidebarItemBg: 'rgba(254,215,170,0.04)',
            sidebarItemText: '#fed7aa',
            sidebarItemActive: '#f97316',
            sidebarItemActiveBg: 'rgba(249,115,22,0.12)',
            sidebarItemActiveHover: '#fbbf24',
            tabletFrameBg: 'linear-gradient(135deg, #5a2e0c 0%, #5a2e0c 100%)',
            tabletFrameBorder: 'rgba(249, 115, 22, 0.3)',
            tabletTitlebarBg: 'linear-gradient(180deg, rgba(234, 88, 12, 0.8) 0%, rgba(194, 65, 12, 0.8) 100%)',
            contentBg: 'transparent',
            panelBg: 'rgba(90, 46, 12, 0.78)',
            pageContentBg: 'linear-gradient(135deg, #5a2e0c 0%, #7c2d12 100%)',
            cardBg: 'rgba(90,46,12,0.9)',
            cardBorder: 'rgba(249,115,22,0.12)',
            cardText: '#fed7aa',
            sectionHeaderBg: '#7c2d12',
            sectionHeaderText: '#fed7aa',
            btnPrimaryBg: 'linear-gradient(135deg, #ea580c, #dc2626)',
            btnPrimaryText: '#fef3c7',
            btnPrimaryHover: 'linear-gradient(135deg, #f97316, #ea580c)',
            btnSecondaryBg: 'rgba(249,115,22,0.08)',
            btnSecondaryBorder: 'rgba(249,115,22,0.2)',
            btnSecondaryText: '#fed7aa',
            btnSecondaryHover: 'rgba(249,115,22,0.12)',
            btnDangerBg: 'linear-gradient(135deg, #b91c1c, #7f1d1d)',
            btnDangerHover: 'linear-gradient(135deg, #dc2626, #b91c1c)',
            btnSuccessBg: 'linear-gradient(135deg, #f97316, #ea580c)',
            btnSuccessHover: 'linear-gradient(135deg, #fb923c, #f97316)',
            inputBg: 'rgba(249,115,22,0.06)',
            inputBorder: 'rgba(249,115,22,0.15)',
            inputText: '#fed7aa',
            inputPlaceholder: 'rgba(249,115,22,0.5)',
            inputFocus: 'rgba(249,115,22,0.3)',
            inputFocusGlow: 'rgba(249,115,22,0.1)',
            tabBg: 'rgba(249,115,22,0.06)',
            tabBorder: 'rgba(249,115,22,0.15)',
            tabText: '#fed7aa',
            tabActiveBg: 'rgba(249,115,22,0.12)',
            tabActiveBorder: '#f97316',
            tabHoverBg: 'rgba(249,115,22,0.1)',
            badgeBg: 'rgba(249,115,22,0.08)',
            badgeBorder: 'rgba(249,115,22,0.2)',
            badgeText: '#fed7aa',
            badgeSuccessBorder: '#f97316',
            badgeSuccessText: '#f97316',
            badgeWarnBorder: '#fbbf24',
            badgeWarnText: '#fbbf24',
            badgeInfoBorder: '#06b6d4',
            badgeInfoText: '#06b6d4',
            textPrimary: '#fed7aa',
            textSecondary: 'rgba(254,215,170,0.7)',
            textTertiary: 'rgba(254,215,170,0.5)',
            textMuted: 'rgba(254,215,170,0.55)',
            borderLight: 'rgba(249,115,22,0.08)',
            borderMedium: 'rgba(249,115,22,0.12)',
            borderDark: 'rgba(249,115,22,0.15)',
            statusSuccess: '#f97316',
            statusWarning: '#fbbf24',
            statusError: '#dc2626',
            statusInfo: '#06b6d4',
            
            // Accent Highlights
            accentPrimary: '#ea580c',
            accentHover: '#f97316',
            accentActive: '#dc2626',
            
            scrollbarTrack: 'rgba(249,115,22,0.03)',
            scrollbarThumb: 'linear-gradient(180deg, rgba(249,115,22,0.7), rgba(202,51,15,0.7))',
            scrollbarThumbHover: 'linear-gradient(180deg, rgba(251,191,36,0.9), rgba(249,115,22,0.9))',
            iconDashboard: '#5AA2FF',
            iconDispatch: '#00D4FF',
            iconCctv: '#5AA2FF',
            iconCitizens: '#B388FF',
            iconVehicles: '#FF7EB3',
            iconWarrant: '#FFC75F',
            iconCourt: '#FF9671',
            iconCriminalcode: '#F9F871',
            iconWeapons: '#FF6B6B',
            iconReports: '#77DD77',
            iconIncidents: '#00E5A3',
            iconFto: '#A0CED9',
            iconRoster: '#FFD166',
            iconSop: '#BBD0FF',
            iconOfficers: '#F4A261',
            
            // Profile Avatar & Dispatch
            profileAvatarGradient1: '#7c2d12',
            profileAvatarGradient2: '#431407',
            dispatchBadgeId: 'rgba(249, 115, 22, 0.6)',
            dispatchBadgePriority1: 'rgba(220, 38, 38, 0.9)',
            dispatchBadgePriority2: 'rgba(249, 115, 22, 0.9)',
            dispatchBadgePriority3: 'rgba(100, 116, 139, 0.8)',
            dispatchOverlayBg: 'linear-gradient(160deg, rgba(62, 31, 8, 0.85), rgba(90, 46, 12, 0.92))',
            dispatchOverlayBorder: 'rgba(249, 115, 22, 0.44)',
            dispatchOverlayShadow: '0 16px 38px rgba(40, 20, 6, 0.6)',
            dispatchOverlayHeaderBg: 'rgba(249, 115, 22, 0.22)',
            dispatchOverlayHeaderBorder: 'rgba(249, 115, 22, 0.36)',
            dispatchOverlayTitleText: 'rgba(255, 237, 213, 0.98)',
            dispatchOverlayMetaText: 'rgba(254, 215, 170, 0.9)',
            dispatchOverlayTypeText: 'rgba(255, 247, 237, 0.98)',
            dispatchOverlayLocationText: 'rgba(253, 230, 138, 0.95)',
            dispatchOverlayDescriptionText: 'rgba(255, 237, 213, 0.92)',
            dispatchOverlayFooterBorder: 'rgba(249,115,22,0.24)',
            dispatchOverlayButtonBg: 'rgba(249, 115, 22, 0.2)',
            dispatchOverlayButtonBorder: 'rgba(249, 115, 22, 0.45)',
            dispatchOverlayButtonText: 'rgba(255, 237, 213, 0.98)',
            dispatchOverlayButtonHoverBg: 'rgba(249, 115, 22, 0.34)',
            
            // Modal Gradients
            modalGradient1: 'rgba(194, 65, 12, 0.9)',
            modalGradient2: 'rgba(154, 52, 18, 0.9)',
            
            // Card Avatar Gradient
            cardAvatarGradient1: '#7c2d12',
            cardAvatarGradient2: '#431407',
            
            // Warrant Status Cleared
            warrantStatusClearedColor: '#f97316',
            warrantStatusClearedBorder: 'rgba(249, 115, 22, 0.5)',
            warrantStatusClearedBg: 'rgba(249, 115, 22, 0.15)',
            
            // Incident Details Button
            incidentDetailsButtonBg: 'linear-gradient(135deg, rgba(249, 115, 22, 0.3), rgba(249, 115, 22, 0.15))',
            incidentDetailsButtonBorder: 'rgba(249, 115, 22, 0.5)',
            incidentDetailsButtonColor: '#f97316',
            incidentDetailsButtonHoverBg: 'linear-gradient(135deg, rgba(249, 115, 22, 0.5), rgba(249, 115, 22, 0.3))',
            incidentDetailsButtonHoverBorder: 'rgba(249, 115, 22, 0.8)',
            incidentDetailsButtonHoverShadow: 'rgba(249, 115, 22, 0.2)',
            
            // Incident Editable Focus
            incidentEditableFocusBorder: 'rgba(249, 115, 22, 0.5)',
            incidentEditableFocusBox: 'rgba(249, 115, 22, 0.1)',
            
            // Callsign & Status Colors
            callsignColor: 'rgba(249, 115, 22, 0.85)',
            statusDropdownFocusBorder: 'rgba(249, 115, 22, 0.55)',
            statusDropdownFocusBg: 'rgba(249, 115, 22, 0.1)',
            updateBtnBg: 'rgba(249, 115, 22, 0.3)',
            updateBtnBorder: 'rgba(249, 115, 22, 0.5)',
            updateBtnHoverBg: 'rgba(249, 115, 22, 0.5)',
            updateBtnHoverBorder: 'rgba(249, 115, 22, 0.8)',
            
            // Chat Colors
            chatSelfAuthorColor: 'rgba(249, 115, 22, 0.7)',
            chatSelfBg: 'rgba(249, 115, 22, 0.2)',
            chatSelfBorder: 'rgba(249, 115, 22, 0.5)',
            chatInputFocusBorder: 'rgba(249, 115, 22, 0.55)',
            chatInputFocusBg: 'rgba(249, 115, 22, 0.1)',
            chatSendBtnBg: 'rgba(249, 115, 22, 0.3)',
            chatSendBtnBorder: 'rgba(249, 115, 22, 0.5)'
        }
    };

    let pendingTheme = { ...COLOR_PRESETS.default };
    let mdtTheme = loadThemeFromStorage() || { ...COLOR_PRESETS.default };

    function loadThemeFromStorage() {
        try {
            const stored = localStorage.getItem('mdt_theme');
            return stored ? JSON.parse(stored) : null;
        } catch (_) { return null; }
    }

    function saveThemeToStorage(theme) {
        try {
            localStorage.setItem('mdt_theme', JSON.stringify(theme));
        } catch (_) {}
    }

    function applyThemeToDOM(theme) {
        theme = { ...COLOR_PRESETS.default, ...(theme || {}) };
        // Helper function to convert hex to rgba
        const hexToRgba = (hex, alpha = 1) => {
            const r = parseInt(hex.slice(1, 3), 16);
            const g = parseInt(hex.slice(3, 5), 16);
            const b = parseInt(hex.slice(5, 7), 16);
            return `rgba(${r}, ${g}, ${b}, ${alpha})`;
        };

        // Remove old dynamic theme style if it exists
        const oldStyle = document.getElementById('dynamic-theme-style');
        if (oldStyle) oldStyle.remove();
        
        // Create dynamic CSS stylesheet for theme
        const styleSheet = document.createElement('style');
        styleSheet.id = 'dynamic-theme-style';
        styleSheet.textContent = `
            body, * { 
                --mdt-primary: ${theme.textPrimary} !important;
                --mdt-background: ${theme.cardBg} !important;
                --mdt-text: ${theme.textPrimary} !important;
            }
            
            body { 
                color: ${theme.textPrimary} !important;
                background: transparent !important;
            }
            
            .topbar {
                background: ${theme.topbarBg} !important;
                color: ${theme.topbarText} !important;
            }
            
            .sidebar {
                background: ${theme.sidebarBg} !important;
                border-color: ${theme.sidebarBorder} !important;
            }
            
            .nav-item {
                color: ${theme.sidebarItemText} !important;
                background: ${theme.sidebarItemBg} !important;
                border-color: ${theme.borderMedium} !important;
            }
            
            .nav-item.active {
                background: ${theme.sidebarItemActiveBg} !important;
                color: ${theme.sidebarItemActive} !important;
                border-left-color: ${theme.sidebarItemActive} !important;
            }
            
            .nav-section-title {
                color: ${theme.sidebarItemText} !important;
            }

            .dispatch-overlay {
                background: ${theme.dispatchOverlayBg} !important;
                border-color: ${theme.dispatchOverlayBorder} !important;
                box-shadow: ${theme.dispatchOverlayShadow} !important;
            }

            .dispatch-overlay-header {
                background: ${theme.dispatchOverlayHeaderBg} !important;
                border-bottom-color: ${theme.dispatchOverlayHeaderBorder} !important;
            }

            .dispatch-overlay-title {
                color: ${theme.dispatchOverlayTitleText} !important;
            }

            .dispatch-overlay-count,
            .dispatch-overlay-time,
            .dispatch-overlay-hint {
                color: ${theme.dispatchOverlayMetaText} !important;
            }

            .dispatch-overlay-type {
                color: ${theme.dispatchOverlayTypeText} !important;
            }

            .dispatch-overlay-location {
                color: ${theme.dispatchOverlayLocationText} !important;
            }

            .dispatch-overlay-desc {
                color: ${theme.dispatchOverlayDescriptionText} !important;
            }

            .dispatch-overlay-footer {
                border-top-color: ${theme.dispatchOverlayFooterBorder} !important;
            }

            .dispatch-overlay-nav-btn {
                background: ${theme.dispatchOverlayButtonBg} !important;
                border-color: ${theme.dispatchOverlayButtonBorder} !important;
                color: ${theme.dispatchOverlayButtonText} !important;
            }

            .dispatch-overlay-nav-btn:hover {
                background: ${theme.dispatchOverlayButtonHoverBg} !important;
            }
            
            .modal-card, .card, .modal-body, .modal-header, .modal-footer,
            .vehicle-detail-card, .vehBody {
                background: ${theme.cardBg} !important;
                border-color: ${theme.cardBorder} !important;
                color: ${theme.cardText} !important;
            }

            .vehHeader {
                background: ${theme.sectionHeaderBg} !important;
                border-bottom-color: ${theme.cardBorder} !important;
                color: ${theme.sectionHeaderText} !important;
            }

            .incident-details-modal {
                background: ${theme.cardBg} !important;
                border-color: ${theme.cardBorder} !important;
                color: ${theme.cardText} !important;
            }

            .incident-modal-header {
                background: ${theme.sectionHeaderBg} !important;
                border-bottom-color: ${theme.cardBorder} !important;
            }

            .incident-modal-body {
                background: ${theme.cardBg} !important;
            }

            .fto-panel {
                background: ${theme.panelBg} !important;
                border-color: ${theme.cardBorder} !important;
            }
            
            .modal-section-title, .section-title, .section-header {
                color: ${theme.sectionHeaderText} !important;
            }
            
            button:not(.color-preset):not(.nav-item) {
                background: ${theme.btnSecondaryBg} !important;
                border-color: ${theme.btnSecondaryBorder} !important;
                color: ${theme.btnSecondaryText} !important;
            }
            
            button.btn-primary, button.primary {
                background: ${theme.btnPrimaryBg} !important;
                color: ${theme.btnPrimaryText} !important;
                border-color: transparent !important;
            }
            
            button.btn-danger, button.danger {
                background: ${theme.btnDangerBg} !important;
                color: #fff !important;
                border-color: transparent !important;
            }
            
            button.btn-success, button.success {
                background: ${theme.btnSuccessBg} !important;
                color: #fff !important;
                border-color: transparent !important;
            }
            
            input:not([type="color"]):not([type="radio"]):not([type="checkbox"]):not([type="hidden"]),
            select, textarea {
                background: ${theme.inputBg} !important;
                border-color: ${theme.inputBorder} !important;
                color: ${theme.inputText} !important;
            }
            
            input::placeholder, textarea::placeholder {
                color: ${theme.inputPlaceholder} !important;
            }
            
            label, .label {
                color: ${theme.textPrimary} !important;
            }
            
            .tab {
                background: ${theme.tabBg} !important;
                border-color: ${theme.tabBorder} !important;
                color: ${theme.tabText} !important;
            }
            
            .tab.active {
                background: ${theme.tabActiveBg} !important;
                border-color: ${theme.tabActiveBorder} !important;
                color: ${theme.textPrimary} !important;
            }
            
            .chip, .badge, .status, .tag {
                background: ${theme.badgeBg} !important;
                border-color: ${theme.badgeBorder} !important;
                color: ${theme.badgeText} !important;
            }
            
            .chip.success, .badge.success, .status.success {
                border-color: ${theme.badgeSuccessBorder} !important;
                color: ${theme.badgeSuccessText} !important;
                background: transparent !important;
            }
            
            .chip.warn, .badge.warn, .chip.warning, .badge.warning {
                border-color: ${theme.badgeWarnBorder} !important;
                color: ${theme.badgeWarnText} !important;
                background: transparent !important;
            }
            
            .chip.info, .badge.info {
                border-color: ${theme.badgeInfoBorder} !important;
                color: ${theme.badgeInfoText} !important;
                background: transparent !important;
            }
            
            .text-secondary { color: ${theme.textSecondary} !important; }
            .text-muted { color: ${theme.textMuted} !important; }
            
            tr, td, th, tbody, thead, table {
                border-color: ${theme.borderMedium} !important;
                color: ${theme.textPrimary} !important;
            }
            
            [class*="border"], [class*="divider"], hr {
                border-color: ${theme.borderMedium} !important;
                color: ${theme.borderMedium} !important;
            }
            
            li, a { color: ${theme.textPrimary} !important; }
            
            h1, h2, h3, h4, h5, h6 { color: ${theme.sectionHeaderText} !important; }
            
            .page-content {
                background: ${theme.pageContentBg} !important;
            }
            
            .dashboard-panel {
                background: ${theme.panelBg} !important;
            }
            
            .tablet-frame {
                border-color: ${theme.tabletFrameBorder} !important;
                background: ${theme.tabletFrameBg} !important;
            }
            
            .tablet-titlebar {
                background: ${theme.tabletTitlebarBg} !important;
            }
            
            :root {
                --scrollbar-track: ${theme.scrollbarTrack};
                --scrollbar-thumb: ${theme.scrollbarThumb};
                --scrollbar-thumb-hover: ${theme.scrollbarThumbHover};
                --accent-primary: ${theme.accentPrimary};
                --accent-hover: ${theme.accentHover};
                --accent-active: ${theme.accentActive};
                --accent-light: ${hexToRgba(theme.accentPrimary, 0.1)};
                --accent-medium: ${hexToRgba(theme.accentPrimary, 0.3)};
                --profile-avatar-gradient-1: ${theme.profileAvatarGradient1};
                --profile-avatar-gradient-2: ${theme.profileAvatarGradient2};
                --card-avatar-gradient-1: ${theme.cardAvatarGradient1};
                --card-avatar-gradient-2: ${theme.cardAvatarGradient2};
                --dispatch-badge-id: ${theme.dispatchBadgeId};
                --dispatch-badge-priority-1: ${theme.dispatchBadgePriority1};
                --dispatch-badge-priority-2: ${theme.dispatchBadgePriority2};
                --dispatch-badge-priority-3: ${theme.dispatchBadgePriority3};
                --modal-gradient-1: ${theme.modalGradient1};
                --modal-gradient-2: ${theme.modalGradient2};
                --page-content-bg: ${theme.pageContentBg};
                --warrant-status-cleared-color: ${theme.warrantStatusClearedColor};
                --warrant-status-cleared-border: ${theme.warrantStatusClearedBorder};
                --warrant-status-cleared-bg: ${theme.warrantStatusClearedBg};
                --incident-details-btn-bg: ${theme.incidentDetailsButtonBg};
                --incident-details-btn-border: ${theme.incidentDetailsButtonBorder};
                --incident-details-btn-color: ${theme.incidentDetailsButtonColor};
                --incident-details-btn-hover-bg: ${theme.incidentDetailsButtonHoverBg};
                --incident-details-btn-hover-border: ${theme.incidentDetailsButtonHoverBorder};
                --incident-details-btn-hover-shadow: ${theme.incidentDetailsButtonHoverShadow};
                --incident-editable-focus-border: ${theme.incidentEditableFocusBorder};
                --incident-editable-focus-box: ${theme.incidentEditableFocusBox};
                --callsign-color: ${theme.callsignColor};
                --status-dropdown-focus-border: ${theme.statusDropdownFocusBorder};
                --status-dropdown-focus-bg: ${theme.statusDropdownFocusBg};
                --update-btn-bg: ${theme.updateBtnBg};
                --update-btn-border: ${theme.updateBtnBorder};
                --update-btn-hover-bg: ${theme.updateBtnHoverBg};
                --update-btn-hover-border: ${theme.updateBtnHoverBorder};
                --chat-self-author-color: ${theme.chatSelfAuthorColor};
                --chat-self-bg: ${theme.chatSelfBg};
                --chat-self-border: ${theme.chatSelfBorder};
                --chat-input-focus-border: ${theme.chatInputFocusBorder};
                --chat-input-focus-bg: ${theme.chatInputFocusBg};
                --chat-send-btn-bg: ${theme.chatSendBtnBg};
                --chat-send-btn-border: ${theme.chatSendBtnBorder};
            }
        `;
        document.head.appendChild(styleSheet);
        
        // Topbar & Tablet Frame
        const topbar = document.querySelector('.topbar');
        if (topbar) {
            topbar.style.background = theme.topbarBg;
            topbar.style.color = theme.topbarText;
        }
        
        const tabletFrame = document.querySelector('.tablet-frame');
        if (tabletFrame) {
            tabletFrame.style.borderColor = theme.tabletFrameBorder;
            tabletFrame.style.background = theme.tabletFrameBg;
        }
        
        const tabletTitlebar = document.querySelector('.tablet-titlebar');
        if (tabletTitlebar) {
            tabletTitlebar.style.background = theme.tabletTitlebarBg;
        }
        
        // Sidebar & Navigation
        const sidebar = document.querySelector('.sidebar');
        if (sidebar) {
            sidebar.style.background = theme.sidebarBg;
            sidebar.style.borderColor = theme.sidebarBorder;
        }
        
        document.querySelectorAll('.nav-item').forEach(item => {
            item.style.color = theme.sidebarItemText;
            item.style.background = theme.sidebarItemBg;
            item.style.borderColor = theme.borderMedium;
            if (item.classList.contains('active')) {
                item.style.background = theme.sidebarItemActiveBg;
                item.style.color = theme.sidebarItemActive;
                item.style.borderLeftColor = theme.sidebarItemActive;
            }
        });
        
        document.querySelectorAll('.nav-section-title').forEach(el => {
            el.style.color = theme.sidebarItemText;
        });
        
        // Page Content & Panels
        const pageContent = document.querySelector('.page-content');
        if (pageContent) {
            pageContent.style.background = theme.pageContentBg;
        }
        
        document.querySelectorAll('.dashboard-panel').forEach(panel => {
            panel.style.background = theme.panelBg;
        });
        
        // Content area
        document.body.style.color = theme.textPrimary;
        document.body.style.background = 'transparent';
        
        // Cards & Modals
        document.querySelectorAll('.modal-card, .card, .modal-body, .modal-header, .modal-footer, .vehicle-detail-card, .vehBody').forEach(card => {
            card.style.background = theme.cardBg;
            card.style.borderColor = theme.cardBorder;
            card.style.color = theme.cardText;
        });

        document.querySelectorAll('.vehHeader').forEach(header => {
            header.style.background = theme.sectionHeaderBg;
            header.style.borderBottomColor = theme.cardBorder;
            header.style.color = theme.sectionHeaderText;
        });
        
        // Section headers
        document.querySelectorAll('.modal-section-title, .section-title, .section-header').forEach(el => {
            el.style.color = theme.sectionHeaderText;
        });
        
        // Navigation icons
        const iconColorMap = {
            dashboard: theme.iconDashboard,
            dispatch: theme.iconDispatch,
            cctv: theme.iconCctv,
            citizens: theme.iconCitizens,
            vehicles: theme.iconVehicles,
            warrant: theme.iconWarrant,
            court: theme.iconCourt,
            criminalcode: theme.iconCriminalcode,
            weapons: theme.iconWeapons,
            reports: theme.iconReports,
            incidents: theme.iconIncidents,
            fto: theme.iconFto,
            roster: theme.iconRoster,
            sop: theme.iconSop,
            officers: theme.iconOfficers
        };
        
        document.querySelectorAll('.nav-item svg').forEach(svg => {
            const navItem = svg.closest('.nav-item');
            if (navItem) {
                const page = navItem.getAttribute('data-page');
                if (page && iconColorMap[page]) {
                    svg.style.color = iconColorMap[page];
                }
            }
        });
        
        // Apply to root for CSS variable fallback
        const doc = document.documentElement;
        doc.style.setProperty('--mdt-primary', theme.textPrimary);
        doc.style.setProperty('--mdt-background', theme.cardBg);
        doc.style.setProperty('--mdt-text', theme.textPrimary);
        doc.style.setProperty('--mdt-icon', theme.iconDashboard);
    }

    function buildColorGroupUI(container) {
        if (!container) return;
        container.innerHTML = '';
        
        const colorGroups = [
            { 
                title: '📱 Frame & Borders', 
                description: 'The outer frame of the MDT window',
                colors: ['tabletFrameBg', 'tabletFrameBorder', 'tabletTitlebarBg'] 
            },
            { 
                title: '🎨 Top Bar', 
                description: 'The top section with buttons and title',
                colors: ['topbarBg', 'topbarText'] 
            },
            { 
                title: '📋 Left Sidebar', 
                description: 'Menu navigation on the left side',
                colors: ['sidebarBg', 'sidebarBorder', 'sidebarItemBg', 'sidebarItemText', 'sidebarItemActive', 'sidebarItemActiveBg'] 
            },
            { 
                title: '📄 Main Content Area', 
                description: 'Background and panels of the main page',
                colors: ['pageContentBg', 'panelBg'] 
            },
            { 
                title: '📦 Cards & Pop-ups', 
                description: 'Information boxes and modal windows',
                colors: ['cardBg', 'cardBorder', 'cardText', 'sectionHeaderBg', 'sectionHeaderText'] 
            },
            { 
                title: '🔘 Buttons', 
                description: 'All clickable buttons throughout the MDT',
                colors: ['btnPrimaryBg', 'btnPrimaryText', 'btnSecondaryBg', 'btnSecondaryBorder', 'btnSecondaryText', 'btnDangerBg'] 
            },
            { 
                title: '⌨️ Input Fields & Forms', 
                description: 'Text input boxes and form elements',
                colors: ['inputBg', 'inputBorder', 'inputText', 'inputPlaceholder', 'inputFocus'] 
            },
            { 
                title: '🏷️ Tags & Status Indicators', 
                description: 'Badges, tags, and status displays',
                colors: ['tabBg', 'tabBorder', 'tabActiveBg', 'tabActiveBorder', 'badgeBg', 'badgeBorder', 'statusSuccess', 'statusWarning', 'statusError', 'statusInfo'] 
            },
            { 
                title: '✏️ Text & Dividers', 
                description: 'Text colors and border lines',
                colors: ['textPrimary', 'textSecondary', 'textTertiary', 'textMuted', 'borderLight', 'borderMedium'] 
            },
            { 
                title: '💫 Highlights & Effects', 
                description: 'Active states, highlights, and accent colors',
                colors: ['accentPrimary', 'accentHover', 'accentActive', 'scrollbarThumb', 'scrollbarThumbHover'] 
            },
            { 
                title: '🎯 Menu Icons', 
                description: 'Color of each navigation icon',
                colors: ['iconDashboard', 'iconDispatch', 'iconCctv', 'iconCitizens', 'iconVehicles', 'iconWarrant', 'iconCourt', 'iconCriminalcode', 'iconWeapons', 'iconReports', 'iconIncidents', 'iconFto', 'iconRoster', 'iconSop', 'iconOfficers'] 
            },
            {
                title: '🚨 Dispatch Overlay HUD',
                description: 'Dispatch popout: background, header, text, footer, and nav buttons',
                colors: ['dispatchOverlayBg', 'dispatchOverlayBorder', 'dispatchOverlayShadow', 'dispatchOverlayHeaderBg', 'dispatchOverlayHeaderBorder', 'dispatchOverlayTitleText', 'dispatchOverlayMetaText', 'dispatchOverlayTypeText', 'dispatchOverlayLocationText', 'dispatchOverlayDescriptionText', 'dispatchOverlayFooterBorder', 'dispatchOverlayButtonBg', 'dispatchOverlayButtonBorder', 'dispatchOverlayButtonText', 'dispatchOverlayButtonHoverBg']
            }
        ];

        const cssPropertyGroups = [
            {
                title: 'Font Sizes',
                properties: ['fontSizeXs', 'fontSizeSm', 'fontSizeBase', 'fontSizeLg', 'fontSizeXl', 'fontSize2xl', 'fontSize3xl', 'fontSize4xl']
            },
            {
                title: 'Font Weights',
                properties: ['fontWeightLight', 'fontWeightNormal', 'fontWeightMedium', 'fontWeightSemibold', 'fontWeightBold']
            },
            {
                title: 'Spacing',
                properties: ['spacingXs', 'spacingSm', 'spacingBase', 'spacingMd', 'spacingLg', 'spacingXl', 'spacing2xl']
            },
            {
                title: 'Border Radius',
                properties: ['radiusXs', 'radiusSm', 'radiusBase', 'radiusMd', 'radiusLg', 'radiusXl', 'radius2xl', 'radiusFull']
            },
            {
                title: 'Line Height',
                properties: ['lineHeightTight', 'lineHeightSnug', 'lineHeightNormal', 'lineHeightRelaxed', 'lineHeightLoose']
            },
            {
                title: 'Letter Spacing',
                properties: ['letterSpacingTight', 'letterSpacingNormal', 'letterSpacingWide', 'letterSpacingWider']
            },
            {
                title: 'Transitions',
                properties: ['transitionFast', 'transitionBase', 'transitionSlow', 'transitionSlower']
            },
            {
                title: 'Shadows',
                properties: ['shadowSm', 'shadowBase', 'shadowMd', 'shadowLg', 'shadowXl', 'shadowInner']
            },
            {
                title: 'Opacity',
                properties: ['opacityDisabled', 'opacityHover', 'opacityActive']
            }
        ];
        
        const labelMap = {
            topbarBg: 'Topbar Background',
            topbarText: 'Topbar Text',
            sidebarBg: 'Sidebar Background',
            sidebarBorder: 'Sidebar Border',
            sidebarItemBg: 'Sidebar Item Background',
            sidebarItemText: 'Sidebar Item Text',
            sidebarItemActive: 'Sidebar Active Item',
            sidebarItemActiveBg: 'Sidebar Active Background',
            pageContentBg: 'Page Content Background',
            panelBg: 'Panel Background (Personal Info, Chat, etc)',
            cardBg: 'Card Background',
            cardBorder: 'Card Border',
            cardText: 'Card Text',
            sectionHeaderBg: 'Section Header Background',
            sectionHeaderText: 'Section Header Text',
            btnPrimaryBg: 'Primary Button Background',
            btnPrimaryText: 'Primary Button Text',
            btnSecondaryBg: 'Secondary Button Background',
            btnSecondaryBorder: 'Secondary Button Border',
            btnSecondaryText: 'Secondary Button Text',
            btnDangerBg: 'Danger Button Background',
            inputBg: 'Input Background',
            inputBorder: 'Input Border',
            inputText: 'Input Text',
            inputPlaceholder: 'Input Placeholder',
            inputFocus: 'Input Focus',
            tabBg: 'Tab Background',
            tabBorder: 'Tab Border',
            tabActiveBg: 'Tab Active Background',
            tabActiveBorder: 'Tab Active Border',
            badgeBg: 'Badge Background',
            badgeBorder: 'Badge Border',
            textPrimary: 'Primary Text',
            textSecondary: 'Secondary Text',
            textTertiary: 'Tertiary Text',
            textMuted: 'Muted Text',
            borderLight: 'Light Border',
            borderMedium: 'Medium Border',
            statusSuccess: 'Success Status',
            statusWarning: 'Warning Status',
            statusError: 'Error Status',
            statusInfo: 'Info Status',
            accentPrimary: 'Accent Highlight',
            accentHover: 'Accent Hover',
            accentActive: 'Accent Active',
            scrollbarTrack: 'Scrollbar Track',
            scrollbarThumb: 'Scrollbar Thumb',
            scrollbarThumbHover: 'Scrollbar Hover',
            iconDashboard: 'Dashboard Icon',
            iconDispatch: 'Dispatch Icon',
            iconCctv: 'CCTV Icon',
            iconCitizens: 'Citizens Icon',
            iconVehicles: 'Vehicles Icon',
            iconWarrant: 'Warrant Icon',
            iconCourt: 'Court Icon',
            iconCriminalcode: 'Criminal Code Icon',
            iconWeapons: 'Weapons Icon',
            iconReports: 'Reports Icon',
            iconIncidents: 'Incidents Icon',
            iconFto: 'FTO Icon',
            iconRoster: 'Roster Icon',
            iconSop: 'SOP Icon',
            iconOfficers: 'Officers Icon',
            dispatchOverlayBg: 'Dispatch Background',
            dispatchOverlayBorder: 'Dispatch Border',
            dispatchOverlayShadow: 'Dispatch Shadow',
            dispatchOverlayHeaderBg: 'Dispatch Header Background',
            dispatchOverlayHeaderBorder: 'Dispatch Header Border',
            dispatchOverlayTitleText: 'Dispatch Header Title',
            dispatchOverlayMetaText: 'Dispatch Meta Text',
            dispatchOverlayTypeText: 'Dispatch Call Title',
            dispatchOverlayLocationText: 'Dispatch Location Text',
            dispatchOverlayDescriptionText: 'Dispatch Description Text',
            dispatchOverlayFooterBorder: 'Dispatch Footer Border',
            dispatchOverlayButtonBg: 'Dispatch Button Background',
            dispatchOverlayButtonBorder: 'Dispatch Button Border',
            dispatchOverlayButtonText: 'Dispatch Button Text',
            dispatchOverlayButtonHoverBg: 'Dispatch Button Hover',
            tabletFrameBg: 'Frame Background',
            tabletFrameBorder: 'Frame Border',
            tabletTitlebarBg: 'Title Bar Background',
            // CSS Properties
            fontSizeXs: 'Extra Small',
            fontSizeSm: 'Small',
            fontSizeBase: 'Base',
            fontSizeLg: 'Large',
            fontSizeXl: 'Extra Large',
            fontSize2xl: '2XL',
            fontSize3xl: '3XL',
            fontSize4xl: '4XL',
            fontWeightLight: 'Light',
            fontWeightNormal: 'Normal',
            fontWeightMedium: 'Medium',
            fontWeightSemibold: 'Semibold',
            fontWeightBold: 'Bold',
            spacingXs: 'Extra Small',
            spacingSm: 'Small',
            spacingBase: 'Base',
            spacingMd: 'Medium',
            spacingLg: 'Large',
            spacingXl: 'Extra Large',
            spacing2xl: '2XL',
            radiusXs: 'Extra Small',
            radiusSm: 'Small',
            radiusBase: 'Base',
            radiusMd: 'Medium',
            radiusLg: 'Large',
            radiusXl: 'Extra Large',
            radius2xl: '2XL',
            radiusFull: 'Full',
            lineHeightTight: 'Tight',
            lineHeightSnug: 'Snug',
            lineHeightNormal: 'Normal',
            lineHeightRelaxed: 'Relaxed',
            lineHeightLoose: 'Loose',
            letterSpacingTight: 'Tight',
            letterSpacingNormal: 'Normal',
            letterSpacingWide: 'Wide',
            letterSpacingWider: 'Wider',
            transitionFast: 'Fast',
            transitionBase: 'Base',
            transitionSlow: 'Slow',
            transitionSlower: 'Slower',
            shadowSm: 'Small',
            shadowBase: 'Base',
            shadowMd: 'Medium',
            shadowLg: 'Large',
            shadowXl: 'Extra Large',
            shadowInner: 'Inner',
            opacityDisabled: 'Disabled',
            opacityHover: 'Hover',
            opacityActive: 'Active'
        };
        
        // Add color groups
        colorGroups.forEach(group => {
            const groupDiv = document.createElement('div');
            groupDiv.style.marginBottom = '20px';
            groupDiv.style.padding = '12px';
            groupDiv.style.background = 'rgba(255,255,255,0.02)';
            groupDiv.style.borderRadius = '8px';
            groupDiv.style.border = '1px solid rgba(255,255,255,0.08)';
            
            const title = document.createElement('div');
            title.textContent = group.title;
            title.style.fontSize = '13px';
            title.style.fontWeight = '600';
            title.style.color = 'rgba(255,255,255,0.9)';
            title.style.marginBottom = '4px';
            title.style.letterSpacing = '0.5px';
            groupDiv.appendChild(title);
            
            if (group.description) {
                const desc = document.createElement('div');
                desc.textContent = group.description;
                desc.style.fontSize = '11px';
                desc.style.color = 'rgba(255,255,255,0.5)';
                desc.style.marginBottom = '12px';
                desc.style.fontStyle = 'italic';
                groupDiv.appendChild(desc);
            }
            
            const colorGrid = document.createElement('div');
            colorGrid.style.display = 'grid';
            colorGrid.style.gridTemplateColumns = 'repeat(auto-fit, minmax(150px, 1fr))';
            colorGrid.style.gap = '10px';
            
            group.colors.forEach(colorKey => {
                const currentColor = pendingTheme[colorKey] || COLOR_PRESETS.default[colorKey];
                
                const colorItem = document.createElement('div');
                colorItem.style.display = 'flex';
                colorItem.style.flexDirection = 'column';
                colorItem.style.gap = '6px';
                
                const label = document.createElement('label');
                label.textContent = labelMap[colorKey] || colorKey;
                label.style.fontSize = '11px';
                label.style.color = 'rgba(255,255,255,0.6)';
                colorItem.appendChild(label);
                
                const inputContainer = document.createElement('div');
                inputContainer.style.display = 'flex';
                inputContainer.style.gap = '6px';
                inputContainer.style.alignItems = 'center';
                
                const colorInput = document.createElement('input');
                colorInput.type = 'color';
                colorInput.value = currentColor.substring(0, 7);
                colorInput.style.width = '40px';
                colorInput.style.height = '32px';
                colorInput.style.borderRadius = '4px';
                colorInput.style.border = 'none';
                colorInput.style.cursor = 'pointer';
                
                const hexInput = document.createElement('input');
                hexInput.type = 'text';
                hexInput.value = currentColor.substring(0, 7);
                hexInput.style.flex = '1';
                hexInput.style.height = '32px';
                hexInput.style.borderRadius = '4px';
                hexInput.style.border = '1px solid rgba(255,255,255,0.12)';
                hexInput.style.background = 'rgba(255,255,255,0.06)';
                hexInput.style.color = 'rgba(255,255,255,0.9)';
                hexInput.style.padding = '0 8px';
                hexInput.style.fontSize = '11px';
                hexInput.style.fontFamily = 'monospace';
                
                colorInput.addEventListener('input', (e) => {
                    hexInput.value = e.target.value;
                    pendingTheme[colorKey] = e.target.value;
                });
                
                hexInput.addEventListener('input', (e) => {
                    const val = e.target.value;
                    if (/^#[0-9A-F]{6}$/i.test(val)) {
                        colorInput.value = val;
                        pendingTheme[colorKey] = val;
                    }
                });
                
                inputContainer.appendChild(colorInput);
                inputContainer.appendChild(hexInput);
                colorItem.appendChild(inputContainer);
                colorGrid.appendChild(colorItem);
            });
            
            groupDiv.appendChild(colorGrid);
            container.appendChild(groupDiv);
        });
    }


    function updateColorInput(inputId, hexId, value) {
        const input = document.getElementById(inputId);
        const hex = document.getElementById(hexId);
        if (input) input.value = value;
        if (hex) hex.value = value;
    }

    function syncColorInputs(inputId, hexId, callback) {
        const input = document.getElementById(inputId);
        const hex = document.getElementById(hexId);
        if (!input || !hex) return;

        input.addEventListener('input', (e) => {
            hex.value = e.target.value;
            if (callback) callback(e.target.value);
        });
        hex.addEventListener('input', (e) => {
            const val = e.target.value;
            if (/^#[0-9A-F]{6}$/i.test(val)) {
                input.value = val;
                if (callback) callback(val);
            }
        });
    }

    const settingsBtn = document.getElementById('settingsBtn');
    const settingsModal = document.getElementById('settingsModal');
    const settingsModalClose = document.getElementById('settingsModalClose');
    const settingsApplyBtn = document.getElementById('settingsApplyBtn');
    const settingsDefaultBtn = document.getElementById('settingsDefaultBtn');
    const settingsLanguage = document.getElementById('settingsLanguage');
    const colorModeAll = document.getElementById('colorModeAll');
    const colorModeIndividual = document.getElementById('colorModeIndividual');
    const colorModeAllContainer = document.getElementById('colorModeAllContainer');
    const colorModeIndividualContainer = document.getElementById('colorModeIndividualContainer');
    const iconColorPreview = document.getElementById('iconColorPreview');

    const presetButtons = {
        default: document.getElementById('presetDefault'),
        dark: document.getElementById('presetDark'),
        green: document.getElementById('presetGreen'),
        purple: document.getElementById('presetPurple'),
        orange: document.getElementById('presetOrange')
    };

    function buildIconPreview() {
        if (!iconColorPreview) return;
        iconColorPreview.innerHTML = '';

        const iconCategories = [
            { label: 'Dashboard', key: 'dashboard', paths: ['M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z', 'M9 22v-10h6v10'] },
            { label: 'Dispatch', key: 'dispatch', paths: ['M11 11a9 9 0 1 1 18 0a9 9 0 0 1-18 0', 'M21 21l-4.35-4.35'] },
            { label: 'CCTV', key: 'cctv', paths: ['M14 8H10a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2v-6', 'M9 13l2 2 3-3 4 4', 'M17.5 6.5a1.5 1.5 0 1 0 3 0 1.5 1.5 0 0 0-3 0'] },
            { label: 'Citizens', key: 'citizens', paths: ['M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2', 'M12 7a4 4 0 1 0 0-8 4 4 0 0 0 0 8'] },
            { label: 'Vehicles', key: 'vehicles', paths: ['M19 17a2 2 0 0 0-2-2H7a2 2 0 0 0-2 2', 'M9 11h6V6H9z', 'M6 17a3 3 0 1 0 6 0 3 3 0 0 0-6 0', 'M18 17a3 3 0 1 0 6 0 3 3 0 0 0-6 0'] },
            { label: 'Warrant', key: 'warrant', paths: ['M6 2h12l-3 8v12l-6 0v-12z'] },
            { label: 'Court', key: 'court', paths: ['M9 2h6v4H9z', 'M8 6h8v10a2 2 0 0 1-2 2h-4a2 2 0 0 1-2-2V6', 'M6 18h12', 'M10 13v4', 'M14 13v4'] },
            { label: 'Criminal Code', key: 'criminalcode', paths: ['M4 3h16a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2', 'M9 11h6', 'M9 7h6', 'M9 15h6'] },
            { label: 'Weapons', key: 'weapons', paths: ['M3 16l1.5-1.5L10 20l-2 2H3z', 'M22 7l-8 8'] },
            { label: 'Reports', key: 'reports', paths: ['M13 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z', 'M13 2v7h7'] },
            { label: 'Incidents', key: 'incidents', paths: ['M12 2L2 20h20L12 2', 'M12 9v4', 'M12 17h.01'] },
            { label: 'FTO', key: 'fto', paths: ['M17 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2', 'M11 7v4h4V7H11', 'M7 11h10', 'M7 15h10'] },
            { label: 'Roster', key: 'roster', paths: ['M17 3a2.828 2.828 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5L17 3', 'M12 8v8', 'M8 12h8'] },
            { label: 'SOP', key: 'sop', paths: ['M4 4h16v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V4', 'M9 9h6', 'M9 13h6', 'M9 17h3'] },
            { label: 'Officers', key: 'officers', paths: ['M20 21v-2a4 4 0 0 0-4-4h-2a4 4 0 0 0-4 4v2', 'M16 11a2 2 0 1 0-4 0 2 2 0 0 0 4 0', 'M8 21v-2a4 4 0 0 1 4-4h4', 'M12 11a2 2 0 1 0-4 0 2 2 0 0 0 4 0'] }
        ];

        iconCategories.forEach(cat => {
            const container = document.createElement('div');
            container.style.display = 'grid';
            container.style.gridTemplateColumns = 'auto 1fr';
            container.style.gap = '12px';
            container.style.alignItems = 'center';
            container.style.padding = '12px';
            container.style.background = 'rgba(255,255,255,0.03)';
            container.style.borderRadius = '6px';

            const label = document.createElement('div');
            label.textContent = cat.label;
            label.style.fontSize = '12px';
            label.style.color = 'rgba(255,255,255,0.6)';
            label.style.gridColumn = '1 / -1';

            const inputWrapper = document.createElement('div');
            inputWrapper.style.display = 'flex';
            inputWrapper.style.gap = '10px';
            inputWrapper.style.alignItems = 'center';
            inputWrapper.style.gridColumn = '1 / -1';

            const iconKey = 'icon' + cat.key.charAt(0).toUpperCase() + cat.key.slice(1);
            const defaultColor = COLOR_PRESETS.default[iconKey];
            const currentColor = pendingTheme[iconKey] || defaultColor;

            const colorInput = document.createElement('input');
            colorInput.type = 'color';
            colorInput.value = currentColor;
            colorInput.style.width = '44px';
            colorInput.style.height = '44px';
            colorInput.style.borderRadius = '6px';
            colorInput.style.border = '1px solid rgba(255,255,255,0.12)';
            colorInput.style.cursor = 'pointer';
            colorInput.style.flexShrink = '0';

            const iconPreview = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
            iconPreview.setAttribute('width', '32');
            iconPreview.setAttribute('height', '32');
            iconPreview.setAttribute('viewBox', '0 0 24 24');
            iconPreview.setAttribute('fill', 'none');
            iconPreview.setAttribute('stroke', currentColor);
            iconPreview.setAttribute('stroke-width', '2');
            iconPreview.setAttribute('stroke-linecap', 'round');
            iconPreview.setAttribute('stroke-linejoin', 'round');
            iconPreview.style.flexShrink = '0';

            cat.paths.forEach(pathData => {
                const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
                path.setAttribute('d', pathData);
                iconPreview.appendChild(path);
            });

            colorInput.addEventListener('input', (e) => {
                iconPreview.setAttribute('stroke', e.target.value);
                pendingTheme[iconKey] = e.target.value;
            });

            inputWrapper.appendChild(colorInput);
            inputWrapper.appendChild(iconPreview);

            container.appendChild(label);
            container.appendChild(inputWrapper);
            iconColorPreview.appendChild(container);
        });
    }

    function openSettings() {
        if (!settingsModal) return;
        
        pendingTheme = { ...mdtTheme };
        
        const colorGroupsContainer = document.getElementById('colorGroupsContainer');
        buildColorGroupUI(colorGroupsContainer);
        buildIconPreview();
        
        settingsModal.classList.remove('hidden');
    }

    function closeSettings() {
        if (settingsModal) settingsModal.classList.add('hidden');
    }

    if (settingsBtn) settingsBtn.onclick = openSettings;
    if (settingsModalClose) settingsModalClose.onclick = closeSettings;
    if (settingsModal) settingsModal.addEventListener('click', (e)=>{ if (e.target === settingsModal) closeSettings(); });

    Object.entries(presetButtons).forEach(([key, btn]) => {
        if (btn) {
            btn.addEventListener('click', () => {
                if (COLOR_PRESETS[key]) {
                    pendingTheme = { ...COLOR_PRESETS[key] };
                    updateColorInput('colorPrimaryInput', 'colorPrimaryHex', pendingTheme.primary);
                    updateColorInput('colorBgInput', 'colorBgHex', pendingTheme.background);
                    updateColorInput('colorTextInput', 'colorTextHex', pendingTheme.text);
                    updateColorInput('colorIconInput', 'colorIconHex', pendingTheme.icon);
                    updateColorInput('colorCategoryText', 'colorCategoryTextHex', pendingTheme.categoryText);
                    updateColorInput('colorCategoryBg', 'colorCategoryBgHex', pendingTheme.categoryBg);
                    buildIconPreview();
                }
            });
        }
    });

    syncColorInputs('colorPrimaryInput', 'colorPrimaryHex', (val) => { pendingTheme.primary = val; });
    syncColorInputs('colorBgInput', 'colorBgHex', (val) => { pendingTheme.background = val; });
    syncColorInputs('colorTextInput', 'colorTextHex', (val) => { pendingTheme.text = val; });
    if (settingsApplyBtn) {
        settingsApplyBtn.addEventListener('click', () => {
            mdtTheme = { ...pendingTheme };
            applyThemeToDOM(mdtTheme);
            saveThemeToStorage(mdtTheme);
            closeSettings();
        });
    }

    if (settingsDefaultBtn) {
        settingsDefaultBtn.addEventListener('click', () => {
            pendingTheme = { ...COLOR_PRESETS.default };
            const colorGroupsContainer = document.getElementById('colorGroupsContainer');
            buildColorGroupUI(colorGroupsContainer);
            buildIconPreview();
        });
    }
    
    // Preset buttons
    Object.entries(presetButtons).forEach(([presetName, btn]) => {
        if (btn) {
            btn.addEventListener('click', () => {
                if (COLOR_PRESETS[presetName]) {
                    pendingTheme = { ...COLOR_PRESETS[presetName] };
                    mdtTheme = { ...pendingTheme };
                    
                    // Apply immediately to DOM
                    applyThemeToDOM(mdtTheme);
                    saveThemeToStorage(mdtTheme);
                    
                    // Update the color UI in settings if open
                    const colorGroupsContainer = document.getElementById('colorGroupsContainer');
                    if (colorGroupsContainer && !settingsModal.classList.contains('hidden')) {
                        buildColorGroupUI(colorGroupsContainer);
                        buildIconPreview();
                    }
                    
                    // Update button states
                    Object.values(presetButtons).forEach(b => b && b.classList.remove('active'));
                    btn.classList.add('active');
                }
            });
        }
    });

    applyThemeToDOM(mdtTheme);

    // Universal close-modal handler for all modals
    document.querySelectorAll('.close-modal').forEach(btn => {
        btn.addEventListener('click', (e) => {
            const modal = e.target.closest('.modal');
            if (modal) modal.classList.add('hidden');
        });
    });
}

// ============================================================================
// Vehicle Detail Modal Overlay (NOT a full page)
// ============================================================================

let currentVehicleFlag = '';

function refreshVehicleDatabaseIfActive() {
    try {
        const r = window.router || router;
        if (!r || !r.pages) return;
        // Only refresh if the Vehicle Database page is the current route.
        if (r.current !== 'vehicles') return;
        const vehiclesPage = r.pages.get('vehicles');
        if (vehiclesPage && typeof vehiclesPage.loadVehicles === 'function') {
            vehiclesPage.loadVehicles();
        }
    } catch (_) {}
}

function updateVehicleFlagUi() {
    const btnText = document.getElementById('vehFlagBtnText');
    const removeBtn = document.getElementById('vehFlagRemoveBtn');
    const active = String(currentVehicleFlag || '').trim().toUpperCase();

    if (btnText) {
        btnText.textContent = active ? `Flag: ${active}` : 'Add Flag';
    }
    if (removeBtn) {
        removeBtn.disabled = !active;
        removeBtn.style.opacity = active ? '1' : '0.55';
        removeBtn.style.cursor = active ? 'pointer' : 'not-allowed';
    }
}

function openVehicleDetail(payload) {
    console.log('[MDT DEBUG] openVehicleDetail called with payload:', payload);
    const backdrop = document.getElementById('vehicleDetailBackdrop');
    const modal = document.getElementById('vehicleDetailModal');
    console.log('[MDT DEBUG] backdrop:', backdrop, 'modal:', modal);
    if (backdrop && modal) {
        console.log('[MDT DEBUG] Removing hidden class from backdrop and modal');
        backdrop.classList.remove('hidden');
        modal.classList.remove('hidden');
        setVehicleDetail(payload);
    } else {
        console.error('[MDT ERROR] Missing backdrop or modal elements!');
    }
}

function closeVehicleDetail() {
    const backdrop = document.getElementById('vehicleDetailBackdrop');
    const modal = document.getElementById('vehicleDetailModal');
    if (backdrop && modal) {
        backdrop.classList.add('hidden');
        modal.classList.add('hidden');
        currentVehiclePlate = null;
    }
}

function setupVehicleDetailModal() {
    const backdrop = document.getElementById('vehicleDetailBackdrop');
    const modal = document.getElementById('vehicleDetailModal');
    const closeBtn = document.getElementById('vehCloseBtn');
    const backBtn = document.getElementById('vehBackBtn');

    // Close on back button
    if (backBtn) {
        backBtn.onclick = () => {
            closeVehicleDetail();
        };
    }

    // Close on close button (X)
    if (closeBtn) {
        closeBtn.onclick = () => {
            closeVehicleDetail();
        };
    }

    // Close on backdrop click
    if (backdrop) {
        backdrop.onclick = (e) => {
            if (e.target === backdrop) {
                closeVehicleDetail();
            }
        };
    }

    // Close on ESC key
    const handleEsc = (e) => {
        if (e.key === 'Escape') {
            const modal = document.getElementById('vehicleDetailModal');
            if (modal && !modal.classList.contains('hidden')) {
                closeVehicleDetail();
            }
        }
    };
    document.addEventListener('keydown', handleEsc);

    // Prevent backdrop click from propagating
    if (modal) {
        modal.onclick = (e) => {
            e.stopPropagation();
        };
    }

    // Vehicle flag dropdown
    const flagBtn = document.getElementById('vehFlagBtn');
    const flagMenu = document.getElementById('vehFlagMenu');
    const flagSelect = document.getElementById('vehFlagSelect');
    const flagSetBtn = document.getElementById('vehFlagSetBtn');
    const flagRemoveBtn = document.getElementById('vehFlagRemoveBtn');

    const normalizeFlagValue = (val) => String(val || '').trim().toUpperCase();
    const getPlateFromUi = () => {
        const plate = currentVehicleInfo?.plate || document.getElementById('vehPlateText')?.textContent || '';
        return String(plate || '').trim();
    };

    const closeFlagMenu = () => {
        if (flagMenu) flagMenu.classList.add('hidden');
    };

    const syncFlagSelect = () => {
        if (!flagSelect) return;
        const active = normalizeFlagValue(currentVehicleFlag);
        flagSelect.value = active;
        // If the active flag isn't one of the dropdown options, default to none.
        if (flagSelect.value !== active) {
            flagSelect.value = '';
        }
        updateVehicleFlagUi();
    };

    if (flagBtn) {
        flagBtn.onclick = (e) => {
            e.stopPropagation();
            if (!flagMenu) return;
            const isOpen = !flagMenu.classList.contains('hidden');
            if (isOpen) {
                closeFlagMenu();
            } else {
                syncFlagSelect();
                flagMenu.classList.remove('hidden');
            }
        };
    }

    if (flagSetBtn) {
        flagSetBtn.onclick = (e) => {
            e.stopPropagation();
            const plate = getPlateFromUi();
            const flag = normalizeFlagValue(flagSelect?.value);
            if (!plate) return;
            if (!flag) {
                mdtToastSafe('Select a flag first', 'error');
                return;
            }
            sendCallback('addVehicleFlag', { plate, flag });
            closeFlagMenu();
            setTimeout(() => {
                try { sendCallback('openVehicle', { plate }); } catch (_) {}
                refreshVehicleDatabaseIfActive();
            }, 250);
        };
    }

    if (flagRemoveBtn) {
        flagRemoveBtn.onclick = (e) => {
            e.stopPropagation();
            const plate = getPlateFromUi();
            if (!plate) return;
            if (!normalizeFlagValue(currentVehicleFlag)) return;
            sendCallback('removeVehicleFlag', { plate });
            closeFlagMenu();
            setTimeout(() => {
                try { sendCallback('openVehicle', { plate }); } catch (_) {}
                refreshVehicleDatabaseIfActive();
            }, 250);
        };
    }

    // Click-away closes the dropdown
    document.addEventListener('click', (e) => {
        if (!flagMenu || flagMenu.classList.contains('hidden')) return;
        if (flagMenu.contains(e.target)) return;
        if (flagBtn && flagBtn.contains(e.target)) return;
        closeFlagMenu();
    });

    // Initial state
    updateVehicleFlagUi();
}

function renderActivityCard(a) {
    const eventType = a.type || 'Unknown';
    const timestamp = formatDateTime(a.timestamp || a.createdAt);
    const location = a.location || 'Unknown';
    const officer = a.officer || a.officerName || 'Unknown';
    const refId = a.referenceId || '';
    const icon = {
        'traffic_stop': '🚔',
        'ped_check': '🚶',
        'alpr': '📸',
        'bolo': '⚠️',
        'impound': '🏢',
        'arrest': '🔒',
        'release': '🔓',
        'evidence': '📦',
        'warrant': '📋',
        'dispatch': '📞'
    }[eventType] || '📌';
    
    return `
      <div class="activity-card" style="padding: 14px; border-radius: 8px; border: 1px solid rgba(255,255,255,0.08); background: rgba(255,255,255,0.03); margin-bottom: 8px;">
        <div style="display: flex; gap: 8px; align-items: flex-start;">
          <span style="font-size: 16px;">${icon}</span>
          <div style="flex: 1;">
            <div style="font-weight: 600; margin-bottom: 4px;">${escapeHtml(eventType)}</div>
            <div style="font-size: 12px; color: rgba(255,255,255,0.7); display: flex; gap: 12px; margin-bottom: 4px;">
              <span>📅 ${timestamp}</span>
              <span>📍 ${escapeHtml(location)}</span>
            </div>
            <div style="font-size: 12px; color: rgba(255,255,255,0.6);">Officer: ${escapeHtml(officer)}</div>
            ${refId ? `<div style="font-size: 11px; color: rgba(255,255,255,0.5); margin-top: 4px;">Ref: ${escapeHtml(refId)}</div>` : ''}
          </div>
        </div>
      </div>
    `;
}

function formatReportType(type) {
    // Convert snake_case or lowercase to Title Case
    if (!type) return 'Unknown';
    return type
        .split('_')
        .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
        .join(' ');
}

function renderReportCard(r) {
    const reportId = r.reportId || 'N/A';
    const type = r.type || 'Unknown';
    const typeFormatted = formatReportType(type);
    const category = r.category || r.subcategory || 'General';
    const timestamp = formatDateTime(r.timestamp || r.createdAt);
    const location = r.location || 'Unknown';
    const narrative = r.narrative || r.description || '';
    const approvalStatus = r.approvalStatus || r.status || 'Pending';
    
    const typeIcon = {
        'traffic_citation': '�',
        'arrest': '🔒',
        'incident': '📋',
        'use_of_force': '⚠️',
        'pursuit': '�',
        'accident': '�',
        'seizure': '�'
    }[String(type || '').toLowerCase()] || '📄';
    
    const approvalColor = {
        'approved': { bg: 'rgba(34,197,94,0.15)', border: 'rgba(34,197,94,0.3)', text: '#22c55e' },
        'pending': { bg: 'rgba(168,85,247,0.15)', border: 'rgba(168,85,247,0.3)', text: '#a855f7' },
        'rejected': { bg: 'rgba(239,68,68,0.15)', border: 'rgba(239,68,68,0.3)', text: '#ef4444' }
    };
    
    const statusKey = approvalStatus.toLowerCase();
    const statusStyle = approvalColor[statusKey] || approvalColor['pending'];
    
    // Truncate narrative for compact view
    const shortNarrative = narrative.length > 80 ? narrative.substring(0, 80) + '...' : narrative;
    
    // Check if user can approve reports (ranks 3-4)
    const canApprove = userInfo.rankLevel === 3 || userInfo.rankLevel === 4;
    const isPending = approvalStatus.toLowerCase() === 'pending';
    const showApproveBtn = canApprove && isPending;
    
    return `
      <div class="report-card" style="padding: 10px 12px; border-radius: 10px; border: 1px solid rgba(255,255,255,0.08); background: rgba(255,255,255,0.03); margin-bottom: 8px;">
        <div class="report-card-compact">
          <div class="report-card-icon">${typeIcon}</div>
          <div class="report-card-content">
            <div class="report-card-header">
              <div class="report-card-title">${escapeHtml(typeFormatted)} Report</div>
              <div class="report-card-badges">
                <span class="report-card-badge" style="border-color: rgba(59,130,246,0.3); background: rgba(59,130,246,0.15); color: #3b82f6;">${escapeHtml(category)}</span>
                <span class="report-card-badge" style="border-color: ${statusStyle.border}; background: ${statusStyle.bg}; color: ${statusStyle.text};">${escapeHtml(approvalStatus)}</span>
              </div>
            </div>
            <div class="report-card-meta">
              <span class="report-card-meta-item">📅 ${timestamp}</span>
              <span class="report-card-meta-item">📍 ${escapeHtml(location)}</span>
            </div>
            ${shortNarrative ? `<div class="report-card-description">${escapeHtml(shortNarrative)}</div>` : ''}
            <div class="report-card-footer">
              <span class="report-card-id">ID: ${escapeHtml(reportId)}</span>
              <div class="report-card-actions">
                ${showApproveBtn ? `<button class="report-approve-btn" onclick="approveReport(this, '${escapeHtml(reportId)}')" title="Approve Report">✓ Approve</button>` : ''}
                <button class="report-details-btn" onclick="showReportDetails('${escapeHtml(reportId)}')">View Details</button>
                ${(typeof window.playerGrade !== 'undefined' && window.playerGrade >= 4) ? `<button class="report-delete-btn" onclick="deleteReport(this, '${escapeHtml(reportId)}')" title="Delete Report" style="background: linear-gradient(135deg, rgba(244,67,54,0.3), rgba(211,47,47,0.3)); border-color: rgba(244,67,54,0.5); color: rgba(255,107,107,1);">🗑️ Delete</button>` : ''}
              </div>
            </div>
          </div>
        </div>
      </div>
    `;
}

function approveReport(btn, reportId) {
    if (!reportId) return;

    // Disable button and show progress without blocking UI
    if (btn) {
        btn.disabled = true;
        btn.dataset.originalText = btn.innerText;
        btn.innerText = 'Approving…';
    }

    sendCallback('approveReport', { reportId }, (response) => {
        if (response && response.success) {
            // Update button state
            if (btn) {
                btn.innerText = 'Approved';
            }

            // Refresh the vehicle view if we're in vehicle modal
            const plate = currentVehicleInfo?.plate;
            if (plate) {
                setTimeout(() => {
                    sendCallback('openVehicle', { plate });
                }, 400);
            }
        } else {
            // Restore button on failure
            if (btn) {
                btn.disabled = false;
                btn.innerText = btn.dataset.originalText || '✓ Approve';
            }
            mdtToastSafe('Failed to approve report', 'error');
        }
    });
}

function deleteReport(btn, reportId) {
    if (!reportId) return;

    if (!confirm('Are you sure you want to DELETE this report? This cannot be undone.')) return;

    if (btn) {
        btn.disabled = true;
        btn.dataset.originalText = btn.innerText;
        btn.innerText = 'Deleting…';
    }

    fetch('https://' + window.resName + '/pf_mdt:deleteReport', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify({ reportId })
    }).then(res => res.json()).then(data => {
        mdtToastSafe('Report deleted', 'success');
        // Refresh reports list
        setTimeout(() => {
            const page = window.router?.pages?.get('reports');
            if (page && page.render) page.render();
        }, 300);
    }).catch(err => {
        if (btn) {
            btn.disabled = false;
            btn.innerText = btn.dataset.originalText || '🗑️ Delete';
        }
        mdtToastSafe('Failed to delete report', 'error');
    });
}

function showReportDetails(reportId) {
    // Find the report data from the cache or request from server
    const report = allReportsCache.find(r => r.reportId === reportId);
    if (!report) {
        console.warn('Report not found:', reportId);
        return;
    }

    const officer = report.officer || report.officerName || 'Unknown';
    const title = report.title || report.narrative || 'Report';
    const type = report.type || 'Unknown';
    const typeFormatted = formatReportType(type);
    const category = report.category || report.subcategory || 'General';
    const timestamp = formatDateTime(report.timestamp || report.createdAt);
    const location = report.location || 'Unknown';
    const narrative = report.narrative || report.description || '';
    const involvedParties = report.involvedParties || report.subjects || [];
    const evidence = report.linkedEvidence || report.evidence || [];
    const approvalStatus = report.approvalStatus || report.status || 'Pending';
    const content = report.content || '';

    const typeIcon = {
        'traffic_citation': '🚨',
        'arrest': '🔒',
        'incident': '📋',
        'use_of_force': '⚠️',
        'pursuit': '🚓',
        'accident': '💥',
        'seizure': '📦'
    }[String(type || '').toLowerCase()] || '📄';

    const approvalColor = {
        'approved': { bg: 'rgba(34,197,94,0.15)', border: 'rgba(34,197,94,0.3)', text: '#22c55e' },
        'pending': { bg: 'rgba(168,85,247,0.15)', border: 'rgba(168,85,247,0.3)', text: '#a855f7' },
        'rejected': { bg: 'rgba(239,68,68,0.15)', border: 'rgba(239,68,68,0.3)', text: '#ef4444' }
    };

    const statusKey = approvalStatus.toLowerCase();
    const statusStyle = approvalColor[statusKey] || approvalColor['pending'];

    // Parse involved parties if it's JSON string
    let involvedList = [];
    if (typeof involvedParties === 'string') {
        try {
            involvedList = JSON.parse(involvedParties);
        } catch {
            involvedList = involvedParties.split(',').map(s => s.trim()).filter(Boolean);
        }
    } else if (Array.isArray(involvedParties)) {
        involvedList = involvedParties;
    }
    involvedList = (involvedList || []).map(formatLabel);

    // Parse evidence if it's JSON string
    let evidenceList = [];
    if (typeof evidence === 'string') {
        try {
            evidenceList = JSON.parse(evidence);
        } catch {
            evidenceList = evidence.split(',').map(s => s.trim()).filter(Boolean);
        }
    } else if (Array.isArray(evidence)) {
        evidenceList = evidence;
    }
    evidenceList = (evidenceList || []).map(formatLabel);

    const modalHTML = `
        <div class="modal" id="reportDetailsModal" style="z-index: 10015;">
            <div class="modal-card" style="width: 85vh; max-width: 90vh; max-height: 80vh;">
                <div class="modal-header">
                    <div>
                        <div style="font-size: 24px; margin-bottom: 4px;">${typeIcon}</div>
                        <h2 style="margin: 0; font-size: 16px;">Report Details</h2>
                    </div>
                    <button class="modal-btn" id="reportDetailsClose" title="Close">
                        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <line x1="18" y1="6" x2="6" y2="18"></line>
                            <line x1="6" y1="6" x2="18" y2="18"></line>
                        </svg>
                    </button>
                </div>
                <div class="modal-body" style="max-height: 65vh; overflow-y: auto; flex: 1; min-height: 0;">
                    <div style="padding: 16px;">
                        <!-- Header -->
                        <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 16px; flex-wrap: wrap; gap: 8px;">
                            <div>
                                <div style="font-size: 11px; color: rgba(255,255,255,0.5); margin-bottom: 4px;">REPORT ID</div>
                                <div style="font-weight: 700; font-size: 15px;">#${escapeHtml(reportId)}</div>
                            </div>
                            <div style="display: flex; gap: 6px;">
                                <span style="font-size: 11px; padding: 4px 10px; border-radius: 6px; border: 1px solid rgba(59,130,246,0.3); background: rgba(59,130,246,0.15); color: #3b82f6;">${escapeHtml(category)}</span>
                                <span style="font-size: 11px; padding: 4px 10px; border-radius: 6px; border: 1px solid ${statusStyle.border}; background: ${statusStyle.bg}; color: ${statusStyle.text};">${escapeHtml(approvalStatus)}</span>
                            </div>
                        </div>

                        <!-- Type -->
                        <div style="margin-bottom: 16px;">
                            <div style="font-size: 11px; color: rgba(255,255,255,0.5); margin-bottom: 4px;">TYPE</div>
                            <div style="font-weight: 600; font-size: 14px;">${escapeHtml(typeFormatted)}</div>
                        </div>

                        <!-- Meta Information -->
                        <div style="display: grid; grid-template-columns: repeat(2, 1fr); gap: 12px; margin-bottom: 16px;">
                            <div>
                                <div style="font-size: 11px; color: rgba(255,255,255,0.5); margin-bottom: 4px;">DATE & TIME</div>
                                <div style="font-size: 13px;">📅 ${timestamp}</div>
                            </div>
                            <div>
                                <div style="font-size: 11px; color: rgba(255,255,255,0.5); margin-bottom: 4px;">OFFICER</div>
                                <div style="font-size: 13px;">👤 ${escapeHtml(officer)}</div>
                            </div>
                            <div style="grid-column: 1 / -1;">
                                <div style="font-size: 11px; color: rgba(255,255,255,0.5); margin-bottom: 4px;">LOCATION</div>
                                <div style="font-size: 13px;">📍 ${escapeHtml(location)}</div>
                            </div>
                        </div>

                        ${narrative ? `
                        <div style="margin-bottom: 16px;">
                            <div style="font-size: 11px; color: rgba(255,255,255,0.5); margin-bottom: 6px;">NARRATIVE</div>
                            <div style="padding: 12px; background: rgba(255,255,255,0.03); border-left: 3px solid rgba(59,130,246,0.5); border-radius: 4px; font-size: 13px; line-height: 1.6; color: rgba(255,255,255,0.85);">
                                ${escapeHtml(narrative)}
                            </div>
                        </div>
                        ` : ''}

                        ${involvedList.length > 0 ? `
                        <div style="margin-bottom: 16px;">
                            <div style="font-size: 11px; color: rgba(255,255,255,0.5); margin-bottom: 6px;">INVOLVED PARTIES</div>
                            <div style="display: flex; flex-wrap: wrap; gap: 6px;">
                                ${involvedList.map(p => `<span style="font-size: 11px; padding: 4px 10px; border-radius: 6px; border: 1px solid rgba(255,255,255,0.15); background: rgba(255,255,255,0.06);">👤 ${escapeHtml(p)}</span>`).join('')}
                            </div>
                        </div>
                        ` : ''}

                        ${evidenceList.length > 0 ? `
                        <div style="margin-bottom: 16px;">
                            <div style="font-size: 11px; color: rgba(255,255,255,0.5); margin-bottom: 6px;">LINKED EVIDENCE</div>
                            <div style="display: flex; flex-wrap: wrap; gap: 6px;">
                                ${evidenceList.map(e => `<span style="font-size: 11px; padding: 4px 10px; border-radius: 6px; border: 1px solid rgba(255,193,7,0.3); background: rgba(255,193,7,0.1); color: #ffc107;">📦 ${escapeHtml(e)}</span>`).join('')}
                            </div>
                        </div>
                        ` : ''}

                        ${content ? `
                        <div>
                            <div style="font-size: 11px; color: rgba(255,255,255,0.5); margin-bottom: 6px;">ADDITIONAL DETAILS</div>
                            <div style="padding: 12px; background: rgba(255,255,255,0.03); border-radius: 4px; font-size: 12px; line-height: 1.6; color: rgba(255,255,255,0.75); white-space: pre-wrap;">
                                ${escapeHtml(content)}
                            </div>
                        </div>
                        ` : ''}
                    </div>
                </div>
            </div>
        </div>
    `;

    // Remove existing modal if present
    const existing = document.getElementById('reportDetailsModal');
    if (existing) existing.remove();

    // Insert modal into DOM
    document.body.insertAdjacentHTML('beforeend', modalHTML);

    // Close on background click
    const modal = document.getElementById('reportDetailsModal');
    modal.addEventListener('click', (e) => {
        if (e.target === modal) closeReportDetailsModal();
    });

    // Close on header X click
    const closeBtn = document.getElementById('reportDetailsClose');
    if (closeBtn) closeBtn.onclick = closeReportDetailsModal;
}

function closeReportDetailsModal() {
    const modal = document.getElementById('reportDetailsModal');
    if (modal) modal.remove();
}

// Cache for all reports
let allReportsCache = [];

function generateReportId() {
    const now = new Date();
    const yy = now.getFullYear().toString().slice(2);
    const mm = String(now.getMonth() + 1).padStart(2, '0');
    const dd = String(now.getDate()).padStart(2, '0');
    const hh = String(now.getHours()).padStart(2, '0');
    const min = String(now.getMinutes()).padStart(2, '0');
    return `RPT-${yy}${mm}${dd}${hh}${min}`; // 14 chars total, fits VARCHAR(16)
}

function parseListValue(id) {
    const el = document.getElementById(id);
    if (!el) return [];
    return el.value.split(',').map(s => s.trim()).filter(Boolean);
}

// ============================================================================
// VEHICLE REPORT LINKED DROPDOWNS (Citizens / Weapons / Incidents / Evidence)
// ============================================================================

let __vehReportDropdownsWired = false;

const __vehReportCatalog = {
    citizens: [],
    incidents: [],
    evidence: [],
    weapons: [] // registered weapons from registry
};

const __vehReportSelected = {
    citizens: [], // [{ id, name }]
    incidents: [], // [{ id, label }]
    evidence: [], // [{ id, label }]
    weapons: [] // [{ id, label }]
};

function __vehReportNormalize(s) {
    return String(s || '').toLowerCase().trim();
}

function __vehReportSetHidden(id, values) {
    const el = document.getElementById(id);
    if (!el) return;
    el.value = (Array.isArray(values) ? values : []).join(', ');
}

function __vehReportRenderChips(listId, items, onRemove) {
    const list = document.getElementById(listId);
    if (!list) return;
    list.innerHTML = (items || []).map(it => {
        const key = encodeURIComponent(String(it.id || ''));
        const label = String(it.label || it.name || it.id || '').trim();
        return `<span class="chip" data-key="${escapeHtml(key)}" style="background: rgba(59,130,246,0.2); padding: 4px 8px; border-radius: 6px; display: inline-flex; align-items: center; gap: 6px; border: 1px solid rgba(59,130,246,0.25);">
            <span style="max-width: 260px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${escapeHtml(label)}</span>
            <button type="button" data-remove="${escapeHtml(key)}" style="background: none; border: none; color: rgba(255,255,255,0.85); cursor: pointer; padding: 0 4px;">×</button>
        </span>`;
    }).join('');

    list.querySelectorAll('button[data-remove]').forEach(btn => {
        btn.addEventListener('click', (e) => {
            e.preventDefault();
            e.stopPropagation();
            const key = decodeURIComponent(btn.getAttribute('data-remove') || '');
            onRemove && onRemove(key);
        });
    });
}

function __vehReportWirePicker(opts) {
    const searchEl = document.getElementById(opts.searchId);
    const dropdownEl = document.getElementById(opts.dropdownId);
    const listId = opts.listId;
    const hiddenId = opts.hiddenId;

    const containerEl = searchEl ? (searchEl.closest('label') || searchEl.parentElement) : null;

    if (!searchEl || !dropdownEl) return;

    const closeDropdown = () => {
        dropdownEl.classList.add('hidden');
    };

    const openDropdown = () => {
        dropdownEl.classList.remove('hidden');
    };

    const syncHidden = () => {
        const ids = (opts.getSelected() || []).map(x => String(x.id || '').trim()).filter(Boolean);
        __vehReportSetHidden(hiddenId, ids);
        __vehReportRenderChips(listId, opts.getSelected(), (removeId) => {
            opts.removeSelected(removeId);
            syncHidden();
        });
    };

    const renderDropdown = (query) => {
        const q = __vehReportNormalize(query);
        const all = opts.getAllItems() || [];
        const selectedIds = new Set((opts.getSelected() || []).map(x => String(x.id)));

        let rows = all;
        if (q) {
            rows = all.filter(it => {
                const hay = __vehReportNormalize(opts.getSearchText(it));
                return hay.includes(q);
            });
        }

        // Optional: allow custom entry when query doesn't match (weapons non-registered)
        const custom = (opts.allowCustom && q) ? String(query || '').trim() : '';
        const canAddCustom = !!(custom && !selectedIds.has(custom));

        const max = opts.maxItems || 60;
        const shown = rows.slice(0, max);

        if ((!q && opts.openOnEmpty !== true) && shown.length === 0 && !canAddCustom) {
            closeDropdown();
            return;
        }

        const html = [];
        if (canAddCustom) {
            html.push(`<div class="dropdown-item" data-id="${escapeHtml(custom)}" data-custom="1" style="padding: 8px; cursor: pointer; border-bottom: 1px solid rgba(255,255,255,0.05);">
                <div style="font-weight: 700;">Add: ${escapeHtml(custom)}</div>
                <div class="muted" style="margin-top: 2px;">Non-registered / manual entry</div>
            </div>`);
        }

        html.push(...shown.map(it => {
            const id = String(opts.getId(it));
            const label = String(opts.getLabel(it));
            const disabled = selectedIds.has(id);
            const opacity = disabled ? '0.45' : '1';
            return `<div class="dropdown-item" data-id="${escapeHtml(id)}" data-label="${escapeHtml(label)}" style="padding: 8px; cursor: ${disabled ? 'default' : 'pointer'}; border-bottom: 1px solid rgba(255,255,255,0.05); opacity: ${opacity};">
                ${escapeHtml(label)}
            </div>`;
        }));

        dropdownEl.innerHTML = html.join('');
        openDropdown();
    };

    searchEl.addEventListener('input', (e) => {
        renderDropdown(e.target.value);
    });
    searchEl.addEventListener('focus', () => {
        if (opts.openOnFocus) renderDropdown(searchEl.value);
    });

    dropdownEl.addEventListener('click', (e) => {
        const item = e.target.closest('.dropdown-item');
        if (!item) return;
        const id = String(item.getAttribute('data-id') || '').trim();
        if (!id) return;
        const isCustom = item.getAttribute('data-custom') === '1';

        if (!isCustom) {
            // If it was already selected, ignore
            const selectedIds = new Set((opts.getSelected() || []).map(x => String(x.id)));
            if (selectedIds.has(id)) return;
        }

        const label = isCustom ? id : String(item.getAttribute('data-label') || id);
        opts.addSelected({ id, label });
        syncHidden();

        searchEl.value = '';
        closeDropdown();
        searchEl.focus();
    });

    // Close when clicking outside
    // Use capture=true because some modals stopPropagation() inside their cards.
    document.addEventListener('click', (e) => {
        if (dropdownEl.classList.contains('hidden')) return;
        if (containerEl && containerEl.contains(e.target)) return;
        if (searchEl.contains(e.target) || dropdownEl.contains(e.target)) return;
        closeDropdown();
    }, true);

    // Expose sync for external resets
    opts._syncHidden = syncHidden;
}

function __vehReportResetLinkedPickers() {
    __vehReportSelected.citizens = [];
    __vehReportSelected.weapons = [];
    __vehReportSelected.incidents = [];
    __vehReportSelected.evidence = [];

    __vehReportSetHidden('vehReportLinkedCitizens', []);
    __vehReportSetHidden('vehReportLinkedWeapons', []);
    __vehReportSetHidden('vehReportLinkedIncidents', []);
    __vehReportSetHidden('vehReportEvidence', []);

    __vehReportRenderChips('vehReportLinkedCitizensList', [], null);
    __vehReportRenderChips('vehReportLinkedWeaponsList', [], null);
    __vehReportRenderChips('vehReportLinkedIncidentsList', [], null);
    __vehReportRenderChips('vehReportEvidenceList', [], null);

    const ids = [
        'vehReportLinkedCitizensSearch',
        'vehReportLinkedWeaponsSearch',
        'vehReportLinkedIncidentsSearch',
        'vehReportEvidenceSearch'
    ];
    ids.forEach(i => {
        const el = document.getElementById(i);
        if (el) el.value = '';
    });
}

function __vehReportLoadLinkedCatalogs() {
    // Citizens
    try {
        sendCallback('pf_mdt:getAllCitizens', {}, (res) => {
            __vehReportCatalog.citizens = Array.isArray(res) ? res : [];
        });
    } catch (_) {}

    // Incidents
    try {
        sendCallback('pf_mdt:getAllIncidents', {}, (res) => {
            __vehReportCatalog.incidents = Array.isArray(res) ? res : [];
        });
    } catch (_) {}

    // Evidence (all)
    try {
        sendCallback('pf_mdt:getAllEvidence', {}, (res) => {
            __vehReportCatalog.evidence = Array.isArray(res) ? res : [];
        });
    } catch (_) {}

    // Weapons registry (registered)
    try {
        sendCallback('getWeaponRegistry', {}, (res) => {
            const rows = (res && res.success && Array.isArray(res.weapons)) ? res.weapons : [];
            __vehReportCatalog.weapons = rows.map(w => {
                const serial = w.serial || w.serialNumber || w.weaponSerial || w.serial_number || '';
                const weaponLabel = w.weaponLabel || w.weapon_label || w.weapon || w.weaponHash || '';
                const ownerName = w.ownerName || w.owner_name || w.owner || '';
                const ownerCid = w.ownerCitizenId || w.owner_citizenid || w.citizenid || '';
                return {
                    serial: String(serial || ''),
                    label: `${serial}${weaponLabel ? ` - ${weaponLabel}` : ''}${ownerName || ownerCid ? ` (${[ownerName, ownerCid].filter(Boolean).join(' ')})` : ''}`
                };
            }).filter(w => w.serial);
        });
    } catch (_) {}
}

function __vehReportEnsureLinkedPickersWired() {
    if (__vehReportDropdownsWired) return;
    __vehReportDropdownsWired = true;

    __vehReportWirePicker({
        searchId: 'vehReportLinkedCitizensSearch',
        dropdownId: 'vehReportLinkedCitizensDropdown',
        listId: 'vehReportLinkedCitizensList',
        hiddenId: 'vehReportLinkedCitizens',
        openOnFocus: true,
        openOnEmpty: false,
        getAllItems: () => __vehReportCatalog.citizens,
        getId: (c) => c.citizenId,
        getLabel: (c) => `${c.name} (${c.citizenId})`,
        getSearchText: (c) => `${c.name} ${c.citizenId}`,
        getSelected: () => __vehReportSelected.citizens,
        addSelected: (it) => {
            __vehReportSelected.citizens.push({ id: it.id, label: it.label });
        },
        removeSelected: (id) => {
            __vehReportSelected.citizens = __vehReportSelected.citizens.filter(x => String(x.id) !== String(id));
        }
    });

    __vehReportWirePicker({
        searchId: 'vehReportLinkedIncidentsSearch',
        dropdownId: 'vehReportLinkedIncidentsDropdown',
        listId: 'vehReportLinkedIncidentsList',
        hiddenId: 'vehReportLinkedIncidents',
        openOnFocus: true,
        openOnEmpty: false,
        getAllItems: () => __vehReportCatalog.incidents,
        getId: (i) => i.incidentId,
        getLabel: (i) => `${i.incidentId} - ${i.title || 'Untitled'}`,
        getSearchText: (i) => `${i.incidentId} ${i.title || ''}`,
        getSelected: () => __vehReportSelected.incidents,
        addSelected: (it) => {
            __vehReportSelected.incidents.push({ id: it.id, label: it.label });
        },
        removeSelected: (id) => {
            __vehReportSelected.incidents = __vehReportSelected.incidents.filter(x => String(x.id) !== String(id));
        }
    });

    __vehReportWirePicker({
        searchId: 'vehReportEvidenceSearch',
        dropdownId: 'vehReportEvidenceDropdown',
        listId: 'vehReportEvidenceList',
        hiddenId: 'vehReportEvidence',
        openOnFocus: true,
        openOnEmpty: false,
        getAllItems: () => __vehReportCatalog.evidence,
        getId: (e) => (e.evidence_number != null) ? String(e.evidence_number) : (e.evidenceId || e.evidence_id || e.id),
        getLabel: (e) => {
            const num = (e.evidence_number != null) ? `#${e.evidence_number}` : '';
            const title = e.title || 'Untitled';
            const evid = e.evidence_id || e.evidenceId || '';
            const right = evid ? ` (${evid})` : '';
            return `Evidence ${num} - ${title}${right}`.trim();
        },
        getSearchText: (e) => {
            const num = (e.evidence_number != null) ? String(e.evidence_number) : '';
            return `${num} ${e.title || ''} ${e.evidence_id || ''} ${e.tags || ''}`;
        },
        getSelected: () => __vehReportSelected.evidence,
        addSelected: (it) => {
            __vehReportSelected.evidence.push({ id: it.id, label: it.label });
        },
        removeSelected: (id) => {
            __vehReportSelected.evidence = __vehReportSelected.evidence.filter(x => String(x.id) !== String(id));
        }
    });

    __vehReportWirePicker({
        searchId: 'vehReportLinkedWeaponsSearch',
        dropdownId: 'vehReportLinkedWeaponsDropdown',
        listId: 'vehReportLinkedWeaponsList',
        hiddenId: 'vehReportLinkedWeapons',
        openOnFocus: true,
        openOnEmpty: false,
        allowCustom: true,
        getAllItems: () => __vehReportCatalog.weapons,
        getId: (w) => w.serial,
        getLabel: (w) => w.label || w.serial,
        getSearchText: (w) => `${w.serial} ${w.label || ''}`,
        getSelected: () => __vehReportSelected.weapons,
        addSelected: (it) => {
            __vehReportSelected.weapons.push({ id: it.id, label: it.label });
        },
        removeSelected: (id) => {
            __vehReportSelected.weapons = __vehReportSelected.weapons.filter(x => String(x.id) !== String(id));
        }
    });
}

function openVehicleReportModal() {
    const modal = document.getElementById('vehicleReportModal');
    if (!modal) return;

    __vehReportEnsureLinkedPickersWired();
    __vehReportLoadLinkedCatalogs();

    const vehicleName = currentVehicleInfo?.name || 'Vehicle';
    const plate = currentVehicleInfo?.plate || 'UNKNOWN';

    const reportIdInput = document.getElementById('vehReportId');
    if (reportIdInput) reportIdInput.value = generateReportId();

    const vehicleInput = document.getElementById('vehReportVehicle');
    if (vehicleInput) vehicleInput.value = `${vehicleName} (${plate})`;

    const typeInput = document.getElementById('vehReportIncidentType');
    if (typeInput) typeInput.value = '';
    
    const customTypeInput = document.getElementById('vehReportCustomIncidentType');
    if (customTypeInput) customTypeInput.value = '';
    
    const customRow = document.getElementById('customIncidentTypeRow');
    if (customRow) customRow.style.display = 'none';

    // Initialize RTEs for vehicle report
    if (!window.__rteVehReportNarrative) {
        window.__rteVehReportNarrative = createRTE('vehReportNarrative', {
            placeholder: 'Summarize the incident...',
            minHeight: '100px',
            maxHeight: '30vh'
        });
    } else {
        window.__rteVehReportNarrative.clear();
    }
    
    if (!window.__rteVehReportTow) {
        window.__rteVehReportTow = createRTE('vehReportTow', {
            placeholder: 'Tow company, yard, fees...',
            minHeight: '80px',
            maxHeight: '30vh'
        });
    } else {
        window.__rteVehReportTow.clear();
    }
    
    if (!window.__rteVehReportRecovery) {
        window.__rteVehReportRecovery = createRTE('vehReportRecovery', {
            placeholder: 'Recovered, pending, released...',
            minHeight: '80px',
            maxHeight: '30vh'
        });
    } else {
        window.__rteVehReportRecovery.clear();
    }

    ['vehReportLinkedCitizens','vehReportLinkedWeapons','vehReportLinkedIncidents','vehReportEvidence'].forEach(id => {
        const el = document.getElementById(id);
        if (el) el.value = '';
    });

    __vehReportResetLinkedPickers();

    const dtInput = document.getElementById('vehReportDateTime');
    if (dtInput) {
        const now = new Date();
        const isoLocal = new Date(now.getTime() - now.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
        dtInput.value = isoLocal;
        // Only high ranks (2-4) can manually edit date/time
        dtInput.readOnly = !canEditReports();
    }

    const locInput = document.getElementById('vehReportLocation');
    if (locInput) {
        locInput.value = 'Fetching location...';
        // Only high ranks (2-4) can manually edit location
        locInput.readOnly = !canEditReports();
        sendCallback('getPlayerLocation', { for: 'report' });
    }

    const officerInput = document.getElementById('vehReportOfficer');
    if (officerInput) officerInput.value = formatOfficerLabel();

    modal.classList.remove('hidden');
}

function closeVehicleReportModal() {
    const modal = document.getElementById('vehicleReportModal');
    if (modal) modal.classList.add('hidden');
}

function submitVehicleReport() {
    // Get incident type - use custom if selected
    let type = (document.getElementById('vehReportIncidentType')?.value || '').trim();
    if (type === 'custom') {
        type = (document.getElementById('vehReportCustomIncidentType')?.value || '').trim();
    }
    if (!type || type === '') type = 'N/A';
    
    // Get narrative from RTE if available, fallback to text input
    let narrative = '';
    if (window.__rteVehReportNarrative) {
        narrative = window.__rteVehReportNarrative.getPlainText().trim();
    } else if (window.__mdtRTEManager) {
        narrative = window.__mdtRTEManager.getPlainText('vehReportNarrative').trim();
    } else {
        narrative = (document.getElementById('vehReportNarrative')?.textContent || '').trim();
    }

    if (!narrative || narrative === 'N/A') {
        mdtToastSafe('Narrative summary is required', 'error');
        return;
    }

    const reportId = (document.getElementById('vehReportId')?.value || '').trim();
    const dateVal = document.getElementById('vehReportDateTime')?.value;
    const timestampIso = dateVal ? new Date(dateVal).toISOString() : new Date().toISOString();
    const plate = currentVehicleInfo?.plate || 'UNKNOWN';
    const vehicleName = currentVehicleInfo?.name || 'Vehicle';
    const officer = (document.getElementById('vehReportOfficer')?.value || formatOfficerLabel()).trim() || 'N/A';
    const location = (document.getElementById('vehReportLocation')?.value || '').trim() || 'N/A';

    const linkedCitizens = parseListValue('vehReportLinkedCitizens');
    const linkedWeapons = parseListValue('vehReportLinkedWeapons');
    const linkedIncidents = parseListValue('vehReportLinkedIncidents');
    const linkedEvidence = parseListValue('vehReportEvidence');
    
    // Get tow and recovery from RTE if available, fallback to textarea values
    let towImpound = 'N/A';
    let recoveryStatus = 'N/A';
    if (window.__rteVehReportTow) {
        const tow = window.__rteVehReportTow.getPlainText().trim();
        towImpound = tow || 'N/A';
    } else if (window.__mdtRTEManager) {
        const tow = window.__mdtRTEManager.getPlainText('vehReportTow').trim();
        towImpound = tow || 'N/A';
    } else {
        towImpound = (document.getElementById('vehReportTow')?.textContent || '').trim() || 'N/A';
    }
    
    if (window.__rteVehReportRecovery) {
        const recovery = window.__rteVehReportRecovery.getPlainText().trim();
        recoveryStatus = recovery || 'N/A';
    } else if (window.__mdtRTEManager) {
        const recovery = window.__mdtRTEManager.getPlainText('vehReportRecovery').trim();
        recoveryStatus = recovery || 'N/A';
    } else {
        recoveryStatus = (document.getElementById('vehReportRecovery')?.textContent || '').trim() || 'N/A';
    }

    const contentLines = [
        `Vehicle: ${vehicleName} (${plate})`,
        `Incident Type: ${type}`,
        `Location: ${location}`,
        `Primary Officer: ${officer}`,
        `Date/Time: ${timestampIso}`,
        linkedCitizens.length ? `Linked Citizens: ${linkedCitizens.join(', ')}` : 'Linked Citizens: N/A',
        linkedWeapons.length ? `Linked Weapons: ${linkedWeapons.join(', ')}` : 'Linked Weapons: N/A',
        linkedIncidents.length ? `Linked Incidents: ${linkedIncidents.join(', ')}` : 'Linked Incidents: N/A',
        linkedEvidence.length ? `Evidence: ${linkedEvidence.join(', ')}` : 'Evidence: N/A',
        `Tow/Impound: ${towImpound}`,
        `Recovery Status: ${recoveryStatus}`,
        `Narrative: ${narrative}`
    ];

    const payload = {
        reportId,
        type,
        category: 'Vehicle Report',
        title: `${type} - ${plate}`,
        officer,
        location,
        narrative,
        content: contentLines.join('\n'),
        timestamp: timestampIso,
        vehiclePlate: plate,
        vehicleName,
        linkedCitizens,
        linkedWeapons,
        linkedIncidents,
        linkedEvidence,
        towImpound,
        recoveryStatus
    };

    sendCallback('newReport', payload, (response) => {
        if (response && response.success) {
            closeVehicleReportModal();
            setTimeout(() => {
                if (plate) sendCallback('openVehicle', { plate });
            }, 800);
        } else {
            mdtToastSafe('Failed to create report', 'error');
        }
    });
}

function setupVehicleReportModal() {
    const modal = document.getElementById('vehicleReportModal');
    if (!modal) return;

    __vehReportEnsureLinkedPickersWired();

    const closeBtn = document.getElementById('vehicleReportClose');
    const cancelBtn = document.getElementById('vehReportCancel');
    const submitBtn = document.getElementById('vehReportSubmit');

    if (closeBtn) closeBtn.onclick = closeVehicleReportModal;
    if (cancelBtn) cancelBtn.onclick = closeVehicleReportModal;
    if (submitBtn) submitBtn.onclick = submitVehicleReport;

    // Handle incident type dropdown showing custom input
    const incidentTypeSelect = document.getElementById('vehReportIncidentType');
    const customRow = document.getElementById('customIncidentTypeRow');
    if (incidentTypeSelect && customRow) {
        incidentTypeSelect.addEventListener('change', (e) => {
            if (e.target.value === 'custom') {
                customRow.style.display = 'flex';
                document.getElementById('vehReportCustomIncidentType')?.focus();
            } else {
                customRow.style.display = 'none';
                const customInput = document.getElementById('vehReportCustomIncidentType');
                if (customInput) customInput.value = '';
            }
        });
    }

    modal.addEventListener('click', (e) => {
        if (e.target === modal) closeVehicleReportModal();
    });
    const card = modal.querySelector('.modal-card');
    if (card) card.addEventListener('click', (e) => e.stopPropagation());
}

function setVehicleDetail(payload) {
    console.log('[MDT DEBUG] setVehicleDetail called with payload:', payload);
    const v = payload || {};
    const strikes = Array.isArray(v?.strikes) ? v.strikes : [];
    const activity = Array.isArray(v?.activity) ? v.activity : [];
    const reports = Array.isArray(v?.reports) ? v.reports : [];
    
    // NEVER default to "Vehicle" - show meaningful fallback
    const name = 
        (v.modelLabel && v.modelLabel !== 'NULL' && v.modelLabel.trim()) ? v.modelLabel :
        (v.model && String(v.model).trim()) ? v.model :
        (v.plate ? `Unknown Model (${v.plate})` : 'Unknown Vehicle');
    
    const brand = v.brand && v.brand.trim() ? v.brand : null;
    const displayName = brand ? `${brand} ${name}` : name;

    currentVehicleInfo = { plate: v.plate || null, name: displayName };
    
    console.log('[MDT DEBUG] Vehicle name resolved:', displayName, 'from brand:', v.brand, 'modelLabel:', v.modelLabel, 'model:', v.model);

    document.getElementById('vehTitle').textContent = displayName;
    document.getElementById('vehSummaryName').textContent = displayName;
    document.getElementById('vehPlatePill').textContent = `#${v.plate || 'UNKNOWN'}`;
    document.getElementById('vehPlateText').textContent = v.plate || 'UNKNOWN';
    document.getElementById('vehOwnerLine').textContent = `Owner: ${v.ownerName || 'Unknown'}`;
    document.getElementById('vehOwnerText').textContent = v.ownerName || 'Unknown';
    document.getElementById('vehLastSeenText').textContent = v.lastSeenAt ? formatDateTime(v.lastSeenAt) : 'Unknown';

    // Update vehicle photo display
    const vehIconCircle = document.getElementById('vehIconCircle');
    const vehIcon = document.getElementById('vehIcon');
    if (vehIconCircle && vehIcon) {
        if (v.vehiclePhoto) {
            vehIconCircle.style.backgroundImage = `url('${v.vehiclePhoto}')`;
            vehIcon.style.display = 'none';
        } else {
            vehIconCircle.style.backgroundImage = 'none';
            vehIcon.style.display = 'block';
        }
    }

    const statusText = String(v.status || 'clear').toUpperCase();
    const statusPill = document.getElementById('vehStatusPill');
    statusPill.textContent = statusText;
    statusPill.classList.remove('pillClear');
    statusPill.classList.add(getStatusPillClass(v.status));

    const flags = Array.isArray(v.flags) ? v.flags : [];
    currentVehicleFlag = String(flags[0] || '').trim();

    // Keep dropdown selection in sync if it exists
    const flagSelectEl = document.getElementById('vehFlagSelect');
    if (flagSelectEl) {
        const active = String(currentVehicleFlag || '').trim().toUpperCase();
        flagSelectEl.value = active;
        if (flagSelectEl.value !== active) flagSelectEl.value = '';
    }

    updateVehicleFlagUi();
    const statusDesc = document.getElementById('vehStatusDesc');
    if (!flags.length && String(v.status || '').toLowerCase() === 'clear') {
        statusDesc.textContent = 'This vehicle has no active alerts or flags.';
    } else {
        statusDesc.textContent = `Active Flags: ${flags.join(', ') || statusText}`;
    }

    const { points, activeCount, risk } = computeStrikeSummary(strikes);
    document.getElementById('vehTotalPoints').textContent = String(points);
    document.getElementById('vehActiveStrikes').textContent = String(activeCount);
    document.getElementById('vehRiskPill').textContent = risk;

        // Activity panel removed per request

        const reportsPanel = document.getElementById('vehReportList');
        if (reportsPanel) {
                if (!reports || !reports.length) {
                        reportsPanel.innerHTML = `<div style="padding: 20px; text-align: center; color: rgba(255,255,255,0.5);">📋 No reports found for this vehicle.</div>`;
                        allReportsCache = []; // Clear cache when no reports
                } else {
                        // Update cache for report details
                        allReportsCache = reports.slice();
                        
                        const approved = reports.filter(r => String(r.approvalStatus || r.status || 'Pending').toLowerCase() === 'approved').length;
                        const pending = reports.filter(r => String(r.approvalStatus || r.status || 'Pending').toLowerCase() === 'pending').length;
            
                        const sorted = reports.slice().sort((a, b) => {
                                const da = new Date(a.timestamp || a.createdAt || 0).getTime();
                                const db = new Date(b.timestamp || b.createdAt || 0).getTime();
                                return db - da;
                        });
            
                        let html = `
                            <div class="vehStrikeSummary" style="margin-bottom: 16px;">
                                <div class="card miniCard">
                                    <div class="miniLabel">Total Reports</div>
                                    <div class="miniValue">${reports.length}</div>
                                    <div class="miniIcon">📋</div>
                                </div>
                
                                <div class="card miniCard" style="background: rgba(34,197,94,0.1);">
                                    <div class="miniLabel">Approved</div>
                                    <div class="miniValue" style="color: #22c55e;">${approved}</div>
                                    <div class="miniIcon">✓</div>
                                </div>
                
                                <div class="card miniCard" style="background: rgba(168,85,247,0.1);">
                                    <div class="miniLabel">Pending Review</div>
                                    <div class="miniValue" style="color: #a855f7;">${pending}</div>
                                    <div class="miniIcon">⏳</div>
                                </div>
                            </div>
              
                            <div class="vehSubTitle" style="margin-bottom: 12px;">
                                <span class="clockIcon">📑</span>
                                Report History
                            </div>
              
                            <div class="vehReportList">
                                ${sorted.map(renderReportCard).join('')}
                            </div>
                        `;
            
                        reportsPanel.innerHTML = html;
                }
        }

    // Strikes Tab
    const strikesList = document.getElementById('vehStrikeList');
    if (strikesList) {
        if (!strikes.length) {
            strikesList.innerHTML = `<div class="muted">No strikes found for this vehicle.</div>`;
        } else {
            const sorted = strikes.slice().sort((a, b) => {
                const da = new Date(a.createdAt || 0).getTime();
                const db = new Date(b.createdAt || 0).getTime();
                return db - da;
            });
            strikesList.innerHTML = sorted.map(renderStrikeCard).join('');
        }
    }

    // Add Strike Button
    const addBtn = document.getElementById('vehAddStrikeBtn');
    if (addBtn) {
        addBtn.onclick = () => {
            openAddStrikeModal(v.plate, displayName);
        };
    }

    const newReportBtn = document.getElementById('vehNewReportBtn');
    if (newReportBtn) {
        newReportBtn.onclick = () => {
            openVehicleReportModal();
        };
    }

    // Strike Close Buttons - REMOVED (strikes only expire, cannot be manually deleted)
}

// Hook NUI message to open the modal
window.addEventListener('message', (event) => {
    const msg = event.data;
    if (!msg || typeof msg !== 'object') return;
    if (msg.action === 'setVehicleProfile') {
        console.log('[MDT DEBUG] Received setVehicleProfile in first listener:', msg);
        const payload = msg.payload || {};
        if (!payload) {
            console.error('[MDT ERROR] No payload in setVehicleProfile message!');
            return;
        }
        console.log('[MDT DEBUG] Calling openVehicleDetail with payload:', payload);
        openVehicleDetail(payload);
    }
});

// ============================================================================
// Add Strike Modal
// ============================================================================

let currentStrikePlate = null;
let currentStrikeVehicle = null;

function openAddStrikeModal(plate, vehicleName) {
    currentStrikePlate = plate;
    currentStrikeVehicle = vehicleName;
    
    const modal = document.getElementById('addStrikeModal');
    if (!modal) return;
    
    // Reset form
    document.getElementById('strikeTitle').value = '';
    document.getElementById('strikeOffense').value = '';
    
    // Initialize/reset RTE for description
    if (!window.__rteStrikeDescription) {
        window.__rteStrikeDescription = createRTE('strikeDescription', {
            placeholder: 'Describe the incident...',
            minHeight: '100px',
            maxHeight: '40vh'
        });
    } else {
        window.__rteStrikeDescription.clear();
    }
    document.getElementById('strikeExpiry').value = '60';
    document.getElementById('strikePointsDisplay').textContent = '';
    
    // Set vehicle info
    document.getElementById('strikeModalVehicle').textContent = `${vehicleName} (${plate})`;
    
    // Set officer
    document.getElementById('strikeOfficer').textContent = userInfo?.name || 'Officer';
    
    // Set current date/time
    const now = new Date();
    document.getElementById('strikeDateTime').textContent = now.toLocaleString();
    
    // Request location from backend
    sendCallback('getPlayerLocation', {});
    document.getElementById('strikeLocation').textContent = 'Fetching location...';
    
    modal.classList.remove('hidden');
}

function closeAddStrikeModal() {
    const modal = document.getElementById('addStrikeModal');
    if (modal) modal.classList.add('hidden');
    currentStrikePlate = null;
    currentStrikeVehicle = null;
}

function setupAddStrikeModal() {
    const modal = document.getElementById('addStrikeModal');
    const closeBtn = document.getElementById('addStrikeModalClose');
    const cancelBtn = document.getElementById('addStrikeCancel');
    const submitBtn = document.getElementById('addStrikeSubmit');
    const offenseSelect = document.getElementById('strikeOffense');
    
    if (closeBtn) closeBtn.onclick = closeAddStrikeModal;
    if (cancelBtn) cancelBtn.onclick = closeAddStrikeModal;
    
    // Update points display when offense selected
    if (offenseSelect) {
        offenseSelect.onchange = (e) => {
            const value = e.target.value;
            if (!value) {
                document.getElementById('strikePointsDisplay').textContent = '';
                return;
            }
            const points = value.split(':')[1];
            document.getElementById('strikePointsDisplay').textContent = `This offense will add ${points} points to the vehicle's record.`;
        };
    }
    
    if (submitBtn) {
        submitBtn.onclick = () => {
            const title = document.getElementById('strikeTitle').value.trim();
            const offense = document.getElementById('strikeOffense').value;
            // Get description from RTE if available, fallback to textarea value
            let description = '';
            if (window.__mdtRTEManager) {
                description = window.__mdtRTEManager.getPlainText('strikeDescription').trim();
            } else {
                description = document.getElementById('strikeDescription').value.trim();
            }
            const expiry = parseInt(document.getElementById('strikeExpiry').value);
            const officer = document.getElementById('strikeOfficer').textContent;
            const location = document.getElementById('strikeLocation').textContent;
            
            if (!title) {
                mdtToastSafe('Please enter a strike title', 'error');
                return;
            }
            if (!offense) {
                mdtToastSafe('Please select an offense category', 'error');
                return;
            }
            
            const [offenseType, points] = offense.split(':');
            
            const strikeData = {
                plate: currentStrikePlate,
                title,
                offenseType,
                points: parseInt(points),
                description,
                officer,
                location,
                expiryDays: expiry
            };
            
            sendCallback('addVehicleStrike', strikeData);
            closeAddStrikeModal();
            
            // Refresh vehicle detail after a short delay
            setTimeout(() => {
                sendCallback('openVehicle', { plate: currentStrikePlate });
            }, 300);
        };
    }
    
    // Close on backdrop click
    if (modal) {
        modal.onclick = (e) => {
            if (e.target === modal) closeAddStrikeModal();
        };
        // Prevent modal content clicks from closing
        const modalCard = modal.querySelector('.modal-card');
        if (modalCard) modalCard.onclick = (e) => e.stopPropagation();
    }
}

// Store current vehicle plate for auto-refresh
let currentVehiclePlate = null;

// Handle location response from backend
window.addEventListener('message', (event) => {
    const msg = event.data;
    if (!msg || typeof msg !== 'object') return;
    
    if (msg.action === 'setPlayerLocation') {
        const locationEl = document.getElementById('strikeLocation');
        if (locationEl && msg.location) {
            locationEl.textContent = msg.location;
        }

        const reportLocInput = document.getElementById('vehReportLocation');
        if (reportLocInput && msg.location) {
            reportLocInput.value = msg.location;
        }
    }
    
    if (msg.action === 'setVehicleProfile') {
        console.log('[MDT DEBUG] Received setVehicleProfile:', msg);
        const payload = msg.payload || {};
        if (!payload) return;
        currentVehiclePlate = payload.plate;
        openVehicleDetail(payload);
    }
    
    if (msg.action === 'vehicleStrikeAdded') {
        // Auto-refresh if this vehicle is currently open
        const modal = document.getElementById('vehicleDetailModal');
        if (modal && !modal.classList.contains('hidden') && msg.plate === currentVehiclePlate) {
            console.log('[MDT] Auto-refreshing vehicle detail for plate:', msg.plate);
            sendCallback('openVehicle', { plate: msg.plate });
        }
    }
});

document.addEventListener('DOMContentLoaded', () => {
    setupVehicleDetailModal();
    setupAddStrikeModal();
    setupVehicleReportModal();
    console.log('MDT loaded - vehicle detail modal ready');
});
