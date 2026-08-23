# Sprint 0 — Notes & Findings

Not a re-statement of the Sprint 0 checklist in `SPRINT_PLANNING.md` §11 — this is what actually turned out to be true when I checked this machine and your GitHub org, versus what the plan assumed. Read this as "here's what changed the moment we tried to execute Sprint 0," kept separate from the plan itself so the plan stays a clean reference and this stays a log of reality hitting it.

## Toolchain — most of Sprint 0 was already done

Verified directly on this machine rather than assumed, since it's the same box the prior (Baker Ally) project was built on:

| Tool | Status found |
|---|---|
| Flutter 3.44.5 / Dart 3.12.2 | ✅ Already installed at `C:\src\flutter` |
| Node 24.3.0 / npm 11.4.2 | ✅ Already installed |
| Supabase CLI 2.109.1 | ✅ Installed **and already authenticated** to your account — `supabase projects list` returned your org's existing projects (MindScape, PiCode, ChefAndBaker, LLV) with no login prompt |
| Deno 2.9.1 / Java 17 | ✅ Already installed |
| git | ✅ Installed, identity configured (`Hemin` / `heminkale4@gmail.com`) |
| Android SDK | ⚠️ Present at `C:\Users\hemin\AppData\Local\Android\sdk`, but `flutter doctor` flags two real gaps — see below |
| Xcode | Not applicable yet — correctly deferred to Sprint 14 per your instruction |

**Practical effect:** Sprint 0's "install the toolchain" line item is essentially already satisfied. What's left of Sprint 0 is narrower than the plan implies — two small local fixes plus the account-signup work only you can do.

## Android SDK — two concrete, small gaps (not a full reinstall)

`flutter doctor -v` output:
- `X cmdline-tools component is missing.`
- `X Android license status unknown.`

Fix, whenever you get to it (not urgent — no physical device was plugged in during this check, so nothing was actually blocked by it yet):
1. Install command-line tools only (not full Android Studio, per your original instruction that the emulator/IDE isn't needed): `sdkmanager --install "cmdline-tools;latest"`, or grab them from the Android SDK command-line-tools download page and point `ANDROID_HOME`/`ANDROID_SDK_ROOT` at the existing `C:\Users\hemin\AppData\Local\Android\sdk`.
2. `flutter doctor --android-licenses` — accept the license prompts (this one needs an interactive terminal; I can't run it for you in an automated tool call).

## Source control — the repo didn't exist; it does now, and it's not what I assumed

I initially `git init`'d a fresh local repo in the `Proximity` folder before you told me about `github.com/JKCloudbridge/Proximity`. That would have produced orphaned local history disconnected from your actual GitHub org. Once you gave me the URL:
- Confirmed the remote is reachable (public, no `gh` CLI needed — plain `git`/HTTPS worked).
- Found it already has two branches, `main` and `Sprint-1`, both pointing at a single "Create Readme" commit — i.e. genuinely fresh, nothing to lose.
- Merged my local commits (this planning doc + `migrations/000`–`004`) into `Sprint-1` with `--allow-unrelated-histories` — clean merge, no conflicts, since the file sets didn't overlap with the existing `Readme`.
- Now working directly on `Sprint-1`, tracking `origin/Sprint-1`.

**One thing worth deciding, not yet acted on:** `main` currently has no branch protection that I can see from the outside (no `gh` CLI auth to check rules directly). Worth turning on "require PR before merge" on `main` once there's something real to protect — flagging it now rather than after the first accidental direct push.

## Bundle ID — confirmed

`com.proximity.app`, per your instruction. Matches the same org/app-name convention Baker Ally used (`com.chefsandbakers.app`) — org segment carries the company, app segment is literally `app`. Will be used verbatim in `flutter create --org com.proximity`.

## Supabase — waiting on you, correctly

You said you'll provide the project later, so nothing was created. What this means practically: `migrations/000`–`004` are written and sit ready in the repo, but **unrun and unverified against a real database** until a project exists and gets linked. Everything downstream of "does this SQL actually execute cleanly" (RLS policy correctness, the JWT hook's manual dashboard step, seed data landing right) stays unconfirmed until then — I'm not going to claim Sprint 1 is "done" while that's true; see the Sprint 1 write-up (written on completion, per your instruction) for how that gets closed out.

## Still genuinely blocked on you, not on me

Unchanged from the original Sprint 0 list — these need your identity/payment details, not more of my time: Google Cloud OAuth client, Firebase project, Apple Developer Program enrollment, Razorpay + PayU sandbox signups, Maps/Geocoding billing. None of them block the Sprint 1 code that doesn't touch Sign-In specifically.
