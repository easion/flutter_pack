# flutter_pack
A tool to make developing &amp; distributing linux flutter apps, code taken from https://github.com/ardera/flutterpi_tool.


## Install

```
flutter pub global activate --source git https://github.com/easion/flutter_pack.git
export PATH="$PATH":"$HOME/.pub-cache/bin"
dart pub global list
```

## Remove
```
dart pub global deactivate flutter_pack
```


## Example usage
```
$ flutter_pack help build
$ flutter create hello_world
$ cd hello_world
$ flutter pub get
$ flutter_pack build --arch=arm64 --cpu=rk3399 --release
$ rsync -a --info=progress2 ./build/flutter_assets/ my-pi4:/home/pi/hello_world_app
```
