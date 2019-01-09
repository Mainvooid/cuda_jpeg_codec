#include "jpeg_encoder.cuh"

using namespace std;
using namespace jpeg_common;

CudaJpegEncoder::CudaJpegEncoder()
{
}

CudaJpegEncoder::CudaJpegEncoder(int width, int height, int channel, int quality)
{
	nRestartInterval = -1;//解码及单通道编码时复位间隔参数

	/*--------------------分配DCT状态结构显存--------------------*/
	NPP_CHECK_NPP(nppiDCTInitAlloc(&pDCTState));

	/*--------------------帧头初始化--------------------*/
	memset(&oFrameHeader, 0, sizeof(FrameHeader));
	oFrameHeader.nSamplePrecision = 8;
	oFrameHeader.nComponents = static_cast<unsigned char>(channel);
	oFrameHeader.aComponentIdentifier[0] = 1;//Y
	oFrameHeader.aComponentIdentifier[1] = 2;//Cb
	oFrameHeader.aComponentIdentifier[2] = 3;//Cr
	oFrameHeader.nWidth = static_cast<unsigned short>(width);
	oFrameHeader.nHeight = static_cast<unsigned short>(height);

	if (channel == 1)
	{
		//TODO 支持直接的单通道处理,单通道需要检测是否正确初始化
		// oFrameHeader.aSamplingFactors[0] = 1;
		// oFrameHeader.aQuantizationTableSelector[0] = 0;

		oFrameHeader.aSamplingFactors[0] = 34;
		oFrameHeader.aSamplingFactors[1] = 17;
		oFrameHeader.aSamplingFactors[2] = 17;
		oFrameHeader.aQuantizationTableSelector[0] = 0;
		oFrameHeader.aQuantizationTableSelector[1] = 1;
		oFrameHeader.aQuantizationTableSelector[2] = 1;
	}
	else if (channel == 3)
	{
		oFrameHeader.aSamplingFactors[0] = 34;
		oFrameHeader.aSamplingFactors[1] = 17;
		oFrameHeader.aSamplingFactors[2] = 17;
		oFrameHeader.aQuantizationTableSelector[0] = 0;
		oFrameHeader.aQuantizationTableSelector[1] = 1;
		oFrameHeader.aQuantizationTableSelector[2] = 1;
	}
	else {
		cerr << "暂未支持的输入通道数." << endl;
		return;
	}

	/*--------------------扫描头初始化--------------------*/
	memset(&oScanHeader, 0, sizeof(ScanHeader));
	oScanHeader.nComponents = oFrameHeader.nComponents;
	oScanHeader.nSs = 0;
	oScanHeader.nSe = 63;
	oScanHeader.nA = 0;
	if (oScanHeader.nComponents == 1)
	{
		//TODO 支持直接的单通道处理,单通道需要检测是否正确初始化
		// oScanHeader.aComponentSelector[0] = 1;
		// oScanHeader.aHuffmanTablesSelector[0] = 0;

		oScanHeader.aComponentSelector[0] = 1;
		oScanHeader.aComponentSelector[1] = 2;
		oScanHeader.aComponentSelector[2] = 3;
		oScanHeader.aHuffmanTablesSelector[0] = 0;
		oScanHeader.aHuffmanTablesSelector[1] = 17;
		oScanHeader.aHuffmanTablesSelector[2] = 17;
	}
	else if (oScanHeader.nComponents == 3)
	{
		oScanHeader.aComponentSelector[0] = 1;
		oScanHeader.aComponentSelector[1] = 2;
		oScanHeader.aComponentSelector[2] = 3;
		oScanHeader.aHuffmanTablesSelector[0] = 0;
		oScanHeader.aHuffmanTablesSelector[1] = 17;
		oScanHeader.aHuffmanTablesSelector[2] = 17;
	}
	else {
		cerr << "暂未支持的输入通道数." << endl;
		return;
	}

	/*--------------------量化表初始化--------------------*/
	memset(aQuantizationTables, 0, 4 * sizeof(QuantizationTable));

	//根据编码质量修改量化表
	setQTByQuality(quality);

	//填充2张标准量化表(50%质量分数)
	aQuantizationTables[0].nPrecisionAndIdentifier = 0;
	memcpy(aQuantizationTables[0].aTable,
		getStaticTable(StaticTable::STD_Y_QT),
		getStaticTableLenth(StaticTable::STD_Y_QT));
	aQuantizationTables[1].nPrecisionAndIdentifier = 1;
	memcpy(aQuantizationTables[1].aTable,
		getStaticTable(StaticTable::STD_UV_QT),
		getStaticTableLenth(StaticTable::STD_UV_QT));

	//分配量化表设备缓冲区
	NPP_CHECK_CUDA(cudaMalloc(&pdQuantizationTables, 64 * 4));

	////复制量化表到设备,因标准量化表已经是zigzag order,故而不需要Z形扫描,若量化表为顺序则需要
	//for (int i = 0; i < 4; ++i)
 //   {
 //       Npp8u temp[64];

 //       for (int k = 0; k < 32; ++k)
 //       {
 //           temp[2 * k + 0] = aQuantizationTables[i].aTable[getStaticTable(StaticTable::ZIGZAG)[k + 0]];
 //           temp[2 * k + 1] = aQuantizationTables[i].aTable[getStaticTable(StaticTable::ZIGZAG)[k + 32]];
 //       }

 //       NPP_CHECK_CUDA(cudaMemcpyAsync(pdQuantizationTables + i * 64, temp, 64, cudaMemcpyHostToDevice));
	//}

	NPP_CHECK_CUDA(cudaMemcpyAsync(pdQuantizationTables,
		aQuantizationTables[0].aTable,
		getStaticTableLenth(StaticTable::STD_Y_QT),
		cudaMemcpyHostToDevice));
	NPP_CHECK_CUDA(cudaMemcpyAsync(pdQuantizationTables + getStaticTableLenth(StaticTable::STD_UV_QT),
		aQuantizationTables[1].aTable,
		getStaticTableLenth(StaticTable::STD_UV_QT),
		cudaMemcpyHostToDevice));

	/*--------------------霍夫曼表初始化--------------------*/
	memset(aHuffmanTables, 0, 4 * sizeof(HuffmanTable));

	//初始化表指针
	pHuffmanDCTables = aHuffmanTables;//指向霍夫曼DC表
	pHuffmanACTables = &aHuffmanTables[2];//指向霍夫曼AC表

	//填充Huffman表
	aHuffmanTables[0].nClassAndIdentifier = 0;
	memcpy(aHuffmanTables[0].aCodes, getStaticTable(StaticTable::STD_DC_Y_NRCODES), getStaticTableLenth(StaticTable::STD_DC_Y_NRCODES));
	memcpy(aHuffmanTables[0].aTable, getStaticTable(StaticTable::STD_DC_Y_VALUES), getStaticTableLenth(StaticTable::STD_DC_Y_VALUES));

	aHuffmanTables[1].nClassAndIdentifier = 1;
	memcpy(aHuffmanTables[1].aCodes, getStaticTable(StaticTable::STD_DC_UV_NRCODES), getStaticTableLenth(StaticTable::STD_DC_UV_NRCODES));
	memcpy(aHuffmanTables[1].aTable, getStaticTable(StaticTable::STD_DC_UV_VALUES), getStaticTableLenth(StaticTable::STD_DC_UV_VALUES));

	aHuffmanTables[2].nClassAndIdentifier = 16;
	memcpy(aHuffmanTables[2].aCodes, getStaticTable(StaticTable::STD_AC_Y_NRCODES), getStaticTableLenth(StaticTable::STD_AC_Y_NRCODES));
	memcpy(aHuffmanTables[2].aTable, getStaticTable(StaticTable::STD_AC_Y_VALUES), getStaticTableLenth(StaticTable::STD_AC_Y_VALUES));

	aHuffmanTables[3].nClassAndIdentifier = 17;
	memcpy(aHuffmanTables[3].aCodes, getStaticTable(StaticTable::STD_AC_UV_NRCODES), getStaticTableLenth(StaticTable::STD_AC_UV_NRCODES));
	memcpy(aHuffmanTables[3].aTable, getStaticTable(StaticTable::STD_AC_UV_VALUES), getStaticTableLenth(StaticTable::STD_AC_UV_VALUES));

	//初始化霍夫曼编码表设备缓冲区,oScanHeader.aHuffmanTablesSelector[i]:(0,17,17)->(0,1,1)
	for (int i = 0; i < oFrameHeader.nComponents; ++i)
	{
		NPP_CHECK_NPP(nppiEncodeHuffmanSpecInitAlloc_JPEG(
			pHuffmanDCTables[(oScanHeader.aHuffmanTablesSelector[i] >> 4)].aCodes,
			NppiHuffmanTableType::nppiDCTable,
			&apHuffmanDCTableEncode[i]));

		NPP_CHECK_NPP(nppiEncodeHuffmanSpecInitAlloc_JPEG(
			pHuffmanACTables[(oScanHeader.aHuffmanTablesSelector[i] & 0x0f)].aCodes,
			NppiHuffmanTableType::nppiACTable,
			&apHuffmanACTableEncode[i]));
	}

	/*--------------------计算MCU分配图像显存--------------------*/
	//获取最大采样系数
	nMCUBlocksH = 0;
	nMCUBlocksV = 0;
	for (int i = 0; i < oFrameHeader.nComponents; ++i)
	{
		nMCUBlocksV = std::max(nMCUBlocksV, oFrameHeader.aSamplingFactors[i] & 0x0f);
		nMCUBlocksH = std::max(nMCUBlocksH, oFrameHeader.aSamplingFactors[i] >> 4);
	}

	//分配源图像设备定距内存
	for (int i = 0; i < oFrameHeader.nComponents; ++i)
	{
		NppiSize oBlocks;

		//最小编码单元(Minimum Coded Unit)中的数据单元的尺寸
		NppiSize oBlocksPerMCU = { oFrameHeader.aSamplingFactors[i] >> 4,
								   oFrameHeader.aSamplingFactors[i] & 0x0f };

		//图像宽高应该是MCU的整数倍
		oBlocks.width = (int)ceil((oFrameHeader.nWidth + 7) / 8 *
			static_cast<float>(oBlocksPerMCU.width) / nMCUBlocksH);
		oBlocks.width = DivUp(oBlocks.width, oBlocksPerMCU.width) * oBlocksPerMCU.width;

		oBlocks.height = (int)ceil((oFrameHeader.nHeight + 7) / 8 *
			static_cast<float>(oBlocksPerMCU.height) / nMCUBlocksV);
		oBlocks.height = DivUp(oBlocks.height, oBlocksPerMCU.height) * oBlocksPerMCU.height;

		aSrcSize[i].width = oBlocks.width * 8;
		aSrcSize[i].height = oBlocks.height * 8;

		//在设备上分配定距内存,apdDCT指定分配的设备指针,nPitch分配的间隔,请求分配的宽(apdDCT的类型Npp16s*8*8),高
		size_t nPitch;
		NPP_CHECK_CUDA(cudaMallocPitch(&apdDCT[i], &nPitch, oBlocks.width * 64 * sizeof(Npp16s), oBlocks.height));
		aDCTStep[i] = static_cast<Npp32s>(nPitch);//图像宽度(以像素为单位)x 8 x sizeof(Npp16s)。

		//源图像定距设备缓冲区
		NPP_CHECK_CUDA(cudaMallocPitch(&apdSrcImage[i], &nPitch, aSrcSize[i].width, aSrcSize[i].height));
		aSrcImageStep[i] = static_cast<Npp32s>(nPitch);

		//分配DCT锁页内存(解码时)
		//NPP_CHECK_CUDA(cudaHostAlloc(&aphDCT[i], aDCTStep[i] * oBlocks.height, cudaHostAllocDefault));
	}

	///计算基线霍夫曼编码的临时缓冲区的大小并分配编码缓冲区
	size_t nTempSize = 0;//临时设备缓冲区大小
	NPP_CHECK_NPP(nppiEncodeHuffmanGetSize(aSrcSize[0], oFrameHeader.nComponents,&nTempSize));
	NPP_CHECK_CUDA(cudaMalloc(&pdJpegEncoderTemp, nTempSize));

#ifdef ONLY_IMAGE_COMPRESSION
	//合理分配扫描头大小并分配缓冲区
	Npp32s nScanSize = oFrameHeader.nWidth * oFrameHeader.nHeight * 2;//扫描头缓冲区长度
	nScanSize = nScanSize > (4 << 20) ? nScanSize : (4 << 20);//2048*1024
	NPP_CHECK_CUDA(cudaMalloc(&pdScan, nScanSize));
#else 
	#ifdef ENABLE_IMAGE_SCALING
		//分配目标图像设备定距内存
		nScaleFactor = 1.0f;//TODO 缩放系数(提供接口,并且进一步支持缩放)
		oDstImageSize.width = (int)max(1.0f, floor((float)oFrameHeader.nWidth * nScaleFactor));
		oDstImageSize.height = (int)max(1.0f, floor((float)oFrameHeader.nHeight * nScaleFactor));
	#else 
		oDstImageSize.width = oFrameHeader.nWidth;
		oDstImageSize.height = oFrameHeader.nHeight;
	#endif // !ENABLE_IMAGE_SCALING

	for (int i = 0; i < oFrameHeader.nComponents; ++i) {

		NppiSize oBlocks;
		NppiSize oBlocksPerMCU = { oFrameHeader.aSamplingFactors[i] >> 4 ,
								   oFrameHeader.aSamplingFactors[i] & 0x0f };

		oBlocks.width = (int)ceil((oDstImageSize.width + 7) / 8 *
			static_cast<float>(oBlocksPerMCU.width) / nMCUBlocksH);
		oBlocks.width = DivUp(oBlocks.width, oBlocksPerMCU.width) * oBlocksPerMCU.width;

		oBlocks.height = (int)ceil((oDstImageSize.height + 7) / 8 *
			static_cast<float>(oBlocksPerMCU.height) / nMCUBlocksV);
		oBlocks.height = DivUp(oBlocks.height, oBlocksPerMCU.height) * oBlocksPerMCU.height;

		aDstSize[i].width = oBlocks.width * 8;
		aDstSize[i].height = oBlocks.height * 8;

		size_t nPitch;
		NPP_CHECK_CUDA(cudaMallocPitch(&apDstImage[i], &nPitch, aDstSize[i].width, aDstSize[i].height));
		aDstImageStep[i] = static_cast<Npp32s>(nPitch);
	}

	//合理分配扫描头大小并分配缓冲区
	Npp32s nScanSize = oDstImageSize.width * oDstImageSize.height * 2;//扫描头缓冲区长度
	nScanSize = nScanSize > (4 << 20) ? nScanSize : (4 << 20);//2048*1024
	NPP_CHECK_CUDA(cudaMalloc(&pdScan, nScanSize));
#endif // !ONLY_IMAGE_COMPRESSION

	/*--------------------写JPEG--------------------*/
	NPP_CHECK_CUDA(cudaHostAlloc(&pDstJpeg, nScanSize, cudaHostAllocDefault));

	nOutputLenth = 0;//写入缓冲区长度

	//TODO YUV格式判断后分配//PIX_FMT_YUVI420

	NPP_CHECK_CUDA(cudaHostAlloc(&mY, oFrameHeader.nWidth * oFrameHeader.nHeight, cudaHostAllocDefault));
	NPP_CHECK_CUDA(cudaHostAlloc(&mU, oFrameHeader.nWidth / 2 * oFrameHeader.nHeight / 2, cudaHostAllocDefault));//2:1采样,为Y的1/4大小
	NPP_CHECK_CUDA(cudaHostAlloc(&mV, oFrameHeader.nWidth / 2 * oFrameHeader.nHeight / 2, cudaHostAllocDefault));

	//uint32_t row_bytes = 4096 * 3;
	//NPP_CHECK_CUDA(cudaMalloc(&mRGBData, row_bytes * 4096));
	
	/*--------------------异步流--------------------*/
	//分配及初始化多个stream,主要用于异步内存拷贝
	pStreams = (cudaStream_t *)malloc(3 * sizeof(cudaStream_t));

	for (int i = 0; i < 3; i++)
	{
		NPP_CHECK_CUDA(cudaStreamCreate(&(pStreams[i])));
	}
}


