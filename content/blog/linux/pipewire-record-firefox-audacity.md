---
title: "Record Firefox Audio in Audacity with PipeWire"
date: 2026-04-09T12:00:00-06:00
tags: ['linux', 'pipewire', 'audio']
---

This guide shows how to record audio playing in Firefox using
Audacity, with PipeWire as the audio backend. You'll create a virtual
sink to route Firefox audio into Audacity, and use qpwgraph to set up
monitored playback so you can hear what you're recording through your
headset.

## Prerequisites

 - PipeWire (with pipewire-pulse)
 - Audacity
 - qpwgraph

## Create a virtual sink

Create a null sink called `recordbus` that will act as an
intermediate audio bus:

```bash
pactl load-module module-null-sink sink_name=recordbus \
  sink_properties=device.description=recordbus
```

This creates a virtual sink with an associated monitor source
(`recordbus.monitor`). Firefox audio will be routed into this sink,
and Audacity will record from its monitor.

## Route Firefox to the virtual sink

In your PipeWire/PulseAudio volume control (e.g., `pavucontrol`), move
Firefox's output to the `recordbus` sink. Alternatively, you can do
this from the command line once Firefox is playing audio:

```bash
# Find the Firefox sink input indexes
# Look for entries with application.name = "Firefox"
pactl list sink-inputs | grep -B 20 'application.name = "Firefox"' | grep 'Sink Input #'

# Move all Firefox sink inputs to recordbus
pactl list sink-inputs | grep -B 20 'application.name = "Firefox"' \
  | grep 'Sink Input #' | grep -o '[0-9]*' \
  | xargs -I{} pactl move-sink-input {} recordbus
```

## Set the default recording source

Set `recordbus.monitor` as the default source so that Audacity will
pick it up automatically:

```bash
pactl set-default-source recordbus.monitor
```

## Configure Audacity

In Audacity, set the recording device to the generic **PipeWire**
input. Since you've set `recordbus.monitor` as the default source,
Audacity will capture Firefox audio from the virtual sink rather than
your headset microphone.

Hit Record in Audacity and play audio in Firefox. Audacity will
capture the Firefox audio stream.

## Enable silent monitoring with qpwgraph

By default, you won't hear the audio while recording because it's
being routed to the virtual sink instead of your headset. To monitor
the recording through your headset, use qpwgraph to connect
Audacity's monitor outputs to your headset.

Open qpwgraph:

```bash
qpwgraph
```

In the graph, make these connections:

 - `PipeWire ALSA [audacity.bin]:monitor_FL` → your headset's `playback_FL`
 - `PipeWire ALSA [audacity.bin]:monitor_FR` → your headset's `playback_FR`

This routes Audacity's monitor output to your headset so you can hear
what's being recorded in real time.

### Save and activate the patchbay

To make this routing persistent and automatic:

1. In qpwgraph, go to **Patchbay** → **Save** to save the current
   graph connections as a patchbay file.
2. Enable **Patchbay** → **Activated** so that qpwgraph will
   automatically restore these connections whenever the relevant audio
   nodes appear.

With the patchbay activated, whenever Audacity's audio node appears,
qpwgraph will automatically connect its monitor outputs to your
headset. You don't need to manually reconnect each time.

## Summary

The complete audio routing looks like this:

```
Firefox → recordbus (virtual sink)
                ↓
       recordbus.monitor → Audacity (recording input)
                              ↓
              Audacity monitor → Headset (via qpwgraph patchbay)
```

## Restore your default microphone

When you're done recording, restore your normal microphone as the
default source:

```bash
pactl set-default-source alsa_input.usb-YOUR_DEVICE_NAME.analog-stereo
```

Replace the device name with your actual microphone's PulseAudio
source name. You can list available sources with:

```bash
pactl list sources short
```
