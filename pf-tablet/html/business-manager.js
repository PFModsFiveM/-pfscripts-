window.renderBusinessManagerUI = function($container) {
    const appShell = `
        <div class="businesses-window-content">
            <div class="businesses-topbar">
                <h2>Business Manager</h2>
            </div>
            <div class="businesses-container">
                <div class="businesses-sidebar">
                    <div class="businesses-nav-item active" data-page="overview">Overview</div>
                    <div class="businesses-nav-item" data-page="registry">Registry</div>
                    <div class="businesses-nav-item" data-page="details">Details</div>
                    <div class="businesses-nav-item" data-page="analytics">Analytics</div>
                    <div class="businesses-nav-item" data-page="employees">Employees</div>
                    <div class="businesses-nav-item" data-page="compliance">Compliance</div>
                    <div class="businesses-nav-item" data-page="taxes">Taxes</div>
                    <div class="businesses-nav-item" data-page="audit">Audit</div>
                    <div class="businesses-nav-item" data-page="settings">Settings</div>
                </div>
                <div class="businesses-main" id="businesses-content"></div>
            </div>
        </div>
    `;

    $container.html(appShell);
    window.businessesManager = new BusinessesManager();
};
class BusinessesManager {
    constructor() {
        this.currentPage = 'overview';
        this.currentBusinessId = null;
        this.citizens = [
            { name: 'Mia Harris', citizenId: 'CID-8421' },
            { name: 'Dylan Reese', citizenId: 'CID-1134' },
            { name: 'Laura Park', citizenId: 'CID-7749' },
            { name: 'Marcus Cole', citizenId: 'CID-4920' },
            { name: 'Jordan Blake', citizenId: 'CID-2267' },
            { name: 'Taylor Quinn', citizenId: 'CID-3358' }
        ];
        this.data = {
            stats: {
                totalBusinesses: 128,
                activeBusinesses: 112,
                totalEmployees: 684,
                revenueToday: 185400,
                revenueWeek: 1287400,
                revenueMonth: 5526000,
                mostProfitable: 'Harmony Customs',
                lowestPerforming: 'Bean Machine'
            },
            alerts: {
                unpaidTaxes: 7,
                unlicensed: 3,
                incomeSpikes: 4
            },
            businesses: [
                {
                    id: 'BUS-1001',
                    name: 'Harmony Customs',
                    owner: 'Mia Harris',
                    ownerId: 'CID-8421',
                    type: 'Mechanic',
                    status: 'Open',
                    employees: 18,
                    revenueWeek: 248000,
                    licenseStatus: 'Active',
                    taxStatus: 'Current',
                    balance: 540000,
                    blip: 'Harmony Customs',
                    blipColor: 'Blue',
                    location: 'Strawberry Ave',
                    salesTotal: 985000,
                    invoices: 420,
                    avgSale: 2347,
                    peakHours: '18:00-22:00',
                    payroll: 72000,
                    wageAvg: 3200,
                    permits: ['Repair', 'Towing'],
                    taxDebt: 0,
                    warnings: [],
                    employeesList: [
                        { name: 'Alex Vega', role: 'Lead Mechanic', wage: 4200, activity: 'Active' },
                        { name: 'Sam Patel', role: 'Service Advisor', wage: 3200, activity: 'Active' },
                        { name: 'Jamie Fox', role: 'Mechanic', wage: 2800, activity: 'Active' }
                    ],
                    transactions: [
                        { date: '02/17/2026', type: 'Service', amount: 4200, note: 'Performance upgrades' },
                        { date: '02/16/2026', type: 'Repair', amount: 1650, note: 'Engine rebuild' },
                        { date: '02/15/2026', type: 'Service', amount: 850, note: 'Brake replacement' }
                    ],
                    activityLog: [
                        { date: '02/17/2026 09:20', action: 'Inspection passed', actor: 'City Inspector' },
                        { date: '02/16/2026 17:40', action: 'Tax payment recorded', actor: 'Treasury' },
                        { date: '02/15/2026 14:05', action: 'License renewed', actor: 'Mayor Office' }
                    ]
                },
                {
                    id: 'BUS-1002',
                    name: 'Burger Shot',
                    owner: 'Dylan Reese',
                    ownerId: 'CID-1134',
                    type: 'Restaurant',
                    status: 'Open',
                    employees: 42,
                    revenueWeek: 165500,
                    licenseStatus: 'Active',
                    taxStatus: 'Late',
                    balance: 320000,
                    blip: 'Burger Shot',
                    blipColor: 'Red',
                    location: 'Vespucci Blvd',
                    salesTotal: 612000,
                    invoices: 1250,
                    avgSale: 490,
                    peakHours: '12:00-14:00',
                    payroll: 96000,
                    wageAvg: 1900,
                    permits: ['Food', 'Alcohol'],
                    taxDebt: 18400,
                    warnings: ['Tax delinquency notice'],
                    employeesList: [
                        { name: 'Riley Stone', role: 'Manager', wage: 2600, activity: 'Active' },
                        { name: 'Chris Lane', role: 'Cook', wage: 1700, activity: 'Active' },
                        { name: 'Morgan Lee', role: 'Cashier', wage: 1500, activity: 'Inactive' }
                    ],
                    transactions: [
                        { date: '02/17/2026', type: 'Sales', amount: 6200, note: 'Lunch rush' },
                        { date: '02/16/2026', type: 'Sales', amount: 5400, note: 'Dinner service' },
                        { date: '02/15/2026', type: 'Sales', amount: 4900, note: 'Weekend traffic' }
                    ],
                    activityLog: [
                        { date: '02/17/2026 11:15', action: 'Late fee applied', actor: 'Treasury' },
                        { date: '02/16/2026 10:05', action: 'Compliance warning issued', actor: 'Mayor Office' },
                        { date: '02/15/2026 18:45', action: 'Tax reminder sent', actor: 'Treasury' }
                    ]
                },
                {
                    id: 'BUS-1003',
                    name: 'Bean Machine',
                    owner: 'Laura Park',
                    ownerId: 'CID-7749',
                    type: 'Cafe',
                    status: 'Closed',
                    employees: 6,
                    revenueWeek: 8400,
                    licenseStatus: 'Suspended',
                    taxStatus: 'Delinquent',
                    balance: 14000,
                    blip: 'Bean Machine',
                    blipColor: 'Green',
                    location: 'Downtown',
                    salesTotal: 85000,
                    invoices: 160,
                    avgSale: 530,
                    peakHours: '08:00-10:00',
                    payroll: 9800,
                    wageAvg: 1200,
                    permits: ['Food'],
                    taxDebt: 9200,
                    warnings: ['Operating without license'],
                    employeesList: [
                        { name: 'Dakota Reed', role: 'Barista', wage: 1100, activity: 'Inactive' },
                        { name: 'Casey Wynn', role: 'Barista', wage: 1100, activity: 'Inactive' }
                    ],
                    transactions: [
                        { date: '02/10/2026', type: 'Sales', amount: 600, note: 'Limited service' },
                        { date: '02/08/2026', type: 'Sales', amount: 450, note: 'Morning rush' }
                    ],
                    activityLog: [
                        { date: '02/14/2026 08:10', action: 'License suspended', actor: 'Mayor Office' },
                        { date: '02/12/2026 13:30', action: 'Inspection failed', actor: 'City Inspector' }
                    ]
                },
                {
                    id: 'BUS-1004',
                    name: 'Premium Deluxe Motorsport',
                    owner: 'Marcus Cole',
                    ownerId: 'CID-4920',
                    type: 'Dealership',
                    status: 'Open',
                    employees: 25,
                    revenueWeek: 312000,
                    licenseStatus: 'Active',
                    taxStatus: 'Current',
                    balance: 980000,
                    blip: 'PDM',
                    blipColor: 'Yellow',
                    location: 'Power St',
                    salesTotal: 1850000,
                    invoices: 140,
                    avgSale: 13214,
                    peakHours: '16:00-19:00',
                    payroll: 105000,
                    wageAvg: 4200,
                    permits: ['Sales', 'Test Drive'],
                    taxDebt: 0,
                    warnings: [],
                    employeesList: [
                        { name: 'Avery Shaw', role: 'Sales Lead', wage: 5200, activity: 'Active' },
                        { name: 'Quinn Hayes', role: 'Sales', wage: 3600, activity: 'Active' },
                        { name: 'Drew Scott', role: 'Finance', wage: 4100, activity: 'Active' }
                    ],
                    transactions: [
                        { date: '02/17/2026', type: 'Vehicle Sale', amount: 78000, note: 'Sports vehicle' },
                        { date: '02/16/2026', type: 'Vehicle Sale', amount: 65000, note: 'Sedan package' },
                        { date: '02/15/2026', type: 'Vehicle Sale', amount: 54000, note: 'SUV lease' }
                    ],
                    activityLog: [
                        { date: '02/17/2026 15:30', action: 'Audit completed', actor: 'Mayor Office' },
                        { date: '02/16/2026 12:00', action: 'Tax payment recorded', actor: 'Treasury' }
                    ]
                }
            ],
            auditLog: [
                { timestamp: '02/17/2026 10:15 AM', action: 'Mayor applied late fee', business: 'Burger Shot', type: 'Tax Enforcement' },
                { timestamp: '02/16/2026 04:50 PM', action: 'Mayor suspended license', business: 'Bean Machine', type: 'Compliance' },
                { timestamp: '02/16/2026 01:25 PM', action: 'Mayor renewed license', business: 'Harmony Customs', type: 'Licensing' },
                { timestamp: '02/15/2026 09:10 AM', action: 'Mayor changed business tax', business: 'All Businesses', type: 'Policy' }
            ]
        };
        this.init();
    }