CudaJpegEncoder::~CudaJpegEncoder()
{
	NPP_CHECK_NPP(nppiDCTFree(pDCTState));
	//NPP_CHECK_CUDA(cudaFreeHost(pSrcData));
	//NPP_CHECK_CUDA(cudaFree(pdSrcData));

	NPP_CHECK_CUDA(cudaFree(pdScan));
	NPP_CHECK_CUDA(cudaFree(pdQuantizationTables));
	NPP_CHECK_CUDA(cudaFree(pdJpegEncoderTemp));

	NPP_CHECK_CUDA(cudaFreeHost(mY));
	NPP_CHECK_CUDA(cudaFreeHost(mU));
	NPP_CHECK_CUDA(cudaFreeHost(mV));
	NPP_CHECK_CUDA(cudaFreeHost(pDstJpeg));

	for (int i = 0; i < oFrameHeader.nComponents; ++i)
	{
		NPP_CHECK_NPP(nppiEncodeHuffmanSpecFree_JPEG(apHuffmanDCTableEncode[i]));
		NPP_CHECK_NPP(nppiEncodeHuffmanSpecFree_JPEG(apHuffmanACTableEncode[i]));

		NPP_CHECK_CUDA(cudaFree(apdDCT[i]));
		//NPP_CHECK_CUDA(cudaFreeHost(aphDCT[i]));

		NPP_CHECK_CUDA(cudaFree(apdSrcImage[i]));
		NPP_CHECK_CUDA(cudaFree(apdDstImage[i]));
	}

	for (int i = 0; i < 3; i++)
	{
		NPP_CHECK_CUDA(cudaStreamDestroy(pStreams[i]));
	}

	//异常安全
	//free_s(pHuffmanDCTables);
	//free_s(pHuffmanACTables);
	free_s(pStreams);
	//释放new出的内存
	//deleteA_s(pSrcData);
}

