#include "jpeg_common.cuh"

/*--------------------标准编码表--------------------*/
//详情见enum StaticTable
static unsigned char _ZIGZAG[64] = {
		0,  1,  5,  6, 14, 15, 27, 28,
		2,  4,  7, 13, 16, 26, 29, 42,
		3,  8, 12, 17, 25, 30, 41, 43,
		9, 11, 18, 24, 31, 40, 44, 53,
		10, 19, 23, 32, 39, 45, 52, 54,
		20, 22, 33, 38, 46, 51, 55, 60,
		21, 34, 37, 47, 50, 56, 59, 61,
		35, 36, 48, 49, 57, 58, 62, 63
};

/*APP0 应用程序标记段
2 Bytes | 标记码 0xFFE0
2 Bytes | 数据段长度，包含本字段，但不包括标记码
5 Bytes | 标识符 0x4A46494600，JFIF0的ASCII表示(固定值)
1 Bytes | 主版本号,0x01(版本号表示JFIF的版本1.2)
1 Bytes | 副版本号,0x02
1 Bytes | 图像密度单位0x00(0:无单位,1:点数/英寸,2:点数/厘米)
2 Bytes | X方向像素密度0x00,0x01
2 Bytes | Y方向像素密度0x00,0x01
1 Bytes | 缩略图水平像素数目0x00
1 Bytes | 缩略图垂直像素数目0x00
n Bytes | 缩略图，RGB24位图数据,当上面俩个为0x00时表示无.
*/
static unsigned char _APP0_TAG[14] =
{
	0x4a, 0x46, 0x49, 0x46, 0x00,
	0x01, 0x02,
	0x00,
	0x00, 0x01, 0x00, 0x01,
	0x00, 0x00
};
unsigned char _STD_Y_QT[64] =
{
	16, 11, 10, 16, 24, 40, 51, 61,
	12, 12, 14, 19, 26, 58, 60, 55,
	14, 13, 16, 24, 40, 57, 69, 56,
	14, 17, 22, 29, 51, 87, 80, 62,
	18, 22, 37, 56, 68, 109, 103, 77,
	24, 35, 55, 64, 81, 104, 113, 92,
	49, 64, 78, 87, 103, 121, 120, 101,
	72, 92, 95, 98, 112, 100, 103, 99
};
unsigned char _STD_UV_QT[64] =
{
	17, 18, 24, 47, 99, 99, 99, 99,
	18, 21, 26, 66, 99, 99, 99, 99,
	24, 26, 56, 99, 99, 99, 99, 99,
	47, 66, 99, 99, 99, 99, 99, 99,
	99, 99, 99, 99, 99, 99, 99, 99,
	99, 99, 99, 99, 99, 99, 99, 99,
	99, 99, 99, 99, 99, 99, 99, 99,
	99, 99, 99, 99, 99, 99, 99, 99
};
static unsigned char _STD_DC_Y_NRCODES[16] = { 0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0 };
static unsigned char _STD_DC_Y_VALUES[12] = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 };
static unsigned char _STD_DC_UV_NRCODES[16] = { 0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0 };
static unsigned char _STD_DC_UV_VALUES[12] = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 };
static unsigned char _STD_AC_Y_NRCODES[16] = { 0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 0X7D };
static unsigned char _STD_AC_Y_VALUES[162] =
{
	0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12,
	0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07,
	0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xa1, 0x08,
	0x23, 0x42, 0xb1, 0xc1, 0x15, 0x52, 0xd1, 0xf0,
	0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0a, 0x16,
	0x17, 0x18, 0x19, 0x1a, 0x25, 0x26, 0x27, 0x28,
	0x29, 0x2a, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39,
	0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49,
	0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,
	0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69,
	0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79,
	0x7a, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
	0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98,
	0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7,
	0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6,
	0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3, 0xc4, 0xc5,
	0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4,
	0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xe1, 0xe2,
	0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea,
	0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8,
	0xf9, 0xfa
};
static unsigned char _STD_AC_UV_NRCODES[16] = { 0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 0X77 };
static unsigned char _STD_AC_UV_VALUES[162] =
{
	0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21,
	0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71,
	0x13, 0x22, 0x32, 0x81, 0x08, 0x14, 0x42, 0x91,
	0xa1, 0xb1, 0xc1, 0x09, 0x23, 0x33, 0x52, 0xf0,
	0x15, 0x62, 0x72, 0xd1, 0x0a, 0x16, 0x24, 0x34,
	0xe1, 0x25, 0xf1, 0x17, 0x18, 0x19, 0x1a, 0x26,
	0x27, 0x28, 0x29, 0x2a, 0x35, 0x36, 0x37, 0x38,
	0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48,
	0x49, 0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58,
	0x59, 0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68,
	0x69, 0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78,
	0x79, 0x7a, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
	0x88, 0x89, 0x8a, 0x92, 0x93, 0x94, 0x95, 0x96,
	0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5,
	0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4,
	0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3,
	0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2,
	0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda,
	0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9,
	0xea, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8,
	0xf9, 0xfa
};

