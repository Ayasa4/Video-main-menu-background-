VIDEO MAIN MENU BACKGROUND
==========================
Plays a video (with sound) behind the Garry's Mod main menu, with a video list, a volume control
and video size options.

PARTS
  loader/videomenu_loader.lua   Tiny loader. It has to be installed locally: the Workshop cannot
                                place files in lua/includes.
  videomenu_core                Addon 1 - the player (Workshop, or garrysmod/addons).
  videomenu_pack                Addon 2 - your videos. Several pack addons can be installed together.
  make_pack.bat / .ps1          Optional helper that prepares the videos for the pack (see below).

INSTALL
  1. Copy loader/videomenu_loader.lua to   garrysmod/lua/includes/
  2. Open garrysmod/lua/includes/init_menu.lua and add this line at the very END:
         include("videomenu_loader.lua")
  3. Install videomenu_core and videomenu_pack (Steam Workshop, or copy both folders into garrysmod/addons/).
  4. Start the game.
  A game update may overwrite init_menu.lua. If the video disappears, add the include line again.

UNINSTALL
  Remove the include line from init_menu.lua and delete videomenu_loader.lua.
  If the menu ever breaks: Steam > Garry's Mod > Properties > Installed Files > Verify integrity.

USING IT
  The bar at the bottom-left of the MAIN MENU page (it is hidden on the other menu pages and in game):
    VIDEOS (n)      open the list and click a video to play it
    SOUND / MUTED   click to mute or unmute; the slider sets the volume
    SETTINGS        Video size:  Fill (crop edges) / Fit (show all) / Stretch
                    Debug box:   on / off
  Your choices (video, volume, mute, size, debug) are remembered between sessions.
  Console commands:
    videomenu_list                      list the videos
    videomenu_play <number or name>     play a video (a part of the name is enough; Tab completes names)
    videomenu_reload                    rescan the videos and rebuild the menu overlay

ADDING VIDEOS
  Read videomenu_pack/data_static/videomenu_pack/README.txt. In short:
  - videos must be WebM (not MP4); file names must be ASCII; use the .txt extension for the Workshop;
  - display names go in "<video>.title.txt" files, or let make_pack.bat do everything:
    put your videos (any file names) in a folder named "source" next to make_pack.bat and run it.
  - do not install the same pack twice (e.g. in garrysmod/addons AND from the Workshop).

TROUBLESHOOTING
  - Open the console and look for lines that start with [VideoMenu]. They say what was found, where each
    name came from, and why files were skipped. "videomenu_list" prints the list and the skipped files.
  - A video shows up with a name like vm_1a2b3c4d: its .title.txt file is missing (run make_pack.bat again).
  - Turn on SETTINGS > Debug box for live status (file type, codec support, errors).
  - Nothing at all: make sure the include line is in init_menu.lua and addon 1 is installed and enabled.
