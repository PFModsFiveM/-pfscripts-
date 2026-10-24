const state = {
    open: false,
    isAdmin: false,
    adminMode: false,
    visibleData: { categories: [] },
    adminData: null,
    selectedPageKey: null,
    searchQuery: '',
    adminFilter: '',
    adminTab: 'categories',
    collapsedCategories: {},
    activeEditor: null,
    jobModalResolver: null,
    gpsModalResolver: null,
    emojiModalResolver: null,
    savedEditorSelection: null,
    isClosing: false
};

const APP_CLOSE_ANIMATION_MS = 320;
let appCloseTimer = null;

const el = {
    app: null,
    categoryList: null,
    statCategories: null,
    statPages: null,
    searchInput: null,
    searchClear: null,
    searchBtn: null,
    sidebarAdmin: null,
    contentAdmin: null,
    contentClose: null,
    contentBack: null,
    contentTitle: null,
    contentSubtitle: null,
    contentBody: null,
    adminPanel: null,
    adminClose: null,
    adminTabCategories: null,
    adminTabPages: null,
    adminFilter: null,
    adminCount: null,
    adminCreate: null,
    adminSectionTitle: null,
    adminList: null,
    editorModal: null,
    editorTitle: null,
    editorBody: null,
    editorClose: null,
    jobModal: null,
    jobSelect: null,
    jobGradeSelect: null,
    jobClose: null,
    jobCancel: null,
    jobAdd: null,
    gpsModal: null,
    gpsLabel: null,
    gpsX: null,
    gpsY: null,
    gpsClose: null,
    gpsCancel: null,
    gpsAdd: null,
    emojiModal: null,
    emojiTitle: null,
    emojiSearch: null,
    emojiGrid: null,
    emojiClose: null,
    emojiCancel: null,
    toastStack: null
};

const toastTimers = [];

const EMOJI_LIBRARY = [
    { emoji: '📘', tags: 'book guide docs category' },
    { emoji: '📙', tags: 'book orange guide' },
    { emoji: '📗', tags: 'book green' },
    { emoji: '📕', tags: 'book red' },
    { emoji: '📚', tags: 'books stack library' },
    { emoji: '🧭', tags: 'compass navigation gps travel' },
    { emoji: '🗺️', tags: 'map city location' },
    { emoji: '🏙️', tags: 'city skyline downtown' },
    { emoji: '🏛️', tags: 'government law cityhall' },
    { emoji: '👮', tags: 'police law safety' },
    { emoji: '🚑', tags: 'ems ambulance health' },
    { emoji: '🔧', tags: 'mechanic repair tools' },
    { emoji: '🧰', tags: 'toolbox mechanic work' },
    { emoji: '🧹', tags: 'cleaning janitor' },
    { emoji: '🚛', tags: 'trucking transport' },
    { emoji: '💼', tags: 'jobs work office' },
    { emoji: '🏦', tags: 'bank finance money' },
    { emoji: '🛒', tags: 'store shopping market' },
    { emoji: '🍔', tags: 'restaurant food burger' },
    { emoji: '🏥', tags: 'hospital medical' },
    { emoji: '🎯', tags: 'target goals important' },
    { emoji: '⭐', tags: 'star featured' },
    { emoji: '✅', tags: 'check done complete' },
    { emoji: '⚠️', tags: 'warning caution rules' },
    { emoji: '🚨', tags: 'alert emergency' },
    { emoji: '💡', tags: 'tip hint idea' },
    { emoji: '📝', tags: 'notes writing guide' },
    { emoji: '📌', tags: 'pin important' },
    { emoji: '📍', tags: 'pin location gps point' },
    { emoji: '📣', tags: 'announcement bulletin' },
    { emoji: '💬', tags: 'chat message info' },
    { emoji: '🧠', tags: 'knowledge learn' },
    { emoji: '🎓', tags: 'tutorial school training' },
    { emoji: '🛡️', tags: 'security protection' },
    { emoji: '🎮', tags: 'game fun roleplay' },
    { emoji: '🔍', tags: 'search discover' },
    { emoji: '🌟', tags: 'highlight featured' },
    { emoji: '🔥', tags: 'hot trend important' },
    { emoji: '🚗', tags: 'car vehicle driving' },
    { emoji: '🏍️', tags: 'bike motorcycle' },
    { emoji: '✈️', tags: 'travel airport' },
    { emoji: '🚁', tags: 'helicopter air' },
    { emoji: '⛽', tags: 'fuel gas station' },
    { emoji: '🧾', tags: 'receipt document' },
    { emoji: '💰', tags: 'money cash rewards' },
    { emoji: '💎', tags: 'premium value' },
    { emoji: '🎉', tags: 'celebration welcome' },
    { emoji: '😎', tags: 'cool style' },
    { emoji: '🙂', tags: 'smile friendly' },
    { emoji: '🤝', tags: 'community support help' }
];

function getResourceName() {
    if (typeof GetParentResourceName === 'function') {
        return GetParentResourceName();
    }

    return 'pf-guidebook';
}

async function postNui(name, payload = {}) {
    try {
        const response = await fetch(`https://${getResourceName()}/${name}`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json; charset=UTF-8'
            },
            body: JSON.stringify(payload)
        });

        const json = await response.json();
        return json;
    } catch (_error) {
        return { ok: false, error: 'NUI request failed' };
    }
}

function slugify(value) {
    return String(value || '')
        .toLowerCase()
        .trim()
        .replace(/[^a-z0-9\s_-]/g, '')
        .replace(/\s+/g, '_')
        .replace(/_+/g, '_')
        .replace(/^_+|_+$/g, '') || 'entry';
}

function escapeHtml(value) {
    return String(value || '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#039;');
}

function stripHtml(html) {
    const temp = document.createElement('div');
    temp.innerHTML = html || '';
    return (temp.textContent || temp.innerText || '').replace(/\s+/g, ' ').trim();
}