namespace jpeg_common {

	namespace device {

	}

	void jpeg_common::WriteJpeg(std::string &output_fname, unsigned char *pDstJpeg,int &nOutputLenth)
	{
		//写结果到文件
		std::ofstream outputFile(output_fname, std::ios::binary|std::ios::out);
		outputFile.write(reinterpret_cast<const char *>(pDstJpeg), nOutputLenth);
	}

	//TODO 使用自定义量化函数生成量化表,更方便调整图像质量
	unsigned char * jpeg_common::getStaticTable(int tableName)
	{
		switch (tableName)
		{
		case (StaticTable::ZIGZAG):
			return _ZIGZAG;
		case (StaticTable::APP0_TAG):
			return _APP0_TAG;
		case (StaticTable::STD_Y_QT):
			return _STD_Y_QT;
		case (StaticTable::STD_UV_QT):
			return _STD_UV_QT;
		case (StaticTable::STD_DC_Y_NRCODES):
			return _STD_DC_Y_NRCODES;
		case (StaticTable::STD_DC_Y_VALUES):
			return _STD_DC_Y_VALUES;
		case (StaticTable::STD_DC_UV_NRCODES):
			return _STD_DC_UV_NRCODES;
		case (StaticTable::STD_DC_UV_VALUES):
			return _STD_DC_UV_VALUES;
		case (StaticTable::STD_AC_Y_NRCODES):
			return _STD_AC_Y_NRCODES;
		case (StaticTable::STD_AC_Y_VALUES):
			return _STD_AC_Y_VALUES;
		case (StaticTable::STD_AC_UV_NRCODES):
			return _STD_AC_UV_NRCODES;
		case (StaticTable::STD_AC_UV_VALUES):
			return _STD_AC_UV_VALUES;
		default:
			std::cerr << "未识别的静态表" << std::endl;
			return NULL;
		}
	}

	void jpeg_common::setQTByQuality(int nQualityFactor) {
		nppiQuantFwdRawTableInit_JPEG_8u(_STD_Y_QT, nQualityFactor);
		nppiQuantFwdRawTableInit_JPEG_8u(_STD_UV_QT, nQualityFactor);
		/*与npp实现等价
		float s;
		if (nQualityFactor < 50)
			s = 5000.0f / nQualityFactor;
		else s = 200.0f - 2 * nQualityFactor;

		for (size_t i = 0; i < 64; i++) {
			// 亮度
			float luminVal = (float)_STD_Y_QT[i];
			luminVal = floor((s * luminVal + 50.0f) / 100.0f);
			if (luminVal < 1)
				luminVal = 1;
			else if (luminVal > 255)
				luminVal = 255;
			_STD_Y_QT[i] = (unsigned char)luminVal;
			// 色度
			float chromaVal = (float)_STD_UV_QT[i];
			chromaVal = floor((s * chromaVal + 50.0f) / 100.0f);
			if (chromaVal < 1)
				chromaVal = 1;
			else if (chromaVal > 255)
				chromaVal = 255;
			_STD_UV_QT[i] = (unsigned char)chromaVal;
		}
		*/
	}

