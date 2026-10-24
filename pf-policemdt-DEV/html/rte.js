// ============================================================================
// POLICE MDT - RICH TEXT EDITOR (RTE)
// ============================================================================
// A lightweight, self-contained rich text editor for MDT forms
// Supports: bold, italic, underline, headings, bullet points, code blocks

console.log('[RTE] Script loaded successfully');

const RTE_EMOJI_MAP = {
    smile: '😄',
    grin: '😁',
    joy: '😂',
    laughing: '😆',
    wink: '😉',
    blush: '😊',
    heart_eyes: '😍',
    kiss: '😘',
    thinking: '🤔',
    neutral_face: '😐',
    expressionless: '😑',
    smirk: '😏',
    sweat_smile: '😅',
    cry: '😢',
    sob: '😭',
    angry: '😠',
    rage: '😡',
    thumbsup: '👍',
    thumbsdown: '👎',
    ok_hand: '👌',
    clap: '👏',
    fire: '🔥',
    star: '⭐',
    warning: '⚠️',
    x: '❌',
    check: '✅'
};

function rteReplaceEmojiCodes(s) {
    return String(s).replace(/:([a-z0-9_+-]+):/gi, (m, code) => {
        const key = String(code).toLowerCase();
        return RTE_EMOJI_MAP[key] || m;
    });
}

function rteReplaceShortcodesInElement(root) {
    if (!root) return;
    const sel = window.getSelection();
    const anchorNode = sel && sel.anchorNode ? sel.anchorNode : null;
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    nodes.forEach(node => {
        if (!node.nodeValue || node.nodeValue.indexOf(':') === -1) return;
        const replaced = rteReplaceEmojiCodes(node.nodeValue);
        if (replaced !== node.nodeValue) {
            const wasAnchor = anchorNode === node;
            node.nodeValue = replaced;
            if (wasAnchor && sel) {
                const range = document.createRange();
                range.setStart(node, node.nodeValue.length);
                range.collapse(true);
                sel.removeAllRanges();
                sel.addRange(range);
            }
        }
    });
}

