// KDS JavaScript
// Tickets come from the server (only to the restaurant's staff on shift); every string on them is
// put in the page as text.
let orders = {};

// HTML-escapes a value for text and attribute positions (textContent does &, < and >; quotes too)
function esc(value) {
    const div = document.createElement('div');
    div.textContent = value == null ? '' : String(value);
    return div.innerHTML.replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

$(document).ready(function() {
    updateTime();
    setInterval(updateTime, 1000);

    window.addEventListener('message', function(event) {
        const data = event.data;
        if (!data) return;

        if (data.action === 'newOrder') {
            addOrder(data.order);
        } else if (data.action === 'updateOrderStatus') {
            updateOrderStatus(data.orderId, data.status);
        } else if (data.action === 'setOrders') {
            // a shift started (the open tickets) or ended (none)
            orders = {};
            (Array.isArray(data.orders) ? data.orders : []).forEach(o => {
                if (o && typeof o.orderId === 'string') orders[o.orderId] = o;
            });
            renderOrders();
        }
    });
});

function updateTime() {
    const now = new Date();
    const timeStr = now.toLocaleTimeString();
    $('#kds-time').text(timeStr);
}

function addOrder(order) {
    if (!order || typeof order.orderId !== 'string') return;
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
    const elapsed = Math.floor((Date.now() - (Number(order.placedAt) || 0) * 1000) / 1000);
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
    (Array.isArray(order.items) ? order.items : []).forEach(item => {
        if (!item) return;
        itemsHtml += `
            <div class="ticket-item">
                <strong>${esc(Number(item.qty) || 1)}x ${esc(item.displayName || item.recipeId)}</strong>
                ${item.mods ? '<div class="item-mods">' + esc(JSON.stringify(item.mods)) + '</div>' : ''}
            </div>
        `;
    });

    return $(`
        <div class="order-ticket ${urgencyClass}">
            <div class="ticket-header">
                <span>Order #${esc(String(order.orderId).split('-').pop())}</span>
                <span class="ticket-time">${minutes}:${seconds.toString().padStart(2, '0')}</span>
            </div>
            <div class="ticket-items">
                ${itemsHtml}
            </div>
        </div>
    `);
}
