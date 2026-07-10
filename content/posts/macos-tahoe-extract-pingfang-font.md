+++
title = 'macOS Tahoe 提取苹方字体（OTF / TTF）'
date = 2026-07-10T15:30:00+08:00
tags = [ "macOS", "Font", "Shell", "Python" ]
draft = false
+++

本文记录如何在 **macOS Tahoe（macOS 26）** 上提取系统自带的苹方（PingFang）字体，并分别导出：

* 原始 OTF（无损）
* TrueType TTF（通过 FontTools + cu2qu 转换）

## 一、系统环境

适用于：

* macOS Tahoe（macOS 26）
* Apple Silicon（M 系列）或 Intel Mac

Tahoe 开始，苹方字体不再位于传统的：

```
/System/Library/Fonts/
```

而是作为系统资源（Asset）存放在：

```
/System/Library/AssetsV2/
```

## 二、查找系统中的 PingFang.ttc

直接搜索：

```bash
find /System/Library/AssetsV2 -name "PingFang*.ttc"
```

或者：

```bash
find /System /Library -name "PingFang*.ttc" 2>/dev/null
```

通常会得到类似结果：

```
/System/Library/AssetsV2/.../AssetData/PingFang.ttc
```

复制出来即可：

```bash
cp "/System/Library/AssetsV2/.../PingFang.ttc" .
```

> 建议先复制到当前目录，再进行后续操作。

---

## 三、导出原始 OTF（无损）

系统中的 `PingFang.ttc` 实际上是 **OpenType Collection**。

其中每个成员都是：

* CFF OpenType（OTF）

而不是：

* TrueType（TTF）

因此拆分时应保持原始格式。

使用本文附带的脚本：

```
ttc2otf.sh
```

脚本预览：[ttc2otf.sh](/file/pingfang-tool/ttc2otf-sh/)

即可导出：

```
PingFangSC-Regular.otf
PingFangSC-Medium.otf
PingFangTC-Regular.otf
PingFangHK-Regular.otf
...
```

这种方式不会修改任何轮廓，属于无损提取。

---

## 四、导出 TrueType（TTF）

部分软件（例如部分阅读器、旧软件或仅支持 TrueType 的程序）无法加载 CFF OpenType，此时可以转换为真正的 TrueType。

如果需要生成真正的 TrueType 字体，可以使用本文附带的转换脚本：

```
otf2ttf.py
```

脚本预览：[otf2ttf.py](/file/pingfang-tool/otf2ttf-py/)

该脚本基于：

* FontTools
* cu2qu

完成：

```
CFF
    ↓
cu2qu
    ↓
TrueType(glyf)
```

生成真正包含：

```
glyf
loca
```

的 TrueType 字体。

安装依赖：

```bash
pip install fonttools
```

转换：

```bash
python otf2ttf.py PingFang.ttc
```

默认会输出：

```
PingFang-TTF/
├── PingFangSC-Regular.ttf
├── PingFangSC-Medium.ttf
├── PingFangTC-Regular.ttf
├── PingFangTC-Medium.ttf
├── PingFangHK-Regular.ttf
└── PingFangHK-Medium.ttf
```

---

## 五、验证转换结果

可以使用 FontTools 自带的 `ttx`：

```bash
ttx -l PingFangSC-Regular.ttf
```

如果看到：

```
glyf
loca
```

说明已经是真正的 TrueType。

如果仍然看到：

```
CFF
```

说明仍然是 OpenType，并未完成转换。

---

## 六、脚本与说明

本文用到的脚本：

* [ttc2otf.sh](/file/pingfang-tool/ttc2otf-sh/)：从 `PingFang.ttc` 中拆分出原始 OTF。
* [otf2ttf.py](/file/pingfang-tool/otf2ttf-py/)：将 CFF OpenType 转换为 TrueType TTF。

* OTF 为系统原始字体，建议优先使用。
* TTF 为通过 FontTools + cu2qu 转换得到，更适用于仅支持 TrueType 的软件。
* CFF → TrueType 属于轮廓转换，理论上不是完全无损，但在大多数 UI 和阅读场景下几乎没有可见差异。
* 这些脚本仅用于学习、研究和个人使用，请遵守字体许可协议。
