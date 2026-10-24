let currentOutfits = [];
let renameIndex = null;

// Initialize
document.addEventListener('DOMContentLoaded', function() {
    const closeBtn = document.getElementById('closeBtn');
    const settingsBtn = document.getElementById('settingsBtn');
    const addOutfitBtn = document.getElementById('addOutfitBtn');
    const cancelBtn = document.getElementById('cancelBtn');
    const saveBtn = document.getElementById('saveBtn');
    const renameCancelBtn = document.getElementById('renameCancelBtn');
    const renameConfirmBtn = document.getElementById('renameConfirmBtn');
    const settingsModalClose = document.getElementById('settingsModalClose');
    const settingsApplyBtn = document.getElementById('settingsApplyBtn');
    const settingsDefaultBtn = document.getElementById('settingsDefaultBtn');
    const uiPosLeft = document.getElementById('uiPosLeft');
    const uiPosRight = document.getElementById('uiPosRight');

    closeBtn.addEventListener('click', closeUI);
    settingsBtn.addEventListener('click', openSettingsModal);
    addOutfitBtn.addEventListener('click', openNameModal);
    cancelBtn.addEventListener('click', closeNameModal);
    saveBtn.addEventListener('click', saveNewOutfit);
    renameCancelBtn.addEventListener('click', closeRenameModal);
    renameConfirmBtn.addEventListener('click', confirmRename);
    settingsModalClose.addEventListener('click', closeSettingsModal);
    settingsApplyBtn.addEventListener('click', applySettings);
    settingsDefaultBtn.addEventListener('click', resetToPreset);
    uiPosLeft.addEventListener('click', () => setUiPosition('left'));
    uiPosRight.addEventListener('click', () => setUiPosition('right'));

    setupPresetButtons();
    setupColorSync();

    // ESC key to close UI
    document.addEventListener('keydown', function(event) {
        if (event.key === 'Escape') {
            const settingsModal = document.getElementById('settingsModal');
            if (settingsModal && !settingsModal.classList.contains('hidden')) {
                closeSettingsModal();
                return;
            }
            closeUI();
        }
    });

    // Focus input on modal open
    const nameModal = document.getElementById('nameModal');
    const renameModal = document.getElementById('renameModal');
    const settingsModal = document.getElementById('settingsModal');

    nameModal.addEventListener('shown.bs.modal', () => {
        document.getElementById('outfitNameInput').focus();
    });

    renameModal.addEventListener('shown.bs.modal', () => {
        document.getElementById('renameInput').focus();
    });

    settingsModal.addEventListener('click', (event) => {
        if (event.target === settingsModal) {
            closeSettingsModal();
        }
    });

    loadUiPosition();
    loadThemeColors();
});

// NUI Message Handler
window.addEventListener('message', function(event) {
    const data = event.data;

    if (data.action === 'show') {
        showUI(data.outfits || []);
    } else if (data.action === 'hide') {
        hideUI();
    } else if (data.action === 'updateOutfits') {
        updateOutfits(data.outfits || []);
    }
});

function showUI(outfits) {
    currentOutfits = outfits;
    const container = document.getElementById('outfitBagContainer');
    loadUiPosition();
    loadThemeColors();
    container.classList.add('visible');
    renderOutfits();
}

function hideUI() {
    const container = document.getElementById('outfitBagContainer');
    container.classList.remove('visible');
}

function updateOutfits(outfits) {
    currentOutfits = outfits;
    renderOutfits();
}

function renderOutfits() {
    const outfitsList = document.getElementById('outfitsList');
    const emptyState = document.getElementById('emptyState');

    outfitsList.innerHTML = '';

    if (currentOutfits.length === 0) {
        emptyState.style.display = 'flex';
        return;
    } else {
        emptyState.style.display = 'none';
    }

    currentOutfits.forEach((outfit, index) => {
        const outfitItem = document.createElement('div');
        outfitItem.className = 'outfit-item';
        outfitItem.innerHTML = `
            <div class="outfit-name" onclick="loadOutfit(${index})">
                <i class="fas fa-shirt"></i>
                <span>${outfit.name}</span>
            </div>
            <div class="outfit-actions">
                <button class="outfit-btn rename-btn" onclick="openRenameModal(${index})" title="Rename">
                    <i class="fas fa-pen"></i>
                </button>
                <button class="outfit-btn delete-btn" onclick="deleteOutfit(${index})" title="Delete">
                    <i class="fas fa-trash"></i>
                </button>
            </div>
        `;
        outfitsList.appendChild(outfitItem);
    });
}

