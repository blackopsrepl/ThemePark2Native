#pragma once

// Samples game-specific state exposed by symbols retained in the retail DOS
// executable. The probe is read-only: it establishes safe addresses and real
// runtime values before any widescreen patch is allowed to write guest memory.
void inspectHeimdallEngine();