//void CudaJpegEncoder::readImage(const char * file_name)
//{
//	// 打开文件流以读取
//	std::ifstream stream(file_name, std::ios::binary);
//
//	if (!stream.good())
//	{
//		return;
//	}
//	//获取流长度
//	stream.seekg(0, std::ios::end);//移动基地址至文件结束处，偏移为0
//	nInputLength = (int)stream.tellg();//获取指针的当前位置，即文件大小
//	stream.seekg(0, std::ios::beg);
//
//	//分配raw图像RGB数据内存
//	NPP_CHECK_CUDA(cudaHostAlloc(pSrcData, nInputLength, cudaHostAllocDefault));
//
//	//pSrcData = new unsigned char[nInputLength];
//	stream.read(reinterpret_cast<char *>(pSrcData), nInputLength);//读取
//}

//void CudaJpegEncoder::loadImage(unsigned char *pSrcData[3], int nInputLength)
//{
//	this->pSrcData[0] = pSrcData[0];
//	this->pSrcData[1] = pSrcData[1];
//	this->pSrcData[2] = pSrcData[2];
//	////分配raw图像RGB数据内存
//	//NPP_CHECK_CUDA(cudaHostAlloc(&this->pSrcData, nInputLength, cudaHostAllocDefault));
//
//	this->nInputLength = nInputLength;
//}