	int getStaticTableLenth(int tableName)
	{
		switch (tableName)
		{
		case (StaticTable::ZIGZAG):
			return sizeof(_ZIGZAG);
		case (StaticTable::APP0_TAG):
			return sizeof(_APP0_TAG);
		case (StaticTable::STD_Y_QT):
			return sizeof(_STD_Y_QT);
		case (StaticTable::STD_UV_QT):
			return sizeof(_STD_UV_QT);
		case (StaticTable::STD_DC_Y_NRCODES):
			return sizeof(_STD_DC_Y_NRCODES);
		case (StaticTable::STD_DC_Y_VALUES):
			return sizeof(_STD_DC_Y_VALUES);
		case (StaticTable::STD_DC_UV_NRCODES):
			return sizeof(_STD_DC_UV_NRCODES);
		case (StaticTable::STD_DC_UV_VALUES):
			return sizeof(_STD_DC_UV_VALUES);
		case (StaticTable::STD_AC_Y_NRCODES):
			return sizeof(_STD_AC_Y_NRCODES);
		case (StaticTable::STD_AC_Y_VALUES):
			return sizeof(_STD_AC_Y_VALUES);
		case (StaticTable::STD_AC_UV_NRCODES):
			return sizeof(_STD_AC_UV_NRCODES);
		case (StaticTable::STD_AC_UV_VALUES):
			return sizeof(_STD_AC_UV_VALUES);
		default:
			std::cerr << "未识别的静态表" << std::endl;
			return -1;
		}
	}

	int getStaticTableSize(int tableName)
	{
		switch (tableName)
		{
		case (StaticTable::ZIGZAG):
			return sizeof(_ZIGZAG) / sizeof(unsigned char);
		case (StaticTable::APP0_TAG):
			return sizeof(_APP0_TAG) / sizeof(unsigned char);
		case (StaticTable::STD_Y_QT):
			return sizeof(_STD_Y_QT) / sizeof(unsigned char);
		case (StaticTable::STD_UV_QT):
			return sizeof(_STD_UV_QT) / sizeof(unsigned char);
		case (StaticTable::STD_DC_Y_NRCODES):
			return sizeof(_STD_DC_Y_NRCODES) / sizeof(unsigned char);
		case (StaticTable::STD_DC_Y_VALUES):
			return sizeof(_STD_DC_Y_VALUES) / sizeof(unsigned char);
		case (StaticTable::STD_DC_UV_NRCODES):
			return sizeof(_STD_DC_UV_NRCODES) / sizeof(unsigned char);
		case (StaticTable::STD_DC_UV_VALUES):
			return sizeof(_STD_DC_UV_VALUES) / sizeof(unsigned char);
		case (StaticTable::STD_AC_Y_NRCODES):
			return sizeof(_STD_AC_Y_NRCODES) / sizeof(unsigned char);
		case (StaticTable::STD_AC_Y_VALUES):
			return sizeof(_STD_AC_Y_VALUES) / sizeof(unsigned char);
		case (StaticTable::STD_AC_UV_NRCODES):
			return sizeof(_STD_AC_UV_NRCODES) / sizeof(unsigned char);
		case (StaticTable::STD_AC_UV_VALUES):
			return sizeof(_STD_AC_UV_VALUES) / sizeof(unsigned char);
		default:
			std::cerr << "未识别的静态表" << std::endl;
			return -1;
		}
	}

	bool jpeg_common::isValidJpeg(unsigned char * pJpegData, int &nPos, int nInputLength)
	{
		int nMarker = nextMarker(pJpegData, nPos, nInputLength);
		return nMarker == SOI ? true : false;

	}

	template<class T>
	T readBigEndian(const unsigned char *pData)
	{
		if (sizeof(T) > 1)
		{
			unsigned char p[sizeof(T)];
			//反转 [first, last) 范围中的元素顺序,并复制到dst
			//JPEG文件格式中，一个字(16位)的存储使用的是Motorola格式，而不是Intel格式.
			//也就是说，一个字的高字节(高8位)在数据流的前面，低字节(低8位)在数据流的后面
			std::reverse_copy(pData, pData + sizeof(T), p);
			return *reinterpret_cast<T *>(p);
		}
		else
		{
			return *pData;
		}
	}

	template<class T>
	void writeBigEndian(unsigned char *pData, T value)
	{
		unsigned char *pValue = reinterpret_cast<unsigned char *>(&value);
		//反转 [first, last) 范围中的元素顺序,并复制到dst
		//JPEG文件格式中，一个字(16位)的存储使用的是Motorola格式，而不是Intel格式.
		//也就是说，一个字的高字节(高8位)在数据流的前面，低字节(低8位)在数据流的后面
		std::reverse_copy(pValue, pValue + sizeof(T), pData);
	}

	int jpeg_common::DivUp(int x, int d)
	{
		if (d != 0) {
			return (x + d - 1) / d;
		}
		else {
			return -1;
		}

	}

	template<typename T>
	T readAndAdvance(const unsigned char *&pData)
	{
		T nElement = readBigEndian<T>(pData);
		pData += sizeof(T);
		return nElement;
	}

