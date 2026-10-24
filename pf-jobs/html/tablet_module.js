// pf-jobs tablet module
// Loaded into pf-tablet NUI at runtime when pf-jobs is started.
// This file mounts the pf-jobs app UIs (Gruppe6 + Garbage) into the pf-tablet window system.

(function () {
    const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'pf-tablet';

    // Scoreboard rendering is owned by pf-tablet/html/scoreboard.js.
    // pf-jobs module intentionally does not register its own scoreboard listeners.

    // ---- Gruppe6 state + UI ----
    window.__G6_STATE__ = window.__G6_STATE__ || {
        searching: false,
        xp: 0,
        level: 1,
        contracts: [],
        activeContract: null,
        groups: {},
    };

    function g6RefreshContractDisplay() {
        const contracts = window.__G6_STATE__.contracts || [];
        const activeContract = window.__G6_STATE__.activeContract;
        const searching = !!window.__G6_STATE__.searching;

        if (activeContract) {
            $('#g6-contract-card').show();
            $('#g6-waiting-card').hide();
            $('#g6-tier-badge').text('Tier ' + (activeContract.tier || '1'));
            $('#g6-vehicle-name').text(activeContract.vehicle || 'Speedo');
            $('#g6-contract-type').text(activeContract.contractType || 'Bank Delivery');
            $('#g6-bags').text(activeContract.bags || '12');
            $('#g6-payout').text('$' + (activeContract.payout || 0).toLocaleString());
            $('#g6-maxgroup').text(activeContract.maxGroup || '2');
            $('#g6-start-contract').text('End Contract Early').data('action', 'end');
        } else {
            $('#g6-contract-card').hide();
            $('#g6-waiting-card').show();
            $('#g6-waiting-subtitle').text(searching ? 'Searching for contracts...' : contracts.length > 0 ? 'Accept a contract from the list' : 'Go to Work tab to start searching');
        }

        if ($('.g6-tab-inline.active').data('g6-tab') === 'contracts') {
            g6RenderContractsList(contracts);
        }

        const xp = Number(window.__G6_STATE__.xp || 0);
        const level = Number(window.__G6_STATE__.level || 1);
        $('#g6-level').text(level);

        const thresholds = [0, 1000, 5000, 10000, 15000, 30000];
        const cur = thresholds[level - 1] || 0;
        const next = thresholds[level] || thresholds[thresholds.length - 1];
        const inLevel = Math.max(0, xp - cur);
        const need = Math.max(1, next - cur);
        const pct = Math.min(100, (inLevel / need) * 100);
        $('#g6-xpbar-top').css('width', pct + '%');
        $('#g6-xp-text').text(`${inLevel} / ${need} XP`);
    }

    function g6RenderContractsList(contracts) {
        const activeContract = window.__G6_STATE__.activeContract;

        if (activeContract) {
            $('#g6-right-pane').html(`
                <div class="g6-empty-state">
                    <div style="font-size:48px;margin-bottom:16px;opacity:.3;">🛡️</div>
                    <div style="color:#e5e7eb;font-size:16px;">Contract in progress</div>
                    <div style="color:#94a3b8;font-size:14px;margin-top:8px;">Finish or end your active contract to view new offers</div>
                </div>
            `);
            return;
        }

        if (!contracts || contracts.length === 0) {
            $('#g6-right-pane').html(`
                <div class="g6-empty-state">
                    <div style="font-size:48px;margin-bottom:16px;opacity:.3;">📋</div>
                    <div style="color:#94a3b8;font-size:16px;">No contracts available</div>
                    <div style="color:#64748b;font-size:14px;margin-top:8px;">Go to Work tab to start searching</div>
                </div>
            `);
            return;
        }

        const cards = contracts.slice(0, 3).map((c, idx) => `
            <div class="g6-contract-card-available" data-contract-id="${idx}">
                <div class="g6-tier-badge">Tier ${c.tier || 1}</div>
                <div class="g6-vehicle-name">${c.vehicle || 'Speedo'}</div>
                <div class="g6-rank-badge">
                    <span class="g6-wing left">🪽</span>
                    <div class="g6-rank-circle"><span class="g6-rank-star">⭐</span></div>
                    <span class="g6-wing right">🪽</span>
                </div>
                <div class="g6-info-rows">
                    <div class="g6-info-row"><span class="g6-info-label"><span class="g6-info-icon">📦</span> Type</span><span class="g6-info-value">${c.contractType || 'Bank Delivery'}</span></div>
                    <div class="g6-info-row"><span class="g6-info-label"><span class="g6-info-icon">💼</span> Bags</span><span class="g6-info-value">${c.bags || 12}</span></div>
                    <div class="g6-info-row"><span class="g6-info-label"><span class="g6-info-icon">💰</span> Payout</span><span class="g6-info-value">$${(c.payout || 0).toLocaleString()}</span></div>
                    <div class="g6-info-row"><span class="g6-info-label"><span class="g6-info-icon">👥</span> Max Group</span><span class="g6-info-value">${c.maxGroup || 2}</span></div>
                </div>
                <button class="g6-accept-contract-btn" data-contract-id="${idx}">Accept Contract</button>
            </div>
        `).join('');

        $('#g6-right-pane').html(`
            <div class="g6-contracts-list">
                <div class="g6-contracts-header">
                    <div style="color:#e5e7eb;font-weight:700;font-size:18px;">Available Contracts</div>
                    <div style="color:#94a3b8;font-size:13px;">${contracts.length} contract${contracts.length !== 1 ? 's' : ''} available</div>
                </div>
                <div class="g6-contracts-row">
                    ${cards}
                </div>
            </div>
        `);
    }

    function g6RenderWorkPane() {
        const searching = !!window.__G6_STATE__.searching;
        $('#g6-right-pane').html(`
            <div class="g6-card" style="background:rgba(255,255,255,0.05);border:1px solid rgba(74, 217, 222,0.15);border-radius:16px;padding:24px;">
                <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:20px;">
                    <div style="color:#f1f5f9;font-weight:700;font-size:20px;">Work Status</div>
                    <div>
                        <button id="g6-start-search" class="g6-search-btn" style="${searching ? 'display:none;' : ''}">Start Searching</button>
                        <button id="g6-stop-search" class="g6-stop-search-btn" style="${searching ? '' : 'display:none;'}">Stop Searching</button>
                    </div>
                </div>
                <div style="color:#94a3b8;font-size:15px;text-align:center;padding:40px 20px;">
                    ${searching ? '🔍 Searching for contracts...' : '💼 Click "Start Searching" to find contracts'}
                </div>
            </div>
        `);
    }

    function g6RenderGroupPane() {
        const state = window.__G6_STATE__ || {};
        const group = state.currentGroup;
        const pendingInvites = state.pendingInvites || [];

        if (!group) {
            let invitesHTML = '';
            if (pendingInvites.length > 0) {
                invitesHTML = `
                    <div style="margin-top:24px;">
                        <div style="color:#f1f5f9;font-weight:700;font-size:18px;margin-bottom:16px;">📬 Pending Invites</div>
                        ${pendingInvites.map(invite => `
                            <div style="background:rgba(255,255,255,0.06);border:1px solid rgba(74,217,222,0.3);border-radius:12px;padding:16px;margin-bottom:12px;">
                                <div style="color:#f1f5f9;font-weight:700;margin-bottom:8px;">${invite.leaderName} (ID: ${invite.leaderId})</div>
                                <div style="display:flex;gap:10px;">
                                    <button class="g6-accept-invite" data-leader-id="${invite.leaderId}" style="flex:1;background:linear-gradient(135deg,#10b981,#059669);color:#fff;border:0;padding:10px;border-radius:8px;cursor:pointer;font-weight:700;">Accept</button>
                                    <button class="g6-decline-invite" data-leader-id="${invite.leaderId}" style="flex:1;background:linear-gradient(135deg,#ef4444,#dc2626);color:#fff;border:0;padding:10px;border-radius:8px;cursor:pointer;font-weight:700;">Decline</button>
                                </div>
                            </div>
                        `).join('')}
                    </div>
                `;
            }

            $('#g6-right-pane').html(`
                <div class="g6-card" style="background:linear-gradient(135deg, rgba(74, 217, 222,0.08), rgba(74, 217, 222,0.04));border:2px solid rgba(74, 217, 222,0.3);border-radius:20px;padding:32px;text-align:center;">
                    <div style="font-size:64px;margin-bottom:20px;">👥</div>
                    <div style="color:#f1f5f9;font-weight:700;font-size:22px;margin-bottom:12px;">No Active Party</div>
                    <div style="color:#94a3b8;font-size:15px;margin-bottom:28px;">Create a party to invite members and share contract rewards</div>
                    <button id="g6-create-group" style="background:linear-gradient(135deg, #4ad9de, #22d3ee);color:#0a0e1a;border:0;padding:16px 32px;border-radius:14px;font-size:16px;font-weight:800;cursor:pointer;text-transform:uppercase;letter-spacing:1px;box-shadow:0 8px 24px rgba(74,217,222,0.4);transition:all 0.3s;">
                        Create Party
                    </button>
                    <div style="margin-top:18px;display:flex;gap:10px;justify-content:center;align-items:center;">
                        <input id="g6-join-code" type="text" maxlength="6" placeholder="Group Code" style="width:180px;padding:10px 12px;border-radius:10px;border:1px solid rgba(74,217,222,0.4);background:rgba(255,255,255,0.08);color:#f1f5f9;text-transform:uppercase;" />
                        <button id="g6-join-by-code" style="background:linear-gradient(135deg,#eab308,#f59e0b);color:#111827;border:0;padding:10px 16px;border-radius:10px;font-weight:700;cursor:pointer;">Join</button>
                    </div>
                    ${invitesHTML}
                </div>
            `);
            return;
        }

        const isLeader = (group.leader === state.playerId) || (String(group.leader) === String(state.playerId)) || (Number(group.leader) === Number(state.playerId));
        const members = group.members || [];
        const splits = group.payoutSplits || {};

        let membersHTML = '';
        const leaderSplit = splits[group.leader] || 100;

        if (isLeader) {
            membersHTML += `
                <div style="background:rgba(74,217,222,0.15);border:2px solid rgba(74,217,222,0.4);border-radius:12px;padding:16px;margin-bottom:12px;display:flex;justify-content:space-between;align-items:center;">
                    <div style="display:flex;align-items:center;gap:14px;">
                        <div style="width:44px;height:44px;background:linear-gradient(135deg,#fbbf24,#f59e0b);border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:20px;">👑</div>
                        <div>
                            <div style="color:#f1f5f9;font-weight:700;font-size:15px;">You <span style="color:#fbbf24;font-size:13px;">(Party Leader)</span></div>
                            <div style="color:#94a3b8;font-size:13px;">ID: ${state.playerId}</div>
                        </div>
                    </div>
                    <div style="display:flex;align-items:center;gap:12px;">
                        <input type="number" class="g6-split-input" data-member-id="${state.playerId}" value="${leaderSplit}" min="0" max="100" 
                            style="width:70px;padding:8px;border-radius:8px;border:1px solid rgba(251,191,36,0.4);background:rgba(251,191,36,0.15);color:#fbbf24;text-align:center;font-weight:700;">
                        <span style="color:#fbbf24;font-weight:700;">%</span>
                    </div>
                </div>
            `;
        } else {
            const leaderName = group.leaderName || 'Party Leader';
            membersHTML += `
                <div style="background:rgba(74,217,222,0.08);border:1px solid rgba(251,191,36,0.3);border-radius:12px;padding:16px;margin-bottom:12px;display:flex;justify-content:space-between;align-items:center;">
                    <div style="display:flex;align-items:center;gap:14px;">
                        <div style="width:44px;height:44px;background:linear-gradient(135deg,#fbbf24,#f59e0b);border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:20px;">👑</div>
                        <div>
                            <div style="color:#f1f5f9;font-weight:700;font-size:15px;">${leaderName} <span style="color:#fbbf24;font-size:13px;">(Leader)</span></div>
                            <div style="color:#94a3b8;font-size:13px;">ID: ${group.leader}</div>
                        </div>
                    </div>
                    <div style="color:#fbbf24;font-weight:700;font-size:18px;">${leaderSplit}%</div>
                </div>
            `;
        }

        members.forEach(member => {
            const split = splits[member.id] || 25;
            const isYou = (member.id == state.playerId);
            const bgColor = isYou ? 'rgba(74,217,222,0.12)' : 'rgba(255,255,255,0.06)';
            const borderColor = isYou ? 'rgba(74,217,222,0.4)' : 'rgba(74,217,222,0.2)';

            membersHTML += `
                <div style="background:${bgColor};border:1px solid ${borderColor};border-radius:12px;padding:16px;margin-bottom:12px;display:flex;justify-content:space-between;align-items:center;">
                    <div style="display:flex;align-items:center;gap:14px;">
                        <div style="width:44px;height:44px;background:linear-gradient(135deg,#4ad9de,#22d3ee);border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:20px;">👤</div>
                        <div>
                            <div style="color:#f1f5f9;font-weight:700;font-size:15px;">${member.name}${isYou ? ' <span style="color:#4ad9de;font-size:13px;">(You)</span>' : ''}</div>
                            <div style="color:#94a3b8;font-size:13px;">ID: ${member.id}</div>
                        </div>
                    </div>
                    <div style="display:flex;align-items:center;gap:12px;">
                        ${isLeader ? `
                            <input type="number" class="g6-split-input" data-member-id="${member.id}" value="${split}" min="0" max="100" 
                                style="width:70px;padding:8px;border-radius:8px;border:1px solid rgba(74,217,222,0.3);background:rgba(255,255,255,0.08);color:#f1f5f9;text-align:center;font-weight:700;">
                            <span style="color:#4ad9de;font-weight:700;">%</span>
                            <button class="g6-kick-member" data-member-id="${member.id}" 
                                style="background:linear-gradient(135deg,#ef4444,#dc2626);color:#fff;border:0;padding:8px 14px;border-radius:8px;cursor:pointer;font-weight:700;">Kick</button>
                        ` : `
                            <span style="color:#4ad9de;font-weight:700;font-size:18px;">${split}%</span>
                        `}
                    </div>
                </div>
            `;
        });

        let invitesHTML = '';
        if (pendingInvites.length > 0) {
            invitesHTML = `
                <div style="background:rgba(251,191,36,0.1);border:2px solid rgba(251,191,36,0.4);border-radius:12px;padding:18px;margin-bottom:20px;">
                    <div style="color:#fbbf24;font-weight:700;font-size:16px;margin-bottom:12px;">📬 Pending Party Invites</div>
                    <div style="color:#fef3c7;font-size:13px;margin-bottom:14px;">You have ${pendingInvites.length} pending invitation${pendingInvites.length > 1 ? 's' : ''}. Accepting will leave your current party.</div>
                    ${pendingInvites.map(invite => `
                        <div style="background:rgba(255,255,255,0.08);border:1px solid rgba(251,191,36,0.3);border-radius:10px;padding:14px;margin-bottom:10px;">
                            <div style="color:#f1f5f9;font-weight:700;margin-bottom:8px;">Invitation from ${invite.leaderName} (ID: ${invite.leaderId})</div>
                            <div style="display:flex;gap:10px;">
                                <button class="g6-accept-invite" data-leader-id="${invite.leaderId}" style="flex:1;background:linear-gradient(135deg,#10b981,#059669);color:#fff;border:0;padding:10px;border-radius:8px;cursor:pointer;font-weight:700;transition:all 0.3s;">✓ Accept</button>
                                <button class="g6-decline-invite" data-leader-id="${invite.leaderId}" style="flex:1;background:linear-gradient(135deg,#ef4444,#dc2626);color:#fff;border:0;padding:10px;border-radius:8px;cursor:pointer;font-weight:700;transition:all 0.3s;">✗ Decline</button>
                            </div>
                        </div>
                    `).join('')}
                </div>
            `;
        }

        $('#g6-right-pane').html(`
            <div class="g6-card" style="background:rgba(255,255,255,0.05);border:2px solid rgba(74,217,222,0.25);border-radius:20px;padding:28px;">
                ${invitesHTML}
                <div style="display:flex;justify-content:space-between;align-items:center;background:rgba(255,255,255,0.06);border:1px solid rgba(74,217,222,0.25);padding:12px 14px;border-radius:12px;margin-bottom:14px;">
                    <div style="color:#e2e8f0;font-size:13px;">Group Code: <strong id="g6-group-code">${group.groupCode || '------'}</strong></div>
                    <button id="g6-copy-group-code" style="background:rgba(74,217,222,0.25);color:#e6fbff;border:1px solid rgba(74,217,222,0.4);padding:6px 10px;border-radius:8px;cursor:pointer;font-weight:700;">Copy</button>
                </div>
                
                <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:24px;">
                    <div>
                        <div style="color:#f1f5f9;font-weight:700;font-size:20px;margin-bottom:4px;">${isLeader ? '👑 Your Party' : '👥 Party Members'}</div>
                        <div style="color:#94a3b8;font-size:13px;">${members.length}/${4} members</div>
                    </div>
                    ${isLeader ? `
                        <button id="g6-disband-group" style="background:linear-gradient(135deg,#ef4444,#dc2626);color:#fff;border:0;padding:10px 18px;border-radius:10px;cursor:pointer;font-weight:700;">
                            Disband Party
                        </button>
                    ` : `
                        <button id="g6-leave-group" style="background:linear-gradient(135deg,#6b7280,#4b5563);color:#fff;border:0;padding:10px 18px;border-radius:10px;cursor:pointer;font-weight:700;">
                            Leave Party
                        </button>
                    `}
                </div>
                
                <div style="color:#f1f5f9;font-weight:700;font-size:16px;margin-bottom:14px;">Party Members</div>
                ${membersHTML || '<div style="color:#94a3b8;text-align:center;padding:20px;">No members yet</div>'}
                
                ${isLeader ? `
                    <div style="background:rgba(74,217,222,0.1);border:1px solid rgba(74,217,222,0.3);border-radius:12px;padding:16px;margin-top:20px;">
                        <div style="color:#f1f5f9;font-weight:700;font-size:15px;margin-bottom:12px;">✉️ Invite Player by Server ID</div>
                        <div style="color:#94a3b8;font-size:13px;margin-bottom:12px;">Enter the player's in-game server ID to send them a party invite</div>
                        <div style="display:flex;gap:10px;">
                            <input type="number" id="g6-invite-id" placeholder="Enter player server ID (e.g., 1, 2, 3...)" 
                                style="flex:1;padding:12px;border-radius:10px;border:1px solid rgba(74,217,222,0.4);background:rgba(255,255,255,0.08);color:#f1f5f9;font-size:14px;">
                            <button id="g6-invite-btn" style="background:linear-gradient(135deg,#4ad9de,#22d3ee);color:#0a0e1a;border:0;padding:12px 24px;border-radius:10px;cursor:pointer;font-weight:800;transition:all 0.3s;">
                                Send Invite
                            </button>
                        </div>
                    </div>
                ` : ''}
            </div>
        `);

        g6BindHandlers();
    }

    function g6RenderUpgradesPane() {
        const state = window.__G6_STATE__ || {};
        const level = state.level || 1;
        const upgrades = state.upgrades || {};
        
        const upgradesConfig = [
            { id: 'tier_2', label: 'Vehicle Upgrade', description: 'Unlock Tier 2 contracts with better vehicles', cost: 10000, requiredLevel: 2, icon: '🚚' },
            { id: 'tier_3', label: 'Advanced Vehicle Upgrade', description: 'Unlock Tier 3 contracts with armored vehicles', cost: 25000, requiredLevel: 3, requiresTier2: true, icon: '🛡️' },
            { id: 'bag_capacity', label: 'Bag Capacity Upgrade', description: 'Increase maximum bags per location by 25%', cost: 15000, requiredLevel: 2, icon: '💰' }
        ];
        
        const upgradeCards = upgradesConfig.map(upgrade => {
            const owned = !!upgrades[upgrade.id];
            const canBuy = level >= upgrade.requiredLevel && (!upgrade.requiresTier2 || upgrades.tier_2);
            const statusText = owned ? 'Owned' : canBuy ? `$${upgrade.cost.toLocaleString()}` : `Requires Level ${upgrade.requiredLevel}${upgrade.requiresTier2 ? ' & Tier 2' : ''}`;
            const statusColor = owned ? '#10b981' : canBuy ? '#2563eb' : '#6b7280';
            
            return `
                <div class="g6-upgrade-card" style="background:rgba(255,255,255,0.05);border:1px solid rgba(255,255,255,0.1);border-radius:12px;padding:16px;margin-bottom:12px;">
                    <div style="display:flex;justify-content:space-between;align-items:center;">
                        <div style="display:flex;align-items:center;gap:12px;">
                            <div style="font-size:32px;">${upgrade.icon}</div>
                            <div>
                                <div style="color:#e5e7eb;font-weight:700;font-size:16px;">${upgrade.label}</div>
                                <div style="color:#9ca3af;font-size:13px;margin-top:4px;">${upgrade.description}</div>
                            </div>
                        </div>
                        <button class="g6-buy-upgrade-btn" data-upgrade-id="${upgrade.id}" ${owned || !canBuy ? 'disabled' : ''} 
                            style="background:${statusColor};color:#fff;border:0;padding:10px 16px;border-radius:8px;cursor:${owned || !canBuy ? 'not-allowed' : 'pointer'};opacity:${owned || !canBuy ? '0.6' : '1'};">
                            ${statusText}
                        </button>
                    </div>
                </div>
            `;
        }).join('');
        
        $('#g6-right-pane').html(`
            <div class="g6-card" style="background:rgba(255,255,255,0.05);border:1px solid rgba(255,255,255,0.1);border-radius:12px;padding:18px;">
                <div style="color:#e5e7eb;font-weight:700;font-size:18px;margin-bottom:16px;">Upgrades</div>
                ${upgradeCards}
            </div>
        `);
    }

    function g6BindHandlers() {
        // Tabs
        $(document).off('click.g6tabs').on('click.g6tabs', '.g6-tab-inline[data-g6-tab]', function () {
            const tab = $(this).data('g6-tab');
            $('.g6-tab-inline[data-g6-tab]').removeClass('active');
            $(this).addClass('active');

            if (tab === 'contracts') g6RefreshContractDisplay();
            if (tab === 'work') g6RenderWorkPane();
            if (tab === 'group') g6RenderGroupPane();
            if (tab === 'upgrades') g6RenderUpgradesPane();
        });

        // Work buttons
        $(document).off('click.g6start').on('click.g6start', '#g6-start-search', function () {
            $.post(`https://${RES}/gruppe6:startSearch`, JSON.stringify({}), function () { });
            window.__G6_STATE__.searching = true;
            g6RenderWorkPane();
        });

        $(document).off('click.g6stop').on('click.g6stop', '#g6-stop-search', function () {
            $.post(`https://${RES}/gruppe6:stopSearch`, JSON.stringify({}), function () { });
            window.__G6_STATE__.searching = false;
            g6RenderWorkPane();
        });

        // Accept contract
        $(document).off('click.g6accept').on('click.g6accept', '.g6-accept-contract-btn', function () {
            if ($(this).prop('disabled')) return;
            const idx = Number($(this).data('contract-id'));
            if (Number.isNaN(idx)) return;

            $('.g6-accept-contract-btn').prop('disabled', true).text('Processing...');
            $.post(`https://${RES}/gruppe6:acceptContract`, JSON.stringify({ contractId: idx }), function () { });
        });

        // End contract
        $(document).off('click.g6end').on('click.g6end', '#g6-start-contract', function () {
            const action = $(this).data('action');
            if (action === 'end') {
                $.post(`https://${RES}/gruppe6:endContract`, JSON.stringify({}), function () { });
            }
        });

        // Group basics
        $(document).off('click.g6creategroup').on('click.g6creategroup', '#g6-create-group', function () {
            $.post(`https://${RES}/gruppe6:createGroup`, JSON.stringify({}), function () { });
        });

        $(document).off('click.g6joincode').on('click.g6joincode', '#g6-join-by-code', function () {
            const code = String($('#g6-join-code').val() || '').trim().toUpperCase();
            if (!code) return;
            $.post(`https://${RES}/gruppe6:joinByCode`, JSON.stringify({ code }), function () { });
        });

        $(document).off('click.g6copycode').on('click.g6copycode', '#g6-copy-group-code', function () {
            const code = String($('#g6-group-code').text() || '').trim();
            if (!code || code === '------') return;
            if (navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(code).catch(() => {});
            }
        });

        $(document).off('click.g6disbandgroup').on('click.g6disbandgroup', '#g6-disband-group', function () {
            $.post(`https://${RES}/gruppe6:disbandGroup`, JSON.stringify({}), function () { });
        });

        $(document).off('click.g6leavegroup').on('click.g6leavegroup', '#g6-leave-group', function () {
            $.post(`https://${RES}/gruppe6:leaveGroup`, JSON.stringify({}), function () { });
        });

        $(document).off('click.g6kick').on('click.g6kick', '.g6-kick-member', function () {
            const targetId = $(this).data('member-id');
            $.post(`https://${RES}/gruppe6:kickMember`, JSON.stringify({ targetId }), function () { });
        });

        $(document).off('change.g6splitchange').on('change.g6splitchange', '.g6-split-input', function () {
            const targetId = $(this).data('member-id');
            const percentage = parseInt($(this).val(), 10);
            $.post(`https://${RES}/gruppe6:updateSplit`, JSON.stringify({ targetId, percentage }), function () { });
        });

        $(document).off('click.g6buyupgrade').on('click.g6buyupgrade', '.g6-buy-upgrade-btn', function () {
            if ($(this).is(':disabled')) return;
            const upgradeId = $(this).data('upgrade-id');
            $.post(`https://${RES}/gruppe6:purchaseUpgrade`, JSON.stringify({ upgradeId }), function () { });
        });

        $(document).off('click.g6invite').on('click.g6invite', '#g6-invite-btn', function () {
            const targetId = parseInt($('#g6-invite-id').val(), 10);
            if (!targetId || isNaN(targetId)) return;
            $.post(`https://${RES}/gruppe6:invitePlayer`, JSON.stringify({ targetId }), function () {
                $('#g6-invite-id').val('');
            });
        });

        $(document).off('click.g6acceptinv').on('click.g6acceptinv', '.g6-accept-invite', function () {
            const leaderId = $(this).data('leader-id');
            $.post(`https://${RES}/gruppe6:acceptInvite`, JSON.stringify({ leaderId }), function () { });
        });

        $(document).off('click.g6declineinv').on('click.g6declineinv', '.g6-decline-invite', function () {
            const leaderId = $(this).data('leader-id');
            $.post(`https://${RES}/gruppe6:declineInvite`, JSON.stringify({ leaderId }), function () { });
        });
    }

    function renderGruppe6Window(appName) {
        const $content = $(`.app-window[data-app="${appName}"] .window-content`);
        if (!$content.length) return;

        $content.html(`
            <div class="g6-container">
                <div class="g6-top-bar">
                    <div class="g6-welcome-inline">
                        <div class="g6-logo-small">🛡️</div>
                        <div class="g6-welcome-text-inline">
                            <div class="g6-welcome-title">Welcome</div>
                            <div class="g6-welcome-subtitle">Gruppe6</div>
                        </div>
                    </div>

                    <div class="g6-tabs-inline">
                        <div class="g6-tab-inline active" data-g6-tab="contracts"><span class="g6-tab-icon">📋</span><span>Contract Offers</span></div>
                        <div class="g6-tab-inline" data-g6-tab="work"><span class="g6-tab-icon">🛠️</span><span>Work</span></div>
                        <div class="g6-tab-inline" data-g6-tab="group"><span class="g6-tab-icon">👥</span><span>Group</span></div>
                        <div class="g6-tab-inline" data-g6-tab="upgrades"><span class="g6-tab-icon">⬆️</span><span>Upgrades</span></div>
                    </div>

                    <div class="g6-progression-inline">
                        <div class="g6-prog-header"><span class="g6-prog-icon">⚡</span><span class="g6-prog-title">Level <span id="g6-level">1</span></span></div>
                        <div class="g6-prog-bar-container"><div class="g6-prog-bar" id="g6-xpbar-top" style="width: 0%;"></div></div>
                        <div style="margin-top:4px;font-size:12px;color:#94a3b8;"><span id="g6-xp-text">0 / 1000 XP</span></div>
                    </div>
                </div>

                <div class="g6-main-content">
                    <div class="g6-left-col">
                        <div class="g6-contract-card" id="g6-contract-card" style="display:none;">
                            <div class="g6-tier-badge" id="g6-tier-badge">Tier 1</div>
                            <div class="g6-vehicle-name" id="g6-vehicle-name">Speedo</div>
                            <div class="g6-rank-badge"><span class="g6-wing left">🪽</span><div class="g6-rank-circle"><span class="g6-rank-star">⭐</span></div><span class="g6-wing right">🪽</span></div>
                            <div class="g6-info-rows">
                                <div class="g6-info-row"><span class="g6-info-label"><span class="g6-info-icon">📦</span> Type</span><span class="g6-info-value" id="g6-contract-type">Bank Delivery</span></div>
                                <div class="g6-info-row"><span class="g6-info-label"><span class="g6-info-icon">💼</span> Bags</span><span class="g6-info-value" id="g6-bags">12</span></div>
                                <div class="g6-info-row"><span class="g6-info-label"><span class="g6-info-icon">💰</span> Payout</span><span class="g6-info-value" id="g6-payout">$0</span></div>
                                <div class="g6-info-row"><span class="g6-info-label"><span class="g6-info-icon">👥</span> Max Group</span><span class="g6-info-value" id="g6-maxgroup">2</span></div>
                            </div>
                            <button class="g6-start-contract-btn" id="g6-start-contract">End Contract Early</button>
                        </div>

                        <div class="g6-waiting-card" id="g6-waiting-card">
                            <div class="g6-waiting-icon">⏳</div>
                            <div class="g6-waiting-text">
                                <div class="g6-waiting-title">No Contract Available</div>
                                <div class="g6-waiting-subtitle" id="g6-waiting-subtitle">Start searching to find contracts</div>
                            </div>
                        </div>
                    </div>

                    <div class="g6-right-col" id="g6-right-pane"></div>
                </div>
            </div>
        `);

        g6BindHandlers();
        g6RefreshContractDisplay();

        // Always request init on open (pf-tablet handles this NUI callback)
        $.post(`https://${RES}/gruppe6:getInit`, JSON.stringify({}), function () { });
    }

    // ---- Garbage state + UI ----
    window.__GARBAGE_STATE__ = window.__GARBAGE_STATE__ || { xp: 0, level: 1, carrying: false, currentGroup: null, pendingInvites: [] };

    function refreshGarbageDisplay() {
        const xp = Number(window.__GARBAGE_STATE__.xp || 0);
        const level = Number(window.__GARBAGE_STATE__.level || 1);
        $('#garbage-level').text(level);

        const thresholds = [0, 1000, 3000, 7000, 12000, 20000];
        const cur = thresholds[level - 1] || 0;
        const next = thresholds[level] || thresholds[thresholds.length - 1];
        const inLevel = Math.max(0, xp - cur);
        const need = Math.max(1, next - cur);
        const pct = Math.min(100, (inLevel / need) * 100);
        $('#garbage-xpbar').css('width', pct + '%');
        $('#garbage-xp-text').text(`${inLevel} / ${need} XP`);
        $('#garbage-carrying').text(window.__GARBAGE_STATE__.carrying ? 'Yes' : 'No');
    }

    function renderGarbageGroupPane() {
        const state = window.__GARBAGE_STATE__ || {};
        const group = state.currentGroup;
        const invites = state.pendingInvites || [];

        if (!group) {
            $('#garbage-right-pane').html(`
                <div class="g6-card" style="background:rgba(255,255,255,0.05);border:1px solid rgba(74,217,222,0.2);border-radius:16px;padding:22px;">
                    <div style="font-size:22px;font-weight:700;color:#f8fafc;margin-bottom:10px;">Garbage Group</div>
                    <div style="color:#94a3b8;margin-bottom:14px;">Create a room and share the code, or join by code.</div>
                    <div style="display:flex;gap:8px;flex-wrap:wrap;">
                        <button id="garb-create-group" style="background:linear-gradient(135deg,#22d3ee,#06b6d4);color:#082f49;border:0;padding:10px 14px;border-radius:10px;font-weight:700;cursor:pointer;">Create Group</button>
                        <input id="garb-join-code" type="text" maxlength="6" placeholder="Group Code" style="padding:10px 12px;border-radius:10px;border:1px solid rgba(74,217,222,0.4);background:rgba(255,255,255,0.08);color:#f1f5f9;text-transform:uppercase;" />
                        <button id="garb-join-code-btn" style="background:linear-gradient(135deg,#facc15,#f59e0b);color:#111827;border:0;padding:10px 14px;border-radius:10px;font-weight:700;cursor:pointer;">Join</button>
                    </div>
                    ${invites.length > 0 ? `<div style="margin-top:16px;display:grid;gap:8px;">${invites.map(inv => `
                        <div style="background:rgba(255,255,255,0.08);border:1px solid rgba(74,217,222,0.24);border-radius:10px;padding:10px;">
                            <div style="color:#e2e8f0;font-size:13px;margin-bottom:8px;">Invite from ${inv.leaderName} (${inv.leaderId})</div>
                            <div style="display:flex;gap:6px;">
                                <button class="garb-accept-invite" data-leader-id="${inv.leaderId}" style="flex:1;background:#10b981;color:#ecfdf5;border:0;padding:8px 10px;border-radius:8px;cursor:pointer;font-weight:700;">Accept</button>
                                <button class="garb-decline-invite" data-leader-id="${inv.leaderId}" style="flex:1;background:#ef4444;color:#fee2e2;border:0;padding:8px 10px;border-radius:8px;cursor:pointer;font-weight:700;">Decline</button>
                            </div>
                        </div>
                    `).join('')}</div>` : ''}
                </div>
            `);
            return;
        }

        const members = group.members || [];
        const isLeader = Number(group.leader) === Number((window.__GARBAGE_STATE__ && window.__GARBAGE_STATE__.playerId) || -1);

        $('#garbage-right-pane').html(`
            <div class="g6-card" style="background:rgba(255,255,255,0.05);border:1px solid rgba(74,217,222,0.2);border-radius:16px;padding:22px;">
                <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px;">
                    <div style="font-size:20px;font-weight:700;color:#f8fafc;">Group Room</div>
                    <div style="display:flex;gap:8px;align-items:center;">
                        <span id="garb-group-code" style="font-weight:800;color:#67e8f9;">${group.groupCode || '------'}</span>
                        <button id="garb-copy-code" style="background:rgba(74,217,222,0.22);color:#cffafe;border:1px solid rgba(74,217,222,0.35);padding:6px 10px;border-radius:8px;cursor:pointer;font-weight:700;">Copy</button>
                    </div>
                </div>
                <div style="color:#94a3b8;margin-bottom:10px;">Leader: ${group.leaderName || group.leader}</div>
                <div style="display:grid;gap:8px;margin-bottom:12px;">
                    <div style="padding:10px;border-radius:10px;background:rgba(255,255,255,0.06);border:1px solid rgba(74,217,222,0.2);">${group.leaderName || 'Leader'} (Leader)</div>
                    ${members.map(m => `<div style="padding:10px;border-radius:10px;background:rgba(255,255,255,0.06);border:1px solid rgba(74,217,222,0.2);">${m.name} (ID: ${m.id})</div>`).join('')}
                </div>
                <div style="display:flex;gap:8px;">
                    <button id="garb-leave-group" style="background:#ef4444;color:#fee2e2;border:0;padding:10px 12px;border-radius:10px;cursor:pointer;font-weight:700;">Leave Group</button>
                    ${isLeader ? '<button id="garb-disband-group" style="background:#7f1d1d;color:#fee2e2;border:0;padding:10px 12px;border-radius:10px;cursor:pointer;font-weight:700;">Close Group</button>' : ''}
                </div>
            </div>
        `);
    }

    function bindGarbageHandlers() {
        $(document).off('click.garbstart').on('click.garbstart', '#garbage-start-job', function () {
            $.post(`https://${RES}/garbage:startJob`, JSON.stringify({}), function () { });
        });

        $(document).off('click.garbcreate').on('click.garbcreate', '#garb-create-group', function () {
            $.post(`https://${RES}/garbage/group/create`, JSON.stringify({}), function () { });
        });

        $(document).off('click.garbjoincode').on('click.garbjoincode', '#garb-join-code-btn', function () {
            const code = String($('#garb-join-code').val() || '').trim().toUpperCase();
            if (!code) return;
            $.post(`https://${RES}/garbage/group/joinByCode`, JSON.stringify({ code }), function () { });
        });

        $(document).off('click.garbcopycode').on('click.garbcopycode', '#garb-copy-code', function () {
            const code = String($('#garb-group-code').text() || '').trim();
            if (!code || code === '------') return;
            if (navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(code).catch(() => {});
            }
        });

        $(document).off('click.garbleave').on('click.garbleave', '#garb-leave-group', function () {
            $.post(`https://${RES}/garbage/group/leave`, JSON.stringify({}), function () { });
        });

        $(document).off('click.garbdisband').on('click.garbdisband', '#garb-disband-group', function () {
            $.post(`https://${RES}/garbage/group/disband`, JSON.stringify({}), function () { });
        });

        $(document).off('click.garbacceptinvite').on('click.garbacceptinvite', '.garb-accept-invite', function () {
            const leaderId = Number($(this).attr('data-leader-id'));
            $.post(`https://${RES}/garbage/group/accept`, JSON.stringify({ leaderId }), function () { });
        });

        $(document).off('click.garbdeclineinvite').on('click.garbdeclineinvite', '.garb-decline-invite', function () {
            const leaderId = Number($(this).attr('data-leader-id'));
            $.post(`https://${RES}/garbage/group/decline`, JSON.stringify({ leaderId }), function () { });
        });

        $(document).off('click.garbtabs').on('click.garbtabs', '.g6-tab-inline[data-garbage-tab]', function () {
            const tab = $(this).data('garbage-tab');
            if (!tab) return;
            $('.g6-tab-inline[data-garbage-tab]').removeClass('active');
            $(this).addClass('active');

            if (tab === 'work') {
                $('#garbage-right-pane').html(`<div class="g6-card" style="background:rgba(255,255,255,0.05);border:1px solid rgba(74,217,222,0.15);border-radius:16px;padding:24px;text-align:center;">Collect trash bags from dumpsters and deposit at the Trashmaster. One bag at a time.</div>`);
            } else if (tab === 'group') {
                renderGarbageGroupPane();
            } else if (tab === 'upgrades') {
                $('#garbage-right-pane').html(`<div class="g6-card" style="background:rgba(255,255,255,0.05);border:1px solid rgba(74,217,222,0.15);border-radius:16px;padding:24px;text-align:center;">Upgrades coming soon.</div>`);
            }
        });
    }

    function renderGarbageWindow(appName) {
        const $content = $(`.app-window[data-app="${appName}"] .window-content`);
        if (!$content.length) return;
        $content.html(`
            <div class="g6-container">
                <div class="g6-top-bar">
                    <div class="g6-welcome-inline">
                        <div class="g6-logo-small">🚚</div>
                        <div class="g6-welcome-text-inline">
                            <div class="g6-welcome-title">Welcome</div>
                            <div class="g6-welcome-subtitle">Garbage</div>
                        </div>
                    </div>
                    <div class="g6-tabs-inline">
                        <div class="g6-tab-inline active" data-garbage-tab="work"><span class="g6-tab-icon">🛠️</span><span>Work</span></div>
                        <div class="g6-tab-inline" data-garbage-tab="group"><span class="g6-tab-icon">👥</span><span>Group</span></div>
                        <div class="g6-tab-inline" data-garbage-tab="upgrades"><span class="g6-tab-icon">⬆️</span><span>Upgrades</span></div>
                    </div>
                    <div class="g6-progression-inline">
                        <div class="g6-prog-header"><span class="g6-prog-icon">⚡</span><span class="g6-prog-title">Level <span id="garbage-level">1</span></span></div>
                        <div class="g6-prog-bar-container"><div class="g6-prog-bar" id="garbage-xpbar" style="width:0%;"></div></div>
                        <div style="margin-top:4px;font-size:12px;color:#94a3b8;"><span id="garbage-xp-text">0 / 1000 XP</span></div>
                    </div>
                </div>
                <div class="g6-main-content">
                    <div class="g6-left-col">
                        <div class="g6-contract-card" id="garbage-work-card">
                            <div class="g6-tier-badge">Job</div>
                            <div class="g6-vehicle-name">Trashmaster</div>
                            <div class="g6-info-rows">
                                <div class="g6-info-row"><span class="g6-info-label"><span class="g6-info-icon">🚚</span> Vehicle</span><span class="g6-info-value">Trashmaster</span></div>
                                <div class="g6-info-row"><span class="g6-info-label"><span class="g6-info-icon">📦</span> Carrying</span><span class="g6-info-value" id="garbage-carrying">No</span></div>
                            </div>
                            <button class="g6-start-contract-btn" id="garbage-start-job">Start Job</button>
                        </div>
                    </div>
                    <div class="g6-right-col" id="garbage-right-pane"></div>
                </div>
            </div>
        `);

        bindGarbageHandlers();
        refreshGarbageDisplay();
        $('#garbage-right-pane').html(`<div class="g6-card" style="background:rgba(255,255,255,0.05);border:1px solid rgba(74,217,222,0.15);border-radius:16px;padding:24px;text-align:center;">Collect trash bags from dumpsters and deposit at the Trashmaster. One bag at a time.</div>`);

        // Request init on open
        $.post(`https://${RES}/garbage:getInit`, JSON.stringify({}), function () { });
    }

    // State update messages from client
    window.addEventListener('message', function (e) {
        const d = e.data || {};

        if (d.action === 'gruppe6:init') {
            window.__G6_STATE__ = Object.assign(window.__G6_STATE__ || {}, d.state || {});
            g6RefreshContractDisplay();
            return;
        }
        if (d.action === 'gruppe6:contracts') {
            window.__G6_STATE__.contracts = d.contracts || [];
            g6RefreshContractDisplay();
            return;
        }
        if (d.action === 'gruppe6:activeContract') {
            window.__G6_STATE__.activeContract = d.contract || null;
            g6RefreshContractDisplay();
            return;
        }
        if (d.action === 'gruppe6:updateXP') {
            window.__G6_STATE__.xp = Number(d.xp || 0);
            window.__G6_STATE__.level = Number(d.level || 1);
            g6RefreshContractDisplay();
            return;
        }
        if (d.action === 'gruppe6:groupUpdate') {
            window.__G6_STATE__.currentGroup = d.group || null;
            if ($('.g6-tab-inline.active').data('g6-tab') === 'group') {
                g6RenderGroupPane();
            }
            if (d.group && d.group.members && d.group.members.length === 0) {
                $('.g6-tab-inline').removeClass('active');
                $('.g6-tab-inline[data-g6-tab="group"]').addClass('active');
                g6RenderGroupPane();
            }
            return;
        }
        if (d.action === 'gruppe6:addInvite') {
            if (!window.__G6_STATE__.pendingInvites) window.__G6_STATE__.pendingInvites = [];
            const existing = window.__G6_STATE__.pendingInvites.find(inv => inv.leaderId === d.invite.leaderId);
            if (!existing) window.__G6_STATE__.pendingInvites.push(d.invite);
            if ($('.g6-tab-inline.active').data('g6-tab') === 'group') {
                g6RenderGroupPane();
            }
            return;
        }

        if (d.action === 'gruppe6:upgradesPurchased') {
            window.__G6_STATE__.upgrades = d.upgrades || {};
            if ($('.g6-tab-inline.active').data('g6-tab') === 'upgrades') g6RenderUpgradesPane();
            return;
        }

        if (d.action === 'garbage:init') {
            window.__GARBAGE_STATE__ = Object.assign(window.__GARBAGE_STATE__ || {}, d.state || {});
            refreshGarbageDisplay();
            return;
        }
        if (d.action === 'garbage:updateXP') {
            window.__GARBAGE_STATE__.xp = Number(d.xp || 0);
            window.__GARBAGE_STATE__.level = Number(d.level || 1);
            refreshGarbageDisplay();
            return;
        }
        if (d.action === 'garbage:carrying') {
            window.__GARBAGE_STATE__.carrying = !!d.carrying;
            refreshGarbageDisplay();
            return;
        }

        if (d.action === 'garbage:groupUpdate') {
            window.__GARBAGE_STATE__.currentGroup = d.group || null;
            if ($('.g6-tab-inline.active').data('garbage-tab') === 'group') {
                renderGarbageGroupPane();
            }
            return;
        }

        if (d.action === 'garbage:addInvite') {
            window.__GARBAGE_STATE__.pendingInvites = window.__GARBAGE_STATE__.pendingInvites || [];
            const exists = window.__GARBAGE_STATE__.pendingInvites.find(inv => Number(inv.leaderId) === Number(d.invite && d.invite.leaderId));
            if (!exists && d.invite) {
                window.__GARBAGE_STATE__.pendingInvites.push(d.invite);
            }
            if ($('.g6-tab-inline.active').data('garbage-tab') === 'group') {
                renderGarbageGroupPane();
            }
        }
    });

    // Export mount points for pf-tablet core
    window.PFJobsTablet = window.PFJobsTablet || {};
    window.PFJobsTablet.renderGruppe6Window = renderGruppe6Window;
    window.PFJobsTablet.renderGarbageWindow = renderGarbageWindow;
    if (typeof window.renderTaxiWindow === 'function') {
        window.PFJobsTablet.renderTaxiWindow = window.renderTaxiWindow;
    }

    // signal to the core that jobs UI is ready
    try { window.dispatchEvent(new Event('pfjobs-ready')); } catch (_) {}
})();
