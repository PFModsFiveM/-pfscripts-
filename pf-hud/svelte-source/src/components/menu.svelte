<script lang="ts">
  import { draggable } from '@neodrag/svelte';
  import { faSliders, faCircleNotch, faChartSimple } from '@fortawesome/free-solid-svg-icons'
  import Fa from 'svelte-fa'

  import MenuStore from '../stores/menuStore';

  import HudPanel from './menu/hudPanel.svelte';
  import StatusIconsPanel from './menu/statusIconsPanel.svelte';
  import ProgressPanel from './menu/progressPanel.svelte';

  let menuHandle;
  const screenWidth: number = screen.width;
  const screenHeight: number = screen.height;

  let tabArray: Array<{name: string, icon: any, content: any, adminOnly: boolean}> = [
    { name: "Hud Settings",  icon: faSliders,      content: HudPanel,       adminOnly: false },
    { name: "Progress Bar",  icon: faChartSimple,  content: ProgressPanel,  adminOnly: false },
    { name: "Status Icons",  icon: faCircleNotch,  content: StatusIconsPanel, adminOnly: true },
  ];
  let activeTab: {name: string, icon: any, content: any} = tabArray[0];

  function handleTabClick(index: number) {
    activeTab = tabArray[index];
  }
</script>

<section style="display: {$MenuStore.show ? 'flex' : 'none'};" class="pf-menu" use:draggable={{ handle: menuHandle, bounds: 'body', gpuAcceleration: false, defaultPosition: {x: screenWidth/5, y:screenHeight/5} }}>
  <header class="pf-menu-head" bind:this={menuHandle}>
    <div class="pf-brand">
      <img src="./logo.png" alt="PF" draggable="false" />
      <div>
        <p class="pf-title">PF HUD Control</p>
        <p class="pf-subtitle">Customize layout, icons, colors and progress bars</p>
      </div>
    </div>
    <div class="pf-drag-hint">Drag Window</div>
  </header>

  <nav class="pf-menu-nav">
    {#each tabArray as tab, i}
      {#if !tab.adminOnly || !$MenuStore.adminOnly || ($MenuStore.adminOnly && $MenuStore.isAdmin) }
        <button
          class="pf-nav-btn"
          class:active-tab={activeTab.name == tab.name}
          on:click={() => handleTabClick(i)}
        >
          <Fa icon={tab.icon} translateY={0.27}/>
          <span>{tab.name}</span>
        </button>
      {/if}
    {/each}
  </nav>

  <div class="pf-menu-body">
    {#each tabArray as tab}
      {#if !tab.adminOnly || !$MenuStore.adminOnly || ($MenuStore.adminOnly && $MenuStore.isAdmin) }
        <div style="display: {activeTab.name == tab.name ? 'flex' : 'none'};" class="pf-content-shell">
          <svelte:component this={tab.content}/>
        </div>
      {/if}
    {/each}
  </div>
</section>

<style>
  .pf-menu {
    width: min(1120px, 90vw);
    height: min(960px, 90vh);
    display: flex;
    flex-direction: column;
    border-radius: 12px;
    overflow: hidden;
    color: #eef7ff;
    border: 1px solid rgba(0, 217, 255, 0.28);
    background: linear-gradient(160deg, rgba(8, 14, 24, 0.95) 0%, rgba(16, 18, 26, 0.94) 100%);
    box-shadow: 0 14px 48px rgba(0, 0, 0, 0.45);
  }

  .pf-menu-head {
    height: 78px;
    user-select: none;
    cursor: grab;
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0 16px;
    border-bottom: 1px solid rgba(255, 255, 255, 0.1);
    background: linear-gradient(90deg, rgba(0, 217, 255, 0.17), rgba(0, 217, 255, 0.02));
  }

  .pf-menu-head:active {
    cursor: grabbing;
  }

  .pf-brand {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .pf-brand img {
    width: 48px;
    height: 48px;
    object-fit: contain;
    filter: drop-shadow(0 0 8px rgba(0, 217, 255, 0.35));
  }

  .pf-title {
    margin: 0;
    font-size: 19px;
    font-weight: 800;
    letter-spacing: 0.2px;
  }

  .pf-subtitle {
    margin: 0;
    opacity: 0.72;
    font-size: 12px;
  }

  .pf-drag-hint {
    font-size: 12px;
    letter-spacing: 0.7px;
    text-transform: uppercase;
    opacity: 0.7;
    border: 1px solid rgba(255, 255, 255, 0.18);
    border-radius: 999px;
    padding: 4px 10px;
  }

  .pf-menu-nav {
    display: flex;
    gap: 8px;
    padding: 10px 12px;
    border-bottom: 1px solid rgba(255, 255, 255, 0.1);
    background: rgba(9, 12, 18, 0.7);
  }

  .pf-nav-btn {
    border: 1px solid rgba(255, 255, 255, 0.14);
    background: rgba(255, 255, 255, 0.02);
    color: rgba(236, 248, 255, 0.85);
    border-radius: 8px;
    padding: 8px 12px;
    display: inline-flex;
    align-items: center;
    gap: 8px;
    font-weight: 600;
    cursor: pointer;
    transition: 150ms ease;
  }

  .pf-nav-btn:hover {
    border-color: rgba(0, 217, 255, 0.46);
    color: #ffffff;
  }

  .pf-nav-btn.active-tab {
    background: rgba(0, 217, 255, 0.15);
    border-color: rgba(0, 217, 255, 0.58);
    color: #ffffff;
  }

  .pf-menu-body {
    flex: 1;
    min-height: 0;
    padding: 10px;
    background: rgba(11, 14, 20, 0.74);
    display: flex;
    flex-direction: column;
  }

  .pf-content-shell {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    overflow-x: hidden;
    flex-direction: column;
    border: 1px solid rgba(255, 255, 255, 0.08);
    border-radius: 10px;
    padding: 8px 12px;
    background: rgba(17, 22, 30, 0.72);
  }

  .pf-content-shell::-webkit-scrollbar {
    width: 6px;
  }
  .pf-content-shell::-webkit-scrollbar-track {
    background: rgba(255,255,255,0.04);
    border-radius: 3px;
  }
  .pf-content-shell::-webkit-scrollbar-thumb {
    background: rgba(0,217,255,0.35);
    border-radius: 3px;
  }
</style>