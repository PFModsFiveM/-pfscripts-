// ============================================================================
// CCTV Page for Police MDT
// ============================================================================

(function () {
    // Build stamp for cache/debug (update this line when troubleshooting)
    console.log('[CCTV] Loaded html/cctv.js (build 2025-12-27a)');

    const CAMERA_ICON_SVG = `
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <path d="M23 7l-7 5 7 5V7z"></path>
            <rect x="1" y="5" width="15" height="14" rx="2" ry="2"></rect>
        </svg>
    `;

    class CCTVPage extends BasePage {
        constructor() {
            super('cctv', 'CCTV');
            this.cameras = [];
            this.filteredCameras = [];
            this.searchQuery = '';
            this.page = 1;
            // Screenshot layout: 12 tiles per page (4 columns x 3 rows)
            this.pageSize = 12;
        }

        mount(root) {
            super.mount(root);
            root.innerHTML = `
                <div class="cctv-network">
                    <div class="cctv-network-header">
                        <div class="cctv-network-title">
                            <div class="cctv-network-title-row">
                                <span class="cctv-network-icon">📷</span>
                                <h2>Camera Network</h2>
                            </div>
                        </div>
                    </div>

                    <div class="cctv-network-search">
                        <input type="text" id="cctvSearch" class="cctv-search" placeholder="Search Cameras..." autocomplete="off" />
                    </div>

                    <div id="cctvGrid" class="cctv-grid"><div class="empty-message">Loading cameras...</div></div>

                    <div class="cctv-footer">
                        <div id="cctvCount" class="cctv-count">Showing 0 to 0 of 0 Cameras</div>
                        <div class="cctv-pager">
                            <button id="cctvPrev" class="btn">Previous</button>
                            <button id="cctvNext" class="btn">Next</button>
                        </div>
                    </div>
                </div>
            `;

            this.bindEvents();
            this.loadCameras();
        }

        bindEvents() {
            const searchInput = document.getElementById('cctvSearch');
            const prevBtn = document.getElementById('cctvPrev');
            const nextBtn = document.getElementById('cctvNext');
            const grid = document.getElementById('cctvGrid');

            if (searchInput) {
                searchInput.addEventListener('input', (e) => {
                    this.searchQuery = String((e.target && e.target.value) || '').toLowerCase();
                    this.page = 1;
                    this.filterAndRender();
                });
            }

            if (prevBtn) {
                prevBtn.addEventListener('click', () => {
                    if (this.page > 1) {
                        this.page -= 1;
                        this.renderGrid();
                    }
                });
            }

            if (nextBtn) {
                nextBtn.addEventListener('click', () => {
                    const maxPage = Math.max(1, Math.ceil(this.filteredCameras.length / this.pageSize));
                    if (this.page < maxPage) {
                        this.page += 1;
                        this.renderGrid();
                    }
                });
            }

            if (grid) {
                grid.addEventListener('click', (e) => {
                    const tile = e.target && e.target.closest ? e.target.closest('.cctv-tile') : null;
                    if (!tile) return;
                    const rawId = tile.getAttribute('data-id');
                    const online = tile.getAttribute('data-online') === '1';

                    const cameraId = (rawId && rawId !== 'undefined') ? Number(rawId) : NaN;
                    console.log('[CCTV] Tile clicked: id=' + rawId + ' (num=' + cameraId + '), online=' + online);

                    if (!Number.isFinite(cameraId) || cameraId <= 0 || !online) {
                        console.log('[CCTV] Ignoring click: id=' + rawId + ' (num=' + cameraId + '), online=' + online);
                        return;
                    }
                    console.log('[CCTV] Calling viewCamera with id=' + cameraId);
                    this.viewCamera(cameraId);
                });
            }
        }

        loadCameras() {
            console.log('[CCTV] loadCameras: Requesting camera list...');
            sendCallback('getCCTVList', {}, (res) => {
                console.log('[CCTV] loadCameras: Received response:', res);
                this.cameras = Array.isArray(res) ? res : [];
                console.log('[CCTV] loadCameras: Loaded ' + this.cameras.length + ' cameras');
                if (this.cameras.length > 0) {
                    console.log('[CCTV] First camera:', this.cameras[0]);
                }
                this.page = 1;
                this.filterAndRender();
            });
        }

        filterAndRender() {
            const q = this.searchQuery;
            this.filteredCameras = this.cameras.filter((cam) => {
                if (!q) return true;
                const label = String(cam.location_label || '').toLowerCase();
                const id = String(cam.id || '').toLowerCase();
                return label.includes(q) || id.includes(q);
            });

            this.filteredCameras.sort((a, b) => {
                const da = a && a.created_at ? new Date(a.created_at).getTime() : 0;
                const db = b && b.created_at ? new Date(b.created_at).getTime() : 0;
                return db - da;
            });

            this.renderGrid();
        }

        renderGrid() {
            const grid = document.getElementById('cctvGrid');
            const count = document.getElementById('cctvCount');
            if (!grid) return;

            const total = this.filteredCameras.length;
            const maxPage = Math.max(1, Math.ceil(total / this.pageSize));
            if (this.page > maxPage) this.page = maxPage;

            const start = (this.page - 1) * this.pageSize;
            const end = Math.min(start + this.pageSize, total);
            const slice = this.filteredCameras.slice(start, end);

            if (count) {
                count.textContent = `Showing ${total === 0 ? 0 : (start + 1)} to ${end} of ${total} Cameras`;
            }

            if (slice.length === 0) {
                grid.innerHTML = '<div class="empty-message">No cameras found</div>';
                return;
            }

            grid.innerHTML = slice.map((cam, idx) => {
                const status = String(cam.status || '').toUpperCase();
                const online = status !== 'OFFLINE';

                const title = escapeHtml(cam.location_label || ('Camera #' + (cam.id ?? '')) || 'Camera');
                const sub = escapeHtml(cam.location_label || '');
                const num = start + idx + 1;

                // Use camera id as the data attribute
                const idAttr = escapeHtml(String(cam.id ?? ''));


                return `
                    <div class="cctv-tile" data-id="${idAttr}" data-online="${online ? '1' : '0'}">
                        <div class="cctv-tile-top">
                            <div class="cctv-tile-id">
                                <span class="cctv-mini-icon" aria-hidden="true">${CAMERA_ICON_SVG}</span>
                                <span class="cctv-mini-num">${num}</span>
                            </div>
                            <span class="badge-pill cctv-online-pill ${online ? 'is-online' : 'is-offline'}">${online ? 'Online' : 'Offline'}</span>
                        </div>
                        <div class="cctv-preview">
                            <div class="cctv-preview-icon" aria-hidden="true">${CAMERA_ICON_SVG}</div>
                            <div class="cctv-live">LIVE</div>
                        </div>
                        <div class="cctv-tile-bottom">
                            <div class="cctv-tile-title">${title}</div>
                            <div class="cctv-tile-sub">${sub}</div>
                        </div>
                    </div>
                `;
            }).join('');
        }

        viewCamera(cameraId) {
            if (!Number.isFinite(cameraId) || cameraId <= 0) return;
            sendCallback('openCCTVViewer', { id: cameraId }, (res) => {
                if (res && res.success) {
                    // Camera view is now open; ESC will close it
                    return;
                }
                console.error('[CCTV] Failed to open camera viewer:', cameraId, res);
            });
        }

        onMessage(data) {
            if (data && data.action === 'setCCTVCameras') {
                this.cameras = Array.isArray(data.cameras) ? data.cameras : [];
                this.page = 1;
                this.filterAndRender();
            }
        }

        unmount() {
            super.unmount();
        }
    }

    window.CCTVPage = CCTVPage;
})();
