// ============================================================================
// RICH TEXT EDITOR (RTE) - Lightweight Implementation
// ============================================================================

console.log('[RTE] Script loaded');

class RichTextEditor {
    constructor(containerId, options = {}) {
        this.container = document.getElementById(containerId);
        if (!this.container) {
            console.error(`RTE: Container "${containerId}" not found`);
            return;
        }

        this.options = {
            minHeight: options.minHeight || '200px',
            maxHeight: options.maxHeight || '60vh',
            placeholder: options.placeholder || 'Start typing...',
            readonly: options.readonly || false,
            showToolbar: options.showToolbar !== false,
            ...options
        };

        this.content = options.initialContent || '';
        this.isMaximized = false;
        this.build();
        this.attachEvents();
    }

    build() {
        const wrapper = document.createElement('div');
        wrapper.className = 'rte-wrapper';

        if (!this.options.readonly && this.options.showToolbar) {
            const toolbar = document.createElement('div');
            toolbar.className = 'rte-toolbar';
            toolbar.innerHTML = `
                <div class="rte-toolbar-group">
                    <button class="rte-btn" title="Bold (Ctrl+B)" data-cmd="bold">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <path d="M6 4h8a4 4 0 0 1 4 4 4 4 0 0 1-4 4H6z"></path>
                            <path d="M6 12h9a4 4 0 0 1 4 4 4 4 0 0 1-4 4H6z"></path>
                        </svg>
                    </button>
                    <button class="rte-btn" title="Italic (Ctrl+I)" data-cmd="italic">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <line x1="19" y1="4" x2="10" y2="4"></line>
                            <line x1="14" y1="20" x2="5" y2="20"></line>
                            <line x1="15" y1="4" x2="9" y2="20"></line>
                        </svg>
                    </button>
                    <button class="rte-btn" title="Underline (Ctrl+U)" data-cmd="underline">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <path d="M6 3v7a6 6 0 0 0 6 6 6 6 0 0 0 6-6V3"></path>
                            <line x1="4" y1="21" x2="20" y2="21"></line>
                        </svg>
                    </button>
                </div>
                <div class="rte-toolbar-group">
                    <button class="rte-btn" title="Heading 1" data-cmd="h1">H1</button>
                    <button class="rte-btn" title="Heading 2" data-cmd="h2">H2</button>
                    <button class="rte-btn" title="Heading 3" data-cmd="h3">H3</button>
                </div>
                <div class="rte-toolbar-group">
                    <button class="rte-btn" title="Bullet List" data-cmd="bullet">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <line x1="8" y1="6" x2="21" y2="6"></line>
                            <line x1="8" y1="12" x2="21" y2="12"></line>
                            <line x1="8" y1="18" x2="21" y2="18"></line>
                            <circle cx="3" cy="6" r="1" fill="currentColor"></circle>
                            <circle cx="3" cy="12" r="1" fill="currentColor"></circle>
                            <circle cx="3" cy="18" r="1" fill="currentColor"></circle>
                        </svg>
                    </button>
                    <button class="rte-btn" title="Numbered List" data-cmd="numbered">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <line x1="10" y1="6" x2="21" y2="6"></line>
                            <line x1="10" y1="12" x2="21" y2="12"></line>
                            <line x1="10" y1="18" x2="21" y2="18"></line>
                            <path d="M4 6h1v-2"></path>
                            <path d="M5 12h-2l2-2"></path>
                            <path d="M4 18h1v-2h-1"></path>
                        </svg>
                    </button>
                </div>
                <div class="rte-toolbar-group">
                    <button class="rte-btn rte-btn-emoji" title="Emoji" data-emoji-toggle="true">😊</button>
                    <button class="rte-btn" title="Clear Formatting" data-cmd="clear">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <path d="M3 6h18"></path>
                            <path d="M8 6v12"></path>
                            <path d="M16 6v12"></path>
                        </svg>
                    </button>
                </div>
            `;
            wrapper.appendChild(toolbar);

            const emojiPanel = document.createElement('div');
            emojiPanel.className = 'rte-emoji-panel';
            const emojis = ['😀','😁','😂','🤣','😃','😄','😅','😆','😉','😊','😋','😎','😍','😘','🥰','😗','😙','😚','🙂','🤗','🤔','😐','😑','😶','🙄','😏','😣','😥','😮','😯','😪','😫','😴','😌','😛','😜','😝','😒','😓','😔','😕','🙃','😲','😞','😟','😤','😢','😭','😦','😧','😨','😩','😬','😰','😱','😳','😵','😡','😠','👍','👎','👌','✌️','🤞','🤟','🤘','👋','🤚','👏','🙌','👐','🤝','🙏','💪','🎉','🎊','🎈','🎁','🎀','🏆','🥇','🥈','🥉','⭐','🌟','✨','💫','🔥','💯','❤️','🧡','💛','💚','💙','💜','🖤','🤍','💔','❣️','💕','💞','💓','💗','💖','💘','💝'];
            emojiPanel.innerHTML = emojis.map(e => `<button class="rte-emoji-item" type="button">${e}</button>`).join('');
            wrapper.appendChild(emojiPanel);
        }

        const editor = document.createElement('div');
        editor.className = 'rte-editor';
        editor.contentEditable = !this.options.readonly;
        editor.innerHTML = this.content || '';
        editor.setAttribute('data-placeholder', this.options.placeholder);
        editor.style.minHeight = this.options.minHeight;
        editor.style.maxHeight = this.options.maxHeight;
        this.editor = editor;
        wrapper.appendChild(editor);

        this.container.innerHTML = '';
        this.container.appendChild(wrapper);
    }