    init() {
        const navItems = document.querySelectorAll('.businesses-nav-item');
        const content = document.getElementById('businesses-content');

        if (!content) return;

        navItems.forEach(item => {
            item.addEventListener('click', () => {
                navItems.forEach(nav => nav.classList.remove('active'));
                item.classList.add('active');
                const page = item.dataset.page;
                this.currentPage = page;
                this.renderPage(page, content);
            });
        });

        this.renderPage(this.currentPage, content);
    }

    renderPage(page, container) {
        const pages = {
            overview: this.renderOverview(),
            registry: this.renderRegistry(),
            details: this.renderDetailsPage(),
            analytics: this.renderAnalytics(),
            employees: this.renderEmployees(),
            compliance: this.renderCompliance(),
            taxes: this.renderTaxes(),
            audit: this.renderAuditLog(),
            settings: this.renderSettings()
        };

        if (page === 'details' && !this.currentBusinessId) {
            this.currentPage = 'registry';
            container.innerHTML = this.renderRegistry();
        } else {
            container.innerHTML = pages[page] || this.renderOverview();
        }

        if (page === 'registry') {
            this.attachRegistryHandlers(container);
        } else if (page === 'details') {
            this.attachDetailsPageHandlers(container);
        }
    }

    openBusinessDetails(businessId, container) {
        this.currentBusinessId = businessId;
        this.currentPage = 'details';
        this.renderPage('details', container);
    }

    renderOverview() {
        return `
            <div class="businesses-page">
                <div class="page-title">Business Oversight</div>
                <div class="overview-kpi-grid">
                    <div class="kpi-card">
                        <div class="kpi-label">Total Businesses</div>
                        <div class="kpi-value">${this.data.stats.totalBusinesses}</div>
                        <div class="kpi-subtext">Registered in city directory</div>
                    </div>
                    <div class="kpi-card">
                        <div class="kpi-label">Active Businesses</div>
                        <div class="kpi-value">${this.data.stats.activeBusinesses}</div>
                        <div class="kpi-subtext">Open and operating today</div>
                    </div>
                    <div class="kpi-card">
                        <div class="kpi-label">Total Employees</div>
                        <div class="kpi-value">${this.data.stats.totalEmployees}</div>
                        <div class="kpi-subtext">Across all businesses</div>
                    </div>
                    <div class="kpi-card">
                        <div class="kpi-label">Revenue This Week</div>
                        <div class="kpi-value">$${this.data.stats.revenueWeek.toLocaleString()}</div>
                        <div class="kpi-subtext">Combined gross revenue</div>
                    </div>
                </div>

                <div class="overview-grid">
                    <div class="panel-card">
                        <h3>Economic Summary</h3>
                        <div class="detail-list">
                            <div class="detail-row"><span>Revenue Today</span><strong>$${this.data.stats.revenueToday.toLocaleString()}</strong></div>
                            <div class="detail-row"><span>Revenue This Month</span><strong>$${this.data.stats.revenueMonth.toLocaleString()}</strong></div>
                            <div class="detail-row"><span>Most Profitable</span><strong>${this.data.stats.mostProfitable}</strong></div>
                            <div class="detail-row"><span>Lowest Performing</span><strong>${this.data.stats.lowestPerforming}</strong></div>
                        </div>
                    </div>
                    <div class="panel-card">
                        <h3>Compliance Risk</h3>
                        <div class="risk-list">
                            <div class="risk-item danger">${this.data.alerts.unpaidTaxes} businesses behind on tax</div>
                            <div class="risk-item warning">${this.data.alerts.unlicensed} operating without license</div>
                            <div class="risk-item warning">${this.data.alerts.incomeSpikes} suspicious income spikes</div>
                        </div>
                    </div>
                    <div class="panel-card">
                        <h3>Top Revenue Businesses</h3>
                        <table class="mini-table">
                            <tr><td>Harmony Customs</td><td>$248,000</td></tr>
                            <tr><td>PDM</td><td>$312,000</td></tr>
                            <tr><td>Burger Shot</td><td>$165,500</td></tr>
                            <tr><td>Bean Machine</td><td>$8,400</td></tr>
                        </table>
                    </div>
                    <div class="panel-card">
                        <h3>Compliance Watchlist</h3>
                        <div class="detail-list">
                            <div class="detail-row"><span>Unpaid Taxes</span><strong>7</strong></div>
                            <div class="detail-row"><span>License Suspensions</span><strong>3</strong></div>
                            <div class="detail-row"><span>Escalation Cases</span><strong>2</strong></div>
                            <div class="detail-row"><span>Inspection Queue</span><strong>5</strong></div>
                        </div>
                    </div>
                </div>

                <div class="table-container">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>Business</th>
                                <th>Issue</th>
                                <th>Owner</th>
                                <th>Status</th>
                                <th>Last Action</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr>
                                <td>Bean Machine</td>
                                <td>Operating without license</td>
                                <td>Laura Park</td>
                                <td>${this.getStatusBadge('Suspended')}</td>
                                <td>Compliance notice sent</td>
                            </tr>
                            <tr>
                                <td>Burger Shot</td>
                                <td>Tax delinquency</td>
                                <td>Dylan Reese</td>
                                <td>${this.getStatusBadge('Late')}</td>
                                <td>Late fee applied</td>
                            </tr>
                            <tr>
                                <td>Harmony Customs</td>
                                <td>Income spike review</td>
                                <td>Mia Harris</td>
                                <td>${this.getStatusBadge('Active')}</td>
                                <td>Audit scheduled</td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        `;
    }