//void CudaJpegEncoder::UploadImage()
//{
//	//分配显存
//	NPP_CHECK_CUDA(cudaMalloc(pdSrcData, nInputLength));
//	//上载图像
//	NPP_CHECK_CUDA(cudaMemcpy(pdSrcData, pSrcData, nInputLength, cudaMemcpyHostToDevice));
//}

//void CudaJpegEncoder::RGB2YUV()
//{
//
//	NppiSize oSizeROI = { aSrcSize->width,aSrcSize->height };
//	//RGB2YUV 平面2平面
//	//nppiRGBToYUV_8u_P3R(&pdSrcData, aSrcImageStep[0], apSrcImage, aDstImageStep[0], oSizeROI);
//	nppiRGBToYUV420_8u_P3R(pdSrcData, aSrcImageStep[0], apSrcImage, aDstImageStep, oSizeROI);
//	////RGB2YUV 压缩2平面
//	//nppiRGBToYUV_8u_C3P3R(pdSrcData, (int)aSrcImageStep[0], apSrcImage, (int)aSrcImageStep[0], oSizeROI);
//	//nppiRGBToYUV420_8u_C3P3R(pdSrcData, (int)aSrcImageStep[0], apSrcImage, aSrcImageStep, oSizeROI);
//}
//TODO 提供接收YUV图像及数据并处理的方法
void CudaJpegEncoder::setData(Npp8u * yuv_data, int yuv_fmt)
{
#ifdef DEBUG_MEASURE_KERNEL_TIME
	cudaEvent_t start, stop;
	float elapsedTime;
	NPP_CHECK_CUDA(cudaEventCreate(&start));
	NPP_CHECK_CUDA(cudaEventCreate(&stop));
	NPP_CHECK_CUDA(cudaEventRecord(start, 0));//0默认流
#endif // !DEBUG_MEASURE_KERNEL_TIME

	if (!yuv_data)
	{
		return;
	}
	uint32_t    off = 0;
	uint32_t    off_yuv = 0;
	uint32_t    half_h = oFrameHeader.nHeight >> 1;
	uint32_t    half_w = oFrameHeader.nWidth >> 1;

	for (int i = 0; i < oFrameHeader.nHeight; i++)
	{
		NPP_CHECK_CUDA(cudaMemcpy(mY + off, yuv_data + off_yuv, oFrameHeader.nWidth, cudaMemcpyHostToHost));//Y(HxW)复制到mY

		off += oFrameHeader.nWidth;
		off_yuv += oFrameHeader.nWidth;
	}

	switch (yuv_fmt)
	{
	case PixelFormat::PIX_FMT_YUVI420:
	{
		uint32_t uv_size = half_w * half_h;
		off_yuv = oFrameHeader.nWidth * oFrameHeader.nHeight;
		off = 0;

		for (int i = 0; i < half_h; i++)
		{
			//从I420图像拆解UV,YYYYYYYYUUVV,单块U或V的大小为half_w*(half_h/2)
			//memcpy(mU + off, yuv_data + off_yuv, half_w);//跳过Y并把紧接着的俩个U交替复制到mU(分行存储,mU大小half_w*half_h)
			//memcpy(mV + off, yuv_data + off_yuv + uv_size, half_w);//跳过Y和U并把紧接着的俩个V交替复制到mV
			NPP_CHECK_CUDA(cudaMemcpy(mU + off, yuv_data + off_yuv, half_w, cudaMemcpyHostToHost));
			NPP_CHECK_CUDA(cudaMemcpy(mV + off, yuv_data + off_yuv + uv_size, half_w, cudaMemcpyHostToHost));
			off_yuv += half_w;
			off += half_w;
		}

		//for (int i = 0; i < half_h; i++)
		//{
		//	memset(mU + off, 128, half_w);//灰度图像Y=R=G=B,U=V=128
		//	memset(mV + off, 128, half_w);
		//	off_yuv += half_w;
		//	off += half_w;
		//}

		//if (mChannel == 3) {
		//	for (int i = 0; i < half_h; i++)
		//	{
		//		memcpy(mU + off, yuv_data + off_yuv, half_w);//从I420图像拆解UV
		//		memcpy(mV + off, yuv_data + off_yuv + half_size, half_w);
		//		off_yuv += half_w;
		//		off += half_w;
		//	}
		//}
		//else if (mChannel == 1) {
		//	for (int i = 0; i < half_h; i++)
		//	{
		//		memset(mU + off, 128, half_w);//灰度图像Y=R=G=B,U=V=128
		//		memset(mV + off, 128, half_w);
		//		off_yuv += half_w;
		//		off += half_w;
		//	}
		//}
		break;
	}
	case PixelFormat::PIX_FMT_NV12:
	{
		uint8_t*    yuv_ptr;
		uint8_t*    u_ptr;
		uint8_t*    v_ptr;
		off_yuv = oFrameHeader.nWidth * oFrameHeader.nHeight;
		off = 0;

		for (int i = 0; i < half_h; i++)
		{
			yuv_ptr = yuv_data + off_yuv;
			u_ptr = mU + off;
			v_ptr = mV + off;
			for (int j = 0; j < oFrameHeader.nWidth; j += 2)
			{
				*u_ptr++ = *yuv_ptr++;//*u_ptr=*yuv_ptr;*u_ptr++;*yuv_ptr++;
				*v_ptr++ = *yuv_ptr++;//UVUV交替采样
			}
			off_yuv += oFrameHeader.nWidth;
			off += half_w;
		}
		break;
	}
	case PixelFormat::PIX_FMT_NV21:
	{
		uint8_t*    yuv_ptr;
		uint8_t*    u_ptr;
		uint8_t*    v_ptr;
		off_yuv = oFrameHeader.nWidth *  oFrameHeader.nHeight;
		off = 0;

		for (int i = 0; i < half_h; i++)
		{
			yuv_ptr = yuv_data + off_yuv;
			u_ptr = mU + off;
			v_ptr = mV + off;
			for (int j = 0; j < oFrameHeader.nWidth; j += 2)
			{
				*v_ptr++ = *yuv_ptr++;//VUVU交替采样
				*u_ptr++ = *yuv_ptr++;
			}
			off_yuv += oFrameHeader.nWidth;
			off += half_w;
		}
		break;
	}
	default:
		cerr << "暂未支持的编码模式." << endl;
		break;
	}

	if (oFrameHeader.nComponents == 1) {
		//TODO 独立支持单通道图像编码
	}
	else if (oFrameHeader.nComponents == 3) {
		//定距内存对齐
		NPP_CHECK_CUDA(cudaMemcpy2D(apdSrcImage[0],
			aSrcImageStep[0],
			mY,
			oFrameHeader.nWidth,
			oFrameHeader.nWidth,
			oFrameHeader.nHeight,
			cudaMemcpyHostToDevice));
		NPP_CHECK_CUDA(cudaMemcpy2D(apdSrcImage[1],
			aSrcImageStep[1],
			mU,
			oFrameHeader.nWidth / 2,
			oFrameHeader.nWidth / 2,
			oFrameHeader.nHeight / 2,
			cudaMemcpyHostToDevice));
		NPP_CHECK_CUDA(cudaMemcpy2D(apdSrcImage[2],
			aSrcImageStep[2],
			mV,
			oFrameHeader.nWidth / 2,
			oFrameHeader.nWidth / 2,
			oFrameHeader.nHeight / 2,
			cudaMemcpyHostToDevice));
	}

#ifdef DEBUG_MEASURE_KERNEL_TIME

	NPP_CHECK_CUDA(cudaEventRecord(stop, 0));
	NPP_CHECK_CUDA(cudaEventSynchronize(stop));
	NPP_CHECK_CUDA(cudaEventElapsedTime(&elapsedTime, start, stop));
	printf_s("JPEG setData:0 (file:%s, line:%d) elapsed time : %f ms\n", __FILE__, __LINE__, elapsedTime);
	NPP_CHECK_CUDA(cudaEventDestroy(start));
	NPP_CHECK_CUDA(cudaEventDestroy(stop));
#endif // !DEBUG_MEASURE_KERNEL_TIME

}
//TODO 提供接收YUV图像及数据并处理的方法
void CudaJpegEncoder::setDataAsync(Npp8u * yuv_data, int yuv_fmt)
{
#ifdef DEBUG_MEASURE_KERNEL_TIME
	cudaEvent_t start0, stop0;
	cudaEvent_t start1, stop1;
	cudaEvent_t start2, stop2;
	float elapsedTime0, elapsedTime1, elapsedTime2;
	NPP_CHECK_CUDA(cudaEventCreate(&start0));
	NPP_CHECK_CUDA(cudaEventCreate(&start1));
	NPP_CHECK_CUDA(cudaEventCreate(&start2));
	NPP_CHECK_CUDA(cudaEventCreate(&stop0));
	NPP_CHECK_CUDA(cudaEventCreate(&stop1));
	NPP_CHECK_CUDA(cudaEventCreate(&stop2));
	NPP_CHECK_CUDA(cudaEventRecord(start0, pStreams[0]));
	NPP_CHECK_CUDA(cudaEventRecord(start1, pStreams[1]));
	NPP_CHECK_CUDA(cudaEventRecord(start2, pStreams[2]));
#endif // !DEBUG_MEASURE_KERNEL_TIME
	if (!yuv_data)
	{
		return;
	}
	uint32_t    off=0;
	uint32_t    off_yuv=0;
	uint32_t    half_h = oFrameHeader.nHeight >> 1;
	uint32_t    half_w = oFrameHeader.nWidth >> 1;

	for (int i = 0; i < oFrameHeader.nHeight; i++)
	{
		NPP_CHECK_CUDA(cudaMemcpyAsync(mY + off, yuv_data + off_yuv, oFrameHeader.nWidth, cudaMemcpyHostToHost,pStreams[0]));//Y(HxW)复制到mY

		off += oFrameHeader.nWidth;
		off_yuv += oFrameHeader.nWidth;
	}

	switch (yuv_fmt)
	{
	case PixelFormat::PIX_FMT_YUVI420:
	{
		uint32_t uv_size = half_w * half_h;
		off_yuv = oFrameHeader.nWidth * oFrameHeader.nHeight;
		off = 0;

		for (int i = 0; i < half_h; i++)
		{
			//从I420图像拆解UV,YYYYYYYYUUVV,单块U或V的大小为half_w*(half_h/2)
			//memcpy(mU + off, yuv_data + off_yuv, half_w);//跳过Y并把紧接着的俩个U交替复制到mU(分行存储,mU大小half_w*half_h)
			//memcpy(mV + off, yuv_data + off_yuv + uv_size, half_w);//跳过Y和U并把紧接着的俩个V交替复制到mV
			NPP_CHECK_CUDA(cudaMemcpyAsync(mU + off, yuv_data + off_yuv, half_w, cudaMemcpyHostToHost, pStreams[1]));
			NPP_CHECK_CUDA(cudaMemcpyAsync(mV + off, yuv_data + off_yuv + uv_size, half_w, cudaMemcpyHostToHost, pStreams[2]));
			off_yuv += half_w;
			off += half_w;
		}

		//for (int i = 0; i < half_h; i++)
		//{
		//	memset(mU + off, 128, half_w);//灰度图像Y=R=G=B,U=V=128
		//	memset(mV + off, 128, half_w);
		//	off_yuv += half_w;
		//	off += half_w;
		//}

		//if (mChannel == 3) {
		//	for (int i = 0; i < half_h; i++)
		//	{
		//		memcpy(mU + off, yuv_data + off_yuv, half_w);//从I420图像拆解UV
		//		memcpy(mV + off, yuv_data + off_yuv + half_size, half_w);
		//		off_yuv += half_w;
		//		off += half_w;
		//	}
		//}
		//else if (mChannel == 1) {
		//	for (int i = 0; i < half_h; i++)
		//	{
		//		memset(mU + off, 128, half_w);//灰度图像Y=R=G=B,U=V=128
		//		memset(mV + off, 128, half_w);
		//		off_yuv += half_w;
		//		off += half_w;
		//	}
		//}
		break;
	}
	case PixelFormat::PIX_FMT_NV12:
	{
		uint8_t*    yuv_ptr;
		uint8_t*    u_ptr;
		uint8_t*    v_ptr;
		off_yuv = oFrameHeader.nWidth * oFrameHeader.nHeight;
		off = 0;

		for (int i = 0; i < half_h; i++)
		{
			yuv_ptr = yuv_data + off_yuv;
			u_ptr = mU + off;
			v_ptr = mV + off;
			for (int j = 0; j < oFrameHeader.nWidth; j += 2)
			{
				*u_ptr++ = *yuv_ptr++;//*u_ptr=*yuv_ptr;*u_ptr++;*yuv_ptr++;
				*v_ptr++ = *yuv_ptr++;//UVUV交替采样
			}
			off_yuv += oFrameHeader.nWidth;
			off += half_w;
		}
		break;
	}
	case PixelFormat::PIX_FMT_NV21:
	{
		uint8_t*    yuv_ptr;
		uint8_t*    u_ptr;
		uint8_t*    v_ptr;
		off_yuv = oFrameHeader.nWidth *  oFrameHeader.nHeight;
		off = 0;

		for (int i = 0; i < half_h; i++)
		{
			yuv_ptr = yuv_data + off_yuv;
			u_ptr = mU + off;
			v_ptr = mV + off;
			for (int j = 0; j < oFrameHeader.nWidth; j += 2)
			{
				*v_ptr++ = *yuv_ptr++;//VUVU交替采样
				*u_ptr++ = *yuv_ptr++;
			}
			off_yuv += oFrameHeader.nWidth;
			off += half_w;
		}
		break;
	}
	default:
		cerr << "暂未支持的编码模式." << endl;
		break;
	}

	cudaStreamSynchronize(pStreams[0]);
	cudaStreamSynchronize(pStreams[1]);
	cudaStreamSynchronize(pStreams[2]);

	if (oFrameHeader.nComponents == 1) {
		//TODO 独立支持单通道图像编码
	}
	else if (oFrameHeader.nComponents == 3) {
		//定距内存对齐
		NPP_CHECK_CUDA(cudaMemcpy2DAsync(apdSrcImage[0],
									aSrcImageStep[0],
									mY,
									oFrameHeader.nWidth,
									oFrameHeader.nWidth,
									oFrameHeader.nHeight,
									cudaMemcpyHostToDevice));
		NPP_CHECK_CUDA(cudaMemcpy2DAsync(apdSrcImage[1],
									aSrcImageStep[1],
									mU,
									oFrameHeader.nWidth / 2,
									oFrameHeader.nWidth/2,
									oFrameHeader.nHeight / 2,
									cudaMemcpyHostToDevice));
		NPP_CHECK_CUDA(cudaMemcpy2DAsync(apdSrcImage[2],
									aSrcImageStep[2],
									mV,
									oFrameHeader.nWidth / 2,
									oFrameHeader.nWidth/2,
									oFrameHeader.nHeight / 2,
									cudaMemcpyHostToDevice));
	}
	cudaStreamSynchronize(pStreams[0]);
	cudaStreamSynchronize(pStreams[1]);
	cudaStreamSynchronize(pStreams[2]);

#ifdef DEBUG_MEASURE_KERNEL_TIME

	NPP_CHECK_CUDA(cudaEventRecord(stop0, pStreams[0]));
	NPP_CHECK_CUDA(cudaEventSynchronize(stop0));
	NPP_CHECK_CUDA(cudaEventElapsedTime(&elapsedTime0, start0, stop0));
	printf_s("JPEG setData:pStreams[0] (file:%s, line:%d) elapsed time : %f ms\n", __FILE__, __LINE__, elapsedTime0);
	NPP_CHECK_CUDA(cudaEventDestroy(start0));
	NPP_CHECK_CUDA(cudaEventDestroy(stop0));

	NPP_CHECK_CUDA(cudaEventRecord(stop1, pStreams[1]));
	NPP_CHECK_CUDA(cudaEventSynchronize(stop1));
	NPP_CHECK_CUDA(cudaEventElapsedTime(&elapsedTime1, start1, stop1));
	printf_s("JPEG setData:pStreams[1] (file:%s, line:%d) elapsed time : %f ms\n", __FILE__, __LINE__, elapsedTime1);
	NPP_CHECK_CUDA(cudaEventDestroy(start1));
	NPP_CHECK_CUDA(cudaEventDestroy(stop1));

	NPP_CHECK_CUDA(cudaEventRecord(stop2, pStreams[2]));
	NPP_CHECK_CUDA(cudaEventSynchronize(stop2));
	NPP_CHECK_CUDA(cudaEventElapsedTime(&elapsedTime2, start2, stop2));
	printf_s("JPEG setData:pStreams[2] (file:%s, line:%d) elapsed time : %f ms\n", __FILE__, __LINE__, elapsedTime2);
	NPP_CHECK_CUDA(cudaEventDestroy(start2));
	NPP_CHECK_CUDA(cudaEventDestroy(stop2));
#endif // !DEBUG_MEASURE_KERNEL_TIME

}