function escapeRegex(text) {
    return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function getErrorText(response, fallback) {
    if (response && typeof response.error === 'string' && response.error.trim() !== '') {
        return response.error;
    }

    return fallback;
}

function showToast(message, kind) {
    if (!el.toastStack || !message) {
        return;
    }

    const tone = kind || 'info';
    const node = document.createElement('div');
    node.className = `toast toast-${tone}`;
    node.textContent = String(message);
    el.toastStack.appendChild(node);

    const timer = window.setTimeout(() => {
        node.remove();
    }, 3200);

    toastTimers.push(timer);
}

function countOccurrences(haystack, needle) {
    if (!needle) {
        return 0;
    }

    const regex = new RegExp(escapeRegex(needle), 'ig');
    const matches = haystack.match(regex);
    return matches ? matches.length : 0;
}

function highlightTerms(text, terms) {
    let value = text;
    terms.forEach((term) => {
        if (!term) return;
        const regex = new RegExp(`(${escapeRegex(term)})`, 'ig');
        value = value.replace(regex, '<mark>$1</mark>');
    });
    return value;
}

function flattenVisiblePages() {
    const pages = [];
    (state.visibleData.categories || []).forEach((category) => {
        (category.pages || []).forEach((page) => {
            pages.push({
                ...page,
                categoryLabel: category.emoji ? `${category.emoji} ${category.label}` : category.label
            });
        });
    });
    return pages;
}

function findVisiblePageByKey(pageKey) {
    const key = String(pageKey || '');
    for (const category of state.visibleData.categories || []) {
        for (const page of category.pages || []) {
            if (page.key === key) {
                return { category, page };
            }
        }
    }

    return null;
}

function getFirstVisiblePageKey() {
    for (const category of state.visibleData.categories || []) {
        for (const page of category.pages || []) {
            return page.key;
        }
    }

    return null;
}

function ensureSelectedPage() {
    if (!state.selectedPageKey || !findVisiblePageByKey(state.selectedPageKey)) {
        state.selectedPageKey = getFirstVisiblePageKey();
    }
}

function syncCollapsedCategoriesFromData() {
    (state.visibleData.categories || []).forEach((category) => {
        if (typeof state.collapsedCategories[category.id] === 'undefined') {
            state.collapsedCategories[category.id] = category.expanded === false;
        }
    });
}

function updateSearchControls() {
    if (!el.searchClear) {
        return;
    }

    const hasQuery = state.searchQuery.trim() !== '';
    el.searchClear.classList.toggle('hidden', !hasQuery);
}

function setSearchQuery(query, renderNow) {
    state.searchQuery = String(query || '').trim();
    el.searchInput.value = state.searchQuery;
    updateSearchControls();

    if (renderNow) {
        renderSidebar();
        renderContent();
    }
}

function updateSidebarStats() {
    if (!el.statCategories || !el.statPages) {
        return;
    }

    const categories = state.visibleData.categories || [];
    let pageCount = 0;

    categories.forEach((category) => {
        pageCount = pageCount + ((category.pages || []).length);
    });

    el.statCategories.textContent = `${categories.length} categor${categories.length === 1 ? 'y' : 'ies'}`;
    el.statPages.textContent = `${pageCount} page${pageCount === 1 ? '' : 's'}`;
}

function normalizeSearchText(value) {
    return String(value || '').toLowerCase();
}

function getFilteredCategories() {
    const categories = [...(state.adminData?.categories || [])].sort((a, b) => a.order - b.order);
    const query = normalizeSearchText(state.adminFilter).trim();

    if (!query) {
        return categories;
    }

    return categories.filter((category) => {
        const searchable = normalizeSearchText(`${category.emoji || ''} ${category.label} ${category.key} ${category.order}`);
        return searchable.includes(query);
    });
}

function getFilteredPages() {
    const pages = [...(state.adminData?.pages || [])].sort((a, b) => a.order - b.order);
    const query = normalizeSearchText(state.adminFilter).trim();

    if (!query) {
        return pages;
    }

    return pages.filter((page) => {
        const categoryLabel = getCategoryLabel(page.categoryId);
        const searchable = normalizeSearchText(`${page.label} ${page.key} ${categoryLabel} ${page.order}`);
        return searchable.includes(query);
    });
}

function updateAdminCount(count) {
    if (!el.adminCount) {
        return;
    }

    const filterActive = state.adminFilter.trim() !== '';
    el.adminCount.textContent = filterActive
        ? `${count} filtered result${count === 1 ? '' : 's'}`
        : `${count} record${count === 1 ? '' : 's'}`;
}

function showApp() {
    if (appCloseTimer) {
        window.clearTimeout(appCloseTimer);
        appCloseTimer = null;
    }

    state.open = true;
    state.isClosing = false;
    el.app.classList.remove('hidden');
    el.app.classList.remove('is-closing', 'is-opening');

    // Restart class-based animation each time the app opens.
    void el.app.offsetWidth;
    el.app.classList.add('is-opening');

    el.app.setAttribute('aria-hidden', 'false');
}

function hideApp() {
    if (appCloseTimer) {
        window.clearTimeout(appCloseTimer);
        appCloseTimer = null;
    }

    state.open = false;
    state.isClosing = false;
    el.app.classList.add('hidden');
    el.app.classList.remove('is-closing', 'is-opening');
    el.app.setAttribute('aria-hidden', 'true');

    while (toastTimers.length > 0) {
        const timer = toastTimers.pop();
        window.clearTimeout(timer);
    }

    if (el.toastStack) {
        el.toastStack.innerHTML = '';
    }

    hideAdminPanel();
    hideEditorModal();
    hideJobModal();
    hideGpsModal();
    resolveEmojiModal(null);
}

function requestCloseApp(options) {
    const settings = {
        notifyGame: true,
        animate: true,
        ...options
    };

    if (!state.open || state.isClosing) {
        return;
    }

    state.isClosing = true;

    if (settings.notifyGame) {
        postNui('close', {});
    }

    if (!settings.animate) {
        hideApp();
        return;
    }

    el.app.classList.remove('is-opening');
    el.app.classList.add('is-closing');

    if (appCloseTimer) {
        window.clearTimeout(appCloseTimer);
    }

    appCloseTimer = window.setTimeout(() => {
        hideApp();
    }, APP_CLOSE_ANIMATION_MS);
}

function showAdminButtons() {
    const shouldShow = state.isAdmin;
    el.sidebarAdmin.classList.toggle('hidden', !shouldShow);
    el.contentAdmin.classList.toggle('hidden', !shouldShow);
}

function renderSidebar() {
    const categories = state.visibleData.categories || [];

    if (categories.length === 0) {
        el.categoryList.innerHTML = '<div class="empty-state">No visible categories.</div>';
        return;
    }

    const html = categories.map((category) => {
        const isCollapsed = state.collapsedCategories[category.id] === true;
        const categoryEmoji = category.emoji ? `<span class="category-emoji">${escapeHtml(category.emoji)}</span>` : '';
        const pageList = isCollapsed
            ? ''
            : (category.pages || []).map((page) => {
                const isActive = state.selectedPageKey === page.key && state.searchQuery === '';
                return `
                    <button class="page-link${isActive ? ' active' : ''}" data-page-key="${escapeHtml(page.key)}">
                        ${escapeHtml(page.label)}
                    </button>
                `;
            }).join('');

        return `
            <section class="category-card">
                <button class="category-header" data-category-id="${escapeHtml(category.id)}">
                    <span class="category-title">${categoryEmoji}<span>${escapeHtml(category.label)}</span></span>
                    <span class="chevron" aria-hidden="true">
                        ${isCollapsed
                            ? '<svg class="icon-svg" viewBox="0 0 24 24"><path d="M7 10l5 5 5-5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>'
                            : '<svg class="icon-svg" viewBox="0 0 24 24"><path d="M7 14l5-5 5 5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>'}
                    </span>
                </button>
                <div class="category-pages ${isCollapsed ? 'hidden' : ''}">
                    ${pageList || '<small class="empty-state">No pages</small>'}
                </div>
            </section>
        `;
    }).join('');

    el.categoryList.innerHTML = html;

    el.categoryList.querySelectorAll('.category-header').forEach((button) => {
        button.addEventListener('click', () => {
            const id = button.dataset.categoryId;
            state.collapsedCategories[id] = !state.collapsedCategories[id];
            renderSidebar();
        });
    });

    el.categoryList.querySelectorAll('.page-link').forEach((button) => {
        button.addEventListener('click', () => {
            state.selectedPageKey = button.dataset.pageKey;
            setSearchQuery('', true);
        });
    });
}

function renderGpsButtons(scope) {
    scope.querySelectorAll('.guidebook-gps').forEach((button) => {
        button.addEventListener('click', async () => {
            const payload = {
                pointKey: button.dataset.pointKey || null,
                label: button.dataset.label || button.textContent || 'GPS',
                x: button.dataset.x || null,
                y: button.dataset.y || null
            };

            const response = await postNui('setWaypoint', payload);
            if (!response.ok) {
                showToast(getErrorText(response, 'Unable to set waypoint.'), 'error');
            } else {
                showToast(`Waypoint set: ${payload.label}`, 'success');
            }
        });
    });
}

function renderSelectedPage() {
    const selected = findVisiblePageByKey(state.selectedPageKey);

    if (!selected) {
        el.contentTitle.textContent = 'Guidebook';
        el.contentSubtitle.textContent = 'Select a page from the left.';
        el.contentBody.innerHTML = '<div class="empty-state">No page selected.</div>';
        return;
    }

    el.contentTitle.textContent = selected.page.label;
    const subtitleCategory = selected.category.emoji ? `${selected.category.emoji} ${selected.category.label}` : selected.category.label;
    el.contentSubtitle.textContent = `${subtitleCategory} / ${selected.page.key}`;
    el.contentBody.innerHTML = `
        <article class="page-content">
            ${selected.page.content || ''}
        </article>
    `;

    renderGpsButtons(el.contentBody);
}

function searchPages(query) {
    const cleaned = String(query || '').trim().toLowerCase();
    if (cleaned === '') {
        return [];
    }

    const terms = cleaned.split(/\s+/).filter(Boolean);
    const pages = flattenVisiblePages();

    return pages
        .map((page) => {
            const plain = stripHtml(page.content || '');
            const title = page.label || '';
            const combined = `${title} ${plain}`.toLowerCase();

            const matches = terms.every((term) => combined.includes(term));
            if (!matches) {
                return null;
            }

            const firstHit = Math.max(0, combined.indexOf(terms[0]));
            const snippetStart = Math.max(0, firstHit - 80);
            const snippet = plain.slice(snippetStart, snippetStart + 220);
            let hitCount = 0;
            terms.forEach((term) => {
                hitCount = hitCount + countOccurrences(combined, term);
            });

            return {
                ...page,
                snippet,
                terms,
                hitCount
            };
        })
        .filter(Boolean);
}

function renderSearchResults() {
    const query = state.searchQuery.trim();
    const results = searchPages(query);
    const terms = query.toLowerCase().split(/\s+/).filter(Boolean);

    el.contentTitle.textContent = 'Search Results';
    el.contentSubtitle.textContent = `Query: "${query}"`;

    if (results.length === 0) {
        el.contentBody.innerHTML = `
            <div class="search-result-box">
                <div class="empty-state">No results for "${escapeHtml(query)}".</div>
            </div>
        `;
        return;
    }

    const html = results.map((result) => {
        return `
            <article class="search-item" data-page-key="${escapeHtml(result.key)}">
                <div class="search-meta">
                    <span>${escapeHtml(result.categoryLabel)} / ${escapeHtml(result.label)}</span>
                    <span class="search-count">${result.hitCount} match(es)</span>
                </div>
                <div class="search-snippet">${highlightTerms(escapeHtml(result.snippet), terms)}</div>
            </article>
        `;
    }).join('');

    el.contentBody.innerHTML = `
        <section class="search-result-box">
            <div>Found ${results.length} result(s) for <strong>${escapeHtml(query)}</strong>.</div>
            ${html}
        </section>
    `;

    el.contentBody.querySelectorAll('.search-item').forEach((item) => {
        item.addEventListener('click', () => {
            state.selectedPageKey = item.dataset.pageKey;
            setSearchQuery('', true);
        });
    });
}

function renderContent() {
    const searching = state.searchQuery.trim() !== '';
    el.contentBack.classList.toggle('hidden', !searching);

    if (searching) {
        renderSearchResults();
        return;
    }

    renderSelectedPage();
}

function renderAll() {
    syncCollapsedCategoriesFromData();
    ensureSelectedPage();
    updateSearchControls();
    updateSidebarStats();
    showAdminButtons();
    renderSidebar();
    renderContent();

    if (!el.adminPanel.classList.contains('hidden')) {
        renderAdminSection();
    }
}

function getCategoryById(id) {
    return (state.adminData?.categories || []).find((item) => item.id === id) || null;
}

function getPageById(id) {
    return (state.adminData?.pages || []).find((item) => item.id === id) || null;
}

function getCategoryLabel(categoryId) {
    const category = getCategoryById(categoryId);
    if (!category) {
        return 'Unknown';
    }

    return category.emoji ? `${category.emoji} ${category.label}` : category.label;
}

function hideAdminPanel() {
    el.adminPanel.classList.add('hidden');
    el.adminPanel.setAttribute('aria-hidden', 'true');
}

async function showAdminPanel(forceTab) {
    if (!state.isAdmin) {
        return;
    }

    if (forceTab) {
        state.adminTab = forceTab;
    }

    if (!state.adminData) {
        const response = await postNui('getAdminData', {});
        if (!response.ok) {
            showToast(getErrorText(response, 'Unable to load admin data.'), 'error');
            return;
        }

        state.adminData = response.adminData;
    }

    renderAdminSection();
    el.adminPanel.classList.remove('hidden');
    el.adminPanel.setAttribute('aria-hidden', 'false');
}

function renderAdminSection() {
    if (!state.adminData) {
        el.adminList.innerHTML = '<div class="empty-state">Unable to load admin data.</div>';
        return;
    }

    const isCategories = state.adminTab === 'categories';
    el.adminTabCategories.classList.toggle('active', isCategories);
    el.adminTabPages.classList.toggle('active', !isCategories);

    if (isCategories) {
        el.adminSectionTitle.textContent = 'Categories';
        renderAdminCategories();
    } else {
        el.adminSectionTitle.textContent = 'Pages';
        renderAdminPages();
    }
}

function renderAdminCategories() {
    const categories = getFilteredCategories();
    updateAdminCount(categories.length);

    if (categories.length === 0) {
        el.adminList.innerHTML = `<div class="empty-state">${state.adminFilter.trim() !== '' ? 'No categories match your filter.' : 'No categories yet.'}</div>`;
        return;
    }

    el.adminList.innerHTML = categories.map((category) => {
        const statusPills = [
            `<span class="status-pill ${category.enabled ? 'status-enabled' : 'status-disabled'}">${category.enabled ? 'Enabled' : 'Disabled'}</span>`
        ];

        if (category.permissionsEnabled) {
            statusPills.push('<span class="status-pill status-restricted">Restricted</span>');
        }

        const emojiBlock = category.emoji
            ? `<span class="admin-emoji">${escapeHtml(category.emoji)}</span>`
            : '<span class="admin-emoji admin-emoji-empty">No emoji</span>';

        return `
            <article class="admin-row" data-category-id="${escapeHtml(category.id)}">
                <div>
                    <strong class="admin-label-row">${emojiBlock}<span>${escapeHtml(category.label)}</span></strong>
                    <div class="admin-meta">
                        <small>key: ${escapeHtml(category.key)} | order: ${category.order}</small>
                        ${statusPills.join('')}
                    </div>
                </div>
                <div class="row-actions">
                    <button class="action-btn" data-action="edit">Edit</button>
                    <button class="action-btn delete" data-action="delete">Delete</button>
                </div>
            </article>
        `;
    }).join('');

    el.adminList.querySelectorAll('.admin-row').forEach((row) => {
        const categoryId = row.dataset.categoryId;

        row.querySelector('[data-action="edit"]').addEventListener('click', () => {
            openCategoryEditor(getCategoryById(categoryId));
        });

        row.querySelector('[data-action="delete"]').addEventListener('click', async () => {
            if (!confirm('Delete this category and all pages inside it?')) {
                return;
            }

            const response = await postNui('deleteCategory', { id: categoryId });
            if (!response.ok) {
                showToast(getErrorText(response, 'Category delete failed.'), 'error');
                return;
            }

            applyServerRefresh(response);
            showToast('Category deleted.', 'success');
        });
    });
}

function renderAdminPages() {
    const pages = getFilteredPages();
    updateAdminCount(pages.length);

    if (pages.length === 0) {
        el.adminList.innerHTML = `<div class="empty-state">${state.adminFilter.trim() !== '' ? 'No pages match your filter.' : 'No pages yet.'}</div>`;
        return;
    }

    el.adminList.innerHTML = pages.map((page) => {
        const statusPills = [
            `<span class="status-pill ${page.enabled ? 'status-enabled' : 'status-disabled'}">${page.enabled ? 'Enabled' : 'Disabled'}</span>`
        ];

        if (page.permissionsEnabled) {
            statusPills.push('<span class="status-pill status-restricted">Restricted</span>');
        }

        return `
            <article class="admin-row" data-page-id="${escapeHtml(page.id)}">
                <div>
                    <strong>${escapeHtml(page.label)}</strong>
                    <div class="admin-meta">
                        <small>key: ${escapeHtml(page.key)} | category: ${escapeHtml(getCategoryLabel(page.categoryId))} | order: ${page.order}</small>
                        ${statusPills.join('')}
                    </div>
                </div>
                <div class="row-actions">
                    <button class="action-btn" data-action="edit">Edit</button>
                    <button class="action-btn delete" data-action="delete">Delete</button>
                </div>
            </article>
        `;
    }).join('');

    el.adminList.querySelectorAll('.admin-row').forEach((row) => {
        const pageId = row.dataset.pageId;

        row.querySelector('[data-action="edit"]').addEventListener('click', () => {
            openPageEditor(getPageById(pageId));
        });

        row.querySelector('[data-action="delete"]').addEventListener('click', async () => {
            if (!confirm('Delete this page?')) {
                return;
            }

            const response = await postNui('deletePage', { id: pageId });
            if (!response.ok) {
                showToast(getErrorText(response, 'Page delete failed.'), 'error');
                return;
            }

            applyServerRefresh(response);
            showToast('Page deleted.', 'success');
        });
    });
}

function showEditorModal() {
    el.editorModal.classList.remove('hidden');
    el.editorModal.setAttribute('aria-hidden', 'false');
}

function hideEditorModal() {
    el.editorModal.classList.add('hidden');
    el.editorModal.setAttribute('aria-hidden', 'true');
    el.editorBody.innerHTML = '';
    state.activeEditor = null;
}

function renderAllowedJobs(container, allowedJobs) {
    if (!allowedJobs.length) {
        container.innerHTML = '<small class="empty-state">No job restrictions added.</small>';
        return;
    }

    container.innerHTML = allowedJobs.map((job, index) => {
        return `
            <div class="job-chip" data-index="${index}">
                <span>${escapeHtml(job.job)} (min grade ${job.minGrade})</span>
                <button type="button" data-remove="${index}">x</button>
            </div>
        `;
    }).join('');

    container.querySelectorAll('[data-remove]').forEach((button) => {
        button.addEventListener('click', () => {
            const index = Number(button.dataset.remove);
            allowedJobs.splice(index, 1);
            renderAllowedJobs(container, allowedJobs);
        });
    });
}

function openJobModal() {
    return new Promise((resolve) => {
        state.jobModalResolver = resolve;

        const jobs = state.adminData?.jobs || [];
        if (jobs.length === 0) {
            el.jobSelect.innerHTML = '<option value="">No jobs available</option>';
            el.jobGradeSelect.innerHTML = '<option value="0">Grade 0</option>';
            el.jobAdd.disabled = true;
            el.jobSelect.disabled = true;
            el.jobGradeSelect.disabled = true;
            showToast('No framework job list available in this mode.', 'info');
        } else {
            el.jobAdd.disabled = false;
            el.jobSelect.disabled = false;
            el.jobGradeSelect.disabled = false;
            el.jobSelect.innerHTML = jobs.map((job) => {
                return `<option value="${escapeHtml(job.name)}">${escapeHtml(job.label)}</option>`;
            }).join('');
        }

        const syncGrades = () => {
            const selected = jobs.find((job) => job.name === el.jobSelect.value);
            const grades = selected?.grades?.length ? selected.grades : [{ level: 0, label: 'Grade 0' }];

            el.jobGradeSelect.innerHTML = grades.map((grade) => {
                return `<option value="${grade.level}">${escapeHtml(grade.label)} (${grade.level})</option>`;
            }).join('');
        };

        el.jobSelect.onchange = syncGrades;
        syncGrades();

        el.jobModal.classList.remove('hidden');
        el.jobModal.setAttribute('aria-hidden', 'false');
    });
}

function hideJobModal() {
    el.jobModal.classList.add('hidden');
    el.jobModal.setAttribute('aria-hidden', 'true');
}

function resolveJobModal(value) {
    if (state.jobModalResolver) {
        state.jobModalResolver(value);
        state.jobModalResolver = null;
    }
    hideJobModal();
}

function saveEditorSelection() {
    const selection = window.getSelection();
    if (!selection || selection.rangeCount === 0) {
        state.savedEditorSelection = null;
        return;
    }

    state.savedEditorSelection = selection.getRangeAt(0).cloneRange();
}

function restoreEditorSelection(editorBody) {
    const selection = window.getSelection();
    if (!selection || !state.savedEditorSelection) {
        editorBody.focus();
        return;
    }

    selection.removeAllRanges();
    selection.addRange(state.savedEditorSelection);
    editorBody.focus();
}

function openGpsModal() {
    return new Promise((resolve) => {
        state.gpsModalResolver = resolve;

        el.gpsLabel.value = '';
        el.gpsX.value = '';
        el.gpsY.value = '';

        el.gpsModal.classList.remove('hidden');
        el.gpsModal.setAttribute('aria-hidden', 'false');
    });
}

function hideGpsModal() {
    el.gpsModal.classList.add('hidden');
    el.gpsModal.setAttribute('aria-hidden', 'true');
}

function resolveGpsModal(value) {
    if (state.gpsModalResolver) {
        state.gpsModalResolver(value);
        state.gpsModalResolver = null;
    }
    hideGpsModal();
}

function renderEmojiGrid(query) {
    const search = normalizeSearchText(query).trim();

    const entries = EMOJI_LIBRARY.filter((entry) => {
        if (!search) {
            return true;
        }

        const searchable = normalizeSearchText(`${entry.emoji} ${entry.tags}`);
        return searchable.includes(search);
    });

    if (!entries.length) {
        el.emojiGrid.innerHTML = '<div class="empty-state">No emojis match your search.</div>';
        return;
    }

    el.emojiGrid.innerHTML = entries.map((entry) => {
        return `
            <button type="button" class="emoji-choice" data-emoji="${escapeHtml(entry.emoji)}" title="${escapeHtml(entry.tags)}">
                <span class="emoji-choice-symbol">${escapeHtml(entry.emoji)}</span>
            </button>
        `;
    }).join('');

    const emojiButtons = Array.from(el.emojiGrid.querySelectorAll('.emoji-choice'));

    emojiButtons.forEach((button) => {
        button.addEventListener('click', () => {
            resolveEmojiModal(button.dataset.emoji || '');
        });

        button.addEventListener('keydown', (e) => {
            const cur = emojiButtons.indexOf(e.currentTarget);
            let next = -1;

            if (e.key === 'ArrowRight') {
                next = Math.min(cur + 1, emojiButtons.length - 1);
            } else if (e.key === 'ArrowLeft') {
                next = Math.max(cur - 1, 0);
            } else if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
                // Detect column count by finding the first button on a new row
                const firstTop = emojiButtons[0] ? emojiButtons[0].getBoundingClientRect().top : 0;
                const firstOnNewRow = emojiButtons.findIndex((b, i) => i > 0 && b.getBoundingClientRect().top > firstTop + 4);
                const cols = firstOnNewRow > 0 ? firstOnNewRow : emojiButtons.length;
                next = e.key === 'ArrowDown'
                    ? Math.min(cur + cols, emojiButtons.length - 1)
                    : Math.max(cur - cols, 0);
            } else {
                return; // let other keys (Enter, Escape, Tab) bubble naturally
            }

            e.preventDefault();
            emojiButtons[next].focus();
        });
    });
}