    attachEvents() {
        if (!this.editor) return;

        const toolbar = this.container.querySelector('.rte-toolbar');
        if (toolbar) {
            toolbar.querySelectorAll('[data-cmd]').forEach(btn => {
                btn.addEventListener('click', (e) => {
                    e.preventDefault();
                    this.executeCommand(btn.dataset.cmd);
                });
            });

            const emojiToggle = toolbar.querySelector('[data-emoji-toggle]');
            const emojiPanel = this.container.querySelector('.rte-emoji-panel');
            if (emojiToggle && emojiPanel) {
                emojiToggle.addEventListener('click', (e) => {
                    e.preventDefault();
                    e.stopPropagation();
                    emojiPanel.classList.toggle('open');
                });

                emojiPanel.addEventListener('click', (e) => {
                    const btn = e.target.closest('.rte-emoji-item');
                    if (!btn) return;
                    e.preventDefault();
                    const emoji = btn.textContent;
                    this.editor.focus();
                    document.execCommand('insertText', false, emoji);
                    emojiPanel.classList.remove('open');
                });

                document.addEventListener('click', (e) => {
                    if (!emojiPanel.contains(e.target) && !emojiToggle.contains(e.target)) {
                        emojiPanel.classList.remove('open');
                    }
                });
            }
        }

        this.editor.addEventListener('keydown', (e) => {
            if (e.ctrlKey || e.metaKey) {
                if (e.key === 'b') { e.preventDefault(); this.executeCommand('bold'); }
                if (e.key === 'i') { e.preventDefault(); this.executeCommand('italic'); }
                if (e.key === 'u') { e.preventDefault(); this.executeCommand('underline'); }
            }
        });

        this.editor.addEventListener('input', () => this.managePlaceholder());
        this.managePlaceholder();
    }

    executeCommand(cmd) {
        this.editor.focus();
        
        switch (cmd) {
            case 'bold':
                document.execCommand('bold', false, null);
                break;
            case 'italic':
                document.execCommand('italic', false, null);
                break;
            case 'underline':
                document.execCommand('underline', false, null);
                break;
            case 'h1':
                document.execCommand('formatBlock', false, '<h1>');
                break;
            case 'h2':
                document.execCommand('formatBlock', false, '<h2>');
                break;
            case 'h3':
                document.execCommand('formatBlock', false, '<h3>');
                break;
            case 'bullet':
                document.execCommand('insertUnorderedList', false, null);
                break;
            case 'numbered':
                document.execCommand('insertOrderedList', false, null);
                break;
            case 'clear':
                document.execCommand('removeFormat', false, null);
                break;
        }
    }

    managePlaceholder() {
        if (this.editor.textContent.trim().length === 0) {
            this.editor.innerHTML = '';
        }
    }

    getValue() {
        return this.editor.innerHTML || '';
    }

    getPlainText() {
        return this.editor.textContent || '';
    }

    setValue(html) {
        this.content = html;
        if (this.editor) {
            this.editor.innerHTML = html || '';
            this.managePlaceholder();
        }
    }

    clear() {
        this.setValue('');
    }

    focus() {
        if (this.editor) this.editor.focus();
    }
}

function createRTE(containerId, options = {}) {
    return new RichTextEditor(containerId, options);
}
