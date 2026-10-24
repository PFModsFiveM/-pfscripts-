// ============================================================================
// MDT RTE INITIALIZATION
// ============================================================================
// Manages Rich Text Editors globally - RTEs are initialized by their respective modal open functions

console.log('[RTE-INIT] Initialization script loaded');

(function initializeAllRTEs() {
    console.log('[RTE-INIT] Setting up RTE manager');
    // Global RTE manager
    window.__mdtRTEManager = {
        instances: {},
        
        ensure: function(id, options = {}) {
            if (!this.instances[id]) {
                try {
                    console.log(`[RTE-INIT] Creating RTE for: ${id}`);
                    this.instances[id] = new RichTextEditor(id, options);
                    console.log(`[RTE-INIT] Successfully created RTE for: ${id}`);
                } catch (e) {
                    console.error(`[RTE-INIT] Failed to initialize RTE for ${id}:`, e);
                }
            }
            return this.instances[id];
        },
        
        get: function(id) {
            return this.instances[id];
        },
        
        getValue: function(id) {
            const rte = this.instances[id];
            if (rte) return rte.getValue();
            const el = document.getElementById(id);
            return el ? el.innerHTML : '';
        },
        
        getPlainText: function(id) {
            const rte = this.instances[id];
            if (rte) return rte.getPlainText();
            const el = document.getElementById(id);
            return el ? el.textContent : '';
        },
        
        setValue: function(id, value) {
            const rte = this.instances[id];
            if (rte) rte.setValue(value);
        },
        
        clear: function(id) {
            const rte = this.instances[id];
            if (rte) rte.clear();
        },
        
        clearAll: function() {
            Object.values(this.instances).forEach(rte => {
                if (rte && typeof rte.clear === 'function') rte.clear();
            });
        }
    };
    
    console.log('[RTE-INIT] Manager setup complete');
    
    // Expose global helper functions for backward compatibility
    window.getRTEValue = function(id) {
        return window.__mdtRTEManager.getPlainText(id);
    };

    window.getRTEHTML = function(id) {
        return window.__mdtRTEManager.getValue(id);
    };

    window.setRTEValue = function(id, value) {
        return window.__mdtRTEManager.setValue(id, value);
    };
})();
