// Rental System Variables
let currentCategory = 'all';
let selectedVehicle = null;
let vehicles = [];
let categories = [];

// Sample vehicle data - will be replaced with server data
const sampleRentalVehicles = [
    {
        id: 1,
        brand: 'Grotti',
        model: 'Turismo R',
        displayName: 'Grotti Turismo R',
        category: 'sports',
        price: 500,
        image: 'screenshot:https://via.placeholder.com/400x300?text=Turismo+R'
    },
    {
        id: 2,
        brand: 'Vapid',
        model: 'Dominator GTX',
        displayName: 'Vapid Dominator GTX',
        category: 'muscle',
        price: 400,
        image: 'screenshot:https://via.placeholder.com/400x300?text=Dominator'
    },
    {
        id: 3,
        brand: 'Coil',
        model: 'Roadster',
        displayName: 'Coil Roadster',
        category: 'sports',
        price: 600,
        image: 'screenshot:https://via.placeholder.com/400x300?text=Roadster'
    },
    {
        id: 4,
        brand: 'Declasse',
        model: 'Granger',
        displayName: 'Declasse Granger',
        category: 'trucks',
        price: 300,
        image: 'screenshot:https://via.placeholder.com/400x300?text=Granger'
    },
    {
        id: 5,
        brand: 'Benefactor',
        model: 'Schafter',
        displayName: 'Benefactor Schafter',
        category: 'sedan',
        price: 350,
        image: 'screenshot:https://via.placeholder.com/400x300?text=Schafter'
    },
    {
        id: 6,
        brand: 'BF Injection',
        model: 'Dune Buggy',
        displayName: 'BF Injection Dune Buggy',
        category: 'offroad',
        price: 280,
        image: 'screenshot:https://via.placeholder.com/400x300?text=Dune+Buggy'
    },
    {
        id: 7,
        brand: 'Ducatti',
        model: 'Monster',
        displayName: 'Ducatti Monster',
        category: 'motorcycles',
        price: 200,
        image: 'screenshot:https://via.placeholder.com/400x300?text=Monster'
    },
    {
        id: 8,
        brand: 'Pfister',
        model: '811',
        displayName: 'Pfister 811',
        category: 'sports',
        price: 750,
        image: 'screenshot:https://via.placeholder.com/400x300?text=Pfister+811'
    }
];

// Initialize the Rental UI
function initializeRentalUI() {
    // For now, use sample data; later this will come from the server
    vehicles = sampleRentalVehicles;
    
    // Extract unique categories
    categories = ['all', ...new Set(vehicles.map(v => v.category))];
    
    renderCategories();
    renderVehicles();
    setupCategoryScrolling();
    
    // Listen for messages from the server
    window.addEventListener('message', (event) => {
        const data = event.data;
        
        if (data.action === 'openRentalUI') {
            vehicles = data.vehicles || sampleRentalVehicles;
            categories = ['all', ...new Set(vehicles.map(v => v.category))];
            renderCategories();
            renderVehicles();
            setupCategoryScrolling();
            showRentalUI();
        } else if (data.action === 'closeRentalUI') {
            closeRentalUI();
        }
    });
}

// Render category buttons
function renderCategories() {
    const categoriesList = document.getElementById('categoriesList');
    categoriesList.innerHTML = '';
    
    categories.forEach(category => {
        const btn = document.createElement('button');
        btn.className = 'category-btn' + (category === currentCategory ? ' active' : '');
        btn.textContent = capitalizeFirstLetter(category);
        btn.onclick = () => selectCategory(category);
        categoriesList.appendChild(btn);
    });
}

// Select a category
function selectCategory(category) {
    currentCategory = category;
    renderCategories();
    renderVehicles();
}

// Render vehicles grid
function renderVehicles() {
    const vehiclesGrid = document.getElementById('vehiclesGrid');
    vehiclesGrid.innerHTML = '';
    
    const filteredVehicles = currentCategory === 'all' 
        ? vehicles 
        : vehicles.filter(v => v.category === currentCategory);
    
    filteredVehicles.forEach(vehicle => {
        const card = document.createElement('div');
        card.className = 'vehicle-card';
        card.onclick = () => selectVehicleForRental(vehicle);
        
        card.innerHTML = `
            <div class="vehicle-image">
                <img src="${vehicle.image}" alt="${vehicle.displayName}" onerror="this.src='data:image/svg+xml,%3Csvg xmlns=%22http://www.w3.org/2000/svg%22 width=%22100%22 height=%22100%22%3E%3Crect fill=%22%23334155%22 width=%22100%22 height=%22100%22/%3E%3Ctext x=%2250%25%22 y=%2250%25%22 dominant-baseline=%22middle%22 text-anchor=%22middle%22 font-family=%22Arial%22 font-size=%2212%22 fill=%22%2394a3b8%22%3E${vehicle.displayName}%3C/text%3E%3C/svg%3E'">
            </div>
            <div class="vehicle-details">
                <div class="vehicle-name">${vehicle.displayName}</div>
                <div class="vehicle-model">${vehicle.brand} · ${vehicle.model}</div>
                <div class="vehicle-price">$${vehicle.price}/day</div>
            </div>
        `;
        
        vehiclesGrid.appendChild(card);
    });
}

