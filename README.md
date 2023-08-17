# flutter_pack
A tool to make developing &amp; distributing openwrt flutter apps, code taken from https://github.com/ardera/flutterpi_tool.


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

### Build Release version

```
$ flutter_pack help build #show helps
$ flutter create hello_world
$ cd hello_world
$ flutter_pack create # Generate flutter gix platform related code
$ make # Build the release version
$ rsync -a --info=progress2 ./build/*.ipk remote-ip:/opt/apps/
```

## Build Debug version
```
$ flutter pub get
$ flutter_pack build --arch=arm64 --cpu=rk3399 --debug
$ rsync -a --info=progress2 ./build/flutter_assets/ remote-ip:/opt/apps/hello_world_app
```

## VS-Code debug configuration
```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "flutter debug mode",
            "request": "launch",
            "type": "dart",
            "request": "attach",
            "deviceId": "flutter-tester",
            "observatoryUri": "http://192.168.1.136:12345/"
        }
    ]
}
```
