# Spatial Studio

[English](README.md)

Spatial Studio 实时调整 Mac 播放的系统声音。戴上耳机，点「开始处理」，并允许 macOS 的系统音频录制权限。点「恢复原声」退出处理。

- 拖头像旋转视角；光点沿当前画面做二维平移。拖到头像中心松手可放进脑内；按住 Option 拖动只调整距离。
- 滚轮、捏合或右下角按钮可把声场缩放到 40%–2000%。⌘7 / ⌘8 可近看左右耳；选中光点后，按住 ⌘ 点击耳廓表面即可定位。按住 Shift 拖动可平移画面。
- 默认一个光点播放系统立体声。新增光点后可用「独听」单独听某一个。选中光点，可在设置里选择「系统声音」或单独的应用输入，以及左、右或立体声。
- 声场用淡圆轮廓和一条球面环辅助定位。右侧选择俯视、正面、左侧、右侧、后面或仰视；也可按 ⌘1–⌘6，按 ⌘0 回到默认视角。
- 光点音量支持 −72 dB 到 +18 dB，可直接输入数值，精度 0.1 dB。
- 选中光点后，点声场的方向标注即可定位。方位使用 0° 到 360°，180° 为正后方。右键光点可打开所有定位预设，也可以设置、复制或删除光点。左侧的自动移动菜单按环绕、往返、距离分组，并显示当前预设。运行时可调基准方位、基准高度、距离和速度；普通拖动可结束当前光点的自动移动。

## 安装和运行

仅支持 **macOS 26 或更新版本**。需要 Xcode 26 或更新版本及其命令行工具、Python 3 和 OpenSSL（macOS 自带的 LibreSSL 也可使用）。

```sh
git clone https://github.com/ff-fdt/spatial-studio-macos.git
cd spatial-studio-macos
./scripts/build-app.sh
open "dist/Spatial Studio.app"
```

构建脚本会在本机为应用签名。第一次按「开始处理」时，在 macOS 的「屏幕与系统音频录制」中允许 Spatial Studio 访问系统音频。结束时按「恢复原声」或退出应用。界面随应用的系统语言设置显示中英文。

验证：`swift test`。源码采用 [MIT 许可证](LICENSE)，第三方代码和素材保留各自的许可证。

音频引擎基于 [atmos-control](https://github.com/yukij3/atmos-control/tree/3e62fc3/Sources/SpatialEngine)（MIT）。

头模：[Infinite, 3D Head Scan](https://threejs.org/examples/webgl_materials_normalmap.html)，Lee Perry-Smith / Infinite Realities，[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/)，裁切并以哑光灰渲染。

近场补偿使用 [Spatial Audio Framework 的距离变化模型](https://github.com/leomccormack/Spatial_Audio_Framework/blob/18fd5ab/framework/modules/saf_utilities/saf_utility_dvf.c)（ISC），在 Apple 渲染之后应用单声源的双耳修正。