function openEmojiModal(titleText) {
    return new Promise((resolve) => {
        state.emojiModalResolver = resolve;

        el.emojiTitle.textContent = titleText || 'Pick Emoji';
        el.emojiSearch.value = '';
        renderEmojiGrid('');

        el.emojiModal.classList.remove('hidden');
        el.emojiModal.setAttribute('aria-hidden', 'false');
        el.emojiSearch.focus();
    });
}

function hideEmojiModal() {
    if (!el.emojiModal) {
        return;
    }

    el.emojiModal.classList.add('hidden');
    el.emojiModal.setAttribute('aria-hidden', 'true');
}

function resolveEmojiModal(value) {
    if (state.emojiModalResolver) {
        state.emojiModalResolver(value);
        state.emojiModalResolver = null;
    }

    hideEmojiModal();
}

function insertHtmlAtCursor(html) {
    document.execCommand('insertHTML', false, html);
}

function normalizeYoutubeEmbed(url) {
    if (!url) return null;

    try {
        const parsed = new URL(url);
        if (parsed.hostname.includes('youtube.com')) {
            const id = parsed.searchParams.get('v');
            if (id) {
                return `https://www.youtube.com/embed/${id}`;
            }
        }

        if (parsed.hostname.includes('youtu.be')) {
            const id = parsed.pathname.replace('/', '').trim();
            if (id) {
                return `https://www.youtube.com/embed/${id}`;
            }
        }

        return url;
    } catch (_error) {
        return url;
    }
}

