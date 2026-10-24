// ============================================================================
// ADVANCED TAXI DISPATCH SYSTEM
// ============================================================================

let taxiDispatchData = {
    onDuty: false,
    inCertifiedVehicle: false,
    vehicleType: null, // 'taxi', 'private'
    activeRide: null,
    incomingCalls: [],
    level: 1,
    xp: 0,
    xpNeeded: 100,
    reputation: 100,
    streak: 0,
    dailyRides: 0,
    totalRides: 0,
    totalEarnings: 0,
    totalDistance: 0,
    totalCollisions: 0,
    avgRating: 5.0,
    bestStreak: 0,
    playerRequests: 0,
    npcRequests: 0,
    perfectRides: 0,
    ownedVehicles: ['private-cab'], // Premium unlocks
    rentedVehicle: null,
    currentRankIndex: 0,
    challenges: [],
    vehicles: [
        { id: 'taxi', name: 'Downtown Taxi', tier: 1, rental: 100, deposit: 250, unlockLevel: 1, image: '🚕' },
        { id: 'taxi2', name: 'Comfort Cab', tier: 2, rental: 150, deposit: 400, unlockLevel: 2, image: '🚕' },
        { id: 'minivan', name: 'Family Minivan', tier: 3, rental: 200, deposit: 500, unlockLevel: 3, image: '🚐' },
        { id: 'electric', name: 'Eco Electric', tier: 4, rental: 250, deposit: 600, unlockLevel: 4, image: '🚗' },
        { id: 'limo', name: 'Executive Limo', tier: 5, rental: 400, deposit: 1000, unlockLevel: 5, image: '🚙' },
        { id: 'mercedes', name: 'Luxury Sedan', tier: 6, rental: 500, deposit: 1500, unlockLevel: 6, image: '🚘' },
        { id: 'private-cab', name: 'Private Cab', tier: 7, rental: 0, deposit: 0, unlockLevel: 7, image: '🚖' }
    ],
    ranks: [
        { name: 'Novice Driver', level: 1, xpRequired: 0, multiplier: 1.0, unlocks: ['Downtown Taxi'] },
        { name: 'Experienced Driver', level: 2, xpRequired: 100, multiplier: 1.1, unlocks: ['Comfort Cab'] },
        { name: 'Licensed Operator', level: 3, xpRequired: 300, multiplier: 1.25, unlocks: ['Family Minivan'] },
        { name: 'Professional', level: 4, xpRequired: 600, multiplier: 1.4, unlocks: ['Eco Electric'] },
        { name: 'Elite Driver', level: 5, xpRequired: 1000, multiplier: 1.6, unlocks: ['Executive Limo'] },
        { name: 'VIP Specialist', level: 6, xpRequired: 1500, multiplier: 1.8, unlocks: ['Luxury Sedan'] },
        { name: 'Fleet Owner', level: 7, xpRequired: 2500, multiplier: 2.0, unlocks: ['Private Cab'] }
    ]
};

// Initialize Taxi System
function initializeTaxiSystem() {
    generateDailyChallenges();
    generateLevelChallenges();
    renderVehiclesCatalog();
    renderRankCards();
    updateTaxiUI();
    
    // FOR TESTING: Simulate being in a vehicle
    // Comment out when integrating with backend
    setTimeout(() => {
        updateTaxiVehicleStatus(true, 'taxi');
    }, 1000);
    
    // Update challenge timer every second
    setInterval(updateChallengeTimer, 1000);
}

// Update Vehicle Status (called from backend)
function updateTaxiVehicleStatus(inVehicle, vehicleType) {
    taxiDispatchData.inCertifiedVehicle = inVehicle;
    taxiDispatchData.vehicleType = vehicleType;
    
    const vehicleStatus = document.getElementById('taxi-vehicle-status');
    const vehicleText = vehicleStatus.querySelector('.vehicle-text');
    
    if (inVehicle) {
        vehicleStatus.classList.add('certified');
        vehicleText.textContent = `Certified: ${getSanitizedVehicleName(vehicleType)}`;
    } else {
        vehicleStatus.classList.remove('certified');
        vehicleText.textContent = 'Enter a certified vehicle';
    }
}

