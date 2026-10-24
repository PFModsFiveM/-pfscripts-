// ============================================================================
// License Management Modal - app-extended.js
// ============================================================================

function openLicenseModal(licenseDataStr) {
    try {
        const licenseData = JSON.parse(licenseDataStr);
        const citizenId = licenseData.citizenId;
        const licenseType = licenseData.type;
        const licenseKey = licenseData.key;
        const citizenName = licenseData.citizenName;
        
        const modalHTML = `
            <div class="modal" id="licenseManagementModal" style="z-index: 10016;">
                <div class="modal-card" style="width: 500px; max-width: 90vw;">
                    <div class="modal-header">
                        <h3 style="margin: 0;">📋 ${escapeHtml(licenseType)}</h3>
                        <button class="modal-btn" id="licenseModalClose" title="Close">
                            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                                <line x1="18" y1="6" x2="6" y2="18"></line>
                                <line x1="6" y1="6" x2="18" y2="18"></line>
                            </svg>
                        </button>
                    </div>
                    <div class="modal-body" style="padding: 16px;">
                        <div style="margin-bottom: 16px;">
                            <div style="font-size: 11px; color: rgba(255,255,255,0.5); margin-bottom: 4px;">CITIZEN</div>
                            <div style="font-weight: 600; font-size: 14px;">${escapeHtml(citizenName)}</div>
                        </div>
                        
                        <div style="margin-bottom: 16px;">
                            <div style="font-size: 11px; color: rgba(255,255,255,0.5); margin-bottom: 4px;">LICENSE TYPE</div>
                            <div style="font-weight: 600; font-size: 14px;">${escapeHtml(licenseType)}</div>
                        </div>
                        
                        <div style="margin-bottom: 20px;">
                            <div style="font-size: 11px; color: rgba(255,255,255,0.5); margin-bottom: 4px;">STATUS</div>
                            <div style="font-weight: 600; font-size: 14px; color: #00e676;">✓ Active</div>
                        </div>
                        
                        <div style="border-top: 1px solid rgba(255,255,255,0.1); padding-top: 16px; margin-bottom: 16px;">
                            <div style="margin-bottom: 12px;">
                                <label style="font-size: 12px; color: rgba(255,255,255,0.7); display: block; margin-bottom: 8px;">Suspend License for:</label>
                                <select id="suspendDurationSelect" style="width: 100%; padding: 8px; border-radius: 6px; border: 1px solid rgba(59,130,246,0.3); background: rgba(59,130,246,0.1); color: #fff; font-size: 12px;">
                                    <option value="">-- Select Duration --</option>
                                    <option value="7">1 Week</option>
                                    <option value="14">2 Weeks</option>
                                    <option value="21">3 Weeks</option>
                                    <option value="30">1 Month</option>
                                    <option value="60">2 Months</option>
                                    <option value="90">3 Months</option>
                                </select>
                            </div>
                            <button class="btn primary" style="width: 100%;" onclick="suspendLicense('${escapeHtml(citizenId)}', '${escapeHtml(licenseKey)}', '${escapeHtml(licenseType)}');">⏸️ Suspend License</button>
                        </div>
                        
                        <div style="border-top: 1px solid rgba(255,255,255,0.1); padding-top: 16px;">
                            <button class="btn danger" style="width: 100%;" onclick="removeLicense('${escapeHtml(citizenId)}', '${escapeHtml(licenseKey)}', '${escapeHtml(licenseType)}');">🗑️ Remove License Permanently</button>
                        </div>
                    </div>
                </div>
            </div>
        `;
        
        // Remove existing modal if present
        const existing = document.getElementById('licenseManagementModal');
        if (existing) existing.remove();
        
        // Insert modal into DOM
        document.body.insertAdjacentHTML('beforeend', modalHTML);
        
        // Close on background click
        const modal = document.getElementById('licenseManagementModal');
        modal.addEventListener('click', (e) => {
            if (e.target === modal) closeLicenseModal();
        });
        
        // Close on header X click
        const closeBtn = document.getElementById('licenseModalClose');
        if (closeBtn) closeBtn.onclick = closeLicenseModal;
        
        // Close on ESC key
        const handleEsc = (e) => {
            if (e.key === 'Escape') {
                const m = document.getElementById('licenseManagementModal');
                if (m) closeLicenseModal();
            }
        };
        document.addEventListener('keydown', handleEsc, { once: true });
    } catch (e) {
        console.error('[MDT] Failed to parse license data:', e);
    }
}

function closeLicenseModal() {
    const modal = document.getElementById('licenseManagementModal');
    if (modal) modal.remove();
}

function suspendLicense(citizenId, licenseKey, licenseType) {
    const durationSelect = document.getElementById('suspendDurationSelect');
    const duration = durationSelect ? durationSelect.value : '';
    
    if (!duration) {
        if (typeof mdtToast === 'function') mdtToast('Please select a suspension duration', 'error');
        return;
    }
    
    sendCallback('suspendLicense', {
        citizenId: citizenId,
        licenseType: licenseKey,
        durationDays: parseInt(duration, 10)
    }, (response) => {
        if (response && response.success) {
            closeLicenseModal();
            // Refresh the citizen profile
            setTimeout(() => {
                sendCallback('openCitizen', { citizenId: citizenId });
            }, 300);
        } else {
            if (typeof mdtToast === 'function') mdtToast('Failed to suspend license: ' + (response?.error || 'Unknown error'), 'error');
        }
    });
}

async function removeLicense(citizenId, licenseKey, licenseType) {
    if (typeof window.mdtConfirm === 'function') {
        const ok = await window.mdtConfirm(`Are you sure you want to remove the ${licenseType} from ${citizenId}? This action cannot be undone.`);
        if (!ok) return;
    } else {
        if (typeof mdtToast === 'function') mdtToast('Confirm dialog unavailable', 'error');
        return;
    }
    
    sendCallback('removeLicense', {
        citizenId: citizenId,
        licenseType: licenseKey
    }, (response) => {
        if (response && response.success) {
            closeLicenseModal();
            // Refresh the citizen profile
            setTimeout(() => {
                sendCallback('openCitizen', { citizenId: citizenId });
            }, 300);
        } else {
            if (typeof mdtToast === 'function') mdtToast('Failed to remove license: ' + (response?.error || 'Unknown error'), 'error');
        }
    });
}
