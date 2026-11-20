# Nonet User Guide

<!-- English version of user-guide.md. scripts/build-guide.py makes site/en/guide.html from this file. Keep it in step with user-guide.md, then rebuild both pages with python3 -I scripts/build-guide.py (scripts/tests/site_test.sh catches a page that wasn't rebuilt). Use the app's English labels (the "en" values in Localizable.xcstrings) and the terms in glossary.md -->

## About Nonet

Slide a finger down from the top edge, and Nonet turns your MacBook trackpad into nine buttons, a 3×3 grid that changes with each app. You use only the trackpad, no keys.

- Place a finger on the top edge of the trackpad and slide it down to open the nine buttons. Keep sliding to choose one, then lift your finger on it to run it
- The **direction of the pointer** from the center picks the button: the eight directions and the center match the 3×3 grid in Settings. While the buttons are open, the HUD, an overlay that shows all nine buttons, appears on the screen
- If you change your mind, move the pointer outside the ring of icons and lift your finger. Nothing runs
- The nine buttons follow the front app. Each profile can have up to three pages (27 buttons)

### Requirements

- macOS 14 Sonoma or later (Apple silicon or Intel)
- A multi-touch trackpad: a MacBook's built-in trackpad or a Magic Trackpad. Nonet doesn't work on a Mac with only a mouse
- AI actions also need macOS 26 or later and a Mac that supports Apple Intelligence

## Getting started

### Installing Nonet

1. Open the `Nonet-<version>.dmg` file you downloaded
2. Drag `Nonet` to the `Applications` folder
3. Open Nonet from the Applications folder

If you open Nonet from the disk image or from the folder you downloaded it to, it can't install updates from there, so Nonet asks "Move Nonet to the Applications folder?". Click **Move to Applications Folder**, and Nonet moves there and opens again. On an account that isn't an administrator, it moves to the Applications folder in your home folder. If the Applications folder already has a copy of Nonet, Nonet asks again before replacing it and moves the old copy to the Trash. If Nonet can't move itself to either folder, it explains how to move it in the Finder.

Nonet lives in the menu bar and doesn't appear in the Dock. Its menu bar icon is a ring of eight dots with a dot in the center. In this guide, the menu that opens when you click this icon is called the Nonet menu.

Only one copy of Nonet runs at a time. If you open Nonet again while it's running, the running copy opens its Settings window right away instead of a second copy starting. If you open it right after quitting, it waits for the old copy to finish quitting. When a copy opened from the disk image and the copy in the Applications folder meet, the one in the Applications folder runs, unless the disk image copy is a newer version. Then the disk image copy runs: if the copy in the Applications folder is running, Nonet quits it first, and then asks "Move Nonet to the Applications folder?". If the disk image copy isn't newer, it says "Nonet Is Already Running" and quits, and the running copy opens its Settings window.

### Accessibility permission

The first time you open Nonet, the Welcome to Nonet window (the welcome guide) opens. Click **Open System Settings**, and macOS asks for permission. From there, open **System Settings › Privacy & Security › Accessibility** and turn on Nonet (macOS asks for your password or Touch ID). If macOS doesn't ask, or when you click the button again, Nonet opens that section of System Settings. Once you allow Nonet, the welcome guide comes back in front of System Settings and moves on automatically.

**Why Nonet needs it**: macOS requires this permission for apps that work with the pointer and keyboard while you use other apps. Nonet uses it only to:

- Keep pointer movement and clicks from reaching the front app while the nine buttons are open
- Notice a key press while the nine buttons are open, so it can close them without running anything. While they're closed, Nonet doesn't look at the keyboard at all
- Send the keystrokes you set up, choose menu items and read selected text

**What Nonet doesn't collect**: Nonet never records or sends what you type. Your settings are stored only on your Mac (in `~/Library/Application Support/Nonet/`), and there's no account. Nonet uses the network only to check for updates and to open the purchase page. Reading finger positions on the trackpad needs no permission. For details, see the [privacy policy](privacy.md).

You can click **Not Now** to continue without it, but Nonet doesn't work until you allow it (the Accessibility step at the top of the welcome guide gets a "!"). If you slide down from the top edge before allowing it, the nine buttons don't open, and "Accessibility permission required" appears at the bottom of the screen with where to turn it on (you feel two light taps). If you finish without allowing it, the next time Nonet opens it shows "One more step to start using Nonet". Choose **Don't show again** to stop it. To allow it later, choose **Allow Accessibility Access…** from the Nonet menu (it opens this same step), or click **Open System Settings** in the banner at the top of the Settings window. If Nonet can't find a trackpad, this step says so too, and **Check Again** looks for it again.

The first time you use a File action, or a script uses the URL of the page shown in a browser (`NONET_BROWSER_URL`), macOS asks for Automation permission (see [macOS asks for Automation permission](#macos-asks-for-automation-permission) under Troubleshooting).

### Welcome guide

The Welcome to Nonet window has two steps, shown at the top.

1. **Accessibility**: the permission described above
2. **Try It Out**: two tasks in practice mode. The trackpad drawing shows the names of the buttons the HUD will show. The first task is **Open and lift on a button**: place a finger on the top edge of the trackpad and slide it down, and when the HUD opens, slide to the button named in the task and lift your finger there (if you lift on another button, the task tells you where the named one is). The second is **Cancel outside the ring**: open the HUD from the top edge again, then move the pointer outside the ring of icons and lift your finger. When both are done, a short tip says that holding just below the ring opens Utilities in front of any app, and holding to the right or left changes pages. Nothing runs in practice mode. Practice works only while the welcome guide window is in use; if you click another app, the buttons run for real. Click **Skip** to move on. If you can't practice yet, the step says why and offers a fix: **Enable Nonet** if Nonet is disabled, **Check Again** if there's no trackpad, **Open Settings** if the page in use has no buttons, or **Enter License Key…** if your trial has ended (once you register a key, the notice goes away)

At the bottom of the practice step are the **Open Nonet automatically when you log in** checkbox, **Back**, **Open Settings** and, once both tasks are done, **Done** (otherwise **Skip**). The checkbox is checked the first time you open Nonet. When you see the guide again, it starts from your current setting (**Open at login** in Settings). Nonet applies your choice when the guide closes from the practice step (with **Done**, **Skip**, **Open Settings** or the window's close button). If macOS needs your approval, System Settings opens at Login Items, the practice step says "To open Nonet at login, allow it in System Settings under Login Items.", and the guide stays open (click the button again to close it). If you can't see the Nonet icon in the menu bar, the practice step says "If you can't see the icon in the menu bar, open Nonet from the Applications folder to open Settings."

When you close the guide with **Done**, **Skip** or the window's close button, the Nonet icon in the menu bar flashes, and "Nonet lives here" appears under it. Click **Open Settings** to go straight to the Settings window.

Your settings start with a profile for every app on your Mac that has a preset, a ready-made set of nine buttons (Finder, Safari, Chrome, Arc, Mail, Outlook, Zoom, Teams, Slack, Excel, Word, PowerPoint, Keynote, Pages, Numbers, Notion, Notes, Obsidian, Figma, Photoshop, Final Cut Pro, Xcode, Visual Studio Code, Cursor and Terminal). Delete the profiles you don't want on the Profiles tab of Settings. On a Mac that can't use Apple Intelligence, the presets leave out the AI buttons, and on a Mac without the `claude` command they leave out the Claude Code button. In place of the AI button, another button takes the center and a different button fills the slot it leaves, so the page still has nine. The Claude Code button's slot is left empty (no preset puts Claude Code in the center).

The Global profile also has a launcher of popular apps from your Mac (see [Global profile and launcher](#global-profile-and-launcher) under Basics).

To see the welcome guide again, choose **Show Welcome Guide** from the Nonet menu.

## Basics

### Opening the buttons

1. Place one finger on the top edge (the far edge) of the trackpad
2. Slide it straight down in one smooth move

The nine buttons open as the HUD: nine icons around the pointer, eight on a ring and one in the center, with no panel, frame or text. The trackpad gives a light tick. The pointer starts in the center and keeps moving as usual while the buttons are open. The icon you point at sits on a white disc, so keep sliding your finger to point at an icon and lift to run it. Right after they open, even with the pointer in the center, lifting cancels: the buttons close without running anything (even with **Open sensitivity** set to High, or after a quick slide). Slide toward an icon to start choosing. To choose the center icon, move out once and come back to the center.

- They open when a finger placed on the top edge (within about 9 mm of the far edge) moves down about 5 mm within 0.6 seconds of touching. It doesn't have to be straight down: a diagonal move opens them too, as long as it goes no more than 1.5 times as far sideways as down (distances are measured as a fraction of the trackpad's width and depth, so on a real trackpad, which is wider than it is deep, a move that leans a bit more sideways still opens them). A move that starts more than 0.6 seconds after you touch, or a move along the edge, counts as ordinary pointer movement
- Nonet waits about 0.04 seconds after it recognizes the slide, then opens the buttons. If a second finger touches in that time (the start of a two-finger scroll) or the finger lifts, they don't open
- The speed of your finger isn't checked (it opens if your finger moves about 5 mm down within 0.6 seconds of touching). If you place a finger within 9 mm of the far edge and move the pointer straight down, the buttons open even though you meant to move the pointer. When you move the pointer, start with your finger away from the far edge. If that happens often, set **Open sensitivity** in Settings to Low: the band narrows to about 6 mm and the buttons open only when you slide about 7 mm within 0.4 seconds. If sliding from the edge sometimes doesn't open them, choose High (a 13 mm band, about 4 mm within 1 second)
- They don't open if you touch with two or more fingers or your palm, if your finger slides in from below the edge, or while a mouse or trackpad button is held down (for example, when you click and start dragging)
- They don't open while a Nonet window, such as Settings or the welcome guide, is in front (except for practice in the welcome guide), because Settings uses the trackpad for things like dragging buttons. The first time after Nonet starts, a notice at the bottom of the screen says "The nine buttons don't open while a Nonet window is in front". Try it over another app
- The HUD appears on the display with the pointer. When there is no room for the ring at the edge of the screen, the ring is moved to where it fits and the pointer is moved to its center instead

### Choosing and running a button

1. Keep your finger down and slide it to point the pointer at an icon. That icon sits on a white disc, and each time you move to another icon, the trackpad gives a light tick
2. Stop on the icon you want, then lift your finger

The icon on the white disc runs, and the HUD closes.

- A button runs only if your finger stays on it for a moment (0.1 seconds) before you lift. That's short enough to slide to a button and lift right away. Lifting while still sliding, or on a button you were only passing over, runs nothing, so a finger that was only meant to move the pointer doesn't run a button
- Buttons are chosen by the **direction** of the pointer from the center. The eight directions (up, up-right, right, down-right, down, down-left, left, up-left) are the eight outer buttons of the 3×3 grid in Settings, and the center is the center button. Between two icons, the current one sticks a little, so a shaky finger on the border doesn't switch
- The HUD normally shows no text: only the icons, without the profile name or the keys a button presses (like ⌘B). Empty buttons are small dots. Text appears only for the name of the button you rest on, the name of the page you're about to switch to, trial notices, and "Practice" under the ring in practice mode
- Each icon is drawn in white on its own dark round plate, so it reads the same on light windows, dark windows and photos

### Canceling

Any of these closes the buttons without running anything. You feel two light taps when you lift outside the ring or on an empty button, or lift with two fingers. Closing with a key, or when the 20 seconds run out, gives no tap:

- **Lift outside the ring**: move the pointer outside the ring of icons (more than 134 pt from the center, just past the icons) and lift your finger. There is no visible line, but all the icons dim when you cross it. Any direction works
- **Press a key**: pressing any key (except media keys such as volume and brightness) while the buttons are open closes them right away. The key reaches the app as usual
- **Lift on an empty button**: nothing happens on a button with no action (a small dot)
- **Lift right after opening**: lifting before you move the pointer away from the center runs nothing (there are no border lines; between two icons, the current one stays)
- **Check a name**: if you're unsure what an icon does, keep pointing at it for a moment (about 0.6 seconds). Its name appears under the icon and goes away when you move. It doesn't appear when you lift quickly, as you will once you know the buttons

If the buttons stay open for 20 seconds, they close on their own.

### Buttons that need a longer hold

For buttons that do something you can't undo, such as sending or recording, turn on **Hold before running** in the inspector.

- These buttons have a small mark at the top right of their icon in the HUD
- Keep your finger on the icon for a moment (0.45 seconds), and a line goes all the way around it. When the line is complete, the icon sits on a white disc and the trackpad ticks once (VoiceOver says "Lift to run"). Lift after that to run it. Lifting before the outline is complete runs nothing

### The trackpad while the buttons are open

While the nine buttons are open, the pointer moves as usual (the front app sees it move), but clicks and scrolling don't reach the front app. If you keep a finger on the trackpad and use an external mouse, its clicks and movement are dropped too (the buttons close when you lift, and everything is back to normal). A mouse click, move or scroll that arrives while you aren't touching the trackpad closes the buttons without running anything, and the mouse action reaches the app as usual (this is a safety net for when Nonet misses a finger lifting). Lifting while two fingers are down runs nothing either. If the trackpad stops reporting your finger while the buttons are open (for example, a Magic Trackpad disconnects or its battery runs out, your Mac goes to sleep, or Nonet switches to another trackpad), the buttons close without running the highlighted one.

### Pages

While the nine buttons are open, **hold the pointer just outside the ring** to switch pages. Where you hold it decides where you go.

- **Right or left** (within 45° of horizontal; a diagonal is fine): the next or previous page of that profile
- **Down**: [Utilities](#utilities). The same page opens in front of any app, with or without a profile
- **Up**: the Global pages (Place on Screen and the launcher). Only when the front app has a profile

Up and down work as if the pages were stacked with the app's pages in the middle: the Global pages on top, then the app's pages, then Utilities. Holding the other way from Utilities or from the Global pages takes you back to the page you were on. In an app without a profile, the Global pages are in the middle.

1. Move the pointer just outside the ring of icons (about 134 to 210 pt from the center, a little beyond the icons) and hold it there. While you hold it, a white arrow appears at that edge with a line growing around it, and the name of the page you'll go to appears under the center icon (to the right or left, dots for the pages appear too)
2. After about 0.5 seconds, it switches. The trackpad gives two taps for a new page, and one stronger tap when you move up or down. Each hold moves only one step. To go on, move the pointer back toward the icons and hold it out again
3. Point back at an icon to choose it, then lift to run it

When it switches, the ring of icons is pushed in the direction you went and the next ring slides in (with Reduce Motion on in System Settings, they swap without moving). On the Global pages and Utilities, the circles under the icons turn slightly navy, and right after moving up or down, the profile name appears briefly under the center icon.

Holding toward a side with nothing to move to (left or right with only one page, up in an app without a profile and so on) shows no text; you get two light taps. Holding the pointer farther out (more than about 210 pt from the center) switches nothing. If you're unsure, move farther out. Lifting anywhere outside the ring still closes the buttons without running anything, even after a switch. Holding on the right at the last page goes to the first page, and holding on the left at the first page goes to the last page. It wraps around only within the app's pages or within the Global pages.

Each profile can have up to three pages. While two fingers are touching, no button is chosen (lifting with two fingers runs nothing).

### Global profile and launcher

If the front app has a profile, Nonet uses that app's buttons. In apps without a profile, Nonet uses the Global profile, which works in every app.

The Global profile's first page starts as the nine Place on Screen buttons (Top Left, Top Half, Top Right, Left Half, Maximize, Right Half, Bottom Left, Bottom Half and Bottom Right; see [Place on Screen](#place-on-screen)). After it comes a launcher with up to 9 apps on one page, named **Launcher**. Apps in your Dock come first, in Dock order, and popular apps on your Mac fill the rest. It's a handy stand-in for Launchpad, which macOS 26 no longer has. The last page, the nine Utilities buttons (capture and recording, emoji and symbols, Spotlight, mute, display sleep and screen lock; see [Utilities](#utilities)), isn't one of the pages to the left or right: you open it by holding below the ring. You can change them like any other profile.

If you delete the Place on Screen or Utilities page, you can add it again with **+** (Add page) in Settings. The same goes if you've used Nonet since an earlier version and your Global profile doesn't have these pages. If the Global profile has no Utilities page, the one you add becomes the page that opens below the ring (see [Pages and buttons](#pages-and-buttons)).

### Utilities

**Utilities** holds nine things you do the same way in every app. Open the nine buttons, then hold the pointer just outside the ring below it to open this page (see [Pages](#pages)). It opens the same way whether or not the front app has a profile. Each is a Keystrokes button that sends a macOS shortcut or a short Script button, so they need no new permission.

| | | |
|---|---|---|
| Capture Area (⇧⌘4) | Capture & Record (⇧⌘5) | Stop Recording (⌃⌘Esc) |
| Emoji & Symbols (⌃⌘Space) | Capture & Copy (⌃⇧⌘4) | Spotlight (⌘Space) |
| Mute / Unmute | Sleep Display | Lock Screen (⌃⌘Q) |

- **Capture Area**: select an area and save it as a file
- **Capture & Copy** (center): select an area and put the picture on the clipboard instead of in a file, ready to paste into a chat or a document
- **Capture & Record**: shows the macOS screenshot toolbar. Start window or full-screen captures and screen recordings from there
- **Stop Recording**: stops a screen recording (the same as the stop button in the menu bar)
- **Emoji & Symbols**: opens the emoji and symbols viewer where you're typing
- **Spotlight**: opens the Spotlight search field. Find apps and documents by name and open them
- **Mute / Unmute**: turns the sound off or back on (the script uses `set volume`). If the output device can't be muted, Nonet shows a failure
- **Sleep Display**: puts the display to sleep (the script uses `pmset displaysleepnow`). The Mac itself doesn't sleep
- **Lock Screen**: locks the screen right away. Pressing it by mistake means typing your password again, so it runs only after a longer hold (see [Buttons that need a longer hold](#buttons-that-need-a-longer-hold))

The capture, recording, emoji, Spotlight and lock keys are macOS-wide shortcuts. If you've changed or turned them off in **System Settings › Keyboard › Keyboard Shortcuts**, these buttons do nothing. Change the button's **Keys to send** to match.

Mission Control, App Exposé and switching desktops aren't on this page because three- and four-finger trackpad gestures already open them.

### Haptic feedback

When the nine buttons open, and each time your finger crosses into another button, the trackpad gives a light tick. It ticks once when a button runs or a button that needs a longer hold is ready, twice when the page changes, and once more strongly when you move up or down (to or back from Utilities or the Global pages). When the buttons close without running anything (a lift outside the ring or on an empty button, a lift with two fingers), when you hold toward a side with nothing to move to, and when they don't open because the trial has ended, Accessibility permission is missing or you're entering a password, it gives two light taps. You can turn it off with the **Haptic feedback** setting (you can feel it only on a Force Touch trackpad).

## Menu bar

Click the Nonet icon (the ring of dots) in the menu bar to open the Nonet menu.

| Item | What it does |
|---|---|
| Status (the top line) | While Nonet is running, it shows the profile used for the front app, like "Xcode profile" or "Global profile" ("Not used in this app" for an app where you chose **Turn Off in This App**). If something is wrong, it shows the problem, such as "Accessibility permission required", "Can't find a trackpad", "Unavailable while entering a password" or "Nonet is disabled". When the trial has ended it reads "Your trial has ended", and with 3 days or fewer left it reads, for example, "3 days left in your trial" |
| Allow Accessibility Access… | Appears only when Nonet doesn't have permission. Opens the permission step of the welcome guide |
| Dismiss Notice | Appears with a notice, for example when Nonet couldn't read its settings file |
| Stop “Build” | Appears just below the status line only while a background script, shortcut or AI button is running. Choose it to stop the button the same way the timeout does; "Stopped “Build”" appears at the bottom of the screen (it isn't counted as a failure, and Recent Runs marks it "■") |
| Cheat sheet | Shows the buttons the front app would open with, on the same plates as the HUD in a 3×3 grid (names below the plates; beside them on a short screen), starting from the first page. Use ‹ › to see the other pages. Utilities (the page you open by holding below the ring) comes last and has a down arrow in its title. Click a button to open it on the Profiles tab of Settings (it doesn't run; when the pointer is over a button, it gets an outline and a pencil). Option-click a button to run it in the front app, the same way as **Test This Button** in Settings (with VoiceOver, use the action **Run in Front App**). If Nonet is turned off for the front app, a short line such as "Nonet is off in Xcode" appears instead |
| Enable Nonet | Uncheck it, and sliding down from the top edge no longer opens the buttons |
| Settings… | Opens the Settings window on the General tab |
| Edit Buttons for Xcode… / Create Buttons for Pages… / Edit Global Buttons… | Opens the front app's buttons on the Profiles tab of Settings. If the app has no profile, Nonet creates one (from its preset, if there is one). For an app without a preset the new profile is empty, and until you add a button to it, the Global pages open in that app too. If you ran one of that profile's buttons in the last minute, that button is selected. When Nonet can't tell the front app, it opens the Global buttons |
| Turn Off in This App | Turns Nonet off in the front app (the item gets a checkmark). In that app, sliding down from the top edge doesn't open the nine buttons, and the trackpad works as usual. Choose it again to turn Nonet back on (see [Profile list](#profile-list) under Editing profiles) |
| Recent Runs | Lists up to 10 buttons you ran recently, newest first, like "✓ Xcode › Build". Ones that failed show "✗" and the first line of the reason, and ones you stopped show "■" (long lines are cut short). Choose one to open that button on the Profiles tab of Settings. For a failed one, the whole reason also appears in the result panel, where you can select and copy it |
| Show Welcome Guide | Opens the Welcome to Nonet window |
| User Guide | Opens this guide |
| 14 days left in your trial / Registered / Your trial has ended | Your license status. Choose **Registered** to open the Settings window on the Nonet tab. Nonet doesn't repeat what the status line already says |
| Buy Nonet… / Enter License Key… | Appear during the trial and after it ends. **Buy Nonet…** opens the purchase page, and **Enter License Key…** opens the Nonet tab of Settings |
| Check for Updates… | Checks for a new version. When an automatic check has already found one, this item changes to **Update Available…**; choose it to see the update |
| Quit Nonet | Quits Nonet (without asking) |

The icon also shows the status. It's dimmed while Nonet is disabled. When something needs your attention (no permission, no trackpad found, a password being entered, the trial has ended or has 3 days or fewer left, or a notice), the top-right dot turns into a "!", and the top line of the menu says why. When a new version is available, the top-right dot grows larger.

While the Settings window or the welcome guide is in front, you can also press ⌘? (**Nonet Help**) to open this guide. ⌘, brings the Settings window to the front (on the tab you were using if it's open, or on the General tab). ⌘Q asks "Quit Nonet?" first: after you quit, the HUD doesn't open until you open Nonet again (to close just the window, press ⌘W). Check **Don't ask again** to quit right away next time.

## Editing profiles

Choose **Edit Buttons for Xcode…** (with your front app's name instead of Xcode) from the Nonet menu to open the Profiles tab of the Settings window. It has three columns: the profile list, the buttons and the inspector.

### Profile list

- **Global** at the top (marked Default) holds the nine buttons used in apps without a profile. You can't delete it
- App profiles are listed below it, under **Apps**. Drag to reorder them. The profile the front app is using now is marked In Use
- Click **Add Profile…** and choose an installed app to create its profile. Apps with a preset start with their buttons filled in. For an app that isn't listed, click **Choose Another App…**
- Control-click (or right-click) a profile to see the three **When in Front** choices and **Duplicate for Another App…**, **Reset to Preset…** (only for apps with a preset), **Export This Profile…** and **Delete…**. You can also press Delete. Nonet asks before deleting (you can undo it with ⌘Z)
- **Clean Up Profiles…**: appears under the list (and when you Control-click a profile) once you have two or more app profiles. Select the profiles of apps you don't use and delete them all at once (with **Select All**, **Deselect All**, and **Select Missing Apps** when some apps aren't on this Mac). Nonet asks once and keeps one earlier version, and ⌘Z or **Undo** under the grid brings them all back to where they were
- **When in Front**: at the top right of the grid (or by Control-clicking the profile), choose what happens while the app is in front: **This Profile**, **Use Global** or **Turn Off Nonet in This App**. A profile set to **Use Global** is marked Global, and Nonet uses the Global buttons in that app (the profile's buttons are kept). An app set to **Turn Off Nonet in This App** is marked Off (the same mark appears next to the description above the grid; you can still edit its buttons). In that app, sliding down from the top edge doesn't open the nine buttons, and the trackpad and the keys work as usual. **Turn Off in This App** in the Nonet menu switches it too
- With 8 or more app profiles, a **Filter by name, button or keys** field appears above the list (press ⌘F to show it at any time; press Esc or click × (Clear Filter) to close it). It finds profile names, and the names, contents and keys of buttons in every profile (type keys with their modifiers, like `⌘B`). Results look like "Xcode › Build"
- **Enable Nonet** under the list is the same switch as in the General settings

### Pages and buttons

The middle column shows the nine buttons of the selected profile. They are laid out in a ring, like the HUD (the center and eight around it; the top-left button is at the top left), each icon on the same dark round plate as in the HUD with its name below (Global plates are slightly navy, as in the HUD). Empty buttons are thin rings. In a narrow window the names take one line, and in a narrower one only the icons show (hold the pointer over a button to see its name).

- Below the ring are dots for the pages (‹ ● ○ ›); the selected page's dot is filled. Click a dot or ‹ › (or press ⌘1–⌘3) to switch pages. Like left and right in the HUD, ‹ › wraps around from one end to the other. Hold the pointer over a dot to see the page's name
- Click **+** (Add page) next to the dots to add an empty page, or a page filled with the Place on Screen or Utilities buttons (up to three pages). The **…** menu (Page Actions) has **Add Page**, **Rename…** and **Delete This Page…**. You can also Control-click a dot to rename or delete it. Nonet asks first if the page has buttons
- Above and below the ring are the names of the pages that open when you hold the pointer there in the HUD, like “↑ Global” and “↓ Utilities”. Click one to go to that page. In an app profile, up is the Global pages and down is Utilities; clicking one opens that page in the Global profile. In the Global profile, Utilities appears below, and while you edit Utilities, the page you go back to appears above. Nothing appears on a side with nowhere to go. For an app set to **Use Global** or **Turn Off Nonet in This App** while in front, and for an app with no buttons yet, the HUD doesn't use the app's pages, so nothing appears above or below (with no buttons yet, it says “Add a button and this page opens in front of …”)
- Utilities (the Global page you open by holding below the ring) is a single page and always below. You can change its buttons freely. It isn't one of the dots; open it with “↓ Utilities” below the ring. If you delete all the other Global pages, Utilities is used as an ordinary page
- Double-click a dot, or Control-click it and choose **Rename…**, to give the page a name such as "Debug" or "Git". The name appears in the title of the cheat sheet at the top of the Nonet menu, like "Buttons for Xcode · Debug", and in the HUD under the center icon as the place you'll go while you hold the pointer outside the ring. Leave it empty to go back to "Page 1" and so on
- Click a button to select it, and drag to swap buttons. Drag a button onto a page's dot to move it to an empty button on that page. The selected button is circled and lightly filled: in your accent color when keys (Delete, the arrow keys and so on) go to the nine buttons, and gray when they go somewhere else, such as the profile list or a text field
- Hold the pointer over a button to see its full name (even if it's cut off) and what it does (the keys it sends, the app it opens and so on)
- Use the arrow keys to move the selection, and press Delete to clear a button. For more keys, see "Power editing" below
- Control-click a button to choose **Duplicate**, **Delete** or **Test This Button**. The item acts on the button you Control-clicked and selects it first (after clearing, the notice names the button, as in “Cleared “Build”.”). On an empty button, choose an action type from **Add Action**. Copying, pasting and swapping with the next button are done with keys (see "Power editing" below)

### Undo and earlier versions

- Press ⌘Z to undo, and ⇧⌘Z to redo: changes to buttons (clearing, deleting, duplicating, creating, swapping, moving to another page, assigning a menu item, pasting), changes in the inspector (one step per button), adding or renaming a page, **Reset to Preset…**, **Duplicate for Another App…**, and deleting a profile or a page
- After you clear a button, replace a filled button, or delete a profile or a page, you can also click **Undo** under the grid. If you changed the button again since then, Nonet doesn't undo it and tells you so
- Replacing profiles by importing can't be undone with ⌘Z. Use a saved version instead (below)
- Nonet saves a copy of your settings while you change them (at most once an hour), and before deleting a profile or a page, importing, resetting to a preset or restoring an earlier version. It keeps the newest 10 in `~/Library/Application Support/Nonet/Backups/`. Under Export & Import on the Nonet tab of Settings, click **Restore an Earlier Version…**, choose a version, then click **Restore…** and **Restore** to go back to those profiles and settings. Your settings from before are saved too, so you can go back again

### Power editing

- **Profiles**: **Duplicate for Another App…** (Control-click the profile) creates a profile for another app with all the pages and buttons. Menu Item buttons that chose the original app's menus choose the new app's menus, which helps when you copy VS Code buttons to Cursor, for example. **Reset to Preset…** asks first, then replaces the buttons with the preset
- **Buttons**: ⌘C and ⌘V copy and paste a button. You can paste into another profile too, which is how you copy buttons between profiles
- **Keys on the grid**: ⌘D duplicates, ⌘⌫ clears, ⌥⌘ and an arrow key swap with the next button, and Return moves to the **Name** field
- **Keys on the Profiles tab**: ⌘1–⌘3 switch pages, and ⌘F filters profiles

### Inspector

The right column is where you set up the selected button. Changes are saved right away.

- **Empty button**: click an action type to create one
- **Name**: the name shown under the icon. If you leave it empty, Nonet names the button from its action
- **Icon**: click the icon to the left of the name (Change icon). Choose **Symbol** (SF Symbols, searched by their English names) or **App** (**Use This App's Icon**, available for buttons that open an app, Menu Item buttons and in app profiles). **Restore Default Icon** goes back to the default
- **Action type**: Keystrokes, Open, Place on Screen, Script, Shortcut, Menu Item, AI or File (see Action types)
- **Hold before running**: when on, the button runs only if you hold your finger on it in the HUD a little longer before lifting (see [Buttons that need a longer hold](#buttons-that-need-a-longer-hold) under Basics)
- **Test This Button**: runs the button now and shows "Ran successfully." or the error. Output from a script or a shortcut appears below it, where you can select and copy it. In an app profile, Nonet brings the app to the front, then runs the button. A Global button runs in the app you were using before you opened Settings. A button that sends input to the front app, such as Keystrokes, waits until that app is in front and the Settings window no longer has the keyboard. If the app doesn't come to the front in time, Nonet shows a message such as "Couldn't bring Xcode to the front." instead of sending the keys to the Settings window
- **Clear This Button**: removes the action and leaves an empty button

### Pick from Menus

You can assign an app's menu items without looking up keyboard shortcuts.

1. Make sure the app is running
2. Click **Pick from Menus** at the top right of the grid, then choose the app from the pop-up menu
3. Find the item with **Search menus**, then drag it onto a button. You can also double-click it, or Control-click it and choose **Put in Button**. Then it goes into the selected button if that button is empty or a Menu Item button (even one with no item chosen yet), and otherwise into an empty button

Putting an item in a filled button replaces what was there (press ⌘Z, or click **Undo** under the grid, to get it back). When you open the panel with **Pick from Menus** in the inspector's Menu Item editor, the button you're editing stays selected, so a double-clicked item goes into that button. To go back to the inspector, click the × at the top right of the panel (Back to the inspector).

## Action types

### Keystrokes

Sends keystrokes to the front app. Click the **Keys to send** field (**Record Shortcut**), then press the keys you want to send.

- A combination like `⌘B` or `⇧⌘4`
- A sequence like `⌘L → ⌘C`, up to four keystrokes, sent 40 milliseconds apart

While the field is recording (it shows **Type Shortcut…**):

- Press more keys to record a sequence. Return and Tab are recorded too
- Click **Done** or anywhere else to finish. Recording also finishes after four keystrokes
- Press Esc to stop recording without changing anything (**Cancel** does the same). To send the Esc key itself, click **Add Esc**
- To remove a wrong key, click ⌫ (Delete last key)

Some keys never reach the field because macOS uses them first, such as ⌘Tab, ⌘Space and the ⇧⌘4 screenshot shortcut. For those, type the keys in the field below the recorder (**Type keys as text**) and click **Apply**. Nonet reads symbols like `⇧⌘4` as well as words like `cmd+shift+4`. Separate the keystrokes of a sequence with `→` or `,`.

Shortcuts like `⌘[` work correctly on JIS keyboards too. If the current keyboard layout can't type a shortcut (such as `⌘[` on a German layout), Nonet clicks the front app's menu item with the same shortcut, if there is one.

Right before sending, Nonet checks that the front app is still the one that was in front when you opened the buttons. If it changed (for example, an app opened by the previous button came to the front), Nonet doesn't send the keys, so they can't reach the wrong app, and shows "The front app changed, so the keys weren't sent."

Screenshots are Keystrokes buttons too: the presets' **Capture Area** button simply sends ⇧⌘4. The Global profile's **Utilities** page gathers the capture and recording buttons (see [Utilities](#utilities)).

### Open (app or URL)

Opens an app or a URL. Under **What to open**, choose **App** or **URL**.

- **App**: opens the app, or brings it to the front if it's already running. Under **App to open**, click **Choose App…** and choose an installed app. For an app that isn't listed, click **Choose Another App…**. The app's name appears in the inspector and in the help tag when you hold the pointer over the button. Turn on **Hide if already in front** to hide the app when you run the button again, so you can switch to it and back
- **URL**: opens the **URL to open** in its default app. If you leave out `https://`, Nonet adds it (`http://` for addresses like `localhost`). App URLs like `obsidian://` work too. A path that starts with `/` or `~` opens as a file or folder

### Place on Screen

Puts the front app's window in a fixed part of the screen. Under **Where to place**, choose one of nine: Top Left, Top Half, Top Right, Left Half, Maximize, Right Half, Bottom Left, Bottom Half or Bottom Right. They divide the usable area of the screen (not counting the menu bar and the Dock) in a 3×3 grid: Top Half and Left Half are half of the usable area, and Maximize fills it.

- While this button is highlighted in the HUD, the target area is outlined in light blue on the screen with the note "Lift to place it here". Lift on the button, and the window moves there. Move outside the ring and the outline disappears
- It moves the frontmost window of the app that was in front when you opened the buttons (VoiceOver adds what will move, such as "Safari window", to the HUD's name)
- The window stays on its own display. Full-screen windows and windows with a fixed size (such as System Settings) can't be moved, and Nonet shows "This window couldn't be moved". An app with no window (for example, Finder with all its windows closed) shows "No window is in front"
- In a fresh setup, these nine buttons are the first page of the Global profile (see [Global profile and launcher](#global-profile-and-launcher)). In an app with its own profile, hold the pointer below the ring to reach these buttons; in an app without one, they are the first page. If you delete them, add them again with **+** (Add page) › **Place on Screen** in Settings

### Script

Runs the zsh script in the **Script to run (zsh)** field with `/bin/zsh -l -c`. Click **?** above the field to see the environment variables described below.

- **Run**
  - In Background: waits for the script to finish and stops it after the **Timeout** (60 seconds by default, 1–3600 seconds). If the script fails (a non-zero exit code), Nonet shows the last lines of standard error (or of standard output, if nothing was written to standard error). If it hasn't finished after 0.5 seconds, a "Running “…”…" notice stays at the bottom of the screen until it does. While it runs, you can stop it with **Stop “…”** in the Nonet menu
  - In Terminal: runs the script in a new Terminal window. Use it for interactive commands like `claude`. If iTerm2 is installed, you can switch to it with **Terminal app for scripts** on the General tab of Settings
- **Output** (In Background only): if the script writes anything to standard output, Nonet shows it, without the final newline, in the result panel (the same panel as an AI action's **Show Result**, where you can select and copy text). To keep it out of the panel, add `> /dev/null`. What the login shell's startup files (`~/.zprofile`, `~/.zlogin` and so on) print, such as ssh-agent's "Agent pid …", isn't included. Output that's empty, only spaces and line breaks, or not text shows nothing. If the output is longer than 64 KB, Nonet shows only the last 64 KB, under the line "(The output is long, so only the last 64 KB is shown.)", and the script still counts as successful
- **Working directory**: the project folder (see below), or your home folder if there isn't one
- **Environment**: background scripts run in a login shell (`zsh -l`) with the same `PATH` as Terminal, which Nonet reads (including `~/.zshrc`) when it opens. Aliases and functions from `~/.zshrc` work only with **In Terminal** (a script run in Terminal reads `~/.zshrc`). If you change `~/.zshrc`, quit Nonet and open it again

#### Environment variables passed to scripts

These describe the front app when the script runs. **Variables without a value aren't set.**

| Variable | Contents | Example |
|---|---|---|
| `NONET_APP_BUNDLE_ID` | Bundle ID of the front app | `com.apple.dt.Xcode` |
| `NONET_APP_NAME` | Name of the front app | `Xcode` |
| `NONET_DOCUMENT_PATH` | Document open in the front window (empty in apps that don't tell macOS where the document is, such as Visual Studio Code and Cursor) | `/Users/you/dev/App/App.xcodeproj` |
| `NONET_PROJECT_DIR` | Project folder that contains the document | `/Users/you/dev/App` |
| `PROJECT_DIR` | Same as `NONET_PROJECT_DIR` | `/Users/you/dev/App` |
| `NONET_BROWSER_URL` | URL of the current page in Safari, Google Chrome, Arc, Microsoft Edge or Brave | `https://example.com/article` |
| `NONET_SELECTED_TEXT` | Selected text | |

Nonet reads the selected text (`NONET_SELECTED_TEXT`) and the browser URL (`NONET_BROWSER_URL`) only when the script contains the variable's name, because reading them can mean sending ⌘C or asking the browser. A script that doesn't contain these names never sends ⌘C and never asks the browser, so no Automation prompt appears. In apps whose selection can't be read directly, Nonet copies it with ⌘C and then restores the clipboard. If your script only calls a script in another file, write the names of the variables it uses in your script, even in a comment (see the last example below). The other variables (`NONET_APP_BUNDLE_ID`, `NONET_APP_NAME`, `NONET_DOCUMENT_PATH`, `NONET_PROJECT_DIR` and `PROJECT_DIR`) are always set when they have a value.

Visual Studio Code and Cursor don't tell macOS where the open document is (their window title is just “Code”). In front of these apps, `NONET_DOCUMENT_PATH` and `PROJECT_DIR` are empty, so the preset's Claude Code button opens in your home folder. To open it in a project, replace `cd "${PROJECT_DIR:-$HOME}"` in the script with that folder.

Nonet finds the project folder like this:

- If the document is a `.xcodeproj`, `.xcworkspace` or `.playground`, or a `.swiftpm` inside a package, the folder that contains it. For a Swift Playgrounds `Name.swiftpm`, that folder itself
- For any other file, the nearest folder above it that contains `.git` or `Package.swift`. If there isn't one, the folder that contains the file
  - Inside your home folder, Nonet looks at every folder up to, but not including, your home folder, however deep the document is, so deep Maven, Gradle and Android projects work
  - Outside your home folder (for example `/Volumes/SSD`), Nonet looks at no more than 32 folders above the document, and never at `/` or a top-level folder such as `/Volumes`
  - For a document on a network volume, Nonet doesn't search and uses the folder that contains the document
  - If Nonet can't check the location within 0.3 seconds (for example, a sleeping NAS), there's no project folder, and the script runs in your home folder

Examples:

```zsh
# Open Claude Code in the project folder (Run: In Terminal)
cd "$PROJECT_DIR" && claude

# Open the project in VS Code
open -a "Visual Studio Code" "${PROJECT_DIR:-$HOME}"

# Copy the URL of the current page to the clipboard
printf '%s' "${NONET_BROWSER_URL:?No browser is in front}" | pbcopy

# Pass the selected text to a script in another file (Nonet reads it because this comment names NONET_SELECTED_TEXT)
~/bin/translate.sh
```

Always put variables in double quotes, like `"$NONET_SELECTED_TEXT"`, because they can contain spaces and symbols. If a variable might not be set, use `${VARIABLE:-default}` or `${VARIABLE:?message}`. The `:?` message appears on screen as the error.

### Shortcut

Runs a shortcut from the Shortcuts app. Type its name in **Shortcut to run**, or pick it from the list next to the field (Choose a shortcut). Turn on **Pass selected text as input** to pass the selected text to the shortcut.

If the shortcut returns text, Nonet shows it, without the final newline, in the result panel (rich text is shown as plain text, and long text is cut to the last 64 KB, as for scripts). If it returns something that isn't text, such as an image or a file, or returns nothing, nothing is shown, and neither counts as a failure.

### Menu Item

Chooses a menu item in an app. The easiest way to set it up is **Pick from Menus** (the button in the inspector's Menu Item editor opens the same panel, and a double-clicked item goes into the button you're editing). **Menu item to choose** shows where the item is, its app and its keys.

- If the app is in front and the item's keyboard shortcut matches that item's shortcut in the app's menus, Nonet sends the keys, which is fast. Otherwise (for example, if an app update changed the shortcut, or Nonet can't read the menus), Nonet opens the menus one by one and chooses the item. If the app is no longer in front right before Nonet sends the keys, Nonet also chooses the item from the menus instead
- If it has none (**None (Nonet opens the menus to choose it)**), Nonet opens the menus one by one with Accessibility and chooses the item
- Items whose name changes when you choose them, such as Play and Pause or Show Toolbar and Hide Toolbar, keep working after the first press. If Nonet can't find the name, it looks for the paired name, then for the only item in the same menu with the same keyboard shortcut
- The app must be running
- Menu names depend on the macOS language, so reassign the item if you change the language

### AI

Sends the selected text and the **Prompt** to the on-device language model (Apple Intelligence). The text never leaves your Mac.

- Requirements: macOS 26 or later, a Mac that supports Apple Intelligence, and Apple Intelligence turned on in **System Settings › Apple Intelligence & Siri** (with the model fully downloaded)
- **Output**:
  - Replace Selection: replaces the selected text with the result (Nonet pastes it with ⌘V through the clipboard, then restores the clipboard). If the front app changes while Nonet waits for the result, the result is copied to the clipboard instead. If the app didn't report a selection and Nonet read the text with ⌘C (pasting could insert the result at the cursor instead), or if Nonet can't restore what's on the clipboard (see "Nonet can't read the selected text" under Troubleshooting), Nonet shows the result in the result panel instead of pasting it
  - Copy to Clipboard
  - Show Result: shows the result in the result panel, where you can also select and copy text. Click **Copy** to copy the result, and **Close** or Esc to close the panel
- On a Mac that can't use AI actions, the inspector shows why, and so does the error when the button runs
- If it hasn't finished after 0.5 seconds, a "Running “…”…" notice stays at the bottom of the screen until it does
- When Nonet restores the clipboard, a copied image comes back in one image format, and files copied in the Finder come back as files without their icons

### File

Trashes, renames or duplicates the files selected in Finder. Click a file in Finder to select it, open the nine buttons, and choose this button to use it on that file right away.

- **Operation**:
  - Move to Trash: works like Finder's Move to Trash. It never deletes files for good, so you can put them back from the Trash. Files that are already in the Trash, and files on places without a Trash (such as network volumes), are left alone. When you choose it for a button, **Hold before running** turns on automatically (you can turn it off)
  - Rename: starts Finder's rename, as if you pressed Return. Type the new name and press Return. Works when exactly one file is selected
  - Duplicate: makes a copy in the same place. Large files take a while (Nonet waits up to 10 minutes for Finder). If it hasn't finished after 0.5 seconds, a "Running “…”…" notice stays at the bottom of the screen until it does
- **Target**: the files selected in Finder, while Finder is in front (desktop icons count too). Nonet checks which app is in front right before it runs, so if another app is in front it shows an error and does nothing, and never touches files that stay selected in a Finder window in the background. It does the same when nothing is selected. It doesn't touch symbolic links, because that would change what they point to. It does nothing if more than 500 files are selected or the selection includes your home folder, one of its standard folders (Desktop, Documents and so on), the top of a disk, a system folder or another user's home folder
- **Permission**: the first time you use it, macOS asks whether Nonet may control Finder (see [macOS asks for Automation permission](#macos-asks-for-automation-permission)). Nonet reads only the locations of the files selected in Finder, never what is inside them
- **Test This Button** in Settings asks first, because the Settings window can't show what is selected in Finder
- The second page of the Finder preset (“Selected Files”) has Duplicate, Rename and Move to Trash (Hold before running)

## Settings

Choose **Settings…** from the Nonet menu to open the General tab of the Settings window. Use the tabs at the top of the window to switch between Profiles, General and Nonet. The Profiles tab is described under [Editing profiles](#editing-profiles), and the license and About parts of the Nonet tab under [Trial and license](#trial-and-license) and [Updates and About](#updates-and-about). The General tab is grouped into these sections.

### Opening and HUD

| Setting | Default | What it does |
|---|---|---|
| Enable Nonet | On | When off, sliding down from the top edge of the trackpad doesn't open the nine icons (the HUD). You can also switch it in the Nonet menu and under the profile list |
| How to open and cancel | | Briefly shows how to open, run, cancel and change pages, with a drawing of the trackpad. **Learn more in the User Guide** opens this guide (see [Basics](#basics)) |
| Open sensitivity | Standard | Low, Standard or High. Changes the height of the top-edge band and how far and how soon you need to slide (see [Opening the buttons](#opening-the-buttons)). Choose Low if the buttons open during ordinary pointer moves, and High if sliding from the edge sometimes doesn't open them |
| Show larger | Off | Shows the HUD and the notices at the bottom of the screen at 1.25×. If it doesn't fit on the screen, Nonet makes it as large as fits |
| Haptic feedback | On | The trackpad gives a light tick when the buttons open, when you move to another icon and when a button runs (Force Touch trackpads only). Two taps when the page changes, one stronger tap when you move up or down, and two light taps mean they closed without running anything or there's nothing to move to |

Slow buttons (background scripts, shortcuts, AI and File buttons that duplicate) that haven't finished after 0.5 seconds show a notice like "Running “Translate”…" until they finish, and a notice at the bottom of the screen when they do. Except for File buttons that duplicate, the notice adds "You can stop it from the Nonet menu in the menu bar.", and **Stop “Translate”** in the Nonet menu stops it. When a button fails, Nonet shows which button of which profile it was ("Safari › Reload", plus "(page 2)" if the profile has more than one page) and why, for 3 to 8 seconds depending on the length. Information notices with a second line stay up the same way. If a failure notice is gone, choose the failed button in **Recent Runs** in the Nonet menu to read the whole reason in the result panel.

### Scripts

| Setting | Default | What it does |
|---|---|---|
| Terminal app for scripts | Terminal | Terminal / iTerm2. Scripts set to run In Terminal run in a new window of this app. It appears only when iTerm2 is installed. In iTerm2, a shell stays open in the window after the script ends, so you can read the output even if iTerm2 closes finished sessions. If you remove iTerm2 after choosing it, scripts run in Terminal |

### Startup

| Setting | Default | What it does |
|---|---|---|
| Open at login | Off | Opens Nonet when you log in to your Mac. The first time you open Nonet, the practice step of the welcome guide offers it with the box already checked (see [Welcome guide](#welcome-guide) under Getting started) |

### Export & Import

Under Export & Import on the Nonet tab, you can export profiles to a .nonetprofile file to back them up or to share them with another Mac or another person. Only profiles (the buttons and their actions) are exported. General settings and your license aren't included.

- **Export…**: exports all profiles to one file. To export one profile, Control-click it in the profile list and choose **Export This Profile…**
- **Import…**: adds the profiles in a file (files over 20 MB can't be imported). Double-clicking a `.nonetprofile` file in the Finder imports it the same way. In either of these cases, Nonet first asks "Import “file name”?":
  - Importing would replace something you have (the file contains a Global profile, or a profile for an app you already have a profile for). Nonet lists what would be replaced
  - The file has buttons that run something: Script, Keystrokes, Menu Item, AI and Shortcut buttons, File buttons that trash, rename or duplicate the files selected in Finder, URLs that open a file on your Mac, and URLs that start something else (running a shortcut, ssh, a shared folder and so on). Nonet asks even if nothing would be replaced. In a scrolling list, it shows each of these buttons as "Profile › Button" with everything it does, without cutting anything off: every line of the script, all the keys, the menu item and its keyboard shortcut, the AI prompt and output, the shortcut's name, the file operation, or the location the URL opens. Invisible characters are shown in a visible form, like "⟨U+202E⟩"
- **Restore an Earlier Version…**: goes back to settings saved before deleting, importing and similar changes (see "Undo and earlier versions" under Editing profiles)

In the list, buttons that press a key that works like Return (or a key with ⌃) and lines with commands that need care (curl, wget, base64, eval, `| sh` (also bash, zsh and others), osascript and rm -rf) are marked in orange with an explanation. If the file has buttons that run something, you can't click **Import**, **Replace and Import** or **Add New Profiles Only** until you scroll to the end of the list (Nonet shows "Scroll to the end to check everything before you can import.").

When Nonet asks, check the contents, then choose one of these:

- Replace and Import: shown when something would be replaced. Replaces the listed profiles with the contents of the file and adds any new app profiles. You can't undo this with ⌘Z, but your settings from before the import are kept in **Restore an Earlier Version…**
- Import: shown when nothing would be replaced. Adds the profiles in the file
- Add New Profiles Only: leaves your profiles as they are and adds only profiles for apps you don't have yet (shown only when the file both replaces some profiles and adds new ones)
- Cancel: changes nothing

In other cases, Nonet imports the file without asking. The result (how many profiles were added, replaced or skipped) appears in the banner at the top of the window. For Menu Item buttons, Nonet imports a keyboard shortcut only if it's a single keystroke. It drops longer ones, and Nonet chooses those items by opening the menus. Even a single keystroke is sent only if it matches the item's shortcut in the app's menus; otherwise Nonet chooses the item from the menus (see Menu Item under Action types).

**Import profiles from someone else only if you trust them.** Scripts and keystrokes run with your permissions. Check everything Nonet lists before you import. If the file contains scripts, the banner reminds you after importing.

## Trial and license

- You can use every feature free for **14 days** from the day you first open Nonet. The days left appear in the Nonet menu and on the Nonet tab of Settings
- With 3 days or fewer left, the icon gets a "!", and the top line of the Nonet menu shows the days left. The HUD also shows a line like "3 days left in your trial", once a day. You can buy or register at any time with **Buy Nonet…** and **Enter License Key…** in the Nonet menu
- When the trial ends, sliding down from the top edge no longer opens the nine buttons. Instead, "Your trial has ended" and "Buy Nonet or register a license key from its menu bar icon." appear at the bottom of the screen (you feel two light taps; when the menu bar icon is hidden, the second line reads "Open Nonet from the Applications folder, then buy Nonet or register a license key in Settings."). Your settings are kept. You can also buy or register from a small "Your Nonet trial has ended" window (at most once a day, with **Buy Nonet**, **Enter License Key…** and **Not Now**), and from the banner at the top of the Settings window (**Buy Nonet** and **Enter License Key…**)
- After you buy Nonet, your license key arrives by email (within 24 hours at the latest). One license covers every Mac you use. You can get a full refund within 30 days of purchase
- Keys for refunded licenses and keys that were made public stop working in later versions of Nonet. If your registered key stops working, the Nonet tab says why, and Nonet goes back to the trial if any trial time is left

The license section of the Nonet tab of Settings:

- **Status**: "14 days left in your trial (ends November 14)", "Registered" or "Your trial has ended". Once you register, it also shows who it's registered to, the issue date and the license ID
- **One-time purchase**: **Buy Nonet** opens the purchase page (shown only before you register)
- **Already Bought Nonet?**: paste the license key from your purchase email into the field and click **Register**. It takes effect right away. If you paste the text around the key too, like "License key:", Nonet reads only the key. Nonet checks the key on this Mac, so you don't need a network connection or an account. If Nonet can't register the key, it says why and what to do next (**Contact Support…** next to the message writes an email to us). If you can't find your key, click **Can't find your license key?**. If you click **Register in Nonet** in your purchase email or on the page after checkout, or open a `.nonetlicense` file, Nonet fills in the key and asks "Register this license key?" (it never registers a key without asking)
- **License Key**: once you register, click **Copy License Key** to copy your key and register it on your other Macs. **Register a Different Key…** lets you switch to another key
- **Remove License from This Mac**: click **Remove…** and Nonet asks first. **Copy Key and Remove** copies the key to the clipboard and then removes it from this Mac; **Remove** just removes it (with a copy, you can paste the key to register again later). Use this before you sell or give away this Mac. The same key keeps working on your other Macs

## Updates and About

Nonet checks for new versions automatically. When it finds one, the top-right dot of the menu bar icon grows larger, and the **Check for Updates…** item in the Nonet menu changes to **Update Available…**. Choose it to see the update. If Nonet finds an update right after it opens, or while the menu bar icon is hidden so you can't see the dot, it shows the update right away. To check at any time, choose **Check for Updates…** from the Nonet menu.

The Nonet tab of Settings, below the license section and Export & Import, shows the version and has **Check for Updates…**, **User Guide** (this guide), **Privacy Policy**, **Contact Support…** and **Uninstall Nonet…**, plus the licenses of the third-party software Nonet uses. When Nonet runs in English, the purchase page, the user guide and the privacy policy open in English. While a Settings or welcome window is in front, **About Nonet** in the main menu opens this section.

**Contact Support…** opens an email to us in your email app. It contains only the versions of Nonet and macOS, your Mac model and your keyboard type (never your license key or your settings). You decide whether to send it.

## Troubleshooting

When Nonet can't work, the top line of the Nonet menu and the banner at the top of the Settings window tell you why.

### “Accessibility permission required”

This also appears at the bottom of the screen when you slide down from the top edge without the permission; the nine buttons don't open (the same notice appears at most once every 30 seconds).

- Click **Open System Settings** in the banner at the top of the Settings window (the first click shows the macOS prompt; click again to open System Settings), or choose **Allow Accessibility Access…** from the Nonet menu
- Turn on Nonet in **System Settings › Privacy & Security › Accessibility**. Nonet starts working once you allow it
- If Nonet is on but still doesn't work (after an update, for example), select Nonet in the list, click − to remove it, then click + to add it again and turn it on (the banner in the Settings window and the permission step of the welcome guide say this too)

### “Nonet doesn't work while you enter a password”

While the cursor is in a password field, or while Secure Keyboard Entry is on in Terminal, macOS keeps keystrokes from other apps, so Nonet doesn't open the nine buttons (sliding down from the top edge shows "Doesn't open while you're entering a password" at the bottom of the screen, at most once every 30 seconds). Leave the password field, or turn off **Terminal › Secure Keyboard Entry**. Nonet starts working again on its own. To check right away, click **Check Again** in the banner.

### “Can't find a multi-touch trackpad”

Nonet needs a MacBook's built-in trackpad or a Magic Trackpad. It doesn't work with only a mouse. When you connect or reconnect a Magic Trackpad, Nonet finds it again on its own, which can take about 10 seconds. To check right away, click **Check Again** in the banner. If it still doesn't respond, choose **Quit Nonet** from the Nonet menu and open Nonet again.

### Nothing happens

- Make sure **Enable Nonet** is checked in the Nonet menu
- Make sure **Turn Off in This App** isn't checked for the front app (such apps are marked Off in the profile list)
- Make sure your trial hasn't ended (the Nonet menu shows "Your trial has ended")
- Check whether one of the three problems above (Accessibility, password entry or trackpad) is shown
- Make sure you place your finger on the top edge (the far edge) of the trackpad first, then slide it down in one smooth move. Starting below the edge, or starting to move more than 0.6 seconds after you touch, doesn't open the buttons. (With Open sensitivity set to High, Nonet accepts a start up to about 13 mm from the edge and up to 1 second.) Moving the pointer straight down right after touching near the far edge does open them, even at ordinary pointer speed (see [Opening the buttons](#opening-the-buttons) under Basics)
- While a Nonet window such as Settings is in front, sliding down from the top edge doesn't open the nine buttons, because Settings uses the trackpad for things like dragging buttons. Switch to the app you want to use first, or, to try a button in Settings, use **Test This Button** in the inspector. When you close the Settings window, the app you were using before comes back to the front

### The menu bar icon is missing

When the menu bar is crowded, the Nonet icon can be hidden. Open Nonet again from the Applications folder, and the Settings window opens right away. While the icon is hidden, notices that would point to the menu bar (such as the end of the trial) tell you to open Nonet from the Applications folder instead, and when an update is found, Nonet shows it right away instead of marking the icon.

### The buttons open when you didn't mean to

If you move the pointer by sliding a finger quickly down from the far edge of the trackpad, the nine buttons open. If that happens, just lift your finger: nothing runs, because right after they open, lifting always cancels until you move the pointer away from the center. If it happens often, start pointer moves a little away from the far edge, or set **Open sensitivity** on the General tab of Settings to Low (if you lift right after the buttons open three times within 10 minutes, a notice at the bottom of the screen suggests this once). For apps where you don't use Nonet, choose **Turn Off in This App** from the Nonet menu, and the buttons won't open there.

### The pointer doesn't move or clicks don't work

While the nine buttons are open, Nonet keeps clicks and scrolling from reaching the front app. If Nonet thinks they're still open, any of these gets things back to normal:

- Take all your fingers off the trackpad
- Press any key (this closes them right away)
- Move or click the mouse (the mouse action reaches the app as usual)
- Wait 20 seconds (long sessions end on their own)
- If none of these work, choose **Quit Nonet** from the Nonet menu

### The wrong button runs

Buttons are chosen by the **direction** of the pointer from the center. Check which icon sits on the white disc in the HUD before you lift. If the wrong one does, slide to the right one, or move outside the ring of icons and lift so nothing runs. For buttons that do something you can't undo, turn on **Hold before running** (see [Buttons that need a longer hold](#buttons-that-need-a-longer-hold) under Basics). **Recent Runs** in the Nonet menu shows what ran.

If a Keystrokes button says "The front app changed, so the keys weren't sent.", another app came to the front between opening the buttons and sending the keys (for example, an app opened by the previous button). Nonet sent nothing, so the keys didn't reach the wrong app. Bring the app you want to the front and run the button again. A Menu Item button chooses the item from the menus in this case instead of sending the keys.

### A script fails

- Read the error on screen (if the script wrote nothing to standard error, it shows the end of standard output). If the notice is already gone, choose the failed run ("✗") in **Recent Runs** in the Nonet menu to see the whole reason in the result panel. If the exit code is 127 (`command not found`), run `command -v <name>` in Terminal to check that the command is installed. Background scripts use the same `PATH` as Terminal. Nonet reads it when it opens, so if you change `~/.zshrc`, open Nonet again
- To test under similar conditions, run `zsh -lic '<script>'` in Terminal
- **Test This Button** in the inspector shows the result right away
- For long tasks, raise the **Timeout** or choose **In Terminal**. To stop one that keeps running, choose **Stop “…”** from the Nonet menu

### macOS asks for Automation permission

When a script contains `NONET_BROWSER_URL` and a supported browser (Safari, Google Chrome, Arc, Microsoft Edge or Brave) is in front, Nonet asks that browser for the URL of the current page just before the script runs. The first time, macOS asks whether Nonet may control that browser. If you want to use the URL, allow it and run the button again. If you don't allow it, the script still runs, without `NONET_BROWSER_URL`.

The first time you use a File action, macOS asks whether Nonet may control Finder. Nonet uses it to read the files selected in Finder and to trash, rename or duplicate them. If you don't allow it, File buttons show “Automation (Finder) permission required.” and do nothing.

If you denied it and want it later, turn on the browser or Finder under Nonet in **System Settings › Privacy & Security › Automation**.

### Nonet is listed under Screen Recording

An earlier version had a setting that changed icon colors to match the brightness of the screen under the HUD, and it asked for the macOS Screen Recording permission for that. Nonet now draws each icon in white on a dark plate and no longer uses this permission. You can turn Nonet off, or remove it from the list, in **System Settings › Privacy & Security › Screen & System Audio Recording** (Screen Recording on macOS 14).

### A Menu Item action fails

- Make sure the app is running
- Check whether the menu item's name changed, for example after an app update or a change of the macOS language. If it did, assign it again with **Pick from Menus**

### AI actions aren't available

Make sure you're on macOS 26 or later, your Mac supports Apple Intelligence, and Apple Intelligence is turned on with the model fully downloaded. The AI editor in the inspector also shows the reason. Select some text before you run the button.

### Nonet can't read the selected text

When Nonet passes the selected text to an AI action, a shortcut or a script and the app doesn't report its selection directly, Nonet copies the text with ⌘C and then restores the clipboard. If an AI action can't get the text, Nonet tells you why (shortcuts and scripts run without the selected text):

- "Select some text first.": select the text and run the button again. In VS Code, Cursor, Obsidian, JetBrains IDEs and Sublime Text, ⌘C with nothing selected copies the whole line, so a single copied line that ends with a line break doesn't count as selected text. The message then says "To use a single line, select it without the line break at the end."
- "Couldn't read the selected text without losing what's on the clipboard. …": the clipboard holds something Nonet can't put back, such as more than 64 MB, files that are created when pasted, or content the app that copied it is too slow to provide, so Nonet didn't send ⌘C. Copy the selected text with ⌘C yourself, then run the button again
- "Couldn't read the selected text because Nonet isn't allowed to read the clipboard. …": macOS is set not to let Nonet read the clipboard (see below). Allow it in **System Settings › Privacy & Security**

On macOS 15.4 and later, if your Mac is set to ask before apps read the clipboard, macOS may ask whether Nonet can paste from other apps when Nonet reads the clipboard. Answer within 20 seconds. If it's set to always deny, Nonet never reads or restores the clipboard. It doesn't use ⌘C to read the selected text, and Replace Selection shows the result in the result panel instead.

- Passwords copied from a password manager are never read and never put back
- If ⌘C copies nothing, Nonet waits 0.5 seconds for apps that copy late. It puts the clipboard back only if that app is still in front, and it never undoes a copy you make later yourself

### No haptic feedback

Make sure **Haptic feedback** isn't turned off. You can feel it only on a Force Touch trackpad.

### Nonet doesn't open at login

When you turn on **Open at login** (or **Open Nonet automatically when you log in** in the welcome guide), macOS may ask you to approve it. Allow Nonet in **System Settings › General › Login Items** (Login Items & Extensions on macOS 15 and later).

### “Couldn't load the settings file because it was damaged”

If Nonet says it couldn't load the settings file because it was damaged, it started with the default settings. The original file is kept, under the name shown in the notice, in the same folder (`~/Library/Application Support/Nonet/`). If **Restore an Earlier Version…** has a saved version, you can go back to it. If you exported your profiles, you can also bring them back with **Import…**. To clear the notice, choose **Dismiss Notice** from the Nonet menu.

### Resetting your settings

Quit Nonet, move `~/Library/Application Support/Nonet/` to the Trash, and open Nonet again. It starts as if it were opened for the first time. The days left in your trial and your registration stay as they were. To go back only a little, use **Restore an Earlier Version…** instead.

## Uninstalling

1. On the Nonet tab of Settings, click **Uninstall Nonet…**, then **Uninstall**. Nonet stops opening at login, and moves the app, its settings folder (`~/Library/Application Support/Nonet/`) and its caches to the Trash. Your license key and trial record stay on this Mac, so Nonet works right away if you reinstall it, and the trial doesn't start over. You can undo this until you empty the Trash
2. Click **Open System Settings and Quit**. System Settings opens and Nonet quits. In **Privacy & Security › Accessibility**, select Nonet and click − to remove it. Running `tccutil reset Accessibility com.iam74k4.Nonet` in Terminal does the same

If Nonet can't move itself to the Trash, it changes nothing and tells you. Quit Nonet, then move it from the Applications folder to the Trash in the Finder.

To remove your license key and trial record too, quit Nonet and also delete:

- `~/Library/Preferences/com.iam74k4.Nonet.plist` (preferences such as the trial record and your license key)
- The item you find when you search for `com.iam74k4.Nonet.license.trial` in Keychain Access (the trial record)
- In Keychain Access, the item whose name is 64 hexadecimal digits (0–9 and a–f). It holds a copy of the same trial record. Its name is made from this Mac and the app, and it doesn't say Nonet

If you'll use your license on another Mac, keep a copy of your license key first (**Copy License Key** on the Nonet tab of Settings).
