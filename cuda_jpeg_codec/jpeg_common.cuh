#pragma once

#include <algorithm>
#include <stdio.h>
#include <iostream>
#include <fstream>
//#include <string.h>
//#include <math.h>

#include <cuda_runtime.h>
#include <npp.h>
#include <nppi_compression_functions.h>
#include "Exceptions.h"
//#include <device_launch_parameters.h>
//#include <device_functions.h>
#include <helper_cuda.h>
//#include <helper_functions.h>
#include <helper_string.h>

// //处理的源图像大小
// #define IMG_WIDTH_MAX 4096s
// #define IMG_HEIGHT_MAX 4096
// #define IMG_BUFFER_SIZE_MAX 16777216 //4096*4096
// #define CHANNEL 3 //1 or 3

//编译条件
#define DEBUG_MEASURE_KERNEL_TIME //测量GPU时间
//#define ENABLE_IMAGE_SCALING //图像缩放支持
#define ONLY_IMAGE_COMPRESSION //仅开启图像压缩编码(特别优化,减少了冗余计算及显存开辟)


//安全释放资源
#define free_s(p) if(p!=NULL){free(p);p=NULL;}
#define delete_s(p) if(p!=NULL){delete p;p=NULL;}
#define deleteA_s(p) if(p!=NULL){delete[] p;p=NULL;}

/*--------------------常用标记数据段--------------------*/
#define FF    0x0FF  //标记段的标记 0xff=255

//帧开始标记，Start of Frame，非层次哈夫曼编码
#define SOF0  0x0C0  //基线离散余弦变换
#define SOF1  0x0C1  //扩展顺序离散余弦变换
#define SOF2  0x0C2  //递进离散余弦变换
#define SOF3  0x0C3  //空间顺序无损

//帧开始标记，Start of Frame，层次哈夫曼编码
#define SOF5  0x0C5  //差分离散余弦变换
#define SOF6  0x0C6  //差分层次离散余弦变换
#define SOF7  0x0C7  //差分空间无损

//帧开始标记，Start of Frame，非层次算术编码	    
#define EJPG  0x0C8  //为JPEG扩展保留
#define SOF9  0x0C9  //扩展顺序离散余弦变换
#define SOF10 0x0CA  //递进离散余弦变换
#define SOF11 0x0CB  //差分空间无损

//帧开始标记，Start of Frame，层次算术编码
#define SOF13 0x0CD  //差分离散余弦变换
#define SOF14 0x0CE  //差分层次离散余弦变换
#define SOF15 0x0CF  //递进离散余弦变换

#define DAC   0x0CC  //算术编码表
#define DHT   0x0C4  //哈夫曼表

#define RST0  0x0D0  //差分编码累计复位，D0-D7共8个
#define RST7  0x0D7  //差分编码累计复位，D0-D7共8个
#define SOI   0x0D8  //图像开始
#define EOI   0x0D9  //图像结束
#define SOS   0x0DA  //扫描开始
#define DQT   0x0DB  //量化表
#define DNL   0x0DC  //线数
#define DRI   0x0DD  //差分编码累计复位的间隔
#define DHP   0x0DE  //层次级数
#define EXP   0x0DF  //展开参考图像

#define APP0  0x0E0  //应用保留标记,E0-EE共15个
#define JPG0  0x0F0  //为JPEG扩展保留，F0-FD共14个
#define COM   0x0FE  //注释
#define EC    0x000  //转义符,表示0XFF是图像流的组成部分,需要译码(将0xFF00当做0xFF而不是特殊标记符)
#define TEM   0x001  //算术编码中作临时之用
#define RES   0x002  //保留，02-BF共189个


/*--------------------jpeg数据结构定义--------------------*/

//图片头
struct FrameHeader
{
	unsigned char nSamplePrecision;             //采样精度
	unsigned short nHeight;						//图像高度
	unsigned short nWidth;						//图像宽度
	unsigned char nComponents;					//颜色分量数(1:灰度图,3:YCbCr,4:CMYK)
	unsigned char aComponentIdentifier[3];		//颜色分量ID,1＝Y, 2＝Cb, 3＝Cr, 4＝I, 5＝Q
	unsigned char aSamplingFactors[3];			//颜色分量采样系数,0-3位:垂直采样系数,4-7位:水平采样系数
	unsigned char aQuantizationTableSelector[3];//使用的量化表ID
};