const EDITOR_FONT_OPTIONS = [
    'Arial',
    'Arial Black',
    'Bahnschrift',
    'Book Antiqua',
    'Calibri',
    'Cambria',
    'Candara',
    'Comic Sans MS',
    'Consolas',
    'Constantia',
    'Corbel',
    'Courier New',
    'Franklin Gothic Medium',
    'Garamond',
    'Georgia',
    'Impact',
    'Lucida Console',
    'Lucida Sans Unicode',
    'Palatino Linotype',
    'Segoe UI',
    'Tahoma',
    'Times New Roman',
    'Trebuchet MS',
    'Verdana'
];

function buildFontOptions() {
    return EDITOR_FONT_OPTIONS.map((fontName) => {
        return `<option value="${escapeHtml(fontName)}" ${fontName === 'Bahnschrift' ? 'selected' : ''}>${escapeHtml(fontName)}</option>`;
    }).join('');
}

function buildToggleCard(id, title, description, checked) {
    return `
        <label class="check-card">
            <input id="${id}" type="checkbox" ${checked ? 'checked' : ''} />
            <span class="check-indicator" aria-hidden="true"></span>
            <span class="check-copy">
                <span class="check-title">${escapeHtml(title)}</span>
                <span class="check-description">${escapeHtml(description)}</span>
            </span>
        </label>
    `;
}

