# Mushroom Bunny NPC — Roblox Studio

A small voxel-block bunny with a mushroom cap, built in Roblox Studio, that
hops around a home point in short, randomized directions with a nose twitch
and a blink — all generated procedurally, with no animation clips.

## Features
- **Free-roaming hops**: a closed loop of short (≤4 stud) hops in varied
  directions, computed once at load time from randomized waypoints so every
  player sees the same hop schedule.
- **Natural hop physics**: each hop has a crouch before take-off, a parabolic
  arc, and a landing squash, with longer hops arcing higher.
- **Secondary motion**: the mushroom cap and the small back mushrooms are
  heavier than the body, so they lag behind and wobble for a moment after
  every landing (an exponentially-decaying wiggle), instead of moving rigidly
  with the body.
- **Nose twitch**: short, randomly-timed bursts of motion, more frequent
  while the bunny is sitting still than mid-hop.
- **Independent blinking**: the eyes "blink" by sinking back into the head
  on their own offset timers.
- **Performance-aware**: the client skips updating the animation entirely
  once the camera is far enough away that it wouldn't be visible.

## Tools & Skills
Roblox Studio · Luau (Lua) · Procedural animation · Parabolic motion /
easing curves · Secondary motion (wobble/lag) simulation · Rigid-body
grouping with Motor6D + WeldConstraint

## How to Open / Recreate
The two behaviour scripts in `src/` are complete and ready to drop in; the
3D model itself (roughly 2,000 small blocks forming the bunny) isn't
practical to hand-type as a script — see **Model setup** below.

1. Install [Roblox Studio](https://create.roblox.com/).
2. Open a new/empty place.
3. Build or import the `MushroomBunny` model into `Workspace` (see **Model setup**).
4. Copy `src/BunnyAnimator.luau` into `ReplicatedStorage` as a **ModuleScript**
   named `BunnyAnimator`.
5. Copy `src/BunnyClient.luau` into `StarterPlayer > StarterPlayerScripts` as
   a **LocalScript** named `BunnyClient`.
6. Press Play.

### Model setup
The `MushroomBunny` model (Workspace.MushroomBunny) needs:
- A `PrimaryPart` named `Root` (anchored, invisible), with a `Home` **Vector3
  Attribute** set to its resting position.
- Six pivot parts, each driven by a Motor6D, forming this hierarchy:
  `Root → Pivot_Body → Pivot_Head → Pivot_Cap`,
  `Pivot_Head → Pivot_Eyes`, `Pivot_Head → Pivot_Nose`,
  `Pivot_Body → Pivot_Mush`
  (Motor6D names: `Body`, `Head`, `Cap`, `Eyes`, `Nose`, `Mush`).
- Every Motor6D needs a `BaseC0` **CFrame Attribute** set to its rest C0.
- Every visible block welded (`WeldConstraint`) to whichever of the six
  pivots it visually belongs to.

The actual geometry was built interactively in Studio from a voxelized 3D
reference; the cleanest way to reuse it is to export the finished model
(right-click the model → **Save to File**, producing a `.rbxm`) rather than
reconstruct it from a script.

## What I Learned
- Breaking a soft, bouncy character into rigid sub-groups (body / head / cap
  / eyes / nose) connected by a joint hierarchy, so secondary motion (the cap
  wobbling after a landing) can be layered on top of the primary motion
  (the hop) without fighting it.
- Writing a parabolic arc with a proper crouch-anticipation and landing-
  squash, instead of just lerping height — small timing details that make
  procedural motion read as "alive."
- Using a decaying sine wave (`exp(-k·t) * sin(w·t)`) as a cheap, convincing
  physical wobble with no physics engine involved.
- Cost-aware client scripting: skipping animation work entirely once an
  object is too far from the camera to matter.

## Folder Structure
```
bunny-project/
├── README.md
└── src/
    ├── BunnyAnimator.luau   (ModuleScript  → ReplicatedStorage)
    └── BunnyClient.luau     (LocalScript   → StarterPlayer.StarterPlayerScripts)
```
