// csARM — particles-lib glue.  particles.cpp calls UTIL_IsDedicatedServer(),
// which is engine-layered (defined per game DLL / engine); libparticles must
// not depend upward, so carry a local answer: false = game client path.
bool UTIL_IsDedicatedServer()
{
    return false;
}