function bindPermissionSection(toggleId, sectionId) {
    const toggle = document.getElementById(toggleId);
    const section = document.getElementById(sectionId);

    if (!toggle || !section) {
        return;
    }

    const syncVisibility = () => {
        const visible = toggle.checked;
        section.classList.toggle('hidden', !visible);
        section.setAttribute('aria-hidden', visible ? 'false' : 'true');
    };

    toggle.addEventListener('change', syncVisibility);
    syncVisibility();
}

function buildEditorToolbar() {
    return `
        <div class="editor-toolbar">
            <div class="tool-group">
                <span class="tool-group-label">History</span>
                <div class="tool-group-controls">
                    <button type="button" data-cmd="undo" title="Undo">Undo</button>
                    <button type="button" data-cmd="redo" title="Redo">Redo</button>
                </div>
            </div>

            <div class="tool-group">
                <span class="tool-group-label">Text</span>
                <div class="tool-group-controls">
                    <select data-cmd-select="formatBlock" title="Block style">
                        <option value="P">Paragraph</option>
                        <option value="H1">H1</option>
                        <option value="H2">H2</option>
                        <option value="H3">H3</option>
                        <option value="H4">H4</option>
                        <option value="BLOCKQUOTE">Quote</option>
                        <option value="PRE">Code Block</option>
                    </select>
                    <select data-cmd-select="fontName" title="Font family">
                        ${buildFontOptions()}
                    </select>
                    <select data-cmd-select="fontSize" title="Font size">
                        <option value="2">Small</option>
                        <option value="3" selected>Normal</option>
                        <option value="4">Medium</option>
                        <option value="5">Large</option>
                        <option value="6">XL</option>
                    </select>
                    <input type="color" data-cmd-color="foreColor" value="#132536" title="Text color" />
                    <input type="color" data-cmd-color="hiliteColor" value="#fff3b0" title="Highlight color" />
                </div>
            </div>

            <div class="tool-group">
                <span class="tool-group-label">Inline</span>
                <div class="tool-group-controls">
                    <button type="button" data-cmd="bold" title="Bold"><b>B</b></button>
                    <button type="button" data-cmd="italic" title="Italic"><i>I</i></button>
                    <button type="button" data-cmd="underline" title="Underline"><u>U</u></button>
                    <button type="button" data-cmd="strikeThrough" title="Strike"><s>S</s></button>
                    <button type="button" data-cmd="subscript" title="Subscript">X<sub>2</sub></button>
                    <button type="button" data-cmd="superscript" title="Superscript">X<sup>2</sup></button>
                </div>
            </div>

            <div class="tool-group">
                <span class="tool-group-label">Layout</span>
                <div class="tool-group-controls">
                    <button type="button" data-cmd="justifyLeft" title="Align left">L</button>
                    <button type="button" data-cmd="justifyCenter" title="Align center">C</button>
                    <button type="button" data-cmd="justifyRight" title="Align right">R</button>
                    <button type="button" data-cmd="justifyFull" title="Justify">J</button>
                    <button type="button" data-cmd="insertUnorderedList" title="Bulleted list">UL</button>
                    <button type="button" data-cmd="insertOrderedList" title="Numbered list">OL</button>
                    <button type="button" data-cmd="outdent" title="Outdent">Out</button>
                    <button type="button" data-cmd="indent" title="Indent">In</button>
                </div>
            </div>

            <div class="tool-group">
                <span class="tool-group-label">Insert</span>
                <div class="tool-group-controls">
                    <button type="button" data-action="link">Link</button>
                    <button type="button" data-cmd="unlink">Unlink</button>
                    <button type="button" data-action="image">Image</button>
                    <button type="button" data-action="video">Video</button>
                    <button type="button" data-action="embed">Embed</button>
                    <button type="button" data-action="table">Table</button>
                    <button type="button" data-action="hr">HR</button>
                    <button type="button" data-action="code">Code</button>
                    <button type="button" data-action="emoji" class="toolbar-emoji-btn">Emoji</button>
                    <button type="button" data-action="gps">GPS</button>
                </div>
            </div>

            <div class="tool-group">
                <span class="tool-group-label">Reset</span>
                <div class="tool-group-controls">
                    <button type="button" data-cmd="removeFormat" title="Clear formatting">Clear</button>
                </div>
            </div>
        </div>
    `;
}

