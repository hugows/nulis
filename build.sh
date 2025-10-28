#!/bin/bash

set -e

echo "Building nulis..."
zig build-exe nulis.zig

echo "Copying to ~/bin/..."
mkdir -p ~/bin
cp nulis ~/bin/

echo "Done! nulis installed to ~/bin/nulis"
echo "Make sure ~/bin is in your PATH"
