<script lang="ts">
  import { onDestroy } from 'svelte';
  import type { layoutIconKind } from '../types/types';
  import PlayerHudUIStore from '../stores/playerStatusHudStore';
  import LayoutStore from '../stores/layoutStore';
  import DebugStore from '../stores/debugStore';
  import IconsList from './icons-list.svelte';

  let layout: layoutIconKind = 'standard';
  const { show, designMode, dragEditMode } = PlayerHudUIStore;

  let groupDragging = false;
  let dragStartMouseX = 0;
  let dragStartMouseY = 0;
  let dragStartXSpacing = 0;
  let dragStartYSpacing = 0;

  $: layout = $LayoutStore.layout;

  function clamp(min: number, val: number, max: number) {
    return Math.max(min, Math.min(max, val));
  }

  function stopGroupDrag() {
    if (!groupDragging) return;
    groupDragging = false;
    window.removeEventListener('mousemove', handleGroupDragMove);
    window.removeEventListener('mouseup', stopGroupDrag);
  }

  function handleGroupDragMove(event: MouseEvent) {
    if (!groupDragging) return;
    const deltaX = (event.clientX - dragStartMouseX) * 0.25;
    // Negate deltaY: HUD is bottom-anchored (margin-bottom), so dragging DOWN
    // should decrease yAxisSpacing (move element toward bottom, not away from it)
    const deltaY = (event.clientY - dragStartMouseY) * 0.25;

    LayoutStore.update(state => {
      state.xAxisSpacing = clamp(-100, dragStartXSpacing + deltaX, 500);
      state.yAxisSpacing = clamp(-100, dragStartYSpacing - deltaY, 500);
      return state;
    });
  }

  function handleGroupMouseDown(event: MouseEvent) {
    if (event.button !== 0) return;
    if (!($designMode && $dragEditMode === 'group')) return;

    groupDragging = true;
    dragStartMouseX = event.clientX;
    dragStartMouseY = event.clientY;
    dragStartXSpacing = $LayoutStore.xAxisSpacing;
    dragStartYSpacing = $LayoutStore.yAxisSpacing;

    window.addEventListener('mousemove', handleGroupDragMove);
    window.addEventListener('mouseup', stopGroupDrag);
    event.preventDefault();
  }

  onDestroy(() => {
    stopGroupDrag();
  });
</script>

{#if $show || DebugStore}
  {#if layout == 'center-bottom-row'}
    <div class="absolute bottom-[0.3vw] w-100vw" on:mousedown={handleGroupMouseDown}>
      <div class="static flex flex-row mx-auto" style="width: max-content; cursor: {$designMode && $dragEditMode === 'group' ? 'grab' : 'default'};">
        <div
          class="flex flex-row"
          style="gap: {$LayoutStore.iconBetweenSpacing+'px'};
                 margin-bottom: {$LayoutStore.yAxisSpacing+'px'};
                 margin-left: {$LayoutStore.xAxisSpacing+'px'};"
        >
          <IconsList />
        </div>
      </div>
    </div>
  {:else if layout == 'bottom-right-row'}
    <div
      class="absolute bottom-[0.3vw] right-[0.3vw] flex flex-row"
      on:mousedown={handleGroupMouseDown}
      style="gap: {$LayoutStore.iconBetweenSpacing+'px'};
             margin-bottom: {$LayoutStore.yAxisSpacing+'px'};
             margin-left: {$LayoutStore.xAxisSpacing+'px'};
             cursor: {$designMode && $dragEditMode === 'group' ? 'grab' : 'default'};"
    >
      <IconsList />
    </div>
  {:else if layout == 'left-bottom-column'}
    <div class="absolute bottom-[0.3vw] left-[1vh]" on:mousedown={handleGroupMouseDown}>
      <div
        class="static flex flex-col"
        style="gap: {$LayoutStore.iconBetweenSpacing+'px'};
               margin-bottom: {$LayoutStore.yAxisSpacing+'px'};
               margin-left: {$LayoutStore.xAxisSpacing+'px'};
               cursor: {$designMode && $dragEditMode === 'group' ? 'grab' : 'default'};"
      >
        <IconsList />
      </div>
    </div>
  {:else if layout == 'right-bottom-column'}
    <div class="absolute bottom-[0.3vw] right-[1vh]" on:mousedown={handleGroupMouseDown}>
      <div
        class="static flex flex-col"
        style="gap: {$LayoutStore.iconBetweenSpacing+'px'};
               margin-bottom: {$LayoutStore.yAxisSpacing+'px'};
               margin-left: {$LayoutStore.xAxisSpacing+'px'};
               cursor: {$designMode && $dragEditMode === 'group' ? 'grab' : 'default'};"
      >
        <IconsList />
      </div>
    </div>
  {:else if layout == 'top-left-row'}
    <div
      class="absolute top-[0.3vw] left-[0.3vw] flex flex-row"
      on:mousedown={handleGroupMouseDown}
      style="gap: {$LayoutStore.iconBetweenSpacing+'px'};
             margin-bottom: {$LayoutStore.yAxisSpacing+'px'};
             margin-left: {$LayoutStore.xAxisSpacing+'px'};
             cursor: {$designMode && $dragEditMode === 'group' ? 'grab' : 'default'};"
    >
      <IconsList />
    </div>
  {:else if layout == 'top-right-row'}
    <div
      class="absolute top-[0.3vw] right-[0.3vw] flex flex-row"
      on:mousedown={handleGroupMouseDown}
      style="gap: {$LayoutStore.iconBetweenSpacing+'px'};
             margin-bottom: {$LayoutStore.yAxisSpacing+'px'};
             margin-left: {$LayoutStore.xAxisSpacing+'px'};
             cursor: {$designMode && $dragEditMode === 'group' ? 'grab' : 'default'};"
    >
      <IconsList />
    </div>
  {:else if layout == 'standard'}
    <div
      class="absolute bottom-[0.3vw] left-[0.3vw] flex flex-row standard-layout"
      on:mousedown={handleGroupMouseDown}
      style="gap: {$LayoutStore.iconBetweenSpacing+'px'};
             margin-bottom: {$LayoutStore.yAxisSpacing+'px'};
             margin-left: {$LayoutStore.xAxisSpacing+'px'};
             cursor: {$designMode && $dragEditMode === 'group' ? 'grab' : 'default'};"
    >
      <IconsList />
    </div>
  {/if}
{/if}

<style>
  @media (width: 1280px) and (height: 720px) {
    .standard-layout {
      transform: scale(0.7) !important;
      left: -3vw !important;
      bottom: -1vh !important;
    }
  }
</style>