void CudaJpegEncoder::EncodeJpeg()
{

#ifdef DEBUG_MEASURE_KERNEL_TIME
	cudaEvent_t start, stop;
	float elapsedTime;
	NPP_CHECK_CUDA(cudaEventCreate(&start));
	NPP_CHECK_CUDA(cudaEventRecord(start, 0));//0默认流
#endif // !DEBUG_MEASURE_KERNEL_TIME

#ifdef ENABLE_IMAGE_SCALING
	/*------------------------------缩放支持------------------------------*/
	// 缩放到目标图像大小
	// 只处理420图像
	int aSampleFactor[3] = { 1, 2, 2 };
	for (int i = 0; i < mChannel; ++i)
	{
		NppiSize oBlocksPerMCU = { oFrameHeader.aSamplingFactors[i] >> 4, oFrameHeader.aSamplingFactors[i] & 0x0f };
		NppiSize oSrcImageSize = { (oFrameHeader.nWidth * oBlocksPerMCU.width) / nMCUBlocksH, (oFrameHeader.nHeight * oBlocksPerMCU.height) / nMCUBlocksV };
		NppiRect oSrcImageROI = { 0,0,oSrcImageSize.width, oSrcImageSize.height };
		NppiRect oDstImageROI;
		oDstImageROI.x = 0;
		oDstImageROI.y = 0;
		oDstImageROI.width = oDstImageSize.width / aSampleFactor[i];
		oDstImageROI.height = oDstImageSize.height / aSampleFactor[i];

		NppiInterpolationMode eInterploationMode = NPPI_INTER_SUPER;

		if (nScaleFactor >= 1.f)
			eInterploationMode = NPPI_INTER_LANCZOS;

		NPP_CHECK_NPP(nppiResize_8u_C1R(apSrcImage[i], aSrcImageStep[i], oSrcImageSize, oSrcImageROI,
			apDstImage[i], aDstImageStep[i], oDstImageSize, oDstImageROI, eInterploationMode));
	}
#else
	//重定向
	for (size_t i = 0; i < oFrameHeader.nComponents; i++)
	{
		apdDstImage[i] = apdSrcImage[i];
		aDstImageStep[i] = aSrcImageStep[i];
		aDstSize[i] = aSrcSize[i];

		apdSrcImage[i] = NULL;
		aSrcImageStep[i] = NULL;
	}
#endif // !ENABLE_IMAGE_SCALING



	/*------------------------------前向DCT及量化------------------------------*/
	for (int i = 0; i < oFrameHeader.nComponents; ++i)
	{
		NPP_CHECK_NPP(nppiDCTQuantFwd8x8LS_JPEG_8u16s_C1R_NEW(
			apdDstImage[i],
			aDstImageStep[i],
			apdDCT[i],
			aDCTStep[i],
			pdQuantizationTables + oFrameHeader.aQuantizationTableSelector[i] * 64,
			aDstSize[i],
			pDCTState));
	}

	/*------------------------------霍夫曼编码------------------------------*/
	if (oFrameHeader.nComponents == 1) {
		Npp8u * hpCodesDC[3];
		Npp8u * hpCodesAC[3];
		Npp8u * hpTableDC[3];
		Npp8u * hpTableAC[3];
		for (int i = 0; i < 2; ++i)
		{
			hpCodesDC[i] = pHuffmanDCTables[i].aCodes;
			hpCodesAC[i] = pHuffmanACTables[i].aCodes;
			hpTableDC[i] = pHuffmanDCTables[i].aTable;
			hpTableAC[i] = pHuffmanACTables[i].aTable;
		}
		//TODO 单通道霍夫曼编码
		NPP_CHECK_NPP(nppiEncodeOptimizeHuffmanScan_JPEG_8u16s_P1R(
			*apdDCT,
			aDCTStep[0],
			0,
			oScanHeader.nSs,
			oScanHeader.nSe,
			oScanHeader.nA >> 4,
			oScanHeader.nA & 0x0f,
			pdScan,
			&nScanLength,
			hpCodesDC[0],
			hpTableDC[0],
			hpCodesAC[0],
			hpTableAC[0],
			*apHuffmanDCTableEncode,
			*apHuffmanACTableEncode,
			aDstSize[0],
			pdJpegEncoderTemp));
	}
	else if (oFrameHeader.nComponents == 3) {
		Npp8u * hpCodesDC[3];
		Npp8u * hpCodesAC[3];
		Npp8u * hpTableDC[3];
		Npp8u * hpTableAC[3];
		for (int i = 0; i < 2; ++i)
		{
			hpCodesDC[i] = pHuffmanDCTables[i].aCodes;
			hpCodesAC[i] = pHuffmanACTables[i].aCodes;
			hpTableDC[i] = pHuffmanDCTables[i].aTable;
			hpTableAC[i] = pHuffmanACTables[i].aTable;
		}
		//霍夫曼3通道优化编码
		NPP_CHECK_NPP(nppiEncodeOptimizeHuffmanScan_JPEG_8u16s_P3R(
			apdDCT,
			aDCTStep,
			0,
			oScanHeader.nSs,
			oScanHeader.nSe,
			oScanHeader.nA >> 4,
			oScanHeader.nA & 0x0f,
			pdScan,
			&nScanLength,
			hpCodesDC,
			hpTableDC,
			hpCodesAC,
			hpTableAC,
			apHuffmanDCTableEncode,
			apHuffmanACTableEncode,
			aDstSize,
			pdJpegEncoderTemp));
		//优化非优化似乎没有区别
		 //NPP_CHECK_NPP(nppiEncodeHuffmanScan_JPEG_8u16s_P3R(
		 //	apdDCT,
		 //	aDCTStep,
		 //	0,
		 //	oScanHeader.nSs,
		 //	oScanHeader.nSe,
		 //	oScanHeader.nA >> 4,
		 //	oScanHeader.nA & 0x0f,
		 //	pdScan, &nScanLength,
		 //	apHuffmanDCTableEncode,
		 //	apHuffmanACTableEncode,
		 //	aDstSize,
		 //	pJpegEncoderTemp));
	}
	else {
		cerr << "暂未支持的输入通道数." << endl;
		return;
	}

	/*------------------------------写数据段------------------------------*/
	unsigned char *pDstOutput;//最终编码主机数据(写入缓冲区尾指针)
	pDstOutput = pDstJpeg;//指向头指针
	writeMarker(SOI, pDstOutput);//写SOI,图像开始
	writeJFIFTag(pDstOutput);//写APP0

	writeQuantizationTable(aQuantizationTables[0], pDstOutput);//写量化表
	writeQuantizationTable(aQuantizationTables[1], pDstOutput);

	writeFrameHeader(oFrameHeader, pDstOutput);//写图像头

	writeHuffmanTable(pHuffmanDCTables[0], pDstOutput);//写霍夫曼表
	writeHuffmanTable(pHuffmanACTables[0], pDstOutput);
	writeHuffmanTable(pHuffmanDCTables[1], pDstOutput);
	writeHuffmanTable(pHuffmanACTables[1], pDstOutput);

	writeScanHeader(oScanHeader, pDstOutput);//写扫描头
	NPP_CHECK_CUDA(cudaMemcpy(pDstOutput, pdScan, nScanLength, cudaMemcpyDeviceToHost));//设备扫描头缓冲区数据复制回主机
	pDstOutput += nScanLength;
	writeMarker(EOI, pDstOutput);//图像结束

	nOutputLenth = static_cast<int>(pDstOutput - pDstJpeg);

#ifdef DEBUG_MEASURE_KERNEL_TIME
	NPP_CHECK_CUDA(cudaEventCreate(&stop));
	NPP_CHECK_CUDA(cudaEventRecord(stop, 0));
	NPP_CHECK_CUDA(cudaEventSynchronize(stop));
	NPP_CHECK_CUDA(cudaEventElapsedTime(&elapsedTime, start, stop));
	printf_s("JPEG encode: (file:%s, line:%d) elapsed time : %f ms\n", __FILE__, __LINE__, elapsedTime);
	NPP_CHECK_CUDA(cudaEventDestroy(start));
	NPP_CHECK_CUDA(cudaEventDestroy(stop));
#endif // !DEBUG_MEASURE_KERNEL_TIME
}