    renderRegistry() {
        const citizenOptions = this.citizens.map(citizen => 
            `<option value="${citizen.name} (${citizen.citizenId})">${citizen.name} (${citizen.citizenId})</option>`
        ).join('');
        const rows = this.data.businesses.map(business => `
            <tr data-business-id="${business.id}">
                <td>${business.name}</td>
                <td>${business.owner}</td>
                <td>${business.type}</td>
                <td>${this.getStatusBadge(business.status)}</td>
                <td>${business.employees}</td>
                <td>$${business.revenueWeek.toLocaleString()}</td>
                <td>${this.getStatusBadge(business.licenseStatus)}</td>
                <td>${this.getStatusBadge(business.taxStatus)}</td>
                <td>
                    <div class="action-menu">
                        <button class="kebab-btn" data-menu-toggle="${business.id}">â‹¯</button>
                        <div class="action-dropdown" data-menu="${business.id}">
                            <button class="action-item" data-action="view" data-business-id="${business.id}">View Details</button>
                            <button class="action-item" data-action="transfer" data-business-id="${business.id}">Transfer Ownership</button>
                            <button class="action-item" data-action="remove" data-business-id="${business.id}">Remove Owner</button>
                        </div>
                    </div>
                </td>
            </tr>
        `).join('');

        return `
            <div class="businesses-page">
                <div class="page-title">Business Registry</div>
                <div class="create-business-card">
                    <h3>Create Business</h3>
                    <div class="create-business-grid">
                        <div class="form-group">
                            <label>Business Name</label>
                            <input type="text" class="form-input" id="create-business-name" placeholder="Business name">
                        </div>
                        <div class="form-group">
                            <label>Owner</label>
                            <select class="form-input" id="create-business-owner">
                                <option value="">Select citizen</option>
                                ${citizenOptions}
                            </select>
                        </div>
                        <div class="form-group">
                            <label>Type</label>
                            <select class="form-input" id="create-business-type">
                                <option>Mechanic</option>
                                <option>Restaurant</option>
                                <option>Cafe</option>
                                <option>Dealership</option>
                                <option>Retail</option>
                            </select>
                        </div>
                        <div class="form-group">
                            <label>Location</label>
                            <input type="text" class="form-input" id="create-business-location" placeholder="District or address">
                        </div>
                    </div>
                    <button class="btn-primary" id="create-business-btn">Create Business</button>
                </div>
                <div class="filter-bar">
                    <input type="text" class="search-input" placeholder="Search businesses by name or owner">
                    <select class="setting-select">
                        <option>All Types</option>
                        <option>Mechanic</option>
                        <option>Restaurant</option>
                        <option>Cafe</option>
                        <option>Dealership</option>
                    </select>
                    <select class="setting-select">
                        <option>All Status</option>
                        <option>Open</option>
                        <option>Closed</option>
                    </select>
                    <button class="btn-secondary">Export Report</button>
                    <button class="btn-primary">Open Compliance Review</button>
                </div>
                <div class="registry-layout">
                    <div class="table-container">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>Business</th>
                                    <th>Owner</th>
                                    <th>Type</th>
                                    <th>Status</th>
                                    <th>Employees</th>
                                    <th>Revenue (Week)</th>
                                    <th>License</th>
                                    <th>Tax Status</th>
                                    <th>Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${rows}
                            </tbody>
                        </table>
                    </div>
                    <div class="business-details-panel" id="business-details-panel">
                        ${this.renderBusinessDetails(this.data.businesses[0])}
                    </div>
                </div>
            </div>
        `;
    }

    renderBusinessDetails(business) {
        return `
            <div class="details-header">
                <h3>${business.name}</h3>
                <div class="details-subtitle">${business.type} - ${business.status}</div>
            </div>
            <div class="details-tabs">
                <button class="details-tab active" data-tab="overview">Overview</button>
                <button class="details-tab" data-tab="performance">Performance</button>
                <button class="details-tab" data-tab="employees">Employees</button>
                <button class="details-tab" data-tab="compliance">Compliance</button>
            </div>
            <div class="details-section active" data-tab-content="overview">
                <div class="detail-row"><span>Owner</span><strong>${business.owner}</strong></div>
                <div class="detail-row"><span>Location</span><strong>${business.location}</strong></div>
                <div class="detail-row"><span>Blip</span><strong>${business.blip} (${business.blipColor})</strong></div>
                <div class="detail-row"><span>Balance</span><strong>$${business.balance.toLocaleString()}</strong></div>
            </div>
            <div class="details-section" data-tab-content="performance">
                <div class="detail-row"><span>Sales Total</span><strong>$${business.salesTotal.toLocaleString()}</strong></div>
                <div class="detail-row"><span>Invoices</span><strong>${business.invoices}</strong></div>
                <div class="detail-row"><span>Average Sale</span><strong>$${business.avgSale.toLocaleString()}</strong></div>
                <div class="detail-row"><span>Peak Hours</span><strong>${business.peakHours}</strong></div>
            </div>
            <div class="details-section" data-tab-content="employees">
                <div class="detail-row"><span>Employee Count</span><strong>${business.employees}</strong></div>
                <div class="detail-row"><span>Average Wage</span><strong>$${business.wageAvg.toLocaleString()}</strong></div>
                <div class="detail-row"><span>Total Payroll</span><strong>$${business.payroll.toLocaleString()}</strong></div>
            </div>
            <div class="details-section" data-tab-content="compliance">
                <div class="detail-row"><span>License</span><strong>${business.licenseStatus}</strong></div>
                <div class="detail-row"><span>Tax Status</span><strong>${business.taxStatus}</strong></div>
                <div class="detail-row"><span>Permits</span><strong>${business.permits.join(', ')}</strong></div>
                <div class="detail-row"><span>Warnings</span><strong>${business.warnings.length ? business.warnings.join(', ') : 'None'}</strong></div>
            </div>
        `;
    }

