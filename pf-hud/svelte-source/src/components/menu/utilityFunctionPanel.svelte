<script lang="ts">
  import Button from '../atoms/button.svelte';
  import Panel from '../atoms/panel.svelte';
  import { faScrewdriverWrench } from '@fortawesome/free-solid-svg-icons';
  import ColorEffectStore from '../../stores/colorEffectStore';
  import LocaleStore from '../../stores/localeStore';
  import { applyStylePreset } from '../../utils/stylePresets';

  export let group: string = "";
</script>


<Panel name={$LocaleStore.utilityFunctions.utility_functions} icon={faScrewdriverWrench} color={"white"} bind:group>
  <div class="flex flex-row mx-4">
    <Button name={$LocaleStore.utilityFunctions.copy_progress_colors} buttonClass={"h-15 w-55"}
      on:click={() => {ColorEffectStore.updateIconColorToProgressColor()}}
    />
  </div>
  <div class="mx-4 mt-3">
    <p class="text-base mb-2">{$LocaleStore.utilityFunctions.style_presets}</p>
    <div class="flex flex-row flex-wrap gap-2">
      <Button name={$LocaleStore.utilityFunctions.style_classic} buttonClass={"h-15 w-40"}
        on:click={() => applyStylePreset('classic')}
      />
      <Button name={$LocaleStore.utilityFunctions.style_compact} buttonClass={"h-15 w-40"}
        on:click={() => applyStylePreset('compact')}
      />
      <Button name={$LocaleStore.utilityFunctions.style_minimal} buttonClass={"h-15 w-40"}
        on:click={() => applyStylePreset('minimal')}
      />
      <Button name={$LocaleStore.utilityFunctions.style_neon} buttonClass={"h-15 w-40"}
        on:click={() => applyStylePreset('neon')}
      />
    </div>
  </div>
</Panel>
<hr>