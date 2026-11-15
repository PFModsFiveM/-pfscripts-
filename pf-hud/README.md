
# PF HUD (WHIP look)

The HUD's look is ported from WHIP's (see `NOTICE.md`; LGPL-3.0, `COPYING.LESSER`):

* **Gauges**: a row of black discs in a white rim that drains (voice, health, armour, hunger, thirst; stress, oxygen,
  seatbelt and cruise control when they apply) under the minimap's frame. Styles: Black, Classic (discs that fill
  white in a capsule), Minimal. Money changes show in the gauges' capsule.
* **Minimap**: GTA's radar with WHIP's mask, a white frame drawn under GTA's HUD, the dark map and a blue route
  (the dark map needs **pfm-media-map** started; without it GTA's tiles stay).
* **Vehicle dial**: WHIP's 3D rev dial (three.js, 15 updates a second) at the bottom right, with fuel and nitrous
  gauges round it, flight instruments in aircraft and a power scale on boats. Each car's own dashboard look comes from
  pfm-media-map. Without WebGL, or by choice, a flat dial.
* **Settings**: `/hud` (key **I**). With pfm-ui started most settings are also in the pause menu (Settings, Server,
  HUD); otherwise they are kept in this resource's KVP. The theme's colours stay in `/hud`.
* **Layout editor**: from `/hud`: drag and scroll, or on a controller (pfm-ui): D-pad moves, LB/RB picks the
  element, LT/RT resizes, A saves, B cancels.
* **Radar tuner**: `/radartuner` (admin): every minimap component's position and size, the frame, live; Save keeps
  it for that player, Print writes the values to F8 for `client/radar.lua` / `client/skin.lua`.
* **Preview**: `html/preview.html` in a browser (not shipped to players): the HUD with sample data on foot, in a
  car, a plane and a boat.

# Things you should know:
* To open the menu in-game the **default key** is **"I"** or you can type **"/hud"**
* Your settings will **always** be **stored locally**, so even if you delete the resource it **will** keep your current settings. The **only** way you can wipe the local storage sucessfully is by clicking the **"Reset Settings"** button on the in-game menu
* The **Style** tab lets every player fully customize HUD colors, design preset, scale, and placement (player HUD, vehicle HUD, compass, and money)
* Style choices are persisted in-game through `pf-hud` KVP storage and are automatically re-applied when you reconnect
* If you want the new super snazzy sound effects for the menu, you'll need to download the latest update of [interact-sound](https://github.com/qbcore-framework/interact-sound) <br>
(comes with new open menu sound, close menu sound, click menu sound)
* If you receive ```attempt to index a nil value (global 'Lang')``` in your F8 console, the fastest way you can fix that issue is by downloading a new version via txAdminRecipe but if you are unable to do that because of the progress you’ve made on your existing build; you’ll have to unfortunately go through and download each one from the GitHub which I do not recommend. Save yourself a lot of time and pain by just downloading the recipe!

# FAQ
##
**Q:** Why do my borders not align with the maps?

**A:** Most of the time it generally means your safezone is not set to default in your GTA settings. (Settings/Display/"Restore Defaults")
##

##
**Q:** How do I enable dev mode?

**A:** Simple! All you have to do is type /admin and navigate through the menu to the last section called "Developer Options" and inside there you should see "Dev Mode", this will keep you invincible and add a cool developer icon in your circles/radials 
##

##
**Q:** What does the purple circle/radial do?

**A:** That is your harness indicator! When you have the item "harness" in your inventory and while in a vehicle it will appear. Also, when you use your item "harness", the circle/radial will reflect the amount of uses left and decrease overtime.
##

# Previews
### menu config (this is just a preview more options included than what is shown here)
![menu](https://user-images.githubusercontent.com/91661118/149598723-b34bb93d-8885-4b3a-a0cc-ab68d756a449.PNG)
### all radials
![all radials](https://user-images.githubusercontent.com/91661118/143668930-e9475c53-284c-4054-ad9c-88aa98f76768.png)
### dead health
![dead](https://user-images.githubusercontent.com/91661118/143668617-3f41913f-506e-4c40-bc97-99c0e02eaec6.png)
### engine health
![engine](https://user-images.githubusercontent.com/91661118/143668642-22269059-8220-4b78-8f24-3c3661b7e82f.png)
### altitude
![altitude](https://user-images.githubusercontent.com/91661118/143668687-89ae10b6-9acc-4d68-845d-97db67d3d6de.png)
### parachute
![parachute](https://user-images.githubusercontent.com/91661118/143668699-a9d50ee4-1168-401b-bf92-8ba80a696e6e.png)
### armed
![armed](https://user-images.githubusercontent.com/91661118/143668646-baac9848-56e5-436b-922a-b35e50ed335f.png)
### cinematic
![cinematic](https://user-images.githubusercontent.com/91661118/143668651-74e90ac0-11ad-447a-b27c-1542dd10edfd.png)
### cruise
![cruise](https://user-images.githubusercontent.com/91661118/143668654-1b843009-c791-4482-807d-352b75707d42.png)
### harness
![harness](https://user-images.githubusercontent.com/91661118/143668664-bd03289a-286f-4165-9447-25b16b5b0c8e.png)
### cash
![cash](https://user-images.githubusercontent.com/91661118/143668667-a8e2e856-94be-45c4-9751-39e71315b303.png)
### bank
![bank](https://user-images.githubusercontent.com/91661118/143668668-fed140e6-9043-4daa-8aba-36feac3f9b78.png)
### nitro
![nitro](https://user-images.githubusercontent.com/91661118/143668672-8a164eb0-aca5-4e00-a99f-56c64e4d5069.png)
### stamina
![stamina](https://user-images.githubusercontent.com/91661118/143668678-3327c0bf-7e3b-4fe5-b6e5-da6e4054a47a.png)
### oxygen
![oxygen](https://user-images.githubusercontent.com/91661118/143668693-d623822b-fc78-499a-baa3-a86e29504044.png)
### radio (outdated color)
![radio](https://user-images.githubusercontent.com/91661118/143668707-eb4bb5e7-5900-4dd8-b500-5fc745a7c146.png)
