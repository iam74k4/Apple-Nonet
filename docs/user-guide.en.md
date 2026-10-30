# Nonet User Guide

<!-- English version of user-guide.md. scripts/build-guide.py makes site/en/guide.html from this file. Keep it in step with user-guide.md, then rebuild both pages with python3 -I scripts/build-guide.py (scripts/tests/site_test.sh catches a page that wasn't rebuilt). Use the app's English labels (the "en" values in Localizable.xcstrings) and the terms in glossary.md -->

## About Nonet

Nonet turns your MacBook trackpad into nine buttons, a 3×3 grid that changes with each app, but only while you hold a key.

- The trackpad is split into a 3×3 grid, and **where you rest your finger** picks the button. The pointer position doesn't matter
- Once you know the layout, press the key and tap right away to run a button. The HUD, an overlay that shows all nine buttons, appears only when you hesitate
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

Only one copy of Nonet runs at a time. If you open Nonet again while it's running, the running copy opens its Settings window instead of a second copy starting (this takes about 3 seconds). If a copy opened from the disk image is running and you open the copy in the Applications folder, the disk image copy quits and the one in the Applications folder takes over.

### Accessibility permission

The first time you open Nonet, the Welcome to Nonet window (the welcome guide) opens. Click **Open System Settings**, then turn on Nonet in **System Settings › Privacy & Security › Accessibility**. Once you allow Nonet, the welcome guide comes back in front of System Settings and moves on automatically.

**Why Nonet needs it**: macOS requires this permission for apps that work with the keyboard and pointer while you use other apps. Nonet uses it only to:

- Detect when you press and release the trigger key
- Keep pointer movement and clicks from reaching the front app while you hold the trigger key
- Send the keystrokes you set up, choose menu items and read selected text

**What Nonet doesn't collect**: Nonet never records or sends what you type. Your settings are stored only on your Mac (in `~/Library/Application Support/Nonet/`), and there's no account. Nonet uses the network only to check for updates and to open the purchase page. Reading finger positions on the trackpad needs no permission. For details, see the [privacy policy](privacy.md).

You can click **Not Now** to continue without it, but Nonet doesn't work until you allow it (the Accessibility step at the top of the welcome guide gets a "!"). To allow it later, choose **Allow Accessibility Access…** from the Nonet menu, or click **Open System Settings** in the banner at the top of the Settings window.

The first time a script uses the URL of the page shown in a browser (`NONET_BROWSER_URL`), macOS asks for Automation permission (see [macOS asks for Automation permission](#macos-asks-for-automation-permission) under Troubleshooting).

### Welcome guide

The Welcome to Nonet window has three steps, shown at the top.

1. **Accessibility**: the permission described above
2. **Choose Apps**: lists the apps on your Mac that have a preset, a ready-made set of nine buttons (Xcode, Visual Studio Code, Safari, Slack, Zoom and others). All of them are selected at first. Keep the ones you use, then click **Next: Try It Out**. **Select All** and **Deselect All** change them all at once. Click **Set Up Later** to move on without choosing (the first time, Nonet then uses all of the listed apps)
3. **Try It Out**: practice mode. Follow the prompt: hold the trigger key and tap the top-right corner of the trackpad. Nothing runs in practice mode. Click **Skip** to move on. If you can't practice yet, the step says why and offers a fix: **Enable Nonet** if Nonet is disabled, or **Enter License Key…** if your trial has ended (once you register a key, the notice goes away)

At the end, "You're all set" shows three quick tips. Click **Done** to close the window, or **Open Settings** to go straight to the Settings window.

The Global profile starts with a launcher of popular apps from your Mac (see [Global profile and launcher](#global-profile-and-launcher) under Basics).

To see the welcome guide again, choose **Show Welcome Guide** from the Nonet menu. When you run it again, Choose Apps only adds profiles for the apps you choose. Apps marked Added keep their profiles, so nothing you edited is lost.

## Basics

### Trigger key

The trigger key turns your trackpad into the nine buttons. By default it's **right ⌘** on a JIS keyboard and **right ⌥** on other keyboards (JIS keyboards have no right ⌥). You can also choose right ⇧ or fn (Globe) in Settings. Nonet responds only to the right-side key, so left ⌘ and ⌥ work as usual.

The examples below use right ⌘.

### Quick tap

1. Press right ⌘
2. Right away (within 0.3 seconds by default), tap where the button you want is

The button runs right away, without the HUD. Nonet briefly shows the button at the bottom of the screen. While you keep holding right ⌘, you can tap as many times as you like.

### The HUD

1. Press right ⌘
2. Rest your finger on the trackpad (or wait a moment without touching it)
3. The HUD appears, and the button under your finger is highlighted. Slide to the button you want
4. Release right ⌘ with your finger still down to run the highlighted button

The top of the HUD shows the profile name and the hint "Release ⌘ to run". The HUD appears on the display with the pointer.

If you set **Run on** to **Finger Lift** in Settings, the button runs when you lift your finger instead of at step 4 (the hint reads "Lift your finger to run"). This also changes how you cancel (see the next section, [Canceling](#canceling)).

### Canceling

With any setting:

- If you release right ⌘ without touching the trackpad, nothing happens
- If you press any other key while holding right ⌘, Nonet steps aside right away and runs nothing. The key reaches the app as usual, so shortcuts like right ⌘C still work. To cancel on purpose, press a modifier key that does nothing on its own, such as **left ⇧**

Depending on **Run on**:

- **Key Release (the default)**: lift your finger first, then release right ⌘, and nothing runs
- **Finger Lift**: lifting your finger runs the highlighted button. To cancel while choosing in the HUD, **keep your finger down and press left ⇧**, or slide to an empty button, if there is one, and lift your finger there (nothing happens on an empty button)

### The trackpad while you hold the key

While you hold right ⌘, the pointer stays put, and clicks and scrolling don't reach the front app. Taps with two or more fingers don't run anything. Tapping an empty button does nothing. If you hold right ⌘ for 20 seconds, Nonet steps aside on its own.

### Pages

Hold right ⌘ and **swipe left or right with two fingers** to change pages. Moving two fingers to the left goes to the next page. Each swipe moves one page and stops at the first or last page. If the HUD isn't showing yet, it appears. The page dots under the HUD show the current page.

Each profile can have up to three pages. Global pages follow an app profile's pages (the **Add Global pages after app pages** setting).

### Global profile and launcher

If the front app has a profile, Nonet uses that app's buttons. In apps without a profile, Nonet uses the Global profile, which works in every app.

The Global profile starts as a launcher with up to 27 apps on three pages, chosen from the apps on your Mac. It's a handy stand-in for Launchpad, which macOS 26 no longer has. You can change it like any other profile.

### Haptic feedback

Each time your finger crosses into another button, the trackpad gives a light tick. It also ticks when the page changes and when a button runs. You can choose the strength with the **Haptic feedback** setting.

## Menu bar

Click the 3×3 icon in the menu bar to open the Nonet menu.

| Item | What it does |
|---|---|
| Status (the top line) | While Nonet is running, it shows the profile used for the front app, like "Xcode profile" or "Global profile". If something is wrong, it shows the problem, such as "Accessibility permission required", "Can't find a trackpad", "Unavailable while entering a password" or "Nonet is disabled" |
| Allow Accessibility Access… | Appears only when Nonet doesn't have permission. Opens the Accessibility section of System Settings |
| Dismiss Notice | Appears with a notice, for example when Nonet couldn't read its settings file |
| Enable Nonet | Uncheck it and Nonet ignores the trigger key |
| Settings… | Opens the Settings window on the General tab |
| Edit Profiles… | Opens the Settings window on the Profiles tab |
| Show Welcome Guide | Opens the Welcome to Nonet window |
| 14 days left in your trial / Registered / Your trial has ended | Your license status. Choose it to open the Settings window on the License tab |
| Check for Updates… | Checks for a new version. When an automatic check has already found one, this item changes to **Update Available…**; choose it to see the update |
| Quit Nonet | Quits Nonet |

The icon also shows the status. It's dimmed while Nonet is disabled, and it gets a dot in the top-right corner when something needs your attention (no permission, no trackpad found, a password being entered, the trial has ended, or a notice). It also gets a dot when a new version is available.

## Editing profiles

Choose **Edit Profiles…** from the Nonet menu to open the Profiles tab of the Settings window. It has three columns: the profile list, the buttons and the inspector.

### Profile list

- **Global** at the top (marked Default) holds the nine buttons used in apps without a profile. You can't delete it
- App profiles are listed below it, under **Apps**. Drag to reorder them
- Click **Add Profile…** and choose an installed app to create its profile. Apps with a preset start with their buttons filled in. For an app that isn't listed, click **Choose Another App…**
- Control-click (or right-click) a profile to choose **Disable**, **Export This Profile…** or **Delete…**. You can also press Delete. Nonet asks before deleting, because you can't undo it
- A disabled profile is marked Off, and Nonet uses the Global profile in that app. You can also switch it with **Use this profile** above the buttons
- **Enable Nonet** under the list is the same switch as in the General settings

### Pages and buttons

The middle column shows the pages and the 3×3 grid of the selected profile.

- Click **Page 1**, **Page 2** and so on to switch pages. Click **+** (Add page) to add one (up to three pages). To delete a page, click **−** (Delete this page), or Control-click the page and choose **Delete This Page…**
- Click a button to select it, and drag to swap buttons. Drag a button onto **Page 2** (or another page) to move it to an empty button on that page
- Use the arrow keys to move the selection, and press Delete to clear a button
- Press ⌘Z to undo changes to buttons, such as clearing, deleting, duplicating, creating, swapping or moving them to another page, or assigning a menu item, and ⇧⌘Z to redo. After you clear a button, or replace a filled button with a menu item, you can also click **Undo** under the grid. If you changed the button again since then, Nonet doesn't undo it and tells you so. Deleting a page or a profile, and replacing profiles by importing, can't be undone
- Control-click a button to choose **Duplicate**, **Delete** or **Test This Button**. On an empty button, choose an action type from **Add Action**

### Inspector

The right column is where you set up the selected button. Changes are saved right away.

- **Empty button**: click an action type to create one
- **Name**: the name shown under the icon. If you leave it empty, Nonet names the button from its action
- **Icon**: click the icon to the left of the name (Change icon). Choose **Symbol** (SF Symbols, searched by their English names), **App** (**Use This App's Icon**, available for Open App buttons and in app profiles) or **Text** (type 1–2 characters and click **Use**). **Restore Default Icon** goes back to the default
- **Action type**: Keystrokes, Open App, URL, Script, Shortcut, Menu Item or AI (see Action types)
- **Test This Button**: runs the button now and shows "Ran successfully." or the error. In an app profile, Nonet brings the app to the front, then runs the button. A Global button runs in the app you were using before you opened Settings
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

Opens the app, or brings it to the front if it's already running. Under **App to open**, click **Choose App…** and choose an installed app. For an app that isn't listed, click **Choose Another App…**.

Turn on **Hide if already in front** to hide the app when you tap the button again, so you can switch to it and back.

### URL

Opens the **URL to open** in its default app. If you leave out `https://`, Nonet adds it (`http://` for addresses like `localhost`). App URLs like `obsidian://` work too. A path that starts with `/` or `~` opens as a file or folder.

### Script

Runs the zsh script in the **Script to run (zsh)** field with `/bin/zsh -l -c`. Click **?** above the field to see the environment variables described below.

- **Run**
  - In Background: waits for the script to finish and stops it after the **Timeout** (60 seconds by default, 1–3600 seconds). If the script fails (a non-zero exit code), Nonet shows the last lines of standard error
  - In Terminal: runs the script in a new Terminal window. Use it for interactive commands like `claude`
- **Working directory**: the project folder (see below), or your home folder if there isn't one
- **Environment**: scripts run in a login shell, so `~/.zprofile` is read but `~/.zshrc` isn't. Put your `PATH` for Homebrew and other tools in `~/.zprofile`

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

### Menu Item

Chooses a menu item in an app. The easiest way to set it up is **Pick from Menus** (the button in the inspector's Menu Item editor opens the same panel). **Menu item to choose** shows where the item is, its app and its keys.

- If the app is in front and the item has a keyboard shortcut, Nonet sends the keys, which is fast
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
- When Nonet restores the clipboard, a copied image comes back in one image format, and files copied in the Finder come back as files without their icons

## General settings

Choose **Settings…** from the Nonet menu to open the General tab of the Settings window. Use the tabs at the top of the window to switch between Profiles, General, License and About. The General tab is grouped into these sections.

### Trigger & HUD

| Setting | Default | What it does |
|---|---|---|
| Enable Nonet | On | When off, Nonet ignores the trigger key. You can also switch it in the Nonet menu and under the profile list |
| Trigger key | Right ⌘ on JIS keyboards, right ⌥ on others | Right Command (⌘), Right Option (⌥), Right Shift (⇧) or fn. Nonet responds only to the right-side key. On a JIS keyboard, choosing right ⌥ shows a warning |
| Run on | Key Release | Whether a button you choose in the HUD runs when you release the trigger key (Key Release) or when you lift your finger (Finger Lift). Quick taps always run right away. Finger Lift changes how you cancel (see [Canceling](#canceling) under Basics) |
| HUD delay | 0.30 s | 0.15–0.80 s. Taps faster than this run right away, without the HUD |
| HUD position | Center of Screen | Center of Screen or Near Pointer. The HUD appears on the display with the pointer |

### Profiles

| Setting | Default | What it does |
|---|---|---|
| Switch profiles with the front app | On | When off, Nonet always uses the Global profile |
| Add Global pages after app pages | On | Global pages follow the app's pages, so you can reach them with a two-finger swipe. You can't change it while Switch profiles with the front app is off |

### Feedback

| Setting | Default | What it does |
|---|---|---|
| Haptic feedback | Medium | Off, Light, Medium or Strong. The trackpad ticks when your finger crosses into another button, the page changes or a button runs |
| Show a notice when a button runs | On | When a button runs without the HUD, Nonet briefly shows it at the bottom of the screen |

### Advanced

| Setting | Default | What it does |
|---|---|---|
| Pass the trigger key to the front app | On | When off, the trigger key itself doesn't reach the front app or other tools (see "Another tool also uses right ⌘" under Troubleshooting) |
| Pointer lock method | Automatic | Automatic (discards movement and moves the pointer back if it drifts), Discard Movement, Detach Pointer or Off (the pointer moves with your finger). Try another method if the pointer moves while you hold the trigger key |

### Startup

| Setting | Default | What it does |
|---|---|---|
| Open at login | Off | Opens Nonet when you log in to your Mac |

### Export & Import

You can export profiles to a .nonetprofile file to back them up or to share them with another Mac or another person. Only profiles (the buttons and their actions) are exported. General settings and your license aren't included.

- **Export…**: exports all profiles to one file. To export one profile, Control-click it in the profile list and choose **Export This Profile…**
- **Import…**: adds the profiles in a file. In either of these cases, Nonet first asks "Import “file name”?":
  - Importing would replace something you have (the file contains a Global profile, or a profile for an app you already have a profile for). Nonet lists what would be replaced
  - The file has buttons that run something: scripts, keystrokes that press Return or are longer than four keystrokes, and URLs that open a file on your Mac. Nonet asks even if nothing would be replaced. It lists each of these buttons as "• Profile › Button" with what it runs: the first three lines of the script and its line count, the keys, or the location of the file

When Nonet asks, check the contents, then choose one of these:

- Replace and Import: shown when something would be replaced. Replaces the listed profiles with the contents of the file and adds any new app profiles. You can't undo this action
- Import: shown when nothing would be replaced. Adds the profiles in the file
- Add New Profiles Only: leaves your profiles as they are and adds only profiles for apps you don't have yet (shown only when the file both replaces some profiles and adds new ones)
- Cancel: changes nothing

In other cases, Nonet imports the file without asking. The result (how many profiles were added, replaced or skipped) appears in the banner at the top of the window. For Menu Item buttons, Nonet imports a keyboard shortcut only if it's a single keystroke. It drops longer ones, and Nonet chooses those items by opening the menus.

**Import profiles from someone else only if you trust them.** Scripts and keystrokes run with your permissions. Check the buttons Nonet lists before you import, and read whole scripts in the inspector after importing. If the file contains scripts, the banner reminds you after importing.

## Trial and license

- You can use every feature free for **14 days** from the day you first open Nonet. The days left appear in the Nonet menu and on the License tab of Settings
- When the trial ends, the HUD shows "Your trial has ended" and buttons no longer run. Your settings are kept
- After you buy Nonet, your license key arrives by email

The License tab:

- **Status**: "14 days left in your trial", "Registered" or "Your trial has ended". Once you register, it also shows who it's registered to, the issue date and the license ID
- **License Key**: paste the license key from your purchase email into the field and click **Register**. It takes effect right away. If you paste the text around the key too, like "License key:", Nonet reads only the key. Nonet checks the key on this Mac, so you don't need a network connection or an account
- **Buy Nonet**: opens the purchase page (shown only before you register)
- **Unregister this Mac**: click **Unregister…**, then **Unregister** to confirm, and Nonet removes your license key from this Mac. Use this when you move your license to another Mac. Keep a copy of your license key so you can register again

## Updates and About

Nonet checks for new versions automatically. When it finds one, the menu bar icon gets a dot, and the **Check for Updates…** item in the Nonet menu changes to **Update Available…**. Choose it to see the update. If Nonet finds an update right after it opens, it shows the update right away. To check at any time, choose **Check for Updates…** from the Nonet menu.

The About tab of Settings shows the version and has **Check for Updates…**, **User Guide** (this guide) and **Privacy Policy**, plus the licenses of the third-party software Nonet uses. When Nonet runs in English, the user guide and the privacy policy open in English.

## Troubleshooting

When Nonet can't work, the top line of the Nonet menu and the banner at the top of the Settings window tell you why.

### “Accessibility permission required”

- Click **Request Permission** or **Open System Settings** in the banner at the top of the Settings window, or choose **Allow Accessibility Access…** from the Nonet menu
- Turn on Nonet in **System Settings › Privacy & Security › Accessibility**. Nonet starts working once you allow it
- If Nonet is on but still doesn't work (after an update, for example), select Nonet in the list, click − to remove it, then add it again and turn it on

### “Nonet doesn't work while you enter a password”

While the cursor is in a password field, or while Secure Keyboard Entry is on in Terminal, macOS keeps keystrokes from other apps. Leave the password field, or turn off **Terminal › Secure Keyboard Entry**. Nonet starts working again on its own. To check right away, click **Check Again** in the banner.

### “Can't find a multi-touch trackpad”

Nonet needs a MacBook's built-in trackpad or a Magic Trackpad. It doesn't work with only a mouse. When you connect or reconnect a Magic Trackpad, Nonet finds it again on its own, which can take about 10 seconds. To check right away, click **Check Again** in the banner. If it still doesn't respond, choose **Quit Nonet** from the Nonet menu and open Nonet again.

### Nothing happens

- Make sure **Enable Nonet** is checked in the Nonet menu
- Make sure your trial hasn't ended (the Nonet menu shows "Your trial has ended")
- Make sure you're holding the trigger key set in Settings. Nonet doesn't respond to left ⌘ or ⌥
- Check whether one of the three problems above (Accessibility, password entry or trackpad) is shown
- While a Nonet window such as Settings is in front, Keystrokes, Script, Shortcut, Menu Item and AI buttons don't run, and Nonet shows "Didn't run because a Nonet window is in front. …" (Open App and URL buttons do run). Switch to the app you want to use first, or, to try a button in Settings, use **Test This Button** in the inspector. When you close the Settings window, the app you were using before comes back to the front

### The menu bar icon is missing

When the menu bar is crowded, the Nonet icon can be hidden. Open Nonet again from the Applications folder, and after a moment (about 3 seconds) the Settings window opens.

### The pointer doesn't move or clicks don't work

While you hold the trigger key, Nonet holds the pointer still and blocks clicks. If Nonet thinks the key is still down, any of these gets things back to normal:

- Press and release the trigger key (right ⌘ or the key you chose) once
- Press any other key (this cancels right away)
- Wait 20 seconds (long sessions end on their own)
- If none of these work, choose **Quit Nonet** from the Nonet menu

If the pointer moves a little while you hold the trigger key, try another **Pointer lock method** under Advanced.

### No right ⌥ on a JIS keyboard

JIS keyboards have no right ⌥. Choose right ⌘ (the default), right ⇧ or fn as the trigger key.

### Another tool also uses right ⌘

If you use a tool such as ⌘英かな or Karabiner-Elements that acts when you press right ⌘ by itself, it may react every time you use Nonet. Choose another trigger key, or change that tool's settings. If you turn off **Pass the trigger key to the front app**, the trigger key no longer reaches other apps and tools.

### The wrong button runs

Buttons are chosen by the **absolute position** of your finger on the trackpad. For a button on the edge, tap near that edge of the trackpad. When you're not sure, rest your finger and check the HUD before the button runs. If quick taps keep bringing up the HUD, or the HUD doesn't appear when you want it, change the **HUD delay**.

### A script fails

- Read the error on screen. If it says `command not found`, put your `PATH` in `~/.zprofile` (scripts run in a login shell, so `~/.zshrc` isn't read). For Homebrew, for example, add `eval "$(/opt/homebrew/bin/brew shellenv)"` to `~/.zprofile`
- To test under the same conditions, run `zsh -l -c '<script>'` in Terminal
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

If Nonet says it couldn't load the settings file because it was damaged, it started with the default settings. The original file is kept, under the name shown in the notice, in the same folder (`~/Library/Application Support/Nonet/`). If you exported your profiles, you can bring them back with **Import…**. To clear the notice, choose **Dismiss Notice** from the Nonet menu.

### Resetting your settings

Quit Nonet, move `~/Library/Application Support/Nonet/` to the Trash, and open Nonet again. It starts as if it were opened for the first time. The days left in your trial and your registration stay as they were.

## Uninstalling

1. On the General tab of Settings, turn off **Open at login**
2. If you'll use your license on another Mac, keep a copy of your license key
3. Choose **Quit Nonet** from the Nonet menu
4. Move `Nonet` from the Applications folder to the Trash
5. Delete these files and folders:
   - `~/Library/Application Support/Nonet/` (settings and the trial record)
   - `~/Library/Preferences/com.iam74k4.Nonet.plist` (the trial record and your license key)
   - `~/Library/Caches/com.iam74k4.Nonet/` (temporary update files)
6. In Keychain Access, search for `com.iam74k4.Nonet.license.trial` and delete the item it finds (the trial record)
7. In **System Settings › Privacy & Security › Accessibility**, select Nonet and click − to remove it. Running `tccutil reset Accessibility com.iam74k4.Nonet` in Terminal does the same
