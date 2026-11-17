<div align="center">

<img src="docs/icon.png" width="128" alt="Little Companion icon: a pixel-art beagle sitting">

# Little Companion

**A tiny pixel-art dog — or bird — that lives on your Mac's screen, and minds its own business.**

[**Download for macOS**](https://github.com/XclaimR/Little-Companion/releases/latest) · macOS 14 Sonoma or later · Apple silicon & Intel · free and open source

<img src="docs/hero.gif" width="900" alt="A beagle trots across the desktop, wags, jumps and sits facing you, while a shiba naps in a bed beside the kennel">

</div>

Little Companion isn't a game and it isn't a to-do list with a mascot. There's nothing to feed on a timer, no notifications, and nothing to keep alive. It's closer to having a real dog asleep in the corner of the room while you work, or a bird perched on the edge of your screen. A dog naps, wanders off to sniff its toys, chases a ball for a minute, follows your cursor when it's curious, and sometimes just sits and looks at you, wagging its tail. A bird hops, preens and flutters up to sit on top of your windows.

It lives on the desktop layer, under your windows. It never steals focus, never blocks a click and makes no sound. You can forget it's there, and that's the point.

## Watch the film

https://github.com/user-attachments/assets/ea401cf8-5b84-4d99-8e57-911f039d2d7b



*A Little Company: one workday with Ollie (and a visit from Mango), 46 seconds with sound.*

## Meet the dogs

Each dog has its own hidden personality: playful or lazy, affectionate or independent, curious, energetic, a bit clumsy. You find it out by watching. Pick one from the 🐾 menu. You can switch whenever you like, and each pet remembers its own life. One pet lives on your desktop at a time.

| <img src="docs/dog-ollie.gif" width="150" alt="Ollie the beagle"> | <img src="docs/dog-biscuit.gif" width="150" alt="Biscuit the shiba"> | <img src="docs/dog-mochi.gif" width="150" alt="Mochi the fluffy white pup"> | <img src="docs/dog-bean.gif" width="150" alt="Bean the dachshund"> | <img src="docs/dog-pepper.gif" width="150" alt="Pepper the border collie"> |
|:---:|:---:|:---:|:---:|:---:|
| **Ollie**<br>beagle | **Biscuit**<br>shiba | **Mochi**<br>fluffy white pup | **Bean**<br>dachshund | **Pepper**<br>border collie |

## Meet the birds

Birds live in a tall tree at the right of the screen, with a birdhouse on the trunk, a swing, a bell, and seed and water dishes at its foot. Unlike the dogs, they fly.

| <img src="docs/bird-mango.gif" width="150" alt="Mango the cockatiel"> | <img src="docs/bird-pearl.gif" width="150" alt="Pearl the lutino cockatiel"> | <img src="docs/bird-kiwi.gif" width="150" alt="Kiwi the budgie"> | <img src="docs/bird-sunny.gif" width="150" alt="Sunny the sun conure"> |
|:---:|:---:|:---:|:---:|
| **Mango**<br>cockatiel | **Pearl**<br>lutino cockatiel | **Kiwi**<br>budgie | **Sunny**<br>sun conure |

- **Perching on your windows.** A bird sometimes flies up and sits on the top edge of an app window, if there's room above it. It never sits over your work.
- **Riding along.** Drag that window and the bird rides with it, wobbling to keep its balance. Drag it hard and it flaps off.
- **Falling.** Close the window and the startled bird drops, flaps, and flies off somewhere else. Minimise it and the bird just flies away calmly.
- **A cockatiel's crest shows its mood**: up when excited or startled, flat when relaxed.
- **Bird life**: hopping and pecking along the floor, preening, stretching a wing, eating seed, splashing in the water dish, swinging, ringing the bell, napping fluffed up on a branch, and sleeping the night in its birdhouse.

## Things you'll catch the dogs doing

<img src="docs/moments.png" width="900" alt="Ollie: napping belly-up, carrying a ball, shaking a plush toy, sitting facing you, scratching an ear, jumping, after a tumble, sitting facing away">

- **Sleeping** in their bed, curled up, sprawled or belly-up, with little z's drifting up. Each dog has a favourite position, and twitches when dreaming.
- **Playing**: chasing and pouncing on the ball, carrying toys around, shaking the plush, tossing the rope in the air.
- **Noticing you**: a glance at the cursor, turning to face it, or trotting after it, depending on the dog's mood and personality.
- **Wagging** when they're happy, more when they're looking at you.
- **Grooming**: licking a paw, scratching an ear.
- **Zoomies**, jumps, the odd stumble if they're clumsy, and a sheepish look back afterwards.
- **Heading into the kennel** when your Mac is working hard, so they're out of the way, and coming back out once it's calm.

## Install

1. Download **LittleCompanion-x.y.z.zip** from the [latest release](https://github.com/XclaimR/Little-Companion/releases/latest) and open it.
2. Drag **Little Companion** into your **Applications** folder and open it.
3. The first time, macOS may say it can't check the app for malicious software, because the app isn't notarized by Apple. Click **Done**, then open **System Settings › Privacy & Security**, scroll down and click **Open Anyway** next to Little Companion. You only need to do this once.

Your pet appears at the bottom of the screen, just above the Dock. Everything else is in the 🐾 menu-bar icon:

- **Change pet**: Dogs ▸ Ollie, Biscuit, Mochi, Bean, Pepper · Birds ▸ Mango, Pearl, Kiwi, Sunny.
- **Hide for an hour**: out of sight for a screen share or a demo. Your pet keeps living meanwhile.
- **Open at login**: so your pet is there every morning.
- **Quit**: your pet's life is saved and picks up where it left off.

To uninstall, quit from the 🐾 menu and drag the app to the Trash. Saved pets live in `~/Library/Application Support/LittleCompanion` if you want to remove them too.

## FAQ

**Will it slow my Mac down?**
No. It's native Swift and Core Animation, at about 0.6% CPU while walking and close to zero while asleep. When your Mac is busy, the dog goes into its kennel, or the bird into its birdhouse.

**Does it collect any data or go online?**
No. There's no network code at all. Everything stays in one file on your Mac.

**Can I pick it up, drag it or tell it what to do?**
No, on purpose. It's a little living thing, not a toy you control. Clicking near a sleeping pet may wake it, and it notices your cursor, but it decides for itself.

**Does the bird need any permissions to sit on my windows?**
No. macOS tells every app where windows are, without any permission. The bird never sees what's inside them.

**It hasn't moved for ages.**
It's probably asleep. Pets sleep a lot, especially at night and after lunch.

## Build from source

You need macOS 14 or later and the Xcode Command Line Tools (Swift 6).

```sh
git clone https://github.com/XclaimR/Little-Companion.git
cd Little-Companion
swift run -c release LittleCompanion
```

To make the double-clickable app and a zip for a release:

```sh
scripts/package.sh v0.2.0     # dist/Little Companion.app and dist/LittleCompanion-v0.2.0.zip
```

### For developers

- `swift test` runs the behaviour engine's tests. `swift run -c release simrun 4 24 1` simulates 4 dogs for 24 hours and checks invariants.
- `LC_DEBUG=1` adds an overlay and a Test menu. `LC_SPEED=4` speeds time up. `LC_DEMO=1` runs a scripted tour. `LC_TOP=1` draws above your windows, for recording.
- The art is generated, not hand-pasted. `python3 tools/art/ollie_sheet.py tools/art <breed>` rebuilds a dog's sprite sheet; `python3 tools/art/bird_sheet.py tools/art` rebuilds the birds. `python3 tools/art/readme_media.py` rebuilds the pictures in this README.
- [DESIGN.md](DESIGN.md) covers the design, how the behaviour engine thinks, and the roadmap.

## Contributing

Ideas, bug reports and pull requests are welcome. Please open an issue first for anything big. The one rule: nothing that makes a pet demand attention.

## License

[MIT](LICENSE) © 2026 Nishanth Korupolu
