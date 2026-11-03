// Menu Board JavaScript
// Every menu string (category, name, description) is put in the page as text: the board runs on
// every client near the restaurant, so a name must never become markup or load anything.
let businessId = null;
let menu = {};

// HTML-escapes a value for text and attribute positions (textContent does &, < and >; quotes too)
function esc(value) {
    const div = document.createElement('div');
    div.textContent = value == null ? '' : String(value);
    return div.innerHTML.replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function money(value) {
    const n = Number(value);
    return Number.isFinite(n) ? n.toFixed(2) : '0.00';
}

$(document).ready(function() {
    const urlParams = new URLSearchParams(window.location.search);
    businessId = urlParams.get('businessId');

    // the client sends the menu ('updateMenu') when a player comes near and whenever it changes
    renderMenu();

    window.addEventListener('message', function(event) {
        const data = event.data;

        if (data && data.action === 'updateMenu') {
            menu = (data.menu && typeof data.menu === 'object') ? data.menu : {};
            renderMenu();
        }
    });
});

function renderMenu() {
    const categories = {};

    for (let itemId in menu) {
        const item = menu[itemId];
        if (!item || typeof item !== 'object') continue;
        const cat = item.category || 'Other';

        if (!categories[cat]) {
            categories[cat] = [];
        }

        categories[cat].push(item);
    }

    let html = '';

    for (let category in categories) {
        html += `
            <div class="menu-category">
                <h2 class="category-title">${esc(category)}</h2>
                <div class="category-items">
        `;

        categories[category].forEach(item => {
            const unavailable = !item.enabled ? ' item-unavailable' : '';

            html += `
                <div class="menu-board-item${unavailable}">
                    <div>
                        <div class="item-name">${esc(item.displayName)}</div>
                        ${item.description ? '<div class="item-description">' + esc(item.description) + '</div>' : ''}
                    </div>
                    <div class="item-price">$${money(item.price)}</div>
                </div>
            `;
        });

        html += `
                </div>
            </div>
        `;
    }

    $('#menu-categories').html(html);
}
