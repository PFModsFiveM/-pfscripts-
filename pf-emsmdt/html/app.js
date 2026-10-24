// ============================================================================
// EMS MDT - Clean Build
// ============================================================================

// Global State
let router = null;
let mapConfig = null;
let userPermissions = { allowed: false, isSupervisor: false };
let prioritiesConfig = {};
let statusesConfig = {};
let userInfo = { name: "Medic", rank: "EMS", callsign: "", rankLevel: 0 };
let currentVehicleInfo = { plate: null, name: null };
let mdtConfig = {};
let localeStrings = {};
let currentLocale = 'en';

let __mdtPreloadedMapSrc = null;
let __mdtPreloadPromise = null;

// Keep the latest dispatch payloads even when Dispatch page isn't active.
// This allows instant navigation to Dispatch without waiting for a new push.
let __mdtLastDispatchCalls = null;
let __mdtLastDispatchUnits = null;

let __mdtDispatchWarmed = false;

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
    setTextContent('#tabletTitleLabel', 'tablet_title', 'EMS MDT');

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
        citizens: 'nav_citizens',
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
        if (nameInput) nameInput.setAttribute('placeholder', t('profile_name_placeholder', 'Medic Name'));
        const callsignInput = document.getElementById('profileCallsignInput');
        if (callsignInput) callsignInput.setAttribute('placeholder', t('profile_callsign_placeholder', 'e.g. 3A-12'));
    } catch (_) {}

    // Generic i18n attributes (static HTML + any pages that set them)
    applyLocaleDataAttributes(document);
}

// Lightweight caches so returning to Dashboard can re-render immediately
let dashboardCache = null;           // { bulletins, reports, ... }
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
            const name = m?.name ?? 'Medic';
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
    return 'pf-emsmdt';
}

