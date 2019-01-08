# 基于CUDA加速的JPEG编解码器


## 已完成功能

### 基础
- 图像格式支持:目前支持YUVI420,NV12,NV21

### 编码器
- 支持控制编码质量
- 支持3通道图像压缩编码

### 解码器

---

## 待完善功能
### 基础
- 支持更多图像格式及图像格式间的转换
  
### 编码器
- 支持单通道图像编码
- 支持图像缩放

### 解码器
- TODO

---

## 性能测试

GTX 1050Ti下仅开启图像压缩(减少了冗余判断及内存):
- 3通道4096x4096,90%质量编码:数据上载时间4.1ms,编码时间10.3ms左右,50%质量体积减少一半,时间稍快.

- 3通道1920*1080,90%压缩编码:总体GPU时间3ms以内,编码质量的影响几乎可以忽略.

---

##使用方法
```cpp
CudaJpegEncoder encoder = CudaJpegEncoder(1920, 1080, 3, 90);
encoder.setData(src.data,PixelFormat::PIX_FMT_YUVI420);
encoder.EncodeJpeg();
WriteJpeg(output_fname, encoder.pDstJpeg, encoder.nOutpuLenth);
```