// Get sanitized vehicle name for display
function getSanitizedVehicleName(vehicleType) {
    const vehicle = taxiDispatchData.vehicles.find(v => v.id === vehicleType);
    return vehicle ? vehicle.name : 'Taxi';
}

// Toggle Duty
function toggleTaxiDuty() {
    if (!taxiDispatchData.onDuty) {
        // Check if in certified vehicle
        if (!taxiDispatchData.inCertifiedVehicle) {
            // Show error - must be in vehicle
            console.log('Must be in a certified vehicle');
            return;
        }
        
        taxiDispatchData.onDuty = true;
        taxiDispatchData.dailyRides = 0; // Reset daily counter
        
        // Update UI
        document.getElementById('taxi-duty-btn').textContent = 'GO OFF DUTY';
        document.getElementById('taxi-duty-btn').classList.remove('duty-btn-on');
        document.getElementById('taxi-duty-btn').classList.add('duty-btn-off');
        
        const dutyIndicator = document.querySelector('.duty-status-indicator');
        dutyIndicator.classList.remove('off');
        dutyIndicator.classList.add('on');
        dutyIndicator.innerHTML = '<span class="status-dot"></span> ON DUTY';
        
        document.getElementById('taxi-calls-status').textContent = 'AVAILABLE';
        document.getElementById('taxi-calls-status').classList.add('active');
        
        document.getElementById('taxi-no-calls').style.display = 'none';
        
        // Generate TEST CALLS immediately for demo
        generateTestCalls();
        
        // Start receiving more calls
        setTimeout(() => generateIncomingCall(), Math.random() * 5000 + 3000);
    } else {
        taxiDispatchData.onDuty = false;
        
        // Clear active ride if any
        if (taxiDispatchData.activeRide) {
            endTaxiRide(false);
        }
        
        // Clear incoming calls
        taxiDispatchData.incomingCalls = [];
        document.getElementById('taxi-call-list').innerHTML = '';
        
        // Update UI
        document.getElementById('taxi-duty-btn').textContent = 'GO ON DUTY';
        document.getElementById('taxi-duty-btn').classList.remove('duty-btn-off');
        document.getElementById('taxi-duty-btn').classList.add('duty-btn-on');
        
        const dutyIndicator = document.querySelector('.duty-status-indicator');
        dutyIndicator.classList.remove('on');
        dutyIndicator.classList.add('off');
        dutyIndicator.innerHTML = '<span class="status-dot"></span> OFF DUTY';
        
        document.getElementById('taxi-calls-status').textContent = 'OFF DUTY';
        document.getElementById('taxi-calls-status').classList.remove('active');
        
        document.getElementById('taxi-no-calls').style.display = 'flex';
    }
    
    updateTaxiUI();
}

// Generate Test Calls for Demo
function generateTestCalls() {
    const testCalls = [
        {
            id: Date.now() + 1,
            isPlayer: true,
            isVIP: false,
            name: 'John Mitchell',
            location: 'Legion Square',
            destination: 'Vinewood Hills',
            distance: 3.2,
            pay: 125,
            xp: 48,
            timeLimit: 300
        },
        {
            id: Date.now() + 2,
            isPlayer: false,
            isVIP: true,
            name: 'Sarah Williams',
            location: 'Del Perro Pier',
            destination: 'Airport',
            distance: 2.8,
            pay: 155,
            xp: 45,
            timeLimit: 240
        },
        {
            id: Date.now() + 3,
            isPlayer: false,
            isVIP: false,
            name: 'Michael Chen',
            location: 'Rockford Hills',
            destination: 'Downtown',
            distance: 1.5,
            pay: 45,
            xp: 15,
            timeLimit: 180
        }
    ];
    
    taxiDispatchData.incomingCalls = testCalls;
    renderIncomingCalls();
}

