#pragma once

class Renderer;

// These host-side helpers keep DOSBox headers out of the native application.
// The embedded bridge validates the retail image and owns all guest-memory
// reads/writes; this file only schedules the patch and presents completed data.
bool applyThemeParkWidescreen();
bool presentThemeParkWidescreen(Renderer &renderer);
