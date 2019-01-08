#pragma once
#ifndef JPEG_ENCODER_H
#define JPEG_ENCODER_H

#include "jpeg_common.cuh"
//TODO 相关检查 1和3通道图像要求像素指针与基础数据类型对齐，即pData％sizof（数据类型）== 0
//TODO 内存分配与释放

/*NOTE:
*ROI作为单个NppiSize结构传递，它包含高度和高度,ROI的第一个像素由图像数据指针的位置指定.函数后缀标有R的都支持ROI处理.
*NPP库所有指针都是设备指针(需要cudaMemCpy),相当于CUDA核函数的封装库,可以混合编程.
*临时缓冲区是非结构化的,可以未初始化传给函数.需要用户管理.缓冲区大小通过主机指针返回，因为临时缓冲区的分配是通过CUDA运行时主机代码执行的.
*/



/*--------------------编码器对象--------------------*/
class CudaJpegEncoder
{
public:
	CudaJpegEncoder();
	~CudaJpegEncoder();
	/**
	*@brief 构造函数
	*@param quality 图片编码质量
	*/
	CudaJpegEncoder(int width, int height, int channel, int quality);

public:

	///**
	//*@brief 从文件读取RGB图像
	//*@param file_name 文件路径
	//*/
	//void readImage(const char *file_name);

	///**
	//*@brief 初始化主机源RGB图像
	//*@param pSrcData 原始RGB主机图像
	//*@param nInputLength mWidth * mHeight *mChannel * sizeof(unsigned char);
	//*/
	//void loadImage(unsigned char *pSrcData[3], int nInputLength);

	///**
	//*@brief 加载图片后上载到GPU
	//*/
	//void UploadImage();

	///**
	//*@brief 转为平面YUV格式(平面2平面),设备函数
	//*/
	//void RGB2YUV();

	/**
	*@brief 数据准备:输入YUV图像拆分为3通道并上传GPU
	*@param yuv_data YUV图像数据
	*@param data_size YUV图像长度
	*/
	void setData(Npp8u * yuv_data, int yuv_fmt);

	/**
	*@brief 编码
	*编码结果:数据指针encoder.pDstJpeg,长度encoder.nOutputLenth
	*/
	void EncodeJpeg();



public:
	NppiDCTState* pDCTState;//指向DCT状态结构的指针,必须使用nppiDCTInitAlloc()初始化此结构
	Npp16s *apdDCT[3];//定距设备内存指针,保存DCT系数
	//Npp16s *aphDCT[CHANNEL];//定距锁页主机内存指针,保存DCT系数
	Npp32s aDCTStep[3];//定距分配的间隔(连续行之间的字节数)

	FrameHeader oFrameHeader;//图像头

	ScanHeader oScanHeader;//扫描头
	Npp8u *pdScan;//扫描头缓冲区
	Npp32s nScanLength;//霍夫曼编码后的扫描长度

	QuantizationTable aQuantizationTables[4];//量化表
	Npp8u* pdQuantizationTables;//设备量化表缓冲区64*4

	HuffmanTable aHuffmanTables[4];//霍夫曼表 DC AC x 亮度 色度=4
	HuffmanTable* pHuffmanDCTables;//指向霍夫曼DC表的指针
	HuffmanTable* pHuffmanACTables;//指向霍夫曼AC表的指针
	NppiEncodeHuffmanSpec *apHuffmanDCTableEncode[3];//霍夫曼表缓冲区DC编码
	NppiEncodeHuffmanSpec *apHuffmanACTableEncode[3];//霍夫曼表缓冲区AC编码

	//unsigned char *pSrcData[3];//源图像数据RGB
	//unsigned char *pdSrcData[3];//源图像设备数据RGB

	int nInputLength;//源图像长度
	NppiSize aSrcSize[3];//源图像3通道子图大小,感兴趣区域(ROI)
	Npp8u *apSrcImage[3];//源图像设备缓冲区YUV
	Npp32s aSrcImageStep[3];//定距分配的间隔(连续行之间的字节数)

	unsigned char *pDstJpeg;//目标图像主机数据(写入缓冲区头指针)
	int nOutputLenth;//最终编码主机数据长度
	NppiSize oDstImageSize;//目标图像大小
	Npp8u *apDstImage[3];//目标图像设备缓冲区
	Npp32s aDstImageStep[3];//目标图像定距分配的间隔(连续行之间的字节数)
	NppiSize aDstSize[3];//目标图像3通道子图大小,感兴趣区域(ROI),如果没有缩放则=aSrcSize

	Npp8u *pJpegEncoderTemp;//编码临时设备缓冲区


	int nMCUBlocksH;//水平最大采样系数
	int nMCUBlocksV;//垂直最大采样系数
	int nRestartInterval;//复位间隔

#ifdef ENABLE_IMAGE_SCALING
	float nScaleFactor;//缩放系数
#endif // !ENABLE_IMAGE_SCALING

public:

	//Npp8u* mRGBData;
	unsigned char* mY;//Y通道 host
	unsigned char* mU;//Cb通道 host
	unsigned char* mV;//Cr通道 host

};

#endif // !JPEG_ENCODER_H