//扫描头
struct ScanHeader
{
	unsigned char nComponents;               //颜色分量数
	unsigned char aComponentSelector[3];     //选择的颜色分量ID
	unsigned char aHuffmanTablesSelector[3]; //选择的哈夫曼表ID
	unsigned char nSs;                       //固定值 0x00 谱选择开始,0
	unsigned char nSe;                       //固定值 0x3F 谱选择结束,63
	unsigned char nA;                        //固定值 0x00 逐渐逼近bit高低位,nAh=nA>>4,nAl=nA&0x0F
};

//量化表
struct QuantizationTable
{
	unsigned char nPrecisionAndIdentifier;//0-3位:ID,4-7位:精度(0:8位,1:16位),一般有2张,最多4张,取值0-3
	unsigned char aTable[64];             //表项(当精度为16位时,此字段有128Bytes)
};

//霍夫曼编码表
struct HuffmanTable
{
	unsigned char nClassAndIdentifier;//0-3位:ID,4-7位:表类型(0:DC直流,1:AC交流),一般有4个表:亮度的DC和AC,色度的DC和AC
	unsigned char aCodes[16];         //位表,这16个数的和应该≤256
	unsigned char aTable[256];        //值表,等于表头16个数的和
};

// 标准的静态编解码表（参见JPEG标准部分K.3）
enum StaticTable {
	ZIGZAG,             //Z字形扫描表64
	APP0_TAG,           //APP0应用程序标记段14
	STD_Y_QT,           //标准亮度信号量化表64
	STD_UV_QT,          //标准色差信号量化表64
	STD_DC_Y_NRCODES,   //霍夫曼Y分量DC位表16
	STD_DC_Y_VALUES,    //霍夫曼Y分量DC值表12
	STD_DC_UV_NRCODES,  //霍夫曼UV分量DC位表16
	STD_DC_UV_VALUES,   //霍夫曼UV分量DC值表12
	STD_AC_Y_NRCODES,   //霍夫曼Y分量AC位表16
	STD_AC_Y_VALUES,    //霍夫曼Y分量AC值表162
	STD_AC_UV_NRCODES,  //霍夫曼UV分量AC位表16
	STD_AC_UV_VALUES,   //霍夫曼UV分量AC值表162
};

namespace jpeg_common {

	/**
	*@brief 编码后的图像写入文件
	*@param output_fname 输出文件名
	*@pDstJpeg 目标数据
	*@nOutputLenth 数据长度
	*/
	void WriteJpeg(std::string &output_fname, unsigned char *pDstJpeg, int &nOutputLenth);

	/**
	*@brief 获取标准编解码表
	@param tableName 表名,根据StaticTable
	*/
	unsigned char* getStaticTable(int tableName);

	/**
	*@brief 根据编码质量更改量化表(默认表质量为50)
	@param quality 编码质量0-100
	*/
	void setQTByQuality(int nQualityFactor);

	/**
	*@brief 获取标准编解码表字节长度/表大小(sizeof(unsigned char)=1)
	*@param tableName 表名,根据StaticTable
	*@return sizeof(table),等价于sizeof(table)/sizeof(unsigned char)
	*/
	int getStaticTableLenth(int tableName);

	/**
	*@brief 检查是否是有效的JPEG文件
	*/
	bool isValidJpeg(unsigned char *pJpegData, int &nPos, int nInputLength);

	/**
	*@brief 读取高-低字节流
	*@return 返回字符反转后的序列
	*/
	template<class T>
	T readBigEndian(const unsigned char *pData);

	/**
	*@brief 写入高-低字节流,反转value中的元素并复制到pData
	*/
	template<class T>
	void writeBigEndian(unsigned char *pData, T value);

	/**
	*@brief 返回(x + d - 1) / d,若返回-1代表除数非法.
	*/
	int DivUp(int x, int d);

