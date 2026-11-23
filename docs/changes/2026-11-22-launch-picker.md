# Automatic sign-in on Apple TV

Apple TV already asks who's watching at launch. Settings now lets an unlocked
profile opt into automatic sign-in on this Apple TV. Arc reads the live profile
list before using the saved choice. Deleted profiles and profiles with a PIN
return to the picker. The switch is off and disabled for protected profiles.
Signing out or switching server clears the local UserDefaults choice.

Returning from the background keeps the current profile because the launch
decision runs only while the app model is launching. Plex offers automatic
sign-in that can bypass the PIN. Arc keeps the PIN requirement and follows
server #505.
[Plex Apple TV settings](https://support.plex.tv/articles/settings-plex-for-apple-tv/)

ArcKit decision tests cover fresh launch, resume, automatic selection, deleted
profiles and PIN restrictions. The Linux workspace has no Swift toolchain.
The branch push requests the macOS build, ArcKit tests and the stand-in tvOS
walkthrough with a Settings screenshot. Physical Apple TV and lifecycle behavior
on hardware were not tried.

Arc logs the picker, successful automatic sign-in, and failures without profile
names, identifiers or tokens.