function openNameModal() {
    const modal = document.getElementById('nameModal');
    const input = document.getElementById('outfitNameInput');
    
    // Calculate default name
    const defaultName = `Outfit ${currentOutfits.length + 1}`;
    input.value = defaultName;
    input.select();
    
    modal.classList.add('visible');
}

function closeNameModal() {
    const modal = document.getElementById('nameModal');
    modal.classList.remove('visible');
}

function saveNewOutfit() {
    const input = document.getElementById('outfitNameInput');
    const outfitName = input.value.trim() || `Outfit ${currentOutfits.length + 1}`;
    
    fetch(`https://${GetParentResourceName()}/saveOutfit`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
        },
        body: JSON.stringify({
            outfitName: outfitName
        })
    }).then(resp => resp.json()).then(resp => {
        closeNameModal();
    }).catch(error => {
        console.error('Error saving outfit:', error);
    });
}

function loadOutfit(index) {
    if (currentOutfits[index]) {
        fetch(`https://${GetParentResourceName()}/loadOutfit`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                outfit: currentOutfits[index]
            })
        }).then(resp => resp.json()).then(resp => {
        }).catch(error => {
            console.error('Error loading outfit:', error);
        });
    }
}

function openRenameModal(index) {
    renameIndex = index;
    const modal = document.getElementById('renameModal');
    const input = document.getElementById('renameInput');
    
    input.value = currentOutfits[index].name;
    input.select();
    
    modal.classList.add('visible');
}

function closeRenameModal() {
    const modal = document.getElementById('renameModal');
    modal.classList.remove('visible');
    renameIndex = null;
}

function confirmRename() {
    if (renameIndex !== null) {
        const input = document.getElementById('renameInput');
        const newName = input.value.trim();
        
        if (newName.length > 0) {
            fetch(`https://${GetParentResourceName()}/renameOutfit`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    outfitId: currentOutfits[renameIndex].id,
                    newName: newName
                })
            }).then(resp => resp.json()).then(resp => {
                closeRenameModal();
            }).catch(error => {
                console.error('Error renaming outfit:', error);
            });
        }
    }
}

function deleteOutfit(index) {
    if (confirm(`Are you sure you want to delete "${currentOutfits[index].name}"?`)) {
        fetch(`https://${GetParentResourceName()}/deleteOutfit`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                outfitId: currentOutfits[index].id
            })
        }).then(resp => resp.json()).then(resp => {
        }).catch(error => {
            console.error('Error deleting outfit:', error);
        });
    }
}

function closeUI() {
    fetch(`https://${GetParentResourceName()}/closeUI`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
        },
        body: JSON.stringify({})
    }).then(resp => resp.json()).then(resp => {
        hideUI();
    }).catch(error => {
        console.error('Error closing UI:', error);
    });
}

function openSettingsModal() {
    const settingsModal = document.getElementById('settingsModal');
    settingsModal.classList.remove('hidden');
}

function closeSettingsModal() {
    const settingsModal = document.getElementById('settingsModal');
    settingsModal.classList.add('hidden');
}

function setUiPosition(position) {
    const container = document.getElementById('outfitBagContainer');
    container.classList.toggle('left', position === 'left');
    localStorage.setItem('pf-outfitbag-ui-position', position);
    updateUiPositionButtons(position);
}

function loadUiPosition() {
    const position = localStorage.getItem('pf-outfitbag-ui-position') || 'right';
    setUiPosition(position);
}

function updateUiPositionButtons(position) {
    const uiPosLeft = document.getElementById('uiPosLeft');
    const uiPosRight = document.getElementById('uiPosRight');
    if (!uiPosLeft || !uiPosRight) return;
    uiPosLeft.classList.toggle('active', position === 'left');
    uiPosRight.classList.toggle('active', position === 'right');
}

