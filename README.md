# 基于CUDA加速的JPEG编解码器

编码环境
- cuda 10.0(with npp)
- vs2017
- opencv 4.0(for test)

## 已完成功能

### 基础
- 数据输入：3通道24位彩图YUVI420格式数据
- 数据输出：RAM中的最终压缩的24位彩图
- 图像格式支持:目前支持YUVI420,NV12,NV21

### 编码器
- 支持控制编码压缩质量,JPEG图像质量范围为1到100
- 支持大范围内宽度和高度的编码(是否任意未测试)
- 支持3通道彩色图像压缩编码

### 解码器

---

## 待完善功能
### 基础
- 数据输入：1通道8位灰度图/3通道24位彩图 BMP/JPG/YUV数据
- 数据输出：RAM/GPU中的最终压缩/未压缩的8位/24位图像
- 将通道拆分和图像转码迁移到GPU计算
- 支持更多子采样模式：4：4：4,4：2：2
- 支持更多图像格式及图像格式间的转换
  
### 编码器
- 支持单通道图像编码
- 读取/编辑/编写任何EXIF信息
- 支持图像缩放等

### 解码器
- 支持编码器编码图像的解码,包括灰度与彩色
- 支持更多格式的解析

---

## 短期目标
- 在性能提升的前提下将CPU计算迁移到GPU
- GPU上的JPEG编码：输入数据解析(TODO)，颜色转换(TODO)，2D DCT，量化，Zig-zag，AC / DC，DPCM，RLE，霍夫曼编码，字节填充，JFIF格式化
- GPU上JPEG解码(TODO)：JFIF解析，重新启动标记搜索，逆霍夫曼解码，逆RLE，逆DPCM，AC / DC，逆Z字形，逆量化，逆DCT，逆色彩变换，输出格式

---

## 性能测试

GTX 1050Ti下仅开启图像压缩编码(减少了冗余判断及内存):
- 3通道彩图4096x4096,90%质量编码:数据上载时间50ms,编码时间10ms左右,50%质量体积减少一半,时间稍快.

- 3通道彩图1920*1080,90%压缩编码:数据上载时间13ms,编码时间1.8ms左右

---

## 使用方法
```cpp
CudaJpegEncoder encoder = CudaJpegEncoder(1920, 1080, 3, 90);
//encoder.setData(src.data,PixelFormat::PIX_FMT_YUVI420);
encoder.setDataAsync(src.data, PixelFormat::PIX_FMT_YUVI420);//异步版本性能提升40%
encoder.EncodeJpeg();
WriteJpeg(output_fname, encoder.pDstJpeg, encoder.nOutpuLenth);
```

---

## 合作
合作:guobao.v@gmail.com