// Generate Incoming Call (NPC or Player)
function generateIncomingCall() {
    if (!taxiDispatchData.onDuty || taxiDispatchData.activeRide) return;
    
    const isPlayer = Math.random() < 0.2; // 20% chance player request
    const isVIP = !isPlayer && Math.random() < 0.15; // 15% chance VIP if not player
    const locations = ['Legion Square', 'Vinewood Hills', 'Del Perro Pier', 'Rockford Hills', 'Paleto Bay', 'Sandy Shores'];
    const names = ['Michael', 'Sarah', 'James', 'Emma', 'Robert', 'Lisa', 'David', 'Jennifer'];
    
    const distance = Math.random() * 5 + 1; // 1-6 miles
    const basePay = Math.floor(distance * 15) + (Math.random() * 20);
    const baseXP = Math.floor(distance * 10);
    
    let multiplier = 1.0;
    if (isPlayer) multiplier = 1.5;
    if (isVIP) multiplier = 2.0;
    
    const streakBonus = taxiDispatchData.streak > 0 ? 1 + (taxiDispatchData.streak * 0.05) : 1;
    
    const call = {
        id: Date.now(),
        isPlayer: isPlayer,
        isVIP: isVIP,
        name: isPlayer ? 'Player Request' : names[Math.floor(Math.random() * names.length)],
        location: locations[Math.floor(Math.random() * locations.length)],
        destination: locations[Math.floor(Math.random() * locations.length)],
        distance: distance,
        pay: Math.floor(basePay * multiplier * streakBonus),
        xp: Math.floor(baseXP * multiplier),
        timeLimit: Math.floor(distance * 60 + 180) // Time bonus limit
    };
    
    taxiDispatchData.incomingCalls.push(call);
    renderIncomingCalls();
    
    // Generate next call if still on duty
    if (taxiDispatchData.onDuty && !taxiDispatchData.activeRide) {
        setTimeout(() => generateIncomingCall(), Math.random() * 15000 + 10000);
    }
}

// Render Incoming Calls
function renderIncomingCalls() {
    const container = document.getElementById('taxi-call-list');
    container.innerHTML = '';
    
    taxiDispatchData.incomingCalls.forEach(call => {
        const callCard = document.createElement('div');
        let cardClass = 'call-card';
        if (call.isPlayer) cardClass += ' player-request';
        if (call.isVIP) cardClass += ' vip-request';
        callCard.className = cardClass;
        
        const vipStar = call.isVIP ? '<span class="vip-star">★</span>' : '';
        
        callCard.innerHTML = `
            <div class="call-header-row">
                <div class="call-name">${call.name}${vipStar}</div>
                <div class="call-type ${call.isPlayer ? 'player' : 'npc'}">${call.isPlayer ? 'PLAYER' : 'NPC'}</div>
            </div>
            <div class="call-location"><span class="icon-map-pin"></span> ${call.location} → ${call.destination}</div>
            <div class="call-rewards">
                <div class="call-reward">
                    <span class="reward-icon"><span class="icon-dollar"></span></span>
                    <span class="reward-value">$${call.pay}</span>
                </div>
                <div class="call-reward">
                    <span class="reward-icon"><span class="icon-star"></span></span>
                    <span class="reward-value">+${call.xp} XP</span>
                </div>
                <div class="call-reward">
                    <span class="reward-icon"><span class="icon-map"></span></span>
                    <span class="reward-value">${call.distance.toFixed(1)} mi</span>
                </div>
            </div>
            <div class="call-actions">
                <button class="call-btn call-btn-accept" onclick="acceptTaxiCall(${call.id})">ACCEPT</button>
                <button class="call-btn call-btn-decline" onclick="declineTaxiCall(${call.id})">DECLINE</button>
            </div>
        `;
        container.appendChild(callCard);
    });
}

// Accept Call
function acceptTaxiCall(callId) {
    const call = taxiDispatchData.incomingCalls.find(c => c.id === callId);
    if (!call) return;
    
    taxiDispatchData.activeRide = {
        ...call,
        startTime: Date.now(),
        collisions: 0,
        progress: 0,
        elapsedTime: 0,
        timerInterval: null
    };
    
    // Clear incoming calls
    taxiDispatchData.incomingCalls = [];
    renderIncomingCalls();
    
    // Show active ride UI
    document.getElementById('taxi-active-ride').style.display = 'block';
    document.getElementById('taxi-idle-meter').style.display = 'none';
    document.getElementById('taxi-calls-status').textContent = 'ON RIDE';
    
    updateActiveRideUI();
    startRideTimer();
    
    // Notify backend
    console.log('Accepted ride:', call);
}

// Decline Call
function declineTaxiCall(callId) {
    taxiDispatchData.incomingCalls = taxiDispatchData.incomingCalls.filter(c => c.id !== callId);
    renderIncomingCalls();
}

