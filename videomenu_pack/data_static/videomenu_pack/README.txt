Put your videos in this folder. Every video appears in the VIDEOS list at the bottom-left of the main menu.

File rules (you can do this by hand, the script is optional)
1. File names must be ASCII (English letters, digits, _ and -) with no spaces.
   The game cannot read file names that contain Japanese, Thai, long dashes or spaces:
   such files will not show up in the list.
2. The file content must be WebM (VP8/VP9 video, Opus or Vorbis audio). MP4/H.264 is not supported.
3. For the Steam Workshop, rename .webm to .txt (the Workshop rejects .webm; the content is still WebM).
   When testing locally from garrysmod/addons you can keep .webm.
4. Files smaller than 200 KB are not treated as videos.
5. Name shown in the list: by default the file name (without extension).
   To show another name (Japanese, Thai, spaces are fine) create a small text file next to the video,
   with the same name plus ".title.txt", containing just the name (save it as UTF-8):
       mashu_kimi_iro.txt            <- the video
       mashu_kimi_iro.title.txt      <- contains:   [Fate] Mash Kyrielight
   Every video has its own title file, so addons never clash with each other.
   (Older alternative: a shared titles.txt with lines "file name | display name". Avoid it when several
   addons are installed: if two addons contain a file with the same name the game can only read one of
   them, so the names of the other addon's videos are lost.)

Automatic: make_pack.bat (next to videomenu_core / videomenu_pack)
  - Keep your original videos, with any file names, in a folder called "source".
  - Double-click make_pack.bat. It creates the ASCII file names and the .title.txt files in this folder.

Making your own pack addon that works next to other packs
- Use the same folder name: data_static/videomenu_pack/ . The list merges the videos of every installed addon.
- File names must not clash with another addon's files (if two addons contain a file with the same name,
  the game can only read one of them). make_pack uses names like vm_1a2b3c4d to avoid this.
- Do not install the same pack twice (for example once in garrysmod/addons and once from the Workshop).

The folder name "videomenu_pack" must match PackFolder in videomenu_core.
