// ============================================================================
// GARBAGE & GRUPPE6 GROUP MANAGEMENT SYSTEMS
// ============================================================================

// ============================================================================
// GARBAGE JOB SYSTEM
// ============================================================================

let garbageJobData = {
    level: 1,
    xp: 100,
    xpNeeded: 1000,
    status: 'idle', // idle, active, completed
    collected: 0,
    maxBags: 10,
    payPerBag: 20,
    sessionEarnings: 0,
    sessionXP: 0,
    inGroup: false,
    groupMembers: [],
    groupBonus: 0
};

// Switch Garbage Tab
function switchGarbageTab(tab) {
    document.querySelectorAll('.contract-tab-content').forEach(el => {
        if (el.id.startsWith('garbage-')) el.style.display = 'none';
    });
    
    document.getElementById(`garbage-${tab}-tab`).style.display = 'block';
    
    document.querySelectorAll('.contract-tab-btn').forEach(btn => {
        if (btn.getAttribute('onclick')?.includes('Garbage')) {
            btn.classList.remove('active');
        }
    });
    document.querySelector(`.contract-tab-btn[data-tab="${tab}"]`)?.classList.add('active');
}

// Start Garbage Job
function startGarbageJob() {
    garbageJobData.status = 'active';
    garbageJobData.collected = 0;
    garbageJobData.sessionEarnings = 0;
    garbageJobData.sessionXP = 0;
    
    document.getElementById('garbage-status').textContent = 'Active';
    document.getElementById('garbage-start-btn').textContent = 'END ROUTE';
    document.getElementById('garbage-start-btn').setAttribute('onclick', 'endGarbageJob()');
    
    updateGarbageUI();
    
    // Notify backend
    console.log('Started garbage route');
}

// End Garbage Job
function endGarbageJob() {
    garbageJobData.status = 'idle';
    
    document.getElementById('garbage-status').textContent = 'Idle';
    document.getElementById('garbage-start-btn').textContent = 'START ROUTE';
    document.getElementById('garbage-start-btn').setAttribute('onclick', 'startGarbageJob()');
    
    updateGarbageUI();
    
    console.log('Ended garbage route');
}

// Update Garbage Progress (called from backend)
function updateGarbageProgress(collected) {
    garbageJobData.collected = collected;
    garbageJobData.sessionEarnings = collected * garbageJobData.payPerBag * (1 + garbageJobData.groupBonus / 100);
    garbageJobData.sessionXP = collected * 10;
    
    updateGarbageUI();
    
    if (collected >= garbageJobData.maxBags) {
        completeGarbageRoute();
    }
}

// Complete Route
function completeGarbageRoute() {
    garbageJobData.xp += garbageJobData.sessionXP;
    garbageJobData.status = 'completed';
    
    // Check level up
    while (garbageJobData.xp >= garbageJobData.xpNeeded) {
        garbageJobData.level++;
        garbageJobData.xp -= garbageJobData.xpNeeded;
        garbageJobData.xpNeeded = Math.floor(garbageJobData.xpNeeded * 1.5);
        
        // Update pay per bag based on level
        garbageJobData.payPerBag = 20 + (garbageJobData.level - 1) * 10;
    }
    
    updateGarbageUI();
    console.log('Route completed!');
}

// Update Garbage UI
function updateGarbageUI() {
    document.getElementById('garbage-level-top').textContent = garbageJobData.level;
    document.getElementById('garbage-xp-current').textContent = garbageJobData.xp;
    document.getElementById('garbage-xp-next').textContent = garbageJobData.xpNeeded;
    
    const xpProgress = (garbageJobData.xp / garbageJobData.xpNeeded) * 100;
    document.getElementById('garbage-xp-fill').style.width = Math.min(xpProgress, 100) + '%';
    
    document.getElementById('garbage-collected').textContent = `${garbageJobData.collected}/${garbageJobData.maxBags}`;
    document.getElementById('garbage-pay-rate').textContent = garbageJobData.payPerBag;
    document.getElementById('garbage-bags-collected').textContent = garbageJobData.collected;
    document.getElementById('garbage-session-earnings').textContent = '$' + garbageJobData.sessionEarnings.toFixed(0);
    document.getElementById('garbage-session-xp').textContent = '+' + garbageJobData.sessionXP;
    
    // Update progress circle
    const circumference = 2 * Math.PI * 45;
    const progress = (garbageJobData.collected / garbageJobData.maxBags);
    const offset = circumference - (progress * circumference);
    
    const svg = document.getElementById('garbage-progress-svg');
    if (svg) {
        svg.style.strokeDashoffset = offset;
    }
    
    // Update group display
    document.getElementById('garbage-group-size').textContent = garbageJobData.inGroup ? 
        `${garbageJobData.groupMembers.length} Members` : 'Solo';
    document.getElementById('garbage-group-bonus').textContent = garbageJobData.groupBonus;
}

