<script lang="ts">
  import Select from '../atoms/select.svelte';
  import ColorPicker from '../atoms/colorPicker.svelte';
  import MenuStore from '../../stores/menuStore';
  import { progressBarStyles } from '../../types/types';
  import LocaleStore from '../../stores/localeStore';

  function updateProgressStyle(styleName: any) {
    $MenuStore.progressBarStyle = styleName;
    MenuStore.sendMenuSettingsToClient();
  }

  function updatePrimaryColor(color: string) {
    $MenuStore.progressPrimaryColor = color;
    MenuStore.sendMenuSettingsToClient();
  }

  function updateSecondaryColor(color: string) {
    $MenuStore.progressSecondaryColor = color;
    MenuStore.sendMenuSettingsToClient();
  }
</script>

<div class="text-sm flex flex-col text-[#e8e8e8]">
  <div class="mx-4 mb-5 mt-3">
    <div class="mb-4 text-2xl text-white">
      <p>{$LocaleStore.utilityFunctions.progress_bars}</p>
    </div>

    <div class="mb-6">
      <p class="text-base font-semibold mb-2">{$LocaleStore.utilityFunctions.progress_style}</p>
      <div class="max-w-[320px]">
        <Select
          valuesArray={progressBarStyles}
          value={$MenuStore.progressBarStyle}
          labelArray={[
            $LocaleStore.utilityFunctions.progress_style_qb,
            $LocaleStore.utilityFunctions.progress_style_main,
            $LocaleStore.utilityFunctions.progress_style_ls,
            $LocaleStore.utilityFunctions.progress_style_image,
            $LocaleStore.utilityFunctions.progress_style_main2,
          ]}
          handleSelectFunction={updateProgressStyle}
        />
      </div>
      <p class="text-xs mt-2 opacity-60">Selecting a style will update the progress bar immediately in-game.</p>
    </div>

    <hr class="mb-6" />

    <div>
      <p class="text-base font-semibold mb-4">Colors</p>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-8 max-w-[540px]">
        <div>
          <p class="text-base mb-2">{$LocaleStore.utilityFunctions.progress_primary_color}</p>
          <ColorPicker colorString={$MenuStore.progressPrimaryColor} updateFunction={updatePrimaryColor} />
        </div>
        <div>
          <p class="text-base mb-2">{$LocaleStore.utilityFunctions.progress_secondary_color}</p>
          <ColorPicker colorString={$MenuStore.progressSecondaryColor} updateFunction={updateSecondaryColor} />
        </div>
      </div>
    </div>
  </div>
</div>
