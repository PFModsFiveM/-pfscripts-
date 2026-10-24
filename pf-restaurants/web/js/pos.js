// POS JavaScript
let currentBusiness = null;
let currentMenu = [];
let currentOrder = [];
let currentCategory = 'all';
let currentTaxRate = 0.0;

$(document).ready(function() {
    window.addEventListener('message', function(event) {
        const data = event.data;
        
        if (data.action === 'openPOS') {
            currentBusiness = data.businessId;
            currentMenu = data.menu || {};
            currentTaxRate = data.taxRate || 0.0;
            openPOS();
        }
    });
    
    $('#close-btn').click(function() {
        closePOS();
    });
    
    $('#complete-order').click(function() {
        completeOrder();
    });
    
    $('#void-order').click(function() {
        currentOrder = [];
        updateOrderDisplay();
    });
    
    document.addEventListener('keydown', function(event) {
        if (event.key === 'Escape') {
            closePOS();
        }
    });
});

function openPOS() {
    $('#pos-container').removeClass('hidden');
    loadCategories();
    loadMenuItems();
    updateOrderDisplay();
}

function closePOS() {
    $('#pos-container').addClass('hidden');
    $.post('https://pf-restaurants/closePOS', JSON.stringify({}));
}

function loadCategories() {
    const categories = new Set();
    for (let itemId in currentMenu) {
        if (currentMenu[itemId].category) {
            categories.add(currentMenu[itemId].category);
        }
    }
    
    let html = '<button class="category-btn active" data-category="all">All</button>';
    categories.forEach(cat => {
        html += `<button class="category-btn" data-category="${cat}">${cat}</button>`;
    });
    
    $('#categories').html(html);
    
    $('.category-btn').click(function() {
        $('.category-btn').removeClass('active');
        $(this).addClass('active');
        currentCategory = $(this).data('category');
        loadMenuItems();
    });
}

function loadMenuItems() {
    let html = '';
    
    for (let itemId in currentMenu) {
        const item = currentMenu[itemId];
        
        if (currentCategory !== 'all' && item.category !== currentCategory) {
            continue;
        }
        
        if (!item.enabled) {
            continue;
        }
        
        html += `
            <div class="menu-item" data-item-id="${itemId}">
                <h3>${item.displayName}</h3>
                <div class="price">$${item.price.toFixed(2)}</div>
            </div>
        `;
    }
    
    $('#menu-items').html(html);
    
    $('.menu-item').click(function() {
        const itemId = $(this).data('item-id');
        addToOrder(itemId);
    });
}

function addToOrder(itemId) {
    const item = currentMenu[itemId];
    if (!item) return;
    
    currentOrder.push({
        menuItemId: itemId,
        recipeId: item.recipeId,
        displayName: item.displayName,
        price: item.price,
        qty: 1,
        mods: {}
    });
    
    updateOrderDisplay();
}

function updateOrderDisplay() {
    let html = '';
    let subtotal = 0;
    
    currentOrder.forEach((item, index) => {
        subtotal += item.price * item.qty;
        
        html += `
            <div class="order-item">
                <div>
                    <strong>${item.displayName}</strong> x${item.qty}
                    <div>$${(item.price * item.qty).toFixed(2)}</div>
                </div>
                <button class="order-item-remove" data-index="${index}">×</button>
            </div>
        `;
    });
    
    $('#order-items').html(html);
    
    $('.order-item-remove').click(function() {
        const index = $(this).data('index');
        currentOrder.splice(index, 1);
        updateOrderDisplay();
    });
    
    const tax = subtotal * currentTaxRate;
    const total = subtotal + tax;
    
    $('#subtotal').text('$' + subtotal.toFixed(2));
    $('#tax').text('$' + tax.toFixed(2));
    $('#total').text('$' + total.toFixed(2));
}

function completeOrder() {
    if (currentOrder.length === 0) {
        return;
    }
    
    const subtotal = currentOrder.reduce((sum, item) => sum + (item.price * item.qty), 0);
    const tax = subtotal * currentTaxRate;
    const total = subtotal + tax;
    
    $.post('https://pf-restaurants/createOrder', JSON.stringify({
        businessId: currentBusiness,
        items: currentOrder,
        channel: $('#order-channel').val(),
        subtotal: subtotal,
        tax: tax,
        total: total,
        paymentMethod: $('#payment-method').val()
    }), function(response) {
        if (response.success) {
            currentOrder = [];
            updateOrderDisplay();
        }
    });
}