// Update Active Ride UI
function updateActiveRideUI() {
    const ride = taxiDispatchData.activeRide;
    if (!ride) return;
    
    document.getElementById('taxi-customer-name').textContent = ride.name;
    document.getElementById('taxi-customer-dest').textContent = ride.destination;
    document.getElementById('taxi-active-meter').textContent = (ride.pay * (ride.progress / 100)).toFixed(2);
    document.getElementById('taxi-active-distance').textContent = (ride.distance * (ride.progress / 100)).toFixed(1);
    document.getElementById('taxi-ride-progress').style.width = ride.progress + '%';
    
    // Update timer
    const timeLeft = ride.timeLimit - Math.floor(ride.elapsedTime / 1000);
    const minutes = Math.floor(timeLeft / 60);
    const seconds = timeLeft % 60;
    document.getElementById('taxi-ride-timer').textContent = `${minutes}:${seconds.toString().padStart(2, '0')}`;
    document.getElementById('taxi-ride-timer').style.color = timeLeft < 60 ? '#ef4444' : '#10b981';
    
    // Collision warnings
    const warningsEl = document.getElementById('taxi-warnings');
    warningsEl.innerHTML = '';
    if (ride.collisions > 0) {
        warningsEl.innerHTML = `<div class="warning-item">⚠️ ${ride.collisions} collision(s) - Reduced payment!</div>`;
    }
}

// Start Ride Timer
function startRideTimer() {
    if (taxiDispatchData.activeRide.timerInterval) {
        clearInterval(taxiDispatchData.activeRide.timerInterval);
    }
    
    taxiDispatchData.activeRide.timerInterval = setInterval(() => {
        if (!taxiDispatchData.activeRide) return;
        
        taxiDispatchData.activeRide.elapsedTime += 1000;
        updateActiveRideUI();
        
        // Auto-fail if time runs out (in real scenario, this would be handled by backend)
        const timeLeft = taxiDispatchData.activeRide.timeLimit - Math.floor(taxiDispatchData.activeRide.elapsedTime / 1000);
        if (timeLeft <= 0) {
            endTaxiRide(false);
        }
    }, 1000);
}

// Handle Collision
function handleTaxiCollision() {
    if (!taxiDispatchData.activeRide) return;
    
    taxiDispatchData.activeRide.collisions++;
    taxiDispatchData.totalCollisions++;
    
    // Break streak
    if (taxiDispatchData.streak > 0) {
        taxiDispatchData.streak = 0;
        updateTaxiUI();
    }
    
    updateActiveRideUI();
}

// Update Ride Progress (called from backend)
function updateTaxiRideProgress(progress) {
    if (!taxiDispatchData.activeRide) return;
    
    taxiDispatchData.activeRide.progress = Math.min(progress, 100);
    updateActiveRideUI();
    
    if (progress >= 100) {
        endTaxiRide(true);
    }
}

// End Ride
function endTaxiRide(success) {
    if (!taxiDispatchData.activeRide) return;
    
    clearInterval(taxiDispatchData.activeRide.timerInterval);
    
    if (success) {
        const ride = taxiDispatchData.activeRide;
        const timeLeft = ride.timeLimit - Math.floor(ride.elapsedTime / 1000);
        const timeBonus = timeLeft > 0 ? 1.0 + (timeLeft / ride.timeLimit) * 0.2 : 1.0;
        const collisionPenalty = Math.max(0.5, 1.0 - (ride.collisions * 0.15));
        
        const finalPay = Math.floor(ride.pay * timeBonus * collisionPenalty);
        const finalXP = Math.floor(ride.xp * timeBonus * collisionPenalty);
        
        // Update stats
        taxiDispatchData.totalEarnings += finalPay;
        taxiDispatchData.xp += finalXP;
        taxiDispatchData.dailyRides++;
        taxiDispatchData.totalRides++;
        taxiDispatchData.totalDistance += ride.distance;
        
        if (ride.isPlayer) taxiDispatchData.playerRequests++;
        else taxiDispatchData.npcRequests++;
        
        if (ride.collisions === 0) {
            taxiDispatchData.streak++;
            taxiDispatchData.perfectRides++;
            if (taxiDispatchData.streak > taxiDispatchData.bestStreak) {
                taxiDispatchData.bestStreak = taxiDispatchData.streak;
            }
        } else {
            taxiDispatchData.streak = 0;
        }
        
        // Check level up
        checkTaxiLevelUp();
        
        // Update challenges
        updateTaxiChallenges();
    }
    
    taxiDispatchData.activeRide = null;
    
    // Hide active ride UI
    document.getElementById('taxi-active-ride').style.display = 'none';
    document.getElementById('taxi-idle-meter').style.display = 'block';
    document.getElementById('taxi-calls-status').textContent = 'AVAILABLE';
    
    updateTaxiUI();
    
    // Resume generating calls
    if (taxiDispatchData.onDuty) {
        setTimeout(() => generateIncomingCall(), Math.random() * 5000 + 2000);
    }
}