    renderDetailsPage() {
        const business = this.data.businesses.find(item => item.id === this.currentBusinessId);
        if (!business) {
            return `
                <div class="business-details-page">
                    <div class="page-title">Business Details</div>
                    <p class="text-muted">Select a business from the registry.</p>
                </div>
            `;
        }

        const transactions = business.transactions.map(tx => `
            <tr>
                <td>${tx.date}</td>
                <td>${tx.type}</td>
                <td>$${tx.amount.toLocaleString()}</td>
                <td>${tx.note}</td>
            </tr>
        `).join('');

        const employees = business.employeesList.map(emp => `
            <tr>
                <td>${emp.name}</td>
                <td>${emp.role}</td>
                <td>$${emp.wage.toLocaleString()}</td>
                <td>${emp.activity}</td>
            </tr>
        `).join('');

        const activity = business.activityLog.map(entry => `
            <tr>
                <td>${entry.date}</td>
                <td>${entry.action}</td>
                <td>${entry.actor}</td>
            </tr>
        `).join('');

        return `
            <div class="business-details-page">
                <div class="details-hero">
                    <button class="btn-secondary" id="back-to-registry">Back to Registry</button>
                    <div>
                        <div class="page-title">${business.name}</div>
                        <div class="details-subtitle">${business.type} â€¢ ${business.status} â€¢ Owner: ${business.owner}</div>
                    </div>
                    <div class="details-actions">
                        ${business.owner === 'Unassigned' 
                            ? `<button class="btn-primary" data-action="assign" data-business-id="${business.id}">Assign Owner</button>`
                            : `
                                <button class="btn-secondary" data-action="transfer" data-business-id="${business.id}">Transfer Ownership</button>
                                <button class="btn-secondary" data-action="remove" data-business-id="${business.id}">Remove Owner</button>
                            `
                        }
                    </div>
                </div>

                <div class="details-grid">
                    <div class="panel-card">
                        <h3>Business Profile</h3>
                        <div class="detail-list">
                            <div class="detail-row"><span>Owner</span><strong>${business.owner}</strong></div>
                            <div class="detail-row"><span>Citizen ID</span><strong>${business.ownerId || 'N/A'}</strong></div>
                            <div class="detail-row"><span>Location</span><strong>${business.location}</strong></div>
                            <div class="detail-row"><span>Balance</span><strong>$${business.balance.toLocaleString()}</strong></div>
                            <div class="detail-row"><span>Blip</span><strong>${business.blip} (${business.blipColor})</strong></div>
                        </div>
                    </div>
                    <div class="panel-card">
                        <h3>Performance</h3>
                        <div class="detail-list">
                            <div class="detail-row"><span>Sales Total</span><strong>$${business.salesTotal.toLocaleString()}</strong></div>
                            <div class="detail-row"><span>Invoices</span><strong>${business.invoices}</strong></div>
                            <div class="detail-row"><span>Avg Sale</span><strong>$${business.avgSale.toLocaleString()}</strong></div>
                            <div class="detail-row"><span>Peak Hours</span><strong>${business.peakHours}</strong></div>
                        </div>
                    </div>
                    <div class="panel-card">
                        <h3>Compliance</h3>
                        <div class="detail-list">
                            <div class="detail-row"><span>License</span><strong>${business.licenseStatus}</strong></div>
                            <div class="detail-row"><span>Tax Status</span><strong>${business.taxStatus}</strong></div>
                            <div class="detail-row"><span>Permits</span><strong>${business.permits.join(', ') || 'None'}</strong></div>
                            <div class="detail-row"><span>Warnings</span><strong>${business.warnings.length ? business.warnings.join(', ') : 'None'}</strong></div>
                        </div>
                    </div>
                </div>

                <div class="details-section-block">
                    <h3>Transactions</h3>
                    <div class="table-container">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>Date</th>
                                    <th>Type</th>
                                    <th>Amount</th>
                                    <th>Note</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${transactions || `<tr><td colspan="4">No transactions recorded</td></tr>`}
                            </tbody>
                        </table>
                    </div>
                </div>

                <div class="details-section-block">
                    <h3>Employees</h3>
                    <div class="table-container">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>Name</th>
                                    <th>Role</th>
                                    <th>Wage</th>
                                    <th>Activity</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${employees || `<tr><td colspan="4">No employees listed</td></tr>`}
                            </tbody>
                        </table>
                    </div>
                </div>

                <div class="details-section-block">
                    <h3>Activity Log</h3>
                    <div class="table-container">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>Date</th>
                                    <th>Activity</th>
                                    <th>Actor</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${activity || `<tr><td colspan="3">No activity recorded</td></tr>`}
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
        `;
    }

    attachDetailsPageHandlers(container) {
        const backBtn = container.querySelector('#back-to-registry');
        if (backBtn) {
            backBtn.addEventListener('click', () => {
                this.currentPage = 'registry';
                this.renderPage('registry', container);
            });
        }

        container.querySelectorAll('[data-action="assign"]').forEach(btn => {
            btn.addEventListener('click', () => {
                const businessId = btn.dataset.businessId;
                const business = this.data.businesses.find(item => item.id === businessId);
                if (!business) return;

                this.showModal(`
                    <h3>Assign Owner</h3>
                    <p>Assign an owner to <strong>${business.name}</strong>:</p>
                    <select class="form-input" id="assign-owner">
                        ${this.citizens.map(citizen => `<option value="${citizen.name} (${citizen.citizenId})">${citizen.name} (${citizen.citizenId})</option>`).join('')}
                    </select>
                `, () => {
                    const newOwner = document.getElementById('assign-owner').value;
                    if (newOwner) {
                        business.owner = newOwner;
                        business.ownerId = newOwner.match(/\(([^)]+)\)/)?.[1] || '';
                        this.renderPage('details', container);
                    }
                });
            });
        });

