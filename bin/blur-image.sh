#!/bin/bash

INPUT="$1"
OUTPUT="blurred_edges.png"

# Create a mask
dimensions=$(identify -format "%wx%h" "$INPUT")
convert -size $dimensions canvas:black -fill white -draw "rectangle 15,15 $(identify -format "%[fx:w-15]x%[fx:h-15]" "$INPUT")" mask.png

# Blur the image
convert "$INPUT" -blur 0x8 blurred.png

# Apply the mask
convert blurred.png "$INPUT" mask.png -composite "$OUTPUT"

# Clean up
rm mask.png blurred.png