	/**
	*@brief 读取并步进指针
	*@return 读取的序列
	*/
	template<typename T>
	T readAndAdvance(const unsigned char *&pData);

	/**
	*@brief 写入(反转nElement中的元素并复制到pData)并步进指针
	*/
	template<typename T>
	void writeAndAdvance(unsigned char *&pData, T nElement);

	/**
	*@brief 下一个标记
	*@return -1为达到结尾
	*/
	int nextMarker(const unsigned char *pData, int &nPos, int nLength);

	/**
	*@brief 写入标记码
	*@param nMarker 标记码
	*/
	void writeMarker(unsigned char nMarker, unsigned char *&pData);

	/**
	*@brief 写入JFIF(JPEG文件交换格式)标记段
	*/
	void writeJFIFTag(unsigned char *&pData);

	/**
	*@brief 读取图片头信息
	*@param header 接收图片头信息
	*/
	void readFrameHeader(const unsigned char *pData, FrameHeader &header);

	/**
	*@brief 写入图片信息
	*@param header 准备写入的图片头
	*/
	void writeFrameHeader(const FrameHeader &header, unsigned char *&pData);

	/**
	*@brief 读取Z字形编码扫描头
	@param header 接收扫描头信息
	*/
	void readScanHeader(const unsigned char *pData, ScanHeader &header);

	/**
	*@brief 写入Z字形编码扫描头
	*@param header 要写入的扫描头
	*/
	void writeScanHeader(const ScanHeader &header, unsigned char *&pData);

	/**
	*@brief 读取多个量化表
	*@param pTables 接收多个量化表
	*/
	void readQuantizationTables(const unsigned char *pData, QuantizationTable *pTables);

	/**
	*@brief 写入量化表
	*/
	void writeQuantizationTable(const QuantizationTable &table, unsigned char *&pData);

	/**
	*@brief 写入哈夫曼表
	*@param table 要写入的表
	*/
	void writeHuffmanTable(const HuffmanTable &table, unsigned char *&pData);

	/**
	*@brief 读取多个哈夫曼表
	*@param pTables 接收多个表
	*/
	void readHuffmanTables(const unsigned char *pData, HuffmanTable *pTables);

	/**
	*@brief 读取差分编码累积复位间隔
	*@param nRestartInterval 初始化为-1
	*/
	void readRestartInterval(const unsigned char *pData, int &nRestartInterval);
}

