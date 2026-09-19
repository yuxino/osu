# Finish after the subtitle window closes

Build 10 lost its subtitle PiP at 15:35:22 UTC. The user confirmed another
window replaced it. Capture ended, but the host's last event was `cloud/finishing`
and its saved state still said it was capturing. The process remained alive.
The source releases PiP/audio before the asynchronous cloud finish, leaving no
background execution assertion during that work. Suspension is the working
explanation; no crash has been established.

Acquire a finite UIKit background task before releasing capture/PiP/audio.
Persist `finishing` with capture and PiP inactive immediately. Keep the existing
eight-second cloud deadline; on success, timeout, cancellation, denied execution
or system expiration, close the socket and save idle state before ending the task.
Repeated close callbacks must not cancel an existing finish, and old expiration
callbacks must not stop a new session.

Use the separate simulator test app with production controller/receiver/client,
authenticated loopback PCM and an in-memory service. Inject the PiP close callback
because the current simulator reports PiP unsupported. Test successful final text,
server timeout, system expiration, denied background time, cancel and restart.
Also open Simulator Settings to background the test app and exercise real UIKit
background tasks with delayed success and an unresponsive service.

This repairs session cleanup. It does not provide two simultaneous PiP windows
or establish real ReplayKit/Bilibili acceptance. The user has taken the phone;
this work must not connect to, install on or operate it.