// Check Level Up
function checkTaxiLevelUp() {
    while (taxiDispatchData.level < taxiDispatchData.ranks.length && 
           taxiDispatchData.xp >= taxiDispatchData.ranks[taxiDispatchData.level].xpRequired) {
        taxiDispatchData.level++;
        // Show level up notification
        console.log('Level up!', taxiDispatchData.level);
    }
    
    // Update XP needed
    if (taxiDispatchData.level < taxiDispatchData.ranks.length) {
        taxiDispatchData.xpNeeded = taxiDispatchData.ranks[taxiDispatchData.level].xpRequired;
    }
}

// Switch Taxi Tab
function switchTaxiTab(tab) {
    // Hide all tabs
    document.querySelectorAll('.taxi-tab-content').forEach(el => {
        el.style.display = 'none';
    });
    
    // Show selected tab
    document.getElementById(`taxi-${tab}-tab`).style.display = 'block';
    
    // Update button states
    document.querySelectorAll('.taxi-tab-btn').forEach(btn => {
        btn.classList.remove('active');
    });
    document.querySelector(`.taxi-tab-btn[data-tab="${tab}"]`).classList.add('active');
}

// Render Vehicles Catalog
function renderVehiclesCatalog() {
    const grid = document.getElementById('taxi-vehicles-grid');
    grid.innerHTML = '';
    
    taxiDispatchData.vehicles.forEach(vehicle => {
        const isUnlocked = taxiDispatchData.level >= vehicle.unlockLevel;
        const isRented = taxiDispatchData.rentedVehicle === vehicle.id;
        
        const card = document.createElement('div');
        card.className = 'vehicle-card' + (isUnlocked ? '' : ' locked');
        card.innerHTML = `
            <div class="vehicle-tier">TIER ${vehicle.tier}</div>
            <div class="vehicle-image"><span class="icon-car" style="font-size: 48px; color: #fbbf24;"></span></div>
            <div class="vehicle-name">${vehicle.name}</div>
            <div class="vehicle-stats">
                <div class="vehicle-stat">
                    <div class="vehicle-stat-label">Rental</div>
                    <div class="vehicle-stat-value">$${vehicle.rental}</div>
                </div>
                <div class="vehicle-stat">
                    <div class="vehicle-stat-label">Deposit</div>
                    <div class="vehicle-stat-value">$${vehicle.deposit}</div>
                </div>
            </div>
            <button class="vehicle-rent-btn" ${!isUnlocked || isRented ? 'disabled' : ''} onclick="rentTaxiVehicle('${vehicle.id}')">
                ${!isUnlocked ? 'LOCKED (Lv' + vehicle.unlockLevel + ')' : isRented ? 'RENTED' : 'RENT VEHICLE'}
            </button>
        `;
        grid.appendChild(card);
    });
}

// Rent Vehicle
function rentTaxiVehicle(vehicleId) {
    const vehicle = taxiDispatchData.vehicles.find(v => v.id === vehicleId);
    if (!vehicle || taxiDispatchData.level < vehicle.unlockLevel) return;
    
    taxiDispatchData.rentedVehicle = vehicleId;
    renderVehiclesCatalog();
    
    // Notify backend
    console.log('Rented vehicle:', vehicle);
}

// Return Vehicle
function returnTaxiVehicle(condition) {
    // condition: 'pristine', 'damaged'
    const depositRefund = condition === 'pristine' ? 100 : 50; // % of deposit
    
    taxiDispatchData.rentedVehicle = null;
    renderVehiclesCatalog();
    
    console.log('Returned vehicle, deposit refund:', depositRefund + '%');
}