//bpp(bits per pixel),planar平面模式,packed压缩模式
enum PixelFormat {
	PIX_FMT_NV12,			//planar YUV 4:2:0, 12bpp,YYYYUVUV,IOS模式
	PIX_FMT_NV21,			//YYYYVUVUVU,安卓模式
	PIX_FMT_YUVI420,		//也称YU12(与YV12区别YYYYVVUU),YYYYUUVV,安卓模式
	PIX_FMT_GRAY8,			//Y,8bpp
	PIX_FMT_RGB24,			//packed RGB 8:8:8, 24bpp, RGBRGB...
	PIX_FMT_BGR24,			//packed RGB 8:8:8, 24bpp, BGRBGR...
	PIX_FMT_RGBA,			//packed RGBA 8:8:8:8, 32bpp, RGBARGBA...
};
//enum PixelFormat {
//	PIX_FMT_NONE = -1,
//	PIX_FMT_YUV420P,   ///< planar YUV 4:2:0, 12bpp, (1 Cr & Cb sample per 2x2 Y samples)
//	PIX_FMT_YUYV422,   ///< packed YUV 4:2:2, 16bpp, Y0 Cb Y1 Cr
//	PIX_FMT_RGB24,     ///< packed RGB 8:8:8, 24bpp, RGBRGB...
//	PIX_FMT_BGR24,     ///< packed RGB 8:8:8, 24bpp, BGRBGR...
//	PIX_FMT_YUV422P,   ///< planar YUV 4:2:2, 16bpp, (1 Cr & Cb sample per 2x1 Y samples)
//	PIX_FMT_YUV444P,   ///< planar YUV 4:4:4, 24bpp, (1 Cr & Cb sample per 1x1 Y samples)
//	PIX_FMT_YUV410P,   ///< planar YUV 4:1:0,  9bpp, (1 Cr & Cb sample per 4x4 Y samples)
//	PIX_FMT_YUV411P,   ///< planar YUV 4:1:1, 12bpp, (1 Cr & Cb sample per 4x1 Y samples)
//	PIX_FMT_GRAY8,     ///<        Y        ,  8bpp
//	PIX_FMT_MONOWHITE, ///<        Y        ,  1bpp, 0 is white, 1 is black, in each byte pixels are ordered from the msb to the lsb
//	PIX_FMT_MONOBLACK, ///<        Y        ,  1bpp, 0 is black, 1 is white, in each byte pixels are ordered from the msb to the lsb
//	PIX_FMT_PAL8,      ///< 8 bit with PIX_FMT_RGB32 palette
//	PIX_FMT_YUVJ420P,  ///< planar YUV 4:2:0, 12bpp, full scale (JPEG), deprecated in favor of PIX_FMT_YUV420P and setting color_range
//	PIX_FMT_YUVJ422P,  ///< planar YUV 4:2:2, 16bpp, full scale (JPEG), deprecated in favor of PIX_FMT_YUV422P and setting color_range
//	PIX_FMT_YUVJ444P,  ///< planar YUV 4:4:4, 24bpp, full scale (JPEG), deprecated in favor of PIX_FMT_YUV444P and setting color_range
//	PIX_FMT_XVMC_MPEG2_MC,///< XVideo Motion Acceleration via common packet passing
//	PIX_FMT_XVMC_MPEG2_IDCT,
//	PIX_FMT_UYVY422,   ///< packed YUV 4:2:2, 16bpp, Cb Y0 Cr Y1
//	PIX_FMT_UYYVYY411, ///< packed YUV 4:1:1, 12bpp, Cb Y0 Y1 Cr Y2 Y3
//	PIX_FMT_BGR8,      ///< packed RGB 3:3:2,  8bpp, (msb)2B 3G 3R(lsb)
//	PIX_FMT_BGR4,      ///< packed RGB 1:2:1 bitstream,  4bpp, (msb)1B 2G 1R(lsb), a byte contains two pixels, the first pixel in the byte is the one composed by the 4 msb bits
//	PIX_FMT_BGR4_BYTE, ///< packed RGB 1:2:1,  8bpp, (msb)1B 2G 1R(lsb)
//	PIX_FMT_RGB8,      ///< packed RGB 3:3:2,  8bpp, (msb)2R 3G 3B(lsb)
//	PIX_FMT_RGB4,      ///< packed RGB 1:2:1 bitstream,  4bpp, (msb)1R 2G 1B(lsb), a byte contains two pixels, the first pixel in the byte is the one composed by the 4 msb bits
//	PIX_FMT_RGB4_BYTE, ///< packed RGB 1:2:1,  8bpp, (msb)1R 2G 1B(lsb)
//	PIX_FMT_NV12,      ///< planar YUV 4:2:0, 12bpp, 1 plane for Y and 1 plane for the UV components, which are interleaved (first byte U and the following byte V)
//	PIX_FMT_NV21,      ///< as above, but U and V bytes are swapped
//
//	PIX_FMT_ARGB,      ///< packed ARGB 8:8:8:8, 32bpp, ARGBARGB...
//	PIX_FMT_RGBA,      ///< packed RGBA 8:8:8:8, 32bpp, RGBARGBA...
//	PIX_FMT_ABGR,      ///< packed ABGR 8:8:8:8, 32bpp, ABGRABGR...
//	PIX_FMT_BGRA,      ///< packed BGRA 8:8:8:8, 32bpp, BGRABGRA...
//
//	PIX_FMT_GRAY16BE,  ///<        Y        , 16bpp, big-endian
//	PIX_FMT_GRAY16LE,  ///<        Y        , 16bpp, little-endian
//	PIX_FMT_YUV440P,   ///< planar YUV 4:4:0 (1 Cr & Cb sample per 1x2 Y samples)
//	PIX_FMT_YUVJ440P,  ///< planar YUV 4:4:0 full scale (JPEG), deprecated in favor of PIX_FMT_YUV440P and setting color_range
//	PIX_FMT_YUVA420P,  ///< planar YUV 4:2:0, 20bpp, (1 Cr & Cb sample per 2x2 Y & A samples)
//	PIX_FMT_VDPAU_H264,///< H.264 HW decoding with VDPAU, data[0] contains a vdpau_render_state struct which contains the bitstream of the slices as well as various fields extracted from headers
//	PIX_FMT_VDPAU_MPEG1,///< MPEG-1 HW decoding with VDPAU, data[0] contains a vdpau_render_state struct which contains the bitstream of the slices as well as various fields extracted from headers
//	PIX_FMT_VDPAU_MPEG2,///< MPEG-2 HW decoding with VDPAU, data[0] contains a vdpau_render_state struct which contains the bitstream of the slices as well as various fields extracted from headers
//	PIX_FMT_VDPAU_WMV3,///< WMV3 HW decoding with VDPAU, data[0] contains a vdpau_render_state struct which contains the bitstream of the slices as well as various fields extracted from headers
//	PIX_FMT_VDPAU_VC1, ///< VC-1 HW decoding with VDPAU, data[0] contains a vdpau_render_state struct which contains the bitstream of the slices as well as various fields extracted from headers
//	PIX_FMT_RGB48BE,   ///< packed RGB 16:16:16, 48bpp, 16R, 16G, 16B, the 2-byte value for each R/G/B component is stored as big-endian
//	PIX_FMT_RGB48LE,   ///< packed RGB 16:16:16, 48bpp, 16R, 16G, 16B, the 2-byte value for each R/G/B component is stored as little-endian
//
//	PIX_FMT_RGB565BE,  ///< packed RGB 5:6:5, 16bpp, (msb)   5R 6G 5B(lsb), big-endian
//	PIX_FMT_RGB565LE,  ///< packed RGB 5:6:5, 16bpp, (msb)   5R 6G 5B(lsb), little-endian
//	PIX_FMT_RGB555BE,  ///< packed RGB 5:5:5, 16bpp, (msb)1A 5R 5G 5B(lsb), big-endian, most significant bit to 0
//	PIX_FMT_RGB555LE,  ///< packed RGB 5:5:5, 16bpp, (msb)1A 5R 5G 5B(lsb), little-endian, most significant bit to 0
//
//	PIX_FMT_BGR565BE,  ///< packed BGR 5:6:5, 16bpp, (msb)   5B 6G 5R(lsb), big-endian
//	PIX_FMT_BGR565LE,  ///< packed BGR 5:6:5, 16bpp, (msb)   5B 6G 5R(lsb), little-endian
//	PIX_FMT_BGR555BE,  ///< packed BGR 5:5:5, 16bpp, (msb)1A 5B 5G 5R(lsb), big-endian, most significant bit to 1
//	PIX_FMT_BGR555LE,  ///< packed BGR 5:5:5, 16bpp, (msb)1A 5B 5G 5R(lsb), little-endian, most significant bit to 1
//
//	PIX_FMT_VAAPI_MOCO, ///< HW acceleration through VA API at motion compensation entry-point, Picture.data[3] contains a vaapi_render_state struct which contains macroblocks as well as various fields extracted from headers
//	PIX_FMT_VAAPI_IDCT, ///< HW acceleration through VA API at IDCT entry-point, Picture.data[3] contains a vaapi_render_state struct which contains fields extracted from headers
//	PIX_FMT_VAAPI_VLD,  ///< HW decoding through VA API, Picture.data[3] contains a vaapi_render_state struct which contains the bitstream of the slices as well as various fields extracted from headers
//
//	PIX_FMT_YUV420P16LE,  ///< planar YUV 4:2:0, 24bpp, (1 Cr & Cb sample per 2x2 Y samples), little-endian
//	PIX_FMT_YUV420P16BE,  ///< planar YUV 4:2:0, 24bpp, (1 Cr & Cb sample per 2x2 Y samples), big-endian
//	PIX_FMT_YUV422P16LE,  ///< planar YUV 4:2:2, 32bpp, (1 Cr & Cb sample per 2x1 Y samples), little-endian
//	PIX_FMT_YUV422P16BE,  ///< planar YUV 4:2:2, 32bpp, (1 Cr & Cb sample per 2x1 Y samples), big-endian
//	PIX_FMT_YUV444P16LE,  ///< planar YUV 4:4:4, 48bpp, (1 Cr & Cb sample per 1x1 Y samples), little-endian
//	PIX_FMT_YUV444P16BE,  ///< planar YUV 4:4:4, 48bpp, (1 Cr & Cb sample per 1x1 Y samples), big-endian
//	PIX_FMT_VDPAU_MPEG4,  ///< MPEG4 HW decoding with VDPAU, data[0] contains a vdpau_render_state struct which contains the bitstream of the slices as well as various fields extracted from headers
//	PIX_FMT_DXVA2_VLD,    ///< HW decoding through DXVA2, Picture.data[3] contains a LPDIRECT3DSURFACE9 pointer
//
//	PIX_FMT_RGB444LE,  ///< packed RGB 4:4:4, 16bpp, (msb)4A 4R 4G 4B(lsb), little-endian, most significant bits to 0
//	PIX_FMT_RGB444BE,  ///< packed RGB 4:4:4, 16bpp, (msb)4A 4R 4G 4B(lsb), big-endian, most significant bits to 0
//	PIX_FMT_BGR444LE,  ///< packed BGR 4:4:4, 16bpp, (msb)4A 4B 4G 4R(lsb), little-endian, most significant bits to 1
//	PIX_FMT_BGR444BE,  ///< packed BGR 4:4:4, 16bpp, (msb)4A 4B 4G 4R(lsb), big-endian, most significant bits to 1
//	PIX_FMT_GRAY8A,    ///< 8bit gray, 8bit alpha
//	PIX_FMT_BGR48BE,   ///< packed RGB 16:16:16, 48bpp, 16B, 16G, 16R, the 2-byte value for each R/G/B component is stored as big-endian
//	PIX_FMT_BGR48LE,   ///< packed RGB 16:16:16, 48bpp, 16B, 16G, 16R, the 2-byte value for each R/G/B component is stored as little-endian
//
//	//the following 10 formats have the disadvantage of needing 1 format for each bit depth, thus
//	//If you want to support multiple bit depths, then using PIX_FMT_YUV420P16* with the bpp stored seperately
//	//is better
//	PIX_FMT_YUV420P9BE, ///< planar YUV 4:2:0, 13.5bpp, (1 Cr & Cb sample per 2x2 Y samples), big-endian
//	PIX_FMT_YUV420P9LE, ///< planar YUV 4:2:0, 13.5bpp, (1 Cr & Cb sample per 2x2 Y samples), little-endian
//	PIX_FMT_YUV420P10BE,///< planar YUV 4:2:0, 15bpp, (1 Cr & Cb sample per 2x2 Y samples), big-endian
//	PIX_FMT_YUV420P10LE,///< planar YUV 4:2:0, 15bpp, (1 Cr & Cb sample per 2x2 Y samples), little-endian
//	PIX_FMT_YUV422P10BE,///< planar YUV 4:2:2, 20bpp, (1 Cr & Cb sample per 2x1 Y samples), big-endian
//	PIX_FMT_YUV422P10LE,///< planar YUV 4:2:2, 20bpp, (1 Cr & Cb sample per 2x1 Y samples), little-endian
//	PIX_FMT_YUV444P9BE, ///< planar YUV 4:4:4, 27bpp, (1 Cr & Cb sample per 1x1 Y samples), big-endian
//	PIX_FMT_YUV444P9LE, ///< planar YUV 4:4:4, 27bpp, (1 Cr & Cb sample per 1x1 Y samples), little-endian
//	PIX_FMT_YUV444P10BE,///< planar YUV 4:4:4, 30bpp, (1 Cr & Cb sample per 1x1 Y samples), big-endian
//	PIX_FMT_YUV444P10LE,///< planar YUV 4:4:4, 30bpp, (1 Cr & Cb sample per 1x1 Y samples), little-endian
//	PIX_FMT_YUV422P9BE, ///< planar YUV 4:2:2, 18bpp, (1 Cr & Cb sample per 2x1 Y samples), big-endian
//	PIX_FMT_YUV422P9LE, ///< planar YUV 4:2:2, 18bpp, (1 Cr & Cb sample per 2x1 Y samples), little-endian
//	PIX_FMT_VDA_VLD,    ///< hardware decoding through VDA
//
//#ifdef AV_PIX_FMT_ABI_GIT_MASTER
//	PIX_FMT_RGBA64BE,  ///< packed RGBA 16:16:16:16, 64bpp, 16R, 16G, 16B, 16A, the 2-byte value for each R/G/B/A component is stored as big-endian
//	PIX_FMT_RGBA64LE,  ///< packed RGBA 16:16:16:16, 64bpp, 16R, 16G, 16B, 16A, the 2-byte value for each R/G/B/A component is stored as little-endian
//	PIX_FMT_BGRA64BE,  ///< packed RGBA 16:16:16:16, 64bpp, 16B, 16G, 16R, 16A, the 2-byte value for each R/G/B/A component is stored as big-endian
//	PIX_FMT_BGRA64LE,  ///< packed RGBA 16:16:16:16, 64bpp, 16B, 16G, 16R, 16A, the 2-byte value for each R/G/B/A component is stored as little-endian
//#endif
//	PIX_FMT_GBRP,      ///< planar GBR 4:4:4 24bpp
//	PIX_FMT_GBRP9BE,   ///< planar GBR 4:4:4 27bpp, big endian
//	PIX_FMT_GBRP9LE,   ///< planar GBR 4:4:4 27bpp, little endian
//	PIX_FMT_GBRP10BE,  ///< planar GBR 4:4:4 30bpp, big endian
//	PIX_FMT_GBRP10LE,  ///< planar GBR 4:4:4 30bpp, little endian
//	PIX_FMT_GBRP16BE,  ///< planar GBR 4:4:4 48bpp, big endian
//	PIX_FMT_GBRP16LE,  ///< planar GBR 4:4:4 48bpp, little endian
//
//#ifndef AV_PIX_FMT_ABI_GIT_MASTER
//	PIX_FMT_RGBA64BE = 0x123,  ///< packed RGBA 16:16:16:16, 64bpp, 16R, 16G, 16B, 16A, the 2-byte value for each R/G/B/A component is stored as big-endian
//	PIX_FMT_RGBA64LE,  ///< packed RGBA 16:16:16:16, 64bpp, 16R, 16G, 16B, 16A, the 2-byte value for each R/G/B/A component is stored as little-endian
//	PIX_FMT_BGRA64BE,  ///< packed RGBA 16:16:16:16, 64bpp, 16B, 16G, 16R, 16A, the 2-byte value for each R/G/B/A component is stored as big-endian
//	PIX_FMT_BGRA64LE,  ///< packed RGBA 16:16:16:16, 64bpp, 16B, 16G, 16R, 16A, the 2-byte value for each R/G/B/A component is stored as little-endian
//#endif
//	PIX_FMT_0RGB = 0x123 + 4,      ///< packed RGB 8:8:8, 32bpp, 0RGB0RGB...
//	PIX_FMT_RGB0,      ///< packed RGB 8:8:8, 32bpp, RGB0RGB0...
//	PIX_FMT_0BGR,      ///< packed BGR 8:8:8, 32bpp, 0BGR0BGR...
//	PIX_FMT_BGR0,      ///< packed BGR 8:8:8, 32bpp, BGR0BGR0...
//	PIX_FMT_YUVA444P,  ///< planar YUV 4:4:4 32bpp, (1 Cr & Cb sample per 1x1 Y & A samples)
//
//	PIX_FMT_NB,        ///< number of pixel formats, DO NOT USE THIS if you want to link with shared libav* because the number of formats might differ between versions
//};