// Group Management
function createGarbageGroup() {
    garbageJobData.inGroup = true;
    garbageJobData.groupMembers = [{ name: 'You', role: 'Leader' }];
    garbageJobData.groupBonus = 0; // Will increase as members join
    
    document.getElementById('garbage-no-group').style.display = 'none';
    document.getElementById('garbage-active-group').style.display = 'block';
    
    renderGarbageGroupMembers();
    updateGarbageUI();
    
    console.log('Created garbage group');
}

function findGarbageGroup() {
    // Show available groups (would come from backend)
    console.log('Finding garbage groups...');
}

function leaveGarbageGroup() {
    garbageJobData.inGroup = false;
    garbageJobData.groupMembers = [];
    garbageJobData.groupBonus = 0;
    
    document.getElementById('garbage-no-group').style.display = 'block';
    document.getElementById('garbage-active-group').style.display = 'none';
    
    updateGarbageUI();
    
    console.log('Left garbage group');
}

function renderGarbageGroupMembers() {
    const container = document.getElementById('garbage-group-members');
    container.innerHTML = '';
    
    garbageJobData.groupMembers.forEach(member => {
        const memberEl = document.createElement('div');
        memberEl.className = 'group-member-item';
        memberEl.innerHTML = `
            <div class="member-avatar"><span class="icon-user" style="font-size: 24px;"></span></div>
            <div class="member-info">
                <div class="member-name">${member.name}</div>
                <div class="member-role">${member.role}</div>
            </div>
        `;
        container.appendChild(memberEl);
    });
}

// Add group member (called from backend)
function addGarbageMember(name) {
    garbageJobData.groupMembers.push({ name: name, role: 'Member' });
    garbageJobData.groupBonus = (garbageJobData.groupMembers.length - 1) * 15; // +15% per extra member
    
    renderGarbageGroupMembers();
    updateGarbageUI();
}

// ============================================================================
// GRUPPE6 SECURITY SYSTEM
// ============================================================================

let gruppe6JobData = {
    level: 1,
    xp: 100,
    xpNeeded: 1000,
    status: 'idle', // idle, searching, active
    contracts: [],
    activeContract: null,
    pickupsCompleted: 0,
    maxPickups: 12,
    sessionEarnings: 0,
    completedContracts: 0,
    totalEarnings: 0,
    inGroup: false,
    groupMembers: [],
    maxGroupSize: 4
};

// Initialize Gruppe6
function initializeGruppe6() {
    generateGruppe6Contracts();
    updateGruppe6UI();
}

// Generate Contracts
function generateGruppe6Contracts() {
    gruppe6JobData.contracts = [
        {
            id: 1,
            tier: 1,
            name: 'STOCKADE',
            type: 'Bank Delivery',
            bags: 250,
            payout: 753,
            maxGroup: 4
        },
        {
            id: 2,
            tier: 2,
            name: 'ARMORED TRANSPORT',
            type: 'Vault Transfer',
            bags: 350,
            payout: 1250,
            maxGroup: 4
        },
        {
            id: 3,
            tier: 1,
            name: 'CASH PICKUP',
            type: 'ATM Collection',
            bags: 180,
            payout: 520,
            maxGroup: 2
        }
    ];
    
    renderGruppe6Contracts();
}