	template<typename T>
	void writeAndAdvance(unsigned char *&pData, T nElement)
	{
		writeBigEndian<T>(pData, nElement);
		pData += sizeof(T);
	}

	int jpeg_common::nextMarker(const unsigned char *pData, int &nPos, int nLength)
	{
		unsigned char c = pData[nPos++];

		do
		{
			//0xff=255 u为无符号的意思
			while (c != 0xFFU && nPos < nLength)
			{
				c = pData[nPos++];
			}

			if (nPos >= nLength)
				return -1;

			//c == 0xffu
			c = pData[nPos++];
		} while (c == 0 || c == 0x0FFU);

		return c;
	}

	void jpeg_common::writeMarker(unsigned char nMarker, unsigned char *&pData)
	{
		*pData++ = FF;//写入标记码的标记,指针++
		*pData++ = nMarker;//补充标记码信息,指针++
	}

	void jpeg_common::writeJFIFTag(unsigned char *&pData)
	{
		writeMarker(APP0, pData);//APP0,Application保留标记
		writeAndAdvance<unsigned short>(pData, sizeof(APP0_TAG) + 2);//写入数据段长度,包含本身2字节,但不包括标记码
		memcpy(pData, getStaticTable(StaticTable::APP0_TAG), getStaticTableLenth(StaticTable::APP0_TAG));//写入标记段数据
		pData += sizeof(APP0_TAG);
	}

	void jpeg_common::readFrameHeader(const unsigned char *pData, FrameHeader &header)
	{
		readAndAdvance<unsigned short>(pData);
		header.nSamplePrecision = readAndAdvance<unsigned char>(pData);
		header.nHeight = readAndAdvance<unsigned short>(pData);
		header.nWidth = readAndAdvance<unsigned short>(pData);
		header.nComponents = readAndAdvance<unsigned char>(pData);

		for (int i = 0; i < header.nComponents; ++i)
		{
			header.aComponentIdentifier[i] = readAndAdvance<unsigned char>(pData);
			header.aSamplingFactors[i] = readAndAdvance<unsigned char>(pData);
			header.aQuantizationTableSelector[i] = readAndAdvance<unsigned char>(pData);
		}

	}

	void jpeg_common::writeFrameHeader(const FrameHeader &header, unsigned char *&pData)
	{
		unsigned char aTemp[128];
		unsigned char *pTemp = aTemp;

		writeAndAdvance<unsigned char>(pTemp, header.nSamplePrecision);
		writeAndAdvance<unsigned short>(pTemp, header.nHeight);
		writeAndAdvance<unsigned short>(pTemp, header.nWidth);
		writeAndAdvance<unsigned char>(pTemp, header.nComponents);

		for (int i = 0; i < header.nComponents; ++i)
		{
			writeAndAdvance<unsigned char>(pTemp, header.aComponentIdentifier[i]);
			writeAndAdvance<unsigned char>(pTemp, header.aSamplingFactors[i]);
			writeAndAdvance<unsigned char>(pTemp, header.aQuantizationTableSelector[i]);
		}

		unsigned short nLength = (unsigned short)(pTemp - aTemp);//获取长度

		writeMarker(SOF0, pData);//SOF0,图像帧开始
		writeAndAdvance<unsigned short>(pData, nLength + 2); //写入数据段长度,包含本身2字节,但不包括标记码
		memcpy(pData, aTemp, nLength);//写入标记段数据
		pData += nLength;
	}

	/*TODO 只考虑到了读取到了正确头结构时的处理，
	如果读取到了错误的信息，就会导致segmentfault，
	由于例程只支持彩色jpeg图片的处理，
	所以在读取到扫描头的nComponents字段时判断是否为3，如果不是则说明头部错误。
	*/
	void jpeg_common::readScanHeader(const unsigned char *pData, ScanHeader &header)
	{
		readAndAdvance<unsigned short>(pData);

		header.nComponents = readAndAdvance<unsigned char>(pData);

		for (int i = 0; i < header.nComponents; ++i)
		{
			header.aComponentSelector[i] = readAndAdvance<unsigned char>(pData);
			header.aHuffmanTablesSelector[i] = readAndAdvance<unsigned char>(pData);
		}

		header.nSs = readAndAdvance<unsigned char>(pData);
		header.nSe = readAndAdvance<unsigned char>(pData);
		header.nA = readAndAdvance<unsigned char>(pData);
	}