function getColorInputs() {
    return {
        primary: document.getElementById('colorPrimary'),
        primaryHex: document.getElementById('colorPrimaryHex'),
        secondary: document.getElementById('colorSecondary'),
        secondaryHex: document.getElementById('colorSecondaryHex'),
        accent: document.getElementById('colorAccent'),
        accentHex: document.getElementById('colorAccentHex'),
        success: document.getElementById('colorSuccess'),
        successHex: document.getElementById('colorSuccessHex'),
        danger: document.getElementById('colorDanger'),
        dangerHex: document.getElementById('colorDangerHex'),
        text: document.getElementById('colorText'),
        textHex: document.getElementById('colorTextHex'),
        textSecondary: document.getElementById('colorTextSecondary'),
        textSecondaryHex: document.getElementById('colorTextSecondaryHex'),
        border: document.getElementById('colorBorder'),
        borderHex: document.getElementById('colorBorderHex')
    };
}

const THEME_PRESETS = {
    default: {
        primary: '#0f1419',
        secondary: '#1a202c',
        accent: '#00d9ff',
        success: '#2dd4bf',
        danger: '#ff6b6b',
        text: '#f8fafc',
        textSecondary: '#94a3b8',
        border: '#2d3748'
    },
    dark: {
        primary: '#0f172a',
        secondary: '#111827',
        accent: '#60a5fa',
        success: '#22c55e',
        danger: '#ef4444',
        text: '#e5e7eb',
        textSecondary: '#9ca3af',
        border: '#1f2937'
    },
    green: {
        primary: '#042f2e',
        secondary: '#064e3b',
        accent: '#10b981',
        success: '#34d399',
        danger: '#f87171',
        text: '#ecfdf5',
        textSecondary: '#a7f3d0',
        border: '#0f766e'
    },
    purple: {
        primary: '#2a0a3b',
        secondary: '#3f0f5c',
        accent: '#d946ef',
        success: '#a78bfa',
        danger: '#fb7185',
        text: '#f5f3ff',
        textSecondary: '#c4b5fd',
        border: '#6d28d9'
    },
    orange: {
        primary: '#2a1608',
        secondary: '#5a2e0c',
        accent: '#f97316',
        success: '#fb923c',
        danger: '#f87171',
        text: '#fff7ed',
        textSecondary: '#fdba74',
        border: '#7c2d12'
    },
    custom: null
};

let activePreset = 'default';

function setupPresetButtons() {
    const presetButtons = document.querySelectorAll('.color-preset');
    presetButtons.forEach((btn) => {
        btn.addEventListener('click', () => {
            const preset = btn.getAttribute('data-preset');
            if (!preset || !THEME_PRESETS[preset]) {
                activePreset = 'custom';
                updatePresetButtons();
                return;
            }
            activePreset = preset;
            applyPreset(preset);
            updatePresetButtons();
        });
    });
    updatePresetButtons();
}

function updatePresetButtons() {
    document.querySelectorAll('.color-preset').forEach((btn) => {
        btn.classList.toggle('active', btn.getAttribute('data-preset') === activePreset);
    });
}

function applyPreset(presetName) {
    const preset = THEME_PRESETS[presetName];
    if (!preset) return;
    const inputs = getColorInputs();
    setInputPair(inputs.primary, inputs.primaryHex, preset.primary);
    setInputPair(inputs.secondary, inputs.secondaryHex, preset.secondary);
    setInputPair(inputs.accent, inputs.accentHex, preset.accent);
    setInputPair(inputs.success, inputs.successHex, preset.success);
    setInputPair(inputs.danger, inputs.dangerHex, preset.danger);
    setInputPair(inputs.text, inputs.textHex, preset.text);
    setInputPair(inputs.textSecondary, inputs.textSecondaryHex, preset.textSecondary);
    setInputPair(inputs.border, inputs.borderHex, preset.border);
    applyThemeFromInputs();
}

