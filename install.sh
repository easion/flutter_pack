#!/bin/bash


dart format  lib/src/*.dart

dart pub global deactivate flutter_pack
# dart pub global deactivate flutterpi_tool
#flutter pub global activate --source git https://github.com/easion/flutter_pack.git

flutter pub global activate --source path .
dart pub global list

export PATH="$PATH":"$HOME/.pub-cache/bin"
flutter_pack help build