// Setup category list scrolling with mouse wheel
function setupCategoryScrolling() {
    const categoriesList = document.getElementById('categoriesList');
    
    categoriesList.addEventListener('wheel', (event) => {
        event.preventDefault();
        categoriesList.scrollLeft += event.deltaY > 0 ? 100 : -100;
    });
}

// Select a vehicle for rental
function selectVehicleForRental(vehicle) {
    selectedVehicle = vehicle;
    
    // Update modal with vehicle info
    document.getElementById('modalVehicleName').textContent = vehicle.displayName;
    document.getElementById('modalVehicleModel').textContent = `${vehicle.brand} · ${vehicle.model}`;
    document.getElementById('priceAmount').textContent = vehicle.price;
    document.getElementById('dailyRate').textContent = vehicle.price;
    document.getElementById('modalVehicleImage').src = vehicle.image;
    
    // Reset duration to 1 day
    document.getElementById('durationInput').value = 1;
    updateTotalPrice();
    
    // Show modal
    openRentalModal();
}

// Update total price based on duration
function updateTotalPrice() {
    if (!selectedVehicle) return;
    
    const duration = parseInt(document.getElementById('durationInput').value) || 1;
    const totalPrice = selectedVehicle.price * duration;
    
    document.getElementById('totalPrice').textContent = totalPrice;
    document.getElementById('durationDisplay').textContent = duration === 1 ? '1 day' : `${duration} days`;
}

// Increase duration
function increaseDuration() {
    const input = document.getElementById('durationInput');
    const currentValue = parseInt(input.value) || 1;
    
    if (currentValue < 30) {
        input.value = currentValue + 1;
        updateTotalPrice();
    }
}

// Decrease duration
function decreaseDuration() {
    const input = document.getElementById('durationInput');
    const currentValue = parseInt(input.value) || 1;
    
    if (currentValue > 1) {
        input.value = currentValue - 1;
        updateTotalPrice();
    }
}

// Confirm rental
function confirmRental() {
    if (!selectedVehicle) return;
    
    const duration = parseInt(document.getElementById('durationInput').value) || 1;
    const totalPrice = selectedVehicle.price * duration;
    
    // Send rental confirmation to server
    fetch(`https://${GetParentResourceName()}/confirmRental`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({
            vehicleId: selectedVehicle.id,
            vehicleName: selectedVehicle.displayName,
            modelName: selectedVehicle.model,
            brand: selectedVehicle.brand,
            duration: duration,
            totalPrice: totalPrice,
            dailyRate: selectedVehicle.price
        })
    })
    .then(response => {
        // Close the modal and UI immediately without waiting for response
        closeRentalModal();
        closeRentalUI();
        console.log('Rental request sent!');
        return response.json();
    })
    .then(data => {
        console.log('Rental response:', data);
    })
    .catch(error => console.error('Error:', error));
}

// Open rental modal
function openRentalModal() {
    document.getElementById('rentalModal').classList.add('active');
    document.getElementById('rentalModalOverlay').classList.add('active');
}

// Close rental modal
function closeRentalModal() {
    document.getElementById('rentalModal').classList.remove('active');
    document.getElementById('rentalModalOverlay').classList.remove('active');
    selectedVehicle = null;
}

// Show rental UI
function showRentalUI() {
    document.getElementById('rentalContainer').style.display = 'flex';
}

// Close rental UI
function closeRentalUI() {
    document.getElementById('rentalContainer').style.display = 'none';
    closeRentalModal();
}

// Helper function to capitalize first letter
function capitalizeFirstLetter(str) {
    return str.charAt(0).toUpperCase() + str.slice(1);
}

// Get parent resource name (FiveM function)
function GetParentResourceName() {
    return window.__RESOURCE_NAME__ || 'pf-rentals';
}

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', initializeRentalUI);