function setupEditorTools(editorRoot) {
    const editorBody = editorRoot.querySelector('.editor-body');
    const toolbar = editorRoot.querySelector('.editor-toolbar');

    if (!editorBody || !toolbar) {
        return;
    }

    const normalizeUrl = (raw) => {
        const trimmed = String(raw || '').trim();
        if (!trimmed) {
            return '';
        }

        if (/^(https?:|mailto:|tel:)/i.test(trimmed)) {
            return trimmed;
        }

        return `https://${trimmed}`;
    };

    const applyCommand = (cmd, value) => {
        restoreEditorSelection(editorBody);
        document.execCommand(cmd, false, value ?? null);
        saveEditorSelection();
    };

    editorBody.addEventListener('keyup', saveEditorSelection);
    editorBody.addEventListener('mouseup', saveEditorSelection);
    editorBody.addEventListener('focus', saveEditorSelection);

    toolbar.querySelectorAll('[data-cmd]').forEach((button) => {
        button.addEventListener('click', () => {
            applyCommand(button.dataset.cmd, null);
        });
    });

    toolbar.querySelectorAll('[data-cmd-select]').forEach((select) => {
        select.addEventListener('change', () => {
            const cmd = select.dataset.cmdSelect;
            const value = cmd === 'formatBlock' ? `<${select.value}>` : select.value;
            applyCommand(cmd, value);
            select.blur();
        });
    });

    toolbar.querySelectorAll('[data-cmd-color]').forEach((input) => {
        input.addEventListener('change', () => {
            applyCommand(input.dataset.cmdColor, input.value);
        });
    });

    toolbar.querySelectorAll('[data-action]').forEach((button) => {
        button.addEventListener('click', async () => {
            saveEditorSelection();
            const action = button.dataset.action;

            if (action === 'link') {
                const url = normalizeUrl(window.prompt('Enter URL (https://...)'));
                if (!url) return;
                applyCommand('createLink', url);
                return;
            }

            if (action === 'image') {
                const url = normalizeUrl(window.prompt('Enter image URL'));
                if (!url) return;
                restoreEditorSelection(editorBody);
                insertHtmlAtCursor(`<img src="${escapeHtml(url)}" alt="Image" />`);
                saveEditorSelection();
                return;
            }

            if (action === 'video') {
                const url = normalizeUrl(window.prompt('Enter video URL (YouTube works best)'));
                if (!url) return;
                const embed = normalizeYoutubeEmbed(url);
                restoreEditorSelection(editorBody);
                insertHtmlAtCursor(`<iframe src="${escapeHtml(embed)}" width="640" height="360" frameborder="0" allowfullscreen></iframe>`);
                saveEditorSelection();
                return;
            }

            if (action === 'embed') {
                const url = normalizeUrl(window.prompt('Enter website/embed URL'));
                if (!url) return;
                restoreEditorSelection(editorBody);
                insertHtmlAtCursor(`<iframe src="${escapeHtml(url)}" width="100%" height="480" frameborder="0"></iframe>`);
                saveEditorSelection();
                return;
            }

            if (action === 'table') {
                restoreEditorSelection(editorBody);
                insertHtmlAtCursor('<table><thead><tr><th>Header 1</th><th>Header 2</th></tr></thead><tbody><tr><td>Value</td><td>Value</td></tr><tr><td>Value</td><td>Value</td></tr></tbody></table><p></p>');
                saveEditorSelection();
                return;
            }

            if (action === 'hr') {
                applyCommand('insertHorizontalRule', null);
                return;
            }

            if (action === 'code') {
                const selection = window.getSelection();
                const selectedText = selection && selection.rangeCount ? selection.toString().trim() : '';
                const codeText = selectedText ? selectedText : 'code_sample';
                restoreEditorSelection(editorBody);
                insertHtmlAtCursor(`<pre><code>${escapeHtml(codeText)}</code></pre><p></p>`);
                saveEditorSelection();
                return;
            }

            if (action === 'emoji') {
                const emoji = await openEmojiModal('Insert Emoji in Content');
                if (!emoji) return;
                restoreEditorSelection(editorBody);
                insertHtmlAtCursor(emoji);
                saveEditorSelection();
                return;
            }

            if (action === 'gps') {
                const result = await openGpsModal();
                if (!result) return;

                const key = `${slugify(result.label)}_${Math.floor(Math.random() * 9000) + 1000}`;
                const buttonHtml = `<button class="guidebook-gps" data-point-key="${escapeHtml(key)}" data-label="${escapeHtml(result.label)}" data-x="${result.x}" data-y="${result.y}" data-can-navigate="1">${escapeHtml(result.label)}</button>`;
                restoreEditorSelection(editorBody);
                insertHtmlAtCursor(buttonHtml);
                saveEditorSelection();
            }
        });
    });
}

function openCategoryEditor(category) {
    const record = category || {
        id: null,
        label: '',
        key: '',
        emoji: '',
        order: 0,
        enabled: true,
        expanded: true,
        permissionsEnabled: false,
        allowedJobs: []
    };

    const allowedJobs = [...(record.allowedJobs || [])];

    el.editorTitle.textContent = category ? 'Edit Category' : 'Create Category';
    el.editorBody.innerHTML = `
        <div class="editor-form-layout category-editor-layout">
            <section class="editor-panel">
                <div class="panel-heading">
                    <h5>Category details</h5>
                    <p>Name it clearly and set the key players or admins will recognize.</p>
                </div>

                <div class="form-grid two">
                    <div>
                        <label class="field-label">Label</label>
                        <input id="cat-label" class="field-input" value="${escapeHtml(record.label)}" />
                    </div>
                    <div>
                        <label class="field-label">Key</label>
                        <input id="cat-key" class="field-input" value="${escapeHtml(record.key)}" />
                    </div>
                </div>

                <div>
                    <label class="field-label">Category emoji</label>
                    <div class="emoji-input-row">
                        <input id="cat-emoji" class="field-input" maxlength="8" value="${escapeHtml(record.emoji || '')}" placeholder="Optional emoji" />
                        <button id="cat-pick-emoji" class="ghost-btn" type="button">Pick</button>
                        <button id="cat-clear-emoji" class="ghost-btn" type="button">Clear</button>
                        <span id="cat-emoji-preview" class="emoji-preview">${escapeHtml(record.emoji || '∅')}</span>
                    </div>
                </div>
            </section>

            <section class="editor-panel">
                <div class="panel-heading">
                    <h5>Behavior and access</h5>
                    <p>Control visibility, whether the category starts expanded, and who can access it.</p>
                </div>

                <div class="form-grid three">
                    <div>
                        <label class="field-label">Order</label>
                        <input id="cat-order" class="field-input" type="number" value="${record.order}" />
                    </div>
                    ${buildToggleCard('cat-enabled', 'Enabled', 'Show this category in the guidebook.', record.enabled)}
                    ${buildToggleCard('cat-expanded', 'Expanded by default', 'Open this category automatically when the UI loads.', record.expanded)}
                </div>

                <div class="toggle-grid single-toggle">
                    ${buildToggleCard('cat-perm-enabled', 'Permissions enabled', 'Restrict this category to selected jobs and grades.', record.permissionsEnabled)}
                </div>

                <div id="cat-allowed-jobs-section" class="permission-section">
                    <div class="field-label">Allowed jobs</div>
                    <div id="cat-allowed-jobs" class="allowed-jobs"></div>
                    <div class="permission-actions"><button id="cat-add-job" class="ghost-btn" type="button">+ Add job</button></div>
                </div>
            </section>

            <div class="modal-footer modal-footer-inline">
                <button id="cat-cancel" class="ghost-btn" type="button">Cancel</button>
                <button id="cat-save" class="primary-btn" type="button">Save Category</button>
            </div>
        </div>
    `;

    showEditorModal();

    const allowedContainer = document.getElementById('cat-allowed-jobs');
    renderAllowedJobs(allowedContainer, allowedJobs);
    bindPermissionSection('cat-perm-enabled', 'cat-allowed-jobs-section');

    document.getElementById('cat-add-job').addEventListener('click', async () => {
        const selected = await openJobModal();
        if (!selected) return;

        const existing = allowedJobs.find((job) => job.job === selected.job);
        if (existing) {
            existing.minGrade = selected.minGrade;
        } else {
            allowedJobs.push(selected);
        }

        renderAllowedJobs(allowedContainer, allowedJobs);
    });

    const catEmojiInput = document.getElementById('cat-emoji');
    const catEmojiPreview = document.getElementById('cat-emoji-preview');

    const syncCategoryEmojiPreview = () => {
        const value = catEmojiInput.value.trim();
        catEmojiPreview.textContent = value || '∅';
    };

    catEmojiInput.addEventListener('input', syncCategoryEmojiPreview);
    syncCategoryEmojiPreview();

    document.getElementById('cat-pick-emoji').addEventListener('click', async () => {
        const emoji = await openEmojiModal('Pick Category Emoji');
        if (!emoji) {
            return;
        }

        catEmojiInput.value = emoji;
        syncCategoryEmojiPreview();
    });

    document.getElementById('cat-clear-emoji').addEventListener('click', () => {
        catEmojiInput.value = '';
        syncCategoryEmojiPreview();
    });

    document.getElementById('cat-cancel').addEventListener('click', hideEditorModal);

    document.getElementById('cat-save').addEventListener('click', async () => {
        const payload = {
            id: record.id,
            label: document.getElementById('cat-label').value,
            key: document.getElementById('cat-key').value,
            emoji: document.getElementById('cat-emoji').value.trim(),
            order: Number(document.getElementById('cat-order').value || 0),
            enabled: document.getElementById('cat-enabled').checked,
            expanded: document.getElementById('cat-expanded').checked,
            permissionsEnabled: document.getElementById('cat-perm-enabled').checked,
            allowedJobs
        };

        const response = await postNui('saveCategory', payload);
        if (!response.ok) {
            showToast(getErrorText(response, 'Category save failed.'), 'error');
            return;
        }

        hideEditorModal();
        applyServerRefresh(response);
        showToast('Category saved.', 'success');
    });
}

