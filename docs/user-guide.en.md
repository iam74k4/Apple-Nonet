# Nonet User Guide

<!-- English version of user-guide.md. scripts/build-guide.py makes site/en/guide.html from this file. Keep it in step with user-guide.md, then rebuild both pages with python3 -I scripts/build-guide.py (scripts/tests/site_test.sh catches a page that wasn't rebuilt). Use the app's English labels (the "en" values in Localizable.xcstrings) and the terms in glossary.md -->

## About Nonet

Slide a finger in from the top edge, and Nonet turns your MacBook trackpad into nine buttons, a 3×3 grid that changes with each app. You use only the trackpad, no keys.

- Place a finger on the top edge of the trackpad and slide it down to open the nine buttons. Keep sliding to choose one, then lift your finger on it to run it
- The trackpad is split into a 3×3 grid, and **where your finger is** picks the button. The pointer position doesn't matter. While the buttons are open, the HUD, an overlay that shows all nine buttons, appears on the screen
- If you change your mind, slide out to the frame around the nine buttons and lift your finger. Nothing runs
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

Nonet lives in the menu bar and doesn't appear in the Dock. Its menu bar icon is a 3×3 grid with a filled center. In this guide, the menu that opens when you click this icon is called the Nonet menu.

Only one copy of Nonet runs at a time. If you open Nonet again while it's running, the running copy opens its Settings window right away instead of a second copy starting. If you open it right after quitting, it waits for the old copy to finish quitting. When a copy opened from the disk image and the copy in the Applications folder meet, the one in the Applications folder runs, unless the disk image copy is a newer version. Then the disk image copy runs: if the copy in the Applications folder is running, Nonet quits it first, and then asks "Move Nonet to the Applications folder?". If the disk image copy isn't newer, it says "Nonet Is Already Running" and quits, and the running copy opens its Settings window.

### Accessibility permission

The first time you open Nonet, the Welcome to Nonet window (the welcome guide) opens. Click **Open System Settings**, and macOS asks for permission. From there, open **System Settings › Privacy & Security › Accessibility** and turn on Nonet (macOS asks for your password or Touch ID). If macOS doesn't ask, or when you click the button again, Nonet opens that section of System Settings. Once you allow Nonet, the welcome guide comes back in front of System Settings and moves on automatically.

**Why Nonet needs it**: macOS requires this permission for apps that work with the pointer and keyboard while you use other apps. Nonet uses it only to:

- Keep pointer movement and clicks from reaching the front app while the nine buttons are open
- Notice a key press while the nine buttons are open, so it can close them without running anything. While they're closed, Nonet doesn't look at the keyboard at all
- Send the keystrokes you set up, choose menu items and read selected text

**What Nonet doesn't collect**: Nonet never records or sends what you type. Your settings are stored only on your Mac (in `~/Library/Application Support/Nonet/`), and there's no account. Nonet uses the network only to check for updates and to open the purchase page. Reading finger positions on the trackpad needs no permission. For details, see the [privacy policy](privacy.md).

You can click **Not Now** to continue without it, but Nonet doesn't work until you allow it (the Accessibility step at the top of the welcome guide gets a "!"). If you finish without allowing it, the next time Nonet opens it shows "One more step to start using Nonet". Choose **Don't show again** to stop it. To allow it later, choose **Allow Accessibility Access…** from the Nonet menu (it opens this same step), or click **Open System Settings** in the banner at the top of the Settings window. If Nonet can't find a trackpad, this step says so too, and **Check Again** looks for it again.

The first time a script uses the URL of the page shown in a browser (`NONET_BROWSER_URL`), macOS asks for Automation permission (see [macOS asks for Automation permission](#macos-asks-for-automation-permission) under Troubleshooting).

### Welcome guide

The Welcome to Nonet window has three steps, shown at the top.

1. **Accessibility**: the permission described above
2. **Choose Apps**: lists the apps on your Mac that have a preset, a ready-made set of nine buttons (Xcode, Visual Studio Code, Safari, Slack, Zoom and others). All of them are selected at first. Keep the ones you use, then click **Next: Try It Out**. **Select All** and **Deselect All** change them all at once. On a Mac that can't use Apple Intelligence, the presets leave out the AI buttons, and on a Mac without the `claude` command they leave out the Claude Code button. Another button takes the center instead (no preset puts Claude Code in the center)
3. **Try It Out**: two tasks in practice mode. The trackpad drawing shows the names of the buttons the HUD will show. The first task is **Open and lift on a button**: place a finger on the top edge of the trackpad and slide it down, and when the HUD opens, slide to the button named in the task and lift your finger there (if you lift on another button, the task tells you where the named one is). The second is **Cancel in the frame**: open the HUD from the top edge again, then slide out to the frame (outside the nine buttons) and lift your finger. Nothing runs in practice mode. Click **Skip** to move on. If you can't practice yet, the step says why and offers a fix: **Enable Nonet** if Nonet is disabled, **Check Again** if there's no trackpad, **Open Settings** if the page in use has no buttons, or **Enter License Key…** if your trial has ended (once you register a key, the notice goes away)

At the end, "You're all set" shows four quick tips (open from the top edge, lift in the frame to cancel, swipe left or right with two fingers, change a button) and the days left in your trial. **Open Nonet automatically when you log in** is checked from the start, and takes effect when you click **Done** or **Open Settings** (if macOS needs you to approve it in System Settings, the window says so). When you click **Done**, the Nonet icon in the menu bar flashes, and "Nonet lives here" appears under it. If the icon can't be seen, the window tells you how to find Nonet instead. Click **Open Settings** to go straight to the Settings window.

The Global profile starts with a launcher of popular apps from your Mac (see [Global profile and launcher](#global-profile-and-launcher) under Basics).

To see the welcome guide again, choose **Show Welcome Guide** from the Nonet menu. When you run it again, Choose Apps only adds profiles for the apps you choose. Apps marked Added keep their profiles, so nothing you edited is lost.

## Basics

### Opening the buttons

1. Place one finger on the top edge (the far edge) of the trackpad
2. Slide it straight down in one smooth move

The nine buttons open, the HUD (the overview of all nine buttons) appears on the screen, and the trackpad gives a light tick. The pointer goes back to where your finger first touched and stays put until the buttons close. Right after they open, your finger is still in the frame (outside the nine buttons), so the HUD shows "✕ Lift to cancel". Lift your finger there, and the buttons close without running anything.

- They open when a finger placed on the top edge (within about 6 mm of the far edge) moves down about 5 mm within 0.4 seconds, more down than sideways. A slow move from the top edge counts as ordinary pointer movement
- They don't open if you touch with two or more fingers or your palm, if your finger slides in from below the edge, or while a mouse or trackpad button is held down (for example, when you click and start dragging)
- The HUD appears on the display with the pointer (the **HUD position** setting)

### Choosing and running a button

1. Keep your finger down and slide it to choose a button. The button under your finger is highlighted, and each time you cross into another button, the trackpad gives a light tick
2. Stop on the button you want, then lift your finger

The highlighted button runs, and the HUD closes.

- A button runs only if your finger stays on it for a moment (0.15 seconds) before you lift. Lifting while still sliding, or on a button you were only passing over, runs nothing, so a finger that was only meant to move the pointer doesn't run a button
- Lifting right on the line between two buttons runs nothing, because it isn't clear which one you meant
- Buttons are chosen by **position** on the trackpad. The top-left button is in the top-left of the trackpad, inside the frame
- The top of the HUD shows the profile name and the hint "Lift on a button to run". If the page has a name, it shows that too, like "Xcode · Debug". For your first 20 times, a line under the grid also says "Slide to choose · Lift in the frame to cancel"

### Canceling

Any of these closes the buttons without running anything (you feel two light taps):

- **Lift in the frame**: slide out to the frame around the nine buttons and lift your finger. The frame is the band along the edges of the trackpad: 11% of the width at the left and right, 15% of the depth at the near edge and 17% at the far edge (1.5 to 1.7 cm on a trackpad about 15 cm wide). When your finger enters the frame, the buttons dim, the frame lights up and "✕ Lift to cancel" appears
- **Press a key**: pressing any key while the buttons are open closes them right away. The key reaches the app as usual
- **Lift on an empty button**: nothing happens on a button with no action
- **Lift on the line between two buttons**: nothing runs on a border

If the buttons stay open for 20 seconds, they close on their own.

### Buttons that need a longer hold

For buttons that do something you can't undo, such as sending or recording, turn on **Hold before running** in the inspector.

- These buttons have a mark in the corner of the HUD
- Keep your finger on the button for a moment (0.6 seconds), and its outline goes all the way around. Lift after that to run it. Lifting before the outline is complete runs nothing

### The trackpad while the buttons are open

While the nine buttons are open, the pointer stays put, and clicks and scrolling don't reach the front app. If you click, move or scroll with a mouse while you aren't touching the trackpad, Nonet closes the buttons without running anything, and the mouse action reaches the app as usual. Lifting while two fingers are down runs nothing either.

### Pages

While the nine buttons are open, **swipe left or right with two fingers** to change pages. Moving two fingers to the left goes to the next page. Each swipe moves one page. At the first or last page it stops and gives two light taps. The page dots under the HUD show the current page. There's a small gap between the dots of the app's pages and the dots of the Global pages.

After a swipe, lift one finger, slide the remaining finger again, then lift it on a button. Lifting it without sliding, or lifting both fingers, runs nothing.

Each profile can have up to three pages. Global pages follow an app profile's pages (the **Add Global pages after app pages** setting).

### Global profile and launcher

If the front app has a profile, Nonet uses that app's buttons. In apps without a profile, Nonet uses the Global profile, which works in every app.

The Global profile starts as a launcher with up to 27 apps on three pages. Apps in your Dock come first, in Dock order, and popular apps on your Mac fill the rest. It's a handy stand-in for Launchpad, which macOS 26 no longer has. You can change it like any other profile.

### Haptic feedback

When the nine buttons open, and each time your finger crosses into another button, the trackpad gives a light tick. It ticks once when a button runs and twice when the page changes. When the buttons close without running anything (a lift in the frame, on an empty button or on a border, a lift with two fingers, a swipe past the last page and so on), and when they don't open because the trial has ended, it gives two light taps. You can choose the strength with the **Haptic feedback** setting.

## Menu bar

Click the 3×3 icon in the menu bar to open the Nonet menu.

| Item | What it does |
|---|---|
| Status (the top line) | While Nonet is running, it shows the profile used for the front app, like "Xcode profile" or "Global profile". If something is wrong, it shows the problem, such as "Accessibility permission required", "Can't find a trackpad", "Unavailable while entering a password" or "Nonet is disabled". When the trial has ended it reads "Your trial has ended", and with 3 days or fewer left it reads, for example, "3 days left in your trial" |
| Allow Accessibility Access… | Appears only when Nonet doesn't have permission. Opens the permission step of the welcome guide |
| Dismiss Notice | Appears with a notice, for example when Nonet couldn't read its settings file |
| Cheat sheet | Shows the buttons the front app would open with, starting from the first page. Use ‹ › to see the other pages. Click a button to open it on the Profiles tab of Settings. If Nonet is turned off for the front app, a short line such as "Nonet is off in Xcode" appears instead |
| Enable Nonet | Uncheck it, and sliding in from the top edge no longer opens the buttons |
| Settings… | Opens the Settings window on the General tab |
| Edit Buttons for Xcode… / Create Buttons for Pages… / Edit Global Buttons… | Opens the front app's buttons on the Profiles tab of Settings. If the app has no profile, Nonet creates one (from its preset, if there is one). If you ran one of that profile's buttons in the last minute, that button is selected. When Nonet can't tell the front app, or **Switch profiles with the front app** is off, it opens the Global buttons |
| Turn Off in This App | Turns Nonet off in the front app (the item gets a checkmark). In that app, sliding in from the top edge doesn't open the nine buttons, and the trackpad works as usual. Choose it again to turn Nonet back on (see [Profile list](#profile-list) under Editing profiles) |
| Recent Runs | Lists up to 10 buttons you ran recently, newest first, like "✓ Xcode › Build". Ones that failed show "✗" and the first line of the reason. Choose one to open that button on the Profiles tab of Settings |
| Show Welcome Guide | Opens the Welcome to Nonet window |
| User Guide | Opens this guide |
| 14 days left in your trial / Registered / Your trial has ended | Your license status. Choose **Registered** to open the Settings window on the License tab. Nonet doesn't repeat what the status line already says |
| Buy Nonet… / Enter License Key… | Appear during the trial and after it ends. **Buy Nonet…** opens the purchase page, and **Enter License Key…** opens the License tab of Settings |
| Check for Updates… | Checks for a new version. When an automatic check has already found one, this item changes to **Update Available…**; choose it to see the update |
| Quit Nonet | Quits Nonet |

The icon also shows the status. It's dimmed while Nonet is disabled. When something needs your attention (no permission, no trackpad found, a password being entered, the trial has ended or has 3 days or fewer left, or a notice), the top-right square turns into a "!", and the top line of the menu says why. When a new version is available, the top-right square turns into a dot.

While the Settings window or the welcome guide is in front, you can also press ⌘? (**Nonet Help**) to open this guide.

## Editing profiles

Choose **Edit Buttons for Xcode…** (with your front app's name instead of Xcode) from the Nonet menu to open the Profiles tab of the Settings window. It has three columns: the profile list, the buttons and the inspector.

### Profile list

- **Shared Buttons** at the top holds buttons that appear in the same spot in every app (see [Shared buttons](#shared-buttons) below)
- **Global** below it (marked Default) holds the nine buttons used in apps without a profile. You can't delete it
- App profiles are listed below it, under **Apps**. Drag to reorder them. The profile the front app is using now is marked In Use
- Click **Add Profile…** and choose an installed app to create its profile. Apps with a preset start with their buttons filled in. For an app that isn't listed, click **Choose Another App…**
- Control-click (or right-click) a profile to see the three **When in Front** choices and **Duplicate for Another App…**, **Reset to Preset…** (only for apps with a preset), **Export This Profile…** and **Delete…**. You can also press Delete. Nonet asks before deleting (you can undo it with ⌘Z)
- **When in Front**: at the top right of the grid (or by Control-clicking the profile), choose what happens while the app is in front: **This Profile**, **Use Global** or **Turn Off Nonet in This App**. A profile set to **Use Global** is marked Global, and Nonet uses the Global buttons in that app (the profile's buttons are kept). An app set to **Turn Off Nonet in This App** is marked Off. In that app, sliding in from the top edge doesn't open the nine buttons, and the trackpad and the keys work as usual. **Turn Off in This App** in the Nonet menu switches it too
- With 8 or more app profiles, a **Filter by name, button or keys** field appears above the list (press ⌘F to show it at any time; press Esc or click × (Clear Filter) to close it). It finds profile names, and the names, contents and keys of buttons in every profile (type keys with their modifiers, like `⌘B`). Results look like "Xcode › Build"
- **Enable Nonet** under the list is the same switch as in the General settings

### Pages and buttons

The middle column shows the pages and the 3×3 grid of the selected profile.

- Click **Page 1**, **Page 2** and so on (⌘1–⌘3) to switch pages. Click **+** (Add page) to add one (up to three pages). To delete the selected page, click **…** (Page Actions) next to the pages and choose **Delete This Page…**, or Control-click the page and choose **Delete This Page…**. Nonet asks first if the page has buttons. The **…** menu also has **Add Page** and **Rename…**
- Double-click a page, or Control-click it and choose **Rename…**, to give the page a name such as "Debug" or "Git". The name also appears in the HUD title, like "Xcode · Debug". Leave it empty to go back to "Page 1" and so on
- Click a button to select it, and drag to swap buttons. Drag a button onto **Page 2** (or another page) to move it to an empty button on that page
- Use the arrow keys to move the selection, and press Delete to clear a button. For more keys, see "Power editing" below
- Control-click a button to choose **Duplicate**, **Copy**, **Paste**, **Swap With**, **Copy to Profile**, **Delete** or **Test This Button**. On an empty button, choose an action type from **Add Action**, or use **Paste** and **Swap With**

### Shared buttons

Buttons you want in the same spot in every app, such as opening Settings or locking the screen, can be shared buttons.

- Control-click a button and choose **Make Shared Button**. It then appears in the same spot on every page of every profile (app profiles, Global and the launcher)
- Spots covered by a shared button are marked Shared. The profile's own button is kept, and **Stop Sharing** brings it back
- Edit shared buttons under **Shared Buttons** at the top of the profile list. Control-click a shared button in a profile's grid to choose **Edit Shared Button**, **Copy** or **Stop Sharing**
- If that spot already has a shared button, Nonet asks before replacing it (you can undo it with ⌘Z)

### Undo and earlier versions

- Press ⌘Z to undo, and ⇧⌘Z to redo: changes to buttons (clearing, deleting, duplicating, creating, swapping, moving to another page, assigning a menu item, pasting, copying to another profile), changes in the inspector (one step per button), adding or renaming a page, **Reset to Preset…**, **Duplicate for Another App…**, and deleting a profile or a page
- After you clear a button, replace a filled button, copy a button to another profile, or delete a profile or a page, you can also click **Undo** under the grid. If you changed the button again since then, Nonet doesn't undo it and tells you so
- Replacing profiles by importing can't be undone with ⌘Z. Use a saved version instead (below)
- Nonet saves a copy of your settings while you change them (at most once an hour), and before deleting a profile or a page, importing, resetting to a preset or restoring an earlier version. It keeps the newest 10 in `~/Library/Application Support/Nonet/Backups/`. Under Export & Import on the General tab, click **Restore an Earlier Version…**, choose a version, then click **Restore…** and **Restore** to go back to those profiles and settings. Your settings from before are saved too, so you can go back again

### Power editing

- **Profiles**: **Duplicate for Another App…** (Control-click the profile) creates a profile for another app with all the pages and buttons. Menu Item buttons that chose the original app's menus choose the new app's menus, which helps when you copy VS Code buttons to Cursor, for example. **Reset to Preset…** asks first, then replaces the buttons with the preset
- **Buttons**: ⌘C and ⌘V copy and paste a button (also into another profile). Control-click a button and choose **Copy to Profile** to copy it to the first empty button of the profile you choose
- **Keys on the grid**: ⌘D duplicates, ⌘⌫ clears, ⌥⌘ and an arrow key swap with the next button, and Return moves to the **Name** field
- **Keys on the Profiles tab**: ⌘1–⌘3 switch pages, and ⌘F filters profiles

### Inspector

The right column is where you set up the selected button. Changes are saved right away.

- **Empty button**: click an action type to create one
- **Name**: the name shown under the icon. If you leave it empty, Nonet names the button from its action
- **Icon**: click the icon to the left of the name (Change icon). Choose **Symbol** (SF Symbols, searched by their English names), **App** (**Use This App's Icon**, available for Open App buttons and in app profiles) or **Text** (type 1–2 characters and click **Use**). **Restore Default Icon** goes back to the default
- **Action type**: Keystrokes, Open App, URL, Script, Shortcut, Menu Item or AI (see Action types)
- **Hold before running**: when on, the button runs only if you hold your finger on it in the HUD a little longer before lifting (see [Buttons that need a longer hold](#buttons-that-need-a-longer-hold) under Basics)
- **Test This Button**: runs the button now and shows "Ran successfully." or the error. Output from a script or a shortcut appears below it, where you can select and copy it. In an app profile, Nonet brings the app to the front, then runs the button. A Global button runs in the app you were using before you opened Settings
- **Clear This Button**: removes the action and leaves an empty button

### Pick from Menus

You can assign an app's menu items without looking up keyboard shortcuts.

1. Make sure the app is running
2. Click **Pick from Menus** at the top right of the grid, then choose the app from the pop-up menu
3. Find the item with **Search menus**, then drag it onto an empty button. You can also double-click it, or Control-click it and choose **Add to Empty Button**

To go back to the inspector, click the × at the top right of the panel (Back to the inspector).

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

Shortcuts like `⌘[` work correctly on JIS keyboards too.

### Open App

Opens the app, or brings it to the front if it's already running. Under **App to open**, click **Choose App…** and choose an installed app. For an app that isn't listed, click **Choose Another App…**. In the grid, the button's second line reads **Open App**. The app's name appears in the inspector and in the help tag when you hold the pointer over the button.

Turn on **Hide if already in front** to hide the app when you run the button again, so you can switch to it and back.

### URL

Opens the **URL to open** in its default app. If you leave out `https://`, Nonet adds it (`http://` for addresses like `localhost`). App URLs like `obsidian://` work too. A path that starts with `/` or `~` opens as a file or folder.

### Script

Runs the zsh script in the **Script to run (zsh)** field with `/bin/zsh -l -c`. Click **?** above the field to see the environment variables described below.

- **Run**
  - In Background: waits for the script to finish and stops it after the **Timeout** (60 seconds by default, 1–3600 seconds). If the script fails (a non-zero exit code), Nonet shows the last lines of standard error. If it hasn't finished after 0.5 seconds, a "Running “…”…" notice stays at the bottom of the screen until it does
  - In Terminal: runs the script in a new Terminal window. Use it for interactive commands like `claude`
- **Output** (In Background only): **Ignore** (the default), **Replace Selection**, **Copy to Clipboard** or **Show Result**. Nonet uses the script's standard output, without the final newline, the same way as an AI action's **Output**. Empty output does nothing. Output larger than 64 KB isn't used, and Nonet shows an error instead
- **Working directory**: the project folder (see below), or your home folder if there isn't one
- **Environment**: background scripts run in a login shell (`zsh -l`) with the same `PATH` as Terminal, which Nonet reads (including `~/.zshrc`) when it opens. Aliases and functions from `~/.zshrc` work only with **In Terminal** (a script run in Terminal reads `~/.zshrc`). If you change `~/.zshrc`, quit Nonet and open it again

#### Environment variables passed to scripts

These describe the front app when the script runs. **Variables without a value aren't set.**

| Variable | Contents | Example |
|---|---|---|
| `NONET_APP_BUNDLE_ID` | Bundle ID of the front app | `com.apple.dt.Xcode` |
| `NONET_APP_NAME` | Name of the front app | `Xcode` |
| `NONET_DOCUMENT_PATH` | Document open in the front window | `/Users/you/dev/App/App.xcodeproj` |
| `NONET_PROJECT_DIR` | Project folder that contains the document | `/Users/you/dev/App` |
| `PROJECT_DIR` | Same as `NONET_PROJECT_DIR` | `/Users/you/dev/App` |
| `NONET_BROWSER_URL` | URL of the current page in Safari, Google Chrome, Arc, Microsoft Edge or Brave | `https://example.com/article` |
| `NONET_SELECTED_TEXT` | Selected text | |

Nonet reads the selected text (`NONET_SELECTED_TEXT`) and the browser URL (`NONET_BROWSER_URL`) only when the script contains the variable's name, because reading them can mean sending ⌘C or asking the browser. A script that doesn't contain these names never sends ⌘C and never asks the browser, so no Automation prompt appears. In apps whose selection can't be read directly, Nonet copies it with ⌘C and then restores the clipboard. If your script only calls a script in another file, write the names of the variables it uses in your script, even in a comment (see the last example below). The other variables (`NONET_APP_BUNDLE_ID`, `NONET_APP_NAME`, `NONET_DOCUMENT_PATH`, `NONET_PROJECT_DIR` and `PROJECT_DIR`) are always set when they have a value.

Nonet finds the project folder like this:

- If the document is a `.xcodeproj`, `.xcworkspace` or `.swiftpm`, the folder that contains it
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

**Output** works as it does for scripts (**Ignore** is the default). Nonet takes the shortcut's output as text and uses it without the final newline.

### Menu Item

Chooses a menu item in an app. The easiest way to set it up is **Pick from Menus** (the button in the inspector's Menu Item editor opens the same panel). **Menu item to choose** shows where the item is, its app and its keys.

- If the app is in front and the item's keyboard shortcut matches that item's shortcut in the app's menus, Nonet sends the keys, which is fast. Otherwise (for example, if an app update changed the shortcut, or Nonet can't read the menus), Nonet opens the menus one by one and chooses the item
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

## General settings

Choose **Settings…** from the Nonet menu to open the General tab of the Settings window. Use the tabs at the top of the window to switch between Profiles, General, License and About. The General tab is grouped into these sections.

### Opening and HUD

| Setting | Default | What it does |
|---|---|---|
| Enable Nonet | On | When off, sliding in from the top edge of the trackpad doesn't open the buttons. You can also switch it in the Nonet menu and under the profile list |
| How to open and cancel | | Shows how to open and cancel, with a drawing of the trackpad (see [Basics](#basics)) |
| HUD position | Center of Screen | Center of Screen or Near Pointer. The HUD appears on the display with the pointer |
| HUD size | Standard | Standard, Large or Extra Large. Notices at the bottom of the screen use the same size. If it doesn't fit on the screen, Nonet makes it as large as fits |

### Profiles

| Setting | Default | What it does |
|---|---|---|
| Switch profiles with the front app | On | When off, Nonet always uses the Global profile |
| Add Global pages after app pages | On | Global pages follow the app's pages, so you can reach them with a two-finger swipe. You can't change it while Switch profiles with the front app is off |

### Feedback

| Setting | Default | What it does |
|---|---|---|
| Haptic feedback | Medium | Off, Light, Medium or Strong. Taps when the buttons open, when you cross an edge, when the page changes and when a button runs. Two light taps mean they closed without running anything |
| Show a notice when a button runs | On | Shows a notice at the bottom of the screen when a slow button finishes |

Slow buttons (background scripts, shortcuts and AI) that haven't finished after 0.5 seconds show a notice like "Running “Translate”…" until they finish, whatever this setting is. When a button fails, Nonet shows which button of which profile it was ("Safari › Reload", plus "(page 2)" if the profile has more than one page) and why, for 3 to 8 seconds depending on the length.

### Advanced

| Setting | Default | What it does |
|---|---|---|
| Pointer lock method | Automatic | Automatic (discards movement and moves the pointer back if it drifts), Discard Movement, Detach Pointer or Off (the pointer moves with your finger). Try another method if the pointer moves while the nine buttons are open |

### Startup

| Setting | Default | What it does |
|---|---|---|
| Open at login | Off (turned on at the end of the welcome guide) | Opens Nonet when you log in to your Mac |

### Export & Import

You can export profiles to a .nonetprofile file to back them up or to share them with another Mac or another person. Only profiles (the buttons and their actions) are exported. General settings and your license aren't included.

- **Export…**: exports all profiles to one file. To export one profile, Control-click it in the profile list and choose **Export This Profile…**
- **Import…**: adds the profiles in a file. In either of these cases, Nonet first asks "Import “file name”?":
  - Importing would replace something you have (the file contains a Global profile, or a profile for an app you already have a profile for). Nonet lists what would be replaced
  - The file has buttons that run something: Script, Keystrokes, Menu Item and AI buttons, and URLs that open a file on your Mac. Nonet asks even if nothing would be replaced. In a scrolling list, it shows each of these buttons as "Profile › Button" with everything it does, without cutting anything off: every line of the script, all the keys, the menu item and its keyboard shortcut, the AI prompt and output, or the location of the file. Invisible characters are shown in a visible form, like "⟨U+202E⟩"
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

- You can use every feature free for **14 days** from the day you first open Nonet. The days left appear in the Nonet menu and on the License tab of Settings
- With 3 days or fewer left, the icon gets a "!", and the top line of the Nonet menu shows the days left. The HUD also shows a line like "3 days left in your trial", once a day. You can buy or register at any time with **Buy Nonet…** and **Enter License Key…** in the Nonet menu
- When the trial ends, sliding in from the top edge no longer opens the nine buttons. Instead, "Your trial has ended" and "Buy Nonet or register a license key from its menu bar icon." appear at the bottom of the screen (you feel two light taps). Your settings are kept. You can also buy or register from a small "Your Nonet trial has ended" window (at most once a day, with **Buy Nonet**, **Register License Key…** and **Not Now**), and from the banner at the top of the Settings window (**Buy Nonet** and **Enter License Key…**)
- After you buy Nonet, your license key arrives by email. One license covers every Mac you use. You can get a full refund within 30 days of purchase
- Keys for refunded licenses and keys that were made public stop working in later versions of Nonet. If your registered key stops working, the License tab says why, and Nonet goes back to the trial if any trial time is left

The License tab:

- **Status**: "14 days left in your trial (ends November 14)", "Registered" or "Your trial has ended". Once you register, it also shows who it's registered to, the issue date and the license ID
- **One-time purchase**: **Buy Nonet** opens the purchase page (shown only before you register)
- **Already Bought Nonet?**: paste the license key from your purchase email into the field and click **Register**. It takes effect right away. If you paste the text around the key too, like "License key:", Nonet reads only the key. Nonet checks the key on this Mac, so you don't need a network connection or an account. If Nonet can't register the key, it says why and what to do next (**Contact Support…** next to the message writes an email to us). If you can't find your key, click **Can't find your license key?**. If you open the registration link in your purchase email, or the attached `.nonetlicense` file, Nonet fills in the key and asks "Register this license key?" (it never registers a key without asking)
- **License Key**: once you register, click **Copy License Key** to copy your key and register it on your other Macs. **Register a Different Key…** lets you switch to another key
- **Remove License from This Mac**: click **Remove…**, then **Remove** to confirm, and Nonet removes your license key from this Mac. Use this before you sell or give away this Mac. The same key keeps working on your other Macs

## Updates and About

Nonet checks for new versions automatically. When it finds one, the top-right square of the menu bar icon turns into a dot, and the **Check for Updates…** item in the Nonet menu changes to **Update Available…**. Choose it to see the update. If Nonet finds an update right after it opens, it shows the update right away. To check at any time, choose **Check for Updates…** from the Nonet menu.

The About tab of Settings shows the version and has **Check for Updates…**, **User Guide** (this guide), **Privacy Policy**, **Contact Support…** and **Uninstall Nonet…**, plus the licenses of the third-party software Nonet uses. When Nonet runs in English, the user guide and the privacy policy open in English.

**Contact Support…** opens an email to us in your email app. It contains only the versions of Nonet and macOS, your Mac model and your keyboard type (never your license key or your settings). You decide whether to send it.

## Troubleshooting

When Nonet can't work, the top line of the Nonet menu and the banner at the top of the Settings window tell you why.

### “Accessibility permission required”

- Click **Open System Settings** in the banner at the top of the Settings window (the first click shows the macOS prompt; click again to open System Settings), or choose **Allow Accessibility Access…** from the Nonet menu
- Turn on Nonet in **System Settings › Privacy & Security › Accessibility**. Nonet starts working once you allow it
- If Nonet is on but still doesn't work (after an update, for example), select Nonet in the list, click − to remove it, then add it again and turn it on

### “Nonet doesn't work while you enter a password”

While the cursor is in a password field, or while Secure Keyboard Entry is on in Terminal, macOS keeps keystrokes from other apps, so Nonet doesn't open the nine buttons. Leave the password field, or turn off **Terminal › Secure Keyboard Entry**. Nonet starts working again on its own. To check right away, click **Check Again** in the banner.

### “Can't find a multi-touch trackpad”

Nonet needs a MacBook's built-in trackpad or a Magic Trackpad. It doesn't work with only a mouse. When you connect or reconnect a Magic Trackpad, Nonet finds it again on its own, which can take about 10 seconds. To check right away, click **Check Again** in the banner. If it still doesn't respond, choose **Quit Nonet** from the Nonet menu and open Nonet again.

### Nothing happens

- Make sure **Enable Nonet** is checked in the Nonet menu
- Make sure **Turn Off in This App** isn't checked for the front app (such apps are marked Off in the profile list)
- Make sure your trial hasn't ended (the Nonet menu shows "Your trial has ended")
- Check whether one of the three problems above (Accessibility, password entry or trackpad) is shown
- Make sure you place your finger on the top edge (the far edge) of the trackpad first, then slide it down in one smooth move. Starting below the edge or moving slowly doesn't open the buttons (see [Opening the buttons](#opening-the-buttons) under Basics)
- While a Nonet window such as Settings is in front, sliding in from the top edge doesn't open the nine buttons, because Settings uses the trackpad for things like dragging buttons. Switch to the app you want to use first, or, to try a button in Settings, use **Test This Button** in the inspector. When you close the Settings window, the app you were using before comes back to the front

### The menu bar icon is missing

When the menu bar is crowded, the Nonet icon can be hidden. Open Nonet again from the Applications folder, and the Settings window opens right away.

### The buttons open when you didn't mean to

If you move the pointer by sliding a finger quickly down from the far edge of the trackpad, the nine buttons open. If that happens, just lift your finger: nothing runs, because right after they open your finger is in the frame. If it happens often, start pointer moves a little away from the far edge. For apps where you don't use Nonet, choose **Turn Off in This App** from the Nonet menu, and the buttons won't open there.

### The pointer doesn't move or clicks don't work

While the nine buttons are open, Nonet holds the pointer still and blocks clicks. If Nonet thinks they're still open, any of these gets things back to normal:

- Take all your fingers off the trackpad
- Press any key (this closes them right away)
- Move or click the mouse (the mouse action reaches the app as usual)
- Wait 20 seconds (long sessions end on their own)
- If none of these work, choose **Quit Nonet** from the Nonet menu

If the pointer moves a little while the nine buttons are open, try another **Pointer lock method** under Advanced.

### The wrong button runs

Buttons are chosen by the **absolute position** of your finger on the trackpad. Check which button is highlighted in the HUD before you lift. If the wrong one is highlighted, slide to the right one, or slide out to the frame and lift so nothing runs. Nothing runs on the line between two buttons, so lift in the middle of a button. For buttons that do something you can't undo, turn on **Hold before running** (see [Buttons that need a longer hold](#buttons-that-need-a-longer-hold) under Basics). **Recent Runs** in the Nonet menu shows what ran.

### A script fails

- Read the error on screen. If the exit code is 127 (`command not found`), run `command -v <name>` in Terminal to check that the command is installed. Background scripts use the same `PATH` as Terminal. Nonet reads it when it opens, so if you change `~/.zshrc`, open Nonet again
- To test under similar conditions, run `zsh -lic '<script>'` in Terminal
- **Test This Button** in the inspector shows the result right away
- For long tasks, raise the **Timeout** or choose **In Terminal**

### macOS asks for Automation permission

When a script contains `NONET_BROWSER_URL` and a supported browser (Safari, Google Chrome, Arc, Microsoft Edge or Brave) is in front, Nonet asks that browser for the URL of the current page just before the script runs. The first time, macOS asks whether Nonet may control that browser. If you want to use the URL, allow it and run the button again. If you don't allow it, the script still runs, without `NONET_BROWSER_URL`.

If you denied it and want it later, turn on the browser under Nonet in **System Settings › Privacy & Security › Automation**.

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

Make sure **Haptic feedback** isn't set to Off. You can feel it only on a Force Touch trackpad.

### Nonet doesn't open at login

When you turn on **Open at login**, macOS may ask you to approve it. Allow Nonet in **System Settings › General › Login Items** (Login Items & Extensions on macOS 15 and later).

### “Couldn't load the settings file because it was damaged”

If Nonet says it couldn't load the settings file because it was damaged, it started with the default settings. The original file is kept, under the name shown in the notice, in the same folder (`~/Library/Application Support/Nonet/`). If **Restore an Earlier Version…** has a saved version, you can go back to it. If you exported your profiles, you can also bring them back with **Import…**. To clear the notice, choose **Dismiss Notice** from the Nonet menu.

### Resetting your settings

Quit Nonet, move `~/Library/Application Support/Nonet/` to the Trash, and open Nonet again. It starts as if it were opened for the first time. The days left in your trial and your registration stay as they were. To go back only a little, use **Restore an Earlier Version…** instead.

## Uninstalling

1. On the About tab of Settings, click **Uninstall Nonet…**, then **Uninstall**. Nonet stops opening at login, and moves the app, its settings folder (`~/Library/Application Support/Nonet/`) and its caches to the Trash. Your license key and trial record stay on this Mac, so Nonet works right away if you reinstall it, and the trial doesn't start over. You can undo this until you empty the Trash
2. Click **Open System Settings and Quit**. System Settings opens and Nonet quits. In **Privacy & Security › Accessibility**, select Nonet and click − to remove it. Running `tccutil reset Accessibility com.iam74k4.Nonet` in Terminal does the same

If Nonet can't move itself to the Trash, it changes nothing and tells you. Quit Nonet, then move it from the Applications folder to the Trash in the Finder.

To remove your license key and trial record too, quit Nonet and also delete:

- `~/Library/Preferences/com.iam74k4.Nonet.plist` (preferences such as the trial record, your license key and how many times the HUD tips were shown)
- The item you find when you search for `com.iam74k4.Nonet.license.trial` in Keychain Access (the trial record)
- In Keychain Access, the item whose name is 64 hexadecimal digits (0–9 and a–f). It holds a copy of the same trial record. Its name is made from this Mac and the app, and it doesn't say Nonet

If you'll use your license on another Mac, keep a copy of your license key first (**Copy License Key** on the License tab).