	void jpeg_common::writeScanHeader(const ScanHeader &header, unsigned char *&pData)
	{
		unsigned char aTemp[128];
		unsigned char *pTemp = aTemp;

		writeAndAdvance<unsigned char>(pTemp, header.nComponents);

		for (int c = 0; c < header.nComponents; ++c)
		{
			writeAndAdvance<unsigned char>(pTemp, header.aComponentSelector[c]);
			writeAndAdvance<unsigned char>(pTemp, header.aHuffmanTablesSelector[c]);
		}

		writeAndAdvance<unsigned char>(pTemp, header.nSs);
		writeAndAdvance<unsigned char>(pTemp, header.nSe);
		writeAndAdvance<unsigned char>(pTemp, header.nA);

		unsigned short nLength = (unsigned short)(pTemp - aTemp);

		writeMarker(SOS, pData);//SOS,Start of Scan,扫描开始
		writeAndAdvance<unsigned short>(pData, nLength + 2);//写入数据段长度,包含本身2字节,但不包括标记码
		memcpy(pData, aTemp, nLength);//写入标记段数据
		pData += nLength;
	}

	void jpeg_common::readQuantizationTables(const unsigned char *pData, QuantizationTable *pTables)
	{
		unsigned short nLength = readAndAdvance<unsigned short>(pData) - 2;

		while (nLength > 0)
		{
			unsigned char nPrecisionAndIdentifier = readAndAdvance<unsigned char>(pData);

			//按位取与,保留低位(ID),高位清0
			int nIdentifier = nPrecisionAndIdentifier & 0x0f;

			pTables[nIdentifier].nPrecisionAndIdentifier = nPrecisionAndIdentifier;
			memcpy(pTables[nIdentifier].aTable, pData, 64);//写入标记段数据
			pData += 64;
			nLength -= 65;
		}
	}

	void jpeg_common::writeQuantizationTable(const QuantizationTable &table, unsigned char *&pData)
	{
		writeMarker(DQT, pData);//DQT,Define Quantization Table,定义量化表
		writeAndAdvance<unsigned short>(pData, sizeof(QuantizationTable) + 2);//写入数据段长度,包含本身2字节,但不包括标记码
		memcpy(pData, &table, sizeof(QuantizationTable));//写入标记段数据
		pData += sizeof(QuantizationTable);
	}

	void jpeg_common::writeHuffmanTable(const HuffmanTable &table, unsigned char *&pData)
	{
		writeMarker(DHT, pData);//DHT,Difine Huffman Table,定义哈夫曼表

		int nCodeCount = 0;

		for (int i = 0; i < 16; ++i)
		{
			nCodeCount += table.aCodes[i];
		}

		writeAndAdvance<unsigned short>(pData, 17 + nCodeCount + 2);//段长度2字节+HT信息1字节+HT位表16字节+HT值表256字节
		memcpy(pData, &table, 17 + nCodeCount);//写入标记段
		pData += 17 + nCodeCount;
	}
	/*TODO 只考虑了正确的情况，要分别判断nClass变量，nIdx变量和nCodeCount变量的值是否合法。
	*/
	void jpeg_common::readHuffmanTables(const unsigned char *pData, HuffmanTable *pTables)
	{
		unsigned short nLength = readAndAdvance<unsigned short>(pData) - 2;//段长度-2为段内容长度

		while (nLength > 0)
		{
			unsigned char nClassAndIdentifier = readAndAdvance<unsigned char>(pData);
			//获取高位类型信息AC or DC
			int nClass = nClassAndIdentifier >> 4;
			//按位取与,保留低位(ID),高位清0
			int nIdentifier = nClassAndIdentifier & 0x0f;
			int nIdx = nClass * 2 + nIdentifier;//00亮度DC表,10亮度AC表，01色度DC表,11色度AC表
			pTables[nIdx].nClassAndIdentifier = nClassAndIdentifier;

			int nCodeCount = 0;

			for (int i = 0; i < 16; ++i)
			{
				pTables[nIdx].aCodes[i] = readAndAdvance<unsigned char>(pData);
				nCodeCount += pTables[nIdx].aCodes[i];
			}

			memcpy(pTables[nIdx].aTable, pData, nCodeCount);
			pData += nCodeCount;

			nLength -= (17 + nCodeCount);
		}
	}

	void jpeg_common::readRestartInterval(const unsigned char *pData, int &nRestartInterval)
	{
		readAndAdvance<unsigned short>(pData);
		nRestartInterval = readAndAdvance<unsigned short>(pData);
	}


}