async function sendCallback(action, data, callback, options) {
    const resName = getResourceName();
    const url = `https://${resName}/${action}`;
    console.log('[MDT SEND CALLBACK]', action, data, 'url:', url);
    try {
        const controller = new AbortController();
        const timeoutMs = (options && typeof options.timeoutMs === 'number') ? options.timeoutMs : 7000;
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
        console.error('[MDT CALLBACK ERROR]', action, err);
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

// ============================================================================
// Patient Profile Modal (EMS-only)
// Renders the Overview / Medical / Notes tabs for the #citizenProfileModal.
// ============================================================================

function __emsSetPatientTab(modal, tabId) {
    if (!modal) return;
    modal.querySelectorAll('.tab').forEach((t) => t.classList.toggle('active', t.dataset.tab === tabId));
    const content = modal.querySelector('#citizenProfileContent');
    if (!content) return;
    content.querySelectorAll('[data-view]').forEach((v) => {
        v.style.display = (v.dataset.view === tabId ? 'block' : 'none');
    });
}

function __emsWirePatientTabsOnce(modal) {
    if (!modal || modal.dataset.emsTabsWired === '1') return;
    modal.dataset.emsTabsWired = '1';
    modal.querySelectorAll('.tab').forEach((btn) => {
        btn.addEventListener('click', () => __emsSetPatientTab(modal, btn.dataset.tab));
    });
}

function __emsNormStr(v) {
    const s = String(v ?? '').trim();
    return s.length ? s : '';
}

function __emsGetProfileField(profile, keys) {
    for (const k of keys) {
        const parts = String(k).split('.');
        let cur = profile;
        let ok = true;
        for (const p of parts) {
            if (!cur || typeof cur !== 'object' || !(p in cur)) { ok = false; break; }
            cur = cur[p];
        }
        if (ok) {
            const v = __emsNormStr(cur);
            if (v) return v;
        }
    }
    return '';
}

function __emsRenderPatientProfile(profile) {
    const modal = document.getElementById('citizenProfileModal');
    if (!modal) return;
    modal.classList.remove('hidden');

    __emsWirePatientTabsOnce(modal);

    const citizenId = __emsGetProfileField(profile, ['citizenId', 'citizenid', 'id']);
    const firstName = __emsGetProfileField(profile, ['firstname', 'firstName', 'charinfo.firstname']);
    const lastName = __emsGetProfileField(profile, ['lastname', 'lastName', 'charinfo.lastname']);
    const name = __emsGetProfileField(profile, ['name']) || [firstName, lastName].filter(Boolean).join(' ') || 'Patient Profile';
    const dob = __emsGetProfileField(profile, ['dob', 'birthdate', 'charinfo.birthdate']);
    const phone = __emsGetProfileField(profile, ['phone', 'charinfo.phone', 'charinfo.phone_number']);
    const gender = __emsGetProfileField(profile, ['gender', 'sex']);
    const job = __emsGetProfileField(profile, ['jobLabel', 'job', 'job.name']);
    const address = __emsGetProfileField(profile, ['address']);

    const notesArr = Array.isArray(profile.notes) ? profile.notes : [];

    const medical = (profile && typeof profile.medical === 'object' && profile.medical) ? profile.medical : {};
    const allergies = Array.isArray(medical.allergies) ? medical.allergies : (Array.isArray(profile.allergies) ? profile.allergies : []);
    const conditions = Array.isArray(medical.conditions) ? medical.conditions : (Array.isArray(profile.conditions) ? profile.conditions : []);
    const medications = Array.isArray(medical.medications) ? medical.medications : (Array.isArray(profile.medications) ? profile.medications : []);
    const bloodType = __emsNormStr(medical.bloodType || profile.bloodType || profile.bloodtype);
    const injuries = Array.isArray(medical.injuries) ? medical.injuries : (Array.isArray(profile.injuries) ? profile.injuries : []);

    const nameEl = document.getElementById('citizenProfileName');
    if (nameEl) nameEl.textContent = name || 'Patient Profile';

    const identityHeader = document.getElementById('citizenIdentityHeader');
    if (identityHeader) {
        identityHeader.innerHTML = `
            <div class="citizen-header">
                <div class="citizen-header-main" style="margin-left:0;">
                    <div class="citizen-name-row">
                        <div class="citizen-name">${escapeHtml(name || 'Unknown')}</div>
                        ${citizenId ? `<span class="citizen-id-pill">${escapeHtml(citizenId)}</span>` : ''}
                    </div>
                    <div class="citizen-kv-grid">
                        <div class="citizen-kv"><span class="citizen-k">DOB</span><span class="citizen-v">${escapeHtml(dob || 'N/A')}</span></div>
                        <div class="citizen-kv"><span class="citizen-k">Gender</span><span class="citizen-v">${escapeHtml(gender || 'N/A')}</span></div>
                        <div class="citizen-kv"><span class="citizen-k">Phone</span><span class="citizen-v">${escapeHtml(phone || 'N/A')}</span></div>
                        <div class="citizen-kv"><span class="citizen-k">Job</span><span class="citizen-v">${escapeHtml(job || 'N/A')}</span></div>
                        <div class="citizen-kv" style="grid-column: 1 / -1;"><span class="citizen-k">Address</span><span class="citizen-v">${escapeHtml(address || 'N/A')}</span></div>
                    </div>
                </div>
            </div>
        `;
    }

    const summaryBar = document.getElementById('citizenSummaryBar');
    if (summaryBar) {
        summaryBar.innerHTML = `
            <div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px;">
                <div class="summary-card"><div class="summary-value">${allergies.length}</div><div class="summary-label">Allergies</div></div>
                <div class="summary-card"><div class="summary-value">${conditions.length}</div><div class="summary-label">Conditions</div></div>
                <div class="summary-card"><div class="summary-value">${medications.length}</div><div class="summary-label">Medications</div></div>
                <div class="summary-card"><div class="summary-value">${notesArr.length}</div><div class="summary-label">Notes</div></div>
            </div>
        `;
    }

    const content = document.getElementById('citizenProfileContent');
    if (!content) return;

    const listOrEmpty = (arr, emptyLabel) => {
        const items = (Array.isArray(arr) ? arr : []).map((x) => escapeHtml(String(x ?? '').trim())).filter(Boolean);
        if (!items.length) return `<div class="empty-message">${escapeHtml(emptyLabel)}</div>`;
        return `<div style="display:flex; gap:6px; flex-wrap:wrap;">${items.map(i => `<span class=\"flag-chip\">${i}</span>`).join('')}</div>`;
    };

    const notesHtml = notesArr.length
        ? notesArr.map((n) => {
            const text = escapeHtml(String(n.text ?? n.note ?? ''));
            const meta = [n.author, n.createdAt].filter(Boolean).map((x) => escapeHtml(String(x))).join(' • ');
            return `<div class="note-row"><div>${text}</div><div style="font-size:11px;color:rgba(255,255,255,0.6)">${meta}</div></div>`;
        }).join('')
        : '<div class="empty-message">No notes</div>';

    content.innerHTML = `
        <div data-view="c-overview">
            <h4 style="margin-bottom: 12px;">Patient Overview</h4>
            <div style="display: grid; grid-template-columns: repeat(2, 1fr); gap: 12px;">
                <div class="info-row"><span class="label">Name:</span> <span>${escapeHtml(name || 'N/A')}</span></div>
                <div class="info-row"><span class="label">Patient ID:</span> <span>${escapeHtml(citizenId || 'N/A')}</span></div>
                <div class="info-row"><span class="label">DOB:</span> <span>${escapeHtml(dob || 'N/A')}</span></div>
                <div class="info-row"><span class="label">Phone:</span> <span>${escapeHtml(phone || 'N/A')}</span></div>
                <div class="info-row"><span class="label">Gender:</span> <span>${escapeHtml(gender || 'N/A')}</span></div>
                <div class="info-row"><span class="label">Job:</span> <span>${escapeHtml(job || 'N/A')}</span></div>
                <div class="info-row" style="grid-column: 1 / -1;"><span class="label">Address:</span> <span>${escapeHtml(address || 'N/A')}</span></div>
            </div>
        </div>

        <div data-view="c-medical" style="display:none;">
            <h4 style="margin-bottom: 12px;">Medical</h4>
            <div style="display:grid; grid-template-columns: repeat(2, 1fr); gap: 12px; margin-bottom: 16px;">
                <div class="info-row"><span class="label">Blood Type:</span> <span>${escapeHtml(bloodType || 'Not recorded')}</span></div>
                <div class="info-row"><span class="label">Injuries:</span> <span>${injuries.length ? escapeHtml(String(injuries.length)) : 'None listed'}</span></div>
            </div>

            <div style="margin-bottom: 16px;">
                <h4 style="margin-bottom: 10px; font-size: 14px;">Allergies</h4>
                ${listOrEmpty(allergies, 'No allergies listed')}
            </div>

            <div style="margin-bottom: 16px;">
                <h4 style="margin-bottom: 10px; font-size: 14px;">Conditions</h4>
                ${listOrEmpty(conditions, 'No conditions listed')}
            </div>

            <div style="margin-bottom: 16px;">
                <h4 style="margin-bottom: 10px; font-size: 14px;">Medications</h4>
                ${listOrEmpty(medications, 'No medications listed')}
            </div>

            <div style="margin-bottom: 6px;">
                <h4 style="margin-bottom: 10px; font-size: 14px;">Injury Notes</h4>
                ${injuries.length ? `<div style=\"display:flex; gap:6px; flex-wrap:wrap;\">${injuries.map(i => `<span class=\\\"flag-chip\\\">${escapeHtml(String(i))}</span>`).join('')}</div>` : '<div class="empty-message">No injuries listed</div>'}
            </div>
        </div>

        <div data-view="c-notes" style="display:none;">
            <h4 style="margin-bottom: 12px;">Notes</h4>
            <div style="margin-bottom: 12px;">${notesHtml}</div>
            <div style="display:flex; gap:10px; align-items:flex-end;">
                <div style="flex:1;">
                    <div style="font-size: 12px; color: rgba(255,255,255,0.7); margin-bottom: 6px;">Add note</div>
                    <textarea id="patientNoteText" placeholder="Add a patient note..."></textarea>
                </div>
                <button id="patientNoteAddBtn" class="btn primary" type="button">Add</button>
            </div>
        </div>
    `;

    const addBtn = document.getElementById('patientNoteAddBtn');
    const noteText = document.getElementById('patientNoteText');
    if (addBtn && noteText && citizenId) {
        addBtn.onclick = () => {
            const text = String(noteText.value || '').trim();
            if (!text) return;
            addBtn.disabled = true;
            sendCallback('addPatientNote', { citizenId, text }, () => {
                noteText.value = '';
                addBtn.disabled = false;
                setTimeout(() => sendCallback('openCitizen', { citizenId }), 150);
            });
        };
    }

    __emsSetPatientTab(modal, 'c-overview');
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
    const name = userInfo?.name || 'Medic';
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
    mount(root) { this.root = root; }
    unmount() { if (this.root) this.root.innerHTML = ''; this.root = null; }
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
        // EMS MDT: only Patients search is enabled
        this.searchAllowed = new Set(['citizens']);
    }

    register(name, page, title) {
        this.pages.set(name, page);
        if (title) this.titles.set(name, title);
    }

    set(name) {
        if (!this.pages.has(name)) return;
        if (this.current && this.pages.get(this.current)) { 
            try { this.pages.get(this.current).unmount(); } catch (_) {}
        }
        this.current = name;
        const page = this.pages.get(name);
        page.mount(this.root);
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
                                <button class="emoji-item" type="button">🚑</button>
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
                        <textarea id="bulletinBodyInput" class="chat-input" maxlength="4000" placeholder="${t('bulletin_description', 'Description')}" style="min-height:90px; resize:vertical;"></textarea>
                        <div style="display:flex; gap:8px; justify-content:flex-end;">
                            <button id="bulletinCancelBtn" class="btn" type="button">${t('common_cancel', 'Cancel')}</button>
                            <button id="bulletinSubmitBtn" class="btn primary" type="button">${t('common_save', 'Save')}</button>
                        </div>
                    </div>
                    <div class="bulletin-list" id="dashBulletins">
                        <div class="empty-message">${t('bulletin_empty', 'No bulletins')}</div>
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
            }
        });

        cancelBtn?.addEventListener('click', () => {
            if (!form) return;
            form.classList.add('hidden');
            if (titleInput) titleInput.value = '';
            if (bodyInput) bodyInput.value = '';
        });

        submitBtn?.addEventListener('click', () => {
            if (!canCreateBulletins()) return;
            const title = (titleInput?.value || '').trim();
            const body = (bodyInput?.value || '').trim();
            if (!title || !body) return;
            sendCallback('createBulletin', { title, body }, (res) => {
                if (res && res.success) {
                    if (titleInput) titleInput.value = '';
                    if (bodyInput) bodyInput.value = '';
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
                        const rank = escapeHtml(rankRaw || t('common_officer', 'Medic'));

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
        }
        if (data.action === 'chatMessage') {
            try {
                dashboardChatCache.push({ name: data.name || 'Medic', message: data.message || '' });
                if (dashboardChatCache.length > 200) dashboardChatCache = dashboardChatCache.slice(-200);
            } catch (_) {}
            this.addChatMessage(data.name || 'Medic', data.message || '', false);
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
// Patients (Citizens) Page (EMS)
// ============================================================================

class CitizenSearchPage extends BasePage {
    constructor() {
        super('citizens', 'Patients');
        this.page = 1;
        this.pageSize = 9;
        this.totalCount = 0;
        this.query = '';
        this.citizens = [];
    }

    mount(root) {
        super.mount(root);

        root.innerHTML = `
            <div class="search-page-container">
                <div class="search-page-header">
                    <div class="search-page-title-group">
                        <h2>${t('page_citizens', 'Patients')}</h2>
                        <div class="search-page-subtitle">${t('patients_search_hint', 'Search by name, phone, or citizen ID')}</div>
                    </div>
                </div>

                <div class="search-page-controls">
                    <input id="citizensSearchInput" class="search-page-input" type="text" placeholder="${t('search_placeholder', 'Search...')}" maxlength="64" />
                    <button id="citizensSearchBtn" class="page-action-btn" type="button">${t('common_search', 'Search')}</button>
                </div>

                <div id="citizensResults" class="results-grid"></div>

                <div class="pagination-footer">
                    <div id="citizensCount" class="search-page-subtitle"></div>
                    <div class="pagination-buttons">
                        <button id="citizensPrevBtn" class="pagination-btn" type="button">${t('common_prev', 'Prev')}</button>
                        <button id="citizensNextBtn" class="pagination-btn" type="button">${t('common_next', 'Next')}</button>
                    </div>
                </div>
            </div>
        `;

        const input = document.getElementById('citizensSearchInput');
        const btn = document.getElementById('citizensSearchBtn');
        const prevBtn = document.getElementById('citizensPrevBtn');
        const nextBtn = document.getElementById('citizensNextBtn');

        if (input) {
            input.value = this.query || '';
            input.addEventListener('keydown', (e) => {
                if (e.key !== 'Enter') return;
                this.page = 1;
                this.query = String(input.value || '').trim();
                this.search();
            });
        }

        btn?.addEventListener('click', () => {
            this.page = 1;
            this.query = String(input?.value || '').trim();
            this.search();
        });

        prevBtn?.addEventListener('click', () => {
            if (this.page <= 1) return;
            this.page -= 1;
            this.search();
        });

        nextBtn?.addEventListener('click', () => {
            const maxPage = Math.max(1, Math.ceil((this.totalCount || 0) / this.pageSize));
            if (this.page >= maxPage) return;
            this.page += 1;
            this.search();
        });

        // Sync initial query from topbar search box (if present)
        try {
            const topbarInput = document.querySelector('.search-box input');
            if (topbarInput && String(topbarInput.value || '').trim()) {
                this.query = String(topbarInput.value || '').trim();
                if (input) input.value = this.query;
            }
        } catch (_) {}

        // Initial load
        this.search();
    }

    search() {
        sendCallback('searchPatients', { query: this.query || '', page: this.page, pageSize: this.pageSize }, (cb) => {
            if (!cb || cb.success !== true) {
                console.warn('[MDT] searchPatients failed:', cb?.error);
            }
        });
        // Results will be delivered via `setCitizens` message.
        this.render();
    }

    render() {
        const wrap = document.getElementById('citizensResults');
        const count = document.getElementById('citizensCount');
        const prevBtn = document.getElementById('citizensPrevBtn');
        const nextBtn = document.getElementById('citizensNextBtn');
        if (!wrap) return;

        const total = Number(this.totalCount || 0);
        const maxPage = Math.max(1, Math.ceil(total / this.pageSize));
        const start = total === 0 ? 0 : ((this.page - 1) * this.pageSize + 1);
        const end = Math.min(total, this.page * this.pageSize);

        if (count) {
            if (total === 0) count.textContent = t('patients_no_results', 'No results');
            else count.textContent = `${start}-${end} ${t('common_of', 'of')} ${total}`;
        }

        if (prevBtn) prevBtn.disabled = this.page <= 1;
        if (nextBtn) nextBtn.disabled = this.page >= maxPage;

        const list = Array.isArray(this.citizens) ? this.citizens : [];
        if (!list.length) {
            wrap.innerHTML = `<div class="empty-message">${escapeHtml(t('patients_no_results', 'No results'))}</div>`;
            return;
        }

        const initials = (name) => {
            const parts = String(name || '').trim().split(/\s+/).filter(Boolean);
            return parts.slice(0, 2).map(p => p[0]).join('').toUpperCase() || 'PT';
        };

        wrap.innerHTML = list.map((c) => {
            const citizenId = c?.citizenId || c?.citizenid || c?.id || '';
            const name = c?.name || 'Unknown';
            const dob = c?.dob || c?.birthdate || '';
            const phone = c?.phone || c?.phoneNumber || '';
            const init = initials(name);

            return `
                <div class="citizen-card" role="button" tabindex="0" data-citizenid="${escapeHtml(String(citizenId))}">
                    <div style="display:flex; gap:10px; align-items:center;">
                        <div class="card-avatar" aria-hidden="true">${escapeHtml(init)}</div>
                        <div style="display:flex; flex-direction:column; gap:2px;">
                            <div class="card-name">${escapeHtml(String(name))}</div>
                            <div class="card-id">${escapeHtml(String(citizenId || ''))}</div>
                        </div>
                    </div>
                    <div class="card-info-grid">
                        <div class="card-info-left">
                            <div class="info-row"><span class="label">DOB</span><span>${escapeHtml(String(dob || 'N/A'))}</span></div>
                        </div>
                        <div class="card-info-right">
                            <div class="info-row"><span class="label">Phone</span><span>${escapeHtml(String(phone || 'N/A'))}</span></div>
                        </div>
                    </div>
                </div>
            `;
        }).join('');

        // Click / keyboard open profile
        wrap.querySelectorAll('.citizen-card').forEach((card) => {
            const open = () => {
                const cid = card.getAttribute('data-citizenid');
                if (!cid) return;
                sendCallback('openCitizen', { citizenId: cid }, () => {});
            };
            card.addEventListener('click', open);
            card.addEventListener('keydown', (e) => {
                if (e.key === 'Enter' || e.key === ' ') {
                    e.preventDefault();
                    open();
                }
            });
        });
    }

    onMessage(data) {
        if (data.action !== 'setCitizens') return;
        this.citizens = Array.isArray(data.citizens) ? data.citizens : [];
        this.totalCount = Number(data.totalCount || 0);
        this.render();
    }

    // Used by topbar search box
    applyTopbarQuery(query) {
        this.query = String(query || '').trim();
        this.page = 1;
        const input = document.getElementById('citizensSearchInput');
        if (input) input.value = this.query;
        this.search();
    }
}

// Expose for router registration (handleOpen)
window.CitizenSearchPage = CitizenSearchPage;

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
        return `pf_emsmdt_dispatch_autoclear_${keyPart}`;
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
        if (acceptBtn) acceptBtn.onclick = () => { if (this.selectedCallId) sendCallback('acceptCall', { id: this.selectedCallId }); this.closeModal(); };

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
        const colorByStatus = { pending:'#F44336', accepted:'#2196F3', completed:'#757575' };
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
            const marker = L.marker(latLng, { icon: this.makeCallPinIcon(color, label) }).bindPopup(`<div>${call.title}</div>`);
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
        const descInput = document.getElementById('chargeDescriptionInput');
        const catInput = document.getElementById('chargeCategoryInput');
        const fineInput = document.getElementById('chargeFineInput');
        const bailInput = document.getElementById('chargeBailInput');
        const prisonInput = document.getElementById('chargePrisonInput');
        
        // Populate form fields
        if (idInput) idInput.value = charge ? charge.id : '';
        if (codeInput) codeInput.value = charge ? charge.code : '';
        if (nameInput) nameInput.value = charge ? charge.name : '';
        if (descInput) descInput.value = charge ? (charge.description || '') : '';
        if (catInput) catInput.value = charge ? charge.category : '';
        
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
        const descEl = document.getElementById('chargeDescriptionInput');
        const catEl = document.getElementById('chargeCategoryInput');
        const fineEl = document.getElementById('chargeFineInput');
        const bailEl = document.getElementById('chargeBailInput');
        const prisonEl = document.getElementById('chargePrisonInput');
        
        // Get text values
        const id = idEl ? idEl.value.trim() : '';
        const code = codeEl ? codeEl.value.trim() : '';
        const name = nameEl ? nameEl.value.trim() : '';
        const description = descEl ? descEl.value.trim() : '';
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

window.addEventListener('message', (event) => {
    const data = event.data;
    switch (data.action) {
        // EMS MDT: prison/jail custody timer UI is disabled
        case 'custodyTimer':
            break;
        case 'open': 
        case 'openTablet': handleOpen(data); break;
        case 'close':
        case 'closeTablet': handleClose(); break;
        case 'show': setMDTVisible(true); break;
        case 'hide': setMDTVisible(false); break;
        case 'setMDTVisible': setMDTVisible(data.visible !== false); break;
        case 'playDispatchDing':
            try { playDispatchDing(data); } catch (_) {}
            break;
        case 'setCalls':
            try { __mdtLastDispatchCalls = Array.isArray(data.calls) ? data.calls : (data.calls || null); } catch (_) {}
            if (router) router.message(data);
            break;
        case 'setUnits':
            try { __mdtLastDispatchUnits = Array.isArray(data.units) ? data.units : (data.units || null); } catch (_) {}
            if (router) router.message(data);
            break;
        case 'setCitizenProfile':
            try { __emsRenderPatientProfile(data.profile || {}); } catch (e) { console.error('[EMS MDT] Failed to render patient profile', e); }
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
        // Injury assessment (EMS specific)
        case 'displayInjuries':
        case 'displayInjuryAssessment':
            try {
                if (window.InjuryPanel && typeof window.InjuryPanel.displayInjuryAssessment === 'function') {
                    window.InjuryPanel.displayInjuryAssessment(data);
                } else {
                    console.error('[MDT] InjuryPanel not available');
                }
            } catch (e) {
                console.error('[MDT] Error displaying injury assessment:', e);
            }
            break;
        // Extended pages routing
        case 'setCitizens': if (router) router.message(data); break;
        case 'setVehicles': if (router) router.message(data); break;
        case 'setIncidents': if (router) router.message(data); break;
        case 'setReports': if (router) router.message(data); break;
        case 'setFTOReports': if (router) router.message(data); break;
        case 'setDashboard':
            try { dashboardCache = data.data || null; } catch (_) {}
            if (router) router.message(data);
            break;
        case 'bulletinCreated': {
            const b = data.bulletin;
            if (!b) break;
            try {
                dashboardCache = dashboardCache || { bulletins: [] };
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
    if (e.key !== 'Escape') return;
    try {
        sendCallback('close', {}, () => {});
    } catch (_) {}
}, true);

function setMDTVisible(visible) {
    const app = document.getElementById('app');
    if (!app) return;
    if (visible) app.classList.remove('hidden');
    else app.classList.add('hidden');
}

function deferPageUpgrade(routeName, globalClassName, title) {
    // In FiveM NUI, messages can arrive while the HTML is still loading.
    // If that happens, optional page scripts may not have run yet.
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
    const tabletFrame = document.getElementById('tabletFrame');
    const appDiv = document.getElementById('app');

    // Ensure NUI console logging matches Lua Config.Debug.
    try {
        const dbg = data && data.config && data.config.debug === true;
        if (typeof window.__mdtSetDebug === 'function') window.__mdtSetDebug(dbg);
    } catch (_) {}
    
    // Show both tablet frame and app
    if (tabletFrame) tabletFrame.classList.remove('hidden');
    appDiv.classList.remove('hidden');
    
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
        const contentRoot = document.getElementById('pageContent');
        router = new Router(contentRoot);
        router.register('dashboard', new DashboardPage(), t('page_dashboard', 'Dashboard'));
        router.register('dispatch', new DispatchPage(), t('page_dispatch', 'Dispatch'));
        // EMS MDT: only register EMS-relevant pages.
        const CitizensCls = window.CitizenSearchPage || null;
        const SOPCls = window.SOPPage || null;
        router.register('citizens', CitizensCls ? new CitizensCls() : new BasePage('citizens','Patients'), t('page_citizens', 'Patients'));
        const RosterCls = window.RosterPage || null;
        router.register('roster', RosterCls ? new RosterCls() : new BasePage('roster','Roster'), t('page_roster', 'Roster'));
        router.register('sop', SOPCls ? new SOPCls() : new BasePage('sop','SOP'), 'SOP');
        const OfficersCls = window.OfficersManagementPage || null;
        router.register('officers', OfficersCls ? new OfficersCls() : new BasePage('officers','Staff Management'), 'Staff Management');
        pruneNavToRegisteredPages();
        setupNavigationHandlers();
        router.set('dashboard');

        // Start warming Dispatch immediately after initial dashboard paint.
        // This makes the first switch to Dispatch instant.
        (window.requestAnimationFrame || window.setTimeout)(() => {
            try { __mdtWarmDispatchInBackground(); } catch (_) {}
        }, 0);
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
    appDiv.classList.add('hidden');
}

function updateUserInfo(info) {
    userInfo = Object.assign({}, userInfo, (info || {}));
    document.getElementById('userName').textContent = userInfo?.name || 'Medic';
    document.getElementById('userRank').textContent = userInfo?.grade || userInfo?.job || 'EMS';

    // Sidebar profile reflect
    const name = userInfo?.name || 'Medic';
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

function pruneNavToRegisteredPages() {
    try {
        if (!router || !router.pages) return;
        const keep = new Set(Array.from(router.pages.keys()));
        document.querySelectorAll('.nav-item').forEach((item) => {
            const page = item?.dataset?.page;
            if (!page) return;
            if (!keep.has(page)) item.remove();
        });
    } catch (_) {}
}

function setupNavigationHandlers() {
    document.querySelectorAll('.nav-item').forEach(item => {
        item.addEventListener('click', (e) => { e.preventDefault(); const page = item.dataset.page; if (page && router) router.set(page); });
    });
    document.getElementById('refreshBtn').addEventListener('click', () => sendCallback('refresh', {}));
    document.getElementById('closeBtn').addEventListener('click', () => sendCallback('close', {}));

    // Topbar search (only enabled on Patients page)
    try {
        const topSearch = document.querySelector('.search-box input');
        if (topSearch && !topSearch.dataset.mdtWired) {
            topSearch.dataset.mdtWired = '1';
            let debounceTimer = null;

            const run = () => {
                if (!router || router.current !== 'citizens') return;
                const page = router.pages?.get('citizens');
                if (page && typeof page.applyTopbarQuery === 'function') {
                    page.applyTopbarQuery(topSearch.value);
                }
            };

            topSearch.addEventListener('keydown', (e) => {
                if (e.key !== 'Enter') return;
                run();
            });
            topSearch.addEventListener('input', () => {
                if (!router || router.current !== 'citizens') return;
                clearTimeout(debounceTimer);
                debounceTimer = setTimeout(run, 250);
            });
        }
    } catch (_) {}

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
                        <div style="font-size: 12px; color: rgba(255,255,255,0.6);">Medic: ${escapeHtml(officer)}</div>
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
    const attachments = report.attachments || report.linkedAttachments || [];
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

    // Parse attachments if it's JSON string
    let attachmentList = [];
    if (typeof attachments === 'string') {
        try {
            attachmentList = JSON.parse(attachments);
        } catch {
            attachmentList = attachments.split(',').map(s => s.trim()).filter(Boolean);
        }
    } else if (Array.isArray(attachments)) {
        attachmentList = attachments;
    }
    attachmentList = (attachmentList || []).map(formatLabel);

    const modalHTML = `
        <div class="modal" id="reportDetailsModal" style="z-index: 10015;">
            <div class="modal-card" style="width: 700px; max-width: 90vw;">
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
                <div class="modal-body" style="max-height: 70vh; overflow-y: auto;">
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
                                <div style="font-size: 11px; color: rgba(255,255,255,0.5); margin-bottom: 4px;">MEDIC</div>
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

                        ${attachmentList.length > 0 ? `
                        <div style="margin-bottom: 16px;">
                            <div style="font-size: 11px; color: rgba(255,255,255,0.5); margin-bottom: 6px;">ATTACHMENTS</div>
                            <div style="display: flex; flex-wrap: wrap; gap: 6px;">
                                ${attachmentList.map(a => `<span style="font-size: 11px; padding: 4px 10px; border-radius: 6px; border: 1px solid rgba(255,193,7,0.3); background: rgba(255,193,7,0.1); color: #ffc107;">📎 ${escapeHtml(a)}</span>`).join('')}
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

function openVehicleReportModal() {
    const modal = document.getElementById('vehicleReportModal');
    if (!modal) return;

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

    const narrativeInput = document.getElementById('vehReportNarrative');
    if (narrativeInput) narrativeInput.value = '';

    ['vehReportLinkedPatients','vehReportLinkedItems','vehReportLinkedIncidents','vehReportAttachments','vehReportTow','vehReportRecovery'].forEach(id => {
        const el = document.getElementById(id);
        if (el) el.value = '';
    });

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
    
    const narrative = (document.getElementById('vehReportNarrative')?.value || '').trim();

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

    const linkedPatients = parseListValue('vehReportLinkedPatients');
    const linkedItems = parseListValue('vehReportLinkedItems');
    const linkedIncidents = parseListValue('vehReportLinkedIncidents');
    const attachments = parseListValue('vehReportAttachments');
    const towImpound = (document.getElementById('vehReportTow')?.value || '').trim() || 'N/A';
    const recoveryStatus = (document.getElementById('vehReportRecovery')?.value || '').trim() || 'N/A';

    const contentLines = [
        `Vehicle: ${vehicleName} (${plate})`,
        `Incident Type: ${type}`,
        `Location: ${location}`,
        `Primary Medic: ${officer}`,
        `Date/Time: ${timestampIso}`,
        linkedPatients.length ? `Linked Patients: ${linkedPatients.join(', ')}` : 'Linked Patients: N/A',
        linkedItems.length ? `Linked Items: ${linkedItems.join(', ')}` : 'Linked Items: N/A',
        linkedIncidents.length ? `Linked Incidents: ${linkedIncidents.join(', ')}` : 'Linked Incidents: N/A',
        attachments.length ? `Attachments: ${attachments.join(', ')}` : 'Attachments: N/A',
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
        linkedPatients,
        linkedItems,
        linkedIncidents,
        attachments,
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
    document.getElementById('strikeDescription').value = '';
    document.getElementById('strikeExpiry').value = '60';
    document.getElementById('strikePointsDisplay').textContent = '';
    
    // Set vehicle info
    document.getElementById('strikeModalVehicle').textContent = `${vehicleName} (${plate})`;
    
    // Set medic
    document.getElementById('strikeOfficer').textContent = userInfo?.name || 'Medic';
    
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
            const description = document.getElementById('strikeDescription').value.trim();
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