function rteEscapeHtml(str) {
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

function rteMarkdownToHtml(text) {
    const lines = String(text || '').replace(/\r\n?/g, '\n').split('\n');
    const out = [];
    let inList = false;

    const formatInline = (s) => {
        let safe = rteEscapeHtml(rteReplaceEmojiCodes(s));
        safe = safe.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
        safe = safe.replace(/__([^_]+)__/g, '<strong>$1</strong>');
        safe = safe.replace(/\*(?!\*)([^*]+)\*(?!\*)/g, '<em>$1</em>');
        safe = safe.replace(/_(?!_)([^_]+)_(?!_)/g, '<em>$1</em>');
        return safe;
    };

    const closeList = () => {
        if (inList) {
            out.push('</ul>');
            inList = false;
        }
    };

    for (const raw of lines) {
        const line = raw.trim();
        if (!line) {
            closeList();
            continue;
        }

        if (line.startsWith('### ')) {
            closeList();
            out.push(`<h3>${formatInline(line.slice(4))}</h3>`);
            continue;
        }
        if (line.startsWith('## ')) {
            closeList();
            out.push(`<h2>${formatInline(line.slice(3))}</h2>`);
            continue;
        }
        if (line.startsWith('# ')) {
            closeList();
            out.push(`<h1>${formatInline(line.slice(2))}</h1>`);
            continue;
        }

        if (line.startsWith('- ') || line.startsWith('* ')) {
            if (!inList) {
                out.push('<ul>');
                inList = true;
            }
            out.push(`<li>${formatInline(line.slice(2))}</li>`);
            continue;
        }

        closeList();
        out.push(`<p>${formatInline(line)}</p>`);
    }

    closeList();
    return out.join('');
}

const RTE_EMOJI_LIST = [
    '😀','😁','😂','🤣','😃','😄','😅','😆','😉','😊','😋','😎','😍','😘','🥰','😗','😙','😚','🙂','🤗',
    '🤩','🤔','🤨','😐','😑','😶','🙄','😏','😣','😥','😮','🤐','😯','😪','😫','🥱','😴','😌','😛','😜',
    '😝','🤤','😒','😓','😔','😕','🙃','🫠','😲','☹️','🙁','😖','😞','😟','😤','😢','😭','😦','😧','😨',
    '😩','😬','😰','😱','🥵','🥶','😳','🤯','😵','😵‍💫','😡','😠','🤬','😷','🤒','🤕','🤢','🤮','🤧','😇',
    '🥳','🥸','😎','🤓','🧐','😈','👿','🤡','👹','👺','💀','☠️','👻','👽','👾','🤖','🎃','😺','😸','😹',
    '😻','😼','😽','🙀','😿','😾','🙈','🙉','🙊','💋','💌','💘','💝','💖','💗','💓','💞','💕','💟','❣️',
    '💔','❤️','🧡','💛','💚','💙','💜','🤎','🖤','🤍','💯','💢','💥','💫','💦','💨','🕳️','💣','💬','👋',
    '🤚','🖐️','✋','🖖','👌','🤌','🤏','✌️','🤞','🫰','🤟','🤘','🤙','👈','👉','👆','🖕','👇','☝️','👍',
    '👎','✊','👊','🤛','🤜','👏','🙌','🫶','👐','🤲','🤝','🙏','✍️','💅','🤳','💪','🦾','🦿','🦵','🦶',
    '👂','🦻','👃','🧠','🫀','🫁','🦷','🦴','👀','👁️','👅','👄','🫦','👶','🧒','👦','👧','🧑','👱','👨',
    '👩','🧔','👴','👵','🧓','🙍','🙎','🙅','🙆','💁','🙋','🧏','🙇','🤦','🤷','💆','💇','🚶','🏃','🧍',
    '🧎','🧑‍🦯','🧑‍🦼','🧑‍🦽','👯','🧖','🧗','🤺','🏇','⛷️','🏂','🏌️','🏄','🚣','🏊','🤽','🚴','🚵','🤸','🤼',
    '🤹','🧘','🛀','🛌','👤','👥','🗣️','👣','🐶','🐱','🐭','🐹','🐰','🦊','🐻','🐼','🐻‍❄️','🐨','🐯','🦁',
    '🐮','🐷','🐽','🐸','🐵','🙈','🙉','🙊','🐒','🐔','🐧','🐦','🐤','🐣','🐥','🦆','🦅','🦉','🦇','🐺',
    '🐗','🐴','🦄','🐝','🪲','🪳','🦋','🐌','🐞','🐜','🪰','🪱','🦂','🕷️','🕸️','🐢','🐍','🦎','🦖','🦕',
    '🐙','🦑','🦐','🦞','🦀','🐡','🐠','🐟','🐬','🐳','🐋','🦈','🐊','🐅','🐆','🦓','🦍','🦧','🐘','🦛',
    '🦏','🦒','🐪','🐫','🦙','🦘','🦬','🐃','🐂','🐄','🐎','🐖','🐏','🐑','🦌','🐐','🦙','🦝','🦨','🦡',
    '🦫','🦦','🦥','🐁','🐀','🐇','🐿️','🦔','🐾','🐉','🐲','🌵','🎄','🌲','🌳','🌴','🪵','🌱','🌿','☘️',
    '🍀','🎍','🪴','🎋','🍃','🍂','🍁','🍄','🐚','🪨','🌾','💐','🌷','🌹','🥀','🌺','🌸','🌼','🌻','🌞',
    '🌝','🌛','🌜','🌚','🌕','🌖','🌗','🌘','🌑','🌒','🌓','🌔','🌙','⭐','🌟','✨','⚡','☄️','💥','🔥',
    '🌪️','🌈','☀️','⛅','☁️','🌧️','⛈️','🌩️','🌨️','❄️','☃️','⛄','💧','🌊','💨','🧊','🍏','🍎','🍐','🍊',
    '🍋','🍌','🍉','🍇','🍓','🫐','🍈','🍒','🍑','🥭','🍍','🥥','🥝','🍅','🍆','🥑','🥦','🥬','🥒','🌶️',
    '🫑','🌽','🥕','🫒','🧄','🧅','🥔','🍠','🫘','🥐','🥯','🍞','🥖','🥨','🧀','🥚','🍳','🧈','🥞','🧇',
    '🥓','🥩','🍗','🍖','🌭','🍔','🍟','🍕','🥪','🥙','🧆','🌮','🌯','🥗','🥘','🍝','🍜','🍲','🍛','🍣',
    '🍱','🥟','🦪','🍤','🍙','🍚','🍘','🍥','🥮','🍢','🍡','🍧','🍨','🍦','🥧','🧁','🍰','🎂','🍮','🍭',
    '🍬','🍫','🍿','🍩','🍪','🥛','🍼','☕','🫖','🍵','🥤','🧃','🧉','🧋','🍺','🍻','🥂','🍷','🥃','🍸',
    '🍹','🧊','🥄','🍴','🍽️','🥣','🥡','🥢','🧂','⚽','🏀','🏈','⚾','🥎','🎾','🏐','🏉','🎱','🥏','🏓',
    '🏸','🥅','🏒','🏑','🥍','🏏','🥊','🥋','⛳','⛸️','🎣','🤿','🎽','🛹','🛼','🛷','⛷️','🏂','🏋️','🤼',
    '🤸','⛹️','🤺','🤾','🏌️','🏇','🧘','🧗','🏄','🏊','🚣','🚴','🚵','🎯','🪀','🎮','🕹️','🎲','🧩','♟️',
    '🎭','🎨','🎼','🎤','🎧','🎹','🥁','🪘','🎷','🎺','🎸','🪕','🎻','📱','💻','🖥️','🖨️','🖱️','⌨️','💽',
    '💾','💿','📀','📷','📸','📹','🎥','📽️','🎞️','📞','☎️','📟','📠','📺','📻','🎙️','🎚️','🎛️','🧭','⏱️',
    '⏲️','⏰','🕰️','⌛','⏳','📡','🔋','🔌','💡','🔦','🕯️','🪔','🧯','🛢️','💸','💵','💴','💶','💷','🪙',
    '💰','💳','🧾','💎','⚖️','🧰','🔧','🔨','⚒️','🛠️','⛏️','🪓','🪚','🔩','⚙️','🧱','⛓️','🧲','🔫','💣',
    '🧨','🧳','🛍️','🎒','🪠','🪣','🧴','🧷','🧹','🧺','🧻','🪥','🪒','🧼','🧽','🪤','🧯','🧸','🪅','🎈',
    '🎉','🎊','🎎','🎏','🎐','🎀','🎁','🎃','🧧','🎄','🎆','🎇','🧨','✨','🎗️','🎟️','🎫','🎖️','🏆','🏅',
    '🥇','🥈','🥉','⚔️','🛡️','🏹','🗡️','🪓','🔪','🧿','🪬','📿','💈','⚗️','🔭','🔬','🧫','🧪','🧬','📡',
    '🚗','🚕','🚙','🚌','🚎','🏎️','🚓','🚑','🚒','🚐','🚚','🚛','🚜','🛻','🚲','🛵','🏍️','🚨','🚔','🚍',
    '🚘','🚖','🚡','🚠','🚟','🚃','🚋','🚞','🚝','🚄','🚅','🚈','🚂','🚆','🚇','🚊','🚉','✈️','🛫','🛬',
    '🛩️','💺','🛰️','🚀','🛸','🚁','🛶','⛵','🚤','🛥️','🛳️','⛴️','🚢','⚓','🛟','🏁','🚦','🚧','🛑','⚠️',
    '🚏','🗺️','🗿','🗽','🗼','🏰','🏯','🏟️','🎡','🎢','🎠','⛲','⛺','🏕️','🏖️','🏜️','🏝️','🏞️','🏔️','⛰️',
    '🌋','🗻','🏙️','🌆','🌇','🌃','🌉','🌁','🛤️','🛣️','🏗️','🏭','🏢','🏬','🏣','🏤','🏥','🏦','🏨','🏪',
    '🏫','🏩','💒','🏛️','⛪','🕌','🕍','🛕','🕋','⛩️','🛐','🗾','🎌','🇺🇸','🇬🇧','🇨🇦','🇦🇺','🇫🇷','🇩🇪','🇮🇹',
    '🇪🇸','🇳🇱','🇧🇷','🇲🇽','🇯🇵','🇰🇷','🇨🇳','🇮🇳','🇸🇪','🇳🇴','🇫🇮','🇩🇰','🇵🇱','🇺🇦','🇹🇷','🇬🇷','🇮🇪','🇿🇦','🇳🇿','🇸🇬'
];

class RichTextEditor {
    constructor(containerId, options = {}) {
        this.container = document.getElementById(containerId);
        if (!this.container) {
            console.error(`RTE: Container "${containerId}" not found`);
            return;
        }
        console.log(`[RTE] Initializing RTE for container: ${containerId}`);

        this.options = {
            minHeight: options.minHeight || '100px',
            maxHeight: options.maxHeight || '40vh',
            placeholder: options.placeholder || 'Enter text...',
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
        wrapper.setAttribute('data-rte-id', this.getId());

        // Always show toolbar unless explicitly readonly
        if (!this.options.readonly && this.options.showToolbar !== false) {
            console.log(`[RTE] Creating toolbar for ${this.container.id}`);
            // Toolbar
            const toolbar = document.createElement('div');
            toolbar.className = 'rte-toolbar';
            toolbar.innerHTML = `
                <div class="rte-toolbar-group">
                    <button class="rte-btn rte-btn-bold" title="Bold (Ctrl+B)" data-cmd="bold">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <path d="M6 4h8a4 4 0 0 1 4 4 4 4 0 0 1-4 4H6z"></path>
                            <path d="M6 12h9a4 4 0 0 1 4 4 4 4 0 0 1-4 4H6z"></path>
                        </svg>
                    </button>
                    <button class="rte-btn rte-btn-italic" title="Italic (Ctrl+I)" data-cmd="italic">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <line x1="19" y1="4" x2="10" y2="4"></line>
                            <line x1="14" y1="20" x2="5" y2="20"></line>
                            <line x1="15" y1="4" x2="9" y2="20"></line>
                        </svg>
                    </button>
                    <button class="rte-btn rte-btn-underline" title="Underline (Ctrl+U)" data-cmd="underline">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <path d="M6 3v7a6 6 0 0 0 6 6 6 6 0 0 0 6-6V3"></path>
                            <line x1="4" y1="21" x2="20" y2="21"></line>
                        </svg>
                    </button>
                </div>
                <div class="rte-toolbar-group">
                    <button class="rte-btn rte-btn-heading1" title="Heading 1 (H1)" data-cmd="h1">H1</button>
                    <button class="rte-btn rte-btn-heading2" title="Heading 2 (H2)" data-cmd="h2">H2</button>
                    <button class="rte-btn rte-btn-heading3" title="Heading 3 (H3)" data-cmd="h3">H3</button>
                </div>
                <div class="rte-toolbar-group">
                    <button class="rte-btn rte-btn-align-left" title="Align Left" data-cmd="alignLeft">≡</button>
                    <button class="rte-btn rte-btn-align-center" title="Align Center" data-cmd="alignCenter">≡</button>
                    <button class="rte-btn rte-btn-align-right" title="Align Right" data-cmd="alignRight">≡</button>
                </div>
                <div class="rte-toolbar-group">
                    <button class="rte-btn rte-btn-bullet" title="Bullet List" data-cmd="bullet">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <circle cx="5" cy="6" r="1"></circle>
                            <line x1="9" y1="6" x2="19" y2="6"></line>
                            <circle cx="5" cy="12" r="1"></circle>
                            <line x1="9" y1="12" x2="19" y2="12"></line>
                            <circle cx="5" cy="18" r="1"></circle>
                            <line x1="9" y1="18" x2="19" y2="18"></line>
                        </svg>
                    </button>
                    <button class="rte-btn rte-btn-code" title="Code Block" data-cmd="code">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <polyline points="16 18 22 12 16 6"></polyline>
                            <polyline points="8 6 2 12 8 18"></polyline>
                        </svg>
                    </button>
                </div>
                <div class="rte-toolbar-group">
                    <button class="rte-btn rte-btn-clear" title="Clear Formatting" data-cmd="clear">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <path d="M3 6h18"></path>
                            <path d="M8 6v12"></path>
                            <path d="M16 6v12"></path>
                            <line x1="3" y1="18" x2="21" y2="18"></line>
                        </svg>
                    </button>
                    <button class="rte-btn rte-btn-maximize" title="Maximize" data-cmd="maximize">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <path d="M8 3H5a2 2 0 0 0-2 2v3m18 0V5a2 2 0 0 0-2-2h-3m0 18h3a2 2 0 0 0 2-2v-3M3 16v3a2 2 0 0 0 2 2h3"></path>
                        </svg>
                    </button>
                    <button class="rte-btn rte-btn-emoji" title="Emoji" data-emoji-toggle="true">😊</button>
                    <button class="rte-btn rte-btn-templates" title="Templates" data-template-toggle="true">📄</button>
                </div>
            `;
            wrapper.appendChild(toolbar);

            const emojiPanel = document.createElement('div');
            emojiPanel.className = 'rte-emoji-panel';
            emojiPanel.setAttribute('aria-hidden', 'true');
            emojiPanel.innerHTML = RTE_EMOJI_LIST.map(e => `<button class="rte-emoji-item" type="button">${e}</button>`).join('');
            wrapper.appendChild(emojiPanel);

            const templatePanel = document.createElement('div');
            templatePanel.className = 'rte-template-panel';
            templatePanel.setAttribute('aria-hidden', 'true');
            templatePanel.innerHTML = '<div class="rte-template-empty">Loading templates...</div>';
            wrapper.appendChild(templatePanel);

            const imgToolbar = document.createElement('div');
            imgToolbar.className = 'rte-img-toolbar';
            imgToolbar.setAttribute('aria-hidden', 'true');
            imgToolbar.innerHTML = `
                <button class="rte-img-btn" type="button" data-img-size="25">25%</button>
                <button class="rte-img-btn" type="button" data-img-size="50">50%</button>
                <button class="rte-img-btn" type="button" data-img-size="75">75%</button>
                <button class="rte-img-btn" type="button" data-img-size="100">100%</button>
                <button class="rte-img-btn" type="button" data-img-size="auto">Auto</button>
                <button class="rte-img-btn" type="button" data-img-size="custom">Custom</button>
            `;
            wrapper.appendChild(imgToolbar);

            const handleWrap = document.createElement('div');
            handleWrap.className = 'rte-img-handles';
            handleWrap.setAttribute('aria-hidden', 'true');
            handleWrap.innerHTML = `
                <span class="rte-img-handle" data-handle="nw"></span>
                <span class="rte-img-handle" data-handle="ne"></span>
                <span class="rte-img-handle" data-handle="sw"></span>
                <span class="rte-img-handle" data-handle="se"></span>
            `;
            wrapper.appendChild(handleWrap);
        }

        // Editor
        const editor = document.createElement('div');
        editor.className = 'rte-editor';
        editor.contentEditable = !this.options.readonly;
        editor.innerHTML = this.content || '';
        editor.setAttribute('data-placeholder', this.options.placeholder);
        this.editor = editor;
        wrapper.appendChild(editor);

        // Replace container content
        this.container.innerHTML = '';
        this.container.appendChild(wrapper);
    }

    attachEvents() {
        if (!this.editor) return;

        // Toolbar button events
        const toolbar = this.container.querySelector('.rte-toolbar');
        if (toolbar) {
            toolbar.querySelectorAll('[data-cmd]').forEach(btn => {
                btn.addEventListener('click', (e) => {
                    e.preventDefault();
                    e.stopPropagation();
                    this.executeCommand(btn.dataset.cmd);
                });
            });

            const emojiToggle = toolbar.querySelector('[data-emoji-toggle]');
            const emojiPanel = this.container.querySelector('.rte-emoji-panel');
            if (emojiToggle && emojiPanel) {
                emojiToggle.addEventListener('click', (e) => {
                    e.preventDefault();
                    e.stopPropagation();
                    const isOpen = emojiPanel.classList.toggle('open');
                    emojiPanel.setAttribute('aria-hidden', isOpen ? 'false' : 'true');
                });

                emojiPanel.addEventListener('click', (e) => {
                    const btn = e.target.closest('.rte-emoji-item');
                    if (!btn) return;
                    e.preventDefault();
                    e.stopPropagation();
                    const emoji = btn.textContent || '';
                    if (emoji) {
                        this.editor.focus();
                        document.execCommand('insertText', false, emoji);
                    }
                });

                document.addEventListener('click', (e) => {
                    if (!emojiPanel.classList.contains('open')) return;
                    if (emojiPanel.contains(e.target) || emojiToggle.contains(e.target)) return;
                    emojiPanel.classList.remove('open');
                    emojiPanel.setAttribute('aria-hidden', 'true');
                });
            }

            const templateToggle = toolbar.querySelector('[data-template-toggle]');
            const templatePanel = this.container.querySelector('.rte-template-panel');
            if (templateToggle && templatePanel) {
                const renderTemplates = () => {
                    const list = (window.__mdtTemplateStore && window.__mdtTemplateStore.getTemplates) ? window.__mdtTemplateStore.getTemplates() : [];
                    if (!list || list.length === 0) {
                        templatePanel.innerHTML = `
                            <div class="rte-template-empty">No templates available.</div>
                            <div class="rte-template-actions">
                                <button class="rte-template-btn" data-template-action="refresh">Refresh</button>
                                <button class="rte-template-btn" data-template-action="manage">Manage</button>
                            </div>
                        `;
                        return;
                    }
                    templatePanel.innerHTML = list.map(t => `
                        <div class="rte-template-item" data-template-id="${t.id}">
                            <div class="rte-template-title">${t.title || 'Template'}</div>
                            <div class="rte-template-meta">${(t.visibility || 'private').toUpperCase()} • ${t.author_name || 'Officer'}</div>
                            <div class="rte-template-actions">
                                <button class="rte-template-btn" data-template-action="apply" data-template-id="${t.id}">Apply</button>
                            </div>
                        </div>
                    `).join('') + `
                        <div class="rte-template-actions">
                            <button class="rte-template-btn" data-template-action="refresh">Refresh</button>
                            <button class="rte-template-btn" data-template-action="manage">Manage</button>
                        </div>
                    `;
                };

                templateToggle.addEventListener('click', (e) => {
                    e.preventDefault();
                    e.stopPropagation();
                    renderTemplates();
                    const isOpen = templatePanel.classList.toggle('open');
                    templatePanel.setAttribute('aria-hidden', isOpen ? 'false' : 'true');
                });

                templatePanel.addEventListener('click', (e) => {
                    const btn = e.target.closest('[data-template-action]');
                    if (!btn) return;
                    e.preventDefault();
                    e.stopPropagation();
                    const action = btn.getAttribute('data-template-action');
                    if (action === 'refresh' && window.__mdtTemplateStore && window.__mdtTemplateStore.refresh) {
                        window.__mdtTemplateStore.refresh(() => renderTemplates());
                        return;
                    }
                    if (action === 'manage' && window.router) {
                        window.router.set('templates');
                        templatePanel.classList.remove('open');
                        templatePanel.setAttribute('aria-hidden', 'true');
                        return;
                    }
                    if (action === 'apply') {
                        const id = btn.getAttribute('data-template-id');
                        const list = (window.__mdtTemplateStore && window.__mdtTemplateStore.getTemplates) ? window.__mdtTemplateStore.getTemplates() : [];
                        const tpl = list.find(x => String(x.id) === String(id));
                        if (tpl) {
                            this.setValue(tpl.body_html || tpl.body || '');
                            this.focus();
                            templatePanel.classList.remove('open');
                            templatePanel.setAttribute('aria-hidden', 'true');
                        }
                    }
                });

                document.addEventListener('click', (e) => {
                    if (!templatePanel.classList.contains('open')) return;
                    if (templatePanel.contains(e.target) || templateToggle.contains(e.target)) return;
                    templatePanel.classList.remove('open');
                    templatePanel.setAttribute('aria-hidden', 'true');
                });
            }
        }

        // Image resize toolbar
        const imgToolbar = this.container.querySelector('.rte-img-toolbar');
        const imgHandles = this.container.querySelector('.rte-img-handles');
        if (imgToolbar) {
            imgToolbar.addEventListener('click', (e) => {
                const btn = e.target.closest('[data-img-size]');
                if (!btn || !this.currentImage) return;
                e.preventDefault();
                e.stopPropagation();
                const size = btn.getAttribute('data-img-size');
                if (size === 'auto') {
                    this.currentImage.style.width = '';
                    this.currentImage.style.height = '';
                    if (imgHandles) {
                        imgHandles.classList.remove('open');
                        imgHandles.setAttribute('aria-hidden', 'true');
                    }
                } else if (size === 'custom') {
                    if (imgHandles) {
                        this.positionImageHandles(this.currentImage, imgHandles);
                        imgHandles.classList.add('open');
                        imgHandles.setAttribute('aria-hidden', 'false');
                    }
                } else {
                    this.currentImage.style.width = `${size}%`;
                    this.currentImage.style.height = 'auto';
                    if (imgHandles) {
                        imgHandles.classList.remove('open');
                        imgHandles.setAttribute('aria-hidden', 'true');
                    }
                }
            });
        }

        // Keyboard shortcuts
        this.editor.addEventListener('keydown', (e) => {
            if (e.ctrlKey || e.metaKey) {
                if (e.key === 'b') { e.preventDefault(); this.executeCommand('bold'); }
                if (e.key === 'i') { e.preventDefault(); this.executeCommand('italic'); }
                if (e.key === 'u') { e.preventDefault(); this.executeCommand('underline'); }
            }
            if (e.key === 'Tab') {
                e.preventDefault();
                document.execCommand('insertHTML', false, '&nbsp;&nbsp;&nbsp;&nbsp;');
            }
        });

        // Image click to show resize toolbar
        this.editor.addEventListener('click', (e) => {
            const img = e.target && e.target.tagName === 'IMG' ? e.target : null;
            if (!img || !imgToolbar) {
                if (imgToolbar) {
                    imgToolbar.classList.remove('open');
                    imgToolbar.setAttribute('aria-hidden', 'true');
                }
                if (imgHandles) {
                    imgHandles.classList.remove('open');
                    imgHandles.setAttribute('aria-hidden', 'true');
                }
                return;
            }
            e.preventDefault();
            e.stopPropagation();
            this.currentImage = img;
            const wrapper = this.container.querySelector('.rte-wrapper');
            if (wrapper) {
                const r = img.getBoundingClientRect();
                const w = wrapper.getBoundingClientRect();
                const top = Math.min(r.bottom - w.top + 6, w.height - 40);
                const left = Math.min(Math.max(r.left - w.left, 8), w.width - 220);
                imgToolbar.style.top = `${top}px`;
                imgToolbar.style.left = `${left}px`;
            }
            imgToolbar.classList.add('open');
            imgToolbar.setAttribute('aria-hidden', 'false');
            if (imgHandles) {
                this.positionImageHandles(img, imgHandles);
                imgHandles.classList.add('open');
                imgHandles.setAttribute('aria-hidden', 'false');
            }
        });

        document.addEventListener('click', (e) => {
            if (!imgToolbar || !imgToolbar.classList.contains('open')) return;
            if (imgToolbar.contains(e.target) || this.editor.contains(e.target)) return;
            imgToolbar.classList.remove('open');
            imgToolbar.setAttribute('aria-hidden', 'true');
            if (imgHandles) {
                imgHandles.classList.remove('open');
                imgHandles.setAttribute('aria-hidden', 'true');
            }
        });

        if (imgHandles) {
            imgHandles.addEventListener('mousedown', (e) => {
                const handle = e.target.closest('.rte-img-handle');
                if (!handle || !this.currentImage) return;
                e.preventDefault();
                e.stopPropagation();

                const dir = handle.getAttribute('data-handle');
                const img = this.currentImage;
                const startRect = img.getBoundingClientRect();
                const startX = e.clientX;
                const startY = e.clientY;
                const aspect = startRect.width / Math.max(startRect.height, 1);

                const onMove = (ev) => {
                    const dx = ev.clientX - startX;
                    const dy = ev.clientY - startY;
                    let newW = startRect.width;

                    if (dir.includes('e')) newW = startRect.width + dx;
                    if (dir.includes('w')) newW = startRect.width - dx;

                    newW = Math.max(50, newW);
                    const newH = newW / aspect;
                    img.style.width = `${Math.round(newW)}px`;
                    img.style.height = `${Math.round(newH)}px`;
                    this.positionImageHandles(img, imgHandles);
                };

                const onUp = () => {
                    document.removeEventListener('mousemove', onMove);
                    document.removeEventListener('mouseup', onUp);
                };

                document.addEventListener('mousemove', onMove);
                document.addEventListener('mouseup', onUp);
            });
        }

        // Markdown-like paste support (#, ##, ###, *, **, - lists)
        this.editor.addEventListener('paste', (e) => {
            const html = e.clipboardData?.getData('text/html');
            if (html) return; // allow rich HTML paste as-is
            const text = e.clipboardData?.getData('text/plain');
            if (!text) return;
            if (!/[#*_\-]/.test(text) && !/:[a-z0-9_+-]+:/i.test(text)) return; // no markdown/emoji cues
            e.preventDefault();
            const converted = rteMarkdownToHtml(text);
            document.execCommand('insertHTML', false, converted);
        });

        // Placeholder management
        this.editor.addEventListener('blur', () => this.managePlaceholder());
        this.editor.addEventListener('input', () => this.managePlaceholder());

        // Live :emoji: shortcode replacement
        let emojiTimer = null;
        this.editor.addEventListener('input', () => {
            clearTimeout(emojiTimer);
            emojiTimer = setTimeout(() => {
                rteReplaceShortcodesInElement(this.editor);
            }, 60);
        });
        this.managePlaceholder();
    }

    executeCommand(cmd) {
        const sel = window.getSelection();
        const range = sel.rangeCount > 0 ? sel.getRangeAt(0) : null;

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
            case 'alignLeft':
                document.execCommand('justifyLeft', false, null);
                break;
            case 'alignCenter':
                document.execCommand('justifyCenter', false, null);
                break;
            case 'alignRight':
                document.execCommand('justifyRight', false, null);
                break;
            case 'bullet':
                document.execCommand('insertUnorderedList', false, null);
                break;
            case 'code':
                document.execCommand('formatBlock', false, '<pre>');
                break;
            case 'clear':
                document.execCommand('removeFormat', false, null);
                break;
            case 'maximize':
                this.toggleMaximize();
                break;
        }

        // Restore cursor position
        if (range) {
            const sel = window.getSelection();
            sel.removeAllRanges();
            sel.addRange(range);
        }

        this.editor.focus();
    }

    positionImageHandles(img, handleWrap) {
        const wrapper = this.container.querySelector('.rte-wrapper');
        if (!wrapper || !img || !handleWrap) return;
        const r = img.getBoundingClientRect();
        const w = wrapper.getBoundingClientRect();
        handleWrap.style.top = `${r.top - w.top - 6}px`;
        handleWrap.style.left = `${r.left - w.left - 6}px`;
        handleWrap.style.width = `${r.width + 12}px`;
        handleWrap.style.height = `${r.height + 12}px`;
    }

    toggleMaximize() {
        const wrapper = this.container.querySelector('.rte-wrapper');
        if (!wrapper) return;

        this.isMaximized = !this.isMaximized;

        if (this.isMaximized) {
            wrapper.classList.add('rte-maximized');
            this.editor.style.maxHeight = '70vh';
        } else {
            wrapper.classList.remove('rte-maximized');
            this.editor.style.maxHeight = this.options.maxHeight;
        }
    }

    managePlaceholder() {
        // CSS handles placeholder via :empty::before
        // Just ensure we don't have leftover <p><br></p> or similar
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

    getId() {
        return 'rte_' + Math.random().toString(36).substr(2, 9);
    }

    focus() {
        if (this.editor) this.editor.focus();
    }

    destroy() {
        if (this.editor) {
            this.editor.contentEditable = false;
            this.editor.removeEventListener('blur', () => {});
            this.editor.removeEventListener('input', () => {});
        }
    }
}

// Global registry to manage RTE instances
const rteInstances = new Map();

function createRTE(containerId, options = {}) {
    const rte = new RichTextEditor(containerId, options);
    rteInstances.set(containerId, rte);
    if (window.__mdtRTEManager && window.__mdtRTEManager.instances) {
        window.__mdtRTEManager.instances[containerId] = rte;
    }
    return rte;
}

function getRTE(containerId) {
    return rteInstances.get(containerId);
}

function destroyRTE(containerId) {
    const rte = rteInstances.get(containerId);
    if (rte) {
        rte.destroy();
        rteInstances.delete(containerId);
    }
}