// Render Rank Cards
function renderRankCards() {
    const container = document.getElementById('taxi-rank-cards');
    const rankIndex = taxiDispatchData.currentRankIndex;
    const rank = taxiDispatchData.ranks[rankIndex];
    
    // Find vehicles for this rank
    const unlockedVehicles = taxiDispatchData.vehicles.filter(v => 
        rank.unlocks.includes(v.name)
    );
    
    container.innerHTML = `
        <div class="rank-info-card">
            <div class="rank-card-tier">LEVEL ${rank.level}</div>
            <div class="rank-card-name">${rank.name}</div>
            <div class="rank-card-unlocks">
                <h4><span class="icon-star" style="color: #fbbf24;"></span> Vehicle Unlocks:</h4>
                <ul class="rank-unlock-list">
                    ${rank.unlocks.map(unlock => {
                        const vehicle = taxiDispatchData.vehicles.find(v => v.name === unlock);
                        if (vehicle) {
                            return `<li class="rank-unlock-item">${vehicle.name} (Tier ${vehicle.tier}) - Rental: $${vehicle.rental}, Deposit: $${vehicle.deposit}</li>`;
                        }
                        return `<li class="rank-unlock-item">${unlock}</li>`;
                    }).join('')}
                    <li class="rank-unlock-item">Pay Multiplier: ${rank.multiplier}x</li>
                    <li class="rank-unlock-item">Required XP: ${rank.xpRequired}</li>
                </ul>
            </div>
        </div>
    `;
    
    // Update navigation buttons
    document.querySelector('.rank-nav-btn[onclick="prevTaxiRank()"]').disabled = (rankIndex === 0);
    document.querySelector('.rank-nav-btn[onclick="nextTaxiRank()"]').disabled = (rankIndex === taxiDispatchData.ranks.length - 1);
}

// Navigate Ranks
function prevTaxiRank() {
    if (taxiDispatchData.currentRankIndex > 0) {
        taxiDispatchData.currentRankIndex--;
        renderRankCards();
    }
}

function nextTaxiRank() {
    if (taxiDispatchData.currentRankIndex < taxiDispatchData.ranks.length - 1) {
        taxiDispatchData.currentRankIndex++;
        renderRankCards();
    }
}

// Generate Daily Challenges
function generateDailyChallenges() {
    taxiDispatchData.challenges = [
        { id: 1, type: 'daily', title: '5 Rides Without Collision', description: 'Complete 5 taxi rides without any collisions', progress: 0, goal: 5, reward: '+500 XP', xp: 500, cash: 0 },
        { id: 2, type: 'daily', title: 'Earn $500', description: 'Earn $500 from taxi rides today', progress: 0, goal: 500, reward: '+200 XP', xp: 200, cash: 0 },
        { id: 3, type: 'daily', title: '10 Total Rides', description: 'Complete 10 taxi rides', progress: 0, goal: 10, reward: '+300 XP + $100', xp: 300, cash: 100 }
    ];
    
    renderChallenges();
}

// Generate Level Challenges
function generateLevelChallenges() {
    // Define all level-specific challenges
    const levelChallenges = [
        { level: 1, id: 101, title: 'Beginner Route Master', description: 'Complete 10 rides in Downtown Taxi', goal: 10, reward: '+250 XP + $200', xp: 250, cash: 200 },
        { level: 2, id: 102, title: 'Comfort Specialist', description: 'Complete 15 rides in Comfort Cab', goal: 15, reward: '+400 XP + $300', xp: 400, cash: 300 },
        { level: 3, id: 103, title: 'Family Driver', description: 'Transport 20 groups in Family Minivan', goal: 20, reward: '+600 XP + $400', xp: 600, cash: 400 },
        { level: 4, id: 104, title: 'Eco Warrior', description: 'Drive 50 miles in Eco Electric', goal: 50, reward: '+800 XP + $500', xp: 800, cash: 500 },
        { level: 5, id: 105, title: 'Executive Service', description: 'Complete 10 rides in Executive Limo', goal: 10, reward: '+1000 XP + $750', xp: 1000, cash: 750 },
        { level: 6, id: 106, title: 'Luxury Expert', description: 'Complete 15 Mercedes rides with 5-star rating', goal: 15, reward: '+1500 XP + $1000', xp: 1500, cash: 1000 },
        { level: 7, id: 107, title: 'Fleet Master', description: 'Complete 50 total rides in Private Cab', goal: 50, reward: '+2500 XP + $2000', xp: 2500, cash: 2000 }
    ];
    
    // Only add unlocked challenges to data, but render will show all
    levelChallenges.forEach(challenge => {
        if (challenge.level <= taxiDispatchData.level) {
            const existing = taxiDispatchData.challenges.find(c => c.id === challenge.id);
            if (!existing) {
                taxiDispatchData.challenges.push({
                    ...challenge,
                    type: 'level',
                    progress: 0
                });
            }
        }
    });
    
    renderChallenges(levelChallenges);
}

