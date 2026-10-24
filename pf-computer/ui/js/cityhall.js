// City Hall App Logic for pf-computer
// Only loaded/active for mayor

const CITYHALL_APP_ID = 'city-hall';
const cityHallWindow = document.getElementById('city-hall-window');
const cityHallIcon = document.querySelector('.icon[data-app="city-hall"]');
const cityHallTile = document.querySelector('.start-app-tile[data-app="city-hall"]');

// Show icon/tile only for mayor (replace with real check)
function showCityHallAppForMayor(isMayor) {
    if (isMayor) {
        cityHallIcon && (cityHallIcon.style.display = '');
        cityHallTile && (cityHallTile.style.display = '');
    } else {
        cityHallIcon && (cityHallIcon.style.display = 'none');
        cityHallTile && (cityHallTile.style.display = 'none');
    }
}

// Open/close handlers
function openCityHallWindow() {
    if (!cityHallWindow) return;
    cityHallWindow.style.display = 'flex';
    cityHallWindow.classList.add('active');
    // Load dashboard by default
    loadCityHallPage('dashboard');
}

function closeCityHallWindow() {
    if (!cityHallWindow) return;
    cityHallWindow.style.display = 'none';
    cityHallWindow.classList.remove('active');
}

// Navigation
const navItems = cityHallWindow ? cityHallWindow.querySelectorAll('.cityhall-nav-item') : [];
navItems.forEach(item => {
    item.addEventListener('click', () => {
        navItems.forEach(i => i.classList.remove('active'));
        item.classList.add('active');
        loadCityHallPage(item.dataset.page);
    });
});

// Window controls
if (cityHallWindow) {
    cityHallWindow.querySelector('.window-btn.close').addEventListener('click', closeCityHallWindow);
    cityHallWindow.querySelector('.window-btn.minimize').addEventListener('click', () => cityHallWindow.style.display = 'none');
    cityHallWindow.querySelector('.window-btn.maximize').addEventListener('click', () => cityHallWindow.classList.toggle('maximized'));
}

// Desktop icon/start menu tile open
cityHallIcon && cityHallIcon.addEventListener('dblclick', openCityHallWindow);
cityHallTile && cityHallTile.addEventListener('click', openCityHallWindow);

// Main content loader
function loadCityHallPage(page) {
    const main = document.getElementById('cityhall-main-content');
    if (!main) return;
    main.innerHTML = '<div class="loading">Loading...</div>';
    if (page === 'dashboard') {
        loadCityHallDashboard(main);
    } else if (page === 'announcements') {
        loadCityHallAnnouncements(main);
    } else if (page === 'laws') {
        loadCityHallLaws(main);
    } else if (page === 'taxes') {
        loadCityHallTaxes(main);
    } else {
        main.innerHTML = '<div>Unknown page</div>';
    }
}

// Example NUI requests to pf-government
async function loadCityHallDashboard(main) {
    const res = await nuiRequest('pf-government:getDashboard', {});
    if (res.ok) {
        main.innerHTML = `<h2>Dashboard</h2><pre>${JSON.stringify(res.data, null, 2)}</pre>`;
    } else {
        main.innerHTML = '<div class="error">Failed to load dashboard</div>';
    }
}

async function loadCityHallAnnouncements(main) {
    const res = await nuiRequest('pf-government:getAnnouncements', {});
    if (res.ok) {
        main.innerHTML = `<h2>Announcements</h2><pre>${JSON.stringify(res.data, null, 2)}</pre>`;
    } else {
        main.innerHTML = '<div class="error">Failed to load announcements</div>';
    }
}

async function loadCityHallLaws(main) {
    const res = await nuiRequest('pf-government:getLaws', {});
    if (res.ok) {
        main.innerHTML = `<h2>Laws & Policy</h2><pre>${JSON.stringify(res.data, null, 2)}</pre>`;
    } else {
        main.innerHTML = '<div class="error">Failed to load laws</div>';
    }
}

async function loadCityHallTaxes(main) {
    const res = await nuiRequest('pf-government:getTaxes', {});
    if (res.ok) {
        main.innerHTML = `<h2>Taxes & Fees</h2><pre>${JSON.stringify(res.data, null, 2)}</pre>`;
    } else {
        main.innerHTML = '<div class="error">Failed to load taxes</div>';
    }
}

// TODO: Replace isMayor check with real logic from player data
window.addEventListener('DOMContentLoaded', async () => {
    // Example: fetch player data and check if mayor
    const player = await hydratePlayerProfile();
    const isMayor = player && player.job === 'mayor';
    showCityHallAppForMayor(isMayor);
});
