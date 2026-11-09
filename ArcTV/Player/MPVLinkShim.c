// libmpv's tvOS 26 spatial-audio bridge (edde746/mpv-build, MPVSpatial) was compiled with an
// automatic link to the Swift XPC overlay, which the tvOS SDK doesn't provide, so linking stops on
// its "force load" marker. The bridge uses nothing from XPC (the marker is the only missing
// symbol), so an empty stand-in satisfies the linker. Remove it if a later mpv-build drops the
// auto-link.
void _swift_FORCE_LOAD_$_swiftXPC(void) {}