// Render Challenges
function renderChallenges(allLevelChallenges = null) {
    const dailyContainer = document.getElementById('taxi-daily-challenges');
    const levelContainer = document.getElementById('taxi-level-challenges');
    
    dailyContainer.innerHTML = '';
    levelContainer.innerHTML = '';
    
    // Render daily challenges
    taxiDispatchData.challenges.filter(c => c.type === 'daily').forEach(challenge => {
        const progress = Math.min((challenge.progress / challenge.goal) * 100, 100);
        
        const card = document.createElement('div');
        card.className = 'challenge-card';
        card.innerHTML = `
            <div class="challenge-header-row">
                <div class="challenge-title">${challenge.title}</div>
                <div class="challenge-reward">${challenge.reward}</div>
            </div>
            <div class="challenge-description">${challenge.description}</div>
            <div class="challenge-progress">
                <div class="challenge-bar">
                    <div class="challenge-fill" style="width: ${progress}%"></div>
                </div>
                <div class="challenge-count">${challenge.progress}/${challenge.goal}</div>
            </div>
        `;
        dailyContainer.appendChild(card);
    });
    
    // Render level challenges (show all with locked states)
    if (allLevelChallenges) {
        allLevelChallenges.forEach(challengeTemplate => {
            const activeChallenge = taxiDispatchData.challenges.find(c => c.id === challengeTemplate.id);
            const isLocked = challengeTemplate.level > taxiDispatchData.level;
            const progress = activeChallenge ? Math.min((activeChallenge.progress / activeChallenge.goal) * 100, 100) : 0;
            
            const card = document.createElement('div');
            card.className = 'challenge-card' + (isLocked ? ' locked' : '');
            if (isLocked) {
                card.setAttribute('data-lock-text', `LOCKED - Level up to Level ${challengeTemplate.level} to unlock`);
            }
            card.innerHTML = `
                <div class="challenge-header-row">
                    <div class="challenge-title">${challengeTemplate.title}</div>
                    <div class="challenge-reward">${challengeTemplate.reward}</div>
                </div>
                <div class="challenge-description">${challengeTemplate.description}</div>
                <div class="challenge-progress">
                    <div class="challenge-bar">
                        <div class="challenge-fill" style="width: ${progress}%"></div>
                    </div>
                    <div class="challenge-count">${activeChallenge ? activeChallenge.progress : 0}/${challengeTemplate.goal}</div>
                </div>
            `;
            levelContainer.appendChild(card);
        });
    } else {
        // Fallback if called without templates
        taxiDispatchData.challenges.filter(c => c.type === 'level').forEach(challenge => {
            const progress = Math.min((challenge.progress / challenge.goal) * 100, 100);
            
            const card = document.createElement('div');
            card.className = 'challenge-card';
            card.innerHTML = `
                <div class="challenge-header-row">
                    <div class="challenge-title">${challenge.title}</div>
                    <div class="challenge-reward">${challenge.reward}</div>
                </div>
                <div class="challenge-description">${challenge.description}</div>
                <div class="challenge-progress">
                    <div class="challenge-bar">
                        <div class="challenge-fill" style="width: ${progress}%"></div>
                    </div>
                    <div class="challenge-count">${challenge.progress}/${challenge.goal}</div>
                </div>
            `;
            levelContainer.appendChild(card);
        });
    }
}

