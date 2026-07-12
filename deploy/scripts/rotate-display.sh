#!/bin/bash

OUTPUT=$(xrandr | grep " connected" | head -1 | cut -d" " -f1)
xrandr --output "$OUTPUT" --rotate right
