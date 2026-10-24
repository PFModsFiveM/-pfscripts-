(() => {
  const app = document.getElementById('app');
  const storeNameEl = document.getElementById('storeName');
  const storeSubtitleEl = document.getElementById('storeSubtitle');
  const storeLogoEl = document.getElementById('storeLogo');
  const categoriesEl = document.getElementById('categories');
  const itemsEl = document.getElementById('items');
  const emptyEl = document.getElementById('empty');
  const activeCategoryEl = document.getElementById('activeCategory');
  const categoryHintEl = document.getElementById('categoryHint');
  const cartItemsEl = document.getElementById('cartItems');
  const cartCountEl = document.getElementById('cartCount');
  const cartTotalEl = document.getElementById('cartTotal');
  const checkoutBtn = document.getElementById('checkoutBtn');
  const closeBtn = document.getElementById('closeBtn');
  const searchEl = document.getElementById('search');
  const cartBtn = document.getElementById('cartBtn');
  const cartBadge = document.getElementById('cartBadge');
  const cartOverlay = document.getElementById('cartOverlay');
  const cartModal = document.getElementById('cartModal');
  const modalClose = document.getElementById('modalClose');

  const manageBtn = document.getElementById('manageBtn');
  const manageOverlay = document.getElementById('manageOverlay');
  const manageModal = document.getElementById('manageModal');
  const manageClose = document.getElementById('manageClose');
  const manageSubtitle = document.getElementById('manageSubtitle');
  const manageLoading = document.getElementById('manageLoading');
  const manageBody = document.getElementById('manageBody');
  const mBalance = document.getElementById('mBalance');
  const mWithdrawAmount = document.getElementById('mWithdrawAmount');
  const mWithdrawBtn = document.getElementById('mWithdrawBtn');
  const mDepositBtn = document.getElementById('mDepositBtn');
  const mRevToday = document.getElementById('mRevToday');
  const mRev7d = document.getElementById('mRev7d');
  const mRevTotal = document.getElementById('mRevTotal');
  const mTopItems = document.getElementById('mTopItems');
  const mPriceRows = document.getElementById('mPriceRows');
  const mRecent = document.getElementById('mRecent');

  const payOverlay = document.getElementById('payOverlay');
  const payModal = document.getElementById('payModal');
  const payClose = document.getElementById('payClose');
  const payCash = document.getElementById('payCash');
  const payBank = document.getElementById('payBank');

  const state = {
    open: false,
    storeId: null,
    storeLabel: 'Store',
    moneyType: 'cash',
    moneyTypes: ['cash'],
    categories: [],
    items: [],
    activeCategory: null,
    search: '',
    cart: new Map(), // name -> { name, label, price, quantity }
    busy: false,
    cartOpen: false,
    brand: null,
    stock: {}, // name(lower) -> cases
    payOpen: false,
    isOwner: false,
    manageOpen: false,
    manageBusy: false,
    manage: null, // management data from server
  };

  function fmtMoney(n) {
    const num = Number(n || 0);
    return `$${num.toLocaleString(undefined, { maximumFractionDigits: 0 })}`;
  }

  function fmtMoney2(n) {
    const num = Number(n || 0);
    return `$${num.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
  }

  function fmtTimeAgo(ms) {
    const t = Number(ms || 0);
    if (!t) return '';
    const diff = Date.now() - t;
    if (diff < 60 * 1000) return 'just now';
    const mins = Math.floor(diff / (60 * 1000));
    if (mins < 60) return `${mins}m ago`;
    const hours = Math.floor(mins / 60);
    if (hours < 24) return `${hours}h ago`;
    const days = Math.floor(hours / 24);
    return `${days}d ago`;
  }

  function resolveImageUrl(item) {
    const img = (item && (item.imageUrl || item.image)) ? String(item.imageUrl || item.image) : '';
    if (!img) return null;
    if (img.startsWith('nui://') || img.startsWith('http://') || img.startsWith('https://')) return img;
    // Default to qb-inventory images folder
    return `nui://pfm-inventory/html/images/${img}`;
  }

  function resolveLogoUrl(brand) {
    if (!brand || !brand.logo) return null;
    const logo = String(brand.logo || '').trim();
    if (!logo) return null;
    if (logo.startsWith('nui://') || logo.startsWith('http://') || logo.startsWith('https://')) return logo;
    // Default to this resource UI folder
    return `nui://${GetParentResourceName()}/ui/${logo}`;
  }

  function parseHexColor(hex) {
    const s = String(hex || '').trim();
    if (!s.startsWith('#')) return null;
    const h = s.slice(1);
    if (h.length === 3) {
      const r = parseInt(h[0] + h[0], 16);
      const g = parseInt(h[1] + h[1], 16);
      const b = parseInt(h[2] + h[2], 16);
      if ([r, g, b].some(n => Number.isNaN(n))) return null;
      return { r, g, b };
    }
    if (h.length === 6) {
      const r = parseInt(h.slice(0, 2), 16);
      const g = parseInt(h.slice(2, 4), 16);
      const b = parseInt(h.slice(4, 6), 16);
      if ([r, g, b].some(n => Number.isNaN(n))) return null;
      return { r, g, b };
    }
    return null;
  }

  function applyBrand(brand) {
    // Reset to defaults first
    app.style.removeProperty('--brand');
    app.style.removeProperty('--brandSoft');
    app.style.removeProperty('--brandBorder');
    app.style.removeProperty('--productImgScale');
    app.style.removeProperty('--productImgOffsetY');

    const color = brand && brand.color ? String(brand.color).trim() : '';
    if (color) {
      if (color.startsWith('rgb(') || color.startsWith('rgba(')) {
        // Can't safely derive variants from arbitrary rgba; use a conservative default tint.
        app.style.setProperty('--brand', color);
        app.style.setProperty('--brandSoft', color);
        app.style.setProperty('--brandBorder', 'rgba(255,255,255,0.20)');
      } else {
        const rgb = parseHexColor(color);
        if (rgb) {
          const { r, g, b } = rgb;
          app.style.setProperty('--brand', `rgba(${r}, ${g}, ${b}, 0.22)`);
          app.style.setProperty('--brandSoft', `rgba(${r}, ${g}, ${b}, 0.18)`);
          app.style.setProperty('--brandBorder', `rgba(${r}, ${g}, ${b}, 0.38)`);
        }
      }
    }

    const imgScale = brand && brand.productImageScale != null ? Number(brand.productImageScale) : null;
    if (imgScale && Number.isFinite(imgScale) && imgScale > 0.1 && imgScale < 4) {
      app.style.setProperty('--productImgScale', String(imgScale));
    }

    const offsetY = brand && brand.productImageOffsetY != null ? Number(brand.productImageOffsetY) : null;
    if (offsetY != null && Number.isFinite(offsetY) && Math.abs(offsetY) <= 200) {
      app.style.setProperty('--productImgOffsetY', `${offsetY}px`);
    }

    const logoUrl = resolveLogoUrl(brand);
    if (logoUrl) {
      storeLogoEl.hidden = false;
      storeLogoEl.src = logoUrl;
      storeLogoEl.alt = (state.storeLabel || 'Store') + ' logo';
      storeLogoEl.onerror = () => {
        storeLogoEl.hidden = true;
        storeLogoEl.removeAttribute('src');
      };
    } else {
      storeLogoEl.hidden = true;
      storeLogoEl.removeAttribute('src');
    }
  }

  function postNui(eventName, data) {
    return fetch(`https://${GetParentResourceName()}/${eventName}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data || {}),
    }).then(r => r.json()).catch(() => ({ ok: false }));
  }

  function setOpen(open) {
    state.open = !!open;
    app.dataset.open = state.open ? 'true' : 'false';
    app.setAttribute('aria-hidden', state.open ? 'false' : 'true');
    if (!state.open) {
      state.storeId = null;
      state.items = [];
      state.categories = [];
      state.activeCategory = null;
      state.search = '';
      state.cart.clear();
      state.busy = false;
      state.cartOpen = false;
      state.payOpen = false;
      state.brand = null;
      state.moneyTypes = ['cash'];
      state.isOwner = false;
      state.manage = null;
      state.manageBusy = false;
      searchEl.value = '';
      setCartOpen(false);
      setPayOpen(false);
      setManageOpen(false);
      applyBrand(null);
    }
    render();
  }

  function setCartOpen(open) {
    state.cartOpen = !!open;
    if (!state.open) state.cartOpen = false;

    cartOverlay.hidden = !state.cartOpen;
    cartModal.hidden = !state.cartOpen;
  }

  function setPayOpen(open) {
    state.payOpen = !!open;
    if (!state.open) state.payOpen = false;
    payOverlay.hidden = !state.payOpen;
    payModal.hidden = !state.payOpen;
  }

  function setManageOpen(open) {
    state.manageOpen = !!open;
    if (!state.open || !state.isOwner) state.manageOpen = false;
    manageOverlay.hidden = !state.manageOpen;
    manageModal.hidden = !state.manageOpen;
  }

  function setStore(payload) {
    state.storeId = payload.storeId;
    state.storeLabel = payload.label || 'Store';
    state.moneyType = payload.moneyType || 'cash';
    state.moneyTypes = Array.isArray(payload.moneyTypes) && payload.moneyTypes.length
      ? payload.moneyTypes
      : [state.moneyType];
    state.brand = payload.brand || null;
    state.isOwner = payload.isOwner === true;
    state.manage = null;
    state.manageBusy = false;
    state.categories = Array.isArray(payload.categories) ? payload.categories : [];
    state.stock = (payload && typeof payload.stock === 'object' && payload.stock) ? payload.stock : {};
    const rawItems = Array.isArray(payload.items) ? payload.items : [];
    state.items = rawItems.map((it) => {
      if (!it || typeof it !== 'object') return it;
      const name = (it.name != null) ? String(it.name) : '';
      const key = name.toLowerCase();
      const stock = (state.stock && Object.prototype.hasOwnProperty.call(state.stock, key))
        ? Number(state.stock[key])
        : null;
      return { ...it, stock: Number.isFinite(stock) ? Math.max(0, Math.floor(stock)) : null };
    });
    state.activeCategory = state.categories[0] || null;
    state.search = '';
    searchEl.value = '';
    state.cart.clear();
    state.busy = false;

    applyBrand(state.brand);
  }

  function getFilteredItems() {
    const cat = state.activeCategory;
    const q = state.search.trim().toLowerCase();
    return state.items.filter(it => {
      if (cat && it.category !== cat) return false;
      if (!q) return true;
      const hay = `${it.label || it.name || ''} ${it.category || ''}`.toLowerCase();
      return hay.includes(q);
    });
  }

  function cartTotals() {
    let count = 0;
    let total = 0;
    for (const entry of state.cart.values()) {
      count += entry.quantity;
      total += (Number(entry.price || 0) * Number(entry.quantity || 0));
    }
    return { count, total };
  }

  function ensureCartItem(item) {
    const name = item.name;
    if (!state.cart.has(name)) {
      state.cart.set(name, {
        name,
        label: item.label || name,
        price: Number(item.price || 0),
        quantity: 0,
      });
    }
    return state.cart.get(name);
  }

  function clamp(n, min, max) {
    const x = Number(n || 0);
    return Math.max(min, Math.min(max, x));
  }

  function addToCart(item, qty) {
    const entry = ensureCartItem(item);
    const maxCfg = Number(item.maxQuantity || 50);
    const stock = (item && Number.isFinite(Number(item.stock))) ? Math.floor(Number(item.stock)) : null;
    const maxQty = (stock != null) ? Math.max(0, Math.min(maxCfg, stock)) : maxCfg;
    if (maxQty <= 0) return;
    entry.quantity = clamp(entry.quantity + qty, 1, maxQty);
    renderCart();
  }

  function setCartQty(itemName, qty) {
    const entry = state.cart.get(itemName);
    if (!entry) return;
    if (qty <= 0) {
      state.cart.delete(itemName);
    } else {
      entry.quantity = qty;
    }
    renderCart();
  }

  function renderCategories() {
    categoriesEl.innerHTML = '';
    if (!state.categories.length) {
      const div = document.createElement('div');
      div.className = 'hint';
      div.textContent = 'No categories configured.';
      categoriesEl.appendChild(div);
      return;
    }

    for (const cat of state.categories) {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'tab';
      btn.dataset.active = (state.activeCategory === cat) ? 'true' : 'false';
      btn.textContent = cat;
      btn.addEventListener('click', () => {
        state.activeCategory = cat;
        render();
      });
      categoriesEl.appendChild(btn);
    }
  }

  function renderItems() {
    const list = getFilteredItems();
    itemsEl.innerHTML = '';

    if (state.activeCategory) {
      activeCategoryEl.textContent = state.activeCategory;
      categoryHintEl.textContent = `Browse ${state.activeCategory}.`;
    } else {
      activeCategoryEl.textContent = 'All Items';
      categoryHintEl.textContent = 'Select a category to browse.';
    }

    const hasItems = list.length > 0;
    emptyEl.hidden = hasItems;
    itemsEl.hidden = !hasItems;

    if (!hasItems) return;

    for (const item of list) {
      const card = document.createElement('div');
      card.className = 'itemCard';

      const media = document.createElement('div');
      media.className = 'itemMedia';

      const labelText = (item.label || item.name || '').trim();
      const initials = labelText
        .split(/\s+/)
        .filter(Boolean)
        .slice(0, 2)
        .map(s => s[0]?.toUpperCase() || '')
        .join('') || '•';

      const imgUrl = resolveImageUrl(item);
      if (imgUrl) {
        const img = document.createElement('img');
        img.className = 'itemImg';
        img.src = imgUrl;
        img.alt = item.label || item.name || 'Item';
        img.loading = 'lazy';
        img.onerror = () => {
          media.innerHTML = '';
          const fallback = document.createElement('div');
          fallback.className = 'itemThumb';
          fallback.textContent = initials;
          media.appendChild(fallback);
        };
        media.appendChild(img);
      } else {
        const fallback = document.createElement('div');
        fallback.className = 'itemThumb';
        fallback.textContent = initials;
        media.appendChild(fallback);
      }

      const textWrap = document.createElement('div');
      textWrap.className = 'itemText';

      const nameRow = document.createElement('div');
      nameRow.className = 'itemNameRow';

      const name = document.createElement('div');
      name.className = 'itemName';
      name.textContent = item.label || item.name;

      const stockCases = (item && Number.isFinite(Number(item.stock))) ? Math.floor(Number(item.stock)) : null;
      if (stockCases === 0) {
        const pill = document.createElement('div');
        pill.className = 'pill pillDanger';
        pill.textContent = 'Out of stock';
        nameRow.appendChild(name);
        nameRow.appendChild(pill);
      } else {
        nameRow.appendChild(name);
      }

      const meta = document.createElement('div');
      meta.className = 'itemMetaRow';

      const category = document.createElement('div');
      category.className = 'itemMeta';
      category.textContent = item.category || '';

      const stockEl = document.createElement('div');
      stockEl.className = 'itemStock';
      stockEl.textContent = (stockCases == null) ? '' : `Stock: ${stockCases}`;

      meta.appendChild(category);
      meta.appendChild(stockEl);

      textWrap.appendChild(nameRow);
      textWrap.appendChild(meta);

      const actions = document.createElement('div');
      actions.className = 'itemActions';

      const price = document.createElement('div');
      price.className = 'price';
      price.textContent = fmtMoney(item.price || 0);

      const qtyWrap = document.createElement('div');
      qtyWrap.className = 'qty';

      const minus = document.createElement('button');
      minus.type = 'button';
      minus.className = 'qtyBtn';
      minus.textContent = '-';

      const qtyVal = document.createElement('div');
      qtyVal.className = 'qtyVal';
      qtyVal.textContent = '1';

      const plus = document.createElement('button');
      plus.type = 'button';
      plus.className = 'qtyBtn';
      plus.textContent = '+';

      let qty = 1;
      const maxCfg = Number(item.maxQuantity || 50);
      const maxQty = (stockCases != null) ? Math.max(0, Math.min(maxCfg, stockCases)) : maxCfg;
      const updateQty = () => {
        qtyVal.textContent = String(qty);
      };

      minus.addEventListener('click', () => {
        qty = clamp(qty - 1, 1, maxQty);
        updateQty();
      });
      plus.addEventListener('click', () => {
        qty = clamp(qty + 1, 1, maxQty);
        updateQty();
      });

      qtyWrap.appendChild(minus);
      qtyWrap.appendChild(qtyVal);
      qtyWrap.appendChild(plus);

      const add = document.createElement('button');
      add.type = 'button';
      add.className = 'addBtn';
      add.textContent = 'Add';
      if (maxQty <= 0) {
        add.disabled = true;
        minus.disabled = true;
        plus.disabled = true;
      }
      add.addEventListener('click', () => addToCart(item, qty));

      const right = document.createElement('div');
      right.className = 'itemActionRight';
      right.appendChild(qtyWrap);
      right.appendChild(add);

      actions.appendChild(price);
      actions.appendChild(right);

      card.appendChild(media);
      card.appendChild(textWrap);
      card.appendChild(actions);
      itemsEl.appendChild(card);
    }
  }

  function renderCart() {
    cartItemsEl.innerHTML = '';

    const { count, total } = cartTotals();
    cartCountEl.textContent = `${count} item${count === 1 ? '' : 's'}`;
    cartTotalEl.textContent = fmtMoney(total);
    checkoutBtn.disabled = (count <= 0) || state.busy;

    if (count > 0) {
      cartBadge.hidden = false;
      cartBadge.textContent = String(count);
    } else {
      cartBadge.hidden = true;
      cartBadge.textContent = '0';
    }

    for (const entry of state.cart.values()) {
      const row = document.createElement('div');
      row.className = 'cartRow';

      const top = document.createElement('div');
      top.className = 'cartRowTop';

      const name = document.createElement('div');
      name.className = 'cartRowName';
      name.textContent = entry.label;

      const price = document.createElement('div');
      price.className = 'price';
      price.textContent = fmtMoney(Number(entry.price || 0) * Number(entry.quantity || 0));

      top.appendChild(name);
      top.appendChild(price);

      const sub = document.createElement('div');
      sub.className = 'cartRowSub';
      sub.textContent = `${fmtMoney(entry.price)} each`;

      const actions = document.createElement('div');
      actions.className = 'cartRowActions';

      const qtyWrap = document.createElement('div');
      qtyWrap.className = 'qty';

      const minus = document.createElement('button');
      minus.type = 'button';
      minus.className = 'qtyBtn';
      minus.textContent = '-';

      const qtyVal = document.createElement('div');
      qtyVal.className = 'qtyVal';
      qtyVal.textContent = String(entry.quantity);

      const plus = document.createElement('button');
      plus.type = 'button';
      plus.className = 'qtyBtn';
      plus.textContent = '+';

      minus.addEventListener('click', () => setCartQty(entry.name, entry.quantity - 1));
      plus.addEventListener('click', () => setCartQty(entry.name, entry.quantity + 1));

      qtyWrap.appendChild(minus);
      qtyWrap.appendChild(qtyVal);
      qtyWrap.appendChild(plus);

      const remove = document.createElement('button');
      remove.type = 'button';
      remove.className = 'removeBtn';
      remove.textContent = 'Remove';
      remove.addEventListener('click', () => setCartQty(entry.name, 0));

      actions.appendChild(qtyWrap);
      actions.appendChild(remove);

      row.appendChild(top);
      row.appendChild(sub);
      row.appendChild(actions);

      cartItemsEl.appendChild(row);
    }
  }

  function render() {
    storeNameEl.textContent = state.storeLabel || 'Store';
    const allowed = (state.moneyTypes || []).filter(x => x === 'cash' || x === 'bank');
    if (allowed.length > 1) {
      storeSubtitleEl.textContent = 'Storefront (Cash / Bank)';
    } else {
      storeSubtitleEl.textContent = state.moneyType === 'bank' ? 'Storefront (Bank)' : 'Storefront (Cash)';
    }
    manageBtn.hidden = !state.isOwner;
    renderCategories();
    renderItems();
    renderCart();
  }

  // --- Owner management view ---

  async function refreshManagement() {
    if (!state.isOwner || !state.storeId) return;

    manageLoading.textContent = 'Loading…';
    manageLoading.hidden = state.manage != null;
    manageBody.hidden = state.manage == null;

    const res = await postNui('getManagement', { storeId: state.storeId });
    if (!state.manageOpen) return;

    if (!res || !res.ok || !res.data) {
      manageLoading.hidden = false;
      manageLoading.textContent = 'Failed to load management data.';
      manageBody.hidden = true;
      return;
    }

    state.manage = res.data;
    manageLoading.hidden = true;
    manageBody.hidden = false;
    renderManage();
  }

  function renderManage() {
    const data = state.manage;
    if (!data) return;

    manageSubtitle.textContent = `${data.label || state.storeLabel} — balance, pricing & sales.`;
    mBalance.textContent = fmtMoney2(data.balance);

    const summary = data.ledgerSummary || {};
    mRevToday.textContent = fmtMoney2(summary.today && summary.today.revenue);
    mRev7d.textContent = fmtMoney2(summary.last7days && summary.last7days.revenue);
    mRevTotal.textContent = fmtMoney2(summary.totalSales && summary.totalSales.revenue);

    renderTopItems(Array.isArray(summary.topItems) ? summary.topItems : []);
    renderPriceRows(Array.isArray(data.catalog) ? data.catalog : []);
    renderRecent(Array.isArray(data.recent) ? data.recent : []);
  }

  function renderTopItems(topItems) {
    mTopItems.innerHTML = '';

    if (!topItems.length) {
      const div = document.createElement('div');
      div.className = 'hint';
      div.textContent = 'No sales yet.';
      mTopItems.appendChild(div);
      return;
    }

    const maxRevenue = Math.max(...topItems.map(t => Number(t.revenue || 0)), 1);

    for (const top of topItems) {
      const row = document.createElement('div');
      row.className = 'topItemRow';

      const head = document.createElement('div');
      head.className = 'topItemHead';

      const name = document.createElement('div');
      name.className = 'topItemName';
      name.textContent = top.label || top.item || '';

      const value = document.createElement('div');
      value.className = 'topItemValue';
      value.textContent = `${fmtMoney2(top.revenue)} (${Number(top.units || 0)} sold)`;

      head.appendChild(name);
      head.appendChild(value);

      const bar = document.createElement('div');
      bar.className = 'topItemBar';
      const fill = document.createElement('div');
      fill.className = 'topItemBarFill';
      const pct = Math.max(2, Math.round((Number(top.revenue || 0) / maxRevenue) * 100));
      fill.style.width = `${Math.min(100, pct)}%`;
      bar.appendChild(fill);

      row.appendChild(head);
      row.appendChild(bar);
      mTopItems.appendChild(row);
    }
  }

  function marginEl(effectivePrice, supplyCost) {
    const el = document.createElement('span');
    const cost = Number(supplyCost);
    if (!Number.isFinite(cost) || cost <= 0) {
      el.className = 'marginNone';
      el.textContent = '—';
      return el;
    }
    const margin = Number(effectivePrice || 0) - cost;
    el.className = margin >= 0 ? 'marginPos' : 'marginNeg';
    const pct = Math.round((margin / cost) * 100);
    el.textContent = `${margin >= 0 ? '+' : '-'}${fmtMoney2(Math.abs(margin))} (${pct}%)`;
    return el;
  }

  function renderPriceRows(catalog) {
    mPriceRows.innerHTML = '';

    if (!catalog.length) {
      const tr = document.createElement('tr');
      const td = document.createElement('td');
      td.colSpan = 6;
      td.className = 'hint';
      td.textContent = 'No storefront items configured.';
      tr.appendChild(td);
      mPriceRows.appendChild(tr);
      return;
    }

    for (const item of catalog) {
      const tr = document.createElement('tr');

      const tdName = document.createElement('td');
      const name = document.createElement('div');
      name.className = 'priceItemName';
      name.textContent = item.label || item.name || '';
      const cat = document.createElement('div');
      cat.className = 'priceItemCat';
      cat.textContent = item.category || '';
      tdName.appendChild(name);
      tdName.appendChild(cat);

      const tdStock = document.createElement('td');
      tdStock.textContent = String(Number(item.stockCases || 0));

      const tdDefault = document.createElement('td');
      tdDefault.textContent = fmtMoney2(item.defaultPrice);

      const tdPrice = document.createElement('td');
      const input = document.createElement('input');
      input.type = 'number';
      input.min = '0';
      input.step = '0.01';
      input.className = 'mInput priceInput';
      input.placeholder = 'Default';
      if (item.ownerPrice != null) {
        input.value = String(Number(item.ownerPrice));
      }
      tdPrice.appendChild(input);

      const tdMargin = document.createElement('td');
      const updateMargin = () => {
        tdMargin.innerHTML = '';
        const raw = input.value.trim();
        const parsed = Number(raw);
        const effective = (raw !== '' && Number.isFinite(parsed) && parsed > 0) ? parsed : Number(item.defaultPrice || 0);
        tdMargin.appendChild(marginEl(effective, item.supplyCost));
      };
      updateMargin();
      input.addEventListener('input', updateMargin);

      const tdSave = document.createElement('td');
      const save = document.createElement('button');
      save.type = 'button';
      save.className = 'saveBtn';
      save.textContent = 'Save';
      save.addEventListener('click', async () => {
        if (state.manageBusy) return;
        state.manageBusy = true;
        save.disabled = true;
        save.textContent = '…';

        const raw = input.value.trim();
        const parsed = Number(raw);
        const price = (raw !== '' && Number.isFinite(parsed) && parsed > 0) ? parsed : null;

        const res = await postNui('setPrice', {
          storeId: state.storeId,
          item: item.name,
          price,
        });

        state.manageBusy = false;
        save.disabled = false;

        if (res && res.ok) {
          save.textContent = 'Saved';
          setTimeout(() => { save.textContent = 'Save'; }, 1200);
          // Keep local state + storefront display in sync with the clamped server value.
          const applied = res.data && res.data.price != null ? Number(res.data.price) : null;
          item.ownerPrice = applied;
          item.price = applied != null ? applied : Number(item.defaultPrice || 0);
          input.value = applied != null ? String(applied) : '';
          const sfItem = state.items.find(it => it && String(it.name || '').toLowerCase() === item.name);
          if (sfItem) sfItem.price = item.price;
          updateMargin();
          renderItems();
        } else {
          save.textContent = 'Retry';
        }
      });
      tdSave.appendChild(save);

      tr.appendChild(tdName);
      tr.appendChild(tdStock);
      tr.appendChild(tdDefault);
      tr.appendChild(tdPrice);
      tr.appendChild(tdMargin);
      tr.appendChild(tdSave);
      mPriceRows.appendChild(tr);
    }
  }

  function renderRecent(recent) {
    mRecent.innerHTML = '';

    if (!recent.length) {
      const div = document.createElement('div');
      div.className = 'hint';
      div.textContent = 'No activity yet.';
      mRecent.appendChild(div);
      return;
    }

    for (const entry of recent) {
      const row = document.createElement('div');
      row.className = 'recentRow';

      const main = document.createElement('div');
      main.className = 'recentMain';

      const isWithdraw = entry.item === '__withdraw__';
      const isDeposit = entry.item === '__deposit__';

      const name = document.createElement('div');
      name.className = 'recentName';
      name.textContent = isWithdraw
        ? 'Withdrawal'
        : isDeposit
          ? 'Deposit'
          : `${entry.label || entry.item} x${Number(entry.amount || 0)}`;

      const sub = document.createElement('div');
      sub.className = 'recentSub';
      sub.textContent = (isWithdraw || isDeposit)
        ? fmtTimeAgo(entry.createdAt)
        : `${fmtMoney2(entry.unitPrice)} each · ${fmtTimeAgo(entry.createdAt)}`;

      main.appendChild(name);
      main.appendChild(sub);

      const total = document.createElement('div');
      const totalNum = Number(entry.total || 0);
      total.className = totalNum < 0 ? 'recentTotal recentTotalNeg' : 'recentTotal';
      total.textContent = totalNum < 0 ? `-${fmtMoney2(Math.abs(totalNum))}` : fmtMoney2(totalNum);

      row.appendChild(main);
      row.appendChild(total);
      mRecent.appendChild(row);
    }
  }

  async function doWithdraw() {
    return moveStoreMoney('withdraw');
  }

  async function doDeposit() {
    return moveStoreMoney('deposit');
  }

  // 'withdraw' moves store -> bank, 'deposit' moves bank -> store; the server validates both.
  async function moveStoreMoney(action) {
    if (state.manageBusy) return;

    const amount = Number(mWithdrawAmount.value);
    if (!Number.isFinite(amount) || amount <= 0) return;

    state.manageBusy = true;
    mWithdrawBtn.disabled = true;
    if (mDepositBtn) mDepositBtn.disabled = true;

    const res = await postNui(action, { storeId: state.storeId, amount });

    state.manageBusy = false;
    mWithdrawBtn.disabled = false;
    if (mDepositBtn) mDepositBtn.disabled = false;

    if (res && res.ok) {
      mWithdrawAmount.value = '';
      if (state.manage && res.data && res.data.balance != null) {
        state.manage.balance = Number(res.data.balance);
        mBalance.textContent = fmtMoney2(state.manage.balance);
      }
      refreshManagement();
    }
  }

  async function doCheckout() {
    if (state.busy) return;
    const { count } = cartTotals();
    if (count <= 0) return;

    state.busy = true;
    renderCart();

    const cart = [];
    for (const entry of state.cart.values()) {
      cart.push({ name: entry.name, quantity: entry.quantity });
    }

    const sendCheckout = async (moneyType) => {
      return postNui('checkout', {
        storeId: state.storeId,
        cart,
        moneyType,
      });
    };

    const allowed = (state.moneyTypes || []).filter(x => x === 'cash' || x === 'bank');
    const needsPick = allowed.length > 1;

    let res;
    if (needsPick) {
      // Pause busy state while user selects a payment method.
      state.busy = false;
      renderCart();

      const picked = await new Promise((resolve) => {
        const cleanup = () => {
          payCash.onclick = null;
          payBank.onclick = null;
          setPayOpen(false);
        };

        payCash.onclick = () => { cleanup(); resolve('cash'); };
        payBank.onclick = () => { cleanup(); resolve('bank'); };
        const cancel = () => { cleanup(); resolve(null); };
        payClose.onclick = cancel;
        payOverlay.onclick = cancel;

        setPayOpen(true);
      });

      if (!picked) {
        // Cancelled
        return;
      }

      state.busy = true;
      renderCart();
      res = await sendCheckout(picked);
    } else {
      res = await sendCheckout(state.moneyType || allowed[0] || 'cash');
    }

    state.busy = false;

    if (res && res.ok) {
      // Clear cart and keep UI open
      state.cart.clear();
      render();
    } else {
      // No local error UI; server sends QBCore notify
      renderCart();
    }
  }

  function doClose() {
    postNui('close', {});
  }

  closeBtn.addEventListener('click', doClose);
  checkoutBtn.addEventListener('click', doCheckout);

  cartBtn.addEventListener('click', () => {
    setCartOpen(!state.cartOpen);
  });

  modalClose.addEventListener('click', () => setCartOpen(false));
  cartOverlay.addEventListener('click', () => setCartOpen(false));

  payClose.addEventListener('click', () => setPayOpen(false));
  payOverlay.addEventListener('click', () => setPayOpen(false));

  manageBtn.addEventListener('click', () => {
    if (!state.isOwner) return;
    setCartOpen(false);
    setManageOpen(true);
    refreshManagement();
  });
  manageClose.addEventListener('click', () => setManageOpen(false));
  manageOverlay.addEventListener('click', () => setManageOpen(false));
  mWithdrawBtn.addEventListener('click', doWithdraw);
  if (mDepositBtn) mDepositBtn.addEventListener('click', doDeposit);
  mWithdrawAmount.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      doWithdraw();
    }
  });

  searchEl.addEventListener('input', () => {
    state.search = searchEl.value || '';
    renderItems();
  });

  window.addEventListener('message', (event) => {
    const msg = event.data;
    if (!msg || typeof msg !== 'object') return;

    if (msg.action === 'open') {
      setStore(msg.payload || {});
      setOpen(true);
      setCartOpen(false);
    }

    if (msg.action === 'close') {
      setOpen(false);
    }
  });

  document.addEventListener('keydown', (e) => {
    if (!state.open) return;
    if (e.key === 'Escape') {
      e.preventDefault();
      if (state.payOpen) {
        setPayOpen(false);
      } else if (state.manageOpen) {
        setManageOpen(false);
      } else if (state.cartOpen) {
        setCartOpen(false);
      } else {
        doClose();
      }
    }
  });

  // Initial hidden
  setOpen(false);
})();
