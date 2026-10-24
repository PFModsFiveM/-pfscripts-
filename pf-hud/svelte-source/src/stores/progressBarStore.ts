import { writable } from 'svelte/store';
import type { progressBarStyleKind } from '../types/types';

type progressBarState = {
  visible: boolean,
  cancelled: boolean,
  label: string,
  icon: string,
  duration: number,
  progress: number,
  style: progressBarStyleKind,
  primaryColor: string,
  secondaryColor: string,
};

const defaultState: progressBarState = {
  visible: false,
  cancelled: false,
  label: '',
  icon: '',
  duration: 0,
  progress: 0,
  style: 'qb-default',
  primaryColor: '#00f5ffff',
  secondaryColor: '#1f293799',
};

const store = () => {
  const { subscribe, set, update } = writable(defaultState);
  let animationFrame = 0;
  let startedAt = 0;

  function stopAnimation() {
    if (animationFrame) {
      cancelAnimationFrame(animationFrame);
      animationFrame = 0;
    }
  }

  function animateProgress(duration: number) {
    stopAnimation();
    startedAt = Date.now();

    const step = () => {
      const elapsed = Date.now() - startedAt;
      const nextProgress = Math.min(100, (elapsed / duration) * 100);
      update(state => {
        state.progress = nextProgress;
        return state;
      });

      if (nextProgress < 100) {
        animationFrame = requestAnimationFrame(step);
      }
    };

    animationFrame = requestAnimationFrame(step);
  }

  const methods = {
    receiveMessage(data: any) {
      if (data.topic === 'settings') {
        update(state => {
          state.style = data.style || state.style;
          state.primaryColor = data.primaryColor || state.primaryColor;
          state.secondaryColor = data.secondaryColor || state.secondaryColor;
          return state;
        });
        return;
      }

      if (data.topic === 'start') {
        const duration = Math.max(250, Number(data.duration) || 2500);
        update(state => {
          state.visible = true;
          state.cancelled = false;
          state.label = data.label || 'Loading';
          state.icon = data.icon || '';
          state.duration = duration;
          state.progress = 0;
          state.style = data.style || state.style;
          state.primaryColor = data.primaryColor || state.primaryColor;
          state.secondaryColor = data.secondaryColor || state.secondaryColor;
          return state;
        });
        animateProgress(duration);
        return;
      }

      if (data.topic === 'cancel') {
        stopAnimation();
        update(state => {
          state.cancelled = true;
          state.visible = false;
          return state;
        });
        return;
      }

      if (data.topic === 'stop') {
        stopAnimation();
        update(state => {
          state.visible = false;
          state.cancelled = false;
          state.progress = 100;
          return state;
        });
      }
    },
    reset() {
      stopAnimation();
      set(defaultState);
    }
  };

  return {
    subscribe,
    set,
    update,
    ...methods,
  };
};

export default store();