// Render Contracts
function renderGruppe6Contracts() {
    const container = document.getElementById('gruppe6-contract-list');
    const noContracts = document.getElementById('gruppe6-no-contracts');
    
    if (gruppe6JobData.contracts.length === 0) {
        container.innerHTML = '';
        noContracts.style.display = 'flex';
        return;
    } else {
        noContracts.style.display = 'none';
    }
    
    // Clear existing contract cards (except the example one if you want to keep template)
    container.innerHTML = '';
    
    // Render each contract
    gruppe6JobData.contracts.forEach(contract => {
        const contractCard = document.createElement('div');
        contractCard.className = 'contract-card';
        contractCard.innerHTML = `
            <div class="contract-tier">TIER ${contract.tier}</div>
            <div class="contract-title">${contract.name}</div>
            <div class="contract-badge">
                <div class="badge-wings"><span class="icon-wings-left"></span></div>
                <div class="badge-star"><span class="icon-badge"></span></div>
                <div class="badge-wings"><span class="icon-wings-right"></span></div>
            </div>
            <div class="contract-details">
                <div class="contract-detail-row">
                    <span class="detail-icon"><span class="icon-bank"></span></span>
                    <span class="detail-label">Type:</span>
                    <span class="detail-value">${contract.type}</span>
                </div>
                <div class="contract-detail-row">
                    <span class="detail-icon"><span class="icon-box"></span></span>
                    <span class="detail-label">Bags:</span>
                    <span class="detail-value">${contract.bags}</span>
                </div>
                <div class="contract-detail-row">
                    <span class="detail-icon"><span class="icon-dollar"></span></span>
                    <span class="detail-label">Payout:</span>
                    <span class="detail-value">$${contract.payout}</span>
                </div>
                <div class="contract-detail-row">
                    <span class="detail-icon"><span class="icon-users"></span></span>
                    <span class="detail-label">Max Group:</span>
                    <span class="detail-value">${contract.maxGroup}</span>
                </div>
            </div>
            <button class="contract-accept-btn" onclick="acceptGruppe6Contract(${contract.id})">ACCEPT CONTRACT</button>
        `;
        container.appendChild(contractCard);
    });
    
    const count = gruppe6JobData.contracts.length;
    document.getElementById('gruppe6-contract-count').textContent = count;
    
    // Update the contracts count text (singular/plural)
    const countElement = document.querySelector('.contracts-count');
    if (countElement) {
        countElement.innerHTML = `<span id="gruppe6-contract-count">${count}</span> CONTRACT${count !== 1 ? 'S' : ''} AVAILABLE`;
    }
}

// Switch Gruppe6 Tab
function switchGruppe6Tab(tab) {
    document.querySelectorAll('.contract-tab-content').forEach(el => {
        if (el.id.startsWith('gruppe6-')) el.style.display = 'none';
    });
    
    document.getElementById(`gruppe6-${tab}-tab`).style.display = 'block';
    
    document.querySelectorAll('.contract-tab-btn').forEach(btn => {
        if (btn.getAttribute('onclick')?.includes('Gruppe6')) {
            btn.classList.remove('active');
        }
    });
    document.querySelector(`.contract-tab-btn[data-tab="${tab}"]`)?.classList.add('active');
}

// Accept Contract
function acceptGruppe6Contract(contractId) {
    const contract = gruppe6JobData.contracts.find(c => c.id === contractId);
    if (!contract) return;
    
    gruppe6JobData.activeContract = contract;
    gruppe6JobData.status = 'active';
    gruppe6JobData.pickupsCompleted = 0;
    gruppe6JobData.sessionEarnings = 0;
    
    // Remove from available
    gruppe6JobData.contracts = gruppe6JobData.contracts.filter(c => c.id !== contractId);
    
    // Switch to work tab
    switchGruppe6Tab('work');
    
    document.getElementById('gruppe6-no-active').style.display = 'none';
    document.getElementById('gruppe6-active-contract').style.display = 'block';
    document.getElementById('gruppe6-active-name').textContent = contract.name + ' DELIVERY';
    
    updateGruppe6UI();
    renderGruppe6Contracts();
    
    console.log('Accepted contract:', contract);
}