function setInputPair(colorInput, hexInput, value) {
    if (colorInput) colorInput.value = value;
    if (hexInput) hexInput.value = value;
}

function setupColorSync() {
    const inputs = getColorInputs();
    syncColorInputs(inputs.primary, inputs.primaryHex);
    syncColorInputs(inputs.secondary, inputs.secondaryHex);
    syncColorInputs(inputs.accent, inputs.accentHex);
    syncColorInputs(inputs.success, inputs.successHex);
    syncColorInputs(inputs.danger, inputs.dangerHex);
    syncColorInputs(inputs.text, inputs.textHex);
    syncColorInputs(inputs.textSecondary, inputs.textSecondaryHex);
    syncColorInputs(inputs.border, inputs.borderHex);
}

function syncColorInputs(colorInput, hexInput) {
    if (!colorInput || !hexInput) return;
    colorInput.addEventListener('input', (e) => {
        hexInput.value = e.target.value;
        activePreset = 'custom';
        updatePresetButtons();
        applyThemeFromInputs();
    });
    hexInput.addEventListener('input', (e) => {
        const val = e.target.value;
        if (/^#[0-9A-F]{6}$/i.test(val)) {
            colorInput.value = val;
            activePreset = 'custom';
            updatePresetButtons();
            applyThemeFromInputs();
        }
    });
}

function applyThemeFromInputs() {
    const inputs = getColorInputs();
    const root = document.documentElement;
    if (inputs.primary) root.style.setProperty('--primary-color', inputs.primary.value);
    if (inputs.secondary) root.style.setProperty('--secondary-color', inputs.secondary.value);
    if (inputs.accent) root.style.setProperty('--accent-color', inputs.accent.value);
    if (inputs.success) root.style.setProperty('--success-color', inputs.success.value);
    if (inputs.danger) root.style.setProperty('--danger-color', inputs.danger.value);
    if (inputs.text) root.style.setProperty('--text-primary', inputs.text.value);
    if (inputs.textSecondary) root.style.setProperty('--text-secondary', inputs.textSecondary.value);
    if (inputs.border) root.style.setProperty('--border-color', inputs.border.value);
}

function applySettings() {
    saveThemeColors();
    closeSettingsModal();
}

function resetToPreset() {
    applyPreset(activePreset === 'custom' ? 'default' : activePreset);
    saveThemeColors();
}

function saveThemeColors() {
    const inputs = getColorInputs();
    const data = {
        primary: inputs.primary?.value,
        secondary: inputs.secondary?.value,
        accent: inputs.accent?.value,
        success: inputs.success?.value,
        danger: inputs.danger?.value,
        text: inputs.text?.value,
        textSecondary: inputs.textSecondary?.value,
        border: inputs.border?.value,
        preset: activePreset
    };
    localStorage.setItem('pf-outfitbag-theme', JSON.stringify(data));
}

function loadThemeColors() {
    const stored = localStorage.getItem('pf-outfitbag-theme');
    if (!stored) {
        applyPreset('default');
        return;
    }
    const data = JSON.parse(stored);
    activePreset = data.preset || 'custom';
    const inputs = getColorInputs();
    if (inputs.primary && data.primary) setInputPair(inputs.primary, inputs.primaryHex, data.primary);
    if (inputs.secondary && data.secondary) setInputPair(inputs.secondary, inputs.secondaryHex, data.secondary);
    if (inputs.accent && data.accent) setInputPair(inputs.accent, inputs.accentHex, data.accent);
    if (inputs.success && data.success) setInputPair(inputs.success, inputs.successHex, data.success);
    if (inputs.danger && data.danger) setInputPair(inputs.danger, inputs.dangerHex, data.danger);
    if (inputs.text && data.text) setInputPair(inputs.text, inputs.textHex, data.text);
    if (inputs.textSecondary && data.textSecondary) setInputPair(inputs.textSecondary, inputs.textSecondaryHex, data.textSecondary);
    if (inputs.border && data.border) setInputPair(inputs.border, inputs.borderHex, data.border);
    applyThemeFromInputs();
    updatePresetButtons();
}

function GetParentResourceName() {
    return 'pf-outfitbag';
}
