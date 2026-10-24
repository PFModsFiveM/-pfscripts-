import { writable } from 'svelte/store';

type notifyType = 'success' | 'error' | 'primary' | 'inform' | 'warning' | 'info';

type notifyItem = {
  id: number,
  message: string,
  type: notifyType,
};

const store = () => {
  const { subscribe, update } = writable<Array<notifyItem>>([]);
  let currentId = 0;
  let lastMessage = '';
  let lastType: notifyType = 'primary';
  let lastAt = 0;
  const dedupeWindowMs = 800;

  function normalizeType(input: string): notifyType {
    const low = String(input || '').toLowerCase();
    if (low === 'success' || low === 'error' || low === 'warning' || low === 'info' || low === 'primary' || low === 'inform') {
      return low as notifyType;
    }
    return 'primary';
  }

  const methods = {
    receiveMessage(data: any) {
      const now = Date.now();
      const id = ++currentId;
      const timeout = Math.max(1200, Number(data.length) || 3500);
      const message = String(data.message || data.text || '');
      const type = normalizeType(data.ntype || data.type);

      if (!message) {
        return;
      }

      if (message === lastMessage && type === lastType && (now - lastAt) <= dedupeWindowMs) {
        return;
      }

      lastMessage = message;
      lastType = type;
      lastAt = now;

      const item: notifyItem = {
        id,
        message,
        type,
      };

      update(state => [...state, item]);
      setTimeout(() => {
        update(state => state.filter(x => x.id !== id));
      }, timeout);
    },
  };

  return {
    subscribe,
    ...methods,
  };
};

export default store();