function openPageEditor(page) {
    const record = page || {
        id: null,
        categoryId: state.adminData?.categories?.[0]?.id || null,
        label: '',
        key: '',
        order: 0,
        enabled: true,
        permissionsEnabled: false,
        allowedJobs: [],
        content: ''
    };

    const allowedJobs = [...(record.allowedJobs || [])];
    const categories = state.adminData?.categories || [];

    el.editorTitle.textContent = page ? 'Edit Page' : 'Create Page';
    el.editorBody.innerHTML = `
        <div class="editor-form-layout page-editor-layout">
            <section class="editor-panel">
                <div class="panel-heading">
                    <h5>Page details</h5>
                    <p>Set where the page belongs and how it appears in the guidebook.</p>
                </div>

                <div class="form-grid three">
                    <div>
                        <label class="field-label">Category</label>
                        <select id="page-category" class="field-select">
                            ${categories.map((category) => {
                                const categoryName = `${category.emoji ? `${category.emoji} ` : ''}${category.label}`;
                                return `<option value="${escapeHtml(category.id)}" ${category.id === record.categoryId ? 'selected' : ''}>${escapeHtml(categoryName)}</option>`;
                            }).join('')}
                        </select>
                    </div>
                    <div>
                        <label class="field-label">Label</label>
                        <input id="page-label" class="field-input" value="${escapeHtml(record.label)}" />
                    </div>
                    <div>
                        <label class="field-label">Key</label>
                        <input id="page-key" class="field-input" value="${escapeHtml(record.key)}" />
                    </div>
                </div>
            </section>

            <section class="editor-panel">
                <div class="panel-heading">
                    <h5>Visibility and access</h5>
                    <p>Decide if the page is visible to everyone or restricted to selected jobs.</p>
                </div>

                <div class="form-grid three">
                    <div>
                        <label class="field-label">Order</label>
                        <input id="page-order" class="field-input" type="number" value="${record.order}" />
                    </div>
                    ${buildToggleCard('page-enabled', 'Enabled', 'Show this page in the guidebook.', record.enabled)}
                    ${buildToggleCard('page-perm-enabled', 'Permissions enabled', 'Restrict this page to selected jobs and grades.', record.permissionsEnabled)}
                </div>

                <div id="page-allowed-jobs-section" class="permission-section">
                    <div class="field-label">Allowed jobs</div>
                    <div id="page-allowed-jobs" class="allowed-jobs"></div>
                    <div class="permission-actions"><button id="page-add-job" class="ghost-btn" type="button">+ Add job</button></div>
                </div>
            </section>

            <section class="editor-panel editor-panel-editor">
                <div class="panel-heading panel-heading-split">
                    <div>
                        <h5>Page content</h5>
                        <p>Format the page using the toolbar and write content in the canvas below.</p>
                    </div>
                </div>

                <div id="page-editor-root" class="editor-surface">
                    ${buildEditorToolbar()}
                    <div id="page-editor-body" class="editor-body" contenteditable="true" data-placeholder="Write the guidebook page content here...">${record.content || ''}</div>
                </div>
            </section>

            <div class="modal-footer modal-footer-inline">
                <button id="page-cancel" class="ghost-btn" type="button">Cancel</button>
                <button id="page-save" class="primary-btn" type="button">Save Page</button>
            </div>
        </div>
    `;

    showEditorModal();

    const allowedContainer = document.getElementById('page-allowed-jobs');
    renderAllowedJobs(allowedContainer, allowedJobs);
    bindPermissionSection('page-perm-enabled', 'page-allowed-jobs-section');

    document.getElementById('page-add-job').addEventListener('click', async () => {
        const selected = await openJobModal();
        if (!selected) return;

        const existing = allowedJobs.find((job) => job.job === selected.job);
        if (existing) {
            existing.minGrade = selected.minGrade;
        } else {
            allowedJobs.push(selected);
        }

        renderAllowedJobs(allowedContainer, allowedJobs);
    });

    const editorRoot = document.getElementById('page-editor-root');
    setupEditorTools(editorRoot);

    document.getElementById('page-cancel').addEventListener('click', hideEditorModal);

    document.getElementById('page-save').addEventListener('click', async () => {
        const payload = {
            id: record.id,
            categoryId: document.getElementById('page-category').value,
            label: document.getElementById('page-label').value,
            key: document.getElementById('page-key').value,
            order: Number(document.getElementById('page-order').value || 0),
            enabled: document.getElementById('page-enabled').checked,
            permissionsEnabled: document.getElementById('page-perm-enabled').checked,
            allowedJobs,
            content: document.getElementById('page-editor-body').innerHTML
        };

        const response = await postNui('savePage', payload);
        if (!response.ok) {
            showToast(getErrorText(response, 'Page save failed.'), 'error');
            return;
        }

        hideEditorModal();
        applyServerRefresh(response);
        showToast('Page saved.', 'success');

        if (response.pageKey) {
            state.selectedPageKey = response.pageKey;
            renderSidebar();
            renderContent();
        }
    });
}

function applyServerRefresh(response) {
    if (response.visibleData) {
        state.visibleData = response.visibleData;
    }

    if (response.adminData) {
        state.adminData = response.adminData;
    }

    renderAll();
}

