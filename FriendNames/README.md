# FriendNames

Show your own nicknames for friends in WoW: Forever. Display-only: nobody else sees them.

- Raid and party frames
- Chat (guild, party, raid, say, yell, whispers)
- Guild roster (classic-style window)

Nicknames attach to a Battle.net account (all of a friend's characters) or to a single character.

## Install
Copy the `FriendNames` folder into `World of Warcraft/_classic_beta_/Interface/AddOns/`, then `/reload`.

## Commands
- `/fn set <nickname>`: nickname your target (BattleTag if a BNet friend, else character)
- `/fn char <nickname>`: character-only nickname for your target
- `/fn clear`: remove the nickname from your target
- `/fn alts`: toggle showing the character name beside the nickname in chat/guild
- `/fn list`, `/fn refresh`, `/fn debug`

## Notes
Built for the Forever client (interface 16001). Not yet handled: whisper tab titles, Battle.net friends list, tooltips, nameplates, Communities window.
