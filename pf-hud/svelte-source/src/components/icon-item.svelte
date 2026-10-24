<script lang="ts">
  import { onDestroy } from 'svelte';
  import MetaShape from './meta-shape.svelte';
  import { fade } from 'svelte/transition';
  import type { colorEffect, optionalHudIconMetaShapeType } from '../types/types';
  import PlayerHudStore from '../stores/playerStatusHudStore';

  export let singleIconStore;
  export let designMode: boolean;
  export let designProgress: number;
  export let iconToNotShow: boolean;
  export let buffColorEffect: optionalHudIconMetaShapeType;
  export let currentEffect: colorEffect;

  const { dragEditMode } = PlayerHudStore;

  let dragging = false;
  let dragStartMouseX = 0;
  let dragStartMouseY = 0;
  let dragStartIconX = 0;
  let dragStartIconY = 0;

  function clamp(min: number, val: number, max: number) {
    return Math.max(min, Math.min(max, val));
  }

  function stopIconDrag() {
    if (!dragging) return;
    dragging = false;
    window.removeEventListener('mousemove', handleIconDragMove);
    window.removeEventListener('mouseup', stopIconDrag);
  }

  function handleIconDragMove(event: MouseEvent) {
    if (!dragging) return;
    const deltaX = (event.clientX - dragStartMouseX) * 0.08;
    const deltaY = (event.clientY - dragStartMouseY) * 0.08;

    singleIconStore.update(state => {
      state.translateX = clamp(-20, dragStartIconX + deltaX, 20);
      state.translateY = clamp(-20, dragStartIconY + deltaY, 20);
      return state;
    });
  }

  function handleIconMouseDown(event: MouseEvent) {
    if (event.button !== 0) return;
    if (!(designMode && $dragEditMode === 'individual')) return;

    dragging = true;
    dragStartMouseX = event.clientX;
    dragStartMouseY = event.clientY;
    dragStartIconX = $singleIconStore.translateX;
    dragStartIconY = $singleIconStore.translateY;

    window.addEventListener('mousemove', handleIconDragMove);
    window.addEventListener('mouseup', stopIconDrag);
    event.preventDefault();
  }

  onDestroy(() => {
    stopIconDrag();
  });
</script>

{#if ($singleIconStore.isShowing && iconToNotShow) || designMode}
  <div
    transition:fade|local="{{duration: 1000}}"
    class="my-auto"
    on:mousedown={handleIconMouseDown}
    style="cursor: {designMode && $dragEditMode === 'individual' ? 'grab' : 'default'};"
  >
    <MetaShape hudIconInfo={
      {
        ...$singleIconStore,
        progressColor: currentEffect.progressColor,
        progressContrast: currentEffect.progressContrast,
        progressDropShadowAmount: currentEffect.progressDropShadowAmount,
        progressValue: designMode ?
          designProgress : $singleIconStore.progressValue,
        iconColor: buffColorEffect ? buffColorEffect.iconColor : currentEffect.iconColor,
        iconContrast: currentEffect.iconContrast,
        iconDropShadowAmount: currentEffect.iconDropShadowAmount,
        outlineColor: currentEffect.outlineColor,
        outlineContrast: currentEffect.outlineContrast,
        outlineDropShadowAmount: currentEffect.outlineDropShadowAmount,
        innerColor: currentEffect.innerColor,
      }}
    />
  </div>
{/if}
