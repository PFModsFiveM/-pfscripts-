<script lang="ts">
  import Button from '../atoms/button.svelte';
  import { saveUIDataToServer } from '../../utils/eventHandler';
  import PlayerHudStore from '../../stores/playerStatusHudStore';
  import ColorEffectStore from '../../stores/colorEffectStore';
  import LayoutStore from '../../stores/layoutStore';
  import MenuStore from '../../stores/menuStore';
  import Switch from '../atoms/switch.svelte';
  import ProfilePanel from './profilePanel.svelte';
  import UtilityFunctionPanel from './utilityFunctionPanel.svelte';
  import GlobalLayoutPanel from './globalLayoutPanel.svelte';
  import SingleStatusIconPanel from './singleStatusIconPanel.svelte';
  import GlobalStatusIconPanel from './globalStatusIconPanel.svelte';
  import LocaleStore from '../../stores/localeStore';

  let group: string = '';
  const { designMode, saveUIState, dragEditMode } = PlayerHudStore;

</script>

<div class="text-sm flex flex-col text-[#e8e8e8] select-none">
  <div class="my-3 text-2xl text-white flex flex-row">
    <div class="flex-1 flex flex-col justify-center min-w-min">
      <div>
        <div class="flex flex-row items-center">
          <p class="ml-3 p-0">{$LocaleStore.statusIcons.status_icons_settings}</p>
        </div>
      </div>
    </div>
    <div class="text-base">
      <p>{$LocaleStore.statusIcons.design_mode}</p>
      <Switch center bind:checked={$designMode}/>
    </div>
    <div class="text-base ml-6 min-w-[180px]">
      <p>{$LocaleStore.statusIcons.drag_position_mode}</p>
      <Switch
        checked={$dragEditMode === 'group'}
        checkedText={$LocaleStore.statusIcons.drag_mode_group}
        unCheckedText={$LocaleStore.statusIcons.drag_mode_individual}
        handleUpdateFunction={(checked) => { $dragEditMode = checked ? 'group' : 'individual'; }}
      />
    </div>
    <div class="flex flex-1 min-w-min justify-end">
      <Button name={$LocaleStore.statusIcons.reset_status_icons} buttonClass="mr-5 hover:bg-red-600"
        on:click={() => {
          PlayerHudStore.resetPlayerStatusIcons();
          ColorEffectStore.resetColorEffects();
          LayoutStore.resetLayout();
        }}/>
      {#if $MenuStore.adminOnly && $MenuStore.isAdmin}
        <Button name={$LocaleStore.statusIcons.save_changes_to_server} buttonClass={"my-auto"} disable={$saveUIState == "ready" ? false : true}
          on:click={() => { saveUIDataToServer(); $saveUIState = "updating" }}
        />
      {/if}
    </div>
  </div>
  <div class="px-3 pb-2 text-[13px] opacity-80">
    <p>
      {$dragEditMode === 'group' ? $LocaleStore.statusIcons.drag_mode_group_desc : $LocaleStore.statusIcons.drag_mode_individual_desc}
      {$LocaleStore.statusIcons.drag_help}
    </p>
  </div>
  
  <hr>
  <GlobalStatusIconPanel bind:group/>
  <SingleStatusIconPanel bind:group/>
  <GlobalLayoutPanel bind:group/>
  <UtilityFunctionPanel bind:group/>
  <ProfilePanel bind:group/>
</div>
