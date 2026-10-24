import type { layoutIconKind, shapekind } from '../types/types';
import ColorEffectStore from '../stores/colorEffectStore';
import LayoutStore from '../stores/layoutStore';
import PlayerHudStore from '../stores/playerStatusHudStore';

export type stylePresetKind = 'classic' | 'compact' | 'minimal' | 'neon';

function setLayout(layout: layoutIconKind, iconBetweenSpacing: number, xAxisSpacing: number, yAxisSpacing: number) {
  LayoutStore.receiveUIUpdateMessage({
    layout,
    iconBetweenSpacing,
    xAxisSpacing,
    yAxisSpacing,
  });
}

function setShape(shape: shapekind) {
  PlayerHudStore.updateAllShapes(shape);
  ColorEffectStore.updateAllIconShapeEditableColor(shape);
}

function resetToBaseline() {
  PlayerHudStore.resetPlayerStatusIcons();
  ColorEffectStore.resetColorEffects();
  LayoutStore.resetLayout();
}

export function applyStylePreset(preset: stylePresetKind) {
  resetToBaseline();

  if (preset === 'classic') {
    setLayout('standard', 2, 0, 0);
    setShape('circle-ring');
    PlayerHudStore.updateAllWidth(50);
    PlayerHudStore.updateAllHeight(50);
    PlayerHudStore.updateAllRingSize(6);
    PlayerHudStore.updateAllIconScale(0.40);
    PlayerHudStore.updateAllDisplayOutline(true);
    return;
  }

  if (preset === 'compact') {
    setLayout('bottom-right-row', 1, 0, 0);
    setShape('circle-ring-whole');
    PlayerHudStore.updateAllWidth(42);
    PlayerHudStore.updateAllHeight(42);
    PlayerHudStore.updateAllRingSize(5);
    PlayerHudStore.updateAllIconScale(0.34);
    PlayerHudStore.updateAllDisplayOutline(true);
    return;
  }

  if (preset === 'minimal') {
    setLayout('center-bottom-row', 1, 0, 0);
    setShape('icon-percentage');
    PlayerHudStore.updateAllWidth(38);
    PlayerHudStore.updateAllHeight(38);
    PlayerHudStore.updateAllIconScale(0.30);
    PlayerHudStore.updateAllDisplayOutline(false);
    ColorEffectStore.updateAllDefaultEffectColorSetting('outlineDropShadowAmount', 0);
    ColorEffectStore.updateAllDefaultEffectColorSetting('iconDropShadowAmount', 0);
    ColorEffectStore.updateAllDefaultEffectColorSetting('progressDropShadowAmount', 0);
    return;
  }

  setLayout('right-bottom-column', 1, 0, 0);
  setShape('square-ring');
  PlayerHudStore.updateAllWidth(52);
  PlayerHudStore.updateAllHeight(52);
  PlayerHudStore.updateAllRingSize(10);
  PlayerHudStore.updateAllIconScale(0.42);
  PlayerHudStore.updateAllDisplayOutline(true);

  ColorEffectStore.updateAllDefaultEffectColorSetting('progressColor', '#00F5FF');
  ColorEffectStore.updateAllDefaultEffectColorSetting('iconColor', '#00F5FF');
  ColorEffectStore.updateAllDefaultEffectColorSetting('outlineColor', '#7A00FF');
  ColorEffectStore.updateAllDefaultEffectColorSetting('innerColor', '#14162A');

  ColorEffectStore.updateAllDefaultEffectColorSetting('progressContrast', 140);
  ColorEffectStore.updateAllDefaultEffectColorSetting('iconContrast', 140);
  ColorEffectStore.updateAllDefaultEffectColorSetting('outlineContrast', 140);

  ColorEffectStore.updateAllDefaultEffectColorSetting('progressDropShadowAmount', 8);
  ColorEffectStore.updateAllDefaultEffectColorSetting('iconDropShadowAmount', 6);
  ColorEffectStore.updateAllDefaultEffectColorSetting('outlineDropShadowAmount', 8);
}
