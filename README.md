# ServerAutoDemo

ServerAutoDemo records a server demo of every match on a UT99 server.
Recording starts when the match starts, after warmup and the countdown.
It stops 2 seconds after the match ends, so each demo ends on the final scoreboard.
Next to each demo it saves the match result: the players, their scores and the team scores.

It runs on the server only. Players don't download anything.
It needs UT99 469e or newer, and works with or without InstaGibPlus.

## Install

You need the server's files and its **UnrealTournament.ini**.

### 1. Download the newest build

Open [Releases](https://github.com/rxut/ServerAutoDemo/releases) and download the zip of the newest release.

Every build has its own name, for example **ServerAutoDemo_main-1a2b3c4d**.
The release page shows it at the top, and the **.u** file in the zip has the same name.
You need this name in step 3.

### 2. Copy the package

Copy **ServerAutoDemo_main-1a2b3c4d.u** from the zip's **System** folder into your server's **System** folder.

### 3. Add one line to UnrealTournament.ini

Stop the server first.
A running server can save UnrealTournament.ini when it shuts down, and that would undo your change.

Open **System/UnrealTournament.ini**.
Find the line **[Engine.GameEngine]** and add this line under it:

```
ServerActors=ServerAutoDemo_main-1a2b3c4d.ServerAutoDemo
```

Use your build's name from step 1 in place of ServerAutoDemo_main-1a2b3c4d.
Keep **.ServerAutoDemo** at the end.

Don't add it to ServerPackages. Players don't need it.

### 4. Start the server and check it works

Start the server.
It creates **System/ServerAutoDemo.ini** with the settings below.

Play a match to the end.
**System/Demos** now holds the demo (**.dem**) and its match result (**.json**).
The server log shows **ServerAutoDemo: Demo recording started to Demos/...** when a match starts.

## Update to a newer build

1. Download the zip of the newest release.
2. Copy its **.u** file into your server's **System** folder.
3. Stop the server.
4. In **UnrealTournament.ini**, change the name in your ServerActors line to the new build's name.
5. Start the server.

Your settings in ServerAutoDemo.ini stay as they are.
You can delete the old **.u** file.

## Settings

The settings are in **System/ServerAutoDemo.ini**, under **[Settings]**.
Stop the server before you change them.

| Setting | Default | What it does |
|---|---|---|
| DemoPath | `Demos/` | The folder for demos, inside **System**. End it with a slash. The server creates the folder if it's missing. |
| DemoMask | `[%Y_%M_%D_%T]_[%C]_%E` | The demo's file name, built from the codes below. Leave out **.dem**. The server adds it. |
| DemoChar | `_` | Replaces characters that can't be in a file name, such as spaces and dots. |

With the default DemoMask, the server saves a CTF-Face match that starts on 10 November 2026 at 20:15 as **[2026_11_10_2015]_[Unknown]_CTF-Face.dem**.

The codes for DemoMask:

| Code | Becomes |
|---|---|
| %E | The map's file name, for example CTF-Face |
| %F | The map's title |
| %Y | The year |
| %M | The month, two digits |
| %D | The day, two digits |
| %H | The hour, two digits |
| %N | The minute, two digits |
| %S | The second, two digits |
| %T | Hour and minute, for example 2015 |
| %C | The clan tags of the teams (see below) |
| %% | A single % |

Times use the server's clock.

%C looks at the player names when the match starts.
For each team it takes the part of the name all its players share at the start or the end, such as a clan tag.
A team with no shared part gets **Mix**. If more than one team has none, %C becomes **Unknown**. Outside team games it is **FFA**.

## The match result file

Next to each demo the server saves a **.json** file with the same name.
It holds the match as the scoreboard shows it at the end:

- the server name, map, map title and game type
- start and end time, and the length in seconds
- the time limit, frag limit and team score limit
- the team scores
- each player's name, team, score, deaths and ping, and whether it's a bot

The server writes it 2 seconds after the match ends, just before recording stops.
A match that never ends gets a demo but no **.json**. That happens when an admin changes the map mid-match, for example.

## Disk space

A 20-minute 5 vs 5 match makes a demo of about 25 MB.
Delete old demos from **System/Demos** from time to time, or move them off the server.

## Load it as a mutator instead

ServerActors is the better way.
You can also add **ServerAutoDemo_main-1a2b3c4d.ServerAutoDemo** to the server's mutator list, with your build's name.
Map votes and web admin map switches can change the mutator list, and then recording stops.
Use one way, not both.

## For developers: how builds work

Every push to GitHub builds the package on Windows with UT 469e (`.github/workflows/ci.yml`).
A push to a branch makes a package named after the branch and the commit, for example **ServerAutoDemo_main-1a2b3c4d**, and publishes it as a preview release.
A tag makes a package named after the tag, for example **ServerAutoDemo_v2** for the tag v2. Publishing a release for the tag attaches its zip.
Name tags without dots, for example `v2`. A dot can't be in a package name.

The package takes its name from its folder.
The build checks the repo out into a folder with the build's name, and replaces the example name in this README with it.
The settings section **[Settings]** has no package name in it, so settings carry over from build to build.

To build on Windows, put this repo in a folder next to your UT **System** folder and run **Build.bat**.
The folder's name becomes the package name, and the **.u** lands in the **System** folder inside the repo.

On other systems, put the repo next to **System**.
Add **EditPackages=** with the folder's name to the **[Editor.EditorEngine]** section of the ini you build with, then run `ucc make` from **System**.