// Update Taxi Challenges
function updateTaxiChallenges() {
    taxiDispatchData.challenges.forEach(challenge => {
        if (challenge.id === 1 && taxiDispatchData.activeRide?.collisions === 0) {
            challenge.progress++;
        }
        if (challenge.id === 2) {
            challenge.progress = taxiDispatchData.totalEarnings; // Today's earnings
        }
        if (challenge.id === 3) {
            challenge.progress = taxiDispatchData.dailyRides;
        }
        
        // Check completion
        if (challenge.progress >= challenge.goal && !challenge.completed) {
            challenge.completed = true;
            taxiDispatchData.xp += challenge.xp;
            taxiDispatchData.totalEarnings += challenge.cash;
            console.log('Challenge completed!', challenge.title);
        }
    });
    
    renderChallenges();
}

// Update Challenge Timer
function updateChallengeTimer() {
    const now = new Date();
    const tomorrow = new Date(now);
    tomorrow.setHours(24, 0, 0, 0);
    
    const diff = tomorrow - now;
    const hours = Math.floor(diff / 3600000);
    const minutes = Math.floor((diff % 3600000) / 60000);
    const seconds = Math.floor((diff % 60000) / 1000);
    
    const timerEl = document.getElementById('taxi-challenge-refresh');
    if (timerEl) {
        timerEl.textContent = `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
    }
}

// Update Taxi UI
function updateTaxiUI() {
    // Update top bar
    document.getElementById('taxi-level-display').textContent = taxiDispatchData.level;
    document.getElementById('taxi-daily-rides').textContent = taxiDispatchData.dailyRides;
    document.getElementById('taxi-streak').textContent = taxiDispatchData.streak;
    document.getElementById('taxi-reputation').textContent = taxiDispatchData.reputation + '%';
    
    // Update rank display
    const currentRank = taxiDispatchData.ranks[taxiDispatchData.level - 1];
    const nextRank = taxiDispatchData.ranks[taxiDispatchData.level];
    
    if (nextRank) {
        const xpProgress = ((taxiDispatchData.xp - currentRank.xpRequired) / (nextRank.xpRequired - currentRank.xpRequired)) * 100;
        document.getElementById('taxi-rank-xp-fill').style.width = Math.min(xpProgress, 100) + '%';
        document.getElementById('taxi-rank-xp-current').textContent = taxiDispatchData.xp;
        document.getElementById('taxi-rank-xp-next').textContent = nextRank.xpRequired;
        document.getElementById('taxi-current-rank-name').textContent = currentRank.name;
    }
    
    // Update stats
    document.getElementById('taxi-total-earnings').textContent = '$' + taxiDispatchData.totalEarnings;
    document.getElementById('taxi-total-rides').textContent = taxiDispatchData.totalRides;
    document.getElementById('taxi-total-distance').textContent = taxiDispatchData.totalDistance.toFixed(1) + ' mi';
    document.getElementById('taxi-avg-rating').textContent = taxiDispatchData.avgRating.toFixed(1);
    document.getElementById('taxi-best-streak').textContent = taxiDispatchData.bestStreak;
    document.getElementById('taxi-total-collisions').textContent = taxiDispatchData.totalCollisions;
    document.getElementById('taxi-player-requests').textContent = taxiDispatchData.playerRequests;
    document.getElementById('taxi-npc-requests').textContent = taxiDispatchData.npcRequests;
    document.getElementById('taxi-perfect-rides').textContent = taxiDispatchData.perfectRides;
}

// Check Vehicle Status (called from backend)
function updateTaxiVehicleStatus(inVehicle, vehicleType) {
    taxiDispatchData.inCertifiedVehicle = inVehicle;
    taxiDispatchData.vehicleType = vehicleType;
    
    const statusEl = document.getElementById('taxi-vehicle-status');
    if (inVehicle) {
        statusEl.innerHTML = `
            <span class="vehicle-icon"><span class="icon-taxi" style="color: #fbbf24;"></span></span>
            <span class="vehicle-text">✓ ${vehicleType === 'private' ? 'Private Cab' : 'Taxi'} - Ready</span>
        `;
    } else {
        statusEl.innerHTML = `
            <span class="vehicle-icon"><span class="icon-car" style="opacity: 0.5;"></span></span>
            <span class="vehicle-text">Enter a certified vehicle</span>
        `;
    }
}

// Initialize on page load
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initializeTaxiSystem);
} else {
    initializeTaxiSystem();
}
