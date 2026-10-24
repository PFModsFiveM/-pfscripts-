// Menu Board JavaScript
let businessId = null;
let menu = {};

$(document).ready(function() {
    const urlParams = new URLSearchParams(window.location.search);
    businessId = urlParams.get('businessId');
    
    loadMenu();
    
    window.addEventListener('message', function(event) {
        const data = event.data;
        
        if (data.action === 'updateMenu') {
            menu = data.menu;
            renderMenu();
        }
    });
});

function loadMenu() {
    // Request menu from server via DUI message
    // For now, using placeholder
    setTimeout(renderMenu, 1000);
}

function renderMenu() {
    const categories = {};
    
    for (let itemId in menu) {
        const item = menu[itemId];
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
                <h2 class="category-title">${category}</h2>
                <div class="category-items">
        `;
        
        categories[category].forEach(item => {
            const unavailable = !item.enabled ? ' item-unavailable' : '';
            
            html += `
                <div class="menu-board-item${unavailable}">
                    <div>
                        <div class="item-name">${item.displayName}</div>
                        ${item.description ? '<div class="item-description">' + item.description + '</div>' : ''}
                    </div>
                    <div class="item-price">$${item.price.toFixed(2)}</div>
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
