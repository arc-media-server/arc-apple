# Person page, collection page, Settings and About

## What changed

**Person page** (`ArcTV/Screens/PersonView.swift`), artwork-led like Home:
- **Top:** their photo in a large circle beside their name, with "Acting · 14 titles in your libraries" under it.
- **Focused title:** a line names the title in focus and their part in it ("Heat (1995) · as Lt. Vincent Hanna"). The background is that title's backdrop, faded at the left and bottom.
- **Rows:** Movies and TV Shows they act in, then Behind the Camera (directing, writing, producing). Each row is newest first, and the focus starts on the first title.

**Collection page:**
- It's laid out as a library's Browse page: the collection's name at the top, a sort pill at the right (Release Date as Arc lists it, or Title), the overview, then the poster grid.
- `CollectionRef` gains the optional `overview` and `images` that collections/{id} already sends.

**Settings:**
- It's laid out as tvOS's own Settings: the profile's picture, name and server centred in the left half, the list on the right.
- A new About row shows the version and opens About, in the same layout. About has:
  - Arc's wordmark, the app version and the TMDB/TheTVDB credit on the left;
  - on the right:
    - this app's version and build, and which player it uses;
    - the server's name, Arc version, API version, address and connection (local or remote);
    - Open Source Licences: mpv, FFmpeg, the Apple TV mpv build, libass, libplacebo, FreeType, HarfBuzz and FriBidi, with their licences.

**Walk-through:** it now takes screenshots of the person page, the library's Collections, a collection, and About. The stand-in answers people/{id} for the made-up cast with the titles that list them.

## Limits

- The TMDB and TheTVDB logos wait on the files (#64); About has the credit's words for now.
- The licences screen names each component and its licence. The full licence texts still need adding before an App Store release.
- The person API has no biography or birth details, so the page has none.

## Logging

Unchanged: pages log failed loads through `loadPage` (warning, error type only).