function bindStaticEvents() {
    el.contentClose.addEventListener('click', () => {
        requestCloseApp({ notifyGame: true, animate: true });
    });

    el.contentBack.addEventListener('click', () => {
        setSearchQuery('', true);
    });

    el.searchBtn.addEventListener('click', () => {
        setSearchQuery(el.searchInput.value, true);
    });

    el.searchClear.addEventListener('click', () => {
        setSearchQuery('', true);
        el.searchInput.focus();
    });

    el.searchInput.addEventListener('keydown', (event) => {
        if (event.key === 'Enter') {
            setSearchQuery(el.searchInput.value, true);
        }
    });

    el.searchInput.addEventListener('input', () => {
        setSearchQuery(el.searchInput.value, true);
    });

    el.sidebarAdmin.addEventListener('click', () => showAdminPanel());
    el.contentAdmin.addEventListener('click', () => showAdminPanel());

    el.adminClose.addEventListener('click', hideAdminPanel);

    el.adminTabCategories.addEventListener('click', () => {
        state.adminTab = 'categories';
        renderAdminSection();
    });

    el.adminTabPages.addEventListener('click', () => {
        state.adminTab = 'pages';
        renderAdminSection();
    });

    el.adminFilter.addEventListener('input', () => {
        state.adminFilter = el.adminFilter.value;
        renderAdminSection();
    });

    el.adminFilter.addEventListener('keydown', (event) => {
        if (event.key === 'Escape') {
            el.adminFilter.value = '';
            state.adminFilter = '';
            renderAdminSection();
        }
    });

    el.adminCreate.addEventListener('click', () => {
        if (state.adminTab === 'categories') {
            openCategoryEditor(null);
        } else {
            openPageEditor(null);
        }
    });

    el.editorClose.addEventListener('click', hideEditorModal);

    el.jobClose.addEventListener('click', () => resolveJobModal(null));
    el.jobCancel.addEventListener('click', () => resolveJobModal(null));
    el.jobAdd.addEventListener('click', () => {
        if (el.jobAdd.disabled) {
            resolveJobModal(null);
            return;
        }

        const selected = {
            job: el.jobSelect.value,
            minGrade: Number(el.jobGradeSelect.value || 0)
        };
        resolveJobModal(selected);
    });

    el.gpsClose.addEventListener('click', () => resolveGpsModal(null));
    el.gpsCancel.addEventListener('click', () => resolveGpsModal(null));
    el.gpsAdd.addEventListener('click', () => {
        const label = el.gpsLabel.value.trim();
        const x = Number(el.gpsX.value);
        const y = Number(el.gpsY.value);

        if (!label || Number.isNaN(x) || Number.isNaN(y)) {
            showToast('Please enter valid GPS label, X and Y coordinates.', 'error');
            return;
        }

        resolveGpsModal({ label, x, y });
    });

    el.emojiClose.addEventListener('click', () => resolveEmojiModal(null));
    el.emojiCancel.addEventListener('click', () => resolveEmojiModal(null));

    el.emojiSearch.addEventListener('input', () => {
        renderEmojiGrid(el.emojiSearch.value);
    });

    el.emojiSearch.addEventListener('keydown', (event) => {
        if (event.key !== 'Enter') {
            return;
        }

        const first = el.emojiGrid.querySelector('.emoji-choice');
        if (first) {
            first.click();
        }
    });

    document.addEventListener('keydown', async (event) => {
        if (event.key !== 'Escape') {
            return;
        }

        if (!state.open) {
            return;
        }

        if (!el.emojiModal.classList.contains('hidden')) {
            resolveEmojiModal(null);
            return;
        }

        if (!el.gpsModal.classList.contains('hidden')) {
            resolveGpsModal(null);
            return;
        }

        if (!el.jobModal.classList.contains('hidden')) {
            resolveJobModal(null);
            return;
        }

        if (!el.editorModal.classList.contains('hidden')) {
            hideEditorModal();
            return;
        }

        if (!el.adminPanel.classList.contains('hidden')) {
            hideAdminPanel();
            return;
        }

        requestCloseApp({ notifyGame: true, animate: true });
    });
}

function openWithPayload(payload) {
    state.isAdmin = payload.isAdmin === true;
    state.adminMode = payload.openAdmin === true;
    state.visibleData = payload.visibleData || { categories: [] };
    state.adminData = payload.adminData || null;
    state.adminFilter = '';
    if (el.adminFilter) {
        el.adminFilter.value = '';
    }
    setSearchQuery('', false);

    state.selectedPageKey = payload.pageKey || getFirstVisiblePageKey();

    showApp();
    renderAll();

    if (state.adminMode && state.isAdmin) {
        showAdminPanel();
    }
}

window.addEventListener('message', (event) => {
    const data = event.data || {};

    if (data.action === 'open' && data.payload) {
        openWithPayload(data.payload);
        return;
    }

    if (data.action === 'close') {
        requestCloseApp({ notifyGame: false, animate: true });
    }
});

function init() {
    el.app = document.getElementById('guidebook-app');
    el.categoryList = document.getElementById('category-list');
    el.statCategories = document.getElementById('stat-categories');
    el.statPages = document.getElementById('stat-pages');
    el.searchInput = document.getElementById('search-input');
    el.searchClear = document.getElementById('search-clear');
    el.searchBtn = document.getElementById('search-btn');
    el.sidebarAdmin = document.getElementById('sidebar-admin');
    el.contentAdmin = document.getElementById('content-admin');
    el.contentClose = document.getElementById('content-close');
    el.contentBack = document.getElementById('content-back');
    el.contentTitle = document.getElementById('content-title');
    el.contentSubtitle = document.getElementById('content-subtitle');
    el.contentBody = document.getElementById('content-body');

    el.adminPanel = document.getElementById('admin-panel');
    el.adminClose = document.getElementById('admin-close');
    el.adminTabCategories = document.getElementById('admin-tab-categories');
    el.adminTabPages = document.getElementById('admin-tab-pages');
    el.adminFilter = document.getElementById('admin-filter');
    el.adminCount = document.getElementById('admin-count');
    el.adminCreate = document.getElementById('admin-create');
    el.adminSectionTitle = document.getElementById('admin-section-title');
    el.adminList = document.getElementById('admin-list');

    el.editorModal = document.getElementById('editor-modal');
    el.editorTitle = document.getElementById('editor-title');
    el.editorBody = document.getElementById('editor-body');
    el.editorClose = document.getElementById('editor-close');

    el.jobModal = document.getElementById('job-modal');
    el.jobSelect = document.getElementById('job-select');
    el.jobGradeSelect = document.getElementById('job-grade-select');
    el.jobClose = document.getElementById('job-close');
    el.jobCancel = document.getElementById('job-cancel');
    el.jobAdd = document.getElementById('job-add');

    el.gpsModal = document.getElementById('gps-modal');
    el.gpsLabel = document.getElementById('gps-label');
    el.gpsX = document.getElementById('gps-x');
    el.gpsY = document.getElementById('gps-y');
    el.gpsClose = document.getElementById('gps-close');
    el.gpsCancel = document.getElementById('gps-cancel');
    el.gpsAdd = document.getElementById('gps-add');

    el.emojiModal = document.getElementById('emoji-modal');
    el.emojiTitle = document.getElementById('emoji-title');
    el.emojiSearch = document.getElementById('emoji-search');
    el.emojiGrid = document.getElementById('emoji-grid');
    el.emojiClose = document.getElementById('emoji-close');
    el.emojiCancel = document.getElementById('emoji-cancel');

    el.toastStack = document.getElementById('toast-stack');

    bindStaticEvents();
}

document.addEventListener('DOMContentLoaded', init);
