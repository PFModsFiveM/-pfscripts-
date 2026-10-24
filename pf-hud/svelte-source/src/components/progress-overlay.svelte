<script lang="ts">
  import ProgressBarStore from '../stores/progressBarStore';

  const lsSegmentCount = 30;
  const bulletSegmentCount = 26;
  const chevronSegmentCount = 25;

  $: lsFilledSegments = Math.ceil(($ProgressBarStore.progress / 100) * lsSegmentCount);
  $: bulletFilledSegments = Math.ceil(($ProgressBarStore.progress / 100) * bulletSegmentCount);
  $: chevronFilledSegments = Math.ceil(($ProgressBarStore.progress / 100) * chevronSegmentCount);

  $: iconValue = ($ProgressBarStore.icon || '').trim();
  $: hasIcon = iconValue.length > 0;
  $: isFaIcon = hasIcon && iconValue.includes('fa-');
  $: isImageIcon = hasIcon && /^(https?:|nui:|data:|\.\/|\/)/i.test(iconValue);
  $: textIcon = hasIcon ? iconValue.slice(0, 1).toUpperCase() : '⏳';
</script>

{#if $ProgressBarStore.visible}
  <div class="pf-progress-wrap select-none">
    {#if $ProgressBarStore.style === 'progressbar-main'}
      <div class="pb1-container" style="--pf-primary: {$ProgressBarStore.primaryColor}; --pf-secondary: {$ProgressBarStore.secondaryColor}; --pf-progress: {$ProgressBarStore.progress};">
        <div class="pb1-ring">
          <div class="pb1-inner">
            {#if isFaIcon}
              <i class={`pb1-icon ${iconValue}`}></i>
            {:else if isImageIcon}
              <img src={iconValue} alt="icon" class="pb1-image" />
            {:else if hasIcon}
              <span class="pb1-fallback">{textIcon}</span>
            {:else}
              <i class="pb1-icon fa-solid fa-bars-progress"></i>
            {/if}
          </div>
        </div>
        <div class="pb1-label">{$ProgressBarStore.label}</div>
      </div>
    {:else if $ProgressBarStore.style === 'ls-progressbar'}
      <div class="ls-root" style="--pf-primary: {$ProgressBarStore.primaryColor}; --pf-secondary: {$ProgressBarStore.secondaryColor};">
        {#if hasIcon}
          <div class="ls-icon-box">
            {#if isFaIcon}
              <i class={`ls-icon ${iconValue}`}></i>
            {:else if isImageIcon}
              <img src={iconValue} alt="icon" class="ls-image" />
            {:else}
              <span class="ls-fallback">{textIcon}</span>
            {/if}
          </div>
        {/if}
        <div class="ls-main">
          <div class="ls-head">
            <span>{$ProgressBarStore.label}</span>
            <span>{Math.round($ProgressBarStore.progress)}%</span>
          </div>
          <div class="ls-track">
            {#each Array(lsSegmentCount) as _, index}
              <div class:active={index < lsFilledSegments}></div>
            {/each}
          </div>
        </div>
      </div>
    {:else if $ProgressBarStore.style === 'progressbar-main2'}
      <div class="pb2-root" style="--pf-primary: {$ProgressBarStore.primaryColor}; --pf-secondary: {$ProgressBarStore.secondaryColor};">
        <div class="pb2-head">
          <div class="pb2-label">{$ProgressBarStore.label}</div>
          <div class="pb2-percent">{Math.round($ProgressBarStore.progress)}%</div>
        </div>
        <div class="pb2-track">
          <div class="pb2-backline"></div>
          <div class="pb2-chevron-row">
            {#each Array(chevronSegmentCount) as _, index}
              <div class="pb2-chevron" class:active={index < chevronFilledSegments}></div>
            {/each}
          </div>
        </div>
      </div>
    {:else if $ProgressBarStore.style === 'image-bullets'}
      <div class="img-shell" style="--pf-primary: {$ProgressBarStore.primaryColor}; --pf-secondary: {$ProgressBarStore.secondaryColor};">
        <div class="img-head">
          <span>{$ProgressBarStore.label}</span>
          <span>{Math.round($ProgressBarStore.progress)}%</span>
        </div>
        <div class="img-track">
          {#each Array(bulletSegmentCount) as _, index}
            <span class:active={index < bulletFilledSegments}>➤</span>
          {/each}
        </div>
      </div>
    {:else}
      <div class="qb-shell" style="--pf-primary: {$ProgressBarStore.primaryColor}; --pf-secondary: {$ProgressBarStore.secondaryColor};">
        <div class="qb-head">
          <span>{$ProgressBarStore.label}</span>
          <span>{Math.round($ProgressBarStore.progress)}%</span>
        </div>
        <div class="qb-track">
          <div class="qb-fill" style="width: {$ProgressBarStore.progress}%;"></div>
        </div>
      </div>
    {/if}
  </div>
{/if}

<style>
  .pf-progress-wrap {
    position: fixed;
    left: 50%;
    bottom: 14vh;
    transform: translateX(-50%);
    z-index: 999;
    animation: slide-up 0.35s ease-out;
  }

  .qb-shell,
  .img-shell {
    width: 22vw;
    min-width: 360px;
    background: rgba(9, 12, 18, 0.9);
    border: 1px solid rgba(255, 255, 255, 0.15);
    border-radius: 8px;
    padding: 10px 12px;
    box-shadow: 0 0 22px rgba(0, 0, 0, 0.4);
  }

  .qb-head,
  .img-head {
    display: flex;
    justify-content: space-between;
    color: #f0f7ff;
    font-size: 14px;
    margin-bottom: 8px;
    font-weight: 700;
  }

  .qb-track {
    width: 100%;
    height: 10px;
    border-radius: 999px;
    background: rgba(23, 33, 46, 0.85);
    overflow: hidden;
  }

  .qb-fill {
    height: 100%;
    background: linear-gradient(90deg, var(--pf-primary), #96f7ff);
    transition: width 60ms linear;
  }

  .img-track {
    border: 1px solid rgba(255, 255, 255, 0.28);
    border-radius: 4px;
    padding: 4px 6px;
    display: grid;
    grid-template-columns: repeat(26, minmax(0, 1fr));
    gap: 2px;
    background: rgba(22, 28, 38, 0.88);
  }

  .img-track > span {
    color: rgba(92, 108, 128, 0.9);
    font-size: 11px;
    text-align: center;
  }

  .img-track > span.active {
    color: var(--pf-primary);
    text-shadow: 0 0 6px var(--pf-primary);
  }

  .pb1-container {
    display: flex;
    flex-direction: column;
    align-items: center;
    width: auto;
    transform: translateY(1vh);
  }

  .pb1-ring {
    width: 10vh;
    height: 10vh;
    min-width: 112px;
    min-height: 112px;
    border-radius: 50%;
    background:
      conic-gradient(var(--pf-primary) calc(var(--pf-progress) * 1%), rgba(0, 0, 0, 0.35) 0),
      radial-gradient(circle at center, rgba(0, 0, 0, 0.15), rgba(0, 0, 0, 0.35));
    display: grid;
    place-items: center;
    padding: 0.75vh;
    box-shadow: 0 0 14px rgba(0, 0, 0, 0.35);
  }

  .pb1-inner {
    width: 100%;
    height: 100%;
    border-radius: 50%;
    background: rgba(13, 17, 23, 0.9);
    display: grid;
    place-items: center;
  }

  .pb1-icon,
  .pb1-fallback {
    font-size: 2.8vh;
    color: var(--pf-primary);
    text-shadow: -1px -1px 1px rgba(0, 0, 0, 0.15), 1px 1px 1px rgba(0, 0, 0, 0.6);
    line-height: 1;
  }

  .pb1-image {
    width: 3.2vh;
    height: 3.2vh;
    min-width: 34px;
    min-height: 34px;
    object-fit: contain;
  }

  .pb1-label {
    margin-top: 0.8vh;
    color: #ffffff;
    text-align: center;
    font-weight: 700;
    font-size: 2vh;
    text-shadow: -1px -1px 1px rgba(0, 0, 0, 0.1), 1px 1px 1px rgba(0, 0, 0, 0.6);
    max-width: 32vh;
  }

  .ls-root {
    height: 8%;
    width: 15vw;
    min-width: 320px;
    display: flex;
    flex-direction: row;
    align-items: flex-end;
    gap: 0.7vw;
    margin-bottom: 0.8vh;
  }

  .ls-icon-box {
    width: 50px;
    height: 50px;
    background: rgba(36, 36, 36, 0.82);
    border-radius: 4px;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 6px;
    box-sizing: border-box;
  }

  .ls-icon,
  .ls-fallback {
    font-size: 28px;
    color: var(--pf-primary);
    text-shadow: 0 0 15px rgba(2, 132, 199, 0.8);
  }

  .ls-image {
    width: 28px;
    height: 28px;
    object-fit: contain;
  }

  .ls-main {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 0.6vh;
  }

  .ls-head {
    display: flex;
    justify-content: space-between;
    align-items: center;
    color: #ffffff;
    font-size: 1rem;
    line-height: 1;
  }

  .ls-track {
    width: 100%;
    height: 1rem;
    display: flex;
    gap: 0.2vw;
    background: transparent;
  }

  .ls-track > div {
    flex: 1;
    border-radius: 2px;
    background: rgba(36, 36, 36, 0.95);
    box-shadow: 0 0 6px 2px rgba(36, 36, 36, 0.45);
    transition: background-color 120ms linear, box-shadow 120ms linear;
  }

  .ls-track > div.active {
    background: var(--pf-primary);
    box-shadow: 0 0 6px 2px rgba(2, 132, 199, 0.55);
  }

  .pb2-root {
    color: #fff;
    width: 16.8vw;
    min-width: 320px;
    font-family: "Poppins", sans-serif;
  }

  .pb2-head {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 0.4vh;
  }

  .pb2-label {
    font-size: 1.3vh;
    line-height: 2.8vh;
    font-weight: 550;
    color: #ffffff;
  }

  .pb2-percent {
    font-size: 1.3vh;
    line-height: 2.8vh;
    font-weight: 400;
    color: #ffffff;
  }

  .pb2-track {
    width: 100%;
    height: 2.8vh;
    border-radius: 2px;
    border: 1px solid rgb(61, 63, 79);
    position: relative;
    overflow: hidden;
    background: transparent;
  }

  .pb2-backline {
    position: absolute;
    inset: 0;
    height: 1.8vh;
    top: 0.5vh;
    background: linear-gradient(to right, transparent, rgb(61, 63, 79) 40%, transparent);
  }

  .pb2-chevron-row {
    position: absolute;
    left: 5.5px;
    top: 0.96vh;
    width: calc(100% - 11px);
    display: flex;
    gap: 1.6px;
    overflow: hidden;
  }

  .pb2-chevron {
    flex: 1;
    height: 0.85vh;
    background-color: rgba(0, 0, 0, 0.45);
    clip-path: polygon(75% 0%, 100% 50%, 75% 100%, 0% 100%, 25% 50%, 0% 0%);
    transition: background-color 100ms linear;
  }

  .pb2-chevron.active {
    background-color: var(--pf-primary);
  }

  @keyframes slide-up {
    from {
      transform: translateX(-50%) translateY(12px);
      opacity: 0;
    }
    to {
      transform: translateX(-50%) translateY(0);
      opacity: 1;
    }
  }
</style>