// Update Gruppe6 Progress (called from backend)
function updateGruppe6Pickups(pickups) {
    gruppe6JobData.pickupsCompleted = pickups;
    
    const progress = (pickups / gruppe6JobData.maxPickups) * 100;
    document.getElementById('gruppe6-pickup-fill').style.width = progress + '%';
    document.getElementById('gruppe6-pickups').textContent = `${pickups}/${gruppe6JobData.maxPickups}`;
    
    if (gruppe6JobData.activeContract) {
        const earnedSoFar = Math.floor((pickups / gruppe6JobData.maxPickups) * gruppe6JobData.activeContract.payout);
        document.getElementById('gruppe6-session-pay').textContent = '$' + earnedSoFar;
    }
    
    if (pickups >= gruppe6JobData.maxPickups) {
        completeGruppe6Contract();
    }
}

// Complete Contract
function completeGruppe6Contract() {
    if (!gruppe6JobData.activeContract) return;
    
    gruppe6JobData.totalEarnings += gruppe6JobData.activeContract.payout;
    gruppe6JobData.completedContracts++;
    gruppe6JobData.xp += 100;
    
    gruppe6JobData.activeContract = null;
    gruppe6JobData.status = 'idle';
    
    document.getElementById('gruppe6-no-active').style.display = 'block';
    document.getElementById('gruppe6-active-contract').style.display = 'none';
    
    // Generate new contract after delay
    setTimeout(() => {
        generateGruppe6Contracts();
    }, 5000);
    
    updateGruppe6UI();
    console.log('Contract completed!');
}

// Update Gruppe6 UI
function updateGruppe6UI() {
    document.getElementById('gruppe6-level-top').textContent = gruppe6JobData.level;
    document.getElementById('gruppe6-xp-current').textContent = gruppe6JobData.xp;
    document.getElementById('gruppe6-xp-next').textContent = gruppe6JobData.xpNeeded;
    
    const xpProgress = (gruppe6JobData.xp / gruppe6JobData.xpNeeded) * 100;
    document.getElementById('gruppe6-xp-fill').style.width = Math.min(xpProgress, 100) + '%';
    
    document.getElementById('gruppe6-group-size').textContent = gruppe6JobData.inGroup ? 
        `${gruppe6JobData.groupMembers.length}/${gruppe6JobData.maxGroupSize}` : 'Solo';
    
    document.getElementById('gruppe6-completed').textContent = gruppe6JobData.completedContracts;
    document.getElementById('gruppe6-total-earned').textContent = '$' + gruppe6JobData.totalEarnings;
    document.getElementById('gruppe6-max-members').textContent = gruppe6JobData.maxGroupSize;
}

// Group Management
function createGruppe6Group() {
    gruppe6JobData.inGroup = true;
    gruppe6JobData.groupMembers = [{ name: 'You', role: 'Leader' }];
    
    document.getElementById('gruppe6-no-group').style.display = 'none';
    document.getElementById('gruppe6-active-group').style.display = 'block';
    
    renderGruppe6GroupMembers();
    updateGruppe6UI();
    
    console.log('Created Gruppe6 security team');
}

function findGruppe6Group() {
    console.log('Finding Gruppe6 teams...');
}

function leaveGruppe6Group() {
    gruppe6JobData.inGroup = false;
    gruppe6JobData.groupMembers = [];
    
    document.getElementById('gruppe6-no-group').style.display = 'block';
    document.getElementById('gruppe6-active-group').style.display = 'none';
    
    updateGruppe6UI();
    
    console.log('Left Gruppe6 team');
}

function renderGruppe6GroupMembers() {
    const container = document.getElementById('gruppe6-group-members');
    container.innerHTML = '';
    
    gruppe6JobData.groupMembers.forEach(member => {
        const memberEl = document.createElement('div');
        memberEl.className = 'group-member-item';
        memberEl.innerHTML = `
            <div class="member-avatar">🛡️</div>
            <div class="member-info">
                <div class="member-name">${member.name}</div>
                <div class="member-role">${member.role}</div>
            </div>
        `;
        container.appendChild(memberEl);
    });
}

// Add member (called from backend)
function addGruppe6Member(name) {
    if (gruppe6JobData.groupMembers.length >= gruppe6JobData.maxGroupSize) {
        console.log('Group is full');
        return;
    }
    
    gruppe6JobData.groupMembers.push({ name: name, role: 'Security' });
    
    renderGruppe6GroupMembers();
    updateGruppe6UI();
}

// Initialize on load
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
        initializeGruppe6();
        updateGarbageUI();
    });
} else {
    initializeGruppe6();
    updateGarbageUI();
}