        container.querySelectorAll('[data-action="transfer"]').forEach(btn => {
            btn.addEventListener('click', () => {
                const businessId = btn.dataset.businessId;
                const business = this.data.businesses.find(item => item.id === businessId);
                if (!business) return;

                this.showModal(`
                    <h3>Transfer Ownership</h3>
                    <p>Transfer <strong>${business.name}</strong> to:</p>
                    <select class="form-input" id="transfer-owner">
                        ${this.citizens.map(citizen => `<option value="${citizen.name} (${citizen.citizenId})">${citizen.name} (${citizen.citizenId})</option>`).join('')}
                    </select>
                `, () => {
                    const newOwner = document.getElementById('transfer-owner').value;
                    if (newOwner) {
                        business.owner = newOwner;
                        business.ownerId = newOwner.match(/\(([^)]+)\)/)?.[1] || business.ownerId;
                        this.renderPage('details', container);
                    }
                });
            });
        });

        container.querySelectorAll('[data-action="remove"]').forEach(btn => {
            btn.addEventListener('click', () => {
                const businessId = btn.dataset.businessId;
                const business = this.data.businesses.find(item => item.id === businessId);
                if (!business) return;

                this.showModal(`
                    <h3>Remove Owner</h3>
                    <p class="warning-text">Remove current owner from <strong>${business.name}</strong>?</p>
                `, () => {
                    business.owner = 'Unassigned';
                    business.ownerId = '';
                    this.renderPage('details', container);
                });
            });
        });
    }

    showModal(content, onConfirm) {
        const modal = document.createElement('div');
        modal.className = 'modal-overlay';
        modal.innerHTML = `
            <div class="modal-content">
                ${content}
                <div class="modal-actions">
                    <button class="btn-secondary" onclick="this.closest('.modal-overlay').remove()">Cancel</button>
                    <button class="btn-primary" id="modal-confirm">Confirm</button>
                </div>
            </div>
        `;
        document.body.appendChild(modal);

        document.getElementById('modal-confirm').addEventListener('click', () => {
            onConfirm();
            modal.remove();
        });
    }

    renderAnalytics() {
        return `
            <div class="businesses-page">
                <div class="page-title">Business Analytics</div>
                <div class="filter-bar">
                    <select class="analytics-filter">
                        <option>Last 7 Days</option>
                        <option>Last 30 Days</option>
                        <option>Last 90 Days</option>
                        <option>Year to Date</option>
                        <option>All Time</option>
                    </select>
                    <select class="analytics-filter">
                        <option>All Types</option>
                        <option>Mechanic</option>
                        <option>Restaurant</option>
                        <option>Dealership</option>
                        <option>Retail</option>
                    </select>
                    <select class="analytics-filter">
                        <option>All Districts</option>
                        <option>Downtown</option>
                        <option>Vespucci</option>
                        <option>Strawberry</option>
                        <option>Sandy Shores</option>
                    </select>
                    <button class="btn-primary">Export</button>
                </div>
                
                <div class="analytics-kpi-grid">
                    <div class="analytics-kpi-card">
                        <div class="kpi-icon" style="background: var(--success-bg); color: var(--success);">
                            <span>$</span>
                        </div>
                        <div>
                            <div class="kpi-label">Total Revenue</div>
                            <div class="kpi-value">$1.2M</div>
                            <div class="kpi-change positive">+12.5% vs last period</div>
                        </div>
                    </div>
                    <div class="analytics-kpi-card">
                        <div class="kpi-icon" style="background: var(--info-bg); color: var(--info);">
                            <span>ðŸ“Š</span>
                        </div>
                        <div>
                            <div class="kpi-label">Active Businesses</div>
                            <div class="kpi-value">47</div>
                            <div class="kpi-change positive">+3 new this month</div>
                        </div>
                    </div>
                    <div class="analytics-kpi-card">
                        <div class="kpi-icon" style="background: var(--warning-bg); color: var(--warning);">
                            <span>ðŸ‘¥</span>
                        </div>
                        <div>
                            <div class="kpi-label">Employment</div>
                            <div class="kpi-value">284</div>
                            <div class="kpi-change">$282k total payroll</div>
                        </div>
                    </div>
                    <div class="analytics-kpi-card">
                        <div class="kpi-icon" style="background: var(--danger-bg); color: var(--danger);">
                            <span>âš </span>
                        </div>
                        <div>
                            <div class="kpi-label">Compliance Issues</div>
                            <div class="kpi-value">5</div>
                            <div class="kpi-change negative">+2 since last week</div>
                        </div>
                    </div>
                </div>

                <div class="analytics-charts-grid">
                    <div class="analytics-chart-card full-width">
                        <div class="chart-header">
                            <h3>Revenue Trend (30 Days)</h3>
                            <div class="chart-legend">
                                <span class="legend-item"><span class="legend-dot" style="background: var(--primary);"></span> Revenue</span>
                                <span class="legend-item"><span class="legend-dot" style="background: var(--accent);"></span> Expenses</span>
                            </div>
                        </div>
                        <div class="line-chart">
                            <div class="line-chart-bars">
                                <div class="line-chart-bar" style="height: 40%"><span class="bar-tooltip">$42k</span></div>
                                <div class="line-chart-bar" style="height: 55%"><span class="bar-tooltip">$58k</span></div>
                                <div class="line-chart-bar" style="height: 50%"><span class="bar-tooltip">$52k</span></div>
                                <div class="line-chart-bar" style="height: 65%"><span class="bar-tooltip">$68k</span></div>
                                <div class="line-chart-bar" style="height: 70%"><span class="bar-tooltip">$74k</span></div>
                                <div class="line-chart-bar" style="height: 60%"><span class="bar-tooltip">$63k</span></div>
                                <div class="line-chart-bar" style="height: 75%"><span class="bar-tooltip">$78k</span></div>
                                <div class="line-chart-bar" style="height: 80%"><span class="bar-tooltip">$84k</span></div>
                                <div class="line-chart-bar" style="height: 85%"><span class="bar-tooltip">$89k</span></div>
                                <div class="line-chart-bar" style="height: 78%"><span class="bar-tooltip">$82k</span></div>
                            </div>
                            <div class="chart-x-labels">
                                <span>Week 1</span><span>Week 2</span><span>Week 3</span><span>Week 4</span>
                            </div>
                        </div>
                    </div>

                    <div class="analytics-chart-card">
                        <h3>Revenue by Business Type</h3>
                        <div class="chart-list">
                            <div class="chart-row">
                                <span class="chart-label">Mechanic</span>
                                <div class="chart-bar-container">
                                    <div class="chart-bar-fill" style="width: 80%; background: var(--primary);"></div>
                                </div>
                                <span class="chart-value">$420k</span>
                            </div>
                            <div class="chart-row">
                                <span class="chart-label">Dealership</span>
                                <div class="chart-bar-container">
                                    <div class="chart-bar-fill" style="width: 65%; background: var(--accent);"></div>
                                </div>
                                <span class="chart-value">$350k</span>
                            </div>
                            <div class="chart-row">
                                <span class="chart-label">Restaurant</span>
                                <div class="chart-bar-container">
                                    <div class="chart-bar-fill" style="width: 45%; background: var(--info);"></div>
                                </div>
                                <span class="chart-value">$220k</span>
                            </div>
                            <div class="chart-row">
                                <span class="chart-label">Retail</span>
                                <div class="chart-bar-container">
                                    <div class="chart-bar-fill" style="width: 30%; background: var(--warning);"></div>
                                </div>
                                <span class="chart-value">$140k</span>
                            </div>
                            <div class="chart-row">
                                <span class="chart-label">Other</span>
                                <div class="chart-bar-container">
                                    <div class="chart-bar-fill" style="width: 20%; background: var(--text-muted);"></div>
                                </div>
                                <span class="chart-value">$70k</span>
                            </div>
                        </div>
                    </div>

                    <div class="analytics-chart-card">
                        <h3>Top 5 Businesses</h3>
                        <div class="top-list">
                            <div class="top-list-item">
                                <div class="top-rank">1</div>
                                <div class="top-info">
                                    <div class="top-name">Harmony Customs</div>
                                    <div class="top-meta">Mechanic â€¢ $120k revenue</div>
                                </div>
                            </div>
                            <div class="top-list-item">
                                <div class="top-rank">2</div>
                                <div class="top-info">
                                    <div class="top-name">PDM</div>
                                    <div class="top-meta">Dealership â€¢ $105k revenue</div>
                                </div>
                            </div>
                            <div class="top-list-item">
                                <div class="top-rank">3</div>
                                <div class="top-info">
                                    <div class="top-name">Burger Shot</div>
                                    <div class="top-meta">Restaurant â€¢ $96k revenue</div>
                                </div>
                            </div>
                            <div class="top-list-item">
                                <div class="top-rank">4</div>
                                <div class="top-info">
                                    <div class="top-name">LS Customs</div>
                                    <div class="top-meta">Mechanic â€¢ $88k revenue</div>
                                </div>
                            </div>
                            <div class="top-list-item">
                                <div class="top-rank">5</div>
                                <div class="top-info">
                                    <div class="top-name">Ammunation</div>
                                    <div class="top-meta">Retail â€¢ $72k revenue</div>
                                </div>
                            </div>
                        </div>
                    </div>

                    <div class="analytics-chart-card">
                        <h3>District Performance</h3>
                        <div class="donut-chart-container">
                            <div class="donut-stats">
                                <div class="donut-stat">
                                    <span class="donut-dot" style="background: var(--primary);"></span>
                                    <span>Downtown</span>
                                    <strong>42%</strong>
                                </div>
                                <div class="donut-stat">
                                    <span class="donut-dot" style="background: var(--accent);"></span>
                                    <span>Vespucci</span>
                                    <strong>28%</strong>
                                </div>
                                <div class="donut-stat">
                                    <span class="donut-dot" style="background: var(--info);"></span>
                                    <span>Strawberry</span>
                                    <strong>18%</strong>
                                </div>
                                <div class="donut-stat">
                                    <span class="donut-dot" style="background: var(--warning);"></span>
                                    <span>Sandy Shores</span>
                                    <strong>12%</strong>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        `;
    }

    renderEmployees() {
        return `
            <div class="businesses-page">
                <div class="page-title">Employees Overview</div>
                <div class="dashboard-cards">
                    <div class="dash-card">
                        <div>
                            <div class="dash-card-label">Total Employed</div>
                            <div class="dash-card-value">${this.data.stats.totalEmployees}</div>
                        </div>
                    </div>
                    <div class="dash-card">
                        <div>
                            <div class="dash-card-label">Businesses with Most Staff</div>
                            <div class="dash-card-value">Burger Shot</div>
                        </div>
                    </div>
                    <div class="dash-card">
                        <div>
                            <div class="dash-card-label">High Wage Alerts</div>
                            <div class="dash-card-value">3</div>
                        </div>
                    </div>
                    <div class="dash-card">
                        <div>
                            <div class="dash-card-label">Zero Staff Flags</div>
                            <div class="dash-card-value">2</div>
                        </div>
                    </div>
                </div>
                <div class="table-container">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>Business</th>
                                <th>Employees</th>
                                <th>Average Wage</th>
                                <th>Total Payroll</th>
                                <th>Notes</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr>
                                <td>Harmony Customs</td>
                                <td>18</td>
                                <td>$3,200</td>
                                <td>$72,000</td>
                                <td>Normal</td>
                            </tr>
                            <tr>
                                <td>Burger Shot</td>
                                <td>42</td>
                                <td>$1,900</td>
                                <td>$96,000</td>
                                <td>Most staff</td>
                            </tr>
                            <tr>
                                <td>Bean Machine</td>
                                <td>6</td>
                                <td>$1,200</td>
                                <td>$9,800</td>
                                <td>Under review</td>
                            </tr>
                            <tr>
                                <td>PDM</td>
                                <td>25</td>
                                <td>$4,200</td>
                                <td>$105,000</td>
                                <td>High wages</td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        `;
    }

    renderCompliance() {
        return `
            <div class="businesses-page">
                <div class="compliance-header">
                    <h1 class="page-title">Business Compliance</h1>
                    <div class="header-actions">
                        <button class="btn-primary">Issue Compliance Notice</button>
                        <button class="btn-secondary">Generate Report</button>
                    </div>
                </div>

                <div class="compliance-dashboard">
                    <div class="compliance-kpi">
                        <div class="compliance-gauge">
                            <div class="gauge-value" style="color: var(--success);">91%</div>
                            <div class="gauge-label">Compliance Rate</div>
                        </div>
                    </div>
                    <div class="compliance-stats">
                        <div class="compliance-stat-item">
                            <div class="stat-icon" style="background: var(--success-bg); color: var(--success);">âœ“</div>
                            <div>
                                <div class="stat-value">108</div>
                                <div class="stat-label">Fully Compliant</div>
                            </div>
                        </div>
                        <div class="compliance-stat-item">
                            <div class="stat-icon" style="background: var(--warning-bg); color: var(--warning);">âš </div>
                            <div>
                                <div class="stat-value">9</div>
                                <div class="stat-label">Minor Issues</div>
                            </div>
                        </div>
                        <div class="compliance-stat-item">
                            <div class="stat-icon" style="background: var(--danger-bg); color: var(--danger);">âœ•</div>
                            <div>
                                <div class="stat-value">5</div>
                                <div class="stat-label">Non-Compliant</div>
                            </div>
                        </div>
                    </div>
                </div>

                <div class="compliance-filters">
                    <select class="filter-select">
                        <option>All Businesses</option>
                        <option>Fully Compliant</option>
                        <option>Minor Issues</option>
                        <option>Non-Compliant</option>
                    </select>
                    <select class="filter-select">
                        <option>All Types</option>
                        <option>Mechanic</option>
                        <option>Restaurant</option>
                        <option>Dealership</option>
                        <option>Retail</option>
                    </select>
                    <input type="text" placeholder="Search businesses..." class="search-input">
                </div>

                <div class="compliance-table-container">
                    <table class="data-table compliance-table">
                        <thead>
                            <tr>
                                <th>Business</th>
                                <th>License</th>
                                <th>Permits</th>
                                <th>Tax Status</th>
                                <th>Health/Safety</th>
                                <th>Compliance Score</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr class="compliance-row compliant">
                                <td>
                                    <div class="business-cell">
                                        <strong>Harmony Customs</strong>
                                        <span>Mechanic â€¢ Downtown</span>
                                    </div>
                                </td>
                                <td><span class="status-badge active">Active</span></td>
                                <td><span class="permits-chip">Repair, Towing</span></td>
                                <td><span class="status-badge active">Current</span></td>
                                <td><span class="status-badge active">Pass</span></td>
                                <td>
                                    <div class="compliance-score">
                                        <div class="score-bar" style="width: 100%; background: var(--success);"></div>
                                        <span class="score-text">100%</span>
                                    </div>
                                </td>
                                <td>
                                    <button class="btn-icon" title="View Details">ðŸ‘</button>
                                    <button class="btn-icon" title="Audit">ðŸ“‹</button>
                                </td>
                            </tr>
                            <tr class="compliance-row warning">
                                <td>
                                    <div class="business-cell">
                                        <strong>Burger Shot</strong>
                                        <span>Restaurant â€¢ Strawberry</span>
                                    </div>
                                </td>
                                <td><span class="status-badge active">Active</span></td>
                                <td><span class="permits-chip">Food, Alcohol</span></td>
                                <td><span class="status-badge warning">Late</span></td>
                                <td><span class="status-badge active">Pass</span></td>
                                <td>
                                    <div class="compliance-score">
                                        <div class="score-bar" style="width: 75%; background: var(--warning);"></div>
                                        <span class="score-text">75%</span>
                                    </div>
                                </td>
                                <td>
                                    <button class="btn-icon" title="View Details">ðŸ‘</button>
                                    <button class="btn-icon" title="Send Notice">ðŸ“§</button>
                                </td>
                            </tr>
                            <tr class="compliance-row danger">
                                <td>
                                    <div class="business-cell">
                                        <strong>Bean Machine</strong>
                                        <span>Cafe â€¢ Vespucci</span>
                                    </div>
                                </td>
                                <td><span class="status-badge error">Suspended</span></td>
                                <td><span class="permits-chip">Food</span></td>
                                <td><span class="status-badge error">Delinquent</span></td>
                                <td><span class="status-badge error">Fail</span></td>
                                <td>
                                    <div class="compliance-score">
                                        <div class="score-bar" style="width: 30%; background: var(--danger);"></div>
                                        <span class="score-text">30%</span>
                                    </div>
                                </td>
                                <td>
                                    <button class="btn-icon" title="View Details">ðŸ‘</button>
                                    <button class="btn-icon" title="Enforcement Action">âš </button>
                                </td>
                            </tr>
                            <tr class="compliance-row compliant">
                                <td>
                                    <div class="business-cell">
                                        <strong>PDM</strong>
                                        <span>Dealership â€¢ Downtown</span>
                                    </div>
                                </td>
                                <td><span class="status-badge active">Active</span></td>
                                <td><span class="permits-chip">Sales, Finance</span></td>
                                <td><span class="status-badge active">Current</span></td>
                                <td><span class="status-badge active">Pass</span></td>
                                <td>
                                    <div class="compliance-score">
                                        <div class="score-bar" style="width: 95%; background: var(--success);"></div>
                                        <span class="score-text">95%</span>
                                    </div>
                                </td>
                                <td>
                                    <button class="btn-icon" title="View Details">ðŸ‘</button>
                                    <button class="btn-icon" title="Audit">ðŸ“‹</button>
                                </td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        `;
    }

    renderTaxes() {
        return `
            <div class="businesses-page">
                <div class="taxes-header">
                    <h1 class="page-title">Business Taxes & Revenue</h1>
                    <div class="header-actions">
                        <button class="btn-primary">Generate Tax Report</button>
                        <button class="btn-secondary">Send Payment Reminders</button>
                    </div>
                </div>

                <div class="taxes-dashboard-grid">
                    <div class="taxes-summary-card">
                        <div class="summary-header">
                            <h3>Revenue Summary</h3>
                            <select class="period-select">
                                <option>This Month</option>
                                <option>This Quarter</option>
                                <option>This Year</option>
                                <option>Year to Date</option>
                            </select>
                        </div>
                        <div class="summary-metric-grid">
                            <div class="summary-metric">
                                <div class="metric-icon" style="background: var(--success-bg); color: var(--success);">$</div>
                                <div>
                                    <div class="metric-label">Total Collected</div>
                                    <div class="metric-value">$1,245,000</div>
                                    <div class="metric-trend positive">+8.2% vs last month</div>
                                </div>
                            </div>
                            <div class="summary-metric">
                                <div class="metric-icon" style="background: var(--warning-bg); color: var(--warning);">ðŸ’°</div>
                                <div>
                                    <div class="metric-label">Outstanding</div>
                                    <div class="metric-value">$62,000</div>
                                    <div class="metric-trend">17 businesses</div>
                                </div>
                            </div>
                            <div class="summary-metric">
                                <div class="metric-icon" style="background: var(--info-bg); color: var(--info);">ðŸ“ˆ</div>
                                <div>
                                    <div class="metric-label">Average Tax Rate</div>
                                    <div class="metric-value">7.2%</div>
                                    <div class="metric-trend">Across all businesses</div>
                                </div>
                            </div>
                            <div class="summary-metric">
                                <div class="metric-icon" style="background: var(--danger-bg); color: var(--danger);">âš </div>
                                <div>
                                    <div class="metric-label">Delinquent</div>
                                    <div class="metric-value">$24,600</div>
                                    <div class="metric-trend negative">5 businesses overdue >30 days</div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>

                <div class="taxes-viz-grid">
                    <div class="taxes-chart-card">
                        <h3>Revenue Collection Trend</h3>
                        <div class="revenue-chart">
                            <div class="revenue-bars">
                                <div class="revenue-bar" style="height: 65%"><span class="bar-label">$72k</span></div>
                                <div class="revenue-bar" style="height: 72%"><span class="bar-label">$84k</span></div>
                                <div class="revenue-bar" style="height: 68%"><span class="bar-label">$78k</span></div>
                                <div class="revenue-bar" style="height: 80%"><span class="bar-label">$92k</span></div>
                                <div class="revenue-bar" style="height: 85%"><span class="bar-label">$98k</span></div>
                                <div class="revenue-bar" style="height: 90%"><span class="bar-label">$105k</span></div>
                            </div>
                            <div class="revenue-x-labels">
                                <span>Jan</span><span>Feb</span><span>Mar</span><span>Apr</span><span>May</span><span>Jun</span>
                            </div>
                        </div>
                    </div>

                    <div class="taxes-chart-card">
                        <h3>Top Tax Contributors</h3>
                        <div class="contributors-list">
                            <div class="contributor-item">
                                <span class="contributor-rank">1</span>
                                <div class="contributor-info">
                                    <div class="contributor-name">PDM</div>
                                    <div class="contributor-meta">Dealership â€¢ 8.5% rate</div>
                                </div>
                                <div class="contributor-amount">$42,500</div>
                            </div>
                            <div class="contributor-item">
                                <span class="contributor-rank">2</span>
                                <div class="contributor-info">
                                    <div class="contributor-name">Harmony Customs</div>
                                    <div class="contributor-meta">Mechanic â€¢ 7% rate</div>
                                </div>
                                <div class="contributor-amount">$38,200</div>
                            </div>
                            <div class="contributor-item">
                                <span class="contributor-rank">3</span>
                                <div class="contributor-info">
                                    <div class="contributor-name">Burger Shot</div>
                                    <div class="contributor-meta">Restaurant â€¢ 7% rate</div>
                                </div>
                                <div class="contributor-amount">$28,100</div>
                            </div>
                            <div class="contributor-item">
                                <span class="contributor-rank">4</span>
                                <div class="contributor-info">
                                    <div class="contributor-name">Ammunation</div>
                                    <div class="contributor-meta">Retail â€¢ 9% rate</div>
                                </div>
                                <div class="contributor-amount">$24,800</div>
                            </div>
                            <div class="contributor-item">
                                <span class="contributor-rank">5</span>
                                <div class="contributor-info">
                                    <div class="contributor-name">LS Customs</div>
                                    <div class="contributor-meta">Mechanic â€¢ 7% rate</div>
                                </div>
                                <div class="contributor-amount">$22,600</div>
                            </div>
                        </div>
                    </div>
                </div>

                <div class="taxes-filters">
                    <input type="text" placeholder="Search businesses..." class="search-input">
                    <select class="filter-select">
                        <option>All Payment Status</option>
                        <option>Current</option>
                        <option>Late (1-30 days)</option>
                        <option>Delinquent (>30 days)</option>
                    </select>
                    <select class="filter-select">
                        <option>All Types</option>
                        <option>Mechanic</option>
                        <option>Restaurant</option>
                        <option>Dealership</option>
                        <option>Retail</option>
                    </select>
                </div>

                <div class="taxes-table-container">
                    <table class="data-table taxes-table">
                        <thead>
                            <tr>
                                <th>Business</th>
                                <th>Tax Rate</th>
                                <th>Monthly Revenue</th>
                                <th>Tax Due</th>
                                <th>Paid This Month</th>
                                <th>Outstanding</th>
                                <th>Status</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr class="tax-row current">
                                <td>
                                    <div class="business-cell">
                                        <strong>Harmony Customs</strong>
                                        <span>Mechanic â€¢ Downtown</span>
                                    </div>
                                </td>
                                <td><strong>7%</strong></td>
                                <td>$545,000</td>
                                <td>$38,150</td>
                                <td class="paid-amount">$38,150</td>
                                <td class="outstanding-zero">$0</td>
                                <td><span class="status-badge active">Current</span></td>
                                <td>
                                    <button class="btn-icon" title="View History">ðŸ“Š</button>
                                    <button class="btn-icon" title="Generate Invoice">ðŸ“„</button>
                                </td>
                            </tr>
                            <tr class="tax-row late">
                                <td>
                                    <div class="business-cell">
                                        <strong>Burger Shot</strong>
                                        <span>Restaurant â€¢ Strawberry</span>
                                    </div>
                                </td>
                                <td><strong>7%</strong></td>
                                <td>$401,000</td>
                                <td>$28,070</td>
                                <td class="paid-amount">$18,000</td>
                                <td class="outstanding-late">$10,070</td>
                                <td><span class="status-badge warning">Late (12 days)</span></td>
                                <td>
                                    <button class="btn-icon" title="Send Reminder">ðŸ“§</button>
                                    <button class="btn-icon" title="Apply Late Fee">ðŸ’°</button>
                                </td>
                            </tr>
                            <tr class="tax-row delinquent">
                                <td>
                                    <div class="business-cell">
                                        <strong>Bean Machine</strong>
                                        <span>Cafe â€¢ Vespucci</span>
                                    </div>
                                </td>
                                <td><strong>7%</strong></td>
                                <td>$132,000</td>
                                <td>$9,240</td>
                                <td class="paid-amount">$0</td>
                                <td class="outstanding-delinquent">$9,240</td>
                                <td><span class="status-badge error">Delinquent (42 days)</span></td>
                                <td>
                                    <button class="btn-icon" title="Enforcement Action">âš </button>
                                    <button class="btn-icon" title="Revoke License">ðŸš«</button>
                                </td>
                            </tr>
                            <tr class="tax-row current">
                                <td>
                                    <div class="business-cell">
                                        <strong>PDM</strong>
                                        <span>Dealership â€¢ Downtown</span>
                                    </div>
                                </td>
                                <td><strong>8.5%</strong></td>
                                <td>$500,000</td>
                                <td>$42,500</td>
                                <td class="paid-amount">$42,500</td>
                                <td class="outstanding-zero">$0</td>
                                <td><span class="status-badge active">Current</span></td>
                                <td>
                                    <button class="btn-icon" title="View History">ðŸ“Š</button>
                                    <button class="btn-icon" title="Generate Invoice">ðŸ“„</button>
                                </td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        `;
    }

    renderAuditLog() {
        const rows = this.data.auditLog.map(entry => `
            <tr>
                <td>${entry.timestamp}</td>
                <td>${entry.action}</td>
                <td>${entry.business}</td>
                <td>${entry.type}</td>
            </tr>
        `).join('');

        return `
            <div class="businesses-page">
                <div class="page-title">Audit Log</div>
                <div class="filter-bar">
                    <input type="text" class="search-input" placeholder="Filter by business or action">
                    <select class="setting-select">
                        <option>All Actions</option>
                        <option>Compliance</option>
                        <option>Tax Enforcement</option>
                        <option>Licensing</option>
                        <option>Policy</option>
                    </select>
                    <select class="setting-select">
                        <option>Last 7 Days</option>
                        <option>Last 30 Days</option>
                        <option>Last 90 Days</option>
                    </select>
                </div>
                <div class="table-container">
                    <table class="data-table">
                        <thead>
                            <tr>
                                <th>Timestamp</th>
                                <th>Action</th>
                                <th>Business</th>
                                <th>Type</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${rows}
                        </tbody>
                    </table>
                </div>
            </div>
        `;
    }

    renderSettings() {
        return `
            <div class="businesses-page">
                <div class="page-title">Business Oversight Settings</div>
                <div class="panel-card">
                    <h3>Mayor Access</h3>
                    <div class="detail-list">
                        <div class="detail-row"><span>Access Level</span><strong>Mayor Only</strong></div>
                        <div class="detail-row"><span>Audit Logging</span><strong>Enabled</strong></div>
                        <div class="detail-row"><span>Auto Compliance Alerts</span><strong>Enabled</strong></div>
                        <div class="detail-row"><span>Tax Escalation Rules</span><strong>Enabled</strong></div>
                    </div>
                </div>
                <div class="panel-card">
                    <h3>Policy Notes</h3>
                    <p class="text-muted">This module is read-only for business owners. All actions are reserved for government oversight and enforcement.</p>
                </div>
            </div>
        `;
    }

    attachRegistryHandlers(container) {
        const rows = container.querySelectorAll('[data-business-id]');
        const detailsPanel = container.querySelector('#business-details-panel');
        const createBtn = container.querySelector('#create-business-btn');
        const createName = container.querySelector('#create-business-name');
        const createOwner = container.querySelector('#create-business-owner');
        const createType = container.querySelector('#create-business-type');
        const createLocation = container.querySelector('#create-business-location');

        if (!detailsPanel) return;

        const setActiveRow = (row) => {
            rows.forEach(r => r.classList.remove('active-row'));
            row.classList.add('active-row');
        };

        rows.forEach(row => {
            row.addEventListener('click', () => {
                const businessId = row.dataset.businessId;
                const business = this.data.businesses.find(item => item.id === businessId);
                if (!business) return;
                this.openBusinessDetails(businessId, container.closest('#businesses-content'));
                setActiveRow(row);
            });
        });

        container.addEventListener('click', (e) => {
            const toggle = e.target.closest('[data-menu-toggle]');
            if (toggle) {
                e.stopPropagation();
                const menuId = toggle.dataset.menuToggle;
                container.querySelectorAll('.action-dropdown').forEach(menu => {
                    menu.classList.toggle('open', menu.dataset.menu === menuId);
                });
                return;
            }

            const action = e.target.closest('.action-item');
            if (action) {
                e.stopPropagation();
                const actionType = action.dataset.action;
                const businessId = action.dataset.businessId;
                const business = this.data.businesses.find(item => item.id === businessId);
                if (!business) return;

                if (actionType === 'view') {
                    this.openBusinessDetails(businessId, container.closest('#businesses-content'));
                } else if (actionType === 'transfer') {
                    this.showModal(`
                        <h3>Transfer Ownership</h3>
                        <p>Transfer <strong>${business.name}</strong> to:</p>
                        <select class="form-input" id="transfer-owner">
                            ${this.citizens.map(citizen => `<option value="${citizen.name} (${citizen.citizenId})">${citizen.name} (${citizen.citizenId})</option>`).join('')}
                        </select>
                    `, () => {
                        const newOwner = document.getElementById('transfer-owner').value;
                        if (newOwner) {
                            business.owner = newOwner;
                            this.renderPage('registry', container.closest('#businesses-content'));
                        }
                    });
                } else if (actionType === 'remove') {
                    this.showModal(`
                        <h3>Remove Owner</h3>
                        <p class="warning-text">Remove current owner from <strong>${business.name}</strong>?</p>
                    `, () => {
                        business.owner = 'Unassigned';
                        this.renderPage('registry', container.closest('#businesses-content'));
                    });
                }

                container.querySelectorAll('.action-dropdown').forEach(menu => menu.classList.remove('open'));
                return;
            }

            container.querySelectorAll('.action-dropdown').forEach(menu => menu.classList.remove('open'));
        });

        if (createBtn) {
            createBtn.addEventListener('click', () => {
                const name = createName?.value.trim();
                const owner = createOwner?.value;
                const type = createType?.value;
                const location = createLocation?.value.trim();

                if (!name || !owner) {
                    alert('Business name and owner are required.');
                    return;
                }

                const newBusiness = {
                    id: `BUS-${Math.floor(1000 + Math.random() * 9000)}`,
                    name,
                    owner,
                    ownerId: owner.match(/\(([^)]+)\)/)?.[1] || 'Unassigned',
                    type,
                    status: 'Open',
                    employees: 0,
                    revenueWeek: 0,
                    licenseStatus: 'Pending',
                    taxStatus: 'Current',
                    balance: 0,
                    blip: name,
                    blipColor: 'Blue',
                    location: location || 'Unassigned',
                    salesTotal: 0,
                    invoices: 0,
                    avgSale: 0,
                    peakHours: 'N/A',
                    payroll: 0,
                    wageAvg: 0,
                    permits: [],
                    taxDebt: 0,
                    warnings: [],
                    employeesList: [],
                    transactions: [],
                    activityLog: []
                };

                this.data.businesses.unshift(newBusiness);
                this.renderPage('registry', container.closest('#businesses-content'));
            });
        }

        if (rows[0]) {
            setActiveRow(rows[0]);
            this.attachDetailsTabs(detailsPanel);
        }
    }

    attachDetailsTabs(panel) {
        const tabs = panel.querySelectorAll('.details-tab');
        const sections = panel.querySelectorAll('.details-section');

        tabs.forEach(tab => {
            tab.addEventListener('click', () => {
                tabs.forEach(t => t.classList.remove('active'));
                sections.forEach(s => s.classList.remove('active'));
                tab.classList.add('active');
                const target = panel.querySelector(`[data-tab-content="${tab.dataset.tab}"]`);
                if (target) target.classList.add('active');
            });
        });
    }

    getStatusBadge(status) {
        const normalized = status.toLowerCase();
        let className = 'neutral';

        if (normalized === 'open' || normalized === 'active' || normalized === 'current') {
            className = 'active';
        } else if (normalized === 'closed' || normalized === 'suspended') {
            className = 'inactive';
        } else if (normalized === 'late') {
            className = 'warning';
        } else if (normalized === 'delinquent') {
            className = 'error';
        }

        return `<span class="status-badge ${className}">${status}</span>`;
    }
}

