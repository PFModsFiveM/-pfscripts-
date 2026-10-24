// KDS JavaScript
let orders = {};

$(document).ready(function() {
    updateTime();
    setInterval(updateTime, 1000);
    
    window.addEventListener('message', function(event) {
        const data = event.data;
        
        if (data.action === 'newOrder') {
            addOrder(data.order);
        } else if (data.action === 'updateOrderStatus') {
            updateOrderStatus(data.orderId, data.status);
        }
    });
});

function updateTime() {
    const now = new Date();
    const timeStr = now.toLocaleTimeString();
    $('#kds-time').text(timeStr);
}

function addOrder(order) {
    orders[order.orderId] = order;
    renderOrders();
}

function updateOrderStatus(orderId, newStatus) {
    if (orders[orderId]) {
        orders[orderId].status = newStatus;
        renderOrders();
    }
}

function renderOrders() {
    $('#new-orders').empty();
    
    for (let orderId in orders) {
        const order = orders[orderId];
        
        // Only show pending orders (placed/accepted status)
        if (order.status !== 'placed' && order.status !== 'accepted') {
            delete orders[orderId];
            continue;
        }
        
        const ticket = createTicket(order);
        
        // If ticket is null (expired), skip it
        if (ticket) {
            $('#new-orders').append(ticket);
        }
    }
}

function createTicket(order) {
    const elapsed = Math.floor((Date.now() - order.placedAt * 1000) / 1000);
    const minutes = Math.floor(elapsed / 60);
    const seconds = elapsed % 60;
    
    // Auto-expire after 2 minutes (120 seconds)
    if (elapsed > 120) {
        delete orders[order.orderId];
        return null;
    }
    
    let urgencyClass = '';
    if (elapsed > 90) urgencyClass = 'critical';  // Last 30 seconds
    else if (elapsed > 60) urgencyClass = 'warning'; // Last minute
    
    let itemsHtml = '';
    order.items.forEach(item => {
        itemsHtml += `
            <div class="ticket-item">
                <strong>${item.qty}x ${item.displayName || item.recipeId}</strong>
                ${item.mods ? '<div class="item-mods">' + JSON.stringify(item.mods) + '</div>' : ''}
            </div>
        `;
    });
    
    return $(`
        <div class="order-ticket ${urgencyClass}">
            <div class="ticket-header">
                <span>Order #${order.orderId.split('-').pop()}</span>
                <span class="ticket-time">${minutes}:${seconds.toString().padStart(2, '0')}</span>
            </div>
            <div class="ticket-items">
                ${itemsHtml}
            </div>
        </div>
    `);
}
